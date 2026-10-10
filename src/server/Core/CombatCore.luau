--[[
	CombatCore
	Pure combat state machine for players and NPC targets. All timing uses a `now` argument
	(server clock) so behaviour is deterministic and testable.

	Latency handling ("grace window"): a hostile hit that resolves at time T is applied at
	T + LatencyGrace. A dodge registered in [T - IFrames, T + grace] or a parry registered in
	[T - ParryWindow, T + grace] still counts. This forgives a client whose input left in time
	but arrived slightly late, without granting extra invulnerability on the server.

	Anti stun-lock: after a stagger the player is immune to further staggers for
	StaggerDuration + StaggerImmunity seconds (damage still applies).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local WeaponTypes = require(Shared.Config.WeaponTypes)
local Formulas = require(Shared.Logic.Formulas)
local Catalyst = require(Shared.Logic.Catalyst)

local C = GameConfig.Combat
local NEG = -1e9

local CombatCore = {}

-- ===================================================================== Player state
function CombatCore.newPlayerState(stats, now: number)
	return {
		Health = stats.MaxHealth,
		MaxHealth = stats.MaxHealth,
		Stamina = stats.MaxStamina,
		MaxStamina = stats.MaxStamina,
		Mana = stats.MaxMana,
		MaxMana = stats.MaxMana,
		LastStaminaSpend = NEG,
		ActionLockUntil = 0,
		DodgeCancelFrom = 0,
		ComboIndex = 0,
		LastAttackEnd = NEG,
		LastDodge = NEG,
		LastParry = NEG,
		ParryWindow = C.ParryWindow,
		Blocking = false,
		StaggeredUntil = 0,
		StaggerImmuneUntil = 0,
		InvulnerableUntil = now + GameConfig.Death.RespawnInvulnerability,
		LastDamagedAt = NEG,
		Dead = false,
		Buffs = {},
		Cooldowns = {},
		CritUntil = 0,
		AttackSeq = 0, -- incremented when a stagger/death cancels pending swings
		Status = CombatCore.newStatus(),
	}
end

-- Re-apply max values after equipment/attribute changes, keeping current ratios.
function CombatCore.refreshMax(state, stats)
	local hpRatio = if state.MaxHealth > 0 then state.Health / state.MaxHealth else 1
	state.MaxHealth = stats.MaxHealth
	state.Health = math.clamp(math.floor(stats.MaxHealth * hpRatio + 0.5), if state.Dead then 0 else 1, stats.MaxHealth)
	state.MaxStamina = stats.MaxStamina
	state.Stamina = math.min(state.Stamina, stats.MaxStamina)
	state.MaxMana = stats.MaxMana
	state.Mana = math.min(state.Mana, stats.MaxMana)
end

function CombatCore.buffAmount(state, name: string, now: number): number
	local b = state.Buffs[name]
	if b and now < b.Expires then
		return b.Amount
	end
	return 0
end

function CombatCore.addBuff(state, name: string, amount: number, duration: number, now: number)
	state.Buffs[name] = { Amount = amount, Expires = now + duration }
end

function CombatCore.regen(state, dt: number, now: number, stats)
	if state.Dead then
		return
	end
	if now - state.LastStaminaSpend >= GameConfig.Stamina.RegenDelay and state.Stamina < state.MaxStamina then
		local rate = (stats.StaminaRegen or GameConfig.Stamina.RegenPerSecond) * (1 + CombatCore.buffAmount(state, "StaminaRegen", now))
		if state.Blocking then
			rate *= GameConfig.Stamina.BlockingRegenMultiplier
		end
		state.Stamina = math.min(state.MaxStamina, state.Stamina + rate * dt)
	end
	if state.Mana < state.MaxMana then
		state.Mana = math.min(state.MaxMana, state.Mana + GameConfig.Mana.RegenPerSecond * dt)
	end
end

function CombatCore.canAct(state, now: number, tolerance: number?): boolean
	local tol = tolerance or 0
	return not state.Dead and now + tol >= state.ActionLockUntil and now >= state.StaggeredUntil
end

function CombatCore.spendStamina(state, cost: number, now: number): boolean
	if state.Stamina <= GameConfig.Stamina.ExhaustedThreshold then
		return false
	end
	state.Stamina = math.max(0, state.Stamina - cost)
	state.LastStaminaSpend = now
	return true
end

-- kind = "Light" | "Heavy". charge = seconds the heavy was held (client-reported, clamped).
function CombatCore.attack(state, kind: string, weaponType: string, now: number, charge: number?)
	if kind ~= "Light" and kind ~= "Heavy" then
		return false, "InvalidKind"
	end
	if not CombatCore.canAct(state, now, 0.08) then
		return false, "Busy"
	end
	local wt = WeaponTypes[weaponType] or WeaponTypes.Fist
	if state.Stamina <= GameConfig.Stamina.ExhaustedThreshold then
		return false, "NoStamina"
	end
	local chained = kind == "Light" and now - state.LastAttackEnd <= 0.7 and state.ComboIndex > 0
	-- catalysts cast a spell per step, or fall back to mana-free strikes (shared with the client)
	local choice = Catalyst.choose(wt, kind, state.ComboIndex, chained, state.ComboMode, state.Mana)
	if choice.ManaCost > state.Mana then
		return false, "NoMana"
	end
	local mode, move, manaCost = choice.Mode, choice.Move, choice.ManaCost
	state.ComboMode = mode
	state.ComboIndex = choice.Combo
	local cost = (if kind == "Light" then C.LightAttackCost else C.HeavyAttackCost) * (wt.StaminaMult or 1)
	local motion
	if kind == "Light" then
		motion = move.Motion[state.ComboIndex]
	else
		local c = math.clamp(tonumber(charge) or 0, 0, C.HeavyChargeMax)
		motion = move.Motion * (1 + C.HeavyChargeBonus * (c / C.HeavyChargeMax))
	end
	local spell, name = choice.Spell, choice.Name
	CombatCore.spendStamina(state, cost, now)
	state.Mana -= manaCost
	state.Blocking = false
	local windup = move.Windup
	local recovery = move.Recovery
	state.DodgeCancelFrom = now + windup
	state.ActionLockUntil = now + windup + recovery * 0.85
	state.LastAttackEnd = state.ActionLockUntil
	return true, {
		Kind = kind,
		Windup = windup,
		Recovery = recovery,
		Motion = motion,
		Poise = move.Poise,
		StaminaCost = cost,
		ManaCost = manaCost,
		Combo = state.ComboIndex,
		Ranged = wt.Ranged == true and mode ~= "Melee",
		Mode = mode, -- "Weapon" | "Spell" | "Melee" (catalyst out of mana)
		Spell = spell,
		Name = name,
		Range = if mode == "Melee" then (move.Range or wt.Fallback.Range) else nil,
		Arc = if mode == "Melee" then (move.Arc or wt.Fallback.Arc) else nil,
	}
end

-- Heavy charge is timed by the server: begin on press, measured on release.
function CombatCore.beginCharge(state, now: number): boolean
	if not CombatCore.canAct(state, now, 0.08) then
		return false
	end
	state.ChargeStart = now
	return true
end

-- Seconds charged (0 if no valid charge in progress). Consumes the charge.
function CombatCore.takeCharge(state, now: number): number
	local start = state.ChargeStart
	state.ChargeStart = nil
	if not start or now < start or now - start > 4 then
		return 0
	end
	return math.min(now - start, C.HeavyChargeMax)
end

function CombatCore.dodge(state, now: number, costMult: number?)
	if state.Dead or now < state.StaggeredUntil then
		return false, "Busy"
	end
	-- dodging may cancel attack recovery, but not the windup
	if now < state.DodgeCancelFrom then
		return false, "Busy"
	end
	if now - state.LastDodge < C.DodgeCooldown then
		return false, "Cooldown"
	end
	if not CombatCore.spendStamina(state, C.DodgeCost * (costMult or 1), now) then
		return false, "NoStamina"
	end
	state.LastDodge = now
	state.Blocking = false
	state.ChargeStart = nil
	state.ActionLockUntil = math.max(now + 0.35, 0)
	state.LastAttackEnd = NEG
	return true, { IFrames = C.DodgeIFrames }
end

--[[
	Aerial flip (front or back): a dodge performed in the air.
	* Chained: within FlipChainWindow of a dodge (dodge, then jump) the flip extends that dodge
	  for a small extra cost, once per dodge.
	* Fresh: otherwise (double jump, then dodge) it costs a normal dodge and obeys its cooldown.
	Either way it grants a full set of dodge i-frames from the moment of the flip.
]]
function CombatCore.flip(state, now: number, costMult: number?)
	if state.Dead or now < state.StaggeredUntil then
		return false, "Busy"
	end
	if now < state.DodgeCancelFrom then
		return false, "Busy"
	end
	local chained = now - state.LastDodge <= C.FlipChainWindow and state.FlipChainedFrom ~= state.LastDodge
	if not chained and now - state.LastDodge < C.DodgeCooldown then
		return false, "Cooldown"
	end
	local cost = (if chained then C.FlipChainCost else C.DodgeCost) * (costMult or 1)
	if not CombatCore.spendStamina(state, cost, now) then
		return false, "NoStamina"
	end
	state.LastDodge = now
	-- a chained flip consumes the chain; a fresh flip cannot be chained into another flip
	state.FlipChainedFrom = now
	state.Blocking = false
	state.ChargeStart = nil
	state.ActionLockUntil = math.max(state.ActionLockUntil, now + C.FlipLock)
	state.LastAttackEnd = NEG
	return true, { IFrames = C.DodgeIFrames, Chained = chained, StaminaCost = cost }
end

function CombatCore.parry(state, now: number, parryBonus: number?)
	if not CombatCore.canAct(state, now, 0.05) then
		return false, "Busy"
	end
	if now - state.LastParry < C.ParryCooldown then
		return false, "Cooldown"
	end
	if not CombatCore.spendStamina(state, C.ParryStaminaCost, now) then
		return false, "NoStamina"
	end
	state.LastParry = now
	state.ParryWindow = C.ParryWindow + (parryBonus or 0)
	state.Blocking = false
	state.ActionLockUntil = now + 0.4
	return true, { Window = state.ParryWindow }
end

function CombatCore.setBlocking(state, on: boolean, now: number): boolean
	if on then
		if not CombatCore.canAct(state, now, 0.05) or state.Stamina <= 0 then
			return false
		end
		state.Blocking = true
	else
		state.Blocking = false
	end
	return true
end

function CombatCore.dodgeCovers(state, hitTime: number): boolean
	local d = state.LastDodge
	return d >= hitTime - C.DodgeIFrames and d <= hitTime + C.LatencyGrace
end

function CombatCore.parryCovers(state, hitTime: number): boolean
	local p = state.LastParry
	return p >= hitTime - state.ParryWindow and p <= hitTime + C.LatencyGrace
end

-- Damage reduction from armour and defensive buffs.
function CombatCore.mitigate(raw: number, damageType: string, stats, state, now: number): number
	local def = if damageType == "Physical" then stats.Defense else stats.MagicDefense
	local dmg = raw * (1 - Formulas.absorption(def, C.PlayerDefenseK))
	local buffReduction = math.min(0.8, CombatCore.buffAmount(state, "Defense", now))
	dmg *= (1 - buffReduction)
	return math.max(C.MinDamage, math.floor(dmg + 0.5))
end

--[[
	hit = { Damage, DamageType, Poise, Parryable, Blockable, Status = {..}, Unavoidable? }
	facing = true when the attacker is inside the defender's block arc.
	Returns { Outcome, Damage, StaminaDamage, Staggered, GuardBroken, Died, StatusProcs }
	Outcome: Ignored | Immune | Dodged | Parried | Blocked | GuardBroken | Hit
]]
function CombatCore.resolveIncoming(state, hit, hitTime: number, stats, facing: boolean)
	local r = { Outcome = "Hit", Damage = 0, StaminaDamage = 0, Staggered = false, GuardBroken = false, Died = false, StatusProcs = {} }
	if state.Dead then
		r.Outcome = "Ignored"
		return r
	end
	if state.GodMode or hitTime < state.InvulnerableUntil then
		r.Outcome = "Immune"
		return r
	end
	if CombatCore.dodgeCovers(state, hitTime) then
		r.Outcome = "Dodged"
		return r
	end
	if hit.Parryable and facing and CombatCore.parryCovers(state, hitTime) then
		r.Outcome = "Parried"
		return r
	end
	local damage = CombatCore.mitigate(hit.Damage, hit.DamageType or "Physical", stats, state, hitTime)
	if hit.Blockable and state.Blocking and facing then
		local stability = math.clamp(stats.Stability or 0, 0, 100) / 100
		local chip = math.floor(damage * (1 - stability) + 0.5)
		local staminaDamage = math.max(6, (hit.Poise or 20) * 0.8) * (1.5 - stability)
		r.StaminaDamage = staminaDamage
		state.Stamina -= staminaDamage
		state.LastStaminaSpend = hitTime
		if state.Stamina <= 0 then
			state.Stamina = 0
			state.Blocking = false
			r.Outcome = "GuardBroken"
			r.GuardBroken = true
			state.StaggeredUntil = hitTime + C.GuardBreakStun
			state.ActionLockUntil = math.max(state.ActionLockUntil, state.StaggeredUntil)
			state.StaggerImmuneUntil = state.StaggeredUntil + C.StaggerImmunity
		else
			r.Outcome = "Blocked"
		end
		r.Damage = chip
	else
		r.Damage = damage
		local poise = (stats.Poise or 0) + CombatCore.buffAmount(state, "Poise", hitTime)
		if (hit.Poise or 0) > poise and hitTime >= state.StaggerImmuneUntil then
			r.Staggered = true
			state.Blocking = false
			state.StaggeredUntil = hitTime + C.StaggerDuration
			state.ActionLockUntil = math.max(state.ActionLockUntil, state.StaggeredUntil)
			state.StaggerImmuneUntil = state.StaggeredUntil + C.StaggerImmunity
		end
		if hit.Status then
			for kind, amount in hit.Status do
				if CombatCore.addBuildup(state.Status, kind, amount, hitTime) then
					table.insert(r.StatusProcs, kind)
				end
			end
		end
	end
	if r.Damage > 0 then
		state.LastDamagedAt = hitTime
		r.Died = CombatCore.applyDamage(state, r.Damage)
	end
	return r
end

function CombatCore.applyDamage(state, amount: number): boolean
	if state.Dead or state.GodMode then
		return false
	end
	state.Health = math.max(0, state.Health - amount)
	if state.Health <= 0 then
		state.Dead = true
		state.Blocking = false
		return true
	end
	return false
end

function CombatCore.heal(state, amount: number): number
	if state.Dead or amount <= 0 then
		return 0
	end
	local before = state.Health
	state.Health = math.min(state.MaxHealth, state.Health + math.floor(amount))
	return state.Health - before
end

-- ===================================================================== Status effects
function CombatCore.newStatus()
	return { Bleed = 0, Poison = 0, Burn = 0, PoisonUntil = 0, BurnUntil = 0, LastDecay = 0 }
end

-- Returns true when the build-up procs.
function CombatCore.addBuildup(status, kind: string, amount: number, now: number): boolean
	local cfg = GameConfig.Status[kind]
	if not cfg or status[kind] == nil then
		return false
	end
	status[kind] += amount
	if status[kind] >= cfg.Threshold then
		status[kind] = 0
		if cfg.Duration then
			status[kind .. "Until"] = now + cfg.Duration
		end
		return true
	end
	return false
end

-- Decays build-up and returns damage-over-time fraction of max HP for this tick.
-- targetKind: "Player" | "Enemy" | "Boss"
function CombatCore.tickStatus(status, dt: number, now: number, targetKind: string): number
	local dot = 0
	for kind, cfg in GameConfig.Status do
		if status[kind] > 0 then
			status[kind] = math.max(0, status[kind] - cfg.Decay * dt)
		end
		local untilKey = kind .. "Until"
		if status[untilKey] and now < status[untilKey] then
			dot += (cfg[targetKind .. "Dps"] or 0) * dt
		end
	end
	return dot
end

function CombatCore.cureStatus(status, kind: string)
	if status[kind] then
		status[kind] = 0
		status[kind .. "Until"] = 0
	end
end

-- Instant damage fraction for a Bleed proc.
function CombatCore.bleedFraction(targetKind: string): number
	return GameConfig.Status.Bleed[targetKind .. "Fraction"] or 0
end

-- ===================================================================== Outgoing damage
--[[
	opts = { CritMult, DamageBuff, TypeBonus, TargetDefense, Pvp }
]]
function CombatCore.outgoing(attackRating: number, motion: number, opts)
	opts = opts or {}
	local dmg = attackRating * motion
	dmg *= 1 + (opts.DamageBuff or 0)
	dmg *= 1 + (opts.TypeBonus or 0)
	dmg *= opts.CritMult or 1
	if opts.TargetDefense then
		dmg *= 1 - Formulas.absorption(opts.TargetDefense, C.EnemyDefenseK)
	end
	if opts.Pvp then
		dmg *= C.PvPDamageMultiplier
	end
	return math.max(C.MinDamage, math.floor(dmg + 0.5))
end

-- ===================================================================== NPC targets
function CombatCore.newTarget(maxHealth: number, maxPoise: number)
	return {
		Health = maxHealth,
		MaxHealth = maxHealth,
		Poise = maxPoise,
		MaxPoise = maxPoise,
		LastPoiseDamage = NEG,
		StaggeredUntil = 0,
		Dead = false,
		Status = CombatCore.newStatus(),
		SlowUntil = 0,
		SlowAmount = 0,
	}
end

-- Returns { Died, Staggered, Damage }
function CombatCore.damageTarget(target, damage: number, poiseDamage: number, now: number)
	local r = { Died = false, Staggered = false, Damage = 0 }
	if target.Dead then
		return r
	end
	local dmg = math.max(0, math.floor(damage))
	target.Health = math.max(0, target.Health - dmg)
	r.Damage = dmg
	if target.Health <= 0 then
		target.Dead = true
		r.Died = true
		return r
	end
	if poiseDamage > 0 and now >= target.StaggeredUntil then
		target.Poise -= poiseDamage
		target.LastPoiseDamage = now
		if target.Poise <= 0 then
			target.Poise = target.MaxPoise
			target.StaggeredUntil = now + C.EnemyStaggerDuration
			r.Staggered = true
		end
	end
	return r
end

function CombatCore.regenTargetPoise(target, dt: number, now: number)
	if now - target.LastPoiseDamage >= C.PoiseRegenDelay and target.Poise < target.MaxPoise then
		target.Poise = math.min(target.MaxPoise, target.Poise + target.MaxPoise * 0.25 * dt)
	end
end

function CombatCore.isStaggered(target, now: number): boolean
	return now < target.StaggeredUntil
end

-- Scales a target's health pool by `scale`, preserving the current ratio.
function CombatCore.scaleTargetHealth(target, scale: number)
	if scale == 1 or target.Dead then
		return
	end
	target.MaxHealth = math.max(1, math.floor(target.MaxHealth * scale))
	target.Health = math.clamp(math.floor(target.Health * scale), 1, target.MaxHealth)
end

return CombatCore
