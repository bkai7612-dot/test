local SSS = game:GetService("ServerScriptService")
local TrainingCore = require(SSS.Server.Core.TrainingCore)
local GameConfig = require(game:GetService("ReplicatedStorage").Shared.Config.GameConfig)
local Helpers = require(game:GetService("ServerStorage").Tests.Helpers)

return function(t)
	local expect = t.expect

	t.it("rep timing is validated server-side (autoclick fails)", function()
		local p = Helpers.profile("Warrior")
		local s = TrainingCore.start(p, "weightlifting", 0)
		TrainingCore.rep(s, 0, true)
		expect(TrainingCore.rep(s, 0.1, true)).toBe("Failed")
	end)

	t.it("completing reps succeeds and rewards once", function()
		local p = Helpers.profile("Warrior")
		local s = TrainingCore.start(p, "weightlifting", 0)
		local now = 0
		local state
		for _ = 1, 12 do
			now += 1
			state = TrainingCore.rep(s, now, true)
		end
		expect(state).toBe("Success")
		local r = TrainingCore.reward(p, s, now)
		expect(r.Points).toBe(2)
		local r2 = TrainingCore.reward(p, s, now)
		expect(r2.Points).toBe(0)
	end)

	t.it("cooldown blocks immediate retries", function()
		local p = Helpers.profile("Warrior")
		p.TrainingCooldowns.weightlifting = 100
		local s, err = TrainingCore.start(p, "weightlifting", 110)
		expect(s).toBeNil()
		expect(err).toBe("Cooldown")
	end)

	t.it("training bonus is capped no matter how long you train", function()
		local p = Helpers.profile("Warrior")
		local now = 0
		for day = 1, 200 do
			now = day * GameConfig.Training.DailyResetSeconds
			for _ = 1, 10 do
				now += 400
				local s = TrainingCore.start(p, "weightlifting", now)
				if s then
					s.State = "Success"
					TrainingCore.reward(p, s, now)
				end
			end
		end
		expect(p.TrainingBonus.Strength).toBe(GameConfig.Training.MaxTrainingBonusPerAttribute)
	end)

	t.it("daily point cap", function()
		local p = Helpers.profile("Warrior")
		local total = 0
		for i = 1, 20 do
			local s = TrainingCore.start(p, "dummy_dps", i * 1000)
			if s then
				s.State = "Success"
				total += TrainingCore.reward(p, s, i * 1000).Points
			end
		end
		expect(total <= GameConfig.Training.DailyPointCap * 2).toBeTruthy()
	end)

	t.it("drills require the configured number of successes", function()
		local p = Helpers.profile("Warrior")
		local s = TrainingCore.start(p, "parry_drill", 0)
		TrainingCore.drillAttack(s, "Parried")
		TrainingCore.drillAttack(s, "Hit")
		TrainingCore.drillAttack(s, "Parried")
		expect(TrainingCore.drillAttack(s, "Parried")).toBe("Success")
		local s2 = TrainingCore.start(Helpers.profile("Warrior"), "dodge_drill", 0)
		TrainingCore.drillAttack(s2, "Hit")
		expect(TrainingCore.drillAttack(s2, "Hit")).toBe("Failed")
	end)

	t.it("course posts must be touched in order and in time", function()
		local p = Helpers.profile("Warrior")
		local s = TrainingCore.start(p, "stamina_run", 0)
		TrainingCore.post(s, 2, 1)
		expect(s.Count).toBe(0)
		for i = 1, 6 do TrainingCore.post(s, i, i) end
		expect(s.State).toBe("Success")
		local s2 = TrainingCore.start(Helpers.profile("Warrior"), "stamina_run", 0)
		expect(TrainingCore.post(s2, 1, 100)).toBe("Failed")
	end)
end
