--[[
	MenuController
	All menus: class selection, the main menu (Character, Inventory, Abilities, Quests, Map,
	Tower, Party, Achievements, Cosmetics, Settings) and NPC menus (Shop, Blacksmith,
	Quest giver, Shrine, Tutorial). Menus only display state and send requests; the server
	validates and answers every action.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared.Config
local GameConfig = require(Config.GameConfig)
local Classes = require(Config.Classes)
local Items = require(Config.Items)
local Abilities = require(Config.Abilities)
local Rarities = require(Config.Rarities)
local Quests = require(Config.Quests)
local Shops = require(Config.Shops)
local Bosses = require(Config.Bosses)
local World = require(Config.World)
local Achievements = require(Config.Achievements)
local Cosmetics = require(Config.Cosmetics)
local Products = require(Config.Products)
local WeaponTypes = require(Config.WeaponTypes)
local Formulas = require(Shared.Logic.Formulas)
local Net = require(Shared.Net)

local MenuController = {
	OnSettings = nil :: ((any) -> ())?,
	MapToCanvas = nil :: ((number, number) -> UDim2)?,
}

local player = Players.LocalPlayer
local UIKit, ClientState, InputController, HUD, AudioController
local T
local gui: ScreenGui
local window: Frame
local tabBar: Frame
local content: Frame
local titleLabel: TextLabel
local currentPage = "Character"
local context: any = {} -- NPC context (Shop id, quest list, ...)
local pendingAlloc = {}
local selectedItem: string? = nil
local inventoryFilter = "All"
local classOverlay: Frame? = nil
local mapDot: Frame? = nil

local MAIN_TABS = { "Character", "Inventory", "Abilities", "Quests", "Map", "Tower", "Party", "Achievements", "Cosmetics", "Settings" }

local function profile()
	return ClientState.Profile
end

local function notifyResult(ok: boolean, err, successText: string?)
	if ok then
		if successText then
			HUD.Toast(successText, "Reward")
		end
		AudioController.Play("Ui")
	else
		HUD.Toast(ClientState.ErrorText(err), "Error")
	end
end

-- Sends a request and reports the outcome (keeps the server's error code).
local function act(name: string, payload: any?, successText: string?)
	local ok, res = ClientState.Request(name, payload)
	notifyResult(ok, res, successText)
	return ok, res
end

local function rarityColor(def): Color3
	local r = def and Rarities[def.Rarity]
	return r and r.Color or T.Text
end

local function row(parent: Instance, height: number?)
	local f = UIKit.new("Frame", { BackgroundColor3 = T.Panel2, BorderSizePixel = 0, Size = UDim2.new(1, -8, 0, height or 40), Parent = parent })
	UIKit.corner(f, 6)
	return f
end

local function header(parent: Instance, text: string)
	return UIKit.label(text, { Size = UDim2.new(1, 0, 0, 28), TextSize = 22, TextColor3 = T.Accent, Parent = parent })
end

-- Item description used by inventory, shop and blacksmith.
local function describeItem(def, upgrade: number?, attrs): string
	local lines = { ("%s  [%s]"):format(def.Kind, def.Rarity) }
	if def.Kind == "Weapon" then
		local ar = Formulas.weaponAttackRating(def, upgrade or 0, attrs)
		table.insert(lines, ("Attack %d (%s)  Type: %s"):format(math.floor(ar.Total), def.DamageType, def.WeaponType))
		local sc = {}
		for a, g in def.Scaling do
			table.insert(sc, a:sub(1, 3) .. " " .. g)
		end
		table.insert(lines, "Scaling: " .. table.concat(sc, ", "))
		local req = {}
		for a, v in def.Requires do
			local ok = (attrs[a] or 0) >= v
			table.insert(req, ("%s %d%s"):format(a:sub(1, 3), v, if ok then "" else " (!)"))
		end
		if #req > 0 then
			table.insert(lines, "Requires: " .. table.concat(req, ", ") .. (if ar.RequirementsMet then "" else "  - unmet: -40% damage"))
		end
		local wt = WeaponTypes[def.WeaponType]
		table.insert(lines, ("Reach %s  Speed %.2fs"):format(wt.Ranged and "ranged" or tostring(wt.Range), wt.Light.Windup + wt.Light.Recovery))
		if def.Status then
			for k, v in def.Status do
				table.insert(lines, ("%s build-up %d"):format(k, v))
			end
		end
	elseif def.Kind == "Shield" then
		table.insert(lines, ("Stability %d%%%s"):format(Formulas.shieldStability(def, upgrade or 0), if def.ParryBonus > 0 then "  Parry window +" .. def.ParryBonus .. "s" else ""))
	elseif def.Kind == "Armor" then
		local d, m = Formulas.armorDefense(def, upgrade or 0)
		table.insert(lines, ("%s  Defence %d  Magic %d  Poise %d"):format(def.Slot, math.floor(d), math.floor(m), def.Poise))
	elseif def.Kind == "Accessory" then
		for k, v in def.Bonuses do
			table.insert(lines, ("%s %s"):format(k, if v < 1 then ("+%d%%"):format(v * 100) else "+" .. v))
		end
	end
	if def.Weight then
		table.insert(lines, ("Weight %.1f"):format(def.Weight))
	end
	if def.Description and def.Description ~= "" then
		table.insert(lines, def.Description)
	end
	return table.concat(lines, "\n")
end

local function itemName(inst): string
	local def = Items[inst.Id]
	return def.Name .. (if inst.Upgrade > 0 then (" +%d"):format(inst.Upgrade) else "")
end

-- ===================================================================== pages
local Pages = {}

Pages.Character = function(c)
	local p = profile()
	local stats = p.Derived
	header(c, ("%s  -  Level %d"):format(p.Class, p.Level))
	local spent = 0
	for _, v in pendingAlloc do
		spent += v
	end
	UIKit.label(("Unspent points: %d   (allocate while resting at an Ember Shrine)"):format(p.UnspentPoints - spent), { Size = UDim2.new(1, 0, 0, 22), TextSize = 17, TextColor3 = T.Muted, Parent = c })
	for _, attr in GameConfig.Attributes.List do
		local r = row(c, 34)
		local pending = pendingAlloc[attr] or 0
		local bonus = p.TrainingBonus[attr] or 0
		UIKit.label(("%s  %d%s%s"):format(attr, p.Attributes[attr] + pending, if pending > 0 then (" (+%d)"):format(pending) else "", if bonus > 0 then ("  [+%d trained]"):format(bonus) else ""),
			{ Position = UDim2.fromOffset(10, 0), Size = UDim2.new(0.45, 0, 1, 0), TextSize = 18, Parent = r })
		UIKit.label(GameConfig.Attributes.Descriptions[attr], { Position = UDim2.new(0.45, 0, 0, 0), Size = UDim2.new(0.4, 0, 1, 0), TextSize = 14, TextColor3 = T.Muted, Parent = r })
		UIKit.button("-", function()
			if pending > 0 then
				pendingAlloc[attr] = pending - 1
				MenuController.Render()
			end
		end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -46, 0.5, 0), Size = UDim2.fromOffset(32, 26), Parent = r })
		UIKit.button("+", function()
			if p.UnspentPoints - spent > 0 then
				pendingAlloc[attr] = pending + 1
				MenuController.Render()
			end
		end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(32, 26), Parent = r })
	end
	if spent > 0 then
		UIKit.button(("Confirm %d point%s"):format(spent, spent > 1 and "s" or ""), function()
			local ok, err = ClientState.Request("AllocateAttributes", pendingAlloc)
			if ok then
				table.clear(pendingAlloc)
			end
			notifyResult(ok, err, "Attributes increased.")
		end, { Size = UDim2.fromOffset(200, 34), Parent = c })
	end
	if stats then
		local s = row(c, 120)
		UIKit.label(("Health %d   Stamina %d   Mana %d\nDefence %d   Magic Defence %d   Poise %d\nAttack rating %d%s   Shield/guard stability %d%%\nEquip load %.1f / %.1f  (%s)"):format(
			stats.MaxHealth, stats.MaxStamina, stats.MaxMana, stats.Defense, stats.MagicDefense, stats.Poise,
			math.floor(stats.AttackRating), if stats.RequirementsMet then "" else " (requirements unmet)", stats.Stability,
			stats.EquipLoad, stats.MaxEquipLoad, stats.LoadTier), { Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -20, 1, -12), TextSize = 17, Parent = s })
	end
	local need = Formulas.xpToNext(p.Level)
	UIKit.label(("XP %d / %s   -   Embers %d   -   Flask charges %d"):format(p.Xp, if need == math.huge then "MAX" else tostring(need), p.Currency, p.Flask.MaxCharges), { Size = UDim2.new(1, 0, 0, 24), TextSize = 16, TextColor3 = T.Muted, Parent = c })
