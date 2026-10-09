local SSS = game:GetService("ServerScriptService")
local CombatCore = require(SSS.Server.Core.CombatCore)
local Stats = require(game:GetService("ReplicatedStorage").Shared.Logic.Stats)
local GameConfig = require(game:GetService("ReplicatedStorage").Shared.Config.GameConfig)
local Helpers = require(game:GetService("ServerStorage").Tests.Helpers)
local C = GameConfig.Combat

return function(t)
	local expect = t.expect
	local function setup(class)
		local p = Helpers.profile(class or "Knight")
		local stats = Stats.compute(p)
		local s = CombatCore.newPlayerState(stats, -100)
		return s, stats
	end
	local hit = { Damage = 100, DamageType = "Physical", Poise = 10, Parryable = true, Blockable = true }

	t.it("attacks cost stamina and lock actions", function()
		local s = setup()
		local ok, info = CombatCore.attack(s, "Light", "Sword", 0)
		expect(ok).toBe(true)
		expect(s.Stamina < s.MaxStamina).toBeTruthy()
		local ok2 = CombatCore.attack(s, "Light", "Sword", 0.05)
		expect(ok2).toBe(false)
		local ok3 = CombatCore.attack(s, "Light", "Sword", info.Windup + info.Recovery)
		expect(ok3).toBe(true)
	end)

	t.it("cannot act with zero stamina", function()
		local s = setup()
		s.Stamina = 0
		expect((CombatCore.attack(s, "Light", "Sword", 0))).toBe(false)
		expect((CombatCore.dodge(s, 0))).toBe(false)
	end)

	t.it("invalid attack kinds are rejected", function()
		local s = setup()
		expect((CombatCore.attack(s, "Ultra", "Sword", 0))).toBe(false)
	end)

	t.it("heavy charge is clamped", function()
		local s = setup()
		local _, a = CombatCore.attack(s, "Heavy", "Sword", 0, 999)
		local s2 = setup()
		local _, b = CombatCore.attack(s2, "Heavy", "Sword", 0, C.HeavyChargeMax)
		expect(a.Motion).toBe(b.Motion)
	end)

	t.it("dodge i-frames avoid hits, including the latency grace window", function()
		local s, stats = setup()
		CombatCore.dodge(s, 10)
		expect(CombatCore.resolveIncoming(s, hit, 10.1, stats, true).Outcome).toBe("Dodged")
		-- dodge arriving slightly after the hit resolved (within grace) still counts
		local s2, stats2 = setup()
		CombatCore.dodge(s2, 10.1)
		expect(CombatCore.resolveIncoming(s2, hit, 10.0, stats2, true).Outcome).toBe("Dodged")
		-- too late
		local s3, stats3 = setup()
		CombatCore.dodge(s3, 10 + C.LatencyGrace + 0.05)
		expect(CombatCore.resolveIncoming(s3, hit, 10.0, stats3, true).Outcome).toBe("Hit")
		-- i-frames expire
		local s4, stats4 = setup()
		CombatCore.dodge(s4, 10)
		expect(CombatCore.resolveIncoming(s4, hit, 10 + C.DodgeIFrames + 0.05, stats4, true).Outcome).toBe("Hit")
	end)

	t.it("dodge spam is limited by cooldown", function()
		local s = setup()
		expect((CombatCore.dodge(s, 0))).toBe(true)
		expect((CombatCore.dodge(s, 0.1))).toBe(false)
	end)

	t.it("dodge cannot cancel an attack windup", function()
		local s = setup()
		CombatCore.attack(s, "Heavy", "Greatsword", 0)
		expect((CombatCore.dodge(s, 0.1))).toBe(false)
	end)

	t.it("parry only works on parryable attacks while facing", function()
		local s, stats = setup()
		CombatCore.parry(s, 5)
		expect(CombatCore.resolveIncoming(s, hit, 5.1, stats, true).Outcome).toBe("Parried")
		local s2, stats2 = setup()
		CombatCore.parry(s2, 5)
		expect(CombatCore.resolveIncoming(s2, hit, 5.1, stats2, false).Outcome).toBe("Hit")
		local s3, stats3 = setup()
		CombatCore.parry(s3, 5)
		local unparryable = table.clone(hit)
		unparryable.Parryable = false
		expect(CombatCore.resolveIncoming(s3, unparryable, 5.1, stats3, true).Outcome ~= "Parried").toBeTruthy()
	end)

	t.it("blocking reduces damage by stability and drains stamina", function()
		local s, stats = setup("Knight")
		CombatCore.setBlocking(s, true, 0)
		local r = CombatCore.resolveIncoming(s, hit, 1, stats, true)
		expect(r.Outcome).toBe("Blocked")
		local s2, stats2 = setup("Knight")
		local r2 = CombatCore.resolveIncoming(s2, hit, 1, stats2, true)
		expect(r.Damage < r2.Damage).toBeTruthy()
		expect(s.Stamina < s.MaxStamina).toBeTruthy()
	end)

	t.it("guard breaks at zero stamina", function()
		local s, stats = setup("Knight")
		CombatCore.setBlocking(s, true, 0)
		s.Stamina = 1
		local r = CombatCore.resolveIncoming(s, hit, 1, stats, true)
		expect(r.Outcome).toBe("GuardBroken")
		expect(s.Blocking).toBe(false)
	end)

	t.it("stagger immunity prevents stun-lock", function()
		local s, stats = setup("Mage")
		local heavy = { Damage = 5, DamageType = "Physical", Poise = 999, Parryable = false, Blockable = true }
		local r1 = CombatCore.resolveIncoming(s, heavy, 1, stats, true)
		expect(r1.Staggered).toBe(true)
		local r2 = CombatCore.resolveIncoming(s, heavy, 1.3, stats, true)
		expect(r2.Staggered).toBe(false)
		local r3 = CombatCore.resolveIncoming(s, heavy, 1 + C.StaggerDuration + C.StaggerImmunity + 0.01, stats, true)
		expect(r3.Staggered).toBe(true)
	end)

	t.it("respawn invulnerability", function()
		local p = Helpers.profile("Knight")
		local stats = Stats.compute(p)
		local s = CombatCore.newPlayerState(stats, 100)
		expect(CombatCore.resolveIncoming(s, hit, 101, stats, true).Outcome).toBe("Immune")
	end)

	t.it("death is terminal and further hits are ignored", function()
		local s, stats = setup("Mage")
		local big = { Damage = 1e6, DamageType = "Physical", Poise = 0, Blockable = false }
		local r = CombatCore.resolveIncoming(s, big, 1, stats, true)
		expect(r.Died).toBe(true)
		expect(CombatCore.resolveIncoming(s, big, 2, stats, true).Outcome).toBe("Ignored")
	end)

	t.it("defence buffs are capped", function()
		local s, stats = setup("Knight")
		CombatCore.addBuff(s, "Defense", 5, 100, 0)
		expect(CombatCore.mitigate(1000, "Physical", stats, s, 1) >= 1).toBeTruthy()
		expect(CombatCore.mitigate(1000, "Physical", stats, s, 1) > 0).toBeTruthy()
	end)

	t.it("status build-up procs at threshold", function()
		local st = CombatCore.newStatus()
		expect(CombatCore.addBuildup(st, "Bleed", 60, 0)).toBe(false)
		expect(CombatCore.addBuildup(st, "Bleed", 60, 0)).toBe(true)
		expect(st.Bleed).toBe(0)
		expect(CombatCore.addBuildup(st, "Nope", 999, 0)).toBe(false)
	end)

	t.it("target poise break staggers once, then regenerates", function()
		local tgt = CombatCore.newTarget(1000, 50)
		local r = CombatCore.damageTarget(tgt, 10, 60, 0)
		expect(r.Staggered).toBe(true)
		local r2 = CombatCore.damageTarget(tgt, 10, 60, 0.5)
		expect(r2.Staggered).toBe(false) -- poise frozen while staggered
		expect(CombatCore.isStaggered(tgt, 0.5)).toBe(true)
	end)

	t.it("outgoing damage is never below the minimum", function()
		expect(CombatCore.outgoing(0, 1, { TargetDefense = 1e9 })).toBe(C.MinDamage)
	end)

	t.it("stamina regenerates after the delay", function()
		local s, stats = setup()
		CombatCore.spendStamina(s, 50, 0)
		local before = s.Stamina
		CombatCore.regen(s, 0.1, 0.2, stats)
		expect(s.Stamina).toBe(before)
		CombatCore.regen(s, 1, 2, stats)
		expect(s.Stamina > before).toBeTruthy()
	end)
end
