--[[
	EntityModels
	Procedural, original silhouettes for enemies, bosses and player weapons, built from parts.
	No external assets are required. Each model has:
	  HumanoidRootPart (collidable, invisible), Humanoid (movement only; HP is custom),
	  body parts welded to the root, and an "Arm" Motor6D used for simple swing animations.

	Styles: Humanoid, Brute, Beast, Crawler, Caster, Colossus, Golem, Winged, Serpent
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared.Config.Items)
local Cosmetics = require(Shared.Config.Cosmetics)

local EntityModels = {}

local function darker(c: Color3, f: number): Color3
	return Color3.new(c.R * f, c.G * f, c.B * f)
end

local function newPart(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Anchored = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
end

local function addGlow(part: BasePart, color: Color3, range: number)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = 1.4
	light.Parent = part
end

-- Weapon mesh made of parts, attached to `hand` facing forward/down.
local function buildWeapon(model: Model, hand: BasePart, kind: string, s: number, color: Color3)
	local base = hand.CFrame * CFrame.new(0, -hand.Size.Y / 2, 0)
	local metal = Color3.fromRGB(150, 150, 155)
	local parts = {}
	if kind == "Sword" or kind == "Rapier" or kind == "Greatsword" then
		local len = (if kind == "Greatsword" then 7 elseif kind == "Rapier" then 4.5 else 5) * s
		local width = (if kind == "Greatsword" then 0.9 elseif kind == "Rapier" then 0.25 else 0.5) * s
		table.insert(parts, newPart(model, "Blade", Vector3.new(0.2 * s, len, width), base * CFrame.new(0, -len / 2 - 0.4 * s, 0), metal, Enum.Material.Metal))
		table.insert(parts, newPart(model, "Guard", Vector3.new(0.3 * s, 0.3 * s, 1.6 * s * width + 0.6 * s), base * CFrame.new(0, -0.3 * s, 0), color, Enum.Material.Metal))
	elseif kind == "Axe" or kind == "Cleaver" then
		table.insert(parts, newPart(model, "Haft", Vector3.new(0.3 * s, 4 * s, 0.3 * s), base * CFrame.new(0, -2 * s, 0), Color3.fromRGB(70, 50, 35), Enum.Material.Wood))
		local headSize = if kind == "Cleaver" then Vector3.new(0.3 * s, 2.6 * s, 2.4 * s) else Vector3.new(0.3 * s, 1.6 * s, 1.6 * s)
		table.insert(parts, newPart(model, "Head", headSize, base * CFrame.new(0, -3.5 * s, 0.8 * s), metal, Enum.Material.Metal))
	elseif kind == "Hammer" or kind == "Club" then
		table.insert(parts, newPart(model, "Haft", Vector3.new(0.35 * s, 4.5 * s, 0.35 * s), base * CFrame.new(0, -2.2 * s, 0), Color3.fromRGB(70, 50, 35), Enum.Material.Wood))
		table.insert(parts, newPart(model, "Head", Vector3.new(1.4 * s, 1.4 * s, 2.2 * s), base * CFrame.new(0, -4.6 * s, 0), if kind == "Club" then Color3.fromRGB(90, 70, 50) else metal, if kind == "Club" then Enum.Material.Wood else Enum.Material.Metal))
	elseif kind == "Spear" or kind == "Scythe" then
		table.insert(parts, newPart(model, "Haft", Vector3.new(0.3 * s, 8 * s, 0.3 * s), base * CFrame.new(0, -3 * s, 0), Color3.fromRGB(60, 45, 35), Enum.Material.Wood))
		local tip = if kind == "Scythe" then Vector3.new(0.2 * s, 0.6 * s, 3.4 * s) else Vector3.new(0.3 * s, 1.6 * s, 0.6 * s)
		table.insert(parts, newPart(model, "Tip", tip, base * CFrame.new(0, -7.2 * s, if kind == "Scythe" then 1.5 * s else 0), metal, Enum.Material.Metal))
	elseif kind == "Bow" then
		table.insert(parts, newPart(model, "Bow", Vector3.new(0.3 * s, 4.5 * s, 0.3 * s), base * CFrame.new(0, -1.2 * s, 0.6 * s), Color3.fromRGB(80, 60, 40), Enum.Material.Wood))
	end
	for _, p in parts do
		weld(hand, p)
	end
end

-- Builds an entity model. Returns model, root, humanoid, hitRadius, height.
function EntityModels.build(name: string, def, kind: string?)
	local s = def.Scale or 1
	local color = def.Color or Color3.fromRGB(120, 120, 120)
	local glow = def.Glow
	local style = def.Style or "Humanoid"

	local model = Instance.new("Model")
	model.Name = name
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Transparency = 1
	root.CanCollide = true
	root.CanQuery = false
	root.CanTouch = false
	root.CFrame = CFrame.new()
	root.Parent = model
	model.PrimaryPart = root

	local hipHeight, radius, height = 2 * s, 1.5 * s, 5 * s
	local arm: BasePart? = nil
	local shoulder: Motor6D? = nil
	local rootCf = root.CFrame

	local function attachArm(torso: BasePart, side: number, size: Vector3, offset: Vector3)
		local a = newPart(model, if side > 0 then "RightArm" else "LeftArm", size, torso.CFrame * CFrame.new(offset), darker(color, 0.85))
		if side > 0 then
			local m = Instance.new("Motor6D")
			m.Name = "Shoulder"
			m.Part0 = torso
			m.Part1 = a
			-- joint at the top of the arm
			m.C0 = CFrame.new(offset + Vector3.new(0, size.Y / 2, 0))
			m.C1 = CFrame.new(0, size.Y / 2, 0)
			m.Parent = torso
			arm = a
			shoulder = m
		else
			weld(torso, a)
		end
		return a
	end

	if style == "Humanoid" or style == "Brute" or style == "Colossus" or style == "Golem" or style == "Winged" then
		local bulk = if style == "Brute" then 1.5 elseif style == "Colossus" then 1.8 elseif style == "Golem" then 1.7 else 1
		local legLen = (if style == "Brute" or style == "Golem" then 1.6 else 2) * s
		root.Size = Vector3.new(2 * s * bulk, 2 * s, 1 * s * bulk)
		hipHeight = legLen
		if style == "Winged" then
			hipHeight = legLen + 14
		end
		local mat = if style == "Golem" then Enum.Material.Slate elseif style == "Colossus" then Enum.Material.Ground else Enum.Material.SmoothPlastic
		local torso = newPart(model, "Torso", Vector3.new(2 * s * bulk, 2.2 * s, 1.1 * s * bulk), rootCf, color, mat)
		weld(root, torso)
		local head = newPart(model, "Head", Vector3.new(1.1 * s, 1.1 * s, 1.1 * s) * (if bulk > 1 then 0.9 else 1), rootCf * CFrame.new(0, 1.7 * s, 0), darker(color, 0.9), mat, Enum.PartType.Ball)
		weld(torso, head)
		if glow then
			local eyes = newPart(model, "Eyes", Vector3.new(0.7 * s, 0.15 * s, 0.1 * s), head.CFrame * CFrame.new(0, 0.1 * s, -0.5 * s), glow, Enum.Material.Neon)
			weld(head, eyes)
		end
		local armSize = Vector3.new(0.9 * s * bulk, 2.2 * s, 0.9 * s * bulk)
		local ax = (1 * bulk + 0.5 * bulk) * s
		attachArm(torso, 1, armSize, Vector3.new(ax, 0, 0))
		attachArm(torso, -1, armSize, Vector3.new(-ax, 0, 0))
		for side = -1, 1, 2 do
			local leg = newPart(model, "Leg", Vector3.new(0.95 * s * bulk, legLen, 0.95 * s * bulk), rootCf * CFrame.new(side * 0.55 * s * bulk, -1.1 * s - legLen / 2, 0), darker(color, 0.7), mat)
			weld(torso, leg)
		end
		if def.Hood then
			local hood = newPart(model, "Hood", Vector3.new(1.4 * s, 1.4 * s, 1.4 * s), head.CFrame * CFrame.new(0, 0.2 * s, 0.1 * s), darker(color, 0.5), Enum.Material.Fabric, Enum.PartType.Ball)
			weld(head, hood)
		end
		if def.Crown then
			local crown = newPart(model, "Crown", Vector3.new(1.2 * s, 0.4 * s, 1.2 * s), head.CFrame * CFrame.new(0, 0.7 * s, 0), Color3.fromRGB(200, 170, 60), Enum.Material.Foil)
			weld(head, crown)
		end
		if def.Cape then
			local cape = newPart(model, "Cape", Vector3.new(2 * s * bulk, 3.5 * s, 0.15 * s), torso.CFrame * CFrame.new(0, -0.6 * s, 0.65 * s * bulk), darker(glow or color, 0.4), Enum.Material.Fabric)
			weld(torso, cape)
		end
		if def.Shield then
			local sh = newPart(model, "Shield", Vector3.new(0.3 * s, 2.6 * s, 2 * s), torso.CFrame * CFrame.new(-ax - 0.6 * s, 0, -0.3 * s), Color3.fromRGB(90, 95, 110), Enum.Material.Metal)
			weld(torso, sh)
		end
		if style == "Golem" then
			for i, off in { Vector3.new(0, 0.3, -0.7), Vector3.new(0.9, 0.9, 0), Vector3.new(-0.9, 0.9, 0) } do
				local plate = newPart(model, "ArmorPlate", Vector3.new(1.4, 1, 0.4) * s * bulk, torso.CFrame * CFrame.new(off * s * bulk), Color3.fromRGB(110, 110, 120), Enum.Material.DiamondPlate)
				plate:SetAttribute("Plate", i)
				weld(torso, plate)
			end
			if glow then
				local core = newPart(model, "Core", Vector3.new(0.9, 0.9, 0.9) * s, torso.CFrame * CFrame.new(0, 0, -0.6 * s * bulk), glow, Enum.Material.Neon, Enum.PartType.Ball)
				weld(torso, core)
				addGlow(core, glow, 18)
			end
		end
		if style == "Winged" then
			for side = -1, 1, 2 do
				local wing = newPart(model, "Wing", Vector3.new(7 * s, 0.2 * s, 3 * s), torso.CFrame * CFrame.new(side * 4.2 * s, 0.6 * s, 0.6 * s) * CFrame.Angles(0, 0, side * math.rad(18)), darker(color, 0.8), Enum.Material.Fabric)
				weld(torso, wing)
			end
		end
		radius = 1.4 * s * bulk
		height = (2.2 + 1.1) * s + legLen
	elseif style == "Beast" then
		local legLen = 1.6 * s
		root.Size = Vector3.new(2.2 * s, 1.6 * s, 4 * s)
		hipHeight = legLen
		local body = newPart(model, "Torso", Vector3.new(2.2 * s, 1.6 * s, 4 * s), rootCf, color, Enum.Material.Fabric)
		weld(root, body)
		local head = newPart(model, "Head", Vector3.new(1.4 * s, 1.3 * s, 1.8 * s), rootCf * CFrame.new(0, 0.6 * s, -2.6 * s), darker(color, 0.9), Enum.Material.Fabric)
		weld(body, head)
		local jaw = newPart(model, "RightArm", Vector3.new(1.2 * s, 0.4 * s, 1.4 * s), head.CFrame * CFrame.new(0, -0.6 * s, -0.4 * s), darker(color, 0.6))
		local m = Instance.new("Motor6D")
		m.Name = "Shoulder"
		m.Part0 = head
		m.Part1 = jaw
		m.C0 = CFrame.new(0, -0.6 * s, 0.3 * s)
		m.C1 = CFrame.new(0, 0, 0.7 * s)
		m.Parent = head
		arm, shoulder = jaw, m
		if glow then
			local eyes = newPart(model, "Eyes", Vector3.new(1 * s, 0.15 * s, 0.1 * s), head.CFrame * CFrame.new(0, 0.25 * s, -0.9 * s), glow, Enum.Material.Neon)
			weld(head, eyes)
			addGlow(body, glow, 14)
		end
		for _, off in { Vector3.new(0.8, 0, -1.4), Vector3.new(-0.8, 0, -1.4), Vector3.new(0.8, 0, 1.4), Vector3.new(-0.8, 0, 1.4) } do
			local leg = newPart(model, "Leg", Vector3.new(0.6 * s, legLen, 0.6 * s), rootCf * CFrame.new(off.X * s, -0.8 * s - legLen / 2, off.Z * s), darker(color, 0.7))
			weld(body, leg)
		end
		local tail = newPart(model, "Tail", Vector3.new(0.4 * s, 0.4 * s, 2 * s), rootCf * CFrame.new(0, 0.4 * s, 2.8 * s) * CFrame.Angles(math.rad(25), 0, 0), darker(color, 0.8))
		weld(body, tail)
		radius = 2 * s
		height = 2.6 * s + legLen
	elseif style == "Crawler" then
		local legLen = 0.8 * s
		root.Size = Vector3.new(3 * s, 1 * s, 3 * s)
		hipHeight = legLen
		local body = newPart(model, "Torso", Vector3.new(3 * s, 1.2 * s, 3.4 * s), rootCf, color, Enum.Material.Slate)
		weld(root, body)
		local head = newPart(model, "Head", Vector3.new(1.4 * s, 0.9 * s, 1.2 * s), rootCf * CFrame.new(0, 0.2 * s, -2.1 * s), darker(color, 0.85), Enum.Material.Slate)
		weld(body, head)
		local pincer = newPart(model, "RightArm", Vector3.new(0.5 * s, 0.5 * s, 2 * s), head.CFrame * CFrame.new(0.9 * s, 0, -1 * s), darker(color, 0.6))
		local m = Instance.new("Motor6D")
		m.Name = "Shoulder"
		m.Part0 = head
		m.Part1 = pincer
		m.C0 = CFrame.new(0.9 * s, 0, -0.2 * s)
		m.C1 = CFrame.new(0, 0, 0.8 * s)
		m.Parent = head
		arm, shoulder = pincer, m
		for i = -1, 1 do
			for side = -1, 1, 2 do
				local leg = newPart(model, "Leg", Vector3.new(2 * s, 0.25 * s, 0.25 * s), rootCf * CFrame.new(side * 2 * s, -0.4 * s, i * 1.1 * s) * CFrame.Angles(0, 0, side * math.rad(-25)), darker(color, 0.6))
				weld(body, leg)
			end
		end
		if glow then
			addGlow(body, glow, 12)
		end
		radius = 2 * s
		height = 2 * s
	elseif style == "Caster" then
		root.Size = Vector3.new(2 * s, 2 * s, 1 * s)
		hipHeight = 1.6 * s
		local robe = newPart(model, "Torso", Vector3.new(2.4 * s, 4 * s, 2.4 * s), rootCf * CFrame.new(0, -0.6 * s, 0), color, Enum.Material.Fabric, Enum.PartType.Cylinder)
		robe.CFrame = rootCf * CFrame.new(0, -0.6 * s, 0) * CFrame.Angles(0, 0, math.rad(90))
		robe.Size = Vector3.new(4 * s, 2.2 * s, 2.2 * s)
		weld(root, robe)
		local chest = newPart(model, "Chest", Vector3.new(2 * s, 1.6 * s, 1.2 * s), rootCf * CFrame.new(0, 1.2 * s, 0), darker(color, 0.85), Enum.Material.Fabric)
		weld(root, chest)
		local head = newPart(model, "Head", Vector3.new(1.1 * s, 1.1 * s, 1.1 * s), rootCf * CFrame.new(0, 2.5 * s, 0), darker(color, 0.5), Enum.Material.Fabric, Enum.PartType.Ball)
		weld(chest, head)
		attachArm(chest, 1, Vector3.new(0.7 * s, 2 * s, 0.7 * s), Vector3.new(1.4 * s, 0, 0))
		attachArm(chest, -1, Vector3.new(0.7 * s, 2 * s, 0.7 * s), Vector3.new(-1.4 * s, 0, 0))
		if glow then
			for i = 1, 2 do
				local orb = newPart(model, "Orb", Vector3.new(0.7, 0.7, 0.7) * s, rootCf * CFrame.new((i == 1 and 1 or -1) * 2.2 * s, 2.6 * s, -0.6 * s), glow, Enum.Material.Neon, Enum.PartType.Ball)
				weld(chest, orb)
			end
			local eyes = newPart(model, "Eyes", Vector3.new(0.6 * s, 0.12 * s, 0.1 * s), head.CFrame * CFrame.new(0, 0, -0.5 * s), glow, Enum.Material.Neon)
			weld(head, eyes)
			addGlow(chest, glow, 16)
		end
		radius = 1.4 * s
		height = 5.5 * s
	elseif style == "Serpent" then
		root.Size = Vector3.new(3 * s, 3 * s, 3 * s)
		hipHeight = 6 * s
		local prev: BasePart = root
		for i = 0, 6 do
			local r = (3.2 - i * 0.3) * s
			local seg = newPart(model, if i == 0 then "Torso" else "Segment", Vector3.new(r, r, r), rootCf * CFrame.new(0, -i * 0.9 * s, i * 2.4 * s), if i % 2 == 0 then color else darker(color, 0.8), Enum.Material.Slate, Enum.PartType.Ball)
			weld(prev, seg)
			prev = seg
		end
		local head = newPart(model, "Head", Vector3.new(2.6 * s, 2 * s, 3.6 * s), rootCf * CFrame.new(0, 0.8 * s, -2.6 * s), darker(color, 0.9), Enum.Material.Slate)
		weld(root, head)
		local jaw = newPart(model, "RightArm", Vector3.new(2.2 * s, 0.6 * s, 3 * s), head.CFrame * CFrame.new(0, -1.2 * s, -0.3 * s), darker(color, 0.6), Enum.Material.Slate)
		local m = Instance.new("Motor6D")
		m.Name = "Shoulder"
		m.Part0 = head
		m.Part1 = jaw
		m.C0 = CFrame.new(0, -1.1 * s, 1.2 * s)
		m.C1 = CFrame.new(0, 0, 1.5 * s)
		m.Parent = head
		arm, shoulder = jaw, m
		if glow then
			local eyes = newPart(model, "Eyes", Vector3.new(2 * s, 0.3 * s, 0.2 * s), head.CFrame * CFrame.new(0, 0.5 * s, -1.8 * s), glow, Enum.Material.Neon)
			weld(head, eyes)
		end
		radius = 3 * s
		height = 8 * s
	end

	if def.Weapon and arm then
		buildWeapon(model, arm, def.Weapon, s, glow or color)
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.HipHeight = hipHeight
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.MaxHealth = 1e6
	humanoid.Health = 1e6
	humanoid.AutoJumpEnabled = true
	humanoid.Parent = model

	model:SetAttribute("Kind", kind or "Enemy")
	model:SetAttribute("Radius", radius)
	model:SetAttribute("Height", height)
	return model, root, humanoid, radius, height, shoulder
end

-- Simple swing animation on the "Shoulder" motor: raise during windup, strike on resolve.
-- Optional motor attributes "Windup"/"Strike" (degrees) override the arcs (jaws, paws).
function EntityModels.windup(motor: Motor6D?, duration: number)
	if not motor or not motor.Parent then
		return
	end
	local shoulder = motor :: Motor6D
	local base = shoulder:GetAttribute("BaseC0") or shoulder.C0
	shoulder:SetAttribute("BaseC0", base)
	TweenService:Create(shoulder, TweenInfo.new(math.max(0.05, duration * 0.8), Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		C0 = base * CFrame.Angles(math.rad(shoulder:GetAttribute("Windup") or 150), 0, 0),
	}):Play()
end

function EntityModels.strike(motor: Motor6D?)
	if not motor or not motor.Parent then
		return
	end
	local shoulder = motor :: Motor6D
	local base = shoulder:GetAttribute("BaseC0") or shoulder.C0
	local t = TweenService:Create(shoulder, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		C0 = base * CFrame.Angles(math.rad(shoulder:GetAttribute("Strike") or -40), 0, 0),
	})
	t:Play()
	task.delay(0.35, function()
		if shoulder.Parent then
			TweenService:Create(shoulder, TweenInfo.new(0.3), { C0 = base }):Play()
		end
	end)
end

-- ===================================================================== player held gear
-- Weapons are welded straight to the hand (no Tool), so orientation is exact and nothing
-- depends on Roblox's tool-grip behaviour. Grip space: origin at the hand, the blade
-- extends along -Z (forward when the arm hangs; upward when the arm is raised to strike).

local function gearPart(model: Model, name: string, size: Vector3, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	if shape then
		p.Shape = shape
	end
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.Parent = model
	return p
end

local function gripWeld(hand: BasePart, part: BasePart, grip: CFrame, offset: CFrame)
	local w = Instance.new("Weld")
	w.Part0 = hand
	w.Part1 = part
	w.C0 = grip * offset
	w.Parent = part
end

local function handGrip(character: Model, side: string): (BasePart?, CFrame)
	local r15 = character:FindFirstChild(side .. "Hand")
	if r15 and r15:IsA("BasePart") then
		return r15, CFrame.new(0, -r15.Size.Y / 2 + 0.05, 0)
	end
	local r6 = character:FindFirstChild(side .. " Arm")
	if r6 and r6:IsA("BasePart") then
		return r6, CFrame.new(0, -r6.Size.Y / 2 + 0.1, 0)
	end
	return nil, CFrame.new()
end

-- Returns { {name, size, offset(CFrame in grip space), role} } for a weapon type.
local function weaponLayout(def)
	local wtype = def.WeaponType
	local L = {}
	local function add(name, size, offset, role, shape)
		table.insert(L, { Name = name, Size = size, Offset = offset, Role = role, Shape = shape })
	end
	if wtype == "Sword" or wtype == "Greatsword" or wtype == "Dagger" then
		local length = if wtype == "Greatsword" then 5.5 elseif wtype == "Dagger" then 1.6 else 3.6
		local width = if wtype == "Greatsword" then 0.7 elseif wtype == "Dagger" then 0.28 else 0.38
		add("Grip", Vector3.new(0.28, 0.28, if wtype == "Greatsword" then 1.4 else 0.9), CFrame.new(0, 0, 0.1), "Wood")
		add("Guard", Vector3.new(0.3, width * 2 + 0.5, 0.25), CFrame.new(0, 0, -0.45), "Trim")
		add("Blade", Vector3.new(0.12, width, length), CFrame.new(0, 0, -0.55 - length / 2), "Metal")
	elseif wtype == "Axe" then
		add("Haft", Vector3.new(0.28, 0.28, 3.2), CFrame.new(0, 0, -1.1), "Wood")
		add("Head", Vector3.new(0.2, 1.3, 1.1), CFrame.new(0, 0.6, -2.3), "Metal")
	elseif wtype == "Hammer" then
		add("Haft", Vector3.new(0.3, 0.3, 3.4), CFrame.new(0, 0, -1.2), "Wood")
		add("Head", Vector3.new(1.3, 1.3, 1.6), CFrame.new(0, 0, -3.0), "Metal")
	elseif wtype == "Spear" then
		add("Shaft", Vector3.new(0.25, 0.25, 7), CFrame.new(0, 0, -1.5), "Wood")
		add("Tip", Vector3.new(0.12, 0.45, 1.2), CFrame.new(0, 0, -5.6), "Metal")
	elseif wtype == "Bow" then
		add("Limb", Vector3.new(0.22, 0.22, 4.6), CFrame.new(0, 0, -0.2), "Wood")
		add("String", Vector3.new(0.04, 0.04, 4.4), CFrame.new(0, 0.55, -0.2), "String")
	elseif wtype == "Staff" then
		add("Shaft", Vector3.new(0.26, 0.26, 5.2), CFrame.new(0, 0, -1.6), "Wood")
		add("Gem", Vector3.new(0.75, 0.75, 0.75), CFrame.new(0, 0, -4.4), "Gem", Enum.PartType.Ball)
	elseif wtype == "Seal" then
		add("Seal", Vector3.new(0.18, 1, 1), CFrame.new(0, 0, -0.55) * CFrame.Angles(0, 0, 0), "Trim", Enum.PartType.Cylinder)
		add("Gem", Vector3.new(0.45, 0.45, 0.45), CFrame.new(-0.1, 0, -0.55), "Gem", Enum.PartType.Ball)
	end
	return L
end

-- Attaches the equipped weapon (right hand) and shield (left hand) to a character.
function EntityModels.attachHeldGear(character: Model, weaponId: string?, skinId: string?, offhandId: string?)
	local old = character:FindFirstChild("HeldGear")
	if old then
		old:Destroy()
	end
	local gear = Instance.new("Model")
	gear.Name = "HeldGear"
	local skin = skinId and Cosmetics[skinId]
	local wdef = weaponId and Items[weaponId]
	local right, rgrip = handGrip(character, "Right")
	rgrip *= CFrame.Angles(math.rad(15), 0, 0) -- carry the weapon slightly raised
	if wdef and right then
		local metal = skin and skin.Color or wdef.Color or Color3.fromRGB(175, 175, 182)
		local metalMat = skin and Enum.Material[skin.Material] or Enum.Material.Metal
		local trim = Color3.fromRGB(150, 120, 60)
		local gem = if wdef.DamageType == "Holy" then Color3.fromRGB(255, 230, 150)
			elseif wdef.DamageType == "Fire" then Color3.fromRGB(255, 130, 50)
			else Color3.fromRGB(120, 150, 255)
		for _, spec in weaponLayout(wdef) do
			local color, mat = metal, metalMat
			if spec.Role == "Wood" then
				color, mat = Color3.fromRGB(70, 50, 36), Enum.Material.Wood
			elseif spec.Role == "Trim" then
				color, mat = trim, Enum.Material.Metal
			elseif spec.Role == "Gem" then
				color, mat = gem, Enum.Material.Neon
			elseif spec.Role == "String" then
				color, mat = Color3.fromRGB(220, 215, 200), Enum.Material.Fabric
			end
			local p = gearPart(gear, spec.Name, spec.Size, color, mat, spec.Shape)
			p.CFrame = right.CFrame * rgrip * spec.Offset
			gripWeld(right, p, rgrip, spec.Offset)
		end
		gear:SetAttribute("WeaponType", wdef.WeaponType)
	end
	local odef = offhandId and Items[offhandId]
	local left, lgrip = handGrip(character, "Left")
	if odef and odef.Kind == "Shield" and left then
		local size = if odef.Stability >= 90 then Vector3.new(2.6, 3.4, 0.25) elseif odef.Stability <= 60 then Vector3.new(1.8, 1.8, 0.25) else Vector3.new(2.2, 2.8, 0.25)
		local offset = CFrame.new(0, 0.6, -0.35)
		local plate = gearPart(gear, "Shield", size, Color3.fromRGB(105, 100, 105), Enum.Material.Metal)
		plate.CFrame = left.CFrame * lgrip * offset
		gripWeld(left, plate, lgrip, offset)
		local boss = gearPart(gear, "ShieldBoss", Vector3.new(0.6, 0.6, 0.3), Color3.fromRGB(170, 140, 70), Enum.Material.Metal)
		local bossOffset = offset * CFrame.new(0, 0, -0.2)
		boss.CFrame = left.CFrame * lgrip * bossOffset
		gripWeld(left, boss, lgrip, bossOffset)
	end
	gear.Parent = character
	return gear
end

return EntityModels
