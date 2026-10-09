local SSS = game:GetService("ServerScriptService")
local ProfileSchema = require(SSS.Server.Core.ProfileSchema)
local GameConfig = require(game:GetService("ReplicatedStorage").Shared.Config.GameConfig)
local Helpers = require(game:GetService("ServerStorage").Tests.Helpers)

return function(t)
	local expect = t.expect

	t.it("non-table data produces a default profile with a correction note", function()
		local p, corr = ProfileSchema.reconcile("garbage")
		expect(p.Level).toBe(1)
		expect(#corr > 0).toBeTruthy()
	end)

	t.it("corrupt values are clamped without wiping progress", function()
		local p = Helpers.profile("Warrior")
		p.Level = 30
		p.Currency = -50
		p.Attributes.Vigor = 500
		p.Xp = 0 / 0
		p.Inventory.Items.i999 = { Id = "does_not_exist", Upgrade = 3 }
		p.Inventory.Stacks.ember_shard = -4
		p.Equipped.Head = "i424242"
		p.Abilities.Slot2 = "ghost_ability"
		p.LostCurrency = { Amount = "lots" }
		local fixed, corr = ProfileSchema.reconcile(Helpers.snapshot(p))
		expect(fixed.Level).toBe(30)
		expect(fixed.Class).toBe("Warrior")
		expect(fixed.Currency).toBe(0)
		expect(fixed.Attributes.Vigor).toBe(99)
		expect(fixed.Xp).toBe(0)
		expect(fixed.Inventory.Items.i999).toBeNil()
		expect(fixed.Inventory.Stacks.ember_shard).toBeNil()
		expect(fixed.Equipped.Head).toBeNil()
		expect(fixed.Abilities.Slot2).toBe("")
		expect(fixed.LostCurrency).toBeNil()
		expect(fixed.Equipped.Weapon ~= nil).toBeTruthy() -- valid equipment kept
		expect(#corr >= 8).toBeTruthy()
	end)

	t.it("missing fields are filled from defaults", function()
		local fixed = ProfileSchema.reconcile({ DataVersion = GameConfig.DataVersion, Level = 5, Class = "Mage" })
		expect(fixed.Level).toBe(5)
		expect(type(fixed.Inventory.Items)).toBe("table")
		expect(type(fixed.Settings.CameraSensitivity)).toBe("number")
	end)

	t.it("v1 data migrates", function()
		local fixed = ProfileSchema.reconcile({ DataVersion = 1, Gold = 1234, Tower = 4, Class = "Knight", Level = 12 })
		expect(fixed.Currency).toBe(1234)
		expect(fixed.Tower.HighestCleared).toBe(4)
		expect(fixed.Gold).toBeNil()
		expect(fixed.DataVersion).toBe(GameConfig.DataVersion)
	end)

	t.it("uid counter stays ahead of existing uids", function()
		local p = Helpers.profile("Warrior")
		p.Inventory.Items.i500 = { Id = "rusted_longsword", Upgrade = 0 }
		p.Inventory.NextUid = 3
		local fixed = ProfileSchema.reconcile(p)
		expect(fixed.Inventory.NextUid).toBe(501)
	end)

	t.it("reconcile is idempotent", function()
		local p = Helpers.profile("Paladin")
		local a = ProfileSchema.reconcile(Helpers.snapshot(p))
		local b = ProfileSchema.reconcile(Helpers.snapshot(a))
		a.Corrections, b.Corrections = nil, nil
		expect(a).toEqual(b)
	end)
end
