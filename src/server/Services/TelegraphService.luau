--[[
	TelegraphService
	Ground indicators for hostile attacks and persistent hazard zones.

	Colour language (clients may remap for high-contrast accessibility):
	  Gold   = parryable          (Attribute Telegraph = "Parry")
	  White  = blockable          (Attribute Telegraph = "Block")
	  Red    = unblockable        (Attribute Telegraph = "Danger")
	  Green  = safe zone          (Attribute Telegraph = "Safe")
	  Purple = lingering hazard   (Attribute Telegraph = "Hazard")
	A filling inner shape shows exactly when the attack lands.
]]

local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local TelegraphService = {}

local folder: Folder

TelegraphService.Colors = {
	Parry = Color3.fromRGB(255, 196, 60),
	Block = Color3.fromRGB(235, 235, 235),
	Danger = Color3.fromRGB(225, 40, 40),
	Safe = Color3.fromRGB(70, 220, 110),
	Hazard = Color3.fromRGB(150, 70, 220),
}

function TelegraphService.Init(_services)
	folder = Instance.new("Folder")
	folder.Name = "Telegraphs"
	folder.Parent = workspace
end

function TelegraphService.Start() end

function TelegraphService.KindFor(attack): string
	if attack.Parryable then
		return "Parry"
	elseif attack.Blockable then
		return "Block"
	end
	return "Danger"
end

local function flat(name: string, size: Vector3, cf: CFrame, kind: string, transparency: number, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = TelegraphService.Colors[kind] or TelegraphService.Colors.Danger
	p.Transparency = transparency
	p.Size = size
	if shape then
		p.Shape = shape
	end
	p.CFrame = cf
	p:SetAttribute("Telegraph", kind)
	p.Parent = folder
	return p
end

local function disc(name, center: Vector3, radius: number, kind, transparency, yOff: number?)
	return flat(name, Vector3.new(0.2, radius * 2, radius * 2), CFrame.new(center + Vector3.new(0, 0.15 + (yOff or 0), 0)) * CFrame.Angles(0, 0, math.rad(90)), kind, transparency, Enum.PartType.Cylinder)
end

-- Triangle on the ground from two wedges.
local function triangle(model: Instance, a: Vector3, b: Vector3, c: Vector3, kind: string, transparency: number)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	for i = 1, 2 do
		local w = Instance.new("WedgePart")
		w.Anchored = true
		w.CanCollide = false
		w.CanQuery = false
		w.CanTouch = false
		w.CastShadow = false
		w.Material = Enum.Material.Neon
		w.Color = TelegraphService.Colors[kind]
		w.Transparency = transparency
		w:SetAttribute("Telegraph", kind)
		if i == 1 then
			w.Size = Vector3.new(0.2, height, math.abs(ab:Dot(back)))
			w.CFrame = CFrame.fromMatrix((a + b) / 2, right, up, back)
		else
			w.Size = Vector3.new(0.2, height, math.abs(ac:Dot(back)))
			w.CFrame = CFrame.fromMatrix((a + c) / 2, -right, up, -back)
		end
		w.Parent = model
	end
end

--[[
	Shows a telegraph for `duration` seconds and removes it afterwards.
	shape: Circle(Center, Radius) | Ring(Center, Inner, Outer) | Line(Origin, Dir, Length, Width)
	       | Cone(Origin, Dir, Range, Arc) | Pulse(Center, Radius, SafeZones = {Vector3}, SafeRadius)
]]
function TelegraphService.Show(spec, duration: number)
	local kind = spec.Kind or "Danger"
	local container = Instance.new("Model")
	container.Name = "Telegraph"
	container.Parent = folder
	local y = spec.GroundY or (spec.Center and spec.Center.Y) or (spec.Origin and spec.Origin.Y) or 0
	local fillTween
	if spec.Shape == "Circle" or spec.Shape == "Hazard" then
		local outer = disc("Outer", spec.Center, spec.Radius, kind, 0.65)
		outer.Parent = container
		local inner = disc("Fill", spec.Center, 0.1, kind, 0.35, 0.02)
		inner.Parent = container
		fillTween = TweenService:Create(inner, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Size = Vector3.new(0.2, spec.Radius * 2, spec.Radius * 2) })
	elseif spec.Shape == "Ring" then
		local outer = disc("Outer", spec.Center, spec.Outer, kind, 0.55)
		outer.Parent = container
		local safe = disc("Safe", spec.Center, spec.Inner, "Safe", 0.45, 0.03)
		safe.Parent = container
	elseif spec.Shape == "Line" then
		local dir = Vector3.new(spec.Dir.X, 0, spec.Dir.Z).Unit
		local origin = Vector3.new(spec.Origin.X, y, spec.Origin.Z)
		local cf = CFrame.lookAt(origin, origin + dir)
		local outer = flat("Outer", Vector3.new(spec.Width, 0.2, spec.Length), cf * CFrame.new(0, 0.15, -spec.Length / 2), kind, 0.65)
		outer.Parent = container
		local inner = flat("Fill", Vector3.new(spec.Width, 0.22, 0.1), cf * CFrame.new(0, 0.17, -0.05), kind, 0.35)
		inner.Parent = container
		fillTween = TweenService:Create(inner, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
			Size = Vector3.new(spec.Width, 0.22, spec.Length),
			CFrame = cf * CFrame.new(0, 0.17, -spec.Length / 2),
		})
	elseif spec.Shape == "Cone" then
		local dir = Vector3.new(spec.Dir.X, 0, spec.Dir.Z).Unit
		local origin = Vector3.new(spec.Origin.X, y + 0.15, spec.Origin.Z)
		local half = math.rad(math.min(spec.Arc, 359)) / 2
		local segments = math.clamp(math.ceil(spec.Arc / 30), 2, 8)
		local base = math.atan2(dir.X, dir.Z)
		local prev
		for i = 0, segments do
			local ang = base - half + (2 * half) * (i / segments)
			local pt = origin + Vector3.new(math.sin(ang), 0, math.cos(ang)) * spec.Range
			if prev then
				triangle(container, origin, prev, pt, kind, 0.55)
			end
			prev = pt
		end
	elseif spec.Shape == "Pulse" then
		local outer = disc("Outer", spec.Center, spec.Radius, "Danger", 0.75)
		outer.Parent = container
		for _, z in spec.SafeZones or {} do
			local s = disc("Safe", z, spec.SafeRadius, "Safe", 0.3, 0.04)
			s.Parent = container
		end
	end
	if fillTween then
		fillTween:Play()
	end
	Debris:AddItem(container, duration + 0.05)
	return container
