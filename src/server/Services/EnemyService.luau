--[[
	EnemyService
	Controlled spawning and AI for Wildlands enemies, elites, mini-bosses, boss summons and
	training sparring partners.

	AI states: Idle -> Patrol -> Chase (detect) -> Attack -> Recover -> Stagger -> Return -> Dead
	* One loop updates every enemy at GameConfig.Enemy.TickRate; enemies with no player within
	  ActivationRadius sleep (cheap) and are only re-checked once per second.
	* Leash: an enemy pulled too far from home returns, fully heals and forgets contributors
	  (prevents kiting/farming exploits).
	* Stuck handling: jump, then a PathfindingService path; if no path, return home.
	* Spawn zones keep at most `Count` alive and respawn on a timer (no uncontrolled spawning).
	* Rewards: every player who dealt >= ContributionThreshold of max HP (or landed the kill)
	  gets their own XP, currency and loot roll. Nothing drops on the ground to be stolen.
]]

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Enemies = require(Shared.Config.Enemies)
local World = require(Shared.Config.World)
local Rng = require(Shared.Util.Rng)
local Core = script.Parent.Parent.Core
local BossBrain = require(Core.BossBrain)
local LootCore = require(Core.LootCore)
local EntityModels = require(script.Parent.EntityModels)

local EnemyService = {}
local S
local folder: Folder
local ais = {} -- [ai] = true
local zones = {}
local rng = Rng.new()

local function now()
	return workspace:GetServerTimeNow()
end

local function v3(t)
	return Vector3.new(t[1], t[2], t[3])
end

function EnemyService.Init(services)
	S = services
	folder = Instance.new("Folder")
	folder.Name = "Entities"
	folder.Parent = workspace
end

function EnemyService.Folder()
	return folder
end

local function validTarget(ai, player: Player): boolean
	local rt = S.PlayerStateService.Get(player)
	if not rt or not rt.Root or not rt.Root.Parent or not rt.Combat or rt.Combat.Dead then
		return false
	end
	if ai.Restrict then
		return ai.Restrict(player)
	end
	-- world enemies never follow players into safe zones or tower arenas
	return not player:GetAttribute("Safe") and rt.Encounter == nil
end

local function targetsFor(ai)
	if ai.TargetsFn then
		return ai.TargetsFn()
	end
	local out = {}
	local pos = ai.Root.Position
	for _, plr in Players:GetPlayers() do
		if validTarget(ai, plr) then
			local rt = S.PlayerStateService.Get(plr)
			if (rt.Root.Position - pos).Magnitude <= 120 then
				table.insert(out, plr)
			end
		end
	end
	return out
end

local function grantRewards(ai, killer: Player?)
	local def = ai.Def
	if ai.NoRewards or def.Tier == "Summon" then
		return
	end
	local e = ai.Entity
	local threshold = e.Target.MaxHealth * GameConfig.Enemy.ContributionThreshold
	for userId, dmg in e.Contributors do
		local plr = Players:GetPlayerByUserId(userId)
		if plr and (dmg >= threshold or plr == killer) then
			local loot = LootCore.roll(def.Loot, rng)
			local currency = LootCore.rollRange(def.Currency, rng)
			S.ProgressionService.OnEnemyKilled(plr, def)
			S.ProgressionService.GrantXp(plr, def.Xp, def.Name)
			S.ProgressionService.GrantCurrency(plr, currency)
			if next(loot) then
				S.ProgressionService.GrantItems(plr, loot, def.Name)
			end
			if def.Tier == "MiniBoss" then
				S.NotifyService.Banner(plr, "FOE VANQUISHED", def.Name, "Victory")
			end
			S.CombatService.SendFx(plr, { Type = "Reward", Xp = def.Xp, Currency = currency, Position = ai.Root and ai.Root.Position })
			S.ProgressionService.EvaluateAchievements(plr)
			S.PlayerStateService.Sync(plr)
			S.PlayerStateService.PushVitals(plr)
		end
	end
end

