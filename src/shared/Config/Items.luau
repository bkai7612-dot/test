--[[
	Items
	Data-driven definitions for every item. Kinds:
	  Weapon, Shield, Armor, Accessory, Consumable, Material

	Weapon fields:
	  WeaponType  -> WeaponTypes.luau entry (timing, reach, shape)
	  Damage      -> base attack rating at +0
	  DamageType  -> Physical | Magic | Fire | Holy
	  Scaling     -> { Attribute = Grade }  (grades in GameConfig.ScalingGrades)
	  Requires    -> { Attribute = value } ; unmet requirements apply a damage penalty (no hard lock)
	  Upgrade     -> "Standard" (+10, shards) | "Unique" (+5, remnants)
	  Status      -> { Bleed|Poison|Burn = buildup per hit }
	  Weight      -> equip load
	  Value       -> base shop price (sell = Value * SellRatio * rarity mult)

	Armor pieces are generated from ArmorSets below to keep the data compact.
]]

local Items = {}

local function add(id: string, def)
	def.Id = id
	Items[id] = def
end

local function weapon(id, name, wtype, rarity, damage, scaling, requires, opts)
	opts = opts or {}
	add(id, {
		Kind = "Weapon",
		Name = name,
		WeaponType = wtype,
		Rarity = rarity,
		Damage = damage,
		DamageType = opts.DamageType or "Physical",
		Scaling = scaling,
		Requires = requires or {},
		Upgrade = opts.Upgrade or "Standard",
		Status = opts.Status,
		Weight = opts.Weight or 4,
		Value = opts.Value or math.floor(damage * 12),
		Description = opts.Description or "",
		Color = opts.Color,
	})
end

-- ===================================================================== Weapons
-- Starting / shop weapons
weapon("rusted_longsword", "Rusted Longsword", "Sword", "Common", 30, { Strength = "D", Dexterity = "D" }, { Strength = 8, Dexterity = 8 },
	{ Weight = 4, Value = 220, Description = "A blade worn thin by a hundred forgotten battles." })
weapon("knight_longsword", "Knight's Longsword", "Sword", "Uncommon", 36, { Strength = "C", Dexterity = "D" }, { Strength = 11, Dexterity = 9 },
	{ Weight = 4.5, Value = 900, Description = "Standard issue of the sanctuary's oath-bound knights." })
weapon("warrior_handaxe", "Warrior's Hand Axe", "Axe", "Common", 34, { Strength = "C" }, { Strength = 10 },
	{ Weight = 4, Value = 320, Description = "Heavy-headed and dependable." })
weapon("iron_greatsword", "Iron Greatsword", "Greatsword", "Uncommon", 56, { Strength = "B" }, { Strength = 16 },
	{ Weight = 11, Value = 1600, Description = "Slow, heavy, and decisive." })
weapon("ironbound_maul", "Ironbound Maul", "Hammer", "Uncommon", 52, { Strength = "B" }, { Strength = 15 },
	{ Weight = 10, Value = 1500, Description = "Crushes guards and bones alike." })
weapon("shadow_dagger", "Shadow Dagger", "Dagger", "Common", 22, { Dexterity = "B" }, { Dexterity = 9 },
	{ Weight = 1.5, Value = 260, Status = { Bleed = 18 }, Description = "Favoured by those who strike unseen." })
weapon("serrated_dagger", "Serrated Dagger", "Dagger", "Uncommon", 26, { Dexterity = "B", Arcane = "D" }, { Dexterity = 11 },
	{ Weight = 1.5, Value = 1100, Status = { Bleed = 30 }, Description = "Each cut opens the next." })
weapon("pilgrim_spear", "Pilgrim Spear", "Spear", "Common", 32, { Strength = "D", Dexterity = "C" }, { Strength = 9, Dexterity = 10 },
	{ Weight = 5, Value = 480, Description = "Long reach for a cautious traveller." })
