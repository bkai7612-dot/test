--[[
	CombatController
	Turns input into server intents and gives immediate local feedback:
	  * light/heavy attacks (heavy charge timed locally, clamped on the server)
	  * dodge: local dash movement for responsiveness; i-frames are granted by the server
	  * block (hold) / parry (tap) / sprint
	  * abilities, flask and quick items
	A small local action lock mirrors server timings to avoid spamming rejected requests.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local WeaponTypes = require(Shared.Config.WeaponTypes)
local Net = require(Shared.Net)

local CombatController = {}

local player = Players.LocalPlayer
local actionRemote: RemoteEvent
local CameraController, ClientState, AudioController
local lockUntil = 0
local heavyStart: number? = nil
local lastDodge = 0
local blocking = false

function CombatController.Init(deps)
	CameraController = deps.CameraController
	ClientState = deps.ClientState
	AudioController = deps.AudioController
	actionRemote = Net.event("Action")
end

local function send(payload)
	actionRemote:FireServer(payload)
end

local function canAct(): boolean
	if player:GetAttribute("Health") == 0 then
		return false
	end
	local p = ClientState.Profile
	return p ~= nil and p.Class ~= "" and os.clock() >= lockUntil
end

local function weaponType()
	local p = ClientState.Profile
	local wt = p and p.Derived and p.Derived.WeaponType or "Fist"
	return WeaponTypes[wt] or WeaponTypes.Fist, wt
end

function CombatController.Light()
	if not canAct() then
		return
	end
	local wt = weaponType()
	lockUntil = os.clock() + wt.Light.Windup + wt.Light.Recovery * 0.8
	send({ Kind = "Light", Aim = CameraController.AimDirection() })
	AudioController.Play("Swing")
end

function CombatController.HeavyBegin()
	if not canAct() then
		return
	end
	heavyStart = os.clock()
end

function CombatController.HeavyEnd()
	if not heavyStart then
		return
	end
	local charge = os.clock() - (heavyStart :: number)
	heavyStart = nil
	if not canAct() then
		return
	end
	local wt = weaponType()
	lockUntil = os.clock() + wt.Heavy.Windup + wt.Heavy.Recovery * 0.8
	send({ Kind = "Heavy", Charge = math.min(charge, GameConfig.Combat.HeavyChargeMax), Aim = CameraController.AimDirection() })
	AudioController.Play("HeavySwing")
end

function CombatController.IsCharging(): boolean
	return heavyStart ~= nil
end

function CombatController.Dodge()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not root or hum.Health <= 0 then
		return
	end
	if os.clock() - lastDodge < GameConfig.Combat.DodgeCooldown or (player:GetAttribute("Stamina") or 0) <= 0 then
		return
	end
	lastDodge = os.clock()
	lockUntil = os.clock() + 0.35
	send({ Kind = "Dodge" })
	-- local dash (character physics are client-owned)
	local dir = hum.MoveDirection
	if dir.Magnitude < 0.1 then
		dir = -root.CFrame.LookVector -- backstep
	end
	dir = Vector3.new(dir.X, 0, dir.Z).Unit
	local tier = ClientState.Profile and ClientState.Profile.Derived and ClientState.Profile.Derived.LoadTier or "Medium"
	local dist = GameConfig.Combat.DodgeDistance * (if tier == "Overloaded" then 0.45 elseif tier == "Heavy" then 0.8 else 1)
	local duration = 0.32
	local att = Instance.new("Attachment")
	att.Parent = root
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att
	lv.MaxForce = 1e6
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	lv.PrimaryTangentAxis = Vector3.new(1, 0, 0)
	lv.SecondaryTangentAxis = Vector3.new(0, 0, 1)
	lv.PlaneVelocity = Vector2.new(dir.X, dir.Z) * (dist / duration)
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.Parent = root
	player:SetAttribute("Dodging", true)
	AudioController.Play("Dodge")
	-- visual trail
	local trail = Instance.new("ParticleEmitter")
	trail.Rate = 60
	trail.Lifetime = NumberRange.new(0.25)
	trail.Speed = NumberRange.new(0)
	trail.Size = NumberSequence.new(1.2, 0)
	trail.Transparency = NumberSequence.new(0.5, 1)
	trail.Color = ColorSequence.new(Color3.fromRGB(200, 190, 170))
	trail.Parent = att
	Debris:AddItem(att, duration + 0.3)
	Debris:AddItem(lv, duration)
	task.delay(duration, function()
		trail.Enabled = false
		player:SetAttribute("Dodging", false)
	end)
end

function CombatController.SetBlock(on: boolean)
	if on == blocking then
		return
	end
	blocking = on
	send({ Kind = "Block", On = on })
end

function CombatController.Parry()
	if not canAct() then
		return
	end
	lockUntil = os.clock() + 0.4
	send({ Kind = "Parry" })
end

function CombatController.SetSprint(on: boolean)
	send({ Kind = "Sprint", On = on })
end

function CombatController.Ability(slot: string)
	if not canAct() then
		return
	end
	send({ Kind = "Ability", Slot = slot, Aim = CameraController.AimDirection(), TargetId = CameraController.TargetEntityId() })
end

function CombatController.Flask()
	if not canAct() then
		return
	end
	lockUntil = os.clock() + GameConfig.Flask.UseTime
	send({ Kind = "Flask" })
	AudioController.Play("Drink")
end

function CombatController.UseItem(itemId: string)
	if not canAct() then
		return
	end
	send({ Kind = "Item", ItemId = itemId })
end

function CombatController.Rep()
	send({ Kind = "Rep" })
end

-- Server says we were staggered: drop local locks/charge
function CombatController.OnStaggered(duration: number)
	heavyStart = nil
	lockUntil = os.clock() + duration
end

return CombatController
