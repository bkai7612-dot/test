--[[
	DeathService
	Handles every player death: currency drop via DeathCore, recovery markers, encounter
	removal, statistics, saving and respawning at the last rested shrine.

	Marker placement rules:
	  * normal death: where the player died
	  * fell out of the world: last position the player stood on solid ground
	  * death inside a tower arena: in front of the Tower Gate (arenas are temporary instances)
	  * PvP arena deaths cost nothing (DeathCore NoLoss)
	Recovery is automatic when the OWNER walks within RecoveryRadius. The marker is visible
	only to its owner (clients hide other players' markers) and shows no personal data.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local World = require(Shared.Config.World)
local Net = require(Shared.Net)
local DeathCore = require(script.Parent.Parent.Core.DeathCore)
local AchievementCore = require(script.Parent.Parent.Core.AchievementCore)

local DeathService = {}
local S
local folder: Folder
local markers: { [number]: BasePart } = {}

function DeathService.Init(services)
	S = services
	folder = Instance.new("Folder")
	folder.Name = "LostEmbers"
	folder.Parent = workspace
end

local function removeMarker(userId: number)
	local m = markers[userId]
	if m then
		m:Destroy()
		markers[userId] = nil
	end
end

function DeathService.RefreshMarker(player: Player)
	local rt = S.PlayerStateService.Get(player)
	removeMarker(player.UserId)
	if not rt then
		return
	end
	local lost = rt.Profile.LostCurrency
	if not lost then
		return
	end
	local p = Instance.new("Part")
	p.Name = "LostEmbers"
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(2, 2, 2)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.Neon
	p.Color = Color3.fromRGB(255, 120, 40)
	p.CFrame = CFrame.new(lost.X, lost.Y + 2, lost.Z)
	p:SetAttribute("OwnerUserId", player.UserId)
	p:SetAttribute("Amount", lost.Amount)
	p:SetAttribute("ExpiresAt", lost.CreatedAt + GameConfig.Death.RecoveryExpirySeconds)
	local light = Instance.new("PointLight")
	light.Color = p.Color
	light.Range = 14
	light.Brightness = 2
	light.Parent = p
	local fire = Instance.new("ParticleEmitter")
	fire.Color = ColorSequence.new(Color3.fromRGB(255, 160, 60), Color3.fromRGB(255, 60, 20))
	fire.Rate = 20
	fire.Lifetime = NumberRange.new(0.8, 1.4)
	fire.Speed = NumberRange.new(2, 4)
	fire.Size = NumberSequence.new(0.6, 0)
	fire.LightEmission = 1
	fire.Parent = p
	-- a tall beam so the marker can be found from a distance
	local beam = Instance.new("Part")
	beam.Name = "Beacon"
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.Material = Enum.Material.Neon
	beam.Color = p.Color
	beam.Transparency = 0.6
	beam.Size = Vector3.new(0.4, 60, 0.4)
	beam.CFrame = p.CFrame * CFrame.new(0, 30, 0)
	beam.Parent = p
	p.Parent = folder
	markers[player.UserId] = p
end

local function spawnPoint(): Vector3
	local sp = World.SpawnPoint
	return Vector3.new(sp[1], sp[2], sp[3])
end

function DeathService.OnPlayerDeath(player: Player, cause: string)
	local rt = S.PlayerStateService.Get(player)
	if not rt or rt.DeathHandled then
		return
	end
	rt.DeathHandled = true
	local c = rt.Combat
	if c then
		c.Dead = true
		c.Health = 0
	end
	if rt.Humanoid and rt.Humanoid.Health > 0 then
		rt.Humanoid.Health = 0
	end
	local profile = rt.Profile
	AchievementCore.increment(profile, "Deaths")

	-- where should the recovery marker go?
	local pos
	if rt.Encounter then
		local g = World.Tower.GatePosition
		pos = Vector3.new(g[1] + math.random(-6, 6), g[2], g[3] + 14)
	elseif rt.Root and rt.Root.Position.Y > -40 then
		pos = rt.Root.Position - Vector3.new(0, 2.5, 0)
	else
		pos = rt.LastGroundPos or spawnPoint()
	end
	local noLoss = rt.Region == "pvp" or cause == "PvP" or (rt.Training ~= nil and rt.Training.Def.Kind == "Spar")
	local r = DeathCore.onDeath(profile, pos.X, pos.Y, pos.Z, os.time(), { NoLoss = noLoss })

	if rt.Encounter then
		S.BossService.OnParticipantDied(player)
	end
	if S.TrainingService then
		S.TrainingService.OnPlayerDied(player)
	end

	local sub
	if noLoss then
		sub = "No embers were lost."
	elseif r.Dropped > 0 then
		sub = ("%d %s lie where you fell."):format(r.Dropped, GameConfig.Currency.Name)
	else
		sub = "You carried no embers."
	end
	if r.LostForever > 0 then
		sub ..= (" Your previous %d %s are gone."):format(r.LostForever, GameConfig.Currency.Name)
	end
	Net.event("Notify"):FireClient(player, { Banner = true, Death = true, Text = "YOU DIED", Subtitle = sub, Kind = "Death" })
	DeathService.RefreshMarker(player)
	S.PlayerStateService.Sync(player)
	task.spawn(S.DataService.Save, player)

	task.delay(Players.RespawnTime, function()
		if player.Parent and S.PlayerStateService.Get(player) == rt then
			player:LoadCharacter()
		end
	end)
end

function DeathService.Start()
	S.PlayerStateService.CharacterReady:Connect(function(player)
		DeathService.RefreshMarker(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		removeMarker(player.UserId)
	end)
	-- recovery + expiry + last-ground tracking loop
	task.spawn(function()
		while true do
			task.wait(0.3)
			local t = os.time()
			for player, rt in S.PlayerStateService.All() do
				local root = rt.Root
				local hum = rt.Humanoid
				if root and root.Parent and rt.Combat and not rt.Combat.Dead then
					-- safety net: falling out of the open world returns you to solid ground instead
					-- of killing you (arenas handle their own falls)
					if root.Position.Y < -60 and rt.Encounter == nil and rt.Character then
						local back = (rt.LastGroundPos or S.PlayerStateService.RespawnPosition(player)) + Vector3.new(0, 6, 0)
						S.AntiCheatService.AllowTeleport(player)
						root.AssemblyLinearVelocity = Vector3.zero
						rt.Character:PivotTo(CFrame.new(back))
						S.NotifyService.Toast(player, "The abyss rejects you.", "Warning")
					end
					if hum and hum.FloorMaterial ~= Enum.Material.Air and root.Position.Y > -40 and rt.Encounter == nil then
						rt.LastGroundPos = root.Position - Vector3.new(0, 2.5, 0)
					end
					local lost = rt.Profile.LostCurrency
					if lost then
						if DeathCore.expire(rt.Profile, t) > 0 then
							removeMarker(player.UserId)
							S.NotifyService.Toast(player, "Your lost embers have faded away.", "Warning")
							S.PlayerStateService.Sync(player)
						else
							local p = root.Position
							local ok, amount = DeathCore.recover(rt.Profile, p.X, p.Y - 2.5, p.Z, t)
							if ok then
								removeMarker(player.UserId)
								AchievementCore.increment(rt.Profile, "Recoveries")
								S.NotifyService.Banner(player, "EMBERS RECOVERED", ("+%d %s"):format(amount, GameConfig.Currency.Name), "Reward")
								S.ProgressionService.EvaluateAchievements(player)
								S.PlayerStateService.PushVitals(player)
								S.PlayerStateService.Sync(player)
								task.spawn(S.DataService.Save, player)
							end
						end
					end
				end
			end
		end
	end)
end

return DeathService
