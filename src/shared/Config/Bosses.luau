--[[
	Bosses
	The twenty guardians of the Tower of the Fallen. Each entry defines:
	  Floor, Name, Title, Lore
	  HealthMult / DamageMult / Poise / Defense : multipliers on Formulas.bossHealth/bossDamage
	  Model   : procedural silhouette (Services/EntityModels.luau)
	  Arena   : size + visual theme of the encounter space
	  Phases  : ordered by Threshold (fraction of HP at which the phase begins)
	  Mechanics : distinctive rules handled by the boss framework
	  Rewards : first-clear and replay rewards

	Attack windups/recoveries are authored at "floor 1" speed. The framework multiplies them
	by Formulas.bossTiming(floor), which tightens timings with floor but never below the
	fairness minimums in Bosses.Fairness (validated by tests/BossFairness.spec.luau).
]]

local Attacks = require(script.Parent.Attacks)
local C, Ci, L, R, P = Attacks.Cone, Attacks.Circle, Attacks.Line, Attacks.Ring, Attacks.Projectile
local H, S, T, Lp, D, Pu = Attacks.Hazard, Attacks.Summon, Attacks.Teleport, Attacks.Leap, Attacks.Dash, Attacks.Pulse
local Combo = Attacks.Combo

local Bosses = {}

Bosses.Fairness = {
	MinWindup = 0.42, -- no hostile attack resolves faster than this after its telegraph appears
	MinComboFollowUp = 0.35, -- follow-up steps inside a combo
	MinRecovery = 0.3,
	MaxHitFractionOfHealth = 0.6, -- at recommended level, no single hit takes more than 60% HP
}

local list = {}
local function boss(def)
	def.Id = "boss_" .. def.Floor
	def.HealthMult = def.HealthMult or 1
	def.DamageMult = def.DamageMult or 1
	def.Poise = def.Poise or 150
	def.Defense = def.Defense or 40
	def.WalkSpeed = def.WalkSpeed or 13
	def.Mechanics = def.Mechanics or {}
	list[def.Floor] = def
	Bosses[def.Id] = def
end

-- ===================================================================== 1
boss({
	Floor = 1, Name = "The Ashen Warden", Title = "Keeper of the First Gate",
	Lore = "A gatekeeper who kept his post long after there was nothing left to guard.",
	Mechanic = "Introductory melee: learn to dodge sweeps and punish slow recoveries.",
	Model = { Style = "Humanoid", Scale = 1.9, Color = Color3.fromRGB(110, 104, 98), Glow = Color3.fromRGB(255, 140, 60), Weapon = "Spear" },
	Arena = { Size = 120, Material = "Slate", Color = Color3.fromRGB(70, 66, 62), Fog = Color3.fromRGB(80, 70, 64), Light = Color3.fromRGB(255, 150, 90), Props = "Pillars" },
	Phases = {
		{ Threshold = 1, Attacks = {
			C({ Name = "Halberd Sweep", Windup = 1.1, Recovery = 1.2, Damage = 1, Range = 12, Arc = 140, Parryable = true }),
			L({ Name = "Gate Thrust", Windup = 1.0, Recovery = 1.3, Damage = 1.1, Length = 16, Width = 4, Parryable = true }),
			Combo("Warden's Rhythm", {
				C({ Windup = 1.0, Recovery = 0.3, Damage = 0.9, Range = 11, Arc = 120, Parryable = true }),
				C({ Windup = 0.8, Recovery = 1.4, Damage = 1.0, Range = 11, Arc = 120, Parryable = true }),
			}),
		} },
		{ Threshold = 0.5, Name = "Embers Rekindled", Attacks = {
			C({ Name = "Halberd Sweep", Windup = 1.0, Recovery = 1.1, Damage = 1, Range = 12, Arc = 140, Parryable = true }),
			L({ Name = "Ash Wave", DamageType = "Fire", Windup = 1.2, Recovery = 1.3, Damage = 1.2, Length = 30, Width = 6, Blockable = true }),
			Lp({ Name = "Falling Gate", Windup = 1.2, Recovery = 1.5, Damage = 1.3, Radius = 9 }),
		} },
	},
	Rewards = { FirstClear = { Items = { warden_halberd = 1, ember_shard = 3, flask_shard = 1 }, Ability = "ash_wave", Title = "Gatebreaker" } },
})

-- ===================================================================== 2
boss({
	Floor = 2, Name = "The Hollow Butcher", Title = "Carver of the Lower Halls",
	Lore = "He learned that a delayed blow is the one nobody dodges.",
	Mechanic = "Heavy, deliberately delayed strikes. Do not panic-roll; wait for the swing.",
	HealthMult = 1.1,
	Model = { Style = "Brute", Scale = 2.1, Color = Color3.fromRGB(120, 80, 70), Weapon = "Cleaver" },
	Arena = { Size = 110, Material = "Cobblestone", Color = Color3.fromRGB(70, 50, 46), Fog = Color3.fromRGB(70, 40, 36), Light = Color3.fromRGB(220, 90, 70), Props = "Hooks" },
	Phases = {
		{ Threshold = 1, Attacks = {
			C({ Name = "Delayed Cleave", Windup = 1.6, Recovery = 1.4, Damage = 1.3, Range = 11, Arc = 120, Parryable = true, Delayed = true }),
			Ci({ Name = "Overhead Chop", Windup = 1.4, Recovery = 1.6, Damage = 1.5, Radius = 5, Offset = 7, MaxRange = 12 }),
			Combo("Butcher's Hack", {
				C({ Windup = 1.0, Recovery = 0.3, Damage = 0.8, Range = 10, Arc = 110, Parryable = true, Status = { Bleed = 30 } }),
				C({ Windup = 1.3, Recovery = 1.5, Damage = 1.2, Range = 10, Arc = 110, Parryable = true, Status = { Bleed = 30 } }),
			}),
		} },
		{ Threshold = 0.45, Name = "Frenzy", Attacks = {
			C({ Name = "Delayed Cleave", Windup = 1.5, Recovery = 1.2, Damage = 1.3, Range = 11, Arc = 120, Parryable = true, Delayed = true }),
			D({ Name = "Meat Hook Charge", Windup = 1.1, Recovery = 1.6, Damage = 1.2, Length = 28 }),
			Combo("Butcher's Hack", {
				C({ Windup = 1.0, Recovery = 0.3, Damage = 0.8, Range = 10, Arc = 110, Parryable = true, Status = { Bleed = 30 } }),
				C({ Windup = 0.7, Recovery = 0.3, Damage = 0.8, Range = 10, Arc = 110, Parryable = true, Status = { Bleed = 30 } }),
				Ci({ Windup = 1.4, Recovery = 1.6, Damage = 1.4, Radius = 6, Offset = 6, MaxRange = 12 }),
			}),
		} },
	},
	Rewards = { FirstClear = { Items = { butcher_cleaver = 1, ember_shard = 4 }, Title = "Butcher's Bane" } },
})

