--[[
	PromoCore
	Pure promo-code logic: code lookup, per-character redemption rules and the admin grants
	(unlock all, max upgrades, all items, all customisations). The global use limit is
	enforced separately by PromoService with an atomic DataStore counter.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared.Config.Items)
local Abilities = require(Shared.Config.Abilities)
local Cosmetics = require(Shared.Config.Cosmetics)
local Bosses = require(Shared.Config.Bosses)
local Achievements = require(Shared.Config.Achievements)
local Quests = require(Shared.Config.Quests)
local World = require(Shared.Config.World)
local GameConfig = require(Shared.Config.GameConfig)
local Formulas = require(Shared.Logic.Formulas)
local InventoryCore = require(script.Parent.InventoryCore)

local PromoCore = {}

function PromoCore.normalize(text): string?
	if type(text) ~= "string" or #text > 64 then
		return nil
	end
	local s = string.upper((string.gsub(text, "%s+", "")))
	if s == "" then
		return nil
	end
	return s
end

-- Returns codeDef or nil.
function PromoCore.find(codes, text)
	local norm = PromoCore.normalize(text)
	if not norm then
		return nil
	end
	for _, def in codes do
		if string.upper(def.Code) == norm then
			return def
		end
	end
	return nil
end

-- Per-character checks (does not touch the global counter).
function PromoCore.check(profile, def, now: number): (boolean, string?)
	if not def then
		return false, "InvalidCode"
	end
	if def.Expires and now > def.Expires then
		return false, "CodeExpired"
	end
	if profile.RedeemedCodes[def.Id] then
		return false, "AlreadyRedeemed"
	end
	if def.Kind == "Admin" and profile.Admin.Granted then
		return false, "AlreadyRedeemed"
	end
	return true, nil
end

function PromoCore.markRedeemed(profile, def)
	profile.RedeemedCodes[def.Id] = true
	if def.Kind == "Admin" then
		profile.Admin.Granted = true
	end
end

-- ===================================================================== admin grants
function PromoCore.unlockAll(profile)
	profile.Tower.HighestCleared = GameConfig.Tower.Floors
	for _, cp in World.Checkpoints do
		profile.Checkpoints.Activated[cp.Id] = true
	end
	for _, loc in World.Locations do
		profile.Discovered[loc.Id] = true
	end
	for id in Abilities do
		profile.Abilities.Unlocked[id] = true
	end
	profile.Flask.MaxCharges = GameConfig.Flask.MaxCharges
	profile.Flask.Charges = GameConfig.Flask.MaxCharges
end

function PromoCore.allCosmetics(profile)
	for id in Cosmetics do
		profile.Cosmetics.Owned[id] = true
	end
	for _, b in Bosses.List do
		if b.Rewards.FirstClear.Title then
			profile.Titles[b.Rewards.FirstClear.Title] = true
		end
	end
	for _, a in Achievements do
		if a.Reward and a.Reward.Title then
			profile.Titles[a.Reward.Title] = true
		end
	end
	for _, q in Quests do
		if q.Rewards.Title then
			profile.Titles[q.Rewards.Title] = true
		end
	end
	profile.Titles["Administrator"] = true
end

-- One of every piece of equipment not yet owned, plus stacks of consumables and materials.
function PromoCore.allItems(profile)
	local added = 0
	local ids = {}
	for id in Items do
		if string.sub(id, 1, 1) ~= "_" then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	for _, id in ids do
		local def = Items[id]
		if def.Stackable then
			local want = if def.Kind == "Consumable" then GameConfig.Consumables.MaxStack else 99
			local have = InventoryCore.stackCount(profile, id)
			if have < want then
				local ok, res = InventoryCore.addItem(profile, id, want - have, true)
				if ok then
					added += res.Added
				end
			end
		elseif not InventoryCore.ownsItemId(profile, id) then
			local ok, res = InventoryCore.addItem(profile, id, 1, true)
			if ok then
				added += res.Added
			end
		end
	end
	return added
end

-- Every owned weapon, shield and armour piece to its maximum upgrade level.
function PromoCore.maxUpgrades(profile)
	local n = 0
	for _, inst in profile.Inventory.Items do
		local path = Formulas.upgradePath(Items[inst.Id])
		if path and inst.Upgrade < path.Max then
			inst.Upgrade = path.Max
			n += 1
		end
	end
	return n
end

return PromoCore
