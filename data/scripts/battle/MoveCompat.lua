-- MoveCompat.lua  (Phase f — DEV-8)
-- Plug-in compatibility layer between TurnResolver and the move/ability/status catalog.
--
-- Domain lenses:
--   Compatibility contracts  — moves, abilities, and statuses are plugins to a stable resolver.
--   Authoritative server     — all state mutations go through ctx; client never decides resolution.
--   Replay invariants        — RNG is seeded from (sessionId, turn, moveId) so outputs are deterministic.
--
-- INTERFACE CONTRACT (frozen as of Phase f):
--   The four public methods below are the only surface the resolver touches.
--   Adding a new move/ability/status NEVER requires changes to TurnResolver.
--   Interface changes require a migration note + CTO sign-off per §9.3 of the battle contract.

local TurnRNG = require("battle.TurnRNG")

local MoveCompat = {}
MoveCompat.__index = MoveCompat

-- ─────────────────────────────────────────────────────────────────────────────
-- Internal helpers
-- ─────────────────────────────────────────────────────────────────────────────

-- Standard damage formula: floor((floor(2*L/5)+2) * power * Atk/Def / 50 + 2) * roll/100
-- Burn halves physical Atk (applied before formula).
local function calcDamage(attackerState, defenderState, power, category, rng)
    local level = attackerState.level or 5
    local atk   = (category == "physical") and (attackerState.attack  or 10)
                                             or  (attackerState.spatk  or 10)
    local def   = (category == "physical") and (defenderState.defense or 10)
                                             or  (defenderState.spdef  or 10)
    if attackerState.status == "burn" and category == "physical" then
        atk = math.floor(atk / 2)
    end
    local base = math.floor((math.floor(2 * level / 5) + 2) * power * atk / def / 50) + 2
    -- Random roll 85–100 to introduce natural variance while staying deterministic.
    local roll = 85 + (rng:nextInt() % 16)
    return math.max(1, math.floor(base * roll / 100))
end

-- Reduce target's HP and write back via ctx; returns HP after damage.
local function applyDamage(ctx, targetRef, amount)
    local state  = ctx:getMonState(targetRef)
    local hpAfter = math.max(0, state.hp.current - amount)
    ctx:setMonState(targetRef, "hp.current", hpAfter)
    return hpAfter
end

-- Seed for move-effect RNG.  Uses moveId in the seed string so it is orthogonal
-- to the resolver's interrupt seeds (which use integer actionSeq only).
local function moveRng(ctx, slot, moveId)
    return TurnRNG.new(ctx.sessionId .. ":" .. tostring(slot) .. ":" .. moveId, ctx.turn, 0)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Status tick catalog
-- Each entry: tick(ctx, slot, state, rng) → hpAfter  (may call ctx:markFaint internally)
-- ─────────────────────────────────────────────────────────────────────────────

local STATUS_TICK = {}

STATUS_TICK["poison"] = function(ctx, slot, state)
    local dmg     = math.max(1, math.floor(state.hp.max / 8))
    local hpAfter = applyDamage(ctx, slot, dmg)
    ctx:emit({ kind = "status_tick", slot = slot, status = "poison",
               amount = dmg, hpAfter = hpAfter })
    return hpAfter
end

STATUS_TICK["burn"] = function(ctx, slot, state)
    local dmg     = math.max(1, math.floor(state.hp.max / 16))
    local hpAfter = applyDamage(ctx, slot, dmg)
    ctx:emit({ kind = "status_tick", slot = slot, status = "burn",
               amount = dmg, hpAfter = hpAfter })
    return hpAfter
end

-- Toxic stacks: toxicStacks on the mon state increments every turn (starts at 1).
STATUS_TICK["toxic"] = function(ctx, slot, state)
    local stacks  = state.toxicStacks or 1
    local dmg     = math.max(1, math.floor(state.hp.max * stacks / 16))
    ctx:setMonState(slot, "toxicStacks", stacks + 1)
    local hpAfter = applyDamage(ctx, slot, dmg)
    ctx:emit({ kind = "status_tick", slot = slot, status = "toxic",
               amount = dmg, hpAfter = hpAfter, stacks = stacks })
    return hpAfter
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Ability hook catalog
-- Each entry may define: onHit(ctx, attackerSlot, defenderSlot, move, rng)
--                        blockSecondary = true
-- ─────────────────────────────────────────────────────────────────────────────

local ABILITY_HOOKS = {}

