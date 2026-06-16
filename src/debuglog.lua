-- Tiny ring-buffer logger surfaced by the F9 debug console. Any module can
-- require this and call Log.add("message"). Keeps the last 100 lines.
local Log = { lines = {}, max = 100 }

function Log.add(msg)
    Log.lines[#Log.lines + 1] = tostring(msg)
    while #Log.lines > Log.max do table.remove(Log.lines, 1) end
end

function Log.tail(n)
    n = n or 14
    local out = {}
    local start = math.max(1, #Log.lines - n + 1)
    for i = start, #Log.lines do out[#out + 1] = Log.lines[i] end
    return out
end

return Log
