# Battle Module — Phase g (DEV-9)

## Scope

Persistence, reconnect, anti-desync, and observability for PokéBrave turn-based combat.

## Files

| File | Purpose |
|------|---------|
| `BattleSession.lua` | Central battle state manager; snapshot, reconnect, desync validation |
| `BattleLog.lua` | Append-only, structured, timestamped log per session |
| `BattleMetrics.lua` | Counters and timings (sessions, turns, reconnects, desync events) |
| `TurnResolver.lua` | Turn execution engine (priority → speed → deterministic tie-break) |
| `TurnRNG.lua` | Deterministic per-action RNG seeded by `(sessionId, turn, actionSeq)` |
| `MoveCompat.lua` | Move/ability/status compatibility layer (plugin contract) |
| `test_reconnect_smoke.lua` | Acceptance: disconnect mid-turn, rejoin, finish battle |
| `test_desync_injection.lua` | Acceptance: state mismatch produces structured correction |
| `run_tests.lua` | Unified runner (executes both suites in subprocesses) |

## Running tests

```bash
cd pokebrave-server/data/scripts
export LUA_PATH="?.lua;?/init.lua;;"
lua battle/run_tests.lua
```

Or individually:

```bash
cd pokebrave-server/data/scripts
export LUA_PATH="?.lua;?/init.lua;;"
lua battle/test_reconnect_smoke.lua
lua battle/test_desync_injection.lua
```

## Key design decisions

- **Authoritative server** — all state mutations go through `BattleSession:setMonState` and are logged.
- **Replay invariants** — `TurnRNG` is seeded from `(sessionId, turn, actionSeq)`; identical inputs produce identical outputs.
- **Anti-desync** — `validateClientState` always returns the authoritative `turn` plus per-slot corrections for HP and status.
- **Arena isolation** — battle context is fully sandboxed; no global state.
- **Frozen-then-iterated** — the battle contract (opcodes, payload shapes, lifecycle) is frozen; new moves/abilities are plugins.

## Persistence note

`BattleLog` stores entries in-memory within the session object. For the MVP this satisfies the parseable-post-mortem requirement. File-level persistence would require C++ engine hooks and is out of scope for Phase g.
