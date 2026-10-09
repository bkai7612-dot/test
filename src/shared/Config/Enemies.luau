--[[
	Enemies
	Wildlands enemies, elites, mini-bosses and boss summons.
	Tier: Low (new players), Mid, High, Elite, MiniBoss, Summon.

	Model.Style picks a procedural silhouette (see server Services/EntityModels.luau).
	Damage is the base damage that attack multipliers apply to.
]]

local Attacks = require(script.Parent.Attacks)

local Enemies = {}

local function enemy(id, def)
	def.Id = id
	def.Poise = def.Poise or 40
	def.Defense = def.Defense or 20
	def.WalkSpeed = def.WalkSpeed or 12
	def.AggroRadius = def.AggroRadius or 45
	def.Leash = def.Leash or 85
	def.RespawnTime = def.RespawnTime or 60
	Enemies[id] = def
end

-- ============================================================ Low tier
enemy("hollow_thrall", {
	Name = "Hollow Thrall", Tier = "Low", Level = 1, Health = 140, Damage = 34, Poise = 25, Defense = 10,
	WalkSpeed = 10, Xp = 30, Currency = { 12, 22 }, Loot = "thrall",
	Model = { Style = "Humanoid", Scale = 1, Color = Color3.fromRGB(110, 104, 92), Weapon = "Club" },
	Attacks = {
		Attacks.Cone({ Name = "Club Swing", Windup = 0.9, Recovery = 1.0, Damage = 1, Range = 7, Arc = 90, Parryable = true }),
		Attacks.Circle({ Name = "Lunging Smash", Windup = 1.1, Recovery = 1.2, Damage = 1.3, Radius = 4, Offset = 5, MaxRange = 9, Parryable = true }),
	},
})
enemy("rotwood_wolf", {
	Name = "Rotwood Wolf", Tier = "Low", Level = 3, Health = 120, Damage = 30, Poise = 15, Defense = 6,
	WalkSpeed = 17, Xp = 40, Currency = { 14, 26 }, Loot = "beast", AggroRadius = 55,
	Model = { Style = "Beast", Scale = 0.8, Color = Color3.fromRGB(70, 60, 50) },
	Attacks = {
		Attacks.Cone({ Name = "Bite", Windup = 0.7, Recovery = 0.9, Damage = 1, Range = 6, Arc = 70, Parryable = true }),
		Attacks.Dash({ Name = "Pounce", Windup = 0.9, Recovery = 1.3, Damage = 1.2, Length = 18, Width = 5, MinRange = 8 }),
	},
})
enemy("bog_crawler", {
	Name = "Bog Crawler", Tier = "Low", Level = 4, Health = 160, Damage = 28, Poise = 20, Defense = 12,
	WalkSpeed = 9, Xp = 45, Currency = { 16, 28 }, Loot = "swamp",
	Model = { Style = "Crawler", Scale = 1, Color = Color3.fromRGB(60, 78, 52) },
	Attacks = {
		Attacks.Cone({ Name = "Pincer", Windup = 0.8, Recovery = 1.0, Damage = 1, Range = 6, Arc = 80, Parryable = true }),
		Attacks.Hazard({ Name = "Bile Spit", Windup = 1.2, Recovery = 1.4, Damage = 0.6, Radius = 5, Duration = 5, TickDamage = 0.15, Status = { Poison = 35 }, MinRange = 6, MaxRange = 30 }),
	},
})

