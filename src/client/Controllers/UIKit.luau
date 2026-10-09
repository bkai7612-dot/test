--[[
	UIKit
	Small helper library for building the dark-fantasy interface in code: theme, frames,
	labels, buttons (mouse/touch/gamepad selectable), bars and scrolling lists.
]]

local TweenService = game:GetService("TweenService")

local UIKit = {}

UIKit.Theme = {
	Bg = Color3.fromRGB(14, 12, 16),
	Panel = Color3.fromRGB(26, 23, 28),
	Panel2 = Color3.fromRGB(36, 32, 38),
	Border = Color3.fromRGB(110, 88, 56),
	Accent = Color3.fromRGB(214, 170, 90),
	Text = Color3.fromRGB(236, 226, 206),
	Muted = Color3.fromRGB(160, 150, 136),
	Danger = Color3.fromRGB(210, 60, 50),
	Good = Color3.fromRGB(110, 200, 120),
	Health = Color3.fromRGB(190, 40, 40),
	Stamina = Color3.fromRGB(90, 170, 70),
	Mana = Color3.fromRGB(70, 110, 220),
	Xp = Color3.fromRGB(214, 170, 90),
	Font = Enum.Font.Garamond,
	FontBold = Enum.Font.GothamBold,
}
local T = UIKit.Theme

function UIKit.new(className: string, props, children)
	local inst = Instance.new(className)
	for k, v in props or {} do
		if k ~= "Parent" then
			(inst :: any)[k] = v
		end
	end
	for _, child in children or {} do
		child.Parent = inst
	end
	if props and props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

function UIKit.corner(parent: Instance, r: number?)
	return UIKit.new("UICorner", { CornerRadius = UDim.new(0, r or 6), Parent = parent })
end

function UIKit.stroke(parent: Instance, color: Color3?, thickness: number?)
	return UIKit.new("UIStroke", { Color = color or T.Border, Thickness = thickness or 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = parent })
end

function UIKit.padding(parent: Instance, px: number)
	return UIKit.new("UIPadding", {
		PaddingTop = UDim.new(0, px), PaddingBottom = UDim.new(0, px), PaddingLeft = UDim.new(0, px), PaddingRight = UDim.new(0, px), Parent = parent,
	})
end

function UIKit.panel(props)
	props.BackgroundColor3 = props.BackgroundColor3 or T.Panel
	props.BorderSizePixel = 0
	local f = UIKit.new("Frame", props)
	UIKit.corner(f, 8)
	UIKit.stroke(f)
	return f
end

function UIKit.label(text: string, props)
	props = props or {}
	props.Text = text
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.Font = props.Font or T.Font
	props.TextColor3 = props.TextColor3 or T.Text
	props.TextSize = props.TextSize or 18
	props.TextWrapped = if props.TextWrapped == nil then true else props.TextWrapped
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	return UIKit.new("TextLabel", props)
end

function UIKit.button(text: string, onClick: () -> (), props)
	props = props or {}
	props.Text = text
	props.AutoButtonColor = true
	props.BackgroundColor3 = props.BackgroundColor3 or T.Panel2
	props.Font = props.Font or T.Font
	props.TextColor3 = props.TextColor3 or T.Text
	props.TextSize = props.TextSize or 18
	props.Size = props.Size or UDim2.fromOffset(140, 36)
	props.Selectable = true
	local b = UIKit.new("TextButton", props) :: TextButton
	UIKit.corner(b, 6)
	UIKit.stroke(b, T.Border, 1)
	b.Activated:Connect(function()
		onClick()
	end)
	return b
end

-- Vertical scrolling list that grows with its content.
function UIKit.list(props, spacing: number?)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.BorderSizePixel = 0
	props.ScrollBarThickness = props.ScrollBarThickness or 6
	props.ScrollBarImageColor3 = T.Border
	props.AutomaticCanvasSize = Enum.AutomaticSize.Y
	props.CanvasSize = UDim2.new()
	props.ScrollingDirection = Enum.ScrollingDirection.Y
	local s = UIKit.new("ScrollingFrame", props)
	UIKit.new("UIListLayout", { Padding = UDim.new(0, spacing or 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = s })
	return s
end

function UIKit.clear(container: Instance)
	for _, c in container:GetChildren() do
		if not c:IsA("UIListLayout") and not c:IsA("UIGridLayout") and not c:IsA("UIPadding") and not c:IsA("UICorner") and not c:IsA("UIStroke") then
			c:Destroy()
		end
	end
end

-- Resource bar. Returns an object with :Set(current, max).
function UIKit.bar(parent: Instance, color: Color3, props)
	props = props or {}
	props.BackgroundColor3 = Color3.fromRGB(20, 18, 20)
	props.BorderSizePixel = 0
	props.Parent = parent
	local bg = UIKit.new("Frame", props)
	UIKit.corner(bg, 4)
	UIKit.stroke(bg, Color3.fromRGB(60, 50, 40), 1)
	local lag = UIKit.new("Frame", { BackgroundColor3 = Color3.fromRGB(230, 200, 150), BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Parent = bg })
	UIKit.corner(lag, 4)
	local fill = UIKit.new("Frame", { BackgroundColor3 = color, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Parent = bg })
	UIKit.corner(fill, 4)
	local text = UIKit.label("", { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 14, Font = T.FontBold, Parent = bg, ZIndex = 3 })
	local obj = {}
	local lastFrac = -1
	function obj.Set(_self, current: number, max: number, showText: boolean?)
		local frac = if max > 0 then math.clamp(current / max, 0, 1) else 0
		text.Text = if showText ~= false then ("%d / %d"):format(math.floor(current), math.floor(max)) else ""
		if math.abs(frac - lastFrac) < 0.001 then
			return
		end
		local dropped = frac < lastFrac
		lastFrac = frac
		fill.Size = UDim2.fromScale(frac, 1)
		if dropped then
			-- damage "lag" chip shows how much was lost
			TweenService:Create(lag, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0.25), { Size = UDim2.fromScale(frac, 1) }):Play()
		else
			lag.Size = UDim2.fromScale(frac, 1)
		end
	end
	obj.Frame = bg
	obj.Text = text
	return obj
end

function UIKit.tween(inst: Instance, t: number, props)
	local tw = TweenService:Create(inst, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

return UIKit
