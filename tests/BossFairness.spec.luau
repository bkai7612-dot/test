-- Tester-owned fairness and design checks for all 20 bosses.
local RS = game:GetService("ReplicatedStorage")
local Bosses = require(RS.Shared.Config.Bosses)
local BossBrain = require(game:GetService("ServerScriptService").Server.Core.BossBrain)
local F = Bosses.Fairness

local function allAttacks(def)
	local out = {}
	for _, phase in def.Phases do
		if phase.Stances then
			for _, s in phase.Stances do
				for _, a in s.Attacks do table.insert(out, a) end
			end
		else
			for _, a in phase.Attacks do table.insert(out, a) end
		end
	end
	if def.Mechanics.Ambient then
		table.insert(out, def.Mechanics.Ambient.Attack)
	end
	return out
end

return function(t)
	local expect = t.expect

	t.it("every boss has >= 3 distinct attacks, phases, arena, model and mechanic text", function()
		for floor = 1, 20 do
			local b = Bosses.List[floor]
			local names = {}
			local n = 0
			for _, a in allAttacks(b) do
				if not names[a.Name] then names[a.Name] = true; n += 1 end
			end
			if n < 3 then error("boss " .. floor .. " has only " .. n .. " attacks") end
			expect(#b.Phases >= 2).toBeTruthy()
			expect(b.Arena.Size >= 100).toBeTruthy()
			expect(type(b.Model.Style)).toBe("string")
			expect(type(b.Mechanic)).toBe("string")
		end
	end)

	t.it("authored telegraphs stay above fairness minimums after floor scaling", function()
		for floor = 1, 20 do
			for _, a in allAttacks(Bosses.List[floor]) do
				for i, step in BossBrain.steps(a) do
					local w = BossBrain.rawTiming(step, floor)
					local min = if i == 1 then F.MinWindup else F.MinComboFollowUp
					if w < min then
						error(("boss %d '%s' step %d windup %.2f < %.2f"):format(floor, a.Name, i, w, min))
					end
				end
			end
		end
	end)

	t.it("main attacks give a recovery window", function()
		for floor = 1, 20 do
			local def = Bosses.List[floor]
			for _, phase in def.Phases do
				local lists = {}
				if phase.Stances then for _, s in phase.Stances do table.insert(lists, s.Attacks) end else lists = { phase.Attacks } end
				for _, list in lists do
					for _, a in list do
						local steps = BossBrain.steps(a)
						local last = steps[#steps]
						local _, rec = BossBrain.rawTiming(last, floor)
						if rec < F.MinRecovery then
							error(("boss %d '%s' recovery %.2f"):format(floor, a.Name, rec))
						end
					end
				end
			end
		end
	end)

	t.it("arena pulses always provide safe zones", function()
		for floor = 1, 20 do
			for _, a in allAttacks(Bosses.List[floor]) do
				for _, step in BossBrain.steps(a) do
					if step.Shape == "Pulse" then
						expect(step.SafeZones >= 2).toBeTruthy()
						expect(step.SafeRadius >= 8).toBeTruthy()
						expect(step.Windup >= 2.0).toBeTruthy()
					end
				end
			end
		end
	end)

	t.it("difficulty escalates through mechanics, not just numbers", function()
		-- later bosses must have at least as many phases or combo steps on average
		local function complexity(def)
			local steps = 0
			for _, a in allAttacks(def) do steps += #BossBrain.steps(a) end
			return #def.Phases * 10 + steps
		end
		local early, late = 0, 0
		for f = 1, 5 do early += complexity(Bosses.List[f]) end
		for f = 16, 20 do late += complexity(Bosses.List[f]) end
		expect(late > early).toBeTruthy()
		-- final boss has 3+ phases
		expect(#Bosses.List[20].Phases >= 3).toBeTruthy()
	end)

	t.it("phase thresholds are descending and start at 1", function()
		for floor = 1, 20 do
			local phases = Bosses.List[floor].Phases
			expect(phases[1].Threshold).toBe(1)
			for i = 2, #phases do
				expect(phases[i].Threshold < phases[i - 1].Threshold).toBeTruthy()
			end
		end
	end)

	t.it("phase selection picks the right phase", function()
		local def = Bosses.List[15]
		expect(BossBrain.phaseIndex(def, 1)).toBe(1)
		expect(BossBrain.phaseIndex(def, 0.6)).toBe(2)
		expect(BossBrain.phaseIndex(def, 0.1)).toBe(3)
	end)

	t.it("attack choice respects range and avoids triple repeats", function()
		local Rng = require(RS.Shared.Util.Rng)
		local attacks = Bosses.List[1].Phases[1].Attacks
		local ctx = { Distance = 5, Now = 0, Cooldowns = {}, History = {}, Rng = Rng.new(3) }
		for _ = 1, 50 do
			local a = BossBrain.choose(attacks, ctx)
			expect(a ~= nil).toBeTruthy()
			expect(5 <= a.MaxRange + 2).toBeTruthy()
			BossBrain.recordChoice(ctx, a, 0)
			local h = ctx.History
			if #h >= 3 then
				expect(h[#h] == h[#h - 1] and h[#h - 1] == h[#h - 2]).toBe(false)
			end
		end
		ctx.Distance = 500
		expect(BossBrain.choose(attacks, ctx)).toBeNil()
	end)
end
