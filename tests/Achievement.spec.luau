local SSS = game:GetService("ServerScriptService")
local AchievementCore = require(SSS.Server.Core.AchievementCore)
local Helpers = require(game:GetService("ServerStorage").Tests.Helpers)

return function(t)
	local expect = t.expect
	t.it("stat achievements unlock once and grant titles", function()
		local p = Helpers.profile("Warrior")
		AchievementCore.increment(p, "Kills")
		local u = AchievementCore.evaluate(p)
		local found = false
		for _, a in u do if a.Id == "first_blood" then found = true end end
		expect(found).toBe(true)
		expect(p.Titles.Initiate).toBe(true)
		local again = AchievementCore.evaluate(p)
		for _, a in again do expect(a.Id ~= "first_blood").toBeTruthy() end
	end)
	t.it("hybrid check", function()
		local p = Helpers.profile("Warrior")
		p.Attributes.Strength = 30
		p.Attributes.Intelligence = 30
		AchievementCore.evaluate(p)
		expect(p.Achievements.hybrid).toBe(true)
	end)
end
