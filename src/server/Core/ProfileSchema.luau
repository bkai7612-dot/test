--[[
	ProfileSchema
	Default player data, migrations and validation/reconciliation.

	reconcile(data) never throws and never resets progress wholesale: it fills missing fields,
	clamps out-of-range numbers, drops references to items that no longer exist and records
	every correction in the returned `corrections` list so problems are visible in logs.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Items = require(Shared.Config.Items)
local Abilities = require(Shared.Config.Abilities)
local Classes = require(Shared.Config.Classes)

local ProfileSchema = {}

function ProfileSchema.defaultAttributes()
	local attrs = {}
	for _, name in GameConfig.Attributes.List do
		attrs[name] = 10
	end
	return attrs
end

function ProfileSchema.default()
	return {
		DataVersion = GameConfig.DataVersion,
		CreatedAt = 0,
		LastSaved = 0,
		Class = "",
		Level = 1,
		Xp = 0,
		UnspentPoints = 0,
		Attributes = ProfileSchema.defaultAttributes(),
		TrainingBonus = {},
		TrainingPoints = {},
		TrainingDaily = { Day = 0, Points = 0 },
		TrainingCooldowns = {},
		Currency = GameConfig.Currency.StartingAmount,
		Inventory = { Items = {}, Stacks = {}, NextUid = 1 },
		Equipped = {},
		Abilities = { Unlocked = {}, Slot1 = "", Slot2 = "" },
		Flask = { MaxCharges = GameConfig.Flask.BaseCharges, Charges = GameConfig.Flask.BaseCharges },
		Tower = { HighestCleared = 0, Clears = {}, RewardedEncounters = {} },
		Checkpoints = { Activated = { sanctuary = true }, Last = "sanctuary" },
		Discovered = {},
		OpenedChests = {},
		Quests = { Active = {}, Completed = {} },
		Stats = {},
		KillsByEnemy = {},
		Achievements = {},
		Titles = {},
		ActiveTitle = "",
		Cosmetics = { Owned = { dye_midnight = true }, Equipped = { Aura = "", WeaponSkin = "", ArmorDye = "" } },
		Settings = {
			CameraSensitivity = 1,
			MusicVolume = 0.5,
			SfxVolume = 0.8,
			ReducedEffects = false,
			ShowDamageNumbers = true,
			HighContrastTelegraphs = false,
			TextScale = 1,
			LockOnToggle = true,
			ScreenShake = true,
			MouseLock = true,
			ShowControls = true,
		},
		LostCurrency = nil,
		ShopPurchases = {},
		Purchases = { ProcessedReceipts = {}, Products = {} },
		BuildPresets = {},
		RedeemedCodes = {},
		Admin = { Granted = false, GodMode = false },
		Corrections = {},
	}
end

-- ===================================================================== Migrations
-- Each migration upgrades data FROM version `n` to `n + 1`.
ProfileSchema.Migrations = {
	[1] = function(data)
		-- v1 stored currency as `Gold` and tower progress as a bare number.
		if data.Gold ~= nil and data.Currency == nil then
			data.Currency = data.Gold
		end
		data.Gold = nil
		if type(data.Tower) == "number" then
			data.Tower = { HighestCleared = data.Tower, Clears = {}, RewardedEncounters = {} }
		end
		return data
	end,
}

local function isFiniteNumber(v)
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function note(corrections, msg)
	table.insert(corrections, msg)
end

-- Fill missing keys (recursively for plain tables) from defaults; fix mismatched primitive types.
local function fill(target, defaults, path, corrections)
	for key, dv in defaults do
		local tv = target[key]
		if tv == nil then
			if type(dv) == "table" then
				target[key] = table.clone(dv)
				-- deep-copy nested defaults
				fill(target[key], dv, path .. "." .. key, {})
			else
				target[key] = dv
			end
		elseif type(dv) == "table" then
			if type(tv) ~= "table" then
				note(corrections, "type fix " .. path .. "." .. key)
				target[key] = table.clone(dv)
				fill(target[key], dv, path .. "." .. key, {})
			elseif next(dv) ~= nil then
				fill(tv, dv, path .. "." .. key, corrections)
			end
		elseif type(tv) ~= type(dv) then
			note(corrections, "type fix " .. path .. "." .. key)
			target[key] = dv
		end
	end
end

local function clampNumber(container, key, lo, hi, corrections, path)
	local v = container[key]
	if not isFiniteNumber(v) then
		note(corrections, "invalid number " .. path .. "." .. key)
		container[key] = lo
		return
	end
	local c = math.clamp(math.floor(v), lo, hi)
	if c ~= v then
		note(corrections, ("clamped %s.%s %s -> %s"):format(path, key, tostring(v), tostring(c)))
		container[key] = c
	end
end

function ProfileSchema.reconcile(data)
	local corrections = {}
	if type(data) ~= "table" then
		return ProfileSchema.default(), { "profile was not a table; created default" }
	end

	-- migrations
	local version = isFiniteNumber(data.DataVersion) and data.DataVersion or 1
	while version < GameConfig.DataVersion do
		local migrate = ProfileSchema.Migrations[version]
		if migrate then
			data = migrate(data)
			note(corrections, "migrated v" .. version .. " -> v" .. (version + 1))
		end
		version += 1
	end
	data.DataVersion = GameConfig.DataVersion

	fill(data, ProfileSchema.default(), "Profile", corrections)
	data.Corrections = {} -- runtime only, rebuilt each load

	-- class
	if data.Class ~= "" and not Classes[data.Class] then
		note(corrections, "unknown class " .. tostring(data.Class))
		data.Class = ""
	end

	-- numbers
	clampNumber(data, "Level", 1, GameConfig.Level.Max, corrections, "Profile")
	clampNumber(data, "Xp", 0, 1e12, corrections, "Profile")
	clampNumber(data, "UnspentPoints", 0, GameConfig.Level.Max * GameConfig.Level.PointsPerLevel, corrections, "Profile")
	clampNumber(data, "Currency", 0, GameConfig.Currency.MaxCarried, corrections, "Profile")
	for _, name in GameConfig.Attributes.List do
		clampNumber(data.Attributes, name, GameConfig.Attributes.Min, GameConfig.Attributes.Max, corrections, "Attributes")
		if data.TrainingBonus[name] ~= nil then
			clampNumber(data.TrainingBonus, name, 0, GameConfig.Training.MaxTrainingBonusPerAttribute, corrections, "TrainingBonus")
		end
	end
	-- drop unknown attribute keys
	for k in data.Attributes do
		if not table.find(GameConfig.Attributes.List, k) then
			data.Attributes[k] = nil
			note(corrections, "removed attribute " .. tostring(k))
		end
	end
	clampNumber(data.Flask, "MaxCharges", GameConfig.Flask.BaseCharges, GameConfig.Flask.MaxCharges, corrections, "Flask")
	clampNumber(data.Flask, "Charges", 0, data.Flask.MaxCharges, corrections, "Flask")
	clampNumber(data.Tower, "HighestCleared", 0, GameConfig.Tower.Floors, corrections, "Tower")
	clampNumber(data.Inventory, "NextUid", 1, 1e9, corrections, "Inventory")

	-- inventory instances
	local itemCount = 0
	for uid, inst in data.Inventory.Items do
		if type(uid) ~= "string" or type(inst) ~= "table" or type(inst.Id) ~= "string" or not Items[inst.Id] or Items[inst.Id].Stackable then
			note(corrections, "removed invalid item " .. tostring(uid))
			data.Inventory.Items[uid] = nil
		else
			itemCount += 1
			if not isFiniteNumber(inst.Upgrade) then
				inst.Upgrade = 0
			end
			inst.Upgrade = math.max(0, math.floor(inst.Upgrade))
			-- uid counter must stay ahead of every existing uid
			local n = tonumber(string.match(uid, "^i(%d+)$"))
			if n and n >= data.Inventory.NextUid then
				data.Inventory.NextUid = n + 1
			end
		end
	end
	for id, count in data.Inventory.Stacks do
		if not Items[id] or not Items[id].Stackable or not isFiniteNumber(count) or count <= 0 then
			note(corrections, "removed invalid stack " .. tostring(id))
			data.Inventory.Stacks[id] = nil
		else
			data.Inventory.Stacks[id] = math.min(math.floor(count), GameConfig.Inventory.MaxStack)
		end
	end

	-- equipped references must point at owned, compatible items
	for slot, uid in data.Equipped do
		local inst = data.Inventory.Items[uid]
		if not inst then
			note(corrections, "unequipped missing item in " .. tostring(slot))
			data.Equipped[slot] = nil
		end
	end

	-- abilities
	for id in data.Abilities.Unlocked do
		if not Abilities[id] then
			data.Abilities.Unlocked[id] = nil
			note(corrections, "removed unknown ability " .. tostring(id))
		end
	end
	for _, slot in { "Slot1", "Slot2" } do
		local id = data.Abilities[slot]
		if id ~= "" and not data.Abilities.Unlocked[id] then
			data.Abilities[slot] = ""
			note(corrections, "cleared ability slot " .. slot)
		end
	end

	-- lost currency marker
	local lost = data.LostCurrency
	if lost ~= nil then
		if type(lost) ~= "table" or not isFiniteNumber(lost.Amount) or lost.Amount <= 0
			or not isFiniteNumber(lost.X) or not isFiniteNumber(lost.Y) or not isFiniteNumber(lost.Z) or not isFiniteNumber(lost.CreatedAt) then
			note(corrections, "removed invalid lost currency marker")
			data.LostCurrency = nil
		else
			lost.Amount = math.min(math.floor(lost.Amount), GameConfig.Currency.MaxCarried)
		end
	end

	-- receipts list must be an array of strings
	local receipts = data.Purchases.ProcessedReceipts
	local cleaned = {}
	for _, r in receipts do
		if type(r) == "string" then
			table.insert(cleaned, r)
		end
	end
	while #cleaned > GameConfig.Save.ProcessedReceiptHistory do
		table.remove(cleaned, 1)
	end
	data.Purchases.ProcessedReceipts = cleaned

	data.Corrections = corrections
	return data, corrections
end

return ProfileSchema
