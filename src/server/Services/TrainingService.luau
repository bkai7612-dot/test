--[[
	TrainingService
	Training Grounds challenges. The server observes everything itself:
	  Reps     - rep presses timed by the server, stamina spent per rep
	  Hits     - valid weapon hits on training dummies (EntityService)
	  Avoid    - the drill master's telegraphed attacks: dodged or stepped out of = avoided
	  Parry    - only parries count
	  Course   - posts touched in order (server distance checks)
	  Spar     - defeat a sparring partner that only targets you; dying costs nothing
	Rewards are capped by TrainingCore (cooldowns, daily cap, +5 per-attribute bonus cap).
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Training = require(Shared.Config.Training)
local Attacks = require(Shared.Config.Attacks)
local Net = require(Shared.Net)
local Core = script.Parent.Parent.Core
local TrainingCore = require(Core.TrainingCore)
local CombatCore = require(Core.CombatCore)
local AchievementCore = require(Core.AchievementCore)
local EntityModels = require(script.Parent.EntityModels)

local TrainingService = {}
local S
local remote: RemoteEvent
local stations = {} -- [challengeId] = BasePart
local posts = {} -- [index] = BasePart

local function now()
	return workspace:GetServerTimeNow()
end

function TrainingService.Init(services)
	S = services
	remote = Net.event("Training")
end

local function send(player: Player, payload)
	remote:FireClient(player, payload)
end

local function finish(player: Player, rt, session)
	if rt.Training ~= session then
		return
	end
	rt.Training = nil
	if session.Cleanup then
		session.Cleanup()
	end
	if session.State == "Success" then
		local r = TrainingCore.reward(rt.Profile, session, os.time())
		AchievementCore.increment(rt.Profile, "TrainingDone")
		S.ProgressionService.QuestEvent(player, { Type = "Training" })
		S.ProgressionService.GrantXp(player, r.Xp, "Training")
		local msg = ("+%d XP"):format(r.Xp)
		if r.Points > 0 then
			msg ..= (", +%d %s training"):format(r.Points, session.Def.Attribute)
		end
		if r.BonusGained > 0 then
			msg ..= (" - %s +%d!"):format(session.Def.Attribute, r.BonusGained)
			S.PlayerStateService.RecomputeStats(player)
		end
		if r.Capped then
			msg ..= " (daily/attribute training cap reached)"
		end
		S.NotifyService.Banner(player, "TRAINING COMPLETE", session.Def.Name .. " - " .. msg, "Reward")
		S.ProgressionService.EvaluateAchievements(player)
		S.PlayerStateService.Sync(player)
	else
		S.NotifyService.Toast(player, session.Def.Name .. " failed. " .. (session.Reason or ""), "Warning")
	end
	send(player, { Type = "End", State = session.State })
end

local function runDrill(player: Player, rt, session, station: BasePart)
	local def = session.Def
	local base = station.Position + Vector3.new(0, 0, -8)
	local model, root, humanoid, _, _, shoulder = EntityModels.build("Drill Master", { Style = "Humanoid", Scale = 1.15, Color = Color3.fromRGB(120, 110, 90), Weapon = "Sword" }, "Dummy")
	model:PivotTo(CFrame.new(base + Vector3.new(0, 5, 0)))
	root.Anchored = true
	model.Parent = workspace
	local entity = { Alive = true, Target = CombatCore.newTarget(1e9, 1e9), Kind = "Dummy" }
	local attacker = {
		Entity = entity,
		Model = model,
		Root = root,
		Humanoid = humanoid,
		Shoulder = shoulder,
		BaseDamage = 6, -- drills are safe
		Targets = function()
			return { player }
		end,
	}
	session.Cleanup = function()
		entity.Alive = false
		model:Destroy()
	end
	task.spawn(function()
		task.wait(2)
		for i = 1, def.Attacks do
			if rt.Training ~= session or session.State ~= "Running" then
				return
			end
			local outcome
			attacker.OnHitPlayer = function(_, o)
				outcome = o
			end
			local attack = if i % 2 == 0
				then Attacks.Circle({ Name = "Drill Slam", Windup = def.Windup, Recovery = 0.4, Damage = 1, Radius = 7, Offset = 3, Parryable = def.Kind == "Parry" })
				else Attacks.Cone({ Name = "Drill Cut", Windup = def.Windup, Recovery = 0.4, Damage = 1, Range = 12, Arc = 100, Parryable = true })
			-- the trainee must actually be within reach when the attack begins; standing far away
			-- (AFK) counts as a miss, not an avoid
			local prt = S.PlayerStateService.Get(player)
			local engaged = prt ~= nil and prt.Root ~= nil and (prt.Root.Position - root.Position).Magnitude <= 13
			S.AttackExecutor.Run(attacker, attack, player)
			task.wait(0.25)
			local result = outcome
			if not engaged then
				result = "Miss"
				S.NotifyService.Toast(player, "Stay close to the drill master!", "Warning")
			elseif result == nil or result == "Dodged" then
				result = if def.Kind == "Avoid" then "Avoided" else "Miss"
			end
			local state = TrainingCore.drillAttack(session, result)
			send(player, { Type = "Progress", Count = session.Count, Goal = def.Required, Failures = session.Failures })
			if state ~= "Running" then
				finish(player, rt, session)
				return
			end
			task.wait(math.max(0.5, def.Interval - def.Windup))
		end
		if session.State == "Running" then
			session.State = "Failed"
			finish(player, rt, session)
		end
	end)
end

local function start(player: Player, challengeId: string, station: BasePart)
	local rt = S.PlayerStateService.Get(player)
	if not rt or not rt.Root or not rt.Combat or rt.Combat.Dead then
		return
	end
	if rt.Training then
		S.NotifyService.Toast(player, "Finish your current training first.", "Warning")
		return
	end
	if (rt.Root.Position - station.Position).Magnitude > 16 then
		return
	end
	local session, err = TrainingCore.start(rt.Profile, challengeId, os.time())
	if not session then
		if err == "Cooldown" then
			S.NotifyService.Toast(player, ("Rest first: available in %ds."):format(math.ceil(TrainingCore.cooldownRemaining(rt.Profile, challengeId, os.time()))), "Warning")
		end
		return
	end
	-- sessions are timed with the server clock
	session.StartedAt = now()
	session.Station = station
	rt.Training = session
	local def = session.Def
	send(player, { Type = "Start", Id = challengeId, Name = def.Name, Description = def.Description, Kind = def.Kind,
		Goal = def.Reps or def.Hits or def.Required or def.Posts or 1, TimeLimit = def.TimeLimit })
	if def.Kind == "Avoid" or def.Kind == "Parry" then
		runDrill(player, rt, session, station)
	elseif def.Kind == "Spar" then
		local ai = S.EnemyService.Spawn(def.Enemy, station.Position + Vector3.new(0, 4, -12), {
			Name = "Sparring Partner",
			Owner = player, -- only the trainee can damage it
			HealthScale = def.HealthMult,
			NoRewards = true,
			Leash = 60,
			Restrict = function(plr)
				return plr == player
			end,
			OnDeath = function(_, killer)
				if rt.Training == session and killer == player then
					TrainingCore.spar(session, true)
					finish(player, rt, session)
				end
			end,
		})
		session.Cleanup = function()
			if ai and not ai.Dead then
				S.EnemyService.Despawn(ai, true)
			end
		end
	end
end

function TrainingService.OnRep(player: Player)
	local rt = S.PlayerStateService.Get(player)
	local session = rt and rt.Training
	if not session or session.Def.Kind ~= "Reps" then
		return
	end
	local c = rt.Combat
	local has = c and c.Stamina >= session.Def.StaminaPerRep
	if has then
		c.Stamina -= session.Def.StaminaPerRep
		c.LastStaminaSpend = now()
	end
	local state = TrainingCore.rep(session, now(), has)
	send(player, { Type = "Progress", Count = session.Count, Goal = session.Def.Reps })
	if state ~= "Running" then
		session.Reason = if not has then "Out of stamina." else "Keep a steady rhythm."
		finish(player, rt, session)
	end
end

function TrainingService.OnPlayerDied(player: Player)
	local rt = S.PlayerStateService.Get(player)
	local session = rt and rt.Training
	if session then
		session.State = "Failed"
		session.Reason = "You were defeated."
		finish(player, rt, session)
	end
end

function TrainingService.Start()
	local function hookStation(part: Instance)
		local id = part:GetAttribute("Challenge")
		local def = id and Training[id]
		if not def or not part:IsA("BasePart") then
			return
		end
		stations[id] = part
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Begin"
		prompt.ObjectText = def.Name
		prompt.MaxActivationDistance = 12
		prompt.HoldDuration = 0.4
		prompt.Parent = part
		prompt.Triggered:Connect(function(player)
			start(player, id, part :: BasePart)
		end)
	end
	for _, p in CollectionService:GetTagged("TrainingStation") do
		hookStation(p)
	end
	CollectionService:GetInstanceAddedSignal("TrainingStation"):Connect(hookStation)
	for _, p in CollectionService:GetTagged("TrainingPost") do
		posts[p:GetAttribute("Index")] = p :: BasePart
	end
	CollectionService:GetInstanceAddedSignal("TrainingPost"):Connect(function(p)
		posts[p:GetAttribute("Index")] = p :: BasePart
	end)

	-- training dummies are permanent, unkillable entities
	local function hookDummy(inst: Instance)
		if not inst:IsA("Model") then
			return
		end
		local model = inst :: Model
		local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
		S.EntityService.Register({ Kind = "Dummy", Model = model, Root = root, Name = "Training Dummy", Level = 1, MaxHealth = 1e7, Poise = 1e7, Defense = 0, Radius = 1.6 })
	end
	for _, m in CollectionService:GetTagged("TrainingDummy") do
		hookDummy(m)
	end
	CollectionService:GetInstanceAddedSignal("TrainingDummy"):Connect(hookDummy)

	S.EntityService.Damaged:Connect(function(e, player, _amount, info)
		if not player or e.Kind ~= "Dummy" then
			return
		end
		-- only weapon swings count, and one swing that clips several dummies counts once
		if not info or info.Kind ~= "Melee" then
			e.Target.Health = e.Target.MaxHealth
			S.EntityService.PushHealth(e)
			return
		end
		e.Target.Health = e.Target.MaxHealth
		S.EntityService.PushHealth(e)
		local rt = S.PlayerStateService.Get(player)
		local session = rt and rt.Training
		if session and session.Def.Kind == "Hits" then
			local t = now()
			if t - (session.LastHitAt or -1e9) < 0.12 then
				return
			end
			session.LastHitAt = t
			local state = TrainingCore.hit(session, t)
			send(player, { Type = "Progress", Count = session.Count, Goal = session.Def.Hits })
			if state ~= "Running" then
				finish(player, rt, session)
			end
		end
	end)

	-- session watchdog: timeouts, leaving the station, course posts
	task.spawn(function()
		while true do
			task.wait(0.2)
			local t = now()
			for player, rt in S.PlayerStateService.All() do
				local session = rt.Training
				if session and session.State == "Running" and rt.Root then
					local def = session.Def
					if def.Kind == "Course" then
						local nextPost = posts[session.Count + 1]
						if nextPost and (rt.Root.Position - nextPost.Position).Magnitude < 8 then
							TrainingCore.post(session, session.Count + 1, t)
							send(player, { Type = "Progress", Count = session.Count, Goal = def.Posts })
						end
					elseif (rt.Root.Position - session.Station.Position).Magnitude > 45 then
						session.State = "Failed"
						session.Reason = "You left the training area."
					end
					if session.State == "Running" then
						TrainingCore.tick(session, t)
					end
					if session.State ~= "Running" then
						finish(player, rt, session)
					end
				end
			end
		end
	end)
end

return TrainingService