-- ===================================================================== 3
boss({
	Floor = 3, Name = "The Thorn Matriarch", Title = "Mother of the Root-Choked Floor",
	Lore = "Her garden grew through the tower's stone, and it is still growing.",
	Mechanic = "Area denial: root hazards cover the floor and sprouts must be culled.",
	Mechanics = { },
	Model = { Style = "Caster", Scale = 2.0, Color = Color3.fromRGB(70, 90, 50), Glow = Color3.fromRGB(170, 230, 90) },
	Arena = { Size = 130, Material = "Grass", Color = Color3.fromRGB(50, 66, 40), Fog = Color3.fromRGB(56, 70, 46), Light = Color3.fromRGB(170, 230, 120), Props = "Roots" },
	Phases = {
		{ Threshold = 1, Attacks = {
			H({ Name = "Root Field", Windup = 1.3, Recovery = 1.0, Damage = 0.6, Radius = 7, Duration = 8, TickDamage = 0.15, Count = 2, Status = { Poison = 25 } }),
			S({ Name = "Sprouting", Windup = 1.4, Recovery = 1.0, Summon = "thorn_sprout", Count = 2, MaxAlive = 4, Cooldown = 18 }),
			L({ Name = "Thorn Lash", Windup = 1.0, Recovery = 1.2, Damage = 1.0, Length = 20, Width = 5, Parryable = true }),
			P({ Name = "Seed Volley", Windup = 1.1, Recovery = 1.1, Damage = 0.6, Count = 3, Spread = 30, Speed = 45 }),
		} },
		{ Threshold = 0.5, Name = "Overgrowth", Attacks = {
			H({ Name = "Root Field", Windup = 1.2, Recovery = 0.9, Damage = 0.6, Radius = 8, Duration = 9, TickDamage = 0.15, Count = 3, Status = { Poison = 25 } }),
			R({ Name = "Bramble Ring", Windup = 1.3, Recovery = 1.2, Damage = 1.2, Inner = 8, Outer = 20 }),
			S({ Name = "Sprouting", Windup = 1.3, Recovery = 1.0, Summon = "thorn_sprout", Count = 3, MaxAlive = 5, Cooldown = 16 }),
			L({ Name = "Thorn Lash", Windup = 0.95, Recovery = 1.1, Damage = 1.0, Length = 22, Width = 5, Parryable = true }),
		} },
	},
	Rewards = { FirstClear = { Items = { thorn_seal = 1, ember_shard = 4, flask_shard = 1 }, Ability = "thorn_snare", Title = "Pruner" } },
})

-- ===================================================================== 4
boss({
	Floor = 4, Name = "The Gravebound Knight", Title = "Last Shield of the Sanctuary",
	Lore = "He swore to block every blow aimed at the tower. He still does.",
	Mechanic = "Defensive: raises a guard that counters careless attacks. Break his poise or strike after his counter.",
	Poise = 220, Defense = 70,
	Mechanics = { Counter = { GuardDamageReduction = 0.85 } },
	Model = { Style = "Humanoid", Scale = 1.8, Color = Color3.fromRGB(96, 100, 110), Glow = Color3.fromRGB(160, 200, 255), Weapon = "Sword", Shield = true },
	Arena = { Size = 120, Material = "Marble", Color = Color3.fromRGB(90, 92, 98), Fog = Color3.fromRGB(70, 74, 86), Light = Color3.fromRGB(170, 190, 255), Props = "Graves" },
	Phases = {
		{ Threshold = 1, Attacks = {
			Attacks.CounterStance({ Name = "Guard Stance", Windup = 1.6, Recovery = 0.6, Damage = 1.3, Range = 10, Arc = 140, Duration = 1.6 }),
			Combo("Oath Strikes", {
				C({ Windup = 1.0, Recovery = 0.3, Damage = 0.9, Range = 10, Arc = 110, Parryable = true }),
				L({ Windup = 0.8, Recovery = 1.3, Damage = 1.1, Length = 14, Width = 4, Parryable = true }),
			}),
			D({ Name = "Shield Rush", Windup = 1.0, Recovery = 1.5, Damage = 1.0, Length = 24, Poise = 60 }),
		} },
		{ Threshold = 0.4, Name = "Unbroken Oath", Attacks = {
			Attacks.CounterStance({ Name = "Guard Stance", Windup = 1.4, Recovery = 0.5, Damage = 1.4, Range = 10, Arc = 140, Duration = 1.4 }),
			Combo("Oath Strikes", {
				C({ Windup = 0.9, Recovery = 0.3, Damage = 0.9, Range = 10, Arc = 110, Parryable = true }),
				C({ Windup = 0.7, Recovery = 0.3, Damage = 0.9, Range = 10, Arc = 110, Parryable = true }),
				L({ Windup = 0.8, Recovery = 1.3, Damage = 1.2, Length = 16, Width = 4 }),
			}),
			R({ Name = "Grave Shockwave", Windup = 1.2, Recovery = 1.2, Damage = 1.1, Inner = 7, Outer = 18 }),
		} },
	},
	Rewards = { FirstClear = { Items = { gravebound_blade = 1, gravebound_aegis = 1, tempered_shard = 2 }, Title = "Oathbreaker" } },
})

-- ===================================================================== 5
boss({
	Floor = 5, Name = "The Ember Hound", Title = "Hunger of the Burning Floor",
	Lore = "A hunting beast left in the furnace too long. It never stopped hunting.",
	Mechanic = "Relentless movement and fire trails. Keep calm, dodge through lunges, avoid burning ground.",
	WalkSpeed = 20, HealthMult = 0.95,
	Model = { Style = "Beast", Scale = 2.4, Color = Color3.fromRGB(60, 30, 20), Glow = Color3.fromRGB(255, 110, 30) },
	Arena = { Size = 140, Material = "Basalt", Color = Color3.fromRGB(40, 30, 28), Fog = Color3.fromRGB(90, 40, 20), Light = Color3.fromRGB(255, 120, 40), Props = "Braziers" },
	Phases = {
		{ Threshold = 1, Attacks = {
			D({ Name = "Burning Lunge", DamageType = "Fire", Windup = 0.9, Recovery = 1.1, Damage = 1.0, Length = 30, Width = 6, Status = { Burn = 35 }, LeaveHazard = true }),
			C({ Name = "Savage Bite", Windup = 0.8, Recovery = 1.0, Damage = 1.0, Range = 9, Arc = 80, Parryable = true }),
			Ci({ Name = "Flame Burst", DamageType = "Fire", Windup = 1.2, Recovery = 1.2, Damage = 1.1, Radius = 10, Status = { Burn = 40 } }),
		} },
		{ Threshold = 0.5, Name = "Blazing", Attacks = {
			Combo("Pack Hunt", {
				D({ DamageType = "Fire", Windup = 0.9, Recovery = 0.4, Damage = 0.9, Length = 30, Width = 6, LeaveHazard = true }),
				D({ DamageType = "Fire", Windup = 0.7, Recovery = 1.3, Damage = 0.9, Length = 30, Width = 6, LeaveHazard = true }),
			}),
			C({ Name = "Savage Bite", Windup = 0.75, Recovery = 0.9, Damage = 1.0, Range = 9, Arc = 80, Parryable = true }),
			P({ Name = "Cinder Spit", DamageType = "Fire", Windup = 1.0, Recovery = 1.0, Damage = 0.7, Count = 3, Spread = 25, Speed = 55 }),
		} },
	},
	Rewards = { FirstClear = { Items = { ember_fangs = 1, ember_heart = 1, tempered_shard = 2, flask_shard = 1 }, Ability = "ember_dash", Title = "Houndtamer" } },
})

