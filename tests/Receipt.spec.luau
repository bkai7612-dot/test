local SSS = game:GetService("ServerScriptService")
local ReceiptCore = require(SSS.Server.Core.ReceiptCore)
local Products = require(game:GetService("ReplicatedStorage").Shared.Config.Products)
local Helpers = require(game:GetService("ServerStorage").Tests.Helpers)

return function(t)
	local expect = t.expect
	-- configure a fake product id for the test only
	local function withProduct(fn)
		local old = Products.DevProducts.aura_wisp.Id
		Products.DevProducts.aura_wisp.Id = 555
		local ok, err = pcall(fn)
		Products.DevProducts.aura_wisp.Id = old
		if not ok then error(err, 0) end
	end

	t.it("grants once per PurchaseId", function()
		withProduct(function()
			local p = Helpers.profile("Warrior")
			local s1, granted = ReceiptCore.process(p, { PurchaseId = "abc", ProductId = 555 })
			expect(s1).toBe("Granted")
			expect(granted[1]).toBe("aura_wisp")
			local s2 = ReceiptCore.process(p, { PurchaseId = "abc", ProductId = 555 })
			expect(s2).toBe("AlreadyGranted")
			expect(p.Purchases.Products.aura_wisp).toBe(1)
		end)
	end)

	t.it("unknown and unconfigured (id 0) products are not processed", function()
		local p = Helpers.profile("Warrior")
		expect((ReceiptCore.process(p, { PurchaseId = "x", ProductId = 999 }))).toBe("Unknown")
		expect((ReceiptCore.process(p, { PurchaseId = "y", ProductId = 0 }))).toBe("Unknown")
		expect(#p.Purchases.ProcessedReceipts).toBe(0)
	end)

	t.it("receipt history is bounded", function()
		withProduct(function()
			local p = Helpers.profile("Warrior")
			for i = 1, 200 do
				ReceiptCore.process(p, { PurchaseId = "r" .. i, ProductId = 555 })
			end
			expect(#p.Purchases.ProcessedReceipts <= 80).toBeTruthy()
		end)
	end)
end