-- Poison Touch: contact moves have a 30 % chance to poison the defender.
ABILITY_HOOKS["poison_touch"] = {
    onHit = function(ctx, attackerSlot, defenderSlot, move, rng)
        if not move.contact then return end
        local defState = ctx:getMonState(defenderSlot)
        if defState.status then return end   -- already statused; no effect
        if rng:chance(30) then
            ctx:setMonState(defenderSlot, "status", "poison")
            ctx:emit({ kind = "status_set", slot = defenderSlot, status = "poison",
                       cause = "ability:poison_touch" })
        end
    end,
}

-- Shield Dust: nullifies all secondary effects targeting the holder.
ABILITY_HOOKS["shield_dust"] = {
    blockSecondary = true,
}

-- ─────────────────────────────────────────────────────────────────────────────
-- Move catalog
-- Each entry: id, kind ("damage"|"status"), power, category ("physical"|"special"|"status"),
--             contact (bool), accuracy (0 = never misses), priority,
--             effect (optional table for status moves),
--             switchAfter (bool — user pivots out after hit),
--             flinchChance (0–100, applied after hit)
-- ─────────────────────────────────────────────────────────────────────────────

local MOVE_CATALOG = {}

-- Damage move — Tackle: Normal/physical, 40 power, never misses.
MOVE_CATALOG["tackle"] = {
    id          = "tackle",
    kind        = "damage",
    power       = 40,
    category    = "physical",
    contact     = true,
    accuracy    = 0,   -- 0 = always hits
    priority    = 0,
}

-- Priority move — Quick Attack: Normal/physical, 40 power, +1 priority.
-- Priority resolution is the resolver's job; MoveCompat exposes it via getMoveData().
MOVE_CATALOG["quick_attack"] = {
    id          = "quick_attack",
    kind        = "damage",
    power       = 40,
    category    = "physical",
    contact     = true,
    accuracy    = 0,
    priority    = 1,
}

-- Status move — Thunder Wave: inflicts paralysis, always hits in MVP.
-- (Type immunity is not implemented in the MVP type-chart layer.)
MOVE_CATALOG["thunder_wave"] = {
    id          = "thunder_wave",
    kind        = "status",
    power       = 0,
    category    = "status",
    contact     = false,
    accuracy    = 0,
    priority    = 0,
    effect      = { status = "paralysis", chance = 100 },
}

-- Switch trigger — U-turn: Bug/physical, 70 power, user pivots after hit.
-- Emits switch_trigger when user has at least one benched mon.
MOVE_CATALOG["u_turn"] = {
    id          = "u_turn",
    kind        = "damage",
    power       = 70,
    category    = "physical",
    contact     = true,
    accuracy    = 0,
    priority    = 0,
    switchAfter = true,
}

-- ─────────────────────────────────────────────────────────────────────────────
-- MoveCompat public API
-- ─────────────────────────────────────────────────────────────────────────────

function MoveCompat.new()
    return setmetatable({}, MoveCompat)
end

-- getMoveData: called by BattleSession before the resolve step to fill choice.priority.
-- Returns { priority } or nil when the move is unknown.
function MoveCompat:getMoveData(moveId)
    local m = MOVE_CATALOG[moveId]
    if not m then return nil end
    return { priority = m.priority }
end

