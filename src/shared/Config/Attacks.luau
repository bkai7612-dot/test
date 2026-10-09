--[[
	Attacks
	Constructors for enemy/boss attack definitions. Every hostile attack is:
	  1. Telegraphed: a ground indicator appears for `Windup` seconds (colour shows whether
	     it can be parried: gold = parryable, red = unblockable, white = blockable).
	  2. Resolved: players inside the shape at resolve time take damage, unless dodging
	     (i-frames), blocking (if Blockable) or parrying (if Parryable).
	  3. Recovered: the attacker is idle/vulnerable for `Recovery` seconds.

	Shapes: Circle, Cone, Line, Ring, Projectile, Summon, Hazard, Teleport, Leap, Dash, Pulse
	Damage is a multiplier of the attacker's base damage.
	Steps: an attack may be a combo, listed as `Steps`; each step has its own windup.
]]

local Attacks = {}

local function base(shape, opts)
	local a = {
		Shape = shape,
		Name = opts.Name or shape,
		Windup = opts.Windup or 0.9,
		Recovery = opts.Recovery or 0.8,
		Damage = opts.Damage or 1,
		Poise = opts.Poise or 20,
		Parryable = opts.Parryable == true,
		Blockable = opts.Blockable ~= false,
		Status = opts.Status,
		MinRange = opts.MinRange or 0,
		MaxRange = opts.MaxRange or 10,
		Weight = opts.Weight or 1,
		Cooldown = opts.Cooldown or 0,
	}
	for k, v in opts do
		if a[k] == nil then
			a[k] = v
		end
	end
	return a
end

-- Melee swing in front of the attacker.
function Attacks.Cone(opts)
	opts.Range = opts.Range or 9
	opts.Arc = opts.Arc or 100
	opts.MaxRange = opts.MaxRange or opts.Range
	return base("Cone", opts)
end

-- Area centred `Offset` studs in front of the attacker.
function Attacks.Circle(opts)
	opts.Radius = opts.Radius or 8
	opts.Offset = opts.Offset or 0
	opts.MaxRange = opts.MaxRange or (opts.Radius + opts.Offset)
	return base("Circle", opts)
end

-- Rectangle starting at the attacker extending forward.
function Attacks.Line(opts)
	opts.Length = opts.Length or 24
	opts.Width = opts.Width or 6
	opts.MaxRange = opts.MaxRange or opts.Length
	return base("Line", opts)
end

-- Donut: safe near the attacker and far away.
function Attacks.Ring(opts)
	opts.Inner = opts.Inner or 8
	opts.Outer = opts.Outer or 18
	opts.MaxRange = opts.MaxRange or 30
	opts.Blockable = opts.Blockable == true
	return base("Ring", opts)
end

function Attacks.Projectile(opts)
	opts.Speed = opts.Speed or 60
	opts.Radius = opts.Radius or 2
	opts.Count = opts.Count or 1
	opts.Spread = opts.Spread or 0
	opts.MaxRange = opts.MaxRange or 70
	opts.MinRange = opts.MinRange or 8
	opts.Homing = opts.Homing or 0
	return base("Projectile", opts)
end

-- Persistent damage zones placed under targets after the windup.
function Attacks.Hazard(opts)
	opts.Radius = opts.Radius or 7
	opts.Duration = opts.Duration or 6
	opts.TickDamage = opts.TickDamage or 0.25
	opts.Count = opts.Count or 1
	opts.MaxRange = opts.MaxRange or 80
	opts.Blockable = false
	return base("Hazard", opts)
end

function Attacks.Summon(opts)
	opts.Count = opts.Count or 2
	opts.MaxAlive = opts.MaxAlive or 4
	opts.MaxRange = opts.MaxRange or 100
	opts.Damage = 0
	return base("Summon", opts)
end

-- Teleport to a point near (or away from) the target, telegraphed at the destination.
function Attacks.Teleport(opts)
	opts.MaxRange = opts.MaxRange or 100
	opts.Damage = opts.Damage or 0
	opts.Distance = opts.Distance or 14
	return base("Teleport", opts)
end

-- Jump onto the target's position at windup start; lands with a Circle.
function Attacks.Leap(opts)
	opts.Radius = opts.Radius or 9
	opts.MinRange = opts.MinRange or 12
	opts.MaxRange = opts.MaxRange or 45
	return base("Leap", opts)
end

-- Charge in a straight line toward the target, damaging along the Line.
function Attacks.Dash(opts)
	opts.Length = opts.Length or 30
	opts.Width = opts.Width or 7
	opts.MinRange = opts.MinRange or 8
	opts.MaxRange = opts.MaxRange or opts.Length
	return base("Dash", opts)
end

-- Arena-wide pulse with explicit safe zones (players inside a safe zone take no damage).
function Attacks.Pulse(opts)
	opts.SafeZones = opts.SafeZones or 3
	opts.SafeRadius = opts.SafeRadius or 9
	opts.MaxRange = opts.MaxRange or 200
	opts.Blockable = false
	return base("Pulse", opts)
end

-- Guard/counter stance: the attacker guards for `Duration` (= Windup). Hitting it during the
-- stance triggers an immediate, telegraphed counter (cone). Waiting it out is always safe.
function Attacks.CounterStance(opts)
	opts.Range = opts.Range or 10
	opts.Arc = opts.Arc or 140
	opts.MaxRange = opts.MaxRange or 14
	opts.CounterWindup = opts.CounterWindup or 0.45
	return base("CounterStance", opts)
end

-- Combo: a sequence of attacks performed back to back.
function Attacks.Combo(name, steps, opts)
	opts = opts or {}
	local maxRange = 0
	for _, s in steps do
		maxRange = math.max(maxRange, s.MaxRange or 0)
	end
	return {
		Shape = "Combo",
		Name = name,
		Steps = steps,
		Recovery = opts.Recovery or steps[#steps].Recovery,
		MinRange = opts.MinRange or 0,
		MaxRange = opts.MaxRange or steps[1].MaxRange or maxRange,
		Weight = opts.Weight or 1,
		Cooldown = opts.Cooldown or 0,
		Damage = 0,
		Windup = steps[1].Windup,
	}
end

return Attacks
