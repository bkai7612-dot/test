--[[
	VfxController
	Client-side combat visual effects (purely cosmetic; the server decides all outcomes):
	  * Impact(pos, kind, radius): projectile / spell explosions - flash core, fireball,
	    shockwave ring, particle burst, light flash, sound and a little camera shake nearby
	  * EntityHit(model, ...): hit flash on the enemy, sparks, damage-type burst, bigger
	    burst for criticals / staggers / kills
	  * Slash(character, delay, duration): weapon trail during a swing
	Respects the Reduced Effects and Screen Shake settings.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local VfxController = {}
local ClientState, AudioController

local COLORS = {
	Fire = { Color3.fromRGB(255, 210, 110), Color3.fromRGB(255, 90, 20), Color3.fromRGB(70, 60, 55) },
	Magic = { Color3.fromRGB(190, 205, 255), Color3.fromRGB(100, 100, 255), Color3.fromRGB(60, 50, 120) },
	Holy = { Color3.fromRGB(255, 250, 210), Color3.fromRGB(255, 205, 90), Color3.fromRGB(200, 170, 110) },
	Poison = { Color3.fromRGB(200, 255, 120), Color3.fromRGB(80, 170, 40), Color3.fromRGB(60, 80, 40) },
	Arrow = { Color3.fromRGB(240, 235, 220), Color3.fromRGB(170, 160, 140), Color3.fromRGB(120, 110, 100) },
	Physical = { Color3.fromRGB(255, 245, 225), Color3.fromRGB(220, 200, 160), Color3.fromRGB(120, 110, 100) },
}

local function reduced(): boolean
	local s = ClientState and ClientState.Settings
	return s ~= nil and s.ReducedEffects == true
end

local function fxFolder(): Folder
	local f = workspace:FindFirstChild("ClientVfx")
	if not f then
		f = Instance.new("Folder")
		f.Name = "ClientVfx"
		f.Parent = workspace
	end
	return f :: Folder
end

local function vfxPart(shape: Enum.PartType?, color: Color3, size: Vector3, cf: CFrame, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = material or Enum.Material.Neon
	p.Color = color
	p.Size = size
	if shape then
		p.Shape = shape
	end
	p.CFrame = cf
	p.Parent = fxFolder()
	return p
end

local function burst(pos: Vector3, colors, count: number, speed: number, size: number, lifetime: number, upward: boolean?)
	local holder = vfxPart(nil, colors[1], Vector3.new(0.2, 0.2, 0.2), CFrame.new(pos))
	holder.Transparency = 1
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(colors[1], colors[2])
	e.LightEmission = 1
	e.Rate = 0
	e.Lifetime = NumberRange.new(lifetime * 0.6, lifetime)
	e.Speed = NumberRange.new(speed * 0.5, speed)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = if upward then Vector3.new(0, 8, 0) else Vector3.new(0, -20, 0)
	e.Drag = 3
	e.Size = NumberSequence.new(size, 0)
	e.Transparency = NumberSequence.new(0, 1)
	e.Parent = holder
	e:Emit(if reduced() then math.ceil(count / 3) else count)
	Debris:AddItem(holder, lifetime + 0.2)
	return holder
end

local function shakeNear(pos: Vector3, strength: number)
	local s = ClientState and ClientState.Settings
	if s and s.ScreenShake == false then
		return
	end
	local char = Players.LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not root or not hum then
		return
	end
	local d = ((root :: BasePart).Position - pos).Magnitude
	if d > 30 then
		return
	end
	local k = strength * (1 - d / 30)
	task.spawn(function()
		for i = 1, 5 do
			hum.CameraOffset = Vector3.new(math.random(-10, 10), math.random(-10, 10), 0) / 100 * k * (1 - i / 5)
			task.wait(0.03)
		end
		hum.CameraOffset = Vector3.zero
	end)
end

-- Explosion / impact at a point.
function VfxController.Impact(pos: Vector3, kind: string?, radius: number?, ground: boolean?)
	kind = kind or "Physical"
	local colors = COLORS[kind] or COLORS.Physical
	local r = math.clamp(radius or 3, 1, 30)
	if kind == "Arrow" then
		burst(pos, colors, 10, 12, 0.25, 0.35)
		AudioController.Play("Hit", pos)
		return
	end
	-- bright core flash
	local core = vfxPart(Enum.PartType.Ball, colors[1], Vector3.one * r * 0.4, CFrame.new(pos))
	TweenService:Create(core, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * r * 1.4, Transparency = 1 }):Play()
	Debris:AddItem(core, 0.25)
	-- fireball shell
	local shell = vfxPart(Enum.PartType.Ball, colors[2], Vector3.one * r * 0.6, CFrame.new(pos))
	shell.Transparency = 0.25
	TweenService:Create(shell, TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = Vector3.one * r * 2.2, Transparency = 1 }):Play()
	Debris:AddItem(shell, 0.5)
	-- shockwave ring on the ground plane
	local ringPos = if ground then pos + Vector3.new(0, 0.2, 0) else pos
	local ring = vfxPart(Enum.PartType.Cylinder, colors[1], Vector3.new(0.25, r, r), CFrame.new(ringPos) * CFrame.Angles(0, 0, math.rad(90)))
	ring.Transparency = 0.3
	TweenService:Create(ring, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.1, r * 3.2, r * 3.2), Transparency = 1 }):Play()
	Debris:AddItem(ring, 0.45)
	-- light flash
	local light = Instance.new("PointLight")
	light.Color = colors[2]
	light.Range = r * 5
	light.Brightness = 6
	light.Parent = shell
	TweenService:Create(light, TweenInfo.new(0.45), { Brightness = 0 }):Play()
	-- particles: sparks/embers + smoke
	burst(pos, colors, math.floor(18 + r * 4), 10 + r * 3, 0.5 + r * 0.08, 0.7, kind == "Fire" or kind == "Holy")
	if kind == "Fire" and not reduced() then
		local smoke = burst(pos, { colors[3], colors[3] }, 10, 4, r * 0.6, 1.4, true)
		local e = smoke:FindFirstChildOfClass("ParticleEmitter")
		if e then
			e.LightEmission = 0
			e.Transparency = NumberSequence.new(0.4, 1)
		end
	end
	AudioController.Play(if kind == "Fire" or r >= 6 then "Explosion" else "Hit", pos)
	shakeNear(pos, math.min(3, r * 0.5))
