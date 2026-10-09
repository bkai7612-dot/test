local RS = game:GetService("ReplicatedStorage")
local Formulas = require(RS.Shared.Logic.Formulas)
local Items = require(RS.Shared.Config.Items)
local GameConfig = require(RS.Shared.Config.GameConfig)

return function(t)
	local expect = t.expect
	local attrs = { Vigor = 10, Endurance = 10, Strength = 10, Dexterity = 10, Intelligence = 10, Faith = 10, Arcane = 10 }

	t.it("softCap applies diminishing segments", function()
		local curve = { Base = 100, Segments = { { 10, 2 }, { 20, 1 } } }
		expect(Formulas.softCap(0, curve)).toBe(100)
		expect(Formulas.softCap(10, curve)).toBe(120)
		expect(Formulas.softCap(20, curve)).toBe(130)
		expect(Formulas.softCap(99, curve)).toBe(130)
	end)

	t.it("health has diminishing returns past soft caps", function()
		local h20 = Formulas.maxHealth({ Vigor = 20 })
		local h40 = Formulas.maxHealth({ Vigor = 40 })
		local h60 = Formulas.maxHealth({ Vigor = 60 })
		local h99 = Formulas.maxHealth({ Vigor = 99 })
		expect(h40 - h20 > h60 - h40).toBeTruthy()
		expect((h99 - h60) / 39 < (h60 - h40) / 20).toBeTruthy()
	end)

	t.it("xp curve is strictly increasing and capped", function()
		local prev = 0
		for l = 1, GameConfig.Level.Max - 1 do
			local x = Formulas.xpToNext(l)
			expect(x > prev).toBeTruthy()
			prev = x
		end
		expect(Formulas.xpToNext(GameConfig.Level.Max)).toBe(math.huge)
	end)

	t.it("weapon AR increases with upgrades and scaling attribute", function()
		local def = Items.knight_longsword
		local a = Formulas.weaponAttackRating(def, 0, { Strength = 12, Dexterity = 10 })
		local b = Formulas.weaponAttackRating(def, 5, { Strength = 12, Dexterity = 10 })
		local c = Formulas.weaponAttackRating(def, 5, { Strength = 40, Dexterity = 10 })
		expect(b.Total > a.Total).toBeTruthy()
		expect(c.Total > b.Total).toBeTruthy()
	end)

	t.it("unmet requirements penalise but do not lock the weapon", function()
		local def = Items.iron_greatsword
		local weak = Formulas.weaponAttackRating(def, 0, { Strength = 8 })
		local strong = Formulas.weaponAttackRating(def, 0, { Strength = 16 })
		expect(weak.RequirementsMet).toBe(false)
		expect(weak.Total > 0).toBeTruthy()
		expect(strong.Total > weak.Total).toBeTruthy()
	end)

	t.it("upgrade levels are clamped to the path maximum", function()
		local def = Items.warden_halberd -- Unique path, max 5
		local five = Formulas.weaponAttackRating(def, 5, attrs)
		local ninetynine = Formulas.weaponAttackRating(def, 99, attrs)
		expect(ninetynine.Total).toBe(five.Total)
		expect(Formulas.upgradeCost(def, 5)).toBeNil()
		expect(Formulas.upgradeCost(def, 0).Material).toBe("fallen_remnant")
	end)

	t.it("absorption is capped", function()
		expect(Formulas.absorption(1e9, 100)).toBe(GameConfig.Combat.MaxAbsorption)
		expect(Formulas.absorption(0, 100)).toBe(0)
	end)

	t.it("boss stats escalate monotonically", function()
		for f = 2, 20 do
			expect(Formulas.bossHealth(f) > Formulas.bossHealth(f - 1)).toBeTruthy()
			expect(Formulas.bossDamage(f) > Formulas.bossDamage(f - 1)).toBeTruthy()
			expect(Formulas.bossTiming(f).Windup <= Formulas.bossTiming(f - 1).Windup).toBeTruthy()
		end
	end)

	t.it("boss items cannot be sold", function()
		expect(Formulas.sellPrice(Items.sovereign_blade)).toBe(0)
		expect(Formulas.sellPrice(Items.rusted_longsword) > 0).toBeTruthy()
	end)

	t.it("party health scaling", function()
		expect(Formulas.partyHealthMult(1)).toBe(1)
		expect(Formulas.partyHealthMult(4)).toBeNear(1 + 3 * GameConfig.Party.BossHealthPerExtraPlayer)
	end)
end
