--[[
	HUDController
	Always-on interface: vitals (health/stamina/mana/XP/level), currency, region, flask and
	ability slots with cooldowns, boss bars, banners/toasts, death screen, damage numbers,
	enemy health bars, training progress, data-safety warnings and a controls legend.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Abilities = require(Shared.Config.Abilities)
local Items = require(Shared.Config.Items)
local World = require(Shared.Config.World)
local Formulas = require(Shared.Logic.Formulas)
local Net = require(Shared.Net)

local HUDController = {}

local player = Players.LocalPlayer
local UIKit, ClientState, AudioController, CombatController, InputController
local T
local gui: ScreenGui
local bars = {}
local labels = {}
local toastList: Frame
local bannerFrame: Frame
local bossFrame: Frame
local bossBars = {}
local trainingFrame: Frame
local abilitySlots = {}
local cooldowns = {}
local healthBars = {}
local uiScale: UIScale
local warningLabel: TextLabel
local vignette: Frame
local controlsLabel: TextLabel

local REGION_NAMES = {}
for _, r in World.Regions do
	REGION_NAMES[r.Id] = r.Name
end
REGION_NAMES.wilds = "The Wildlands"

-- ===================================================================== builders
local function buildVitals()
	local panel = UIKit.new("Frame", { Name = "Vitals", BackgroundTransparency = 1, Position = UDim2.fromOffset(18, 14), Size = UDim2.fromOffset(330, 110), Parent = gui })
	local badge = UIKit.panel({ Size = UDim2.fromOffset(52, 52), Parent = panel, BackgroundColor3 = T.Bg })
	labels.Level = UIKit.label("1", { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 26, Font = T.FontBold, TextColor3 = T.Accent, Parent = badge })
	bars.Health = UIKit.bar(panel, T.Health, { Position = UDim2.fromOffset(60, 0), Size = UDim2.fromOffset(260, 20) })
	bars.Stamina = UIKit.bar(panel, T.Stamina, { Position = UDim2.fromOffset(60, 24), Size = UDim2.fromOffset(220, 14) })
	bars.Mana = UIKit.bar(panel, T.Mana, { Position = UDim2.fromOffset(60, 42), Size = UDim2.fromOffset(200, 12) })
	bars.Xp = UIKit.bar(panel, T.Xp, { Position = UDim2.fromOffset(0, 60), Size = UDim2.fromOffset(320, 6) })
	bars.Xp.Text.Visible = false
	labels.Status = UIKit.label("", { Position = UDim2.fromOffset(0, 70), Size = UDim2.fromOffset(330, 20), TextSize = 16, TextColor3 = Color3.fromRGB(160, 230, 90), Parent = panel })
	labels.Lost = UIKit.label("", { Position = UDim2.fromOffset(0, 90), Size = UDim2.fromOffset(330, 20), TextSize = 16, TextColor3 = Color3.fromRGB(255, 150, 70), Parent = panel })
end

local function buildTopRight()
	local panel = UIKit.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -18, 0, 14), Size = UDim2.fromOffset(300, 80), Parent = gui })
	labels.Currency = UIKit.label("0 Embers", { Size = UDim2.new(1, 0, 0, 28), TextXAlignment = Enum.TextXAlignment.Right, TextSize = 24, TextColor3 = T.Accent, Font = T.FontBold, Parent = panel })
	labels.Region = UIKit.label("", { Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Right, TextSize = 20, Parent = panel })
	labels.Floor = UIKit.label("", { Position = UDim2.fromOffset(0, 52), Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Right, TextSize = 16, TextColor3 = T.Muted, Parent = panel })
	warningLabel = UIKit.label("", {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6), Size = UDim2.fromOffset(560, 26), TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 18, TextColor3 = Color3.fromRGB(255, 120, 100), BackgroundTransparency = 0.3, BackgroundColor3 = Color3.fromRGB(40, 10, 10), Visible = false, Parent = gui,
	})
end

