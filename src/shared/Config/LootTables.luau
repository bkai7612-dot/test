--[[
	LootTables
	Each table has:
	  Rolls   : number of weighted rolls from `Entries`
	  Chance  : probability that each roll produces anything (default 1)
	  Entries : { Item, Weight, Min, Max }
	  Guaranteed : items always granted { [itemId] = amount }
	Currency for enemies is defined on the enemy itself.
]]

local LootTables = {
	thrall = { Rolls = 1, Chance = 0.35, Entries = {
		{ Item = "wild_hide", Weight = 40, Min = 1, Max = 2 },
		{ Item = "ember_shard", Weight = 25, Min = 1, Max = 1 },
		{ Item = "healing_draught", Weight = 15, Min = 1, Max = 1 },
		{ Item = "rusted_longsword", Weight = 3, Min = 1, Max = 1 },
		{ Item = "wanderer_head", Weight = 3, Min = 1, Max = 1 },
	} },
	beast = { Rolls = 1, Chance = 0.45, Entries = {
		{ Item = "wild_hide", Weight = 60, Min = 1, Max = 3 },
		{ Item = "ember_shard", Weight = 15, Min = 1, Max = 1 },
	} },
	swamp = { Rolls = 1, Chance = 0.4, Entries = {
		{ Item = "antidote", Weight = 30, Min = 1, Max = 1 },
		{ Item = "ember_shard", Weight = 30, Min = 1, Max = 1 },
		{ Item = "wild_hide", Weight = 20, Min = 1, Max = 1 },
	} },
	bandit = { Rolls = 1, Chance = 0.5, Entries = {
		{ Item = "ember_shard", Weight = 30, Min = 1, Max = 2 },
		{ Item = "tempered_shard", Weight = 8, Min = 1, Max = 1 },
		{ Item = "healing_draught", Weight = 20, Min = 1, Max = 2 },
		{ Item = "serrated_dagger", Weight = 2, Min = 1, Max = 1 },
		{ Item = "brigand_chest", Weight = 3, Min = 1, Max = 1 },
		{ Item = "iron_ore", Weight = 15, Min = 1, Max = 2 },
	} },
	cultist = { Rolls = 1, Chance = 0.5, Entries = {
		{ Item = "ember_shard", Weight = 30, Min = 1, Max = 2 },
		{ Item = "fire_resin", Weight = 15, Min = 1, Max = 1 },
		{ Item = "mana_tonic", Weight = 20, Min = 1, Max = 1 },
		{ Item = "cinder_axe", Weight = 1, Min = 1, Max = 1 },
	} },
	grave = { Rolls = 1, Chance = 0.5, Entries = {
		{ Item = "grave_dust", Weight = 40, Min = 1, Max = 2 },
		{ Item = "tempered_shard", Weight = 12, Min = 1, Max = 1 },
		{ Item = "mana_tonic", Weight = 15, Min = 1, Max = 1 },
		{ Item = "scholar_chest", Weight = 2, Min = 1, Max = 1 },
	} },
	cave = { Rolls = 1, Chance = 0.55, Entries = {
		{ Item = "tempered_shard", Weight = 20, Min = 1, Max = 1 },
		{ Item = "iron_ore", Weight = 30, Min = 1, Max = 3 },
		{ Item = "armor_plate", Weight = 15, Min = 1, Max = 1 },
		{ Item = "moonlit_estoc", Weight = 1, Min = 1, Max = 1 },
	} },
	forest_high = { Rolls = 1, Chance = 0.55, Entries = {
		{ Item = "tempered_shard", Weight = 25, Min = 1, Max = 2 },
		{ Item = "ancient_shard", Weight = 5, Min = 1, Max = 1 },
		{ Item = "stamina_tonic", Weight = 15, Min = 1, Max = 1 },
	} },
	elite = { Rolls = 2, Chance = 0.8, Entries = {
		{ Item = "tempered_shard", Weight = 30, Min = 1, Max = 2 },
		{ Item = "ancient_shard", Weight = 10, Min = 1, Max = 1 },
		{ Item = "armor_plate", Weight = 25, Min = 1, Max = 2 },
		{ Item = "oathknight_chest", Weight = 3, Min = 1, Max = 1 },
		{ Item = "iron_ring", Weight = 4, Min = 1, Max = 1 },
		{ Item = "ogre_signet", Weight = 1, Min = 1, Max = 1 },
	} },
	vale = { Rolls = 2, Chance = 0.85, Entries = {
		{ Item = "ancient_shard", Weight = 25, Min = 1, Max = 2 },
		{ Item = "vale_bloom", Weight = 30, Min = 1, Max = 2 },
		{ Item = "fallen_core", Weight = 2, Min = 1, Max = 1 },
		{ Item = "vale_head", Weight = 2, Min = 1, Max = 1 },
		{ Item = "vale_chest", Weight = 2, Min = 1, Max = 1 },
		{ Item = "vale_hands", Weight = 2, Min = 1, Max = 1 },
		{ Item = "vale_feet", Weight = 2, Min = 1, Max = 1 },
		{ Item = "vale_glaive", Weight = 1, Min = 1, Max = 1 },
	} },
	miniboss_forest = { Rolls = 2, Guaranteed = { tempered_shard = 2 }, Entries = {
		{ Item = "hearth_ring", Weight = 20, Min = 1, Max = 1 },
		{ Item = "ember_shard", Weight = 40, Min = 2, Max = 4 },
		{ Item = "stamina_tonic", Weight = 20, Min = 1, Max = 2 },
	} },
	miniboss_cave = { Rolls = 2, Guaranteed = { tempered_shard = 3, armor_plate = 2 }, Entries = {
		{ Item = "endurance_band", Weight = 20, Min = 1, Max = 1 },
		{ Item = "ancient_shard", Weight = 15, Min = 1, Max = 1 },
		{ Item = "iron_ore", Weight = 40, Min = 2, Max = 5 },
	} },
	miniboss_fortress = { Rolls = 2, Guaranteed = { ancient_shard = 1, flask_shard = 1 }, Entries = {
		{ Item = "tower_shield", Weight = 15, Min = 1, Max = 1 },
		{ Item = "ogre_signet", Weight = 15, Min = 1, Max = 1 },
		{ Item = "ancient_shard", Weight = 30, Min = 1, Max = 2 },
	} },
	chest_low = { Rolls = 2, Guaranteed = { ember_shard = 2 }, Entries = {
		{ Item = "healing_draught", Weight = 30, Min = 1, Max = 2 },
		{ Item = "pilgrim_spear", Weight = 10, Min = 1, Max = 1 },
		{ Item = "hunter_shortbow", Weight = 10, Min = 1, Max = 1 },
		{ Item = "wanderer_chest", Weight = 10, Min = 1, Max = 1 },
	} },
	chest_mid = { Rolls = 2, Guaranteed = { tempered_shard = 1 }, Entries = {
		{ Item = "lucent_pendant", Weight = 10, Min = 1, Max = 1 },
		{ Item = "iron_ring", Weight = 15, Min = 1, Max = 1 },
		{ Item = "stamina_tonic", Weight = 25, Min = 1, Max = 2 },
		{ Item = "armor_plate", Weight = 25, Min = 1, Max = 2 },
	} },
	chest_high = { Rolls = 2, Guaranteed = { ancient_shard = 1 }, Entries = {
		{ Item = "ashwood_longbow", Weight = 10, Min = 1, Max = 1 },
		{ Item = "rift_staff", Weight = 10, Min = 1, Max = 1 },
		{ Item = "pilgrim_amulet", Weight = 10, Min = 1, Max = 1 },
		{ Item = "armor_plate", Weight = 30, Min = 2, Max = 3 },
	} },
	chest_secret = { Rolls = 1, Guaranteed = { flask_shard = 1, tempered_shard = 1 }, Entries = {
		{ Item = "hearth_ring", Weight = 10, Min = 1, Max = 1 },
		{ Item = "endurance_band", Weight = 10, Min = 1, Max = 1 },
		{ Item = "ember_shard", Weight = 20, Min = 3, Max = 4 },
	} },
	chest_secret_high = { Rolls = 1, Guaranteed = { flask_shard = 1, ancient_shard = 1 }, Entries = {
		{ Item = "shadow_ring", Weight = 10, Min = 1, Max = 1 },
		{ Item = "sorcery_band", Weight = 10, Min = 1, Max = 1 },
		{ Item = "bloodstone_ring", Weight = 10, Min = 1, Max = 1 },
	} },
	chest_vale = { Rolls = 2, Guaranteed = { fallen_core = 1 }, Entries = {
		{ Item = "vale_glaive", Weight = 10, Min = 1, Max = 1 },
		{ Item = "vale_bloom", Weight = 40, Min = 2, Max = 4 },
		{ Item = "ancient_shard", Weight = 30, Min = 1, Max = 2 },
	} },
	boss_replay = { Rolls = 2, Entries = {
		{ Item = "ember_shard", Weight = 30, Min = 2, Max = 4 },
		{ Item = "tempered_shard", Weight = 25, Min = 1, Max = 2 },
		{ Item = "ancient_shard", Weight = 12, Min = 1, Max = 1 },
		{ Item = "armor_plate", Weight = 20, Min = 1, Max = 3 },
		{ Item = "fallen_remnant", Weight = 6, Min = 1, Max = 1 },
	} },
	training_dummy = { Rolls = 1, Chance = 0, Entries = { { Item = "ember_shard", Weight = 1, Min = 1, Max = 1 } } },
}

return LootTables
