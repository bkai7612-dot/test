-- Double jump and aerial front/back flips.
local SSS = game:GetService("ServerScriptService")
local Shared = game:GetService("ReplicatedStorage").Shared
local Movement = require(Shared.Logic.Movement)
local CombatCore = require(SSS.Server.Core.CombatCore)
local Stats = require(Shared.Logic.Stats)
local GameConfig = require(Shared.Config.GameConfig)
local Helpers = require(game:GetService("ServerStorage").Tests.Helpers)
local C = GameConfig.Combat

return function(t)
	local expect = t.expect

	t.it("the first jump is a normal jump; a fresh press in the air double jumps once", function()
		local m = Movement.new()
		expect(Movement.jumpRequest(m, 0)).toBe(nil) -- on the ground: normal jump
		Movement.tookOff(m, 0.02)
		expect(Movement.jumpRequest(m, 0.06)).toBe(nil) -- too soon after take-off
		expect(Movement.jumpRequest(m, 0.4)).toBe("DoubleJump")
		expect(Movement.jumpRequest(m, 0.8)).toBe(nil) -- only one per airtime
		Movement.landed(m)
		expect(Movement.jumpRequest(m, 1.2)).toBe(nil)
		Movement.tookOff(m, 1.2)
		expect(Movement.jumpRequest(m, 1.6)).toBe("DoubleJump") -- reset after landing
	end)

	t.it("holding jump does not trigger a double jump", function()
		local m = Movement.new()
		Movement.jumpRequest(m, 0)
		Movement.tookOff(m, 0)
		local any = false
		for i = 1, 30 do -- held key: requests every frame-ish
			if Movement.jumpRequest(m, i * 0.05) then
				any = true
			end
		end
		expect(any).toBe(false)
	end)

	t.it("double jump then dodge = flip; only one flip per airtime", function()
		local m = Movement.new()
		Movement.tookOff(m, 0)
		expect(Movement.jumpRequest(m, 0.3)).toBe("DoubleJump")
		expect(Movement.dodgePressed(m, 0.4)).toBe("Flip")
		expect(Movement.dodgePressed(m, 0.6)).toBe("Dodge")
		Movement.landed(m)
		expect(Movement.dodgePressed(m, 1)).toBe("Dodge")
	end)

	t.it("a dodge in the air without a double jump stays an air dash", function()
		local m = Movement.new()
		Movement.tookOff(m, 0)
		expect(Movement.dodgePressed(m, 0.3)).toBe("Dodge")
	end)

	t.it("dodge then jump (in time) = flip", function()
		local m = Movement.new()
		expect(Movement.dodgePressed(m, 5)).toBe("Dodge")
		expect(Movement.jumpRequest(m, 5.2)).toBe("Flip")
		local late = Movement.new()
		Movement.dodgePressed(late, 5)
		expect(Movement.jumpRequest(late, 5 + Movement.ChainWindow + 0.1)).toBe(nil)
		expect(Movement.ChainWindow).toBe(C.FlipChainWindow)
	end)

	t.it("flip direction follows movement input", function()
		-- facing -Z
		expect(Movement.flipDirection(0, 0, 0, -1)).toBe("Back") -- no input: backflip
		expect(Movement.flipDirection(0, -1, 0, -1)).toBe("Front")
		expect(Movement.flipDirection(0, 1, 0, -1)).toBe("Back")
		expect(Movement.flipDirection(1, 0, 0, -1)).toBe("Front") -- sideways counts as front
		expect(Movement.flipDirection(0.2, 0.9, 0, -1)).toBe("Back")
	end)

	local function state()
		local s = CombatCore.newPlayerState(Stats.compute(Helpers.profile("Assassin")), -100)
		s.Stamina, s.MaxStamina = 100, 100
		return s
	end

	t.it("a fresh flip costs a dodge and grants dodge i-frames", function()
		local s = state()
		local ok, info = CombatCore.flip(s, 10)
		expect(ok).toBe(true)
		expect(info.Chained).toBe(false)
		expect(s.Stamina).toBeNear(100 - C.DodgeCost)
		expect(CombatCore.dodgeCovers(s, 10.1)).toBe(true)
		expect(CombatCore.dodgeCovers(s, 10 + C.DodgeIFrames + 0.05)).toBe(false)
	end)

	t.it("dodge then flip chains for a small cost, once", function()
		local s = state()
		expect((CombatCore.dodge(s, 20))).toBe(true)
		local ok, info = CombatCore.flip(s, 20.2)
		expect(ok).toBe(true)
		expect(info.Chained).toBe(true)
		expect(s.Stamina).toBeNear(100 - C.DodgeCost - C.FlipChainCost)
		-- i-frames refreshed from the flip
		expect(CombatCore.dodgeCovers(s, 20.2 + C.DodgeIFrames - 0.02)).toBe(true)
		-- a second flip straight after is not a chain and hits the dodge cooldown
		local ok2, why = CombatCore.flip(s, 20.3)
		expect(ok2).toBe(false)
		expect(why).toBe("Cooldown")
	end)

	t.it("flips respect stamina, staggers and attack windups", function()
		local s = state()
		s.Stamina = 0
		expect((CombatCore.flip(s, 30))).toBe(false)
		local s2 = state()
		s2.StaggeredUntil = 40
		expect((CombatCore.flip(s2, 39))).toBe(false)
		local s3 = state()
		CombatCore.attack(s3, "Heavy", "Greatsword", 50)
		expect((CombatCore.flip(s3, 50.1))).toBe(false) -- cannot flip out of a windup
	end)
end