weapon("hunter_shortbow", "Hunter's Shortbow", "Bow", "Common", 24, { Dexterity = "C" }, { Dexterity = 10 },
	{ Weight = 3, Value = 500, Description = "Draws quickly. Arrows are fletched from ash." })
weapon("ashwood_longbow", "Ashwood Longbow", "Bow", "Rare", 38, { Dexterity = "B" }, { Dexterity = 16, Strength = 10 },
	{ Weight = 5, Value = 2600, Description = "Its string hums before every shot." })
weapon("apprentice_staff", "Apprentice Staff", "Staff", "Common", 26, { Intelligence = "B" }, { Intelligence = 10 },
	{ DamageType = "Magic", Weight = 3, Value = 400, Description = "A focus for raw, untamed sorcery." })
weapon("lucent_staff", "Lucent Staff", "Staff", "Uncommon", 32, { Intelligence = "A" }, { Intelligence = 16 },
	{ DamageType = "Magic", Weight = 3, Value = 1800, Description = "Crystal-tipped; bends light into force." })
weapon("rift_staff", "Rift Staff", "Staff", "Rare", 40, { Intelligence = "A", Arcane = "D" }, { Intelligence = 22 },
	{ DamageType = "Magic", Weight = 3.5, Value = 4200, Description = "Tears small wounds in the world." })
weapon("pilgrim_seal", "Pilgrim Seal", "Seal", "Common", 24, { Faith = "B" }, { Faith = 10 },
	{ DamageType = "Holy", Weight = 1.5, Value = 400, Description = "A prayer-worn sigil of the old light." })
weapon("lightbound_mace", "Lightbound Mace", "Hammer", "Uncommon", 38, { Strength = "C", Faith = "C" }, { Strength = 12, Faith = 12 },
	{ DamageType = "Holy", Weight = 6, Value = 1400, Description = "Its head glows faintly in the dark." })
weapon("cinder_axe", "Cinder Axe", "Axe", "Rare", 44, { Strength = "C" }, { Strength = 14 },
	{ DamageType = "Fire", Weight = 6, Value = 3800, Status = { Burn = 25 }, Description = "Embers still smoulder in its edge." })
weapon("moonlit_estoc", "Moonlit Estoc", "Sword", "Rare", 40, { Dexterity = "A", Intelligence = "D" }, { Dexterity = 18 },
	{ Weight = 3.5, Value = 4000, Description = "Thin as a moonbeam and twice as cold." })
weapon("vale_glaive", "Hollow Vale Glaive", "Spear", "Epic", 54, { Strength = "B", Dexterity = "B" }, { Strength = 18, Dexterity = 18 },
	{ Weight = 7, Value = 9000, Description = "Found only in the hidden vale beyond the falls." })

-- Boss weapons (Unique upgrade path, +5 max)
local function bossWeapon(id, name, wtype, rarity, damage, scaling, requires, opts)
	opts = opts or {}
	opts.Upgrade = "Unique"
	opts.Value = opts.Value or 0 -- cannot be bought
	weapon(id, name, wtype, rarity, damage, scaling, requires, opts)
	Items[id].BossWeapon = true
end

bossWeapon("warden_halberd", "Ashen Warden's Halberd", "Spear", "Rare", 46, { Strength = "C", Dexterity = "C" }, { Strength = 12, Dexterity = 12 },
	{ Weight = 7, Description = "The Warden held the gate long after the city fell." })
bossWeapon("butcher_cleaver", "Hollow Butcher's Cleaver", "Greatsword", "Rare", 62, { Strength = "B" }, { Strength = 18 },
	{ Weight = 12, Status = { Bleed = 35 }, Description = "Notched by countless delayed swings." })
bossWeapon("thorn_seal", "Matriarch's Thorn Seal", "Seal", "Rare", 38, { Faith = "B", Arcane = "C" }, { Faith = 14 },
	{ DamageType = "Holy", Weight = 2, Status = { Poison = 25 }, Description = "Roots answer the bearer's prayers." })
