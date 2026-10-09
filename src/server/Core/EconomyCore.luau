--[[
	EconomyCore
	Server-authoritative shop purchases. The client sends only (shopId, itemId, quantity);
	price, availability and limits come from Config/Shops.luau.
	All validation happens before any mutation, so a purchase either fully succeeds or
	changes nothing (no negative balances, no partial grants).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Shops = require(Shared.Config.Shops)
local Items = require(Shared.Config.Items)
local InventoryCore = require(script.Parent.InventoryCore)

local EconomyCore = {}

function EconomyCore.findStock(shopId: string, itemId: string)
	local shop = Shops[shopId]
	if not shop then
		return nil
	end
	for _, entry in shop.Stock do
		if entry.Item == itemId then
			return entry
		end
	end
	return nil
end

function EconomyCore.isVisible(entry, highestCleared: number): boolean
	return (entry.RequiresFloor or 0) <= highestCleared
end

function EconomyCore.purchaseKey(shopId: string, itemId: string): string
	return shopId .. ":" .. itemId
end

function EconomyCore.remainingLimit(profile, shopId: string, entry): number?
	if not entry.Limit then
		return nil
	end
	local bought = profile.ShopPurchases[EconomyCore.purchaseKey(shopId, entry.Item)] or 0
	return math.max(0, entry.Limit - bought)
end

function EconomyCore.buy(profile, shopId, itemId, quantity)
	if type(shopId) ~= "string" or type(itemId) ~= "string" then
		return false, "InvalidRequest"
	end
	if type(quantity) ~= "number" or quantity ~= quantity or math.floor(quantity) ~= quantity
		or quantity < 1 or quantity > GameConfig.Shop.MaxPurchaseQuantity then
		return false, "InvalidQuantity"
	end
	local entry = EconomyCore.findStock(shopId, itemId)
	if not entry or not Items[itemId] then
		return false, "NotForSale"
	end
	if not EconomyCore.isVisible(entry, profile.Tower.HighestCleared) then
		return false, "Locked"
	end
	local limit = EconomyCore.remainingLimit(profile, shopId, entry)
	if limit and quantity > limit then
		return false, "LimitReached"
	end
	local total = entry.Price * quantity
	if total <= 0 or total ~= total then
		return false, "InvalidPrice"
	end
	if profile.Currency < total then
		return false, "NotEnoughCurrency"
	end
	local canAdd, err = InventoryCore.canAdd(profile, itemId, quantity)
	if not canAdd then
		return false, err
	end
	-- mutate
	profile.Currency -= total
	local ok, result = InventoryCore.addItem(profile, itemId, quantity)
	if not ok then
		-- should be impossible after canAdd; refund defensively
		profile.Currency += total
		return false, result
	end
	if entry.Limit then
		local key = EconomyCore.purchaseKey(shopId, itemId)
		profile.ShopPurchases[key] = (profile.ShopPurchases[key] or 0) + quantity
	end
	return true, { Spent = total, Item = itemId, Quantity = quantity, Uids = result.Uids }
end

function EconomyCore.addCurrency(profile, amount: number): number
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return 0
	end
	local before = profile.Currency
	profile.Currency = math.min(GameConfig.Currency.MaxCarried, before + math.floor(amount))
	return profile.Currency - before
end

return EconomyCore
