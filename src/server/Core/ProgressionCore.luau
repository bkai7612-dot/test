--[[
	ProgressionCore
	Class selection, XP/levels, attribute allocation and ability unlocks.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Classes = require(Shared.Config.Classes)
local Abilities = require(Shared.Config.Abilities)
local Formulas = require(Shared.Logic.Formulas)
local InventoryCore = require(script.Parent.InventoryCore)

local ProgressionCore = {}

function ProgressionCore.chooseClass(profile, className)
	if type(className) ~= "string" or not Classes[className] then
		return false, "UnknownClass"
	end
	if profile.Class ~= "" then
		return false, "AlreadyChosen"
	end
	local class = Classes[className]
	profile.Class = className
	for name, value in class.Attributes do
		profile.Attributes[name] = value
	end
	local loadout = class.Loadout
	local function giveAndEquip(itemId, slot)
		local ok, res = InventoryCore.addItem(profile, itemId, 1)
		if ok and res.Uids[1] then
			InventoryCore.equip(profile, res.Uids[1], slot)
		end
	end
	if loadout.Weapon then
		giveAndEquip(loadout.Weapon, "Weapon")
	end
	if loadout.Offhand then
		giveAndEquip(loadout.Offhand, "Offhand")
	end
	for slot, itemId in loadout.Armor or {} do
		giveAndEquip(itemId, slot)
	end
	for itemId, amount in class.Items or {} do
		InventoryCore.addItem(profile, itemId, amount, true)
	end
	for _, abilityId in class.Abilities do
		local def = Abilities[abilityId]
		if def and def.UnlockLevel <= profile.Level then
			profile.Abilities.Unlocked[abilityId] = true
		end
	end
	profile.Abilities.Slot1 = class.Abilities[1] or ""
	profile.Abilities.Slot2 = ""
	return true, className
end

-- Class abilities whose UnlockLevel has been reached. Returns newly unlocked ids.
function ProgressionCore.unlockLevelAbilities(profile)
	local unlocked = {}
	local class = Classes[profile.Class]
	if not class then
		return unlocked
	end
	for _, abilityId in class.Abilities do
		local def = Abilities[abilityId]
		if def and def.UnlockLevel <= profile.Level and not profile.Abilities.Unlocked[abilityId] then
			profile.Abilities.Unlocked[abilityId] = true
			table.insert(unlocked, abilityId)
			if profile.Abilities.Slot2 == "" and profile.Abilities.Slot1 ~= abilityId then
				profile.Abilities.Slot2 = abilityId
			end
		end
	end
	return unlocked
end

-- Grants XP and levels up. Returns { Gained = xp, Levels = n, NewAbilities = {...} }
function ProgressionCore.grantXp(profile, amount)
	local result = { Gained = 0, Levels = 0, NewAbilities = {} }
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 or amount == math.huge then
		return result
	end
	amount = math.floor(amount)
	local maxLevel = GameConfig.Level.Max
	if profile.Level >= maxLevel then
		return result
	end
	profile.Xp += amount
	result.Gained = amount
	while profile.Level < maxLevel do
		local need = Formulas.xpToNext(profile.Level)
		if profile.Xp < need then
			break
		end
		profile.Xp -= need
		profile.Level += 1
		profile.UnspentPoints += GameConfig.Level.PointsPerLevel
		result.Levels += 1
	end
	if profile.Level >= maxLevel then
		profile.Xp = 0
	end
	if result.Levels > 0 then
		result.NewAbilities = ProgressionCore.unlockLevelAbilities(profile)
	end
	return result
end

-- allocations: { [attribute] = points }. All-or-nothing.
function ProgressionCore.allocate(profile, allocations)
	if type(allocations) ~= "table" then
		return false, "InvalidRequest"
	end
	local total = 0
	for attr, points in allocations do
		if not table.find(GameConfig.Attributes.List, attr) then
			return false, "UnknownAttribute"
		end
		if type(points) ~= "number" or points ~= points or points < 0 or math.floor(points) ~= points then
			return false, "InvalidPoints"
		end
		if profile.Attributes[attr] + points > GameConfig.Attributes.Max then
			return false, "AttributeCap"
		end
		total += points
	end
	if total <= 0 then
		return false, "NothingToSpend"
	end
	if total > profile.UnspentPoints then
		return false, "NotEnoughPoints"
	end
	for attr, points in allocations do
		profile.Attributes[attr] += points
	end
	profile.UnspentPoints -= total
	return true, total
end

function ProgressionCore.unlockAbility(profile, abilityId: string): boolean
	if not Abilities[abilityId] or profile.Abilities.Unlocked[abilityId] then
		return false
	end
	profile.Abilities.Unlocked[abilityId] = true
	return true
end

function ProgressionCore.setAbilitySlot(profile, slot, abilityId)
	if slot ~= "Slot1" and slot ~= "Slot2" then
		return false, "InvalidSlot"
	end
	if abilityId == "" then
		profile.Abilities[slot] = ""
		return true, slot
	end
	if type(abilityId) ~= "string" or not profile.Abilities.Unlocked[abilityId] then
		return false, "NotUnlocked"
	end
	local other = if slot == "Slot1" then "Slot2" else "Slot1"
	if profile.Abilities[other] == abilityId then
		profile.Abilities[other] = profile.Abilities[slot]
	end
	profile.Abilities[slot] = abilityId
	return true, slot
end

return ProgressionCore
