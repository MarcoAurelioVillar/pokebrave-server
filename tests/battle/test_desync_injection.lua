-- test_desync_injection.lua  (Phase g — DEV-9)
-- Acceptance: desync injection test produces structured error and authoritative
-- correction without crashing the session.

local BattleSession = require("battle.BattleSession")

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

local function assertFalse(a, msg)
    if a then
        error(string.format("ASSERT FAIL: %s | expected false, got %s", msg or "", tostring(a)))
    end
end

local function newTestSession()
    return BattleSession.new("desync-test", {
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
-- Test 1: identical state passes validation
-- ─────────────────────────────────────────────────────────────────────────────
run("validate_identical_state", function()
    local sess = newTestSession()
    local snap = sess:getSnapshot()
    local clientState = {
        turn = snap.turn,
        monStates = snap.monStates,
    }
    local ok, correction = sess:validateClientState(clientState)
    assertTrue(ok, "identical state should validate")
    assertEq(correction, nil, "no correction for identical state")
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Test 2: HP mismatch → rejected with correction
-- ─────────────────────────────────────────────────────────────────────────────
run("hp_mismatch_correction", function()
    local sess = newTestSession()
    -- Simulate a turn that reduces p2a HP.
    sess:setMonState("p2a", "hp.current", 75)

    local clientState = {
        turn = 0,   -- client still thinks it's turn 0
        monStates = {
            p1a = { hp = { current = 100 }, status = nil },
            p2a = { hp = { current = 100 }, status = nil },  -- wrong HP
        },
    }

    local ok, correction = sess:validateClientState(clientState)
    assertFalse(ok, "mismatched state should be rejected")
    assertTrue(correction ~= nil, "correction should be provided")
    assertEq(correction.turn, 0, "correction includes turn")
    assertEq(correction.p2a.hp.current, 75, "correction has authoritative HP")
    assertEq(correction.p2a.hp.max, 100, "correction has max HP")
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Test 3: status mismatch → rejected with correction
-- ─────────────────────────────────────────────────────────────────────────────
run("status_mismatch_correction", function()
    local sess = newTestSession()
    sess:setMonState("p1a", "status", "poison")

    local clientState = {
        turn = 0,
        monStates = {
            p1a = { hp = { current = 100 }, status = nil },  -- missing poison
            p2a = { hp = { current = 100 }, status = nil },
        },
    }

    local ok, correction = sess:validateClientState(clientState)
    assertFalse(ok, "status mismatch should be rejected")
    assertEq(correction.p1a.status, "poison", "correction includes authoritative status")
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Test 4: missing mon in client state → full mon correction
-- ─────────────────────────────────────────────────────────────────────────────
run("missing_mon_correction", function()
    local sess = newTestSession()
    local clientState = {
        turn = 0,
        monStates = {
            p1a = { hp = { current = 100 }, status = nil },
            -- p2a missing
        },
    }

    local ok, correction = sess:validateClientState(clientState)
    assertFalse(ok, "missing mon should be rejected")
    assertTrue(correction.p2a ~= nil, "correction includes full p2a state")
    assertEq(correction.p2a.hp.current, 100, "correct p2a hp")
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Test 5: nil client state → rejected without crash
-- ─────────────────────────────────────────────────────────────────────────────
run("nil_client_state", function()
    local sess = newTestSession()
    local ok, correction = sess:validateClientState(nil)
    assertFalse(ok, "nil state should be rejected")
    assertEq(correction.error, "missing_client_state", "structured error code")
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Test 6: desync event increments metric and logs
-- ─────────────────────────────────────────────────────────────────────────────
run("desync_metrics_and_log", function()
    local sess = newTestSession()
    local before = sess.metrics:getSnapshot().counters.desync_events or 0

    local clientState = {
        turn = 999,   -- impossible turn
        monStates = {},
    }
    local ok, _ = sess:validateClientState(clientState)
    assertFalse(ok, "should detect desync")

    local after = sess.metrics:getSnapshot().counters.desync_events or 0
    assertEq(after, before + 1, "desync counter incremented")

    -- Log should contain a desync_correction entry.
    local found = false
    for _, e in ipairs(sess.log:getSince(1)) do
        if e.opcode == "desync_correction" then
            found = true
            break
        end
    end
    assertTrue(found, "log contains desync_correction opcode")
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Test 7: session survives multiple desync injections
-- ─────────────────────────────────────────────────────────────────────────────
run("survive_multiple_desyncs", function()
    local sess = newTestSession()
    for i = 1, 5 do
        local ok, corr = sess:validateClientState({ turn = i, monStates = {} })
        assertFalse(ok, "desync " .. i .. " detected")
        assertTrue(corr ~= nil, "correction " .. i .. " provided")
    end
    -- Session must still be functional.
    local snap = sess:getSnapshot()
    assertEq(snap.sessionId, "desync-test", "session intact")
    assertEq(snap.monStates["p1a"].hp.current, 100, "p1a unharmed")
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Test 8: turn mismatch only — mon states are identical
-- ─────────────────────────────────────────────────────────────────────────────
run("turn_only_mismatch", function()
    local sess = newTestSession()
    -- Advance turn artificially.
    sess.turn = 3

    local clientState = {
        turn = 2,   -- one behind
        monStates = {
            p1a = { hp = { current = 100 }, status = nil },
            p2a = { hp = { current = 100 }, status = nil },
        },
    }

    local ok, correction = sess:validateClientState(clientState)
    assertFalse(ok, "turn mismatch should be rejected")
    assertEq(correction.turn, 3, "correction has authoritative turn")
    -- No per-slot corrections because mons match.
    assertEq(correction.p1a, nil, "no p1a correction")
    assertEq(correction.p2a, nil, "no p2a correction")
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Test 9: client sends extra mon — server ignores it (authoritative server)
-- ─────────────────────────────────────────────────────────────────────────────
run("client_extra_mon_ignored", function()
    local sess = newTestSession()
    local clientState = {
        turn = 0,
        monStates = {
            p1a = { hp = { current = 100 }, status = nil },
            p2a = { hp = { current = 100 }, status = nil },
            p3a = { hp = { current = 999 }, status = "flying_dragon" },  -- bogus
        },
    }

    local ok, correction = sess:validateClientState(clientState)
    assertTrue(ok, "extra unknown mons should be ignored")
    assertEq(correction, nil, "no correction needed")
end)

print("")
print(string.format("Desync injection: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