end

local KIND_FILTERS = { "All", "Weapon", "Shield", "Armor", "Accessory", "Consumable", "Material" }

Pages.Inventory = function(c)
	local p = profile()
	local attrs = p.Derived and p.Derived.Attributes or p.Attributes
	local equippedBy = {}
	for slot, uid in p.Equipped do
		equippedBy[uid] = slot
	end
	local filters = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), Parent = c })
	UIKit.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), Parent = filters })
	for _, f in KIND_FILTERS do
		UIKit.button(f, function()
			inventoryFilter = f
			MenuController.Render()
		end, { Size = UDim2.fromOffset(92, 28), TextSize = 15, BackgroundColor3 = if inventoryFilter == f then T.Border else T.Panel2, Parent = filters })
	end
	local body = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -120), Parent = c })
	local list = UIKit.list({ Size = UDim2.new(0.5, -4, 1, 0), Parent = body }, 4)
	local detail = UIKit.panel({ Position = UDim2.new(0.5, 4, 0, 0), Size = UDim2.new(0.5, -4, 1, 0), BackgroundColor3 = T.Bg, Parent = body })
	UIKit.padding(detail, 10)
	local entries = {}
	for uid, inst in p.Inventory.Items do
		local def = Items[inst.Id]
		if def and (inventoryFilter == "All" or def.Kind == inventoryFilter) then
			table.insert(entries, { Key = uid, Def = def, Inst = inst, Name = itemName(inst), Equipped = equippedBy[uid] })
		end
	end
	for id, n in p.Inventory.Stacks do
		local def = Items[id]
		if def and (inventoryFilter == "All" or def.Kind == inventoryFilter) then
			table.insert(entries, { Key = id, Def = def, Count = n, Name = def.Name .. " x" .. n })
		end
	end
	table.sort(entries, function(a, b)
		if (a.Equipped ~= nil) ~= (b.Equipped ~= nil) then
			return a.Equipped ~= nil
		end
		return a.Name < b.Name
	end)
	for _, e in entries do
		local b = UIKit.button((if e.Equipped then "[E] " else "") .. e.Name, function()
			selectedItem = e.Key
			MenuController.Render()
		end, { Size = UDim2.new(1, -8, 0, 32), TextSize = 16, TextColor3 = rarityColor(e.Def), TextXAlignment = Enum.TextXAlignment.Left, Parent = list })
		UIKit.padding(b, 6)
	end
	-- details
	local sel
	for _, e in entries do
		if e.Key == selectedItem then
			sel = e
		end
	end
	if sel then
		UIKit.label(sel.Name, { Size = UDim2.new(1, 0, 0, 26), TextSize = 22, TextColor3 = rarityColor(sel.Def), Parent = detail })
		UIKit.label(describeItem(sel.Def, sel.Inst and sel.Inst.Upgrade or 0, attrs), { Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 1, -80), TextSize = 16, TextYAlignment = Enum.TextYAlignment.Top, Parent = detail })
		-- comparison with equipped
		if sel.Inst and not sel.Equipped and (sel.Def.Kind == "Weapon" or sel.Def.Kind == "Armor") then
			local slot = if sel.Def.Kind == "Weapon" then "Weapon" else sel.Def.Slot
			local cur = p.Equipped[slot] and p.Inventory.Items[p.Equipped[slot]]
			if cur then
				local cdef = Items[cur.Id]
				local delta
				if sel.Def.Kind == "Weapon" then
					delta = Formulas.weaponAttackRating(sel.Def, sel.Inst.Upgrade, attrs).Total - Formulas.weaponAttackRating(cdef, cur.Upgrade, attrs).Total
					delta = ("Attack %+d vs equipped"):format(math.floor(delta))
				else
					delta = ("Defence %+d vs equipped"):format(math.floor((Formulas.armorDefense(sel.Def, sel.Inst.Upgrade)) - (Formulas.armorDefense(cdef, cur.Upgrade))))
				end
				UIKit.label(delta, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -40), Size = UDim2.new(1, 0, 0, 20), TextSize = 16, TextColor3 = T.Accent, Parent = detail })
			end
		end
		local actions = UIKit.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 34), Parent = detail })
		UIKit.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), Parent = actions })
		if sel.Inst then
			if sel.Equipped then
				UIKit.button("Unequip", function()
					act("Unequip", sel.Equipped)
				end, { Size = UDim2.fromOffset(110, 32), Parent = actions })
			elseif sel.Def.Kind ~= "Material" then
				UIKit.button("Equip", function()
					act("Equip", { Uid = sel.Key })
				end, { Size = UDim2.fromOffset(110, 32), Parent = actions })
				if sel.Def.Kind == "Accessory" then
					UIKit.button("Equip (slot 2)", function()
						act("Equip", { Uid = sel.Key, Slot = "Accessory2" })
					end, { Size = UDim2.fromOffset(130, 32), Parent = actions })
				end
			end
		elseif sel.Def.Kind == "Consumable" then
			UIKit.button("Use", function()
				ClientState.Request("UseItem", sel.Key)
			end, { Size = UDim2.fromOffset(110, 32), Parent = actions })
		end
		if context.Menu == "Shop" then
			local price = Formulas.sellPrice(sel.Def)
			if price > 0 and not sel.Equipped then
				UIKit.button(("Sell (%d)"):format(price), function()
					act("Sell", { Key = sel.Key, Amount = 1 })
				end, { Size = UDim2.fromOffset(120, 32), Parent = actions })
			end
		end
	else
		UIKit.label("Select an item to see details.", { Size = UDim2.fromScale(1, 1), TextColor3 = T.Muted, Parent = detail })
	end
	-- build presets
	local presets = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 74), Parent = c })
	local max = if p.HasWardrobePass then GameConfig.Inventory.BuildPresetsWithPass else GameConfig.Inventory.BuildPresetsFree
	UIKit.label(("Build presets (%d slots)"):format(max), { Size = UDim2.new(1, 0, 0, 20), TextSize = 16, TextColor3 = T.Muted, Parent = presets })
	for i = 1, max do
		local has = p.BuildPresets[tostring(i)] ~= nil
		UIKit.button(("Save %d"):format(i), function()
			act("SavePreset", i, "Preset saved.")
		end, { Position = UDim2.fromOffset((i - 1) * 150, 22), Size = UDim2.fromOffset(70, 28), TextSize = 14, Parent = presets })
		UIKit.button(("Load %d"):format(i), function()
			act("LoadPreset", i, "Preset loaded.")
		end, { Position = UDim2.fromOffset((i - 1) * 150 + 74, 22), Size = UDim2.fromOffset(70, 28), TextSize = 14, BackgroundColor3 = if has then T.Panel2 else T.Bg, Parent = presets })
	end
