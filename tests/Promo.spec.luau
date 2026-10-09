local SSS = game:GetService("ServerScriptService")
local PromoCore = require(SSS.Server.Core.PromoCore)
local PromoCodes = require(SSS.Server.Config.PromoCodes)
local CombatCore = require(SSS.Server.Core.CombatCore)
local Items = require(game:GetService("ReplicatedStorage").Shared.Config.Items)
local Cosmetics = require(game:GetService("ReplicatedStorage").Shared.Config.Cosmetics)
local Stats = require(game:GetService("ReplicatedStorage").Shared.Logic.Stats)
local Formulas = require(game:GetService("ReplicatedStorage").Shared.Logic.Formulas)
local Helpers = require(game:GetService("ServerStorage").Tests.Helpers)

return function(t)
	local expect = t.expect

	t.it("both admin codes are 30 characters, distinct, and limited to 2 uses", function()
		local seen = {}
		local admins = 0
		for _, def in PromoCodes do
			expect(seen[string.upper(def.Code)]).toBeNil()
			seen[string.upper(def.Code)] = true
			if def.Kind == "Admin" then
				admins += 1
				expect(#def.Code).toBe(30)
				expect(def.MaxUses).toBe(2)
			end
		end
		expect(admins).toBe(2)
	end)

	t.it("lookup is case/space-insensitive and rejects junk", function()
		local def = PromoCodes.admin_1
		expect(PromoCore.find(PromoCodes, "  " .. string.lower(def.Code) .. " ")).toBe(def)
		expect(PromoCore.find(PromoCodes, "nope")).toBeNil()
		expect(PromoCore.find(PromoCodes, 123)).toBeNil()
		expect(PromoCore.find(PromoCodes, string.rep("A", 200))).toBeNil()
		expect(PromoCore.find(PromoCodes, "")).toBeNil()
	end)

	t.it("a code works once per character", function()
		local p = Helpers.profile("Warrior")
		local def = PromoCodes.launch
		expect((PromoCore.check(p, def, 0))).toBe(true)
		PromoCore.markRedeemed(p, def)
		local ok, err = PromoCore.check(p, def, 0)
		expect(ok).toBe(false)
		expect(err).toBe("AlreadyRedeemed")
	end)

	t.it("admin grants: second admin code cannot be stacked by the same character", function()
		local p = Helpers.profile("Warrior")
		PromoCore.markRedeemed(p, PromoCodes.admin_1)
		expect(p.Admin.Granted).toBe(true)
		expect((PromoCore.check(p, PromoCodes.admin_2, 0))).toBe(false)
	end)

	t.it("unlock all / all items / max upgrades / all cosmetics", function()
		local p = Helpers.profile("Mage")
		PromoCore.unlockAll(p)
		expect(p.Tower.HighestCleared).toBe(20)
		expect(p.Abilities.Unlocked.sovereign_wrath).toBe(true)
		PromoCore.allItems(p)
		for id, def in Items do
			if string.sub(id, 1, 1) ~= "_" then
				expect(Helpers.owns(p, id)).toBe(true)
			end
		end
		PromoCore.maxUpgrades(p)
		for _, inst in p.Inventory.Items do
			local path = Formulas.upgradePath(Items[inst.Id])
			if path then
				expect(inst.Upgrade).toBe(path.Max)
			end
		end
		PromoCore.allCosmetics(p)
		for id in Cosmetics do
			expect(p.Cosmetics.Owned[id]).toBe(true)
		end
		expect(p.Titles.Administrator).toBe(true)
		-- the result is still a valid profile
		local ProfileSchema = require(SSS.Server.Core.ProfileSchema)
		local _, corrections = ProfileSchema.reconcile(Helpers.snapshot(p))
		expect(#corrections).toBe(0)
	end)

	t.it("never die blocks all damage", function()
		local p = Helpers.profile("Mage")
		local stats = Stats.compute(p)
		local s = CombatCore.newPlayerState(stats, -100)
		s.GodMode = true
		local r = CombatCore.resolveIncoming(s, { Damage = 1e9, DamageType = "Physical", Poise = 999 }, 0, stats, true)
		expect(r.Outcome).toBe("Immune")
		expect(CombatCore.applyDamage(s, 1e9)).toBe(false)
		expect(s.Health).toBe(s.MaxHealth)
	end)
end
