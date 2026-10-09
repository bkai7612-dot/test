--[[
	Classes
	Starting identity only: attributes, loadout, abilities and description.
	No class is locked out of any equipment or ability; requirements are attribute-based.
	Every class starts at level 1 with the same attribute total (74) so no class is
	strictly ahead; they differ in where those points sit.
]]

local Classes = {
	Order = { "Warrior", "Knight", "Mage", "Wizard", "Assassin", "Paladin" },

	Warrior = {
		Name = "Warrior",
		Description = "High strength and solid survivability. Excels with swords and axes and thrives in aggressive melee.",
		Playstyle = "Aggressive melee",
		Attributes = { Vigor = 13, Endurance = 11, Strength = 15, Dexterity = 11, Intelligence = 7, Faith = 8, Arcane = 9 },
		Loadout = {
			Weapon = "warrior_handaxe",
			Offhand = "wooden_shield",
			Armor = { Head = "brigand_head", Chest = "brigand_chest", Hands = "brigand_hands", Feet = "brigand_feet" },
		},
		Abilities = { "war_cry", "whirlwind" },
		Items = { healing_draught = 2, ember_shard = 1 },
		Color = Color3.fromRGB(176, 72, 52),
	},

	Knight = {
		Name = "Knight",
		Description = "Heavy armour, a sturdy shield and patient counterattacks. Less mobile, very hard to kill.",
		Playstyle = "Defensive / counter",
		Attributes = { Vigor = 14, Endurance = 13, Strength = 13, Dexterity = 10, Intelligence = 7, Faith = 9, Arcane = 8 },
		Loadout = {
			Weapon = "knight_longsword",
			Offhand = "kite_shield",
			Armor = { Head = "oathknight_head", Chest = "oathknight_chest", Hands = "oathknight_hands", Feet = "oathknight_feet" },
		},
		Abilities = { "bulwark", "shield_bash" },
		Items = { healing_draught = 2, iron_resin = 1 },
		Color = Color3.fromRGB(150, 156, 168),
	},

	Mage = {
		Name = "Mage",
		Description = "Ranged elemental sorcery. Manages mana and distance to burn enemies down from afar.",
		Playstyle = "Ranged caster",
		Attributes = { Vigor = 10, Endurance = 10, Strength = 7, Dexterity = 10, Intelligence = 16, Faith = 10, Arcane = 11 },
		Loadout = {
			Weapon = "apprentice_staff",
			Offhand = nil,
			Armor = { Head = "scholar_head", Chest = "scholar_chest", Hands = "scholar_hands", Feet = "scholar_feet" },
		},
		Abilities = { "firebolt", "glacial_ring" },
		Items = { healing_draught = 1, mana_tonic = 3 },
		Color = Color3.fromRGB(70, 110, 210),
	},

	Wizard = {
		Name = "Wizard",
		Description = "Advanced spellcraft: slow, devastating area magic and piercing lances. Rewards careful timing.",
		Playstyle = "Area-of-effect caster",
		Attributes = { Vigor = 9, Endurance = 10, Strength = 7, Dexterity = 9, Intelligence = 18, Faith = 9, Arcane = 12 },
		Loadout = {
			Weapon = "apprentice_staff",
			Offhand = nil,
			Armor = { Head = "arcanist_head", Chest = "arcanist_chest", Hands = "arcanist_hands", Feet = "arcanist_feet" },
		},
		Abilities = { "arcane_nova", "rift_lance" },
		Items = { healing_draught = 1, mana_tonic = 3 },
		Color = Color3.fromRGB(130, 70, 190),
	},

	Assassin = {
		Name = "Assassin",
		Description = "Fast, evasive and lethal from behind. Daggers, bleed, critical strikes and shadow movement.",
		Playstyle = "Evasive critical",
		Attributes = { Vigor = 10, Endurance = 12, Strength = 8, Dexterity = 16, Intelligence = 8, Faith = 7, Arcane = 13 },
		Loadout = {
			Weapon = "shadow_dagger",
			Offhand = nil,
			Armor = { Head = "nightstalker_head", Chest = "nightstalker_chest", Hands = "nightstalker_hands", Feet = "nightstalker_feet" },
		},
		Abilities = { "shadow_step", "venom_edge" },
		Items = { healing_draught = 2, antidote = 2 },
		Color = Color3.fromRGB(60, 60, 72),
	},

	Paladin = {
		Name = "Paladin",
		Description = "Holy warrior: solid melee with radiant strikes, protective light and limited healing.",
		Playstyle = "Melee support",
		Attributes = { Vigor = 12, Endurance = 11, Strength = 12, Dexterity = 8, Intelligence = 7, Faith = 15, Arcane = 9 },
		Loadout = {
			Weapon = "lightbound_mace",
			Offhand = "sacred_buckler",
			Armor = { Head = "lightward_head", Chest = "lightward_chest", Hands = "lightward_hands", Feet = "lightward_feet" },
		},
		Abilities = { "sacred_mend", "radiant_smite" },
		Items = { healing_draught = 1, mana_tonic = 2 },
		Color = Color3.fromRGB(220, 196, 120),
	},
}

return Classes
