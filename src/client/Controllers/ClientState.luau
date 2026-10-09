--[[
	ClientState
	Read-only mirror of the server's profile snapshot plus helpers for calling the server.
	The client NEVER decides outcomes; it only displays state and sends requests.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)

local ClientState = {
	Profile = nil,
	Changed = Signal.new(),
	Party = { Members = {}, Leader = nil },
	PartyChanged = Signal.new(),
	Busy = false,
	Settings = nil,
}

local requestFn: RemoteFunction

local ERRORS = {
	NotEnoughCurrency = "Not enough embers.",
	NotEnoughMaterials = "Missing upgrade materials.",
	MaxLevel = "Already at maximum upgrade level.",
	RestAtShrine = "Rest at a kindled Ember Shrine first.",
	InCombat = "You cannot do that during combat.",
	NotAtMerchant = "Speak to a merchant to do that.",
	NotAtBlacksmith = "Speak to the blacksmith to do that.",
	NotAtGate = "Gather at the Tower Gate first.",
	Locked = "Locked: clear the previous tower floor first.",
	OnlyLeaderStarts = "Only the party leader can begin an encounter.",
	TowerBusy = "All arenas are in use; try again in a moment.",
	LimitReached = "Purchase limit reached.",
	CannotSell = "This item cannot be sold.",
	Equipped = "Unequip the item first.",
	InventoryFull = "Inventory full.",
	StackFull = "You cannot carry more of that.",
	TooFast = "Slow down.",
	Unavailable = "Not available yet.",
	NotKindled = "You have not kindled that shrine.",
	DuplicateAccessory = "You already wear that accessory.",
	NotComplete = "Objectives not yet complete.",
	TooFar = "You are too far away.",
	Busy = "You are busy.",
}

function ClientState.Init()
	requestFn = Net.func("Request")
	Net.event("Profile").OnClientEvent:Connect(function(profile)
		ClientState.Profile = profile
		ClientState.Settings = profile.Settings
		ClientState.Changed:Fire(profile)
	end)
	Net.event("Party").OnClientEvent:Connect(function(payload)
		if payload.Type == "State" then
			ClientState.Party = payload
			ClientState.PartyChanged:Fire(payload)
		end
	end)
end

function ClientState.ErrorText(err: string?): string
	return ERRORS[err or ""] or tostring(err or "Something went wrong.")
end

-- Calls a server request. Returns ok, result|error.
function ClientState.Request(name: string, payload: any): (boolean, any)
	local ok, response = pcall(function()
		return requestFn:InvokeServer(name, payload)
	end)
	if not ok or type(response) ~= "table" then
		return false, "ServerError"
	end
	if response.Ok then
		return true, response.Result
	end
	return false, response.Error
end

function ClientState.LocalPlayer(): Player
	return Players.LocalPlayer
end

return ClientState
