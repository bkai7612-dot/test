-- Shared helpers for specs.
local SSS = game:GetService("ServerScriptService")
local Core = SSS.Server.Core
local ProfileSchema = require(Core.ProfileSchema)
local ProgressionCore = require(Core.ProgressionCore)
local Rng = require(game:GetService("ReplicatedStorage").Shared.Util.Rng)

local Helpers = {}

function Helpers.profile(className: string?)
	local p = ProfileSchema.reconcile(ProfileSchema.default())
	if className then
		ProgressionCore.chooseClass(p, className)
	end
	return p
end

function Helpers.rng(seed)
	return Rng.new(seed or 12345)
end

function Helpers.snapshot(v)
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = Helpers.snapshot(x)
	end
	return out
end

return Helpers
