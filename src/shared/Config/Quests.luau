--[[
	Quests
	Objective types:
	  Kill      { Enemy, Count }   enemy defeats credited to the player (contribution rules apply)
	  Boss      { Floor }          tower floor cleared (first clear or earlier)
	  Discover  { Location | Count } location id, or any N locations
	  Secret    { Count }          number of Secret locations discovered
	  Upgrade   { Level }          any equipment upgraded to Level
	  Collect   { Item, Count }    items handed in (consumed on turn-in)
	  Training  { Count }          training challenges completed
	Rewards: { Xp, Currency, Items = { [id] = n }, Title }
	Requires: quest ids that must be completed first.
]]

local Quests = {
	main_tower_1 = { Name = "The First Gate", Giver = "elder", Description = "Defeat the Ashen Warden on the tower's first floor.",
		Objective = { Type = "Boss", Floor = 1 }, Rewards = { Xp = 400, Currency = 500, Items = { healing_draught = 3 } } },
	main_tower_5 = { Name = "Fire on the Fifth", Giver = "elder", Requires = { "main_tower_1" }, Description = "Reach and defeat the Ember Hound.",
		Objective = { Type = "Boss", Floor = 5 }, Rewards = { Xp = 3000, Currency = 2500, Items = { tempered_shard = 2 } } },
	main_tower_10 = { Name = "The Broken Engine", Giver = "elder", Requires = { "main_tower_5" }, Description = "Destroy the Siege Golem.",
		Objective = { Type = "Boss", Floor = 10 }, Rewards = { Xp = 12000, Currency = 8000, Items = { ancient_shard = 2 } } },
	main_tower_15 = { Name = "Regicide", Giver = "elder", Requires = { "main_tower_10" }, Description = "Overthrow the Iron Regent.",
		Objective = { Type = "Boss", Floor = 15 }, Rewards = { Xp = 30000, Currency = 20000, Items = { fallen_core = 1 } } },
	main_tower_20 = { Name = "The Summit", Giver = "elder", Requires = { "main_tower_15" }, Description = "End the Sovereign of Ruin.",
		Objective = { Type = "Boss", Floor = 20 }, Rewards = { Xp = 80000, Currency = 50000, Title = "Fallen No More" } },

	hunt_thralls = { Name = "Thinning the Hollow", Giver = "huntmaster", Description = "Defeat 8 Hollow Thralls in the Wildlands.",
		Objective = { Type = "Kill", Enemy = "hollow_thrall", Count = 8 }, Rewards = { Xp = 250, Currency = 300, Items = { ember_shard = 2 } } },
	hunt_wolves = { Name = "Rotwood Cull", Giver = "huntmaster", Requires = { "hunt_thralls" }, Description = "Defeat 6 Rotwood Wolves in Mistveil Forest.",
		Objective = { Type = "Kill", Enemy = "rotwood_wolf", Count = 6 }, Rewards = { Xp = 400, Currency = 400, Items = { healing_draught = 2 } } },
	hunt_shepherd = { Name = "The Rot Shepherd", Giver = "huntmaster", Requires = { "hunt_wolves" }, Description = "Find and defeat the Rot Shepherd deep in the forest.",
		Objective = { Type = "Kill", Enemy = "rot_shepherd", Count = 1 }, Rewards = { Xp = 1500, Currency = 1200, Items = { flask_shard = 1 } } },
	hunt_bandits = { Name = "Bandits of Ashford", Giver = "huntmaster", Requires = { "hunt_thralls" }, Description = "Defeat 10 Ruin Bandits.",
		Objective = { Type = "Kill", Enemy = "ruin_bandit", Count = 10 }, Rewards = { Xp = 1400, Currency = 1100, Items = { tempered_shard = 1 } } },
	hunt_varrow = { Name = "The Broken Gate", Giver = "huntmaster", Requires = { "hunt_bandits" }, Description = "Defeat Captain Varrow in the abandoned fortress.",
		Objective = { Type = "Kill", Enemy = "captain_varrow", Count = 1 }, Rewards = { Xp = 5000, Currency = 4000, Items = { ancient_shard = 2 } } },

	explore_regions = { Name = "Charting the Wilds", Giver = "archivist", Description = "Discover 6 locations.",
		Objective = { Type = "Discover", Count = 6 }, Rewards = { Xp = 600, Currency = 500 } },
	explore_secrets = { Name = "What the Maps Forgot", Giver = "archivist", Requires = { "explore_regions" }, Description = "Discover 3 secret locations.",
		Objective = { Type = "Secret", Count = 3 }, Rewards = { Xp = 2000, Currency = 1500, Items = { flask_shard = 1 } } },
	explore_vale = { Name = "Beyond the Falls", Giver = "archivist", Requires = { "explore_secrets" }, Description = "Find the Hollow Vale.",
		Objective = { Type = "Discover", Location = "loc_vale" }, Rewards = { Xp = 6000, Currency = 4000, Title = "Valewalker" } },

	smith_upgrade3 = { Name = "Tempered Steel", Giver = "smith_quest", Description = "Upgrade any weapon or shield to +3.",
		Objective = { Type = "Upgrade", Level = 3 }, Rewards = { Xp = 500, Currency = 400, Items = { tempered_shard = 1 } } },
	smith_ore = { Name = "Ore for the Forge", Giver = "smith_quest", Requires = { "smith_upgrade3" }, Description = "Bring 6 Iron Ore to the forge.",
		Objective = { Type = "Collect", Item = "iron_ore", Count = 6 }, Rewards = { Xp = 900, Currency = 300, Items = { armor_plate = 3 } } },

	train_basics = { Name = "Forms and Footwork", Giver = "trainer", Description = "Complete 3 training challenges.",
		Objective = { Type = "Training", Count = 3 }, Rewards = { Xp = 300, Currency = 250, Items = { stamina_tonic = 1 } } },
}

for id, q in Quests do
	q.Id = id
	q.Requires = q.Requires or {}
end

return Quests