local function buildHotbar()
	local panel = UIKit.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 18, 1, -18), Size = UDim2.fromOffset(420, 70), Parent = gui })
	local flask = UIKit.panel({ Size = UDim2.fromOffset(64, 64), BackgroundColor3 = T.Bg, Parent = panel })
	UIKit.label("Flask", { Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 14, TextColor3 = T.Muted, Parent = flask })
	labels.Flask = UIKit.label("3/3", { Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 40), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 24, Font = T.FontBold, TextColor3 = Color3.fromRGB(255, 150, 80), Parent = flask })
	for i, slot in { "Slot1", "Slot2" } do
		local box = UIKit.panel({ Position = UDim2.fromOffset(70 + (i - 1) * 132, 0), Size = UDim2.fromOffset(126, 64), BackgroundColor3 = T.Bg, Parent = panel })
		local name = UIKit.label("-", { Position = UDim2.fromOffset(6, 4), Size = UDim2.new(1, -12, 0, 36), TextSize = 16, TextXAlignment = Enum.TextXAlignment.Center, Parent = box })
		local key = UIKit.label(if i == 1 then "Z" else "X", { Position = UDim2.new(0, 6, 1, -22), Size = UDim2.new(1, -12, 0, 18), TextSize = 13, TextColor3 = T.Muted, TextXAlignment = Enum.TextXAlignment.Center, Parent = box })
		local cd = UIKit.new("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, BorderSizePixel = 0, Size = UDim2.fromScale(1, 0), AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Parent = box })
		abilitySlots[slot] = { Name = name, Key = key, Cooldown = cd }
	end
	labels.Quick = UIKit.label("", { Position = UDim2.fromOffset(340, 0), Size = UDim2.fromOffset(200, 64), TextSize = 14, TextColor3 = T.Muted, Parent = panel })
end

local function buildBoss()
	bossFrame = UIKit.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -100), Size = UDim2.fromOffset(640, 110), Visible = false, Parent = gui })
	labels.BossPhase = UIKit.label("", { Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 16, TextColor3 = T.Accent, Parent = bossFrame })
end

local function buildBanner()
	bannerFrame = UIKit.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.32), Size = UDim2.fromOffset(900, 130), Visible = false, Parent = gui })
	labels.BannerTitle = UIKit.label("", { Size = UDim2.new(1, 0, 0, 70), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 56, TextColor3 = T.Accent, TextStrokeTransparency = 0.4, Parent = bannerFrame })
	labels.BannerSub = UIKit.label("", { Position = UDim2.fromOffset(0, 72), Size = UDim2.new(1, 0, 0, 50), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 22, TextStrokeTransparency = 0.5, Parent = bannerFrame })
	toastList = UIKit.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -18, 0, 110), Size = UDim2.fromOffset(340, 400), Parent = gui })
	UIKit.new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Top, Parent = toastList })
	vignette = UIKit.new("Frame", { BackgroundColor3 = Color3.fromRGB(160, 0, 0), BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, ZIndex = 0, Parent = gui })
end

local function buildTraining()
	trainingFrame = UIKit.panel({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 40), Size = UDim2.fromOffset(420, 86), BackgroundColor3 = T.Bg, Visible = false, Parent = gui })
	UIKit.padding(trainingFrame, 8)
	labels.TrainName = UIKit.label("", { Size = UDim2.new(1, 0, 0, 24), TextSize = 22, TextColor3 = T.Accent, Parent = trainingFrame })
	labels.TrainDesc = UIKit.label("", { Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 0, 30), TextSize = 15, TextColor3 = T.Muted, Parent = trainingFrame })
	labels.TrainProgress = UIKit.label("", { Position = UDim2.fromOffset(0, 52), Size = UDim2.new(1, 0, 0, 20), TextSize = 18, Parent = trainingFrame })
end

local function buildControls()
	controlsLabel = UIKit.label("", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -14, 1, -14), Size = UDim2.fromOffset(330, 150), TextSize = 14, TextColor3 = T.Muted,
		TextXAlignment = Enum.TextXAlignment.Right, TextYAlignment = Enum.TextYAlignment.Bottom, Parent = gui })
end

local function refreshControls()
	local s = ClientState.Settings
	controlsLabel.Visible = (s == nil or s.ShowControls ~= false) and not UserInputService.TouchEnabled
	if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		controlsLabel.Text = "R1 attack  R2 heavy  L1 block  L2 parry\nB dodge  R3 lock-on  X flask  Y/Up skills\nSelect: menu"
	else
		controlsLabel.Text = "LMB attack  R heavy (hold)  RMB block  F parry\nQ dodge  Shift sprint  T lock-on  H flask\nZ/X skills  1-3 items  Tab menu  Alt cursor"
	end
end