function EnemyService.Despawn(ai, fade: boolean?)
	ais[ai] = nil
	ai.Dead = true
	if ai.Entity and ai.Entity.Alive then
		S.EntityService.Unregister(ai.Entity)
	end
	local model = ai.Model
	if not model or not model.Parent then
		return
	end
	if fade then
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") and p.Transparency < 1 then
				TweenService:Create(p, TweenInfo.new(1.2), { Transparency = 1 }):Play()
			end
		end
		task.delay(1.3, function()
			model:Destroy()
		end)
	else
		model:Destroy()
	end
end

--[[
	opts = { Zone?, Home?: Vector3, TargetsFn?, Restrict?, BaseDamage?, HealthScale?, Floor?,
	         Leash?, NoRewards?, OnDeath?, ArenaCenter?, ArenaRadius?, Name? }
]]
function EnemyService.Spawn(enemyId: string, position: Vector3, opts)
	local def = Enemies[enemyId]
	if not def then
		warn("[EnemyService] unknown enemy " .. tostring(enemyId))
		return nil
	end
	opts = opts or {}
	local model, root, humanoid, radius, height, shoulder = EntityModels.build(opts.Name or def.Name, def.Model, "Enemy")
	local groundY = S.AttackExecutor.GroundY(position, position.Y)
	model:PivotTo(CFrame.new(position.X, groundY + humanoid.HipHeight + root.Size.Y / 2, position.Z))
	model.Parent = folder
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	humanoid.WalkSpeed = def.WalkSpeed
	local maxHp = math.floor(def.Health * (opts.HealthScale or 1))
	local ai = {
		Def = def,
		Model = model,
		Root = root,
		Humanoid = humanoid,
		Shoulder = shoulder,
		Home = opts.Home or position,
		Zone = opts.Zone,
		State = "Idle",
		Target = nil,
		Busy = false,
		NextAttackAt = 0,
		Cooldowns = {},
		History = {},
		Rng = Rng.new(math.floor(os.clock() * 1000) + math.random(1, 1e6)),
		LastPos = root.Position,
		StuckSince = nil,
		Leash = opts.Leash or def.Leash or GameConfig.Enemy.DefaultLeash,
		TargetsFn = opts.TargetsFn,
		Restrict = opts.Restrict,
		NoRewards = opts.NoRewards,
		Floor = opts.Floor,
		ArenaCenter = opts.ArenaCenter,
		ArenaRadius = opts.ArenaRadius,
	}
	ai.Attacker = {
		Model = model,
		Root = root,
		Humanoid = humanoid,
		Shoulder = shoulder,
		BaseDamage = opts.BaseDamage or def.Damage,
		Floor = opts.Floor,
		ArenaCenter = opts.ArenaCenter,
		ArenaRadius = opts.ArenaRadius,
		Targets = function()
			return targetsFor(ai)
		end,
		OnHitPlayer = opts.OnHitPlayer,
	}
	ai.Entity = S.EntityService.Register({
		Kind = if def.Tier == "MiniBoss" then "MiniBoss" else "Enemy",
		Encounter = opts.Encounter,
		Owner = opts.Owner,
		Model = model,
		Root = root,
		Name = opts.Name or def.Name,
		Level = def.Level,
		MaxHealth = maxHp,
		Poise = def.Poise,
		Defense = def.Defense,
		Radius = radius,
		Def = def,
		OnDeath = function(e, killer)
			ai.Dead = true
			ais[ai] = nil
			grantRewards(ai, killer)
			if opts.OnDeath then
				opts.OnDeath(ai, killer)
			end
			if ai.Zone then
				ai.Zone.Alive -= 1
				ai.Zone.NextSpawn[#ai.Zone.NextSpawn + 1] = os.clock() + (ai.Zone.RespawnTime or def.RespawnTime)
			end
			EnemyService.Despawn(ai, true)
		end,
	})
	ai.Attacker.Entity = ai.Entity
	-- being hit always provokes a reaction: chase the attacker if reachable, otherwise retreat
	-- home and fully heal (prevents risk-free sniping from beyond aggro/leash range)
	ai.Entity.OnDamaged = function(_, player)
		if not player or ai.Dead or ai.Target == player then
			return
		end
		local prt = S.PlayerStateService.Get(player)
		local reachable = prt ~= nil and prt.Root ~= nil and validTarget(ai, player)
			and (Vector3.new(prt.Root.Position.X, 0, prt.Root.Position.Z) - Vector3.new(ai.Home.X, 0, ai.Home.Z)).Magnitude <= ai.Leash
		if reachable then
			ai.Target = player
		elseif not ai.Target then
			ai.State = "Return"
			ai.ForceReset = true
		end
	end
	model:SetAttribute("Height", height)
	model:SetAttribute("Tier", def.Tier)
	ais[ai] = true
	return ai
end

local function nearestPlayer(ai, radius: number): Player?
	local best, bestD = nil, radius
	local pos = ai.Root.Position
	for _, plr in Players:GetPlayers() do
		if validTarget(ai, plr) then
			local d = (S.PlayerStateService.Get(plr).Root.Position - pos).Magnitude
			if d < bestD then
				best, bestD = plr, d
			end
		end
	end
	return best
end

local function anyPlayerNear(pos: Vector3, radius: number): boolean
	for _, rt in S.PlayerStateService.All() do
		if rt.Root and rt.Root.Parent and (rt.Root.Position - pos).Magnitude <= radius then
			return true
		end
	end
	return false
end

local function followPath(ai, goal: Vector3)
	if ai.Pathing then
		return
	end
	ai.Pathing = true
	task.spawn(function()
		local path = PathfindingService:CreatePath({ AgentRadius = math.min(4, ai.Entity.Radius), AgentHeight = 5, AgentCanJump = true })
		local ok = pcall(function()
			path:ComputeAsync(ai.Root.Position, goal)
		end)
		if not ok or path.Status ~= Enum.PathStatus.Success then
			ai.Pathing = false
			ai.State = "Return"
			return
		end
		for _, wp in path:GetWaypoints() do
			if ai.Dead or ai.State ~= "Chase" or ai.Busy then
				break
			end
			if wp.Action == Enum.PathWaypointAction.Jump then
				ai.Humanoid.Jump = true
			end
			ai.Humanoid:MoveTo(wp.Position)
			local reached = ai.Humanoid.MoveToFinished:Wait()
			if not reached then
				break
			end
		end
		ai.Pathing = false
		ai.StuckSince = nil
	end)
end

local function think(ai, dt: number)
	if ai.Dead or not ai.Root.Parent then
		ais[ai] = nil
		return
	end
	local t = now()
	local e = ai.Entity
	local hum = ai.Humanoid
	local pos = ai.Root.Position
	S.EntityService.TickStatus(e, dt, t)
	if ai.Dead then
		return
	end
	-- slow debuff
	local slow = if t < e.Target.SlowUntil then e.Target.SlowAmount else 0
	hum.WalkSpeed = ai.Def.WalkSpeed * (1 - slow) * (ai.SpeedMult or 1)
	if pos.Y < -60 then
		-- fell out of the world (or was flung): no rewards for anyone
		ai.NoRewards = true
		S.EntityService.Kill(e, nil)
		return
	end
	if ai.Busy then
		return
	end
	if t < e.Target.StaggeredUntil then
		ai.State = "Stagger"
		hum:MoveTo(pos)
		return
	end

	local distHome = (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(ai.Home.X, 0, ai.Home.Z)).Magnitude
	if ai.State == "Return" then
		hum:MoveTo(ai.Home)
		if distHome < 6 or ai.ForceReset then
			ai.ForceReset = false
			ai.State = "Idle"
			e.Target.Health = e.Target.MaxHealth
			e.Contributors = {}
			S.EntityService.PushHealth(e)
		end
		return
	end

	if ai.Target and not validTarget(ai, ai.Target) then
		ai.Target = nil
	end
	if not ai.Target then
		ai.Target = nearestPlayer(ai, ai.Def.AggroRadius)
		if not ai.Target then
			if distHome > 8 then
				ai.State = "Return"
			elseif ai.State ~= "Patrol" or math.random() < 0.02 then
				ai.State = "Patrol"
				if math.random() < 0.3 then
					local ang = math.random() * math.pi * 2
					hum:MoveTo(ai.Home + Vector3.new(math.cos(ang), 0, math.sin(ang)) * math.random(3, 12))
				end
			end
			return
		end
	end

	ai.State = "Chase"
	if distHome > ai.Leash then
		ai.Target = nil
		ai.State = "Return"
		return
	end
	local trt = S.PlayerStateService.Get(ai.Target)
	local tpos = trt.Root.Position
	local dist = (Vector3.new(tpos.X, 0, tpos.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude - e.Radius
	if t >= ai.NextAttackAt then
		local attack = BossBrain.choose(ai.Def.Attacks, { Distance = dist, Now = t, Cooldowns = ai.Cooldowns, History = ai.History, Rng = ai.Rng })
		if attack then
			BossBrain.recordChoice({ Cooldowns = ai.Cooldowns, History = ai.History }, attack, t)
			ai.Busy = true
			ai.State = "Attack"
			local target = ai.Target
			task.spawn(function()
				S.AttackExecutor.Run(ai.Attacker, attack, target)
				ai.Busy = false
				ai.State = "Recover"
				ai.NextAttackAt = now() + 0.4 + ai.Rng:NextNumber() * 1.0
			end)
			return
		end
	end
	-- approach
	if not ai.Pathing then
		local keep = math.max(2, (ai.Def.Attacks[1].MaxRange or 6) * 0.6)
		if dist > keep then
			hum:MoveTo(tpos)
		else
			hum:MoveTo(pos)
			ai.Root.CFrame = CFrame.lookAt(pos, Vector3.new(tpos.X, pos.Y, tpos.Z))
		end
		-- stuck detection
		if (pos - ai.LastPos).Magnitude < 0.3 and dist > keep + 2 then
			ai.StuckSince = ai.StuckSince or os.clock()
			local stuckFor = os.clock() - ai.StuckSince
			if stuckFor > 1.2 then
				hum.Jump = true
			end
			if stuckFor > 2.5 then
				followPath(ai, tpos)
			end
		else
			ai.StuckSince = nil
		end
	end
	ai.LastPos = pos
end

local function spawnInZone(zone)
	local def = Enemies[zone.Def.Enemy]
	local ang = rng:NextNumber() * math.pi * 2
	local r = rng:NextNumber() * zone.Def.Radius
	local c = v3(zone.Def.Center)
	local pos = c + Vector3.new(math.cos(ang) * r, 10, math.sin(ang) * r)
	local ai = EnemyService.Spawn(zone.Def.Enemy, pos, { Zone = zone, Home = Vector3.new(pos.X, c.Y, pos.Z) })
	if ai then
		zone.Alive += 1
	end
	return def
end

function EnemyService.ActiveCount(): number
	local n = 0
	for _ in ais do
		n += 1
	end
	return n
end

function EnemyService.Start()
	for _, z in World.SpawnZones do
		local zone = { Def = z, Alive = 0, NextSpawn = {}, RespawnTime = z.RespawnTime }
		table.insert(zones, zone)
		for _ = 1, z.Count do
			table.insert(zone.NextSpawn, 0)
		end
	end

	-- spawn manager (1 Hz)
	task.spawn(function()
		while true do
			local clock = os.clock()
			for _, zone in zones do
				for i = #zone.NextSpawn, 1, -1 do
					if clock >= zone.NextSpawn[i] and zone.Alive < zone.Def.Count and EnemyService.ActiveCount() < GameConfig.Enemy.MaxActive then
						-- don't pop enemies into existence right next to a player
						if not anyPlayerNear(v3(zone.Def.Center), 25) then
							table.remove(zone.NextSpawn, i)
							spawnInZone(zone)
						end
					end
				end
			end
			task.wait(1)
		end
	end)

	-- AI loop
	task.spawn(function()
		local sleepCheck = 0
		while true do
			local dt = task.wait(GameConfig.Enemy.TickRate)
			sleepCheck += dt
			local checkSleep = sleepCheck >= 1
			if checkSleep then
				sleepCheck = 0
			end
			for ai in ais do
				if checkSleep and not ai.TargetsFn then
					ai.Asleep = not anyPlayerNear(ai.Root.Position, GameConfig.Enemy.ActivationRadius)
				end
				if not ai.Asleep then
					local ok, err = pcall(think, ai, dt)
					if not ok then
						warn("[EnemyService] AI error: " .. tostring(err))
						ai.Busy = false
					end
				end
			end
		end
	end)
end

return EnemyService
