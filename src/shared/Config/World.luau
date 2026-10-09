--[[
	World
	Layout data for the procedurally built world. Positions are { X, Y, Z } tables so that the
	data can be validated by pure tests; the server WorldBuilder converts them to Vector3.

	Map overview (top-down, +Z is south):

	                     Hollow Vale (hidden, north)
	                               |
	      Cemetery      Tower of the Fallen      Fortress
	  Caves     Mist Forest     |      Ruined Village
	                      Fallen Sanctuary (hub)
	         PvP Arena                      Training Grounds
]]

local World = {}

World.Tower = { Center = { 0, 0, 0 }, Radius = 58, FloorHeight = 34, GatePosition = { 0, 0, 78 } }
World.SpawnPoint = { 0, 4, 300 }

World.Regions = {
	{ Id = "sanctuary", Name = "Fallen Sanctuary", Center = { 0, 0, 240 }, Radius = 120, Safe = true, Material = "Cobblestone" },
	{ Id = "training", Name = "Training Grounds", Center = { 240, 0, 270 }, Radius = 70, Safe = true, Material = "Sand" },
	{ Id = "pvp", Name = "Ashen Pit", Center = { -240, 0, 300 }, Radius = 45, Safe = false, PvP = true, Material = "Slate" },
	{ Id = "forest", Name = "Mistveil Forest", Center = { -450, 0, 100 }, Radius = 210, Material = "LeafyGrass", Fog = true },
	{ Id = "village", Name = "Ruins of Ashford", Center = { 420, 0, 60 }, Radius = 160, Material = "Ground" },
	{ Id = "cemetery", Name = "Hallowed Rest Cemetery", Center = { -360, 0, -330 }, Radius = 140, Material = "Mud" },
	{ Id = "caves", Name = "The Hollow Deep", Center = { -700, 0, -170 }, Radius = 110, Material = "Rock" },
	{ Id = "fortress", Name = "Broken Gate Fortress", Center = { 430, 0, -390 }, Radius = 150, Material = "Concrete" },
	{ Id = "vale", Name = "The Hollow Vale", Center = { 0, 0, -760 }, Radius = 170, Material = "Grass", Hidden = true, RequiresFloor = 10 },
}

-- Ember Shrines (checkpoints)
World.Checkpoints = {
	{ Id = "sanctuary", Name = "Sanctuary Bonfire", Position = { 0, 0, 262 }, Default = true },
	{ Id = "tower_gate", Name = "Tower Gate Shrine", Position = { 22, 0, 100 } },
	{ Id = "forest", Name = "Mistveil Shrine", Position = { -360, 0, 130 } },
	{ Id = "village", Name = "Ashford Well Shrine", Position = { 350, 0, 90 } },
	{ Id = "cemetery", Name = "Gravekeeper's Shrine", Position = { -290, 0, -250 } },
	{ Id = "caves", Name = "Deepmouth Shrine", Position = { -565, 0, -170 } },
	{ Id = "fortress", Name = "Gatehouse Shrine", Position = { 360, 0, -300 } },
	{ Id = "vale", Name = "Vale Spring Shrine", Position = { 0, 0, -640 } },
}