end

Pages.Abilities = function(c)
	local p = profile()
	header(c, "Abilities")
	UIKit.label(("Slot 1: %s     Slot 2: %s"):format(Abilities[p.Abilities.Slot1] and Abilities[p.Abilities.Slot1].Name or "-", Abilities[p.Abilities.Slot2] and Abilities[p.Abilities.Slot2].Name or "-"),
		{ Size = UDim2.new(1, 0, 0, 22), TextSize = 17, Parent = c })
	local list = UIKit.list({ Size = UDim2.new(1, 0, 1, -60), Parent = c }, 6)
	local ids = {}
	for id in p.Abilities.Unlocked do
		table.insert(ids, id)
	end
	table.sort(ids)
	for _, id in ids do
		local def = Abilities[id]
		local r = row(list, 64)
		UIKit.label(("%s  -  %s  (mana %d, stamina %d, cooldown %ds)\n%s"):format(def.Name, def.Type, def.Mana or 0, def.Stamina or 0, def.Cooldown, def.Description),
			{ Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -250, 1, -8), TextSize = 15, Parent = r })
		for i, slot in { "Slot1", "Slot2" } do
			UIKit.button("Slot " .. i, function()
				act("SetAbilitySlot", { Slot = slot, Ability = id })
			end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10 - (2 - i) * 110, 0.5, 0), Size = UDim2.fromOffset(100, 30), Parent = r })
		end
	end
	UIKit.label("Defeat tower guardians to learn more abilities - any build may use any ability.", { Size = UDim2.new(1, 0, 0, 20), TextSize = 14, TextColor3 = T.Muted, Parent = c })
end

local function questProgressText(p, id): string
	local q = Quests[id]
	local o = q.Objective
	local active = p.Quests.Active[id]
	if o.Type == "Kill" or o.Type == "Training" then
		return ("%d / %d"):format(math.min(active and active.Progress or 0, o.Count), o.Count)
	elseif o.Type == "Boss" then
		return if p.Tower.HighestCleared >= o.Floor then "Complete" else ("Floor %d"):format(o.Floor)
	elseif o.Type == "Collect" then
		return ("%d / %d"):format(math.min(p.Inventory.Stacks[o.Item] or 0, o.Count), o.Count)
	end
	return ""
end

Pages.Quests = function(c)
	local p = profile()
	header(c, "Quest Log")
	local list = UIKit.list({ Size = UDim2.new(1, 0, 1, -34), Parent = c }, 6)
	local any = false
	for id in p.Quests.Active do
		any = true
		local q = Quests[id]
		local r = row(list, 56)
		UIKit.label(("%s   [%s]\n%s"):format(q.Name, questProgressText(p, id), q.Description), { Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -140, 1, -8), TextSize = 16, Parent = r })
		UIKit.button("Abandon", function()
			act("AbandonQuest", id)
		end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(110, 30), Parent = r })
	end
	if not any then
		UIKit.label("No active quests. Speak to the people of the Sanctuary.", { Size = UDim2.new(1, 0, 0, 24), TextColor3 = T.Muted, Parent = list })
	end
	local done = 0
	for _ in p.Quests.Completed do
		done += 1
	end
	UIKit.label(("Completed quests: %d"):format(done), { Size = UDim2.new(1, 0, 0, 24), TextColor3 = T.Muted, Parent = list })
end

