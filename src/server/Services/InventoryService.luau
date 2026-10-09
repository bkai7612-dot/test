--[[
	InventoryService
	Equipment, consumable use (outside combat actions), selling, blacksmith upgrades,
	build presets and the held-weapon visual. All operations go through InventoryCore,
	which validates before mutating.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Items = require(Shared.Config.Items)
local Core = script.Parent.Parent.Core
local InventoryCore = require(Core.InventoryCore)
local CombatCore = require(Core.CombatCore)
local QuestCore = require(Core.QuestCore)
local EntityModels = require(script.Parent.EntityModels)

local InventoryService = {}
local S

function InventoryService.Init(services)
	S = services
end

-- Rebuilds the held weapon Tool to match the equipped weapon and weapon skin.
function InventoryService.ApplyWeaponVisual(player: Player)
	local rt = S.PlayerStateService.Get(player)
	if not rt or not rt.Character or not rt.Humanoid then
		return
	end
	for _, child in rt.Character:GetChildren() do
		if child:IsA("Tool") then
			child:Destroy()
		end
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		backpack:ClearAllChildren()
	end
	local uid = rt.Profile.Equipped.Weapon
	local inst = uid and rt.Profile.Inventory.Items[uid]
	local skin = rt.Profile.Cosmetics.Equipped.WeaponSkin
	local tool = EntityModels.buildWeaponTool(inst and inst.Id, if skin ~= "" then skin else nil)
	if tool then
		tool.Parent = backpack or rt.Character
		rt.Humanoid:EquipTool(tool)
	end
end

local function canChangeGear(rt): (boolean, string?)
	local c = rt.Combat
	if not c or c.Dead then
		return false, "Dead"
	end
	if not CombatCore.canAct(c, workspace:GetServerTimeNow(), 0.05) then
		return false, "Busy"
	end
	return true, nil
end

local function afterGearChange(player: Player)
	S.PlayerStateService.RecomputeStats(player)
	InventoryService.ApplyWeaponVisual(player)
	S.PlayerStateService.Sync(player)
end

function InventoryService.Start()
	local R = S.RequestService

	S.PlayerStateService.CharacterReady:Connect(function(player)
		task.defer(InventoryService.ApplyWeaponVisual, player)
	end)

	R.Register("Equip", function(player, rt, payload)
		if type(payload) ~= "table" then
			return false, "BadRequest"
		end
		local ok, err = canChangeGear(rt)
		if not ok then
			return false, err
		end
		local okEq, res = InventoryCore.equip(rt.Profile, payload.Uid, payload.Slot)
		if not okEq then
			return false, res
		end
		afterGearChange(player)
		return true, res
	end)

	R.Register("Unequip", function(player, rt, slot)
		local ok, err = canChangeGear(rt)
		if not ok then
			return false, err
		end
		local okU, res = InventoryCore.unequip(rt.Profile, slot)
		if not okU then
			return false, res
		end
		afterGearChange(player)
		return true, res
	end)

	R.Register("Sell", function(player, rt, payload)
		if type(payload) ~= "table" then
			return false, "BadRequest"
		end
		if not S.InteractionService.IsNearRole(player, "Shop") then
			return false, "NotAtMerchant"
		end
		local ok, res = InventoryCore.sell(rt.Profile, payload.Key, payload.Amount)
		if not ok then
			return false, res
		end
		S.PlayerStateService.Sync(player)
		S.PlayerStateService.PushVitals(player)
		return true, res
	end)

	R.Register("UpgradePreview", function(player, rt, uid)
		if type(uid) ~= "string" then
			return false, "BadRequest"
		end
		local preview, err = InventoryCore.upgradePreview(rt.Profile, uid, rt.Stats.Attributes)
		if not preview then
			return false, err
		end
		return true, preview
	end)

	R.Register("Upgrade", function(player, rt, uid)
		if not S.InteractionService.IsNearRole(player, "Blacksmith") then
			return false, "NotAtBlacksmith"
		end
		local ok, res = InventoryCore.upgrade(rt.Profile, uid, rt.Stats.Attributes)
		if not ok then
			return false, res
		end
		local inst = rt.Profile.Inventory.Items[uid]
		S.NotifyService.Toast(player, ("%s upgraded to +%d"):format(Items[inst.Id].Name, inst.Upgrade), "Reward")
		S.PlayerStateService.RecomputeStats(player)
		S.ProgressionService.EvaluateAchievements(player)
		for qid in rt.Profile.Quests.Active do
			if QuestCore.isComplete(rt.Profile, qid) then
				S.NotifyService.Toast(player, "Quest ready to turn in.", "Quest")
			end
		end
		S.PlayerStateService.Sync(player)
		S.PlayerStateService.PushVitals(player)
		task.spawn(S.DataService.Save, player)
		return true, res
	end)

	-- Consumables usable from the inventory menu go through the combat path (cooldowns, locks)
	R.Register("UseItem", function(player, rt, itemId)
		S.CombatService.UseItemFromMenu(player, itemId)
		return true, itemId
	end)

	R.Register("SavePreset", function(player, rt, index)
		local max = if rt.HasWardrobePass then GameConfig.Inventory.BuildPresetsWithPass else GameConfig.Inventory.BuildPresetsFree
		if type(index) ~= "number" or index ~= index or index < 1 or index > max or math.floor(index) ~= index then
			return false, "InvalidSlot"
		end
		rt.Profile.BuildPresets[tostring(index)] = {
			Equipped = table.clone(rt.Profile.Equipped),
			Slot1 = rt.Profile.Abilities.Slot1,
			Slot2 = rt.Profile.Abilities.Slot2,
		}
		S.PlayerStateService.Sync(player)
		return true, index
	end)

	R.Register("LoadPreset", function(player, rt, index)
		local preset = type(index) == "number" and rt.Profile.BuildPresets[tostring(index)]
		if not preset then
			return false, "EmptySlot"
		end
		local ok, err = canChangeGear(rt)
		if not ok then
			return false, err
		end
		if rt.Encounter then
			return false, "InCombat"
		end
		-- equip each still-owned item; silently skip anything sold since
		for slot, uid in preset.Equipped do
			if rt.Profile.Inventory.Items[uid] then
				InventoryCore.equip(rt.Profile, uid, slot)
			end
		end
		for _, slot in { "Head", "Chest", "Hands", "Feet", "Offhand", "Accessory1", "Accessory2", "Weapon" } do
			if preset.Equipped[slot] == nil then
				rt.Profile.Equipped[slot] = nil
			end
		end
		for _, s in { "Slot1", "Slot2" } do
			local id = preset[s]
			if id == "" or rt.Profile.Abilities.Unlocked[id] then
				rt.Profile.Abilities[s] = id
			end
		end
		afterGearChange(player)
		return true, index
	end)
end

return InventoryService
