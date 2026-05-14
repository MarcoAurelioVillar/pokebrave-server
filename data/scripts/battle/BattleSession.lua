-- BattleSession.lua  (Phase g — DEV-9)
-- Central battle state manager with persistence, reconnect, and anti-desync.
--
-- Domain lenses:
--   Authoritative server      — server is the only source of truth.
--   Replay invariants         — every mutation is logged; snapshots reconstruct state.
--   Anti-desync              — client-reported mismatches are rejected with correction.
--   Arena isolation          — battle context is fully sandboxed.
--   Observable battles       — every session produces a structured log.
--   Client-side hint, server-side truth — HUD predictions are visual only.

local BattleLog     = require("battle.BattleLog")
local BattleMetrics = require("battle.BattleMetrics")
local TurnResolver  = require("battle.TurnResolver")
local MoveCompat    = require("battle.MoveCompat")

local BattleSession = {}
BattleSession.__index = BattleSession

-- teamsConfig: { p1 = { {slot="p1a", species="bulbasaur", hp={current=100,max=100}, ... }, ... }, p2 = {...} }
function BattleSession.new(sessionId, teamsConfig)
    local self = setmetatable({}, BattleSession)
    self.sessionId   = sessionId
    self.createdAt   = os.time()
    self.turn        = 0
    self.phase       = "setup"      -- setup | waiting | resolve | finished
    self.log         = BattleLog.new()
    self.metrics     = BattleMetrics.new()
    self.moveCompat  = MoveCompat.new()

    -- Mon state table keyed by slot ref (e.g. "p1a", "p2a").
    self._monStates  = {}
    for player, team in pairs(teamsConfig or {}) do
        for _, mon in ipairs(team) do
            mon.player = player
            self._monStates[mon.slot] = mon
        end
    end

    -- Per-turn transient flags.
    self._flinchSet  = {}
    self._faintQueue = {}

    self.metrics:inc("sessions_created")
    self.log:append("internal", "session_created", {
        sessionId = sessionId,
        turn      = 0,
        monCount  = self:countMons(),
    })

    return self
end

-- ─────────────────────────────────────────────────────────────────────────────
-- State accessors (resolver interface)
-- ─────────────────────────────────────────────────────────────────────────────

function BattleSession:getMonState(slot)
    return self._monStates[slot]
end

function BattleSession:getAllMonStates()
    return self._monStates
end

function BattleSession:countMons()
    local n = 0
    for _ in pairs(self._monStates) do n = n + 1 end
    return n
end

-- Deep-enough copy for snapshot / desync comparison.
local function copyState(st)
    local c = {}
    for k, v in pairs(st) do
        if type(v) == "table" then
            c[k] = {}
            for kk, vv in pairs(v) do c[k][kk] = vv end
        else
            c[k] = v
        end
    end
    return c
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Mutators (all logged)
-- ─────────────────────────────────────────────────────────────────────────────

