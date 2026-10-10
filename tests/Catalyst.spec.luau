-- Staff/Seal move sets: spells while mana lasts, mana-free strikes while it recharges.
local SSS = game:GetService("ServerScriptService")
local Shared = game:GetService("ReplicatedStorage").Shared
local CombatCore = require(SSS.Server.Core.CombatCore)
local Catalyst = require(Shared.Logic.Catalyst)
local WeaponTypes = require(Shared.Config.WeaponTypes)
local Stats = require(Shared.Logic.Stats)
local Helpers = require(game:GetService("ServerStorage").Tests.Helpers)

return function(t)
	local expect = t.expect
	local function setup()
		local s = CombatCore.newPlayerState(Stats.compute(Helpers.profile("Mage")), -100)
		s.MaxMana, s.Mana = 200, 200
		s.MaxStamina, s.Stamina = 1000, 1000
		return s
	end
	-- performs attacks back to back inside the combo window
	local clock = 0
	local function swing(s, kind)
		local ok, info = CombatCore.attack(s, kind, s.__weapon or "Staff", clock)
		if ok then
			clock = s.ActionLockUntil + 0.01
		end
		return ok, info
	end

	t.it("staff light combo casts three different spells with per-step mana costs", function()
		local s = setup()
		local names, costs = {}, {}
		for i = 1, 3 do
			local ok, info = swing(s, "Light")
			expect(ok).toBe(true)
			expect(info.Mode).toBe("Spell")
			expect(info.Ranged).toBe(true)
			names[i], costs[i] = info.Name, info.ManaCost
		end
		expect(names[1]).toBe("Arcane Bolt")
		expect(names[2]).toBe("Twin Bolts")
		expect(names[3]).toBe("Arcane Burst")
		expect(costs[1] + costs[2] + costs[3]).toBe(6 + 8 + 12)
		expect(s.Mana).toBe(200 - 26)
	end)

	t.it("twin bolts fire two projectiles and arcane burst pierces", function()
		local s = setup()
		swing(s, "Light")
		local _, twin = swing(s, "Light")
		expect(twin.Spell.Shots).toBe(2)
		local _, burst = swing(s, "Light")
		expect(burst.Spell.Pierce).toBe(true)
		local _, orb = swing(s, "Heavy")
		expect(orb.Name).toBe("Charged Orb")
	end)

	t.it("with no mana the staff strikes in melee instead of refusing", function()
		local s = setup()
		s.Mana = 0
		local names = {}
		for i = 1, 3 do
			local ok, info = swing(s, "Light")
			expect(ok).toBe(true)
			expect(info.Mode).toBe("Melee")
			expect(info.Ranged).toBe(false)
			expect(info.ManaCost).toBe(0)
			expect(info.Range).toBe(WeaponTypes.Staff.Fallback.Range)
			names[i] = info.Name
		end
		expect(names[1]).toBe("Staff Jab")
		expect(names[2]).toBe("Staff Sweep")
		expect(names[3]).toBe("Overhead Crack")
		expect(s.Mana).toBe(0)
		local ok, heavy = swing(s, "Heavy")
		expect(ok).toBe(true)
		expect(heavy.Name).toBe("Spinning Sweep")
		expect(heavy.Arc).toBe(360)
	end)

	t.it("strikes deal less than spells (motion values)", function()
		local fb = WeaponTypes.Staff.Fallback
		for i, m in fb.Light.Motion do
			expect(m < WeaponTypes.Staff.Light.Motion[1] + 0.01).toBeTruthy()
			expect(i <= #fb.Light.Names).toBeTruthy()
		end
		expect(fb.ManaOnHit > 0).toBeTruthy()
	end)

	t.it("running short mid-combo switches to strikes and restarts the combo", function()
		local s = setup()
		s.Mana = 7 -- enough for Arcane Bolt (6), not Twin Bolts (8)
		local _, a = swing(s, "Light")
		expect(a.Name).toBe("Arcane Bolt")
		local _, b = swing(s, "Light")
		expect(b.Mode).toBe("Melee")
		expect(b.Name).toBe("Staff Jab") -- step 1 of the strike combo, not step 2
		local _, c = swing(s, "Light")
		expect(c.Name).toBe("Staff Sweep")
		s.Mana = 200 -- mana recharged: back to spells, combo restarts at the first spell
		local _, d = swing(s, "Light")
		expect(d.Mode).toBe("Spell")
		expect(d.Name).toBe("Arcane Bolt")
	end)

	t.it("seal has holy spells and a mana-free bash", function()
		local s = setup()
		s.__weapon = "Seal"
		local _, a = swing(s, "Light")
		expect(a.Name).toBe("Holy Burst")
		s.Mana = 0
		local _, b = swing(s, "Light")
		expect(b.Mode).toBe("Melee")
		expect(b.Name).toBe("Seal Bash")
		local _, h = swing(s, "Heavy")
		expect(h.Name).toBe("Consecrated Slam")
	end)

	t.it("non-catalyst weapons are unaffected", function()
		local s = setup()
		s.__weapon = "Sword"
		s.Mana = 0
		local ok, info = swing(s, "Light")
		expect(ok).toBe(true)
		expect(info.Mode).toBe("Weapon")
		expect(info.ManaCost).toBe(0)
		expect(info.Name).toBe(nil)
	end)

	t.it("client and server pick the same move (shared rule)", function()
		-- the client runs Catalyst.choose with its own mirrored combo state
		local s = setup()
		local combo, mode = 0, nil
		local manas = { 200, 9, 3, 3, 200, 200 }
		for _, mana in manas do
			s.Mana = mana
			local predicted = Catalyst.choose(WeaponTypes.Staff, "Light", combo, combo > 0, mode, mana)
			local _, info = swing(s, "Light")
			expect(info.Mode).toBe(predicted.Mode)
			expect(info.Name).toBe(predicted.Name)
			combo, mode = predicted.Combo, predicted.Mode
		end
	end)
end