-- ===================================================================== 6
boss({
	Floor = 6, Name = "The Twin Executioners", Title = "Judge and Sentence",
	Lore = "One reads the charge. The other carries it out. Neither ever disagreed.",
	Mechanic = "Two bosses with separate health. Killing one enrages the other; manage both.",
	HealthMult = 0.6, -- per twin
	Mechanics = { Twin = { Count = 2, EnrageDamage = 0.25, EnrageSpeed = 0.15 } },
	Model = { Style = "Humanoid", Scale = 1.7, Color = Color3.fromRGB(60, 50, 52), Glow = Color3.fromRGB(200, 40, 40), Weapon = "Axe", Hood = true },
	Arena = { Size = 140, Material = "Slate", Color = Color3.fromRGB(60, 56, 56), Fog = Color3.fromRGB(60, 30, 30), Light = Color3.fromRGB(230, 60, 60), Props = "Gallows" },
	Phases = {
		{ Threshold = 1, Attacks = {
			C({ Name = "Verdict", Windup = 1.1, Recovery = 1.3, Damage = 1.0, Range = 10, Arc = 120, Parryable = true }),
			Ci({ Name = "Execution", Windup = 1.5, Recovery = 1.6, Damage = 1.6, Radius = 5, Offset = 7, MaxRange = 12 }),
			D({ Name = "Pursuit", Windup = 1.1, Recovery = 1.4, Damage = 1.0, Length = 26 }),
		} },
		{ Threshold = 0.4, Name = "Sentence Carried", Attacks = {
			Combo("Double Verdict", {
				C({ Windup = 1.0, Recovery = 0.3, Damage = 0.9, Range = 10, Arc = 120, Parryable = true }),
				C({ Windup = 0.7, Recovery = 1.3, Damage = 1.0, Range = 10, Arc = 120, Parryable = true }),
			}),
			Ci({ Name = "Execution", Windup = 1.4, Recovery = 1.5, Damage = 1.6, Radius = 5, Offset = 7, MaxRange = 12 }),
			Lp({ Name = "Gallows Drop", Windup = 1.2, Recovery = 1.5, Damage = 1.2, Radius = 8 }),
		} },
	},
	Rewards = { FirstClear = { Items = { executioner_axe = 1, tempered_shard = 3, armor_plate = 3 }, Title = "Acquitted" } },
})

-- ===================================================================== 7
boss({
	Floor = 7, Name = "The Mire Colossus", Title = "The Floor That Walks",
	Lore = "The flooded seventh floor rose up one day and decided it was a giant.",
	Mechanic = "Environmental hazards: bog pools spread periodically. Positioning matters more than speed.",
	HealthMult = 1.25, WalkSpeed = 8, Poise = 300, Defense = 60,
	Mechanics = { Ambient = { Interval = 11, Attack = H({ Name = "Rising Bog", Windup = 1.6, Recovery = 0, Damage = 0.4, Radius = 9, Duration = 10, TickDamage = 0.12, Count = 2, Status = { Poison = 20 } }) } },
	Model = { Style = "Colossus", Scale = 3.2, Color = Color3.fromRGB(70, 76, 56), Glow = Color3.fromRGB(150, 200, 90) },
	Arena = { Size = 160, Material = "Mud", Color = Color3.fromRGB(50, 52, 38), Fog = Color3.fromRGB(60, 66, 44), Light = Color3.fromRGB(150, 200, 120), Props = "Pools" },
	Phases = {
		{ Threshold = 1, Attacks = {
			Ci({ Name = "Mire Stomp", Windup = 1.4, Recovery = 1.6, Damage = 1.3, Radius = 12, Offset = 4 }),
			C({ Name = "Mud Sweep", Windup = 1.3, Recovery = 1.5, Damage = 1.1, Range = 18, Arc = 150 }),
			P({ Name = "Sludge Hurl", Windup = 1.3, Recovery = 1.2, Damage = 1.0, Speed = 45, Radius = 3.5, MinRange = 14 }),
		} },
		{ Threshold = 0.5, Name = "Sinking", Attacks = {
			R({ Name = "Collapse", Windup = 1.5, Recovery = 1.6, Damage = 1.4, Inner = 10, Outer = 26 }),
			Ci({ Name = "Mire Stomp", Windup = 1.3, Recovery = 1.5, Damage = 1.3, Radius = 13, Offset = 4 }),
			H({ Name = "Swamp Gas", Windup = 1.4, Recovery = 1.0, Damage = 0.5, Radius = 10, Duration = 8, TickDamage = 0.14, Count = 3, Status = { Poison = 30 } }),
		} },
	},
	Rewards = { FirstClear = { Items = { colossus_maul = 1, tempered_shard = 3, flask_shard = 1 }, Title = "Mirewalker" } },
})

-- ===================================================================== 8
boss({
	Floor = 8, Name = "The Veiled Arcanist", Title = "Keeper of the Sealed Library",
	Lore = "She read every book in the tower, then started on the ones that were never written.",
	Mechanic = "Teleports and fills the air with magic projectiles; close distance during her recovery.",
	HealthMult = 0.9,
	Mechanics = { },
	Model = { Style = "Caster", Scale = 1.9, Color = Color3.fromRGB(40, 40, 70), Glow = Color3.fromRGB(110, 140, 255), Hood = true },
	Arena = { Size = 140, Material = "Marble", Color = Color3.fromRGB(46, 46, 70), Fog = Color3.fromRGB(40, 40, 80), Light = Color3.fromRGB(120, 140, 255), Props = "Shelves" },
	Phases = {
		{ Threshold = 1, Attacks = {
			P({ Name = "Arcane Missiles", DamageType = "Magic", Windup = 1.0, Recovery = 1.0, Damage = 0.6, Count = 4, Spread = 40, Speed = 60, Homing = 0.4 }),
			T({ Name = "Blink", Windup = 0.8, Recovery = 0.6, Cooldown = 7, Distance = 25, Away = true }),
			Ci({ Name = "Sigil Burst", DamageType = "Magic", Windup = 1.3, Recovery = 1.3, Damage = 1.2, Radius = 9, Offset = 0, MaxRange = 9 }),
		} },
		{ Threshold = 0.5, Name = "Unveiled", Attacks = {
			P({ Name = "Arcane Storm", DamageType = "Magic", Windup = 1.1, Recovery = 1.0, Damage = 0.55, Count = 6, Spread = 70, Speed = 60, Homing = 0.35 }),
			T({ Name = "Blink", Windup = 0.7, Recovery = 0.5, Cooldown = 6, Distance = 25, Away = true }),
			L({ Name = "Lance of Pages", DamageType = "Magic", Windup = 1.1, Recovery = 1.2, Damage = 1.3, Length = 50, Width = 5, MinRange = 8, MaxRange = 50 }),
			H({ Name = "Runic Snare", DamageType = "Magic", Windup = 1.3, Recovery = 1.0, Damage = 0.6, Radius = 7, Duration = 6, TickDamage = 0.15, Count = 2 }),
		} },
	},
	Rewards = { FirstClear = { Items = { veiled_staff = 1, sorcery_band = 1, ancient_shard = 1 }, Title = "Unveiler" } },
})

