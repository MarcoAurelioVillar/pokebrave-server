# pokebrave-server

Server-side implementation of the PokéBrave battle system for Phase 1.

This is the authoritative side of the `battle:*` wire contract frozen in
[DEV-3](/DEV/issues/DEV-3) (Contract v1, plan doc `ffae02f4` rev `dfea0fc9`).
Client lives in `../pokebrave-client-otcv8/`.

## Phase b scope (DEV-4)

Server-only lifecycle of one battle session:

- session create / run / end
- per-session arena instance ownership (no cross-session leak)
- turn / forced-switch / reconnect-grace timers
- surrender flow + final `battle:end`
- reconnect → `battle:snapshot`
- Lua-callable session API (the seam Phase c / Phase d plug into)

Layout under `src/battle/` is normative (BattleSession, BattleSessionManager,
BattleArena, BattleWire, BattleTimers, BattleLog) so downstream phases can
target stable headers. See the [Phase b plan](/DEV/issues/DEV-4#document-plan).

## Build

```
cmake -S . -B build
cmake --build build
ctest --test-dir build --output-on-failure
```

C++17, no external dependencies. Tests use a small in-tree harness.

## Authority

The server is the only source of truth for battle state. No client-authored
state, no hidden opponent state leaked into `battle:start` / `battle:resolve` /
`battle:snapshot`. The wire is capped at 32,768 bytes per message. See
Contract v1 §7 and §10.
