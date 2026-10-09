--[[
	GameConfig
	Central tunables for Tower of the Fallen. Every gameplay number that a designer
	may want to change lives here or in the other Config modules; logic modules read
	from these tables rather than hard-coding values.
]]

local GameConfig = {}

GameConfig.Version = "0.4.0"
GameConfig.DataVersion = 2

GameConfig.Currency = {
	Name = "Embers",
	StartingAmount = 150,
	MaxCarried = 50_000_000,
}

GameConfig.Level = {
	Max = 120, -- hard level cap; prevents unlimited scaling
	PointsPerLevel = 1,
	-- XP needed to advance FROM `level` to `level + 1` = floor(Base * level ^ Exponent + Linear * level)
	XpBase = 60,
	XpExponent = 1.45,
	XpLinear = 40,
}

GameConfig.Attributes = {
	Min = 1,
	Max = 99,
	List = { "Vigor", "Endurance", "Strength", "Dexterity", "Intelligence", "Faith", "Arcane" },
	Descriptions = {
		Vigor = "Raises maximum health.",
		Endurance = "Raises stamina, stamina regeneration and equipment load.",
		Strength = "Improves damage of heavy weapons and strength-scaling gear.",
		Dexterity = "Improves damage of fast and precise weapons, and bow handling.",
		Intelligence = "Improves sorcery damage and maximum mana.",
		Faith = "Improves holy damage, healing magic and maximum mana.",
		Arcane = "Improves bleed and poison build-up, and arcane-scaling gear.",
	},
}

-- Soft-cap curves: each segment is { upToValue, gainPerPoint }.
-- After the last segment no further gain is awarded.
GameConfig.Curves = {
	Health = { Base = 300, Segments = { { 20, 30 }, { 40, 20 }, { 60, 8 }, { 99, 2 } } },
	Stamina = { Base = 80, Segments = { { 20, 3 }, { 40, 2 }, { 60, 0.75 }, { 99, 0.25 } } },
	Mana = { Base = 50, Segments = { { 20, 5 }, { 40, 3.5 }, { 60, 1.5 }, { 99, 0.5 } } },
	EquipLoad = { Base = 40, Segments = { { 20, 1.5 }, { 40, 1 }, { 60, 0.5 }, { 99, 0.2 } } },
	-- Weapon attribute bonus (fraction of base damage before grade coefficient)
	ScalingBonus = { Base = 0, Segments = { { 20, 0.015 }, { 40, 0.012 }, { 60, 0.006 }, { 99, 0.002 } } },
	StatusBonus = { Base = 0, Segments = { { 20, 0.02 }, { 45, 0.015 }, { 99, 0.004 } } },
}

-- Attribute scaling grade coefficients.
GameConfig.ScalingGrades = { S = 1.2, A = 0.95, B = 0.75, C = 0.5, D = 0.3, E = 0.15 }

GameConfig.Stamina = {
	RegenPerSecond = 34,
	RegenDelay = 0.75, -- seconds after spending before regen resumes
	BlockingRegenMultiplier = 0.4,
	SprintCostPerSecond = 14,
	SprintSpeed = 24,
	WalkSpeed = 16,
	ExhaustedThreshold = 0, -- actions require stamina > threshold
}

GameConfig.Mana = {
	RegenPerSecond = 1.5,
}

GameConfig.Combat = {
	LightAttackCost = 14,
	HeavyAttackCost = 26,
	DodgeCost = 18,
	DodgeCooldown = 0.5,
	DodgeIFrames = 0.32,
	DodgeDistance = 16,
	LatencyGrace = 0.15, -- extra time allowed on dodge/parry windows for network latency
	ParryWindow = 0.22,
	ParryCooldown = 0.9,
	ParryStaminaCost = 10,
	BlockAngle = 130, -- degrees in front of the player that a block covers
	BlockStaminaPerDamage = 0.55, -- multiplied by (1 - stability)
	GuardBreakStun = 1.1,
	StaggerDuration = 0.45, -- player hitstun
	StaggerImmunity = 1.2, -- seconds of stagger immunity after being staggered (anti stun-lock)
	EnemyStaggerDuration = 1.6,
	RiposteWindow = 2.0,
	RiposteMultiplier = 2.5,
	BackstabAngle = 60, -- attacker within this angle of target's back counts as a backstab
	BackstabMultiplier = 1.6,
	DaggerCritBonus = 0.5, -- added to crit multipliers for daggers
	MaxReachTolerance = 3, -- studs of slack on server-side reach checks
	CombatTagSeconds = 8,
	HeavyChargeMax = 1.2, -- seconds of charge for max heavy bonus
	HeavyChargeBonus = 0.6, -- +60% damage at full charge
	MinDamage = 1,
	MaxHitsPerSwing = 6, -- caps multi-target cleave
	PlayerDefenseK = 160, -- absorption = def / (def + K)
	MaxAbsorption = 0.72,
	EnemyDefenseK = 120,
	PoiseRegenDelay = 3,
	PvPDamageMultiplier = 0.5,
}

