--[[
	Bootstrap
	Creates remotes, then initialises and starts every service in dependency order.
	Init() wires references and builds static content; Start() connects events and loops.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

Net.setupServer()

local ServicesFolder = script.Parent:WaitForChild("Services")

local ORDER = {
	"DataService",
	"NotifyService",
	"RequestService",
	"TelegraphService",
	"EntityService",
	"WorldBuilder",
	"PlayerStateService",
	"AntiCheatService",
	"ProjectileService",
	"AttackExecutor",
	"CombatService",
	"ProgressionService",
	"InventoryService",
	"ShopService",
	"InteractionService",
	"CheckpointService",
	"DeathService",
	"QuestService",
	"ExplorationService",
	"EnemyService",
	"PartyService",
	"BossService",
	"TrainingService",
	"CosmeticService",
	"PurchaseService",
	"PromoService",
	"LeaderboardService",
}

local services = {}
for _, name in ORDER do
	services[name] = require(ServicesFolder:WaitForChild(name))
end

for _, name in ORDER do
	local svc = services[name]
	if svc.Init then
		local ok, err = pcall(svc.Init, services)
		if not ok then
			warn(("[Bootstrap] %s.Init failed: %s"):format(name, tostring(err)))
		end
	end
end

for _, name in ORDER do
	local svc = services[name]
	if svc.Start then
		local ok, err = pcall(svc.Start)
		if not ok then
			warn(("[Bootstrap] %s.Start failed: %s"):format(name, tostring(err)))
		end
	end
end

workspace:SetAttribute("ServerReady", true)
print(("[Tower of the Fallen] server ready (%d services)"):format(#ORDER))
