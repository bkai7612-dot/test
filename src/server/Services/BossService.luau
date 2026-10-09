--[[
	BossService
	Reusable boss framework for the 20 tower floors.

	* Each attempt builds a private arena instance in one of MaxConcurrentArenas slots far
	  from the world, so several solo players / parties can fight any floor at the same time.
	* Encounter ownership and reward eligibility live in EncounterCore (pure, tested).
	* Phases come from Config/Bosses; mechanics are generic and data-driven:
	    Twin, Armor, WeakPoints, Airborne, Stances, Ambient, Counter, ParryReward, summons.
	* Phase transitions grant a short invulnerable roar so players can read the change.
	* Boss HP scales with participant count; leaving/dying participants scale it back down.
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Bosses = require(Shared.Config.Bosses)
local World = require(Shared.Config.World)
local Formulas = require(Shared.Logic.Formulas)
local Rng = require(Shared.Util.Rng)
local Net = require(Shared.Net)
local Core = script.Parent.Parent.Core
local EncounterCore = require(Core.EncounterCore)
local BossBrain = require(Core.BossBrain)
local CombatCore = require(Core.CombatCore)
local AchievementCore = require(Core.AchievementCore)
local BossModels = require(script.Parent.BossModels)

local BossService = {}
local S
local bossRemote: RemoteEvent
local slots = {} -- [slotIndex] = encounter runtime
local rng = Rng.new()

local function now()
	return workspace:GetServerTimeNow()
end

local function gatePos(): Vector3
	local g = World.Tower.GatePosition
	return Vector3.new(g[1], g[2], g[3])
end

function BossService.Init(services)
	S = services
	bossRemote = Net.event("Boss")
	local arenas = Instance.new("Folder")
	arenas.Name = "Arenas"
	arenas.Parent = workspace
end

local function participants(run)
	local out = {}
	for uid, p in run.Core.Participants do
		if p.Alive then
			local plr = run.Players[uid]
			if plr and plr.Parent then
				table.insert(out, plr)
			end
		end
	end
	return out
end

local function broadcast(run, payload, includeRemoved: boolean?)
	for uid, plr in run.Players do
		if plr.Parent and (includeRemoved or (run.Core.Participants[uid] and run.Core.Participants[uid].Alive)) then
			bossRemote:FireClient(plr, payload)
		end
	end
end

local function bossSnapshot(run)
	local list = {}
	for _, ctl in run.Bosses do
		table.insert(list, {
			Id = ctl.Entity.Id,
			Name = ctl.Name,
			Health = math.max(0, math.floor(ctl.Entity.Target.Health)),
			Max = ctl.Entity.Target.MaxHealth,
			Poise = ctl.Entity.Target.Poise / ctl.Entity.Target.MaxPoise,
			Armor = ctl.Entity.ArmorUp == true,
		})
	end
	return list
end

local function sendUpdate(run)
	broadcast(run, {
		Type = "Update",
		Bosses = bossSnapshot(run),
		Phase = run.PhaseName,
		Stance = run.StanceName,
	})
end

local function teleport(player: Player, cf: CFrame)
	local rt = S.PlayerStateService.Get(player)
	if not rt or not rt.Character then
		return
	end
	pcall(function()
		player:RequestStreamAroundAsync(cf.Position, 5)
	end)
	S.AntiCheatService.AllowTeleport(player)
	rt.Character:PivotTo(cf)
end

local function cleanup(run)
	if run.Cleaned then
		return
	end
	run.Cleaned = true
	run.Ended = true
	for _, ai in run.Summons do
		if not ai.Dead then
			S.EnemyService.Despawn(ai, false)
		end
	end
	for _, ctl in run.Bosses do
		for _, wp in ctl.WeakPoints or {} do
			S.EntityService.Unregister(wp)
		end
		if ctl.Entity.Alive then
			S.EntityService.Unregister(ctl.Entity)
		end
		if ctl.Model then
			ctl.Model:Destroy()
		end
	end
	for uid, plr in run.Players do
		local rt = S.PlayerStateService.Get(plr)
		if rt and rt.Encounter == run then
			rt.Encounter = nil
			plr:SetAttribute("ArenaFloor", nil)
		end
		if plr.Parent then
			bossRemote:FireClient(plr, { Type = "End" })
		end
		run.Players[uid] = nil
	end
	if run.ArenaEntity then
		run.ArenaEntity.Alive = false
	end
	if run.Arena then
		run.Arena:Destroy()
	end
	slots[run.Slot] = nil
end

local function exitArena(run, player: Player)
	local rt = S.PlayerStateService.Get(player)
	if rt and rt.Encounter == run then
		rt.Encounter = nil
		player:SetAttribute("ArenaFloor", nil)
		if rt.Combat and not rt.Combat.Dead then
			teleport(player, CFrame.new(gatePos() + Vector3.new(math.random(-6, 6), 4, 16)))
		end
	end
end

-- ===================================================================== victory / defeat
local function victory(run)
	if not EncounterCore.markVictory(run.Core) then
		return
	end
	local def = run.Def
	run.Ended = true
	for _, ai in run.Summons do
		if not ai.Dead then
			S.EnemyService.Despawn(ai, true)
		end
	end
	broadcast(run, { Type = "Victory", Name = def.Name, Floor = def.Floor, Final = def.Floor == GameConfig.Tower.Floors })
	for _, plr in participants(run) do
		local rt = S.PlayerStateService.Get(plr)
		if rt then
			local rewards = EncounterCore.claim(run.Core, plr.UserId, rt.Profile, rng)
			if rewards then
				AchievementCore.increment(rt.Profile, if rewards.Solo then "SoloBossKills" else "CoopBossKills")
				if rewards.Flawless then
					AchievementCore.increment(rt.Profile, "FlawlessBosses")
				end
				S.NotifyService.Banner(plr, if rewards.FirstClear then "GUARDIAN FELLED" else "GUARDIAN FELLED AGAIN", def.Name .. (if rewards.FirstClear and def.Floor < GameConfig.Tower.Floors then (" - Floor %d unlocked"):format(def.Floor + 1) else ""), "Victory")
				S.ProgressionService.GrantBundle(plr, rewards, def.Name)
				if S.LeaderboardService then
					S.LeaderboardService.Update(plr)
				end
				if rewards.FirstClear and def.Floor == GameConfig.Tower.Floors then
					bossRemote:FireClient(plr, { Type = "Ending" })
				end
				task.spawn(S.DataService.Save, plr)
			end
		end
	end
	-- death sequence
	task.delay(GameConfig.Tower.VictoryTeleportDelay, function()
		for _, plr in participants(run) do
			exitArena(run, plr)
		end
		cleanup(run)
	end)
end

local function defeat(run)
	if run.Ended then
		return
	end
	run.Ended = true
	broadcast(run, { Type = "Defeat", Name = run.Def.Name }, true)
	task.delay(3, function()
		cleanup(run)
	end)
end

-- ===================================================================== participants
local function removeParticipant(player: Player)
	local rt = S.PlayerStateService.Get(player)
	local run = rt and rt.Encounter
	if not run then
		-- player may already be gone from runtime: search
		for _, r in slots do
			if r.Players[player.UserId] then
				run = r
			end
		end
	end
	if not run or run.Ended then
		return
	end
	local scale, failed = EncounterCore.removeParticipant(run.Core, player.UserId)
	if failed then
		defeat(run)
		return
	end
	if scale ~= 1 then
		for _, ctl in run.Bosses do
			CombatCore.scaleTargetHealth(ctl.Entity.Target, scale)
			S.EntityService.PushHealth(ctl.Entity)
		end
		sendUpdate(run)
	end
	if rt then
		rt.Encounter = nil
		player:SetAttribute("ArenaFloor", nil)
	end
end

function BossService.OnParticipantDied(player: Player)
	local rt = S.PlayerStateService.Get(player)
	local run = rt and rt.Encounter
	if run and player.Parent then
		bossRemote:FireClient(player, { Type = "Removed" })
	end
	removeParticipant(player)
end

function BossService.OnParticipantLeft(player: Player)
	removeParticipant(player)
end

function BossService.RecordDamage(player: Player, amount: number)
	local rt = S.PlayerStateService.Get(player)
	if rt and rt.Encounter then
		EncounterCore.recordDamage(rt.Encounter.Core, player.UserId, amount)
	end
end

function BossService.RecordHitTaken(player: Player)
	local rt = S.PlayerStateService.Get(player)
	if rt and rt.Encounter then
		EncounterCore.recordHitTaken(rt.Encounter.Core, player.UserId)
	end
end

-- ===================================================================== boss controllers
local function nearestParticipant(run, pos: Vector3): Player?
	local best, bestD = nil, math.huge
	for _, plr in participants(run) do
		local rt = S.PlayerStateService.Get(plr)
		if rt and rt.Root and rt.Combat and not rt.Combat.Dead then
			local d = (rt.Root.Position - pos).Magnitude
			if d < bestD then
				best, bestD = plr, d
			end
		end
	end
	return best
end

local function setPlatesVisible(ctl, visible: boolean)
	for _, p in ctl.Model:GetDescendants() do
		if p:IsA("BasePart") and p.Name == "ArmorPlate" then
			p.Transparency = if visible then 0 else 1
		end
	end
end

local function spawnBoss(run, index: number, count: number)
	local def = run.Def
	local floor = def.Floor
	local n = run.Core.StartCount
	local name = def.Name
	if count > 1 then
		name = def.Name .. (if index == 1 then " (Judge)" else " (Sentence)")
	end
	local model, root, humanoid, radius, _height, shoulder = BossModels.build(def, index, name)
	local offset = if count > 1 then Vector3.new((index - 1.5) * 24, 0, 0) else Vector3.zero
	local spawnPos = run.Origin + Vector3.new(0, 0, -run.Radius * 0.45) + offset
	model:PivotTo(CFrame.lookAt(spawnPos + Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0), run.Origin + Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0)))
	model.Parent = run.Arena
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	humanoid.WalkSpeed = def.WalkSpeed
	local maxHp = math.floor(Formulas.bossHealth(floor) * def.HealthMult * Formulas.partyHealthMult(n))
	local ctl: any = {
		Run = run,
		Name = name,
		Model = model,
		Root = root,
		Humanoid = humanoid,
		Phase = 0,
		Busy = false,
		NextAttackAt = now() + 2.5,
		Ctx = { Cooldowns = {}, History = {}, Rng = Rng.new(math.random(1, 1e6)) },
		GroundHip = humanoid.HipHeight,
	}
	ctl.Entity = S.EntityService.Register({
		Kind = "Boss",
		Encounter = run,
		Model = model,
		Root = root,
		Name = name,
		Level = Formulas.recommendedLevel(floor),
		MaxHealth = maxHp,
		Poise = math.floor(def.Poise * Formulas.partyPoiseMult(n)),
		Defense = def.Defense,
		Radius = radius,
		Def = def,
		OnDeath = function()
			ctl.Dead = true
			for _, wp in ctl.WeakPoints or {} do
				S.EntityService.Unregister(wp)
			end
			for _, p in model:GetDescendants() do
				if p:IsA("BasePart") then
					p.Anchored = true
					TweenService:Create(p, TweenInfo.new(3), { Transparency = 1, Position = p.Position - Vector3.new(0, 4, 0) }):Play()
				end
			end
			S.TelegraphService.Impact(root.Position, 20, def.Model.Glow)
			local alive = 0
			for _, other in run.Bosses do
				if not other.Dead then
					alive += 1
					local twin = def.Mechanics.Twin
					if twin and not other.Enraged then
						other.Enraged = true
						other.Attacker.DamageScale = 1 + twin.EnrageDamage
						other.Humanoid.WalkSpeed = def.WalkSpeed * (1 + twin.EnrageSpeed)
						other.ForcedPhase = #def.Phases
						broadcast(run, { Type = "Phase", Name = "Grief-stricken fury" })
					end
				end
			end
			if alive == 0 then
				victory(run)
			end
		end,
	})
	local baseDamage = Formulas.bossDamage(floor) * def.DamageMult
	ctl.Attacker = {
		Entity = ctl.Entity,
		Model = model,
		Root = root,
		Humanoid = humanoid,
		Shoulder = shoulder,
		BaseDamage = baseDamage,
		Floor = floor,
		GroundY = run.Origin.Y,
		ArenaCenter = run.Origin,
		ArenaRadius = run.Radius,
		CounterReduction = def.Mechanics.Counter and def.Mechanics.Counter.GuardDamageReduction or nil,
		ParryReward = def.Mechanics.ParryReward,
		Targets = function()
			return participants(run)
		end,
		ArenaGone = function()
			return run.Cleaned == true
		end,
		OnSummon = function(enemyId, count, maxAlive, pos)
			local alive = 0
			for _, ai in run.Summons do
				if not ai.Dead and ai.Def.Id == enemyId then
					alive += 1
				end
			end
			for i = 1, math.min(count, maxAlive - alive) do
				local ang = (i / count) * math.pi * 2 + math.random()
				local p = pos + Vector3.new(math.cos(ang) * 8, 6, math.sin(ang) * 8)
				local ai = S.EnemyService.Spawn(enemyId, p, {
					TargetsFn = function()
						return participants(run)
					end,
					Restrict = function(plr)
						return run.Core.Participants[plr.UserId] ~= nil and run.Core.Participants[plr.UserId].Alive
					end,
					BaseDamage = baseDamage * 0.3,
					HealthScale = 1 + floor * 0.15,
					Floor = floor,
					NoRewards = true,
					Leash = 1e4,
					Encounter = run,
					ArenaCenter = run.Origin,
					ArenaRadius = run.Radius,
				})
				if ai then
					if ai.Model then
						ai.Model.Parent = run.Arena
					end
					table.insert(run.Summons, ai)
				end
			end
		end,
	}
	local mech = def.Mechanics
	if mech.Armor then
		ctl.Entity.ArmorUp = true
		ctl.Entity.ArmorReduction = mech.Armor.Reduction
	end
	if mech.WeakPoints then
		ctl.Entity.DamageMultiplier = mech.WeakPoints.BodyMultiplier
		ctl.WeakPoints = {}
		local torso = model:FindFirstChild("Torso") :: BasePart?
		for i = 1, mech.WeakPoints.Count do
			local wp = Instance.new("Part")
			wp.Name = "WeakPoint"
			wp.Shape = Enum.PartType.Ball
			wp.Size = Vector3.new(2.6, 2.6, 2.6)
			wp.Material = Enum.Material.Neon
			wp.Color = def.Model.Glow or Color3.fromRGB(80, 255, 220)
			wp.CanCollide = false
			wp.CanQuery = false
			wp.Massless = true
			local anchor = torso or root
			local spot = anchor:FindFirstChild("WeakPoint" .. i)
			wp.CFrame = if spot and spot:IsA("Attachment") then spot.WorldCFrame else anchor.CFrame * CFrame.new((i == 1 and 1 or -1) * 2.2, 1.5, 2 + i * 2)
			local w = Instance.new("WeldConstraint")
			w.Part0 = anchor
			w.Part1 = wp
			w.Parent = wp
			wp.Parent = model
			local wpe = S.EntityService.Register({
				Kind = "WeakPoint", Root = wp, Name = name .. " Weak Point", MaxHealth = 1e9, Poise = 1e9, Defense = 0,
				Radius = 1.8, Parent = ctl.Entity, WeakMultiplier = mech.WeakPoints.WeakMultiplier,
			})
			table.insert(ctl.WeakPoints, wpe)
		end
	end
	if mech.Airborne then
		ctl.Attacker.Airborne = true
		ctl.Entity.Airborne = true
		ctl.Attacker.OnLand = function()
			ctl.Entity.Airborne = false
			humanoid.HipHeight = math.max(2, ctl.GroundHip - mech.Airborne.Height)
			model:SetAttribute("Grounded", true)
		end
		ctl.Attacker.OnTakeoff = function()
			ctl.Entity.Airborne = true
			humanoid.HipHeight = ctl.GroundHip
			model:SetAttribute("Grounded", false)
		end
	end
	ctl.Entity.OnDamaged = function(e, _player, result)
		if result.Staggered and e.ArmorUp and mech.Armor then
			e.ArmorUp = false
			setPlatesVisible(ctl, false)
			broadcast(run, { Type = "Phase", Name = "ARMOR BROKEN" })
			task.delay(mech.Armor.BreakDuration, function()
				if e.Alive then
					e.ArmorUp = true
					setPlatesVisible(ctl, true)
				end
			end)
		end
	end
	return ctl
