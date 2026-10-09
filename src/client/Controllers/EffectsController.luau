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
local REGION_ATMOSPHERE = {
	sanctuary = { Density = 0.22, Color = Color3.fromRGB(215, 205, 195), Haze = 0.8, Brightness = 3.2, Exposure = 0.45, Ambient = Color3.fromRGB(125, 120, 120), Outdoor = Color3.fromRGB(175, 170, 165) },
	training = { Density = 0.22, Color = Color3.fromRGB(215, 205, 190), Haze = 0.8, Brightness = 3.2, Exposure = 0.45, Ambient = Color3.fromRGB(125, 120, 115), Outdoor = Color3.fromRGB(175, 170, 160) },
	pvp = { Density = 0.3, Color = Color3.fromRGB(190, 160, 150), Haze = 1.2, Brightness = 2.8, Exposure = 0.3, Ambient = Color3.fromRGB(115, 105, 105), Outdoor = Color3.fromRGB(160, 150, 145) },
	forest = { Density = 0.45, Color = Color3.fromRGB(175, 190, 185), Haze = 2.2, Brightness = 2.2, Exposure = 0.2, Ambient = Color3.fromRGB(100, 108, 104), Outdoor = Color3.fromRGB(140, 150, 145) },
	village = { Density = 0.32, Color = Color3.fromRGB(190, 165, 145), Haze = 1.4, Brightness = 2.6, Exposure = 0.25, Ambient = Color3.fromRGB(110, 102, 98), Outdoor = Color3.fromRGB(155, 145, 138) },
	cemetery = { Density = 0.42, Color = Color3.fromRGB(160, 170, 195), Haze = 2, Brightness = 2.1, Exposure = 0.2, Ambient = Color3.fromRGB(98, 104, 118), Outdoor = Color3.fromRGB(135, 142, 160) },
	caves = { Density = 0.35, Color = Color3.fromRGB(110, 110, 125), Haze = 0.8, Brightness = 2, Exposure = 0.45, Ambient = Color3.fromRGB(110, 110, 125), Outdoor = Color3.fromRGB(120, 120, 135) },
	fortress = { Density = 0.32, Color = Color3.fromRGB(185, 160, 150), Haze = 1.5, Brightness = 2.5, Exposure = 0.25, Ambient = Color3.fromRGB(108, 100, 98), Outdoor = Color3.fromRGB(150, 140, 135) },
	vale = { Density = 0.3, Color = Color3.fromRGB(160, 215, 200), Haze = 1.2, Brightness = 2.8, Exposure = 0.3, Ambient = Color3.fromRGB(100, 125, 118), Outdoor = Color3.fromRGB(145, 175, 165) },
	wilds = { Density = 0.32, Color = Color3.fromRGB(190, 182, 185), Haze = 1.4, Brightness = 2.6, Exposure = 0.25, Ambient = Color3.fromRGB(108, 104, 106), Outdoor = Color3.fromRGB(155, 150, 150) },
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
		if e:IsA("BloomEffect") or e:IsA("SunRaysEffect") then
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
			applyAtmosphere({ Density = 0.3, Color = theme.Fog, Haze = 1.2, Brightness = 2.6, Exposure = 0.35,
				Ambient = Color3.fromRGB(115, 110, 115), Outdoor = Color3.fromRGB(150, 145, 150) })
		else
			lastRegion = nil
			applyAtmosphere(REGION_ATMOSPHERE[player:GetAttribute("Region") or "wilds"] or REGION_ATMOSPHERE.wilds)
		end
	end
end

return EffectsController
