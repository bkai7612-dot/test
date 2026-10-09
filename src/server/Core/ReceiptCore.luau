--[[
	ReceiptCore
	Idempotent Developer Product receipt handling (MarketplaceService.ProcessReceipt).

	process() returns one of:
	  "Granted"        newly granted; caller must SAVE successfully before returning PurchaseGranted
	  "AlreadyGranted" PurchaseId was processed before; return PurchaseGranted without re-granting
	  "Unknown"        product id is not configured; return NotProcessedYet
	Rewards are only ever cosmetics; nothing here affects combat power.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Products = require(Shared.Config.Products)
local Cosmetics = require(Shared.Config.Cosmetics)

local ReceiptCore = {}

function ReceiptCore.findProduct(productId: number)
	if type(productId) ~= "number" or productId == 0 then
		return nil, nil
	end
	for key, p in Products.DevProducts do
		if p.Id == productId then
			return key, p
		end
	end
	return nil, nil
end

function ReceiptCore.isProcessed(profile, purchaseId: string): boolean
	return table.find(profile.Purchases.ProcessedReceipts, purchaseId) ~= nil
end

function ReceiptCore.grant(profile, grant)
	local granted = {}
	local list = grant.Cosmetics or (grant.Cosmetic and { grant.Cosmetic }) or {}
	for _, id in list do
		if Cosmetics[id] then
			profile.Cosmetics.Owned[id] = true
			table.insert(granted, id)
		end
	end
	return granted
end

function ReceiptCore.process(profile, receipt)
	local purchaseId = tostring(receipt.PurchaseId)
	if ReceiptCore.isProcessed(profile, purchaseId) then
		return "AlreadyGranted", nil
	end
	local key, product = ReceiptCore.findProduct(receipt.ProductId)
	if not product then
		return "Unknown", nil
	end
	local granted = ReceiptCore.grant(profile, product.Grant)
	local list = profile.Purchases.ProcessedReceipts
	table.insert(list, purchaseId)
	while #list > GameConfig.Save.ProcessedReceiptHistory do
		table.remove(list, 1)
	end
	profile.Purchases.Products[key] = (profile.Purchases.Products[key] or 0) + 1
	return "Granted", granted
end

return ReceiptCore
