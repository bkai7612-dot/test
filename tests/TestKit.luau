--[[
	TestKit
	Tiny test framework that runs both in the offline luau CLI bundle (tools/build_test_bundle.py)
	and inside Roblox Studio (ServerScriptService.Server.TestRunner, when Workspace attribute
	RunTests = true). Spec modules are ModuleScripts named "*.spec" returning function(t).
]]

local TestKit = {}

local function fmt(v)
	if type(v) == "string" then
		return string.format("%q", v)
	end
	return tostring(v)
end

local function deepEqual(a, b)
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for k, v in a do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

function TestKit.expect(actual)
	local e = {}
	function e.toBe(expected)
		if actual ~= expected then
			error(("expected %s to be %s"):format(fmt(actual), fmt(expected)), 2)
		end
	end
	function e.toEqual(expected)
		if not deepEqual(actual, expected) then
			error(("expected tables to be deeply equal (got %s)"):format(fmt(actual)), 2)
		end
	end
	function e.toBeTruthy()
		if not actual then
			error(("expected %s to be truthy"):format(fmt(actual)), 2)
		end
	end
	function e.toBeFalsy()
		if actual then
			error(("expected %s to be falsy"):format(fmt(actual)), 2)
		end
	end
	function e.toBeNear(expected, eps)
		if type(actual) ~= "number" or math.abs(actual - expected) > (eps or 1e-6) then
			error(("expected %s to be near %s"):format(fmt(actual), fmt(expected)), 2)
		end
	end
	function e.toBeAtLeast(n)
		if type(actual) ~= "number" or actual < n then
			error(("expected %s >= %s"):format(fmt(actual), fmt(n)), 2)
		end
	end
	function e.toBeAtMost(n)
		if type(actual) ~= "number" or actual > n then
			error(("expected %s <= %s"):format(fmt(actual), fmt(n)), 2)
		end
	end
	function e.toBeNil()
		if actual ~= nil then
			error(("expected nil, got %s"):format(fmt(actual)), 2)
		end
	end
	return e
end

-- Runs every *.spec module under `folder`. Returns true when all pass.
function TestKit.runAll(folder, requireFn, filter: string?)
	local passed, failed, total = 0, 0, 0
	local failures = {}
	local specs = {}
	for _, child in folder:GetChildren() do
		if string.sub(child.Name, -5) == ".spec" and (not filter or string.find(child.Name, filter, 1, true)) then
			table.insert(specs, child)
		end
	end
	table.sort(specs, function(a, b)
		return a.Name < b.Name
	end)
	for _, spec in specs do
		local suiteName = string.sub(spec.Name, 1, -6)
		local okLoad, specFn = pcall(requireFn, spec)
		if not okLoad then
			failed += 1
			total += 1
			table.insert(failures, suiteName .. " (load): " .. tostring(specFn))
		else
			local t = {
				expect = TestKit.expect,
				it = function(name, fn)
					total += 1
					local ok, err = pcall(fn)
					if ok then
						passed += 1
					else
						failed += 1
						table.insert(failures, suiteName .. " > " .. name .. ": " .. tostring(err))
					end
				end,
			}
			local okRun, err = pcall(specFn, t)
			if not okRun then
				failed += 1
				total += 1
				table.insert(failures, suiteName .. " (suite): " .. tostring(err))
			end
		end
	end
	for _, f in failures do
		print("FAIL  " .. f)
	end
	print(("Tests: %d passed, %d failed, %d total (%d suites)"):format(passed, failed, total, #specs))
	TestKit.LastResult = { Passed = passed, Failed = failed, Total = total, Failures = failures }
	return failed == 0
end

return TestKit