Pages.Map = function(c)
	local p = profile()
	header(c, "Map of the Fallen Lands")
	local size = 420
	local scale = size / 2100
	local canvas = UIKit.panel({ Size = UDim2.fromOffset(size, size), BackgroundColor3 = Color3.fromRGB(30, 34, 28), Parent = c })
	canvas.ClipsDescendants = true
	local function toMap(x, z)
		return UDim2.fromOffset(size / 2 + x * scale, size / 2 + z * scale)
	end
	for _, r in World.Regions do
		if not r.Hidden or p.Tower.HighestCleared >= (r.RequiresFloor or 0) or p.Discovered.loc_vale then
			local d = r.Radius * 2 * scale
			local f = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = toMap(r.Center[1], r.Center[3]), Size = UDim2.fromOffset(d, d),
				BackgroundColor3 = if r.Safe then Color3.fromRGB(90, 80, 60) else Color3.fromRGB(60, 70, 55), BackgroundTransparency = 0.3, Parent = canvas })
			UIKit.corner(f, 999)
			UIKit.label(r.Name, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(120, 30), TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center, Parent = f })
		end
	end
	local tower = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = toMap(0, 0), Size = UDim2.fromOffset(14, 14), BackgroundColor3 = Color3.fromRGB(200, 60, 50), Parent = canvas })
	UIKit.corner(tower, 999)
	for _, cp in World.Checkpoints do
		local on = p.Checkpoints.Activated[cp.Id]
		local d = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = toMap(cp.Position[1], cp.Position[3]), Size = UDim2.fromOffset(8, 8),
			BackgroundColor3 = if on then Color3.fromRGB(255, 170, 70) else Color3.fromRGB(90, 90, 90), Parent = canvas })
		UIKit.corner(d, 999)
	end
	if p.LostCurrency then
		local l = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = toMap(p.LostCurrency.X, p.LostCurrency.Z), Size = UDim2.fromOffset(10, 10), BackgroundColor3 = Color3.fromRGB(255, 90, 30), Parent = canvas })
		UIKit.corner(l, 999)
	end
	local me = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(10, 10), BackgroundColor3 = Color3.fromRGB(120, 200, 255), Parent = canvas })
	UIKit.corner(me, 999)
	mapDot = me
	MenuController.MapToCanvas = toMap
	UIKit.label("Red: Tower   Orange: kindled shrines   Ember: lost embers   Blue: you", { Size = UDim2.new(1, 0, 0, 22), TextSize = 14, TextColor3 = T.Muted, Parent = c })
end

Pages.Tower = function(c)
	local p = profile()
	header(c, ("Tower of the Fallen  -  %d / 20 cleared"):format(p.Tower.HighestCleared))
	if player:GetAttribute("ArenaFloor") then
		UIKit.button("Leave arena (forfeit)", function()
			act("LeaveArena")
			MenuController.Close()
		end, { Size = UDim2.fromOffset(220, 32), BackgroundColor3 = Color3.fromRGB(90, 30, 30), Parent = c })
	end
	local list = UIKit.list({ Size = UDim2.new(1, 0, 1, -70), Parent = c }, 4)
	for floor = 1, 20 do
		local b = Bosses.List[floor]
		local cleared = p.Tower.HighestCleared >= floor
		local unlocked = p.Tower.HighestCleared >= floor - 1
		local r = row(list, 52)
		local clears = p.Tower.Clears[tostring(floor)] or 0
		UIKit.label(("Floor %d  -  %s%s\n%s  (recommended level %d)"):format(floor, if unlocked then b.Name else "???", if cleared then ("   [cleared x%d]"):format(clears) else "",
			if unlocked then b.Mechanic else "Defeat the previous guardian to reveal this floor.", Formulas.recommendedLevel(floor)),
			{ Position = UDim2.fromOffset(10, 2), Size = UDim2.new(1, -140, 1, -4), TextSize = 14, TextColor3 = if cleared then T.Accent elseif unlocked then T.Text else T.Muted, Parent = r })
		if unlocked then
			UIKit.button(if cleared then "Replay" else "Challenge", function()
				local ok, err = ClientState.Request("EnterFloor", floor)
				notifyResult(ok, err)
				if ok then
					MenuController.Close()
				end
			end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(120, 30), Parent = r })
		end
	end
	UIKit.label("Encounters begin at the Tower Gate. Party leaders bring every member standing at the gate.", { Size = UDim2.new(1, 0, 0, 20), TextSize = 14, TextColor3 = T.Muted, Parent = c })
end

Pages.Party = function(c)
	local party = ClientState.Party
	header(c, "Fellowship")
	UIKit.label("Parties are optional. Bosses gain health per extra member; every member is rewarded individually.", { Size = UDim2.new(1, 0, 0, 22), TextSize = 15, TextColor3 = T.Muted, Parent = c })
	local list = UIKit.list({ Size = UDim2.new(1, 0, 0.45, 0), Parent = c }, 4)
	local isLeader = party.Leader == player.UserId
	if #party.Members == 0 then
		UIKit.label("You are travelling alone.", { Size = UDim2.new(1, 0, 0, 24), Parent = list })
	end
	for _, m in party.Members do
		local r = row(list, 36)
		UIKit.label(("%s%s  -  %s Lv.%d  -  floor %d"):format(m.Name, if m.UserId == party.Leader then " (leader)" else "", m.Class, m.Level, m.Floor),
			{ Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -250, 1, 0), TextSize = 16, Parent = r })
		if isLeader and m.UserId ~= player.UserId then
			UIKit.button("Kick", function()
				act("PartyKick", m.UserId)
			end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -120, 0.5, 0), Size = UDim2.fromOffset(100, 28), Parent = r })
			UIKit.button("Promote", function()
				act("PartyPromote", m.UserId)
			end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(100, 28), Parent = r })
		end
	end
	if #party.Members > 0 then
		UIKit.button("Leave party", function()
			act("PartyLeave")
		end, { Size = UDim2.fromOffset(160, 30), Parent = c })
	end
	UIKit.label("Invite players in this server:", { Size = UDim2.new(1, 0, 0, 22), TextSize = 16, Parent = c })
	local others = UIKit.list({ Size = UDim2.new(1, 0, 0.35, 0), Parent = c }, 4)
	for _, other in Players:GetPlayers() do
		if other ~= player then
			local r = row(others, 34)
			UIKit.label(("%s  Lv.%d"):format(other.DisplayName, other:GetAttribute("Level") or 1), { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -140, 1, 0), TextSize = 16, Parent = r })
			UIKit.button("Invite", function()
				act("PartyInvite", other.UserId, "Invite sent.")
			end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(100, 28), Parent = r })
		end
	end
end