-- ===================================================================== 9
boss({
	Floor = 9, Name = "The Crimson Duelist", Title = "Blade of a Thousand Ripostes",
	Lore = "She only ever fought one duel: against everyone, one at a time.",
	Mechanic = "Fast parryable attacks and counter-stances. Patience and parries are richly rewarded.",
	HealthMult = 0.9, WalkSpeed = 17, Poise = 130,
	Mechanics = { Counter = { GuardDamageReduction = 0.9 }, ParryReward = 1.5 },
	Model = { Style = "Humanoid", Scale = 1.5, Color = Color3.fromRGB(120, 20, 30), Glow = Color3.fromRGB(255, 60, 70), Weapon = "Rapier" },
	Arena = { Size = 110, Material = "WoodPlanks", Color = Color3.fromRGB(70, 40, 36), Fog = Color3.fromRGB(70, 30, 34), Light = Color3.fromRGB(255, 90, 100), Props = "Banners" },
	Phases = {
		{ Threshold = 1, Attacks = {
			Combo("Crimson Flurry", {
				C({ Windup = 0.75, Recovery = 0.2, Damage = 0.6, Range = 9, Arc = 70, Parryable = true, Status = { Bleed = 20 } }),
				C({ Windup = 0.55, Recovery = 0.2, Damage = 0.6, Range = 9, Arc = 70, Parryable = true, Status = { Bleed = 20 } }),
				C({ Windup = 0.6, Recovery = 1.2, Damage = 0.8, Range = 9, Arc = 70, Parryable = true, Status = { Bleed = 20 } }),
			}),
			Attacks.CounterStance({ Name = "Counter Stance", Windup = 1.2, Recovery = 0.5, Damage = 1.2, Range = 10, Arc = 140, Duration = 1.2 }),
			D({ Name = "Fleche", Windup = 0.8, Recovery = 1.2, Damage = 1.0, Length = 24, Width = 4, Parryable = true }),
		} },
		{ Threshold = 0.5, Name = "First Blood", Attacks = {
			Combo("Crimson Tempest", {
				C({ Windup = 0.7, Recovery = 0.2, Damage = 0.55, Range = 9, Arc = 70, Parryable = true, Status = { Bleed = 20 } }),
				C({ Windup = 0.5, Recovery = 0.2, Damage = 0.55, Range = 9, Arc = 70, Parryable = true, Status = { Bleed = 20 } }),
				C({ Windup = 0.5, Recovery = 0.2, Damage = 0.55, Range = 9, Arc = 70, Parryable = true, Status = { Bleed = 20 } }),
				L({ Windup = 0.8, Recovery = 1.3, Damage = 0.9, Length = 16, Width = 4 }),
			}),
			Attacks.CounterStance({ Name = "Counter Stance", Windup = 1.1, Recovery = 0.5, Damage = 1.3, Range = 10, Arc = 140, Duration = 1.1 }),
			D({ Name = "Fleche", Windup = 0.75, Recovery = 1.1, Damage = 1.0, Length = 26, Width = 4, Parryable = true }),
		} },
	},
	Rewards = { FirstClear = { Items = { crimson_rapier = 1, shadow_ring = 1, ancient_shard = 1, flask_shard = 1 }, Title = "Duelist" } },
})

-- ===================================================================== 10
boss({
	Floor = 10, Name = "The Siege Golem", Title = "Engine of the Broken War",
	Lore = "Built to take a fortress. It took the tower's tenth floor instead, and never left.",
	Mechanic = "Armoured: damage is heavily reduced until heavy hits break its plating. Huge area attacks.",
	HealthMult = 1.2, WalkSpeed = 9, Poise = 260, Defense = 70,
	Mechanics = { Armor = { Reduction = 0.6, BreakDuration = 10 } },
	Model = { Style = "Golem", Scale = 2.8, Color = Color3.fromRGB(100, 96, 90), Glow = Color3.fromRGB(255, 200, 100) },
	Arena = { Size = 150, Material = "Concrete", Color = Color3.fromRGB(80, 76, 70), Fog = Color3.fromRGB(80, 70, 60), Light = Color3.fromRGB(255, 200, 120), Props = "Rubble" },
	Phases = {
		{ Threshold = 1, Attacks = {
			Ci({ Name = "Siege Slam", Windup = 1.4, Recovery = 1.6, Damage = 1.4, Radius = 12, Offset = 6 }),
			R({ Name = "Shockwave", Windup = 1.3, Recovery = 1.4, Damage = 1.2, Inner = 9, Outer = 24 }),
			P({ Name = "Boulder Launch", Windup = 1.4, Recovery = 1.3, Damage = 1.2, Speed = 50, Radius = 4, MinRange = 15 }),
		} },
		{ Threshold = 0.5, Name = "Overpressure", Attacks = {
			Combo("Bombardment", {
				Ci({ Windup = 1.3, Recovery = 0.4, Damage = 1.2, Radius = 11, Offset = 6 }),
				R({ Windup = 1.0, Recovery = 1.5, Damage = 1.2, Inner = 10, Outer = 26 }),
			}),
			H({ Name = "Molten Slag", DamageType = "Fire", Windup = 1.3, Recovery = 1.0, Damage = 0.5, Radius = 8, Duration = 8, TickDamage = 0.15, Count = 3 }),
			D({ Name = "Ram", Windup = 1.2, Recovery = 1.8, Damage = 1.3, Length = 34, Width = 9 }),
		} },
	},
	Rewards = { FirstClear = { Items = { siege_breaker = 1, ancient_shard = 2, armor_plate = 5 }, Title = "Siegebreaker", Cosmetic = "aura_ember" } },
})

