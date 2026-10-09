--[[
	PurchaseService
	Monetisation (cosmetic / convenience only) through Roblox-supported flows.

	Developer Products: MarketplaceService.ProcessReceipt -> ReceiptCore (idempotent by
	PurchaseId). We only return PurchaseGranted after the grant is SAVED; if the save fails we
	return NotProcessedYet and Roblox retries later - the receipt id is already recorded in the
	profile, so the retry cannot grant twice.
	Game Passes: ownership checked with UserOwnsGamePassAsync on join and after
	PromptGamePassPurchaseFinished. Products with Id = 0 are disabled.
	Clients may only *request a prompt*; they can never grant anything.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Products = require(Shared.Config.Products)
local ReceiptCore = require(script.Parent.Parent.Core.ReceiptCore)

local PurchaseService = {}
local S

function PurchaseService.Init(services)
	S = services
end

local function checkPasses(player: Player)
	local rt = S.PlayerStateService.Get(player)
	if not rt then
		return
	end
	local pass = Products.GamePasses.wardrobe_plus
	if pass.Id ~= 0 then
		local ok, owns = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.Id)
		end)
		rt.HasWardrobePass = ok and owns == true
	end
	S.PlayerStateService.Sync(player)
end

local function processReceipt(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	-- wait briefly for the profile if the player just joined
	local rt
	for _ = 1, 20 do
		rt = S.PlayerStateService.Get(player)
		if rt then
			break
		end
		task.wait(0.5)
	end
	if not rt then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local status, granted = ReceiptCore.process(rt.Profile, receipt)
	if status == "Unknown" then
		warn("[PurchaseService] unknown product " .. tostring(receipt.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if status == "Granted" then
		S.NotifyService.Banner(player, "THANK YOU", "Cosmetic unlocked: " .. table.concat(granted or {}, ", "), "Reward")
		S.PlayerStateService.Sync(player)
	end
	-- persist before acknowledging
	if not S.DataService.Save(player) and not S.DataService.IsMemoryMode() then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function PurchaseService.Start()
	MarketplaceService.ProcessReceipt = processReceipt
	S.PlayerStateService.CharacterReady:Connect(function(player)
		task.spawn(checkPasses, player)
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if purchased then
			checkPasses(player)
		end
	end)
	S.RequestService.Register("PromptProduct", function(player, rt, key)
		local p = type(key) == "string" and Products.DevProducts[key]
		if not p or p.Id == 0 then
			return false, "Unavailable"
		end
		MarketplaceService:PromptProductPurchase(player, p.Id)
		return true, nil
	end)
	S.RequestService.Register("PromptPass", function(player, rt, key)
		local p = type(key) == "string" and Products.GamePasses[key]
		if not p or p.Id == 0 then
			return false, "Unavailable"
		end
		MarketplaceService:PromptGamePassPurchase(player, p.Id)
		return true, nil
	end)
end

return PurchaseService
