--[[
	PartyService
	Server-side parties (per server) using PartyCore. Pushes party state to members and invites
	to targets. Parties are optional: everything in the game is completable solo.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local PartyCore = require(script.Parent.Parent.Core.PartyCore)

local PartyService = {}
local S
local state = PartyCore.newState()
local remote: RemoteEvent

function PartyService.Init(services)
	S = services
	remote = Net.event("Party")
end

local function playerById(uid)
	return Players:GetPlayerByUserId(uid)
end

function PartyService.Members(player: Player): { Player }
	local out = {}
	for _, uid in PartyCore.members(state, player.UserId) do
		local p = playerById(uid)
		if p then
			table.insert(out, p)
		end
	end
	return out
end

function PartyService.IsLeader(player: Player): boolean
	local party = PartyCore.get(state, player.UserId)
	return party == nil or party.Leader == player.UserId
end

local function pushState(uid)
	local plr = playerById(uid)
	if not plr then
		return
	end
	local party = PartyCore.get(state, uid)
	local payload = { Type = "State", Members = {}, Leader = nil }
	if party then
		payload.Leader = party.Leader
		for _, m in party.Members do
			local mp = playerById(m)
			local rt = mp and S.PlayerStateService.Get(mp)
			table.insert(payload.Members, {
				UserId = m,
				Name = mp and mp.DisplayName or "?",
				Level = rt and rt.Profile.Level or 0,
				Class = rt and rt.Profile.Class or "",
				Floor = rt and rt.Profile.Tower.HighestCleared or 0,
			})
		end
	end
	remote:FireClient(plr, payload)
end

local function pushParty(uid)
	for _, m in PartyCore.members(state, uid) do
		pushState(m)
	end
end

function PartyService.Start()
	local R = S.RequestService

	R.Register("PartyInvite", function(player, rt, targetUserId)
		local target = type(targetUserId) == "number" and playerById(targetUserId)
		if not target or not S.PlayerStateService.Get(target) then
			return false, "PlayerNotFound"
		end
		local ok, err = PartyCore.invite(state, player.UserId, target.UserId, os.time())
		if not ok then
			return false, err
		end
		remote:FireClient(target, { Type = "Invite", From = player.UserId, FromName = player.DisplayName })
		pushParty(player.UserId)
		return true, nil
	end)

	R.Register("PartyRespond", function(player, rt, accept)
		if accept == true then
			local ok, err = PartyCore.accept(state, player.UserId, os.time())
			if not ok then
				return false, err
			end
			pushParty(player.UserId)
			for _, m in PartyService.Members(player) do
				if m ~= player then
					S.NotifyService.Toast(m, player.DisplayName .. " joined the party.", "Info")
				end
			end
			return true, nil
		end
		return PartyCore.decline(state, player.UserId)
	end)

	R.Register("PartyLeave", function(player)
		local before = PartyCore.members(state, player.UserId)
		local ok, err = PartyCore.leave(state, player.UserId)
		for _, uid in before do
			pushState(uid)
		end
		return ok, err
	end)

	R.Register("PartyKick", function(player, rt, targetUserId)
		local before = PartyCore.members(state, player.UserId)
		local ok, err = PartyCore.kick(state, player.UserId, targetUserId)
		for _, uid in before do
			pushState(uid)
		end
		return ok, err
	end)

	R.Register("PartyPromote", function(player, rt, targetUserId)
		local ok, err = PartyCore.promote(state, player.UserId, targetUserId)
		pushParty(player.UserId)
		return ok, err
	end)

	Players.PlayerRemoving:Connect(function(player)
		local before = PartyCore.members(state, player.UserId)
		PartyCore.leave(state, player.UserId)
		for _, uid in before do
			if uid ~= player.UserId then
				pushState(uid)
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(10)
			PartyCore.pruneInvites(state, os.time())
		end
	end)
end

return PartyService
