-- TurnResolver.lua  (Phase c — DEV-5, hardened in Phase g — DEV-9)
-- Executes a single battle turn: sort actions, resolve each, apply end-of-turn ticks.
--
-- Domain lenses:
--   Turn-order determinism — priority → speed → random tie-break.
--   Arena isolation        — nothing outside the battle context leaks in.
--   Authoritative server   — all state changes go through ctx; client never decides.
--   Replay invariants      — RNG is seeded from (sessionId, turn, actionSeq).

local MoveCompat = require("battle.MoveCompat")
local TurnRNG    = require("battle.TurnRNG")

local TurnResolver = {}
TurnResolver.__index = TurnResolver

function TurnResolver.new(ctx)
    local self = setmetatable({}, TurnResolver)
    self.ctx = ctx
    self.compat = MoveCompat.new()
    return self
end

-- Sort key: lower number = acts earlier.
local function sortKey(choice, ctx, rng)
    local moveData = ctx.moveCompat:getMoveData(choice.moveId)
    local priority = (moveData and moveData.priority) or 0
    local speed    = 0
    local state    = ctx:getMonState(choice.slot)
    if state then
        speed = state.speed or 0
        local speedMod = ctx.moveCompat:getStatusSpeedModifier(state.status)
        speed = math.floor(speed * speedMod)
    end
    -- Deterministic tie-break using the action sequence.
    local tie = rng:nextInt()
    -- Negate priority so higher priority sorts first (lower sort key = acts earlier).
    return { -priority, -speed, tie }
end

-- Resolve a full turn given a list of player choices.
-- choices: list of { slot, kind, moveId, targetRef } — resolver is move-agnostic.
function TurnResolver:resolveTurn(choices)
    local ctx = self.ctx
    local rng = TurnRNG.new(ctx.sessionId, ctx.turn, 0)

    -- 1. Precompute sort keys and sort by priority, then speed, then deterministic tie-break.
    local sorted = {}
    for i, c in ipairs(choices) do
        local key = sortKey(c, ctx, rng)
        table.insert(sorted, { choice = c, key = key, _origIndex = i })
    end
    table.sort(sorted, function(a, b)
        for i = 1, 3 do
            if a.key[i] ~= b.key[i] then return a.key[i] < b.key[i] end
        end
        return false
    end)

    -- 2. Resolve each action.
    for actionSeq, wrapped in ipairs(sorted) do
        local choice = wrapped.choice
        local slot = choice.slot
        local state = ctx:getMonState(slot)
        local act = true

        -- Skip fainted slots.
        if not state or state.hp.current <= 0 then
            ctx:emit({ kind = "skip_fainted", slot = slot })
            act = false
        end

        -- Skip flinched slots.
        if act and ctx:isFlinching(slot) then
            ctx:emit({ kind = "skip_flinch", slot = slot })
            act = false
        end

        -- Confusion check (20 % chance to hit self; simplified MVP rule).
        if act and state.confusion then
            local confRng = TurnRNG.new(ctx.sessionId, ctx.turn, actionSeq * 1000)
            if confRng:chance(20) then
                ctx:emit({ kind = "confusion_proc", slot = slot })
                self.compat:resolveConfusionSelfHit(ctx, slot)
                act = false
            end
        end

        if act then
            if choice.kind == "move" then
                self.compat:resolveMove(ctx, slot, choice)
            elseif choice.kind == "item" then
                self.compat:resolveItem(ctx, slot, choice)
            elseif choice.kind == "switch" then
                ctx:applySwitch(slot, choice.targetRef)
            else
                ctx:emit({ kind = "choice_unknown", slot = slot, kind = choice.kind })
            end
        end
    end

    -- 3. End-of-turn status ticks.
    for slot, state in pairs(ctx:getAllMonStates()) do
        if state.hp.current > 0 and state.status then
            self.compat:applyStatusTick(ctx, slot, state.status)
        end
    end

    -- 4. Process faint queue (expunge persistent per-turn flags).
    ctx:clearFlinch()
    ctx:drainFaintQueue()
end

return TurnResolver