end

-- Hit reaction on an enemy model.
local flashes = {} -- [Model] = Highlight
function VfxController.EntityHit(model: Model?, pos: Vector3, damageType: string?, crit: boolean?, staggered: boolean?, heavy: boolean?, died: boolean?)
	local kind = if damageType == "Physical" or damageType == nil then "Physical" else damageType
	local colors = COLORS[kind] or COLORS.Physical
	if model and model.Parent then
		local h = flashes[model]
		if not h or not h.Parent then
			h = Instance.new("Highlight")
			h.DepthMode = Enum.HighlightDepthMode.Occluded
			h.OutlineTransparency = 1
			h.FillTransparency = 1
			h.Adornee = model
			h.Parent = model
			flashes[model] = h
		end
		local hl = h :: Highlight
		hl.FillColor = if crit then Color3.fromRGB(255, 220, 120) elseif kind == "Physical" then Color3.fromRGB(255, 255, 255) else colors[2]
		hl.FillTransparency = if crit or staggered then 0.15 else 0.45
		TweenService:Create(hl, TweenInfo.new(if crit then 0.3 else 0.18), { FillTransparency = 1 }):Play()
	end
	-- sparks
	burst(pos, colors, if crit then 26 else 12, if crit then 22 else 14, if crit then 0.45 else 0.3, 0.4)
	if kind ~= "Physical" then
		burst(pos, colors, 10, 6, 0.6, 0.6, true)
	end
	if crit or staggered or died then
		local ring = vfxPart(Enum.PartType.Ball, if crit then Color3.fromRGB(255, 225, 140) else colors[1], Vector3.one * 1.5, CFrame.new(pos))
		ring.Transparency = 0.3
		TweenService:Create(ring, TweenInfo.new(0.3), { Size = Vector3.one * (if died then 10 else 6), Transparency = 1 }):Play()
		Debris:AddItem(ring, 0.35)
		shakeNear(pos, if heavy then 1.5 else 0.8)
	end
end

-- Weapon trail during a swing.
local trails = {} -- [Model] = Trail
local function trailFor(character: Model): Trail?
	local gear = character:FindFirstChild("HeldGear")
	if not gear then
		return nil
	end
	local existing = trails[character]
	if existing and existing.Parent then
		return existing
	end
	local blade = gear:FindFirstChild("Blade") or gear:FindFirstChild("Head") or gear:FindFirstChild("Tip") or gear:FindFirstChild("Haft") or gear:FindFirstChild("Shaft")
	if not blade or not blade:IsA("BasePart") then
		return nil
	end
	local half = blade.Size.Z / 2
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0, -half)
	a0.Parent = blade
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, 0, half * 0.3)
	a1.Parent = blade
	local t = Instance.new("Trail")
	t.Attachment0 = a0
	t.Attachment1 = a1
	t.Lifetime = 0.18
	t.LightEmission = 0.6
	t.Color = ColorSequence.new(Color3.fromRGB(255, 250, 235), Color3.fromRGB(200, 190, 170))
	t.Transparency = NumberSequence.new(0.25, 1)
	t.MinLength = 0.05
	t.Enabled = false
	t.Parent = blade
	trails[character] = t
	return t
end

function VfxController.Slash(character: Model?, delay: number, duration: number)
	if not character or reduced() then
		return
	end
	local t = trailFor(character :: Model)
	if not t then
		return
	end
	task.delay(math.max(0, delay), function()
		if t.Parent then
			t.Enabled = true
			task.delay(duration, function()
				if t.Parent then
					t.Enabled = false
				end
			end)
		end
	end)
end

function VfxController.Init(deps)
	ClientState = deps.ClientState
	AudioController = deps.AudioController
end

return VfxController
