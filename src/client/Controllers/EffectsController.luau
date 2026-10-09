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

local REGION_ATMOSPHERE = {
	sanctuary = { Density = 0.38, Color = Color3.fromRGB(160, 140, 140), Haze = 1.8 },
	training = { Density = 0.36, Color = Color3.fromRGB(170, 150, 130), Haze = 1.5 },
	forest = { Density = 0.6, Color = Color3.fromRGB(150, 165, 160), Haze = 3.2 },
	village = { Density = 0.42, Color = Color3.fromRGB(160, 130, 110), Haze = 2 },
	cemetery = { Density = 0.55, Color = Color3.fromRGB(130, 140, 165), Haze = 2.8 },
	caves = { Density = 0.5, Color = Color3.fromRGB(60, 60, 70), Haze = 1 },
	fortress = { Density = 0.44, Color = Color3.fromRGB(150, 120, 110), Haze = 2.2 },
	vale = { Density = 0.4, Color = Color3.fromRGB(120, 190, 170), Haze = 2 },
	pvp = { Density = 0.42, Color = Color3.fromRGB(150, 110, 100), Haze = 2 },
	wilds = { Density = 0.45, Color = Color3.fromRGB(150, 140, 145), Haze = 2.2 },
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
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atmo or not target then
		return
	end
	TweenService:Create(atmo, TweenInfo.new(2.5), { Density = target.Density, Color = target.Color, Haze = target.Haze }):Play()
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
			applyAtmosphere({ Density = 0.5, Color = theme.Fog, Haze = 2.5 })
		else
			lastRegion = nil
			applyAtmosphere(REGION_ATMOSPHERE[player:GetAttribute("Region") or "wilds"] or REGION_ATMOSPHERE.wilds)
		end
	end
end

return EffectsController
