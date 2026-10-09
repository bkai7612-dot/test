--[[
	Formulas
	Pure, documented gameplay maths shared by server (authoritative) and client (previews).
	No Roblox services are used here so the module runs in the offline test harness.

	Key formulas:
	  softCap(v, curve)       = curve.Base + Σ segment gains (diminishing returns per segment)
	  xpToNext(L)             = floor(XpBase * L^XpExponent + XpLinear * L)
	  maxHealth               = softCap(Vigor, Health) (+ bonuses)
	  weapon attack rating    = D*R*(1 + u*Up) + Σ D*R*G(grade)*S(attr)*(1 + u*UpScale)
	                            (×0.6 and no scaling when requirements are unmet)
	  absorption              = min(Max, def / (def + K))
	  bossHealth(f)           = 1100 * 1.14^(f-1)
	  bossDamage(f)           = 120 * (1 + 0.16 * (f-1))
	  bossTiming(f)           = windup ×max(0.7, 1.08 - 0.02(f-1)), recovery ×max(0.6, 1.1 - 0.03(f-1))
	  partyHealthMult(n)      = 1 + BossHealthPerExtraPlayer * (n-1)
]]

local Config = script.Parent.Parent.Config
local GameConfig = require(Config.GameConfig)
local Rarities = require(Config.Rarities)
local Upgrades = require(Config.Upgrades)

local Formulas = {}

function Formulas.softCap(value: number, curve): number
	local total = curve.Base or 0
	local prev = 0
	for _, seg in curve.Segments do
		local cap, gain = seg[1], seg[2]
		if value <= prev then
			break
		end
		local span = math.min(value, cap) - prev
		if span > 0 then
			total += span * gain
		end
		prev = cap
	end
	return total
end

function Formulas.clamp(v: number, lo: number, hi: number): number
	if v < lo then
		return lo
	elseif v > hi then
		return hi
	end
	return v
end

-- ================================================================ Levels
function Formulas.xpToNext(level: number): number
	local c = GameConfig.Level
	if level >= c.Max then
		return math.huge
	end
	return math.floor(c.XpBase * level ^ c.XpExponent + c.XpLinear * level)
end

function Formulas.totalXpForLevel(level: number): number
	local total = 0
	for l = 1, level - 1 do
		total += Formulas.xpToNext(l)
	end
	return total
end

-- ================================================================ Resources
function Formulas.maxHealth(attrs, bonus: number?): number
	return math.floor(Formulas.softCap(attrs.Vigor or 1, GameConfig.Curves.Health) + (bonus or 0))
end

function Formulas.maxStamina(attrs): number
	return math.floor(Formulas.softCap(attrs.Endurance or 1, GameConfig.Curves.Stamina))
end

function Formulas.maxMana(attrs, bonus: number?): number
	local int, fai = attrs.Intelligence or 1, attrs.Faith or 1
	local curve = GameConfig.Curves.Mana
	local hi = Formulas.softCap(math.max(int, fai), curve)
	local lo = Formulas.softCap(math.min(int, fai), curve) - curve.Base
	return math.floor(hi + 0.3 * lo + (bonus or 0))
end

function Formulas.maxEquipLoad(attrs): number
	return Formulas.softCap(attrs.Endurance or 1, GameConfig.Curves.EquipLoad)
end

