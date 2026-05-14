-- TurnRNG.lua  (Phase d — DEV-6, hardened in Phase g — DEV-9)
-- Deterministic per-action RNG, seeded by (sessionId, turn, actionSeq).
-- REPLAY INVARIANT: identical inputs always produce identical outputs.
-- Compatible with Lua 5.1, 5.2, 5.3, and LuaJIT (no native bitwise ops required).

local TurnRNG = {}
TurnRNG.__index = TurnRNG

-- Pure-Lua 32-bit XOR for non-negative integers (sufficient for djb2/LCG).
local function bxor(a, b)
    local result = 0
    local bitval = 1
    while a > 0 or b > 0 do
        local abit = a % 2
        local bbit = b % 2
        if abit ~= bbit then
            result = result + bitval
        end
        bitval = bitval * 2
        a = math.floor(a / 2)
        b = math.floor(b / 2)
    end
    return result
end

-- Restrict to unsigned 32-bit range.
local function u32(v)
    return math.floor(v) % 0x100000000
end

local function djb2(str)
    local h = 5381
    for i = 1, #str do
        local c = string.byte(str, i)
        h = u32(bxor(h * 33, c))
    end
    return h
end

local LCG_A = 1664525
local LCG_C = 1013904223

function TurnRNG.new(sessionId, turn, actionSeq)
    local self = setmetatable({}, TurnRNG)
    local seed_str = tostring(sessionId) .. ":" .. tostring(turn) .. ":" .. tostring(actionSeq)
    self._state = djb2(seed_str)
    return self
end

function TurnRNG:nextInt()
    self._state = u32(LCG_A * self._state + LCG_C)
    return self._state
end

function TurnRNG:chance(pct)
    return (self:nextInt() % 100) < pct
end

function TurnRNG:coin(slotA, slotB)
    if (self:nextInt() % 2) == 0 then return slotA else return slotB end
end

return TurnRNG
