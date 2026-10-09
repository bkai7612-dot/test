--[[
	Client entry point. Wires controllers together; each controller only presents state and
	sends intents - all outcomes are decided by the server.
]]

local Controllers = script.Parent:WaitForChild("Controllers")

local UIKit = require(Controllers.UIKit)
local ClientState = require(Controllers.ClientState)
local AudioController = require(Controllers.AudioController)
local CameraController = require(Controllers.CameraController)
local CombatController = require(Controllers.CombatController)
local InputController = require(Controllers.InputController)
local HUDController = require(Controllers.HUDController)
local MenuController = require(Controllers.MenuController)
local EffectsController = require(Controllers.EffectsController)

local deps = {
	UIKit = UIKit,
	ClientState = ClientState,
	AudioController = AudioController,
	CameraController = CameraController,
	CombatController = CombatController,
	InputController = InputController,
	HUDController = HUDController,
	MenuController = MenuController,
	EffectsController = EffectsController,
}

ClientState.Init()
AudioController.Init()
CameraController.Init()
CombatController.Init(deps)
HUDController.Init(deps)
MenuController.Init(deps)
InputController.Init(deps)
EffectsController.Init(deps)

MenuController.OnSettings = function(settings)
	EffectsController.ApplySettings(settings)
end
