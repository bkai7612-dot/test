--[[
	Rarities
	Six rarity tiers. `Power` modestly scales base damage/defence; rarity is mostly about
	special properties and upgrade paths rather than raw numbers, so earnable gear stays relevant.
]]

local Rarities = {
	Order = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" },
	Common = { Rank = 1, Color = Color3.fromRGB(190, 190, 185), Power = 1.0, SellMultiplier = 1.0 },
	Uncommon = { Rank = 2, Color = Color3.fromRGB(110, 200, 120), Power = 1.04, SellMultiplier = 1.2 },
	Rare = { Rank = 3, Color = Color3.fromRGB(90, 150, 235), Power = 1.08, SellMultiplier = 1.5 },
	Epic = { Rank = 4, Color = Color3.fromRGB(170, 100, 225), Power = 1.12, SellMultiplier = 2.0 },
	Legendary = { Rank = 5, Color = Color3.fromRGB(235, 170, 60), Power = 1.16, SellMultiplier = 2.6 },
	Mythic = { Rank = 6, Color = Color3.fromRGB(225, 60, 70), Power = 1.2, SellMultiplier = 3.2 },
}

return Rarities