-- Discoverable locations (XP on first discovery). Radius = trigger distance.
World.Locations = {
	{ Id = "loc_sanctuary", Name = "Fallen Sanctuary", Position = { 0, 0, 240 }, Radius = 60, Xp = 0 },
	{ Id = "loc_training", Name = "Training Grounds", Position = { 240, 0, 270 }, Radius = 45, Xp = 40 },
	{ Id = "loc_forest", Name = "Mistveil Forest", Position = { -400, 0, 110 }, Radius = 70, Xp = 80 },
	{ Id = "loc_grotto", Name = "Hidden Grotto", Position = { -600, 0, 280 }, Radius = 18, Xp = 250, Secret = true },
	{ Id = "loc_village", Name = "Ruins of Ashford", Position = { 420, 0, 60 }, Radius = 70, Xp = 80 },
	{ Id = "loc_chapel", Name = "Collapsed Chapel", Position = { 500, 0, 140 }, Radius = 20, Xp = 150, Secret = true },
	{ Id = "loc_cemetery", Name = "Hallowed Rest Cemetery", Position = { -360, 0, -330 }, Radius = 70, Xp = 160 },
	{ Id = "loc_crypt", Name = "Sealed Crypt", Position = { -430, 0, -400 }, Radius = 16, Xp = 300, Secret = true },
	{ Id = "loc_caves", Name = "The Hollow Deep", Position = { -680, 0, -170 }, Radius = 60, Xp = 220 },
	{ Id = "loc_fortress", Name = "Broken Gate Fortress", Position = { 430, 0, -390 }, Radius = 75, Xp = 260 },
	{ Id = "loc_ramparts", Name = "Fortress Ramparts", Position = { 500, 18, -460 }, Radius = 18, Xp = 350, Secret = true },
	{ Id = "loc_vale", Name = "The Hollow Vale", Position = { 0, 0, -760 }, Radius = 90, Xp = 1200 },
	{ Id = "loc_pvp", Name = "Ashen Pit", Position = { -240, 0, 300 }, Radius = 40, Xp = 40 },
}

-- Controlled enemy spawn zones. Count = max alive at once; RespawnTime overrides enemy default.
World.SpawnZones = {
	{ Id = "fz1", Enemy = "hollow_thrall", Center = { -320, 0, 160 }, Radius = 40, Count = 4 },
	{ Id = "fz2", Enemy = "rotwood_wolf", Center = { -440, 0, 40 }, Radius = 50, Count = 3 },
	{ Id = "fz3", Enemy = "hollow_thrall", Center = { -520, 0, 120 }, Radius = 40, Count = 3 },
	{ Id = "fz4", Enemy = "bog_crawler", Center = { -480, 0, 230 }, Radius = 40, Count = 3 },
	{ Id = "fz5", Enemy = "mist_stalker", Center = { -600, 0, 40 }, Radius = 40, Count = 2 },
	{ Id = "fmb", Enemy = "rot_shepherd", Center = { -580, 0, 190 }, Radius = 5, Count = 1 },
	{ Id = "vz1", Enemy = "hollow_thrall", Center = { 340, 0, 30 }, Radius = 40, Count = 3 },
	{ Id = "vz2", Enemy = "ruin_bandit", Center = { 450, 0, 40 }, Radius = 45, Count = 4 },
	{ Id = "vz3", Enemy = "pyre_cultist", Center = { 490, 0, 120 }, Radius = 30, Count = 2 },
	{ Id = "vz4", Enemy = "iron_sentinel", Center = { 520, 0, -20 }, Radius = 10, Count = 1 },
	{ Id = "cz1", Enemy = "grave_shade", Center = { -340, 0, -300 }, Radius = 45, Count = 3 },
	{ Id = "cz2", Enemy = "bone_archer", Center = { -400, 0, -370 }, Radius = 40, Count = 3 },
	{ Id = "cz3", Enemy = "hollow_thrall", Center = { -300, 0, -380 }, Radius = 35, Count = 3 },
	{ Id = "kz1", Enemy = "cave_ghoul", Center = { -680, 0, -150 }, Radius = 30, Count = 3 },
	{ Id = "kz2", Enemy = "bog_crawler", Center = { -720, 0, -210 }, Radius = 25, Count = 3 },
	{ Id = "kmb", Enemy = "cave_mother", Center = { -760, 0, -190 }, Radius = 5, Count = 1 },
	{ Id = "tz1", Enemy = "ruin_bandit", Center = { 380, 0, -360 }, Radius = 40, Count = 3 },
	{ Id = "tz2", Enemy = "fortress_knight", Center = { 450, 0, -420 }, Radius = 30, Count = 2 },
	{ Id = "tz3", Enemy = "bone_archer", Center = { 480, 0, -340 }, Radius = 30, Count = 2 },
	{ Id = "tmb", Enemy = "captain_varrow", Center = { 470, 0, -460 }, Radius = 5, Count = 1 },
	{ Id = "hz1", Enemy = "vale_wraith", Center = { -60, 0, -780 }, Radius = 40, Count = 2 },
	{ Id = "hz2", Enemy = "mist_stalker", Center = { 60, 0, -740 }, Radius = 50, Count = 3 },
}

