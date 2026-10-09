--[[
	ExplorationService
	* Region tracking (Player attribute "Region"; used for PvP, safe zones, ambience).
	* Location discovery: XP once per location per character.
	* Treasure chests: once per character, server-validated distance, server-rolled loot.
	* Hollow Vale gate: the hidden late-game region requires tower floor 10.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local World = require(Shared.Config.World)
local Rng = require(Shared.Util.Rng)
local LootCore = require(script.Parent.Parent.Core.LootCore)

local ExplorationService = {}
local S
local rng = Rng.new()
local chests = {}

local function v3(t)
	return Vector3.new(t[1], t[2], t[3])
end

function ExplorationService.Init(services)
	S = services
	for _, c in World.Chests do
		chests[c.Id] = c
	end
end

local function regionAt(pos: Vector3)
	local best, bestD = nil, math.huge
	for _, r in World.Regions do
		local c = v3(r.Center)
		local d = Vector3.new(pos.X - c.X, 0, pos.Z - c.Z).Magnitude
		if d <= r.Radius and d < bestD then
			best, bestD = r, d
		end
	end
	return best
end
ExplorationService.RegionAt = regionAt

local function openChest(player: Player, chest)
	local rt = S.PlayerStateService.Get(player)
	if not rt or not rt.Root or rt.Profile.Class == "" then
		return
	end
	if (rt.Root.Position - v3(chest.Position)).Magnitude > 14 then
		return
	end
	if rt.Profile.OpenedChests[chest.Id] then
		S.NotifyService.Toast(player, "You have already looted this chest.", "Info")
		return
	end
	rt.Profile.OpenedChests[chest.Id] = true
	local loot = LootCore.roll(chest.Loot, rng)
	S.ProgressionService.GrantBundle(player, { Items = loot, Currency = rng:NextInteger(50, 150) * (1 + rt.Profile.Tower.HighestCleared // 4) }, "Chest")
	task.spawn(S.DataService.Save, player)
end

function ExplorationService.Start()
	local function hookChest(part: Instance)
		local id = part:GetAttribute("ChestId")
		local chest = id and chests[id]
		if not chest then
			return
		end
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Open"
		prompt.ObjectText = "Chest"
		prompt.MaxActivationDistance = 10
		prompt.HoldDuration = 0.6
		prompt.Parent = part
		prompt.Triggered:Connect(function(player)
			openChest(player, chest)
		end)
	end
	for _, p in CollectionService:GetTagged("Chest") do
		hookChest(p)
	end
	CollectionService:GetInstanceAddedSignal("Chest"):Connect(hookChest)

	task.spawn(function()
		while true do
			task.wait(0.5)
			for player, rt in S.PlayerStateService.All() do
				local root = rt.Root
				if root and root.Parent and rt.Profile.Class ~= "" and not rt.Encounter then
					local pos = root.Position
					local region = regionAt(pos)
					local id = region and region.Id or "wilds"
					-- Hollow Vale requires tower floor 10
					if region and region.RequiresFloor and rt.Profile.Tower.HighestCleared < region.RequiresFloor then
						local c = v3(region.Center)
						local out = Vector3.new(pos.X - c.X, 0, pos.Z - c.Z)
						out = if out.Magnitude > 0.1 then out.Unit else Vector3.new(0, 0, 1)
						S.AntiCheatService.AllowTeleport(player)
						rt.Character:PivotTo(CFrame.new(c + out * (region.Radius + 12) + Vector3.new(0, 5, 0)))
						S.NotifyService.Toast(player, ("An ancient seal bars the way. (Clear tower floor %d)"):format(region.RequiresFloor), "Warning")
						continue
					end
					if rt.Region ~= id then
						rt.Region = id
						player:SetAttribute("Region", id)
						player:SetAttribute("Safe", region ~= nil and region.Safe == true)
						player:SetAttribute("PvP", region ~= nil and region.PvP == true)
					end
					for _, loc in World.Locations do
						if not rt.Profile.Discovered[loc.Id] and (pos - v3(loc.Position)).Magnitude <= loc.Radius then
							rt.Profile.Discovered[loc.Id] = true
							S.NotifyService.Banner(player, if loc.Secret then "SECRET DISCOVERED" else "LOCATION DISCOVERED", loc.Name, "Discovery")
							if loc.Xp > 0 then
								S.ProgressionService.GrantXp(player, loc.Xp, "Discovery")
							end
							S.ProgressionService.EvaluateAchievements(player)
							S.PlayerStateService.Sync(player)
						end
					end
				end
			end
		end
	end)
end

return ExplorationService
