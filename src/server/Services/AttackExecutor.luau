--[[
	AttackExecutor
	Runs an enemy/boss attack definition (Config/Attacks.luau) against players:
	telegraph -> windup (interruptible by stagger/death) -> resolve -> recovery.
	Positions are locked when the telegraph appears, so what the player sees is exactly what
	gets checked. Used by EnemyService, BossService and TrainingService.

	attacker = {
	  Entity, Model, Root, Humanoid, Shoulder, BaseDamage, Floor?, DamageScale?,
	  Targets(): { Player }            -- eligible victims
	  ArenaCenter?: Vector3, ArenaRadius?: number
	  OnSummon?(enemyId, count, maxAlive, position)
	  OnHitPlayer?(player, outcome)
	  OnLand?(), OnTakeoff?()          -- airborne bosses
	  Airborne?: bool
	}
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Geometry = require(Shared.Logic.Geometry)
local BossBrain = require(script.Parent.Parent.Core.BossBrain)
local EntityModels = require(script.Parent.EntityModels)

local AttackExecutor = {}

local S
local VERTICAL_TOLERANCE = 12

function AttackExecutor.Init(services)
	S = services
end
function AttackExecutor.Start() end

local function now()
	return workspace:GetServerTimeNow()
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include

function AttackExecutor.GroundY(pos: Vector3, fallback: number?): number
	local map = workspace:FindFirstChild("Map")
	local list = { workspace.Terrain }
	if map then
		table.insert(list, map)
	end
	local arenas = workspace:FindFirstChild("Arenas")
	if arenas then
		table.insert(list, arenas)
	end
	groundParams.FilterDescendantsInstances = list
	local hit = workspace:Raycast(pos + Vector3.new(0, 4, 0), Vector3.new(0, -80, 0), groundParams)
	if hit then
		return hit.Position.Y
	end
	return fallback or (pos.Y - 3)
end

local function interrupted(attacker): boolean
	local e = attacker.Entity
	if not e or not e.Alive or e.Target.Dead then
		return true
	end
	if attacker.Model == nil or attacker.Model.Parent == nil then
		return true
	end
	return now() < e.Target.StaggeredUntil
end

-- Waits `t` seconds; returns false if interrupted.
local function waitInterruptible(attacker, t: number): boolean
	local deadline = os.clock() + t
	while os.clock() < deadline do
		if interrupted(attacker) then
			return false
		end
		task.wait(math.min(0.05, deadline - os.clock()))
	end
	return not interrupted(attacker)
end

local function targetPos(player: Player?): Vector3?
	if not player then
		return nil
	end
	local rt = S.PlayerStateService.Get(player)
	if rt and rt.Root and rt.Root.Parent and rt.Combat and not rt.Combat.Dead then
		return rt.Root.Position
	end
	return nil
end

local function face(attacker, pos: Vector3)
	local root = attacker.Root
	if not root or not root.Parent then
		return
	end
	local flat = Vector3.new(pos.X, root.Position.Y, pos.Z)
	if (flat - root.Position).Magnitude > 0.1 then
		root.CFrame = CFrame.lookAt(root.Position, flat)
	end
end

local function hitSpec(attacker, step)
	return {
		Damage = attacker.BaseDamage * (step.Damage or 1) * (attacker.DamageScale or 1),
		DamageType = step.DamageType or "Physical",
		Poise = step.Poise or 20,
		Parryable = step.Parryable == true,
		Blockable = step.Blockable ~= false,
		Status = step.Status,
		Attacker = attacker,
		Name = step.Name,
	}
end

local function damagePlayers(attacker, step, test: (Vector3) -> boolean, sourcePos: Vector3, groundY: number)
	local spec = hitSpec(attacker, step)
	for _, plr in attacker.Targets() do
		local pos = targetPos(plr)
		if pos and math.abs(pos.Y - groundY) <= VERTICAL_TOLERANCE + 3 and test(pos) then
			S.CombatService.QueueHostileHit(plr, spec, sourcePos)
		end
	end
end

local function moveKinematic(attacker, toPos: Vector3, duration: number, arcHeight: number)
	local root = attacker.Root
	if not root or not root.Parent then
		return
	end
	local from = root.Position
	local look = Vector3.new(toPos.X - from.X, 0, toPos.Z - from.Z)
	root.Anchored = true
	local t0 = os.clock()
	while true do
		local a = math.clamp((os.clock() - t0) / duration, 0, 1)
		local p = from:Lerp(toPos, a) + Vector3.new(0, arcHeight * 4 * a * (1 - a), 0)
		if look.Magnitude > 0.1 then
			root.CFrame = CFrame.lookAt(p, p + look)
		else
			root.CFrame = CFrame.new(p) * root.CFrame.Rotation
		end
		if a >= 1 or not root.Parent then
			break
		end
		task.wait()
	end
	-- a boss that died mid-move stays anchored for its death fade
	if root.Parent and attacker.Entity and attacker.Entity.Alive then
		root.Anchored = false
		-- anchoring resets network ownership; keep AI physics on the server
		pcall(function()
			root:SetNetworkOwner(nil)
		end)
	end
end

local function clampToArena(attacker, pos: Vector3): Vector3
	local c, r = attacker.ArenaCenter, attacker.ArenaRadius
	if not c or not r then
		return pos
	end
	local d = Vector3.new(pos.X - c.X, 0, pos.Z - c.Z)
	local limit = r - 8
	if d.Magnitude > limit then
		d = d.Unit * limit
	end
	return Vector3.new(c.X + d.X, pos.Y, c.Z + d.Z)
end

-- Executes one step. Returns false if interrupted.
local function runStep(attacker, step, isFollowUp: boolean, primary: Player?): boolean
	local windup, _ = BossBrain.timing(step, attacker.Floor, isFollowUp)
	local root = attacker.Root
	if not root or not root.Parent then
		return false
	end
	local tpos = targetPos(primary) or (root.Position + root.CFrame.LookVector * 10)
	if attacker.Humanoid then
		attacker.Humanoid:MoveTo(root.Position)
		attacker.Humanoid.AutoRotate = false
	end
	face(attacker, tpos)
	local origin = root.Position
	local groundY = attacker.GroundY or AttackExecutor.GroundY(origin)
	if attacker.Airborne and not (step.Lands or step.Shape == "Dash" or step.Shape == "Leap") then
		-- airborne attackers telegraph from directly beneath them
		origin = Vector3.new(origin.X, groundY, origin.Z)
	end
	local dir = Vector3.new(tpos.X - origin.X, 0, tpos.Z - origin.Z)
	dir = if dir.Magnitude > 0.1 then dir.Unit else Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
	local kind = S.TelegraphService.KindFor(step)
	local shape = step.Shape
	local ground = Vector3.new(origin.X, groundY, origin.Z)

	EntityModels.windup(attacker.Shoulder, windup)

	if shape == "Cone" then
		S.TelegraphService.Show({ Shape = "Cone", Origin = ground, Dir = dir, Range = step.Range, Arc = step.Arc, Kind = kind, GroundY = groundY }, windup)
		if not waitInterruptible(attacker, windup) then
			return false
		end
		EntityModels.strike(attacker.Shoulder)
		damagePlayers(attacker, step, function(p)
			return Geometry.inCone(ground.X, ground.Z, dir.X, dir.Z, p.X, p.Z, step.Range, step.Arc, 1.2)
		end, origin, groundY)
	elseif shape == "Circle" then
		local c = ground + dir * (step.Offset or 0)
		S.TelegraphService.Show({ Shape = "Circle", Center = c, Radius = step.Radius, Kind = kind }, windup)
		if not waitInterruptible(attacker, windup) then
			return false
		end
		EntityModels.strike(attacker.Shoulder)
		S.TelegraphService.Impact(c, step.Radius)
		damagePlayers(attacker, step, function(p)
			return Geometry.inCircle(c.X, c.Z, p.X, p.Z, step.Radius, 1)
		end, origin, groundY)
	elseif shape == "Line" then
		local o = ground
		local d = dir
		if step.FromEdge and attacker.ArenaCenter then
			local ang = math.random() * math.pi * 2
			d = Vector3.new(math.cos(ang), 0, math.sin(ang))
			o = Vector3.new(attacker.ArenaCenter.X, groundY, attacker.ArenaCenter.Z) - d * (attacker.ArenaRadius or 70)
			local side = Vector3.new(-d.Z, 0, d.X)
			o += side * (math.random() * 2 - 1) * (attacker.ArenaRadius or 70) * 0.6
		end
		S.TelegraphService.Show({ Shape = "Line", Origin = o, Dir = d, Length = step.Length, Width = step.Width, Kind = kind, GroundY = groundY }, windup)
		if not waitInterruptible(attacker, windup) then
			return false
		end
		EntityModels.strike(attacker.Shoulder)
		damagePlayers(attacker, step, function(p)
			return Geometry.inLine(o.X, o.Z, d.X, d.Z, p.X, p.Z, step.Length, step.Width, 1)
		end, o, groundY)
	elseif shape == "Ring" then
		S.TelegraphService.Show({ Shape = "Ring", Center = ground, Inner = step.Inner, Outer = step.Outer, Kind = kind }, windup)
		if not waitInterruptible(attacker, windup) then
			return false
		end
		S.TelegraphService.Impact(ground, step.Outer * 0.5)
		damagePlayers(attacker, step, function(p)
			return Geometry.inRing(ground.X, ground.Z, p.X, p.Z, step.Inner, step.Outer, 0.5)
		end, origin, groundY)
	elseif shape == "Dash" then
		local length = math.min(step.Length, (Vector3.new(tpos.X, 0, tpos.Z) - Vector3.new(origin.X, 0, origin.Z)).Magnitude + 6)
		length = math.max(length, 8)
		S.TelegraphService.Show({ Shape = "Line", Origin = ground, Dir = dir, Length = length, Width = step.Width, Kind = kind, GroundY = groundY }, windup)
		if attacker.Airborne and attacker.OnLand then
			attacker.OnLand()
		end
		if not waitInterruptible(attacker, windup) then
			return false
		end
		local dest = clampToArena(attacker, Vector3.new(origin.X, root.Position.Y, origin.Z) + dir * length)
		if attacker.Airborne then
			dest = Vector3.new(dest.X, groundY + (attacker.Model:GetAttribute("Height") or 5) * 0.5, dest.Z)
		end
		moveKinematic(attacker, dest, 0.25, 0)
		damagePlayers(attacker, step, function(p)
			return Geometry.inLine(ground.X, ground.Z, dir.X, dir.Z, p.X, p.Z, length, step.Width, 1)
		end, origin, groundY)
		if step.LeaveHazard then
			for i = 1, 3 do
				local pt = ground + dir * (length * i / 4)
				AttackExecutor.SpawnHazard(attacker, { Radius = 4, Duration = 4, TickDamage = 0.12, DamageType = "Fire", Status = step.Status }, pt)
			end
		end
	elseif shape == "Leap" then
		local landing = clampToArena(attacker, Vector3.new(tpos.X, groundY, tpos.Z))
		S.TelegraphService.Show({ Shape = "Circle", Center = landing, Radius = step.Radius, Kind = kind }, windup)
		if attacker.Airborne and attacker.OnLand then
			attacker.OnLand()
		end
		local rootOffset = root.Position.Y - groundY
		if attacker.Airborne then
			rootOffset = (attacker.Model:GetAttribute("Height") or 5) * 0.5
		end
		-- hang in the air briefly, then fall on the marked spot at the end of the windup
		if not waitInterruptible(attacker, windup * 0.45) then
			return false
		end
		moveKinematic(attacker, landing + Vector3.new(0, rootOffset, 0), windup * 0.55, 18)
		if interrupted(attacker) then
			return false
		end
		S.TelegraphService.Impact(landing, step.Radius)
		damagePlayers(attacker, step, function(p)
			return Geometry.inCircle(landing.X, landing.Z, p.X, p.Z, step.Radius, 1)
		end, landing, groundY)
	elseif shape == "Teleport" then
		local dest
		if step.Away then
			local away = Vector3.new(origin.X - tpos.X, 0, origin.Z - tpos.Z)
			away = if away.Magnitude > 0.1 then away.Unit else Vector3.new(1, 0, 0)
			dest = tpos + away * (step.Distance or 20)
		else
			local ang = math.random() * math.pi * 2
			dest = tpos + Vector3.new(math.cos(ang), 0, math.sin(ang)) * (step.Distance or 12)
		end
		dest = clampToArena(attacker, Vector3.new(dest.X, groundY, dest.Z))
		S.TelegraphService.Show({ Shape = "Circle", Center = dest, Radius = 4, Kind = if (step.Damage or 0) > 0 then kind else "Block" }, windup)
		if not waitInterruptible(attacker, windup) then
			return false
		end
		local rootOffset = root.Position.Y - groundY
		attacker.Model:PivotTo(CFrame.lookAt(dest + Vector3.new(0, rootOffset, 0), Vector3.new(tpos.X, dest.Y + rootOffset, tpos.Z)))
		S.TelegraphService.Impact(dest, 4, Color3.fromRGB(150, 120, 255))
		if (step.Damage or 0) > 0 then
			damagePlayers(attacker, step, function(p)
				return Geometry.inCircle(dest.X, dest.Z, p.X, p.Z, 6, 1)
			end, dest, groundY)
		end
	elseif shape == "Projectile" then
		-- telegraph: a short line showing the firing direction
		S.TelegraphService.Show({ Shape = "Line", Origin = ground, Dir = dir, Length = 10, Width = 1.5, Kind = kind, GroundY = groundY }, windup)
		if not waitInterruptible(attacker, windup) then
			return false
		end
		EntityModels.strike(attacker.Shoulder)
		local count = step.Count or 1
		local spread = math.rad(step.Spread or 0)
		local spec = hitSpec(attacker, step)
		local primaryRt = primary and S.PlayerStateService.Get(primary)
		for i = 1, count do
			local ang = if count > 1 then -spread / 2 + spread * ((i - 1) / (count - 1)) else 0
			local base = math.atan2(dir.X, dir.Z) + ang
			local d = Vector3.new(math.sin(base), 0, math.cos(base))
			local start = root.Position + d * 2 + Vector3.new(0, 1, 0)
			if attacker.Airborne then
				local aim = (tpos - start)
				d = if aim.Magnitude > 0.1 then (Vector3.new(math.sin(base), 0, math.cos(base)) * aim.Magnitude + Vector3.new(0, aim.Y, 0)).Unit else d
			end
			S.ProjectileService.Fire({
				Origin = start,
				Direction = d,
				Speed = step.Speed or 60,
				Radius = step.Radius or 2,
				Range = (step.MaxRange or 70) + 30,
				Color = if spec.DamageType == "Fire" then Color3.fromRGB(255, 120, 40) elseif spec.DamageType == "Magic" then Color3.fromRGB(140, 120, 255) else Color3.fromRGB(230, 220, 200),
				Hostile = true,
				IgnoreCharacters = true,
				HomingTarget = primaryRt and primaryRt.Root or nil,
				Homing = step.Homing or 0,
				OnHit = function(plr, pos)
					S.CombatService.QueueHostileHit(plr, spec, pos - d * 3)
				end,
			})
		end
	elseif shape == "Hazard" then
		local victims = attacker.Targets()
		local points = {}
		for i = 1, step.Count or 1 do
			local plr = victims[((i - 1) % math.max(1, #victims)) + 1]
			local p = targetPos(plr) or tpos
			local jitter = if i > #victims then Vector3.new(math.random(-12, 12), 0, math.random(-12, 12)) else Vector3.zero
			table.insert(points, clampToArena(attacker, Vector3.new(p.X, groundY, p.Z) + jitter))
		end
		for _, pt in points do
			S.TelegraphService.Show({ Shape = "Hazard", Center = pt, Radius = step.Radius, Kind = "Danger" }, windup)
		end
		if not waitInterruptible(attacker, windup) then
			return false
		end
		for _, pt in points do
			if (step.Damage or 0) > 0 then
				damagePlayers(attacker, step, function(p)
					return Geometry.inCircle(pt.X, pt.Z, p.X, p.Z, step.Radius, 0.5)
				end, pt, groundY)
			end
			if (step.Duration or 0) > 1 then
				AttackExecutor.SpawnHazard(attacker, step, pt)
			end
		end
	elseif shape == "Summon" then
		S.TelegraphService.Show({ Shape = "Circle", Center = ground, Radius = 6, Kind = "Block" }, windup)
		if not waitInterruptible(attacker, windup) then
			return false
		end
		if attacker.OnSummon then
			attacker.OnSummon(step.Summon, step.Count or 1, step.MaxAlive or 4, ground)
		end
	elseif shape == "Pulse" then
		local c = attacker.ArenaCenter or ground
		local r = attacker.ArenaRadius or 60
		local cy = Vector3.new(c.X, groundY, c.Z)
		local zones = {}
		local count = step.SafeZones or 3
		-- seed safe zones near players (one per victim, up to the zone count) so a zone is always
		-- within sprinting distance; the rest are spread around the arena
		local victims = attacker.Targets()
		for i = 1, count do
			local plr = victims[i]
			local p = plr and targetPos(plr)
			local z
			if p then
				local ang = math.random() * math.pi * 2
				z = clampToArena(attacker, Vector3.new(p.X, groundY, p.Z) + Vector3.new(math.cos(ang), 0, math.sin(ang)) * (10 + math.random() * 10))
			else
				local ang = (i / count) * math.pi * 2 + math.random()
				z = cy + Vector3.new(math.cos(ang), 0, math.sin(ang)) * r * (0.35 + 0.3 * math.random())
			end
			table.insert(zones, Vector3.new(z.X, groundY, z.Z))
		end
		-- guarantee time to reach the nearest zone at sprint speed (24 studs/s) with margin
		for _, plr in victims do
			local p = targetPos(plr)
			if p then
				local nearest = math.huge
				for _, z in zones do
					nearest = math.min(nearest, Vector3.new(p.X - z.X, 0, p.Z - z.Z).Magnitude - step.SafeRadius)
				end
				windup = math.max(windup, math.max(0, nearest) / 20 + 0.6)
			end
		end
		S.TelegraphService.Show({ Shape = "Pulse", Center = cy, Radius = r, SafeZones = zones, SafeRadius = step.SafeRadius }, windup)
		if not waitInterruptible(attacker, windup) then
			return false
		end
		S.TelegraphService.Impact(cy, r * 0.6, Color3.fromRGB(255, 80, 60))
		damagePlayers(attacker, step, function(p)
			for _, z in zones do
				if Geometry.inCircle(z.X, z.Z, p.X, p.Z, step.SafeRadius, 0) then
					return false
				end
			end
			return true
		end, cy, groundY)
	elseif shape == "CounterStance" then
		local e = attacker.Entity
		local fired = false
		e.CounterStance = {
			Until = now() + windup,
			Reduction = attacker.CounterReduction or 0.85,
			Fired = false,
			OnCounter = function(player)
				fired = true
				local p = targetPos(player)
				if p then
					face(attacker, p)
				end
				local counter = {
					Shape = "Cone", Name = step.Name .. " (Counter)", Windup = step.CounterWindup or 0.45, Recovery = 0.4,
					Damage = step.Damage, Range = step.Range, Arc = step.Arc, Poise = 50, Parryable = true, Blockable = true,
				}
				runStep(attacker, counter, true, player)
			end,
		}
		if attacker.Model then
			attacker.Model:SetAttribute("CounterStance", true)
		end
		S.TelegraphService.Show({ Shape = "Ring", Center = ground, Inner = 2, Outer = 4, Kind = "Parry" }, windup)
		local deadline = os.clock() + windup
		while os.clock() < deadline and not fired and not interrupted(attacker) do
			task.wait(0.05)
		end
		if fired then
			-- let the counterattack (running on its own thread) finish before recovering
			task.wait((step.CounterWindup or 0.45) + 0.5)
		end
		e.CounterStance = nil
		if attacker.Model and attacker.Model.Parent then
			attacker.Model:SetAttribute("CounterStance", false)
		end
	end
	return true
end

function AttackExecutor.SpawnHazard(attacker, step, center: Vector3)
	local duration = step.Duration or 5
	local radius = step.Radius or 5
	S.TelegraphService.Hazard(center, radius, duration)
	local spec = hitSpec(attacker, step)
	spec.Damage = attacker.BaseDamage * (step.TickDamage or 0.15) * (attacker.DamageScale or 1)
	spec.Blockable = false
	spec.Parryable = false
	spec.Poise = 0
	spec.Tick = true
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < duration do
			task.wait(0.6)
			if not attacker.Model or not attacker.Model.Parent then
				-- hazards outlive dead casters briefly, but stop if the arena is gone
				if attacker.ArenaGone and attacker.ArenaGone() then
					return
				end
			end
			for _, plr in attacker.Targets() do
				local p = targetPos(plr)
				if p and Geometry.inCircle(center.X, center.Z, p.X, p.Z, radius, 0.5) and math.abs(p.Y - center.Y) < 8 then
					S.CombatService.QueueHostileHit(plr, spec, center)
				end
			end
		end
	end)
end

-- Runs a full attack (single or combo). Yields. Returns true if completed.
function AttackExecutor.Run(attacker, attack, primary: Player?): boolean
	local steps = BossBrain.steps(attack)
	local ok = true
	for i, step in steps do
		if interrupted(attacker) then
			ok = false
			break
		end
		if not runStep(attacker, step, i > 1, primary) then
			ok = false
			break
		end
		if i < #steps then
			local _, rec = BossBrain.timing(step, attacker.Floor, i > 1)
			-- inside a combo, only the authored short gap separates steps
			task.wait(math.min(rec, step.Recovery or 0.3))
		end
	end
	local last = steps[#steps]
	local _, recovery = BossBrain.timing({ Windup = 1, Recovery = attack.Recovery or last.Recovery }, attacker.Floor, false)
	if ok and attacker.Airborne and (last.Lands or last.Shape == "Dash" or last.Shape == "Leap") and attacker.OnLand then
		attacker.OnLand()
	end
	if attacker.Humanoid and attacker.Humanoid.Parent then
		attacker.Humanoid.AutoRotate = true
	end
	-- recovery window (vulnerable)
	if attacker.Model and attacker.Model.Parent then
		attacker.Model:SetAttribute("Recovering", true)
	end
	task.wait(recovery)
	if attacker.Model and attacker.Model.Parent then
		attacker.Model:SetAttribute("Recovering", false)
	end
	if attacker.Airborne and attacker.OnTakeoff then
		attacker.OnTakeoff()
	end
	return ok
end

return AttackExecutor