end

local function phaseTransition(run, ctl, phaseIndex: number)
	local phase = run.Def.Phases[phaseIndex]
	ctl.Phase = phaseIndex
	if phaseIndex == 1 then
		return
	end
	ctl.Busy = true
	ctl.Entity.Invulnerable = true -- brief roar so players can read the phase change
	run.PhaseName = phase.Name or ("Phase " .. phaseIndex)
	broadcast(run, { Type = "Phase", Name = run.PhaseName })
	ctl.Humanoid:MoveTo(ctl.Root.Position)
	S.TelegraphService.Impact(ctl.Root.Position, 14, run.Def.Model.Glow)
	task.delay(2, function()
		ctl.Entity.Invulnerable = false
		ctl.Busy = false
		ctl.NextAttackAt = now() + 0.5
	end)
end

local function bossThink(run, ctl)
	if ctl.Dead or ctl.Busy or run.Ended then
		return
	end
	local e = ctl.Entity
	local t = now()
	S.EntityService.TickStatus(e, 0.1, t)
	if ctl.Dead then
		return
	end
	if t < e.Target.StaggeredUntil then
		ctl.Humanoid:MoveTo(ctl.Root.Position)
		return
	end
	-- keep inside the arena
	local pos = ctl.Root.Position
	local flat = Vector3.new(pos.X - run.Origin.X, 0, pos.Z - run.Origin.Z)
	if flat.Magnitude > run.Radius - 4 or pos.Y < run.Origin.Y - 20 then
		ctl.Model:PivotTo(CFrame.new(run.Origin + Vector3.new(0, ctl.Humanoid.HipHeight + ctl.Root.Size.Y / 2, 0)))
	end
	local phaseIndex = ctl.ForcedPhase or BossBrain.phaseIndex(run.Def, e.Target.Health / e.Target.MaxHealth)
	if phaseIndex ~= ctl.Phase then
		phaseTransition(run, ctl, phaseIndex)
		return
	end
	if ctl.Target == nil or not run.Core.Participants[ctl.Target.UserId] or not run.Core.Participants[ctl.Target.UserId].Alive or t > (ctl.RetargetAt or 0) then
		ctl.Target = nearestParticipant(run, pos)
		ctl.RetargetAt = t + 3
	end
	local target = ctl.Target
	if not target then
		return
	end
	local trt = S.PlayerStateService.Get(target)
	if not trt or not trt.Root then
		ctl.Target = nil
		return
	end
	local tpos = trt.Root.Position
	local dist = Vector3.new(tpos.X - pos.X, 0, tpos.Z - pos.Z).Magnitude - e.Radius
	local phase = run.Def.Phases[ctl.Phase]
	local attacks, stanceName = BossBrain.phaseAttacks(phase, run.StanceIndex)
	if stanceName ~= run.StanceName then
		run.StanceName = stanceName
		if stanceName then
			broadcast(run, { Type = "Phase", Name = stanceName })
		end
	end
	if t >= ctl.NextAttackAt then
		ctl.Ctx.Distance = dist
		ctl.Ctx.Now = t
		local attack = BossBrain.choose(attacks, ctl.Ctx)
		if attack then
			BossBrain.recordChoice(ctl.Ctx, attack, t)
			ctl.Busy = true
			task.spawn(function()
				local ok, err = pcall(S.AttackExecutor.Run, ctl.Attacker, attack, target)
				if not ok then
					warn("[BossService] attack error: " .. tostring(err))
				end
				ctl.Busy = false
				-- aggression rises with floor
				ctl.NextAttackAt = now() + math.max(0.25, 1.1 - 0.035 * run.Def.Floor) + ctl.Ctx.Rng:NextNumber() * 0.6
			end)
			return
		end
	end
	if dist > 5 then
		ctl.Humanoid:MoveTo(tpos)
	else
		ctl.Humanoid:MoveTo(pos)
	end
