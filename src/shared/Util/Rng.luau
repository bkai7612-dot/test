--[[
	Rng
	Deterministic, seedable Park-Miller PRNG. Used for loot and AI choices so that tests can
	reproduce results exactly. On the server it is seeded from os.clock()/os.time().
]]

local Rng = {}
Rng.__index = Rng

local MOD = 2147483647

function Rng.new(seed: number?)
	local self = setmetatable({}, Rng)
	local s = math.floor((seed or (os.time() + os.clock() * 1e6)) % MOD)
	if s <= 0 then
		s += MOD - 1
	end
	self._state = s
	return self
end

-- Uniform in [0, 1)
function Rng:NextNumber(): number
	self._state = (self._state * 16807) % MOD
	return (self._state - 1) / (MOD - 1)
end

-- Uniform integer in [min, max]
function Rng:NextInteger(min: number, max: number): number
	if max <= min then
		return min
	end
	return min + math.floor(self:NextNumber() * (max - min + 1))
end

function Rng:Chance(p: number): boolean
	return self:NextNumber() < p
end

-- Picks an entry from `list` using `weightKey` (default "Weight"). Returns entry, index.
function Rng:Weighted(list, weightKey: string?)
	local key = weightKey or "Weight"
	local total = 0
	for _, e in list do
		total += math.max(0, e[key] or 0)
	end
	if total <= 0 then
		return nil, nil
	end
	local roll = self:NextNumber() * total
	for i, e in list do
		roll -= math.max(0, e[key] or 0)
		if roll < 0 then
			return e, i
		end
	end
	return list[#list], #list
end

return Rng