bossWeapon("gravebound_blade", "Gravebound Blade", "Sword", "Epic", 50, { Strength = "B", Dexterity = "C" }, { Strength = 16, Dexterity = 12 },
	{ Weight = 5, Description = "Strikes hardest against those who wait." })
bossWeapon("ember_fangs", "Ember Fangs", "Dagger", "Epic", 36, { Dexterity = "A" }, { Dexterity = 18 },
	{ DamageType = "Fire", Weight = 2, Status = { Burn = 30 }, Description = "Torn from the hound's still-burning jaw." })
bossWeapon("executioner_axe", "Executioner's Twin Axe", "Axe", "Epic", 64, { Strength = "A" }, { Strength = 22 },
	{ Weight = 9, Description = "Two sentences, one blade." })
bossWeapon("colossus_maul", "Mire Colossus Maul", "Hammer", "Epic", 76, { Strength = "S" }, { Strength = 28 },
	{ Weight = 16, Description = "Swamp water still drips from the stone head." })
bossWeapon("veiled_staff", "Veiled Arcanist's Staff", "Staff", "Epic", 52, { Intelligence = "S" }, { Intelligence = 26 },
	{ DamageType = "Magic", Weight = 3, Description = "Whispers the location of its next spell." })
bossWeapon("crimson_rapier", "Crimson Rapier", "Sword", "Epic", 50, { Dexterity = "S" }, { Dexterity = 26 },
	{ Weight = 3, Status = { Bleed = 40 }, Description = "The duelist never missed a riposte." })
bossWeapon("siege_breaker", "Siege Breaker", "Greatsword", "Epic", 84, { Strength = "A" }, { Strength = 30 },
	{ Weight = 15, Description = "Built to crack walls, used to crack armour." })
bossWeapon("oracle_seal", "Drowned Oracle's Seal", "Seal", "Legendary", 56, { Faith = "S" }, { Faith = 30 },
	{ DamageType = "Holy", Weight = 2, Description = "Its prophecies arrive a moment late." })
bossWeapon("reaper_scythe", "Blackwing Scythe", "Spear", "Legendary", 66, { Dexterity = "A", Arcane = "B" }, { Dexterity = 28, Arcane = 16 },
	{ Weight = 7, Status = { Bleed = 45 }, Description = "Swung from above, it falls like a shadow." })
bossWeapon("champion_blade", "Forsaken Champion's Blade", "Greatsword", "Legendary", 88, { Strength = "A", Dexterity = "B" }, { Strength = 30, Dexterity = 20 },
	{ Weight = 13, Description = "Three stances, one oath, no kingdom." })
bossWeapon("plague_bow", "Plague Alchemist's Bow", "Bow", "Legendary", 56, { Dexterity = "A", Arcane = "B" }, { Dexterity = 26, Arcane = 18 },
	{ Weight = 4, Status = { Poison = 40 }, Description = "Arrows tipped with the alchemist's last recipe." })
bossWeapon("regent_sword", "Iron Regent's Sword", "Sword", "Legendary", 74, { Strength = "A", Dexterity = "A" }, { Strength = 26, Dexterity = 26 },
	{ Weight = 6, Description = "A ruler's blade, heavier than it looks." })
bossWeapon("leviathan_spear", "Leviathan Tooth Spear", "Spear", "Legendary", 76, { Strength = "B", Dexterity = "A" }, { Strength = 22, Dexterity = 30 },
	{ Weight = 8, Description = "Still hungry." })
bossWeapon("eclipse_staff", "Eclipse Staff", "Staff", "Legendary", 68, { Intelligence = "S", Faith = "C" }, { Intelligence = 34, Faith = 16 },
	{ DamageType = "Magic", Weight = 3, Description = "Casts two shadows; only one is real." })