end

-- A lingering hazard zone (purple disc) for `duration` seconds.
function TelegraphService.Hazard(center: Vector3, radius: number, duration: number)
	local p = disc("Hazard", center, radius, "Hazard", 0.55)
	local smoke = Instance.new("ParticleEmitter")
	smoke.Color = ColorSequence.new(TelegraphService.Colors.Hazard)
	smoke.Rate = math.clamp(radius * 2, 5, 30)
	smoke.Lifetime = NumberRange.new(1, 2)
	smoke.Speed = NumberRange.new(1, 3)
	smoke.Size = NumberSequence.new(2, 4)
	smoke.Transparency = NumberSequence.new(0.6, 1)
	smoke.Parent = p
	Debris:AddItem(p, duration)
	return p
end

-- Brief impact flash at a position.
function TelegraphService.Impact(center: Vector3, radius: number, color: Color3?)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.Neon
	p.Color = color or Color3.fromRGB(255, 200, 150)
	p.Transparency = 0.4
	p.Size = Vector3.new(1, 1, 1) * math.max(1, radius * 0.6)
	p.CFrame = CFrame.new(center)
	p.Parent = folder
	TweenService:Create(p, TweenInfo.new(0.3), { Size = Vector3.new(1, 1, 1) * radius * 2, Transparency = 1 }):Play()
	Debris:AddItem(p, 0.35)
end

return TelegraphService
