--[[
	BossBrain
	Pure decision logic shared by bosses and regular enemies:
	  * phase selection from health fraction
	  * attack selection by range, cooldown and weight, avoiding 3x repeats
	  * floor-based timing (tighter windups/recoveries on higher floors, never below fairness minimums)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Bosses = require(Shared.Config.Bosses)
local Formulas = require(Shared.Logic.Formulas)

local BossBrain = {}

-- Phases are ordered by descending Threshold. Returns phase index for the HP fraction.
function BossBrain.phaseIndex(def, hpFraction: number): number
	local idx = 1
	for i, phase in def.Phases do
		if hpFraction <= phase.Threshold then
			idx = i
		end
	end
	return idx
end

-- Attack list for a phase, honouring stances (Forsaken Champion).
function BossBrain.phaseAttacks(phase, stanceIndex: number?)
	if phase.Stances then
		local s = phase.Stances[((stanceIndex or 1) - 1) % #phase.Stances + 1]
		return s.Attacks, s.Name
	end
	return phase.Attacks, nil
end

--[[
	ctx = { Distance, Now, Cooldowns = { [name] = readyAt }, History = { lastName, ... }, Rng }
	Returns attack or nil (nil => reposition / chase).
]]
function BossBrain.choose(attacks, ctx)
	local candidates = {}
	local hist = ctx.History or {}
	local last, prev = hist[#hist], hist[#hist - 1]
	for _, a in attacks do
		local ready = (ctx.Cooldowns[a.Name] or 0) <= ctx.Now
		local inRange = ctx.Distance >= (a.MinRange or 0) and ctx.Distance <= (a.MaxRange or 10) + 2
		local repeated = last == a.Name and prev == a.Name
		if ready and inRange and not repeated then
			table.insert(candidates, a)
		end
	end
	if #candidates == 0 then
		return nil
	end
	return (ctx.Rng:Weighted(candidates))
end

function BossBrain.recordChoice(ctx, attack, now: number)
	ctx.History = ctx.History or {}
	table.insert(ctx.History, attack.Name)
	if #ctx.History > 4 then
		table.remove(ctx.History, 1)
	end
	if (attack.Cooldown or 0) > 0 then
		ctx.Cooldowns[attack.Name] = now + attack.Cooldown
	end
end

-- Effective timings for a step on a given floor. `isFollowUp` = not the first step of a combo.
function BossBrain.timing(step, floor: number?, isFollowUp: boolean?)
	local f = Bosses.Fairness
	local scale = if floor then Formulas.bossTiming(floor) else { Windup = 1, Recovery = 1 }
	local minWindup = if isFollowUp then f.MinComboFollowUp else f.MinWindup
	return math.max(minWindup, (step.Windup or 0.9) * scale.Windup), math.max(f.MinRecovery, (step.Recovery or 0.8) * scale.Recovery)
end

-- Unscaled-by-clamp timings, used by the fairness test to detect authored values that rely on the clamp.
function BossBrain.rawTiming(step, floor: number)
	local scale = Formulas.bossTiming(floor)
	return (step.Windup or 0.9) * scale.Windup, (step.Recovery or 0.8) * scale.Recovery
end

-- Flattens an attack into executable steps.
function BossBrain.steps(attack)
	if attack.Shape == "Combo" then
		return attack.Steps
	end
	return { attack }
end

return BossBrain
