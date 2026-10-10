-- ===== DataModel + Roblox service mocks for integration scenarios =====
T = 0 -- the simulated clock (os.clock, server time)
local __os = os
os = setmetatable({ clock = function() return T end }, { __index = __os })
local Node = {}
local NodeMethods = {}
Node.__index = function(self, key)
	local m = NodeMethods[key]
	if m then return m end
	local c = rawget(self, "_children")[key]
	if c then return c end
	error(("%s is not a valid member of %s"):format(tostring(key), rawget(self, "Name")), 2)
end
local function newNode(name, cls, parent)
	local n = setmetatable({ Name = name, ClassName = cls, Parent = parent, _children = {} }, Node)
	if parent then rawget(parent, "_children")[name] = n end
	return n
end
function NodeMethods.WaitForChild(self, n) return rawget(self, "_children")[n] or error("no child " .. n) end
function NodeMethods.FindFirstChild(self, n) return rawget(self, "_children")[n] end

Signal = {}
Signal.__index = Signal
function Signal.new() return setmetatable({ fns = {} }, Signal) end
function Signal:Connect(f) table.insert(self.fns, f); return { Disconnect = function() end } end
function Signal:Fire(...) for _, f in self.fns do f(...) end end

-- generic service: any member is a no-op function or a signal
local function generic(name)
	return setmetatable({ Name = name }, { __index = function(t, k)
		if k:match("^[A-Z].*ed$") or k == "Heartbeat" or k == "RenderStepped" or k == "Stepped" or k == "JumpRequest" then
			local s = Signal.new(); rawset(t, k, s); return s
		end
		return function() return nil end
	end })
end

QUEUE = {}
task = {
	spawn = function(f, ...) return f(...) end,
	defer = function(f, ...) return f(...) end,
	delay = function(d, f, ...) table.insert(QUEUE, { At = T + d, F = f, Args = table.pack(...) }) end,
	wait = function() return 0 end,
}
-- advance the clock, running scheduled task.delay callbacks in order
function advance(dt)
	local target = T + dt
	while true do
		table.sort(QUEUE, function(a, b) return a.At < b.At end)
		local nxt = QUEUE[1]
		if not nxt or nxt.At > target then break end
		table.remove(QUEUE, 1)
		T = nxt.At
		nxt.F(table.unpack(nxt.Args, 1, nxt.Args.n))
	end
	T = target
end

-- players
local function mkPlayer(userId)
	local p = Instance.new("Player")
	p.UserId = userId
	p.Name = "Tester" .. userId
	p.CharacterAdded = Signal.new()
	local char = Instance.new("Model")
	char.Name = "Character"
	local hum = Instance.new("Humanoid")
	hum.Health = 100
	hum.MoveDirection = Vector3.zero
	hum.StateChanged = Signal.new()
	hum.RigType = "HumanoidRigType.R15"
	hum.Parent = char
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.CFrame = CFrame.new(0, 3, 0)
	root.Position = Vector3.new(0, 3, 0)
	root.AssemblyLinearVelocity = Vector3.zero
	root.Parent = char
	p.Character = char
	return p, char, hum, root
end
LOCAL, CHAR, HUM, ROOT = mkPlayer(1)
local PlayersSvc = generic("Players")
PlayersSvc.LocalPlayer = LOCAL
PlayersSvc.PlayerRemoving = Signal.new()
PlayersSvc.PlayerAdded = Signal.new()
PlayersSvc.GetPlayers = function() return { LOCAL } end
PlayersSvc.GetPlayerByUserId = function(_, id) return if id == 1 then LOCAL else nil end
local UIS = generic("UserInputService")
UIS.JumpRequest = Signal.new()
USER_INPUT = UIS

local game = newNode("game", "DataModel", nil)
local SERVICES = { Players = PlayersSvc, UserInputService = UIS }
function NodeMethods.GetService(self, name)
	if SERVICES[name] then return SERVICES[name] end
	local c = rawget(self, "_children")[name]
	if c then return c end
	SERVICES[name] = generic(name)
	return SERVICES[name]
end
workspace = { GetServerTimeNow = function() return T end, Terrain = generic("Terrain"), FindFirstChild = function() return nil end }

local __cache, __loading = {}, {}
function __require(node)
	local c = __cache[node]
	if c ~= nil then return c end
	local fn = rawget(node, "_fn") or error("not a module: " .. tostring(rawget(node, "Name")))
	__cache[node] = fn(node)
	return __cache[node]
end
-- inject a module result directly (used to replace Shared.Net)
function inject(node, value) __cache[node] = value end
function __path(parts, cls)
	local n = game
	for i, name in parts do
		local c = rawget(n, "_children")[name]
		if not c then c = newNode(name, if i == #parts then cls else "Folder", n) end
		n = c
	end
	return n
end
typeof = function(v)
	if type(v) == "table" and v.X ~= nil and v.Z ~= nil then return "Vector3" end
	return type(v)
end
GAME = game
