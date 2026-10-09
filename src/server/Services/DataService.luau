--[[
	DataService
	Persistent player data with DataStoreService.

	Session locking (prevents duplication across servers):
	  Stored value = { Data = profile, Lock = { JobId, Time } }
	  * Load: UpdateAsync acquires the lock if it is free, ours, or stale (> LockStaleSeconds).
	    If another live server holds it we retry LockAcquireAttempts times, then take it over.
	    Taking over is safe because every later save from the old server checks the lock and
	    refuses to write once it no longer owns it.
	  * Save: UpdateAsync writes only while we own the lock (and refreshes Lock.Time).
	  * Release: on leave, final save clears the lock.

	Failure handling:
	  * Load failures retry with backoff. In a live game, if loading ultimately fails the player
	    is kicked with an explanation - we never let them play on a blank profile that could
	    overwrite real progress.
	  * In Studio without API access the service falls back to in-memory data and marks the
	    player with attribute DataUnsaved = true so the HUD shows a visible warning.
	  * Save failures retry; persistent failures set DataSaveFailing = true (HUD warning).
	  * BindToClose saves every loaded profile in parallel before shutdown.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Signal = require(Shared.Util.Signal)
local ProfileSchema = require(script.Parent.Parent.Core.ProfileSchema)

local SaveCfg = GameConfig.Save

local DataService = {
	ProfileLoaded = Signal.new(), -- (player, profile)
	BeforeSave = Signal.new(),
}

local profiles: { [Player]: any } = {}
local saving: { [Player]: boolean } = {}
local released: { [Player]: boolean } = {}
local store: DataStore? = nil
local memoryMode = false
local jobId = game.JobId ~= "" and game.JobId or ("studio-" .. HttpService:GenerateGUID(false))

local function keyFor(player: Player): string
	return SaveCfg.KeyPrefix .. player.UserId
end

local function retry(label: string, fn: () -> any)
	local lastErr
	for attempt = 1, SaveCfg.MaxRetries do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		warn(("[DataService] %s failed (attempt %d): %s"):format(label, attempt, tostring(result)))
		task.wait(SaveCfg.RetryBaseDelay * attempt)
	end
	return false, lastErr
end

function DataService.Init(_services)
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(SaveCfg.StoreName)
	end)
	if ok then
		store = result
		-- In Studio, probe access once; without "Enable Studio Access to API Services" this errors.
		if RunService:IsStudio() then
			local probeOk = pcall(function()
				(result :: DataStore):GetAsync("__probe")
			end)
			if not probeOk then
				memoryMode = true
				warn("[DataService] DataStore unavailable in Studio: using in-memory data (progress will NOT be saved).")
			end
		end
	else
		memoryMode = true
		warn("[DataService] Could not open DataStore: " .. tostring(result))
	end
end

local function acquire(player: Player)
	if memoryMode or not store then
		return true, nil
	end
	local key = keyFor(player)
	for attempt = 1, SaveCfg.LockAcquireAttempts do
		local force = attempt == SaveCfg.LockAcquireAttempts
		local blocked = false
		local ok, value = retry("load " .. key, function()
			return (store :: DataStore):UpdateAsync(key, function(old)
				old = old or {}
				local lock = old.Lock
				local now = os.time()
				if lock and lock.JobId ~= jobId and now - (lock.Time or 0) < SaveCfg.LockStaleSeconds and not force then
					blocked = true
					return nil -- abort write, keep their lock
				end
				old.Lock = { JobId = jobId, Time = now }
				return old
			end)
		end)
		if not ok then
			return false, value
		end
		if not blocked then
			return true, value and value.Data or nil
		end
		warn(("[DataService] %s locked by another server; retrying (%d/%d)"):format(key, attempt, SaveCfg.LockAcquireAttempts))
		task.wait(SaveCfg.LockRetryWait)
		if not player.Parent then
			return false, "left"
		end
	end
	return false, "lock"
end

function DataService.Load(player: Player)
	local ok, raw = acquire(player)
	if not player.Parent then
		return nil
	end
	if not ok then
		if RunService:IsStudio() then
			memoryMode = true
			raw = nil
		else
			player:Kick("Tower of the Fallen could not load your save data safely. Your progress is untouched - please rejoin in a minute.")
			return nil
		end
	end
	local profile, corrections = ProfileSchema.reconcile(raw or ProfileSchema.default())
	if raw == nil then
		profile.CreatedAt = os.time()
	end
	if #corrections > 0 then
		warn(("[DataService] %d data corrections for %d: %s"):format(#corrections, player.UserId, table.concat(corrections, "; ")))
	end
	profiles[player] = profile
	player:SetAttribute("DataUnsaved", memoryMode)
	player:SetAttribute("DataSaveFailing", false)
	DataService.ProfileLoaded:Fire(player, profile)
	return profile
end

function DataService.Get(player: Player)
	return profiles[player]
end

-- Saves the profile. `release` clears the session lock (used on leave/shutdown).
function DataService.Save(player: Player, release: boolean?): boolean
	local profile = profiles[player]
	if not profile or released[player] then
		return false
	end
	if memoryMode or not store then
		return true
	end
	while saving[player] do
		task.wait(0.1)
	end
	saving[player] = true
	DataService.BeforeSave:Fire(player, profile)
	profile.LastSaved = os.time()
	local lostLock = false
	local key = keyFor(player)
	local ok, err = retry("save " .. key, function()
		return (store :: DataStore):UpdateAsync(key, function(old)
			old = old or {}
			local lock = old.Lock
			if lock and lock.JobId ~= jobId then
				lostLock = true
				return nil -- another server owns this profile now; never overwrite it
			end
			local corrections = profile.Corrections
			profile.Corrections = nil
			old.Data = profile
			local copy = table.clone(old)
			profile.Corrections = corrections
			copy.Lock = if release then nil else { JobId = jobId, Time = os.time() }
			return copy
		end)
	end)
	saving[player] = nil
	if lostLock then
		warn("[DataService] session lock lost for " .. key .. "; stopping saves for this session")
		released[player] = true
		if player.Parent then
			player:Kick("Your character was loaded on another server. Please rejoin.")
		end
		return false
	end
	if player.Parent then
		player:SetAttribute("DataSaveFailing", not ok)
	end
	if not ok then
		warn("[DataService] save failed for " .. key .. ": " .. tostring(err))
	end
	return ok
end

function DataService.Release(player: Player)
	if profiles[player] then
		DataService.Save(player, true)
		released[player] = true
		profiles[player] = nil
	end
	saving[player] = nil
	task.delay(5, function()
		released[player] = nil
	end)
end

function DataService.IsMemoryMode(): boolean
	return memoryMode
end

function DataService.Start()
	-- Autosave loop
	task.spawn(function()
		while true do
			task.wait(SaveCfg.AutosaveInterval)
			for player in profiles do
				task.spawn(DataService.Save, player, false)
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				DataService.Save(player, true)
				pending -= 1
			end)
		end
		local start = os.clock()
		while pending > 0 and os.clock() - start < 25 do
			task.wait(0.2)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		DataService.Release(player)
	end)
end

return DataService
