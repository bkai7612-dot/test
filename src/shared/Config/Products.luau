--[[
	Products
	Roblox monetisation configuration. ALL purchases are cosmetic or non-combat convenience.

	IMPORTANT: Product and pass IDs are 0 until real assets are created in the Creator Dashboard.
	Entries with Id = 0 are hidden from the store UI and ignored by receipt processing,
	so nothing can be bought until a developer configures real IDs.

	DevProducts grant `Grant` on a successful, server-validated ProcessReceipt:
	  { Cosmetic = id } or { Cosmetics = { ids } }
	GamePasses are checked with UserOwnsGamePassAsync (and PromptGamePassPurchaseFinished).
]]

local Products = {
	DevProducts = {
		aura_starlight = { Id = 0, Name = "Starlight Aura", PriceRobux = 99, Grant = { Cosmetic = "aura_starlight" } },
		aura_wisp = { Id = 0, Name = "Wisp Aura", PriceRobux = 99, Grant = { Cosmetic = "aura_wisp" } },
		skin_gilded = { Id = 0, Name = "Gilded Weapon Finish", PriceRobux = 79, Grant = { Cosmetic = "skin_gilded" } },
		skin_bone = { Id = 0, Name = "Bone Weapon Finish", PriceRobux = 79, Grant = { Cosmetic = "skin_bone" } },
		dye_pack = { Id = 0, Name = "Dye Pack (Crimson + Ivory)", PriceRobux = 59, Grant = { Cosmetics = { "dye_crimson", "dye_ivory" } } },
	},
	GamePasses = {
		wardrobe_plus = { Id = 0, Name = "Wardrobe Plus", PriceRobux = 149,
			Description = "Three extra build preset slots (5 total). Presets only store equipment you already own." },
	},
}

return Products
