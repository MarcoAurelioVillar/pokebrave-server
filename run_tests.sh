#!/bin/sh
# Root-level convenience runner for Phase g battle module tests.
# Runs the unified test runner so failure in any suite is propagated.
set -e
export LUA_PATH="pokebrave-server/data/scripts/?.lua;pokebrave-server/data/scripts/?/init.lua;;"
cd pokebrave-server/data/scripts
lua battle/run_tests.lua
