--[[
	CosmeticService
	Purely visual: auras (particles), weapon finishes, armour dyes and the overhead title.
	Nothing here reads or writes combat statistics.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cosmetics = require(Shared.Config.Cosmetics)
local Classes = require(Shared.Config.Classes)

local CosmeticService = {}
local S

function CosmeticService.Init(services)
	S = services
end

function CosmeticService.Refresh(player: Player)
	local rt = S.PlayerStateService.Get(player)
	local char = rt and rt.Character
	if not char or not rt.Root then
		return
	end
	local eq = rt.Profile.Cosmetics.Equipped
	-- aura
	local old = rt.Root:FindFirstChild("CosmeticAura")
	if old then
		old:Destroy()
	end
	local aura = Cosmetics[eq.Aura]
	if aura and aura.Type == "Aura" and rt.Profile.Cosmetics.Owned[eq.Aura] then
		local e = Instance.new("ParticleEmitter")
		e.Name = "CosmeticAura"
		e.Color = ColorSequence.new(aura.Color)
		e.LightEmission = 0.6
		e.Rate = 12
		e.Lifetime = NumberRange.new(1, 1.6)
		e.Speed = NumberRange.new(0.5, 1.5)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Size = NumberSequence.new(0.5, 0)
		e.Transparency = NumberSequence.new(0.3, 1)
		e.Parent = rt.Root
	end
	-- armour dye tints body colors (cosmetic only)
	local dye = Cosmetics[eq.ArmorDye]
	local bc = char:FindFirstChildOfClass("BodyColors")
	if bc and dye and dye.Type == "ArmorDye" and rt.Profile.Cosmetics.Owned[eq.ArmorDye] then
		bc.TorsoColor3 = dye.Color
		bc.LeftLegColor3 = dye.Color
		bc.RightLegColor3 = dye.Color
	end
	-- overhead title
	local head = char:FindFirstChild("Head")
	if head then
		local tag = head:FindFirstChild("TitleTag") :: BillboardGui?
		if not tag then
			local b = Instance.new("BillboardGui")
			b.Name = "TitleTag"
			b.Size = UDim2.fromOffset(220, 46)
			b.StudsOffset = Vector3.new(0, 2.6, 0)
			b.MaxDistance = 80
			b.AlwaysOnTop = false
			local name = Instance.new("TextLabel")
			name.Name = "NameLabel"
			name.BackgroundTransparency = 1
			name.Size = UDim2.new(1, 0, 0.55, 0)
			name.Font = Enum.Font.Garamond
			name.TextScaled = true
			name.TextColor3 = Color3.fromRGB(235, 225, 200)
			name.TextStrokeTransparency = 0.4
			name.Parent = b
			local title = Instance.new("TextLabel")
			title.Name = "TitleLabel"
			title.BackgroundTransparency = 1
			title.Position = UDim2.new(0, 0, 0.55, 0)
			title.Size = UDim2.new(1, 0, 0.45, 0)
			title.Font = Enum.Font.Garamond
			title.TextScaled = true
			title.TextColor3 = Color3.fromRGB(230, 180, 90)
			title.TextStrokeTransparency = 0.5
			title.Parent = b
			b.Parent = head
			tag = b
		end
		local class = Classes[rt.Profile.Class]
		local nameLabel = (tag :: BillboardGui):FindFirstChild("NameLabel") :: TextLabel
		local titleLabel = (tag :: BillboardGui):FindFirstChild("TitleLabel") :: TextLabel
		nameLabel.Text = ("%s  Lv.%d"):format(player.DisplayName, rt.Profile.Level)
		local t = rt.Profile.ActiveTitle
		titleLabel.Text = if t ~= "" then ("<%s>"):format(t) elseif class then class.Name else ""
		local hum = rt.Humanoid
		if hum then
			hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
	end
end

function CosmeticService.Start()
	S.PlayerStateService.CharacterReady:Connect(function(player)
		task.delay(0.5, CosmeticService.Refresh, player)
	end)
	S.RequestService.Register("EquipCosmetic", function(player, rt, payload)
		if type(payload) ~= "table" or type(payload.Slot) ~= "string" then
			return false, "BadRequest"
		end
		local slot = payload.Slot
		if rt.Profile.Cosmetics.Equipped[slot] == nil then
			return false, "BadSlot"
		end
		local id = payload.Id
		if id ~= "" then
			local c = Cosmetics[id]
			local typeForSlot = { Aura = "Aura", WeaponSkin = "WeaponSkin", ArmorDye = "ArmorDye" }
			if not c or c.Type ~= typeForSlot[slot] or not rt.Profile.Cosmetics.Owned[id] then
				return false, "NotOwned"
			end
		end
		rt.Profile.Cosmetics.Equipped[slot] = id
		CosmeticService.Refresh(player)
		if slot == "WeaponSkin" then
			S.InventoryService.ApplyWeaponVisual(player)
		end
		S.PlayerStateService.Sync(player)
		return true, id
	end)
end

return CosmeticService
