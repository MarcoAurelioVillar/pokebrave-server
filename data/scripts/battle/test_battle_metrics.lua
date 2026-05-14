-- test_battle_metrics.lua  (Phase g — DEV-9)
-- Isolated unit tests for BattleMetrics (inc, record, getSnapshot).

local BattleMetrics = require("battle.BattleMetrics")

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
-- Test 1: inc starts from zero and accumulates
-- ─────────────────────────────────────────────────────────────────────────────
run("inc_accumulates", function()
    local m = BattleMetrics.new()
    m:inc("turns")
    m:inc("turns")
    m:inc("turns", 3)
    local snap = m:getSnapshot()
    assertEq(snap.counters.turns, 5, "turns counter")
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Test 2: record computes avg/min/max
-- ─────────────────────────────────────────────────────────────────────────────
run("record_stats", function()
    local m = BattleMetrics.new()
    m:record("latency", 12)
    m:record("latency", 8)
    m:record("latency", 16)

    local snap = m:getSnapshot()
    local t = snap.timings.latency
    assertTrue(t ~= nil, "timing exists")
    assertEq(t.count, 3, "count")
    assertEq(t.avg, 12, "avg")
    assertEq(t.min, 8, "min")
    assertEq(t.max, 16, "max")
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Test 3: single sample avg/min/max are all the same
-- ─────────────────────────────────────────────────────────────────────────────
run("record_single_sample", function()
    local m = BattleMetrics.new()
    m:record("latency", 42)

    local t = m:getSnapshot().timings.latency
    assertEq(t.count, 1, "count")
    assertEq(t.avg, 42, "avg")
    assertEq(t.min, 42, "min")
    assertEq(t.max, 42, "max")
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Test 4: snapshot isolates counters and timings
-- ─────────────────────────────────────────────────────────────────────────────
run("snapshot_isolation", function()
    local m = BattleMetrics.new()
    m:inc("sessions")
    m:record("turn_duration_ms", 100)

    local snap = m:getSnapshot()
    -- Mutate snapshot copies — must not affect the source.
    snap.counters.sessions = 999
    snap.timings.turn_duration_ms.avg = 999

    local snap2 = m:getSnapshot()
    assertEq(snap2.counters.sessions, 1, "counter unchanged")
    assertEq(snap2.timings.turn_duration_ms.avg, 100, "timing unchanged")
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Test 5: empty metrics snapshot
-- ─────────────────────────────────────────────────────────────────────────────
run("empty_snapshot", function()
    local m = BattleMetrics.new()
    local snap = m:getSnapshot()
    assertEq(next(snap.counters), nil, "no counters")
    assertEq(next(snap.timings), nil, "no timings")
end)

print("")
print(string.format("Battle metrics: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
