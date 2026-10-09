--[[
	DeathCore
	Soulslike currency loss and recovery. State lives in profile.LostCurrency so it survives
	disconnects and server shutdowns; the marker in the world is only a view of this state.

	Rules (configurable in GameConfig.Death):
	  * On death, all carried currency moves into a recovery marker at the death position.
	  * SecondDeathRule "LosePrevious": dying again before recovering destroys the old marker
	    (its currency is gone) and creates a new one. "Merge": the new marker holds both sums.
	  * Markers expire after RecoveryExpirySeconds of real time.
	  * Recovery: only the owner (the profile itself), within RecoveryRadius, exactly once.
	  * Equipment and purchases are never touched by death.
	  * A death with nothing to drop and no rule-preserved marker leaves no marker.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)

local DeathCore = {}

function DeathCore.isExpired(lost, now: number): boolean
	return lost ~= nil and (now - lost.CreatedAt) >= GameConfig.Death.RecoveryExpirySeconds
end

-- Clears an expired marker. Returns the amount that expired (0 if none).
function DeathCore.expire(profile, now: number): number
	local lost = profile.LostCurrency
	if lost and DeathCore.isExpired(lost, now) then
		profile.LostCurrency = nil
		return lost.Amount
	end
	return 0
end

--[[
	context = { NoLoss = bool }  (PvP arena / training deaths cost nothing)
	Returns { Dropped = n, LostForever = n, Marker = table? }
]]
function DeathCore.onDeath(profile, x: number, y: number, z: number, now: number, context)
	local result = { Dropped = 0, LostForever = 0, Marker = nil }
	if context and context.NoLoss then
		result.Marker = profile.LostCurrency
		return result
	end
	DeathCore.expire(profile, now)
	local carried = math.max(0, math.floor(profile.Currency))
	local previous = profile.LostCurrency
	local amount = carried
	if previous then
		if GameConfig.Death.SecondDeathRule == "Merge" then
			amount += previous.Amount
		else
			result.LostForever = previous.Amount
		end
	end
	profile.Currency = 0
	if amount > 0 then
		profile.LostCurrency = { Amount = amount, X = x, Y = y, Z = z, CreatedAt = now }
	else
		profile.LostCurrency = nil
	end
	result.Dropped = carried
	result.Marker = profile.LostCurrency
	return result
end

-- Attempt recovery at the player's position. Returns ok, amountOrError.
function DeathCore.recover(profile, px: number, py: number, pz: number, now: number)
	local lost = profile.LostCurrency
	if not lost then
		return false, "NoMarker"
	end
	if DeathCore.isExpired(lost, now) then
		profile.LostCurrency = nil
		return false, "Expired"
	end
	local dx, dy, dz = px - lost.X, py - lost.Y, pz - lost.Z
	local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
	if dist > GameConfig.Death.RecoveryRadius then
		return false, "TooFar"
	end
	-- single mutation: clear marker and credit in the same step (no double-award possible)
	profile.LostCurrency = nil
	local before = profile.Currency
	profile.Currency = math.min(GameConfig.Currency.MaxCarried, before + lost.Amount)
	return true, profile.Currency - before
end

return DeathCore
