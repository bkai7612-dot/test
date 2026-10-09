--[[
	AntiCheatService
	Lightweight movement sanity check. Characters are client-simulated on Roblox, so we sample
	horizontal speed once per window and, after repeated impossible movement, return the
	player to their last valid position. Server-initiated teleports are whitelisted briefly.
	(Combat, economy and progression are already fully server-authoritative.)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)

local AntiCheatService = {}
local S
local tracking = {}

function AntiCheatService.Init(services)
	S = services
end

function AntiCheatService.AllowTeleport(player: Player)
	local t = tracking[player]
	if t then
		t.GraceUntil = os.clock() + 3
		t.LastPos = nil
	else
		tracking[player] = { GraceUntil = os.clock() + 3, Violations = 0 }
	end
end

function AntiCheatService.Start()
	local cfg = GameConfig.AntiCheat
	S.PlayerStateService.CharacterReady:Connect(function(player)
		AntiCheatService.AllowTeleport(player)
	end)
	task.spawn(function()
		while true do
			task.wait(cfg.SampleWindow)
			for player, rt in S.PlayerStateService.All() do
				local root = rt.Root
				if root and root.Parent then
					local t = tracking[player] or { Violations = 0, GraceUntil = 0 }
					tracking[player] = t
					local pos = root.Position
					if t.LastPos and os.clock() > t.GraceUntil then
						local flat = Vector3.new(pos.X - t.LastPos.X, 0, pos.Z - t.LastPos.Z).Magnitude
						if flat / cfg.SampleWindow > cfg.MaxHorizontalSpeed then
							t.Violations += 1
							if t.Violations >= cfg.ViolationsBeforeReset and t.ValidPos then
								warn(("[AntiCheat] %s moved %.0f studs/s; resetting position"):format(player.Name, flat / cfg.SampleWindow))
								root.CFrame = CFrame.new(t.ValidPos)
								t.Violations = 0
								pos = t.ValidPos
							end
						else
							t.Violations = math.max(0, t.Violations - 1)
							t.ValidPos = pos
						end
					else
						t.ValidPos = pos
					end
					t.LastPos = pos
				end
			end
		end
	end)
	game:GetService("Players").PlayerRemoving:Connect(function(p)
		tracking[p] = nil
	end)
end

return AntiCheatService
