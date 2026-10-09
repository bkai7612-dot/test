--[[
	BossModels
	Hand-sculpted, per-boss models for all 20 tower bosses. Every boss gets its own silhouette,
	materials, lights and particle work that reads its name at a glance (the Ashen Warden's
	ember-cracked plate, the Blackwing Reaper's feathered wings, the Godbreaker's gold-mended
	marble, ...). Everything is built from engine primitives (blocks, balls, cylinders, wedges,
	ellipsoid meshes, Fire/Smoke/ParticleEmitter, PointLight), so no uploaded assets are needed.

	Authoring happens in "design space": units are multiplied by the boss scale, y = 0 is the
	ground under the boss and the boss faces -Z (right hand is +X).

	Contract kept with BossService / AttackExecutor (same tuple as EntityModels.build):
	  model, root, humanoid, radius, height, shoulder
	  * HumanoidRootPart: collidable, invisible; Humanoid.HipHeight puts the feet on the ground.
	  * "Torso" part: anchor for weak points (attachments "WeakPoint1".. if present).
	  * "ArmorPlate" parts: hidden while armour is broken (Siege Golem, Godbreaker).
	  * Motor6D "Shoulder": swing animation joint. Optional attributes "Windup"/"Strike" give the
	    swing angles in degrees (jaws and paws use smaller arcs than arms).
]]

local EntityModels = require(script.Parent.EntityModels)

local BossModels = {}

local V = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local rad = math.rad
local TAU = math.pi * 2
local C3 = Color3.fromRGB
local M = Enum.Material

local GOLD = C3(196, 158, 72)
local OLD_GOLD = C3(150, 122, 62)
local IRON = C3(64, 66, 72)
local STEEL = C3(150, 152, 160)
local BONE = C3(214, 204, 178)
local WOOD = C3(66, 46, 32)
local LEATHER = C3(72, 50, 36)
local BLACK = C3(16, 14, 18)
local BLOOD = C3(96, 12, 16)

local function shade(c: Color3, f: number): Color3
	return Color3.new(math.clamp(c.R * f, 0, 1), math.clamp(c.G * f, 0, 1), math.clamp(c.B * f, 0, 1))
end

-- CFrame at `pos` whose -Z axis points along `dir`.
local function frameAlong(pos: Vector3, dir: Vector3, hint: Vector3?): CFrame
	local back = -dir.Unit
	local up = hint or Vector3.yAxis
	if math.abs(back:Dot(up.Unit)) > 0.98 then
		up = if math.abs(back.Z) > 0.9 then Vector3.yAxis else Vector3.zAxis
	end
	local right = up:Cross(back).Unit
	local up2 = back:Cross(right)
	return CFrame.fromMatrix(pos, right, up2, back)
end

-- ===================================================================== builder toolkit
local Builder = {}
Builder.__index = Builder

local function newBuilder(name: string, s: number, hip: number, rootSize: Vector3): any
	local model = Instance.new("Model")
	model.Name = name
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = rootSize * s
	root.CFrame = CFrame.new()
	root.Transparency = 1
	root.CanCollide = true
	root.CanQuery = false
	root.CanTouch = false
	root.Parent = model
	model.PrimaryPart = root
	local b: any = setmetatable({
		Model = model,
		Root = root,
		S = s,
		Hip = hip,
		G = CF(0, -(hip + rootSize.Y / 2) * s, 0),
		Attach = root,
		Lights = 0,
		Shoulder = nil,
	}, Builder)
	return b
end

function Builder:W(cf: CFrame): CFrame
	return self.G * CF(cf.Position * self.S) * cf.Rotation
end

function Builder:Make(name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?, shape: Enum.PartType?, attach: any): Part
	local p = Instance.new("Part")
	p.Name = name
	if shape then
		p.Shape = shape
	end
	p.Size = size * self.S
	p.CFrame = self:W(cf)
	p.Color = color
	p.Material = mat or M.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Anchored = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if attach ~= false then
		local w = Instance.new("WeldConstraint")
		w.Part0 = attach or self.Attach
		w.Part1 = p
		w.Parent = p
	end
	p.Parent = self.Model
	return p
end

function Builder:Box(name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?, attach: any): Part
	return self:Make(name, size, cf, color, mat, nil, attach)
end

function Builder:Ball(name: string, d: number, pos: Vector3, color: Color3, mat: Enum.Material?, attach: any): Part
	return self:Make(name, V(d, d, d), CF(pos), color, mat, Enum.PartType.Ball, attach)
end

-- Ellipsoid (block + sphere mesh): organic volumes such as bellies, skulls and muscles.
function Builder:Ell(name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?, attach: any): Part
	local p = self:Make(name, size, cf, color, mat, nil, attach)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

function Builder:Cyl(name: string, a: Vector3, b: Vector3, d: number, color: Color3, mat: Enum.Material?, attach: any): Part
	local len = math.max((b - a).Magnitude, 0.05)
	local cf = frameAlong((a + b) / 2, b - a) * ANG(0, rad(90), 0)
	return self:Make(name, V(len, d, d), cf, color, mat, Enum.PartType.Cylinder, attach)
end

-- Disc (flat cylinder) centred on `cf`, facing along cf's Z axis.
function Builder:Disc(name: string, cf: CFrame, d: number, t: number, color: Color3, mat: Enum.Material?, attach: any): Part
	return self:Make(name, V(t, d, d), cf * ANG(0, rad(90), 0), color, mat, Enum.PartType.Cylinder, attach)
end

function Builder:Rod(name: string, a: Vector3, b: Vector3, w: number, d: number?, color: Color3, mat: Enum.Material?, attach: any): Part
	local len = math.max((b - a).Magnitude, 0.05)
	return self:Make(name, V(w, d or w, len), frameAlong((a + b) / 2, b - a), color, mat, nil, attach)
end

-- Rounded limb (ellipsoid stretched between two joints, overlapping them slightly).
function Builder:Limb(name: string, a: Vector3, b: Vector3, w: number, d: number?, color: Color3, mat: Enum.Material?, attach: any): Part
	local len = math.max((b - a).Magnitude, 0.05)
	return self:Ell(name, V(w, d or w, len * 1.22), frameAlong((a + b) / 2, b - a), color, mat, attach)
end

-- Flat panel from a to b (length), `tangent` gives its width direction.
function Builder:Panel(name: string, a: Vector3, b: Vector3, tangent: Vector3, w: number, t: number, color: Color3, mat: Enum.Material?, attach: any): Part
	local up = (b - a).Unit
	local right = (tangent - up * tangent:Dot(up)).Unit
	local back = right:Cross(up)
	local len = math.max((b - a).Magnitude, 0.05)
	return self:Make(name, V(w, len, t), CFrame.fromMatrix((a + b) / 2, right, up, back), color, mat, nil, attach)
end

function Builder:Wedge(name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?, attach: any): Part
	return self:Make(name, size, cf, color, mat, Enum.PartType.Wedge, attach)
end

-- Tapered spike / fin / horn / feather from base to tip (two mirrored wedges, optional cross).
function Builder:Spike(name: string, base: Vector3, tip: Vector3, w: number, t: number, color: Color3, mat: Enum.Material?, attach: any, cross: boolean?, hint: Vector3?)
	local dir = tip - base
	local h = math.max(dir.Magnitude, 0.05)
	local mid = frameAlong(base, dir, hint) * ANG(rad(-90), 0, 0) * CF(0, h / 2, 0)
	local function fin(cf: CFrame)
		self:Wedge(name, V(t, h, w / 2), cf * CF(0, 0, -w / 4), color, mat, attach)
		self:Wedge(name, V(t, h, w / 2), cf * CF(0, 0, w / 4) * ANG(0, math.pi, 0), color, mat, attach)
	end
	fin(mid)
	if cross then
		fin(mid * ANG(0, math.pi / 2, 0))
	end
end

-- Ring of n segments lying in cf's XZ plane (rotate cf for vertical halos).
function Builder:Ring(name: string, cf: CFrame, r: number, n: number, radial: number, height: number, color: Color3, mat: Enum.Material?, attach: any, skip: ((number) -> boolean)?)
	local segLen = TAU * r / n * 1.08
	for i = 1, n do
		if not (skip and skip(i)) then
			local th = (i - 0.5) / n * TAU
			self:Box(name, V(radial, height, segLen), cf * CF(math.cos(th) * r, 0, math.sin(th) * r) * ANG(0, -th, 0), color, mat, attach)
		end
	end
end

-- Segmented, ragged cape hanging from `top` (centre of the shoulder line, on the back).
function Builder:Cape(name: string, top: Vector3, width: number, length: number, n: number, color: Color3, mat: Enum.Material?, o: any?)
	o = o or {}
	local rng = Random.new(o.Seed or 11)
	local flare = o.Flare or 1.3
	local billow = o.Billow or 0.45
	local drift = o.Drift or 0.22
	local rag = o.Rag or 0.35
	local t = o.Thick or 0.1
	local sw = width / n
	for i = 1, n do
		local x = -width / 2 + sw * (i - 0.5)
		local len = length * (1 - rng:NextNumber() * rag)
		local a = top + V(x, 0, 0)
		local m = top + V(x * (1 + flare) / 2, -len * 0.5, billow + len * 0.5 * drift)
		local e = top + V(x * flare, -len, len * drift + billow * 0.6)
		self:Panel(name, a, m, Vector3.xAxis, sw * 1.15, t, color, mat, o.Attach)
		self:Panel(name, m, e, Vector3.xAxis, sw * flare * 1.15, t, shade(color, 0.82), mat, o.Attach)
	end
end

-- Conical skirt / robe of panels from a ring at `top` down `height`.
function Builder:Skirt(name: string, top: Vector3, topR: number, botR: number, height: number, n: number, color: Color3, mat: Enum.Material?, o: any?)
	o = o or {}
	local rng = Random.new(o.Seed or 5)
	local rag = o.Rag or 0.15
	local t = o.Thick or 0.12
	local alt = o.Alt
	for i = 1, n do
		local th = (i - 0.5) / n * TAU
		local dir = V(math.cos(th), 0, math.sin(th))
		local h = height * (1 - rng:NextNumber() * rag)
		local r1 = topR + (botR - topR) * h / height
		local a = top + dir * topR
		local e = top + dir * r1 - V(0, h, 0)
		local w = TAU * math.max(topR, r1) / n * 1.18
		local col = if alt and i % 2 == 0 then alt else color
		self:Panel(name, a, e, V(-math.sin(th), 0, math.cos(th)), w, t, col, mat, o.Attach)
	end
end

-- Random glowing crack lines on a surface frame (its XY plane, facing -Z).
function Builder:Cracks(surface: CFrame, w: number, h: number, count: number, color: Color3, mat: Enum.Material?, seed: number, thick: number?, attach: any)
	local rng = Random.new(seed)
	local tk = thick or 0.07
	for _ = 1, count do
		local p = V(rng:NextNumber(-w / 2, w / 2), rng:NextNumber(-h / 2, h / 2), 0)
		local ang = rng:NextNumber(0, TAU)
		for _ = 1, 3 do
			ang += rng:NextNumber(-0.9, 0.9)
			local len = rng:NextNumber(0.3, 0.75)
			local q = p + V(math.cos(ang) * len, math.sin(ang) * len, 0)
			q = V(math.clamp(q.X, -w / 2, w / 2), math.clamp(q.Y, -h / 2, h / 2), 0)
			if (q - p).Magnitude > 0.08 then
				local a = (surface * CF(p)).Position
				local c = (surface * CF(q)).Position
				self:Rod("Crack", a, c, tk, tk, color, mat or M.Neon, attach)
			end
			p = q
		end
	end
end

function Builder:Light(part: BasePart, color: Color3, range: number, brightness: number?)
	if self.Lights >= 4 then
		return
	end
	self.Lights += 1
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = math.min(range * self.S, 60)
	l.Brightness = brightness or 1.6
	l.Shadows = false
	l.Parent = part
end

function Builder:Fire(part: BasePart, color: Color3, secondary: Color3, size: number, heat: number?)
	local f = Instance.new("Fire")
	f.Color = color
	f.SecondaryColor = secondary
	f.Size = math.clamp(size * self.S, 2, 30)
	f.Heat = heat or 6
	f.Parent = part
end

function Builder:Smoke(part: BasePart, color: Color3, opacity: number, size: number, rise: number)
	local sm = Instance.new("Smoke")
	sm.Color = color
	sm.Opacity = opacity
	sm.Size = math.clamp(size * self.S, 0.1, 100)
	sm.RiseVelocity = rise
	sm.Parent = part
end

-- Particle helper. o: Color, Color2, Size, Rate, Life, Speed, Spread, Accel, Emission, Trans, Drag
function Builder:Emit(part: BasePart, o: any)
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(o.Color, o.Color2 or o.Color)
	local sz = (o.Size or 0.4) * self.S
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, sz), NumberSequenceKeypoint.new(1, sz * (o.EndSize or 0.1)) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, o.Trans or 0.1), NumberSequenceKeypoint.new(1, 1) })
	e.Rate = o.Rate or 12
	e.Lifetime = NumberRange.new((o.Life or 1.5) * 0.6, o.Life or 1.5)
	e.Speed = NumberRange.new((o.Speed or 2) * 0.5, o.Speed or 2)
	e.SpreadAngle = Vector2.new(o.Spread or 180, o.Spread or 180)
	e.Acceleration = o.Accel or V(0, 2, 0)
	e.LightEmission = o.Emission or 1
	e.Drag = o.Drag or 0.5
	e.RotSpeed = NumberRange.new(-60, 60)
	e.Rotation = NumberRange.new(0, 360)
	e.Parent = part
	return e
end

function Builder:Motor(part0: BasePart, part1: BasePart, joint: CFrame, windup: number?, strike: number?)
	local jw = self:W(joint)
	local m = Instance.new("Motor6D")
	m.Name = "Shoulder"
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = part0.CFrame:Inverse() * jw
	m.C1 = part1.CFrame:Inverse() * jw
	if windup then
		m:SetAttribute("Windup", windup)
	end
	if strike then
		m:SetAttribute("Strike", strike)
	end
	m.Parent = part0
	self.Shoulder = m
	return m
end

function Builder:Attachment(part: BasePart, name: string, pos: Vector3)
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = part.CFrame:Inverse() * self:W(CF(pos))
	a.Parent = part
end

function Builder:Finish(kind: string, radius: number, height: number, hipStuds: number?)
	local humanoid = Instance.new("Humanoid")
	humanoid.HipHeight = hipStuds or self.Hip * self.S
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.MaxHealth = 1e6
	humanoid.Health = 1e6
	humanoid.AutoJumpEnabled = true
	humanoid.Parent = self.Model
	local r, h = radius * self.S, height * self.S
	self.Model:SetAttribute("Kind", kind)
	self.Model:SetAttribute("Radius", r)
	self.Model:SetAttribute("Height", h)
	self.Model:SetAttribute("Sculpted", true)
	return self.Model, self.Root, humanoid, r, h, self.Shoulder
end