-- ===================================================================== messages
function HUDController.Toast(text: string, kind: string?)
	local colors = { Reward = T.Accent, Loot = Color3.fromRGB(150, 200, 255), Warning = Color3.fromRGB(255, 170, 90), Error = T.Danger, Currency = T.Accent, Xp = Color3.fromRGB(200, 200, 140), Quest = Color3.fromRGB(180, 230, 160) }
	local f = UIKit.panel({ Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = T.Bg, BackgroundTransparency = 0.15, Parent = toastList })
	UIKit.label(text, { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 1, 0), TextSize = 16, TextColor3 = colors[kind or ""] or T.Text, TextTruncate = Enum.TextTruncate.AtEnd, Parent = f })
	local children = 0
	for _, c in toastList:GetChildren() do
		if c:IsA("Frame") then
			children += 1
		end
	end
	if children > 8 then
		for _, c in toastList:GetChildren() do
			if c:IsA("Frame") then
				c:Destroy()
				break
			end
		end
	end
	task.delay(4.5, function()
		if f.Parent then
			UIKit.tween(f, 0.4, { BackgroundTransparency = 1 })
			task.wait(0.4)
			f:Destroy()
		end
	end)
	if kind == "Reward" or kind == "Loot" then
		AudioController.Play("Reward")
	end
end

local bannerToken = 0
function HUDController.Banner(title: string, sub: string?, kind: string?)
	bannerToken += 1
	local token = bannerToken
	local death = kind == "Death"
	labels.BannerTitle.Text = title
	labels.BannerTitle.TextColor3 = if death then Color3.fromRGB(170, 20, 20) elseif kind == "Victory" then Color3.fromRGB(255, 210, 120) else T.Accent
	labels.BannerTitle.TextSize = if death then 84 else 56
	labels.BannerSub.Text = sub or ""
	bannerFrame.Visible = true
	labels.BannerTitle.TextTransparency = 1
	labels.BannerSub.TextTransparency = 1
	UIKit.tween(labels.BannerTitle, 0.6, { TextTransparency = 0 })
	UIKit.tween(labels.BannerSub, 0.9, { TextTransparency = 0 })
	if death then
		AudioController.Play("Death")
		UIKit.tween(vignette, 0.5, { BackgroundTransparency = 0.55 })
	end
	task.delay(if death then 3.6 else 3.2, function()
		if token == bannerToken then
			UIKit.tween(labels.BannerTitle, 0.6, { TextTransparency = 1 })
			UIKit.tween(labels.BannerSub, 0.6, { TextTransparency = 1 })
			UIKit.tween(vignette, 0.8, { BackgroundTransparency = 1 })
			task.wait(0.6)
			if token == bannerToken then
				bannerFrame.Visible = false
			end
		end
	end)
end

-- ===================================================================== world-space feedback
local function popText(position: Vector3, text: string, color: Color3, size: number?)
	local att = Instance.new("Attachment")
	att.WorldPosition = position + Vector3.new(math.random(-10, 10) / 10, 0, math.random(-10, 10) / 10)
	att.Parent = workspace.Terrain
	local b = Instance.new("BillboardGui")
	b.Size = UDim2.fromOffset(120, 40)
	b.AlwaysOnTop = true
	b.LightInfluence = 0
	b.Adornee = att
	local l = UIKit.label(text, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, Font = T.FontBold, TextSize = size or 22, TextColor3 = color, TextStrokeTransparency = 0.3, Parent = b })
	b.Parent = gui
	UIKit.tween(b, 0.9, { StudsOffset = Vector3.new(0, 3, 0) })
	task.delay(0.5, function()
		UIKit.tween(l, 0.4, { TextTransparency = 1, TextStrokeTransparency = 1 })
	end)
	Debris:AddItem(att, 1)
	Debris:AddItem(b, 1)
end

local function shake(intensity: number)
	local s = ClientState.Settings
	if s and s.ScreenShake == false then
		return
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	task.spawn(function()
		for i = 1, 6 do
			hum.CameraOffset = Vector3.new(math.random(-10, 10), math.random(-10, 10), 0) / 100 * intensity * (1 - i / 6)
			task.wait(0.03)
		end
		hum.CameraOffset = Vector3.zero
	end)
end