bossWeapon("general_warblade", "Nameless General's Warblade", "Greatsword", "Mythic", 96, { Strength = "S", Dexterity = "B" }, { Strength = 36, Dexterity = 22 },
	{ Weight = 14, Description = "Every scar on it belongs to a different war." })
bossWeapon("godbreaker", "Godbreaker", "Hammer", "Mythic", 106, { Strength = "S", Faith = "B" }, { Strength = 40, Faith = 22 },
	{ DamageType = "Holy", Weight = 18, Description = "It was forged for exactly one purpose." })
bossWeapon("sovereign_blade", "Blade of the Ruined Sovereign", "Sword", "Mythic", 92,
	{ Strength = "B", Dexterity = "B", Intelligence = "B", Faith = "B" }, { Strength = 20, Dexterity = 20, Intelligence = 20, Faith = 20 },
	{ Weight = 7, Description = "It answers to every discipline, and favours none." })

-- ===================================================================== Shields
local function shield(id, name, rarity, stability, opts)
	opts = opts or {}
	add(id, {
		Kind = "Shield",
		Name = name,
		Rarity = rarity,
		Stability = stability, -- 0..100 ; % of blocked damage absorbed
		ParryBonus = opts.ParryBonus or 0, -- extra seconds on parry window
		Requires = opts.Requires or {},
		Weight = opts.Weight or 4,
		Value = opts.Value or 300,
		Upgrade = opts.Upgrade or "Standard",
		Description = opts.Description or "",
		BossWeapon = opts.BossWeapon,
	})
end

shield("wooden_shield", "Weathered Round Shield", "Common", 55, { Weight = 3, Value = 200, Description = "Splintered but serviceable." })
shield("kite_shield", "Sanctuary Kite Shield", "Uncommon", 78, { Weight = 6, Value = 900, Requires = { Strength = 10 }, Description = "Bears the faded crest of the sanctuary." })
shield("tower_shield", "Bastion Tower Shield", "Rare", 92, { Weight = 14, Value = 3500, Requires = { Strength = 20 }, Description = "A wall you can carry, barely." })
shield("sacred_buckler", "Sacred Buckler", "Uncommon", 60, { Weight = 2.5, Value = 800, ParryBonus = 0.06, Description = "Small, bright and quick to turn a blade." })
shield("gravebound_aegis", "Gravebound Aegis", "Epic", 96, { Weight = 10, Value = 0, Upgrade = "Unique", BossWeapon = true, Requires = { Strength = 16 }, Description = "The knight's shield never fell, even when he did." })

-- ===================================================================== Armor
-- Slot multipliers distribute a set's totals across the four pieces.
local SLOT_SHARE = { Head = 0.2, Chest = 0.4, Hands = 0.15, Feet = 0.25 }
local SLOT_NAMES = { Head = "Helm", Chest = "Armor", Hands = "Gauntlets", Feet = "Greaves" }

