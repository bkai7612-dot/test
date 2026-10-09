-- Cross-reference validation for all data-driven configuration.
local RS = game:GetService("ReplicatedStorage")
local Config = RS.Shared.Config
local Items = require(Config.Items)
local Classes = require(Config.Classes)
local Abilities = require(Config.Abilities)
local Enemies = require(Config.Enemies)
local Bosses = require(Config.Bosses)
local LootTables = require(Config.LootTables)
local Shops = require(Config.Shops)
local Quests = require(Config.Quests)
local Achievements = require(Config.Achievements)
local Cosmetics = require(Config.Cosmetics)
local World = require(Config.World)
local WeaponTypes = require(Config.WeaponTypes)
local Rarities = require(Config.Rarities)
local Training = require(Config.Training)
local Upgrades = require(Config.Upgrades)
local Products = require(Config.Products)
local GameConfig = require(Config.GameConfig)

return function(t)
	local expect = t.expect

	t.it("every item has a valid kind, rarity and fields", function()
		local kinds = { Weapon = true, Shield = true, Armor = true, Accessory = true, Consumable = true, Material = true }
		for id, def in Items do
			if string.sub(id, 1, 1) ~= "_" then
				expect(kinds[def.Kind] ~= nil).toBeTruthy()
				expect(Rarities[def.Rarity] ~= nil).toBeTruthy()
				expect(type(def.Name)).toBe("string")
				if def.Kind == "Weapon" then
					expect(WeaponTypes[def.WeaponType] ~= nil).toBeTruthy()
					expect(def.Damage > 0).toBeTruthy()
					expect(Upgrades[def.Upgrade] ~= nil).toBeTruthy()
					for attr, grade in def.Scaling do
						expect(table.find(GameConfig.Attributes.List, attr) ~= nil).toBeTruthy()
						expect(GameConfig.ScalingGrades[grade] ~= nil).toBeTruthy()
					end
					for attr in def.Requires do
						expect(table.find(GameConfig.Attributes.List, attr) ~= nil).toBeTruthy()
					end
				end
			end
		end
	end)

	t.it("all six classes exist with valid loadouts and 74 starting points", function()
		expect(#Classes.Order).toBe(6)
		for _, name in Classes.Order do
			local c = Classes[name]
			expect(c ~= nil).toBeTruthy()
			local sum = 0
			for _, attr in GameConfig.Attributes.List do
				expect(type(c.Attributes[attr])).toBe("number")
				sum += c.Attributes[attr]
			end
			expect(sum).toBe(74)
			expect(Items[c.Loadout.Weapon].Kind).toBe("Weapon")
			if c.Loadout.Offhand then
				expect(Items[c.Loadout.Offhand].Kind).toBe("Shield")
			end
			for slot, id in c.Loadout.Armor do
				expect(Items[id].Kind).toBe("Armor")
				expect(Items[id].Slot).toBe(slot)
			end
			for _, a in c.Abilities do
				expect(Abilities[a] ~= nil).toBeTruthy()
			end
			for id in c.Items do
				expect(Items[id] ~= nil).toBeTruthy()
			end
			-- starting weapon requirements must be met by the class itself
			for attr, req in Items[c.Loadout.Weapon].Requires do
				expect(c.Attributes[attr] >= req).toBeTruthy()
			end
		end
	end)

	t.it("loot tables reference real items", function()
		for id, tbl in LootTables do
			for _, e in tbl.Entries do
				if not Items[e.Item] then error("loot " .. id .. " unknown item " .. e.Item) end
				expect(e.Weight > 0).toBeTruthy()
				expect(e.Min <= e.Max).toBeTruthy()
			end
			for item in tbl.Guaranteed or {} do
				if not Items[item] then error("loot " .. id .. " unknown guaranteed " .. item) end
			end
		end
	end)

	t.it("enemies reference valid loot tables and summons", function()
		for id, e in Enemies do
			if e.Loot and not LootTables[e.Loot] then error(id .. " bad loot " .. e.Loot) end
			expect(#e.Attacks > 0).toBeTruthy()
			for _, a in e.Attacks do
				if a.Shape == "Summon" and not Enemies[a.Summon] then error(id .. " bad summon") end
			end
		end
	end)

	t.it("there are exactly 20 bosses with rewards that exist", function()
		for floor = 1, 20 do
			local b = Bosses.List[floor]
			expect(b ~= nil).toBeTruthy()
			expect(b.Floor).toBe(floor)
			for item in b.Rewards.FirstClear.Items do
				if not Items[item] then error("boss " .. floor .. " unknown reward " .. item) end
			end
			if b.Rewards.FirstClear.Ability and not Abilities[b.Rewards.FirstClear.Ability] then
				error("boss " .. floor .. " unknown ability")
			end
			if b.Rewards.FirstClear.Cosmetic and not Cosmetics[b.Rewards.FirstClear.Cosmetic] then
				error("boss " .. floor .. " unknown cosmetic")
			end
			for _, phase in b.Phases do
				local lists = phase.Stances and {} or { phase.Attacks }
				for _, s in phase.Stances or {} do table.insert(lists, s.Attacks) end
				for _, list in lists do
					for _, a in list do
						if a.Shape == "Summon" and not Enemies[a.Summon] then error("boss " .. floor .. " bad summon") end
					end
				end
			end
		end
		expect(Bosses.List[21]).toBeNil()
	end)

	t.it("shops sell real items at positive prices", function()
		for shopId, shop in Shops do
			for _, entry in shop.Stock do
				if not Items[entry.Item] then error(shopId .. " unknown item " .. entry.Item) end
				expect(entry.Price > 0).toBeTruthy()
				-- no shop sells boss uniques
				expect(Items[entry.Item].BossWeapon == nil).toBeTruthy()
			end
		end
	end)

	t.it("shop sell-back can never exceed purchase price (no arbitrage)", function()
		local Formulas = require(RS.Shared.Logic.Formulas)
		for _, shop in Shops do
			for _, entry in shop.Stock do
				expect(Formulas.sellPrice(Items[entry.Item]) < entry.Price).toBeTruthy()
			end
		end
	end)

	t.it("quests reference real givers, enemies, items, locations", function()
		local npcs = {}
		for _, n in World.NPCs do npcs[n.Id] = n end
		local locs = {}
		for _, l in World.Locations do locs[l.Id] = true end
		for id, q in Quests do
			expect(npcs[q.Giver] ~= nil).toBeTruthy()
			expect(table.find(npcs[q.Giver].Quests, id) ~= nil).toBeTruthy()
			local o = q.Objective
			if o.Type == "Kill" and not Enemies[o.Enemy] then error(id .. " bad enemy") end
			if o.Type == "Collect" and not Items[o.Item] then error(id .. " bad item") end
			if o.Type == "Discover" and o.Location and not locs[o.Location] then error(id .. " bad location") end
			for _, r in q.Requires do expect(Quests[r] ~= nil).toBeTruthy() end
			for item in q.Rewards.Items or {} do expect(Items[item] ~= nil).toBeTruthy() end
		end
	end)

	t.it("achievement rewards reference real cosmetics", function()
		for id, a in Achievements do
			if a.Reward and a.Reward.Cosmetic and not Cosmetics[a.Reward.Cosmetic] then error(id) end
		end
	end)

	t.it("world spawn zones, chests and training stations are valid", function()
		for _, z in World.SpawnZones do
			if not Enemies[z.Enemy] then error("zone " .. z.Id) end
			expect(z.Count >= 1 and z.Count <= 6).toBeTruthy()
		end
		for _, c in World.Chests do
			if not LootTables[c.Loot] then error("chest " .. c.Id) end
		end
		for _, s in World.TrainingStations do
			expect(Training[s.Challenge] ~= nil).toBeTruthy()
		end
		local defaults = 0
		for _, cp in World.Checkpoints do if cp.Default then defaults += 1 end end
		expect(defaults).toBe(1)
	end)

	t.it("products only grant cosmetics", function()
		for _, p in Products.DevProducts do
			local list = p.Grant.Cosmetics or { p.Grant.Cosmetic }
			for _, c in list do
				expect(Cosmetics[c] ~= nil).toBeTruthy()
			end
			for k in p.Grant do
				expect(k == "Cosmetic" or k == "Cosmetics").toBeTruthy()
			end
		end
	end)
end