local function flash(color: Color3, alpha: number)
	vignette.BackgroundColor3 = color
	vignette.BackgroundTransparency = alpha
	UIKit.tween(vignette, 0.35, { BackgroundTransparency = 1 })
end

local function onFx(payload)
	local s = ClientState.Settings
	local t = payload.Type
	if t == "Damage" then
		if s == nil or s.ShowDamageNumbers ~= false then
			local color = if payload.Crit then Color3.fromRGB(255, 200, 80) elseif payload.WeakPoint then Color3.fromRGB(120, 255, 220) else Color3.fromRGB(240, 235, 225)
			local text = tostring(payload.Amount)
			if payload.Crit then
				text = payload.Crit .. "! " .. text
			end
			if payload.Proc then
				text ..= " " .. payload.Proc:upper()
			end
			if payload.Countered then
				text = "COUNTERED " .. text
			end
			popText(payload.Position, text, color, if payload.Crit then 28 else 22)
		end
		AudioController.Play("Hit", payload.Position)
	elseif t == "Hurt" then
		if payload.Outcome == "Blocked" then
			AudioController.Play("Parry")
			flash(Color3.fromRGB(200, 200, 200), 0.85)
		else
			AudioController.Play("Hurt")
			flash(Color3.fromRGB(160, 0, 0), if payload.Staggered then 0.55 else 0.75)
			shake(if payload.Staggered then 2 else 1)
		end
		if payload.Staggered or payload.GuardBroken then
			CombatController.OnStaggered(if payload.GuardBroken then GameConfig.Combat.GuardBreakStun else GameConfig.Combat.StaggerDuration)
			if payload.GuardBroken then
				HUDController.Toast("Guard broken!", "Warning")
			end
		end
		for _, proc in payload.Procs or {} do
			HUDController.Toast(proc .. "!", "Warning")
		end
	elseif t == "Parry" then
		AudioController.Play("Parry", payload.Position)
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.Shape = Enum.PartType.Ball
		p.Material = Enum.Material.Neon
		p.Color = Color3.fromRGB(255, 230, 150)
		p.Size = Vector3.new(1, 1, 1)
		p.Position = payload.Position + Vector3.new(0, 2, 0)
		p.Parent = workspace
		UIKit.tween(p, 0.25, { Size = Vector3.new(6, 6, 6), Transparency = 1 })
		Debris:AddItem(p, 0.3)
		popText(payload.Position + Vector3.new(0, 3, 0), "PARRY", Color3.fromRGB(255, 220, 120), 30)
	elseif t == "Dodged" then
		local r = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if r then
			popText((r :: BasePart).Position + Vector3.new(0, 3, 0), "Evaded", Color3.fromRGB(200, 220, 255), 18)
		end
	elseif t == "Heal" then
		local r = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if r then
			popText((r :: BasePart).Position + Vector3.new(0, 3, 0), "+" .. payload.Amount, Color3.fromRGB(120, 255, 120), 22)
		end
	elseif t == "AbilityCast" then
		cooldowns[payload.Ability] = { Start = os.clock(), Duration = payload.Cooldown }
	elseif t == "ActionDenied" then
		local msg = ({ NoMana = "Not enough mana", NoStamina = "Too exhausted", Cooldown = "Not ready", NoTarget = "Lock on to a target first" })[payload.Reason]
		if msg then
			HUDController.Toast(msg, "Warning")
		end
	elseif t == "Reward" then
		if payload.Position then
			popText(payload.Position + Vector3.new(0, 5, 0), ("+%d XP  +%d"):format(payload.Xp or 0, payload.Currency or 0), T.Accent, 18)
		end
	elseif t == "Buff" then
		HUDController.Toast(("%s active (%ds)"):format(payload.Buff, payload.Duration), "Reward")
	elseif t == "Dash" then
		CombatController.Dodge()
	elseif t == "AbilityFx" then
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.Material = Enum.Material.Neon
		p.Transparency = 0.4
		p.Color = Color3.fromRGB(255, 220, 160)
		if payload.Radius then
			p.Shape = Enum.PartType.Cylinder
			p.Size = Vector3.new(0.3, 1, 1)
			p.CFrame = CFrame.new(payload.Position - Vector3.new(0, 2.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
			p.Parent = workspace
			UIKit.tween(p, 0.35, { Size = Vector3.new(0.3, payload.Radius * 2, payload.Radius * 2), Transparency = 1 })
		else
			local len = payload.Length or 10
			p.Size = Vector3.new(payload.Width or 4, 0.3, len)
			p.CFrame = CFrame.lookAt(payload.Position, payload.Position + payload.Direction) * CFrame.new(0, -2.5, -len / 2)
			p.Parent = workspace
			UIKit.tween(p, 0.35, { Transparency = 1 })
		end
		Debris:AddItem(p, 0.4)
	elseif t == "Stagger" then
		HUDController.Toast("Enemy staggered - strike now!", "Reward")
	elseif t == "Blink" then
		AudioController.Play("Dodge", payload.Position)
	end
end

-- ===================================================================== boss bar
local function renderBossBars(list)
	for id, b in bossBars do
		local still = false
		for _, info in list do
			if info.Id == id then
				still = true
			end
		end
		if not still then
			b.Frame:Destroy()
			bossBars[id] = nil
		end
	end
	for i, info in list do
		local b = bossBars[info.Id]
		if not b then
			local frame = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), Parent = bossFrame })
			local name = UIKit.label(info.Name, { Size = UDim2.new(1, 0, 0, 22), TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left, Parent = frame })
			local bar = UIKit.bar(frame, Color3.fromRGB(150, 25, 25), { Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 0, 14) })
			local poise = UIKit.new("Frame", { BackgroundColor3 = Color3.fromRGB(230, 200, 120), BorderSizePixel = 0, Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 0, 3), Parent = frame })
			b = { Frame = frame, Name = name, Bar = bar, Poise = poise }
			bossBars[info.Id] = b
		end
		b.Frame.Position = UDim2.fromOffset(0, 22 + (i - 1) * 46)
		b.Bar:Set(info.Health, info.Max, false)
		b.Poise.Size = UDim2.new(math.clamp(info.Poise or 1, 0, 1), 0, 0, 3)
		b.Name.Text = info.Name .. (if info.Armor then "  [Armoured]" else "")
		if info.Health <= 0 then
			b.Name.TextColor3 = T.Muted
		end
	end
