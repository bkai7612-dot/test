local SSS = game:GetService("ServerScriptService")
local EconomyCore = require(SSS.Server.Core.EconomyCore)
local InventoryCore = require(SSS.Server.Core.InventoryCore)
local Helpers = require(game:GetService("ServerStorage").Tests.Helpers)

return function(t)
	local expect = t.expect

	t.it("buying deducts the server price and grants the item", function()
		local p = Helpers.profile("Warrior")
		p.Currency = 1000
		local ok, res = EconomyCore.buy(p, "potions", "healing_draught", 3)
		expect(ok).toBe(true)
		expect(res.Spent).toBe(360)
		expect(p.Currency).toBe(640)
	end)

	t.it("cannot create a negative balance", function()
		local p = Helpers.profile("Warrior")
		p.Currency = 100
		local snap = Helpers.snapshot(p)
		local ok, err = EconomyCore.buy(p, "potions", "healing_draught", 1)
		expect(ok).toBe(false)
		expect(err).toBe("NotEnoughCurrency")
		expect(p).toEqual(snap)
	end)

	t.it("rejects malicious quantities and ids", function()
		local p = Helpers.profile("Warrior")
		p.Currency = 1e6
		for _, q in { 0, -5, 2.5, 0 / 0, math.huge, 21, -math.huge } do
			expect((EconomyCore.buy(p, "potions", "healing_draught", q))).toBe(false)
		end
		expect((EconomyCore.buy(p, "potions", "sovereign_blade", 1))).toBe(false)
		expect((EconomyCore.buy(p, "nope", "healing_draught", 1))).toBe(false)
		expect((EconomyCore.buy(p, nil, nil, nil))).toBe(false)
		expect(p.Currency).toBe(1e6)
	end)

	t.it("locked stock requires tower progress", function()
		local p = Helpers.profile("Warrior")
		p.Currency = 1e6
		local ok, err = EconomyCore.buy(p, "weapons", "rift_staff", 1)
		expect(ok).toBe(false)
		expect(err).toBe("Locked")
		p.Tower.HighestCleared = 7
		expect((EconomyCore.buy(p, "weapons", "rift_staff", 1))).toBe(true)
	end)

	t.it("lifetime purchase limits cannot be bypassed by split purchases", function()
		local p = Helpers.profile("Warrior")
		p.Currency = 1e6
		p.Tower.HighestCleared = 5
		expect((EconomyCore.buy(p, "general", "flask_shard", 1))).toBe(true)
		expect((EconomyCore.buy(p, "general", "flask_shard", 2))).toBe(false)
		expect((EconomyCore.buy(p, "general", "flask_shard", 1))).toBe(true)
		expect((EconomyCore.buy(p, "general", "flask_shard", 1))).toBe(false)
		expect(InventoryCore.stackCount(p, "flask_shard")).toBe(2)
	end)

	t.it("buy then sell loop always loses currency", function()
		local p = Helpers.profile("Warrior")
		p.Currency = 10000
		for _ = 1, 10 do
			local ok, res = EconomyCore.buy(p, "weapons", "rusted_longsword", 1)
			expect(ok).toBe(true)
			InventoryCore.sell(p, res.Uids[1])
		end
		expect(p.Currency < 10000).toBeTruthy()
	end)

	t.it("full stacks refuse purchase without charging", function()
		local p = Helpers.profile("Warrior")
		p.Currency = 1e6
		p.Inventory.Stacks.healing_draught = 995
		local before = p.Currency
		expect((EconomyCore.buy(p, "potions", "healing_draught", 10))).toBe(false)
		expect(p.Currency).toBe(before)
	end)
end
