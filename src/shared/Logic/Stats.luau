--[[
	Stats
	Derives a character's combat statistics from its saved profile:
	attributes (+ capped training bonus), equipped items and upgrade levels.
	Used authoritatively by the server and for previews/tooltips on the client.
]]

local Config = script.Parent.Parent.Config
local GameConfig = require(Config.GameConfig)
local Items = require(Config.Items)
local WeaponTypes = require(Config.WeaponTypes)
local Formulas = require(script.Parent.Formulas)

local Stats = {}

Stats.EquipSlots = { "Weapon", "Offhand", "Head", "Chest", "Hands", "Feet", "Accessory1", "Accessory2" }
Stats.ArmorSlots = { "Head", "Chest", "Hands", "Feet" }

-- Effective attributes = base + training bonus (bonus capped per attribute).
function Stats.effectiveAttributes(profile)
	local out = {}
	local cap = GameConfig.Training.MaxTrainingBonusPerAttribute
	for _, name in GameConfig.Attributes.List do
		local base = (profile.Attributes and profile.Attributes[name]) or GameConfig.Attributes.Min
		local bonus = math.min(cap, (profile.TrainingBonus and profile.TrainingBonus[name]) or 0)
		out[name] = math.min(GameConfig.Attributes.Max + cap, base + bonus)
	end
	return out
end

-- Returns (itemDef, itemInstance) for an equipped slot, or nil.
function Stats.equipped(profile, slot: string)
	local uid = profile.Equipped and profile.Equipped[slot]
	if not uid then
		return nil, nil
	end
	local inst = profile.Inventory and profile.Inventory.Items[uid]
	if not inst then
		return nil, nil
	end
	return Items[inst.Id], inst
end

function Stats.compute(profile)
	local attrs = Stats.effectiveAttributes(profile)
	local bonuses = {
		MaxHealth = 0, MaxMana = 0, Poise = 0, StaminaRegen = 0, PhysicalDamage = 0, MagicDamage = 0,
		FireDamage = 0, HolyDamage = 0, CritDamage = 0, StatusBuildup = 0, HealingPower = 0,
	}
	local defense, magicDefense, poise, load = 0, 0, 0, 0

	for _, slot in Stats.EquipSlots do
		local def, inst = Stats.equipped(profile, slot)
		if def then
			load += def.Weight or 0
			if def.Kind == "Armor" then
				local d, m = Formulas.armorDefense(def, inst.Upgrade)
				defense += d
				magicDefense += m
				poise += def.Poise or 0
			elseif def.Kind == "Accessory" then
				for k, v in def.Bonuses or {} do
					bonuses[k] = (bonuses[k] or 0) + v
				end
			end
		end
	end
	poise += bonuses.Poise

	local weaponDef, weaponInst = Stats.equipped(profile, "Weapon")
	local offDef, offInst = Stats.equipped(profile, "Offhand")
	local ar = Formulas.weaponAttackRating(weaponDef, weaponInst and weaponInst.Upgrade or 0, attrs)
	local wtype = WeaponTypes[weaponDef and weaponDef.WeaponType or "Fist"] or WeaponTypes.Fist

	local maxLoad = Formulas.maxEquipLoad(attrs)
	local tier, ratio = Formulas.loadTier(load, maxLoad)

	local stability
	local parryBonus = 0
	if offDef and offDef.Kind == "Shield" then
		stability = Formulas.shieldStability(offDef, offInst.Upgrade)
		parryBonus = offDef.ParryBonus or 0
	else
		stability = math.floor((wtype.Guard or 0.2) * 100)
	end

	return {
		Attributes = attrs,
		MaxHealth = Formulas.maxHealth(attrs, bonuses.MaxHealth),
		MaxStamina = Formulas.maxStamina(attrs),
		MaxMana = Formulas.maxMana(attrs, bonuses.MaxMana),
		Defense = defense,
		MagicDefense = magicDefense,
		Poise = poise,
		EquipLoad = load,
		MaxEquipLoad = maxLoad,
		LoadRatio = ratio,
		LoadTier = tier.Name,
		DodgeCostMult = tier.DodgeCost,
		SpeedMult = tier.Speed,
		WeaponId = weaponDef and weaponDef.Id or nil,
		WeaponType = weaponDef and weaponDef.WeaponType or "Fist",
		WeaponDamageType = weaponDef and weaponDef.DamageType or "Physical",
		WeaponStatus = weaponDef and weaponDef.Status or nil,
		AttackRating = ar.Total,
		RequirementsMet = ar.RequirementsMet,
		Stability = stability,
		ParryBonus = parryBonus,
		HasShield = offDef ~= nil and offDef.Kind == "Shield",
		Bonuses = bonuses,
		StaminaRegen = GameConfig.Stamina.RegenPerSecond * (1 + bonuses.StaminaRegen),
	}
end

return Stats
