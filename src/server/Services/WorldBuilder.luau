--[[
	WorldBuilder
	Builds the whole world procedurally at server start from Config/World.luau, using only
	terrain, parts, materials, lights and particles (no external assets):
	  lighting & atmosphere, terrain, the Tower of the Fallen, the Fallen Sanctuary hub and its
	  NPCs, Ember Shrines, Training Grounds, Ashen Pit (PvP), Mistveil Forest, Ruins of Ashford,
	  Hallowed Rest Cemetery, The Hollow Deep (caves), Broken Gate Fortress, The Hollow Vale,
	  treasure chests and leaderboards. BuildArena() creates instanced boss arenas.

	Layout is deterministic (seeded Rng) so every server looks the same.
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local World = require(Shared.Config.World)
local Bosses = require(Shared.Config.Bosses)
local Rng = require(Shared.Util.Rng)
local Net = require(Shared.Net)
local EntityModels = require(script.Parent.EntityModels)

local WorldBuilder = {}
local map: Folder
local rng = Rng.new(20241009)

local STONE = Color3.fromRGB(96, 92, 88)
local DARK_STONE = Color3.fromRGB(62, 60, 58)
local WOOD = Color3.fromRGB(70, 52, 38)

local function v3(t)
	return Vector3.new(t[1], t[2], t[3])
end

local function part(parent: Instance, props): BasePart
	local p = Instance.new(props.Class or "Part") :: BasePart
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = props.Size or Vector3.new(4, 4, 4)
	p.CFrame = props.CFrame or CFrame.new(props.Position or Vector3.zero)
	p.Color = props.Color or STONE
	p.Material = props.Material or Enum.Material.Slate
	if props.Shape and p:IsA("Part") then
		(p :: Part).Shape = props.Shape
	end
	p.Transparency = props.Transparency or 0
	p.CanCollide = props.CanCollide ~= false
	p.CastShadow = props.CastShadow ~= false
	p.Name = props.Name or "Part"
	p.Parent = parent
	return p
end

local function cylinderUp(parent, center: Vector3, diameter: number, height: number, props)
	props = props or {}
	props.Shape = Enum.PartType.Cylinder
	props.Size = Vector3.new(height, diameter, diameter)
	props.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
	return part(parent, props)
end

local function light(parentPart: Instance, color: Color3, range: number, brightness: number?)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness or 1.5
	l.Shadows = false
	l.Parent = parentPart
	return l
end

local function fire(parentPart: Instance, color: Color3?, size: number?)
	local f = Instance.new("Fire")
	f.Color = color or Color3.fromRGB(255, 140, 60)
	f.SecondaryColor = Color3.fromRGB(255, 60, 20)
	f.Size = size or 5
	f.Heat = 8
	f.Parent = parentPart
	return f
end

local function folder(name: string, parent: Instance?): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent or map
	return f
end

local function label(parentPart: Instance, text: string, sub: string?, maxDist: number?)
	local b = Instance.new("BillboardGui")
	b.Size = UDim2.fromOffset(240, 50)
	b.StudsOffset = Vector3.new(0, 4.5, 0)
	b.MaxDistance = maxDist or 60
	b.LightInfluence = 0
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.new(1, 0, 0.6, 0)
	t.Font = Enum.Font.Garamond
	t.TextScaled = true
	t.TextColor3 = Color3.fromRGB(240, 220, 170)
	t.TextStrokeTransparency = 0.3
	t.Text = text
	t.Parent = b
	if sub then
		local s2 = t:Clone()
		s2.Position = UDim2.new(0, 0, 0.6, 0)
		s2.Size = UDim2.new(1, 0, 0.4, 0)
		s2.TextColor3 = Color3.fromRGB(190, 180, 160)
		s2.Text = sub
		s2.Parent = b
	end
	b.Parent = parentPart
	return b
end

-- ===================================================================== lighting
local function buildLighting()
	-- NOTE: Lighting.Technology cannot be set by scripts (Roblox-only security); it is set in
	-- default.project.json instead.
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmo.Density = 0.28
	atmo.Offset = 0.15
	atmo.Color = Color3.fromRGB(200, 195, 200)
	atmo.Decay = Color3.fromRGB(90, 70, 80)
	atmo.Glare = 0.2
	atmo.Haze = 1.2
	atmo.Parent = Lighting
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "Grade"
	cc.Brightness = 0.04
	cc.Contrast = 0.08
	cc.Saturation = -0.1
	cc.TintColor = Color3.fromRGB(240, 232, 225)
	cc.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.6
	bloom.Size = 30
	bloom.Threshold = 1.6
	bloom.Parent = Lighting
	local rays = Instance.new("SunRaysEffect")
	rays.Intensity = 0.06
	rays.Spread = 0.6
	rays.Parent = Lighting
end

-- ===================================================================== terrain
local function buildTerrain()
	local terrain = workspace.Terrain
	terrain:FillBlock(CFrame.new(0, -4, 0), Vector3.new(2100, 8, 2100), Enum.Material.Ground)
	for _, r in World.Regions do
		local mat = Enum.Material[r.Material] or Enum.Material.Grass
		local c = v3(r.Center)
		terrain:FillCylinder(CFrame.new(c.X, -1, c.Z), 2, r.Radius, mat)
	end
	-- wide grass between regions
	terrain:FillCylinder(CFrame.new(0, -1.5, 0), 1, 300, Enum.Material.Grass)
	-- surrounding hills (world boundary feel)
	for i = 1, 28 do
		local ang = (i / 28) * math.pi * 2
		local d = 1000 + rng:NextInteger(-20, 40)
		terrain:FillBall(Vector3.new(math.cos(ang) * d, -10, math.sin(ang) * d), rng:NextInteger(110, 170), Enum.Material.Rock)
	end
	-- roads from the hub
	local hub = v3(World.Regions[1].Center)
	for _, r in World.Regions do
		if r.Id ~= "sanctuary" then
			local c = v3(r.Center)
			local mid = (hub + c) / 2
			local len = (c - hub).Magnitude
			terrain:FillBlock(CFrame.lookAt(Vector3.new(mid.X, -1.2, mid.Z), Vector3.new(c.X, -1.2, c.Z)), Vector3.new(10, 1.6, len), Enum.Material.Pavement)
		end
	end
	-- the Hollow Deep: carve a cave out of a rock mass
	terrain:FillBlock(CFrame.new(-700, 22, -170), Vector3.new(220, 46, 180), Enum.Material.Rock)
	terrain:FillBlock(CFrame.new(-700, 18, -170), Vector3.new(200, 36, 160), Enum.Material.Air)
	terrain:FillBlock(CFrame.new(-592, 10, -170), Vector3.new(24, 20, 22), Enum.Material.Air)
	-- vale basin with water
	terrain:FillCylinder(CFrame.new(60, -2, -800), 4, 40, Enum.Material.Water)
end

-- ===================================================================== tower
local function buildTower()
	local tower = Instance.new("Model")
	tower.Name = "TowerOfTheFallen"
	local c = v3(World.Tower.Center)
	local fh = World.Tower.FloorHeight
	local baseR = World.Tower.Radius
	for floor = 1, 20 do
		local r = baseR * (1 - floor * 0.012)
		local y = c.Y + (floor - 0.5) * fh
		cylinderUp(tower, Vector3.new(c.X, y, c.Z), r * 2, fh, { Color = if floor % 2 == 0 then STONE else DARK_STONE, Material = Enum.Material.Slate, Name = "Floor" .. floor })
		local ring = cylinderUp(tower, Vector3.new(c.X, y + fh / 2 - 1.5, c.Z), r * 2 + 1.2, 1.2, {
			Color = Color3.fromRGB(70, 60, 60), Material = Enum.Material.Neon, Name = "FloorRing", CanCollide = false, CastShadow = false,
		})
		ring:SetAttribute("Floor", floor)
		-- windows
		for k = 0, 3 do
			local ang = k * math.pi / 2 + floor * 0.4
			local w = part(tower, {
				Size = Vector3.new(3, 8, 1), Color = Color3.fromRGB(255, 150, 80), Material = Enum.Material.Neon, CanCollide = false,
				CFrame = CFrame.new(c.X + math.cos(ang) * r, y, c.Z + math.sin(ang) * r) * CFrame.Angles(0, -ang + math.pi / 2, 0), Name = "Window",
			})
			w.Transparency = if (floor + k) % 3 == 0 then 0.2 else 0.85
		end
	end
	-- buttresses
	for k = 0, 7 do
		local ang = k * math.pi / 4
		local h = 180
		part(tower, {
			Class = "WedgePart", Size = Vector3.new(10, h, 34), Color = DARK_STONE,
			CFrame = CFrame.new(c.X + math.cos(ang) * (baseR + 14), h / 2, c.Z + math.sin(ang) * (baseR + 14)) * CFrame.Angles(0, -ang - math.pi / 2, 0),
			Name = "Buttress",
		})
	end
	-- crown
	local topY = c.Y + 20 * fh
	for k = 0, 11 do
		local ang = k * math.pi / 6
		part(tower, { Size = Vector3.new(5, 30 + (k % 3) * 12, 5), Color = DARK_STONE, Position = Vector3.new(c.X + math.cos(ang) * 40, topY + 15, c.Z + math.sin(ang) * 40), Name = "Spike" })
	end
	local beacon = part(tower, { Shape = Enum.PartType.Ball, Size = Vector3.new(16, 16, 16), Color = Color3.fromRGB(255, 50, 40), Material = Enum.Material.Neon, Position = Vector3.new(c.X, topY + 30, c.Z), CanCollide = false, Name = "Beacon" })
	light(beacon, Color3.fromRGB(255, 60, 40), 60, 4)
	-- gate
	local g = v3(World.Tower.GatePosition)
	for side = -1, 1, 2 do
		part(tower, { Size = Vector3.new(8, 50, 8), Color = STONE, Position = g + Vector3.new(side * 16, 25, 0), Name = "GatePillar" })
		local brazier = part(tower, { Size = Vector3.new(4, 2, 4), Color = DARK_STONE, Position = g + Vector3.new(side * 24, 6, 6), Name = "Brazier" })
		fire(brazier)
		light(brazier, Color3.fromRGB(255, 140, 70), 30, 2)
	end
	part(tower, { Size = Vector3.new(44, 8, 10), Color = STONE, Position = g + Vector3.new(0, 52, 0), Name = "Lintel" })
	local portal = part(tower, {
		Size = Vector3.new(24, 40, 1), Color = Color3.fromRGB(255, 110, 60), Material = Enum.Material.Neon, Transparency = 0.35,
		Position = g + Vector3.new(0, 20, -1), CanCollide = true, Name = "TowerGate",
	})
	light(portal, Color3.fromRGB(255, 110, 60), 40, 3)
	label(portal, "Tower of the Fallen", "Twenty guardians await", 120)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Enter the Tower"
	prompt.ObjectText = "Tower Gate"
	prompt.MaxActivationDistance = 20
	prompt.RequiresLineOfSight = false
	prompt.Parent = portal
	prompt.Triggered:Connect(function(player)
		Net.event("OpenUI"):FireClient(player, { Menu = "Tower" })
	end)
	tower.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	tower.Parent = map
end

-- ===================================================================== hub
local function npcModel(parent: Instance, npc)
	local styles = {
		Shop = { Style = "Humanoid", Color = Color3.fromRGB(110, 90, 70) },
		Blacksmith = { Style = "Brute", Color = Color3.fromRGB(90, 70, 60), Weapon = "Hammer" },
		Quest = { Style = "Caster", Color = Color3.fromRGB(80, 70, 100), Glow = Color3.fromRGB(255, 220, 140), Hood = true },
		Wardrobe = { Style = "Caster", Color = Color3.fromRGB(60, 60, 80), Glow = Color3.fromRGB(180, 160, 255) },
		Party = { Style = "Humanoid", Color = Color3.fromRGB(70, 90, 70) },
		Tutorial = { Style = "Humanoid", Color = Color3.fromRGB(120, 110, 90), Hood = true },
	}
	local style = table.clone(styles[npc.Role] or styles.Shop)
	style.Scale = 1
	local model, root, humanoid = EntityModels.build(npc.Name, style, "NPC")
	local pos = v3(npc.Position)
	model:PivotTo(CFrame.lookAt(pos + Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0), Vector3.new(0, pos.Y + humanoid.HipHeight + root.Size.Y / 2, 260)))
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = true
		end
	end
	model:SetAttribute("NpcId", npc.Id)
	model:SetAttribute("Role", npc.Role)
	model.Parent = parent
	label(root, npc.Name, npc.Role == "Shop" and "Merchant" or npc.Role, 50)
	CollectionService:AddTag(model, "NPC")
	return model
end

local function shrine(parent: Instance, cp)
	local pos = v3(cp.Position)
	local m = Instance.new("Model")
	m.Name = "Shrine_" .. cp.Id
	local base = cylinderUp(m, pos + Vector3.new(0, 0.6, 0), 9, 1.2, { Color = DARK_STONE, Name = "Base" })
	cylinderUp(m, pos + Vector3.new(0, 1.6, 0), 6, 0.8, { Color = STONE, Name = "Step" })
	local sword = part(m, { Size = Vector3.new(0.4, 6, 1.1), Color = Color3.fromRGB(80, 80, 85), Material = Enum.Material.Metal, CFrame = CFrame.new(pos + Vector3.new(0, 4.5, 0)) * CFrame.Angles(0, 0, math.rad(10)), Name = "Sword" })
	local embers = part(m, { Size = Vector3.new(2, 1, 2), Color = Color3.fromRGB(40, 30, 25), Position = pos + Vector3.new(0, 2.4, 0), CanCollide = false, Name = "Embers" })
	fire(embers, nil, 4)
	light(embers, Color3.fromRGB(255, 150, 70), 26, 2)
	base:SetAttribute("ShrineId", cp.Id)
	CollectionService:AddTag(base, "Shrine")
	label(sword, cp.Name, "Ember Shrine", 70)
	m.Parent = parent
end

local function bench(parent, cf: CFrame)
	part(parent, { Size = Vector3.new(8, 0.8, 2.4), Color = WOOD, Material = Enum.Material.Wood, CFrame = cf * CFrame.new(0, 2, 0), Name = "Bench" })
	for side = -1, 1, 2 do
		part(parent, { Size = Vector3.new(0.8, 2, 2), Color = DARK_STONE, CFrame = cf * CFrame.new(side * 3.2, 1, 0), Name = "BenchLeg" })
	end
end

local function brazierAt(parent, pos: Vector3, color: Color3?)
	local stand = cylinderUp(parent, pos + Vector3.new(0, 2.5, 0), 1.2, 5, { Color = DARK_STONE, Material = Enum.Material.Metal, Name = "BrazierStand" })
	local bowl = cylinderUp(parent, pos + Vector3.new(0, 5.3, 0), 3, 0.8, { Color = Color3.fromRGB(50, 45, 40), Material = Enum.Material.Metal, Name = "Bowl" })
	fire(bowl, color, 3)
	light(bowl, color or Color3.fromRGB(255, 140, 70), 22, 1.6)
	return stand
end

local function statue(parent, pos: Vector3, facing: Vector3)
	local m = Instance.new("Model")
	m.Name = "Statue"
	local cf = CFrame.lookAt(pos, Vector3.new(facing.X, pos.Y, facing.Z))
	part(m, { Size = Vector3.new(6, 3, 6), Color = DARK_STONE, CFrame = cf * CFrame.new(0, 1.5, 0) })
	part(m, { Size = Vector3.new(3.4, 7, 2), Color = STONE, Material = Enum.Material.Marble, CFrame = cf * CFrame.new(0, 6.5, 0) })
	part(m, { Shape = Enum.PartType.Ball, Size = Vector3.new(2.2, 2.2, 2.2), Color = STONE, Material = Enum.Material.Marble, CFrame = cf * CFrame.new(0, 11, 0) })
	part(m, { Size = Vector3.new(0.5, 9, 0.9), Color = STONE, Material = Enum.Material.Marble, CFrame = cf * CFrame.new(1.8, 7, -1) * CFrame.Angles(0, 0, math.rad(-8)) })
	m.Parent = parent
end

local function leaderboard(parent, pos: Vector3, facing: Vector3)
	local board = part(parent, { Size = Vector3.new(14, 12, 1), Color = WOOD, Material = Enum.Material.Wood, CFrame = CFrame.lookAt(pos + Vector3.new(0, 7, 0), facing + Vector3.new(0, 7, 0)), Name = "Leaderboard" })
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(700, 600)
	gui.LightInfluence = 0
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0.16, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.Garamond
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(240, 210, 140)
	title.Text = "Highest Climbers"
	title.Parent = gui
	local rows = Instance.new("TextLabel")
	rows.Name = "Rows"
	rows.Position = UDim2.new(0.05, 0, 0.18, 0)
	rows.Size = UDim2.new(0.9, 0, 0.8, 0)
	rows.BackgroundTransparency = 1
	rows.Font = Enum.Font.Garamond
	rows.TextSize = 30
	rows.TextXAlignment = Enum.TextXAlignment.Left
	rows.TextYAlignment = Enum.TextYAlignment.Top
	rows.TextColor3 = Color3.fromRGB(230, 220, 200)
	rows.Text = "Gathering records..."
	rows.Parent = gui
	gui.Parent = board
	CollectionService:AddTag(board, "Leaderboard")
end

local function buildHub()
	local hub = folder("FallenSanctuary")
	local c = v3(World.Regions[1].Center)
	-- ruined wall ring with gaps
	for i = 0, 35 do
		if i % 9 ~= 0 and i % 9 ~= 1 then
			local ang = (i / 36) * math.pi * 2
			local h = 10 + rng:NextInteger(0, 14)
			part(hub, {
				Size = Vector3.new(19, h, 4), Color = if i % 2 == 0 then STONE else DARK_STONE,
				CFrame = CFrame.new(c.X + math.cos(ang) * 115, h / 2, c.Z + math.sin(ang) * 115) * CFrame.Angles(0, -ang + math.pi / 2, math.rad(rng:NextInteger(-3, 3))),
				Name = "RuinWall",
			})
		end
	end
	-- columns
	for i = 0, 11 do
		local ang = (i / 12) * math.pi * 2
		local h = if i % 3 == 0 then 8 else 26
		cylinderUp(hub, Vector3.new(c.X + math.cos(ang) * 78, h / 2, c.Z + math.sin(ang) * 78), 5, h, { Color = STONE, Material = Enum.Material.Marble, Name = "Column" })
	end
	-- benches & braziers around the bonfire
	for i = 0, 5 do
		local ang = (i / 6) * math.pi * 2
		local p = Vector3.new(0, 0, 262) + Vector3.new(math.cos(ang) * 16, 0, math.sin(ang) * 16)
		bench(hub, CFrame.lookAt(p, Vector3.new(0, 0, 262)))
	end
	for _, off in { Vector3.new(-35, 0, -35), Vector3.new(35, 0, -35), Vector3.new(-35, 0, 35), Vector3.new(35, 0, 35), Vector3.new(-70, 0, 0), Vector3.new(70, 0, 0) } do
		brazierAt(hub, c + off)
	end
	-- market stalls
	for _, npc in World.NPCs do
		if npc.Role == "Shop" or npc.Role == "Blacksmith" then
			local p = v3(npc.Position)
			local back = p + Vector3.new(if p.X < 0 then -6 else 6, 0, 0)
			part(hub, { Size = Vector3.new(2, 8, 12), Color = WOOD, Material = Enum.Material.Wood, Position = back + Vector3.new(0, 4, 0), Name = "StallBack" })
			part(hub, { Size = Vector3.new(10, 0.6, 14), Color = Color3.fromRGB(110, 40, 36), Material = Enum.Material.Fabric, CFrame = CFrame.new(back + Vector3.new(if p.X < 0 then 3 else -3, 9, 0)) * CFrame.Angles(0, 0, math.rad(if p.X < 0 then -12 else 12)), Name = "Awning" })
			part(hub, { Size = Vector3.new(3, 3, 8), Color = WOOD, Material = Enum.Material.WoodPlanks, Position = p + Vector3.new(if p.X < 0 then 3 else -3, 1.5, 0), Name = "Counter" })
			if npc.Role == "Blacksmith" then
				local forge = part(hub, { Size = Vector3.new(6, 4, 6), Color = DARK_STONE, Position = p + Vector3.new(-4, 2, 8), Name = "Forge" })
				fire(forge, Color3.fromRGB(255, 120, 40), 6)
				light(forge, Color3.fromRGB(255, 120, 40), 26, 2.5)
				part(hub, { Size = Vector3.new(3, 2, 1.5), Color = Color3.fromRGB(60, 60, 64), Material = Enum.Material.Metal, Position = p + Vector3.new(3, 3, 6), Name = "Anvil" })
			end
		end
	end
	statue(hub, c + Vector3.new(-25, 0, -60), c)
	statue(hub, c + Vector3.new(25, 0, -60), c)
	leaderboard(hub, c + Vector3.new(60, 0, 60), c)
	-- wardrobe mirror (cosmetic display)
	local wardrobePos = Vector3.new(-30, 0, 340)
	for _, npc in World.NPCs do
		if npc.Role == "Wardrobe" then
			wardrobePos = v3(npc.Position)
		end
	end
	local mirror = part(hub, { Size = Vector3.new(6, 10, 0.5), Color = Color3.fromRGB(180, 190, 210), Material = Enum.Material.Glass, Transparency = 0.2, Position = wardrobePos + Vector3.new(0, 5, 6), Name = "Mirror" })
	light(mirror, Color3.fromRGB(180, 170, 255), 14, 1)
	-- party board
	part(hub, { Size = Vector3.new(8, 6, 0.6), Color = WOOD, Material = Enum.Material.Wood, Position = Vector3.new(30, 4, 286), Name = "FellowshipBoard" })
	for _, npc in World.NPCs do
		npcModel(hub, npc)
	end
end

-- ===================================================================== shrines, chests
local function buildShrines()
	local f = folder("Shrines")
	for _, cp in World.Checkpoints do
		shrine(f, cp)
	end
end

local function buildChests()
	local f = folder("Chests")
	for _, ch in World.Chests do
		local pos = v3(ch.Position)
		local m = Instance.new("Model")
		m.Name = ch.Id
		local box = part(m, { Size = Vector3.new(4, 2.4, 2.6), Color = WOOD, Material = Enum.Material.WoodPlanks, Position = pos + Vector3.new(0, 1.2, 0), Name = "Box" })
		part(m, { Size = Vector3.new(4.2, 0.9, 2.8), Color = Color3.fromRGB(90, 70, 40), Material = Enum.Material.Wood, Position = pos + Vector3.new(0, 2.8, 0), Name = "Lid" })
		part(m, { Size = Vector3.new(0.6, 0.8, 0.2), Color = Color3.fromRGB(200, 170, 80), Material = Enum.Material.Foil, Position = pos + Vector3.new(0, 2.2, -1.4), Name = "Lock" })
		light(box, Color3.fromRGB(255, 210, 120), 10, 0.8)
		box:SetAttribute("ChestId", ch.Id)
		CollectionService:AddTag(box, "Chest")
		m.Parent = f
	end
end

-- ===================================================================== training grounds
local function buildTraining()
	local f = folder("TrainingGrounds")
	local c = v3(World.Regions[2].Center)
	-- fence
	for i = 0, 23 do
		local ang = (i / 24) * math.pi * 2
		part(f, { Size = Vector3.new(1, 4, 15), Color = WOOD, Material = Enum.Material.Wood,
			CFrame = CFrame.new(c.X + math.cos(ang) * 68, 2, c.Z + math.sin(ang) * 68) * CFrame.Angles(0, -ang, 0), Name = "Fence" })
	end
	for _, st in World.TrainingStations do
		local pos = v3(st.Position)
		local marker = cylinderUp(f, pos + Vector3.new(0, 0.3, 0), 8, 0.6, { Color = Color3.fromRGB(150, 120, 70), Material = Enum.Material.Sand, Name = "Station_" .. st.Id })
		marker:SetAttribute("Challenge", st.Challenge)
		CollectionService:AddTag(marker, "TrainingStation")
		label(marker, ({ weights = "Weightlifting", dummies = "Weapon Practice", dodge = "Dodge Drill", parry = "Parry Drill", endurance = "Endurance Run", sparring = "Sparring Ring" })[st.Id] or st.Id, "Training", 50)
		if st.Id == "weights" then
			part(f, { Size = Vector3.new(6, 0.6, 2), Color = WOOD, Position = pos + Vector3.new(0, 1.6, 4), Name = "WeightBench" })
			cylinderUp(f, pos + Vector3.new(-3.5, 3, 4), 2.4, 0.6, { Color = Color3.fromRGB(50, 50, 55), Material = Enum.Material.Metal })
			cylinderUp(f, pos + Vector3.new(3.5, 3, 4), 2.4, 0.6, { Color = Color3.fromRGB(50, 50, 55), Material = Enum.Material.Metal })
			part(f, { Size = Vector3.new(8, 0.3, 0.3), Color = Color3.fromRGB(120, 120, 125), Material = Enum.Material.Metal, Position = pos + Vector3.new(0, 3, 4) })
		elseif st.Id == "dummies" then
			for k = -1, 1 do
				local dm = Instance.new("Model")
				dm.Name = "TrainingDummy"
				local root = part(dm, { Size = Vector3.new(2, 5, 1.5), Color = Color3.fromRGB(160, 130, 80), Material = Enum.Material.Fabric, Position = pos + Vector3.new(k * 7, 4.5, -8), Name = "HumanoidRootPart" })
				part(dm, { Shape = Enum.PartType.Ball, Size = Vector3.new(2, 2, 2), Color = Color3.fromRGB(170, 140, 90), Material = Enum.Material.Fabric, Position = pos + Vector3.new(k * 7, 8, -8), Name = "Head" })
				cylinderUp(dm, pos + Vector3.new(k * 7, 1, -8), 1, 2, { Color = WOOD, Material = Enum.Material.Wood })
				dm.PrimaryPart = root
				dm:SetAttribute("Height", 8)
				dm.Parent = f
				CollectionService:AddTag(dm, "TrainingDummy")
			end
		elseif st.Id == "endurance" then
			for k = 1, 6 do
				local ang = (k / 6) * math.pi * 2
				local post = cylinderUp(f, c + Vector3.new(math.cos(ang) * 52, 4, math.sin(ang) * 52), 1.6, 8, { Color = Color3.fromRGB(230, 200, 120), Material = Enum.Material.Neon, Name = "Post" .. k, CanCollide = false })
				post:SetAttribute("Index", k)
				CollectionService:AddTag(post, "TrainingPost")
				label(post, "Post " .. k, nil, 80)
			end
		end
	end
end

-- ===================================================================== wild regions
local function tree(parent, pos: Vector3, scale: number, dead: boolean?)
	local h = 18 * scale
	cylinderUp(parent, pos + Vector3.new(0, h / 2, 0), 2.2 * scale, h, { Color = Color3.fromRGB(58, 46, 38), Material = Enum.Material.Wood, Name = "Trunk" })
	if not dead then
		for k = 1, 2 do
			part(parent, {
				Shape = Enum.PartType.Ball, Size = Vector3.new(12, 12, 12) * scale * (1.2 - k * 0.2),
				Color = Color3.fromRGB(40 + rng:NextInteger(0, 15), 58 + rng:NextInteger(0, 15), 38),
				Material = Enum.Material.Grass, CanCollide = false,
				Position = pos + Vector3.new(rng:NextInteger(-2, 2), h - 2 + k * 4 * scale, rng:NextInteger(-2, 2)), Name = "Leaves",
			})
		end
	else
		part(parent, { Size = Vector3.new(1, 8 * scale, 1), Color = Color3.fromRGB(58, 46, 38), Material = Enum.Material.Wood,
			CFrame = CFrame.new(pos + Vector3.new(2, h * 0.75, 0)) * CFrame.Angles(0, 0, math.rad(-40)), Name = "Branch" })
	end
end

local function scatter(region, count: number, minR: number, fn)
	local c = v3(region.Center)
	for _ = 1, count do
		local ang = rng:NextNumber() * math.pi * 2
		local r = minR + rng:NextNumber() * (region.Radius - minR)
		fn(c + Vector3.new(math.cos(ang) * r, 0, math.sin(ang) * r))
	end
end

local function regionById(id)
	for _, r in World.Regions do
		if r.Id == id then
			return r
		end
	end
	return nil
end

local function ruinedHouse(parent, pos: Vector3, rot: number)
	local cf = CFrame.new(pos) * CFrame.Angles(0, rot, 0)
	local w, d, h = 18, 14, 10
	part(parent, { Size = Vector3.new(w, h, 1.5), Color = STONE, Material = Enum.Material.Brick, CFrame = cf * CFrame.new(0, h / 2, -d / 2) })
	part(parent, { Size = Vector3.new(1.5, h * 0.7, d), Color = STONE, Material = Enum.Material.Brick, CFrame = cf * CFrame.new(-w / 2, h * 0.35, 0) })
	part(parent, { Size = Vector3.new(1.5, h, d), Color = STONE, Material = Enum.Material.Brick, CFrame = cf * CFrame.new(w / 2, h / 2, 0) })
	part(parent, { Size = Vector3.new(w * 0.4, h * 0.5, 1.5), Color = STONE, Material = Enum.Material.Brick, CFrame = cf * CFrame.new(-w * 0.3, h * 0.25, d / 2) })
	part(parent, { Class = "WedgePart", Size = Vector3.new(w * 0.6, 5, d / 2), Color = Color3.fromRGB(70, 50, 40), Material = Enum.Material.WoodPlanks, CFrame = cf * CFrame.new(w * 0.2, h + 2.5, -d / 4) })
end

local function buildRegions()
	-- Mistveil Forest
	local forest = folder("MistveilForest")
	scatter(regionById("forest"), 130, 10, function(p)
		tree(forest, p, 0.8 + rng:NextNumber() * 0.7, rng:NextNumber() < 0.15)
	end)
	-- hidden grotto
	local g = Vector3.new(-600, 0, 280)
	for k = 0, 7 do
		local ang = (k / 8) * math.pi * 2
		if k ~= 2 then
			part(forest, { Size = Vector3.new(12, 14, 6), Color = Color3.fromRGB(80, 80, 76), Material = Enum.Material.Rock, CFrame = CFrame.new(g + Vector3.new(math.cos(ang) * 14, 7, math.sin(ang) * 14)) * CFrame.Angles(0, -ang, 0), Name = "GrottoRock" })
		end
	end
	part(forest, { Size = Vector3.new(34, 3, 34), Color = Color3.fromRGB(70, 70, 66), Material = Enum.Material.Rock, Position = g + Vector3.new(0, 15, 0), Name = "GrottoRoof" })
	local glow = part(forest, { Shape = Enum.PartType.Ball, Size = Vector3.new(2, 2, 2), Color = Color3.fromRGB(120, 255, 200), Material = Enum.Material.Neon, Position = g + Vector3.new(0, 10, 0), CanCollide = false })
	light(glow, Color3.fromRGB(120, 255, 200), 20, 1.5)

	-- Ruins of Ashford
	local village = folder("RuinsOfAshford")
	local vc = v3(regionById("village").Center)
	for k = 0, 8 do
		local ang = (k / 9) * math.pi * 2
		ruinedHouse(village, vc + Vector3.new(math.cos(ang) * 70, 0, math.sin(ang) * 70), -ang)
	end
	-- collapsed chapel (secret)
	local ch = Vector3.new(500, 0, 140)
	part(village, { Size = Vector3.new(24, 16, 2), Color = STONE, Material = Enum.Material.Brick, Position = ch + Vector3.new(0, 8, -10) })
	part(village, { Size = Vector3.new(2, 12, 20), Color = STONE, Material = Enum.Material.Brick, Position = ch + Vector3.new(-12, 6, 0) })
	part(village, { Size = Vector3.new(8, 2, 3), Color = DARK_STONE, Position = ch + Vector3.new(0, 1, -6), Name = "Altar" })
	local well = cylinderUp(village, vc + Vector3.new(0, 1.5, 0), 6, 3, { Color = STONE, Name = "Well" })
	light(well, Color3.fromRGB(255, 160, 90), 16, 1)

	-- Hallowed Rest Cemetery
	local cem = folder("HallowedRest")
	scatter(regionById("cemetery"), 90, 8, function(p)
		part(cem, { Size = Vector3.new(2.4, 3.2 + rng:NextNumber() * 2, 0.6), Color = Color3.fromRGB(110, 110, 112), Material = Enum.Material.Slate,
			CFrame = CFrame.new(p + Vector3.new(0, 1.6, 0)) * CFrame.Angles(math.rad(rng:NextInteger(-8, 8)), rng:NextNumber() * 0.4, math.rad(rng:NextInteger(-8, 8))), Name = "Grave" })
	end)
	scatter(regionById("cemetery"), 14, 30, function(p)
		tree(cem, p, 0.9, true)
	end)
	local crypt = Vector3.new(-430, 0, -400)
	part(cem, { Size = Vector3.new(20, 12, 16), Color = DARK_STONE, Material = Enum.Material.Marble, Position = crypt + Vector3.new(0, 6, -10), Name = "Crypt" })
	part(cem, { Size = Vector3.new(8, 10, 2), Color = Color3.fromRGB(30, 30, 34), Position = crypt + Vector3.new(0, 5, -1.5), CanCollide = false, Name = "CryptDoor" })
	local ghost = part(cem, { Shape = Enum.PartType.Ball, Size = Vector3.new(1.5, 1.5, 1.5), Color = Color3.fromRGB(150, 200, 255), Material = Enum.Material.Neon, Position = crypt + Vector3.new(0, 4, 2), CanCollide = false })
	light(ghost, Color3.fromRGB(150, 200, 255), 18, 1.2)

	-- The Hollow Deep (cave interior lights & stalagmites)
	local caves = folder("HollowDeep")
	scatter(regionById("caves"), 26, 6, function(p)
		if math.abs(p.X + 700) < 95 and math.abs(p.Z + 170) < 75 then
			part(caves, { Class = "WedgePart", Size = Vector3.new(3, 6 + rng:NextNumber() * 6, 3), Color = Color3.fromRGB(90, 86, 80), Material = Enum.Material.Rock, Position = p + Vector3.new(0, 4, 0), Name = "Stalagmite" })
		end
	end)
	for k = 1, 6 do
		local crystal = part(caves, { Size = Vector3.new(1.4, 4, 1.4), Color = Color3.fromRGB(120, 180, 255), Material = Enum.Material.Neon,
			CFrame = CFrame.new(-760 + k * 22, 2, -170 + (k % 2 == 0 and 50 or -50)) * CFrame.Angles(0.3, k, 0.2), CanCollide = false, Name = "Crystal" })
		light(crystal, Color3.fromRGB(120, 180, 255), 22, 1.2)
	end

	-- Broken Gate Fortress
	local fort = folder("BrokenGateFortress")
	local fc = v3(regionById("fortress").Center)
	local half = 70
	for side = 0, 3 do
		local ang = side * math.pi / 2
		local dirv = Vector3.new(math.cos(ang), 0, math.sin(ang))
		local perp = Vector3.new(-dirv.Z, 0, dirv.X)
		for seg = -2, 2 do
			if not (side == 2 and seg == 0) then -- gate gap facing the hub road
				part(fort, { Size = Vector3.new(28, 18, 4), Color = STONE, Material = Enum.Material.Cobblestone,
					CFrame = CFrame.lookAt(fc + dirv * half + perp * seg * 28 + Vector3.new(0, 9, 0), fc + Vector3.new(0, 9, 0)), Name = "FortWall" })
			end
		end
		local corner = fc + (dirv + perp) * half
		cylinderUp(fort, corner + Vector3.new(0, 14, 0), 14, 28, { Color = DARK_STONE, Material = Enum.Material.Cobblestone, Name = "FortTower" })
	end
	-- ramparts (secret)
	part(fort, { Size = Vector3.new(30, 2, 14), Color = STONE, Material = Enum.Material.Cobblestone, Position = Vector3.new(500, 17, -460), Name = "Rampart" })
	for k = 0, 7 do
		part(fort, { Size = Vector3.new(6, 2, 3), Color = STONE, Material = Enum.Material.Cobblestone, Position = Vector3.new(480 - k * 0.1, 1 + k * 2, -440 - k * 2.6), Name = "Stair" })
	end
	for k = 0, 3 do
		local b = part(fort, { Size = Vector3.new(2, 1, 2), Color = DARK_STONE, Position = fc + Vector3.new(-40 + k * 26, 6, 10), Name = "FortBrazier" })
		fire(b, nil, 3)
		light(b, Color3.fromRGB(255, 130, 60), 20, 1.4)
	end

	-- The Hollow Vale (hidden region) and its seal
	local vale = folder("HollowVale")
	scatter(regionById("vale"), 60, 15, function(p)
		local crystal = part(vale, { Size = Vector3.new(2, 6 + rng:NextNumber() * 8, 2), Color = Color3.fromRGB(80, 255, 200), Material = Enum.Material.Neon,
			CFrame = CFrame.new(p + Vector3.new(0, 4, 0)) * CFrame.Angles(rng:NextNumber() * 0.4, rng:NextNumber() * 3, rng:NextNumber() * 0.4), CanCollide = false, Name = "ValeCrystal" })
		if rng:NextNumber() < 0.2 then
			light(crystal, Color3.fromRGB(80, 255, 200), 18, 1)
		end
	end)
	scatter(regionById("vale"), 40, 20, function(p)
		tree(vale, p, 1.2, false)
	end)
	local seal = part(vale, { Size = Vector3.new(60, 40, 2), Color = Color3.fromRGB(80, 255, 200), Material = Enum.Material.ForceField, Transparency = 0.3, Position = Vector3.new(0, 20, -585), CanCollide = false, Name = "ValeSeal" })
	label(seal, "The Hollow Vale", "Sealed until the tenth guardian falls", 120)

	-- Ashen Pit (PvP)
	local pit = folder("AshenPit")
	local pc = v3(regionById("pvp").Center)
	for k = 0, 15 do
		local ang = (k / 16) * math.pi * 2
		part(pit, { Size = Vector3.new(10, 5, 3), Color = DARK_STONE, CFrame = CFrame.new(pc + Vector3.new(math.cos(ang) * 42, 2.5, math.sin(ang) * 42)) * CFrame.Angles(0, -ang + math.pi / 2, 0), Name = "PitWall" })
	end
	local sign = part(pit, { Size = Vector3.new(10, 6, 1), Color = WOOD, Material = Enum.Material.Wood, Position = pc + Vector3.new(0, 3, 50), Name = "PitSign" })
	label(sign, "The Ashen Pit", "Opt-in duels: no embers lost", 80)
end

-- ===================================================================== arenas
local PROPS = {
	Pillars = function(m, o, r, def)
		for k = 0, 7 do
			local ang = (k / 8) * math.pi * 2
			cylinderUp(m, o + Vector3.new(math.cos(ang) * r * 0.82, 14, math.sin(ang) * r * 0.82), 6, 28, { Color = def.Arena.Color, Material = Enum.Material.Marble })
		end
	end,
	Graves = function(m, o, r)
		for k = 0, 15 do
			local ang = (k / 16) * math.pi * 2
			part(m, { Size = Vector3.new(3, 4, 0.8), Color = Color3.fromRGB(110, 110, 115), Position = o + Vector3.new(math.cos(ang) * r * 0.86, 2, math.sin(ang) * r * 0.86) })
		end
	end,
	Roots = function(m, o, r)
		for k = 0, 9 do
			local ang = (k / 10) * math.pi * 2
			part(m, { Size = Vector3.new(3, 3, 26), Color = Color3.fromRGB(60, 50, 34), Material = Enum.Material.Wood, CanCollide = false,
				CFrame = CFrame.new(o + Vector3.new(math.cos(ang) * r * 0.85, 1.5, math.sin(ang) * r * 0.85)) * CFrame.Angles(0, -ang, 0.3) })
		end
	end,
	Braziers = function(m, o, r, def)
		for k = 0, 5 do
			local ang = (k / 6) * math.pi * 2
			brazierAt(m, o + Vector3.new(math.cos(ang) * r * 0.85, 0, math.sin(ang) * r * 0.85), def.Arena.Light)
		end
	end,
	Pools = function(m, o, r, def)
		for k = 0, 4 do
			local ang = (k / 5) * math.pi * 2
			cylinderUp(m, o + Vector3.new(math.cos(ang) * r * 0.8, 0.12, math.sin(ang) * r * 0.8), 14, 0.2, { Color = def.Arena.Light, Material = Enum.Material.Glass, Transparency = 0.5, CanCollide = false })
		end
	end,
	Statues = function(m, o, r)
		for k = 0, 5 do
			local ang = (k / 6) * math.pi * 2
			statue(m, o + Vector3.new(math.cos(ang) * r * 0.85, 0, math.sin(ang) * r * 0.85), o)
		end
	end,
}
PROPS.Throne = function(m, o, r, def)
	local back = o + Vector3.new(0, 0, -r * 0.85)
	part(m, { Size = Vector3.new(14, 4, 10), Color = DARK_STONE, Position = back + Vector3.new(0, 2, 0) })
	part(m, { Size = Vector3.new(10, 22, 2), Color = def.Arena.Color, Material = Enum.Material.Marble, Position = back + Vector3.new(0, 13, -4) })
	PROPS.Pillars(m, o, r, def)
end
for _, alias in { "Hooks", "Gallows", "Shelves", "Banners", "Rubble", "Ruins", "Vats", "Moons" } do
	PROPS[alias] = function(m, o, r, def)
		for k = 0, 9 do
			local ang = (k / 10) * math.pi * 2
			local p = o + Vector3.new(math.cos(ang) * r * 0.86, 0, math.sin(ang) * r * 0.86)
			if alias == "Moons" then
				local moon = part(m, { Shape = Enum.PartType.Ball, Size = Vector3.new(6, 6, 6), Color = def.Arena.Light, Material = Enum.Material.Neon, Position = p + Vector3.new(0, 30, 0), CanCollide = false })
				light(moon, def.Arena.Light, 30, 1)
			elseif alias == "Banners" or alias == "Hooks" or alias == "Gallows" then
				part(m, { Size = Vector3.new(1, 18, 1), Color = WOOD, Material = Enum.Material.Wood, Position = p + Vector3.new(0, 9, 0) })
				part(m, { Size = Vector3.new(5, 8, 0.3), Color = def.Arena.Light, Material = Enum.Material.Fabric, CanCollide = false, Position = p + Vector3.new(0, 13, 0) })
			elseif alias == "Shelves" then
				part(m, { Size = Vector3.new(10, 16, 3), Color = WOOD, Material = Enum.Material.WoodPlanks, CFrame = CFrame.lookAt(p + Vector3.new(0, 8, 0), o + Vector3.new(0, 8, 0)) })
			elseif alias == "Vats" then
				local vat = cylinderUp(m, p + Vector3.new(0, 3, 0), 7, 6, { Color = Color3.fromRGB(60, 70, 40), Material = Enum.Material.Metal })
				light(vat, def.Arena.Light, 16, 1)
			else
				part(m, { Size = Vector3.new(6 + rng:NextNumber() * 6, 3 + rng:NextNumber() * 5, 6), Color = def.Arena.Color, Material = Enum.Material.Rock, Position = p + Vector3.new(0, 2, 0) })
			end
		end
	end
end

function WorldBuilder.BuildArena(def, origin: Vector3): Model
	local m = Instance.new("Model")
	m.Name = "Arena_Floor" .. def.Floor
	local r = def.Arena.Size / 2
	local material = Enum.Material[def.Arena.Material] or Enum.Material.Slate
	cylinderUp(m, origin - Vector3.new(0, 2, 0), r * 2 + 24, 4, { Color = def.Arena.Color, Material = material, Name = "ArenaFloor" })
	-- walls
	local segs = 36
	for k = 0, segs - 1 do
		local ang = (k / segs) * math.pi * 2
		local w = 2 * math.pi * (r + 4) / segs + 1
		part(m, { Size = Vector3.new(w, 46, 4), Color = Color3.new(def.Arena.Color.R * 0.6, def.Arena.Color.G * 0.6, def.Arena.Color.B * 0.6),
			CFrame = CFrame.new(origin + Vector3.new(math.cos(ang) * (r + 4), 21, math.sin(ang) * (r + 4))) * CFrame.Angles(0, -ang + math.pi / 2, 0), Name = "ArenaWall" })
	end
	-- invisible ceiling keeps everyone inside
	cylinderUp(m, origin + Vector3.new(0, 80, 0), r * 2 + 24, 2, { Transparency = 1, Name = "Ceiling", CastShadow = false })
	local builder = PROPS[def.Arena.Props] or PROPS.Pillars
	builder(m, origin, r, def)
	-- lighting rig
	for k = 0, 3 do
		local ang = (k / 4) * math.pi * 2 + math.pi / 4
		local l = part(m, { Size = Vector3.new(1, 1, 1), Transparency = 1, CanCollide = false, Position = origin + Vector3.new(math.cos(ang) * r * 0.5, 30, math.sin(ang) * r * 0.5), Name = "Light" })
		light(l, def.Arena.Light, r * 1.4, 1.2)
	end
	-- floor number sigil
	local sigil = cylinderUp(m, origin + Vector3.new(0, 0.06, 0), 18, 0.12, { Color = def.Arena.Light, Material = Enum.Material.Neon, Transparency = 0.7, CanCollide = false, Name = "Sigil" })
	sigil.CastShadow = false
	m:SetAttribute("Floor", def.Floor)
	return m
end

-- ===================================================================== init
function WorldBuilder.Init(_services)
	map = Instance.new("Folder")
	map.Name = "Map"
	map.Parent = workspace
	-- Each step is isolated: a failure in decoration must never leave the world without ground.
	-- Terrain is built first because everything stands on it.
	local steps = {
		{ "terrain", buildTerrain },
		{ "lighting", buildLighting },
		{ "tower", buildTower },
		{ "hub", buildHub },
		{ "shrines", buildShrines },
		{ "chests", buildChests },
		{ "training", buildTraining },
		{ "regions", buildRegions },
	}
	for _, step in steps do
		local ok, err = pcall(step[2])
		if not ok then
			warn(("[WorldBuilder] building %s failed: %s"):format(step[1], tostring(err)))
		end
	end
	-- spawn location in the hub
	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.Position = v3(World.SpawnPoint) - Vector3.new(0, 3.5, 0)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Duration = 0
	spawn.Parent = map
	assert(#Bosses.List == 20, "expected 20 bosses")
end

function WorldBuilder.Start() end

return WorldBuilder
