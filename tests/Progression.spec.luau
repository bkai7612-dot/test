local SSS = game:GetService("ServerScriptService")
local ProgressionCore = require(SSS.Server.Core.ProgressionCore)
local Formulas = require(game:GetService("ReplicatedStorage").Shared.Logic.Formulas)
local GameConfig = require(game:GetService("ReplicatedStorage").Shared.Config.GameConfig)
local Helpers = require(game:GetService("ServerStorage").Tests.Helpers)

return function(t)
	local expect = t.expect

	t.it("class can only be chosen once", function()
		local p = Helpers.profile()
		expect((ProgressionCore.chooseClass(p, "Mage"))).toBe(true)
		expect((ProgressionCore.chooseClass(p, "Warrior"))).toBe(false)
		expect(p.Class).toBe("Mage")
		expect((ProgressionCore.chooseClass(Helpers.profile(), "Necromancer"))).toBe(false)
	end)

	t.it("xp grants levels and points", function()
		local p = Helpers.profile("Warrior")
		local need = Formulas.xpToNext(1) + Formulas.xpToNext(2)
		local r = ProgressionCore.grantXp(p, need + 5)
		expect(r.Levels).toBe(2)
		expect(p.Level).toBe(3)
		expect(p.UnspentPoints).toBe(2)
		expect(p.Xp).toBe(5)
	end)

	t.it("rejects invalid xp amounts", function()
		local p = Helpers.profile("Warrior")
		for _, x in { -100, 0 / 0, math.huge, "100" } do
			ProgressionCore.grantXp(p, x)
		end
		expect(p.Level).toBe(1)
		expect(p.Xp).toBe(0)
	end)

	t.it("level cap is enforced", function()
		local p = Helpers.profile("Warrior")
		ProgressionCore.grantXp(p, 1e12)
		expect(p.Level).toBe(GameConfig.Level.Max)
		expect(p.Xp).toBe(0)
	end)

	t.it("allocation is validated and all-or-nothing", function()
		local p = Helpers.profile("Warrior")
		p.UnspentPoints = 3
		expect((ProgressionCore.allocate(p, { Vigor = 2, Strength = 2 }))).toBe(false)
		expect(p.UnspentPoints).toBe(3)
		expect((ProgressionCore.allocate(p, { Vigor = -1, Strength = 4 }))).toBe(false)
		expect((ProgressionCore.allocate(p, { Luck = 1 }))).toBe(false)
		expect((ProgressionCore.allocate(p, { Vigor = 1.5 }))).toBe(false)
		local vig = p.Attributes.Vigor
		expect((ProgressionCore.allocate(p, { Vigor = 2, Strength = 1 }))).toBe(true)
		expect(p.Attributes.Vigor).toBe(vig + 2)
		expect(p.UnspentPoints).toBe(0)
	end)

	t.it("attribute cap 99", function()
		local p = Helpers.profile("Warrior")
		p.UnspentPoints = 200
		expect((ProgressionCore.allocate(p, { Vigor = 99 }))).toBe(false)
	end)

	t.it("second class ability unlocks at level 10", function()
		local p = Helpers.profile("Mage")
		expect(p.Abilities.Unlocked.glacial_ring).toBeNil()
		ProgressionCore.grantXp(p, Formulas.totalXpForLevel(10))
		expect(p.Level).toBe(10)
		expect(p.Abilities.Unlocked.glacial_ring).toBe(true)
		expect(p.Abilities.Slot2).toBe("glacial_ring")
	end)

	t.it("ability slots only accept unlocked abilities", function()
		local p = Helpers.profile("Mage")
		expect((ProgressionCore.setAbilitySlot(p, "Slot1", "sovereign_wrath"))).toBe(false)
		expect((ProgressionCore.setAbilitySlot(p, "Slot3", "firebolt"))).toBe(false)
		ProgressionCore.unlockAbility(p, "ash_wave")
		expect((ProgressionCore.setAbilitySlot(p, "Slot2", "ash_wave"))).toBe(true)
	end)
end
