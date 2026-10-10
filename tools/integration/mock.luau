-- Minimal Roblox math/instance mock for offline integration scenarios (tools/run_integration.sh).
-- Minimal Roblox math/instance mock for offline builder checks.
local V3 = {}
V3.__index = function(v, k)
	if k == "Magnitude" then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z) end
	if k == "Unit" then local m = math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z); assert(m > 0, "Unit of zero vector"); return Vector3.new(v.X/m, v.Y/m, v.Z/m) end
	return V3[k]
end
local function isV(x) return type(x) == "table" and getmetatable(x) == V3 end
Vector3 = {}
function Vector3.new(x, y, z)
	x, y, z = x or 0, y or 0, z or 0
	assert(type(x)=="number" and type(y)=="number" and type(z)=="number", "Vector3.new needs numbers")
	assert(x == x and y == y and z == z, "NaN in Vector3")
	return setmetatable({X=x, Y=y, Z=z}, V3)
end
V3.__add = function(a, b) assert(isV(a) and isV(b), "v3 add"); return Vector3.new(a.X+b.X, a.Y+b.Y, a.Z+b.Z) end
V3.__sub = function(a, b) assert(isV(a) and isV(b), "v3 sub"); return Vector3.new(a.X-b.X, a.Y-b.Y, a.Z-b.Z) end
V3.__unm = function(a) return Vector3.new(-a.X, -a.Y, -a.Z) end
V3.__mul = function(a, b)
	if type(a) == "number" then a, b = b, a end
	if type(b) == "number" then return Vector3.new(a.X*b, a.Y*b, a.Z*b) end
	return Vector3.new(a.X*b.X, a.Y*b.Y, a.Z*b.Z)
end
V3.__div = function(a, b) return Vector3.new(a.X/b, a.Y/b, a.Z/b) end
function V3.Dot(a, b) return a.X*b.X + a.Y*b.Y + a.Z*b.Z end
function V3.Cross(a, b) return Vector3.new(a.Y*b.Z - a.Z*b.Y, a.Z*b.X - a.X*b.Z, a.X*b.Y - a.Y*b.X) end
function V3.Lerp(a, b, t) return a + (b - a) * t end
Vector3.xAxis = Vector3.new(1,0,0); Vector3.yAxis = Vector3.new(0,1,0); Vector3.zAxis = Vector3.new(0,0,1)
Vector3.one = Vector3.new(1,1,1); Vector3.zero = Vector3.new(0,0,0)

-- CFrame: p + columns rx, ry, rz
local CFm = {}
local function mk(p, rx, ry, rz) return setmetatable({p=p, rx=rx, ry=ry, rz=rz}, CFm) end
local function rot(cf, v) return cf.rx * v.X + cf.ry * v.Y + cf.rz * v.Z end
CFm.__index = function(cf, k)
	if k == "Position" then return cf.p end
	if k == "Rotation" then return mk(Vector3.zero, cf.rx, cf.ry, cf.rz) end
	if k == "UpVector" then return cf.ry end
	if k == "LookVector" then return -cf.rz end
	if k == "RightVector" then return cf.rx end
	return CFm[k]
end
CFm.__mul = function(a, b)
	if isV(b) then return a.p + rot(a, b) end
	return mk(a.p + rot(a, b.p), rot(a, b.rx), rot(a, b.ry), rot(a, b.rz))
end
function CFm.VectorToWorldSpace(cf, v) return rot(cf, v) end
function CFm.Inverse(cf)
	-- transpose rotation
	local rx = Vector3.new(cf.rx.X, cf.ry.X, cf.rz.X)
	local ry = Vector3.new(cf.rx.Y, cf.ry.Y, cf.rz.Y)
	local rz = Vector3.new(cf.rx.Z, cf.ry.Z, cf.rz.Z)
	local inv = mk(Vector3.zero, rx, ry, rz)
	return mk(-rot(inv, cf.p), rx, ry, rz)
end
CFrame = {}
function CFrame.new(x, y, z)
	if isV(x) then return mk(x, Vector3.xAxis, Vector3.yAxis, Vector3.zAxis) end
	return mk(Vector3.new(x or 0, y or 0, z or 0), Vector3.xAxis, Vector3.yAxis, Vector3.zAxis)
end
local function Rx(t) local c, s = math.cos(t), math.sin(t); return mk(Vector3.zero, Vector3.new(1,0,0), Vector3.new(0,c,s), Vector3.new(0,-s,c)) end
local function Ry(t) local c, s = math.cos(t), math.sin(t); return mk(Vector3.zero, Vector3.new(c,0,-s), Vector3.new(0,1,0), Vector3.new(s,0,c)) end
local function Rz(t) local c, s = math.cos(t), math.sin(t); return mk(Vector3.zero, Vector3.new(c,s,0), Vector3.new(-s,c,0), Vector3.new(0,0,1)) end
function CFrame.Angles(x, y, z) return Rx(x) * Ry(y) * Rz(z) end
function CFrame.fromAxisAngle(axis, a)
	assert(math.abs(axis.Y - 1) < 1e-9, "mock fromAxisAngle supports the Y axis only")
	return Ry(a)
