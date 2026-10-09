--[[
	Audio
	Sound configuration. Only Roblox built-in content sounds (rbxasset://) are referenced by
	default because no licensed audio has been uploaded for this project yet. Music and
	ambience IDs are intentionally empty: add your own licensed "rbxassetid://..." values here.
	Empty entries are skipped silently.
]]

local Audio = {
	Sfx = {
		Swing = { Id = "rbxasset://sounds/swordslash.wav", Volume = 0.5, PitchRange = { 0.9, 1.1 } },
		HeavySwing = { Id = "rbxasset://sounds/swordlunge.wav", Volume = 0.6, PitchRange = { 0.8, 0.95 } },
		Explosion = { Id = "rbxasset://sounds/swordlunge.wav", Volume = 0.9, PitchRange = { 0.35, 0.45 } },
		Hit = { Id = "rbxasset://sounds/swordslash.wav", Volume = 0.6, PitchRange = { 0.6, 0.75 } },
		Hurt = { Id = "rbxasset://sounds/swordlunge.wav", Volume = 0.6, PitchRange = { 0.5, 0.6 } },
		Parry = { Id = "rbxasset://sounds/unsheath.wav", Volume = 0.9, PitchRange = { 1.2, 1.3 } },
		Dodge = { Id = "rbxasset://sounds/swordlunge.wav", Volume = 0.25, PitchRange = { 1.4, 1.6 } },
		Drink = { Id = "rbxasset://sounds/unsheath.wav", Volume = 0.4, PitchRange = { 0.6, 0.7 } },
		Ui = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.25, PitchRange = { 0.9, 1.0 } },
		Reward = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.4, PitchRange = { 1.3, 1.4 } },
		Death = { Id = "rbxasset://sounds/swordlunge.wav", Volume = 0.8, PitchRange = { 0.3, 0.35 } },
	},
	-- Licensed music / ambience goes here (rbxassetid://...). Empty = silent.
	Music = {
		Sanctuary = "",
		Wilds = "",
		Boss = "",
		Victory = "",
	},
	Ambience = {
		Wind = "",
		Forest = "",
		Cave = "",
	},
}

return Audio