-- ============================================================ Mid tier
enemy("ruin_bandit", {
	Name = "Ruin Bandit", Tier = "Mid", Level = 10, Health = 380, Damage = 60, Poise = 40, Defense = 28,
	WalkSpeed = 13, Xp = 140, Currency = { 45, 80 }, Loot = "bandit",
	Model = { Style = "Humanoid", Scale = 1, Color = Color3.fromRGB(96, 66, 50), Weapon = "Sword" },
	Attacks = {
		Attacks.Combo("Bandit Flurry", {
			Attacks.Cone({ Windup = 0.75, Recovery = 0.25, Damage = 0.8, Range = 7, Arc = 100, Parryable = true }),
			Attacks.Cone({ Windup = 0.55, Recovery = 1.0, Damage = 1.0, Range = 7, Arc = 100, Parryable = true }),
		}),
		Attacks.Dash({ Name = "Rushing Stab", Windup = 0.9, Recovery = 1.2, Damage = 1.2, Length = 16, Width = 4, Parryable = true }),
	},
})
enemy("grave_shade", {
	Name = "Grave Shade", Tier = "Mid", Level = 14, Health = 300, Damage = 58, Poise = 30, Defense = 18,
	WalkSpeed = 12, Xp = 170, Currency = { 50, 90 }, Loot = "grave",
	Model = { Style = "Caster", Scale = 1.05, Color = Color3.fromRGB(80, 100, 120), Glow = Color3.fromRGB(140, 200, 255) },
	Attacks = {
		Attacks.Projectile({ Name = "Soul Bolt", Windup = 0.9, Recovery = 1.0, Damage = 1, Speed = 50, Radius = 1.8, MinRange = 6, MaxRange = 55, Blockable = true }),
		Attacks.Teleport({ Name = "Fade", Windup = 0.8, Recovery = 0.6, Distance = 12, Cooldown = 8, MaxRange = 12 }),
	},
})
enemy("pyre_cultist", {
	Name = "Pyre Cultist", Tier = "Mid", Level = 12, Health = 280, Damage = 55, Poise = 25, Defense = 16,
	WalkSpeed = 11, Xp = 150, Currency = { 45, 85 }, Loot = "cultist",
	Model = { Style = "Caster", Scale = 1, Color = Color3.fromRGB(110, 40, 30), Glow = Color3.fromRGB(255, 120, 40) },
	Attacks = {
		Attacks.Projectile({ Name = "Firebrand", DamageType = "Fire", Windup = 1.0, Recovery = 1.1, Damage = 1, Speed = 55, Status = { Burn = 30 }, MaxRange = 60 }),
		Attacks.Hazard({ Name = "Pyre", DamageType = "Fire", Windup = 1.4, Recovery = 1.2, Damage = 0.8, Radius = 6, Duration = 4, TickDamage = 0.2, MaxRange = 45 }),
	},
})
enemy("bone_archer", {
	Name = "Bone Archer", Tier = "Mid", Level = 16, Health = 260, Damage = 62, Poise = 20, Defense = 14,
	WalkSpeed = 12, Xp = 175, Currency = { 55, 95 }, Loot = "grave", AggroRadius = 70,
	Model = { Style = "Humanoid", Scale = 0.95, Color = Color3.fromRGB(200, 196, 180), Weapon = "Bow" },
	Attacks = {
		Attacks.Projectile({ Name = "Bone Arrow", Windup = 1.0, Recovery = 0.9, Damage = 1, Speed = 95, Radius = 1.2, MinRange = 10, MaxRange = 80 }),
		Attacks.Cone({ Name = "Bow Bash", Windup = 0.8, Recovery = 1.0, Damage = 0.7, Range = 6, Arc = 90, Parryable = true, MaxRange = 6 }),
	},
})
enemy("cave_ghoul", {
	Name = "Cave Ghoul", Tier = "Mid", Level = 18, Health = 420, Damage = 66, Poise = 35, Defense = 22,
	WalkSpeed = 15, Xp = 210, Currency = { 60, 110 }, Loot = "cave",
	Model = { Style = "Crawler", Scale = 1.15, Color = Color3.fromRGB(150, 150, 140) },
	Attacks = {
		Attacks.Combo("Rending Claws", {
			Attacks.Cone({ Windup = 0.65, Recovery = 0.2, Damage = 0.7, Range = 6, Arc = 100, Parryable = true, Status = { Bleed = 25 } }),
			Attacks.Cone({ Windup = 0.45, Recovery = 0.2, Damage = 0.7, Range = 6, Arc = 100, Parryable = true, Status = { Bleed = 25 } }),
			Attacks.Cone({ Windup = 0.6, Recovery = 1.2, Damage = 1.0, Range = 7, Arc = 100, Parryable = true, Status = { Bleed = 25 } }),
		}),
		Attacks.Leap({ Name = "Ambush Leap", Windup = 1.0, Recovery = 1.2, Damage = 1.2, Radius = 6 }),
	},
})
enemy("mist_stalker", {
	Name = "Mist Stalker", Tier = "High", Level = 24, Health = 560, Damage = 82, Poise = 40, Defense = 26,
	WalkSpeed = 16, Xp = 320, Currency = { 90, 150 }, Loot = "forest_high",
	Model = { Style = "Beast", Scale = 1.1, Color = Color3.fromRGB(150, 160, 170), Glow = Color3.fromRGB(200, 220, 255) },
	Attacks = {
		Attacks.Dash({ Name = "Mist Lunge", Windup = 0.8, Recovery = 1.2, Damage = 1.2, Length = 24 }),
		Attacks.Cone({ Name = "Rake", Windup = 0.65, Recovery = 0.9, Damage = 1, Range = 7, Arc = 120, Parryable = true }),
		Attacks.Teleport({ Name = "Vanish", Windup = 0.7, Recovery = 0.5, Cooldown = 10, Distance = 10, MaxRange = 30 }),
	},
})