-- ===================================================================== 11
boss({
	Floor = 11, Name = "The Drowned Oracle", Title = "She Who Spoke Too Late",
	Lore = "Her prophecies were all true. They simply arrived after the fact.",
	Mechanic = "Delayed magic and tidal waves. Read where the spell will land, not where she is.",
	HealthMult = 0.95,
	Mechanics = { Ambient = { Interval = 14, Attack = L({ Name = "Tidal Surge", Windup = 1.8, Recovery = 0, Damage = 0.9, Length = 160, Width = 14, Blockable = false, FromEdge = true }) } },
	Model = { Style = "Caster", Scale = 2.1, Color = Color3.fromRGB(40, 70, 80), Glow = Color3.fromRGB(80, 200, 220), Hood = true },
	Arena = { Size = 150, Material = "Glass", Color = Color3.fromRGB(30, 50, 60), Fog = Color3.fromRGB(30, 60, 70), Light = Color3.fromRGB(90, 210, 230), Props = "Pools" },
	Phases = {
		{ Threshold = 1, Attacks = {
			H({ Name = "Late Prophecy", DamageType = "Magic", Windup = 2.0, Recovery = 0.8, Damage = 1.2, Radius = 8, Duration = 0.5, TickDamage = 0, Count = 3, Blockable = false }),
			P({ Name = "Brine Orbs", DamageType = "Magic", Windup = 1.1, Recovery = 1.0, Damage = 0.7, Count = 3, Spread = 30, Speed = 40, Homing = 0.25 }),
			T({ Name = "Undertow", Windup = 0.9, Recovery = 0.6, Distance = 20, Cooldown = 9, Away = true }),
		} },
		{ Threshold = 0.5, Name = "High Tide", Attacks = {
			H({ Name = "Late Prophecy", DamageType = "Magic", Windup = 1.8, Recovery = 0.7, Damage = 1.2, Radius = 8, Duration = 0.5, TickDamage = 0, Count = 5, Blockable = false }),
			R({ Name = "Whirlpool", DamageType = "Magic", Windup = 1.3, Recovery = 1.2, Damage = 1.1, Inner = 8, Outer = 22 }),
			P({ Name = "Brine Orbs", DamageType = "Magic", Windup = 1.0, Recovery = 1.0, Damage = 0.7, Count = 5, Spread = 50, Speed = 42, Homing = 0.25 }),
		} },
	},
	Rewards = { FirstClear = { Items = { oracle_seal = 1, oracle_tear = 1, ancient_shard = 2, flask_shard = 1 }, Ability = "oracle_tide", Title = "Tidecaller" } },
})

-- ===================================================================== 12
boss({
	Floor = 12, Name = "The Blackwing Reaper", Title = "Shadow Over the Open Floor",
	Lore = "It nests in the broken roof and only lands to collect.",
	Mechanic = "Airborne most of the fight: melee only connects after its dives. Ranged builds can strike any time.",
	HealthMult = 0.95, WalkSpeed = 18,
	Mechanics = { Airborne = { Height = 16 } },
	Model = { Style = "Winged", Scale = 2.0, Color = Color3.fromRGB(20, 20, 26), Glow = Color3.fromRGB(180, 40, 60), Weapon = "Scythe" },
	Arena = { Size = 160, Material = "Slate", Color = Color3.fromRGB(40, 40, 46), Fog = Color3.fromRGB(30, 30, 40), Light = Color3.fromRGB(200, 70, 90), Props = "Ruins" },
	Phases = {
		{ Threshold = 1, Attacks = {
			D({ Name = "Reaping Dive", Windup = 1.1, Recovery = 1.8, Damage = 1.2, Length = 40, Width = 7, Lands = true }),
			P({ Name = "Feather Storm", Windup = 1.0, Recovery = 1.0, Damage = 0.6, Count = 5, Spread = 60, Speed = 70 }),
			Lp({ Name = "Grim Descent", Windup = 1.3, Recovery = 1.8, Damage = 1.3, Radius = 10, Lands = true }),
		} },
		{ Threshold = 0.5, Name = "Harvest", Attacks = {
			Combo("Double Dive", {
				D({ Windup = 1.1, Recovery = 0.4, Damage = 1.0, Length = 40, Width = 7 }),
				D({ Windup = 0.8, Recovery = 1.8, Damage = 1.1, Length = 40, Width = 7, Lands = true }),
			}),
			P({ Name = "Feather Storm", Windup = 0.9, Recovery = 1.0, Damage = 0.55, Count = 7, Spread = 80, Speed = 72 }),
			Ci({ Name = "Scythe Whirl", Windup = 1.1, Recovery = 1.6, Damage = 1.2, Radius = 11, Lands = true, Status = { Bleed = 35 } }),
		} },
	},
	Rewards = { FirstClear = { Items = { reaper_scythe = 1, ancient_shard = 2 }, Title = "Grounded", Cosmetic = "aura_shadow" } },
})

-- ===================================================================== 13
boss({
	Floor = 13, Name = "The Forsaken Champion", Title = "Three Stances, No Kingdom",
	Lore = "He mastered every school of the blade, and was abandoned by all of them.",
	Mechanic = "Switches between three weapon stances, each with its own patterns. Learn the tells.",
	HealthMult = 1.05,
	Mechanics = { Stances = { Interval = 16 } },
	Model = { Style = "Humanoid", Scale = 1.9, Color = Color3.fromRGB(90, 80, 60), Glow = Color3.fromRGB(255, 220, 140), Weapon = "Greatsword" },
	Arena = { Size = 130, Material = "Cobblestone", Color = Color3.fromRGB(70, 66, 56), Fog = Color3.fromRGB(70, 64, 50), Light = Color3.fromRGB(255, 220, 150), Props = "Statues" },
	Phases = {
		{ Threshold = 1, Stances = {
			{ Name = "Stance of the Blade", Attacks = {
				Combo("Measured Cuts", {
					C({ Windup = 0.9, Recovery = 0.3, Damage = 0.8, Range = 11, Arc = 110, Parryable = true }),
					C({ Windup = 0.6, Recovery = 0.3, Damage = 0.8, Range = 11, Arc = 110, Parryable = true }),
					C({ Windup = 0.8, Recovery = 1.3, Damage = 1.1, Range = 11, Arc = 110, Parryable = true }),
				}),
				L({ Name = "Piercing Lunge", Windup = 0.9, Recovery = 1.2, Damage = 1.1, Length = 18, Width = 4, Parryable = true }),
			} },
			{ Name = "Stance of the Hammer", Attacks = {
				Ci({ Name = "Crushing Blow", Windup = 1.3, Recovery = 1.6, Damage = 1.5, Radius = 8, Offset = 6 }),
				R({ Name = "Quake", Windup = 1.3, Recovery = 1.5, Damage = 1.2, Inner = 8, Outer = 20 }),
			} },
			{ Name = "Stance of the Bow", Attacks = {
				P({ Name = "Volley", Windup = 1.0, Recovery = 1.0, Damage = 0.7, Count = 4, Spread = 45, Speed = 90 }),
				T({ Name = "Disengage", Windup = 0.8, Recovery = 0.6, Distance = 22, Away = true, Cooldown = 6 }),
			} },
		} },
		{ Threshold = 0.45, Name = "All Schools", Attacks = {
			Combo("Champion's Medley", {
				C({ Windup = 0.85, Recovery = 0.3, Damage = 0.8, Range = 11, Arc = 110, Parryable = true }),
				Ci({ Windup = 1.0, Recovery = 0.4, Damage = 1.2, Radius = 8, Offset = 6 }),
				P({ Windup = 0.8, Recovery = 1.3, Damage = 0.7, Count = 3, Spread = 30, Speed = 90 }),
			}),
			R({ Name = "Quake", Windup = 1.2, Recovery = 1.4, Damage = 1.2, Inner = 8, Outer = 22 }),
			L({ Name = "Piercing Lunge", Windup = 0.85, Recovery = 1.1, Damage = 1.1, Length = 20, Width = 4, Parryable = true }),
		} },
	},
	Rewards = { FirstClear = { Items = { champion_blade = 1, ancient_shard = 3, flask_shard = 1 }, Title = "Champion" } },
})

