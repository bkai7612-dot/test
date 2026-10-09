--[[
	QuestCore
	Quest acceptance, progress tracking and turn-in. Progress for Kill/Training objectives is
	counted only while the quest is active; Boss/Discover/Secret/Upgrade objectives are evaluated
	from profile state so they can never desync.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Quests = require(Shared.Config.Quests)
local World = require(Shared.Config.World)
local InventoryCore = require(script.Parent.InventoryCore)

local QuestCore = {}

local secretSet = {}
for _, loc in World.Locations do
	if loc.Secret then
		secretSet[loc.Id] = true
	end
end

function QuestCore.status(profile, questId: string): string
	if profile.Quests.Completed[questId] then
		return "Completed"
	elseif profile.Quests.Active[questId] then
		return "Active"
	end
	local q = Quests[questId]
	if not q then
		return "Unknown"
	end
	for _, req in q.Requires do
		if not profile.Quests.Completed[req] then
			return "Locked"
		end
	end
	return "Available"
end

function QuestCore.accept(profile, questId)
	if type(questId) ~= "string" or not Quests[questId] then
		return false, "UnknownQuest"
	end
	local status = QuestCore.status(profile, questId)
	if status ~= "Available" then
		return false, status
	end
	profile.Quests.Active[questId] = { Progress = 0 }
	return true, questId
end

function QuestCore.abandon(profile, questId)
	if not profile.Quests.Active[questId] then
		return false, "NotActive"
	end
	profile.Quests.Active[questId] = nil
	return true, questId
end

local function countTable(t)
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

-- Returns current, goal for a quest.
function QuestCore.progress(profile, questId: string): (number, number)
	local q = Quests[questId]
	if not q then
		return 0, 1
	end
	local o = q.Objective
	local active = profile.Quests.Active[questId]
	if o.Type == "Kill" or o.Type == "Training" then
		return math.min(active and active.Progress or 0, o.Count), o.Count
	elseif o.Type == "Boss" then
		return (profile.Tower.HighestCleared >= o.Floor) and 1 or 0, 1
	elseif o.Type == "Discover" then
		if o.Location then
			return profile.Discovered[o.Location] and 1 or 0, 1
		end
		return math.min(countTable(profile.Discovered), o.Count), o.Count
	elseif o.Type == "Secret" then
		local n = 0
		for id in profile.Discovered do
			if secretSet[id] then
				n += 1
			end
		end
		return math.min(n, o.Count), o.Count
	elseif o.Type == "Upgrade" then
		return math.min(InventoryCore.highestUpgrade(profile), o.Level), o.Level
	elseif o.Type == "Collect" then
		return math.min(InventoryCore.stackCount(profile, o.Item), o.Count), o.Count
	end
	return 0, 1
end

function QuestCore.isComplete(profile, questId: string): boolean
	if not profile.Quests.Active[questId] then
		return false
	end
	local cur, goal = QuestCore.progress(profile, questId)
	return cur >= goal
end

-- event = { Type = "Kill", Enemy = id } | { Type = "Training" }
-- Returns list of quest ids whose progress changed.
function QuestCore.onEvent(profile, event)
	local changed = {}
	for questId, state in profile.Quests.Active do
		local q = Quests[questId]
		if q then
			local o = q.Objective
			if o.Type == event.Type and (o.Type ~= "Kill" or o.Enemy == event.Enemy) then
				if state.Progress < o.Count then
					state.Progress += 1
					table.insert(changed, questId)
				end
			end
		end
	end
	return changed
end

-- Validates completion, consumes Collect items, marks completed. Returns ok, rewards.
function QuestCore.turnIn(profile, questId)
	if type(questId) ~= "string" or not Quests[questId] then
		return false, "UnknownQuest"
	end
	if not QuestCore.isComplete(profile, questId) then
		return false, "NotComplete"
	end
	local q = Quests[questId]
	if q.Objective.Type == "Collect" then
		local ok = InventoryCore.removeStack(profile, q.Objective.Item, q.Objective.Count)
		if not ok then
			return false, "NotComplete"
		end
	end
	profile.Quests.Active[questId] = nil
	profile.Quests.Completed[questId] = true
	return true, q.Rewards
end

return QuestCore