Pages.Achievements = function(c)
	local p = profile()
	local ids = {}
	for id in Achievements do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		local da, db = p.Achievements[a] == true, p.Achievements[b] == true
		if da ~= db then
			return da
		end
		return Achievements[a].Name < Achievements[b].Name
	end)
	local n = 0
	for _ in p.Achievements do
		n += 1
	end
	header(c, ("Achievements  %d / %d"):format(n, #ids))
	local list = UIKit.list({ Size = UDim2.new(1, 0, 1, -34), Parent = c }, 4)
	for _, id in ids do
		local a = Achievements[id]
		local done = p.Achievements[id] == true
		local prog = ""
		if a.Stat and not done then
			prog = ("  (%d / %d)"):format(math.min(p.Stats[a.Stat] or 0, a.Goal), a.Goal)
		end
		local reward = a.Reward and (a.Reward.Title and ("Title: " .. a.Reward.Title) or a.Reward.Cosmetic and ("Cosmetic: " .. Cosmetics[a.Reward.Cosmetic].Name)) or ""
		local r = row(list, 40)
		UIKit.label(("%s%s%s\n%s  %s"):format(if done then "[x] " else "[ ] ", a.Name, prog, a.Description, reward), { Position = UDim2.fromOffset(10, 2), Size = UDim2.new(1, -20, 1, -4), TextSize = 14,
			TextColor3 = if done then T.Accent else T.Text, Parent = r })
	end
end

Pages.Cosmetics = function(c)
	local p = profile()
	header(c, "Wardrobe (cosmetic only - never affects combat)")
	local list = UIKit.list({ Size = UDim2.new(1, 0, 1, -34), Parent = c }, 4)
	for _, slot in { "Aura", "WeaponSkin", "ArmorDye" } do
		UIKit.label(slot, { Size = UDim2.new(1, 0, 0, 22), TextSize = 18, TextColor3 = T.Accent, Parent = list })
		local r0 = row(list, 32)
		UIKit.button("None", function()
			act("EquipCosmetic", { Slot = slot, Id = "" })
		end, { Position = UDim2.fromOffset(6, 2), Size = UDim2.fromOffset(100, 28), Parent = r0 })
		for id, def in Cosmetics do
			if def.Type == slot and p.Cosmetics.Owned[id] then
				local r = row(list, 32)
				local equipped = p.Cosmetics.Equipped[slot] == id
				UIKit.label(def.Name .. (if equipped then "  (equipped)" else ""), { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -140, 1, 0), TextSize = 16, TextColor3 = def.Color, Parent = r })
				UIKit.button("Equip", function()
					act("EquipCosmetic", { Slot = slot, Id = id })
				end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(100, 26), Parent = r })
			end
		end
	end
	UIKit.label("Titles", { Size = UDim2.new(1, 0, 0, 22), TextSize = 18, TextColor3 = T.Accent, Parent = list })
	local titles = {}
	for t in p.Titles do
		table.insert(titles, t)
	end
	table.sort(titles)
	table.insert(titles, 1, "")
	for _, t in titles do
		local r = row(list, 32)
		UIKit.label(if t == "" then "(no title)" else t, { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -140, 1, 0), TextSize = 16, Parent = r })
		UIKit.button(if p.ActiveTitle == t then "Active" else "Use", function()
			act("SetTitle", t)
		end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(100, 26), Parent = r })
	end
	UIKit.label("Store", { Size = UDim2.new(1, 0, 0, 22), TextSize = 18, TextColor3 = T.Accent, Parent = list })
	local anyProduct = false
	for key, prod in Products.DevProducts do
		if prod.Id ~= 0 then
			anyProduct = true
			local r = row(list, 32)
			UIKit.label(("%s  -  R$ %d"):format(prod.Name, prod.PriceRobux), { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -140, 1, 0), TextSize = 16, Parent = r })
			UIKit.button("Buy", function()
				act("PromptProduct", key)
			end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(100, 26), Parent = r })
		end
	end
	for key, pass in Products.GamePasses do
		if pass.Id ~= 0 then
			anyProduct = true
			local r = row(list, 40)
			UIKit.label(("%s  -  R$ %d\n%s"):format(pass.Name, pass.PriceRobux, pass.Description), { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -140, 1, 0), TextSize = 14, Parent = r })
			UIKit.button(if p.HasWardrobePass then "Owned" else "Buy", function()
				act("PromptPass", key)
			end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(100, 26), Parent = r })
		end
	end
	if not anyProduct then
		UIKit.label("The store is not open yet.", { Size = UDim2.new(1, 0, 0, 22), TextSize = 15, TextColor3 = T.Muted, Parent = list })
	end
end

local SETTINGS_NUMERIC = {
	{ Key = "CameraSensitivity", Name = "Camera sensitivity", Step = 0.1, Min = 0.2, Max = 3 },
	{ Key = "MusicVolume", Name = "Music volume", Step = 0.1, Min = 0, Max = 1 },
	{ Key = "SfxVolume", Name = "Effects volume", Step = 0.1, Min = 0, Max = 1 },
	{ Key = "TextScale", Name = "Interface scale", Step = 0.05, Min = 0.75, Max = 1.5 },
}
local SETTINGS_TOGGLES = {
	{ Key = "ShowDamageNumbers", Name = "Damage numbers" },
	{ Key = "HighContrastTelegraphs", Name = "High-contrast attack telegraphs" },
	{ Key = "ReducedEffects", Name = "Reduced visual effects" },
	{ Key = "ScreenShake", Name = "Screen shake" },
	{ Key = "MouseLock", Name = "Combat mouse lock (desktop)" },
	{ Key = "ShowControls", Name = "Show controls legend" },
}

Pages.Settings = function(c)
	local s = ClientState.Settings
	header(c, "Settings")
	local list = UIKit.list({ Size = UDim2.new(1, 0, 1, -80), Parent = c }, 4)
	for _, n in SETTINGS_NUMERIC do
		local r = row(list, 34)
		UIKit.label(("%s: %.2f"):format(n.Name, s[n.Key] or 1), { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -120, 1, 0), TextSize = 16, Parent = r })
		UIKit.button("-", function()
			s[n.Key] = math.clamp((s[n.Key] or 1) - n.Step, n.Min, n.Max)
			MenuController.ApplySettings()
		end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -54, 0.5, 0), Size = UDim2.fromOffset(36, 26), Parent = r })
		UIKit.button("+", function()
			s[n.Key] = math.clamp((s[n.Key] or 1) + n.Step, n.Min, n.Max)
			MenuController.ApplySettings()
		end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(36, 26), Parent = r })
	end
	for _, tg in SETTINGS_TOGGLES do
		local r = row(list, 34)
		UIKit.label(tg.Name, { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -120, 1, 0), TextSize = 16, Parent = r })
		UIKit.button(if s[tg.Key] then "On" else "Off", function()
			s[tg.Key] = not s[tg.Key]
			MenuController.ApplySettings()
		end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(80, 26), Parent = r })
	end
	UIKit.button("Save settings", function()
		act("SaveSettings", s, "Settings saved.")
	end, { Size = UDim2.fromOffset(180, 32), Parent = c })
