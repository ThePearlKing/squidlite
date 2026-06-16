-- Small math/draw helpers used everywhere.
local U = {}

function U.clamp(v, lo, hi) return v < lo and lo or (v > hi and hi or v) end
function U.lerp(a, b, t) return a + (b - a) * t end
function U.sign(x) return x > 0 and 1 or (x < 0 and -1 or 0) end
function U.round(x) return math.floor(x + 0.5) end

-- Frame-rate independent lerp toward a target ("smooth damp"-ish).
function U.approach(a, b, rate, dt)
    return U.lerp(a, b, 1 - math.exp(-rate * dt))
end

function U.dist(ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    return math.sqrt(dx * dx + dy * dy)
end

function U.dist2(ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    return dx * dx + dy * dy
end

function U.angleTo(ax, ay, bx, by)
    return math.atan2(by - ay, bx - ax)
end

-- Normalize a vector; returns 0,0 for the zero vector.
function U.normalize(x, y)
    local m = math.sqrt(x * x + y * y)
    if m < 1e-6 then return 0, 0, 0 end
    return x / m, y / m, m
end

function U.rand(a, b) return a + (b - a) * love.math.random() end
function U.randi(a, b) return love.math.random(a, b) end
function U.pick(t) return t[love.math.random(1, #t)] end

function U.chance(p) return love.math.random() < p end

-- Shortest signed angular difference from a to b.
function U.angleDiff(a, b)
    local d = (b - a) % (2 * math.pi)
    if d > math.pi then d = d - 2 * math.pi end
    return d
end

-- Mix two {r,g,b} colors. t=0 -> c1, t=1 -> c2.
function U.mixColor(c1, c2, t)
    return {
        U.lerp(c1[1], c2[1], t),
        U.lerp(c1[2], c2[2], t),
        U.lerp(c1[3], c2[3], t),
    }
end

-- Lighten/darken a color by factor (1 = same).
function U.shade(c, f)
    return { U.clamp(c[1] * f, 0, 1), U.clamp(c[2] * f, 0, 1), U.clamp(c[3] * f, 0, 1) }
end

function U.withAlpha(c, a)
    return { c[1], c[2], c[3], a }
end

-- Set love color from a {r,g,b} (or {r,g,b,a}) table, optional alpha override.
function U.setColor(c, a)
    if a then
        love.graphics.setColor(c[1], c[2], c[3], a)
    else
        love.graphics.setColor(c[1], c[2], c[3], c[4] or 1)
    end
end

-- Point-in-rect (used for mouse UI hit-testing in logical coordinates).
function U.inRect(px, py, x, y, w, h)
    return px >= x and px <= x + w and py >= y and py <= y + h
end

-- Format an integer with thousands separators: 12345 -> "12,345".
function U.commafy(n)
    n = math.floor(n + 0.5)
    local s = tostring(n)
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end

-- Deep copy of plain data tables.
function U.deepcopy(t)
    if type(t) ~= "table" then return t end
    local r = {}
    for k, v in pairs(t) do r[k] = U.deepcopy(v) end
    return r
end

-- Draw a "Thing" — the game's currency token: a small white cubic blob, shown
-- as a soft isometric cube. `s` is roughly the half-size. Used in counters, the
-- in-world pickups, and the shop's coin-fly animation so the currency reads the
-- same everywhere.
function U.drawThing(x, y, s, alpha)
    alpha = alpha or 1
    -- top face (brightest)
    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.polygon("fill", x, y - s, x + s, y - s * 0.5, x, y, x - s, y - s * 0.5)
    -- left face (shaded)
    love.graphics.setColor(0.70, 0.78, 0.92, alpha)
    love.graphics.polygon("fill", x - s, y - s * 0.5, x, y, x, y + s, x - s, y + s * 0.5)
    -- right face (mid)
    love.graphics.setColor(0.86, 0.91, 1.0, alpha)
    love.graphics.polygon("fill", x + s, y - s * 0.5, x, y, x, y + s, x + s, y + s * 0.5)
end

-- Draw a soft radial glow (cheap: stacked translucent circles).
function U.glow(x, y, radius, color, intensity)
    intensity = intensity or 0.4
    local steps = 6
    for i = steps, 1, -1 do
        local f = i / steps
        love.graphics.setColor(color[1], color[2], color[3], intensity * (1 - f) * (1 - f))
        love.graphics.circle("fill", x, y, radius * f)
    end
end

return U
