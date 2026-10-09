local SSS = game:GetService("ServerScriptService")
local InventoryCore = require(SSS.Server.Core.InventoryCore)
local Helpers = require(game:GetService("ServerStorage").Tests.Helpers)

return function(t)
	local expect = t.expect

	t.it("class loadout is owned and equipped", function()
		local p = Helpers.profile("Knight")
		expect(p.Equipped.Weapon ~= nil).toBeTruthy()
		expect(p.Equipped.Offhand ~= nil).toBeTruthy()
		expect(p.Inventory.Items[p.Equipped.Weapon].Id).toBe("knight_longsword")
		expect(p.Equipped.Head ~= nil and p.Equipped.Chest ~= nil and p.Equipped.Hands ~= nil and p.Equipped.Feet ~= nil).toBeTruthy()
	end)

	t.it("rejects invalid quantities", function()
		local p = Helpers.profile("Warrior")
		for _, q in { 0, -1, 1.5, 0 / 0, math.huge, "3" } do
			local ok = InventoryCore.addItem(p, "ember_shard", q)
			expect(ok).toBe(false)
		end
	end)

	t.it("equip validates slot compatibility and ownership", function()
		local p = Helpers.profile("Warrior")
		local _, res = InventoryCore.addItem(p, "hearth_ring", 1)
		local uid = res.Uids[1]
		expect((InventoryCore.equip(p, uid, "Weapon"))).toBe(false)
		expect((InventoryCore.equip(p, "i99999", "Weapon"))).toBe(false)
		local ok, slot = InventoryCore.equip(p, uid)
		expect(ok).toBe(true)
		expect(slot).toBe("Accessory1")
	end)

	t.it("cannot double-equip the same accessory id", function()
		local p = Helpers.profile("Warrior")
		local _, a = InventoryCore.addItem(p, "hearth_ring", 2)
		expect((InventoryCore.equip(p, a.Uids[1], "Accessory1"))).toBe(true)
		local ok, err = InventoryCore.equip(p, a.Uids[2], "Accessory2")
		expect(ok).toBe(false)
		expect(err).toBe("DuplicateAccessory")
	end)

	t.it("cannot sell equipped or boss items; selling credits once", function()
		local p = Helpers.profile("Warrior")
		local before = p.Currency
		expect((InventoryCore.sell(p, p.Equipped.Weapon))).toBe(false)
		local _, r = InventoryCore.addItem(p, "rusted_longsword", 1)
		local ok, price = InventoryCore.sell(p, r.Uids[1])
		expect(ok).toBe(true)
		expect(p.Currency).toBe(before + price)
		expect((InventoryCore.sell(p, r.Uids[1]))).toBe(false) -- already gone
		local _, b = InventoryCore.addItem(p, "sovereign_blade", 1)
		expect((InventoryCore.sell(p, b.Uids[1]))).toBe(false)
	end)

	t.it("upgrade consumes exact materials and currency, failure leaves profile untouched", function()
		local p = Helpers.profile("Warrior")
		local uid = p.Equipped.Weapon
		p.Currency = 100
		p.Inventory.Stacks.ember_shard = nil
		local snap = Helpers.snapshot(p)
		local ok, err = InventoryCore.upgrade(p, uid, p.Attributes)
		expect(ok).toBe(false)
		expect(err).toBe("NotEnoughCurrency")
		expect(p).toEqual(snap)
		p.Currency = 1000
		ok, err = InventoryCore.upgrade(p, uid, p.Attributes)
		expect(err).toBe("NotEnoughMaterials")
		InventoryCore.addItem(p, "ember_shard", 1)
		ok = InventoryCore.upgrade(p, uid, p.Attributes)
		expect(ok).toBe(true)
		expect(p.Inventory.Items[uid].Upgrade).toBe(1)
		expect(p.Currency).toBe(800)
		expect(InventoryCore.stackCount(p, "ember_shard")).toBe(0)
	end)

	t.it("upgrade preview shows before/after stats", function()
		local p = Helpers.profile("Warrior")
		local preview = InventoryCore.upgradePreview(p, p.Equipped.Weapon, p.Attributes)
		expect(preview.After > preview.Before).toBeTruthy()
		expect(preview.Cost.Currency > 0).toBeTruthy()
	end)

	t.it("stack and slot capacity are enforced", function()
		local p = Helpers.profile("Warrior")
		local ok = InventoryCore.addItem(p, "wild_hide", 999)
		expect(ok).toBe(true)
		expect((InventoryCore.addItem(p, "wild_hide", 1))).toBe(false)
		local ok2, res = InventoryCore.addItem(p, "wild_hide", 5, true)
		expect(ok2).toBe(true)
		expect(res.Added).toBe(0)
	end)
end