end

-- ===================================================================== NPC pages
Pages.Shop = function(c)
	local p = profile()
	local shop = Shops[context.Shop]
	header(c, ("%s  -  %d Embers"):format(shop.Name, p.Currency))
	UIKit.label("Selling: open the Inventory tab while talking to a merchant.", { Size = UDim2.new(1, 0, 0, 20), TextSize = 14, TextColor3 = T.Muted, Parent = c })
	local list = UIKit.list({ Size = UDim2.new(1, 0, 1, -56), Parent = c }, 4)
	for _, entry in shop.Stock do
		local def = Items[entry.Item]
		local locked = (entry.RequiresFloor or 0) > p.Tower.HighestCleared
		local r = row(list, 52)
		local owned = p.Inventory.Stacks[entry.Item]
		if not owned then
			owned = 0
			for _, inst in p.Inventory.Items do
				if inst.Id == entry.Item then
					owned += 1
				end
			end
		end
		local limit = ""
		if entry.Limit then
			limit = ("  (limit %d, bought %d)"):format(entry.Limit, p.ShopPurchases[context.Shop .. ":" .. entry.Item] or 0)
		end
		UIKit.label(("%s  -  %d%s   owned %d\n%s"):format(def.Name, entry.Price, limit, owned, if locked then ("Unlocks after tower floor %d"):format(entry.RequiresFloor) else (describeItem(def, 0, p.Derived.Attributes):match("[^\n]*\n?([^\n]*)") or "")),
			{ Position = UDim2.fromOffset(10, 2), Size = UDim2.new(1, -240, 1, -4), TextSize = 14, TextColor3 = if locked then T.Muted else rarityColor(def), Parent = r })
		if not locked then
			UIKit.button("Buy 1", function()
				act("Buy", { Shop = context.Shop, Item = entry.Item, Quantity = 1 })
			end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -116, 0.5, 0), Size = UDim2.fromOffset(100, 28), Parent = r })
			if def.Stackable then
				UIKit.button("Buy 5", function()
					act("Buy", { Shop = context.Shop, Item = entry.Item, Quantity = 5 })
				end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(100, 28), Parent = r })
			end
		end
	end
end

Pages.Blacksmith = function(c)
	local p = profile()
	header(c, ("Doran's Forge  -  %d Embers"):format(p.Currency))
	local body = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -34), Parent = c })
	local list = UIKit.list({ Size = UDim2.new(0.5, -4, 1, 0), Parent = body }, 4)
	local detail = UIKit.panel({ Position = UDim2.new(0.5, 4, 0, 0), Size = UDim2.new(0.5, -4, 1, 0), BackgroundColor3 = T.Bg, Parent = body })
	UIKit.padding(detail, 10)
	local entries = {}
	for uid, inst in p.Inventory.Items do
		local def = Items[inst.Id]
		if def.Kind == "Weapon" or def.Kind == "Shield" or def.Kind == "Armor" then
			table.insert(entries, { Uid = uid, Inst = inst, Def = def })
		end
	end
	table.sort(entries, function(a, b)
		return itemName(a.Inst) < itemName(b.Inst)
	end)
	for _, e in entries do
		UIKit.button(itemName(e.Inst), function()
			selectedItem = e.Uid
			MenuController.Render()
		end, { Size = UDim2.new(1, -8, 0, 30), TextSize = 15, TextColor3 = rarityColor(e.Def), Parent = list })
	end
	if selectedItem and p.Inventory.Items[selectedItem] then
		local uid = selectedItem
		local inst = p.Inventory.Items[uid]
		UIKit.label(itemName(inst), { Size = UDim2.new(1, 0, 0, 26), TextSize = 22, TextColor3 = rarityColor(Items[inst.Id]), Parent = detail })
		local info = UIKit.label("Inspecting...", { Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 1, -80), TextSize = 17, TextYAlignment = Enum.TextYAlignment.Top, Parent = detail })
		task.spawn(function()
			local ok, preview = ClientState.Request("UpgradePreview", uid)
			if not info.Parent then
				return
			end
			if not ok then
				info.Text = ClientState.ErrorText(preview)
				return
			end
			local cost = preview.Cost
			local have = p.Inventory.Stacks[cost.Material] or 0
			info.Text = ("Upgrade +%d  ->  +%d\n\n%s: %d  ->  %d\n\nCost: %d Embers + %s x%d (you have %d)"):format(
				preview.From, preview.To, if Items[inst.Id].Kind == "Weapon" then "Attack" elseif Items[inst.Id].Kind == "Shield" then "Stability" else "Defence",
				math.floor(preview.Before or 0), math.floor(preview.After or 0), cost.Currency, Items[cost.Material].Name, cost.Amount, have)
			UIKit.button("Confirm upgrade", function()
				act("Upgrade", uid)
			end, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromOffset(180, 34), Parent = detail })
		end)
	else
		UIKit.label("Select equipment to see upgrade costs and results before confirming.", { Size = UDim2.fromScale(1, 1), TextColor3 = T.Muted, Parent = detail })
	end
end

Pages.Quest = function(c)
	local p = profile()
	header(c, context.Name or "Quests")
	local list = UIKit.list({ Size = UDim2.new(1, 0, 1, -34), Parent = c }, 6)
	for _, id in context.Quests or {} do
		local q = Quests[id]
		local status
		if p.Quests.Completed[id] then
			status = "Completed"
		elseif p.Quests.Active[id] then
			status = "Active"
		else
			status = "Available"
			for _, req in q.Requires do
				if not p.Quests.Completed[req] then
					status = "Locked"
				end
			end
		end
		local r = row(list, 70)
		local rewards = {}
		if q.Rewards.Xp then
			table.insert(rewards, q.Rewards.Xp .. " XP")
		end
		if q.Rewards.Currency then
			table.insert(rewards, q.Rewards.Currency .. " Embers")
		end
		for item, n in q.Rewards.Items or {} do
			table.insert(rewards, Items[item].Name .. " x" .. n)
		end
		if q.Rewards.Title then
			table.insert(rewards, "Title: " .. q.Rewards.Title)
		end
		UIKit.label(("%s  [%s]%s\n%s\nRewards: %s"):format(q.Name, status, if status == "Active" then "  " .. questProgressText(p, id) else "", if status == "Locked" then "Complete earlier tasks first." else q.Description, table.concat(rewards, ", ")),
			{ Position = UDim2.fromOffset(10, 2), Size = UDim2.new(1, -140, 1, -4), TextSize = 14, TextColor3 = if status == "Locked" then T.Muted else T.Text, Parent = r })
		if status == "Available" then
			UIKit.button("Accept", function()
				act("AcceptQuest", id)
			end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(110, 30), Parent = r })
		elseif status == "Active" then
			UIKit.button("Turn in", function()
				act("TurnInQuest", id)
			end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(110, 30), Parent = r })
		end
	end
