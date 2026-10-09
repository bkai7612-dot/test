--[[
	TestRunner
	Runs the automated spec suite inside Roblox Studio. To use: select Workspace, add a boolean
	attribute RunTests = true, then press Play (or Run). Results print to the Output window and
	are reported through TestService. The same specs run offline via tools/run_tests.sh.
]]

local ServerStorage = game:GetService("ServerStorage")
local TestService = game:GetService("TestService")

if workspace:GetAttribute("RunTests") ~= true then
	return
end

local tests = ServerStorage:WaitForChild("Tests")
local TestKit = require(tests:WaitForChild("TestKit"))
local ok = TestKit.runAll(tests, require, nil)
local result = TestKit.LastResult
if ok then
	TestService:Message(("All %d tests passed"):format(result.Total))
else
	for _, f in result.Failures do
		TestService:Error(f)
	end
end
