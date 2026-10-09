--[[
	Upgrades
	Blacksmith upgrade paths. Cost of upgrading FROM level L to L+1 is Costs[L + 1].
	DamagePerLevel multiplies base damage: base * (1 + DamagePerLevel * level).
	ScalingPerLevel improves attribute scaling contribution in the same way.
]]

local Upgrades = {
	Standard = {
		Max = 10,
		DamagePerLevel = 0.09,
		ScalingPerLevel = 0.04,
		StabilityPerLevel = 1.0, -- shields
		Costs = {
			{ Material = "ember_shard", Amount = 1, Currency = 200 },
			{ Material = "ember_shard", Amount = 2, Currency = 400 },
			{ Material = "ember_shard", Amount = 3, Currency = 700 },
			{ Material = "tempered_shard", Amount = 1, Currency = 1100 },
			{ Material = "tempered_shard", Amount = 2, Currency = 1600 },
			{ Material = "tempered_shard", Amount = 3, Currency = 2300 },
			{ Material = "ancient_shard", Amount = 1, Currency = 3200 },
			{ Material = "ancient_shard", Amount = 2, Currency = 4300 },
			{ Material = "ancient_shard", Amount = 3, Currency = 5600 },
			{ Material = "fallen_core", Amount = 1, Currency = 8000 },
		},
	},
	Unique = {
		Max = 5,
		DamagePerLevel = 0.18,
		ScalingPerLevel = 0.08,
		StabilityPerLevel = 1.0,
		Costs = {
			{ Material = "fallen_remnant", Amount = 1, Currency = 1500 },
			{ Material = "fallen_remnant", Amount = 1, Currency = 3000 },
			{ Material = "fallen_remnant", Amount = 2, Currency = 5000 },
			{ Material = "fallen_remnant", Amount = 2, Currency = 7500 },
			{ Material = "fallen_remnant", Amount = 3, Currency = 10000 },
		},
	},
	Armor = {
		Max = 5,
		DefensePerLevel = 0.08,
		Costs = {
			{ Material = "armor_plate", Amount = 1, Currency = 250 },
			{ Material = "armor_plate", Amount = 2, Currency = 600 },
			{ Material = "armor_plate", Amount = 3, Currency = 1200 },
			{ Material = "armor_plate", Amount = 4, Currency = 2200 },
			{ Material = "armor_plate", Amount = 5, Currency = 3600 },
		},
	},
}

return Upgrades
