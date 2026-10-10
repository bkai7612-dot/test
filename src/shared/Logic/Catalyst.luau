--[[
	Catalyst
	Decides which move a light/heavy press performs. Shared by the server (CombatCore, the
	authority) and the client (instant local animation), so both always agree.

	Catalysts (Staff, Seal) cast a spell per combo step while mana lasts. When the player
	cannot afford the next spell, the weapon's Fallback technique is used instead: physical
	strikes that cost no mana (and siphon some back on hit). Switching between spells and
	strikes restarts the combo. Every other weapon simply uses its normal move ("Weapon").
]]

local Catalyst = {}

export type Choice = {
	Mode: string, -- "Weapon" | "Spell" | "Melee"
	Move: any, -- the move table whose Windup/Recovery/Motion/Poise apply
	ManaCost: number,
	Combo: number, -- combo step after this press (0 for heavies)
	Spell: any?, -- per-step spell data (Shots, Spread, Size, Speed, Pierce, Range, Arc)
	Name: string?, -- spell / technique name for the HUD
	AnimType: string?, -- weapon type whose animations to use (nil = the weapon's own)
}

-- wt: WeaponTypes entry. combo: current combo index. chained: within the combo window.
-- prevMode: mode of the previous attack. mana: current mana.
function Catalyst.choose(wt, kind: string, combo: number, chained: boolean, prevMode: string?, mana: number): Choice
	local spellMove = wt[kind]
	local step = if kind == "Light" and chained and combo > 0 then combo % #spellMove.Motion + 1 else 1
	local rawMana = spellMove.Mana
	local cost = if type(rawMana) == "table" then (rawMana[step] or rawMana[#rawMana]) else (rawMana or 0)
	local mode, move = "Weapon", spellMove
	if cost > 0 then
		if mana >= cost or not wt.Fallback then
			mode = "Spell"
		else
			mode, move, cost = "Melee", wt.Fallback[kind], 0
		end
	end
	if prevMode ~= nil and mode ~= prevMode then
		chained = false
	end
	local newCombo = 0
	if kind == "Light" then
		newCombo = if chained and combo > 0 then combo % #move.Motion + 1 else 1
	end
	local spell, name, animType = nil, nil, nil
	if mode == "Spell" then
		spell = if kind == "Light" then (spellMove.Spells and spellMove.Spells[newCombo]) else spellMove.Spell
		name = spell and spell.Name
	elseif mode == "Melee" then
		name = if kind == "Light" then (move.Names and move.Names[newCombo]) else move.Name
		animType = wt.Fallback.AnimType
	end
	return { Mode = mode, Move = move, ManaCost = cost, Combo = newCombo, Spell = spell, Name = name, AnimType = animType }
end

return Catalyst
