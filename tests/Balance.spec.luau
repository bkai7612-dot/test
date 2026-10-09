--[[
	Balance simulation (Tester). For every class at every floor's recommended level and upgrade,
	estimates time-to-kill on the floor's boss and the share of player HP a boss hit removes.
	Bounds are deliberately wide; they catch broken tuning, not fine balance.
]]
local RS = game:GetService("ReplicatedStorage")
local Formulas = require(RS.Shared.Logic.Formulas)
local Items = require(RS.Shared.Config.Items)
local Bosses = require(RS.Shared.Config.Bosses)
local Classes = require(RS.Shared.Config.Classes)
local WeaponTypes = require(RS.Shared.Config.WeaponTypes)
local GameConfig = require(RS.Shared.Config.GameConfig)

-- Build plans: share of levelled points per attribute.
local Plans = {
	Warrior = { Vigor = 0.32, Endurance = 0.18, Strength = 0.4, Dexterity = 0.1 },
	Knight = { Vigor = 0.35, Endurance = 0.2, Strength = 0.35, Dexterity = 0.1 },
	Mage = { Vigor = 0.3, Endurance = 0.12, Intelligence = 0.5, Dexterity = 0.08 },
	Wizard = { Vigor = 0.3, Endurance = 0.12, Intelligence = 0.5, Faith = 0.08 },
	Assassin = { Vigor = 0.3, Endurance = 0.15, Dexterity = 0.45, Arcane = 0.1 },
	Paladin = { Vigor = 0.32, Endurance = 0.15, Strength = 0.23, Faith = 0.3 },
}
-- Weapon progression: { fromFloorCleared, itemId }
local Weapons = {
	Warrior = { { 0, "warrior_handaxe" }, { 1, "iron_greatsword" }, { 6, "executioner_axe" }, { 10, "siege_breaker" }, { 13, "champion_blade" }, { 18, "general_warblade" } },
	Knight = { { 0, "knight_longsword" }, { 4, "gravebound_blade" }, { 15, "regent_sword" } },
	Mage = { { 0, "apprentice_staff" }, { 2, "lucent_staff" }, { 8, "veiled_staff" }, { 17, "eclipse_staff" } },
	Wizard = { { 0, "apprentice_staff" }, { 2, "lucent_staff" }, { 8, "veiled_staff" }, { 17, "eclipse_staff" } },
	Assassin = { { 0, "shadow_dagger" }, { 2, "serrated_dagger" }, { 5, "ember_fangs" }, { 9, "crimson_rapier" }, { 12, "reaper_scythe" } },
	Paladin = { { 0, "lightbound_mace" }, { 3, "thorn_seal" }, { 11, "oracle_seal" }, { 19, "godbreaker" } },
}

local function buildAttrs(class, level)
	local attrs = table.clone(Classes[class].Attributes)
	local pts = level - 1
	for attr, share in Plans[class] do
		attrs[attr] = math.min(GameConfig.Attributes.Max, attrs[attr] + math.floor(pts * share))
	end
	return attrs
end

local function weaponFor(class, floor)
	local pick = Weapons[class][1][2]
	for _, w in Weapons[class] do
		if floor - 1 >= w[1] then pick = w[2] end
	end
	return Items[pick]
end

local function upgradeFor(def, floor)
	local u = Formulas.recommendedUpgrade(floor)
	if def.Upgrade == "Unique" then
		u = math.min(5, math.floor(u / 2))
	end
	return u
end

local function estimate(class, floor)
	local level = Formulas.recommendedLevel(floor)
	local attrs = buildAttrs(class, level)
	local def = weaponFor(class, floor)
	local ar = Formulas.weaponAttackRating(def, upgradeFor(def, floor), attrs).Total
	local wt = WeaponTypes[def.WeaponType]
	local motions = wt.Light.Motion
	local avg = 0
	for _, m in motions do avg += m end
	avg /= #motions
	local cycle = wt.Light.Windup + wt.Light.Recovery * 0.85
	local uptime = if wt.Ranged then 0.45 else 0.35
	local boss = Bosses.List[floor]
	local absorb = Formulas.absorption(boss.Defense, GameConfig.Combat.EnemyDefenseK)
	local dps = ar * avg / cycle * uptime * (1 - absorb)
	local hp = Formulas.bossHealth(floor) * boss.HealthMult
	if boss.Mechanics.Twin then hp *= boss.Mechanics.Twin.Count end
	local ttk = hp / dps

	-- incoming: player HP vs biggest single hit
	local playerHp = Formulas.maxHealth(attrs)
	local armorDef = 30 + 5.5 * floor -- typical worn armour at that point incl. upgrades
	local maxMult = 0
	for _, phase in boss.Phases do
		local lists = {}
		if phase.Stances then for _, s in phase.Stances do table.insert(lists, s.Attacks) end else lists = { phase.Attacks } end
		for _, list in lists do
			for _, a in list do
				local steps = if a.Shape == "Combo" then a.Steps else { a }
				for _, s in steps do maxMult = math.max(maxMult, s.Damage or 0) end
			end
		end
	end
	local hit = Formulas.bossDamage(floor) * boss.DamageMult * maxMult * (1 - Formulas.absorption(armorDef, GameConfig.Combat.PlayerDefenseK))
	return ttk, hit / playerHp, ar
end

return function(t)
	local expect = t.expect

	t.it("solo time-to-kill stays within 30s..360s (final boss 450s) for every class and floor", function()
		local report = {}
		for floor = 1, 20 do
			local maxTtk = if floor == 20 then 450 else 360
			for _, class in Classes.Order do
				local ttk = estimate(class, floor)
				if ttk < 30 or ttk > maxTtk then
					table.insert(report, ("%s floor %d TTK %.0fs"):format(class, floor, ttk))
				end
			end
		end
		if #report > 0 then error(table.concat(report, "; ")) end
	end)

	t.it("no boss hit removes more than the fairness cap of HP at recommended level", function()
		local report = {}
		for floor = 1, 20 do
			for _, class in Classes.Order do
				local _, frac = estimate(class, floor)
				if frac > Bosses.Fairness.MaxHitFractionOfHealth then
					table.insert(report, ("%s floor %d biggest hit %.0f%%"):format(class, floor, frac * 100))
				end
			end
		end
		if #report > 0 then error(table.concat(report, "; ")) end
	end)

	t.it("bosses remain threatening (biggest hit >= 15% HP)", function()
		for floor = 1, 20 do
			local _, frac = estimate("Knight", floor)
			expect(frac >= 0.15).toBeTruthy()
		end
	end)

	t.it("prints a balance table", function()
		local lines = { "floor | " .. table.concat(Classes.Order, " | ") }
		for floor = 1, 20, 3 do
			local row = { tostring(floor) }
			for _, class in Classes.Order do
				local ttk, frac = estimate(class, floor)
				table.insert(row, ("%3.0fs/%2.0f%%"):format(ttk, frac * 100))
			end
			table.insert(lines, table.concat(row, " | "))
		end
		print("[balance] TTK / biggest-hit-%HP\n" .. table.concat(lines, "\n"))
	end)
end
