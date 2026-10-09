--[[
	AudioController
	SFX through a pooled set of Sounds in SoundGroups ("SFX", "Music") whose volumes come
	from player settings. Music switches between hub / wilds / boss tracks when IDs are set.
]]

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Audio = require(ReplicatedStorage:WaitForChild("Shared").Config.Audio)

local AudioController = {}
local sfxGroup: SoundGroup, musicGroup: SoundGroup
local music: Sound
local currentTrack = ""

function AudioController.Init()
	sfxGroup = Instance.new("SoundGroup")
	sfxGroup.Name = "SFX"
	sfxGroup.Volume = 0.8
	sfxGroup.Parent = SoundService
	musicGroup = Instance.new("SoundGroup")
	musicGroup.Name = "Music"
	musicGroup.Volume = 0.5
	musicGroup.Parent = SoundService
	music = Instance.new("Sound")
	music.Name = "MusicTrack"
	music.Looped = true
	music.SoundGroup = musicGroup
	music.Parent = SoundService
end

function AudioController.ApplySettings(settings)
	if not settings then
		return
	end
	sfxGroup.Volume = settings.SfxVolume or 0.8
	musicGroup.Volume = settings.MusicVolume or 0.5
end

function AudioController.Play(name: string, position: Vector3?)
	local def = Audio.Sfx[name]
	if not def or def.Id == "" then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = def.Id
	s.Volume = def.Volume or 0.5
	local pr = def.PitchRange or { 1, 1 }
	s.PlaybackSpeed = pr[1] + math.random() * (pr[2] - pr[1])
	s.SoundGroup = sfxGroup
	if position then
		local att = Instance.new("Attachment")
		att.WorldPosition = position
		att.Parent = workspace.Terrain
		s.Parent = att
		s.Ended:Connect(function()
			att:Destroy()
		end)
		task.delay(5, function()
			if att.Parent then
				att:Destroy()
			end
		end)
	else
		s.Parent = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui") or SoundService
		s.Ended:Connect(function()
			s:Destroy()
		end)
		task.delay(5, function()
			if s.Parent then
				s:Destroy()
			end
		end)
	end
	s:Play()
end

function AudioController.SetMusic(track: string)
	if track == currentTrack then
		return
	end
	currentTrack = track
	local id = Audio.Music[track] or ""
	music:Stop()
	if id ~= "" then
		music.SoundId = id
		music:Play()
	end
end

return AudioController
