--[[
	PromoService
	Promo-code redemption and the admin panel.

	* Codes live in ServerScriptService.Server.Config.PromoCodes (never sent to clients).
	* Each code works once per character (profile.RedeemedCodes).
	* MaxUses is a GLOBAL limit across all servers, enforced with an atomic UpdateAsync counter
	  BEFORE anything is granted, so two players redeeming at the same moment can't exceed it.
	* Failed attempts are throttled (5 per minute) to stop guessing.
	* Admin codes unlock the admin panel: Never Die toggle, Unlock All, Max Upgrades,
	  All Items, All Customisations. Every admin action re-checks profile.Admin.Granted.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local PromoCodes = require(script.Parent.Parent.Config.PromoCodes)
local PromoCore = require(script.Parent.Parent.Core.PromoCore)

local PromoService = {}
local S
local store: DataStore? = nil
local memoryUses = {} -- Studio fallback when DataStores are unavailable
local failures = {}
local inFlight = {} -- one redemption at a time per player

function PromoService.Init(services)
	S = services
	pcall(function()
		store = DataStoreService:GetDataStore("TOTF_PromoCodes_v1")
	end)
end

-- Atomically reserves one global use. Returns true if a use was available.
local function claimGlobalUse(def): (boolean, string?)
	if not def.MaxUses then
		return true, nil
	end
	if S.DataService.IsMemoryMode() or not store then
		local used = memoryUses[def.Id] or 0
		if used >= def.MaxUses then
			return false, "CodeUsedUp"
		end
		memoryUses[def.Id] = used + 1
		return true, nil
	end
	local granted = false
	local ok = pcall(function()
		(store :: DataStore):UpdateAsync("uses_" .. def.Id, function(old)
			local used = tonumber(old) or 0
			if used >= def.MaxUses then
				granted = false
				return nil -- abort: no uses left
			end
			granted = true
			return used + 1
		end)
	end)
	if not ok then
		return false, "TryAgainLater"
	end
	return granted, if granted then nil else "CodeUsedUp"
end

local function throttled(player: Player): boolean
	local f = failures[player]
	local t = os.clock()
	if f and t - f.Since > 60 then
		f = nil
		failures[player] = nil
	end
	return f ~= nil and f.Count >= 5
end

local function noteFailure(player: Player)
	local f = failures[player] or { Count = 0, Since = os.clock() }
	f.Count += 1
	failures[player] = f
end

local function refresh(player: Player, statsChanged: boolean?)
	if statsChanged then
		S.PlayerStateService.RecomputeStats(player)
		S.InventoryService.ApplyWeaponVisual(player)
	end
	S.CosmeticService.Refresh(player)
	S.PlayerStateService.Sync(player)
	S.PlayerStateService.PushVitals(player)
	task.spawn(S.DataService.Save, player)
end

function PromoService.Start()
	local R = S.RequestService

	R.Register("RedeemCode", function(player, rt, text)
		if throttled(player) then
			return false, "TooManyAttempts"
		end
		if inFlight[player] then
			return false, "Busy"
		end
		local def = PromoCore.find(PromoCodes, text)
		local ok, err = PromoCore.check(rt.Profile, def, os.time())
		if not ok then
			noteFailure(player)
			return false, err
		end
		inFlight[player] = true
		local claimed, why = claimGlobalUse(def)
		inFlight[player] = nil
		if not claimed then
			return false, why
		end
		-- the player may have left while the counter was updating
		if not player.Parent or S.PlayerStateService.Get(player) ~= rt then
			return false, "NotLoaded"
		end
		PromoCore.markRedeemed(rt.Profile, def)
		if def.Kind == "Admin" then
			S.NotifyService.Banner(player, "ADMIN ACCESS GRANTED", "Open the menu -> Codes to use the admin panel.", "Reward")
			warn(("[PromoService] admin code %s redeemed by %s (%d)"):format(def.Id, player.Name, player.UserId))
			refresh(player)
		else
			S.ProgressionService.GrantBundle(player, def.Reward, "Promo code")
			task.spawn(S.DataService.Save, player)
		end
		return true, def.Kind
	end)

	R.Register("AdminAction", function(player, rt, payload)
		local admin = rt.Profile.Admin
		if not admin.Granted then
			return false, "NotAdmin"
		end
		if type(payload) ~= "table" or type(payload.Action) ~= "string" then
			return false, "BadRequest"
		end
		local a = payload.Action
		if a == "GodMode" then
			admin.GodMode = payload.On == true
			if rt.Combat then
				rt.Combat.GodMode = admin.GodMode
			end
			S.NotifyService.Toast(player, if admin.GodMode then "Never Die: ON" else "Never Die: OFF", "Reward")
			refresh(player)
		elseif a == "UnlockAll" then
			PromoCore.unlockAll(rt.Profile)
			S.NotifyService.Toast(player, "Unlocked all floors, shrines, locations and abilities.", "Reward")
			refresh(player, true)
		elseif a == "MaxUpgrades" then
			local n = PromoCore.maxUpgrades(rt.Profile)
			S.NotifyService.Toast(player, ("Upgraded %d items to maximum."):format(n), "Reward")
			refresh(player, true)
		elseif a == "AllItems" then
			local n = PromoCore.allItems(rt.Profile)
			S.NotifyService.Toast(player, ("Added %d items."):format(n), "Reward")
			refresh(player, true)
		elseif a == "AllCosmetics" then
			PromoCore.allCosmetics(rt.Profile)
			S.NotifyService.Toast(player, "All cosmetics and titles unlocked.", "Reward")
			refresh(player)
		else
			return false, "BadRequest"
		end
		return true, a
	end)

	Players.PlayerRemoving:Connect(function(p)
		failures[p] = nil
		inFlight[p] = nil
	end)
end

return PromoService