function BattleSession:setMonState(slot, path, value)
    local state = self._monStates[slot]
    if not state then return end
    local keys = {}
    for part in string.gmatch(path, "[^.]+") do
        table.insert(keys, part)
    end
    local cur = state
    for i = 1, #keys - 1 do
        cur = cur[keys[i]]
    end
    cur[keys[#keys]] = value
    self.log:append("internal", "state_mutated", {
        slot  = slot,
        path  = path,
        value = value,
        turn  = self.turn,
    })
end

function BattleSession:emit(event)
    event.turn = self.turn
    self.log:append("internal", "event", event)
end

function BattleSession:markFaint(slot, cause)
    table.insert(self._faintQueue, { slot = slot, cause = cause, turn = self.turn })
    self.log:append("internal", "faint_queued", { slot = slot, cause = cause, turn = self.turn })
end

function BattleSession:markFlinch(slot)
    self._flinchSet[slot] = true
    self.log:append("internal", "flinch_marked", { slot = slot, turn = self.turn })
end

function BattleSession:isFlinching(slot)
    return self._flinchSet[slot] == true
end

function BattleSession:clearFlinch()
    self._flinchSet = {}
end

function BattleSession:drainFaintQueue()
    for _, entry in ipairs(self._faintQueue) do
        local st = self._monStates[entry.slot]
        if st then
            st.hp.current = 0
            self.log:append("internal", "faint_applied", entry)
        end
    end
    self._faintQueue = {}
end

function BattleSession:applySwitch(slot, targetRef)
    local old = self._monStates[slot]
    local neu = self._monStates[targetRef]
    if old and neu then
        self._monStates[slot] = neu
        self._monStates[targetRef] = old
        neu.slot = slot
        old.slot = targetRef
        self:emit({ kind = "switch", slot = slot, with = targetRef })
    else
        self:emit({ kind = "switch_failed", slot = slot, targetRef = targetRef })
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Turn lifecycle
-- ─────────────────────────────────────────────────────────────────────────────

function BattleSession:enqueueChoice(choice)
    self.log:append("in", "choice", {
        slot = choice.slot,
        kind = choice.kind,
        moveId = choice.moveId,
        targetRef = choice.targetRef,
        itemId = choice.itemId,
        turn = self.turn,
    })
end

function BattleSession:resolveTurn(choices)
    self.phase = "resolve"
    self.turn = self.turn + 1
    local startMs = os.clock() * 1000

    self.log:append("internal", "turn_begin", { turn = self.turn, choiceCount = #choices })

    local resolver = TurnResolver.new(self)
    resolver:resolveTurn(choices)

    local elapsed = (os.clock() * 1000) - startMs
    self.metrics:record("turn_duration_ms", elapsed)
    self.metrics:inc("turns_resolved")

    self.log:append("internal", "turn_end", { turn = self.turn, durationMs = elapsed })

    -- Check for battle end (simplified: all mons of one player fainted).
    local p1Alive, p2Alive = false, false
    for slot, st in pairs(self._monStates) do
        if st.hp.current > 0 then
            if st.player == "p1" then p1Alive = true else p2Alive = true end
        end
    end
    if not p1Alive or not p2Alive then
        self.phase = "finished"
        self:emit({ kind = "battle_end", winner = p1Alive and "p1" or "p2" })
    else
        self.phase = "waiting"
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Snapshot & reconnect (Phase g core)
-- ─────────────────────────────────────────────────────────────────────────────

-- Produce an authoritative snapshot for battle:snapshot.
function BattleSession:getSnapshot()
    local mons = {}
    for slot, st in pairs(self._monStates) do
        mons[slot] = copyState(st)
    end
    return {
        sessionId = self.sessionId,
        turn      = self.turn,
        phase     = self.phase,
        monStates = mons,
        logHead   = self.log._seq,
        metrics   = self.metrics:getSnapshot(),
    }
end

-- Rebuild client state from snapshot on reconnect.
function BattleSession:buildReconnectSnapshot(clientLogHead)
    self.metrics:inc("reconnects")
    local snap = self:getSnapshot()
    -- Also send any log entries the client missed.
    snap.missedEntries = self.log:getSince((clientLogHead or 0) + 1)
    self.log:append("out", "battle_snapshot", {
        clientLogHead = clientLogHead,
        serverLogHead = self.log._seq,
        monCount      = self:countMons(),
    })
    return snap
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Anti-desync guardrails (Phase g core)
-- ─────────────────────────────────────────────────────────────────────────────

-- Validate a client-reported state hash / summary.
-- clientState: { monStates = { p1a = { hp={current=...}, status=... }, ... }, turn = N }
-- Returns: ok (bool), correction (table or nil)
function BattleSession:validateClientState(clientState)
    if not clientState then
        self.metrics:inc("desync_events")
        return false, { error = "missing_client_state", serverTurn = self.turn }
    end

    local correction = { turn = self.turn }
    local mismatches = 0

    -- Turn mismatch counts as a mismatch.
    if clientState.turn ~= self.turn then
        mismatches = mismatches + 1
    end

    -- Per-mon field checks.
    for slot, serverSt in pairs(self._monStates) do
        local clientSt = (clientState.monStates or {})[slot]
        if not clientSt then
            mismatches = mismatches + 1
            correction[slot] = copyState(serverSt)
        else
            local slotCorr = {}
            -- HP
            if (clientSt.hp and clientSt.hp.current) ~= serverSt.hp.current then
                slotCorr.hp = { current = serverSt.hp.current, max = serverSt.hp.max }
            end
            -- Status
            if clientSt.status ~= serverSt.status then
                slotCorr.status = serverSt.status
            end
            if next(slotCorr) then
                mismatches = mismatches + 1
                correction[slot] = slotCorr
            end
        end
    end

    if mismatches > 0 then
        self.metrics:inc("desync_events")
        self.log:append("out", "desync_correction", {
            clientTurn = clientState.turn,
            serverTurn = self.turn,
            mismatches = mismatches,
        })
        return false, correction
    end

    return true, nil
end

return BattleSession
