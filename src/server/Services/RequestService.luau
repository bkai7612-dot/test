--[[
	RequestService
	Single RemoteFunction router for menu/interaction requests:
	  client: Request:InvokeServer(name, payload) -> { Ok = bool, Result = any, Error = string? }
	Handlers are registered by services. Every call is rate limited and wrapped in pcall so a
	bad payload can never error the remote or leak a stack trace to the client.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local RequestService = {}

local S
local handlers = {}

function RequestService.Init(services)
	S = services
end

function RequestService.Register(name: string, handler)
	assert(handlers[name] == nil, "duplicate request handler " .. name)
	handlers[name] = handler
end

function RequestService.Start()
	Net.func("Request").OnServerInvoke = function(player: Player, name, payload)
		if type(name) ~= "string" then
			return { Ok = false, Error = "BadRequest" }
		end
		local handler = handlers[name]
		if not handler then
			return { Ok = false, Error = "UnknownRequest" }
		end
		if not S.CombatService.Allow(player) then
			return { Ok = false, Error = "TooFast" }
		end
		local rt = S.PlayerStateService.Get(player)
		if not rt then
			return { Ok = false, Error = "NotLoaded" }
		end
		local ok, success, result = pcall(handler, player, rt, payload)
		if not ok then
			warn(("[RequestService] %s from %s errored: %s"):format(name, player.Name, tostring(success)))
			return { Ok = false, Error = "ServerError" }
		end
		if success then
			return { Ok = true, Result = result }
		end
		return { Ok = false, Error = tostring(result) }
	end
end

return RequestService
