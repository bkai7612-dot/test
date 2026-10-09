--[[
	PartyCore
	Pure party state machine: invite, accept, decline, leave, kick, promote, disband.
	State is per-server (parties do not persist across servers).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)

local PartyCore = {}

function PartyCore.newState()
	return { Parties = {}, MemberOf = {}, Invites = {}, NextId = 1 }
end

function PartyCore.get(state, uid)
	local pid = state.MemberOf[uid]
	return pid and state.Parties[pid], pid
end

function PartyCore.members(state, uid)
	local party = PartyCore.get(state, uid)
	if not party then
		return { uid }
	end
	return table.clone(party.Members)
end

local function createParty(state, leader)
	local pid = "p" .. state.NextId
	state.NextId += 1
	state.Parties[pid] = { Id = pid, Leader = leader, Members = { leader } }
	state.MemberOf[leader] = pid
	return state.Parties[pid], pid
end

local function disband(state, pid)
	local party = state.Parties[pid]
	if not party then
		return
	end
	for _, m in party.Members do
		state.MemberOf[m] = nil
	end
	state.Parties[pid] = nil
	for target, inv in state.Invites do
		if inv.Party == pid then
			state.Invites[target] = nil
		end
	end
end

-- Invites[target] = { From, Party, Expires }  (one pending invite per target)
function PartyCore.invite(state, from, to, now: number)
	if from == to then
		return false, "Self"
	end
	if state.MemberOf[to] then
		return false, "TargetInParty"
	end
	local party, pid = PartyCore.get(state, from)
	if party and party.Leader ~= from then
		return false, "NotLeader"
	end
	if party and #party.Members >= GameConfig.Party.MaxSize then
		return false, "PartyFull"
	end
	if not party then
		party, pid = createParty(state, from)
	end
	state.Invites[to] = { From = from, Party = pid, Expires = now + GameConfig.Party.InviteExpiry }
	return true, pid
end

function PartyCore.accept(state, uid, now: number)
	local inv = state.Invites[uid]
	if not inv then
		return false, "NoInvite"
	end
	state.Invites[uid] = nil
	if now > inv.Expires then
		return false, "Expired"
	end
	if state.MemberOf[uid] then
		return false, "AlreadyInParty"
	end
	local party = state.Parties[inv.Party]
	if not party then
		return false, "PartyGone"
	end
	if #party.Members >= GameConfig.Party.MaxSize then
		return false, "PartyFull"
	end
	table.insert(party.Members, uid)
	state.MemberOf[uid] = inv.Party
	return true, inv.Party
end

function PartyCore.decline(state, uid)
	if not state.Invites[uid] then
		return false, "NoInvite"
	end
	state.Invites[uid] = nil
	return true, nil
end

function PartyCore.leave(state, uid)
	local party, pid = PartyCore.get(state, uid)
	state.Invites[uid] = nil
	if not party then
		return false, "NotInParty"
	end
	local idx = table.find(party.Members, uid)
	if idx then
		table.remove(party.Members, idx)
	end
	state.MemberOf[uid] = nil
	if #party.Members <= 1 then
		disband(state, pid)
		return true, "Disbanded"
	end
	if party.Leader == uid then
		party.Leader = party.Members[1]
	end
	return true, pid
end

function PartyCore.kick(state, leader, target)
	local party = PartyCore.get(state, leader)
	if not party or party.Leader ~= leader then
		return false, "NotLeader"
	end
	if leader == target or not table.find(party.Members, target) then
		return false, "InvalidTarget"
	end
	return PartyCore.leave(state, target)
end

function PartyCore.promote(state, leader, target)
	local party = PartyCore.get(state, leader)
	if not party or party.Leader ~= leader then
		return false, "NotLeader"
	end
	if not table.find(party.Members, target) then
		return false, "InvalidTarget"
	end
	party.Leader = target
	return true, target
end

function PartyCore.pruneInvites(state, now: number)
	for target, inv in state.Invites do
		if now > inv.Expires then
			state.Invites[target] = nil
		end
	end
	-- disband parties that were created by an invite nobody accepted
	for pid, party in state.Parties do
		if #party.Members <= 1 then
			local pending = false
			for _, inv in state.Invites do
				if inv.Party == pid then
					pending = true
				end
			end
			if not pending then
				disband(state, pid)
			end
		end
	end
end

return PartyCore
