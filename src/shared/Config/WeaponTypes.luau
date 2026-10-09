--[[
	WeaponTypes
	Move-set data shared by every weapon of a type. Individual weapons in Items.luau set
	damage, scaling and specials; these numbers define timing, reach and attack shape.

	Melee attacks are resolved server-side as a cone in front of the attacker:
	  Range = reach in studs, Arc = cone angle in degrees.
	Ranged types fire a server-simulated projectile instead.

	Timings (seconds): Windup = delay before the hit resolves, Recovery = lockout after it.
	Motion values multiply the weapon's attack rating per hit of the light combo.
]]

local WeaponTypes = {
	Sword = {
		Range = 7.5, Arc = 110,
		Light = { Windup = 0.16, Recovery = 0.3, Motion = { 1.0, 1.0, 1.2 }, Poise = 12 },
		Heavy = { Windup = 0.42, Recovery = 0.5, Motion = 1.6, Poise = 28 },
		StaminaMult = 1.0, Guard = 0.4, CritBonus = 0,
	},
	Greatsword = {
		Range = 9.5, Arc = 140,
		Light = { Windup = 0.32, Recovery = 0.48, Motion = { 1.0, 1.1 }, Poise = 26 },
		Heavy = { Windup = 0.7, Recovery = 0.7, Motion = 1.75, Poise = 55 },
		StaminaMult = 1.45, Guard = 0.55, CritBonus = 0,
	},
	Axe = {
		Range = 7, Arc = 100,
		Light = { Windup = 0.2, Recovery = 0.34, Motion = { 1.0, 1.05, 1.25 }, Poise = 16 },
		Heavy = { Windup = 0.48, Recovery = 0.55, Motion = 1.7, Poise = 34 },
		StaminaMult = 1.1, Guard = 0.35, CritBonus = 0,
	},
	Hammer = {
		Range = 7.5, Arc = 90,
		Light = { Windup = 0.3, Recovery = 0.46, Motion = { 1.0, 1.15 }, Poise = 32 },
		Heavy = { Windup = 0.65, Recovery = 0.7, Motion = 1.8, Poise = 65 },
		StaminaMult = 1.35, Guard = 0.45, CritBonus = 0,
	},
	Dagger = {
		Range = 5.5, Arc = 80,
		Light = { Windup = 0.1, Recovery = 0.2, Motion = { 0.9, 0.9, 1.0, 1.1 }, Poise = 6 },
		Heavy = { Windup = 0.3, Recovery = 0.38, Motion = 1.4, Poise = 14 },
		StaminaMult = 0.7, Guard = 0.2, CritBonus = 0.5,
	},
	Spear = {
		Range = 11, Arc = 40,
		Light = { Windup = 0.2, Recovery = 0.32, Motion = { 1.0, 1.0, 1.1 }, Poise = 10 },
		Heavy = { Windup = 0.5, Recovery = 0.52, Motion = 1.65, Poise = 30 },
		StaminaMult = 1.0, Guard = 0.4, CritBonus = 0.1,
	},
	Bow = {
		Ranged = true, ProjectileSpeed = 140, ProjectileRadius = 1.2, MaxRange = 160,
		Light = { Windup = 0.28, Recovery = 0.35, Motion = { 1.0 }, Poise = 6 },
		Heavy = { Windup = 0.75, Recovery = 0.5, Motion = 1.9, Poise = 18 },
		StaminaMult = 0.8, Guard = 0.1, CritBonus = 0.2,
	},
	Staff = {
		Ranged = true, Catalyst = true, ProjectileSpeed = 95, ProjectileRadius = 1.8, MaxRange = 120,
		Light = { Windup = 0.32, Recovery = 0.38, Motion = { 1.0 }, Poise = 8, Mana = 6 },
		Heavy = { Windup = 0.8, Recovery = 0.6, Motion = 2.0, Poise = 24, Mana = 16 },
		StaminaMult = 0.6, Guard = 0.15, CritBonus = 0,
	},
	Seal = {
		-- Faith catalyst: short-ranged holy burst instead of a projectile
		Range = 10, Arc = 70, Catalyst = true,
		Light = { Windup = 0.3, Recovery = 0.38, Motion = { 1.0 }, Poise = 12, Mana = 5 },
		Heavy = { Windup = 0.75, Recovery = 0.6, Motion = 1.9, Poise = 30, Mana = 14 },
		StaminaMult = 0.6, Guard = 0.15, CritBonus = 0,
	},
	Fist = {
		Range = 5, Arc = 80,
		Light = { Windup = 0.14, Recovery = 0.26, Motion = { 1.0, 1.0 }, Poise = 5 },
		Heavy = { Windup = 0.4, Recovery = 0.45, Motion = 1.5, Poise = 15 },
		StaminaMult = 0.7, Guard = 0.1, CritBonus = 0,
	},
}

return WeaponTypes
