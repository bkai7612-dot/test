--[[
	ShopService
	Merchant purchases. Validation: the player must be near the NPC that runs `shopId`, and
	EconomyCore validates price, stock visibility, limits, quantity and balance atomically.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared.Config.Items)
local Shops = require(Shared.Config.Shops)
local EconomyCore = require(script.Parent.Parent.Core.EconomyCore)

local ShopService = {}
local S

function ShopService.Init(services)
	S = services
end

function ShopService.Start()
	S.RequestService.Register("Buy", function(player, rt, payload)
		if type(payload) ~= "table" or type(payload.Shop) ~= "string" or not Shops[payload.Shop] then
			return false, "BadRequest"
		end
		if not S.InteractionService.IsNearShop(player, payload.Shop) then
			return false, "NotAtMerchant"
		end
		local ok, res = EconomyCore.buy(rt.Profile, payload.Shop, payload.Item, payload.Quantity)
		if not ok then
			return false, res
		end
		S.NotifyService.Toast(player, ("Bought %s x%d"):format(Items[res.Item].Name, res.Quantity), "Loot")
		S.PlayerStateService.Sync(player)
		S.PlayerStateService.PushVitals(player)
		return true, res
	end)
end

return ShopService
