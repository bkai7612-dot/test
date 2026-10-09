--[[
	InputController
	Binds keyboard/mouse, gamepad and touch through ContextActionService. Touch buttons are
	created by CAS and arranged around the jump button. Bindings:

	  Action        Keyboard/Mouse     Gamepad        Touch
	  Light attack  LMB                R1             Attack
	  Heavy (hold)  R                  R2             Heavy
	  Block (hold)  RMB                L1             Block
	  Parry         F                  L2             Parry
	  Dodge/roll    Q                  B              Dodge
	  Sprint        Left Shift (hold)  L3 (toggle)    Sprint (toggle)
	  Lock-on       T / MMB            R3             Lock
	  Switch target Mouse wheel        D-pad L/R      Switch
	  Ability 1/2   Z / X              Y / D-pad Up   Skill 1 / Skill 2
	  Ember Flask   H                  X              Flask
	  Quick items   1 / 2 / 3          D-pad Down     -
	  Menu          Tab / M            Select/Start   Menu
	While a weightlifting session is active, the attack input performs a rep instead.
]]

local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local InputController = {
	RepMode = false,
	MenuOpen = false,
	CursorFree = false,
}

local Combat, Camera, Menu, ClientState
local sprintToggle = false
local BEGIN = Enum.UserInputState.Begin
local END = Enum.UserInputState.End

local QUICK = { "healing_draught", "mana_tonic", "stamina_tonic" }

local function bind(name: string, fn, touchTitle: string?, ...)
	ContextActionService:BindAction(name, function(_, state, input)
		if InputController.MenuOpen and name ~= "TotfMenu" then
			return Enum.ContextActionResult.Pass
		end
		fn(state, input)
		return Enum.ContextActionResult.Sink
	end, touchTitle ~= nil, ...)
	if touchTitle then
		ContextActionService:SetTitle(name, touchTitle)
	end
end

function InputController.Init(deps)
	Combat = deps.CombatController
	Camera = deps.CameraController
	Menu = deps.MenuController
	ClientState = deps.ClientState
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	end)

	bind("TotfLight", function(state)
		if state == BEGIN then
			if InputController.RepMode then
				Combat.Rep()
			else
				Combat.Light()
			end
		end
	end, "Attack", Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR1)
	bind("TotfHeavy", function(state)
		if state == BEGIN then
			Combat.HeavyBegin()
		elseif state == END then
			Combat.HeavyEnd()
		end
	end, "Heavy", Enum.KeyCode.R, Enum.KeyCode.ButtonR2)
	bind("TotfBlock", function(state)
		Combat.SetBlock(state == BEGIN)
	end, "Block", Enum.UserInputType.MouseButton2, Enum.KeyCode.ButtonL1)
	bind("TotfParry", function(state)
		if state == BEGIN then
			Combat.Parry()
		end
	end, "Parry", Enum.KeyCode.F, Enum.KeyCode.ButtonL2)
	bind("TotfDodge", function(state)
		if state == BEGIN then
			Combat.Dodge()
		end
	end, "Dodge", Enum.KeyCode.Q, Enum.KeyCode.ButtonB)
	bind("TotfSprint", function(state, input)
		if input.UserInputType == Enum.UserInputType.Touch or input.KeyCode == Enum.KeyCode.ButtonL3 then
			if state == BEGIN then
				sprintToggle = not sprintToggle
				Combat.SetSprint(sprintToggle)
			end
		else
			Combat.SetSprint(state == BEGIN)
		end
	end, "Sprint", Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)
	bind("TotfLock", function(state)
		if state == BEGIN then
			Camera.ToggleLock()
		end
	end, "Lock", Enum.KeyCode.T, Enum.UserInputType.MouseButton3, Enum.KeyCode.ButtonR3)
	bind("TotfSwitchL", function(state)
		if state == BEGIN then
			Camera.Switch(-1)
		end
	end, nil, Enum.KeyCode.DPadLeft)
	bind("TotfSwitchR", function(state)
		if state == BEGIN then
			Camera.Switch(1)
		end
	end, "Switch", Enum.KeyCode.DPadRight)
	bind("TotfAbility1", function(state)
		if state == BEGIN then
			Combat.Ability("Slot1")
		end
	end, "Skill 1", Enum.KeyCode.Z, Enum.KeyCode.ButtonY)
	bind("TotfAbility2", function(state)
		if state == BEGIN then
			Combat.Ability("Slot2")
		end
	end, "Skill 2", Enum.KeyCode.X, Enum.KeyCode.DPadUp)
	bind("TotfFlask", function(state)
		if state == BEGIN then
			Combat.Flask()
		end
	end, "Flask", Enum.KeyCode.H, Enum.KeyCode.ButtonX)
	bind("TotfQuick", function(state, input)
		if state ~= BEGIN then
			return
		end
		local idx = if input.KeyCode == Enum.KeyCode.One then 1 elseif input.KeyCode == Enum.KeyCode.Two then 2 elseif input.KeyCode == Enum.KeyCode.Three then 3 else 1
		Combat.UseItem(QUICK[idx])
	end, nil, Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.DPadDown)
	bind("TotfMenu", function(state)
		if state == BEGIN then
			Menu.Toggle()
		end
	end, "Menu", Enum.KeyCode.Tab, Enum.KeyCode.M, Enum.KeyCode.ButtonSelect, Enum.KeyCode.ButtonStart)

	-- arrange touch buttons in an arc around the jump button
	local layout = {
		TotfLight = UDim2.new(1, -95, 1, -170),
		TotfHeavy = UDim2.new(1, -165, 1, -150),
		TotfDodge = UDim2.new(1, -200, 1, -90),
		TotfBlock = UDim2.new(1, -165, 1, -220),
		TotfParry = UDim2.new(1, -95, 1, -240),
		TotfAbility1 = UDim2.new(1, -235, 1, -200),
		TotfAbility2 = UDim2.new(1, -235, 1, -265),
		TotfFlask = UDim2.new(1, -270, 1, -140),
		TotfLock = UDim2.new(1, -95, 1, -310),
		TotfSwitchR = UDim2.new(1, -165, 1, -290),
		TotfSprint = UDim2.new(0, 30, 1, -260),
		TotfMenu = UDim2.new(0, 30, 0, 140),
	}
	for name, pos in layout do
		pcall(function()
			ContextActionService:SetPosition(name, pos)
		end)
	end

	-- combat mouse lock on desktop (frees RMB for blocking)
	RunService:BindToRenderStep("TotfMouseLock", Enum.RenderPriority.Camera.Value + 2, function()
		local settings = ClientState.Settings
		local wantLock = settings == nil or settings.MouseLock ~= false
		if UserInputService.MouseEnabled and not UserInputService.TouchEnabled then
			if wantLock and not InputController.MenuOpen and not InputController.CursorFree then
				UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
			elseif InputController.MenuOpen or InputController.CursorFree then
				UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			end
		end
		if settings and settings.CameraSensitivity then
			UserInputService.MouseDeltaSensitivity = math.clamp(settings.CameraSensitivity, 0.2, 3)
		end
	end)
	-- hold Left Alt to free the cursor temporarily
	UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.LeftAlt then
			InputController.CursorFree = true
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.LeftAlt then
			InputController.CursorFree = false
		end
	end)
end

function InputController.SetMenuOpen(open: boolean)
	InputController.MenuOpen = open
	if open then
		Combat.SetBlock(false)
	end
end

return InputController