local ArmorSets = {
	{ Id = "wanderer", Name = "Wanderer", Rarity = "Common", Defense = 30, Magic = 20, Poise = 8, Weight = 8, Value = 600, Color = Color3.fromRGB(105, 92, 78) },
	{ Id = "brigand", Name = "Brigand", Rarity = "Common", Defense = 42, Magic = 18, Poise = 16, Weight = 14, Value = 900, Color = Color3.fromRGB(92, 70, 55) },
	{ Id = "oathknight", Name = "Oathknight", Rarity = "Uncommon", Defense = 70, Magic = 30, Poise = 34, Weight = 28, Value = 2400, Color = Color3.fromRGB(120, 124, 130) },
	{ Id = "scholar", Name = "Scholar", Rarity = "Common", Defense = 22, Magic = 46, Poise = 4, Weight = 6, Value = 700, Color = Color3.fromRGB(52, 60, 96) },
	{ Id = "arcanist", Name = "Arcanist", Rarity = "Uncommon", Defense = 28, Magic = 62, Poise = 6, Weight = 8, Value = 2000, Color = Color3.fromRGB(70, 44, 98) },
	{ Id = "nightstalker", Name = "Nightstalker", Rarity = "Common", Defense = 34, Magic = 26, Poise = 8, Weight = 9, Value = 800, Color = Color3.fromRGB(38, 38, 44) },
	{ Id = "lightward", Name = "Lightward", Rarity = "Uncommon", Defense = 60, Magic = 44, Poise = 26, Weight = 22, Value = 2200, Color = Color3.fromRGB(196, 184, 140) },
	{ Id = "vale", Name = "Hollow Vale", Rarity = "Epic", Defense = 88, Magic = 70, Poise = 30, Weight = 20, Value = 12000, Color = Color3.fromRGB(70, 96, 88) },
	{ Id = "regent", Name = "Iron Regent", Rarity = "Legendary", Defense = 120, Magic = 80, Poise = 52, Weight = 34, Value = 0, Color = Color3.fromRGB(80, 82, 90), BossArmor = true },
	{ Id = "eclipse", Name = "Eclipse", Rarity = "Legendary", Defense = 70, Magic = 120, Poise = 14, Weight = 12, Value = 0, Color = Color3.fromRGB(30, 20, 46), BossArmor = true },
}

for _, set in ArmorSets do
	for slot, share in SLOT_SHARE do
		add(set.Id .. "_" .. string.lower(slot), {
			Kind = "Armor",
			Slot = slot,
			Set = set.Id,
			Name = set.Name .. " " .. SLOT_NAMES[slot],
			Rarity = set.Rarity,
			Defense = math.floor(set.Defense * share + 0.5),
			MagicDefense = math.floor(set.Magic * share + 0.5),
			Poise = math.floor(set.Poise * share + 0.5),
			Weight = math.floor(set.Weight * share * 10 + 0.5) / 10,
			Value = math.floor(set.Value * share),
			Upgrade = "Armor",
			Color = set.Color,
			BossWeapon = set.BossArmor,
			Description = set.Name .. " set piece.",
		})
	end
end
Items._ArmorSets = ArmorSets

-- ===================================================================== Accessories
local function accessory(id, name, rarity, bonuses, value, desc)
	add(id, {
		Kind = "Accessory",
		Name = name,
		Rarity = rarity,
		Bonuses = bonuses,
		Weight = 0.5,
		Value = value,
		Description = desc,
	})
end

accessory("hearth_ring", "Ring of the Hearth", "Uncommon", { MaxHealth = 80 }, 1500, "Warmth that lingers after the fire dies.")
accessory("endurance_band", "Band of Endurance", "Uncommon", { StaminaRegen = 0.15 }, 1500, "Breathe, and go again.")
accessory("ogre_signet", "Ogre Signet", "Rare", { PhysicalDamage = 0.06 }, 3000, "Too large for most fingers.")
accessory("bloodstone_ring", "Bloodstone Ring", "Rare", { StatusBuildup = 0.3 }, 3000, "Pulses when blood is spilled nearby.")
accessory("pilgrim_amulet", "Pilgrim Amulet", "Uncommon", { HolyDamage = 0.1, HealingPower = 0.1 }, 1800, "Carried by those who walked to the tower and back.")
accessory("lucent_pendant", "Lucent Pendant", "Uncommon", { MaxMana = 40 }, 1600, "A drop of trapped starlight.")
accessory("iron_ring", "Iron Ring", "Common", { Poise = 12 }, 700, "Plain, heavy, steadying.")
accessory("shadow_ring", "Shadow Ring", "Rare", { CritDamage = 0.2 }, 3200, "Rewards those who strike from behind.")
accessory("sorcery_band", "Sorcerer's Band", "Rare", { MagicDamage = 0.1 }, 3000, "Etched with sigils that refuse to stay still.")
accessory("ember_heart", "Ember Heart", "Epic", { MaxHealth = 120, FireDamage = 0.1 }, 0, "Taken from the Ember Hound. It still beats.")
accessory("oracle_tear", "Oracle's Tear", "Legendary", { MaxMana = 60, HealingPower = 0.2 }, 0, "Salt water that never dries.")
accessory("regent_crown", "Regent's Iron Circlet", "Legendary", { Poise = 25, PhysicalDamage = 0.05 }, 0, "Heavy is the head.")
accessory("sovereign_sigil", "Sigil of the Sovereign", "Mythic", { MaxHealth = 150, PhysicalDamage = 0.05, MagicDamage = 0.05, HolyDamage = 0.05 }, 0, "Proof you climbed the whole way.")

