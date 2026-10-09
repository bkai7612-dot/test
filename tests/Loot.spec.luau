local LootCore = require(game:GetService("ServerScriptService").Server.Core.LootCore)
local Helpers = require(game:GetService("ServerStorage").Tests.Helpers)

return function(t)
	local expect = t.expect
	t.it("rolls are deterministic for a seed", function()
		local a = LootCore.roll("elite", Helpers.rng(42))
		local b = LootCore.roll("elite", Helpers.rng(42))
		expect(a).toEqual(b)
	end)
	t.it("guaranteed drops always appear", function()
		for seed = 1, 50 do
			local r = LootCore.roll("chest_secret", Helpers.rng(seed))
			expect(r.flask_shard).toBe(1)
		end
	end)
	t.it("unknown tables yield nothing", function()
		expect(LootCore.roll("nope", Helpers.rng())).toEqual({})
		expect(LootCore.roll(nil, Helpers.rng())).toEqual({})
	end)
	t.it("rng ranges are inclusive and in bounds", function()
		local rng = Helpers.rng(9)
		local seen = {}
		for _ = 1, 500 do
			local v = rng:NextInteger(1, 3)
			expect(v >= 1 and v <= 3).toBeTruthy()
			seen[v] = true
		end
		expect(seen[1] and seen[2] and seen[3]).toBeTruthy()
	end)
end
