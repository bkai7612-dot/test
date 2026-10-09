local PartyCore = require(game:GetService("ServerScriptService").Server.Core.PartyCore)

return function(t)
	local expect = t.expect

	t.it("invite and accept forms a party", function()
		local s = PartyCore.newState()
		expect((PartyCore.invite(s, 1, 2, 0))).toBe(true)
		expect((PartyCore.accept(s, 2, 1))).toBe(true)
		expect(#PartyCore.members(s, 1)).toBe(2)
		expect(PartyCore.get(s, 1).Leader).toBe(1)
	end)

	t.it("expired invites fail", function()
		local s = PartyCore.newState()
		PartyCore.invite(s, 1, 2, 0)
		local ok, err = PartyCore.accept(s, 2, 1000)
		expect(ok).toBe(false)
		expect(err).toBe("Expired")
	end)

	t.it("only the leader may invite, kick or promote", function()
		local s = PartyCore.newState()
		PartyCore.invite(s, 1, 2, 0)
		PartyCore.accept(s, 2, 0)
		expect((PartyCore.invite(s, 2, 3, 0))).toBe(false)
		expect((PartyCore.kick(s, 2, 1))).toBe(false)
		expect((PartyCore.promote(s, 1, 2))).toBe(true)
		expect((PartyCore.kick(s, 2, 1))).toBe(true)
		expect(PartyCore.get(s, 2)).toBeNil() -- disbanded at 1 member
	end)

	t.it("party size is capped", function()
		local s = PartyCore.newState()
		for i = 2, 4 do
			PartyCore.invite(s, 1, i, 0)
			PartyCore.accept(s, i, 0)
		end
		expect((PartyCore.invite(s, 1, 5, 0))).toBe(false)
	end)

	t.it("leader leaving promotes the next member", function()
		local s = PartyCore.newState()
		for i = 2, 3 do
			PartyCore.invite(s, 1, i, 0)
			PartyCore.accept(s, i, 0)
		end
		PartyCore.leave(s, 1)
		expect(PartyCore.get(s, 2).Leader).toBe(2)
	end)

	t.it("cannot be in two parties", function()
		local s = PartyCore.newState()
		PartyCore.invite(s, 1, 2, 0)
		PartyCore.accept(s, 2, 0)
		expect((PartyCore.invite(s, 3, 2, 0))).toBe(false)
	end)

	t.it("unanswered solo parties are pruned", function()
		local s = PartyCore.newState()
		PartyCore.invite(s, 1, 2, 0)
		PartyCore.pruneInvites(s, 1000)
		expect(PartyCore.get(s, 1)).toBeNil()
	end)
end
