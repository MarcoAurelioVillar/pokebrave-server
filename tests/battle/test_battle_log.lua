-- test_battle_log.lua  (Phase g — DEV-9)
-- Isolated unit tests for BattleLog (append, getSince, getSnapshot, applySnapshot, count).

local BattleLog = require("battle.BattleLog")

local function assertEq(a, b, msg)
    if a ~= b then
        error(string.format("ASSERT FAIL: %s | expected %s, got %s", msg or "", tostring(b), tostring(a)))
    end
end

local function assertTrue(a, msg)
    if not a then
        error(string.format("ASSERT FAIL: %s | expected true, got %s", msg or "", tostring(a)))
    end
end

local passed = 0
local failed = 0

local function run(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
        print("  [PASS] " .. name)
    else
        failed = failed + 1
        print("  [FAIL] " .. name .. " -> " .. tostring(err))
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Test 1: append returns monotonic seq
-- ─────────────────────────────────────────────────────────────────────────────
run("append_monotonic_seq", function()
    local log = BattleLog.new()
    local s1 = log:append("in", "choice", { slot = "p1a" })
    local s2 = log:append("internal", "turn_begin", { turn = 1 })
    local s3 = log:append("out", "event", { kind = "damage" })
    assertEq(s1, 1, "first seq")
    assertEq(s2, 2, "second seq")
    assertEq(s3, 3, "third seq")
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Test 2: getSince returns correct subset
-- ─────────────────────────────────────────────────────────────────────────────
run("getSince_subset", function()
    local log = BattleLog.new()
    log:append("in", "choice", { slot = "p1a" })
    log:append("internal", "turn_begin", { turn = 1 })
    log:append("out", "event", { kind = "damage" })

    local subset = log:getSince(2)
    assertEq(#subset, 2, "two entries from seq 2")
    assertEq(subset[1].seq, 2, "first subset seq")
    assertEq(subset[2].seq, 3, "second subset seq")

    local empty = log:getSince(5)
    assertEq(#empty, 0, "no entries from seq 5")
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Test 3: getSnapshot captures full state
-- ─────────────────────────────────────────────────────────────────────────────
run("getSnapshot_full", function()
    local log = BattleLog.new()
    log:append("in", "choice", { slot = "p1a" })
    local snap = log:getSnapshot()
    assertEq(snap.headSeq, 1, "snapshot headSeq")
    assertEq(#snap.entries, 1, "snapshot entry count")
    assertEq(snap.entries[1].opcode, "choice", "snapshot opcode")
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Test 4: applySnapshot restores state
-- ─────────────────────────────────────────────────────────────────────────────
run("applySnapshot_restore", function()
    local log = BattleLog.new()
    log:append("in", "choice", { slot = "p1a" })
    log:append("internal", "turn_begin", { turn = 1 })

    local snap = log:getSnapshot()
    local log2 = BattleLog.new()
    log2:applySnapshot(snap)

    assertEq(log2._seq, 2, "restored seq")
    assertEq(log2:count(), 2, "restored count")
    assertEq(log2:getSince(1)[1].opcode, "choice", "restored entry 1")
    assertEq(log2:getSince(1)[2].opcode, "turn_begin", "restored entry 2")
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Test 5: count matches entries length
-- ─────────────────────────────────────────────────────────────────────────────
run("count_matches", function()
    local log = BattleLog.new()
    assertEq(log:count(), 0, "empty count")
    log:append("in", "choice", {})
    log:append("out", "snapshot", {})
    assertEq(log:count(), 2, "count after two appends")
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Test 6: every entry has required fields
-- ─────────────────────────────────────────────────────────────────────────────
run("entry_fields", function()
    local log = BattleLog.new()
    log:append("in", "choice", { foo = "bar" })
    local e = log:getSince(1)[1]
    assertTrue(e.seq ~= nil, "entry has seq")
    assertTrue(e.timestamp ~= nil, "entry has timestamp")
    assertEq(e.direction, "in", "entry direction")
    assertEq(e.opcode, "choice", "entry opcode")
    assertEq(e.payload.foo, "bar", "entry payload")
end)

print("")
print(string.format("Battle log: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