end

local function onBoss(payload)
	local t = payload.Type
	if t == "Start" then
		bossFrame.Visible = true
		labels.BossPhase.Text = ""
		renderBossBars(payload.Bosses)
		HUDController.Banner(("FLOOR %d"):format(payload.Floor), payload.Name .. " - " .. payload.Title .. "\n" .. payload.Mechanic, "Boss")
		AudioController.SetMusic("Boss")
		HUDController.ArenaTheme(payload.Theme)
	elseif t == "Update" then
		renderBossBars(payload.Bosses)
		labels.BossPhase.Text = payload.Stance or payload.Phase or ""
	elseif t == "Phase" then
		labels.BossPhase.Text = payload.Name
		HUDController.Toast(payload.Name, "Warning")
		shake(1.5)
	elseif t == "Victory" then
		HUDController.Banner(if payload.Final then "THE TOWER IS SILENT" else "GUARDIAN FELLED", payload.Name, "Victory")
		AudioController.SetMusic("Victory")
	elseif t == "Defeat" then
		bossFrame.Visible = false
	elseif t == "Removed" or t == "End" then
		bossFrame.Visible = false
		for id, b in bossBars do
			b.Frame:Destroy()
			bossBars[id] = nil
		end
		HUDController.ArenaTheme(nil)
		AudioController.SetMusic("")
	elseif t == "Ending" then
		HUDController.ShowEnding()
	end
end

HUDController.ArenaTheme = function(_theme) end -- replaced by EffectsController

function HUDController.ShowEnding()
	local f = UIKit.panel({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(620, 360), BackgroundColor3 = T.Bg, Parent = gui })
	UIKit.padding(f, 18)
	UIKit.label("The Sovereign of Ruin has fallen.", { Size = UDim2.new(1, 0, 0, 40), TextSize = 30, TextColor3 = T.Accent, TextXAlignment = Enum.TextXAlignment.Center, Parent = f })
	UIKit.label("Twenty guardians lie silent. The beacon atop the tower gutters out, and for the first time in an age the Sanctuary sees a clear dawn.\n\nThe tower remains - and so do you. Every guardian can be challenged again, every build reforged, every secret of the Wildlands still waits.\n\nThank you for playing Tower of the Fallen.",
		{ Position = UDim2.fromOffset(0, 50), Size = UDim2.new(1, 0, 1, -100), TextSize = 19, TextXAlignment = Enum.TextXAlignment.Center, Parent = f })
	UIKit.button("Continue", function()
		f:Destroy()
	end, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Parent = f })