end

Pages.Shrine = function(c)
	local p = profile()
	local name = context.ShrineId
	for _, cp in World.Checkpoints do
		if cp.Id == context.ShrineId then
			name = cp.Name
		end
	end
	header(c, name)
	UIKit.label("You rest by the embers. Health, stamina, mana and flask charges are restored, and you will return here when you fall.", { Size = UDim2.new(1, 0, 0, 44), TextSize = 16, Parent = c })
	UIKit.button(("Level up (%d point%s)"):format(p.UnspentPoints, p.UnspentPoints == 1 and "" or "s"), function()
		MenuController.Show("Character")
	end, { Size = UDim2.fromOffset(220, 34), Parent = c })
	UIKit.label("Travel to a kindled shrine:", { Size = UDim2.new(1, 0, 0, 24), TextSize = 17, TextColor3 = T.Accent, Parent = c })
	local list = UIKit.list({ Size = UDim2.new(1, 0, 1, -140), Parent = c }, 4)
	for _, cp in World.Checkpoints do
		if p.Checkpoints.Activated[cp.Id] and cp.Id ~= context.ShrineId then
			UIKit.button(cp.Name, function()
				local ok, err = ClientState.Request("Travel", cp.Id)
				notifyResult(ok, err)
				if ok then
					MenuController.Close()
				end
			end, { Size = UDim2.new(1, -8, 0, 32), Parent = list })
		end
	end
end

local TUTORIAL = {
	"Welcome to the Fallen Sanctuary. The tower above us holds twenty guardians. Defeat them, one floor at a time.",
	"Combat is deliberate: attacks, dodges, blocks and parries cost STAMINA. Watch the green bar - an exhausted fighter cannot roll.",
	"Enemy attacks are telegraphed on the ground. GOLD markings can be parried (F), WHITE can be blocked (RMB), RED must be avoided. Dodging (Q) grants a moment of invulnerability.",
	"Lock on with T (or the Lock button) to keep your target in view. Heavy attacks (hold R) break poise; a staggered foe takes a devastating riposte.",
	"Your Ember Flask (H) heals. Rest at Ember Shrines to refill it, set your respawn point and spend attribute points.",
	"When you die you drop your carried Embers where you fell. Return and touch the glowing marker to reclaim them - die again first and they are lost.",
	"Merchants sell gear, the blacksmith upgrades it, and the Training Grounds east of here sharpen your skills. Party up at the Fellowship Board if you want company.",
}

Pages.Tutorial = function(c)
	context.Page = context.Page or 1
	header(c, "Ilya the Guide")
	UIKit.label(TUTORIAL[context.Page], { Size = UDim2.new(1, 0, 0, 120), TextSize = 20, Parent = c })
	UIKit.label(("%d / %d"):format(context.Page, #TUTORIAL), { Size = UDim2.new(1, 0, 0, 20), TextColor3 = T.Muted, Parent = c })
	UIKit.button(if context.Page < #TUTORIAL then "Next" else "Farewell", function()
		if context.Page < #TUTORIAL then
			context.Page += 1
			MenuController.Render()
		else
			MenuController.Close()
		end
	end, { Size = UDim2.fromOffset(160, 34), Parent = c })
end

-- ===================================================================== window
local function buildWindow()
	window = UIKit.panel({ Name = "Menu", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0.9, 0, 0.85, 0), BackgroundColor3 = T.Bg, Visible = false, Parent = gui })
	UIKit.new("UISizeConstraint", { MaxSize = Vector2.new(980, 620), Parent = window })
	titleLabel = UIKit.label("", { Position = UDim2.fromOffset(16, 6), Size = UDim2.new(1, -80, 0, 34), TextSize = 28, TextColor3 = T.Accent, Parent = window })
	UIKit.button("X", function()
		MenuController.Close()
	end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 8), Size = UDim2.fromOffset(36, 32), Parent = window })
	tabBar = UIKit.list({ Position = UDim2.fromOffset(10, 48), Size = UDim2.new(0, 150, 1, -58), Parent = window }, 4)
	content = UIKit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(170, 48), Size = UDim2.new(1, -184, 1, -58), Parent = window })
	UIKit.new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = content })
	for i, name in MAIN_TABS do
		local b = UIKit.button(name, function()
			context = {}
			selectedItem = nil
			MenuController.Show(name)
		end, { Size = UDim2.new(1, -8, 0, 34), LayoutOrder = i, Parent = tabBar })
		b.Name = name
	end
end

function MenuController.Render()
	if not window.Visible or not profile() then
		return
	end
	UIKit.clear(content)
	titleLabel.Text = if context.Menu then (context.Name or currentPage) else currentPage
	for _, b in tabBar:GetChildren() do
		if b:IsA("TextButton") then
			b.BackgroundColor3 = if b.Name == currentPage then T.Border else T.Panel2
		end
	end
	local page = Pages[currentPage]
	if page then
		local ok, err = pcall(page, content)
		if not ok then
			warn("[Menu] render error: " .. tostring(err))
		end
	end
end

function MenuController.Show(page: string)
	currentPage = page
	window.Visible = true
	InputController.SetMenuOpen(true)
	MenuController.Render()
	if UserInputService.GamepadEnabled then
		local first = tabBar:FindFirstChild(page) or tabBar:FindFirstChildWhichIsA("TextButton")
		GuiService.SelectedObject = first
	end
end

function MenuController.Close()
	window.Visible = false
	context = {}
	InputController.SetMenuOpen(false)
	GuiService.SelectedObject = nil
end

function MenuController.Toggle()
	if classOverlay then
		return
	end
	if window.Visible then
		MenuController.Close()
	else
		MenuController.Show(currentPage ~= "" and Pages[currentPage] and not table.find({ "Shop", "Blacksmith", "Quest", "Shrine", "Tutorial" }, currentPage) and currentPage or "Character")
	end
end