-- ===================================================================== 14
boss({
	Floor = 14, Name = "The Plague Alchemist", Title = "Distiller of the Rot",
	Lore = "She sought a cure for the fall. She found something that spreads faster.",
	Mechanic = "Poison zones and summoned swarms. Carry antidotes, keep moving, cut down the swarm.",
	HealthMult = 0.95,
	Model = { Style = "Caster", Scale = 1.8, Color = Color3.fromRGB(70, 80, 40), Glow = Color3.fromRGB(170, 255, 60), Hood = true },
	Arena = { Size = 140, Material = "Cobblestone", Color = Color3.fromRGB(50, 56, 36), Fog = Color3.fromRGB(70, 90, 40), Light = Color3.fromRGB(170, 255, 80), Props = "Vats" },
	Phases = {
		{ Threshold = 1, Attacks = {
			H({ Name = "Miasma Flask", Windup = 1.2, Recovery = 1.0, Damage = 0.4, Radius = 9, Duration = 9, TickDamage = 0.14, Count = 3, Status = { Poison = 40 } }),
			S({ Name = "Release the Swarm", Windup = 1.3, Recovery = 1.0, Summon = "plague_rat", Count = 3, MaxAlive = 6, Cooldown = 16 }),
			P({ Name = "Caustic Shot", Windup = 0.9, Recovery = 1.0, Damage = 0.8, Count = 2, Spread = 15, Speed = 70, Status = { Poison = 30 } }),
			C({ Name = "Pestle Smash", Windup = 1.0, Recovery = 1.2, Damage = 1.0, Range = 8, Arc = 100, Parryable = true, MaxRange = 8 }),
		} },
		{ Threshold = 0.45, Name = "Final Recipe", Attacks = {
			H({ Name = "Miasma Rain", Windup = 1.2, Recovery = 0.9, Damage = 0.4, Radius = 9, Duration = 10, TickDamage = 0.15, Count = 5, Status = { Poison = 45 } }),
			S({ Name = "Release the Swarm", Windup = 1.2, Recovery = 1.0, Summon = "plague_rat", Count = 4, MaxAlive = 8, Cooldown = 14 }),
			Ci({ Name = "Volatile Burst", Windup = 1.4, Recovery = 1.4, Damage = 1.3, Radius = 12, Status = { Poison = 50 } }),
		} },
	},
	Rewards = { FirstClear = { Items = { plague_bow = 1, bloodstone_ring = 1, ancient_shard = 3 }, Title = "Purifier", Cosmetic = "aura_venom" } },
})

-- ===================================================================== 15
boss({
	Floor = 15, Name = "The Iron Regent", Title = "Ruler of the Fifteenth Throne",
	Lore = "He ruled the tower's middle floors with an iron hand, and an iron sword, and an iron everything.",
	Mechanic = "Complex combos across three phases; each phase adds a new branch to his strings.",
	HealthMult = 1.15, Poise = 240, Defense = 65,
	Model = { Style = "Humanoid", Scale = 2.0, Color = Color3.fromRGB(80, 82, 92), Glow = Color3.fromRGB(255, 240, 200), Weapon = "Sword", Crown = true },
	Arena = { Size = 130, Material = "Marble", Color = Color3.fromRGB(64, 64, 72), Fog = Color3.fromRGB(60, 60, 70), Light = Color3.fromRGB(255, 230, 180), Props = "Throne" },
	Phases = {
		{ Threshold = 1, Attacks = {
			Combo("Royal Decree", {
				C({ Windup = 0.9, Recovery = 0.3, Damage = 0.8, Range = 11, Arc = 120, Parryable = true }),
				C({ Windup = 0.65, Recovery = 0.3, Damage = 0.8, Range = 11, Arc = 120, Parryable = true }),
				L({ Windup = 0.8, Recovery = 1.3, Damage = 1.1, Length = 16, Width = 4, Parryable = true }),
			}),
			Lp({ Name = "Throne Fall", Windup = 1.2, Recovery = 1.5, Damage = 1.2, Radius = 9 }),
		} },
		{ Threshold = 0.66, Name = "Iron Will", Attacks = {
			Combo("Royal Decree II", {
				C({ Windup = 0.85, Recovery = 0.3, Damage = 0.8, Range = 11, Arc = 120, Parryable = true }),
				C({ Windup = 0.6, Recovery = 0.3, Damage = 0.8, Range = 11, Arc = 120, Parryable = true }),
				C({ Windup = 0.9, Recovery = 0.3, Damage = 0.9, Range = 11, Arc = 120, Parryable = true, Delayed = true }),
				R({ Windup = 0.9, Recovery = 1.4, Damage = 1.0, Inner = 6, Outer = 16 }),
			}),
			D({ Name = "Regal Charge", Windup = 1.0, Recovery = 1.5, Damage = 1.1, Length = 32 }),
			S({ Name = "Summon the Guard", Windup = 1.4, Recovery = 1.0, Summon = "hollow_soldier", Count = 2, MaxAlive = 2, Cooldown = 30 }),
		} },
		{ Threshold = 0.33, Name = "Tyranny", Attacks = {
			Combo("Final Decree", {
				C({ Windup = 0.8, Recovery = 0.3, Damage = 0.8, Range = 11, Arc = 120, Parryable = true }),
				L({ Windup = 0.6, Recovery = 0.3, Damage = 0.9, Length = 16, Width = 4, Parryable = true }),
				Lp({ Windup = 0.9, Recovery = 0.4, Damage = 1.0, Radius = 8 }),
				R({ Windup = 0.8, Recovery = 1.5, Damage = 1.0, Inner = 6, Outer = 18 }),
			}),
			Pu({ Name = "Iron Edict", Windup = 2.2, Recovery = 1.6, Damage = 1.0, SafeZones = 3, SafeRadius = 10 }),
			D({ Name = "Regal Charge", Windup = 0.95, Recovery = 1.4, Damage = 1.1, Length = 32 }),
		} },
	},
	Rewards = { FirstClear = { Items = { regent_sword = 1, regent_crown = 1, regent_head = 1, regent_chest = 1, regent_hands = 1, regent_feet = 1, flask_shard = 1 }, Title = "Regicide" } },
})

-- ===================================================================== 16
boss({
	Floor = 16, Name = "The Starved Leviathan", Title = "The Hunger Beneath the Sixteenth Floor",
	Lore = "The tower's cistern held something that has not eaten in a thousand years.",
	Mechanic = "Only its glowing weak points take full damage. The whole arena is its hunting ground.",
	HealthMult = 1.3, Poise = 400, Defense = 50, WalkSpeed = 10,
	Mechanics = { WeakPoints = { Count = 2, BodyMultiplier = 0.35, WeakMultiplier = 1.6 },
		Ambient = { Interval = 16, Attack = Pu({ Name = "Maelstrom", Windup = 2.4, Recovery = 0, Damage = 0.8, SafeZones = 4, SafeRadius = 10 }) } },
	Model = { Style = "Serpent", Scale = 3.0, Color = Color3.fromRGB(30, 50, 60), Glow = Color3.fromRGB(80, 255, 220) },
	Arena = { Size = 170, Material = "Glass", Color = Color3.fromRGB(20, 40, 50), Fog = Color3.fromRGB(20, 40, 56), Light = Color3.fromRGB(60, 220, 210), Props = "Pools" },
	Phases = {
		{ Threshold = 1, Attacks = {
			C({ Name = "Devour", Windup = 1.3, Recovery = 1.6, Damage = 1.5, Range = 16, Arc = 90 }),
			L({ Name = "Tail Lash", Windup = 1.2, Recovery = 1.4, Damage = 1.1, Length = 30, Width = 8 }),
			P({ Name = "Bile Torrent", Windup = 1.2, Recovery = 1.2, Damage = 0.7, Count = 5, Spread = 60, Speed = 50 }),
		} },
		{ Threshold = 0.5, Name = "Ravenous", Attacks = {
			D({ Name = "Breach", Windup = 1.3, Recovery = 1.8, Damage = 1.4, Length = 50, Width = 12 }),
			C({ Name = "Devour", Windup = 1.2, Recovery = 1.5, Damage = 1.5, Range = 16, Arc = 90 }),
			R({ Name = "Coil", Windup = 1.3, Recovery = 1.4, Damage = 1.2, Inner = 10, Outer = 28 }),
		} },
	},
	Rewards = { FirstClear = { Items = { leviathan_spear = 1, ancient_shard = 3, fallen_core = 1 }, Title = "Leviathan Slayer" } },
})

