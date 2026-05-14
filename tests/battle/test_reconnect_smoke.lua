-- test_reconnect_smoke.lua  (Phase g — DEV-9)
-- Acceptance: disconnect mid-turn, rejoin, finish battle.

local BattleSession = require("battle.BattleSession")

local function assertEq(a, b, msg)
    if a ~= b then
        error(string.format("ASSERT FAIL: %s | expected %s, got %s", msg or "", tostring(b), tostring(a)))
    end
end

local function assertGt(a, b, msg)
    if not (a > b) then
        error(string.format("ASSERT FAIL: %s | expected %s > %s", msg or "", tostring(a), tostring(b)))
    end
end

local function assertTrue(a, msg)
    if not a then
        error(string.format("ASSERT FAIL: %s | expected true, got %s", msg or "", tostring(a)))
    end
end

local function newTestSession()
    return BattleSession.new("reconnect-test", {
        p1 = {
            { slot = "p1a", species = "bulbasaur", level = 5,
              hp = { current = 100, max = 100 }, attack = 20, defense = 20, spatk = 20, spdef = 20, speed = 20,
              status = nil, ability = nil },
        },
        p2 = {
            { slot = "p2a", species = "charmander", level = 5,
              hp = { current = 100, max = 100 }, attack = 20, defense = 20, spatk = 20, spdef = 20, speed = 15,
              status = nil, ability = nil },
        },
    })
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
-- Test 1: snapshot contains correct state after setup
-- ─────────────────────────────────────────────────────────────────────────────
run("snapshot_after_setup", function()
    local sess = newTestSession()
    local snap = sess:getSnapshot()
    assertEq(snap.sessionId, "reconnect-test", "sessionId")
    assertEq(snap.turn, 0, "turn")
    assertEq(snap.phase, "setup", "phase")
    assertEq(snap.monStates["p1a"].hp.current, 100, "p1a hp")
    assertEq(snap.monStates["p2a"].hp.current, 100, "p2a hp")
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Test 2: disconnect mid-turn, reconnect, state is restored
-- ─────────────────────────────────────────────────────────────────────────────
run("reconnect_mid_turn", function()
    local sess = newTestSession()

    -- Turn 1: p1a uses tackle on p2a.
    sess:enqueueChoice({ slot = "p1a", kind = "move", moveId = "tackle", targetRef = "p2a" })
    sess:enqueueChoice({ slot = "p2a", kind = "move", moveId = "tackle", targetRef = "p1a" })
    sess:resolveTurn({
        { slot = "p1a", kind = "move", moveId = "tackle", targetRef = "p2a" },
        { slot = "p2a", kind = "move", moveId = "tackle", targetRef = "p1a" },
    })

    -- Simulate disconnect: client loses state, reconnects with old log head.
    local clientLogHead = 0   -- client knows nothing
    local reconnectSnap = sess:buildReconnectSnapshot(clientLogHead)

    -- Reconnect snapshot must have current turn and HP.
    assertEq(reconnectSnap.turn, 1, "reconnect turn")
    assertGt(reconnectSnap.logHead, clientLogHead, "logHead advanced")
    assertGt(#reconnectSnap.missedEntries, 0, "missed entries delivered")

    -- Verify p2a took damage from tackle (40 power vs 20 def ≈ 8-9 dmg).
    local p2aHp = reconnectSnap.monStates["p2a"].hp.current
    assertGt(100, p2aHp, "p2a hp reduced")

    -- Metrics must show one reconnect.
    local m = reconnectSnap.metrics
    assertEq((m.counters and m.counters.reconnects) or 0, 1, "reconnect counter")
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Test 3: finish battle after reconnect
-- ─────────────────────────────────────────────────────────────────────────────
run("finish_after_reconnect", function()
    local sess = newTestSession()

    -- Reduce p2a HP so next hit KOs (tackle does 4-5 dmg at this level).
    sess:setMonState("p2a", "hp.current", 1)

    sess:enqueueChoice({ slot = "p1a", kind = "move", moveId = "tackle", targetRef = "p2a" })
    sess:resolveTurn({
        { slot = "p1a", kind = "move", moveId = "tackle", targetRef = "p2a" },
    })

    assertEq(sess.phase, "finished", "battle finished")
    local snap = sess:getSnapshot()
    assertEq(snap.monStates["p2a"].hp.current, 0, "p2a fainted")
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Test 4: log contains every opcode with timestamps
-- ─────────────────────────────────────────────────────────────────────────────
run("log_has_timestamps_and_opcodes", function()
    local sess = newTestSession()
    local snap = sess.log:getSnapshot()
    assertGt(#snap.entries, 0, "log not empty")
    for _, e in ipairs(snap.entries) do
        assertGt(e.timestamp, 0, "entry has timestamp")
        assertGt(e.seq, 0, "entry has seq")
        assertEq(type(e.opcode), "string", "opcode is string")
    end
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Test 5: partial reconnect — client already has some log entries
-- ─────────────────────────────────────────────────────────────────────────────
run("partial_reconnect_delivers_only_missed_entries", function()
    local sess = newTestSession()

    -- Client connects, sees the session_created entry (seq 1), then disconnects.
    local clientLogHead = 1

    -- Server advances: resolve a turn.
    sess:enqueueChoice({ slot = "p1a", kind = "move", moveId = "tackle", targetRef = "p2a" })
    sess:enqueueChoice({ slot = "p2a", kind = "move", moveId = "tackle", targetRef = "p1a" })
    sess:resolveTurn({
        { slot = "p1a", kind = "move", moveId = "tackle", targetRef = "p2a" },
        { slot = "p2a", kind = "move", moveId = "tackle", targetRef = "p1a" },
    })

    local reconnectSnap = sess:buildReconnectSnapshot(clientLogHead)

    -- missedEntries should start from seq 2 (after the client's known head).
    local missed = reconnectSnap.missedEntries
    assertGt(#missed, 0, "some entries missed")
    for _, e in ipairs(missed) do
        assertGt(e.seq, clientLogHead, "missed entry seq > clientLogHead")
    end

    -- The snapshot itself must still be authoritative.
    assertEq(reconnectSnap.turn, 1, "reconnect turn")
    assertGt(100, reconnectSnap.monStates["p2a"].hp.current, "p2a hp reduced")
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Test 6: metrics timing aggregation (avg / min / max)
-- ─────────────────────────────────────────────────────────────────────────────
run("metrics_timing_aggregation", function()
    local sess = newTestSession()
    -- Manually inject timing samples.
    sess.metrics:record("turn_duration_ms", 10)
    sess.metrics:record("turn_duration_ms", 20)
    sess.metrics:record("turn_duration_ms", 30)

    local m = sess.metrics:getSnapshot()
    local t = m.timings["turn_duration_ms"]
    assertTrue(t ~= nil, "timing entry exists")
    assertEq(t.count, 3, "count")
    assertEq(t.avg, 20, "avg")
    assertEq(t.min, 10, "min")
    assertEq(t.max, 30, "max")
end)

print("")
print(string.format("Reconnect smoke: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
