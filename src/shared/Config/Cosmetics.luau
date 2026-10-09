--[[
	Cosmetics
	Purely visual. Nothing here touches combat numbers; CosmeticService only changes
	particles, colours, materials and name tags. Sources: Achievement, Boss, Purchase, Default.
]]

local Cosmetics = {
	-- Auras (ParticleEmitter around the character)
	aura_ember = { Name = "Ember Aura", Type = "Aura", Color = Color3.fromRGB(255, 140, 60), Source = "Boss" },
	aura_shadow = { Name = "Shadow Aura", Type = "Aura", Color = Color3.fromRGB(40, 30, 60), Source = "Boss" },
	aura_venom = { Name = "Venom Aura", Type = "Aura", Color = Color3.fromRGB(150, 255, 80), Source = "Boss" },
	aura_radiant = { Name = "Radiant Aura", Type = "Aura", Color = Color3.fromRGB(255, 240, 160), Source = "Boss" },
	aura_crown = { Name = "Crown of Ruin", Type = "Aura", Color = Color3.fromRGB(255, 60, 40), Source = "Boss" },
	aura_frost = { Name = "Frost Aura", Type = "Aura", Color = Color3.fromRGB(170, 220, 255), Source = "Achievement" },
	aura_bloodmist = { Name = "Blood Mist", Type = "Aura", Color = Color3.fromRGB(150, 20, 30), Source = "Achievement" },
	aura_starlight = { Name = "Starlight Aura", Type = "Aura", Color = Color3.fromRGB(200, 200, 255), Source = "Purchase" },
	aura_wisp = { Name = "Wisp Aura", Type = "Aura", Color = Color3.fromRGB(120, 255, 220), Source = "Purchase" },
	-- Weapon skins (colour/material override on the held weapon model)
	skin_sovereign = { Name = "Sovereign Finish", Type = "WeaponSkin", Color = Color3.fromRGB(60, 10, 10), Material = "Neon", Source = "Achievement" },
	skin_shadow = { Name = "Shadowsteel Finish", Type = "WeaponSkin", Color = Color3.fromRGB(25, 25, 30), Material = "Metal", Source = "Achievement" },
	skin_gilded = { Name = "Gilded Finish", Type = "WeaponSkin", Color = Color3.fromRGB(220, 180, 70), Material = "Foil", Source = "Purchase" },
	skin_bone = { Name = "Bone Finish", Type = "WeaponSkin", Color = Color3.fromRGB(225, 220, 200), Material = "Marble", Source = "Purchase" },
	-- Armour dyes (tint on the procedural armour pieces)
	dye_crimson = { Name = "Crimson Dye", Type = "ArmorDye", Color = Color3.fromRGB(120, 20, 30), Source = "Purchase" },
	dye_ivory = { Name = "Ivory Dye", Type = "ArmorDye", Color = Color3.fromRGB(230, 225, 210), Source = "Purchase" },
	dye_midnight = { Name = "Midnight Dye", Type = "ArmorDye", Color = Color3.fromRGB(20, 24, 40), Source = "Default" },
}

for id, c in Cosmetics do
	c.Id = id
end

return Cosmetics
