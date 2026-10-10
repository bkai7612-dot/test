--[[
	Movement
	Pure, testable rules for the client's air movement:

	  * Double jump: one extra jump per airtime. It needs a fresh press (held jump keeps firing
	    JumpRequest on some devices, so a stream of requests closer than PressGap apart is
	    treated as one held press) and a short moment of airtime after take-off.
	  * Flip: a front or back flip, which is a dodge in the air (the server grants the i-frames).
	      - double jump, then dodge  -> flip
	      - dodge, then jump (within FlipChainWindow of the dodge) -> flip
	    One flip per airtime. Direction comes from movement input relative to facing:
	    moving backwards (or no input) = backflip, otherwise = front flip.
]]

local Movement = {}

Movement.PressGap = 0.2 -- seconds between jump requests that count as separate presses
Movement.MinAirTime = 0.12 -- airtime before a double jump is allowed
Movement.ChainWindow = 0.45 -- must match GameConfig.Combat.FlipChainWindow

export type State = {
	Airborne: boolean,
	AirborneSince: number,
	DoubleJumped: boolean,
	Flipped: boolean,
	LastJumpRequest: number,
	LastDodge: number,
}

function Movement.new(): State
	return {
		Airborne = false,
		AirborneSince = 0,
		DoubleJumped = false,
		Flipped = false,
		LastJumpRequest = -math.huge,
		LastDodge = -math.huge,
	}
end

function Movement.tookOff(m: State, now: number)
	if not m.Airborne then
		m.Airborne = true
		m.AirborneSince = now
	end
end

function Movement.landed(m: State)
	m.Airborne = false
	m.DoubleJumped = false
	m.Flipped = false
end

-- A jump request arrived. Returns "Flip", "DoubleJump" or nil (let the normal jump happen).
function Movement.jumpRequest(m: State, now: number): string?
	local fresh = now - m.LastJumpRequest >= Movement.PressGap
	m.LastJumpRequest = now
	if not fresh then
		return nil
	end
	-- dodge then jump: the dodge becomes a flip (works from the ground or the air)
	if now - m.LastDodge <= Movement.ChainWindow and not m.Flipped then
		m.Flipped = true
		return "Flip"
	end
	if m.Airborne and not m.DoubleJumped and now - m.AirborneSince >= Movement.MinAirTime then
		m.DoubleJumped = true
		return "DoubleJump"
	end
	return nil
end

-- The dodge button was pressed. Returns "Flip" or "Dodge".
function Movement.dodgePressed(m: State, now: number): string
	if m.Airborne and m.DoubleJumped and not m.Flipped then
		m.Flipped = true
		return "Flip"
	end
	m.LastDodge = now
	return "Dodge"
end

-- "Front" or "Back" from horizontal move input and the character's facing.
function Movement.flipDirection(moveX: number, moveZ: number, lookX: number, lookZ: number): string
	local mag = math.sqrt(moveX * moveX + moveZ * moveZ)
	if mag < 0.1 then
		return "Back"
	end
	local lmag = math.max(math.sqrt(lookX * lookX + lookZ * lookZ), 1e-6)
	local dot = (moveX * lookX + moveZ * lookZ) / (mag * lmag)
	return if dot < -0.3 then "Back" else "Front"
end

return Movement
