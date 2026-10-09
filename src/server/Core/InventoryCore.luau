--[[
	InventoryCore
	Pure inventory/equipment operations on a profile table. Every function validates fully
	BEFORE mutating, so a failed call leaves the profile untouched (no partial updates).
	Returns (ok: boolean, errOrResult).

	Data model:
	  profile.Inventory.Items  = { [uid: string] = { Id = itemId, Upgrade = n } }  -- equipment
	  profile.Inventory.Stacks = { [itemId] = count }                               -- stackables
	  profile.Equipped         = { [slot] = uid }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Items = require(Shared.Config.Items)
local Formulas = require(Shared.Logic.Formulas)

local InventoryCore = {}

local function isPositiveInt(n)
	return type(n) == "number" and n == n and n >= 1 and n <= 1e6 and math.floor(n) == n
end

function InventoryCore.instanceCount(profile): number
	local n = 0
	for _ in profile.Inventory.Items do
		n += 1
	end
	return n
end

function InventoryCore.stackCount(profile, itemId: string): number
	return profile.Inventory.Stacks[itemId] or 0
end

function InventoryCore.ownsItemId(profile, itemId: string): boolean
	local def = Items[itemId]
	if not def then
		return false
	end
	if def.Stackable then
		return InventoryCore.stackCount(profile, itemId) > 0
	end
	for _, inst in profile.Inventory.Items do
		if inst.Id == itemId then
			return true
		end
	end
	return false
end

-- Can `amount` of `itemId` be added? (capacity check only)
function InventoryCore.canAdd(profile, itemId: string, amount: number): (boolean, string?)
	local def = Items[itemId]
	if not def then
		return false, "UnknownItem"
	end
	if not isPositiveInt(amount) then
		return false, "InvalidQuantity"
	end
	if def.Stackable then
		if InventoryCore.stackCount(profile, itemId) + amount > GameConfig.Inventory.MaxStack then
			return false, "StackFull"
		end
	elseif InventoryCore.instanceCount(profile) + amount > GameConfig.Inventory.MaxSlots then
		return false, "InventoryFull"
	end
	return true, nil
end

-- Adds items. For loot, `clampToCapacity` adds as many as fit instead of failing.
-- Returns ok, { Added = n, Uids = {...} } or error.
function InventoryCore.addItem(profile, itemId: string, amount: number, clampToCapacity: boolean?)
	local def = Items[itemId]
	if not def then
		return false, "UnknownItem"
	end
	if not isPositiveInt(amount) then
		return false, "InvalidQuantity"
	end
	if def.Stackable then
		local have = InventoryCore.stackCount(profile, itemId)
		local room = GameConfig.Inventory.MaxStack - have
		local add = amount
		if add > room then
			if not clampToCapacity then
				return false, "StackFull"
			end
			add = math.max(0, room)
		end
		if add > 0 then
			profile.Inventory.Stacks[itemId] = have + add
		end
		return true, { Added = add, Uids = {} }
	end
	local room = GameConfig.Inventory.MaxSlots - InventoryCore.instanceCount(profile)
	local add = amount
	if add > room then
		if not clampToCapacity then
			return false, "InventoryFull"
		end
		add = math.max(0, room)
	end
	local uids = {}
	for _ = 1, add do
		local uid = "i" .. profile.Inventory.NextUid
		profile.Inventory.NextUid += 1
		profile.Inventory.Items[uid] = { Id = itemId, Upgrade = 0 }
		table.insert(uids, uid)
	end
	return true, { Added = add, Uids = uids }
end

function InventoryCore.removeStack(profile, itemId: string, amount: number)
	if not isPositiveInt(amount) then
		return false, "InvalidQuantity"
	end
	local have = InventoryCore.stackCount(profile, itemId)
	if have < amount then
		return false, "NotEnough"
	end
	local left = have - amount
	profile.Inventory.Stacks[itemId] = if left > 0 then left else nil
	return true, left
end

function InventoryCore.isEquipped(profile, uid: string): boolean
	for _, v in profile.Equipped do
		if v == uid then
			return true
		end
	end
	return false
end

-- Which slot(s) can hold this item?
function InventoryCore.slotsFor(def)
	if not def then
		return {}
	end
	if def.Kind == "Weapon" then
		return { "Weapon" }
	elseif def.Kind == "Shield" then
		return { "Offhand" }
	elseif def.Kind == "Armor" then
		return { def.Slot }
	elseif def.Kind == "Accessory" then
		return { "Accessory1", "Accessory2" }
	end
	return {}
end

function InventoryCore.equip(profile, uid: string, slot: string?)
	if type(uid) ~= "string" then
		return false, "InvalidItem"
	end
	local inst = profile.Inventory.Items[uid]
	if not inst then
		return false, "NotOwned"
	end
	local def = Items[inst.Id]
	local allowed = InventoryCore.slotsFor(def)
	if #allowed == 0 then
		return false, "NotEquippable"
	end
	local target = slot
	if target == nil then
		target = allowed[1]
		if def.Kind == "Accessory" and profile.Equipped.Accessory1 and not profile.Equipped.Accessory2 then
			target = "Accessory2"
		end
	end
	if not table.find(allowed, target) then
		return false, "WrongSlot"
	end
	-- prevent the same accessory id in both accessory slots (no double-stacking bonuses)
	if def.Kind == "Accessory" then
		local other = if target == "Accessory1" then "Accessory2" else "Accessory1"
		local otherUid = profile.Equipped[other]
		if otherUid and otherUid ~= uid and profile.Inventory.Items[otherUid] and profile.Inventory.Items[otherUid].Id == inst.Id then
			return false, "DuplicateAccessory"
		end
	end
	-- move from any other slot it currently occupies
	for s, v in profile.Equipped do
		if v == uid then
			profile.Equipped[s] = nil
		end
	end
	profile.Equipped[target] = uid
	return true, target
end

function InventoryCore.unequip(profile, slot: string)
	if type(slot) ~= "string" or profile.Equipped[slot] == nil then
		return false, "NothingEquipped"
	end
	profile.Equipped[slot] = nil
	return true, slot
end

-- Sell equipment (uid) or stackables (itemId + amount). Currency is computed server-side.
function InventoryCore.sell(profile, key: string, amount: number?)
	if type(key) ~= "string" then
		return false, "InvalidItem"
	end
	local inst = profile.Inventory.Items[key]
	if inst then
		if InventoryCore.isEquipped(profile, key) then
			return false, "Equipped"
		end
		local def = Items[inst.Id]
		local price = Formulas.sellPrice(def)
		if price <= 0 then
			return false, "CannotSell"
		end
		profile.Inventory.Items[key] = nil
		profile.Currency = math.min(GameConfig.Currency.MaxCarried, profile.Currency + price)
		return true, price
	end
	local def = Items[key]
	if not def or not def.Stackable then
		return false, "NotOwned"
	end
	local qty = amount or 1
	if not isPositiveInt(qty) then
		return false, "InvalidQuantity"
	end
	local price = Formulas.sellPrice(def)
	if price <= 0 then
		return false, "CannotSell"
	end
	if InventoryCore.stackCount(profile, key) < qty then
		return false, "NotEnough"
	end
	InventoryCore.removeStack(profile, key, qty)
	profile.Currency = math.min(GameConfig.Currency.MaxCarried, profile.Currency + price * qty)
	return true, price * qty
end

-- Returns a preview { Cost, From, To, Before, After } or nil, err
function InventoryCore.upgradePreview(profile, uid: string, attrs)
	local inst = profile.Inventory.Items[uid]
	if not inst then
		return nil, "NotOwned"
	end
	local def = Items[inst.Id]
	local cost = Formulas.upgradeCost(def, inst.Upgrade)
	if not cost then
		return nil, "MaxLevel"
	end
	local preview = { Cost = cost, From = inst.Upgrade, To = inst.Upgrade + 1 }
	if def.Kind == "Weapon" then
		preview.Before = Formulas.weaponAttackRating(def, inst.Upgrade, attrs).Total
		preview.After = Formulas.weaponAttackRating(def, inst.Upgrade + 1, attrs).Total
	elseif def.Kind == "Shield" then
		preview.Before = Formulas.shieldStability(def, inst.Upgrade)
		preview.After = Formulas.shieldStability(def, inst.Upgrade + 1)
	elseif def.Kind == "Armor" then
		preview.Before = (Formulas.armorDefense(def, inst.Upgrade))
		preview.After = (Formulas.armorDefense(def, inst.Upgrade + 1))
	end
	return preview, nil
end

function InventoryCore.upgrade(profile, uid: string, attrs)
	if type(uid) ~= "string" then
		return false, "InvalidItem"
	end
	local preview, err = InventoryCore.upgradePreview(profile, uid, attrs or {})
	if not preview then
		return false, err
	end
	local cost = preview.Cost
	if profile.Currency < cost.Currency then
		return false, "NotEnoughCurrency"
	end
	if InventoryCore.stackCount(profile, cost.Material) < cost.Amount then
		return false, "NotEnoughMaterials"
	end
	-- all checks passed: mutate
	InventoryCore.removeStack(profile, cost.Material, cost.Amount)
	profile.Currency -= cost.Currency
	local inst = profile.Inventory.Items[uid]
	inst.Upgrade += 1
	return true, preview
end

function InventoryCore.highestUpgrade(profile): number
	local best = 0
	for _, inst in profile.Inventory.Items do
		if inst.Upgrade > best then
			best = inst.Upgrade
		end
	end
	return best
end

return InventoryCore
