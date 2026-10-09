--[[
	Abilities
	Class abilities and boss-reward abilities. Any character can equip any ability they have
	unlocked (two slots), which enables hybrid builds; classes only decide the starting set.

	Types:
	  Projectile : server-simulated projectile (Speed, Radius, Range)
	  Circle     : area around the caster (Radius)
	  Cone       : area in front of the caster (Range, Arc)
	  Line       : rectangle in front of the caster (Length, Width)
	  Buff       : timed self buff (Buff, Amount, Duration)
	  Heal       : heal caster (+ allies within AllyRadius)
	  ShadowStep : teleport behind a nearby target, next hit is a critical
	Power = damage as a multiple of the scaling attribute's ability power (see Formulas.abilityPower).
]]

local Abilities = {
	-- Warrior
	war_cry = { Name = "War Cry", Type = "Buff", Buff = "Damage", Amount = 0.2, Poise = 30, Duration = 12, Cooldown = 30, Stamina = 20, Mana = 0,
		Description = "+20% damage and +30 poise for 12 seconds." },
	whirlwind = { Name = "Whirlwind", Type = "Circle", Radius = 9, Power = 1.5, Scaling = "Strength", Windup = 0.35, Cooldown = 10, Stamina = 35, Mana = 0, Poise = 40,
		UnlockLevel = 10, Description = "Spin with your weapon, striking all around you." },
	-- Knight
	bulwark = { Name = "Bulwark", Type = "Buff", Buff = "Defense", Amount = 0.4, Duration = 8, Cooldown = 25, Stamina = 15, Mana = 0,
		Description = "Take 40% less damage for 8 seconds." },
	shield_bash = { Name = "Shield Bash", Type = "Cone", Range = 7, Arc = 80, Power = 0.9, Scaling = "Strength", Windup = 0.2, Cooldown = 8, Stamina = 22, Mana = 0, Poise = 90,
		UnlockLevel = 10, Description = "A heavy bash that breaks poise." },
	-- Mage
	firebolt = { Name = "Firebolt", Type = "Projectile", DamageType = "Fire", Speed = 110, Radius = 2, Range = 120, Power = 1.3, Scaling = "Intelligence", Windup = 0.25,
		Cooldown = 1.4, Stamina = 6, Mana = 12, Poise = 14, Status = { Burn = 30 }, Description = "Hurl a bolt of fire." },
	glacial_ring = { Name = "Glacial Ring", Type = "Circle", DamageType = "Magic", Radius = 12, Power = 1.6, Scaling = "Intelligence", Windup = 0.45, Cooldown = 12,
		Stamina = 10, Mana = 30, Poise = 20, Slow = { Amount = 0.4, Duration = 4 }, UnlockLevel = 10, Description = "A ring of frost that damages and slows." },
	-- Wizard
	arcane_nova = { Name = "Arcane Nova", Type = "Circle", DamageType = "Magic", Radius = 14, Power = 2.2, Scaling = "Intelligence", Windup = 0.7, Cooldown = 10,
		Stamina = 10, Mana = 35, Poise = 40, Description = "A delayed burst of pure force around you." },
	rift_lance = { Name = "Rift Lance", Type = "Line", DamageType = "Magic", Length = 40, Width = 5, Power = 1.9, Scaling = "Intelligence", Windup = 0.5,
		Cooldown = 6, Stamina = 8, Mana = 25, Poise = 25, UnlockLevel = 10, Description = "A piercing lance that strikes everything in a line." },
	-- Assassin
	shadow_step = { Name = "Shadow Step", Type = "ShadowStep", Range = 26, Cooldown = 8, Stamina = 25, Mana = 0, CritDuration = 2.5,
		Description = "Step behind your target. Your next hit within 2.5 seconds is critical." },
	venom_edge = { Name = "Venom Edge", Type = "Buff", Buff = "Poison", Amount = 35, Duration = 20, Cooldown = 30, Stamina = 10, Mana = 0,
		UnlockLevel = 10, Description = "Coat your blade: hits add poison build-up for 20 seconds." },
	-- Paladin
	sacred_mend = { Name = "Sacred Mend", Type = "Heal", Power = 0.22, Scaling = "Faith", AllyRadius = 18, AllyFraction = 0.5, Windup = 0.6, Cooldown = 18,
		Stamina = 0, Mana = 30, Description = "Heal yourself and half as much to nearby allies." },
	radiant_smite = { Name = "Radiant Smite", Type = "Cone", DamageType = "Holy", Range = 11, Arc = 70, Power = 1.6, Scaling = "Faith", Windup = 0.4, Cooldown = 8,
		Stamina = 10, Mana = 20, Poise = 35, UnlockLevel = 10, Description = "A wave of holy light in front of you." },
	-- Boss rewards (any build)
	ash_wave = { Name = "Ash Wave", Type = "Line", DamageType = "Fire", Length = 26, Width = 6, Power = 1.5, Scaling = "Strength", Windup = 0.45, Cooldown = 9,
		Stamina = 20, Mana = 10, Poise = 30, Description = "Send a wave of cinders along the ground." },
	thorn_snare = { Name = "Thorn Snare", Type = "Circle", Radius = 10, Power = 1.0, Scaling = "Arcane", Windup = 0.4, Cooldown = 14, Stamina = 10, Mana = 20,
		Status = { Poison = 50 }, Slow = { Amount = 0.5, Duration = 3 }, Description = "Roots burst from the ground, poisoning and slowing foes." },
	ember_dash = { Name = "Ember Dash", Type = "Line", DamageType = "Fire", Length = 18, Width = 5, Power = 1.2, Scaling = "Dexterity", Windup = 0.15, Cooldown = 7,
		Stamina = 25, Mana = 0, Poise = 20, Dash = true, Description = "Dash forward in a trail of fire." },
	oracle_tide = { Name = "Oracle's Tide", Type = "Heal", Power = 0.3, Scaling = "Faith", AllyRadius = 25, AllyFraction = 0.75, Windup = 0.8, Cooldown = 30,
		Stamina = 0, Mana = 45, Description = "A tide of restoration for you and your allies." },
	eclipse_burst = { Name = "Eclipse Burst", Type = "Circle", DamageType = "Magic", Radius = 16, Power = 2.6, Scaling = "Intelligence", Windup = 0.9, Cooldown = 18,
		Stamina = 10, Mana = 50, Poise = 60, Description = "Darkness collapses around you, then explodes." },
	sovereign_wrath = { Name = "Sovereign's Wrath", Type = "Cone", Range = 16, Arc = 120, Power = 3.0, Scaling = "Strength", Windup = 0.8, Cooldown = 25,
		Stamina = 30, Mana = 30, Poise = 80, Description = "The final ruler's judgement, in your hands." },
}

for id, def in Abilities do
	def.Id = id
	def.DamageType = def.DamageType or "Physical"
	def.UnlockLevel = def.UnlockLevel or 1
end

return Abilities
