-- BattleMetrics.lua  (Phase g — DEV-9)
-- Lightweight observability: counters and timings for battle sessions.
--
-- Domain lens: Observable battles — every session emits metrics that can be scraped.

local BattleMetrics = {}
BattleMetrics.__index = BattleMetrics

function BattleMetrics.new()
    local self = setmetatable({}, BattleMetrics)
    self._counters = {}
    self._timings  = {}
    return self
end

-- Increment a counter by `delta` (default 1).
function BattleMetrics:inc(name, delta)
    delta = delta or 1
    self._counters[name] = (self._counters[name] or 0) + delta
end

-- Record a timing sample (milliseconds).
function BattleMetrics:record(name, ms)
    if not self._timings[name] then
        self._timings[name] = { count = 0, sum = 0, min = ms, max = ms }
    end
    local t = self._timings[name]
    t.count = t.count + 1
    t.sum   = t.sum + ms
    if ms < t.min then t.min = ms end
    if ms > t.max then t.max = ms end
end

-- Full snapshot for external scrapers or debug endpoints.
function BattleMetrics:getSnapshot()
    local timings = {}
    for name, t in pairs(self._timings) do
        timings[name] = {
            count = t.count,
            avg   = (t.count > 0) and (t.sum / t.count) or 0,
            min   = t.min,
            max   = t.max,
        }
    end
    local counters = {}
    for k, v in pairs(self._counters) do counters[k] = v end
    return {
        counters = counters,
        timings  = timings,
    }
end

return BattleMetrics
