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
function EntityModels.windup(motor: Motor6D?, duration: number)
	if not motor or not motor.Parent then
		return
	end
	local shoulder = motor :: Motor6D
	local base = shoulder:GetAttribute("BaseC0") or shoulder.C0
	shoulder:SetAttribute("BaseC0", base)
	TweenService:Create(shoulder, TweenInfo.new(math.max(0.05, duration * 0.8), Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		C0 = base * CFrame.Angles(math.rad(150), 0, 0),
	}):Play()
end

function EntityModels.strike(motor: Motor6D?)
	if not motor or not motor.Parent then
		return
	end
	local shoulder = motor :: Motor6D
	local base = shoulder:GetAttribute("BaseC0") or shoulder.C0
	local t = TweenService:Create(shoulder, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		C0 = base * CFrame.Angles(math.rad(-40), 0, 0),
	})
	t:Play()
	task.delay(0.35, function()
		if shoulder.Parent then
			TweenService:Create(shoulder, TweenInfo.new(0.3), { C0 = base }):Play()
		end
	end)
end

-- Player weapon as a Tool (gives the default character animations a held item and a slash anim).
function EntityModels.buildWeaponTool(itemId: string?, skinId: string?): Tool?
	local def = itemId and Items[itemId]
	if not def then
		return nil
	end
	local tool = Instance.new("Tool")
	tool.Name = def.Name
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.ManualActivationOnly = true
	tool:SetAttribute("ItemId", itemId)
	local wtype = def.WeaponType
	local skin = skinId and Cosmetics[skinId]
	local color = skin and skin.Color or def.Color or Color3.fromRGB(160, 160, 165)
	local material = skin and Enum.Material[skin.Material] or Enum.Material.Metal
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.CanCollide = false
	handle.Massless = true
	handle.CanQuery = false
	handle.Color = Color3.fromRGB(60, 45, 35)
	handle.Material = Enum.Material.Wood
	handle.Size = Vector3.new(0.3, 1.2, 0.3)
	handle.Parent = tool
	local length, width, thick = 4, 0.4, 0.15
	if wtype == "Greatsword" then
		length, width = 6, 0.8
	elseif wtype == "Dagger" then
		length, width = 1.8, 0.3
	elseif wtype == "Axe" then
		length, width = 3, 0.3
	elseif wtype == "Hammer" then
		length, width = 3.2, 0.35
	elseif wtype == "Spear" then
		length, width = 7, 0.25
	elseif wtype == "Staff" or wtype == "Seal" then
		length, width = if wtype == "Staff" then 5 else 1.2, 0.3
	elseif wtype == "Bow" then
		length, width = 4, 0.25
	end
	local blade = Instance.new("Part")
	blade.Name = "Blade"
	blade.CanCollide = false
	blade.Massless = true
	blade.CanQuery = false
	blade.Size = Vector3.new(thick, length, width)
	blade.Color = color
	blade.Material = material
	blade.CFrame = handle.CFrame * CFrame.new(0, 0.6 + length / 2, 0)
	blade.Parent = tool
	weld(handle, blade)
	if wtype == "Axe" or wtype == "Hammer" then
		local head = Instance.new("Part")
		head.Name = "WeaponHead"
		head.CanCollide = false
		head.Massless = true
		head.CanQuery = false
		head.Size = if wtype == "Axe" then Vector3.new(0.25, 1.2, 1.4) else Vector3.new(1.2, 1.2, 1.8)
		head.Color = color
		head.Material = material
		head.CFrame = blade.CFrame * CFrame.new(0, length / 2 - 0.5, if wtype == "Axe" then 0.6 else 0)
		head.Parent = tool
		weld(blade, head)
	elseif wtype == "Staff" or wtype == "Seal" then
		local gem = Instance.new("Part")
		gem.Name = "Gem"
		gem.Shape = Enum.PartType.Ball
		gem.CanCollide = false
		gem.Massless = true
		gem.CanQuery = false
		gem.Size = Vector3.new(0.7, 0.7, 0.7)
		gem.Material = Enum.Material.Neon
		gem.Color = if def.DamageType == "Holy" then Color3.fromRGB(255, 230, 150) else Color3.fromRGB(120, 150, 255)
		gem.CFrame = blade.CFrame * CFrame.new(0, length / 2 + 0.3, 0)
		gem.Parent = tool
		weld(blade, gem)
	end
	tool.Grip = CFrame.new(0, -0.3, 0)
	return tool
end

return EntityModels
