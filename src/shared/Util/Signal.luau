--[[
	Signal
	Minimal synchronous signal for server-internal events (kills, discoveries, boss clears).
	Handlers run in their own thread so one failing handler cannot break the others.
]]

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(fn)
	local handler = { Fn = fn, Connected = true }
	table.insert(self._handlers, handler)
	local handlers = self._handlers
	return {
		Disconnect = function()
			handler.Connected = false
			local i = table.find(handlers, handler)
			if i then
				table.remove(handlers, i)
			end
		end,
	}
end

function Signal:Fire(...)
	for _, h in table.clone(self._handlers) do
		if h.Connected then
			task.spawn(h.Fn, ...)
		end
	end
end

return Signal
