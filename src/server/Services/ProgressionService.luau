--[[
	ProgressionService
	Grants XP / currency / items / abilities / titles (the only path rewards take), tracks kill
	statistics, forwards quest events, evaluates achievements, and handles character requests:
	class selection, attribute allocation, ability slots, titles and settings.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Items = require(Shared.Config.Items)
local Abilities = require(Shared.Config.Abilities)
local Achievements = require(Shared.Config.Achievements)
local Cosmetics = require(Shared.Config.Cosmetics)
local Core = script.Parent.Parent.Core
local ProgressionCore = require(Core.ProgressionCore)
local InventoryCore = require(Core.InventoryCore)
local EconomyCore = require(Core.EconomyCore)
local AchievementCore = require(Core.AchievementCore)
local QuestCore = require(Core.QuestCore)

local ProgressionService = {}
local S

function ProgressionService.Init(services)
	S = services
end

function ProgressionService.EvaluateAchievements(player: Player)
	local rt = S.PlayerStateService.Get(player)
	if not rt then
		return
	end
	for _, a in AchievementCore.evaluate(rt.Profile) do
		local def = Achievements[a.Id]
		local extra = ""
		if a.Reward and a.Reward.Title then
			extra = " - Title: " .. a.Reward.Title
		elseif a.Reward and a.Reward.Cosmetic then
			extra = " - Cosmetic: " .. (Cosmetics[a.Reward.Cosmetic] and Cosmetics[a.Reward.Cosmetic].Name or a.Reward.Cosmetic)
		end
		S.NotifyService.Banner(player, "Achievement: " .. def.Name, def.Description .. extra, "Achievement")
	end
end

function ProgressionService.GrantXp(player: Player, amount: number, reason: string?)
	local rt = S.PlayerStateService.Get(player)
	if not rt or amount <= 0 then
		return
	end
	local r = ProgressionCore.grantXp(rt.Profile, amount)
	if r.Levels > 0 then
		S.NotifyService.Banner(player, "Level " .. rt.Profile.Level, ("+%d attribute point%s - rest at an Ember Shrine to spend them."):format(r.Levels, r.Levels > 1 and "s" or ""), "Level")
		for _, id in r.NewAbilities do
			S.NotifyService.Toast(player, "New ability unlocked: " .. Abilities[id].Name, "Reward")
		end
		if S.LeaderboardService then
			S.LeaderboardService.Update(player)
		end
	end
	return r
end

function ProgressionService.GrantCurrency(player: Player, amount: number)
	local rt = S.PlayerStateService.Get(player)
	if not rt then
		return 0
	end
	return EconomyCore.addCurrency(rt.Profile, amount)
end

function ProgressionService.GrantItems(player: Player, items, source: string?)
	local rt = S.PlayerStateService.Get(player)
	if not rt then
		return
	end
	for itemId, n in items do
		if Items[itemId] and n > 0 then
			local ok, res = InventoryCore.addItem(rt.Profile, itemId, n, true)
			if ok and res.Added > 0 then
				S.NotifyService.Toast(player, ("%s%s x%d"):format(source and (source .. ": ") or "", Items[itemId].Name, res.Added), "Loot")
			elseif ok then
				S.NotifyService.Toast(player, "Inventory full: " .. Items[itemId].Name .. " was lost.", "Warning")
			end
		end
	end
end

-- bundle = { Xp, Currency, Items, Ability, Title, Cosmetic }
function ProgressionService.GrantBundle(player: Player, bundle, source: string?)
	local rt = S.PlayerStateService.Get(player)
	if not rt or not bundle then
		return
	end
	if (bundle.Currency or 0) > 0 then
		local got = ProgressionService.GrantCurrency(player, bundle.Currency)
		S.NotifyService.Toast(player, ("+%d %s"):format(got, GameConfig.Currency.Name), "Currency")
	end
	if bundle.Items then
		ProgressionService.GrantItems(player, bundle.Items, source)
	end
	if bundle.Ability and ProgressionCore.unlockAbility(rt.Profile, bundle.Ability) then
		S.NotifyService.Toast(player, "Ability learned: " .. Abilities[bundle.Ability].Name, "Reward")
	end
	if bundle.Title then
		rt.Profile.Titles[bundle.Title] = true
		S.NotifyService.Toast(player, "Title earned: " .. bundle.Title, "Reward")
	end
	if bundle.Cosmetic and Cosmetics[bundle.Cosmetic] then
		rt.Profile.Cosmetics.Owned[bundle.Cosmetic] = true
		S.NotifyService.Toast(player, "Cosmetic unlocked: " .. Cosmetics[bundle.Cosmetic].Name, "Reward")
	end
	if (bundle.Xp or 0) > 0 then
		ProgressionService.GrantXp(player, bundle.Xp, source)
		S.NotifyService.Toast(player, ("+%d XP"):format(bundle.Xp), "Xp")
	end
	ProgressionService.EvaluateAchievements(player)
	S.PlayerStateService.Sync(player)
	S.PlayerStateService.PushVitals(player)
end

function ProgressionService.QuestEvent(player: Player, event)
	local rt = S.PlayerStateService.Get(player)
	if not rt then
		return
	end
	local changed = QuestCore.onEvent(rt.Profile, event)
	for _, qid in changed do
		if QuestCore.isComplete(rt.Profile, qid) then
			S.NotifyService.Toast(player, "Quest ready to turn in.", "Quest")
		end
	end
end

function ProgressionService.OnEnemyKilled(player: Player, enemyDef)
	local rt = S.PlayerStateService.Get(player)
	if not rt then
		return
	end
	AchievementCore.increment(rt.Profile, "Kills")
	rt.Profile.KillsByEnemy[enemyDef.Id] = (rt.Profile.KillsByEnemy[enemyDef.Id] or 0) + 1
	ProgressionService.QuestEvent(player, { Type = "Kill", Enemy = enemyDef.Id })
end

-- ===================================================================== requests
local function outOfCombat(rt): boolean
	return workspace:GetServerTimeNow() - (rt.Combat and rt.Combat.LastDamagedAt or -1e9) > GameConfig.Combat.CombatTagSeconds
		and rt.Encounter == nil
end

function ProgressionService.Start()
	local R = S.RequestService

	R.Register("ChooseClass", function(player, rt, className)
		local ok, err = ProgressionCore.chooseClass(rt.Profile, className)
		if not ok then
			return false, err
		end
		S.PlayerStateService.RecomputeStats(player)
		S.PlayerStateService.FullRestore(player)
		S.CosmeticService.Refresh(player)
		S.PlayerStateService.Sync(player)
		S.DataService.Save(player)
		S.NotifyService.Banner(player, "The " .. className .. " awakens", "Speak to Ilya the Guide, or climb the tower when ready.", "Banner")
		return true, className
	end)

	R.Register("AllocateAttributes", function(player, rt, allocations)
		if not S.CheckpointService.IsNearActivatedShrine(player) then
			return false, "RestAtShrine"
		end
		if not outOfCombat(rt) then
			return false, "InCombat"
		end
		local ok, err = ProgressionCore.allocate(rt.Profile, allocations)
		if not ok then
			return false, err
		end
		S.PlayerStateService.RecomputeStats(player)
		ProgressionService.EvaluateAchievements(player)
		S.PlayerStateService.Sync(player)
		return true, err
	end)

	R.Register("SetAbilitySlot", function(player, rt, payload)
		if type(payload) ~= "table" then
			return false, "BadRequest"
		end
		if not outOfCombat(rt) then
			return false, "InCombat"
		end
		local ok, err = ProgressionCore.setAbilitySlot(rt.Profile, payload.Slot, payload.Ability)
		S.PlayerStateService.Sync(player)
		return ok, err
	end)

	R.Register("SetTitle", function(player, rt, title)
		if title ~= "" and (type(title) ~= "string" or not rt.Profile.Titles[title]) then
			return false, "NotOwned"
		end
		rt.Profile.ActiveTitle = title
		S.CosmeticService.Refresh(player)
		S.PlayerStateService.Sync(player)
		return true, title
	end)

	R.Register("SaveSettings", function(player, rt, settings)
		if type(settings) ~= "table" then
			return false, "BadRequest"
		end
		local cur = rt.Profile.Settings
		for k, v in settings do
			local old = cur[k]
			if old ~= nil and type(v) == type(old) then
				if type(v) == "number" then
					if v == v then
						cur[k] = math.clamp(v, 0, 3)
					end
				else
					cur[k] = v
				end
			end
		end
		return true, cur
	end)
end

return ProgressionService
