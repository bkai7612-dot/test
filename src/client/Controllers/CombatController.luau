--[[
	CombatController
	Turns input into server intents and gives immediate local feedback:
	  * light/heavy attacks (heavy charge timed locally, clamped on the server)
	  * dodge: local dash movement for responsiveness; i-frames are granted by the server
	  * double jump and aerial front/back flips (double jump + dodge, or dodge + jump);
	    flips are dodges, so the server grants their i-frames
	  * catalysts (staff/seal) cast spells while mana lasts, then switch to mana-free strikes
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
local Movement = require(Shared.Logic.Movement)
local Catalyst = require(Shared.Logic.Catalyst)
local UserInputService = game:GetService("UserInputService")

local CombatController = {}

local player = Players.LocalPlayer
local actionRemote: RemoteEvent
local CameraController, ClientState, AudioController, AnimationController
local Abilities = require(Shared.Config.Abilities)
local combo = 0
local lastLightEnd = 0
local lockUntil = 0
local heavyStart: number? = nil
local lastDodge = 0
local blocking = false
local comboMode: string? = nil -- mirrors the server's state.ComboMode
local move = Movement.new()

function CombatController.Init(deps)
	CameraController = deps.CameraController
	ClientState = deps.ClientState
	AudioController = deps.AudioController
	AnimationController = deps.AnimationController
	actionRemote = Net.event("Action")
	CombatController.StartMovement()
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

-- Same rule as the server (shared Catalyst module): which move fires for this press?
local function pickMove(kind: string, chained: boolean)
	local wt, wtName = weaponType()
	local choice = Catalyst.choose(wt, kind, combo, chained, comboMode, player:GetAttribute("Mana") or 0)
	comboMode = choice.Mode
	combo = choice.Combo
	return choice.Move, choice.AnimType or wtName
end

function CombatController.Light()
	if not canAct() then
		return
	end
	local m, animType = pickMove("Light", os.clock() - lastLightEnd <= 0.7 and combo > 0)
	lockUntil = os.clock() + m.Windup + m.Recovery * 0.8
	lastLightEnd = lockUntil
	AnimationController.PlayLocal({ Anim = "Light", Combo = combo, WeaponType = animType, Windup = m.Windup, Recovery = m.Recovery })
	send({ Kind = "Light", Aim = CameraController.AimDirection() })
	AudioController.Play("Swing")
end

function CombatController.HeavyBegin()
	if not canAct() then
		return
	end
	heavyStart = os.clock()
	send({ Kind = "HeavyStart" })
end

function CombatController.HeavyEnd()
	if not heavyStart then
		return
	end
	heavyStart = nil
	if not canAct() then
		return
	end
	local m, animType = pickMove("Heavy", false)
	lockUntil = os.clock() + m.Windup + m.Recovery * 0.8
	AnimationController.PlayLocal({ Anim = "Heavy", WeaponType = animType, Windup = m.Windup, Recovery = m.Recovery })
	-- the server measures the charge itself between HeavyStart and Heavy
	send({ Kind = "Heavy", Aim = CameraController.AimDirection() })
	AudioController.Play("HeavySwing")
end

function CombatController.IsCharging(): boolean
	return heavyStart ~= nil
end

function CombatController.Dodge()
	-- double jump, then dodge: flip instead of an air dash
	if Movement.dodgePressed(move, os.clock()) == "Flip" then
		CombatController.Flip()
		return
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not root or hum.Health <= 0 then
		return
	end
	if os.clock() - lastDodge < GameConfig.Combat.DodgeCooldown or (player:GetAttribute("Stamina") or 0) <= 0 then
		move.LastDodge = -math.huge -- a refused dodge cannot be chained into a flip
		return
	end
	lastDodge = os.clock()
	lockUntil = os.clock() + 0.35
	combo = 0
	send({ Kind = "Dodge" })
	AnimationController.PlayLocal({ Anim = "Dodge" })
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
	local _, wtName = weaponType()
	AnimationController.PlayLocal({ Anim = "Parry", WeaponType = wtName })
end

function CombatController.SetSprint(on: boolean)
	send({ Kind = "Sprint", On = on })
end

function CombatController.Ability(slot: string)
	if not canAct() then
		return
	end
	send({ Kind = "Ability", Slot = slot, Aim = CameraController.AimDirection(), TargetId = CameraController.TargetEntityId() })
	local p = ClientState.Profile
	local def = p and Abilities[p.Abilities[slot]]
	if def and def.Type ~= "ShadowStep" then
		AnimationController.PlayLocal({ Anim = "Cast", Windup = def.Windup or 0.2 })
	end
end

function CombatController.Flask()
	if not canAct() then
		return
	end
	lockUntil = os.clock() + GameConfig.Flask.UseTime
	send({ Kind = "Flask" })
	if (player:GetAttribute("FlaskCharges") or 0) > 0 then
		AnimationController.PlayLocal({ Anim = "Flask" })
	end
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

-- ===================================================================== air movement
local function characterParts(): (Humanoid?, BasePart?)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not root or hum.Health <= 0 then
		return nil, nil
	end
	return hum, root
end

local function airPuff(root: BasePart, color: Color3)
	local att = Instance.new("Attachment")
	att.Position = Vector3.new(0, -2.5, 0)
	att.Parent = root
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.Lifetime = NumberRange.new(0.35, 0.5)
	e.Speed = NumberRange.new(6, 10)
	e.SpreadAngle = Vector2.new(180, 20)
	e.Size = NumberSequence.new(1.1, 0)
	e.Transparency = NumberSequence.new(0.35, 1)
	e.Color = ColorSequence.new(color)
	e.LightEmission = 0.4
	e.Parent = att
	e:Emit(18)
	Debris:AddItem(att, 0.8)
end

-- Front or back flip: an aerial dodge. Local physics for responsiveness, i-frames from the server.
function CombatController.Flip()
	local hum, root = characterParts()
	if not hum or not root or (player:GetAttribute("Stamina") or 0) <= 0 then
		return
	end
	local md = hum.MoveDirection
	local look = root.CFrame.LookVector
	local dir = Movement.flipDirection(md.X, md.Z, look.X, look.Z)
	lastDodge = os.clock()
	lockUntil = os.clock() + GameConfig.Combat.FlipLock
	combo = 0
	send({ Kind = "Flip", Dir = dir })
	AnimationController.PlayLocal({ Anim = "Flip", Dir = dir })
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
	if dir == "Back" then
		flat = -flat
	end
	local duration = 0.5
	local v = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(v.X, GameConfig.Combat.FlipHeight, v.Z)
	local att = Instance.new("Attachment")
	att.Parent = root
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att
	lv.MaxForce = 1e6
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	lv.PrimaryTangentAxis = Vector3.new(1, 0, 0)
	lv.SecondaryTangentAxis = Vector3.new(0, 0, 1)
	lv.PlaneVelocity = Vector2.new(flat.X, flat.Z) * (GameConfig.Combat.FlipDistance / duration)
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.Parent = root
	Debris:AddItem(att, duration + 0.1)
	Debris:AddItem(lv, duration)
	player:SetAttribute("Dodging", true)
	AudioController.Play("Dodge")
	airPuff(root, Color3.fromRGB(220, 215, 235))
	task.delay(duration, function()
		player:SetAttribute("Dodging", false)
	end)
end

local function doubleJump()
	local hum, root = characterParts()
	if not hum or not root then
		return
	end
	local v = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(v.X, GameConfig.Combat.DoubleJumpPower, v.Z)
	AnimationController.PlayLocal({ Anim = "DoubleJump" })
	airPuff(root, Color3.fromRGB(235, 230, 220))
	AudioController.Play("Dodge")
end

local function watchCharacter(char: Model)
	move = Movement.new()
	local hum = char:WaitForChild("Humanoid", 10)
	if not hum or not hum:IsA("Humanoid") then
		return
	end
	hum.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Jumping or new == Enum.HumanoidStateType.Freefall then
			Movement.tookOff(move, os.clock())
		elseif new == Enum.HumanoidStateType.Landed or new == Enum.HumanoidStateType.Running
			or new == Enum.HumanoidStateType.Swimming or new == Enum.HumanoidStateType.Climbing then
			Movement.landed(move)
		end
	end)
end

function CombatController.OnJumpRequest()
	local p = ClientState.Profile
	if not p or p.Class == "" or player:GetAttribute("Health") == 0 then
		return
	end
	local result = Movement.jumpRequest(move, os.clock())
	if result == "Flip" then
		CombatController.Flip()
	elseif result == "DoubleJump" then
		doubleJump()
	end
end

function CombatController.StartMovement()
	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end
	player.CharacterAdded:Connect(watchCharacter)
	UserInputService.JumpRequest:Connect(CombatController.OnJumpRequest)
end

-- Server says we were staggered: drop local locks/charge
function CombatController.OnStaggered(duration: number)
	heavyStart = nil
	combo = 0
	AnimationController.PlayLocal({ Anim = "Hurt" })
	lockUntil = os.clock() + duration
end

return CombatController
