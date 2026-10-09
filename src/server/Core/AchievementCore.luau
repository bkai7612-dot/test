--[[
	AchievementCore
	Stat counters and achievement evaluation. Rewards are titles and cosmetics only.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Achievements = require(Shared.Config.Achievements)
local Items = require(Shared.Config.Items)
local Rarities = require(Shared.Config.Rarities)
local World = require(Shared.Config.World)
local InventoryCore = require(script.Parent.InventoryCore)

local AchievementCore = {}

function AchievementCore.increment(profile, stat: string, amount: number?)
	profile.Stats[stat] = (profile.Stats[stat] or 0) + (amount or 1)
	return profile.Stats[stat]
end

local function checkCustom(profile, a): boolean
	if a.Check == "Floor" then
		return profile.Tower.HighestCleared >= a.Goal
	elseif a.Check == "AllLocations" then
		for _, loc in World.Locations do
			if not profile.Discovered[loc.Id] then
				return false
			end
		end
		return true
	elseif a.Check == "AllSecrets" then
		for _, loc in World.Locations do
			if loc.Secret and not profile.Discovered[loc.Id] then
				return false
			end
		end
		return true
	elseif a.Check == "HighRarity" then
		local n = 0
		for _, inst in profile.Inventory.Items do
			local def = Items[inst.Id]
			if def and Rarities[def.Rarity].Rank >= Rarities.Legendary.Rank then
				n += 1
			end
		end
		return n >= a.Goal
	elseif a.Check == "UpgradeLevel" then
		return InventoryCore.highestUpgrade(profile) >= a.Goal
	elseif a.Check == "Hybrid" then
		local n = 0
		for _, attr in { "Strength", "Dexterity", "Intelligence", "Faith", "Arcane" } do
			if (profile.Attributes[attr] or 0) >= a.Goal then
				n += 1
			end
		end
		return n >= 2
	end
	return false
end

-- Unlocks every newly satisfied achievement; returns list of { Id, Reward }.
function AchievementCore.evaluate(profile)
	local unlocked = {}
	for id, a in Achievements do
		if not profile.Achievements[id] then
			local done
			if a.Stat then
				done = (profile.Stats[a.Stat] or 0) >= a.Goal
			else
				done = checkCustom(profile, a)
			end
			if done then
				profile.Achievements[id] = true
				if a.Reward then
					if a.Reward.Title then
						profile.Titles[a.Reward.Title] = true
					end
					if a.Reward.Cosmetic then
						profile.Cosmetics.Owned[a.Reward.Cosmetic] = true
					end
				end
				table.insert(unlocked, { Id = id, Reward = a.Reward })
			end
		end
	end
	table.sort(unlocked, function(x, y)
		return x.Id < y.Id
	end)
	return unlocked
end

return AchievementCore
