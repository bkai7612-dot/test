--[[
	LootCore
	Rolls loot tables with an injected Rng so results are reproducible in tests.
	Returns a map { [itemId] = quantity }.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local LootTables = require(Shared.Config.LootTables)

local LootCore = {}

local function addTo(out, item, n)
	out[item] = (out[item] or 0) + n
end

function LootCore.roll(tableId: string?, rng, luck: number?)
	local out = {}
	if not tableId then
		return out
	end
	local tbl = LootTables[tableId]
	if not tbl then
		return out
	end
	for item, n in tbl.Guaranteed or {} do
		addTo(out, item, n)
	end
	local chance = math.min(1, (tbl.Chance or 1) * (1 + (luck or 0)))
	for _ = 1, tbl.Rolls or 1 do
		if rng:NextNumber() < chance then
			local entry = rng:Weighted(tbl.Entries)
			if entry then
				addTo(out, entry.Item, rng:NextInteger(entry.Min or 1, entry.Max or 1))
			end
		end
	end
	return out
end

function LootCore.rollRange(range, rng): number
	if type(range) ~= "table" then
		return 0
	end
	return rng:NextInteger(range[1] or 0, range[2] or range[1] or 0)
end

return LootCore
