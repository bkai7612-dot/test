--[[
	PromoCodes (SERVER ONLY - lives in ServerScriptService, never replicated to clients)

	Fields:
	  Code        : the text players type (compared case-insensitively, spaces ignored)
	  Kind        : "Reward" (one-off bundle) | "Admin" (unlocks the admin panel)
	  MaxUses     : total redemptions across ALL servers (atomic DataStore counter); nil = unlimited
	  Reward      : for Kind "Reward": { Currency, Items = { [itemId] = n }, Title, Cosmetic }
	  Expires     : optional os.time() after which the code stops working
	Every code can be redeemed at most once per character.

	SECURITY: anyone who can read this repository can read these codes. Change them before
	making the repository public, and never put them in ReplicatedStorage.
]]

local PromoCodes = {
	admin_1 = { Code = "FKYCZ6BGQ3RF3HHDEGADWWCPZRW9XX", Kind = "Admin", MaxUses = 2 },
	admin_2 = { Code = "ZU2R2S4JQE29XFCR8NMU8HWQC33WEX", Kind = "Admin", MaxUses = 2 },
	-- example public code (edit or remove freely)
	launch = { Code = "TOWERLAUNCH", Kind = "Reward", MaxUses = nil,
		Reward = { Currency = 500, Items = { healing_draught = 3 } } },
}

for id, def in PromoCodes do
	def.Id = id
end

return PromoCodes