end

-- ===================================================================== training
local function onTraining(payload)
	if payload.Type == "Start" then
		trainingFrame.Visible = true
		labels.TrainName.Text = payload.Name
		labels.TrainDesc.Text = payload.Description
		labels.TrainProgress.Text = ("Progress: 0 / %d"):format(payload.Goal)
		InputController.RepMode = payload.Kind == "Reps"
		HUDController.TrainingGoal = payload.Goal
		HUDController.TrainingEnds = payload.TimeLimit and (os.clock() + payload.TimeLimit) or nil
	elseif payload.Type == "Progress" then
		local extra = if payload.Failures then ("  (misses: %d)"):format(payload.Failures) else ""
		labels.TrainProgress.Text = ("Progress: %d / %d%s"):format(payload.Count, payload.Goal, extra)
	elseif payload.Type == "End" then
		trainingFrame.Visible = false
		InputController.RepMode = false
		HUDController.TrainingEnds = nil
	end
end

-- ===================================================================== entity health bars
local function attachHealthBar(inst: Instance)
	if not inst:IsA("Model") or healthBars[inst] then
		return
	end
	local model = inst :: Model
	local kind = model:GetAttribute("Kind")
	if kind == "Boss" or kind == "NPC" then
		return
	end
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	if not root then
		return
	end
	local height = model:GetAttribute("Height") or 5
	local b = Instance.new("BillboardGui")
	b.Size = UDim2.fromOffset(140, 30)
	b.StudsOffset = Vector3.new(0, height * 0.6 + 1.5, 0)
	b.MaxDistance = 70
	b.LightInfluence = 0
	b.Adornee = root
	local tier = model:GetAttribute("Tier")
	local nameColor = if tier == "Elite" then Color3.fromRGB(240, 180, 90) elseif tier == "MiniBoss" then Color3.fromRGB(255, 110, 90) else T.Text
	local name = UIKit.label(("%s  Lv.%d"):format(tostring(model:GetAttribute("DisplayName") or model.Name), tonumber(model:GetAttribute("Level")) or 1), {
		Size = UDim2.new(1, 0, 0, 14), TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = nameColor, TextStrokeTransparency = 0.4, Parent = b,
	})
	local bar = UIKit.bar(b, Color3.fromRGB(170, 35, 35), { Position = UDim2.fromOffset(10, 16), Size = UDim2.new(1, -20, 0, 7) })
	bar.Text.Visible = false
	local function update()
		local hp, max = model:GetAttribute("Health") or 0, model:GetAttribute("MaxHealth") or 1
		bar:Set(hp, max, false)
		b.Enabled = kind ~= "Dummy" and (hp < max or tier == "Elite" or tier == "MiniBoss")
	end
	update()
	local conn = model:GetAttributeChangedSignal("Health"):Connect(update)
	b.Parent = gui
	healthBars[model] = { Gui = b, Conn = conn, Name = name }
	model.AncestryChanged:Connect(function()
		if not model.Parent then
			conn:Disconnect()
			b:Destroy()
			healthBars[model] = nil
		end
	end)
end

-- ===================================================================== refresh
local function refreshProfile(p)
	if not p then
		return
	end
	labels.Level.Text = tostring(p.Level)
	local need = Formulas.xpToNext(p.Level)
	bars.Xp:Set(p.Xp, if need == math.huge then 1 else need, false)
	labels.Floor.Text = ("Tower: %d / %d floors cleared"):format(p.Tower.HighestCleared, GameConfig.Tower.Floors)
	for slot, ui in abilitySlots do
		local id = p.Abilities[slot]
		ui.Name.Text = if id ~= "" and Abilities[id] then Abilities[id].Name else "-"
	end
	local quick = {}
	for i, id in { "healing_draught", "mana_tonic", "stamina_tonic" } do
		local n = p.Inventory.Stacks[id] or 0
		table.insert(quick, ("[%d] %s x%d"):format(i, Items[id].Name, n))
	end
	labels.Quick.Text = table.concat(quick, "\n")
	if uiScale then
		uiScale.Scale = math.clamp(p.Settings.TextScale or 1, 0.75, 1.5)
	end
	refreshControls()