-- resolveMove: called by TurnResolver for kind="move" choices.
--   ctx    — TurnResolver instance (emit, markFlinch, markFaint, getMonState, setMonState)
--   slot   — acting slot ref (string)
--   choice — { kind="move", moveId=string, targetRef=string, priority=int, ... }
function MoveCompat:resolveMove(ctx, slot, choice)
    local moveId  = choice.moveId
    local move    = MOVE_CATALOG[moveId]
    if not move then
        ctx:emit({ kind = "move_unknown", slot = slot, moveId = moveId })
        return
    end

    local targetRef = choice.targetRef
    local rng       = moveRng(ctx, slot, moveId)

    ctx:emit({ kind = "move_used", slot = slot, moveId = moveId, targetRef = targetRef })

    -- Accuracy check (accuracy = 0 means always hits).
    if move.accuracy > 0 and not rng:chance(move.accuracy) then
        ctx:emit({ kind = "move_missed", slot = slot, moveId = moveId })
        return
    end

    local attackerState = ctx:getMonState(slot)
    local defenderState = ctx:getMonState(targetRef)

    if move.kind == "damage" then
        local dmg     = calcDamage(attackerState, defenderState, move.power, move.category, rng)
        local hpAfter = applyDamage(ctx, targetRef, dmg)
        ctx:emit({ kind = "damage", target = targetRef, amount = dmg, hpAfter = hpAfter })

        if hpAfter <= 0 then
            ctx:markFaint(targetRef, "move:" .. moveId)
            return   -- do not apply secondary effects after a KO
        end

        -- Flinch secondary (checked before ability so order is stable).
        if move.flinchChance and move.flinchChance > 0 and rng:chance(move.flinchChance) then
            ctx:markFlinch(targetRef)
        end

        -- Attacker ability on-hit hook (blocked by defender's shield_dust).
        local attackerAbility = attackerState.ability
        if attackerAbility then
            local hook = ABILITY_HOOKS[attackerAbility]
            if hook and hook.onHit then
                local defAbility = defenderState.ability
                local blocked    = defAbility
                               and ABILITY_HOOKS[defAbility]
                               and ABILITY_HOOKS[defAbility].blockSecondary
                if not blocked then
                    hook.onHit(ctx, slot, targetRef, move, rng)
                end
            end
        end

        -- Switch trigger: user pivots after hitting (e.g. U-turn).
        if move.switchAfter then
            local slotState = ctx:getMonState(slot)
            if (slotState.benchCount or 0) > 0 then
                ctx:emit({ kind = "switch_trigger", slot = slot,
                           cause = "move:" .. moveId })
            end
        end

    elseif move.kind == "status" then
        local eff = move.effect
        if eff and eff.status then
            if defenderState.status then
                ctx:emit({ kind = "move_failed", slot = slot, moveId = moveId,
                           reason = "already_statused" })
            else
                ctx:setMonState(targetRef, "status", eff.status)
                ctx:emit({ kind = "status_set", slot = targetRef, status = eff.status,
                           cause = "move:" .. moveId })
            end
        end
    end
end

-- resolveItem: called by TurnResolver for kind="item" choices.
--   choice — { kind="item", itemId=string, targetRef=string, ... }
function MoveCompat:resolveItem(ctx, slot, choice)
    local itemId    = choice.itemId
    local targetRef = choice.targetRef

    if itemId == "potion" then
        local state     = ctx:getMonState(targetRef)
        local hpBefore  = state.hp.current
        local hpAfter   = math.min(state.hp.max, hpBefore + 20)
        ctx:setMonState(targetRef, "hp.current", hpAfter)
        ctx:emit({ kind = "item_used", slot = slot, itemId = itemId,
                   target = targetRef, heal = hpAfter - hpBefore })

    elseif itemId == "full_restore" then
        local state    = ctx:getMonState(targetRef)
        local hpBefore = state.hp.current
        ctx:setMonState(targetRef, "hp.current", state.hp.max)
        ctx:setMonState(targetRef, "status", nil)
        ctx:emit({ kind = "item_used", slot = slot, itemId = itemId,
                   target = targetRef, heal = state.hp.max - hpBefore, clearedStatus = true })

    else
        ctx:emit({ kind = "item_unknown", slot = slot, itemId = itemId })
    end
end

-- Speed multipliers applied to a mon during turn-order sort, keyed by status string.
local STATUS_SPEED_MODIFIER = {
    paralysis = 0.25,
}

-- getStatusSpeedModifier: returns the speed multiplier (0.0–1.0) for a given status.
-- Returns 1.0 for unknown/nil statuses — resolver stays move-agnostic.
function MoveCompat:getStatusSpeedModifier(status)
    return STATUS_SPEED_MODIFIER[status] or 1.0
end

-- applyStatusTick: called by TurnResolver at end of each turn for non-fainted statused slots.
--   status — current status string on the slot
function MoveCompat:applyStatusTick(ctx, slot, status)
    local tickFn = STATUS_TICK[status]
    if not tickFn then return end   -- unknown status: safe no-op; resolver stays clean

    local state   = ctx:getMonState(slot)
    local hpAfter = tickFn(ctx, slot, state)
    if hpAfter <= 0 then
        ctx:markFaint(slot, "status:" .. status)
    end
end

-- resolveConfusionSelfHit: called by TurnResolver when the confusion proc fires.
-- Deals typeless physical damage to self using a fixed 40-power formula.
function MoveCompat:resolveConfusionSelfHit(ctx, slot)
    local state = ctx:getMonState(slot)
    local rng   = TurnRNG.new(ctx.sessionId .. ":" .. tostring(slot) .. ":confusion", ctx.turn, 0)
    -- Self-hit uses attacker stats as both attacker and defender.
    local dmg     = calcDamage(state, state, 40, "physical", rng)
    local hpAfter = applyDamage(ctx, slot, dmg)
    ctx:emit({ kind = "confusion_self_hit", slot = slot, amount = dmg, hpAfter = hpAfter })
    if hpAfter <= 0 then
        ctx:markFaint(slot, "confusion")
    end
end

return MoveCompat