-- ===================================================================== Consumables
local function consumable(id, name, rarity, effect, value, desc)
	add(id, {
		Kind = "Consumable",
		Name = name,
		Rarity = rarity,
		Effect = effect,
		Stackable = true,
		Value = value,
		Description = desc,
	})
end

consumable("healing_draught", "Healing Draught", "Common", { Type = "Heal", Fraction = 0.3, Cooldown = 6 }, 120, "Restores 30% of maximum health.")
consumable("mana_tonic", "Mana Tonic", "Common", { Type = "Mana", Fraction = 0.45, Cooldown = 6 }, 110, "Restores 45% of maximum mana.")
consumable("stamina_tonic", "Stamina Tonic", "Uncommon", { Type = "Buff", Buff = "StaminaRegen", Amount = 0.4, Duration = 30, Cooldown = 45 }, 260, "Stamina regenerates 40% faster for 30 seconds.")
consumable("antidote", "Antidote", "Common", { Type = "Cure", Status = "Poison", Cooldown = 3 }, 80, "Cures poison and clears poison build-up.")
consumable("fire_resin", "Cinder Resin", "Uncommon", { Type = "Buff", Buff = "FireCoat", Amount = 0.15, Duration = 45, Cooldown = 60 }, 300, "Coats your weapon in fire: +15% damage as fire for 45 seconds.")
consumable("iron_resin", "Iron Resin", "Uncommon", { Type = "Buff", Buff = "Defense", Amount = 0.15, Duration = 40, Cooldown = 60 }, 300, "Reduces damage taken by 15% for 40 seconds.")
consumable("flask_shard", "Flask Shard", "Rare", { Type = "FlaskUpgrade" }, 0, "Use to permanently add one charge to your Ember Flask.")

-- ===================================================================== Materials
local function material(id, name, rarity, value, desc)
	add(id, {
		Kind = "Material",
		Name = name,
		Rarity = rarity,
		Stackable = true,
		Value = value,
		Description = desc,
	})
end

material("ember_shard", "Ember Shard", "Common", 80, "Upgrades standard equipment to +1 through +3.")
material("tempered_shard", "Tempered Shard", "Uncommon", 260, "Upgrades standard equipment to +4 through +6.")
material("ancient_shard", "Ancient Shard", "Rare", 700, "Upgrades standard equipment to +7 through +9.")
material("fallen_core", "Fallen Core", "Epic", 2500, "Upgrades standard equipment to +10.")
material("fallen_remnant", "Fallen Remnant", "Epic", 0, "Residue of a fallen tower guardian. Upgrades unique equipment.")
material("armor_plate", "Armour Plate", "Uncommon", 150, "Reinforces armour.")
material("wild_hide", "Wild Hide", "Common", 25, "Tough hide from the Wildlands. Merchants pay for it.")
material("grave_dust", "Grave Dust", "Uncommon", 60, "Collected from the haunted cemetery.")
material("iron_ore", "Iron Ore", "Common", 35, "Mined from the abandoned fortress.")
material("vale_bloom", "Vale Bloom", "Rare", 220, "Grows only in the hidden vale.")

return Items
