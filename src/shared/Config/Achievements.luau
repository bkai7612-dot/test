--[[
	Achievements
	Counter-based achievements. `Stat` is a key in profile.Stats incremented by the server;
	`Goal` is the threshold. Some use custom checks (Check = "...") evaluated by AchievementCore.
	Rewards are cosmetic (titles, auras) or small quality-of-life items; never combat power.
]]

local Achievements = {
	first_blood = { Name = "First Blood", Description = "Defeat your first enemy.", Stat = "Kills", Goal = 1, Reward = { Title = "Initiate" } },
	slayer = { Name = "Slayer", Description = "Defeat 250 enemies.", Stat = "Kills", Goal = 250, Reward = { Title = "Slayer" } },
	exterminator = { Name = "Exterminator", Description = "Defeat 2000 enemies.", Stat = "Kills", Goal = 2000, Reward = { Cosmetic = "aura_bloodmist" } },
	floor_1 = { Name = "The Climb Begins", Description = "Clear tower floor 1.", Check = "Floor", Goal = 1 },
	floor_5 = { Name = "Fivefold", Description = "Clear tower floor 5.", Check = "Floor", Goal = 5, Reward = { Title = "Climber" } },
	floor_10 = { Name = "Halfway Up", Description = "Clear tower floor 10.", Check = "Floor", Goal = 10, Reward = { Title = "Ascendant" } },
	floor_15 = { Name = "Thin Air", Description = "Clear tower floor 15.", Check = "Floor", Goal = 15 },
	floor_20 = { Name = "Summit of Ruin", Description = "Clear all 20 floors.", Check = "Floor", Goal = 20, Reward = { Title = "Tower Conqueror", Cosmetic = "skin_sovereign" } },
	parry_10 = { Name = "Deflection", Description = "Parry 10 attacks.", Stat = "Parries", Goal = 10 },
	parry_100 = { Name = "Parry Master", Description = "Parry 100 attacks.", Stat = "Parries", Goal = 100, Reward = { Title = "Riposte" } },
	dodge_500 = { Name = "Untouchable Feet", Description = "Dodge 500 times.", Stat = "Dodges", Goal = 500 },
	flawless = { Name = "Flawless", Description = "Defeat a tower boss without taking damage.", Stat = "FlawlessBosses", Goal = 1, Reward = { Title = "Flawless", Cosmetic = "aura_frost" } },
	solo_10 = { Name = "Lone Climber", Description = "Defeat 10 tower bosses solo.", Stat = "SoloBossKills", Goal = 10, Reward = { Title = "Lone Wolf" } },
	coop_5 = { Name = "Fellowship", Description = "Defeat 5 tower bosses with a party.", Stat = "CoopBossKills", Goal = 5, Reward = { Title = "Companion" } },
	recover_10 = { Name = "Never Lost", Description = "Recover your lost embers 10 times.", Stat = "Recoveries", Goal = 10 },
	deaths_50 = { Name = "Fallen, Not Finished", Description = "Die 50 times. It happens.", Stat = "Deaths", Goal = 50, Reward = { Title = "Undying" } },
	explorer = { Name = "Cartographer", Description = "Discover every location.", Check = "AllLocations", Reward = { Title = "Cartographer" } },
	secrets = { Name = "Secret Keeper", Description = "Discover every secret location.", Check = "AllSecrets", Reward = { Cosmetic = "skin_shadow" } },
	collector = { Name = "Collector", Description = "Own 5 Legendary or Mythic items.", Check = "HighRarity", Goal = 5 },
	smith_10 = { Name = "Master Smith", Description = "Upgrade any item to +10.", Check = "UpgradeLevel", Goal = 10, Reward = { Title = "Smith" } },
	hybrid = { Name = "Spellsword", Description = "Have two different damage attributes at 30 or more.", Check = "Hybrid", Goal = 30, Reward = { Title = "Spellsword" } },
	trainer = { Name = "Disciplined", Description = "Complete 25 training challenges.", Stat = "TrainingDone", Goal = 25, Reward = { Title = "Disciplined" } },
	quests_10 = { Name = "Helping Hand", Description = "Complete 10 quests.", Stat = "QuestsDone", Goal = 10 },
	pvp_10 = { Name = "Pit Fighter", Description = "Win 10 duels in the Ashen Pit.", Stat = "PvPWins", Goal = 10, Reward = { Title = "Pit Fighter" } },
}

for id, a in Achievements do
	a.Id = id
end

return Achievements