-- ===================================================================== 17
boss({
	Floor = 17, Name = "The Eclipse Witch", Title = "Twin Shadow of the Dark Moon",
	Lore = "She cast two shadows long before the eclipse. Now there are many.",
	Mechanic = "Illusions mimic her; the real witch glows faintly gold. Patterns shift each phase.",
	HealthMult = 1.0,
	Model = { Style = "Caster", Scale = 2.0, Color = Color3.fromRGB(30, 20, 46), Glow = Color3.fromRGB(255, 215, 120), Hood = true },
	Arena = { Size = 150, Material = "Slate", Color = Color3.fromRGB(26, 20, 36), Fog = Color3.fromRGB(30, 20, 50), Light = Color3.fromRGB(160, 100, 255), Props = "Moons" },
	Phases = {
		{ Threshold = 1, Attacks = {
			S({ Name = "Mirror Image", Windup = 1.2, Recovery = 0.8, Summon = "illusion", Count = 2, MaxAlive = 3, Cooldown = 15 }),
			P({ Name = "Crescent Blades", DamageType = "Magic", Windup = 1.0, Recovery = 1.0, Damage = 0.7, Count = 3, Spread = 40, Speed = 70 }),
			T({ Name = "Eclipse Step", Windup = 0.8, Recovery = 0.5, Distance = 16, Cooldown = 8 }),
			Ci({ Name = "Umbral Burst", DamageType = "Magic", Windup = 1.2, Recovery = 1.3, Damage = 1.2, Radius = 10 }),
		} },
		{ Threshold = 0.6, Name = "Penumbra", Attacks = {
			S({ Name = "Mirror Image", Windup = 1.1, Recovery = 0.8, Summon = "illusion", Count = 3, MaxAlive = 4, Cooldown = 14 }),
			R({ Name = "Dark Halo", DamageType = "Magic", Windup = 1.2, Recovery = 1.2, Damage = 1.2, Inner = 8, Outer = 22 }),
			L({ Name = "Moonbeam", DamageType = "Magic", Windup = 1.1, Recovery = 1.2, Damage = 1.3, Length = 60, Width = 6, MinRange = 6, MaxRange = 60 }),
		} },
		{ Threshold = 0.3, Name = "Totality", Attacks = {
			Pu({ Name = "Total Eclipse", DamageType = "Magic", Windup = 2.2, Recovery = 1.5, Damage = 1.0, SafeZones = 3, SafeRadius = 9 }),
			S({ Name = "Mirror Image", Windup = 1.0, Recovery = 0.8, Summon = "illusion", Count = 3, MaxAlive = 4, Cooldown = 12 }),
			P({ Name = "Crescent Storm", DamageType = "Magic", Windup = 0.9, Recovery = 1.0, Damage = 0.6, Count = 6, Spread = 90, Speed = 75, Homing = 0.2 }),
		} },
	},
	Rewards = { FirstClear = { Items = { eclipse_staff = 1, eclipse_head = 1, eclipse_chest = 1, eclipse_hands = 1, eclipse_feet = 1, fallen_core = 1 }, Ability = "eclipse_burst", Title = "Lightbringer" } },
})

-- ===================================================================== 18
boss({
	Floor = 18, Name = "The Nameless General", Title = "Commander of a Forgotten War",
	Lore = "His name was struck from every record. His technique was not.",
	Mechanic = "Aggressive, advanced melee: long strings, delayed finishers and gap closers. Pure skill check.",
	HealthMult = 1.1, WalkSpeed = 17, Poise = 260, Defense = 65,
	Model = { Style = "Humanoid", Scale = 1.9, Color = Color3.fromRGB(46, 44, 40), Glow = Color3.fromRGB(255, 80, 40), Weapon = "Greatsword", Cape = true },
	Arena = { Size = 130, Material = "Basalt", Color = Color3.fromRGB(40, 36, 34), Fog = Color3.fromRGB(50, 36, 30), Light = Color3.fromRGB(255, 110, 60), Props = "Banners" },
	Phases = {
		{ Threshold = 1, Attacks = {
			Combo("War String", {
				C({ Windup = 0.85, Recovery = 0.3, Damage = 0.8, Range = 12, Arc = 130, Parryable = true }),
				C({ Windup = 0.55, Recovery = 0.3, Damage = 0.8, Range = 12, Arc = 130, Parryable = true }),
				C({ Windup = 1.1, Recovery = 0.3, Damage = 1.0, Range = 12, Arc = 130, Parryable = true, Delayed = true }),
				L({ Windup = 0.6, Recovery = 1.3, Damage = 1.1, Length = 18, Width = 5 }),
			}),
			D({ Name = "Vanguard Rush", Windup = 0.85, Recovery = 1.3, Damage = 1.1, Length = 34, Parryable = true }),
			Lp({ Name = "Warlord's Leap", Windup = 1.0, Recovery = 1.4, Damage = 1.3, Radius = 10 }),
		} },
		{ Threshold = 0.5, Name = "No Retreat", Attacks = {
			Combo("Endless War", {
				D({ Windup = 0.8, Recovery = 0.3, Damage = 0.9, Length = 30, Parryable = true }),
				C({ Windup = 0.5, Recovery = 0.3, Damage = 0.8, Range = 12, Arc = 130, Parryable = true }),
				C({ Windup = 0.5, Recovery = 0.3, Damage = 0.8, Range = 12, Arc = 130, Parryable = true }),
				Ci({ Windup = 1.0, Recovery = 1.4, Damage = 1.3, Radius = 10, Offset = 4 }),
			}),
			R({ Name = "Shockwave Cleave", Windup = 1.1, Recovery = 1.3, Damage = 1.2, Inner = 9, Outer = 24 }),
			L({ Name = "Sundering Wave", DamageType = "Fire", Windup = 1.0, Recovery = 1.2, Damage = 1.2, Length = 40, Width = 7 }),
		} },
	},
	Rewards = { FirstClear = { Items = { general_warblade = 1, fallen_core = 1, fallen_remnant = 2 }, Title = "The Named" } },
})

