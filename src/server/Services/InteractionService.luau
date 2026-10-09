--[[
	InteractionService
	Hub NPC interactions. WorldBuilder creates NPC models tagged "NPC" with attribute NpcId.
	Each gets a ProximityPrompt; triggering it (server-validated distance) tells the client to
	open the matching menu. Menu actions (buy/sell/upgrade/quests) re-check proximity on the
	server, so a modified client cannot shop from across the map.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local World = require(Shared.Config.World)
local Net = require(Shared.Net)

local InteractionService = {}
local S
local npcs = {}

local ACTIONS = {
	Shop = "Trade",
	Blacksmith = "Upgrade",
	Quest = "Talk",
	Wardrobe = "Wardrobe",
	Party = "Fellowship",
	Tutorial = "Ask",
}

function InteractionService.Init(services)
	S = services
	for _, n in World.NPCs do
		npcs[n.Id] = n
	end
end

local function npcPos(n): Vector3
	return Vector3.new(n.Position[1], n.Position[2], n.Position[3])
end

function InteractionService.IsNear(player: Player, npcId: string): boolean
	local rt = S.PlayerStateService.Get(player)
	local n = npcs[npcId]
	if not rt or not rt.Root or not n then
		return false
	end
	return (rt.Root.Position - npcPos(n)).Magnitude <= GameConfig.Shop.InteractRadius + 4
end

function InteractionService.IsNearRole(player: Player, role: string): boolean
	for id, n in npcs do
		if n.Role == role and InteractionService.IsNear(player, id) then
			return true
		end
	end
	return false
end

function InteractionService.IsNearShop(player: Player, shopId: string): boolean
	for id, n in npcs do
		if n.Role == "Shop" and n.Shop == shopId and InteractionService.IsNear(player, id) then
			return true
		end
	end
	return false
end

function InteractionService.Start()
	local openUI = Net.event("OpenUI")
	local function hook(model: Instance)
		local id = model:GetAttribute("NpcId")
		local n = id and npcs[id]
		if not n then
			return
		end
		local anchor = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChildWhichIsA("BasePart")
		if not anchor then
			return
		end
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = ACTIONS[n.Role] or "Talk"
		prompt.ObjectText = n.Name
		prompt.MaxActivationDistance = GameConfig.Shop.InteractRadius
		prompt.RequiresLineOfSight = false
		prompt.Parent = anchor
		prompt.Triggered:Connect(function(player)
			if not InteractionService.IsNear(player, id) then
				return
			end
			local rt = S.PlayerStateService.Get(player)
			if not rt or rt.Profile.Class == "" then
				return
			end
			openUI:FireClient(player, { Menu = n.Role, NpcId = id, Shop = n.Shop, Quests = n.Quests, Name = n.Name })
		end)
	end
	for _, m in CollectionService:GetTagged("NPC") do
		hook(m)
	end
	CollectionService:GetInstanceAddedSignal("NPC"):Connect(hook)
end

return InteractionService