function MenuController.ApplySettings()
	local s = ClientState.Settings
	if not s then
		return
	end
	AudioController.ApplySettings(s)
	local cb = MenuController.OnSettings
	if cb then
		cb(s)
	end
	MenuController.Render()
end

-- ===================================================================== class selection
local function showClassSelect()
	if classOverlay then
		return
	end
	InputController.SetMenuOpen(true)
	local overlay = UIKit.new("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.25, Size = UDim2.fromScale(1, 1), Parent = gui })
	classOverlay = overlay
	UIKit.label("TOWER OF THE FALLEN", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 30), Size = UDim2.fromOffset(800, 60), TextSize = 52, TextColor3 = T.Accent, TextXAlignment = Enum.TextXAlignment.Center, Parent = overlay })
	UIKit.label("Choose who you were before the fall. Your class shapes where you begin - never what you may become.", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 92), Size = UDim2.fromOffset(820, 30), TextSize = 19, TextXAlignment = Enum.TextXAlignment.Center, Parent = overlay })
	local grid = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 130), Size = UDim2.new(0.94, 0, 0, 230), BackgroundTransparency = 1, Parent = overlay })
	UIKit.new("UIGridLayout", { CellSize = UDim2.new(1 / 3, -8, 0.5, -6), CellPadding = UDim2.fromOffset(8, 8), Parent = grid })
	local detail = UIKit.panel({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 370), Size = UDim2.new(0.94, 0, 0, 220), BackgroundColor3 = T.Bg, Parent = overlay })
	UIKit.padding(detail, 12)
	local info = UIKit.label("Select a class.", { Size = UDim2.new(1, 0, 1, -44), TextSize = 17, TextYAlignment = Enum.TextYAlignment.Top, Parent = detail })
	local confirm
	local function select(name)
		local c = Classes[name]
		local attrs = {}
		for _, a in GameConfig.Attributes.List do
			table.insert(attrs, ("%s %d"):format(a:sub(1, 3), c.Attributes[a]))
		end
		local abil = {}
		for _, id in c.Abilities do
			table.insert(abil, ("%s%s"):format(Abilities[id].Name, if Abilities[id].UnlockLevel > 1 then (" (level %d)"):format(Abilities[id].UnlockLevel) else ""))
		end
		info.Text = ("%s  -  %s\n%s\n\nAttributes: %s\nStarting weapon: %s%s\nAbilities: %s"):format(
			c.Name, c.Playstyle, c.Description, table.concat(attrs, "  "), Items[c.Loadout.Weapon].Name,
			if c.Loadout.Offhand then " + " .. Items[c.Loadout.Offhand].Name else "", table.concat(abil, ", "))
		if confirm then
			confirm:Destroy()
		end
		confirm = UIKit.button("Begin as " .. c.Name, function()
			local ok, err = ClientState.Request("ChooseClass", name)
			if ok then
				overlay:Destroy()
				classOverlay = nil
				InputController.SetMenuOpen(false)
			else
				HUD.Toast(ClientState.ErrorText(err), "Error")
			end
		end, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1), Size = UDim2.fromOffset(220, 38), Parent = detail })
	end
	for _, name in Classes.Order do
		local c = Classes[name]
		local card = UIKit.button("", function()
			select(name)
		end, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.Panel, Parent = grid })
		UIKit.label(c.Name, { Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 0, 30), TextSize = 26, TextColor3 = c.Color, Parent = card })
		UIKit.label(c.Playstyle, { Position = UDim2.fromOffset(12, 38), Size = UDim2.new(1, -24, 0, 22), TextSize = 16, TextColor3 = T.Muted, Parent = card })
	end
	select(Classes.Order[1])
end

-- ===================================================================== init
function MenuController.Init(deps)
	UIKit = deps.UIKit
	ClientState = deps.ClientState
	InputController = deps.InputController
	HUD = deps.HUDController
	AudioController = deps.AudioController
	T = UIKit.Theme
	gui = UIKit.new("ScreenGui", { Name = "TotfMenu", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 5, Parent = player:WaitForChild("PlayerGui") })
	UIKit.new("UIScale", { Name = "Scale", Parent = gui })
	buildWindow()

	ClientState.Changed:Connect(function(p)
		if p.Class == "" then
			showClassSelect()
		elseif classOverlay then
			classOverlay:Destroy()
			classOverlay = nil
			InputController.SetMenuOpen(false)
		end
		local scale = gui:FindFirstChild("Scale") :: UIScale
		scale.Scale = math.clamp(p.Settings.TextScale or 1, 0.75, 1.5)
		MenuController.Render()
	end)
	ClientState.PartyChanged:Connect(function()
		if currentPage == "Party" then
			MenuController.Render()
		end
	end)

	Net.event("OpenUI").OnClientEvent:Connect(function(payload)
		context = payload
		selectedItem = nil
		local map = { Shop = "Shop", Blacksmith = "Blacksmith", Quest = "Quest", Shrine = "Shrine", Tower = "Tower", Party = "Party", Wardrobe = "Cosmetics", Tutorial = "Tutorial" }
		local page = map[payload.Menu]
		if page then
			if page == "Tower" or page == "Party" or page == "Cosmetics" then
				context = {}
			end
			MenuController.Show(page)
		end
	end)

	Net.event("Party").OnClientEvent:Connect(function(payload)
		if payload.Type ~= "Invite" then
			return
		end
		local pop = UIKit.panel({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 120), Size = UDim2.fromOffset(380, 110), BackgroundColor3 = T.Bg, Parent = gui })
		UIKit.padding(pop, 10)
		UIKit.label(payload.FromName .. " invites you to their party.", { Size = UDim2.new(1, 0, 0, 40), TextSize = 18, Parent = pop })
		UIKit.button("Accept", function()
			act("PartyRespond", true, "Joined the party.")
			pop:Destroy()
		end, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromOffset(150, 32), Parent = pop })
		UIKit.button("Decline", function()
			ClientState.Request("PartyRespond", false)
			pop:Destroy()
		end, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1), Size = UDim2.fromOffset(150, 32), Parent = pop })
		task.delay(GameConfig.Party.InviteExpiry, function()
			if pop.Parent then
				pop:Destroy()
			end
		end)
	end)

	-- live map dot
	RunService.RenderStepped:Connect(function()
		local toMap = MenuController.MapToCanvas
		if window.Visible and currentPage == "Map" and mapDot and mapDot.Parent and toMap then
			local r = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if r then
				mapDot.Position = toMap((r :: BasePart).Position.X, (r :: BasePart).Position.Z)
			end
		end
	end)
end

return MenuController