-- ===================================================================== 19
boss({
	Floor = 19, Name = "The Godbreaker", Title = "Weapon That Ended an Age",
	Lore = "Forged from every guardian below, built to destroy whatever waits above.",
	Mechanic = "A gauntlet of earlier lessons: armour, hazards, summons, teleports and arena pulses.",
	HealthMult = 1.15, Poise = 320, Defense = 60,
	Mechanics = { Armor = { Reduction = 0.45, BreakDuration = 9 },
		Ambient = { Interval = 18, Attack = H({ Name = "Fallen Embers", DamageType = "Fire", Windup = 1.5, Recovery = 0, Damage = 0.5, Radius = 8, Duration = 8, TickDamage = 0.12, Count = 3 }) } },
	Model = { Style = "Golem", Scale = 2.6, Color = Color3.fromRGB(60, 56, 70), Glow = Color3.fromRGB(255, 240, 120), Weapon = "Hammer" },
	Arena = { Size = 160, Material = "Concrete", Color = Color3.fromRGB(50, 48, 56), Fog = Color3.fromRGB(56, 50, 66), Light = Color3.fromRGB(255, 240, 160), Props = "Statues" },
	Phases = {
		{ Threshold = 1, Attacks = {
			Ci({ Name = "Hammer of Ages", Windup = 1.3, Recovery = 1.5, Damage = 1.4, Radius = 11, Offset = 6 }),
			Combo("Breaker String", {
				C({ Windup = 0.9, Recovery = 0.3, Damage = 0.9, Range = 13, Arc = 130, Parryable = true }),
				C({ Windup = 1.1, Recovery = 1.4, Damage = 1.1, Range = 13, Arc = 130, Parryable = true, Delayed = true }),
			}),
			S({ Name = "Echoes of the Fallen", Windup = 1.4, Recovery = 1.0, Summon = "hollow_soldier", Count = 2, MaxAlive = 3, Cooldown = 25 }),
		} },
		{ Threshold = 0.5, Name = "Unmaking", Attacks = {
			T({ Name = "Godstep", Windup = 0.9, Recovery = 0.5, Distance = 12, Cooldown = 8 }),
			Lp({ Name = "Skyfall", Windup = 1.1, Recovery = 1.5, Damage = 1.4, Radius = 12 }),
			Pu({ Name = "Shatter Pulse", Windup = 2.2, Recovery = 1.5, Damage = 1.0, SafeZones = 3, SafeRadius = 10 }),
			R({ Name = "Godwave", Windup = 1.2, Recovery = 1.4, Damage = 1.2, Inner = 10, Outer = 26 }),
		} },
	},
	Rewards = { FirstClear = { Items = { godbreaker = 1, fallen_core = 2, fallen_remnant = 3 }, Title = "Breaker of Gods", Cosmetic = "aura_radiant" } },
})

-- ===================================================================== 20
boss({
	Floor = 20, Name = "The Sovereign of Ruin", Title = "The Fallen Crown at the Summit",
	Lore = "The ruler who climbed first, and fell furthest. The tower is the shape of his regret.",
	Mechanic = "Final multi-phase encounter combining blade stances, arena pulses, summons, illusions and hazards.",
	HealthMult = 1.3, Poise = 320, Defense = 60, WalkSpeed = 15,
	Mechanics = { Final = true },
	Model = { Style = "Humanoid", Scale = 2.4, Color = Color3.fromRGB(30, 26, 30), Glow = Color3.fromRGB(255, 60, 40), Weapon = "Greatsword", Crown = true, Cape = true },
	Arena = { Size = 170, Material = "Marble", Color = Color3.fromRGB(36, 30, 34), Fog = Color3.fromRGB(46, 20, 20), Light = Color3.fromRGB(255, 80, 60), Props = "Throne" },
	Phases = {
		{ Threshold = 1, Name = "The Crown", Attacks = {
			Combo("Sovereign Edict", {
				C({ Windup = 0.9, Recovery = 0.3, Damage = 0.8, Range = 13, Arc = 130, Parryable = true }),
				C({ Windup = 0.6, Recovery = 0.3, Damage = 0.8, Range = 13, Arc = 130, Parryable = true }),
				L({ Windup = 0.85, Recovery = 1.3, Damage = 1.2, Length = 22, Width = 5, Parryable = true }),
			}),
			L({ Name = "Ruinous Wave", DamageType = "Fire", Windup = 1.1, Recovery = 1.2, Damage = 1.1, Length = 45, Width = 7 }),
			Lp({ Name = "Fall of Kings", Windup = 1.2, Recovery = 1.5, Damage = 1.3, Radius = 11 }),
		} },
		{ Threshold = 0.66, Name = "The Ruin", Attacks = {
			Pu({ Name = "Collapse of the Tower", Windup = 2.3, Recovery = 1.6, Damage = 1.0, SafeZones = 3, SafeRadius = 10 }),
			S({ Name = "Fallen Court", Windup = 1.3, Recovery = 1.0, Summon = "hollow_soldier", Count = 2, MaxAlive = 3, Cooldown = 24 }),
			H({ Name = "Embers of the Fall", DamageType = "Fire", Windup = 1.2, Recovery = 0.9, Damage = 0.5, Radius = 8, Duration = 8, TickDamage = 0.14, Count = 4 }),
			Combo("Sovereign Edict", {
				C({ Windup = 0.85, Recovery = 0.3, Damage = 0.8, Range = 13, Arc = 130, Parryable = true }),
				Ci({ Windup = 1.0, Recovery = 1.4, Damage = 1.2, Radius = 10, Offset = 5 }),
			}),
		} },
		{ Threshold = 0.33, Name = "The Eclipse of Kings", Attacks = {
			S({ Name = "Mirror of the Crown", Windup = 1.1, Recovery = 0.8, Summon = "illusion", Count = 2, MaxAlive = 3, Cooldown = 16 }),
			Combo("Last Decree", {
				D({ Windup = 0.85, Recovery = 0.3, Damage = 0.9, Length = 34, Parryable = true }),
				C({ Windup = 0.55, Recovery = 0.3, Damage = 0.8, Range = 13, Arc = 130, Parryable = true }),
				R({ Windup = 1.0, Recovery = 0.4, Damage = 1.0, Inner = 9, Outer = 24 }),
				Lp({ Windup = 1.0, Recovery = 1.6, Damage = 1.3, Radius = 12 }),
			}),
			Pu({ Name = "Ruin Unending", Windup = 2.2, Recovery = 1.5, Damage = 1.1, SafeZones = 2, SafeRadius = 11 }),
			P({ Name = "Crown of Blades", DamageType = "Magic", Windup = 1.0, Recovery = 1.0, Damage = 0.6, Count = 8, Spread = 120, Speed = 70 }),
		} },
	},
	Rewards = { FirstClear = { Items = { sovereign_blade = 1, sovereign_sigil = 1, fallen_remnant = 3 }, Ability = "sovereign_wrath", Title = "Sovereign's End", Cosmetic = "aura_crown" } },
})

Bosses.List = list

-- Shared replay rewards
Bosses.ReplayLoot = "boss_replay"

return Bosses