function Formulas.loadTier(load: number, maxLoad: number)
	local ratio = if maxLoad > 0 then load / maxLoad else math.huge
	for _, tier in GameConfig.EquipLoad.Tiers do
		if ratio <= tier.MaxRatio then
			return tier, ratio
		end
	end
	local tiers = GameConfig.EquipLoad.Tiers
	return tiers[#tiers], ratio
end

-- ================================================================ Damage
function Formulas.scalingBonus(attrValue: number): number
	return Formulas.softCap(attrValue or 0, GameConfig.Curves.ScalingBonus)
end

function Formulas.statusBonus(arcane: number): number
	return Formulas.softCap(arcane or 0, GameConfig.Curves.StatusBonus)
end

function Formulas.requirementsMet(def, attrs): boolean
	for attr, req in def.Requires or {} do
		if (attrs[attr] or 0) < req then
			return false
		end
	end
	return true
end

-- Returns { Total, Base, Scaling, RequirementsMet }
function Formulas.weaponAttackRating(def, upgradeLevel: number?, attrs)
	if not def or def.Kind ~= "Weapon" then
		-- Unarmed
		local str = attrs and attrs.Strength or 10
		local total = 14 + 14 * Formulas.scalingBonus(str)
		return { Total = total, Base = 14, Scaling = total - 14, RequirementsMet = true }
	end
	local path = Upgrades[def.Upgrade] or Upgrades.Standard
	local up = Formulas.clamp(math.floor(upgradeLevel or 0), 0, path.Max)
	local rarity = Rarities[def.Rarity] or Rarities.Common
	local raw = def.Damage * rarity.Power
	local base = raw * (1 + path.DamagePerLevel * up)
	local scaling = 0
	for attr, grade in def.Scaling or {} do
		local coef = GameConfig.ScalingGrades[grade] or 0
		scaling += raw * coef * Formulas.scalingBonus(attrs[attr] or 0) * (1 + path.ScalingPerLevel * up)
	end
	local met = Formulas.requirementsMet(def, attrs)
	if not met then
		return { Total = base * 0.6, Base = base * 0.6, Scaling = 0, RequirementsMet = false }
	end
	return { Total = base + scaling, Base = base, Scaling = scaling, RequirementsMet = true }
end

function Formulas.shieldStability(def, upgradeLevel: number?): number
	if not def then
		return 0
	end
	local path = Upgrades[def.Upgrade] or Upgrades.Standard
	local up = Formulas.clamp(math.floor(upgradeLevel or 0), 0, path.Max)
	return math.min(100, def.Stability + (path.StabilityPerLevel or 0) * up)
end

function Formulas.armorDefense(def, upgradeLevel: number?)
	local up = Formulas.clamp(math.floor(upgradeLevel or 0), 0, Upgrades.Armor.Max)
	local mult = 1 + Upgrades.Armor.DefensePerLevel * up
	return def.Defense * mult, def.MagicDefense * mult
end

-- Ability base power: grows with character level and the ability's scaling attribute.
function Formulas.abilityPower(def, attrs, level: number): number
	local attr = attrs[def.Scaling or "Strength"] or 10
	return (28 + 1.6 * math.max(1, level)) * (1 + 2.2 * Formulas.scalingBonus(attr)) * (def.Power or 1)
end

function Formulas.healAmount(def, attrs, maxHealth: number, healingBonus: number?): number
	local attr = attrs[def.Scaling or "Faith"] or 10
	return math.floor(maxHealth * (def.Power or 0.2) * (1 + Formulas.scalingBonus(attr)) * (1 + (healingBonus or 0)))
end

function Formulas.absorption(defense: number, k: number): number
	if defense <= 0 then
		return 0
	end
	return math.min(GameConfig.Combat.MaxAbsorption, defense / (defense + k))
end

-- ================================================================ Bosses / scaling
function Formulas.bossHealth(floor: number): number
	return math.floor(1100 * 1.14 ^ (floor - 1))
end

function Formulas.bossDamage(floor: number): number
	return 120 * (1 + 0.16 * (floor - 1))
end

function Formulas.bossTiming(floor: number)
	return {
		Windup = math.max(0.7, 1.08 - 0.02 * (floor - 1)),
		Recovery = math.max(0.6, 1.1 - 0.03 * (floor - 1)),
	}
end

function Formulas.partyHealthMult(participants: number): number
	return 1 + GameConfig.Party.BossHealthPerExtraPlayer * math.max(0, participants - 1)
end

function Formulas.partyPoiseMult(participants: number): number
	return 1 + GameConfig.Party.BossPoisePerExtraPlayer * math.max(0, participants - 1)
end

function Formulas.recommendedLevel(floor: number): number
	return math.floor(5 + 4.5 * (floor - 1))
end

function Formulas.recommendedUpgrade(floor: number): number
	return math.min(10, math.floor(floor / 2))
end

function Formulas.bossXp(floor: number): number
	return math.floor(800 * 1.28 ^ (floor - 1))
end

function Formulas.bossCurrency(floor: number): number
	return math.floor(600 * 1.24 ^ (floor - 1))
end

-- ================================================================ Economy
function Formulas.sellPrice(def): number
	if not def or (def.Value or 0) <= 0 or def.BossWeapon then
		return 0
	end
	local rarity = Rarities[def.Rarity] or Rarities.Common
	return math.max(1, math.floor(def.Value * GameConfig.Shop.SellRatio * rarity.SellMultiplier))
end

function Formulas.upgradePath(def)
	if not def then
		return nil
	end
	if def.Kind == "Armor" then
		return Upgrades.Armor
	elseif def.Kind == "Weapon" or def.Kind == "Shield" then
		return Upgrades[def.Upgrade] or Upgrades.Standard
	end
	return nil
end

-- Cost to go from `currentLevel` to currentLevel + 1, or nil if not upgradable / maxed.
function Formulas.upgradeCost(def, currentLevel: number)
	local path = Formulas.upgradePath(def)
	if not path or currentLevel >= path.Max then
		return nil
	end
	return path.Costs[currentLevel + 1]
end

return Formulas
