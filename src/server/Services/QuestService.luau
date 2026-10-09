--[[
	QuestService
	Accept / abandon / turn in quests at the giving NPC. Rewards go through ProgressionService.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Quests = require(Shared.Config.Quests)
local Core = script.Parent.Parent.Core
local QuestCore = require(Core.QuestCore)
local AchievementCore = require(Core.AchievementCore)

local QuestService = {}
local S

function QuestService.Init(services)
	S = services
end

function QuestService.Start()
	local R = S.RequestService

	R.Register("AcceptQuest", function(player, rt, questId)
		local q = type(questId) == "string" and Quests[questId]
		if not q then
			return false, "UnknownQuest"
		end
		if not S.InteractionService.IsNear(player, q.Giver) then
			return false, "TooFar"
		end
		local ok, err = QuestCore.accept(rt.Profile, questId)
		if ok then
			S.NotifyService.Toast(player, "Quest accepted: " .. q.Name, "Quest")
			S.PlayerStateService.Sync(player)
		end
		return ok, err
	end)

	R.Register("AbandonQuest", function(player, rt, questId)
		local ok, err = QuestCore.abandon(rt.Profile, questId)
		S.PlayerStateService.Sync(player)
		return ok, err
	end)

	R.Register("TurnInQuest", function(player, rt, questId)
		local q = type(questId) == "string" and Quests[questId]
		if not q then
			return false, "UnknownQuest"
		end
		if not S.InteractionService.IsNear(player, q.Giver) then
			return false, "TooFar"
		end
		local ok, rewards = QuestCore.turnIn(rt.Profile, questId)
		if not ok then
			return false, rewards
		end
		AchievementCore.increment(rt.Profile, "QuestsDone")
		S.NotifyService.Banner(player, "QUEST COMPLETE", q.Name, "Quest")
		S.ProgressionService.GrantBundle(player, rewards, q.Name)
		task.spawn(S.DataService.Save, player)
		return true, questId
	end)
end

return QuestService
