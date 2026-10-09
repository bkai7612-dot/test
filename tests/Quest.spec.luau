local SSS = game:GetService("ServerScriptService")
local QuestCore = require(SSS.Server.Core.QuestCore)
local InventoryCore = require(SSS.Server.Core.InventoryCore)
local Helpers = require(game:GetService("ServerStorage").Tests.Helpers)

return function(t)
	local expect = t.expect

	t.it("prerequisites gate quests", function()
		local p = Helpers.profile("Warrior")
		expect(QuestCore.status(p, "hunt_wolves")).toBe("Locked")
		expect((QuestCore.accept(p, "hunt_wolves"))).toBe(false)
		expect((QuestCore.accept(p, "hunt_thralls"))).toBe(true)
		expect((QuestCore.accept(p, "hunt_thralls"))).toBe(false)
	end)

	t.it("kill progress only counts matching enemies while active", function()
		local p = Helpers.profile("Warrior")
		QuestCore.onEvent(p, { Type = "Kill", Enemy = "hollow_thrall" }) -- not accepted yet
		QuestCore.accept(p, "hunt_thralls")
		for _ = 1, 7 do
			QuestCore.onEvent(p, { Type = "Kill", Enemy = "hollow_thrall" })
		end
		QuestCore.onEvent(p, { Type = "Kill", Enemy = "rotwood_wolf" })
		expect(QuestCore.isComplete(p, "hunt_thralls")).toBe(false)
		QuestCore.onEvent(p, { Type = "Kill", Enemy = "hollow_thrall" })
		expect(QuestCore.isComplete(p, "hunt_thralls")).toBe(true)
		local ok, rewards = QuestCore.turnIn(p, "hunt_thralls")
		expect(ok).toBe(true)
		expect(rewards.Xp > 0).toBeTruthy()
		expect((QuestCore.turnIn(p, "hunt_thralls"))).toBe(false)
	end)

	t.it("collect quests consume items on turn-in", function()
		local p = Helpers.profile("Warrior")
		p.Quests.Completed.smith_upgrade3 = true
		QuestCore.accept(p, "smith_ore")
		InventoryCore.addItem(p, "iron_ore", 7)
		local ok = QuestCore.turnIn(p, "smith_ore")
		expect(ok).toBe(true)
		expect(InventoryCore.stackCount(p, "iron_ore")).toBe(1)
	end)

	t.it("boss objectives read tower progress", function()
		local p = Helpers.profile("Warrior")
		QuestCore.accept(p, "main_tower_1")
		expect(QuestCore.isComplete(p, "main_tower_1")).toBe(false)
		p.Tower.HighestCleared = 1
		expect(QuestCore.isComplete(p, "main_tower_1")).toBe(true)
	end)
end
