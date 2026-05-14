-- BattleLog.lua  (Phase g — DEV-9)
-- Persisted, append-only, structured log per battle session.
--
-- Domain lenses:
--   Replay invariants    — every opcode in/out is timestamped and sequenced.
--   Observable battles   — the log is the single source for reconnect and post-mortem.
--   Anti-desync         — server state and client state are both verifiable against the log.
--
-- INTERFACE CONTRACT (frozen as of Phase g):
--   append(direction, opcode, payload) -> seq
--   getSince(seq)          -> entries from seq (inclusive)
--   getSnapshot()          -> full entry list + head seq
--   applySnapshot(snap)    -> restore from snapshot

local BattleLog = {}
BattleLog.__index = BattleLog

function BattleLog.new()
    local self = setmetatable({}, BattleLog)
    self._entries = {}
    self._seq = 0
    return self
end

-- Append a single entry.  All mutations go through here.
-- direction: "in" (client→server), "out" (server→client), "internal" (resolver mutation)
-- opcode:    short string identifying the message type
-- payload:   arbitrary Lua table (must be serialisable)
-- Returns the assigned monotonic sequence number.
function BattleLog:append(direction, opcode, payload)
    self._seq = self._seq + 1
    local entry = {
        seq       = self._seq,
        timestamp = os.time(),           -- seconds since epoch; enough for MVP
        direction = direction,
        opcode    = opcode,
        payload   = payload,
    }
    table.insert(self._entries, entry)
    return self._seq
end

-- Retrieve every entry with seq >= startSeq.
function BattleLog:getSince(startSeq)
    local out = {}
    for _, e in ipairs(self._entries) do
        if e.seq >= startSeq then
            table.insert(out, e)
        end
    end
    return out
end

-- Full snapshot for reconnect or post-mortem.
function BattleLog:getSnapshot()
    return {
        headSeq  = self._seq,
        entries  = self._entries,
    }
end

-- Restore from a snapshot (used when resuming a persisted session).
function BattleLog:applySnapshot(snap)
    self._entries = {}
    for _, e in ipairs(snap.entries or {}) do
        table.insert(self._entries, e)
    end
    self._seq = snap.headSeq or #self._entries
end

-- Total entries written (useful for metrics).
function BattleLog:count()
    return #self._entries
end

return BattleLog
