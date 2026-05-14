-- run_tests.lua  (Phase g — DEV-9)
-- Unified test runner for all battle module acceptance tests.
-- Usage: cd pokebrave-server/data/scripts && lua battle/run_tests.lua

local function banner(text)
    print("")
    print(string.rep("=", 60))
    print("  " .. text)
    print(string.rep("=", 60))
end

local totalPassed = 0
local totalFailed = 0

local function runFile(path, label)
    banner(label)
    -- Run each test file in its own subprocess so an os.exit(1) in one
    -- does not kill the runner.
    local cmd = "lua " .. path
    local handle, err = io.popen(cmd, "r")
    if not handle then
        print("  [FAIL] could not spawn: " .. tostring(err))
        totalFailed = totalFailed + 1
        return
    end
    local output = handle:read("*a")
    local ok, exitType, code = handle:close()
    if output then
        print(output)
    end
    -- Lua 5.1 close() returns true/nil; Lua 5.2+ returns true/false, "exit", code.
    local success
    if ok == true then
        success = true
    elseif ok == nil or ok == false then
        success = false
    elseif type(ok) == "number" then
        success = (ok == 0)
    else
        success = (code == 0 or code == true)
    end
    if success then
        totalPassed = totalPassed + 1
    else
        totalFailed = totalFailed + 1
    end
end

runFile("battle/test_move_compat.lua",      "MoveCompat Tests")
runFile("battle/test_reconnect_smoke.lua",   "Reconnect Smoke Tests")
runFile("battle/test_desync_injection.lua", "Desync Injection Tests")

banner("Summary")
print(string.format("  Test suites passed: %d", totalPassed))
print(string.format("  Test suites failed: %d", totalFailed))
print("")

if totalFailed > 0 then
    print("  RESULT: FAILED")
    os.exit(1)
else
    print("  RESULT: PASSED")
    os.exit(0)
end
