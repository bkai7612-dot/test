--[[
	CameraController
	Third-person camera with target lock-on:
	  * Lock picks the entity closest to screen centre within LOCK_RANGE.
	  * Switch cycles to the next target left/right of the current one.
	  * While locked, the camera frames player + target, the character faces the target,
	    and camera collision is handled by raycasting from the focus point.
	  * Lock breaks on target death, distance or line-of-sight loss for too long.
	  * Camera recovers automatically on respawn.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage:WaitForChild("Shared").Util.Signal)

local CameraController = {
	Target = nil :: Model?,
	TargetChanged = Signal.new(),
}

local LOCK_RANGE = 70
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local lostSight = 0
local reticle: BillboardGui? = nil

local function root(): BasePart?
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function targetPart(model: Model): BasePart?
	local r = model:FindFirstChild("HumanoidRootPart")
	if r and r:IsA("BasePart") then
		return r
	end
	return model.PrimaryPart
end

local function alive(m: Model?): boolean
	if not m or not m.Parent then
		return false
	end
	local model = m :: Model
	local hp = model:GetAttribute("Health")
	local kind = model:GetAttribute("Kind")
	return kind ~= "NPC" and (hp == nil or hp > 0) and targetPart(model) ~= nil
end

local function candidates(): { Model }
	local out = {}
	local r = root()
	if not r then
		return out
	end
	for _, m in CollectionService:GetTagged("Entity") do
		if m:IsA("Model") and alive(m) then
			local tp = targetPart(m)
			if tp and (tp.Position - r.Position).Magnitude <= LOCK_RANGE then
				table.insert(out, m)
			end
		end
	end
	-- other players in the PvP pit
	if player:GetAttribute("PvP") then
		for _, other in Players:GetPlayers() do
			if other ~= player and other:GetAttribute("PvP") and other.Character and other.Character:FindFirstChild("HumanoidRootPart") then
				table.insert(out, other.Character)
			end
		end
	end
	return out
end

local function setReticle(model: Model?)
	if reticle then
		reticle:Destroy()
		reticle = nil
	end
	if model then
		local tp = targetPart(model)
		if tp then
			local b = Instance.new("BillboardGui")
			b.Name = "LockReticle"
			b.Size = UDim2.fromOffset(34, 34)
			b.AlwaysOnTop = true
			b.LightInfluence = 0
			b.Adornee = tp
			local img = Instance.new("Frame")
			img.Size = UDim2.fromScale(1, 1)
			img.BackgroundTransparency = 1
			local stroke = Instance.new("UIStroke")
			stroke.Color = Color3.fromRGB(255, 220, 140)
			stroke.Thickness = 2
			stroke.Parent = img
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(1, 0)
			corner.Parent = img
			local dot = Instance.new("Frame")
			dot.Size = UDim2.fromOffset(8, 8)
			dot.Position = UDim2.new(0.5, -4, 0.5, -4)
			dot.BackgroundColor3 = Color3.fromRGB(255, 220, 140)
			local c2 = corner:Clone()
			c2.Parent = dot
			dot.Parent = img
			img.Parent = b
			b.Parent = player:WaitForChild("PlayerGui")
			reticle = b
		end
	end
end

function CameraController.SetTarget(model: Model?)
	CameraController.Target = model
	lostSight = 0
	setReticle(model)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.AutoRotate = model == nil
	end
	CameraController.TargetChanged:Fire(model)
end

function CameraController.ToggleLock()
	if CameraController.Target then
		CameraController.SetTarget(nil)
		return
	end
	local best, bestScore = nil, math.huge
	local vp = camera.ViewportSize
	for _, m in candidates() do
		local tp = targetPart(m) :: BasePart
		local screen, onScreen = camera:WorldToViewportPoint(tp.Position)
		if onScreen then
			local d = (Vector2.new(screen.X, screen.Y) - vp / 2).Magnitude
			if d < bestScore then
				best, bestScore = m, d
			end
		end
	end
	if not best then
		-- nothing on screen: nearest
		local r = root()
		for _, m in candidates() do
			local d = ((targetPart(m) :: BasePart).Position - (r :: BasePart).Position).Magnitude
			if d < bestScore then
				best, bestScore = m, d
			end
		end
	end
	CameraController.SetTarget(best)
end

-- dir: +1 right, -1 left
function CameraController.Switch(dir: number)
	local cur = CameraController.Target
	if not cur then
		return
	end
	local curScreen = camera:WorldToViewportPoint((targetPart(cur) :: BasePart).Position)
	local best, bestDx = nil, math.huge
	for _, m in candidates() do
		if m ~= cur then
			local s = camera:WorldToViewportPoint((targetPart(m) :: BasePart).Position)
			local dx = (s.X - curScreen.X) * dir
			if dx > 0 and dx < bestDx then
				best, bestDx = m, dx
			end
		end
	end
	if best then
		CameraController.SetTarget(best)
	end
end

function CameraController.Init()
	player.CharacterAdded:Connect(function()
		CameraController.SetTarget(nil)
		camera.CameraType = Enum.CameraType.Custom
	end)
	UserInputService.InputChanged:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.MouseWheel and CameraController.Target and not processed then
			CameraController.Switch(if input.Position.Z > 0 then 1 else -1)
		end
	end)
	RunService:BindToRenderStep("TotfLockOn", Enum.RenderPriority.Camera.Value + 1, function(dt)
		local target = CameraController.Target
		if not target then
			return
		end
		local r = root()
		if not alive(target) or not r then
			CameraController.SetTarget(nil)
			return
		end
		local tp = targetPart(target) :: BasePart
		local toTarget = tp.Position - r.Position
		if toTarget.Magnitude > LOCK_RANGE + 15 then
			CameraController.SetTarget(nil)
			return
		end
		-- face target (horizontal)
		local flat = Vector3.new(toTarget.X, 0, toTarget.Z)
		if flat.Magnitude > 0.5 and not player:GetAttribute("Dodging") then
			r.CFrame = CFrame.lookAt(r.Position, r.Position + flat)
		end
		-- frame both
		local focus = r.Position + Vector3.new(0, 3, 0)
		local back = if flat.Magnitude > 0.1 then -flat.Unit else -r.CFrame.LookVector
		local desired = focus + back * 14 + Vector3.new(0, 4.5, 0)
		rayParams.FilterDescendantsInstances = { player.Character, target }
		local hit = workspace:Raycast(focus, desired - focus, rayParams)
		if hit then
			desired = hit.Position + (focus - hit.Position).Unit * 0.8
		end
		local look = CFrame.lookAt(desired, tp.Position:Lerp(focus, 0.35))
		camera.CFrame = camera.CFrame:Lerp(look, math.clamp(dt * 12, 0, 1))
		-- line of sight
		local los = workspace:Raycast(focus, tp.Position - focus, rayParams)
		if los then
			lostSight += dt
			if lostSight > 2.5 then
				CameraController.SetTarget(nil)
			end
		else
			lostSight = 0
		end
	end)
end

-- Aim direction for ranged attacks: at the locked target, else where the camera looks.
function CameraController.AimDirection(): Vector3
	local r = root()
	if CameraController.Target and r then
		local tp = targetPart(CameraController.Target)
		if tp then
			return (tp.Position - (r.Position + Vector3.new(0, 1.5, 0))).Unit
		end
	end
	return camera.CFrame.LookVector
end

function CameraController.TargetEntityId(): number?
	local t = CameraController.Target
	return t and t:GetAttribute("EntityId") or nil
end

return CameraController