end
function CFrame.lookAt(p, target)
	local back = (p - target).Unit
	local right = Vector3.yAxis:Cross(back).Unit
	return mk(p, right, back:Cross(right), back)
end
function CFrameVectorToWorldSpace(cf, v) return rot(cf, v) end
function CFrame.fromMatrix(p, vx, vy, vz)
	vz = vz or vx:Cross(vy)
	local d = vx:Cross(vy):Dot(vz)
	assert(d > 0.9, "fromMatrix: not right-handed orthonormal (" .. d .. ")")
	return mk(p, vx, vy, vz)
end
CFrame.identity = CFrame.new()

Color3 = {}
local C3m = {}; C3m.__index = C3m
function Color3.new(r, g, b) assert(type(r)=="number" and type(g)=="number" and type(b)=="number", "Color3"); return setmetatable({R=r, G=g, B=b}, C3m) end
function Color3.fromRGB(r, g, b) return Color3.new(r/255, g/255, b/255) end
function C3m.Lerp(a, b, t) return Color3.new(a.R+(b.R-a.R)*t, a.G+(b.G-a.G)*t, a.B+(b.B-a.B)*t) end

local V2 = {}
V2.__mul = function(a, b) if type(a) == "number" then a, b = b, a end return Vector2.new(a.X * b, a.Y * b) end
Vector2 = { new = function(x, y) return setmetatable({X=x, Y=y}, V2) end }
NumberRange = { new = function(a, b) return {Min=a, Max=b or a} end }
NumberSequenceKeypoint = { new = function(t, v) assert(v == v, "NaN keypoint"); return {Time=t, Value=v} end }
NumberSequence = { new = function(k) return {Keypoints=k} end }
ColorSequence = { new = function(a, b) assert(a, "ColorSequence nil"); return {a, b or a} end }

Enum = setmetatable({}, { __index = function(_, cat)
	return setmetatable({}, { __index = function(_, item) return cat .. "." .. item end })
end })

local RandomM = {}; RandomM.__index = RandomM
Random = { new = function(seed) return setmetatable({ s = seed or 1 }, RandomM) end }
function RandomM.NextNumber(r, a, b)
	r.s = (r.s * 1103515245 + 12345) % 2147483648
	local u = r.s / 2147483648
	if a then return a + (b - a) * u end
	return u
end
function RandomM.NextInteger(r, a, b) return math.floor(r:NextNumber(a, b + 1)) end

local IsA = {
	Part = { Part = true, BasePart = true, Instance = true },
}
local Inst = {}
Inst.__index = function(t, k)
	local v = rawget(t, "_props")[k]
	if v ~= nil then return v end
	if k == "Parent" then return nil end
	return Inst[k]
end
Inst.__newindex = function(t, k, v)
	local props = rawget(t, "_props")
	if k == "Parent" then
		local old = props.Parent
		if old then
			for i, c in rawget(old, "_children") do if c == t then table.remove(rawget(old, "_children"), i) break end end
		end
		if v then table.insert(rawget(v, "_children"), t) end
	end
	props[k] = v
end
ALL = {}
Instance = {}
function Instance.new(class)
	local i = setmetatable({ _props = { ClassName = class, Name = class }, _children = {}, _attrs = {} }, Inst)
	table.insert(ALL, i)
	return i
end
function Inst.IsA(i, c) local set = IsA[i.ClassName]; if set then return set[c] == true end; return i.ClassName == c end
function Inst.SetAttribute(i, k, v) rawget(i, "_attrs")[k] = v end
function Inst.GetAttribute(i, k) return rawget(i, "_attrs")[k] end
function Inst.GetChildren(i) return table.clone(rawget(i, "_children")) end
function Inst.GetDescendants(i)
	local out = {}
	local function walk(x) for _, c in rawget(x, "_children") do table.insert(out, c); walk(c) end end
	walk(i)
	return out
end
function Inst.FindFirstChild(i, n) for _, c in rawget(i, "_children") do if c.Name == n then return c end end return nil end
function Inst.FindFirstChildOfClass(i, n) for _, c in rawget(i, "_children") do if c.ClassName == n then return c end end return nil end
function Inst.Destroy(i) i.Parent = nil end
function Inst.Emit() end
function Inst.WaitForChild(i, n) return Inst.FindFirstChild(i, n) end
-- Attachment WorldCFrame
local oldIndex = Inst.__index
Inst.__index = function(t, k)
	if k == "WorldCFrame" then return t.Parent.CFrame * t.CFrame end
	return oldIndex(t, k)
end

WARNINGS = {}
warn = function(...) table.insert(WARNINGS, table.concat({...}, " ")) ; print("WARN", ...) end
