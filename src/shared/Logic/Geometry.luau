--[[
	Geometry
	Pure 2D (X/Z plane) shape tests used for hit resolution and telegraph validation.
	All functions take plain numbers so they run outside Roblox and allocate nothing.
	`r` is the target's own radius, so large targets are easier to clip.
]]

local Geometry = {}

local rad, cos, sqrt = math.rad, math.cos, math.sqrt

function Geometry.dist2(ax: number, az: number, bx: number, bz: number): number
	local dx, dz = bx - ax, bz - az
	return sqrt(dx * dx + dz * dz)
end

-- Normalise a 2D direction; returns 0,1 for a zero vector.
function Geometry.normalize(x: number, z: number): (number, number)
	local m = sqrt(x * x + z * z)
	if m < 1e-6 then
		return 0, 1
	end
	return x / m, z / m
end

function Geometry.inCircle(cx: number, cz: number, px: number, pz: number, radius: number, r: number?): boolean
	return Geometry.dist2(cx, cz, px, pz) <= radius + (r or 0)
end

function Geometry.inRing(cx: number, cz: number, px: number, pz: number, inner: number, outer: number, r: number?): boolean
	local d = Geometry.dist2(cx, cz, px, pz)
	local rr = r or 0
	return d <= outer + rr and d >= inner - rr
end

-- Cone with apex at origin, facing (fx, fz), half-angle arc/2.
function Geometry.inCone(ox: number, oz: number, fx: number, fz: number, px: number, pz: number, range: number, arcDeg: number, r: number?): boolean
	local rr = r or 0
	local dx, dz = px - ox, pz - oz
	local d = sqrt(dx * dx + dz * dz)
	if d > range + rr then
		return false
	end
	if d <= rr + 0.5 then
		return true -- overlapping the attacker
	end
	local nfx, nfz = Geometry.normalize(fx, fz)
	local dot = (dx * nfx + dz * nfz) / d
	-- widen the arc slightly by the angular size of the target
	local extra = math.atan(rr / math.max(d, 0.001))
	local half = math.min(math.pi, rad(arcDeg) / 2 + extra)
	return dot >= cos(half)
end

-- Rectangle from origin extending `length` along (fx, fz) with full width `width`.
function Geometry.inLine(ox: number, oz: number, fx: number, fz: number, px: number, pz: number, length: number, width: number, r: number?): boolean
	local rr = r or 0
	local nfx, nfz = Geometry.normalize(fx, fz)
	local dx, dz = px - ox, pz - oz
	local along = dx * nfx + dz * nfz
	if along < -rr or along > length + rr then
		return false
	end
	local across = math.abs(dx * -nfz + dz * nfx)
	return across <= width / 2 + rr
end

-- Angle in degrees between facing (fx, fz) and the direction to (px, pz).
function Geometry.angleTo(ox: number, oz: number, fx: number, fz: number, px: number, pz: number): number
	local nfx, nfz = Geometry.normalize(fx, fz)
	local dx, dz = Geometry.normalize(px - ox, pz - oz)
	local dot = math.clamp(nfx * dx + nfz * dz, -1, 1)
	return math.deg(math.acos(dot))
end

-- True when (ax, az) is behind a target at (tx, tz) facing (tfx, tfz) within `angleDeg`.
function Geometry.isBehind(tx: number, tz: number, tfx: number, tfz: number, ax: number, az: number, angleDeg: number): boolean
	return Geometry.angleTo(tx, tz, -tfx, -tfz, ax, az) <= angleDeg
end

return Geometry