-- Treasure chests. Each can be opened once per character (tracked in the profile).
World.Chests = {
	{ Id = "chest_forest_1", Position = { -420, 0, 170 }, Loot = "chest_low" },
	{ Id = "chest_grotto", Position = { -604, 0, 284 }, Loot = "chest_secret" },
	{ Id = "chest_village_1", Position = { 380, 0, 0 }, Loot = "chest_low" },
	{ Id = "chest_chapel", Position = { 504, 0, 144 }, Loot = "chest_secret" },
	{ Id = "chest_cemetery_1", Position = { -380, 0, -280 }, Loot = "chest_mid" },
	{ Id = "chest_crypt", Position = { -432, 0, -404 }, Loot = "chest_secret_high" },
	{ Id = "chest_caves_1", Position = { -740, 0, -150 }, Loot = "chest_mid" },
	{ Id = "chest_fortress_1", Position = { 400, 0, -430 }, Loot = "chest_high" },
	{ Id = "chest_ramparts", Position = { 500, 18, -464 }, Loot = "chest_secret_high" },
	{ Id = "chest_vale_1", Position = { -40, 0, -820 }, Loot = "chest_vale" },
	{ Id = "chest_vale_2", Position = { 80, 0, -700 }, Loot = "chest_vale" },
}

-- Hub NPCs. Role decides the interaction.
World.NPCs = {
	{ Id = "weapon_merchant", Name = "Hedra the Armsdealer", Role = "Shop", Shop = "weapons", Position = { -50, 0, 210 } },
	{ Id = "armor_merchant", Name = "Oswin the Outfitter", Role = "Shop", Shop = "armor", Position = { -50, 0, 250 } },
	{ Id = "potion_merchant", Name = "Mother Brine", Role = "Shop", Shop = "potions", Position = { 50, 0, 210 } },
	{ Id = "general_merchant", Name = "Pell the Collector", Role = "Shop", Shop = "general", Position = { 50, 0, 250 } },
	{ Id = "blacksmith", Name = "Doran the Smith", Role = "Blacksmith", Position = { -80, 0, 290 } },
	{ Id = "elder", Name = "Elder Maelis", Role = "Quest", Quests = { "main_tower_1", "main_tower_5", "main_tower_10", "main_tower_15", "main_tower_20" }, Position = { 0, 0, 200 } },
	{ Id = "huntmaster", Name = "Huntmaster Corvin", Role = "Quest", Quests = { "hunt_thralls", "hunt_wolves", "hunt_shepherd", "hunt_bandits", "hunt_varrow" }, Position = { 80, 0, 290 } },
	{ Id = "archivist", Name = "Archivist Sela", Role = "Quest", Quests = { "explore_regions", "explore_secrets", "explore_vale" }, Position = { 30, 0, 330 } },
	{ Id = "smith_quest", Name = "Doran's Apprentice", Role = "Quest", Quests = { "smith_upgrade3", "smith_ore" }, Position = { -95, 0, 305 } },
	{ Id = "trainer", Name = "Trainer Hask", Role = "Quest", Quests = { "train_basics" }, Position = { 210, 0, 250 } },
	{ Id = "wardrobe", Name = "The Mirror Keeper", Role = "Wardrobe", Position = { -30, 0, 340 } },
	{ Id = "party_board", Name = "Fellowship Board", Role = "Party", Position = { 30, 0, 280 } },
	{ Id = "guide", Name = "Ilya the Guide", Role = "Tutorial", Position = { 0, 0, 315 } },
}

-- Training station layout (positions relative to the training region).
World.TrainingStations = {
	{ Id = "weights", Challenge = "weightlifting", Position = { 210, 0, 290 } },
	{ Id = "dummies", Challenge = "dummy_dps", Position = { 250, 0, 240 } },
	{ Id = "dodge", Challenge = "dodge_drill", Position = { 280, 0, 280 } },
	{ Id = "parry", Challenge = "parry_drill", Position = { 260, 0, 310 } },
	{ Id = "endurance", Challenge = "stamina_run", Position = { 220, 0, 320 } },
	{ Id = "sparring", Challenge = "sparring", Position = { 290, 0, 240 } },
}

return World
