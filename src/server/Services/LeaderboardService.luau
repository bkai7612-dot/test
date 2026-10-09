--[[
	LeaderboardService
	In-server leaderstats (Level, Floor) and global boards via OrderedDataStore
	(highest floor, level). Hub boards (parts tagged "Leaderboard") show the top 10.
	All DataStore calls are pcall-wrapped; failures only delay board refreshes.
]]

local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)

local LeaderboardService = {}
local S
local floorStore, levelStore
local pending = {}

function LeaderboardService.Init(services)
	S = services
	pcall(function()
		floorStore = DataStoreService:GetOrderedDataStore(GameConfig.Save.LeaderboardStore .. "_Floor")
		levelStore = DataStoreService:GetOrderedDataStore(GameConfig.Save.LeaderboardStore .. "_Level")
	end)
end

function LeaderboardService.Update(player: Player)
	local rt = S.PlayerStateService.Get(player)
	if not rt then
		return
	end
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		(ls:FindFirstChild("Level") :: IntValue).Value = rt.Profile.Level;
		(ls:FindFirstChild("Floor") :: IntValue).Value = rt.Profile.Tower.HighestCleared
	end
	pending[player.UserId] = { Floor = rt.Profile.Tower.HighestCleared, Level = rt.Profile.Level }
end

local function flush()
	if S.DataService.IsMemoryMode() then
		return
	end
	for uid, v in pending do
		pending[uid] = nil
		pcall(function()
			floorStore:SetAsync(tostring(uid), v.Floor)
			levelStore:SetAsync(tostring(uid), v.Level)
		end)
	end
end

local function refreshBoards()
	if S.DataService.IsMemoryMode() or not floorStore then
		return
	end
	local ok, pages = pcall(function()
		return floorStore:GetSortedAsync(false, 10)
	end)
	if not ok then
		return
	end
	local rows = {}
	for rank, entry in pages:GetCurrentPage() do
		local name = "Player"
		pcall(function()
			name = Players:GetNameFromUserIdAsync(tonumber(entry.key))
		end)
		table.insert(rows, ("%d. %s - Floor %d"):format(rank, name, entry.value))
	end
	for _, board in CollectionService:GetTagged("Leaderboard") do
		local label = board:FindFirstChild("Rows", true)
		if label and label:IsA("TextLabel") then
			label.Text = if #rows > 0 then table.concat(rows, "\n") else "No climbers yet."
		end
	end
end

function LeaderboardService.Start()
	S.DataService.ProfileLoaded:Connect(function(player, profile)
		local ls = Instance.new("Folder")
		ls.Name = "leaderstats"
		local lv = Instance.new("IntValue")
		lv.Name = "Level"
		lv.Value = profile.Level
		lv.Parent = ls
		local fl = Instance.new("IntValue")
		fl.Name = "Floor"
		fl.Value = profile.Tower.HighestCleared
		fl.Parent = ls
		ls.Parent = player
	end)
	Players.PlayerRemoving:Connect(function(player)
		LeaderboardService.Update(player)
	end)
	task.spawn(function()
		while true do
			task.wait(60)
			flush()
		end
	end)
	task.spawn(function()
		task.wait(10)
		while true do
			refreshBoards()
			task.wait(GameConfig.Save.LeaderboardRefresh)
		end
	end)
end

return LeaderboardService
