--[[
	EncounterCore
	Pure state for tower boss encounters (one encounter = one arena instance).

	Ownership & eligibility rules (documented in docs/DESIGN.md):
	  * An encounter is created for a solo player or a party. Every participant must have the
	    floor unlocked (HighestCleared >= Floor - 1). Members who have not are left behind.
	  * Participants are fixed at start. Nobody joins mid-fight.
	  * A participant who dies or disconnects is removed from the fight (no re-entry).
	  * Boss HP scales with the participant count at start; when someone leaves, current and
	    max HP are scaled down proportionally so the remaining players are not punished.
	  * If no participants remain, the encounter fails and the boss resets.
	  * On victory, every participant still alive in the arena is eligible. Each is rewarded
	    exactly once per encounter (Rewarded set) and once per encounter id per profile
	    (profile.Tower.RewardedEncounters), so reconnects or simultaneous kills can't duplicate.
	  * First clear (HighestCleared == Floor - 1): full rewards + unique items, progression +1.
	    Replays: reduced currency/XP + replay loot table, small chance of the unique weapon.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Bosses = require(Shared.Config.Bosses)
local Formulas = require(Shared.Logic.Formulas)
local LootCore = require(script.Parent.LootCore)

local EncounterCore = {}

function EncounterCore.canEnter(profile, floor: number): (boolean, string?)
	if type(floor) ~= "number" or floor < 1 or floor > GameConfig.Tower.Floors or math.floor(floor) ~= floor then
		return false, "InvalidFloor"
	end
	if profile.Class == "" then
		return false, "NoClass"
	end
	if profile.Tower.HighestCleared < floor - 1 then
		return false, "Locked"
	end
	return true, nil
end

function EncounterCore.new(id: string, floor: number, userIds, now: number)
	local enc = {
		Id = id,
		Floor = floor,
		State = "Active",
		StartedAt = now,
		Participants = {},
		Rewarded = {},
		StartCount = #userIds,
		DamageTaken = {},
	}
	for _, uid in userIds do
		enc.Participants[uid] = { Alive = true, Damage = 0, Hits = 0 }
	end
	return enc
end

function EncounterCore.activeCount(enc): number
	local n = 0
	for _, p in enc.Participants do
		if p.Alive then
			n += 1
		end
	end
	return n
end

function EncounterCore.isParticipant(enc, uid): boolean
	local p = enc.Participants[uid]
	return p ~= nil and p.Alive
end

function EncounterCore.recordDamage(enc, uid, amount: number)
	local p = enc.Participants[uid]
	if p and p.Alive and enc.State == "Active" then
		p.Damage += amount
	end
end

function EncounterCore.recordHitTaken(enc, uid)
	local p = enc.Participants[uid]
	if p then
		p.Hits += 1
	end
end

-- Removes a participant (death or disconnect). Returns hpScale to apply to the boss
-- (newMultiplier / oldMultiplier), and whether the encounter has failed.
function EncounterCore.removeParticipant(enc, uid)
	local p = enc.Participants[uid]
	if not p or not p.Alive or enc.State ~= "Active" then
		return 1, false
	end
	local before = math.max(1, EncounterCore.activeCount(enc))
	p.Alive = false
	local after = EncounterCore.activeCount(enc)
	if after == 0 then
		enc.State = "Failed"
		return 1, true
	end
	return Formulas.partyHealthMult(after) / Formulas.partyHealthMult(before), false
end

function EncounterCore.markVictory(enc): boolean
	if enc.State ~= "Active" then
		return false
	end
	enc.State = "Victory"
	return true
end

function EncounterCore.eligible(enc, uid): boolean
	return enc.State == "Victory" and EncounterCore.isParticipant(enc, uid) and not enc.Rewarded[uid]
end

-- Builds the reward bundle (does not apply it).
function EncounterCore.buildRewards(profile, floor: number, rng)
	local def = Bosses.List[floor]
	local firstClear = profile.Tower.HighestCleared == floor - 1
	local rewards = { FirstClear = firstClear, Floor = floor, Items = {}, Xp = 0, Currency = 0 }
	local xp, currency = Formulas.bossXp(floor), Formulas.bossCurrency(floor)
	if firstClear then
		rewards.Xp, rewards.Currency = xp, currency
		for item, n in def.Rewards.FirstClear.Items or {} do
			rewards.Items[item] = (rewards.Items[item] or 0) + n
		end
		rewards.Ability = def.Rewards.FirstClear.Ability
		rewards.Title = def.Rewards.FirstClear.Title
		rewards.Cosmetic = def.Rewards.FirstClear.Cosmetic
	else
		rewards.Xp = math.floor(xp * GameConfig.Tower.ReplayXpMultiplier)
		rewards.Currency = math.floor(currency * GameConfig.Tower.ReplayCurrencyMultiplier)
		for item, n in LootCore.roll(Bosses.ReplayLoot, rng) do
			rewards.Items[item] = (rewards.Items[item] or 0) + n
		end
		if rng:NextNumber() < GameConfig.Tower.ReplayUniqueDropChance then
			-- one of the boss's unique weapons/shields (not consumables)
			local uniques = {}
			for item in def.Rewards.FirstClear.Items or {} do
				if string.find(item, "_shard") == nil and item ~= "flask_shard" and item ~= "fallen_core" and item ~= "fallen_remnant" and item ~= "armor_plate" then
					table.insert(uniques, item)
				end
			end
			table.sort(uniques)
			if #uniques > 0 then
				local pick = uniques[rng:NextInteger(1, #uniques)]
				rewards.Items[pick] = (rewards.Items[pick] or 0) + 1
			end
		end
	end
	return rewards
end

-- Marks the player rewarded and applies tower progression. Returns rewards or nil if ineligible.
-- The caller applies XP/currency/items via ProgressionCore/InventoryCore.
function EncounterCore.claim(enc, uid, profile, rng)
	if not EncounterCore.eligible(enc, uid) then
		return nil, "NotEligible"
	end
	local history = profile.Tower.RewardedEncounters
	if table.find(history, enc.Id) then
		enc.Rewarded[uid] = true
		return nil, "AlreadyRewarded"
	end
	enc.Rewarded[uid] = true
	local rewards = EncounterCore.buildRewards(profile, enc.Floor, rng)
	table.insert(history, enc.Id)
	while #history > 20 do
		table.remove(history, 1)
	end
	local key = tostring(enc.Floor)
	profile.Tower.Clears[key] = (profile.Tower.Clears[key] or 0) + 1
	if rewards.FirstClear then
		profile.Tower.HighestCleared = enc.Floor
	end
	local p = enc.Participants[uid]
	rewards.Flawless = p ~= nil and p.Hits == 0
	rewards.Solo = enc.StartCount == 1
	return rewards, nil
end

return EncounterCore
