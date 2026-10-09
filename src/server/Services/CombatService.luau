--[[
	CombatService
	Server-authoritative combat. Clients send *intents* through the Action remote
	({ Kind = "Light" | "Heavy" | "Dodge" | "Parry" | "Block" | "Sprint" | "Ability" | "Flask" | "Item" }).
	The server validates state, timing, stamina/mana, ownership and cooldowns; computes all
	damage itself; and resolves hits using server positions. Clients never send damage numbers.

	Hostile hits are applied after LatencyGrace (see CombatCore) so a dodge/parry that left the
	client in time still counts.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local WeaponTypes = require(Shared.Config.WeaponTypes)
local Abilities = require(Shared.Config.Abilities)
local Items = require(Shared.Config.Items)
local Formulas = require(Shared.Logic.Formulas)
local Geometry = require(Shared.Logic.Geometry)
local Net = require(Shared.Net)
local CombatCore = require(script.Parent.Parent.Core.CombatCore)
local InventoryCore = require(script.Parent.Parent.Core.InventoryCore)
local AchievementCore = require(script.Parent.Parent.Core.AchievementCore)

local C = GameConfig.Combat

local CombatService = {}

local S
local fx: RemoteEvent
local buckets = {}

local function now()
	return workspace:GetServerTimeNow()
end

function CombatService.Init(services)
	S = services
	fx = Net.event("Fx")
end

-- Token bucket: true if the player may perform another request.
local function allow(player: Player): boolean
	local b = buckets[player]
	local t = os.clock()
	if not b then
		b = { Tokens = GameConfig.Interaction.MaxRemoteRate, Last = t }
		buckets[player] = b
	end
	b.Tokens = math.min(GameConfig.Interaction.MaxRemoteRate, b.Tokens + (t - b.Last) * GameConfig.Interaction.MaxRemoteRate)
	b.Last = t
	if b.Tokens < 1 then
		return false
	end
	b.Tokens -= 1
	return true
end
CombatService.Allow = allow

local function validVector(v): boolean
	return typeof(v) == "Vector3" and v.X == v.X and v.Y == v.Y and v.Z == v.Z and v.Magnitude > 0.01 and v.Magnitude < 1e4
end

local function inPvp(rt): boolean
	return rt.Region == "pvp"
end

local function playSlash(rt, heavy: boolean)
	local char = rt.Character
	local tool = char and char:FindFirstChildOfClass("Tool")
	if tool then
		local anim = Instance.new("StringValue")
		anim.Name = "toolanim"
		anim.Value = if heavy then "Lunge" else "Slash"
		anim.Parent = tool
		game:GetService("Debris"):AddItem(anim, 0.5)
	end
end

function CombatService.SendFx(player: Player, payload)
	fx:FireClient(player, payload)
end

local function fxNear(position: Vector3, payload, radius: number)
	for _, plr in Players:GetPlayers() do
		local rt = S.PlayerStateService.Get(plr)
		if rt and rt.Root and (rt.Root.Position - position).Magnitude <= radius then
			fx:FireClient(plr, payload)
		end
	end
end
CombatService.FxNear = fxNear

-- ===================================================================== Outgoing damage
local function critFor(rt, e, attackerPos: Vector3, wtype): (number, string?)
	local bonus = (wtype.CritBonus or 0) + (rt.Stats.Bonuses.CritDamage or 0)
	local t = now()
	if CombatCore.isStaggered(e.Target, t) then
		return C.RiposteMultiplier + bonus, "Riposte"
	end
	if t < (rt.Combat.CritUntil or 0) then
		rt.Combat.CritUntil = 0
		return 1.5 + bonus, "Critical"
	end
	if e.Kind ~= "Boss" and e.Parent == nil and e.Root and e.Root.Parent then
		local look = e.Root.CFrame.LookVector
		local tp = e.Root.Position
		if Geometry.isBehind(tp.X, tp.Z, look.X, look.Z, attackerPos.X, attackerPos.Z, C.BackstabAngle) then
			return C.BackstabMultiplier + bonus, "Backstab"
		end
	end
	return 1, nil
end

local function statusFor(rt, base)
	local mult = 1 + Formulas.statusBonus(rt.Stats.Attributes.Arcane) + (rt.Stats.Bonuses.StatusBuildup or 0)
	local out = nil
	if base then
		out = {}
		for k, v in base do
			out[k] = v * mult
		end
	end
	local venom = CombatCore.buffAmount(rt.Combat, "Poison", now())
	if venom > 0 then
		out = out or {}
		out.Poison = (out.Poison or 0) + venom * mult
	end
	return out
end

local function damageOpts(rt, damageType: string)
	local t = now()
	local buff = CombatCore.buffAmount(rt.Combat, "Damage", t) + CombatCore.buffAmount(rt.Combat, "FireCoat", t)
	return {
		DamageBuff = buff,
		TypeBonus = rt.Stats.Bonuses[damageType .. "Damage"] or 0,
	}
end

-- Applies `motion`-scaled damage from `player` to entity `e`.
function CombatService.HitEntity(player: Player, rt, e, power: number, motion: number, poise: number, damageType: string, statusBase, kind: string)
	if not CombatService.CanHit(rt, e) then
		return { Damage = 0, Died = false, Staggered = false, Countered = false }
	end
	local pos = rt.Root.Position
	local wtype = WeaponTypes[rt.Stats.WeaponType] or WeaponTypes.Fist
	local critMult, critKind = 1, nil
	if kind == "Melee" then
		critMult, critKind = critFor(rt, e, pos, wtype)
	end
	local opts = damageOpts(rt, damageType)
	opts.CritMult = critMult
	opts.TargetDefense = e.Defense or 0
	local dmg = CombatCore.outgoing(power, motion, opts)
	local result = S.EntityService.Damage(e, dmg, player, {
		Poise = poise * (if critKind then 1.5 else 1),
		Status = statusFor(rt, statusBase),
		Kind = kind,
		DamageType = damageType,
		Crit = critKind,
	})
	if result.Damage > 0 or result.Countered then
		local epos = S.EntityService.Position(e) or pos
		fx:FireClient(player, {
			Type = "Damage",
			Position = epos + Vector3.new(0, 3, 0),
			Amount = result.Damage,
			Crit = critKind,
			Proc = result.Proc,
			WeakPoint = result.WeakPoint,
			Countered = result.Countered,
		})
		if rt.Encounter and S.BossService then
			S.BossService.RecordDamage(player, result.Damage)
		end
	end
	return result
end

-- Entities that belong to a boss encounter can only be hit by that encounter's participants;
-- entities owned by a player (sparring partner) only by that player.
function CombatService.CanHit(rt, e): boolean
	local root = e.Parent or e
	-- no attacking world enemies from inside safe zones (hub snipe protection)
	if rt.Player and rt.Player:GetAttribute("Safe") and root.Encounter == nil and root.Owner == nil and root.Kind ~= "Dummy" then
		return false
	end
	if root.Encounter ~= nil and rt.Encounter ~= root.Encounter then
		return false
	end
	if root.Owner ~= nil and root.Owner ~= rt.Player then
		return false
	end
	return true
end

local function pvpTargets(rt)
	local out = {}
	if not inPvp(rt) then
		return out
	end
	for _, plr in Players:GetPlayers() do
		local other = S.PlayerStateService.Get(plr)
		if other and other ~= rt and inPvp(other) and other.Root and other.Combat and not other.Combat.Dead then
			table.insert(out, plr)
		end
	end
	return out
end

local function hitPlayerPvp(attacker: Player, rt, victim: Player, power: number, motion: number, poise: number, damageType: string)
	local vrt = S.PlayerStateService.Get(victim)
	if not vrt or not vrt.Combat or vrt.Combat.Dead or not inPvp(vrt) or not inPvp(rt) then
		return
	end
	local opts = damageOpts(rt, damageType)
	opts.Pvp = true
	local raw = CombatCore.outgoing(power, motion, opts)
	CombatService.QueueHostileHit(victim, {
		Damage = raw, DamageType = damageType, Poise = poise, Parryable = true, Blockable = true,
		PvpAttacker = attacker,
	}, rt.Root.Position)
end

local function meleeSweep(player: Player, rt, range: number, arc: number, power: number, motion: number, poise: number, damageType: string, statusBase)
	local root = rt.Root
	local pos = root.Position
	local look = root.CFrame.LookVector
	local candidates = S.EntityService.Near(pos, range + C.MaxReachTolerance, 10)
	-- one hit per root entity per swing: a weak point (best multiplier) replaces its parent body
	local best = {} -- [rootEntity] = entity to hit
	local order = {}
	for _, e in candidates do
		local ep = S.EntityService.Position(e)
		if ep and CombatService.CanHit(rt, e) and Geometry.inCone(pos.X, pos.Z, look.X, look.Z, ep.X, ep.Z, range, arc, e.Radius) then
			local rootEntity = e.Parent or e
			local cur = best[rootEntity]
			if cur == nil then
				table.insert(order, rootEntity)
				best[rootEntity] = e
			elseif e.Parent and (cur == rootEntity or (e.WeakMultiplier or 0) > (cur.WeakMultiplier or 0)) then
				best[rootEntity] = e
			end
		end
	end
	local count = 0
	for _, rootEntity in order do
		if count < C.MaxHitsPerSwing then
			count += 1
			CombatService.HitEntity(player, rt, best[rootEntity], power, motion, poise, damageType, statusBase, "Melee")
		end
	end
	for _, victim in pvpTargets(rt) do
		local vrt = S.PlayerStateService.Get(victim)
		local vp = vrt.Root.Position
		if Geometry.inCone(pos.X, pos.Z, look.X, look.Z, vp.X, vp.Z, range, arc, 1.5) and math.abs(vp.Y - pos.Y) < 8 then
			hitPlayerPvp(player, rt, victim, power, motion, poise, damageType)
		end
	end
	return count
end

local function fireProjectile(player: Player, rt, aim: Vector3, speed: number, radius: number, range: number, power: number, motion: number, poise: number, damageType: string, statusBase, color: Color3, pierce: boolean?)
	local root = rt.Root
	local dir = if validVector(aim) then aim.Unit else root.CFrame.LookVector
	-- the server only accepts aim within 75 degrees of the character's facing (no shooting backwards)
	local look = root.CFrame.LookVector
	if dir:Dot(look) < math.cos(math.rad(75)) then
		dir = look
	end
	local pvp = pvpTargets(rt)
	S.ProjectileService.Fire({
		Origin = root.Position + look * 2 + Vector3.new(0, 1.5, 0),
		Direction = dir,
		Speed = speed,
		Radius = radius,
		Range = range,
		Color = color,
		Hostile = false,
		Owner = player,
		Pierce = pierce,
		PvpTargets = if #pvp > 0 then pvp else nil,
		OnHit = function(e)
			if rt.Combat and rt.Root and rt.Root.Parent then
				CombatService.HitEntity(player, rt, e, power, motion, poise, damageType, statusBase, "Projectile")
			end
		end,
		OnHitPlayer = function(victim)
			hitPlayerPvp(player, rt, victim, power, motion, poise, damageType)
		end,
	})
end

local DAMAGE_COLORS = {
	Physical = Color3.fromRGB(230, 220, 200),
	Magic = Color3.fromRGB(120, 140, 255),
	Fire = Color3.fromRGB(255, 120, 40),
	Holy = Color3.fromRGB(255, 230, 140),
}

-- ===================================================================== Actions
local function onAttack(player: Player, rt, kind: string, payload)
	local c = rt.Combat
	local stats = rt.Stats
	local t = now()
	-- heavy charge is measured on the server (HeavyStart -> Heavy); client values are ignored
	local charge = if kind == "Heavy" then CombatCore.takeCharge(c, t) else 0
	local ok, info = CombatCore.attack(c, kind, stats.WeaponType, t, charge)
	if not ok then
		return
	end
	local seq = c.AttackSeq or 0
	playSlash(rt, kind == "Heavy")
	local aim = payload.Aim
	task.delay(info.Windup, function()
		if c.Dead or (c.AttackSeq or 0) ~= seq or not rt.Root or not rt.Root.Parent then
			return
		end
		local wt = WeaponTypes[stats.WeaponType] or WeaponTypes.Fist
		local power = stats.AttackRating
		local dtype = stats.WeaponDamageType
		if wt.Ranged then
			fireProjectile(player, rt, aim, wt.ProjectileSpeed, wt.ProjectileRadius * (if kind == "Heavy" then 1.4 else 1), wt.MaxRange,
				power, info.Motion, info.Poise, dtype, stats.WeaponStatus, DAMAGE_COLORS[dtype] or DAMAGE_COLORS.Physical, kind == "Heavy" and wt.Catalyst)
		else
			meleeSweep(player, rt, wt.Range * (if kind == "Heavy" then 1.1 else 1), wt.Arc, power, info.Motion, info.Poise, dtype, stats.WeaponStatus)
		end
	end)
end

local function onDodge(player: Player, rt, payload)
	local ok, info = CombatCore.dodge(rt.Combat, now(), rt.Stats.DodgeCostMult)
	if ok then
		AchievementCore.increment(rt.Profile, "Dodges")
		fx:FireClient(player, { Type = "DodgeOk", IFrames = info.IFrames })
	else
		fx:FireClient(player, { Type = "ActionDenied", Action = "Dodge", Reason = info })
	end
end

local function onParry(player: Player, rt)
	local ok = CombatCore.parry(rt.Combat, now(), rt.Stats.ParryBonus)
	if ok then
		playSlash(rt, false)
	end
end

local function onBlock(player: Player, rt, payload)
	CombatCore.setBlocking(rt.Combat, payload.On == true, now())
	player:SetAttribute("Blocking", rt.Combat.Blocking)
	if rt.Combat.Blocking then
		S.PlayerStateService.SetSprinting(player, false)
	end
end

local function useFlask(player: Player, rt)
	local c = rt.Combat
	local t = now()
	local p = rt.Profile
	if p.Flask.Charges <= 0 or not CombatCore.canAct(c, t, 0.05) then
		return
	end
	if t < (c.Cooldowns.Flask or 0) then
		return
	end
	p.Flask.Charges -= 1
	c.Cooldowns.Flask = t + GameConfig.Flask.Cooldown
	c.ActionLockUntil = t + GameConfig.Flask.UseTime
	-- committed until the heal lands: no dodge-cancelling the drink
	c.DodgeCancelFrom = t + GameConfig.Flask.UseTime * 0.6
	c.Blocking = false
	local amount = math.floor(c.MaxHealth * GameConfig.Flask.HealFraction * (1 + (rt.Stats.Bonuses.HealingPower or 0)))
	-- heal lands at the end of the drinking animation (punishable, like the genre)
	task.delay(GameConfig.Flask.UseTime * 0.6, function()
		if not c.Dead and rt.Combat == c and c.LastDodge < t then
			CombatCore.heal(c, amount)
			S.PlayerStateService.PushVitals(player)
			fx:FireClient(player, { Type = "Heal", Amount = amount })
		end
	end)
	S.PlayerStateService.PushVitals(player)
end

local function useItem(player: Player, rt, itemId)
	if type(itemId) ~= "string" then
		return
	end
	local def = Items[itemId]
	if not def or def.Kind ~= "Consumable" or not def.Effect then
		return
	end
	local c = rt.Combat
	local t = now()
	if not CombatCore.canAct(c, t, 0.05) or t < (c.Cooldowns.Item or 0) or t < (c.Cooldowns[itemId] or 0) then
		return
	end
	local effect = def.Effect
	if effect.Type == "FlaskUpgrade" then
		if rt.Profile.Flask.MaxCharges >= GameConfig.Flask.MaxCharges then
			S.NotifyService.Toast(player, "Your Ember Flask cannot hold more charges.", "Warning")
			return
		end
	end
	if not InventoryCore.removeStack(rt.Profile, itemId, 1) then
		return
	end
	c.Cooldowns.Item = t + GameConfig.Consumables.SharedCooldown
	c.Cooldowns[itemId] = t + (effect.Cooldown or 0)
	c.ActionLockUntil = t + 0.6
	if effect.Type == "Heal" then
		CombatCore.heal(c, c.MaxHealth * effect.Fraction)
	elseif effect.Type == "Mana" then
		c.Mana = math.min(c.MaxMana, c.Mana + c.MaxMana * effect.Fraction)
	elseif effect.Type == "Buff" then
		CombatCore.addBuff(c, effect.Buff, effect.Amount, effect.Duration, t)
		fx:FireClient(player, { Type = "Buff", Buff = effect.Buff, Duration = effect.Duration })
	elseif effect.Type == "Cure" then
		CombatCore.cureStatus(c.Status, effect.Status)
	elseif effect.Type == "FlaskUpgrade" then
		rt.Profile.Flask.MaxCharges += 1
		rt.Profile.Flask.Charges = math.min(rt.Profile.Flask.Charges + 1, rt.Profile.Flask.MaxCharges)
		S.NotifyService.Toast(player, ("Ember Flask strengthened: %d charges."):format(rt.Profile.Flask.MaxCharges), "Reward")
	end
	S.PlayerStateService.PushVitals(player)
	S.PlayerStateService.Sync(player)
end

local function onAbility(player: Player, rt, payload)
	local slot = payload.Slot
	if slot ~= "Slot1" and slot ~= "Slot2" then
		return
	end
	local id = rt.Profile.Abilities[slot]
	local def = id and Abilities[id]
	if not def or not rt.Profile.Abilities.Unlocked[id] then
		return
	end
	local c = rt.Combat
	local t = now()
	if not CombatCore.canAct(c, t, 0.05) then
		return
	end
	if t < (c.Cooldowns[id] or 0) then
		fx:FireClient(player, { Type = "ActionDenied", Action = "Ability", Reason = "Cooldown" })
		return
	end
	if c.Mana < (def.Mana or 0) then
		fx:FireClient(player, { Type = "ActionDenied", Action = "Ability", Reason = "NoMana" })
		return
	end
	if (def.Stamina or 0) > 0 and c.Stamina <= 0 then
		fx:FireClient(player, { Type = "ActionDenied", Action = "Ability", Reason = "NoStamina" })
		return
	end
	-- ShadowStep needs a valid target before paying costs
	local target
	if def.Type == "ShadowStep" then
		local entityId = payload.TargetId
		for _, e in S.EntityService.All() do
			if e.Id == entityId and e.Parent == nil and e.Kind ~= "Dummy" and CombatService.CanHit(rt, e) then
				target = e
			end
		end
		local tp = target and S.EntityService.Position(target)
		if not tp or (tp - rt.Root.Position).Magnitude > def.Range + C.MaxReachTolerance then
			fx:FireClient(player, { Type = "ActionDenied", Action = "Ability", Reason = "NoTarget" })
			return
		end
	end
	c.Mana -= def.Mana or 0
	if (def.Stamina or 0) > 0 then
		CombatCore.spendStamina(c, def.Stamina, t)
	end
	c.Cooldowns[id] = t + def.Cooldown
	local windup = def.Windup or 0.2
	c.ActionLockUntil = t + windup + 0.25
	c.DodgeCancelFrom = t + windup
	c.Blocking = false
	fx:FireClient(player, { Type = "AbilityCast", Ability = id, Windup = windup, Cooldown = def.Cooldown })
	playSlash(rt, true)
	local seq = c.AttackSeq or 0
	local attrs = rt.Stats.Attributes
	local power = Formulas.abilityPower(def, attrs, rt.Profile.Level)

	if def.Type == "Buff" then
		CombatCore.addBuff(c, def.Buff, def.Amount, def.Duration, t)
		if def.Poise then
			CombatCore.addBuff(c, "Poise", def.Poise, def.Duration, t)
		end
		fx:FireClient(player, { Type = "Buff", Buff = def.Buff, Duration = def.Duration })
		return
	elseif def.Type == "ShadowStep" then
		local tp = S.EntityService.Position(target)
		if tp and target.Root then
			local behind = tp - target.Root.CFrame.LookVector * (target.Radius + 3)
			S.AntiCheatService.AllowTeleport(player)
			rt.Character:PivotTo(CFrame.lookAt(Vector3.new(behind.X, rt.Root.Position.Y, behind.Z), Vector3.new(tp.X, rt.Root.Position.Y, tp.Z)))
			c.CritUntil = t + def.CritDuration
			fxNear(rt.Root.Position, { Type = "Blink", Position = rt.Root.Position }, 120)
		end
		return
	end

	task.delay(windup, function()
		if c.Dead or (c.AttackSeq or 0) ~= seq or not rt.Root or not rt.Root.Parent then
			return
		end
		local root = rt.Root
		local pos = root.Position
		local look = root.CFrame.LookVector
		local dtype = def.DamageType
		local poise = def.Poise or 20
		local function applySlow(e)
			if def.Slow then
				e.Target.SlowUntil = now() + def.Slow.Duration
				e.Target.SlowAmount = def.Slow.Amount
			end
		end
		if def.Type == "Heal" then
			local amount = Formulas.healAmount(def, attrs, c.MaxHealth, rt.Stats.Bonuses.HealingPower)
			CombatCore.heal(c, amount)
			fx:FireClient(player, { Type = "Heal", Amount = amount })
			-- allies = party members (never opponents in the PvP pit)
			for _, plr in S.PartyService.Members(player) do
				local ort = S.PlayerStateService.Get(plr)
				if ort and ort ~= rt and ort.Root and ort.Combat and not ort.Combat.Dead and (ort.Root.Position - pos).Magnitude <= def.AllyRadius then
					local a = math.floor(ort.Combat.MaxHealth * (amount / c.MaxHealth) * def.AllyFraction)
					CombatCore.heal(ort.Combat, a)
					S.PlayerStateService.PushVitals(plr)
					fx:FireClient(plr, { Type = "Heal", Amount = a, From = player.Name })
				end
			end
			fxNear(pos, { Type = "AbilityFx", Ability = id, Position = pos, Radius = def.AllyRadius }, 150)
			S.PlayerStateService.PushVitals(player)
		elseif def.Type == "Projectile" then
			fireProjectile(player, rt, payload.Aim, def.Speed, def.Radius, def.Range, power, 1, poise, dtype, def.Status, DAMAGE_COLORS[dtype] or DAMAGE_COLORS.Physical)
		elseif def.Type == "Circle" then
			fxNear(pos, { Type = "AbilityFx", Ability = id, Position = pos, Radius = def.Radius }, 150)
			for _, e in S.EntityService.Near(pos, def.Radius, 10) do
				if not e.Parent then
					CombatService.HitEntity(player, rt, e, power, 1, poise, dtype, def.Status, "Ability")
					applySlow(e)
				end
			end
			for _, victim in pvpTargets(rt) do
				local vrt = S.PlayerStateService.Get(victim)
				if (vrt.Root.Position - pos).Magnitude <= def.Radius then
					hitPlayerPvp(player, rt, victim, power, 1, poise, dtype)
				end
			end
		elseif def.Type == "Cone" or def.Type == "Line" then
			if def.Dash then
				fx:FireClient(player, { Type = "Dash", Distance = def.Length })
			end
			fxNear(pos, { Type = "AbilityFx", Ability = id, Position = pos, Direction = look, Length = def.Length or def.Range, Width = def.Width, Arc = def.Arc }, 150)
			for _, e in S.EntityService.Near(pos, (def.Length or def.Range) + 2, 12) do
				local ep = S.EntityService.Position(e)
				local inside = if def.Type == "Cone"
					then Geometry.inCone(pos.X, pos.Z, look.X, look.Z, ep.X, ep.Z, def.Range, def.Arc, e.Radius)
					else Geometry.inLine(pos.X, pos.Z, look.X, look.Z, ep.X, ep.Z, def.Length, def.Width, e.Radius)
				if inside and not e.Parent then
					CombatService.HitEntity(player, rt, e, power, 1, poise, dtype, def.Status, "Ability")
					applySlow(e)
				end
			end
		end
	end)
end

local function onAction(player: Player, payload)
	if type(payload) ~= "table" or type(payload.Kind) ~= "string" then
		return
	end
	if not allow(player) then
		return
	end
	local rt = S.PlayerStateService.Get(player)
	if not rt or not rt.Combat or not rt.Root or rt.Combat.Dead or rt.Profile.Class == "" then
		return
	end
	local kind = payload.Kind
	if kind == "Light" or kind == "Heavy" then
		onAttack(player, rt, kind, payload)
	elseif kind == "HeavyStart" then
		CombatCore.beginCharge(rt.Combat, workspace:GetServerTimeNow())
	elseif kind == "Dodge" then
		onDodge(player, rt, payload)
	elseif kind == "Parry" then
		onParry(player, rt)
	elseif kind == "Block" then
		onBlock(player, rt, payload)
	elseif kind == "Sprint" then
		S.PlayerStateService.SetSprinting(player, payload.On == true)
	elseif kind == "Ability" then
		onAbility(player, rt, payload)
	elseif kind == "Flask" then
		useFlask(player, rt)
	elseif kind == "Item" then
		useItem(player, rt, payload.ItemId)
	elseif kind == "Rep" then
		if S.TrainingService then
			S.TrainingService.OnRep(player)
		end
	end
end

-- ===================================================================== Incoming hostile hits
--[[
	spec = { Damage, DamageType, Poise, Parryable, Blockable, Status, Attacker?, PvpAttacker?, Tick? }
	sourcePos = where the hit came from (for block/parry facing)
]]
function CombatService.QueueHostileHit(player: Player, spec, sourcePos: Vector3)
	local hitTime = now()
	task.delay(C.LatencyGrace, function()
		local rt = S.PlayerStateService.Get(player)
		if not rt or not rt.Combat or not rt.Root or not rt.Root.Parent then
			return
		end
		local c = rt.Combat
		local root = rt.Root
		local toSource = Vector3.new(sourcePos.X - root.Position.X, 0, sourcePos.Z - root.Position.Z)
		local look = root.CFrame.LookVector
		local facing = toSource.Magnitude < 0.5
			or Geometry.angleTo(0, 0, look.X, look.Z, toSource.X, toSource.Z) <= C.BlockAngle / 2
		local wasSeq = c.AttackSeq or 0
		local r = CombatCore.resolveIncoming(c, spec, hitTime, rt.Stats, facing)
		if r.Staggered or r.GuardBroken or r.Died then
			c.AttackSeq = wasSeq + 1 -- cancels any pending swing
		end
		if r.Outcome == "Ignored" or r.Outcome == "Immune" then
			return
		end
		if spec.Attacker and spec.Attacker.OnHitPlayer then
			task.spawn(spec.Attacker.OnHitPlayer, player, r.Outcome)
		end
		if r.Outcome == "Parried" then
			AchievementCore.increment(rt.Profile, "Parries")
			CombatService.OnParried(player, spec)
			fxNear(root.Position, { Type = "Parry", Position = root.Position + look * 2 }, 120)
			return
		elseif r.Outcome == "Dodged" then
			fx:FireClient(player, { Type = "Dodged" })
			return
		end
		if r.Damage > 0 and rt.Encounter and S.BossService then
			S.BossService.RecordHitTaken(player)
		end
		S.PlayerStateService.PushVitals(player)
		fx:FireClient(player, {
			Type = "Hurt",
			Amount = r.Damage,
			Outcome = r.Outcome,
			Staggered = r.Staggered,
			GuardBroken = r.GuardBroken,
			Procs = r.StatusProcs,
			Source = sourcePos,
		})
		player:SetAttribute("Blocking", c.Blocking)
		for _, proc in r.StatusProcs do
			if proc == "Bleed" then
				CombatCore.applyDamage(c, math.floor(c.MaxHealth * CombatCore.bleedFraction("Player")))
				S.PlayerStateService.PushVitals(player)
			end
		end
		if c.Dead then
			local killer = spec.PvpAttacker
			if killer then
				local krt = S.PlayerStateService.Get(killer)
				if krt then
					AchievementCore.increment(krt.Profile, "PvPWins")
				end
			end
			S.DeathService.OnPlayerDeath(player, if killer then "PvP" else "Combat")
		end
	end)
end

-- A parried attacker is staggered (non-bosses) or loses a big chunk of poise (bosses).
function CombatService.OnParried(player: Player, spec)
	local attacker = spec.Attacker
	if spec.PvpAttacker then
		local art = S.PlayerStateService.Get(spec.PvpAttacker)
		if art and art.Combat then
			local t = now()
			art.Combat.StaggeredUntil = t + C.StaggerDuration * 2
			art.Combat.ActionLockUntil = math.max(art.Combat.ActionLockUntil, art.Combat.StaggeredUntil)
			art.Combat.AttackSeq = (art.Combat.AttackSeq or 0) + 1
			fx:FireClient(spec.PvpAttacker, { Type = "Hurt", Amount = 0, Staggered = true, Outcome = "Parried" })
		end
		return
	end
	if not attacker or not attacker.Entity then
		return
	end
	local e = attacker.Entity
	local t = now()
	if e.Kind == "Boss" then
		local reward = attacker.ParryReward or 1
		local r = CombatCore.damageTarget(e.Target, 0, e.Target.MaxPoise * 0.34 * reward, t)
		if r.Staggered then
			fxNear(S.EntityService.Position(e) or Vector3.zero, { Type = "Stagger", EntityId = e.Id }, 200)
		end
	else
		e.Target.StaggeredUntil = t + C.EnemyStaggerDuration
		fxNear(S.EntityService.Position(e) or Vector3.zero, { Type = "Stagger", EntityId = e.Id }, 200)
	end
end

function CombatService.UseItemFromMenu(player: Player, itemId)
	local rt = S.PlayerStateService.Get(player)
	if rt and rt.Combat and not rt.Combat.Dead and rt.Profile.Class ~= "" then
		useItem(player, rt, itemId)
	end
end

function CombatService.Start()
	Net.event("Action").OnServerEvent:Connect(onAction)
	Players.PlayerRemoving:Connect(function(p)
		buckets[p] = nil
	end)
end

return CombatService