GameConfig.Status = {
	Bleed = { Threshold = 100, PlayerFraction = 0.12, EnemyFraction = 0.08, BossFraction = 0.04, Decay = 8 },
	Poison = { Threshold = 100, Duration = 10, PlayerDps = 0.012, EnemyDps = 0.01, BossDps = 0.003, Decay = 6 },
	Burn = { Threshold = 100, Duration = 4, PlayerDps = 0.02, EnemyDps = 0.015, BossDps = 0.005, Decay = 10 },
}

GameConfig.EquipLoad = {
	-- ratio thresholds -> dodge cost / dodge cooldown multipliers
	Tiers = {
		{ MaxRatio = 0.3, Name = "Light", DodgeCost = 0.85, Speed = 1.05 },
		{ MaxRatio = 0.7, Name = "Medium", DodgeCost = 1.0, Speed = 1.0 },
		{ MaxRatio = 1.0, Name = "Heavy", DodgeCost = 1.3, Speed = 0.9 },
		{ MaxRatio = math.huge, Name = "Overloaded", DodgeCost = 1.8, Speed = 0.75 },
	},
}

GameConfig.Flask = {
	BaseCharges = 3,
	MaxCharges = 9,
	HealFraction = 0.42,
	UseTime = 0.9, -- seconds the player is committed
	Cooldown = 1.6,
}

GameConfig.Consumables = {
	SharedCooldown = 1.0,
	MaxStack = 20,
}

GameConfig.Death = {
	RecoveryExpirySeconds = 2 * 60 * 60, -- lost embers expire after 2 hours of real time
	-- "LosePrevious": a second death before recovery destroys the earlier marker (classic rule).
	-- "Merge": the new marker holds the sum of both drops.
	SecondDeathRule = "LosePrevious",
	RecoveryRadius = 9,
	RespawnInvulnerability = 2.5,
	LoseCurrencyInPvP = false,
}

GameConfig.Save = {
	StoreName = "TOTF_PlayerData_v2",
	KeyPrefix = "player_",
	AutosaveInterval = 120,
	MaxRetries = 5,
	RetryBaseDelay = 1.5,
	LockStaleSeconds = 600, -- a session lock older than this is considered abandoned
	LockAcquireAttempts = 4,
	LockRetryWait = 4,
	ProcessedReceiptHistory = 80,
	LeaderboardStore = "TOTF_Leaderboard_v1",
	LeaderboardRefresh = 300,
}

GameConfig.Party = {
	MaxSize = 4,
	InviteExpiry = 60,
	BossHealthPerExtraPlayer = 0.7, -- +70% boss HP per extra participant
	BossPoisePerExtraPlayer = 0.25,
	GatherRadius = 40, -- party members must be this close to the tower gate to enter together
}

GameConfig.Tower = {
	Floors = 20,
	ReplayCurrencyMultiplier = 0.35,
	ReplayXpMultiplier = 0.35,
	ReplayUniqueDropChance = 0.12,
	ArenaSlotSpacing = 700,
	ArenaOrigin = { X = 4000, Y = 600, Z = 0 },
	MaxConcurrentArenas = 12,
	EncounterIdleTimeout = 900,
	VictoryTeleportDelay = 8,
}

GameConfig.Enemy = {
	TickRate = 0.1,
	ActivationRadius = 220, -- AI sleeps if no player within this range
	DefaultLeash = 85,
	LootPickupLifetime = 120,
	MaxActive = 120,
	ContributionThreshold = 0.1, -- fraction of max HP a player must deal to earn rewards
}

GameConfig.Training = {
	DailyResetSeconds = 24 * 60 * 60,
	MaxTrainingBonusPerAttribute = 5,
	PointsPerBonus = 10,
	DailyPointCap = 12,
}

GameConfig.Shop = {
	SellRatio = 0.35,
	MaxPurchaseQuantity = 20,
	InteractRadius = 18,
}

GameConfig.Inventory = {
	MaxSlots = 300,
	MaxStack = 999,
	BuildPresetsFree = 2,
	BuildPresetsWithPass = 5,
}

GameConfig.Checkpoint = {
	InteractRadius = 14,
}

GameConfig.AntiCheat = {
	MaxHorizontalSpeed = 75, -- studs/s averaged over a sample window, generous for dodges
	SampleWindow = 1,
	ViolationsBeforeReset = 3,
}

GameConfig.Interaction = {
	MaxRemoteRate = 20, -- per-player requests per second per remote before throttling
}

return GameConfig
