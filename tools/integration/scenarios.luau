-- ===================================================================== scenarios
local game = GAME
local RS = game:GetService("ReplicatedStorage")
local Shared = RS:WaitForChild("Shared")
-- fake remotes
local SENT, FX = {}, {}
local remotes = {}
local FakeNet = { event = function(name)
	if not remotes[name] then
		remotes[name] = {
			OnServerEvent = Signal.new(), OnClientEvent = Signal.new(),
			FireServer = function(_, payload) table.insert(SENT, { Name = name, Payload = payload }) end,
			FireClient = function(_, plr, payload) table.insert(FX, payload) end,
			FireAllClients = function(_, payload) table.insert(FX, payload) end,
		}
	end
	return remotes[name]
end, func = function() return {} end }
inject(Shared.Net, FakeNet)

local GameConfig = __require(Shared.Config.GameConfig)
local C = GameConfig.Combat
local failures, passes = 0, 0
local function check(cond, msg)
	if cond then passes += 1 else failures += 1; print("FAIL: " .. msg) end
end

-- ------------------------------------------------------------------ client
local client = game.StarterPlayer.StarterPlayerScripts.Client.Controllers
local CombatController = __require(client.CombatController)
local AnimationController = __require(client.AnimationController)
local played = {}
local profile = { Class = "Mage", Derived = { WeaponType = "Staff", LoadTier = "Medium" }, Abilities = {} }
CombatController.Init({
	CameraController = { AimDirection = function() return Vector3.new(0, 0, -1) end, TargetEntityId = function() return nil end },
	ClientState = { Profile = profile },
	AudioController = { Play = function() end },
	AnimationController = { PlayLocal = function(p) table.insert(played, p) end },
})
LOCAL:SetAttribute("Stamina", 100)
LOCAL:SetAttribute("Health", 100)
local function lastSent() return SENT[#SENT] and SENT[#SENT].Payload end
local function lastPlayed() return played[#played] end
local function state(s) HUM.StateChanged:Fire(nil, "HumanoidStateType." .. s) end

-- spells with mana, strikes without
LOCAL:SetAttribute("Mana", 200)
T = 10
CombatController.Light()
check(lastSent().Kind == "Light", "light attack sent")
check(lastPlayed().WeaponType == "Staff", "with mana the staff plays its casting animation")
advance(1.5)
LOCAL:SetAttribute("Mana", 0)
CombatController.Light()
check(lastPlayed().WeaponType == "Spear", "with no mana the staff plays the quarterstaff (spear) animation, got " .. tostring(lastPlayed().WeaponType))
check(lastPlayed().Combo == 1, "switching to strikes restarts the local combo")
advance(0.6)
CombatController.Light()
check(lastPlayed().Combo == 2, "strike combo advances")
advance(1.5)
CombatController.HeavyBegin(); advance(0.2); CombatController.HeavyEnd()
check(lastPlayed().Anim == "Heavy" and lastPlayed().WeaponType == "Spear", "heavy without mana = spinning sweep animation")
advance(2)

-- double jump
local nSent = #SENT
T = 20
UIS.JumpRequest:Fire() -- ground jump (normal)
state("Jumping")
check(ROOT.AssemblyLinearVelocity.Y == 0, "ground jump is left to Roblox")
advance(0.3)
UIS.JumpRequest:Fire()
check(ROOT.AssemblyLinearVelocity.Y == C.DoubleJumpPower, "double jump sets upward speed " .. tostring(ROOT.AssemblyLinearVelocity.Y))
check(lastPlayed().Anim == "DoubleJump", "double jump animation plays")
advance(0.3)
UIS.JumpRequest:Fire()
check(ROOT.AssemblyLinearVelocity.Y == C.DoubleJumpPower and lastPlayed().Anim == "DoubleJump", "no triple jump")
check(#SENT == nSent, "jumping sends nothing to the server")

-- double jump + dodge = flip (holding back = backflip)
HUM.MoveDirection = Vector3.new(0, 0, 1) -- moving backwards (facing -Z)
ROOT.AssemblyLinearVelocity = Vector3.new(0, -5, 0)
CombatController.Dodge()
check(lastSent().Kind == "Flip" and lastSent().Dir == "Back", "double jump + dodge sends a backflip")
check(lastPlayed().Anim == "Flip" and lastPlayed().Dir == "Back", "backflip animation plays")
check(ROOT.AssemblyLinearVelocity.Y == C.FlipHeight, "flip lifts the player")
local lv = ROOT:FindFirstChild("Attachment") and nil
local found = nil
for _, d in ROOT:GetDescendants() do if d.ClassName == "LinearVelocity" then found = d end end
check(found ~= nil and found.PlaneVelocity.Y > 0, "backflip pushes backwards (+Z)")
check(LOCAL:GetAttribute("Dodging") == true, "flip marks the player as dodging")
advance(0.6)
CombatController.Dodge()
check(lastSent().Kind == "Dodge", "only one flip per airtime; next dodge is an air dash")
state("Landed")
advance(1)

-- dodge then jump = front flip
HUM.MoveDirection = Vector3.new(0, 0, -1) -- moving forward
for _, d in ROOT:GetChildren() do d:Destroy() end
CombatController.Dodge()
check(lastSent().Kind == "Dodge", "ground dodge")
advance(0.2)
UIS.JumpRequest:Fire()
check(lastSent().Kind == "Flip" and lastSent().Dir == "Front", "dodge + jump sends a front flip")
local fwd = nil
for _, d in ROOT:GetDescendants() do if d.ClassName == "LinearVelocity" then fwd = d end end
check(fwd ~= nil and fwd.PlaneVelocity.Y < 0, "front flip pushes forwards (-Z)")
state("Freefall"); advance(1); state("Landed"); advance(1)

-- held jump never double jumps
local before = #played
UIS.JumpRequest:Fire(); state("Jumping")
for _ = 1, 20 do advance(0.05); UIS.JumpRequest:Fire() end
local dj = false
for i = before + 1, #played do if played[i].Anim == "DoubleJump" then dj = true end end
check(not dj, "holding jump does not double jump")
state("Landed")

-- animation keyframes: front flip rotates forward (-x), backflip backward (+x), full turn
local front = AnimationController.Build({ Anim = "Flip", Dir = "Front" })
local back = AnimationController.Build({ Anim = "Flip", Dir = "Back" })
local function rootAt(frames, i) return frames[i].Pose.Root and frames[i].Pose.Root[1] or 0 end
check(rootAt(front, #front - 1) == -360 and rootAt(back, #back - 1) == 360, "flip keyframes spin a full turn in the right direction")
check(front[#front].T > 0.4 and front[#front].T < 1, "flip lasts about half a second")
check(AnimationController.Build({ Anim = "DoubleJump" }) ~= nil, "double jump animation exists")

-- ------------------------------------------------------------------ server
local SSS = game:GetService("ServerScriptService")
local CombatService = __require(SSS.Server.Services.CombatService)
local CombatCore = __require(SSS.Server.Core.CombatCore)
local Helpers = __require(game:GetService("ServerStorage").Tests.Helpers)
local Stats = __require(Shared.Logic.Stats)
local fired, hits = {}, {}
local enemy = { Id = 1, Radius = 2, Kind = "Enemy" }
local nearList = {}
local rt = {
	Player = LOCAL, Root = ROOT, Profile = Helpers.profile("Mage"),
	Stats = { WeaponType = "Staff", AttackRating = 100, WeaponDamageType = "Magic", DodgeCostMult = 1 },
}
rt.Profile.Class = "Mage"
rt.Combat = CombatCore.newPlayerState(Stats.compute(rt.Profile), -100)
rt.Combat.MaxMana, rt.Combat.Mana, rt.Combat.MaxStamina, rt.Combat.Stamina = 200, 200, 1000, 1000
ROOT.CFrame = CFrame.new(0, 3, 0)
ROOT.Position = Vector3.new(0, 3, 0)
CombatService.Init({
	PlayerStateService = { Get = function() return rt end },
	ProjectileService = { Fire = function(spec) table.insert(fired, spec) end },
	EntityService = { Near = function() return nearList end, Position = function() return Vector3.new(0, 3, -4) end },
})
CombatService.HitEntity = function(_, _, e, power, motion, poise, dtype) table.insert(hits, { E = e, Motion = motion, Type = dtype }) end
CombatService.Start()
local action = remotes.Action.OnServerEvent
local function act(payload) action:Fire(LOCAL, payload) end

T = 100
act({ Kind = "Light" }); advance(0.4)
check(#fired == 1, "arcane bolt fires one projectile, got " .. #fired)
advance(0.5); act({ Kind = "Light" }); advance(0.4)
check(#fired == 3, "twin bolts fire two more projectiles, total " .. #fired)
local a, b = fired[2].Direction, fired[3].Direction
local ang = math.deg(math.acos(math.clamp(a:Dot(b), -1, 1)))
check(math.abs(ang - 12) < 0.01, "twin bolts are spread 12 degrees apart, got " .. ang)
advance(0.5); act({ Kind = "Light" }); advance(0.4)
check(#fired == 4 and fired[4].Pierce == true, "arcane burst pierces")
check(fired[4].Radius > fired[1].Radius * 1.5, "arcane burst is bigger")
check(math.abs(rt.Combat.Mana - (200 - 26)) < 1e-6, "mana spent 6+8+12")
local tech = {}
for _, p in FX do if p.Type == "Technique" then table.insert(tech, p.Name) end end
check(tech[1] == "Arcane Bolt" and tech[2] == "Twin Bolts" and tech[3] == "Arcane Burst", "HUD told the technique names")

-- out of mana: strikes + mana siphon
advance(2)
rt.Combat.Mana = 0
nearList = { enemy }
act({ Kind = "Light" }); advance(0.3)
check(#fired == 4, "no projectile without mana")
check(#hits == 1 and hits[1].Type == "Physical", "staff strike hits the enemy in front (physical)")
check(math.abs(rt.Combat.Mana - 3) < 1e-6, "hit siphons 3 mana, mana = " .. rt.Combat.Mana)
local lastTech = nil
for _, p in FX do if p.Type == "Technique" then lastTech = p end end
check(lastTech.Name == "Staff Jab" and lastTech.Mode == "Melee", "HUD told: Staff Jab (melee)")
nearList = {}

-- flips on the server
advance(2)
local fxBefore = #FX
act({ Kind = "Flip", Dir = "Back" })
local ok = false
for i = fxBefore + 1, #FX do if FX[i].Type == "DodgeOk" and FX[i].Flip == "Back" then ok = true end end
check(ok, "server accepts the flip and grants i-frames")
check(CombatCore.dodgeCovers(rt.Combat, T + 0.1), "flip i-frames cover a hit 0.1s later")
advance(0.1)
act({ Kind = "Flip", Dir = "Front" })
local denied = false
for i = fxBefore + 1, #FX do if FX[i].Type == "ActionDenied" and FX[i].Action == "Flip" then denied = true end end
check(denied, "flip spam is refused (cooldown)")

print(("integration: %d passed, %d failed"):format(passes, failures))
if failures > 0 then error("INTEGRATION FAILED") end
