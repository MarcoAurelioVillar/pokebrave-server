#!/bin/sh
# Roda os testes unitários de battle a partir do root do repo.
set -e
export LUA_PATH="./data/scripts/?.lua;./data/scripts/?/init.lua;;"
lua tests/battle/run_tests.lua
