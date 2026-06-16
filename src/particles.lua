-- Lightweight particle pool. Used for ink splatter, bubbles, death bursts,
-- pickups sparkle, and the ambient marine-snow drifting in every scene.
local U = require("src.util")
local Particles = {}
Particles.__index = Particles

function Particles.new()
    return setmetatable({ list = {} }, Particles)
end

-- kind: "spark" (shrinking dot), "bubble" (rising ring), "ink" (fading blob),
-- "ring" (expanding ring).
function Particles:spawn(x, y, opts)
    opts = opts or {}
    local p = {
        x = x, y = y,
        vx = opts.vx or 0, vy = opts.vy or 0,
        life = opts.life or 0.6, maxLife = opts.life or 0.6,
        size = opts.size or 3,
        color = opts.color or { 1, 1, 1 },
        kind = opts.kind or "spark",
        drag = opts.drag or 2,
        grav = opts.grav or 0,
        spin = opts.spin or 0, rot = opts.rot or 0,
        seed = opts.seed or 0,
    }
    self.list[#self.list + 1] = p
    return p
end

function Particles:burst(x, y, n, color, opts)
    opts = opts or {}
    local spd = opts.speed or 120
    for _ = 1, n do
        local a = U.rand(0, math.pi * 2)
        local s = U.rand(spd * 0.3, spd)
        self:spawn(x, y, {
            vx = math.cos(a) * s, vy = math.sin(a) * s,
            life = U.rand(0.3, opts.life or 0.7),
            size = U.rand(opts.size or 2, (opts.size or 2) + 3),
            color = color, kind = opts.kind or "spark", drag = opts.drag or 3,
        })
    end
end

function Particles:update(dt)
    local list = self.list
    local i = 1
    while i <= #list do
        local p = list[i]
        p.life = p.life - dt
        if p.life <= 0 then
            list[i] = list[#list]
            list[#list] = nil
        else
            local d = math.exp(-p.drag * dt)
            p.vx = p.vx * d
            p.vy = p.vy * d + p.grav * dt
            p.x = p.x + p.vx * dt
            p.y = p.y + p.vy * dt
            p.rot = p.rot + p.spin * dt
            i = i + 1
        end
    end
end

function Particles:draw()
    for _, p in ipairs(self.list) do
        local a = p.life / p.maxLife
        local c = p.color
        if p.kind == "spark" or p.kind == "ink" then
            love.graphics.setColor(c[1], c[2], c[3], a)
            love.graphics.circle("fill", p.x, p.y, p.size * (p.kind == "ink" and (0.4 + a) or a))
        elseif p.kind == "bubble" then
            love.graphics.setColor(c[1], c[2], c[3], a * 0.7)
            love.graphics.circle("line", p.x, p.y, p.size)
        elseif p.kind == "ring" then
            love.graphics.setLineWidth(2)
            love.graphics.setColor(c[1], c[2], c[3], a * 0.8)
            love.graphics.circle("line", p.x, p.y, p.size * (1.6 - a))
        elseif p.kind == "rune" then
            -- a small drawn glyph (simple strokes; varies by seed)
            local s = p.size * (0.6 + a)
            local sd = p.seed
            love.graphics.push(); love.graphics.translate(p.x, p.y); love.graphics.rotate(p.rot)
            love.graphics.setColor(c[1], c[2], c[3], a * 0.95)
            love.graphics.setLineWidth(1.5)
            love.graphics.line(0, -s, 0, s)                                   -- spine
            love.graphics.line(-s * 0.5, -s * 0.4, s * 0.5, -s * 0.4)         -- top bar
            if sd % 2 == 0 then love.graphics.line(-s * 0.5, s * 0.4, s * 0.5, s * 0.4) end
            if sd % 3 == 0 then love.graphics.circle("line", 0, 0, s * 0.34) end
            if sd % 2 == 1 then love.graphics.line(-s * 0.5, 0, s * 0.5, -s * 0.3) end
            love.graphics.pop()
        elseif p.kind == "digit" then
            -- floating lime binary digits (0/1) for the hacker trail — just glowing
            -- text, no tile (the tiles are on the bullets)
            local s = p.size * (0.55 + 0.45 * a)
            love.graphics.setColor(c[1], c[2], c[3], a)
            love.graphics.setLineWidth(math.max(2, s * 0.18))
            if p.seed % 2 == 1 then
                love.graphics.line(p.x, p.y - s * 0.5, p.x, p.y + s * 0.5)               -- "1"
                love.graphics.line(p.x, p.y - s * 0.5, p.x - s * 0.24, p.y - s * 0.26)
            else
                love.graphics.ellipse("line", p.x, p.y, s * 0.34, s * 0.52)              -- "0"
            end
        end
    end
end

function Particles:count() return #self.list end

return Particles