-- ============================================================ Elites
enemy("iron_sentinel", {
	Name = "Iron Sentinel", Tier = "Elite", Level = 20, Health = 1300, Damage = 90, Poise = 120, Defense = 60,
	WalkSpeed = 9, Xp = 650, Currency = { 220, 340 }, Loot = "elite", RespawnTime = 240,
	Model = { Style = "Brute", Scale = 1.5, Color = Color3.fromRGB(90, 92, 100), Weapon = "Hammer" },
	Attacks = {
		Attacks.Circle({ Name = "Ground Pound", Windup = 1.3, Recovery = 1.6, Damage = 1.3, Radius = 9, Offset = 3, Blockable = true }),
		Attacks.Cone({ Name = "Sweeping Blow", Windup = 1.0, Recovery = 1.3, Damage = 1, Range = 11, Arc = 150, Parryable = true }),
	},
})
enemy("fortress_knight", {
	Name = "Fortress Knight", Tier = "Elite", Level = 30, Health = 1800, Damage = 110, Poise = 100, Defense = 70,
	WalkSpeed = 12, Xp = 950, Currency = { 300, 480 }, Loot = "elite", RespawnTime = 240,
	Model = { Style = "Humanoid", Scale = 1.3, Color = Color3.fromRGB(70, 70, 80), Weapon = "Greatsword" },
	Attacks = {
		Attacks.Combo("Knight's Pressure", {
			Attacks.Cone({ Windup = 0.8, Recovery = 0.2, Damage = 0.9, Range = 9, Arc = 120, Parryable = true }),
			Attacks.Cone({ Windup = 0.6, Recovery = 0.2, Damage = 0.9, Range = 9, Arc = 120, Parryable = true }),
			Attacks.Line({ Windup = 0.8, Recovery = 1.3, Damage = 1.3, Length = 14, Width = 5 }),
		}),
		Attacks.Dash({ Name = "Shield Charge", Windup = 1.0, Recovery = 1.5, Damage = 1.1, Length = 22, Poise = 60 }),
	},
})
enemy("vale_wraith", {
	Name = "Vale Wraith", Tier = "Elite", Level = 45, Health = 2600, Damage = 150, Poise = 80, Defense = 60,
	WalkSpeed = 14, Xp = 1800, Currency = { 600, 900 }, Loot = "vale", RespawnTime = 300,
	Model = { Style = "Caster", Scale = 1.4, Color = Color3.fromRGB(40, 70, 64), Glow = Color3.fromRGB(80, 255, 200) },
	Attacks = {
		Attacks.Projectile({ Name = "Vale Lances", DamageType = "Magic", Windup = 1.0, Recovery = 1.0, Damage = 0.7, Count = 3, Spread = 25, Speed = 65 }),
		Attacks.Ring({ Name = "Spirit Ring", DamageType = "Magic", Windup = 1.2, Recovery = 1.2, Damage = 1.2, Inner = 6, Outer = 16, MaxRange = 18 }),
		Attacks.Teleport({ Name = "Drift", Windup = 0.8, Recovery = 0.6, Cooldown = 9 }),
	},
})

