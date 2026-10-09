--[[
	EntityService
	Registry of every damageable non-player entity (enemies, bosses, weak points, training
	dummies, summons). Applies player damage with all entity-specific rules:
	  * counter stances (damage reduced + counterattack triggered)
	  * armour (reduced damage until poise is broken)
	  * weak points (forward damage to their parent boss with a multiplier)
	  * damage contribution tracking (for fair, individual rewards)
	Health is replicated through model attributes for client health bars.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Util.Signal)
local CombatCore = require(script.Parent.Parent.Core.CombatCore)

local EntityService = {
	Died = Signal.new(), -- (entity, killerPlayer?)
	Damaged = Signal.new(), -- (entity, player, amount, info)
}

local entities = {} -- [id] = entity
local byModel = {} -- [Model] = entity
local nextId = 0

function EntityService.Init(_services) end
function EntityService.Start() end

--[[
	spec = { Kind, Model, Root, Humanoid?, Name, Level?, MaxHealth, Poise, Defense, Radius,
	         Def?, OnDeath?, Parent?, Encounter?, BaseDamage?, NoRewards? }
]]
function EntityService.Register(spec)
	nextId += 1
	local e = spec
	e.Id = nextId
	e.Target = CombatCore.newTarget(spec.MaxHealth, spec.Poise or 50)
	e.Contributors = {}
	e.DamageMultiplier = spec.DamageMultiplier or 1
	e.Alive = true
	e.Radius = spec.Radius or 2
	entities[e.Id] = e
	if e.Model then
		byModel[e.Model] = e
		e.Model:SetAttribute("EntityId", e.Id)
		e.Model:SetAttribute("DisplayName", spec.Name)
		e.Model:SetAttribute("Level", spec.Level or 1)
		e.Model:SetAttribute("Kind", spec.Kind)
		CollectionService:AddTag(e.Model, "Entity")
		EntityService.PushHealth(e)
	end
	return e
end

function EntityService.Unregister(e)
	if not e then
		return
	end
	entities[e.Id] = nil
	if e.Model then
		byModel[e.Model] = nil
		CollectionService:RemoveTag(e.Model, "Entity")
	end
	e.Alive = false
end

function EntityService.FromModel(model: Instance)
	return byModel[model]
end

function EntityService.All()
	return entities
end

function EntityService.PushHealth(e)
	if e.Model and e.Model.Parent then
		e.Model:SetAttribute("Health", math.floor(e.Target.Health))
		e.Model:SetAttribute("MaxHealth", e.Target.MaxHealth)
	end
end

function EntityService.Position(e): Vector3?
	local root = e.Root
	if root and root.Parent then
		return root.Position
	end
	return nil
end

-- Entities whose position is within `radius` (+ entity radius) of `pos` (XZ plane, with vertical limit).
function EntityService.Near(pos: Vector3, radius: number, verticalLimit: number?)
	local out = {}
	local vlim = verticalLimit or 30
	for _, e in entities do
		if e.Alive and not e.Target.Dead then
			local p = EntityService.Position(e)
			if p then
				local dx, dz = p.X - pos.X, p.Z - pos.Z
				if math.sqrt(dx * dx + dz * dz) <= radius + e.Radius and math.abs(p.Y - pos.Y) <= vlim + (e.Model and e.Model:GetAttribute("Height") or 0) then
					table.insert(out, e)
				end
			end
		end
	end
	return out
end

--[[
	Applies damage from a player (or nil for environmental).
	info = { Poise, Status = {...}, Crit, Kind = "Melee"|"Projectile"|"Ability", DamageType }
	Returns { Damage, Died, Staggered, Countered, Blocked }
]]
function EntityService.Damage(e, amount: number, player: Player?, info)
	info = info or {}
	local result = { Damage = 0, Died = false, Staggered = false, Countered = false }
	if not e or not e.Alive or e.Target.Dead then
		return result
	end
	local now = workspace:GetServerTimeNow()

	-- weak points forward to their parent
	if e.Parent then
		local parent = e.Parent
		local fwd = EntityService.Damage(parent, amount * (e.WeakMultiplier or 1.5) / math.max(0.01, parent.DamageMultiplier), player, info)
		fwd.WeakPoint = true
		return fwd
	end

	if e.Invulnerable then
		return result
	end
	local mult = e.DamageMultiplier or 1
	if e.ArmorUp then
		mult *= 1 - (e.ArmorReduction or 0.5)
	end
	if e.CounterStance and now < e.CounterStance.Until and not e.CounterStance.Fired then
		mult *= 1 - (e.CounterStance.Reduction or 0.85)
		e.CounterStance.Fired = true
		result.Countered = true
		if e.CounterStance.OnCounter then
			task.spawn(e.CounterStance.OnCounter, player)
		end
	end
	if e.Airborne and info.Kind == "Melee" then
		return result -- out of reach while flying
	end

	local dmg = math.max(1, math.floor(amount * mult + 0.5))
	local poise = (info.Poise or 0) * (if e.ArmorUp then 1.4 else 1)
	local r = CombatCore.damageTarget(e.Target, dmg, poise, now)
	result.Damage, result.Died, result.Staggered = r.Damage, r.Died, r.Staggered

	-- status build-up
	if info.Status and not r.Died then
		for kind, buildup in info.Status do
			if CombatCore.addBuildup(e.Target.Status, kind, buildup, now) then
				if kind == "Bleed" then
					local frac = CombatCore.bleedFraction(if e.Kind == "Boss" then "Boss" else "Enemy")
					local extra = CombatCore.damageTarget(e.Target, math.floor(e.Target.MaxHealth * frac), 0, now)
					result.Damage += extra.Damage
					result.Died = result.Died or extra.Died
				end
				result.Proc = kind
			end
		end
	end

	if player then
		e.Contributors[player.UserId] = (e.Contributors[player.UserId] or 0) + result.Damage
	end
	EntityService.PushHealth(e)
	if e.OnDamaged then
		task.spawn(e.OnDamaged, e, player, result, info)
	end
	EntityService.Damaged:Fire(e, player, result.Damage, info)
	if result.Died then
		EntityService.Kill(e, player)
	end
	return result
end

function EntityService.Kill(e, killer: Player?)
	if not e.Alive then
		return
	end
	e.Target.Dead = true
	e.Target.Health = 0
	EntityService.PushHealth(e)
	EntityService.Unregister(e)
	if e.OnDeath then
		task.spawn(e.OnDeath, e, killer)
	end
	EntityService.Died:Fire(e, killer)
end

-- Status damage-over-time for entities.
function EntityService.TickStatus(e, dt: number, now: number)
	if not e.Alive then
		return
	end
	local frac = CombatCore.tickStatus(e.Target.Status, dt, now, if e.Kind == "Boss" then "Boss" else "Enemy")
	if frac > 0 then
		local r = CombatCore.damageTarget(e.Target, math.max(1, math.floor(e.Target.MaxHealth * frac)), 0, now)
		EntityService.PushHealth(e)
		if r.Died then
			-- credit the top contributor
			local best, bestDmg = nil, 0
			for uid, d in e.Contributors do
				if d > bestDmg then
					best, bestDmg = uid, d
				end
			end
			EntityService.Kill(e, best and game:GetService("Players"):GetPlayerByUserId(best) or nil)
		end
	end
	CombatCore.regenTargetPoise(e.Target, dt, now)
end

return EntityService