-- ===================================================================== anatomy
--[[
	Biped body (leg length = the builder's hip). o: Round (organic limbs), LegColor, LegMat, ChestW, ChestD, ChestH, ArmW, ArmLen, LegW, Head, Body, BodyMat, Limb,
	LimbMat, Skin, HeadMat, Joint, Foot, Hand, TorsoEll, NoLegs, NoHead, Forearm, LeftUpper,
	LeftFore, Windup, Strike
	Returns joints J (design-space positions) for dressing.
]]
local function biped(b: any, o: any): any
	local legL = b.Hip
	local cw, cd, ch = o.ChestW or 2.2, o.ChestD or 1.2, o.ChestH or 2.2
	local aw, al = o.ArmW or 0.8, o.ArmLen or 2.4
	local lw = o.LegW or 0.9
	local head = o.Head or 1.1
	local body, bodyMat = o.Body, o.BodyMat or M.SmoothPlastic
	local limb, limbMat = o.Limb or body, o.LimbMat or bodyMat
	local base = legL + 0.45
	local chestY = base + ch / 2
	local seg = if o.Round then b.Limb else b.Rod
	local J: any = { Base = base, ChestY = chestY, ChestTop = base + ch, Front = -cd / 2, Back = cd / 2, CW = cw, CD = cd, Leg = legL }
	local torsoCf = CF(0, chestY, 0)
	local torso = if o.TorsoEll
		then b:Ell("Torso", V(cw, ch, cd), torsoCf, body, bodyMat, b.Root)
		else b:Box("Torso", V(cw, ch, cd), torsoCf, body, bodyMat, b.Root)
	b.Attach = torso
	J.Torso = torso
	b:Box("Pelvis", V(cw * 0.78, 0.9, cd * 0.85), CF(0, legL + 0.3, 0), o.Pelvis or limb, limbMat)
	if not o.NoLegs then
		for side = -1, 1, 2 do
			local hj = V(side * cw * 0.24, legL + 0.2, 0)
			local knee = V(side * cw * 0.27, legL * 0.5, -0.22)
			local ankle = V(side * cw * 0.29, 0.35, 0.05)
			seg(b, "Thigh", hj, knee, lw, lw, o.LegColor or limb, o.LegMat or limbMat)
			seg(b, "Shin", knee, ankle, lw * 0.82, lw * 0.82, o.LegColor or limb, o.LegMat or limbMat)
			b:Ball("Knee", lw * 0.95, knee, o.LegColor or o.Joint or limb, o.LegMat or limbMat)
			b:Box("Foot", V(lw * 1.05, 0.45, lw * 1.7), CF(ankle.X, 0.23, -0.25), o.Foot or shade(limb, 0.8), limbMat)
		end
	end
	local sy = base + ch - aw * 0.45
	local sx = cw / 2 + aw * 0.42
	local shR = V(sx, sy, 0)
	local elR = shR + V(0.12, -al * 0.5, 0.05)
	local wrR = elR + (o.Forearm or V(0, -al * 0.38, -al * 0.3))
	local upper = seg(b, "RightArm", shR + V(0, aw * 0.3, 0), elR, aw, aw, limb, limbMat, false)
	seg(b, "Forearm", elR, wrR, aw * 0.85, aw * 0.85, limb, limbMat, upper)
	b:Ball("Elbow", aw * 0.9, elR, o.Joint or limb, limbMat, upper)
	b:Ball("Hand", aw * 0.95, wrR, o.Hand or shade(limb, 0.85), limbMat, upper)
	b:Motor(torso, upper, CF(shR), o.Windup, o.Strike)
	local shL = V(-sx, sy, 0)
	local elL = shL + (o.LeftUpper or V(-0.12, -al * 0.5, 0.05))
	local wrL = elL + (o.LeftFore or V(0, -al * 0.38, -al * 0.3))
	seg(b, "LeftArm", shL + V(0, aw * 0.3, 0), elL, aw, aw, limb, limbMat)
	seg(b, "LeftForearm", elL, wrL, aw * 0.85, aw * 0.85, limb, limbMat)
	b:Ball("LeftElbow", aw * 0.9, elL, o.Joint or limb, limbMat)
	b:Ball("LeftHand", aw * 0.95, wrL, o.Hand or shade(limb, 0.85), limbMat)
	local neckY = base + ch
	local headY = neckY + 0.15 + head * 0.55
	if not o.NoHead then
		b:Cyl("Neck", V(0, neckY - 0.3, 0), V(0, neckY + 0.35, 0), head * 0.5, o.Skin or limb, limbMat)
		J.Head = b:Ell("Head", V(head * 0.92, head * 1.05, head), CF(0, headY, 0), o.Skin or body, o.HeadMat or bodyMat)
	end
	J.HeadCf = CF(0, headY, 0)
	J.HeadSize = head
	J.HeadTop = headY + head * 0.55
	J.ShR, J.ElR, J.WrR, J.ShL, J.ElL, J.WrL = shR, elR, wrR, shL, elL, wrL
	J.Arm = upper
	J.ArmW = aw
	J.Grip = CF(wrR) * ANG(rad(-12), 0, 0) -- weapon axis = -Z of the grip, slightly downward
	J.PoleGrip = CF(wrR) * ANG(rad(55), 0, 0) -- polearms / staffs held upright-forward
	return J
end

local function eyes(b: any, J: any, color: Color3, o: any?)
	o = o or {}
	local h = J.HeadSize
	local spread = o.Spread or 0.2
	local y = o.Y or 0.05
	for side = -1, 1, 2 do
		b:Box("Eye", V(h * (o.W or 0.2), h * (o.H or 0.08), 0.06), J.HeadCf * CF(side * h * spread, y * h, -h * (o.Z or 0.5)), color, M.Neon, o.Attach)
	end
end

local function pauldron(b: any, at: Vector3, side: number, size: number, color: Color3, mat: Enum.Material, layers: number, trim: Color3?)
	for i = 0, layers - 1 do
		local k = 1 - i * 0.16
		local cf = CF(at + V(side * i * 0.18 * size, -i * 0.32 * size, 0)) * ANG(0, 0, side * rad(-18 - i * 8))
		b:Box("Pauldron", V(size * 1.15 * k, size * 0.35, size * 1.2 * k), cf, if i % 2 == 1 and trim then trim else color, mat)
	end
	b:Ell("PauldronDome", V(size * 1.1, size * 0.8, size * 1.15), CF(at + V(0, size * 0.12, 0)), color, mat)
end

local function chain(b: any, a: Vector3, c: Vector3, links: number, d: number, color: Color3, attach: any)
	for i = 0, links - 1 do
		local p0 = a:Lerp(c, i / links)
		local p1 = a:Lerp(c, (i + 1) / links)
		local cf = frameAlong((p0 + p1) / 2, p1 - p0) * ANG(0, 0, if i % 2 == 0 then 0 else math.pi / 2)
		b:Box("Chain", V(d * 0.35, d, (p1 - p0).Magnitude * 1.1), cf, color, M.CorrodedMetal, attach)
	end
end

-- ===================================================================== weapons
-- All weapons hang off the swinging arm (attach) and extend along -Z of `grip`.
local function at(grip: CFrame, x: number, y: number, d: number): Vector3
	return (grip * CF(x, y, -d)).Position
end

local function haft(b: any, grip: CFrame, d0: number, d1: number, w: number, color: Color3, mat: Enum.Material, attach: any)
	return b:Cyl("Haft", at(grip, 0, 0, d0), at(grip, 0, 0, d1), w, color, mat, attach)
end

local function bladeAlong(b: any, grip: CFrame, d0: number, d1: number, w: number, t: number, color: Color3, mat: Enum.Material, attach: any, tip: number?)
	b:Box("Blade", V(t, w, d1 - d0), grip * CF(0, 0, -(d0 + d1) / 2), color, mat, attach)
	b:Spike("BladeTip", at(grip, 0, 0, d1 - 0.01), at(grip, 0, 0, d1 + (tip or w * 1.3)), w, t, color, mat, attach)
end

local function greatsword(b: any, grip: CFrame, attach: any, o: any)
	local len, w = o.Len or 6, o.Width or 0.75
	local metal, mat = o.Metal or STEEL, o.Mat or M.Metal
	haft(b, grip, -1.1, 0.4, 0.26, o.Grip or LEATHER, M.Leather, attach)
	b:Ball("Pommel", 0.45, at(grip, 0, 0, -1.2), o.Trim or OLD_GOLD, M.Metal, attach)
	b:Box("Guard", V(0.3, w * 2.6, 0.32), grip * CF(0, 0, -0.5), o.Trim or OLD_GOLD, M.Metal, attach)
	for side = -1, 1, 2 do
		b:Spike("GuardTip", at(grip, 0, side * w * 1.25, 0.5), at(grip, 0, side * w * 1.7, 0.85), 0.3, 0.26, o.Trim or OLD_GOLD, M.Metal, attach)
	end
	bladeAlong(b, grip, 0.6, 0.6 + len, w, 0.16, metal, mat, attach)
	b:Box("Fuller", V(0.18, w * 0.22, len * 0.75), grip * CF(0, 0, -(0.6 + len * 0.42)), o.Fuller or shade(metal, 0.6), o.FullerMat or mat, attach)
	if o.Notches then
		local rng = Random.new(o.Notches)
		for i = 1, 4 do
			local d = 1.2 + i * len / 5
			b:Box("Notch", V(0.2, 0.18, 0.3), grip * CF(0, (rng:NextNumber() > 0.5 and 1 or -1) * w * 0.45, -d) * ANG(rad(45), 0, 0), BLACK, M.Slate, attach)
		end
	end
	return at(grip, 0, 0, 0.6 + len * 0.5)
end

local function halberd(b: any, grip: CFrame, attach: any, o: any)
	local len = o.Len or 9
	haft(b, grip, -2.2, len, 0.3, o.Wood or WOOD, M.Wood, attach)
	for i = 0, 3 do
		b:Cyl("Band", at(grip, 0, 0, i * len / 4 - 0.1), at(grip, 0, 0, i * len / 4 + 0.15), 0.38, IRON, M.Metal, attach)
	end
	local hd = len - 1.6
	b:Box("AxeBlade", V(0.16, 1.5, 1.9), grip * CF(0, 0.95, -hd), o.Metal or STEEL, M.Metal, attach)
	b:Spike("AxeEdge", at(grip, 0, 1.7, hd - 0.95), at(grip, 0, 1.7, hd + 0.95), 0.6, 0.15, o.Metal or STEEL, M.Metal, attach)
	b:Spike("Tip", at(grip, 0, 0, len - 0.1), at(grip, 0, 0, len + 2.2), 0.7, 0.2, o.Metal or STEEL, M.Metal, attach, true)
	b:Spike("Hook", at(grip, 0, -0.1, hd), at(grip, 0, -1.6, hd + 0.6), 0.6, 0.16, o.Metal or STEEL, M.Metal, attach)
	if o.Glow then
		b:Box("EmberEdge", V(0.2, 0.12, 1.9), grip * CF(0, 1.73, -hd), o.Glow, M.Neon, attach)
	end
end

local function cleaver(b: any, grip: CFrame, attach: any)
	haft(b, grip, -0.9, 0.5, 0.32, WOOD, M.Wood, attach)
	b:Box("Cleaver", V(0.2, 2.8, 3.6), grip * CF(0, -0.9, -2.4), C3(120, 112, 104), M.CorrodedMetal, attach)
	b:Box("CleaverSpine", V(0.3, 0.3, 3.6), grip * CF(0, 0.45, -2.4), IRON, M.Metal, attach)
	b:Box("CleaverEdge", V(0.22, 0.25, 3.6), grip * CF(0, -2.25, -2.4), BLOOD, M.SmoothPlastic, attach)
	b:Disc("CleaverHole", grip * CF(0, 0, -3.7) * ANG(0, rad(90), 0), 0.6, 0.24, BLACK, M.Slate, attach)
	for i = 1, 3 do
		b:Box("Blood", V(0.23, 0.5 + i * 0.2, 0.25), grip * CF(0, -1.6, -1.2 - i * 0.8), BLOOD, M.SmoothPlastic, attach)
	end
end

local function executionerAxe(b: any, grip: CFrame, attach: any, double: boolean, glow: Color3)
	haft(b, grip, -1.6, 5.2, 0.3, C3(40, 30, 26), M.Wood, attach)
	local heads = if double then { 1, -1 } else { 1 }
	for _, side in heads do
		b:Box("AxeHead", V(0.2, 1.8, 1.6), grip * CF(0, side * 1.0, -4.3), C3(110, 108, 112), M.Metal, attach)
		b:Spike("AxeCrescent", at(grip, 0, side * 1.85, 3.2), at(grip, 0, side * 2.3, 4.3), 1.1, 0.18, C3(130, 128, 132), M.Metal, attach)
		b:Spike("AxeCrescent", at(grip, 0, side * 1.85, 5.4), at(grip, 0, side * 2.3, 4.3), 1.1, 0.18, C3(130, 128, 132), M.Metal, attach)
		b:Box("AxeEdge", V(0.22, 0.14, 2.2), grip * CF(0, side * 2.0, -4.3), glow, M.Neon, attach)
	end
	b:Spike("AxeTop", at(grip, 0, 0, 5.15), at(grip, 0, 0, 6.2), 0.45, 0.25, IRON, M.Metal, attach, true)
end

local function rapier(b: any, grip: CFrame, attach: any, glow: Color3)
	haft(b, grip, -0.7, 0.3, 0.2, BLACK, M.Leather, attach)
	b:Ball("Pommel", 0.35, at(grip, 0, 0, -0.75), GOLD, M.Metal, attach)
	b:Ring("SweptHilt", grip * CF(0, 0, -0.35) * ANG(rad(90), 0, 0), 0.45, 10, 0.06, 0.08, GOLD, M.Metal, attach)
	b:Ring("SweptHilt", grip * CF(0, 0, -0.2) * ANG(rad(90), 0, rad(90)), 0.35, 8, 0.06, 0.08, GOLD, M.Metal, attach)
	b:Box("Quillon", V(0.1, 1.4, 0.1), grip * CF(0, 0, -0.45), GOLD, M.Metal, attach)
	bladeAlong(b, grip, 0.5, 5.4, 0.14, 0.08, C3(225, 225, 232), M.Metal, attach, 0.6)
	b:Box("BloodLine", V(0.09, 0.05, 4.2), grip * CF(0, 0, -2.8), glow, M.Neon, attach)
end

local function scythe(b: any, grip: CFrame, attach: any, glow: Color3)
	haft(b, grip, -3, 7, 0.26, C3(30, 26, 28), M.Wood, attach)
	b:Spike("Butt", at(grip, 0, 0, -3), at(grip, 0, 0, -3.8), 0.3, 0.2, IRON, M.Metal, attach, true)
	local prev = at(grip, 0, 0, 6.8)
	local n = 6
	for i = 1, n do
		local t = i / n
		local p = at(grip, 0, -0.2 - 4.4 * t, 6.8 + math.sin(t * math.pi) * 1.4 - 0.4 * t)
		b:Rod("ScytheBlade", prev, p, 0.1, 0.9 * (1 - t * 0.8), C3(170, 170, 178), M.Metal, attach)
		prev = p
	end
	b:Spike("ScytheTip", prev, prev + (prev - at(grip, 0, -3.8, 7.6)).Unit * 1.1, 0.25, 0.1, C3(170, 170, 178), M.Metal, attach)
	b:Rod("ScytheEdge", at(grip, 0, -0.5, 7.15), at(grip, 0, -3.6, 7.5), 0.12, 0.1, glow, M.Neon, attach)
end

local function warhammer(b: any, grip: CFrame, attach: any, o: any)
	haft(b, grip, -1.6, 6.4, 0.38, o.Haft or WOOD, o.HaftMat or M.Wood, attach)
	local hc = grip * CF(0, 0, -6.6)
	b:Box("HammerHead", V(2.2, 1.9, 1.9), hc, o.Head or STEEL, o.HeadMat or M.Metal, attach)
	for side = -1, 1, 2 do
		b:Box("HammerFace", V(0.3, 2.2, 2.2), hc * CF(side * 1.2, 0, 0), o.Trim or GOLD, o.TrimMat or M.Metal, attach)
	end
	b:Box("HammerBand", V(2.3, 0.3, 2.0), hc, o.Trim or GOLD, o.TrimMat or M.Metal, attach)
	b:Spike("HammerSpike", at(grip, 0, 0, 7.5), at(grip, 0, 0, 8.6), 0.6, 0.4, o.Trim or GOLD, M.Metal, attach, true)
	if o.Glow then
		for side = -1, 1, 2 do
			b:Box("HammerRune", V(0.32, 0.9, 0.18), hc * CF(side * 1.2, 0, 0), o.Glow, M.Neon, attach)
		end
	end
end

-- ===================================================================== the bosses
local Build: { [number]: (any, any, number) -> (number, number) } = {}

-- 1  The Ashen Warden: charred plate, ember cracks, T-visor helm, ash cloak, halberd.
Build[1] = function(b, def)
	local glow = def.Model.Glow
	local plate, plateMat = C3(62, 58, 56), M.CorrodedMetal
	local J = biped(b, { ChestW = 2.4, ChestD = 1.35, ChestH = 2.3, ArmW = 0.85, LegW = 0.95, Head = 1.1,
		Body = plate, BodyMat = plateMat, Limb = C3(48, 45, 44), LimbMat = M.Metal, Joint = C3(80, 74, 70) })
	local f = J.Front
	-- breastplate layers and ember cracks
	b:Box("Breastplate", V(J.CW * 1.04, 1.4, 0.2), CF(0, J.ChestY + 0.35, f - 0.08) * ANG(rad(-6), 0, 0), C3(74, 68, 64), plateMat)
	b:Cracks(CF(0, J.ChestY + 0.2, f - 0.2), J.CW * 0.9, 1.9, 7, glow, M.Neon, 101)
	local core = b:Ball("EmberCore", 0.55, V(0, J.ChestY + 0.1, f - 0.12), glow, M.Neon)
	b:Light(core, glow, 9, 2)
	b:Emit(core, { Color = glow, Color2 = C3(255, 60, 20), Size = 0.18, Rate = 14, Life = 2.2, Speed = 2, Accel = V(0, 3, 0) })
	-- faulds (armoured skirt)
	b:Skirt("Fauld", V(0, J.Base + 0.2, 0), J.CW * 0.55, J.CW * 0.75, 1.5, 10, C3(58, 54, 52), M.Metal, { Rag = 0.1, Alt = C3(70, 64, 60) })
	-- pauldrons
	pauldron(b, J.ShR + V(0.15, 0.35, 0), 1, 1.2, C3(70, 64, 60), M.Metal, 3, C3(40, 36, 36))
	pauldron(b, J.ShL + V(-0.15, 0.35, 0), -1, 1.2, C3(70, 64, 60), M.Metal, 3, C3(40, 36, 36))
	-- great helm with T visor and crest
	local hc, h = J.HeadCf, J.HeadSize
	b:Box("Helm", V(h * 1.05, h * 1.25, h * 1.1), hc * CF(0, 0.05, 0), C3(66, 62, 60), M.Metal)
	b:Box("VisorSlit", V(h * 0.8, h * 0.1, 0.06), hc * CF(0, h * 0.12, -h * 0.56), glow, M.Neon)
	b:Box("VisorSlit", V(h * 0.12, h * 0.5, 0.06), hc * CF(0, -h * 0.15, -h * 0.56), glow, M.Neon)
	for i = -2, 2 do
		b:Spike("Crest", (hc * CF(0, h * 0.6, i * h * 0.2)).Position, (hc * CF(0, h * (1.15 - math.abs(i) * 0.12), i * h * 0.3)).Position, 0.35, 0.12, C3(40, 36, 36), M.Metal)
	end
	-- ash cloak
	b:Cape("AshCloak", V(0, J.ChestTop - 0.1, J.Back + 0.12), J.CW * 1.1, 4.3, 9, C3(92, 88, 86), M.Fabric, { Seed = 1, Rag = 0.4 })
	local hem = b:Box("CloakEmber", V(J.CW, 0.1, 0.1), CF(0, J.ChestTop - 0.15, J.Back + 0.2), glow, M.Neon)
	b:Emit(hem, { Color = C3(120, 115, 112), Size = 0.35, Rate = 6, Life = 3, Speed = 0.6, Emission = 0, Trans = 0.4, Accel = V(0, 0.8, 0) })
	halberd(b, J.PoleGrip, J.Arm, { Len = 9, Glow = glow })
	return 1.6, J.HeadTop
end

-- 2  The Hollow Butcher: hulking, sack hood, bloody apron, hooks and chains, cleaver.
Build[2] = function(b, def)
	local skin = C3(158, 126, 112)
	local J = biped(b, { ChestW = 3.3, ChestD = 2.2, ChestH = 2.5, ArmW = 1.15, ArmLen = 2.6, LegW = 1.25, Head = 1.0,
		Body = skin, Limb = skin, TorsoEll = true, Skin = C3(140, 112, 84), HeadMat = M.Fabric,
		Pelvis = LEATHER, Foot = C3(40, 30, 26), Round = true, Hand = C3(150, 110, 100), Forearm = V(0.1, 0.35, -1.25) })
	b:Ell("Belly", V(3.2, 2.3, 2.4), CF(0, J.Base + 0.75, -0.2), skin, M.SmoothPlastic)
	b:Ell("Hunch", V(2.8, 1.4, 1.6), CF(0, J.ChestTop - 0.1, 0.45), shade(skin, 0.92), M.SmoothPlastic)
	for side = -1, 1, 2 do
		b:Ell("Trap", V(1.3, 0.9, 1.2), CF(side * 1.0, J.ChestTop + 0.05, 0.15), skin, M.SmoothPlastic)
		b:Ell("Bicep", V(1.35, 1.6, 1.35), CF((if side > 0 then J.ShR else J.ShL) + V(side * 0.05, -0.75, 0)), skin, M.SmoothPlastic, if side > 0 then J.Arm else nil)
	end
	-- stitched scars
	for i = 1, 5 do
		b:Box("Stitch", V(0.06, 0.32, 0.06), CF(-0.7 + i * 0.12, J.ChestY + 0.5 - i * 0.12, J.Front - 0.05) * ANG(0, 0, rad(40)), C3(50, 20, 20), M.Fabric)
	end
	-- apron
	b:Panel("Apron", V(0, J.ChestY + 0.6, J.Front - 0.35), V(0, 0.9, J.Front - 0.95), Vector3.xAxis, 2.6, 0.12, C3(150, 140, 120), M.Leather)
	local rng = Random.new(2)
	for _ = 1, 9 do
		local y = rng:NextNumber(1.2, J.ChestY + 0.4)
		local z = J.Front - 0.35 - (J.ChestY + 0.6 - y) / (J.ChestY - 0.3) * 0.6 - 0.08
		b:Ell("BloodStain", V(rng:NextNumber(0.4, 0.9), rng:NextNumber(0.3, 0.8), 0.06), CF(rng:NextNumber(-1, 1), y, z), BLOOD, M.SmoothPlastic)
	end
	-- belt, hooks and chains
	b:Box("Belt", V(3.35, 0.45, 2.3), CF(0, J.Base + 0.05, 0), C3(40, 30, 24), M.Leather)
	for side = -1, 1, 2 do
		for k = 0, 1 do
			local top = V(side * 1.55, J.Base - 0.15, -0.4 + k * 0.8)
			local bottom = top + V(0, -0.9 - k * 0.4, 0)
			chain(b, top, bottom, 4, 0.22, IRON)
			b:Spike("MeatHook", bottom, bottom + V(side * 0.2, -0.5, -0.35), 0.2, 0.12, C3(130, 128, 130), M.Metal)
		end
	end
	chain(b, V(-1.3, J.ChestTop - 0.1, J.Front - 0.1), V(1.4, J.Base + 0.2, J.Front - 0.35), 9, 0.26, IRON)
	-- sack hood: burlap with stitched eye holes
	local hc, h = J.HeadCf, J.HeadSize
	b:Ell("SackHood", V(h * 1.25, h * 1.35, h * 1.2), hc * CF(0, 0.1, 0), C3(150, 124, 86), M.Fabric)
	b:Spike("SackTie", (hc * CF(0, h * 0.62, 0.1)).Position, (hc * CF(0.1, h * 1.05, 0.5)).Position, 0.4, 0.3, C3(140, 114, 78), M.Fabric)
	for side = -1, 1, 2 do
		b:Disc("EyeHole", hc * CF(side * h * 0.24, h * 0.08, -h * 0.58), h * 0.3, 0.05, BLACK, M.Fabric)
	end
	eyes(b, J, C3(220, 50, 30), { Spread = 0.24, Y = 0.08, W = 0.1, H = 0.08, Z = 0.62 })
	b:Box("StitchedMouth", V(h * 0.55, h * 0.06, 0.05), hc * CF(0, -h * 0.25, -h * 0.6), C3(60, 30, 26), M.Fabric)
	cleaver(b, J.Grip, J.Arm)
	return 2.0, J.HeadTop
end

-- 3  The Thorn Matriarch: tree-woman rising from a skirt of roots, thorn arms, flower crown.
Build[3] = function(b, def)
	local glow = def.Model.Glow
	local bark, barkMat = C3(78, 60, 44), M.Wood
	local J = biped(b, { NoLegs = true, ChestW = 1.8, ChestD = 1.1, ChestH = 2.3, ArmW = 0.55, ArmLen = 3.0, Head = 1.0,
		Round = true, Body = bark, BodyMat = barkMat, Limb = C3(64, 50, 38), TorsoEll = true, Skin = C3(110, 92, 70), HeadMat = M.Wood,
		Forearm = V(0.1, -1.0, -1.0), LeftFore = V(-0.3, -0.6, -1.1) })
	-- roots: a flared skirt of twisting roots reaching the ground
	local rng = Random.new(3)
	for i = 1, 14 do
		local th = (i / 14) * TAU + rng:NextNumber(-0.15, 0.15)
		local dir = V(math.cos(th), 0, math.sin(th))
		local a = V(0, J.Base + 0.3, 0) + dir * 0.6
		local m = V(0, J.Base * 0.5, 0) + dir * (1.2 + rng:NextNumber(0, 0.4))
		local e = dir * (2.4 + rng:NextNumber(0, 1)) + V(0, 0.15, 0)
		b:Rod("Root", a, m, 0.45, 0.45, shade(bark, 0.9), barkMat)
		b:Rod("Root", m, e, 0.32, 0.32, shade(bark, 0.8), barkMat)
		if i % 3 == 0 then
			b:Spike("RootThorn", m, m + dir * 0.5 + V(0, 0.5, 0), 0.2, 0.1, C3(50, 40, 30), M.Wood)
		end
	end
	b:Skirt("BarkSkirt", V(0, J.Base + 0.5, 0), 0.85, 1.4, J.Base * 0.7, 10, shade(bark, 0.85), barkMat, { Rag = 0.35 })
	-- moss and lichen
	for _ = 1, 8 do
		local th = rng:NextNumber(0, TAU)
		b:Ell("Moss", V(0.6, 0.35, 0.6), CF(math.cos(th) * 0.8, rng:NextNumber(J.Base, J.ChestTop), math.sin(th) * 0.5), C3(80, 110, 50), M.LeafyGrass)
	end
	-- thorns along both arms
	for k = 0, 5 do
		local t = k / 5
		local pr = J.ElR:Lerp(J.WrR, t)
		b:Spike("ArmThorn", pr, pr + V(0.45, 0.25, 0.1), 0.18, 0.1, C3(46, 36, 28), M.Wood, J.Arm)
		local pl = J.ElL:Lerp(J.WrL, t)
		b:Spike("ArmThorn", pl, pl + V(-0.45, 0.25, 0.1), 0.18, 0.1, C3(46, 36, 28), M.Wood)
	end
	-- thorn whip: a long barbed vine in the striking hand
	local prev = J.WrR
	for k = 1, 6 do
		local nxt = J.WrR + V(0.1 * k, -0.15 * k * k * 0.1, -0.85 * k)
		b:Rod("Vine", prev, nxt, 0.22, 0.22, C3(60, 80, 40), M.Grass, J.Arm)
		b:Spike("Barb", nxt, nxt + V(0, 0.4, 0.1), 0.15, 0.08, C3(46, 36, 28), M.Wood, J.Arm)
		prev = nxt
	end
	-- face: carved mask with glowing eyes, branch antlers, flower crown
	local hc, h = J.HeadCf, J.HeadSize
	b:Ell("FaceMask", V(h * 0.8, h * 0.95, 0.3), hc * CF(0, 0, -h * 0.42), C3(150, 130, 100), M.Wood)
	eyes(b, J, glow, { Spread = 0.18, Z = 0.58, W = 0.14, H = 0.1 })
	for side = -1, 1, 2 do
		local base = (hc * CF(side * h * 0.3, h * 0.4, 0)).Position
		local b1 = base + V(side * 0.6, 1.1, 0.1)
		b:Rod("Antler", base, b1, 0.18, 0.18, C3(70, 55, 40), barkMat)
		b:Rod("Antler", b1, b1 + V(side * 0.7, 0.8, 0.2), 0.13, 0.13, C3(70, 55, 40), barkMat)
		b:Rod("Antler", b1, b1 + V(side * -0.1, 0.9, -0.2), 0.12, 0.12, C3(70, 55, 40), barkMat)
	end
	local petals = { C3(240, 150, 190), C3(250, 235, 240), C3(250, 210, 90) }
	for i = 1, 9 do
		local th = (i / 9) * TAU
		local p = (hc * CF(math.cos(th) * h * 0.55, h * 0.45, math.sin(th) * h * 0.5)).Position
		b:Ball("Flower", 0.32, p, petals[i % 3 + 1], M.SmoothPlastic)
		b:Ball("FlowerHeart", 0.14, p + V(0, 0.12, 0), glow, M.Neon)
	end
	local heart = b:Ball("HeartBloom", 0.6, V(0, J.ChestY + 0.3, J.Front - 0.1), glow, M.Neon)
	b:Light(heart, glow, 9, 1.6)
	b:Emit(heart, { Color = glow, Color2 = C3(255, 255, 200), Size = 0.12, Rate = 10, Life = 3.5, Speed = 1.2, Accel = V(0, 0.4, 0) })
	return 1.5, J.HeadTop + 1.5
end

-- 4  The Gravebound Knight: spectral armour, tower shield, blue wisps.
Build[4] = function(b, def)
	local glow = def.Model.Glow
	local ghost = C3(120, 150, 190)
	local J = biped(b, { ChestW = 2.2, ChestD = 1.25, ChestH = 2.3, ArmW = 0.8, LegW = 0.9, Head = 1.05,
		Body = C3(84, 92, 108), BodyMat = M.Metal, Limb = C3(70, 76, 90), LimbMat = M.Metal,
		LeftFore = V(0.2, -0.5, -1.0) })
	-- spectral overlay
	b:Box("SpectralShell", V(J.CW * 1.08, 2.4, J.CD * 1.12), CF(0, J.ChestY, 0), ghost, M.ForceField)
	b:Box("Breastplate", V(J.CW * 1.02, 1.6, 0.2), CF(0, J.ChestY + 0.3, J.Front - 0.08), C3(110, 118, 132), M.Metal)
	b:Box("Cross", V(0.25, 1.3, 0.06), CF(0, J.ChestY + 0.25, J.Front - 0.2), glow, M.Neon)
	b:Box("Cross", V(0.9, 0.22, 0.06), CF(0, J.ChestY + 0.55, J.Front - 0.2), glow, M.Neon)
	b:Panel("Tabard", V(0, J.Base + 0.2, J.Front - 0.15), V(0, J.Leg * 0.35, J.Front - 0.35), Vector3.xAxis, 1.2, 0.08, C3(40, 50, 70), M.Fabric)
	pauldron(b, J.ShR + V(0.1, 0.3, 0), 1, 1.05, C3(100, 108, 124), M.Metal, 2)
	pauldron(b, J.ShL + V(-0.1, 0.3, 0), -1, 1.05, C3(100, 108, 124), M.Metal, 2)
	-- great helm, ghost-flame plume
	local hc, h = J.HeadCf, J.HeadSize
	b:Cyl("GreatHelm", (hc * CF(0, -h * 0.55, 0)).Position, (hc * CF(0, h * 0.62, 0)).Position, h * 1.12, C3(96, 104, 120), M.Metal)
	b:Box("HelmSlit", V(h * 0.85, h * 0.1, 0.08), hc * CF(0, h * 0.1, -h * 0.55), glow, M.Neon)
	local plume = b:Ball("Plume", 0.4, (hc * CF(0, h * 0.75, 0)).Position, glow, M.Neon)
	b:Fire(plume, C3(120, 180, 255), C3(30, 60, 160), 1.3, 9)
	-- tower shield on the left arm
	local sh = CF(J.WrL + V(-0.15, 0.2, -0.5)) * ANG(0, rad(-12), 0)
	b:Box("TowerShield", V(2.6, 4.2, 0.3), sh, C3(80, 88, 104), M.Metal)
	b:Box("ShieldRim", V(2.8, 0.25, 0.4), sh * CF(0, 2.05, 0), C3(130, 138, 150), M.Metal)
	b:Box("ShieldRim", V(2.8, 0.25, 0.4), sh * CF(0, -2.05, 0), C3(130, 138, 150), M.Metal)
	b:Box("ShieldEmblem", V(0.28, 2.6, 0.1), sh * CF(0, 0.1, -0.2), glow, M.Neon)
	b:Box("ShieldEmblem", V(1.6, 0.28, 0.1), sh * CF(0, 0.7, -0.2), glow, M.Neon)
	b:Cracks(sh * CF(0, 0, -0.17), 2.2, 3.6, 3, C3(30, 34, 44), M.Slate, 44, 0.06)
	-- sword
	greatsword(b, J.Grip, J.Arm, { Len = 4.6, Width = 0.5, Metal = C3(170, 190, 220), Trim = C3(120, 130, 150), Fuller = glow, FullerMat = M.Neon })
	-- wisps
	local wisp = b:Box("WispSource", V(0.2, 0.2, 0.2), CF(0, J.ChestY, 0), glow, M.Neon)
	wisp.Transparency = 1
	b:Emit(wisp, { Color = glow, Color2 = C3(60, 100, 220), Size = 0.6, EndSize = 0, Rate = 18, Life = 2.4, Speed = 2.5, Accel = V(0, 1.6, 0), Trans = 0.35 })
	b:Light(wisp, glow, 10, 1.8)
	return 1.5, J.HeadTop
end

-- 5  The Ember Hound: basalt-plated wolf with molten veins and a burning mane.
Build[5] = function(b, def)
	local glow = def.Model.Glow
	local hide, hideMat = C3(46, 30, 26), M.Basalt
	local lava = M.CrackedLava
	local body = b:Ell("Torso", V(2.6, 2.2, 2.5), CF(0, 2.9, -1.0), hide, lava, b.Root)
	b.Attach = body
	b:Ell("Waist", V(1.9, 1.7, 2.3), CF(0, 2.75, 0.8), hide, hideMat)
	b:Ell("Haunch", V(2.2, 1.9, 1.7), CF(0, 2.85, 2.0), hide, lava)
	-- ribs
	for i = 0, 3 do
		for side = -1, 1, 2 do
			b:Rod("Rib", V(side * 0.95, 3.3, -1.5 + i * 0.45), V(side * 1.2, 2.3, -1.4 + i * 0.45), 0.14, 0.14, C3(70, 50, 40), M.Basalt)
		end
	end
	-- plates and spinal spikes burning
	for i = 0, 6 do
		local z = -1.8 + i * 0.65
		local base = V(0, 3.75 - math.abs(z + 0.3) * 0.12, z)
		b:Spike("SpineSpike", base, base + V(0, 0.9 - i * 0.08, 0.35), 0.5, 0.2, if i < 3 then C3(255, 120, 40) else C3(60, 40, 34), if i < 3 then M.Neon else hideMat)
	end
	b:Cracks(CF(1.2, 2.8, 0.4) * ANG(0, rad(90), 0), 3.4, 1.4, 5, glow, M.Neon, 55)
	b:Cracks(CF(-1.2, 2.8, 0.4) * ANG(0, rad(-90), 0), 3.4, 1.4, 5, glow, M.Neon, 56)
	-- neck and head
	b:Rod("Neck", V(0, 3.3, -1.7), V(0, 3.9, -2.8), 1.3, 1.2, hide, lava)
	b:Ell("Head", V(1.4, 1.2, 1.5), CF(0, 4.05, -3.2), hide, hideMat)
	b:Box("Snout", V(0.85, 0.65, 1.6), CF(0, 3.85, -4.3) * ANG(rad(-6), 0, 0), hide, hideMat)
	b:Ball("Nose", 0.38, V(0, 4.1, -5.05), BLACK, M.Slate)
	b:Box("Jaw", V(0.75, 0.28, 1.5), CF(0, 3.35, -4.1) * ANG(rad(14), 0, 0), C3(40, 28, 24), hideMat)
	b:Box("Maw", V(0.6, 0.25, 1.2), CF(0, 3.55, -4.2), glow, M.Neon)
	for i = 0, 3 do
		for side = -1, 1, 2 do
			b:Spike("Fang", V(side * 0.33, 3.6, -3.7 - i * 0.35), V(side * 0.33, 3.25 - (if i == 3 then 0.2 else 0), -3.7 - i * 0.35), 0.13, 0.1, BONE, M.SmoothPlastic)
		end
	end
	for side = -1, 1, 2 do
		b:Box("Eye", V(0.28, 0.12, 0.08), CF(side * 0.42, 4.2, -3.85) * ANG(0, side * rad(20), side * rad(-12)), C3(255, 220, 120), M.Neon)
		b:Spike("Ear", V(side * 0.45, 4.5, -3.0), V(side * 0.7, 5.3, -2.7), 0.45, 0.14, hide, hideMat)
	end
	-- burning mane
	for i = 1, 9 do
		local th = (i / 9) * math.pi
		local base = V(math.cos(th) * 0.7, 3.6 + math.sin(th) * 0.5, -2.3)
		b:Spike("Mane", base, base + V(math.cos(th) * 0.6, math.sin(th) * 0.7 + 0.5, 0.9), 0.4, 0.12, C3(255, 110, 30), M.Neon)
	end
	local maneFire = b:Box("ManeFire", V(1, 0.6, 0.6), CF(0, 4.1, -2.2), glow, M.Neon)
	maneFire.Transparency = 1
	b:Fire(maneFire, C3(255, 140, 40), C3(200, 40, 10), 1.4, 12)
	b:Light(maneFire, glow, 12, 2.2)
	b:Emit(body, { Color = glow, Color2 = C3(255, 70, 20), Size = 0.15, Rate = 16, Life = 1.6, Speed = 3, Accel = V(0, 5, 0) })
	-- legs: the right foreleg is the striking limb (paw swipe)
	local function leg(name: string, top: Vector3, knee: Vector3, paw: Vector3, attach: any)
		local upper = b:Rod(name, top, knee, 0.55, 0.65, hide, hideMat, attach)
		local a = if attach == false then upper else nil
		b:Rod("Shin", knee, paw + V(0, 0.2, 0), 0.42, 0.42, hide, hideMat, a)
		b:Ell("Paw", V(0.65, 0.35, 0.8), CF(paw + V(0, 0.05, -0.15)), C3(30, 22, 20), hideMat, a)
		for c = -1, 1 do
			b:Spike("Claw", paw + V(c * 0.2, 0, -0.5), paw + V(c * 0.22, -0.15, -0.85), 0.12, 0.08, BONE, M.SmoothPlastic, a)
		end
		return upper
	end
	local foreR = leg("RightArm", V(0.9, 2.7, -1.3), V(1.0, 1.4, -1.05), V(1.0, 0.2, -1.4), false)
	b:Motor(body, foreR, CF(0.9, 2.7, -1.3), 110, -15)
	leg("ForeLeg", V(-0.9, 2.7, -1.3), V(-1.0, 1.4, -1.05), V(-1.0, 0.2, -1.4))
	leg("HindLeg", V(0.95, 2.7, 2.1), V(1.05, 1.3, 2.7), V(1.0, 0.2, 2.35))
	leg("HindLeg", V(-0.95, 2.7, 2.1), V(-1.05, 1.3, 2.7), V(-1.0, 0.2, 2.35))
	-- tail of embers
	local prev = V(0, 3.0, 2.75)
	for k = 1, 4 do
		local nxt = prev + V(0, 0.25 + k * 0.05, 0.55)
		b:Rod("Tail", prev, nxt, 0.4 - k * 0.06, 0.4 - k * 0.06, if k == 4 then C3(255, 120, 40) else hide, if k == 4 then M.Neon else lava)
		prev = nxt
	end
	local tip = b:Ball("TailFlame", 0.3, prev, glow, M.Neon)
	b:Fire(tip, C3(255, 150, 50), C3(220, 40, 10), 0.8, 10)
	return 2.0, 5.3
end

-- 6  The Twin Executioners: Judge (hood, red sash, noose) and Sentence (iron mask, chains).
Build[6] = function(b, def, index)
	local glow = def.Model.Glow
	local judge = index ~= 2
	local skin = if judge then C3(150, 112, 96) else C3(118, 100, 96)
	local J = biped(b, { ChestW = 2.4, ChestD = 1.3, ChestH = 2.3, ArmW = 0.9, LegW = 0.95, Head = 1.0,
		Round = true, LegColor = C3(36, 30, 30), LegMat = M.Leather, Body = skin, TorsoEll = true, Limb = skin, Pelvis = C3(40, 32, 30), Foot = C3(30, 24, 22), Skin = skin,
		Forearm = V(0.1, -0.3, -1.1) })
	local axeGrip = CF(J.WrR) * ANG(rad(10), 0, 0)
	-- muscle definition
	for side = -1, 1, 2 do
		b:Ell("Pec", V(1.05, 0.8, 0.5), CF(side * 0.55, J.ChestY + 0.45, J.Front + 0.1), shade(skin, 0.96), M.SmoothPlastic)
	end
	for r = 0, 2 do
		for side = -1, 1, 2 do
			b:Ell("Abs", V(0.42, 0.34, 0.3), CF(side * 0.24, J.ChestY - 0.25 - r * 0.38, J.Front + 0.12), shade(skin, 0.94), M.SmoothPlastic)
		end
	end
	-- trousers, belt, boots
	for side = -1, 1, 2 do
		b:Rod("Trouser", V(side * 0.58, J.Leg + 0.2, 0), V(side * 0.66, J.Leg * 0.5, -0.22), 1.05, 1.05, C3(36, 30, 30), M.Leather)
		b:Rod("Boot", V(side * 0.66, J.Leg * 0.55, -0.22), V(side * 0.7, 0.3, 0.05), 1.0, 1.0, C3(26, 22, 22), M.Leather)
	end
	b:Box("Belt", V(2.2, 0.4, 1.35), CF(0, J.Base, 0), C3(30, 24, 22), M.Leather)
	b:Box("Buckle", V(0.45, 0.35, 0.1), CF(0, J.Base, J.Front - 0.03), C3(110, 108, 112), M.Metal)
	local hc, h = J.HeadCf, J.HeadSize
	if judge then
		b:Ell("Hood", V(h * 1.3, h * 1.45, h * 1.3), hc * CF(0, 0.1, 0.05), C3(20, 16, 18), M.Fabric)
		b:Spike("HoodPoint", (hc * CF(0, h * 0.6, 0.2)).Position, (hc * CF(0, h * 1.25, 0.55)).Position, 0.7, 0.4, C3(20, 16, 18), M.Fabric)
		b:Panel("HoodDrape", (hc * CF(0, -h * 0.4, 0.2)).Position, V(0, J.ChestTop - 0.6, J.Back + 0.1), Vector3.xAxis, 1.8, 0.1, C3(20, 16, 18), M.Fabric)
		b:Box("HoodShadow", V(h * 0.85, h * 0.85, 0.05), hc * CF(0, 0, -h * 0.62), BLACK, M.Fabric)
		eyes(b, J, glow, { Z = 0.66, Spread = 0.18, W = 0.16, H = 0.07 })
		-- red sash across the chest
		b:Rod("Sash", V(1.2, J.ChestTop - 0.1, J.Front - 0.05), V(-1.15, J.Base + 0.2, J.Front - 0.05), 0.55, 0.12, C3(150, 20, 26), M.Fabric)
		b:Rod("Sash", V(1.2, J.ChestTop - 0.1, J.Back + 0.05), V(-1.15, J.Base + 0.2, J.Back + 0.05), 0.55, 0.12, C3(150, 20, 26), M.Fabric)
		-- noose coiled at the hip
		local nc = CF(-1.25, J.Base - 0.3, 0) * ANG(0, 0, rad(90))
		b:Ring("Noose", nc, 0.45, 10, 0.14, 0.14, C3(150, 120, 80), M.Fabric)
		b:Ring("Noose", nc * CF(0.18, 0, 0), 0.4, 10, 0.14, 0.14, C3(140, 110, 72), M.Fabric)
		b:Rod("NooseRope", V(-1.25, J.Base - 0.75, 0), V(-1.3, J.Base - 1.6, -0.1), 0.14, 0.14, C3(150, 120, 80), M.Fabric)
		executionerAxe(b, axeGrip, J.Arm, false, glow)
	else
		b:Box("IronMask", V(h * 1.05, h * 1.15, h * 1.05), hc, C3(70, 70, 76), M.CorrodedMetal)
		for i = -2, 2 do
			b:Box("MaskBar", V(0.07, h * 0.8, 0.07), hc * CF(i * h * 0.15, -h * 0.1, -h * 0.55), C3(40, 40, 44), M.Metal)
		end
		b:Box("MaskBand", V(h * 1.1, 0.18, h * 1.1), hc * CF(0, h * 0.3, 0), C3(90, 88, 92), M.Metal)
		eyes(b, J, glow, { Z = 0.53, Spread = 0.22, W = 0.16, H = 0.07, Y = 0.15 })
		-- chains wrapped across the torso and arms
		chain(b, V(-1.3, J.ChestTop, J.Front - 0.1), V(1.3, J.Base + 0.4, J.Front - 0.1), 10, 0.24, IRON)
		chain(b, V(1.3, J.ChestTop, J.Front - 0.1), V(-1.3, J.Base + 0.4, J.Front - 0.1), 10, 0.24, IRON)
		chain(b, J.ElL, J.ElL + V(0, -1.4, 0.3), 5, 0.2, IRON)
		b:Ball("Shackle", 0.6, J.ElL + V(0, -1.6, 0.35), C3(50, 50, 54), M.Metal)
		chain(b, J.ElR + V(0, 0.2, 0), J.ElR + V(0.25, -0.8, 0.1), 4, 0.2, IRON, J.Arm)
		executionerAxe(b, axeGrip, J.Arm, true, glow)
	end
	return 1.5, J.HeadTop + 0.4
end

-- 7  The Mire Colossus: a walking bog of mud, moss and roots with a glowing core.
Build[7] = function(b, def)
	local glow = def.Model.Glow
	local mud = C3(70, 60, 44)
	local J = biped(b, { ChestW = 3.0, ChestD = 2.3, ChestH = 2.6, ArmW = 1.25, ArmLen = 3.1, LegW = 1.35, Head = 0.85,
		Round = true, Body = mud, BodyMat = M.Mud, Limb = C3(64, 56, 42), LimbMat = M.Ground, TorsoEll = true, HeadMat = M.Mud,
		Forearm = V(0.2, -1.4, -0.6), LeftFore = V(-0.2, -1.4, -0.6) })
	b:Ell("Hump", V(3.4, 2.0, 2.2), CF(0, J.ChestTop - 0.1, 0.55), shade(mud, 0.9), M.Mud)
	-- chest cavity with the bog core
	b:Ell("Cavity", V(1.5, 1.4, 0.6), CF(0, J.ChestY + 0.2, J.Front + 0.1), BLACK, M.Slate)
	local core = b:Ball("BogCore", 0.85, V(0, J.ChestY + 0.2, J.Front - 0.05), glow, M.Neon)
	b:Light(core, glow, 12, 2)
	for i = 1, 6 do
		local th = i / 6 * TAU
		b:Rod("CoreRoot", V(math.cos(th) * 0.35, J.ChestY + 0.2 + math.sin(th) * 0.35, J.Front - 0.05), V(math.cos(th) * 0.9, J.ChestY + 0.2 + math.sin(th) * 0.8, J.Front + 0.05), 0.1, 0.1, C3(50, 40, 28), M.Wood)
	end
	-- moss caps, embedded stones, mushrooms
	local rng = Random.new(7)
	for side = -1, 1, 2 do
		b:Ell("MossCap", V(1.9, 0.8, 1.8), CF(side * 1.5, J.ChestTop + 0.15, 0.1), C3(70, 100, 46), M.LeafyGrass)
	end
	for _ = 1, 10 do
		local th = rng:NextNumber(0, TAU)
		local y = rng:NextNumber(J.Leg, J.ChestTop)
		b:Ball("Stone", rng:NextNumber(0.4, 0.8), V(math.cos(th) * 1.45, y, math.sin(th) * 1.05), C3(96, 92, 86), M.Rock)
	end
	for _ = 1, 5 do
		local p = V(rng:NextNumber(-1.2, 1.2), J.ChestTop + 0.4, rng:NextNumber(0.3, 1.1))
		b:Cyl("MushroomStem", p, p + V(0, 0.4, 0), 0.14, C3(200, 190, 160), M.SmoothPlastic)
		b:Ell("MushroomCap", V(0.5, 0.22, 0.5), CF(p + V(0, 0.45, 0)), C3(150, 200, 90), M.Neon)
	end
	-- dead tree and roots growing from its back
	local trunkBase = V(-0.6, J.ChestTop, 0.9)
	local trunkTop = trunkBase + V(-0.4, 2.6, 0.5)
	b:Rod("DeadTree", trunkBase, trunkTop, 0.45, 0.45, C3(60, 48, 38), M.Wood)
	for k = 1, 4 do
		local p = trunkBase:Lerp(trunkTop, 0.4 + k * 0.15)
		b:Rod("Branch", p, p + V((k % 2 == 0 and 1 or -1) * 1.1, 0.6, 0.2), 0.16, 0.16, C3(60, 48, 38), M.Wood)
	end
	for side = -1, 1, 2 do
		b:Rod("BackRoot", V(side * 0.9, J.ChestTop - 0.3, J.Back), V(side * 1.6, J.Base - 0.5, J.Back + 0.9), 0.3, 0.3, C3(56, 44, 34), M.Wood)
	end
	-- sunken head
	local hc, h = J.HeadCf, J.HeadSize
	b:Ell("Brow", V(h * 1.5, h * 0.6, h * 1.2), hc * CF(0, h * 0.25, -0.1), shade(mud, 0.8), M.Mud)
	eyes(b, J, glow, { Z = 0.5, Spread = 0.25, W = 0.18, H = 0.1 })
	-- great clay fists
	b:Ell("Fist", V(1.7, 1.5, 1.7), CF(J.WrR), C3(84, 76, 60), M.Mud, J.Arm)
	b:Ell("Fist", V(1.7, 1.5, 1.7), CF(J.WrL), C3(84, 76, 60), M.Mud)
	b:Emit(J.Torso, { Color = C3(70, 60, 40), Size = 0.35, Rate = 6, Life = 1.4, Speed = 0.5, Accel = V(0, -14, 0), Emission = 0, Trans = 0 })
	b:Emit(core, { Color = glow, Size = 0.25, Rate = 6, Life = 3, Speed = 0.8, Accel = V(0, 1, 0) })
	return 1.9, J.ChestTop + 1.2
end

-- 8  The Veiled Arcanist: floating robed scholar, veil, orbiting rings and books, crystal staff.
Build[8] = function(b, def)
	local glow = def.Model.Glow
	local robe = C3(36, 34, 66)
	local J = biped(b, { NoLegs = true, ChestW = 1.8, ChestD = 1.1, ChestH = 2.1, ArmW = 0.6, ArmLen = 2.5, Head = 1.0,
		Round = true, TorsoEll = true, Body = robe, BodyMat = M.Fabric, Limb = shade(robe, 0.9), Skin = C3(200, 190, 210),
		LeftFore = V(-0.3, -0.2, -1.0) })
	b:Skirt("Robe", V(0, J.Base + 0.6, 0), 0.9, 1.5, 2.9, 14, robe, M.Fabric, { Rag = 0.25, Alt = shade(robe, 0.85) })
	b:Ring("RobeHem", CF(0, J.Base - 1.75, 0), 1.25, 16, 0.08, 0.1, glow, M.Neon, nil, function(i)
		return i % 4 == 0
	end)
	for side = -1, 1, 2 do
		b:Skirt("Sleeve", (if side > 0 then J.ElR else J.ElL), 0.35, 0.6, 1.0, 6, shade(robe, 0.8), M.Fabric, { Attach = if side > 0 then J.Arm else nil })
	end
	b:Box("Stole", V(0.4, 3.4, 0.1), CF(0.5, J.ChestY - 0.6, J.Front - 0.08), C3(170, 140, 70), M.Fabric)
	b:Box("Stole", V(0.4, 3.4, 0.1), CF(-0.5, J.ChestY - 0.6, J.Front - 0.08), C3(170, 140, 70), M.Fabric)
	-- hood and veil
	local hc, h = J.HeadCf, J.HeadSize
	b:Ell("Hood", V(h * 1.35, h * 1.4, h * 1.4), hc * CF(0, 0.12, 0.1), shade(robe, 0.7), M.Fabric)
	b:Spike("HoodPeak", (hc * CF(0, h * 0.6, 0)).Position, (hc * CF(0, h * 1.1, -0.2)).Position, 0.8, 0.5, shade(robe, 0.7), M.Fabric)
	local veil = b:Panel("Veil", (hc * CF(0, h * 0.35, -h * 0.62)).Position, (hc * CF(0, -h * 1.0, -h * 0.75)).Position, Vector3.xAxis, h * 0.9, 0.04, C3(200, 200, 230), M.Fabric)
	veil.Transparency = 0.3
	eyes(b, J, glow, { Z = 0.55, Spread = 0.17, W = 0.14, H = 0.06, Y = 0.1 })
	-- orbiting arcane rings
	b:Ring("ArcaneRing", CF(0, J.ChestY - 0.3, 0) * ANG(rad(12), 0, rad(8)), 2.6, 24, 0.07, 0.12, glow, M.Neon, nil, function(i)
		return i % 6 == 0
	end)
	b:Ring("ArcaneRing", CF(0, J.ChestY + 0.4, 0) * ANG(rad(-20), 0, rad(-14)), 2.1, 20, 0.06, 0.1, C3(190, 170, 255), M.Neon, nil, function(i)
		return i % 5 == 0
	end)
	-- floating tomes
	for i = 1, 3 do
		local th = i / 3 * TAU + 0.4
		local p = V(math.cos(th) * 2.4, J.ChestTop + 0.4 + i * 0.25, math.sin(th) * 2.0)
		local bc = CF(p) * ANG(rad(20 * i), th, rad(15))
		b:Box("Tome", V(0.9, 0.25, 1.2), bc, ({ C3(120, 30, 30), C3(30, 70, 50), C3(40, 40, 110) })[i], M.Leather)
		b:Box("Pages", V(0.8, 0.2, 1.1), bc * CF(0.06, 0, 0), C3(230, 220, 190), M.SmoothPlastic)
		b:Box("TomeSigil", V(0.4, 0.27, 0.4), bc, glow, M.Neon)
	end
	-- crystal staff
	local grip = J.PoleGrip
	haft(b, grip, -3, 4.4, 0.22, C3(60, 50, 70), M.Wood, J.Arm)
	b:Ring("StaffClaw", grip * CF(0, 0, -4.5) * ANG(rad(90), 0, 0), 0.45, 8, 0.12, 0.12, GOLD, M.Metal, J.Arm)
	local crystal = b:Box("Crystal", V(0.6, 0.6, 1.4), grip * CF(0, 0, -5.2) * ANG(0, 0, rad(45)), glow, M.Neon, J.Arm)
	b:Light(crystal, glow, 10, 2)
	b:Emit(crystal, { Color = glow, Color2 = C3(255, 255, 255), Size = 0.15, Rate = 12, Life = 1.4, Speed = 1.5 })
	local sigil = b:Disc("HandSigil", CF(J.WrL + V(0, 0, -0.5)), 1.2, 0.05, glow, M.Neon)
	sigil.Transparency = 0.25
	return 1.5, J.HeadTop + 0.5
end

-- 9  The Crimson Duelist: slim fencer in a red long coat, plumed hat, porcelain mask, rapier.
Build[9] = function(b, def)
	local glow = def.Model.Glow
	local coat = C3(130, 18, 30)
	local J = biped(b, { ChestW = 1.7, ChestD = 1.0, ChestH = 2.2, ArmW = 0.55, ArmLen = 2.6, LegW = 0.6, Head = 0.95,
		Body = coat, BodyMat = M.Fabric, Limb = C3(30, 24, 28), LimbMat = M.Leather, Joint = C3(30, 24, 28), Skin = C3(230, 225, 220),
		HeadMat = M.Marble, Forearm = V(0.1, -0.5, -1.1), LeftUpper = V(-0.3, -1.2, 0.3), LeftFore = V(0.3, -0.2, 0.7) })
	-- tall boots and coat tails
	for side = -1, 1, 2 do
		b:Rod("TallBoot", V(side * 0.46, J.Leg * 0.62, -0.18), V(side * 0.5, 0.25, 0.05), 0.72, 0.72, C3(20, 16, 18), M.Leather)
	end
	b:Skirt("CoatTails", V(0, J.Base + 0.2, 0), 0.9, 1.3, J.Leg * 0.85, 10, coat, M.Fabric, { Rag = 0.05 })
	b:Box("Lapel", V(0.5, 1.8, 0.1), CF(0.4, J.ChestY + 0.1, J.Front - 0.05) * ANG(0, 0, rad(12)), shade(coat, 0.7), M.Fabric)
	b:Box("Lapel", V(0.5, 1.8, 0.1), CF(-0.4, J.ChestY + 0.1, J.Front - 0.05) * ANG(0, 0, rad(-12)), shade(coat, 0.7), M.Fabric)
	b:Box("Cravat", V(0.45, 0.8, 0.14), CF(0, J.ChestTop - 0.35, J.Front - 0.08), C3(240, 235, 230), M.Fabric)
	for i = 0, 3 do
		b:Ball("Button", 0.13, V(0.22, J.ChestY + 0.3 - i * 0.38, J.Front - 0.04), GOLD, M.Metal)
	end
	b:Box("Sash", V(1.75, 0.3, 1.05), CF(0, J.Base + 0.1, 0), C3(20, 16, 18), M.Fabric)
	for side = -1, 1, 2 do
		b:Box("Epaulette", V(0.75, 0.15, 0.7), CF((if side > 0 then J.ShR else J.ShL) + V(0, 0.4, 0)), GOLD, M.Metal)
		for k = -1, 1 do
			b:Box("Fringe", V(0.06, 0.3, 0.06), CF((if side > 0 then J.ShR else J.ShL) + V(side * 0.35, 0.22, k * 0.2)), GOLD, M.Metal)
		end
	end
	-- half cape over the left shoulder
	b:Cape("HalfCape", V(-0.55, J.ChestTop, J.Back + 0.05), 1.2, 3.2, 4, C3(30, 10, 14), M.Fabric, { Seed = 9, Rag = 0.1, Flare = 1.4 })
	-- porcelain mask with a red tear, plumed hat
	local hc, h = J.HeadCf, J.HeadSize
	b:Ell("Mask", V(h * 0.8, h * 1.0, 0.3), hc * CF(0, -0.02, -h * 0.4), C3(245, 242, 238), M.Marble)
	eyes(b, J, glow, { Z = 0.57, Spread = 0.17, W = 0.17, H = 0.06, Y = 0.1 })
	b:Box("RedTear", V(0.06, h * 0.35, 0.05), hc * CF(h * 0.17, -h * 0.15, -h * 0.57), C3(200, 20, 30), M.SmoothPlastic)
	b:Box("Lips", V(h * 0.2, 0.05, 0.05), hc * CF(0, -h * 0.32, -h * 0.56), C3(150, 20, 30), M.SmoothPlastic)
	b:Disc("HatBrim", hc * CF(0, h * 0.5, 0) * ANG(rad(90), 0, rad(6)), h * 2.3, 0.1, C3(22, 18, 22), M.Fabric)
	b:Cyl("HatCrown", (hc * CF(0, h * 0.5, 0)).Position, (hc * CF(0, h * 1.05, 0)).Position, h * 1.0, C3(26, 20, 24), M.Fabric)
	b:Cyl("HatBand", (hc * CF(0, h * 0.55, 0)).Position, (hc * CF(0, h * 0.68, 0)).Position, h * 1.04, coat, M.Fabric)
	for k = 0, 2 do
		local base = (hc * CF(-h * 0.4, h * 0.65, h * 0.1)).Position
		b:Spike("Plume", base, base + V(-0.4 - k * 0.2, 1.0 - k * 0.15, 0.9 + k * 0.2), 0.45 - k * 0.08, 0.06, if k == 1 then C3(240, 240, 240) else C3(200, 20, 34), M.Fabric)
	end
	rapier(b, J.Grip, J.Arm, glow)
	return 1.2, J.HeadTop + 0.6
end

-- 10 The Siege Golem: masonry and iron engine, furnace heart, chimneys, ram arm, armour plates.
Build[10] = function(b, def)
	local glow = def.Model.Glow
	local stone, stoneMat = C3(110, 104, 96), M.Cobblestone
	local J = biped(b, { ChestW = 3.0, ChestD = 2.0, ChestH = 2.4, ArmW = 1.15, ArmLen = 2.9, LegW = 1.25, Head = 0.8,
		Body = stone, BodyMat = stoneMat, Limb = C3(96, 92, 86), LimbMat = M.Slate, Joint = IRON, NoHead = true,
		Forearm = V(0.1, -0.8, -1.0) })
	-- iron banding
	for _, y in { J.Base + 0.3, J.ChestY, J.ChestTop - 0.3 } do
		b:Box("IronBand", V(3.1, 0.25, 2.1), CF(0, y, 0), IRON, M.CorrodedMetal)
		for x = -1, 1 do
			b:Ball("Rivet", 0.18, V(x * 1.1, y, J.Front - 0.07), C3(90, 90, 96), M.Metal)
		end
	end
	-- furnace belly
	b:Box("Furnace", V(1.6, 1.0, 0.3), CF(0, J.Base + 0.75, J.Front - 0.05), C3(255, 120, 30), M.CrackedLava)
	local fire = b:Box("FurnaceGlow", V(1.4, 0.8, 0.1), CF(0, J.Base + 0.75, J.Front - 0.18), glow, M.Neon)
	for i = -2, 2 do
		b:Box("Grate", V(0.1, 1.0, 0.12), CF(i * 0.3, J.Base + 0.75, J.Front - 0.26), IRON, M.Metal)
	end
	b:Light(fire, C3(255, 150, 60), 12, 2.4)
	b:Emit(fire, { Color = C3(255, 170, 60), Color2 = C3(255, 60, 20), Size = 0.14, Rate = 12, Life = 1.2, Speed = 4, Spread = 30, Accel = V(0, 4, 0) })
	-- removable armour plates (Armor mechanic)
	local plates = {
		{ V(2.4, 1.3, 0.3), CF(0, J.ChestY + 0.45, J.Front - 0.18) },
		{ V(1.5, 0.45, 1.7), CF(J.ShR + V(0.1, 0.65, 0)) * ANG(0, 0, rad(-15)) },
		{ V(1.5, 0.45, 1.7), CF(J.ShL + V(-0.1, 0.65, 0)) * ANG(0, 0, rad(15)) },
		{ V(1.0, 1.4, 0.25), CF(0.75, J.Leg * 0.6, -0.55) },
		{ V(1.0, 1.4, 0.25), CF(-0.75, J.Leg * 0.6, -0.55) },
	}
	for i, pl in plates do
		local p = b:Box("ArmorPlate", pl[1], pl[2], C3(120, 120, 128), M.DiamondPlate)
		p:SetAttribute("Plate", i)
	end
	-- gears on the shoulders
	for side = -1, 1, 2 do
		local sh = if side > 0 then J.ShR else J.ShL
		local gc = CF(sh + V(side * 0.75, 0, 0)) * ANG(0, rad(90), 0)
		b:Disc("Gear", gc, 1.4, 0.25, C3(110, 90, 60), M.Metal, if side > 0 then J.Arm else nil)
		for k = 1, 8 do
			local th = k / 8 * TAU
			b:Box("GearTooth", V(0.22, 0.3, 0.3), gc * CF(math.cos(th) * 0.75, math.sin(th) * 0.75, 0) * ANG(0, 0, th), C3(110, 90, 60), M.Metal, if side > 0 then J.Arm else nil)
		end
	end
	-- chimneys
	for side = -1, 1, 2 do
		local base = V(side * 0.8, J.ChestTop - 0.4, J.Back + 0.3)
		b:Cyl("Chimney", base, base + V(0, 2.3, 0.2), 0.6, C3(60, 56, 54), M.Brick)
		b:Cyl("ChimneyCap", base + V(0, 2.2, 0.2), base + V(0, 2.45, 0.2), 0.8, IRON, M.Metal)
		local tip = b:Ball("ChimneyMouth", 0.45, base + V(0, 2.5, 0.2), C3(255, 120, 40), M.Neon)
		b:Smoke(tip, C3(60, 58, 56), 0.35, 1.2, 6)
	end
	-- turret head with glowing visor
	local headC = CF(0, J.ChestTop + 0.45, -0.25)
	b:Box("Head", V(1.1, 0.9, 1.0), headC, C3(90, 86, 80), M.Slate)
	b:Box("Visor", V(0.85, 0.14, 0.06), headC * CF(0, 0.05, -0.52), glow, M.Neon)
	b:Box("HeadCrest", V(0.25, 0.45, 1.1), headC * CF(0, 0.6, 0), IRON, M.Metal)
	-- ram arm: a banded iron log with spikes
	local grip = CF(J.WrR) * ANG(rad(-10), 0, 0)
	b:Cyl("Ram", at(grip, 0, 0, -0.6), at(grip, 0, 0, 2.2), 1.5, C3(70, 52, 38), M.Wood, J.Arm)
	b:Cyl("RamHead", at(grip, 0, 0, 2.1), at(grip, 0, 0, 2.9), 1.8, IRON, M.Metal, J.Arm)
	for k = 1, 4 do
		local th = k / 4 * TAU
		b:Spike("RamSpike", at(grip, math.cos(th) * 0.6, math.sin(th) * 0.6, 2.9), at(grip, math.cos(th) * 0.7, math.sin(th) * 0.7, 3.6), 0.35, 0.3, C3(140, 140, 150), M.Metal, J.Arm, true)
	end
	b:Ell("Fist", V(1.4, 1.2, 1.4), CF(J.WrL), C3(96, 92, 86), M.Slate)
	return 2.1, J.ChestTop + 1.3
end

-- 11 The Drowned Oracle: seaweed hair, barnacled robes, water orb, coral crown.
Build[11] = function(b, def)
	local glow = def.Model.Glow
	local robe = C3(36, 70, 78)
	local J = biped(b, { NoLegs = true, ChestW = 1.7, ChestD = 1.0, ChestH = 2.2, ArmW = 0.55, ArmLen = 2.5, Head = 1.0,
		Round = true, TorsoEll = true, Body = robe, BodyMat = M.Fabric, Limb = C3(120, 150, 150), Skin = C3(150, 180, 178),
		LeftFore = V(-0.2, 0.1, -1.1), Forearm = V(0.3, -0.4, -1.0) })
	b:Skirt("DrownedRobe", V(0, J.Base + 0.6, 0), 0.85, 1.6, 2.8, 14, robe, M.Fabric, { Rag = 0.45, Alt = C3(30, 60, 64), Seed = 11 })
	-- barnacles and shells
	local rng = Random.new(11)
	for _ = 1, 14 do
		local th = rng:NextNumber(0, TAU)
		local y = rng:NextNumber(J.Base - 1.6, J.ChestTop)
		local r = if y < J.Base then 0.95 + (J.Base - y) * 0.25 else 0.85
		b:Ball("Barnacle", rng:NextNumber(0.15, 0.3), V(math.cos(th) * r, y, math.sin(th) * r * 0.75), C3(200, 196, 180), M.Pebble)
	end
	-- seaweed hair streaming down
	local hc, h = J.HeadCf, J.HeadSize
	for i = 1, 11 do
		local th = (i / 11) * math.pi + math.pi * 0.0
		local root = (hc * CF(math.cos(th) * h * 0.45, h * 0.3, math.abs(math.sin(th)) * h * 0.3 + 0.05)).Position
		local tip = root + V(math.cos(th) * 0.5, -2.8 - rng:NextNumber(0, 1.2), 0.6)
		local mid = root:Lerp(tip, 0.5) + V(math.cos(th) * 0.3, 0, 0.2)
		b:Panel("Seaweed", root, mid, V(-math.sin(th), 0, math.cos(th)), 0.35, 0.05, C3(30, 70, 40), M.Grass)
		b:Panel("Seaweed", mid, tip, V(-math.sin(th), 0, math.cos(th)), 0.3, 0.05, C3(40, 90, 50), M.Grass)
	end
	b:Ell("Hair", V(h * 1.1, h * 0.8, h * 1.1), hc * CF(0, h * 0.25, 0.08), C3(30, 60, 40), M.Grass)
	eyes(b, J, glow, { Z = 0.5, Spread = 0.18, W = 0.15, H = 0.05, Y = 0.05 })
	-- coral crown
	local coral = { C3(240, 110, 120), C3(255, 160, 120), C3(230, 90, 150) }
	for i = 1, 7 do
		local th = (i / 7) * TAU
		local base = (hc * CF(math.cos(th) * h * 0.42, h * 0.48, math.sin(th) * h * 0.42)).Position
		local top = base + V(math.cos(th) * 0.25, 0.6 + (i % 2) * 0.3, math.sin(th) * 0.25)
		b:Rod("Coral", base, top, 0.12, 0.12, coral[i % 3 + 1], M.Pebble)
		b:Rod("Coral", base:Lerp(top, 0.5), base:Lerp(top, 0.5) + V(math.cos(th + 1) * 0.3, 0.3, math.sin(th + 1) * 0.3), 0.09, 0.09, coral[(i + 1) % 3 + 1], M.Pebble)
	end
	-- water orb held aloft
	local orbPos = J.WrL + V(0, 0.6, -0.3)
	local orb = b:Ball("WaterOrb", 1.5, orbPos, C3(120, 200, 230), M.Glass)
	orb.Transparency = 0.45
	local orbCore = b:Ball("OrbCore", 0.6, orbPos, glow, M.Neon)
	b:Light(orbCore, glow, 12, 2.2)
	b:Emit(orbCore, { Color = C3(160, 230, 255), Size = 0.12, Rate = 14, Life = 1.6, Speed = 1.5, Accel = V(0, -3, 0) })
	local glowHand = b:Ball("TideHand", 0.5, J.WrR, glow, M.Neon, J.Arm)
	b:Emit(glowHand, { Color = C3(120, 220, 240), Size = 0.15, Rate = 10, Life = 1.2, Speed = 1, Accel = V(0, -4, 0) })
	-- constant dripping
	b:Emit(J.Torso, { Color = C3(130, 190, 220), Size = 0.12, Rate = 14, Life = 1.0, Speed = 0.3, Accel = V(0, -20, 0), Emission = 0.3, Trans = 0.2 })
	return 1.5, J.HeadTop + 0.8
end

-- 12 The Blackwing Reaper: hooded skeleton, vast feathered wings, scythe.
Build[12] = function(b, def)
	local glow = def.Model.Glow
	local cloth = C3(16, 14, 18)
	local J = biped(b, { NoLegs = true, ChestW = 1.8, ChestD = 1.0, ChestH = 2.2, ArmW = 0.32, ArmLen = 2.8, Head = 0.95,
		Round = true, Body = cloth, BodyMat = M.Fabric, Limb = BONE, LimbMat = M.SmoothPlastic, Skin = BONE, Hand = BONE, Joint = BONE })
	-- tattered robe, open ribcage
	b:Skirt("ShroudRobe", V(0, J.Base + 0.4, 0), 0.8, 1.5, 3.2, 14, cloth, M.Fabric, { Rag = 0.5, Seed = 12 })
	for i = 0, 3 do
		b:Ring("Rib", CF(0, J.ChestY + 0.6 - i * 0.35, J.Front + 0.1) * ANG(0, 0, 0), 0.5 - i * 0.05, 10, 0.08, 0.1, BONE, M.SmoothPlastic, nil, function(k)
			return k > 6
		end)
	end
	b:Cyl("Spine", V(0, J.Base, J.Front + 0.35), V(0, J.ChestTop, J.Front + 0.35), 0.2, BONE, M.SmoothPlastic)
	local heart = b:Ball("SoulFlame", 0.5, V(0, J.ChestY + 0.2, J.Front + 0.3), glow, M.Neon)
	b:Fire(heart, C3(220, 50, 70), C3(60, 0, 10), 0.6, 8)
	b:Light(heart, glow, 10, 2)
	-- hood framing a skull
	local hc, h = J.HeadCf, J.HeadSize
	b:Ell("Skull", V(h * 0.85, h * 0.95, h * 0.9), hc, BONE, M.SmoothPlastic)
	b:Box("Jaw", V(h * 0.6, h * 0.25, h * 0.5), hc * CF(0, -h * 0.45, -h * 0.15), BONE, M.SmoothPlastic)
	for side = -1, 1, 2 do
		b:Ball("Socket", h * 0.28, (hc * CF(side * h * 0.18, h * 0.05, -h * 0.36)).Position, BLACK, M.Slate)
	end
	eyes(b, J, glow, { Z = 0.47, Spread = 0.18, W = 0.12, H = 0.12 })
	b:Ell("Hood", V(h * 1.35, h * 1.4, h * 1.35), hc * CF(0, 0.12, 0.12), cloth, M.Fabric)
	b:Spike("HoodTip", (hc * CF(0, h * 0.4, h * 0.5)).Position, (hc * CF(0, h * 0.2, h * 1.6)).Position, 0.8, 0.3, cloth, M.Fabric)
	b:Cape("Shroud", V(0, J.ChestTop, J.Back + 0.1), 2.2, 4.4, 7, cloth, M.Fabric, { Seed = 12, Rag = 0.5, Flare = 1.5 })
	-- wings: bone arm + fanned primaries and coverts
	for side = -1, 1, 2 do
		local root = V(side * 0.5, J.ChestTop - 0.3, J.Back + 0.2)
		local elbow = root + V(side * 2.4, 1.8, 0.8)
		local wrist = elbow + V(side * 2.6, 0.7, 0.4)
		local tip = wrist + V(side * 2.0, -0.4, 0.2)
		b:Rod("WingBone", root, elbow, 0.3, 0.3, C3(30, 26, 30), M.Slate)
		b:Rod("WingBone", elbow, wrist, 0.25, 0.25, C3(30, 26, 30), M.Slate)
		b:Rod("WingBone", wrist, tip, 0.2, 0.2, C3(30, 26, 30), M.Slate)
		for k = 0, 9 do
			local t = k / 9
			local base = if t < 0.5 then elbow:Lerp(wrist, t * 2) else wrist:Lerp(tip, (t - 0.5) * 2)
			local ang = rad(75 - 60 * t)
			local len = 3.2 + 2.6 * t
			local dir = V(side * math.cos(ang), -math.sin(ang), 0.12).Unit
			b:Spike("Feather", base, base + dir * len, 0.75, 0.06, if k % 2 == 0 then C3(22, 20, 26) else C3(34, 30, 38), M.Fabric)
		end
		for k = 0, 5 do
			local base = root:Lerp(elbow, k / 5)
			local dir = V(side * 0.35, -1, 0.15).Unit
			b:Spike("Covert", base, base + dir * (2.2 + k * 0.25), 0.8, 0.06, C3(28, 24, 32), M.Fabric)
		end
		local glowFeather = b:Box("WingRim", V(0.08, 0.08, 0.08), CF(wrist), glow, M.Neon)
		b:Emit(glowFeather, { Color = C3(40, 30, 40), Size = 0.4, Rate = 6, Life = 2.2, Speed = 1, Accel = V(0, -2, 0), Emission = 0, Trans = 0.2 })
	end
	scythe(b, J.PoleGrip, J.Arm, glow)
	b:Emit(J.Torso, { Color = C3(20, 16, 22), Size = 0.8, Rate = 10, Life = 2, Speed = 0.6, Accel = V(0, -1.5, 0), Emission = 0, Trans = 0.3 })
	return 1.6, J.HeadTop + 1.8
end

-- 13 The Forsaken Champion: tarnished gold armour, broken laurel, three weapons of three schools.
Build[13] = function(b, def)
	local glow = def.Model.Glow
	local gold = C3(150, 124, 64)
	local J = biped(b, { ChestW = 2.3, ChestD = 1.3, ChestH = 2.3, ArmW = 0.85, LegW = 0.92, Head = 1.0,
		Body = gold, BodyMat = M.Metal, Limb = C3(110, 92, 54), LimbMat = M.Metal, Joint = C3(70, 60, 40) })
	b:Box("Cuirass", V(J.CW * 1.04, 1.5, 0.2), CF(0, J.ChestY + 0.3, J.Front - 0.08), C3(170, 140, 70), M.Metal)
	b:Cracks(CF(0, J.ChestY + 0.2, J.Front - 0.19), 1.8, 1.4, 5, C3(60, 70, 50), M.CorrodedMetal, 131, 0.09)
	b:Ell("Sunburst", V(0.7, 0.7, 0.1), CF(0, J.ChestY + 0.4, J.Front - 0.2), glow, M.Neon)
	b:Skirt("Pteruges", V(0, J.Base + 0.15, 0), J.CW * 0.55, J.CW * 0.72, 1.4, 12, C3(120, 30, 30), M.Fabric, { Alt = C3(140, 116, 60), Rag = 0.15 })
	pauldron(b, J.ShR + V(0.12, 0.35, 0), 1, 1.15, C3(160, 132, 68), M.Metal, 3, C3(90, 74, 40))
	pauldron(b, J.ShL + V(-0.12, 0.35, 0), -1, 1.15, C3(160, 132, 68), M.Metal, 3, C3(90, 74, 40))
	-- corinthian-style helm with broken laurel
	local hc, h = J.HeadCf, J.HeadSize
	b:Ell("Helm", V(h * 1.08, h * 1.2, h * 1.12), hc, C3(160, 132, 68), M.Metal)
	b:Box("FaceGuard", V(h * 0.9, h * 0.75, 0.12), hc * CF(0, -h * 0.15, -h * 0.5), C3(140, 116, 60), M.Metal)
	b:Box("EyeSlot", V(h * 0.7, h * 0.12, 0.06), hc * CF(0, h * 0.1, -h * 0.57), glow, M.Neon)
	b:Box("NoseGuard", V(h * 0.12, h * 0.5, 0.08), hc * CF(0, -h * 0.1, -h * 0.58), C3(150, 124, 64), M.Metal)
	b:Ring("Laurel", hc * CF(0, h * 0.35, 0), h * 0.62, 14, 0.12, 0.16, C3(120, 100, 40), M.Metal, nil, function(i)
		return i >= 5 and i <= 7
	end)
	for i = 1, 14 do
		if i < 5 or i > 7 then
			local th = (i - 0.5) / 14 * TAU
			local p = (hc * CF(math.cos(th) * h * 0.66, h * 0.38, math.sin(th) * h * 0.66)).Position
			b:Spike("LaurelLeaf", p, p + V(math.cos(th) * 0.15, 0.32, math.sin(th) * 0.15), 0.2, 0.05, C3(190, 160, 70), M.Metal)
		end
	end
	-- torn banner cape
	b:Cape("BannerCape", V(0, J.ChestTop, J.Back + 0.1), J.CW, 3.8, 6, C3(100, 24, 28), M.Fabric, { Seed = 13, Rag = 0.45 })
	-- weapons of the other two schools carried on the back
	b:Rod("Quiver", V(0.6, J.ChestTop + 0.3, J.Back + 0.45), V(0.9, J.Base - 0.4, J.Back + 0.5), 0.5, 0.5, LEATHER, M.Leather)
	for k = 0, 3 do
		b:Rod("Arrow", V(0.55 + k * 0.08, J.ChestTop + 0.3, J.Back + 0.45), V(0.5 + k * 0.08, J.ChestTop + 0.9, J.Back + 0.42), 0.06, 0.06, C3(220, 220, 220), M.Fabric)
	end
	b:Rod("Bow", V(-0.8, J.ChestTop + 0.9, J.Back + 0.4), V(0.9, J.Base - 0.9, J.Back + 0.35), 0.16, 0.16, WOOD, M.Wood)
	b:Rod("BowCurve", V(-0.8, J.ChestTop + 0.9, J.Back + 0.4), V(-1.2, J.ChestTop + 0.3, J.Back + 0.4), 0.14, 0.14, WOOD, M.Wood)
	local hb = CF(V(-0.5, J.ChestY, J.Back + 0.55)) * ANG(0, 0, rad(-30)) * ANG(rad(90), 0, 0)
	warhammer(b, hb * CF(0, 0, 2.0), J.Torso, { Head = C3(130, 110, 60), Trim = C3(90, 74, 40) })
	greatsword(b, J.Grip, J.Arm, { Len = 5.6, Width = 0.7, Metal = C3(190, 180, 150), Trim = C3(170, 140, 70) })
	return 1.6, J.HeadTop + 0.3
end

-- 14 The Plague Alchemist: beak mask, wide hat, leather coat, vials and a smoking censer.
Build[14] = function(b, def)
	local glow = def.Model.Glow
	local coat = C3(54, 44, 36)
	local J = biped(b, { ChestW = 1.9, ChestD = 1.15, ChestH = 2.2, ArmW = 0.62, ArmLen = 2.6, LegW = 0.75, Head = 0.95,
		Round = true, TorsoEll = true, Body = coat, BodyMat = M.Leather, Limb = C3(46, 38, 32), LimbMat = M.Leather, Skin = C3(40, 34, 30),
		LeftFore = V(-0.1, -0.3, -1.0) })
	b:Skirt("LongCoat", V(0, J.Base + 0.3, 0), 0.95, 1.4, J.Leg + 0.3, 12, coat, M.Leather, { Rag = 0.12, Seed = 14 })
	b:Ell("Hunch", V(2.0, 1.0, 1.2), CF(0, J.ChestTop - 0.15, 0.3), coat, M.Leather)
	-- bandolier of vials
	b:Rod("Bandolier", V(0.95, J.ChestTop - 0.1, J.Front - 0.05), V(-0.9, J.Base + 0.1, J.Front - 0.05), 0.3, 0.12, C3(80, 60, 40), M.Leather)
	for k = 0, 4 do
		local p = V(0.75 - k * 0.38, J.ChestTop - 0.3 - k * 0.42, J.Front - 0.2)
		b:Cyl("Vial", p - V(0, 0.22, 0), p + V(0, 0.22, 0), 0.22, C3(200, 230, 200), M.Glass).Transparency = 0.4
		b:Cyl("Tincture", p - V(0, 0.2, 0), p + V(0, 0.05, 0), 0.16, if k % 2 == 0 then glow else C3(200, 80, 220), M.Neon)
	end
	b:Box("Belt", V(2.0, 0.35, 1.25), CF(0, J.Base, 0), C3(30, 24, 20), M.Leather)
	for side = -1, 1, 2 do
		b:Box("Pouch", V(0.5, 0.55, 0.35), CF(side * 0.75, J.Base - 0.35, J.Front + 0.1), C3(80, 60, 40), M.Leather)
	end
	-- alembic backpack
	local bp = V(0, J.ChestY + 0.1, J.Back + 0.5)
	b:Box("Pack", V(1.4, 1.6, 0.7), CF(bp), C3(80, 60, 40), M.Leather)
	local flask = b:Ball("Alembic", 0.9, bp + V(0.2, 1.1, 0.1), C3(190, 230, 190), M.Glass)
	flask.Transparency = 0.35
	b:Ball("AlembicBrew", 0.6, bp + V(0.2, 1.05, 0.1), glow, M.Neon)
	b:Rod("AlembicTube", bp + V(0.2, 1.5, 0.1), bp + V(-0.6, 1.9, 0.3), 0.1, 0.1, C3(150, 120, 60), M.Metal)
	-- hat, beak, goggles
	local hc, h = J.HeadCf, J.HeadSize
	b:Ell("Cowl", V(h * 1.2, h * 1.15, h * 1.15), hc, C3(36, 30, 26), M.Leather)
	b:Disc("HatBrim", hc * CF(0, h * 0.52, 0) * ANG(rad(90), 0, 0), h * 2.4, 0.08, C3(24, 20, 18), M.Leather)
	b:Cyl("HatCrown", (hc * CF(0, h * 0.52, 0)).Position, (hc * CF(0, h * 1.2, 0)).Position, h * 1.0, C3(28, 24, 20), M.Leather)
	b:Cyl("HatBand", (hc * CF(0, h * 0.58, 0)).Position, (hc * CF(0, h * 0.72, 0)).Position, h * 1.04, C3(120, 30, 30), M.Fabric)
	local beakBase = (hc * CF(0, -h * 0.1, -h * 0.45)).Position
	local beakTip = (hc * CF(0, -h * 0.6, -h * 2.0)).Position
	b:Spike("Beak", beakBase, beakTip, h * 0.55, h * 0.45, C3(200, 186, 150), M.Leather, nil, true)
	b:Ell("BeakBase", V(h * 0.55, h * 0.5, h * 0.4), CF(beakBase), C3(200, 186, 150), M.Leather)
	for side = -1, 1, 2 do
		local gp = hc * CF(side * h * 0.24, h * 0.1, -h * 0.5)
		b:Disc("GoggleRim", gp, h * 0.38, 0.1, OLD_GOLD, M.Metal)
		b:Disc("Goggle", gp * CF(0, 0, -0.04), h * 0.3, 0.06, glow, M.Neon)
	end
	-- censer on a chain in the striking hand
	chain(b, J.WrR, J.WrR + V(0, -1.2, -0.35), 5, 0.18, OLD_GOLD, J.Arm)
	local cp = J.WrR + V(0, -1.6, -0.45)
	b:Ball("Censer", 0.85, cp, OLD_GOLD, M.Metal, J.Arm)
	b:Ring("CenserBand", CF(cp), 0.45, 10, 0.1, 0.14, C3(110, 90, 40), M.Metal, J.Arm)
	local ember = b:Ball("CenserEmber", 0.4, cp + V(0, 0.3, 0), glow, M.Neon, J.Arm)
	b:Smoke(ember, C3(120, 200, 60), 0.3, 1.5, 2.5)
	b:Light(ember, glow, 10, 2)
	-- a raised flask in the left hand
	local lf = J.WrL + V(0, 0.45, 0)
	b:Ball("Flask", 0.6, lf, C3(200, 230, 200), M.Glass).Transparency = 0.35
	b:Ball("FlaskBrew", 0.42, lf, C3(200, 80, 220), M.Neon)
	b:Emit(J.Torso, { Color = C3(130, 180, 60), Size = 0.7, Rate = 5, Life = 3, Speed = 0.6, Emission = 0.2, Trans = 0.55, Accel = V(0, 0.5, 0) })
	return 1.4, J.HeadTop + 0.8
end

-- 15 The Iron Regent: heavy iron plate, spiked crown, purple mantle with fur trim.
Build[15] = function(b, def)
	local glow = def.Model.Glow
	local iron = C3(74, 76, 86)
	local purple = C3(70, 30, 96)
	local J = biped(b, { ChestW = 2.5, ChestD = 1.4, ChestH = 2.4, ArmW = 0.9, LegW = 1.0, Head = 1.0,
		Body = iron, BodyMat = M.Metal, Limb = C3(60, 62, 70), LimbMat = M.Metal, Joint = C3(40, 40, 46) })
	b:Box("Breastplate", V(J.CW * 1.05, 1.6, 0.25), CF(0, J.ChestY + 0.3, J.Front - 0.1), C3(92, 94, 104), M.Metal)
	b:Box("Gorget", V(1.6, 0.5, 1.5), CF(0, J.ChestTop + 0.05, 0), C3(60, 62, 70), M.Metal)
	for k = -2, 2 do
		b:Box("Filigree", V(0.08, 1.2, 0.05), CF(k * 0.35, J.ChestY + 0.3, J.Front - 0.24), GOLD, M.Metal)
	end
	b:Skirt("PlateSkirt", V(0, J.Base + 0.15, 0), J.CW * 0.55, J.CW * 0.75, 1.6, 12, C3(66, 68, 78), M.Metal, { Rag = 0.05, Alt = C3(80, 82, 92) })
	pauldron(b, J.ShR + V(0.12, 0.4, 0), 1, 1.3, C3(84, 86, 96), M.Metal, 3, GOLD)
	pauldron(b, J.ShL + V(-0.12, 0.4, 0), -1, 1.3, C3(84, 86, 96), M.Metal, 3, GOLD)
	-- royal mantle and ermine collar
	b:Cape("Mantle", V(0, J.ChestTop + 0.1, J.Back + 0.2), J.CW * 1.4, J.ChestTop + 0.3, 9, purple, M.Fabric, { Seed = 15, Rag = 0.05, Flare = 1.35, Billow = 0.35 })
	for i = 0, 10 do
		local th = math.pi + i / 10 * math.pi
		b:Ell("Ermine", V(0.75, 0.6, 0.75), CF(math.cos(th) * 1.25, J.ChestTop + 0.25, -math.sin(th) * 0.8 + 0.1), C3(236, 232, 224), M.Fabric)
		if i % 3 == 0 then
			b:Ball("ErmineTip", 0.2, V(math.cos(th) * 1.3, J.ChestTop + 0.25, -math.sin(th) * 0.85 + 0.1), BLACK, M.Fabric)
		end
	end
	-- closed royal helm and spiked crown
	local hc, h = J.HeadCf, J.HeadSize
	b:Box("RegalHelm", V(h * 1.0, h * 1.15, h * 1.05), hc, C3(80, 82, 92), M.Metal)
	b:Box("HelmVisor", V(h * 0.75, h * 0.08, 0.08), hc * CF(0, h * 0.08, -h * 0.55), glow, M.Neon)
	b:Ring("Crown", hc * CF(0, h * 0.6, 0), h * 0.6, 12, 0.12, 0.3, GOLD, M.Foil)
	for i = 1, 8 do
		local th = i / 8 * TAU
		local base = (hc * CF(math.cos(th) * h * 0.6, h * 0.72, math.sin(th) * h * 0.6)).Position
		b:Spike("CrownSpike", base, base + V(0, if i % 2 == 0 then 0.9 else 0.55, 0), 0.3, 0.12, GOLD, M.Foil)
	end
	b:Ball("CrownJewel", 0.25, (hc * CF(0, h * 0.75, -h * 0.62)).Position, C3(170, 40, 200), M.Neon)
	-- regal longsword
	greatsword(b, J.Grip, J.Arm, { Len = 5.2, Width = 0.6, Metal = C3(170, 172, 182), Trim = GOLD, Fuller = C3(110, 40, 140), FullerMat = M.Neon })
	local orb = b:Ball("RegentOrb", 0.6, J.WrL + V(0, 0.4, 0), GOLD, M.Foil)
	b:Light(orb, glow, 8, 1.2)
	return 1.6, J.HeadTop + 0.9
end

-- 16 The Starved Leviathan: emaciated sea serpent, toothed jaws, glowing gills, dorsal spines.
Build[16] = function(b, def)
	local glow = def.Model.Glow
	local hide = C3(32, 52, 62)
	local belly = C3(120, 130, 120)
	-- Torso is the neck segment so weak points sit on the gills.
	local neck = b:Ell("Torso", V(2.8, 2.6, 3.2), CF(0, 7.4, 0), hide, M.Slate, b.Root)
	b.Attach = neck
	for side = -1, 1, 2 do
		for k = 0, 2 do
			b:Box("Gill", V(0.08, 1.5 - k * 0.2, 0.18), CF(side * 1.38, 7.5, -0.6 + k * 0.45) * ANG(0, 0, side * rad(8)), glow, M.Neon)
		end
		b:Attachment(neck, "WeakPoint" .. (if side > 0 then 1 else 2), V(side * 1.6, 7.5, -0.2))
	end
	b:Light(neck, glow, 10, 1.6)
	-- emaciated body: shrinking segments sinking into the floor, ribs showing
	local prev = V(0, 7.4, 0)
	for i = 1, 11 do
		local r = 2.6 - i * 0.14
		local p = V(math.sin(i * 0.55) * 2.6 * math.min(1, i / 4), 7.2 - i * 0.62, 1.4 + i * 1.75)
		b:Ell("Segment", V(r, r * 0.95, 2.3), frameAlong(p, p - prev), if i % 2 == 0 then hide else shade(hide, 0.85), M.Slate)
		b:Ell("Belly", V(r * 0.7, r * 0.4, 2.0), frameAlong(p - V(0, r * 0.35, 0), p - prev), belly, M.Slate)
		if i % 2 == 1 and i < 9 then
			for side = -1, 1, 2 do
				b:Rod("Rib", p + V(side * r * 0.45, r * 0.25, 0), p + V(side * r * 0.52, -r * 0.3, 0.2), 0.14, 0.14, BONE, M.SmoothPlastic)
			end
		end
		b:Spike("Dorsal", p + V(0, r * 0.4, 0), p + V(0, r * 0.4 + 1.3 - i * 0.07, 0.8), 1.0, 0.1, C3(20, 34, 40), M.Slate)
		prev = p
	end
	-- head
	local head = b:Ell("Head", V(2.6, 1.9, 3.8), CF(0, 8.3, -2.6), hide, M.Slate)
	b:Box("Snout", V(2.0, 1.1, 2.2), CF(0, 8.2, -4.4) * ANG(rad(-5), 0, 0), hide, M.Slate, head)
	b:Ell("Brow", V(2.8, 0.7, 1.6), CF(0, 9.05, -3.0), shade(hide, 0.8), M.Slate, head)
	for side = -1, 1, 2 do
		b:Ball("Eye", 0.5, V(side * 1.05, 8.85, -3.6), glow, M.Neon, head)
		b:Spike("Frill", V(side * 1.1, 8.8, -1.6), V(side * 2.4, 9.8, -0.6), 1.2, 0.08, C3(40, 90, 100), M.Slate, head)
		b:Spike("Frill", V(side * 1.2, 8.3, -1.4), V(side * 2.6, 8.4, -0.3), 1.0, 0.08, C3(40, 90, 100), M.Slate, head)
		b:Spike("Whisker", V(side * 0.8, 7.9, -5.2), V(side * 1.6, 6.6, -5.6), 0.15, 0.08, C3(60, 80, 90), M.Slate, head)
	end
	for k = 0, 5 do
		for side = -1, 1, 2 do
			b:Spike("Tooth", V(side * 0.85, 7.7, -2.9 - k * 0.42), V(side * 0.85, 6.95, -2.95 - k * 0.42), 0.22, 0.14, BONE, M.SmoothPlastic, head)
		end
	end
	-- lower jaw is the striking joint (snaps open on windup, shut on the strike)
	local jaw = b:Box("RightArm", V(1.9, 0.55, 3.8), CF(0, 6.9, -3.6), shade(hide, 0.8), M.Slate, false)
	b:Box("Gullet", V(1.5, 0.12, 3.2), CF(0, 7.2, -3.4), glow, M.Neon, jaw)
	for k = 0, 5 do
		for side = -1, 1, 2 do
			b:Spike("Tooth", V(side * 0.75, 7.1, -2.4 - k * 0.45), V(side * 0.75, 7.75, -2.45 - k * 0.45), 0.2, 0.14, BONE, M.SmoothPlastic, jaw)
		end
	end
	b:Motor(head, jaw, CF(0, 7.0, -1.8), -35, 8)
	b:Emit(head, { Color = C3(120, 220, 230), Size = 0.2, Rate = 10, Life = 1.2, Speed = 0.4, Accel = V(0, -18, 0), Emission = 0.4 })
	return 3.0, 10
end

-- 17 The Eclipse Witch: floating gown, eclipse halo, crescent staff, falling stars.
Build[17] = function(b, def)
	local glow = def.Model.Glow
	local gown = C3(32, 20, 50)
	local J = biped(b, { NoLegs = true, ChestW = 1.6, ChestD = 0.95, ChestH = 2.2, ArmW = 0.5, ArmLen = 2.6, Head = 0.95,
		Round = true, TorsoEll = true, Body = gown, BodyMat = M.Fabric, Limb = C3(200, 190, 210), Skin = C3(200, 190, 215), LeftUpper = V(-0.6, -0.9, 0), LeftFore = V(-0.6, 0.6, -0.3) })
	b:Skirt("Gown", V(0, J.Base + 0.5, 0), 0.75, 1.9, 3.0, 16, gown, M.Fabric, { Rag = 0.3, Seed = 17, Alt = C3(44, 26, 70) })
	b:Ring("GownTrim", CF(0, J.Base + 0.45, 0), 0.8, 14, 0.08, 0.12, glow, M.Neon)
	b:Ring("Hem", CF(0, J.Base - 2.3, 0), 1.6, 18, 0.08, 0.1, glow, M.Neon, nil, function(i)
		return i % 3 == 0
	end)
	b:Box("Corset", V(1.65, 1.4, 1.0), CF(0, J.ChestY - 0.35, 0), C3(20, 12, 30), M.Leather)
	for k = 0, 3 do
		b:Box("Lacing", V(0.5, 0.05, 0.05), CF(0, J.ChestY - 0.85 + k * 0.3, J.Front - 0.03), GOLD, M.Metal)
	end
	-- long silver hair
	local hc, h = J.HeadCf, J.HeadSize
	b:Ell("Hair", V(h * 1.1, h * 1.05, h * 1.1), hc * CF(0, h * 0.12, 0.08), C3(210, 210, 225), M.Fabric)
	b:Panel("HairFall", (hc * CF(0, h * 0.2, h * 0.4)).Position, V(0, J.Base, J.Back + 0.4), Vector3.xAxis, 1.1, 0.12, C3(200, 200, 220), M.Fabric)
	eyes(b, J, glow, { Z = 0.48, Spread = 0.17, W = 0.14, H = 0.05 })
	-- eclipse halo: dark disc, burning corona, crescent
	local halo = hc * CF(0, h * 0.3, h * 1.0)
	b:Disc("EclipseDisc", halo, 2.6, 0.1, BLACK, M.Slate)
	b:Ring("Corona", halo * ANG(rad(90), 0, 0), 1.45, 24, 0.12, 0.1, glow, M.Neon)
	b:Ring("Corona", halo * ANG(rad(90), 0, 0), 1.8, 24, 0.05, 0.06, C3(255, 240, 200), M.Neon, nil, function(i)
		return i % 2 == 0
	end)
	for i = 1, 8 do
		local th = (i + 0.5) / 8 * TAU
		local base = (halo * CF(math.cos(th) * 1.5, math.sin(th) * 1.5, 0)).Position
		local tip = (halo * CF(math.cos(th) * 2.3, math.sin(th) * 2.3, 0)).Position
		b:Spike("CoronaRay", base, tip, 0.35, 0.05, glow, M.Neon)
	end
	local haloLight = b:Box("HaloLight", V(0.1, 0.1, 0.1), halo, glow, M.Neon)
	b:Light(haloLight, glow, 10, 1.8)
	-- crescent staff
	local grip = J.PoleGrip
	haft(b, grip, -3, 4.5, 0.2, C3(30, 20, 40), M.Wood, J.Arm)
	local moon = grip * CF(0, 0, -5.2) * ANG(rad(90), 0, 0)
	b:Ring("Crescent", moon, 0.9, 14, 0.2, 0.14, GOLD, M.Foil, J.Arm, function(i)
		return i >= 4 and i <= 7
	end)
	local star = b:Ball("StaffStar", 0.4, (moon).Position, C3(255, 245, 210), M.Neon, J.Arm)
	b:Emit(star, { Color = C3(255, 230, 150), Size = 0.15, Rate = 10, Life = 1.6, Speed = 1.2 })
	-- dark moon held in the left hand
	local dm = J.WrL + V(0, 0.6, 0)
	b:Ball("DarkMoon", 0.9, dm, C3(20, 14, 30), M.Slate)
	b:Ring("DarkMoonRing", CF(dm) * ANG(rad(70), 0, rad(20)), 0.65, 12, 0.05, 0.08, glow, M.Neon)
	b:Emit(J.Torso, { Color = C3(255, 230, 150), Color2 = C3(180, 140, 255), Size = 0.18, Rate = 16, Life = 3, Speed = 1.5, Accel = V(0, -1, 0) })
	return 1.6, J.HeadTop + 1.5
end

-- 18 The Nameless General: blackened plate, spiked pauldrons, horned helm, war banners.
Build[18] = function(b, def)
	local glow = def.Model.Glow
	local black = C3(36, 34, 34)
	local J = biped(b, { ChestW = 2.5, ChestD = 1.4, ChestH = 2.4, ArmW = 0.9, LegW = 1.0, Head = 1.0,
		Body = black, BodyMat = M.Metal, Limb = C3(30, 28, 28), LimbMat = M.Metal, Joint = C3(60, 20, 16) })
	b:Box("Breastplate", V(J.CW * 1.05, 1.6, 0.25), CF(0, J.ChestY + 0.3, J.Front - 0.1) * ANG(rad(-5), 0, 0), C3(46, 44, 44), M.Metal)
	b:Cracks(CF(0, J.ChestY + 0.3, J.Front - 0.24), 2.0, 1.4, 4, glow, M.Neon, 181)
	b:Skirt("Tassets", V(0, J.Base + 0.15, 0), J.CW * 0.55, J.CW * 0.78, 1.7, 10, C3(40, 38, 38), M.Metal, { Rag = 0.2, Alt = C3(80, 16, 14) })
	for side = -1, 1, 2 do
		local sh = (if side > 0 then J.ShR else J.ShL) + V(side * 0.15, 0.45, 0)
		pauldron(b, sh, side, 1.45, C3(44, 42, 42), M.Metal, 3, C3(90, 20, 16))
		for k = -1, 1 do
			b:Spike("PauldronSpike", sh + V(side * 0.3, 0.3, k * 0.4), sh + V(side * 1.1, 1.2, k * 0.55), 0.35, 0.3, C3(30, 28, 28), M.Metal, nil, true)
		end
	end
	-- horned great helm, faceless slit
	local hc, h = J.HeadCf, J.HeadSize
	b:Box("Helm", V(h * 1.08, h * 1.25, h * 1.12), hc * CF(0, 0.05, 0), C3(40, 38, 38), M.Metal)
	b:Spike("HelmRidge", (hc * CF(0, h * 0.45, -h * 0.5)).Position, (hc * CF(0, h * 0.95, h * 0.2)).Position, 0.25, 0.3, C3(30, 28, 28), M.Metal)
	b:Box("FaceSlit", V(h * 0.12, h * 0.6, 0.06), hc * CF(0, -h * 0.05, -h * 0.57), glow, M.Neon)
	b:Box("FaceSlit", V(h * 0.75, h * 0.08, 0.06), hc * CF(0, h * 0.15, -h * 0.57), glow, M.Neon)
	for side = -1, 1, 2 do
		local p0 = (hc * CF(side * h * 0.5, h * 0.35, 0)).Position
		local p1 = p0 + V(side * 0.8, 0.35, 0.2)
		local p2 = p1 + V(side * 0.5, 0.8, 0.1)
		b:Rod("Horn", p0, p1, 0.35, 0.35, BONE, M.SmoothPlastic)
		b:Rod("Horn", p1, p2, 0.27, 0.27, C3(190, 180, 150), M.SmoothPlastic)
		b:Spike("HornTip", p2, p2 + V(side * -0.1, 0.7, -0.3), 0.27, 0.22, C3(160, 150, 120), M.SmoothPlastic, nil, true)
	end
	-- war cape and twin back banners
	b:Cape("WarCape", V(0, J.ChestTop, J.Back + 0.15), J.CW * 1.05, 4.2, 8, C3(90, 16, 14), M.Fabric, { Seed = 18, Rag = 0.5 })
	for side = -1, 1, 2 do
		local base = V(side * 0.75, J.ChestY - 0.4, J.Back + 0.45)
		local top = base + V(side * 0.6, 5.0, 0.4)
		b:Cyl("BannerPole", base, top, 0.18, C3(30, 24, 22), M.Wood)
		b:Spike("BannerTip", top, top + V(side * 0.1, 0.6, 0.05), 0.3, 0.12, C3(120, 110, 100), M.Metal, nil, true)
		local fa = top + V(0, -0.3, 0.05)
		b:Panel("Banner", fa, fa + V(side * 0.15, -2.0, 0.15), V(0, 0, 1), 1.4, 0.06, C3(110, 18, 14), M.Fabric)
		b:Box("BannerSigil", V(0.08, 0.6, 0.6), CF(fa + V(side * 0.12, -0.9, 0.12)), glow, M.Neon)
		b:Panel("Banner", fa + V(side * 0.15, -2.0, 0.15), fa + V(side * 0.2, -2.6, 0.5), V(0, 0, 1), 0.9, 0.06, C3(80, 12, 10), M.Fabric)
	end
	greatsword(b, J.Grip, J.Arm, { Len = 6.4, Width = 0.8, Metal = C3(70, 66, 66), Trim = C3(40, 38, 38), Fuller = glow, FullerMat = M.Neon, Notches = 18 })
	b:Emit(J.Torso, { Color = C3(255, 110, 50), Color2 = C3(255, 40, 20), Size = 0.12, Rate = 10, Life = 2.4, Speed = 2, Accel = V(0, 3, 0) })
	return 1.7, J.HeadTop + 1.2
end

-- 19 The Godbreaker: marble colossus mended with gold, floating halo shards, titan hammer.
Build[19] = function(b, def)
	local glow = def.Model.Glow
	local marble = C3(222, 216, 206)
	local J = biped(b, { ChestW = 2.9, ChestD = 1.7, ChestH = 2.6, ArmW = 1.05, ArmLen = 2.8, LegW = 1.15, Head = 1.0,
		Body = marble, BodyMat = M.Marble, Limb = C3(210, 204, 194), LimbMat = M.Marble, Joint = GOLD, HeadMat = M.Marble })
	-- kintsugi: gold seams over every surface
	b:Cracks(CF(0, J.ChestY, J.Front - 0.03), J.CW * 0.95, 2.4, 9, C3(230, 190, 80), M.Foil, 191, 0.08)
	b:Cracks(CF(0, J.ChestY, J.Back + 0.03) * ANG(0, math.pi, 0), J.CW * 0.95, 2.4, 6, C3(230, 190, 80), M.Foil, 192, 0.08)
	for side = -1, 1, 2 do
		b:Cracks(CF(side * (J.CW / 2 + 0.02), J.ChestY, 0) * ANG(0, side * rad(90), 0), J.CD * 0.9, 2.2, 3, C3(230, 190, 80), M.Foil, 193 + side, 0.08)
		b:Rod("ThighSeam", V(side * 0.75, J.Leg, -0.6), V(side * 0.8, J.Leg * 0.55, -0.82), 0.08, 0.08, glow, M.Neon)
	end
	b:Rod("ArmSeam", J.ShR + V(0.1, -0.3, -0.5), J.ElR + V(0.1, 0, -0.5), 0.08, 0.08, glow, M.Neon, J.Arm)
	b:Rod("ArmSeam", J.ShL + V(-0.1, -0.3, -0.5), J.ElL + V(-0.1, 0, -0.5), 0.08, 0.08, glow, M.Neon)
	-- gilded armour plates (Armor mechanic)
	local plates = {
		{ V(2.2, 1.4, 0.25), CF(0, J.ChestY + 0.4, J.Front - 0.15) },
		{ V(1.4, 0.4, 1.6), CF(J.ShR + V(0.1, 0.6, 0)) * ANG(0, 0, rad(-14)) },
		{ V(1.4, 0.4, 1.6), CF(J.ShL + V(-0.1, 0.6, 0)) * ANG(0, 0, rad(14)) },
		{ V(2.4, 0.6, 1.8), CF(0, J.Base + 0.2, 0) },
	}
	for i, pl in plates do
		local p = b:Box("ArmorPlate", pl[1], pl[2], C3(212, 172, 72), M.Foil)
		p:SetAttribute("Plate", i)
	end
	b:Skirt("MarbleDrape", V(0, J.Base + 0.1, 0), J.CW * 0.5, J.CW * 0.7, 1.8, 12, C3(236, 232, 224), M.Marble, { Rag = 0.1 })
	-- serene blank mask, gold eyes, broken nose
	local hc, h = J.HeadCf, J.HeadSize
	b:Ell("Mask", V(h * 0.85, h * 1.05, 0.35), hc * CF(0, 0, -h * 0.38), C3(240, 236, 228), M.Marble)
	eyes(b, J, glow, { Z = 0.58, Spread = 0.2, W = 0.2, H = 0.05 })
	b:Rod("MaskSeam", (hc * CF(-h * 0.1, h * 0.45, -h * 0.55)).Position, (hc * CF(h * 0.15, -h * 0.45, -h * 0.56)).Position, 0.06, 0.06, C3(230, 190, 80), M.Foil)
	-- floating halo shards (separate pieces with gaps, held in place)
	local halo = hc * CF(0, h * 0.25, h * 1.1)
	for i = 1, 9 do
		local th = i / 9 * TAU
		local p = (halo * CF(math.cos(th) * 1.9, math.sin(th) * 1.9, 0)).Position
		local q = (halo * CF(math.cos(th + 0.45) * 1.9, math.sin(th + 0.45) * 1.9, 0)).Position
		b:Rod("HaloShard", p, q, 0.25, 0.2, if i % 3 == 0 then glow else C3(230, 190, 80), if i % 3 == 0 then M.Neon else M.Foil)
	end
	for i = 1, 6 do
		local th = i / 6 * TAU + 0.3
		local p = (halo * CF(math.cos(th) * 2.7, math.sin(th) * 2.7, 0.3)).Position
		b:Box("MarbleShard", V(0.5, 0.35, 0.3), CF(p) * ANG(th, th * 2, 0), marble, M.Marble)
	end
	local haloLight = b:Box("HaloLight", V(0.1, 0.1, 0.1), halo, glow, M.Neon)
	b:Light(haloLight, glow, 12, 1.8)
	b:Emit(haloLight, { Color = C3(255, 230, 140), Size = 0.15, Rate = 10, Life = 2, Speed = 1.2 })
	warhammer(b, CF(J.WrR) * ANG(rad(-8), 0, 0), J.Arm, { Head = C3(230, 226, 218), HeadMat = M.Marble, Trim = C3(212, 172, 72), TrimMat = M.Foil, Glow = glow, Haft = C3(200, 194, 184), HaftMat = M.Marble })
	return 2.0, J.HeadTop + 2.2
end

-- 20 The Sovereign of Ruin: charred king with molten cracks, burning broken crown, ragged
--    royal robes, shadow cape and a burning greatsword.
Build[20] = function(b, def)
	local glow = def.Model.Glow
	local char = C3(30, 26, 28)
	local J = biped(b, { ChestW = 2.5, ChestD = 1.4, ChestH = 2.5, ArmW = 0.92, LegW = 1.0, Head = 1.0,
		Body = char, BodyMat = M.Basalt, Limb = C3(26, 22, 24), LimbMat = M.Basalt, Joint = C3(255, 80, 30) })
	-- molten veins
	b:Cracks(CF(0, J.ChestY, J.Front - 0.03), J.CW * 0.9, 2.3, 9, glow, M.Neon, 201)
	b:Cracks(CF(0, J.ChestY, J.Back + 0.03) * ANG(0, math.pi, 0), J.CW * 0.9, 2.3, 5, glow, M.Neon, 202)
	for side = -1, 1, 2 do
		b:Rod("LegVein", V(side * 0.7, J.Leg, -0.5), V(side * 0.75, 0.6, -0.55), 0.08, 0.08, glow, M.Neon)
	end
	b:Rod("ArmVein", J.ShR + V(0.05, -0.3, -0.45), J.WrR + V(0, 0.3, 0), 0.08, 0.08, glow, M.Neon, J.Arm)
	local heart = b:Ball("RuinHeart", 0.6, V(0, J.ChestY + 0.35, J.Front - 0.05), C3(255, 140, 60), M.Neon)
	b:Light(heart, glow, 12, 2.4)
	-- ragged royal robes over the charred plate
	b:Skirt("RoyalRobe", V(0, J.Base + 0.2, 0), J.CW * 0.55, J.CW * 0.95, J.Leg + 0.2, 14, C3(90, 14, 24), M.Fabric, { Rag = 0.5, Seed = 20, Alt = C3(70, 10, 18) })
	b:Ring("RobeGold", CF(0, J.Base + 0.2, 0), J.CW * 0.56, 14, 0.08, 0.2, OLD_GOLD, M.Metal)
	pauldron(b, J.ShR + V(0.1, 0.4, 0), 1, 1.3, C3(40, 34, 36), M.Basalt, 3, OLD_GOLD)
	pauldron(b, J.ShL + V(-0.1, 0.4, 0), -1, 1.3, C3(40, 34, 36), M.Basalt, 3, OLD_GOLD)
	-- shadow cape: long, many-tailed, trailing smoke
	b:Cape("ShadowCape", V(0, J.ChestTop + 0.05, J.Back + 0.2), J.CW * 1.35, J.ChestTop - 0.3, 12, C3(12, 8, 14), M.Fabric, { Seed = 21, Rag = 0.45, Flare = 1.6, Billow = 0.6, Drift = 0.35 })
	local capeSmoke = b:Box("CapeShadow", V(2, 0.2, 0.2), CF(0, J.Base - 1, J.Back + 1.6), BLACK, M.Fabric)
	capeSmoke.Transparency = 1
	b:Emit(capeSmoke, { Color = C3(14, 10, 16), Size = 1.2, Rate = 12, Life = 2.5, Speed = 0.8, Accel = V(0, 0.6, 0), Emission = 0, Trans = 0.35, EndSize = 1.6 })
	-- burned skull face and the broken, burning crown
	local hc, h = J.HeadCf, J.HeadSize
	b:Ell("CharredFace", V(h * 0.9, h * 1.0, h * 0.95), hc, C3(40, 32, 30), M.Basalt)
	eyes(b, J, C3(255, 200, 120), { Z = 0.47, Spread = 0.2, W = 0.17, H = 0.08 })
	b:Box("Maw", V(h * 0.4, h * 0.1, 0.05), hc * CF(0, -h * 0.3, -h * 0.47), glow, M.Neon)
	b:Ring("BrokenCrown", hc * CF(0, h * 0.55, 0) * ANG(0, 0, rad(-8)), h * 0.62, 12, 0.14, 0.32, GOLD, M.Foil, nil, function(i)
		return i == 3 or i == 4
	end)
	for i = 1, 12 do
		if i ~= 3 and i ~= 4 then
			local th = (i - 0.5) / 12 * TAU
			local base = (hc * CF(0, h * 0.55, 0) * ANG(0, 0, rad(-8)) * CF(math.cos(th) * h * 0.62, 0.12, math.sin(th) * h * 0.62)).Position
			local tall = if i % 3 == 0 then 0.25 else if i % 2 == 0 then 0.9 else 0.6
			b:Spike("CrownPoint", base, base + V(0, tall, 0), 0.28, 0.1, GOLD, M.Foil)
		end
	end
	local crownFire = b:Box("CrownFire", V(0.6, 0.3, 0.6), hc * CF(0, h * 0.8, 0), glow, M.Neon)
	crownFire.Transparency = 1
	b:Fire(crownFire, C3(255, 120, 40), C3(160, 20, 10), 1.1, 10)
	b:Ball("CrownRuby", 0.25, (hc * CF(0, h * 0.62, -h * 0.66)).Position, C3(220, 20, 30), M.Neon)
	-- burning greatsword
	local mid = greatsword(b, J.Grip, J.Arm, { Len = 7, Width = 0.9, Metal = C3(36, 30, 30), Mat = M.Basalt, Trim = OLD_GOLD, Fuller = glow, FullerMat = M.Neon })
	local bladeFire = b:Box("BladeFire", V(0.2, 0.2, 0.2), CF(mid), glow, M.Neon, J.Arm)
	bladeFire.Transparency = 1
	b:Fire(bladeFire, C3(255, 120, 40), C3(180, 30, 10), 1.0, 12)
	b:Emit(J.Torso, { Color = C3(255, 120, 40), Color2 = C3(255, 40, 20), Size = 0.14, Rate = 18, Life = 2.4, Speed = 2.5, Accel = V(0, 4, 0) })
	return 1.9, J.HeadTop + 1.2
end

-- ===================================================================== entry
-- Root/hip setup per floor: { hip, rootSize } in design units.
local FRAME = {
	[5] = { 1.8, V(2.2, 1.6, 4.2) },
	[16] = { 6.0, V(3, 3, 3) },
}

function BossModels.has(floor: number): boolean
	return Build[floor] ~= nil
end

-- Builds the sculpted model for a boss def. `index` distinguishes twins (1 = Judge, 2 = Sentence).
function BossModels.build(def, index: number?, name: string?)
	local floor = def.Floor
	local builder = Build[floor]
	local displayName = name or def.Name
	if not builder then
		return EntityModels.build(displayName, def.Model, "Boss")
	end
	local ok, result = pcall(function()
		local s = def.Model.Scale or 1
		local frame = FRAME[floor]
		-- bipeds: the root spans the pelvis and sits right on top of the legs
		local hip = if frame then frame[1] else (BossModels.LegLength[floor] or 2)
		local rootSize = if frame then frame[2] else V(2, 2, 1.2)
		local b = newBuilder(displayName, s, hip, rootSize)
		local radius, height = Build[floor](b, def, index or 1)
		local hipStuds: number? = nil
		if def.Mechanics and def.Mechanics.Airborne then
			-- airborne bosses hover Airborne.Height above their landed pose
			hipStuds = hip * s + def.Mechanics.Airborne.Height
		end
		return table.pack(b:Finish("Boss", radius, height, hipStuds))
	end)
	if ok then
		return table.unpack(result, 1, result.n)
	end
	warn("[BossModels] sculpted build failed for floor " .. tostring(floor) .. ": " .. tostring(result))
	return EntityModels.build(displayName, def.Model, "Boss")
end

-- Leg length (design units) used by each biped builder; root sits right on top of the legs.
BossModels.LegLength = {
	[1] = 2.1, [2] = 1.6, [3] = 1.8, [4] = 2.1, [6] = 2.0, [7] = 1.7, [8] = 2.6, [9] = 2.4, [10] = 1.6,
	[11] = 2.4, [12] = 2.4, [13] = 2.2, [14] = 2.0, [15] = 2.2, [17] = 2.6, [18] = 2.2, [19] = 2.0, [20] = 2.3,
}

return BossModels