-- ============================================================ Mini-bosses (world)
enemy("rot_shepherd", {
	Name = "The Rot Shepherd", Tier = "MiniBoss", Level = 12, Health = 2400, Damage = 70, Poise = 140, Defense = 30,
	WalkSpeed = 11, Xp = 1500, Currency = { 800, 1100 }, Loot = "miniboss_forest", RespawnTime = 900, Leash = 60,
	Model = { Style = "Brute", Scale = 1.7, Color = Color3.fromRGB(80, 70, 40), Glow = Color3.fromRGB(150, 220, 60) },
	Attacks = {
		Attacks.Cone({ Name = "Crook Sweep", Windup = 1.0, Recovery = 1.2, Damage = 1.1, Range = 12, Arc = 140, Parryable = true }),
		Attacks.Summon({ Name = "Call the Flock", Windup = 1.4, Recovery = 1.0, Summon = "rotwood_wolf", Count = 2, MaxAlive = 3, Cooldown = 20 }),
		Attacks.Hazard({ Name = "Rot Bloom", Windup = 1.3, Recovery = 1.0, Damage = 0.5, Radius = 7, Duration = 6, TickDamage = 0.12, Status = { Poison = 40 }, Count = 2 }),
	},
})
enemy("captain_varrow", {
	Name = "Captain Varrow of the Broken Gate", Tier = "MiniBoss", Level = 28, Health = 5200, Damage = 115, Poise = 180, Defense = 60,
	WalkSpeed = 13, Xp = 4200, Currency = { 1800, 2400 }, Loot = "miniboss_fortress", RespawnTime = 900, Leash = 60,
	Model = { Style = "Humanoid", Scale = 1.6, Color = Color3.fromRGB(110, 40, 40), Weapon = "Spear" },
	Attacks = {
		Attacks.Combo("Gatebreaker Thrusts", {
			Attacks.Line({ Windup = 0.8, Recovery = 0.2, Damage = 0.8, Length = 14, Width = 4, Parryable = true }),
			Attacks.Line({ Windup = 0.55, Recovery = 0.2, Damage = 0.8, Length = 14, Width = 4, Parryable = true }),
			Attacks.Line({ Windup = 0.75, Recovery = 1.4, Damage = 1.3, Length = 18, Width = 5 }),
		}),
		Attacks.Leap({ Name = "Siege Leap", Windup = 1.1, Recovery = 1.5, Damage = 1.4, Radius = 10 }),
	},
})
enemy("cave_mother", {
	Name = "The Cave Mother", Tier = "MiniBoss", Level = 20, Health = 3600, Damage = 90, Poise = 150, Defense = 40,
	WalkSpeed = 10, Xp = 2600, Currency = { 1200, 1600 }, Loot = "miniboss_cave", RespawnTime = 900, Leash = 50,
	Model = { Style = "Crawler", Scale = 2.2, Color = Color3.fromRGB(120, 115, 105), Glow = Color3.fromRGB(255, 240, 180) },
	Attacks = {
		Attacks.Cone({ Name = "Maw", Windup = 1.0, Recovery = 1.2, Damage = 1.2, Range = 10, Arc = 90, Parryable = true }),
		Attacks.Summon({ Name = "Brood", Windup = 1.5, Recovery = 1.0, Summon = "cave_ghoul", Count = 2, MaxAlive = 2, Cooldown = 25 }),
		Attacks.Ring({ Name = "Tremor", Windup = 1.3, Recovery = 1.3, Damage = 1.1, Inner = 7, Outer = 18 }),
	},
})

-- ============================================================ Boss summons (low rewards, never drop loot)
enemy("thorn_sprout", {
	Name = "Thorn Sprout", Tier = "Summon", Level = 1, Health = 90, Damage = 1, Poise = 10, Defense = 5,
	WalkSpeed = 9, Xp = 0, Currency = { 0, 0 }, Loot = nil, AggroRadius = 200, Leash = 1000,
	Model = { Style = "Crawler", Scale = 0.6, Color = Color3.fromRGB(70, 110, 50) },
	Attacks = { Attacks.Cone({ Name = "Lash", Windup = 0.9, Recovery = 1.0, Damage = 1, Range = 6, Arc = 90, Parryable = true }) },
})
enemy("plague_rat", {
	Name = "Plague Swarm", Tier = "Summon", Level = 1, Health = 70, Damage = 1, Poise = 5, Defense = 0,
	WalkSpeed = 15, Xp = 0, Currency = { 0, 0 }, Loot = nil, AggroRadius = 200, Leash = 1000,
	Model = { Style = "Beast", Scale = 0.45, Color = Color3.fromRGB(80, 90, 40) },
	Attacks = { Attacks.Cone({ Name = "Gnaw", Windup = 0.7, Recovery = 0.9, Damage = 1, Range = 5, Arc = 90, Parryable = true, Status = { Poison = 30 } }) },
})
enemy("hollow_soldier", {
	Name = "Hollow Soldier", Tier = "Summon", Level = 1, Health = 220, Damage = 1, Poise = 20, Defense = 15,
	WalkSpeed = 12, Xp = 0, Currency = { 0, 0 }, Loot = nil, AggroRadius = 200, Leash = 1000,
	Model = { Style = "Humanoid", Scale = 1, Color = Color3.fromRGB(80, 80, 90), Weapon = "Sword" },
	Attacks = { Attacks.Cone({ Name = "Slash", Windup = 0.85, Recovery = 1.0, Damage = 1, Range = 7, Arc = 100, Parryable = true }) },
})
enemy("illusion", {
	Name = "Eclipse Illusion", Tier = "Summon", Level = 1, Health = 1, Damage = 1, Poise = 1, Defense = 0,
	WalkSpeed = 13, Xp = 0, Currency = { 0, 0 }, Loot = nil, AggroRadius = 200, Leash = 1000,
	Model = { Style = "Caster", Scale = 1.6, Color = Color3.fromRGB(30, 20, 46), Glow = Color3.fromRGB(150, 80, 255) },
	Attacks = { Attacks.Projectile({ Name = "False Moon", DamageType = "Magic", Windup = 1.1, Recovery = 1.2, Damage = 1, Speed = 45 }) },
})

return Enemies
