--[[
	Net
	Declares every remote used by the game. The server creates them under
	ReplicatedStorage.Remotes at boot; clients wait for them.

	Client -> Server
	  Action  (RemoteEvent)    high-frequency combat input: { Kind, ... }
	  Request (RemoteFunction) menu/interaction requests: (name, payload) -> { Ok, Result | Error }

	Server -> Client
	  Profile   (RemoteEvent)  sanitized profile snapshot + derived stats
	  Notify    (RemoteEvent)  toast / banner messages
	  Fx        (RemoteEvent)  combat feedback (damage numbers, hit flashes, parry, stagger)
	  Boss      (RemoteEvent)  boss bar, phase and victory/defeat state
	  OpenUI    (RemoteEvent)  ask the client to open a menu (shop, blacksmith, dialog, tower)
	  Party     (RemoteEvent)  party state + invites
	  Training  (RemoteEvent)  training challenge HUD state
]]

local Net = {}

Net.Events = { "Action", "Profile", "Notify", "Fx", "Boss", "OpenUI", "Party", "Training" }
Net.Functions = { "Request" }

local FOLDER = "Remotes"

function Net.setupServer()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local folder = ReplicatedStorage:FindFirstChild(FOLDER)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER
		folder.Parent = ReplicatedStorage
	end
	for _, name in Net.Events do
		if not folder:FindFirstChild(name) then
			local r = Instance.new("RemoteEvent")
			r.Name = name
			r.Parent = folder
		end
	end
	for _, name in Net.Functions do
		if not folder:FindFirstChild(name) then
			local r = Instance.new("RemoteFunction")
			r.Name = name
			r.Parent = folder
		end
	end
	return folder
end

function Net.folder()
	return game:GetService("ReplicatedStorage"):WaitForChild(FOLDER)
end

function Net.event(name: string): RemoteEvent
	return Net.folder():WaitForChild(name) :: RemoteEvent
end

function Net.func(name: string): RemoteFunction
	return Net.folder():WaitForChild(name) :: RemoteFunction
end

return Net
