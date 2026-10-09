--[[
	AnimationController
	Procedural combat animations for player characters, built from keyframed joint poses
	(no uploaded animation assets needed). It drives the shoulder, waist and root Motor6D C0s
	on top of Roblox's default walk/idle animations, works for R15 and R6, and runs on every
	client: your own swings play instantly; other players' swings arrive as "Anim" Fx events.

	Animations: Light (3-hit combo per weapon family), Heavy, Parry, Dodge (roll), Flask,
	Cast (abilities), Hurt (flinch), plus a held Block guard while the Blocking attribute is set.

	Pose values are degrees (x, y, z) applied in the parent part's space at the joint pivot:
	  shoulder  x>0 raises the arm forward (90 = straight ahead, 180 = overhead)
	            z>0 swings the RIGHT arm outward (left arm: inward)
	  waist     x<0 leans forward, y twists the torso
	  root      x rotates the whole body (used for the roll)
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local AnimationController = {}

local JOINT_NAMES = {
	R = { "RightShoulder", "Right Shoulder" },
	L = { "LeftShoulder", "Left Shoulder" },
	W = { "Waist" },
	Root = { "Root", "RootJoint" },
}

type Pose = { [string]: { number } } -- joint -> { rx, ry, rz, px, py, pz }
type Frame = { T: number, Pose: Pose }

local rigs = {} -- [Model] = { Motors = { [joint] = Motor6D }, Base = { [joint] = CFrame } }
local playing = {} -- [Model] = { Frames, Start, Duration }
local holding = {} -- [Model] = Pose (block guard)

-- ===================================================================== rig access
local function rigFor(character: Model)
	local rig = rigs[character]
	if rig then
		return rig
	end
	rig = { Motors = {}, Base = {} }
	for joint, names in JOINT_NAMES do
		for _, name in names do
			local m = character:FindFirstChild(name, true)
			if m and m:IsA("Motor6D") then
				rig.Motors[joint] = m
				rig.Base[joint] = m.C0
				break
			end
		end
	end
	rigs[character] = rig
	character.AncestryChanged:Connect(function()
		if not character.Parent then
			rigs[character] = nil
			playing[character] = nil
			holding[character] = nil
		end
	end)
	return rig
end

local function applyPose(character: Model, pose: Pose?)
	local rig = rigFor(character)
	for joint, motor in rig.Motors do
		local base = rig.Base[joint]
		local v = pose and pose[joint]
		if v and motor.Parent then
			local rot = CFrame.Angles(math.rad(v[1]), math.rad(v[2]), math.rad(v[3]))
			local offset = Vector3.new(v[4] or 0, v[5] or 0, v[6] or 0)
			-- rotate about the joint pivot in the parent's space, keep the joint's own orientation
			motor.C0 = CFrame.new(base.Position + offset) * rot * base.Rotation
		elseif motor.Parent then
			motor.C0 = base
		end
	end
end

local function lerpPose(a: Pose, b: Pose, t: number): Pose
	local out = {}
	for _, joint in { "R", "L", "W", "Root" } do
		local va, vb = a[joint], b[joint]
		if va or vb then
			va = va or { 0, 0, 0, 0, 0, 0 }
			vb = vb or { 0, 0, 0, 0, 0, 0 }
			local v = {}
			for i = 1, 6 do
				local x, y = va[i] or 0, vb[i] or 0
				v[i] = x + (y - x) * t
			end
			out[joint] = v
		end
	end
	return out
end

local function ease(t: number): number
	return if t < 0.5 then 2 * t * t else 1 - (-2 * t + 2) ^ 2 / 2
end

-- ===================================================================== animation library
local NEUTRAL: Pose = {}

-- Weapon families decide the light-combo shapes.
local FAMILY = {
	Sword = "Slash", Greatsword = "Slash", Axe = "Slash", Fist = "Punch",
	Hammer = "Smash", Dagger = "Dagger", Spear = "Thrust",
	Bow = "Bow", Staff = "Staff", Seal = "Seal",
}

-- { windupPose, strikePose } for each family and combo step
local LIGHT = {
	Slash = {
		{ { R = { 150, 0, 35 }, W = { 0, 25, 0 } }, { R = { 40, 0, -35 }, W = { -10, -25, 0 } } }, -- diagonal cut
		{ { R = { 85, 0, 75 }, W = { 0, 35, 0 } }, { R = { 85, 0, -55 }, W = { 0, -35, 0 } } }, -- horizontal sweep
		{ { R = { 175, 0, 10 }, W = { 12, 0, 0 } }, { R = { 35, 0, 0 }, W = { -20, 0, 0 } } }, -- overhead finisher
	},
	Smash = {
		{ { R = { 170, 0, 15 }, L = { 150, 0, 15 }, W = { 15, 0, 0 } }, { R = { 30, 0, 0 }, L = { 30, 0, 0 }, W = { -25, 0, 0 } } },
		{ { R = { 90, 0, 80 }, W = { 0, 45, 0 } }, { R = { 80, 0, -60 }, W = { -5, -40, 0 } } },
	},
	Dagger = {
		{ { R = { 70, 0, 20, 0, 0, 0.5 } }, { R = { 95, 0, 0, 0, 0, -0.6 }, W = { -8, -10, 0 } } },
		{ { R = { 110, 0, 50 } }, { R = { 70, 0, -40 }, W = { 0, -20, 0 } } },
		{ { R = { 70, 0, 20, 0, 0, 0.5 } }, { R = { 95, 0, 0, 0, 0, -0.6 }, W = { -8, 10, 0 } } },
		{ { R = { 160, 0, 20 }, W = { 10, 0, 0 } }, { R = { 50, 0, -10 }, W = { -18, 0, 0 } } },
	},
	Thrust = {
		{ { R = { 75, 0, 15, 0, 0, 0.7 }, W = { 0, 15, 0 } }, { R = { 92, 0, 0, 0, 0, -0.9 }, W = { -10, -10, 0 } } },
	},
	Punch = {
		{ { R = { 70, 0, 10, 0, 0, 0.5 } }, { R = { 92, 0, 0, 0, 0, -0.8 }, W = { 0, -15, 0 } } },
		{ { L = { 70, 0, -10, 0, 0, 0.5 } }, { L = { 92, 0, 0, 0, 0, -0.8 }, W = { 0, 15, 0 } } },
	},
	Bow = { { { R = { 92, 0, 0 }, L = { 85, 0, 40, 0, 0, 0.4 }, W = { 0, 20, 0 } }, { R = { 92, 0, 0 }, L = { 80, 0, 50, 0, 0, 0.8 }, W = { 0, 20, 0 } } } },
	Staff = { { { R = { 130, 0, 10 } }, { R = { 95, 0, 0, 0, 0, -0.5 }, W = { -8, 0, 0 } } } },
	Seal = { { { R = { 160, 0, 20 }, W = { 8, 0, 0 } }, { R = { 100, 0, 0, 0, 0, -0.4 }, W = { -8, 0, 0 } } } },
}

local HEAVY = {
	Slash = { { R = { 185, 0, 25 }, W = { 18, 30, 0 } }, { R = { 25, 0, -20 }, W = { -28, -15, 0 } } },
	Smash = { { R = { 185, 0, 10 }, L = { 175, 0, 10 }, W = { 22, 0, 0 } }, { R = { 20, 0, 0 }, L = { 20, 0, 0 }, W = { -35, 0, 0 } } },
	Dagger = { { R = { 60, 0, 25, 0, 0, 0.9 }, W = { 0, 30, 0 } }, { R = { 95, 0, 0, 0, 0, -1 }, W = { -15, -20, 0 } } },
	Thrust = { { R = { 70, 0, 25, 0, 0, 1 }, W = { 5, 35, 0 } }, { R = { 95, 0, 0, 0, 0, -1.2 }, W = { -18, -20, 0 } } },
	Punch = { { R = { 60, 0, 30, 0, 0, 0.8 }, W = { 0, 35, 0 } }, { R = { 95, 0, 0, 0, 0, -1 }, W = { -15, -25, 0 } } },
	Bow = { { R = { 92, 0, 0 }, L = { 85, 0, 35, 0, 0, 0.3 }, W = { 0, 25, 0 } }, { R = { 92, 0, 0 }, L = { 80, 0, 55, 0, 0, 1 }, W = { 0, 25, 0 } } },
	Staff = { { R = { 175, 0, 0 }, L = { 165, 0, 0 }, W = { 12, 0, 0 } }, { R = { 100, 0, 0, 0, 0, -0.6 }, L = { 100, 0, 0, 0, 0, -0.6 }, W = { -15, 0, 0 } } },
	Seal = { { R = { 175, 0, 0 }, L = { 165, 0, 0 }, W = { 12, 0, 0 } }, { R = { 100, 0, 0 }, L = { 100, 0, 0 }, W = { -15, 0, 0 } } },
}

local BLOCK: Pose = { R = { 70, 0, -30 }, L = { 65, 0, 40 }, W = { -5, 0, 0 } }

local function attackFrames(pair, windup: number, recovery: number): { Frame }
	local w = math.max(0.06, windup)
	return {
		{ T = 0, Pose = NEUTRAL },
		{ T = w * 0.8, Pose = pair[1] },
		{ T = w + 0.06, Pose = pair[2] },
		{ T = w + recovery * 0.45, Pose = pair[2] },
		{ T = w + recovery * 0.95, Pose = NEUTRAL },
	}
end

-- Builds keyframes for an animation request.
function AnimationController.Build(payload): { Frame }?
	local anim = payload.Anim
	local family = FAMILY[payload.WeaponType or "Fist"] or "Slash"
	if anim == "Light" then
		local set = LIGHT[family] or LIGHT.Slash
		local pair = set[((payload.Combo or 1) - 1) % #set + 1]
		return attackFrames(pair, payload.Windup or 0.2, payload.Recovery or 0.35)
	elseif anim == "Heavy" then
		return attackFrames(HEAVY[family] or HEAVY.Slash, payload.Windup or 0.45, payload.Recovery or 0.55)
	elseif anim == "Parry" then
		local p = { R = { 105, 0, -55 }, L = { 60, 0, 30 }, W = { 0, -20, 0 } }
		return { { T = 0, Pose = NEUTRAL }, { T = 0.07, Pose = p }, { T = 0.25, Pose = p }, { T = 0.45, Pose = NEUTRAL } }
	elseif anim == "Dodge" then
		local d = 0.34
		local frames = { { T = 0, Pose = NEUTRAL } }
		for i = 1, 6 do
			local a = i / 6
			table.insert(frames, { T = d * a, Pose = { Root = { -360 * a, 0, 0 }, R = { 60, 0, -20 }, L = { 60, 0, 20 } } })
		end
		table.insert(frames, { T = d + 0.08, Pose = NEUTRAL })
		return frames
	elseif anim == "Flask" then
		local p = { R = { 150, 0, -45 }, W = { 10, 0, 0 } }
		return { { T = 0, Pose = NEUTRAL }, { T = 0.25, Pose = p }, { T = 0.75, Pose = p }, { T = 1.0, Pose = NEUTRAL } }
	elseif anim == "Cast" then
		local w = math.max(0.15, payload.Windup or 0.3)
		local up = { R = { 165, 0, 15 }, L = { 165, 0, -15 }, W = { 12, 0, 0 } }
		local out = { R = { 95, 0, 0, 0, 0, -0.5 }, L = { 95, 0, 0, 0, 0, -0.5 }, W = { -12, 0, 0 } }
		return { { T = 0, Pose = NEUTRAL }, { T = w * 0.85, Pose = up }, { T = w + 0.08, Pose = out }, { T = w + 0.35, Pose = out }, { T = w + 0.6, Pose = NEUTRAL } }
	elseif anim == "Hurt" then
		local p = { W = { 22, 0, 0 }, R = { 30, 0, 20 }, L = { 30, 0, -20 } }
		return { { T = 0, Pose = NEUTRAL }, { T = 0.08, Pose = p }, { T = 0.3, Pose = NEUTRAL } }
	end
	return nil
end

function AnimationController.Play(character: Model?, payload)
	if not character or not character.Parent then
		return
	end
	local frames = AnimationController.Build(payload)
	if not frames then
		return
	end
	playing[character] = { Frames = frames, Start = os.clock(), Duration = frames[#frames].T }
end

function AnimationController.PlayFor(userId: number, payload)
	local plr = Players:GetPlayerByUserId(userId)
	if plr and plr.Character then
		AnimationController.Play(plr.Character, payload)
	end
end

function AnimationController.PlayLocal(payload)
	AnimationController.Play(Players.LocalPlayer.Character, payload)
end

-- ===================================================================== update loop
local function sample(state, t: number): Pose
	local frames = state.Frames
	for i = 2, #frames do
		local a, b = frames[i - 1], frames[i]
		if t <= b.T then
			local span = b.T - a.T
			local alpha = if span > 0 then ease((t - a.T) / span) else 1
			return lerpPose(a.Pose, b.Pose, alpha)
		end
	end
	return frames[#frames].Pose
end

function AnimationController.Init()
	RunService.RenderStepped:Connect(function()
		-- held guard pose for blocking players
		for _, plr in Players:GetPlayers() do
			local char = plr.Character
			if char then
				if plr:GetAttribute("Blocking") then
					holding[char] = BLOCK
				elseif holding[char] then
					holding[char] = nil
					if not playing[char] then
						applyPose(char, nil)
					end
				end
			end
		end
		local now = os.clock()
		for char, state in playing do
			local t = now - state.Start
			if t >= state.Duration or not char.Parent then
				playing[char] = nil
				if char.Parent then
					applyPose(char, holding[char])
				end
			else
				applyPose(char, sample(state, t))
			end
		end
		for char, pose in holding do
			if not playing[char] and char.Parent then
				applyPose(char, pose)
			end
		end
	end)
	Players.LocalPlayer.CharacterAdded:Connect(function(char)
		rigs[char] = nil
		playing[char] = nil
	end)
end

return AnimationController