end

-- ===================================================================== encounter lifecycle
local function freeSlot(): number?
	for i = 1, GameConfig.Tower.MaxConcurrentArenas do
		if not slots[i] then
			return i
		end
	end
	return nil
end

local function startEncounter(floor: number, group: { Player })
	if #group == 0 then
		return false, "NoParticipants"
	end
	local slot = freeSlot()
	if not slot then
		return false, "TowerBusy"
	end
	local def = Bosses.List[floor]
	local o = GameConfig.Tower.ArenaOrigin
	local origin = Vector3.new(o.X + (slot - 1) * GameConfig.Tower.ArenaSlotSpacing, o.Y, o.Z)
	local run: any = {
		Slot = slot,
		Def = def,
		Origin = origin,
		Radius = def.Arena.Size / 2,
		Players = {},
		Bosses = {},
		Summons = {},
		StanceIndex = 1,
		StartedAt = os.clock(),
	}
	slots[slot] = run
	local uids = {}
	for _, plr in group do
		table.insert(uids, plr.UserId)
		run.Players[plr.UserId] = plr
	end
	run.Core = EncounterCore.new(HttpService:GenerateGUID(false), floor, uids, os.time())
	run.Arena = S.WorldBuilder.BuildArena(def, origin)
	run.Arena.Parent = workspace:FindFirstChild("Arenas")

	for i, plr in group do
		local rt = S.PlayerStateService.Get(plr)
		rt.Encounter = run
		plr:SetAttribute("ArenaFloor", floor)
		local ang = math.rad(-30 + 60 * ((i - 0.5) / #group))
		local p = origin + Vector3.new(math.sin(ang) * (run.Radius - 14), 4, math.cos(ang) * (run.Radius - 14))
		teleport(plr, CFrame.lookAt(p, Vector3.new(origin.X, p.Y, origin.Z)))
		S.PlayerStateService.FullRestore(plr)
	end

	local count = def.Mechanics.Twin and def.Mechanics.Twin.Count or 1
	for i = 1, count do
		table.insert(run.Bosses, spawnBoss(run, i, count))
	end
	broadcast(run, {
		Type = "Start",
		Floor = floor,
		Name = def.Name,
		Title = def.Title,
		Mechanic = def.Mechanic,
		Theme = { Fog = def.Arena.Fog, Light = def.Arena.Light },
		Bosses = bossSnapshot(run),
	})

	-- ambient hazards
	if def.Mechanics.Ambient then
		local anchor = Instance.new("Part")
		anchor.Name = "AmbientAnchor"
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.Transparency = 1
		anchor.CFrame = CFrame.new(origin + Vector3.new(0, 3, 0))
		anchor.Parent = run.Arena
		local amb = def.Mechanics.Ambient
		local first = run.Bosses[1]
		-- the arena itself casts ambient hazards: independent of any boss's stagger/death
		local arenaEntity = { Alive = true, Kind = "Arena", Target = CombatCore.newTarget(1, 1) }
		run.ArenaEntity = arenaEntity
		local ambient = {
			Entity = arenaEntity,
			Model = run.Arena,
			Root = anchor,
			BaseDamage = first.Attacker.BaseDamage,
			Floor = floor,
			GroundY = origin.Y,
			ArenaCenter = origin,
			ArenaRadius = run.Radius,
			Targets = first.Attacker.Targets,
			ArenaGone = first.Attacker.ArenaGone,
		}
		task.spawn(function()
			task.wait(6)
			local turn = 0
			while not run.Ended do
				local list = participants(run)
				turn += 1
				local victim = list[(turn - 1) % math.max(1, #list) + 1]
				pcall(S.AttackExecutor.Run, ambient, amb.Attack, victim)
				task.wait(amb.Interval)
			end
		end)
	end

	-- main loop
	task.spawn(function()
		task.wait(2.5) -- intro title card
		local lastUpdate = 0
		local lastStance = os.clock()
		while not run.Ended do
			task.wait(0.1)
			if def.Mechanics.Stances and os.clock() - lastStance >= def.Mechanics.Stances.Interval then
				lastStance = os.clock()
				run.StanceIndex += 1
			end
			for _, ctl in run.Bosses do
				local ok, err = pcall(bossThink, run, ctl)
				if not ok then
					warn("[BossService] think error: " .. tostring(err))
					ctl.Busy = false
				end
			end
			-- keep participants inside the arena
			for _, plr in participants(run) do
				local rt = S.PlayerStateService.Get(plr)
				if rt and rt.Root and rt.Combat and not rt.Combat.Dead then
					local p = rt.Root.Position
					if p.Y < origin.Y - 30 then
						S.DeathService.OnPlayerDeath(plr, "Fall")
					elseif Vector3.new(p.X - origin.X, 0, p.Z - origin.Z).Magnitude > run.Radius + 25 then
						teleport(plr, CFrame.new(origin + Vector3.new(0, 4, run.Radius - 14)))
					end
				end
			end
			if os.clock() - lastUpdate > 0.2 then
				lastUpdate = os.clock()
				sendUpdate(run)
			end
			if os.clock() - run.StartedAt > GameConfig.Tower.EncounterIdleTimeout then
				for _, plr in participants(run) do
					exitArena(run, plr)
				end
				defeat(run)
			end
		end
	end)
	return true, run.Core.Id
end

function BossService.Start()
	local lastEnter = {}
	S.RequestService.Register("EnterFloor", function(player, rt, floor)
		if rt.Encounter then
			return false, "AlreadyInside"
		end
		if not rt.Combat or rt.Combat.Dead then
			return false, "Dead"
		end
		if os.clock() - (lastEnter[player] or -1e9) < 5 then
			return false, "TooFast"
		end
		lastEnter[player] = os.clock()
		if not rt.Root or (rt.Root.Position - gatePos()).Magnitude > GameConfig.Party.GatherRadius then
			return false, "NotAtGate"
		end
		local ok, err = EncounterCore.canEnter(rt.Profile, floor)
		if not ok then
			return false, err
		end
		-- solo, or the whole party if the requester leads it
		local members = S.PartyService.Members(player)
		if #members > 1 and not S.PartyService.IsLeader(player) then
			return false, "OnlyLeaderStarts"
		end
		local group = {}
		for _, m in members do
			local mrt = S.PlayerStateService.Get(m)
			if mrt and mrt.Root and mrt.Combat and not mrt.Combat.Dead and not mrt.Encounter
				and (mrt.Root.Position - gatePos()).Magnitude <= GameConfig.Party.GatherRadius then
				local can, why = EncounterCore.canEnter(mrt.Profile, floor)
				if can then
					table.insert(group, m)
				elseif m ~= player then
					S.NotifyService.Toast(player, ("%s cannot enter floor %d (%s)."):format(m.DisplayName, floor, tostring(why)), "Warning")
					S.NotifyService.Toast(m, ("You have not unlocked floor %d."):format(floor), "Warning")
				end
			elseif m ~= player then
				S.NotifyService.Toast(m, "Your party entered the tower without you (gather at the gate to join).", "Warning")
			end
		end
		if not table.find(group, player) then
			return false, "NoParticipants"
		end
		return startEncounter(floor, group)
	end)
	game:GetService("Players").PlayerRemoving:Connect(function(p)
		lastEnter[p] = nil
	end)

	S.RequestService.Register("LeaveArena", function(player, rt)
		local run = rt.Encounter
		if not run then
			return false, "NotInside"
		end
		if not run.Ended then
			removeParticipant(player)
		end
		exitArena(run, player)
		bossRemote:FireClient(player, { Type = "End" })
		return true, nil
	end)
end

function BossService.ActiveArenas(): number
	local n = 0
	for _ in slots do
		n += 1
	end
	return n
end

return BossService
