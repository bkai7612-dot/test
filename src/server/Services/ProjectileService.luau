--[[
	ProjectileService
	Server-simulated projectiles (arrows, spells, boss volleys). Each projectile is an anchored
	part moved every Heartbeat; collision is a sphere test against targets plus a raycast
	against world geometry. Projectiles are capped and always cleaned up.

	spec = {
	  Origin: Vector3, Direction: Vector3, Speed, Radius, Range, Color,
	  Hostile: bool          -- true = hits players, false = hits entities
	  Owner: Player?         -- for player projectiles
	  HomingTarget: BasePart?, Homing: number (0..1 turn rate)
	  OnHit(target, position) -- target = Player (hostile) or entity (friendly)
	  Pierce: bool
	}
]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local ProjectileService = {}

local S
local active = {}
local folder: Folder
local MAX_ACTIVE = 300


function ProjectileService.Init(services)
	S = services
	folder = Instance.new("Folder")
	folder.Name = "Projectiles"
	folder.Parent = workspace
end

function ProjectileService.Fire(spec)
	if #active >= MAX_ACTIVE then
		return nil
	end
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.Neon
	p.Color = spec.Color or Color3.fromRGB(255, 160, 80)
	p.Size = Vector3.new(1, 1, 1) * math.max(0.6, spec.Radius * 1.2)
	p.CFrame = CFrame.new(spec.Origin)
	local light = Instance.new("PointLight")
	light.Color = p.Color
	light.Range = 8
	light.Parent = p
	p.Parent = folder
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = { folder, workspace:FindFirstChild("Telegraphs"), workspace:FindFirstChild("Entities") }
	if spec.Owner and spec.Owner.Character then
		table.insert(ignore, spec.Owner.Character)
	end
	if spec.IgnoreCharacters then
		for _, plr in Players:GetPlayers() do
			if plr.Character then
				table.insert(ignore, plr.Character)
			end
		end
	end
	params.FilterDescendantsInstances = ignore
	local proj = {
		Params = params,
		Part = p,
		Pos = spec.Origin,
		Dir = if spec.Direction.Magnitude > 0 then spec.Direction.Unit else Vector3.new(0, 0, -1),
		Travelled = 0,
		Spec = spec,
		Hit = {},
	}
	table.insert(active, proj)
	return proj
end

local function finish(i: number)
	local proj = active[i]
	if proj.Part then
		proj.Part:Destroy()
	end
	table.remove(active, i)
end

local function step(dt: number)
	for i = #active, 1, -1 do
		local proj = active[i]
		local spec = proj.Spec
		if not proj.Part.Parent then
			table.remove(active, i)
			continue
		end
		if spec.HomingTarget and spec.HomingTarget.Parent and (spec.Homing or 0) > 0 then
			local want = (spec.HomingTarget.Position - proj.Pos)
			if want.Magnitude > 0.1 then
				proj.Dir = proj.Dir:Lerp(want.Unit, math.clamp(spec.Homing * dt * 3, 0, 1)).Unit
			end
		end
		local move = proj.Dir * spec.Speed * dt
		local hitWorld = workspace:Raycast(proj.Pos, move, proj.Params)
		local nextPos = if hitWorld then hitWorld.Position else proj.Pos + move
		proj.Travelled += (nextPos - proj.Pos).Magnitude
		proj.Pos = nextPos
		proj.Part.CFrame = CFrame.new(nextPos)

		local done = false
		if spec.Hostile then
			for _, plr in Players:GetPlayers() do
				local rt = S.PlayerStateService.Get(plr)
				if rt and rt.Root and rt.Combat and not rt.Combat.Dead and not proj.Hit[plr] then
					if (rt.Root.Position - nextPos).Magnitude <= spec.Radius + 2 then
						proj.Hit[plr] = true
						task.spawn(spec.OnHit, plr, nextPos)
						if not spec.Pierce then
							done = true
							break
						end
					end
				end
			end
		else
			for _, e in S.EntityService.Near(nextPos, spec.Radius, 10) do
				if not proj.Hit[e] then
					proj.Hit[e] = true
					task.spawn(spec.OnHit, e, nextPos)
					if not spec.Pierce then
						done = true
						break
					end
				end
			end
			-- PvP projectiles
			if not done and spec.PvpTargets then
				for _, plr in spec.PvpTargets do
					local rt = S.PlayerStateService.Get(plr)
					if rt and rt.Root and not proj.Hit[plr] and (rt.Root.Position - nextPos).Magnitude <= spec.Radius + 2 then
						proj.Hit[plr] = true
						task.spawn(spec.OnHitPlayer, plr, nextPos)
						done = true
						break
					end
				end
			end
		end
		if done or hitWorld or proj.Travelled >= spec.Range then
			if spec.OnExpire then
				task.spawn(spec.OnExpire, nextPos)
			end
			finish(i)
		end
	end
end

function ProjectileService.Start()
	RunService.Heartbeat:Connect(step)
end

function ProjectileService.Count(): number
	return #active
end

return ProjectileService