end

function HUDController.Init(deps)
	UIKit = deps.UIKit
	ClientState = deps.ClientState
	AudioController = deps.AudioController
	CombatController = deps.CombatController
	InputController = deps.InputController
	T = UIKit.Theme
	gui = UIKit.new("ScreenGui", { Name = "TotfHUD", ResetOnSpawn = false, IgnoreGuiInset = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = player:WaitForChild("PlayerGui") })
	uiScale = UIKit.new("UIScale", { Parent = gui })
	buildVitals()
	buildTopRight()
	buildHotbar()
	buildBoss()
	buildBanner()
	buildTraining()
	buildControls()

	ClientState.Changed:Connect(refreshProfile)
	Net.event("Fx").OnClientEvent:Connect(onFx)
	Net.event("Boss").OnClientEvent:Connect(onBoss)
	Net.event("Training").OnClientEvent:Connect(onTraining)
	Net.event("Notify").OnClientEvent:Connect(function(payload)
		if payload.Banner then
			HUDController.Banner(payload.Text, payload.Subtitle, payload.Kind)
		else
			HUDController.Toast(payload.Text, payload.Kind)
		end
	end)

	for _, m in CollectionService:GetTagged("Entity") do
		attachHealthBar(m)
	end
	CollectionService:GetInstanceAddedSignal("Entity"):Connect(attachHealthBar)

	RunService.Heartbeat:Connect(function()
		local hp, maxHp = player:GetAttribute("Health") or 0, player:GetAttribute("MaxHealth") or 1
		bars.Health:Set(hp, maxHp)
		bars.Stamina:Set(player:GetAttribute("Stamina") or 0, player:GetAttribute("MaxStamina") or 1)
		bars.Mana:Set(player:GetAttribute("Mana") or 0, player:GetAttribute("MaxMana") or 1)
		labels.Flask.Text = ("%d/%d"):format(player:GetAttribute("FlaskCharges") or 0, player:GetAttribute("FlaskMax") or 0)
		labels.Currency.Text = ("%d %s"):format(player:GetAttribute("Currency") or 0, GameConfig.Currency.Name)
		local region = player:GetAttribute("Region")
		labels.Region.Text = REGION_NAMES[region or ""] or ""
		if player:GetAttribute("ArenaFloor") then
			labels.Region.Text = ("Tower Floor %d"):format(player:GetAttribute("ArenaFloor"))
		end
		local status = {}
		if player:GetAttribute("Poisoned") then
			table.insert(status, "Poisoned")
		end
		if player:GetAttribute("Burning") then
			table.insert(status, "Burning")
		end
		if player:GetAttribute("Blocking") then
			table.insert(status, "Guarding")
		end
		if CombatController.IsCharging() then
			table.insert(status, "Charging...")
		end
		labels.Status.Text = table.concat(status, "  ")
		local p = ClientState.Profile
		local lost = p and p.LostCurrency
		if lost then
			local remain = lost.CreatedAt + GameConfig.Death.RecoveryExpirySeconds - os.time()
			labels.Lost.Text = ("Lost embers: %d (fade in %d:%02d)"):format(lost.Amount, math.max(0, remain) // 60, math.max(0, remain) % 60)
		else
			labels.Lost.Text = ""
		end
		-- ability cooldowns
		for slot, ui in abilitySlots do
			local id = p and p.Abilities[slot]
			local cd = id and cooldowns[id]
			local frac = 0
			if cd then
				frac = math.clamp(1 - (os.clock() - cd.Start) / cd.Duration, 0, 1)
			end
			ui.Cooldown.Size = UDim2.fromScale(1, frac)
		end
		-- data safety warnings
		if player:GetAttribute("DataUnsaved") then
			warningLabel.Visible = true
			warningLabel.Text = "Studio test mode: progress is NOT being saved (DataStore unavailable)"
		elseif player:GetAttribute("DataSaveFailing") then
			warningLabel.Visible = true
			warningLabel.Text = "Warning: saving is failing - your progress will retry automatically"
		else
			warningLabel.Visible = false
		end
		if HUDController.TrainingEnds then
			local left = math.max(0, HUDController.TrainingEnds - os.clock())
			labels.TrainDesc.Text = ("Time left: %.1fs"):format(left)
		end
	end)
	refreshControls()
end

return HUDController
