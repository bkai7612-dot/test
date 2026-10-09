local SSS = game:GetService("ServerScriptService")
local DeathCore = require(SSS.Server.Core.DeathCore)
local GameConfig = require(game:GetService("ReplicatedStorage").Shared.Config.GameConfig)
local Helpers = require(game:GetService("ServerStorage").Tests.Helpers)

return function(t)
	local expect = t.expect

	t.it("death drops all carried currency into a marker", function()
		local p = Helpers.profile("Warrior")
		p.Currency = 500
		local r = DeathCore.onDeath(p, 10, 0, 10, 1000)
		expect(r.Dropped).toBe(500)
		expect(p.Currency).toBe(0)
		expect(p.LostCurrency.Amount).toBe(500)
	end)

	t.it("recovery is awarded exactly once", function()
		local p = Helpers.profile("Warrior")
		p.Currency = 500
		DeathCore.onDeath(p, 10, 0, 10, 1000)
		local ok, amount = DeathCore.recover(p, 11, 0, 10, 1010)
		expect(ok).toBe(true)
		expect(amount).toBe(500)
		expect(p.Currency).toBe(500)
		local ok2 = DeathCore.recover(p, 11, 0, 10, 1011)
		expect(ok2).toBe(false)
		expect(p.Currency).toBe(500)
	end)

	t.it("recovery requires proximity", function()
		local p = Helpers.profile("Warrior")
		p.Currency = 300
		DeathCore.onDeath(p, 0, 0, 0, 0)
		local ok, err = DeathCore.recover(p, 100, 0, 0, 5)
		expect(ok).toBe(false)
		expect(err).toBe("TooFar")
		expect(p.LostCurrency.Amount).toBe(300)
	end)

	t.it("second death before recovery follows the configured rule", function()
		local p = Helpers.profile("Warrior")
		p.Currency = 400
		DeathCore.onDeath(p, 0, 0, 0, 0)
		p.Currency = 50
		local r = DeathCore.onDeath(p, 50, 0, 50, 10)
		if GameConfig.Death.SecondDeathRule == "LosePrevious" then
			expect(r.LostForever).toBe(400)
			expect(p.LostCurrency.Amount).toBe(50)
		else
			expect(p.LostCurrency.Amount).toBe(450)
		end
		expect(p.LostCurrency.X).toBe(50)
	end)

	t.it("dying with nothing leaves no marker (LosePrevious)", function()
		local p = Helpers.profile("Warrior")
		p.Currency = 0
		DeathCore.onDeath(p, 0, 0, 0, 0)
		expect(p.LostCurrency).toBeNil()
	end)

	t.it("markers expire", function()
		local p = Helpers.profile("Warrior")
		p.Currency = 100
		DeathCore.onDeath(p, 0, 0, 0, 0)
		local ok, err = DeathCore.recover(p, 0, 0, 0, GameConfig.Death.RecoveryExpirySeconds + 1)
		expect(ok).toBe(false)
		expect(err).toBe("Expired")
		expect(p.LostCurrency).toBeNil()
	end)

	t.it("no-loss deaths (PvP/training) keep currency and existing marker", function()
		local p = Helpers.profile("Warrior")
		p.Currency = 100
		DeathCore.onDeath(p, 0, 0, 0, 0)
		p.Currency = 70
		DeathCore.onDeath(p, 5, 0, 5, 1, { NoLoss = true })
		expect(p.Currency).toBe(70)
		expect(p.LostCurrency.Amount).toBe(100)
	end)

	t.it("marker survives a save/load round trip (disconnect)", function()
		local ProfileSchema = require(SSS.Server.Core.ProfileSchema)
		local p = Helpers.profile("Warrior")
		p.Currency = 250
		DeathCore.onDeath(p, 1, 2, 3, 100)
		local loaded = ProfileSchema.reconcile(Helpers.snapshot(p))
		expect(loaded.LostCurrency.Amount).toBe(250)
		expect(loaded.Currency).toBe(0)
	end)
end
