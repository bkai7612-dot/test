--[[
	EffectsController
	Client-only presentation:
	  * high-contrast telegraph colours (accessibility)
	  * lost-ember markers: only your own is shown, with its amount
	  * tower floor rings reflect YOUR progress; opened chests look opened
	  * regional and arena ambience (atmosphere, fog colour, music)
	  * reduced-effects mode
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local EffectsController = {}
local player = Players.LocalPlayer
local ClientState, HUD, AudioController

local HIGH_CONTRAST = {
	Parry = Color3.fromRGB(0, 210, 255),
	Block = Color3.fromRGB(255, 255, 255),
	Danger = Color3.fromRGB(255, 0, 200),
	Safe = Color3.fromRGB(0, 255, 90),
	Hazard = Color3.fromRGB(255, 140, 0),
}

-- Per-region look. The hub and training grounds are bright and welcoming; the wilds are
-- moodier but always readable (Ambient never drops low enough to hide enemies).
-- Night everywhere: dark atmosphere and sky, but a strong cool ambient + moonlight so the
-- ground, enemies and telegraphs stay easy to read. The hub is the brightest area.
local REGION_ATMOSPHERE = {
	sanctuary = { Density = 0.2, Color = Color3.fromRGB(80, 90, 125), Haze = 0.3, Brightness = 3.4, Exposure = 0.7, Ambient = Color3.fromRGB(130, 132, 155), Outdoor = Color3.fromRGB(170, 175, 205) },
	training = { Density = 0.2, Color = Color3.fromRGB(85, 90, 120), Haze = 0.3, Brightness = 3.4, Exposure = 0.7, Ambient = Color3.fromRGB(130, 130, 150), Outdoor = Color3.fromRGB(170, 172, 200) },
	pvp = { Density = 0.26, Color = Color3.fromRGB(95, 70, 85), Haze = 0.5, Brightness = 3, Exposure = 0.55, Ambient = Color3.fromRGB(120, 112, 130), Outdoor = Color3.fromRGB(160, 150, 175) },
	forest = { Density = 0.34, Color = Color3.fromRGB(55, 80, 85), Haze = 0.9, Brightness = 2.8, Exposure = 0.55, Ambient = Color3.fromRGB(108, 120, 125), Outdoor = Color3.fromRGB(145, 160, 170) },
	village = { Density = 0.28, Color = Color3.fromRGB(90, 75, 85), Haze = 0.6, Brightness = 3, Exposure = 0.55, Ambient = Color3.fromRGB(118, 112, 125), Outdoor = Color3.fromRGB(158, 152, 172) },
	cemetery = { Density = 0.34, Color = Color3.fromRGB(65, 75, 110), Haze = 0.9, Brightness = 2.8, Exposure = 0.55, Ambient = Color3.fromRGB(108, 115, 140), Outdoor = Color3.fromRGB(145, 155, 185) },
	caves = { Density = 0.3, Color = Color3.fromRGB(55, 58, 75), Haze = 0.5, Brightness = 2.6, Exposure = 0.65, Ambient = Color3.fromRGB(118, 118, 138), Outdoor = Color3.fromRGB(128, 128, 150) },
	fortress = { Density = 0.28, Color = Color3.fromRGB(90, 70, 75), Haze = 0.6, Brightness = 2.9, Exposure = 0.55, Ambient = Color3.fromRGB(116, 108, 120), Outdoor = Color3.fromRGB(155, 145, 165) },
	vale = { Density = 0.26, Color = Color3.fromRGB(55, 95, 100), Haze = 0.5, Brightness = 3.1, Exposure = 0.6, Ambient = Color3.fromRGB(105, 130, 130), Outdoor = Color3.fromRGB(145, 180, 180) },
	wilds = { Density = 0.26, Color = Color3.fromRGB(75, 82, 110), Haze = 0.5, Brightness = 3, Exposure = 0.55, Ambient = Color3.fromRGB(115, 115, 135), Outdoor = Color3.fromRGB(158, 160, 188) },
}

local function settings()
	return ClientState.Settings or {}
end

local function recolorTelegraph(obj: Instance)
	if not obj:IsA("BasePart") then
		return
	end
	local inst = obj :: BasePart
	local kind = inst:GetAttribute("Telegraph")
	if kind and settings().HighContrastTelegraphs and HIGH_CONTRAST[kind] then
		inst.Color = HIGH_CONTRAST[kind]
		inst.Transparency = math.min(inst.Transparency, 0.4)
	end
end

local function handleMarker(obj: Instance)
	if not obj:IsA("BasePart") then
		return
	end
	local marker = obj :: BasePart
	local mine = marker:GetAttribute("OwnerUserId") == player.UserId
	if not mine then
		for _, d in marker:GetDescendants() do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = 1
			elseif d:IsA("Light") or d:IsA("ParticleEmitter") then
				d.Enabled = false
			end
		end
		marker.LocalTransparencyModifier = 1
		return
	end
	local b = Instance.new("BillboardGui")
	b.Size = UDim2.fromOffset(200, 40)
	b.StudsOffset = Vector3.new(0, 3, 0)
	b.AlwaysOnTop = true
	b.LightInfluence = 0
	b.MaxDistance = 400
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(1, 1)
	l.Font = Enum.Font.Garamond
	l.TextScaled = true
	l.TextColor3 = Color3.fromRGB(255, 170, 90)
	l.TextStrokeTransparency = 0.3
	l.Text = ("Your lost embers (%d)"):format(tonumber(marker:GetAttribute("Amount")) or 0)
	l.Parent = b
	b.Parent = marker
end

local function refreshTower()
	local p = ClientState.Profile
	if not p then
		return
	end
	local map = workspace:FindFirstChild("Map")
	local tower = map and map:FindFirstChild("TowerOfTheFallen")
	if not tower then
		return
	end
	for _, ring in tower:GetChildren() do
		if ring.Name == "FloorRing" and ring:IsA("BasePart") then
			local floor = ring:GetAttribute("Floor")
			if floor <= p.Tower.HighestCleared then
				ring.Color = Color3.fromRGB(255, 200, 110)
			elseif floor == p.Tower.HighestCleared + 1 then
				ring.Color = Color3.fromRGB(255, 90, 40)
			else
				ring.Color = Color3.fromRGB(50, 40, 40)
			end
		end
	end
	-- the vale seal disappears for those who earned passage
	local valeFolder = map:FindFirstChild("HollowVale")
	local seal = valeFolder and valeFolder:FindFirstChild("ValeSeal")
	if seal and seal:IsA("BasePart") then
		seal.LocalTransparencyModifier = if p.Tower.HighestCleared >= 10 then 1 else 0
	end
	-- opened chests
	for _, box in CollectionService:GetTagged("Chest") do
		local opened = p.OpenedChests[box:GetAttribute("ChestId")] == true
		local light = box:FindFirstChildOfClass("PointLight")
		if light then
			light.Enabled = not opened
		end
		if box:IsA("BasePart") then
			box.Color = if opened then Color3.fromRGB(70, 60, 50) else Color3.fromRGB(70, 52, 38)
		end
	end
end

local function applyAtmosphere(target)
	if not target then
		return
	end
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmo then
		TweenService:Create(atmo, TweenInfo.new(2.5), { Density = target.Density, Color = target.Color, Haze = target.Haze }):Play()
	end
	if target.Brightness then
		TweenService:Create(Lighting, TweenInfo.new(2.5), {
			Brightness = target.Brightness,
			ExposureCompensation = target.Exposure,
			Ambient = target.Ambient,
			OutdoorAmbient = target.Outdoor,
		}):Play()
	end
end

function EffectsController.ApplySettings(s)
	local reduced = s.ReducedEffects == true
	for _, e in Lighting:GetChildren() do
		if e:IsA("BloomEffect") or e:IsA("SunRaysEffect") or e:IsA("DepthOfFieldEffect") then
			e.Enabled = not reduced
		end
	end
	local telegraphs = workspace:FindFirstChild("Telegraphs")
	if telegraphs then
		for _, d in telegraphs:GetDescendants() do
			recolorTelegraph(d)
		end
	end
end

function EffectsController.Init(deps)
	ClientState = deps.ClientState
	HUD = deps.HUDController
	AudioController = deps.AudioController

	task.spawn(function()
		local telegraphs = workspace:WaitForChild("Telegraphs", 30)
		if telegraphs then
			telegraphs.DescendantAdded:Connect(function(d)
				task.defer(recolorTelegraph, d)
			end)
		end
	end)
	task.spawn(function()
		local markers = workspace:WaitForChild("LostEmbers", 30)
		if markers then
			for _, m in markers:GetChildren() do
				handleMarker(m)
			end
			markers.ChildAdded:Connect(function(m)
				task.defer(handleMarker, m)
			end)
		end
	end)

	ClientState.Changed:Connect(function(p)
		refreshTower()
		EffectsController.ApplySettings(p.Settings)
		AudioController.ApplySettings(p.Settings)
	end)
	CollectionService:GetInstanceAddedSignal("Chest"):Connect(function()
		task.defer(refreshTower)
	end)

	applyAtmosphere(REGION_ATMOSPHERE.sanctuary)
	local lastRegion
	player:GetAttributeChangedSignal("Region"):Connect(function()
		local region = player:GetAttribute("Region")
		if region ~= lastRegion and not player:GetAttribute("ArenaFloor") then
			lastRegion = region
			applyAtmosphere(REGION_ATMOSPHERE[region] or REGION_ATMOSPHERE.wilds)
			AudioController.SetMusic(if region == "sanctuary" or region == "training" then "Sanctuary" else "Wilds")
		end
	end)

	HUD.ArenaTheme = function(theme)
		if theme then
			-- arenas: themed fog colour, but bright enough to read every telegraph
			applyAtmosphere({ Density = 0.26, Color = theme.Fog:Lerp(Color3.fromRGB(40, 45, 70), 0.5), Haze = 0.6, Brightness = 3, Exposure = 0.6,
				Ambient = Color3.fromRGB(125, 122, 140), Outdoor = Color3.fromRGB(160, 160, 185) })
		else
			lastRegion = nil
			applyAtmosphere(REGION_ATMOSPHERE[player:GetAttribute("Region") or "wilds"] or REGION_ATMOSPHERE.wilds)
		end
	end
end

return EffectsController
