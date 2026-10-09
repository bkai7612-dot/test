--[[
	NotifyService
	Toasts and banners sent to clients. Kinds: Info, Reward, Warning, Error, Banner, Discovery.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local NotifyService = {}
local remote: RemoteEvent

function NotifyService.Init(_services)
	remote = Net.event("Notify")
end
function NotifyService.Start() end

function NotifyService.Toast(player: Player, text: string, kind: string?)
	remote:FireClient(player, { Text = text, Kind = kind or "Info" })
end

function NotifyService.Banner(player: Player, title: string, subtitle: string?, kind: string?)
	remote:FireClient(player, { Banner = true, Text = title, Subtitle = subtitle, Kind = kind or "Banner" })
end

function NotifyService.All(text: string, kind: string?)
	remote:FireAllClients({ Text = text, Kind = kind or "Info" })
end

return NotifyService
