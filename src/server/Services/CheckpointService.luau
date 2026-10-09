--[[
	CheckpointService
	Ember Shrines: resting restores health, stamina, mana and flask charges, sets the respawn
	point, and opens the shrine menu (level up, fast travel). Enemies are NOT reset on rest -
	the world is shared with other players.
	Fast travel is allowed between shrines the player has kindled, outside combat only.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local World = require(Shared.Config.World)
local Net = require(Shared.Net)

local CheckpointService = {}
local S
local byId = {}

function CheckpointService.Init(services)
	S = services
	for _, cp in World.Checkpoints do
		byId[cp.Id] = cp
	end
end

local function cpPos(cp): Vector3
	return Vector3.new(cp.Position[1], cp.Position[2], cp.Position[3])
end

function CheckpointService.NearestShrine(player: Player, radius: number?)
	local rt = S.PlayerStateService.Get(player)
	if not rt or not rt.Root then
		return nil
	end
	local best, bestD = nil, radius or (GameConfig.Checkpoint.InteractRadius + 4)
	for _, cp in World.Checkpoints do
		local d = (rt.Root.Position - cpPos(cp)).Magnitude
		if d <= bestD then
			best, bestD = cp, d
		end
	end
	return best
end

function CheckpointService.IsNearActivatedShrine(player: Player): boolean
	local rt = S.PlayerStateService.Get(player)
	local cp = CheckpointService.NearestShrine(player)
	return cp ~= nil and rt ~= nil and rt.Profile.Checkpoints.Activated[cp.Id] == true
end

local function rest(player: Player, cp)
	local rt = S.PlayerStateService.Get(player)
	if not rt or not rt.Combat or rt.Combat.Dead or rt.Encounter then
		return
	end
	local p = rt.Profile
	if not p.Checkpoints.Activated[cp.Id] then
		p.Checkpoints.Activated[cp.Id] = true
		S.NotifyService.Banner(player, "SHRINE KINDLED", cp.Name, "Discovery")
	end
	p.Checkpoints.Last = cp.Id
	S.PlayerStateService.FullRestore(player)
	S.PlayerStateService.Sync(player)
	Net.event("OpenUI"):FireClient(player, { Menu = "Shrine", ShrineId = cp.Id })
	task.spawn(S.DataService.Save, player)
end

function CheckpointService.Start()
	local function hook(part: Instance)
		local id = part:GetAttribute("ShrineId")
		local cp = id and byId[id]
		if not cp then
			return
		end
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Rest"
		prompt.ObjectText = cp.Name
		prompt.MaxActivationDistance = GameConfig.Checkpoint.InteractRadius
		prompt.RequiresLineOfSight = false
		prompt.Parent = part
		prompt.Triggered:Connect(function(player)
			-- server-side distance validation (prompts can be spoofed by exploits)
			if CheckpointService.NearestShrine(player) == cp then
				rest(player, cp)
			end
		end)
	end
	for _, part in CollectionService:GetTagged("Shrine") do
		hook(part)
	end
	CollectionService:GetInstanceAddedSignal("Shrine"):Connect(hook)

	S.RequestService.Register("Travel", function(player, rt, targetId)
		local target = type(targetId) == "string" and byId[targetId]
		if not target then
			return false, "UnknownShrine"
		end
		if not rt.Profile.Checkpoints.Activated[targetId] then
			return false, "NotKindled"
		end
		if not CheckpointService.IsNearActivatedShrine(player) then
			return false, "RestAtShrine"
		end
		if rt.Encounter or not rt.Character then
			return false, "Busy"
		end
		local pos = cpPos(target) + Vector3.new(0, 4, 6)
		pcall(function()
			player:RequestStreamAroundAsync(pos, 5)
		end)
		S.AntiCheatService.AllowTeleport(player)
		rt.Character:PivotTo(CFrame.new(pos))
		rt.Profile.Checkpoints.Last = targetId
		S.PlayerStateService.Sync(player)
		return true, targetId
	end)
end

return CheckpointService
