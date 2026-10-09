--[[
	TrainingCore
	Server-measured training sessions and capped rewards.

	A session is created when the player starts a challenge; the server feeds it events it
	observed itself (rep presses with server timestamps, validated dummy hits, attacks avoided
	or parried, course posts touched). Completion is decided here, never by the client.

	Reward caps:
	  * Cooldown per challenge.
	  * DailyPointCap training points per real-time day.
	  * Every PointsPerBonus points in an attribute grants +1 bonus, up to
	    MaxTrainingBonusPerAttribute (+5). Repetition can never produce unlimited stats.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Training = require(Shared.Config.Training)

local TrainingCore = {}

function TrainingCore.day(now: number): number
	return math.floor(now / GameConfig.Training.DailyResetSeconds)
end

function TrainingCore.cooldownRemaining(profile, challengeId: string, now: number): number
	local def = Training[challengeId]
	if not def then
		return math.huge
	end
	local last = profile.TrainingCooldowns[challengeId] or -math.huge
	return math.max(0, last + def.Cooldown - now)
end

function TrainingCore.start(profile, challengeId, now: number)
	local def = Training[challengeId]
	if not def then
		return nil, "Unknown"
	end
	if profile.Class == "" then
		return nil, "NoClass"
	end
	if TrainingCore.cooldownRemaining(profile, challengeId, now) > 0 then
		return nil, "Cooldown"
	end
	return {
		Id = challengeId,
		Def = def,
		StartedAt = now,
		Count = 0,
		Failures = 0,
		LastRep = nil,
		Posts = {},
		State = "Running",
	}, nil
end

local function finish(session, success: boolean)
	session.State = if success then "Success" else "Failed"
	return session.State
end

-- Called once per server tick or event; returns session.State.
function TrainingCore.tick(session, now: number)
	if session.State ~= "Running" then
		return session.State
	end
	local def = session.Def
	if def.TimeLimit and now - session.StartedAt > def.TimeLimit then
		return finish(session, false)
	end
	if def.Kind == "Reps" and session.LastRep and now - session.LastRep > def.MaxInterval then
		return finish(session, false)
	end
	return session.State
end

-- Reps: a press at server time `now`. Too-fast presses (macro/autoclick) fail the set.
function TrainingCore.rep(session, now: number, hasStamina: boolean)
	if session.State ~= "Running" or session.Def.Kind ~= "Reps" then
		return session.State
	end
	local def = session.Def
	if session.LastRep then
		local dt = now - session.LastRep
		if dt < def.MinInterval or dt > def.MaxInterval then
			return finish(session, false)
		end
	end
	if not hasStamina then
		return finish(session, false)
	end
	session.LastRep = now
	session.Count += 1
	if session.Count >= def.Reps then
		return finish(session, true)
	end
	return session.State
end

-- Hits: a server-validated hit on the dummy.
function TrainingCore.hit(session, now: number)
	if session.State ~= "Running" or session.Def.Kind ~= "Hits" then
		return session.State
	end
	if now - session.StartedAt > session.Def.TimeLimit then
		return finish(session, false)
	end
	session.Count += 1
	if session.Count >= session.Def.Hits then
		return finish(session, true)
	end
	return session.State
end

-- Avoid/Parry drills: called after each drill attack resolves.
-- outcome: "Hit" | "Avoided" | "Blocked" | "Parried"
function TrainingCore.drillAttack(session, outcome: string)
	if session.State ~= "Running" then
		return session.State
	end
	local def = session.Def
	if def.Kind == "Avoid" then
		if outcome == "Avoided" or outcome == "Parried" then
			session.Count += 1
		else
			session.Failures += 1
		end
	elseif def.Kind == "Parry" then
		if outcome == "Parried" then
			session.Count += 1
		else
			session.Failures += 1
		end
	else
		return session.State
	end
	if session.Count >= def.Required then
		return finish(session, true)
	end
	if session.Failures > def.Attacks - def.Required then
		return finish(session, false)
	end
	return session.State
end

-- Course: posts must be touched in order 1..N.
function TrainingCore.post(session, index: number, now: number)
	if session.State ~= "Running" or session.Def.Kind ~= "Course" then
		return session.State
	end
	if now - session.StartedAt > session.Def.TimeLimit then
		return finish(session, false)
	end
	if index == session.Count + 1 then
		session.Count = index
		if session.Count >= session.Def.Posts then
			return finish(session, true)
		end
	end
	return session.State
end

function TrainingCore.spar(session, won: boolean)
	if session.State ~= "Running" or session.Def.Kind ~= "Spar" then
		return session.State
	end
	return finish(session, won)
end

-- Applies rewards for a successful session. Returns { Xp, Points, BonusGained, Capped }.
function TrainingCore.reward(profile, session, now: number)
	local result = { Xp = 0, Points = 0, BonusGained = 0, Capped = false }
	if session.State ~= "Success" or session.Rewarded then
		return result
	end
	session.Rewarded = true
	local def = session.Def
	profile.TrainingCooldowns[session.Id] = now
	result.Xp = math.floor(def.Xp * (1 + profile.Level * 0.05))

	local today = TrainingCore.day(now)
	if profile.TrainingDaily.Day ~= today then
		profile.TrainingDaily.Day = today
		profile.TrainingDaily.Points = 0
	end
	local room = math.max(0, GameConfig.Training.DailyPointCap - profile.TrainingDaily.Points)
	local attr = def.Attribute
	local bonus = profile.TrainingBonus[attr] or 0
	if bonus >= GameConfig.Training.MaxTrainingBonusPerAttribute then
		room = 0
	end
	local points = math.min(def.Points, room)
	result.Capped = points < def.Points
	if points > 0 then
		profile.TrainingDaily.Points += points
		local total = (profile.TrainingPoints[attr] or 0) + points
		while total >= GameConfig.Training.PointsPerBonus and bonus < GameConfig.Training.MaxTrainingBonusPerAttribute do
			total -= GameConfig.Training.PointsPerBonus
			bonus += 1
			result.BonusGained += 1
		end
		if bonus >= GameConfig.Training.MaxTrainingBonusPerAttribute then
			total = 0
		end
		profile.TrainingPoints[attr] = total
		profile.TrainingBonus[attr] = bonus
	end
	result.Points = points
	return result
end

return TrainingCore
