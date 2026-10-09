--[[
	Shops
	Server-authoritative stock lists. `Price` is always read from here on the server; clients
	only send (shopId, itemId, quantity). `Limit` caps lifetime purchases per character.
	`RequiresFloor` hides stock until that tower floor has been cleared.
]]

local Shops = {
	weapons = {
		Name = "Hedra's Arms",
		Stock = {
			{ Item = "rusted_longsword", Price = 220 },
			{ Item = "warrior_handaxe", Price = 320 },
			{ Item = "shadow_dagger", Price = 260 },
			{ Item = "pilgrim_spear", Price = 480 },
			{ Item = "hunter_shortbow", Price = 500 },
			{ Item = "apprentice_staff", Price = 400 },
			{ Item = "pilgrim_seal", Price = 400 },
			{ Item = "wooden_shield", Price = 200 },
			{ Item = "knight_longsword", Price = 900 },
			{ Item = "lightbound_mace", Price = 1400 },
			{ Item = "kite_shield", Price = 900 },
			{ Item = "sacred_buckler", Price = 800 },
			{ Item = "iron_greatsword", Price = 1600, RequiresFloor = 1 },
			{ Item = "ironbound_maul", Price = 1500, RequiresFloor = 1 },
			{ Item = "serrated_dagger", Price = 1100, RequiresFloor = 2 },
			{ Item = "lucent_staff", Price = 1800, RequiresFloor = 2 },
			{ Item = "ashwood_longbow", Price = 2600, RequiresFloor = 4 },
			{ Item = "tower_shield", Price = 3500, RequiresFloor = 5 },
			{ Item = "moonlit_estoc", Price = 4000, RequiresFloor = 6 },
			{ Item = "rift_staff", Price = 4200, RequiresFloor = 7 },
		},
	},
	armor = {
		Name = "Oswin's Outfitting",
		Stock = {
			{ Item = "wanderer_head", Price = 120 }, { Item = "wanderer_chest", Price = 240 },
			{ Item = "wanderer_hands", Price = 90 }, { Item = "wanderer_feet", Price = 150 },
			{ Item = "scholar_head", Price = 140 }, { Item = "scholar_chest", Price = 280 },
			{ Item = "scholar_hands", Price = 105 }, { Item = "scholar_feet", Price = 175 },
			{ Item = "brigand_head", Price = 180 }, { Item = "brigand_chest", Price = 360 },
			{ Item = "brigand_hands", Price = 135 }, { Item = "brigand_feet", Price = 225 },
			{ Item = "nightstalker_head", Price = 160 }, { Item = "nightstalker_chest", Price = 320 },
			{ Item = "nightstalker_hands", Price = 120 }, { Item = "nightstalker_feet", Price = 200 },
			{ Item = "oathknight_head", Price = 480, RequiresFloor = 1 }, { Item = "oathknight_chest", Price = 960, RequiresFloor = 1 },
			{ Item = "oathknight_hands", Price = 360, RequiresFloor = 1 }, { Item = "oathknight_feet", Price = 600, RequiresFloor = 1 },
			{ Item = "arcanist_head", Price = 400, RequiresFloor = 1 }, { Item = "arcanist_chest", Price = 800, RequiresFloor = 1 },
			{ Item = "arcanist_hands", Price = 300, RequiresFloor = 1 }, { Item = "arcanist_feet", Price = 500, RequiresFloor = 1 },
			{ Item = "lightward_head", Price = 440, RequiresFloor = 1 }, { Item = "lightward_chest", Price = 880, RequiresFloor = 1 },
			{ Item = "lightward_hands", Price = 330, RequiresFloor = 1 }, { Item = "lightward_feet", Price = 550, RequiresFloor = 1 },
			{ Item = "iron_ring", Price = 700 },
			{ Item = "hearth_ring", Price = 1500, RequiresFloor = 2 },
			{ Item = "lucent_pendant", Price = 1600, RequiresFloor = 2 },
			{ Item = "endurance_band", Price = 1500, RequiresFloor = 3 },
			{ Item = "pilgrim_amulet", Price = 1800, RequiresFloor = 3 },
		},
	},
	potions = {
		Name = "Mother Brine's Remedies",
		Stock = {
			{ Item = "healing_draught", Price = 120 },
			{ Item = "mana_tonic", Price = 110 },
			{ Item = "antidote", Price = 80 },
			{ Item = "stamina_tonic", Price = 260, RequiresFloor = 1 },
			{ Item = "iron_resin", Price = 300, RequiresFloor = 2 },
			{ Item = "fire_resin", Price = 300, RequiresFloor = 2 },
		},
	},
	general = {
		Name = "Pell's Curiosities",
		Stock = {
			{ Item = "ember_shard", Price = 160 },
			{ Item = "armor_plate", Price = 300 },
			{ Item = "tempered_shard", Price = 520, RequiresFloor = 3 },
			{ Item = "ancient_shard", Price = 1400, RequiresFloor = 8 },
			{ Item = "flask_shard", Price = 2500, Limit = 2, RequiresFloor = 2 },
		},
	},
}

return Shops
