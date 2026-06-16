-- Enemy bestiary. Eight unique base creatures, each with distinct AI and look,
-- plus stronger "Abyssal" variants and two bosses (the Warden, the Maw).
--
-- ctx passed to ai/render each frame:
--   { player = {x,y, alive}, shoot(x,y,vx,vy,dmg,color,radius,life),
--     spawnAdd(id,x,y,opts), particles, arena, time }
local U = require("src.util")
local P = require("src.palette")
local E = {}

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------
-- Read a custom-campaign editor knob off an enemy (e.cfg holds the per-spawn
-- "special" overrides). 0 / nil means "use the built-in default".
local function spec(e, key, default)
    local v = e.cfg and e.cfg[key]
    if v and v > 0 then return v end
    return default
end

-- Distance-based body trail for the worm/leech-style segmented mobs: records a
-- point each time the head has moved ~radius*gap from the last (so the spacing
-- between segments scales with the creature's SIZE, not its speed), and keeps
-- `segN` segments. Fixes scaled mobs looking bunched-up or strung-out.
local function trailBody(e, segN, gap)
    e.trail = e.trail or {}
    local last = e.trail[1]
    local step = e.radius * gap
    if not last or U.dist(e.x, e.y, last[1], last[2]) >= step then
        table.insert(e.trail, 1, { e.x, e.y })
        for _ = math.max(1, segN) + 1, #e.trail do table.remove(e.trail) end
    end
end

local function moveToward(e, tx, ty, speed, dt)
    local nx, ny = U.normalize(tx - e.x, ty - e.y)
    e.x = e.x + nx * speed * dt
    e.y = e.y + ny * speed * dt
    if nx ~= 0 or ny ~= 0 then e.facing = math.atan2(ny, nx) end
end

local function clampArena(e, ctx, pad)
    pad = pad or e.radius
    local a = ctx.arena
    e.x = U.clamp(e.x, a.x + pad, a.x + a.w - pad)
    e.y = U.clamp(e.y, a.y + pad, a.y + a.h - pad)
end

-- Bullet-dodging: if a player ink bolt is bearing down on `e`, jink sideways
-- (perpendicular to the bolt) so it whiffs. Makes evasive enemies hard to just
-- spray down. Returns true if it dodged this frame.
local function dodgeBullets(e, ctx, react, strength, dt)
    if not ctx.bullets then return false end
    for _, b in ipairs(ctx.bullets.list) do
        if b.team == "player" then
            local dx, dy = e.x - b.x, e.y - b.y
            if dx * dx + dy * dy < react * react and (b.vx * dx + b.vy * dy) > 0 then
                local bx, by = U.normalize(b.vx, b.vy)
                local side = (dx * by - dy * bx) >= 0 and 1 or -1
                e.x = e.x - by * side * strength * dt
                e.y = e.y + bx * side * strength * dt
                return true
            end
        end
    end
    return false
end

-- soft body blob used by several creatures
local function blob(x, y, r, n, t, wob)
    local pts = {}
    for i = 0, n - 1 do
        local a = i / n * math.pi * 2
        local rr = r * (1 + wob * 0.12 * math.sin(a * 3 + t * 4))
        pts[#pts + 1] = x + math.cos(a) * rr
        pts[#pts + 1] = y + math.sin(a) * rr
    end
    love.graphics.polygon("fill", pts)
end

----------------------------------------------------------------------
-- TYPES
----------------------------------------------------------------------
E.types = {}

E.types.drifter = {
    name = "Drifter", hp = 38, speed = 46, radius = 18, damage = 10, score = 8, things = 2,
    color = { 0.55, 0.45, 0.95 }, glow = { 0.7, 0.5, 1.0 },
    ai = function(e, dt, ctx)
        e.wob = (e.wob or 0) + dt
        local wobx = math.cos(e.wob * 2) * 18
        moveToward(e, ctx.player.x + wobx, ctx.player.y, e.speed, dt)
        clampArena(e, ctx)
    end,
    render = function(e, ctx)
        local t = e.anim
        local pulse = 1 + 0.12 * math.sin(t * 4)
        U.glow(e.x, e.y, e.radius * 1.8, e.glow, 0.4)
        -- trailing tentacles
        U.setColor(U.shade(e.color, 0.8), 0.8)
        for i = 1, 6 do
            local ox = (i - 3.5) * e.radius * 0.28
            local sway = math.sin(t * 5 + i) * e.radius * 0.3
            love.graphics.setLineWidth(3)
            love.graphics.line(e.x + ox, e.y, e.x + ox + sway, e.y + e.radius * 1.6)
        end
        -- bell
        U.setColor(e.color)
        love.graphics.arc("fill", e.x, e.y, e.radius * pulse, math.pi, math.pi * 2, 18)
        love.graphics.rectangle("fill", e.x - e.radius * pulse, e.y, e.radius * 2 * pulse, e.radius * 0.4)
        U.setColor(U.shade(e.color, 1.4), 0.6)
        love.graphics.arc("line", e.x, e.y, e.radius * 0.7, math.pi, math.pi * 2, 14)
    end,
}

E.types.darter = {
    name = "Darter", hp = 22, speed = 220, radius = 11, damage = 8, score = 6, things = 1,
    color = { 0.4, 0.95, 0.85 }, glow = { 0.4, 1.0, 0.9 },
    ai = function(e, dt, ctx)
        e.timer = (e.timer or 0) - dt
        if e.timer <= 0 then
            e.timer = U.rand(0.6, 1.1)
            local a = U.angleTo(e.x, e.y, ctx.player.x, ctx.player.y) + U.rand(-0.4, 0.4)
            e.dvx, e.dvy = math.cos(a), math.sin(a)
            e.facing = a
        end
        e.x = e.x + (e.dvx or 0) * e.speed * dt
        e.y = e.y + (e.dvy or 0) * e.speed * dt
        local a = ctx.arena
        if e.x < a.x + e.radius or e.x > a.x + a.w - e.radius then e.dvx = -(e.dvx or 0) end
        if e.y < a.y + e.radius or e.y > a.y + a.h - e.radius then e.dvy = -(e.dvy or 0) end
        clampArena(e, ctx)
    end,
    render = function(e, ctx)
        U.glow(e.x, e.y, e.radius * 1.5, e.glow, 0.35)
        love.graphics.push(); love.graphics.translate(e.x, e.y); love.graphics.rotate(e.facing or 0)
        U.setColor(e.color)
        love.graphics.polygon("fill", e.radius, 0, -e.radius, -e.radius * 0.7, -e.radius * 0.6, 0, -e.radius, e.radius * 0.7)
        -- tail flick
        U.setColor(U.shade(e.color, 0.7))
        local flick = math.sin(e.anim * 18) * e.radius * 0.5
        love.graphics.polygon("fill", -e.radius * 0.6, 0, -e.radius * 1.4, flick, -e.radius * 1.4, -flick)
        love.graphics.pop()
    end,
}

E.types.snapper = {
    name = "Snapper", hp = 95, speed = 66, radius = 20, damage = 18, score = 22, things = 6,
    spawnWeight = 0.28,  -- tanky bruiser: deliberately rare, even in big waves
    color = { 0.62, 0.18, 0.20 }, glow = { 1.0, 0.32, 0.22 },
    ai = function(e, dt, ctx)
        e.state = e.state or "approach"
        e.st = (e.st or 0) - dt
        if e.state == "approach" then
            moveToward(e, ctx.player.x, ctx.player.y, e.speed, dt)
            -- charge from much FARTHER away, with a snappier windup
            if U.dist(e.x, e.y, ctx.player.x, ctx.player.y) < 360 and e.st <= 0 then
                e.state = "windup"; e.st = 0.32
                e.aimx, e.aimy = ctx.player.x, ctx.player.y
            end
        elseif e.state == "windup" then
            if e.st <= 0 then
                -- faster charge that covers a LONGER distance
                e.state = "charge"; e.st = 0.5
                local a = U.angleTo(e.x, e.y, e.aimx, e.aimy)
                e.cvx, e.cvy = math.cos(a) * e.speed * 8.5, math.sin(a) * e.speed * 8.5
                e.facing = a
            end
        elseif e.state == "charge" then
            e.x = e.x + e.cvx * dt; e.y = e.y + e.cvy * dt
            if e.st <= 0 then e.state = "approach"; e.st = U.rand(0.5, 0.9) end
        end
        clampArena(e, ctx)
    end,
    render = function(e, ctx)
        local t = e.anim
        local r = e.radius
        local f = e.facing or 0
        if e.state ~= "charge" then
            f = U.angleTo(e.x, e.y, ctx.player.x, ctx.player.y)  -- face the prey
        end
        local fx, fy = math.cos(f), math.sin(f)          -- forward
        local px, py = -fy, fx                            -- right (perp)
        local dark = U.shade(e.color, 0.55)
        local lite = U.shade(e.color, 1.35)

        -- charge telegraph: claws gape + glow charges during windup
        local charging = e.state == "windup"
        local gape = charging and (0.55 + 0.35 * math.abs(math.sin(t * 24))) or 0.16
        local reach = e.state == "charge" and 1.0 or (charging and 0.55 or 0.7)
        local legBeat = math.sin(t * (e.state == "charge" and 22 or 9))

        love.graphics.push()
        love.graphics.translate(e.x, e.y)

        -- 4 segmented walking legs per side (drawn behind the shell)
        love.graphics.setColor(dark[1], dark[2], dark[3], 1)
        for s = -1, 1, 2 do
            for k = 1, 4 do
                local spread = (k - 2.5) * 0.42
                local baseA = math.atan2(py, px) * s + spread
                local hx = (px * s) * r * 0.7 + fx * (k - 2.5) * r * 0.30
                local hy = (py * s) * r * 0.7 + fy * (k - 2.5) * r * 0.30
                local kneeA = baseA + (legBeat * 0.12 + 0.2) * s
                local kx = hx + math.cos(kneeA) * r * 0.85
                local ky = hy + math.sin(kneeA) * r * 0.85
                local tipA = kneeA + 0.7 * s
                local tx = kx + math.cos(tipA) * r * 0.7
                local ty = ky + math.sin(tipA) * r * 0.7
                love.graphics.setLineWidth(4)
                love.graphics.line(hx, hy, kx, ky)
                love.graphics.setLineWidth(2.5)
                love.graphics.line(kx, ky, tx, ty)        -- pointed foot
            end
        end

        -- carapace: hard armored shell with ridges + spikes + rim light
        U.glow(0, 0, r * 1.5, e.glow, charging and 0.5 or 0.22)
        local cw, ch = r * 1.25, r * 0.92
        love.graphics.push(); love.graphics.rotate(f + math.pi / 2)
        love.graphics.setColor(e.color); love.graphics.ellipse("fill", 0, 0, cw, ch, 18)
        love.graphics.setColor(dark[1], dark[2], dark[3], 1); love.graphics.ellipse("fill", 0, -ch * 0.18, cw * 0.92, ch * 0.6, 18)
        -- shell ridges
        love.graphics.setColor(lite[1], lite[2], lite[3], 0.7); love.graphics.setLineWidth(2)
        for i = -2, 2 do
            love.graphics.line(i * cw * 0.28, -ch * 0.5, i * cw * 0.34, ch * 0.45)
        end
        -- spikes along the leading brow
        love.graphics.setColor(lite[1], lite[2], lite[3], 1)
        for i = -3, 3 do
            local sxk = i * cw * 0.24
            love.graphics.polygon("fill", sxk - cw * 0.06, -ch * 0.86, sxk + cw * 0.06, -ch * 0.86, sxk, -ch * 1.12)
        end
        love.graphics.pop()

        -- two armored arms + serrated pincer claws reaching FORWARD (drawn over
        -- the shell so they read as the crab's main threat).
        for s = -1, 1, 2 do
            local sx = px * s * r * 0.7                       -- shoulder on the front-side
            local sy = py * s * r * 0.7
            local elbx = sx + fx * r * 0.7 + px * s * r * 0.25
            local elby = sy + fy * r * 0.7 + py * s * r * 0.25
            local handx = elbx + fx * r * (1.0 * reach) - px * s * r * 0.1
            local handy = elby + fy * r * (1.0 * reach) - py * s * r * 0.1
            love.graphics.setColor(dark[1], dark[2], dark[3], 1)
            love.graphics.setLineWidth(9); love.graphics.line(sx, sy, elbx, elby)   -- upper arm
            love.graphics.setLineWidth(7); love.graphics.line(elbx, elby, handx, handy) -- forearm
            love.graphics.setColor(e.color); love.graphics.circle("fill", elbx, elby, r * 0.16)  -- elbow joint

            -- claw hand, rotated to point along the forearm
            local ca = math.atan2(handy - elby, handx - elbx)
            love.graphics.push(); love.graphics.translate(handx, handy); love.graphics.rotate(ca)
            local cs = r * 0.85
            love.graphics.setColor(e.color)                  -- palm / knuckle
            love.graphics.polygon("fill", -cs * 0.35, -cs * 0.5, cs * 0.35, -cs * 0.45, cs * 0.45, cs * 0.45, -cs * 0.35, cs * 0.5)
            -- two opposing serrated fingers that gape during windup
            for _, sgn in ipairs({ -1, 1 }) do
                love.graphics.push(); love.graphics.translate(cs * 0.35, sgn * cs * 0.28); love.graphics.rotate(sgn * gape)
                love.graphics.setColor(lite[1], lite[2], lite[3], 1)
                love.graphics.polygon("fill", 0, -sgn * cs * 0.05, cs * 1.05, -sgn * cs * 0.04, cs * 1.3, sgn * cs * 0.16, 0, sgn * cs * 0.3)
                love.graphics.setColor(dark[1], dark[2], dark[3], 1)   -- inner serrations
                for tooth = 0, 3 do
                    local tx = cs * (0.32 + tooth * 0.22)
                    love.graphics.polygon("fill", tx, sgn * cs * 0.02, tx + cs * 0.10, sgn * cs * 0.16, tx + cs * 0.2, sgn * cs * 0.02)
                end
                love.graphics.pop()
            end
            love.graphics.pop()
        end

        -- two glowing eyes on short stalks, aimed forward
        for s = -1, 1, 2 do
            local exs = fx * r * 0.55 + px * s * r * 0.32
            local eys = fy * r * 0.55 + py * s * r * 0.32
            love.graphics.setColor(dark[1], dark[2], dark[3], 1); love.graphics.setLineWidth(3)
            love.graphics.line(px * s * r * 0.22, py * s * r * 0.22, exs, eys)
            U.glow(exs, eys, r * 0.4, e.glow, charging and 1.0 or 0.7)
            love.graphics.setColor(e.glow); love.graphics.circle("fill", exs, eys, r * 0.16)
            love.graphics.setColor(1, 1, 1, 0.9); love.graphics.circle("fill", exs, eys, r * 0.06)
        end
        love.graphics.pop()
    end,
}

E.types.spitter = {
    name = "Spitter", hp = 38, speed = 30, radius = 17, damage = 10, score = 12, things = 3,
    color = { 0.7, 0.4, 0.9 }, glow = { 0.8, 0.4, 1.0 },
    ai = function(e, dt, ctx)
        e.wob = (e.wob or 0) + dt
        moveToward(e, ctx.player.x, ctx.player.y, e.speed * (0.5 + 0.5 * math.sin(e.wob)), dt)
        e.timer = (e.timer or U.rand(1.5, 2.8)) - dt
        if e.timer <= 0 then
            e.timer = spec(e, "fireCd", 3.4)           -- fires less often (less spam)
            local n = spec(e, "rings", 8)              -- a clean 8-point ring with a gap
            local gap = love.math.random(n)
            for i = 1, n do
                if i ~= gap then
                    local a = i / n * math.pi * 2 + e.wob
                    ctx.shoot(e.x, e.y, math.cos(a) * 140, math.sin(a) * 140, e.damage, e.glow, 6, 4)
                end
            end
            ctx.particles:burst(e.x, e.y, 6, e.glow, { speed = 80 })
        end
        clampArena(e, ctx)
    end,
    render = function(e, ctx)
        local t = e.anim
        U.glow(e.x, e.y, e.radius * 1.5, e.glow, 0.35)
        U.setColor(U.shade(e.color, 0.9))
        for i = 1, 12 do
            local a = i / 12 * math.pi * 2 + t * 0.5
            local sp = e.radius * (1.5 + 0.15 * math.sin(t * 3 + i))
            love.graphics.setLineWidth(3)
            love.graphics.line(e.x, e.y, e.x + math.cos(a) * sp, e.y + math.sin(a) * sp)
        end
        U.setColor(e.color)
        love.graphics.circle("fill", e.x, e.y, e.radius)
        U.setColor(e.glow, 0.5 + 0.4 * math.sin(t * 5))
        love.graphics.circle("fill", e.x, e.y, e.radius * 0.5)
    end,
}

-- The Lurker is an ambush predator: it skulks at range and plants glowing
-- "light-lures" right where you're standing. Each lure arms over ~1.3s (its
-- flash quickens as a warning) then detonates into a ring of bullets — so you
-- can never stand still near one. Kill the Lurker to stop the traps.
E.types.lurker = {
    name = "Lurker", hp = 42, speed = 88, radius = 19, damage = 11, score = 18, things = 5,
    color = { 0.14, 0.22, 0.32 }, glow = { 0.4, 1.0, 0.9 },
    ai = function(e, dt, ctx)
        e.lures = e.lures or {}
        local d = U.dist(e.x, e.y, ctx.player.x, ctx.player.y)
        if d < 270 then
            moveToward(e, e.x * 2 - ctx.player.x, e.y * 2 - ctx.player.y, e.speed, dt)   -- retreat
        elseif d > 360 then
            moveToward(e, ctx.player.x, ctx.player.y, e.speed * 0.7, dt)                 -- close in
        else
            local a = U.angleTo(e.x, e.y, ctx.player.x, ctx.player.y) + math.pi / 2      -- strafe
            e.x = e.x + math.cos(a) * e.speed * dt
            e.y = e.y + math.sin(a) * e.speed * dt
        end
        e.facing = U.angleTo(e.x, e.y, ctx.player.x, ctx.player.y)
        clampArena(e, ctx)

        -- plant a lure trap on the player's position
        e.castTimer = (e.castTimer or U.rand(1.0, 1.8)) - dt
        if e.castTimer <= 0 then
            e.castTimer = spec(e, "fireCd", 0); if e.castTimer <= 0 then e.castTimer = U.rand(2.6, 3.4) end
            local a = ctx.arena
            local lx = U.clamp(ctx.player.x + U.rand(-35, 35), a.x + 20, a.x + a.w - 20)
            local ly = U.clamp(ctx.player.y + U.rand(-35, 35), a.y + 20, a.y + a.h - 20)
            e.lures[#e.lures + 1] = { x = lx, y = ly, fuse = 1.3, max = 1.3 }
            ctx.particles:burst(lx, ly, 6, e.glow, { speed = 40 })
        end
        -- arm + detonate lures into a bullet ring
        local i = 1
        while i <= #e.lures do
            local lu = e.lures[i]
            lu.fuse = lu.fuse - dt
            if lu.fuse <= 0 then
                local n = spec(e, "shrapnel", 11)
                for k = 1, n do
                    local aa = k / n * math.pi * 2
                    ctx.shoot(lu.x, lu.y, math.cos(aa) * 175, math.sin(aa) * 175, e.damage, e.glow, 6, 4)
                end
                ctx.particles:burst(lu.x, lu.y, 16, e.glow, { speed = 200 })
                table.remove(e.lures, i)
            else i = i + 1 end
        end
    end,
    render = function(e, ctx)
        local t = e.anim
        -- pending lures: warning orbs that flash faster as they arm
        for _, lu in ipairs(e.lures or {}) do
            local f = 1 - lu.fuse / lu.max
            local flash = 0.5 + 0.5 * math.abs(math.sin(t * (6 + f * 34)))
            U.glow(lu.x, lu.y, 20 + f * 18, e.glow, 0.6 * flash)
            U.setColor(e.glow, flash); love.graphics.circle("fill", lu.x, lu.y, 4 + f * 5)
            U.setColor(e.glow, 0.5 * flash); love.graphics.setLineWidth(2)
            love.graphics.circle("line", lu.x, lu.y, 28)        -- danger radius
        end
        -- dim angler body + gaping maw
        U.setColor(e.color); blob(e.x, e.y, e.radius, 12, t, 0.5)
        U.setColor(P.abyss)
        love.graphics.push(); love.graphics.translate(e.x, e.y); love.graphics.rotate(e.facing or 0)
        love.graphics.polygon("fill", e.radius * 0.9, 0, e.radius * 0.2, -e.radius * 0.5, e.radius * 0.2, e.radius * 0.5)
        U.setColor(P.white)
        for i = -2, 2 do
            love.graphics.polygon("fill", e.radius * 0.3, i * 3, e.radius * 0.7, i * 3 - 2, e.radius * 0.7, i * 3 + 2)
        end
        love.graphics.pop()
        -- lure light on a stalk
        local lx = e.x + math.cos(e.facing or 0) * e.radius * 1.6 + math.sin(t * 2) * 4
        local ly = e.y + math.sin(e.facing or 0) * e.radius * 1.6
        U.setColor(e.glow, 0.4); love.graphics.setLineWidth(2)
        love.graphics.line(e.x, e.y, lx, ly)
        U.glow(lx, ly, e.radius * 0.9, e.glow, 0.9)
        U.setColor(e.glow); love.graphics.circle("fill", lx, ly, e.radius * 0.25)
    end,
}

E.types.gulper = {
    name = "Gulper", hp = 50, speed = 130, radius = 16, damage = 14, score = 16, things = 4,
    color = { 0.35, 0.7, 0.55 }, glow = { 0.4, 1.0, 0.6 },
    ai = function(e, dt, ctx)
        e.trail = e.trail or {}
        e.lunge = (e.lunge or 0) - dt
        local spd = e.speed
        if e.lunge <= 0 then e.lunge = U.rand(1.2, 2.0); e.boost = 0.5 end
        if (e.boost or 0) > 0 then e.boost = e.boost - dt; spd = e.speed * 2.4 end
        moveToward(e, ctx.player.x, ctx.player.y, spd, dt)
        clampArena(e, ctx)
        -- record body trail by DISTANCE (spacing scales with size, not speed) and
        -- keep a configurable number of segments
        trailBody(e, spec(e, "segs", 10), 0.6)
    end,
    render = function(e, ctx)
        local tr = e.trail or {}
        for i = #tr, 1, -1 do
            local seg = tr[i]
            local f = i / #tr
            U.setColor(U.shade(e.color, 0.6 + 0.4 * (1 - f)), 1)
            love.graphics.circle("fill", seg[1], seg[2], e.radius * (1 - f * 0.7))
        end
        U.glow(e.x, e.y, e.radius * 1.4, e.glow, 0.3)
        U.setColor(e.color); love.graphics.circle("fill", e.x, e.y, e.radius)
        U.setColor(P.abyss)
        love.graphics.push(); love.graphics.translate(e.x, e.y); love.graphics.rotate(e.facing or 0)
        love.graphics.arc("fill", 0, 0, e.radius * 0.9, -0.7, 0.7, 10)
        love.graphics.pop()
    end,
}

E.types.puffer = {
    name = "Puffer", hp = 30, speed = 55, radius = 16, damage = 26, score = 14, things = 4,
    color = { 0.95, 0.8, 0.35 }, glow = { 1.0, 0.7, 0.2 },
    ai = function(e, dt, ctx)
        if e.state == "boom" then return end
        local d = U.dist(e.x, e.y, ctx.player.x, ctx.player.y)
        if e.state == "inflate" then
            e.st = e.st - dt
            if e.st <= 0 then
                e.state = "boom"
                e.explodeNow = true   -- game reads this to apply AoE + kill
            end
        else
            moveToward(e, ctx.player.x, ctx.player.y, e.speed, dt)
            if d < 80 then e.state = "inflate"; e.st = 0.6 end
        end
        clampArena(e, ctx)
    end,
    render = function(e, ctx)
        local t = e.anim
        local infl = e.state == "inflate" and (1 + 0.5 * math.abs(math.sin(t * 25))) or 1
        U.glow(e.x, e.y, e.radius * 1.6 * infl, e.glow, 0.4)
        U.setColor(e.color)
        love.graphics.circle("fill", e.x, e.y, e.radius * infl)
        U.setColor(U.shade(e.color, 0.7))
        for i = 1, 10 do
            local a = i / 10 * math.pi * 2
            local sp = e.radius * infl * 1.5
            love.graphics.polygon("fill",
                e.x + math.cos(a) * e.radius * infl, e.y + math.sin(a) * e.radius * infl,
                e.x + math.cos(a + 0.2) * sp, e.y + math.sin(a + 0.2) * sp,
                e.x + math.cos(a - 0.2) * sp, e.y + math.sin(a - 0.2) * sp)
        end
        U.setColor(P.abyss)
        love.graphics.circle("fill", e.x - e.radius * 0.3, e.y - 2, 3)
        love.graphics.circle("fill", e.x + e.radius * 0.3, e.y - 2, 3)
    end,
}

E.types.wisp = {
    name = "Wisp", hp = 34, speed = 60, radius = 14, damage = 12, score = 16, things = 5,
    color = { 0.6, 0.9, 1.0 }, glow = { 0.6, 0.95, 1.0 },
    ai = function(e, dt, ctx)
        moveToward(e, ctx.player.x, ctx.player.y, e.speed, dt)
        e.blink = (e.blink or U.rand(2, 3)) - dt
        e.phase = math.max(0, (e.phase or 0) - dt)
        if e.blink <= 0 then
            e.blink = U.rand(2.5, 3.5)
            local a = U.rand(0, math.pi * 2)
            local r = U.rand(120, 200)
            e.x = ctx.player.x + math.cos(a) * r
            e.y = ctx.player.y + math.sin(a) * r
            e.phase = 0.4
            ctx.particles:burst(e.x, e.y, 12, e.glow, { speed = 120, kind = "spark" })
        end
        clampArena(e, ctx)
    end,
    render = function(e, ctx)
        local t = e.anim
        local a = e.phase and e.phase > 0 and 0.4 or 1
        U.glow(e.x, e.y, e.radius * 2.2, e.glow, 0.5 * a)
        U.setColor(e.color, a)
        for i = 1, 5 do
            local off = math.sin(t * 3 + i) * e.radius * 0.4
            love.graphics.circle("fill", e.x + off, e.y - i * e.radius * 0.3 + e.radius, e.radius * (1 - i * 0.12))
        end
        U.setColor(P.abyss, a)
        love.graphics.circle("fill", e.x - 4, e.y - 2, 2.5)
        love.graphics.circle("fill", e.x + 4, e.y - 2, 2.5)
    end,
}

----------------------------------------------------------------------
-- BOSSES
----------------------------------------------------------------------
E.types.warden = {
    name = "The Warden", boss = true, hp = 1600, speed = 60, radius = 56, damage = 24,
    score = 400, things = 60, color = { 0.9, 0.4, 0.5 }, glow = { 1.0, 0.3, 0.4 },
    ai = function(e, dt, ctx)
        e.phaseT = (e.phaseT or 0) + dt
        local function ring(speed, gapHalf)
            e.gapA = (e.gapA or 0) + 0.7
            local n = spec(e, "ringBullets", 20)
            for i = 1, n do
                local aa = i / n * math.pi * 2
                if math.abs(U.angleDiff(aa, e.gapA)) > gapHalf * (2 * math.pi / n) then
                    ctx.shoot(e.x, e.y, math.cos(aa) * speed, math.sin(aa) * speed, e.damage, e.glow, 7, 6)
                end
            end
        end

        moveToward(e, ctx.player.x, ctx.player.y, e.speed, dt)
        -- Both Wardens warm up 2s, then fire dodgeable rings on a beat. The 2nd
        -- Warden (tier2) is twice as tanky and fires twice as fast (0.5s vs 1s).
        e.warm = (e.warm or 2.0) - dt
        if e.warm <= 0 then
            e.ringT = (e.ringT or 0) - dt
            if e.ringT <= 0 then
                e.ringT = spec(e, "ringDelay", e.tier2 and 0.5 or 1.0)
                ring(e.tier2 and 430 or 400, 2.4)   -- faster than your walk: slide to the gap
            end
        end
        clampArena(e, ctx)
    end,
    render = function(e, ctx)
        local t = e.anim
        local r = e.radius
        local f = U.angleTo(e.x, e.y, ctx.player.x, ctx.player.y)
        local fx, fy = math.cos(f), math.sin(f)
        local px, py = -fy, fx
        local dark = U.shade(e.color, 0.45)
        local lite = U.shade(e.color, 1.3)
        local charging = (e.attackCd or 1) < 0.45          -- about to attack
        local flare = charging and (0.6 + 0.4 * math.abs(math.sin(t * 22))) or (0.45 + 0.2 * math.sin(t * 3))

        U.glow(e.x, e.y, r * 2.3, e.glow, charging and 0.7 or 0.4)

        love.graphics.push(); love.graphics.translate(e.x, e.y)

        -- eight heavy segmented legs
        love.graphics.setColor(dark[1], dark[2], dark[3], 1)
        for s = -1, 1, 2 do
            for k = 1, 4 do
                local base = math.atan2(py, px) * s + (k - 2.5) * 0.34
                local hx = px * s * r * 0.8 + fx * (k - 2.5) * r * 0.34
                local hy = py * s * r * 0.8 + fy * (k - 2.5) * r * 0.34
                local kneeA = base + (0.25 + math.sin(t * 4 + k) * 0.1) * s
                local kx = hx + math.cos(kneeA) * r * 1.0
                local ky = hy + math.sin(kneeA) * r * 1.0
                local tipA = kneeA + 0.7 * s
                love.graphics.setLineWidth(7); love.graphics.line(hx, hy, kx, ky)
                love.graphics.setLineWidth(4); love.graphics.line(kx, ky, kx + math.cos(tipA) * r * 0.8, ky + math.sin(tipA) * r * 0.8)
            end
        end

        -- armored carapace with plates, ridges and brow spikes
        love.graphics.push(); love.graphics.rotate(f + math.pi / 2)
        local cw, ch = r * 1.5, r * 1.15
        love.graphics.setColor(e.color); love.graphics.ellipse("fill", 0, 0, cw, ch, 22)
        love.graphics.setColor(dark[1], dark[2], dark[3], 1); love.graphics.ellipse("fill", 0, -ch * 0.2, cw * 0.92, ch * 0.62, 22)
        love.graphics.setColor(lite[1], lite[2], lite[3], 0.65); love.graphics.setLineWidth(3)
        for i = -3, 3 do love.graphics.line(i * cw * 0.2, -ch * 0.55, i * cw * 0.26, ch * 0.5) end
        for ri = 1, 3 do love.graphics.arc("line", "open", 0, ch * 0.1, r * 0.4 * ri, math.pi * 1.15, math.pi * 1.85, 14) end
        love.graphics.setColor(lite[1], lite[2], lite[3], 1)
        for i = -4, 4 do
            local sk = i * cw * 0.2
            love.graphics.polygon("fill", sk - cw * 0.05, -ch * 0.85, sk + cw * 0.05, -ch * 0.85, sk, -ch * 1.18)
        end
        love.graphics.pop()

        -- glowing heart-core + a ring of eyes (red when winding up an attack)
        love.graphics.setColor(e.glow[1], e.glow[2], e.glow[3], flare)
        love.graphics.circle("fill", 0, 0, r * 0.34)
        love.graphics.setColor(1, 1, 1, flare * 0.6); love.graphics.circle("fill", 0, 0, r * 0.15)
        for i = 1, 7 do
            local a = i / 7 * math.pi * 2 + t * 0.3
            local ex, ey = math.cos(a) * r * 0.74, math.sin(a) * r * 0.74
            U.glow(ex, ey, r * 0.22, e.glow, flare)
            love.graphics.setColor((charging and P.red or e.glow)[1], (charging and P.red or e.glow)[2], (charging and P.red or e.glow)[3], 1)
            love.graphics.circle("fill", ex, ey, r * 0.1)
            love.graphics.setColor(0, 0, 0, 0.7); love.graphics.circle("fill", ex, ey, r * 0.04)
        end
        love.graphics.pop()

        -- two massive serrated claws reaching forward (drawn over the body)
        local gape = charging and (0.5 + 0.3 * math.abs(math.sin(t * 22))) or 0.18
        for s = -1, 1, 2 do
            local sx = e.x + px * s * r * 0.9
            local sy = e.y + py * s * r * 0.9
            local hx = sx + fx * r * 1.4 - px * s * r * 0.2
            local hy = sy + fy * r * 1.4 - py * s * r * 0.2
            love.graphics.setColor(dark[1], dark[2], dark[3], 1)
            love.graphics.setLineWidth(12); love.graphics.line(sx, sy, hx, hy)
            local ca = math.atan2(hy - sy, hx - sx)
            love.graphics.push(); love.graphics.translate(hx, hy); love.graphics.rotate(ca)
            local cs = r * 0.7
            love.graphics.setColor(e.color)
            love.graphics.polygon("fill", -cs * 0.3, -cs * 0.5, cs * 0.4, -cs * 0.45, cs * 0.4, cs * 0.45, -cs * 0.3, cs * 0.5)
            for _, sgn in ipairs({ -1, 1 }) do
                love.graphics.push(); love.graphics.translate(cs * 0.35, sgn * cs * 0.28); love.graphics.rotate(sgn * gape)
                love.graphics.setColor(lite[1], lite[2], lite[3], 1)
                love.graphics.polygon("fill", 0, -sgn * cs * 0.05, cs * 1.0, -sgn * cs * 0.04, cs * 1.2, sgn * cs * 0.16, 0, sgn * cs * 0.3)
                love.graphics.setColor(dark[1], dark[2], dark[3], 1)
                for tooth = 0, 3 do
                    local tx = cs * (0.3 + tooth * 0.22)
                    love.graphics.polygon("fill", tx, sgn * cs * 0.02, tx + cs * 0.1, sgn * cs * 0.16, tx + cs * 0.2, sgn * cs * 0.02)
                end
                love.graphics.pop()
            end
            love.graphics.pop()
        end
    end,
}

E.types.maw = {
    -- Gatekeeper of the Hadal Depths (depth 8). A wall of teeth and bullets —
    -- you have to keep MOVING. Beating it drags you deeper.
    name = "The Maw", boss = true, hp = 5400, speed = 46, radius = 80, damage = 30,
    score = 1500, things = 200, color = { 0.15, 0.35, 0.4 }, glow = { 0.3, 1.0, 0.9 },
    ai = function(e, dt, ctx)
        e.phaseT = (e.phaseT or 0) + dt
        e.enraged = e.hp < e.maxHp * 0.5
        local a = U.angleTo(e.x, e.y, ctx.player.x, ctx.player.y)

        if e.lungeT and e.lungeT > 0 then
            e.lungeT = e.lungeT - dt
            e.x = e.x + e.lvx * dt; e.y = e.y + e.lvy * dt
        else
            moveToward(e, ctx.player.x, ctx.player.y, (e.enraged and e.speed * 1.3 or e.speed) * 0.55, dt)
        end

        -- PREDICTABLE RING BEAT: one ring with a moving gap on a steady rhythm.
        -- Read where the gap is and move into it. Pure, fair bullet hell.
        e.ringT = (e.ringT or 0.6) - dt
        if e.ringT <= 0 then
            e.ringT = spec(e, "ringDelay", e.enraged and 0.7 or 0.95)
            e.gapA = (e.gapA or 0) + (e.enraged and 1.1 or 0.8)   -- gap drifts each beat
            local n = spec(e, "ringBullets", 26)
            local gapHalf = (e.enraged and 1.6 or 2.4) * (2 * math.pi / n)
            for i = 1, n do
                local aa = i / n * math.pi * 2
                if math.abs(U.angleDiff(aa, e.gapA)) > gapHalf then
                    ctx.shoot(e.x, e.y, math.cos(aa) * 410, math.sin(aa) * 410, e.damage, e.glow, 7, 7)
                end
            end
        end

        -- every few beats, one telegraphed aimed shot to punish camping
        e.aimT = (e.aimT or 1.8) - dt
        if e.aimT <= 0 then
            e.aimT = e.enraged and 2.0 or 2.8
            for j = -1, 1 do
                ctx.shoot(e.x, e.y, math.cos(a + j * 0.16) * 260, math.sin(a + j * 0.16) * 260, e.damage, P.red, 8, 6)
            end
            if e.enraged and U.chance(0.4) then           -- occasional lunge
                e.lungeT = 0.4; e.lvx, e.lvy = math.cos(a) * 560, math.sin(a) * 560
            end
        end
        clampArena(e, ctx)
    end,
    render = function(e, ctx)
        local t = e.anim
        local col = e.enraged and U.mixColor(e.color, P.red, 0.5) or e.color
        -- huge maw with writhing tendrils
        U.glow(e.x, e.y, e.radius * 2.4, e.enraged and P.red or e.glow, 0.5)
        U.setColor(U.shade(col, 0.7))
        for i = 1, 10 do
            local a = i / 10 * math.pi * 2
            local sway = math.sin(t * 3 + i) * 16
            love.graphics.setLineWidth(8)
            love.graphics.line(e.x + math.cos(a) * e.radius, e.y + math.sin(a) * e.radius,
                e.x + math.cos(a) * (e.radius * 1.9) + sway, e.y + math.sin(a) * (e.radius * 1.9))
        end
        U.setColor(col); blob(e.x, e.y, e.radius, 18, t, 0.3)
        -- gullet
        U.setColor(P.abyss)
        love.graphics.circle("fill", e.x, e.y, e.radius * 0.55 * (1 + 0.1 * math.sin(t * 3)))
        U.setColor(e.glow, 0.7); love.graphics.circle("fill", e.x, e.y, e.radius * 0.2)
        -- ring of eyes
        U.setColor(e.enraged and P.red or P.gold)
        for i = 1, 6 do
            local a = i / 6 * math.pi * 2 + t * 0.5
            love.graphics.circle("fill", e.x + math.cos(a) * e.radius * 0.7, e.y + math.sin(a) * e.radius * 0.7, 6)
        end
    end,
}

----------------------------------------------------------------------
-- HADAL DEPTHS — the horror act below the Maw
----------------------------------------------------------------------
-- Flesh parasite: a dark-red, glistening leech. Round maw ringed with teeth.
-- Fast, swarmy, and EVASIVE — it jinks around your ink — then latches on to
-- drain your shell. Shake it off by dashing.
E.types.parasite = {
    name = "Flesh Parasite", hp = 120, speed = 195, radius = 12, damage = 9, score = 12, things = 3,
    latchTime = 2.4, leechRate = 13, dodge = 240,
    color = { 0.42, 0.05, 0.07 }, glow = { 1.0, 0.15, 0.18 },
    ai = function(e, dt, ctx)
        e.trail = e.trail or {}
        local pl = ctx.player
        -- LATCHED: stick to the squid and drain HP for a couple seconds.
        if e.latched then
            e.latchT = e.latchT - dt
            e.x = pl.x + (e.lx or 0); e.y = pl.y + (e.ly or 0)
            e.facing = U.angleTo(e.x, e.y, pl.x, pl.y)
            -- drain is handled by the shared latch timer (fed on latch), so extra
            -- parasites add TIME, not rate.
            -- you can't just dash it off — it drains until its timer runs out
            -- (or you kill it). Kite and shoot the rest of the swarm meanwhile.
            if e.latchT <= 0 then
                e.latched = false; e.recool = 1.4
                -- gorged and sluggish: it takes a chunk of damage as it detaches
                -- (weakened, not gone — finish it off while you can)
                e.hp = math.max(e.maxHp * 0.18, e.hp - e.maxHp * 0.45)
                e.hurtFlash = 1
                local a = U.rand(0, math.pi * 2)
                e.x = pl.x + math.cos(a) * 40; e.y = pl.y + math.sin(a) * 40
            end
            return
        end
        e.recool = math.max(0, (e.recool or 0) - dt)
        e.lunge = (e.lunge or U.rand(0.8, 1.6)) - dt
        local spd = e.speed
        if e.lunge <= 0 then e.lunge = U.rand(1.0, 1.8); e.boost = 0.35 end
        if (e.boost or 0) > 0 then e.boost = e.boost - dt; spd = e.speed * 2.2 end
        moveToward(e, pl.x, pl.y, spd, dt)
        dodgeBullets(e, ctx, 80, e.type.dodge or 240, dt)        -- jink around your ink
        clampArena(e, ctx)
        if e.recool <= 0 and U.dist(e.x, e.y, pl.x, pl.y) < e.radius + pl.radius then
            e.latched = true; e.latchT = spec(e, "latch", e.type.latchTime or 2.2)
            if ctx.parasiteLatch then ctx.parasiteLatch(e.latchT, spec(e, "leech", e.type.leechRate or 9)) end
            local ox, oy = U.normalize(e.x - pl.x, e.y - pl.y)
            e.lx, e.ly = ox * pl.radius, oy * pl.radius
        end
        trailBody(e, spec(e, "segs", 6), 0.6)
    end,
    render = function(e, ctx)
        local t = e.anim
        for i = #(e.trail or {}), 1, -1 do
            local s = e.trail[i]; local f = i / #e.trail
            U.setColor(U.shade(e.color, 0.7 + 0.4 * (1 - f)))
            love.graphics.circle("fill", s[1], s[2], e.radius * (1 - f * 0.6))
        end
        U.glow(e.x, e.y, e.radius * 1.3, e.glow, 0.35)
        U.setColor(e.color); love.graphics.circle("fill", e.x, e.y, e.radius)
        -- round toothy maw facing travel
        love.graphics.push(); love.graphics.translate(e.x, e.y); love.graphics.rotate(e.facing or 0)
        love.graphics.setColor(0, 0, 0, 1); love.graphics.circle("fill", e.radius * 0.35, 0, e.radius * 0.62)
        love.graphics.setColor(1, 1, 1, 0.95)
        for k = 1, 10 do
            local a = k / 10 * math.pi * 2
            local rr = e.radius * 0.62
            love.graphics.polygon("fill",
                e.radius * 0.35 + math.cos(a) * rr, math.sin(a) * rr,
                e.radius * 0.35 + math.cos(a + 0.18) * rr * 0.6, math.sin(a + 0.18) * rr * 0.6,
                e.radius * 0.35 + math.cos(a - 0.18) * rr * 0.6, math.sin(a - 0.18) * rr * 0.6)
        end
        love.graphics.pop()
        -- wet shine
        love.graphics.setColor(1, 1, 1, 0.5)
        love.graphics.circle("fill", e.x - e.radius * 0.3, e.y - e.radius * 0.3, e.radius * 0.22)
    end,
}

-- Abyssal Terror: a roiling mass of dark flesh, eyes and lashing tendrils — the
-- signature horror of the Hadal Depths. Fast for its size, hits hard, and
-- alternates an aimed spread with a sudden radial burst. Common down here.
E.types.terror = {
    name = "Abyssal Terror", hp = 190, speed = 56, radius = 32, damage = 22, score = 30, things = 8,
    spawnWeight = 1.3,
    color = { 0.06, 0.03, 0.10 }, glow = { 0.75, 0.15, 0.95 },
    ai = function(e, dt, ctx)
        moveToward(e, ctx.player.x, ctx.player.y, e.speed, dt)
        e.timer = (e.timer or U.rand(1.2, 2.0)) - dt
        if e.timer <= 0 then
            e.timer = U.rand(1.8, 2.4)
            if love.math.random() < 0.5 then        -- aimed 3-spread
                local base = U.angleTo(e.x, e.y, ctx.player.x, ctx.player.y)
                for j = -1, 1 do
                    ctx.shoot(e.x, e.y, math.cos(base + j * 0.28) * 150, math.sin(base + j * 0.28) * 150, e.damage, e.glow, 8, 5)
                end
            else                                     -- radial burst with gaps
                for i = 1, 12 do
                    if i % 3 ~= 0 then
                        local a = i / 12 * math.pi * 2 + e.anim
                        ctx.shoot(e.x, e.y, math.cos(a) * 135, math.sin(a) * 135, e.damage, e.glow, 7, 5)
                    end
                end
            end
            ctx.particles:burst(e.x, e.y, 6, e.glow, { speed = 60 })
        end
        clampArena(e, ctx)
    end,
    render = function(e, ctx)
        local t = e.anim
        U.glow(e.x, e.y, e.radius * 2.0, e.glow, 0.35)
        -- thrashing tendrils
        U.setColor(U.shade(e.color, 1.2))
        for i = 1, 11 do
            local a = i / 11 * math.pi * 2 + t * 0.5
            local sway = math.sin(t * 3 + i) * 14
            love.graphics.setLineWidth(7)
            love.graphics.line(e.x, e.y, e.x + math.cos(a) * (e.radius * 1.9) + sway, e.y + math.sin(a) * (e.radius * 1.9))
        end
        U.setColor(e.color); blob(e.x, e.y, e.radius, 18, t, 0.7)
        -- many darting eyes
        for i = 1, 9 do
            local a = i / 9 * math.pi * 2 + t * 0.3
            local rr = e.radius * (0.4 + 0.25 * math.sin(t * 2 + i))
            local ex, ey = e.x + math.cos(a) * rr, e.y + math.sin(a) * rr
            U.setColor(e.glow); love.graphics.circle("fill", ex, ey, 4)
            love.graphics.setColor(0, 0, 0, 0.85); love.graphics.circle("fill", ex + math.cos(t) * 1.5, ey + math.sin(t) * 1.5, 1.8)
        end
        U.setColor(e.glow, 0.6 + 0.35 * math.sin(t * 4)); love.graphics.circle("fill", e.x, e.y, e.radius * 0.34)
    end,
}

-- Worm Singularity: four eel-worms fused to a single point, each swimming
-- outward in a different direction as the whole knot spins. It careens around
-- the arena fast and aimless, and its bite is brutal. Lurks in the deepest dark.
E.types.wormsing = {
    name = "Worm Singularity", hp = 200, speed = 150, radius = 42, damage = 46, score = 40, things = 11,
    spawnWeight = 1.0,
    color = { 0.45, 0.12, 0.30 }, glow = { 1.0, 0.35, 0.7 },
    ai = function(e, dt, ctx)
        e.spin = (e.spin or U.rand(0, 6)) + dt * 1.4
        -- It can't see you: it orbits a fixed point on a set circular path,
        -- sometimes reversing. Oblivious, weird, and dangerous to be near.
        if not e.cx then
            local a = ctx.arena
            local pl = ctx.player
            -- anchor the orbit to where it spawned (spawnEnemy already shoves that
            -- clear of the player) so you never start trapped inside its pull
            e.cx, e.cy = e.x, e.y
            if U.dist(e.cx, e.cy, pl.x, pl.y) < 280 then
                local aa = U.angleTo(pl.x, pl.y, e.cx, e.cy)
                if aa ~= aa then aa = U.rand(0, math.pi * 2) end   -- guard exact overlap
                e.cx = pl.x + math.cos(aa) * 300
                e.cy = pl.y + math.sin(aa) * 300
            end
            e.cx = U.clamp(e.cx, a.x + 90, a.x + a.w - 90)
            e.cy = U.clamp(e.cy, a.y + 90, a.y + a.h - 90)
            e.orbitR = U.rand(120, 200); e.orbitA = U.rand(0, math.pi * 2); e.orbitDir = 1
        end
        e.flipT = (e.flipT or U.rand(2, 4)) - dt
        if e.flipT <= 0 then e.flipT = U.rand(2, 4); e.orbitDir = -e.orbitDir end   -- changes direction
        e.orbitA = e.orbitA + e.orbitDir * (e.speed / e.orbitR) * dt
        e.x = e.cx + math.cos(e.orbitA) * e.orbitR
        e.y = e.cy + math.sin(e.orbitA) * e.orbitR
        clampArena(e, ctx)
        -- a singularity: it drags you in, and the closer you are the harder it
        -- pulls. Get away or it'll reel you onto its worms.
        local pl = ctx.player
        local pd = U.dist(e.x, e.y, pl.x, pl.y)
        local range = spec(e, "pull", e.radius * 6.5)   -- editor-tunable blackhole range
        if pd < range and pd > 4 then
            local pull = (1 - pd / range) ^ 2 * 520    -- ramps up sharply when close
            local nx, ny = U.normalize(e.x - pl.x, e.y - pl.y)
            pl.x = pl.x + nx * pull * dt
            pl.y = pl.y + ny * pull * dt
        end
    end,
    render = function(e, ctx)
        local t = e.anim
        U.glow(e.x, e.y, e.radius * 1.8, e.glow, 0.45)
        -- four worms swimming OUTWARD from a shared point — no core, just the
        -- worms joined where they meet. Bulbous toothy heads at the tips.
        for k = 0, 3 do
            local ang = (e.spin or t) + k * math.pi / 2   -- fall back to anim clock (bestiary has no ai)
            local px, py = e.x, e.y
            for i = 1, 11 do
                local f = i / 11
                local wob = math.sin(t * 6 + k * 1.7 + f * 6) * (12 + f * 18)
                px = e.x + math.cos(ang) * (e.radius * 2.6 * f) - math.sin(ang) * wob
                py = e.y + math.sin(ang) * (e.radius * 2.6 * f) + math.cos(ang) * wob
                local rr = e.radius * 0.18 + f * (e.radius * 0.42)   -- thick where they join, bulge to the head
                U.setColor(U.shade(e.color, 0.55 + 0.45 * f))
                love.graphics.circle("fill", px, py, rr)
            end
            U.glow(px, py, e.radius * 0.5, e.glow, 0.6)
            U.setColor(U.shade(e.color, 1.15)); love.graphics.circle("fill", px, py, e.radius * 0.5)
            love.graphics.setColor(0, 0, 0, 0.85); love.graphics.circle("fill", px, py, e.radius * 0.22)
            U.setColor(e.glow); love.graphics.circle("fill", px, py, e.radius * 0.1)
        end
    end,
}

-- The Unseen: you cannot make it out — only a faint distortion and a pair of
-- dim eyes drifting at you in the black. Dangerous on contact.
E.types.unseen = {
    name = "The Unseen", hp = 120, speed = 78, radius = 22, damage = 22, score = 24, things = 7,
    color = { 0.02, 0.02, 0.03 }, glow = { 0.55, 0.85, 0.9 },
    ai = function(e, dt, ctx)
        e.wob = (e.wob or 0) + dt
        moveToward(e, ctx.player.x + math.cos(e.wob) * 30, ctx.player.y + math.sin(e.wob * 1.3) * 30, e.speed, dt)
        e.blinkT = (e.blinkT or U.rand(2, 4)) - dt
        if e.blinkT <= 0 then e.blinkT = U.rand(2, 4); e.blink = 0.2 end
        e.blink = math.max(0, (e.blink or 0) - dt)
        clampArena(e, ctx)
    end,
    render = function(e, ctx)
        local t = e.anim
        -- barely-there body: a near-black shape only slightly darker than the dark
        love.graphics.setColor(0.0, 0.0, 0.0, 0.55)
        blob(e.x, e.y, e.radius * (1.2 + 0.1 * math.sin(t * 1.5)), 14, t, 0.7)
        love.graphics.setColor(e.glow[1], e.glow[2], e.glow[3], 0.05)
        love.graphics.circle("line", e.x, e.y, e.radius * 1.4)
        -- two dim eyes (vanish on blink)
        if (e.blink or 0) <= 0 then
            local f = e.facing or 0
            for s = -1, 1, 2 do
                local ex = e.x + math.cos(f) * e.radius * 0.4 + math.cos(f + math.pi / 2) * s * e.radius * 0.35
                local ey = e.y + math.sin(f) * e.radius * 0.4 + math.sin(f + math.pi / 2) * s * e.radius * 0.35
                love.graphics.setColor(e.glow[1], e.glow[2], e.glow[3], 0.7)
                love.graphics.circle("fill", ex, ey, 3.2)
            end
        end
    end,
}

-- Deep-sea mine: stationary hazard. Blinks a warning light in the dark. When
-- you get close it arms (faster blink) then detonates into an AoE + a small
-- ring. Low HP — shoot it from range to clear it safely.
E.types.mine = {
    name = "Deep Mine", hp = 18, speed = 0, radius = 30, damage = 30, score = 12, things = 3,
    spawnWeight = 1.5,   -- common hidden hazard in the dark
    color = { 0.20, 0.22, 0.28 }, glow = { 1.0, 0.5, 0.2 },
    ai = function(e, dt, ctx)
        if e.state == "boom" then return end
        e.bob = (e.bob or U.rand(0, 6)) + dt
        e.x = e.x + math.sin(e.bob) * 4 * dt   -- gentle drift in place
        local d = U.dist(e.x, e.y, ctx.player.x, ctx.player.y)
        if e.state == "arm" then
            e.st = e.st - dt
            if e.st <= 0 then e.state = "boom"; e.explodeNow = true end
        elseif d < 78 then
            e.state = "arm"; e.st = 0.7
        end
    end,
    render = function(e, ctx)
        local t = e.anim
        local arming = e.state == "arm"
        -- HIDDEN: idle it barely glints, so in the dark you won't see it until
        -- you're close — then it arms and flashes a clear warning.
        local blink = arming and (0.5 + 0.5 * math.abs(math.sin(t * 26))) or (0.08 + 0.08 * math.sin(t * 1.5))
        U.glow(e.x, e.y, e.radius * 1.6, e.glow, (arming and 0.5 or 0.12) * blink)
        U.setColor(U.shade(e.color, arming and 1.0 or 0.7)); love.graphics.circle("fill", e.x, e.y, e.radius)
        -- spikes (dark military casing)
        U.setColor(U.shade(e.color, arming and 1.4 or 0.95))
        for i = 1, 8 do
            local a = i / 8 * math.pi * 2
            love.graphics.setLineWidth(3)
            love.graphics.line(e.x + math.cos(a) * e.radius, e.y + math.sin(a) * e.radius,
                e.x + math.cos(a) * e.radius * 1.5, e.y + math.sin(a) * e.radius * 1.5)
        end
        -- warning light
        love.graphics.setColor(e.glow[1], e.glow[2], e.glow[3], blink)
        love.graphics.circle("fill", e.x, e.y, e.radius * 0.45)
    end,
}

-- The Eldritch Squid — the true final boss. A corrupted leviathan of the
-- hollow. A real wall: huge HP and relentless, layered bullet hell. Free the
-- squids by surviving it.
-- A weird drawn glyph (rune) — a jagged vertical stroke with a crossbar. The
-- look is procedural-but-stable per `seed`, so the Eldritch Squid is wreathed
-- in shifting alien script rather than random scribble.
local function rune(x, y, sz, seed, rot)
    love.graphics.push(); love.graphics.translate(x, y); love.graphics.rotate(rot or 0)
    local pts = {}
    local steps = 4 + (seed % 3)
    for k = 0, steps do
        local a = seed * 1.7 + k * 2.3
        pts[#pts + 1] = math.sin(a) * 0.5 * sz
        pts[#pts + 1] = (k / steps - 0.5) * sz * 1.5
    end
    love.graphics.line(pts)
    love.graphics.line(-sz * 0.4, math.sin(seed) * 0.3 * sz, sz * 0.4, math.cos(seed) * 0.3 * sz)
    if seed % 2 == 0 then love.graphics.circle("line", 0, math.sin(seed * 2) * sz * 0.4, sz * 0.18) end
    love.graphics.pop()
end

E.types.eldritch = {
    name = "The Eldritch Squid", boss = true, finalBoss = true, hp = 11100, speed = 52, radius = 84, damage = 26,
    score = 4000, things = 600, color = { 0.18, 0.05, 0.24 }, glow = { 0.8, 0.2, 1.0 },
    ai = function(e, dt, ctx)
        e.phaseT = (e.phaseT or 0) + dt
        e.enraged = e.hp < e.maxHp * 0.45
        local a = U.angleTo(e.x, e.y, ctx.player.x, ctx.player.y)
        moveToward(e, ctx.player.x, ctx.player.y, (e.enraged and e.speed * 1.25 or e.speed) * 0.5, dt)

        -- HALFWAY: leviathans surface on the left & right to bombard you, and in
        -- TERROR mode long arms claw in from the corners of the screen.
        if not e.summonedHalf and e.hp < e.maxHp * 0.5 then
            e.summonedHalf = true
            ctx.summonBossLevis()
            if e.terror then ctx.spawnCornerArms() end
            ctx.shake(20)
        end

        -- Once the side leviathans are bombarding you (at half health), the
        -- Eldritch backs OFF its own bullets a lot so the leviathan fire stays
        -- dodgeable instead of being a wall.
        local half = e.summonedHalf

        -- PREDICTABLE RING BEAT — slower now (fewer rings), still on a readable
        -- beat with a steadily drifting gap to dodge through.
        e.ringT = (e.ringT or 1.0) - dt
        if e.ringT <= 0 then
            e.ringT = spec(e, "ringDelay", half and 2.6 or (e.enraged and 1.1 or 1.4))
            e.gapA = (e.gapA or 0) + (e.enraged and 1.0 or 0.7)
            local n = spec(e, "ringBullets", half and 18 or 24)  -- fewer bolts in the ring
            local gapHalf = (half and 3.6 or (e.enraged and 1.9 or 2.7)) * (2 * math.pi / n)  -- bigger gap
            for i = 1, n do
                local aa = i / n * math.pi * 2
                if math.abs(U.angleDiff(aa, e.gapA)) > gapHalf then
                    ctx.shoot(e.x, e.y, math.cos(aa) * 410, math.sin(aa) * 410, e.damage, e.glow, 7, 7)
                end
            end
        end

        -- a slow steady spiral ARM (one bolt at a time) — easy to read, adds
        -- motion. Paused while the leviathans are firing.
        if not half then
            e.armT = (e.armT or 0) - dt
            if e.armT <= 0 then
                e.armT = 0.12
                e.armA = (e.armA or 0) + 0.55
                ctx.shoot(e.x, e.y, math.cos(e.armA) * 185, math.sin(e.armA) * 185, e.damage, P.purple, 6, 7)
            end
        end

        -- periodic telegraphed aimed shot + occasional add (rarer at half)
        e.aimT = (e.aimT or 2) - dt
        if e.aimT <= 0 then
            e.aimT = half and 3.6 or (e.enraged and 1.9 or 2.6)
            local spread = half and 1 or 2
            for j = -spread, spread do
                ctx.shoot(e.x, e.y, math.cos(a + j * 0.13) * 280, math.sin(a + j * 0.13) * 280, e.damage, P.red, 8, 6)
            end
            -- editor: how many parasites it spawns per burst (0 = spawns none)
            local adds = (e.cfg and e.cfg.adds) or 1
            if adds > 0 and U.chance(0.6) then
                for _ = 1, adds do ctx.spawnAdd("parasite", e.x + U.rand(-50, 50), e.y + U.rand(-50, 50), { cfg = e.addCfg }) end
            end
        end

        -- TENTACLES: it lashes anything that gets close. This punishes melee /
        -- lifesteal builds that try to sit on top of it. Reach grows when enraged.
        e.lash = math.max(0, (e.lash or 0) - dt)
        local reach = e.radius * (e.enraged and 2.6 or 2.1)
        local pd = U.dist(e.x, e.y, ctx.player.x, ctx.player.y)
        if pd < reach then
            e.tentTarget = 1
            if e.lash <= 0 then
                e.lash = 0.55
                ctx.player:takeDamage(e.damage * 1.4, ctx)     -- a hard whip
                ctx.shake(8)
            end
        else
            e.tentTarget = 0
        end
        e.tentReach = U.approach(e.tentReach or 0, e.tentTarget or 0, 8, dt)
        clampArena(e, ctx)
    end,
    render = function(e, ctx)
        local t = e.anim
        local col = e.enraged and U.mixColor(e.color, P.red, 0.4) or e.color
        local R = e.radius
        local pa = U.angleTo(e.x, e.y, ctx.player.x, ctx.player.y)
        U.glow(e.x, e.y, R * 2.9, e.glow, e.enraged and 0.6 or 0.45)

        -- long hanging squid ARMS (8), fanned below the mantle, that reach and
        -- bend toward you as you get close (drives the lashing tentacle attack)
        local reach = e.tentReach or 0
        for i = 1, 8 do
            local spread = (i - 4.5) * 0.17
            local baseA = math.pi * 0.5 + spread
            local sway = math.sin(t * 2.0 + i) * 0.18
            local len = R * (2.5 + reach * 1.3)
            local aim = baseA + U.angleDiff(baseA, pa) * reach * 0.7 + sway
            local x1 = e.x + math.cos(baseA) * R * 0.45
            local y1 = e.y + math.sin(baseA) * R * 0.45 + R * 0.25
            local mx = x1 + math.cos(baseA + sway) * len * 0.5
            local my = y1 + math.sin(baseA + sway) * len * 0.5
            local tx = mx + math.cos(aim) * len * 0.5
            local ty = my + math.sin(aim) * len * 0.5
            U.setColor(U.shade(col, reach > 0.4 and 0.95 or 0.7))
            love.graphics.setLineWidth(10 - (i % 2) * 3 + reach * 4)
            love.graphics.line(x1, y1, mx, my, tx, ty)
            if reach > 0.5 then U.setColor(e.glow); love.graphics.circle("fill", tx, ty, 5) end
        end

        -- LONG tapered mantle — a real squid body, pointed at the top
        U.setColor(col)
        love.graphics.push(); love.graphics.translate(e.x, e.y)
        love.graphics.polygon("fill",
            0, -R * 2.05, R * 0.42, -R * 1.2, R * 0.62, -R * 0.2, R * 0.5, R * 0.55,
            0, R * 0.78, -R * 0.5, R * 0.55, -R * 0.62, -R * 0.2, -R * 0.42, -R * 1.2)
        -- fins near the top of the mantle
        U.setColor(U.shade(col, 1.25))
        love.graphics.polygon("fill", R * 0.4, -R * 1.25, R * 1.05, -R * 1.55, R * 0.55, -R * 0.7)
        love.graphics.polygon("fill", -R * 0.4, -R * 1.25, -R * 1.05, -R * 1.55, -R * 0.55, -R * 0.7)
        love.graphics.pop()

        -- weird drawn GLYPHS orbiting the mantle (alien script, not a plain ring)
        love.graphics.setColor(e.glow[1], e.glow[2], e.glow[3], 0.45 + 0.35 * math.sin(t * 2))
        love.graphics.setLineWidth(2.5)
        for i = 1, 6 do
            local a = i / 6 * math.pi * 2 + t * 0.5
            local gx = e.x + math.cos(a) * R * 1.55
            local gy = e.y - R * 0.4 + math.sin(a) * R * 0.95
            rune(gx, gy, R * 0.32, i, a + math.pi * 0.5)
        end

        -- ONE huge central eye, slit pupil tracking you
        local ex, ey = e.x, e.y - R * 0.35
        local eyeC = e.enraged and P.red or e.glow
        U.glow(ex, ey, R * 0.75, eyeC, 0.7)
        love.graphics.setColor(0.92, 0.9, 0.95, 1); love.graphics.circle("fill", ex, ey, R * 0.42)   -- sclera
        U.setColor(eyeC); love.graphics.circle("fill", ex, ey, R * 0.27)                               -- iris
        local ox, oy = math.cos(pa) * R * 0.11, math.sin(pa) * R * 0.11
        love.graphics.setColor(0.02, 0.0, 0.05, 1)
        love.graphics.ellipse("fill", ex + ox, ey + oy, R * 0.07, R * 0.2)                             -- vertical slit
        love.graphics.setColor(1, 1, 1, 0.85); love.graphics.circle("fill", ex - R * 0.11, ey - R * 0.13, R * 0.05)
    end,
}

-- CHURGLY'NTH — the corrupt god of the fractalspace. A 40-segment serpent
-- curving into a vanishing point at the arena's heart, head thrashing on the
-- surface. Only reachable in TERROR, after the Eldritch Squid falls. The
-- final-final boss: an absolutely hellish, possible-but-insane bullet storm.
local CH_SEGS = 40
E.types.churglynth = {
    name = "Churgly'nth", boss = true, finalFinal = true, hp = 4500, speed = 0, radius = 46, damage = 24,
    score = 12000, things = 0, color = { 0.20, 0.03, 0.38 }, glow = { 0.85, 0.25, 1.0 },
    ai = function(e, dt, ctx)
        local a = ctx.arena
        e.ct = (e.ct or 0) + dt
        e.enraged = e.hp < e.maxHp * 0.4
        local mm = e.enraged and 1.7 or 1.0
        -- vanishing point at the arena's centre; head drifts and darts around it
        local vx, vy = a.x + a.w * 0.5, a.y + a.h * 0.5
        e.vx, e.vy = vx, vy
        local bigX = math.sin(e.ct * 0.30 * mm) * a.w * 0.34 + math.cos(e.ct * 0.16 * mm) * a.w * 0.15
        local bigY = math.sin(e.ct * 0.22 * mm + 1.3) * a.h * 0.30 + math.cos(e.ct * 0.11 * mm) * a.h * 0.12
        local dart = (math.sin(e.ct * 2.2 * mm) > 0.8) and math.sin(e.ct * 30) * 26 or 0
        e.x = U.clamp(vx + bigX + dart, a.x + 60, a.x + a.w - 60)
        e.y = U.clamp(vy + bigY, a.y + 60, a.y + a.h - 60)

        -- build the curving spine from head -> vanishing point
        local dx, dy = vx - e.x, vy - e.y
        local len = math.max(1, math.sqrt(dx * dx + dy * dy))
        local px, py = -dy / len, dx / len
        e.segN = spec(e, "segs", CH_SEGS)
        e.segPos = e.segPos or {}
        for i = #e.segPos, e.segN + 1, -1 do e.segPos[i] = nil end   -- shrink if reconfigured
        for i = 1, e.segN do
            local tp = (i - 1) / math.max(1, e.segN - 1)
            local falloff = 1 - tp
            local bx, by = e.x + dx * tp, e.y + dy * tp
            local wave = math.sin(e.ct * 1.3 + tp * 6 + e.x * 0.001) * 44 * (1 - tp) ^ 0.7
            e.segPos[i] = e.segPos[i] or {}
            local s = e.segPos[i]
            s.x = bx + px * wave; s.y = by + py * wave
            s.r = (22 * falloff + 3) * 1.15; s.fo = falloff; s.idx = i
        end

        -- it looms and speaks first — no bullets, no contact damage yet
        if (e.introT or 0) > 0 then e.introT = e.introT - dt; return end

        local pang = U.angleTo(e.x, e.y, ctx.player.x, ctx.player.y)
        -- (1) relentless spiral arms spewing from the head
        e.spin = (e.spin or 0) + dt * (e.enraged and 4.2 or 3.0)
        e.spT = (e.spT or 0) - dt
        if e.spT <= 0 then
            e.spT = e.enraged and 0.07 or 0.10
            for k = 0, (e.enraged and 3 or 2) do
                local aa = e.spin + k * (math.pi * 2 / (e.enraged and 4 or 3))
                ctx.shoot(e.x, e.y, math.cos(aa) * 300, math.sin(aa) * 300, e.damage, e.glow, 6, 6)
            end
        end
        -- (2) full rings on a beat, with a moving gap to slip through
        e.ringT = (e.ringT or 1.4) - dt
        if e.ringT <= 0 then
            e.ringT = spec(e, "ringDelay", e.enraged and 1.0 or 1.4)
            e.gapA = (e.gapA or 0) + 0.85
            local n = spec(e, "ringBullets", 30)
            local gapHalf = (e.enraged and 1.9 or 2.4) * (2 * math.pi / n)
            for i = 1, n do
                local aa = i / n * math.pi * 2
                if math.abs(U.angleDiff(aa, e.gapA)) > gapHalf then
                    ctx.shoot(e.x, e.y, math.cos(aa) * 360, math.sin(aa) * 360, e.damage, P.purple, 6, 7)
                end
            end
        end
        -- (3) aimed shotgun blast straight at you
        e.aimT = (e.aimT or 2.4) - dt
        if e.aimT <= 0 then
            e.aimT = e.enraged and 1.7 or 2.4
            for j = -3, 3 do
                ctx.shoot(e.x, e.y, math.cos(pang + j * 0.12) * 340, math.sin(pang + j * 0.12) * 340, e.damage, P.red, 8, 6)
            end
        end
        -- (4) a few segments cough bolts too (the whole serpent attacks)
        e.segT = (e.segT or 1.8) - dt
        if e.segT <= 0 then
            e.segT = 1.8
            for i = 4, e.segN, 8 do
                local s = e.segPos[i]
                if s then
                    local sa = U.angleTo(s.x, s.y, ctx.player.x, ctx.player.y)
                    ctx.shoot(s.x, s.y, math.cos(sa) * 240, math.sin(sa) * 240, e.damage * 0.7, e.glow, 5, 5)
                end
            end
        end

        -- contact damage: head + any body segment
        e.contactCd = math.max(0, (e.contactCd or 0) - dt)
        if e.contactCd <= 0 then
            local hit = U.dist(e.x, e.y, ctx.player.x, ctx.player.y) < e.radius + ctx.player.radius
            if not hit then
                for i = 1, e.segN, 2 do
                    local s = e.segPos[i]
                    if s and U.dist(s.x, s.y, ctx.player.x, ctx.player.y) < s.r + ctx.player.radius then hit = true; break end
                end
            end
            if hit then e.contactCd = 0.5; ctx.player:takeDamage(e.damage, ctx) end
        end
        -- LIFESTEAL: it's the only thing hurting you in the fractalspace, so it
        -- drinks a share of every point of shell you lose and knits itself back.
        e.lastPlHp = e.lastPlHp or ctx.player.hp
        local lost = e.lastPlHp - ctx.player.hp
        if lost > 0 and e.hp < e.maxHp then
            e.hp = math.min(e.maxHp, e.hp + lost * 40)   -- VORACIOUS: a single hit heals it massively
            e.healFlash = 0.45
        end
        e.lastPlHp = ctx.player.hp
        e.healFlash = math.max(0, (e.healFlash or 0) - dt)
    end,
    render = function(e, ctx)
        local t = e.anim
        if not e.segPos then return end
        local segN = e.segN or CH_SEGS
        local flash = e.hurtFlash or 0
        if (e.healFlash or 0) > 0 then U.glow(e.x, e.y, e.radius * 2.6, { 0.4, 1.0, 0.5 }, 0.7 * math.min(1, e.healFlash / 0.45)) end
        -- connector flesh between segments (thick purple rope)
        love.graphics.setLineWidth(16)
        for i = 1, segN - 1 do
            local s, z = e.segPos[i], e.segPos[i + 1]
            love.graphics.setColor(0.2, 0.04, 0.34)
            love.graphics.line(s.x, s.y, z.x, z.y)
        end
        love.graphics.setLineWidth(1)
        -- segments TAIL -> HEAD so the head sits on top
        for i = segN, 1, -1 do
            local s = e.segPos[i]
            local size, fo = s.r, s.fo
            -- flesh ring
            love.graphics.setColor(0.20 * fo + 0.10 + flash * 0.5, 0.03 + flash * 0.3, 0.32 * fo + 0.12 + flash * 0.5)
            love.graphics.circle("fill", s.x, s.y, size)
            love.graphics.setColor(0.6 * fo + 0.12, 0.1, 0.6 * fo + 0.12)
            love.graphics.setLineWidth(2); love.graphics.circle("line", s.x, s.y, size)
            -- gaping lizard mouth
            local open = 0.45 + 0.55 * math.abs(math.sin(t * 1.5 + i * 0.5))
            local jaw = size * 0.55 * open
            love.graphics.setColor(0.04, 0.0, 0.07)
            love.graphics.polygon("fill", s.x - size * 0.5, s.y, s.x + size * 0.5, s.y - jaw, s.x + size * 0.5, s.y + jaw)
            -- teeth
            love.graphics.setColor(0.95, 0.9, 0.8)
            for k = 0, 3 do
                local tx = s.x - size * 0.5 + (k + 1) * (size / 5)
                love.graphics.polygon("fill", tx, s.y - jaw * 0.9, tx - 1.6, s.y - jaw * 0.3, tx + 1.6, s.y - jaw * 0.3)
                love.graphics.polygon("fill", tx, s.y + jaw * 0.9, tx - 1.6, s.y + jaw * 0.3, tx + 1.6, s.y + jaw * 0.3)
            end
            -- slit eye
            love.graphics.setColor(1, 0.75, 0.15)
            love.graphics.circle("fill", s.x - size * 0.3, s.y - size * 0.55, size * 0.15)
            love.graphics.setColor(0, 0, 0)
            love.graphics.ellipse("fill", s.x - size * 0.3, s.y - size * 0.55, size * 0.05, size * 0.14)
        end
        -- vanishing-point fractal: shrinking dot spiral inward
        for i = 1, 14 do
            local f = 1 - i / 14
            local tw = t * 0.8 + i * 0.3
            love.graphics.setColor(0.25 * f, 0.03, 0.42 * f, f * 0.85)
            love.graphics.circle("fill", e.vx + math.cos(tw) * (3 + i * 1.4) * f, e.vy + math.sin(tw) * (3 + i * 1.4) * f, 3 * f + 0.5)
        end

        -- HEAD: thrashing spikes, opaque body, forward maw, twin slit eyes
        local hx, hy, hR = e.x, e.y, e.radius
        local pang = U.angleTo(hx, hy, ctx.player.x, ctx.player.y)
        for i = 1, 18 do
            local a = i / 18 * math.pi * 2 + t * 0.4
            local flex = 0.55 + 0.45 * math.sin(t * 9 + i * 1.7)
            local sLen = hR * (0.6 + flex + math.sin(t * 13 + i * 3.3) * 0.3)
            local bx, by = hx + math.cos(a) * hR * 0.95, hy + math.sin(a) * hR * 0.95
            local perpX, perpY = -math.sin(a) * hR * 0.16, math.cos(a) * hR * 0.16
            love.graphics.setColor(0.16, 0.02, 0.32)
            love.graphics.polygon("fill", bx + perpX, by + perpY, bx - perpX, by - perpY,
                hx + math.cos(a) * (hR + sLen), hy + math.sin(a) * (hR + sLen))
        end
        U.glow(hx, hy, hR * 1.8, e.glow, 0.5)
        love.graphics.setColor(0.22 + flash * 0.6, 0.04, 0.4 + flash * 0.4)
        love.graphics.circle("fill", hx, hy, hR)
        love.graphics.setColor(0.5, 0.14, 0.74); love.graphics.setLineWidth(3); love.graphics.circle("line", hx, hy, hR)
        love.graphics.setLineWidth(1)
        -- forward maw (aims at you)
        local openBig = 0.6 + 0.4 * math.abs(math.sin(t * 1.3))
        love.graphics.push(); love.graphics.translate(hx, hy); love.graphics.rotate(pang)
        love.graphics.setColor(0, 0, 0.02)
        local mawR = hR * 0.95
        love.graphics.polygon("fill", -mawR, 0, mawR * 0.4, -mawR * 0.65 * openBig, mawR * 0.4, mawR * 0.65 * openBig)
        love.graphics.pop()
        -- twin side eyes (vertical slit pupils in world space)
        local eyeR = hR * 0.16
        for sgn = -1, 1, 2 do
            local lx, ly = -hR * 0.22, sgn * hR * 0.5
            local ex = hx + math.cos(pang) * lx - math.sin(pang) * ly
            local ey = hy + math.sin(pang) * lx + math.cos(pang) * ly
            love.graphics.setColor(1, 0.8, 0.15); love.graphics.circle("fill", ex, ey, eyeR)
            love.graphics.setColor(0, 0, 0); love.graphics.ellipse("fill", ex, ey, eyeR * 0.3, eyeR * 0.9)
        end
    end,
}

-- Brood Sac: a swollen, slow fleshy host. When killed it bursts into a swarm
-- of parasites — so killing it carelessly in a crowd is dangerous.
E.types.brood = {
    name = "Brood Sac", hp = 150, speed = 40, radius = 21, damage = 16, score = 22, things = 5,
    spawnWeight = 0.7, splitInto = { id = "parasite", n = 3 },
    color = { 0.32, 0.07, 0.12 }, glow = { 1.0, 0.3, 0.42 },
    ai = function(e, dt, ctx)
        e.pulse = (e.pulse or 0) + dt
        moveToward(e, ctx.player.x, ctx.player.y, e.speed, dt)
        clampArena(e, ctx)
    end,
    render = function(e, ctx)
        local t = e.anim
        local sw = 1 + 0.12 * math.sin(t * 4)
        U.glow(e.x, e.y, e.radius * 1.5, e.glow, 0.3)
        U.setColor(e.color); blob(e.x, e.y, e.radius * sw, 14, t, 0.8)
        -- parasites squirming inside
        love.graphics.setColor(0, 0, 0, 0.6)
        for i = 1, 3 do
            local a = t * 1.5 + i * 2.1
            love.graphics.circle("fill", e.x + math.cos(a) * e.radius * 0.4, e.y + math.sin(a) * e.radius * 0.4, e.radius * 0.22)
        end
        love.graphics.setColor(1, 1, 1, 0.4)
        love.graphics.circle("fill", e.x - e.radius * 0.3, e.y - e.radius * 0.3, e.radius * 0.2)
    end,
}

-- Phantom: a flickering wraith that blinks toward you and leaves a damaging
-- rift of ink where it was. You can't out-run it — you have to read the blink.
E.types.phantom = {
    name = "Phantom", hp = 95, speed = 100, radius = 16, damage = 20, score = 22, things = 6,
    color = { 0.10, 0.10, 0.20 }, glow = { 0.6, 0.9, 1.0 },
    ai = function(e, dt, ctx)
        moveToward(e, ctx.player.x, ctx.player.y, e.speed, dt)
        e.tp = (e.tp or U.rand(2.2, 3.2)) - dt
        e.fade = math.max(0, (e.fade or 0) - dt)
        if e.tp <= 0 then
            e.tp = U.rand(2.4, 3.4)
            ctx.spawnInkCloud(e.x, e.y, e.damage * 0.5)        -- leave a rift
            local a = U.angleTo(ctx.player.x, ctx.player.y, e.x, e.y) + U.rand(-0.6, 0.6)
            e.x = ctx.player.x + math.cos(a) * U.rand(110, 170)
            e.y = ctx.player.y + math.sin(a) * U.rand(110, 170)
            e.fade = 0.5
            ctx.particles:burst(e.x, e.y, 10, e.glow, { speed = 120 })
        end
        clampArena(e, ctx)
    end,
    render = function(e, ctx)
        local t = e.anim
        local a = (e.fade and e.fade > 0) and 0.35 or (0.7 + 0.2 * math.sin(t * 5))
        U.glow(e.x, e.y, e.radius * 1.8, e.glow, 0.4 * a)
        love.graphics.setColor(e.color[1], e.color[2], e.color[3], a)
        for i = 1, 4 do
            love.graphics.circle("fill", e.x + math.sin(t * 3 + i) * e.radius * 0.3, e.y - i * e.radius * 0.28 + e.radius, e.radius * (1 - i * 0.14))
        end
        love.graphics.setColor(e.glow[1], e.glow[2], e.glow[3], a)
        love.graphics.circle("fill", e.x - 4, e.y - 2, 2.6)
        love.graphics.circle("fill", e.x + 4, e.y - 2, 2.6)
    end,
}

-- Churgspawn: a slow, huge, tanky mass of the void bled in from fractalspace.
-- Origin unknown. A black-purple blob with one realistic human eye that reaches
-- for you with long procedurally-bending arms (contact damage), and leaves a
-- purple toxic trail as it creeps.
E.types.churgspawn = {
    name = "Churgspawn", hp = 260, speed = 26, radius = 36, damage = 16, score = 38, things = 11,
    spawnWeight = 0.7,
    color = { 0.14, 0.05, 0.20 }, glow = { 0.7, 0.25, 0.95 },
    ai = function(e, dt, ctx)
        local pl = ctx.player
        moveToward(e, pl.x, pl.y, e.speed, dt)
        clampArena(e, ctx)
        e.armA = U.angleTo(e.x, e.y, pl.x, pl.y)
        e.armHitCd = math.max(0, (e.armHitCd or 0) - dt)

        -- procedurally-generated reaching arms that bend far toward the player
        e.arms = e.arms or {}
        local nArms = spec(e, "arms", 4)
        if #e.arms ~= nArms then
            e.arms = {}
            for i = 1, nArms do e.arms[i] = { ang = i / nArms * math.pi * 2, phase = U.rand(0, 6), t = 0, path = {} } end
        end
        -- whichever arm points most at you LUNGES out to grab — it reaches twice
        -- as far and aims true.
        local reachIdx, best = 1, math.huge
        for i, arm in ipairs(e.arms) do
            local d = math.abs(U.angleDiff(arm.ang, e.armA))
            if d < best then best = d; reachIdx = i end
        end
        local steps = 9
        local armMax = e.radius * 4.4 * ((e.cfg and (e.cfg.armLen or 0) > 0) and e.cfg.armLen or 1)
        for idx, arm in ipairs(e.arms) do
            arm.t = arm.t + dt
            arm.reaching = (idx == reachIdx)
            if arm.reaching then
                arm.len = armMax * 2.0 * (0.85 + 0.15 * math.sin(arm.t * 1.6 + arm.phase))   -- stretch 2x
            else
                arm.len = armMax * (0.45 + 0.55 * (0.5 + 0.5 * math.sin(arm.t * 1.0 + arm.phase)))
            end
            local px = e.x + math.cos(arm.ang) * e.radius * 0.8
            local py = e.y + math.sin(arm.ang) * e.radius * 0.8
            arm.path[1] = arm.path[1] or {}; arm.path[1][1] = px; arm.path[1][2] = py
            local seg = arm.len / steps
            local toP = U.angleDiff(arm.ang, e.armA)
            local bend = arm.reaching and 1.0 or 0.95
            local wob = arm.reaching and 0.08 or 0.25
            for i = 1, steps do
                local f = i / steps
                -- bend ever more toward the player along the length
                local dir = arm.ang + toP * f * f * bend + math.sin(arm.t * 3 + f * 5 + arm.phase) * (1 - f) * wob
                px = px + math.cos(dir) * seg
                py = py + math.sin(dir) * seg
                arm.path[i + 1] = arm.path[i + 1] or {}
                arm.path[i + 1][1] = px; arm.path[i + 1][2] = py
            end
            -- the grab: if an arm reaches the player it hits, then goes on a long
            -- cooldown before it can grab again.
            for i = 3, steps + 1 do
                local p = arm.path[i]
                if U.dist(p[1], p[2], pl.x, pl.y) < pl.radius + 11 then
                    if e.armHitCd <= 0 then e.armHitCd = 3.0; pl:takeDamage(e.damage * 1.8, ctx) end
                    break
                end
            end
        end

        -- thick purple toxic trail — big, overlapping pools that form a real,
        -- long-lasting obstacle behind it while it lives (and fade once it dies)
        e.trailT = (e.trailT or 0) - dt
        if e.trailT <= 0 then
            e.trailT = 0.35
            ctx.spawnHazard(e.x, e.y, e.radius * 1.15 * spec(e, "trailSize", 1), spec(e, "sludgeDmg", 9), spec(e, "sludgeLife", 22), { 0.72, 0.2, 0.95 }, e)
        end
    end,
    render = function(e, ctx)
        local t = e.anim
        local dark = U.shade(e.color, 0.7)
        U.glow(e.x, e.y, e.radius * 2.1, e.glow, 0.3)

        -- arms are built by the AI; in a no-AI context (the bestiary portrait)
        -- synthesize a splayed set so the entry isn't a bare blob.
        local arms = e.arms
        if not (arms and arms[1] and arms[1].path and #arms[1].path > 1) then
            arms = {}
            local steps = 9
            for k = 1, 4 do
                local base = (k / 4) * math.pi * 2
                local path, px, py = {}, e.x, e.y
                path[1] = { px, py }
                for i = 1, steps do
                    local ang = base + math.sin(t * 1.4 + i * 0.45 + k) * 0.3 * (1 - i / steps)
                    px = px + math.cos(ang) * e.radius * 0.42
                    py = py + math.sin(ang) * e.radius * 0.42
                    path[#path + 1] = { px, py }
                end
                arms[k] = { path = path }
            end
        end

        -- reaching arms, drawn behind the mass
        for _, arm in ipairs(arms) do
            local path = arm.path
            if path and #path > 1 then
                for i = 1, #path - 1 do
                    local f = (i - 1) / (#path - 1)
                    love.graphics.setColor(dark[1], dark[2], dark[3], 1)
                    love.graphics.setLineWidth((1 - f) * e.radius * 0.5 + 2)
                    love.graphics.line(path[i][1], path[i][2], path[i + 1][1], path[i + 1][2])
                end
                local tip = path[#path]
                U.glow(tip[1], tip[2], e.radius * 0.35, e.glow, 0.6)
                love.graphics.setColor(e.glow[1], e.glow[2], e.glow[3], 1)
                love.graphics.circle("fill", tip[1], tip[2], 4)
            end
        end

        -- the void blob mass
        love.graphics.setColor(e.color[1], e.color[2], e.color[3], 1)
        blob(e.x, e.y, e.radius, 16, t, 1.0)
        love.graphics.setColor(dark[1], dark[2], dark[3], 0.6)
        blob(e.x, e.y, e.radius * 0.62, 12, t * 1.3, 1.2)

        -- ONE realistic human eyeball, tracking the player
        local la = e.armA or 0
        local ex, ey, er = e.x, e.y, e.radius * 0.5
        love.graphics.setColor(0.95, 0.94, 0.9, 1)                 -- sclera
        love.graphics.circle("fill", ex, ey, er)
        love.graphics.setColor(0.82, 0.22, 0.2, 0.45)              -- bloodshot veins
        love.graphics.setLineWidth(1.4)
        for i = 1, 6 do
            local a = i / 6 * math.pi * 2 + t * 0.3
            love.graphics.line(ex + math.cos(a) * er * 0.32, ey + math.sin(a) * er * 0.32,
                ex + math.cos(a + 0.25) * er * 0.96, ey + math.sin(a + 0.25) * er * 0.96)
        end
        local ox, oy = math.cos(la) * er * 0.4, math.sin(la) * er * 0.4
        love.graphics.setColor(0.28, 0.5, 0.66, 1)                 -- iris
        love.graphics.circle("fill", ex + ox, ey + oy, er * 0.52)
        love.graphics.setColor(0.12, 0.26, 0.4, 1)
        love.graphics.setLineWidth(2); love.graphics.circle("line", ex + ox, ey + oy, er * 0.52)
        love.graphics.setColor(0, 0, 0, 1)                         -- pupil
        love.graphics.circle("fill", ex + ox, ey + oy, er * 0.25)
        love.graphics.setColor(1, 1, 1, 0.9)                       -- catchlight
        love.graphics.circle("fill", ex + ox - er * 0.13, ey + oy - er * 0.13, er * 0.09)
    end,
}

-- HUSK CRAWLER: a long pale roach-centipede from below the Maw. Its head is
-- ARMORED — shots barely dent it and just knock it aside. Hit the SEGMENTS on
-- its back instead: they take heavy damage and break off, shortening it, and
-- the moment its last segment is gone it dies with a screech. Its bite hits
-- hard AND injects a vicious poison, so you want Lifesteal to outlast it. It
-- turns slowly — circle behind it and shred its spine.
local CRAWL_SEG = 8
-- The armored head is drawn on its own so it can be rendered AFTER the Hadal
-- darkness overlay (see E.drawOverlay) — the chitin plate glints through the
-- pitch-black while the soft body behind it stays swallowed by the fog.
local function drawCrawlerHead(e, ctx)
    local t = e.anim
    local dark = U.shade(e.color, 0.56)
    local edge = U.shade(e.color, 0.72)
    local lite = U.shade(e.color, 1.2)
    -- PALE ROACH HEAD: a flat wedge of chitin with faceted sunken compound
    -- eyes, a darker clypeus, twitching palps and real curved pincer mandibles.
    local hx, hy, hr = e.x, e.y, e.radius * 1.7
    local f = e.facing or 0
    local fwx, fwy = math.cos(f), math.sin(f)
    local pxw, pyw = -fwy, fwx
    local snap = 0.1 + 0.16 * math.abs(math.sin(t * 6))
    -- no self-glow on the head — it should be eaten by the dark like the body;
    -- only the faint face-plate overlay (drawCrawlerArmor) shows through the fog
    -- a bright flash on the plate the instant it deflects a shot
    if (e.headFlash or 0) > 0 then U.glow(hx, hy, hr * 1.7, { 1, 1, 0.85 }, 0.6 * (e.headFlash / 0.12)) end
    -- tilt the head aside from the last deflected hit (headKnock springs back)
    love.graphics.push(); love.graphics.translate(hx, hy); love.graphics.rotate(f + (e.headKnock or 0))
    -- MANDIBLES first (head plate overlaps their base): curved serrated pincers
    local function mandible(sgn)
        love.graphics.setColor(0.12, 0.07, 0.06, 1)
        love.graphics.polygon("fill",
            hr * 0.5, sgn * hr * 0.36,
            hr * 0.8, sgn * hr * 0.1,
            hr * 1.5, sgn * (hr * 0.05 + snap * hr),
            hr * 1.14, sgn * (hr * 0.4 + snap * hr))
        love.graphics.setColor(0.86, 0.82, 0.68, 1)              -- pale serration teeth
        for k = 1, 3 do
            local u = 0.34 + k * 0.2
            local ix = hr * 0.8 + (hr * 1.5 - hr * 0.8) * u
            local iy = sgn * (hr * 0.1 + (hr * 0.05 + snap * hr - hr * 0.1) * u)
            love.graphics.polygon("fill", ix, iy, ix + hr * 0.09, iy, ix + hr * 0.045, iy + sgn * hr * 0.16)
        end
    end
    mandible(-1); mandible(1)
    -- dark outline wedge head
    love.graphics.setColor(dark[1], dark[2], dark[3], 1)
    love.graphics.polygon("fill",
        -hr * 0.92, -hr * 0.95, hr * 0.45, -hr * 0.72, hr * 0.98, -hr * 0.2,
        hr * 0.98, hr * 0.2, hr * 0.45, hr * 0.72, -hr * 0.92, hr * 0.95)
    -- pale chitin inset
    love.graphics.setColor(e.color[1], e.color[2], e.color[3], 1)
    love.graphics.polygon("fill",
        -hr * 0.78, -hr * 0.8, hr * 0.42, -hr * 0.58, hr * 0.82, -hr * 0.14,
        hr * 0.82, hr * 0.14, hr * 0.42, hr * 0.58, -hr * 0.78, hr * 0.8)
    -- darker clypeus / face plate up by the mouth
    love.graphics.setColor(edge[1], edge[2], edge[3], 1)
    love.graphics.polygon("fill", hr * 0.4, -hr * 0.4, hr * 0.88, -hr * 0.15, hr * 0.88, hr * 0.15, hr * 0.4, hr * 0.4)
    -- bright specular sheen on the armor (off-centre) — makes it read SHINY
    -- and easy to spot in the dark
    love.graphics.setColor(lite[1], lite[2], lite[3], 0.85)
    love.graphics.ellipse("fill", -hr * 0.34, -hr * 0.14, hr * 0.4, hr * 0.26)
    love.graphics.setColor(1, 1, 0.96, 0.7 + 0.25 * math.sin(t * 2))   -- hot glint
    love.graphics.ellipse("fill", -hr * 0.42, -hr * 0.22, hr * 0.14, hr * 0.1)
    -- sunken compound eyes — solid BLACK voids (no transparent shine), so they
    -- read as pits of dark and vanish completely when the fog swallows the head
    for sgn = -1, 1, 2 do
        love.graphics.push(); love.graphics.translate(-hr * 0.02, sgn * hr * 0.54); love.graphics.rotate(sgn * 0.5)
        love.graphics.setColor(0, 0, 0, 1); love.graphics.ellipse("fill", 0, 0, hr * 0.42, hr * 0.2)
        love.graphics.setColor(0.06, 0.04, 0.05, 1); love.graphics.setLineWidth(1)   -- barely-there facets
        for k = -2, 2 do love.graphics.line(k * hr * 0.13, -hr * 0.15, k * hr * 0.13, hr * 0.15) end
        love.graphics.pop()
    end
    -- maxillary palps twitching under the jaw
    love.graphics.setColor(edge[1], edge[2], edge[3], 1); love.graphics.setLineWidth(2.5)
    for sgn = -1, 1, 2 do
        love.graphics.line(hr * 0.8, sgn * hr * 0.2, hr * 1.0 + math.sin(t * 9 + sgn) * 3, sgn * hr * 0.4,
            hr * 1.12 + math.sin(t * 11 + sgn) * 3, sgn * hr * 0.34)
    end
    love.graphics.pop()
    -- long 3-joint antennae whipping from the front corners (world space)
    love.graphics.setColor(edge[1], edge[2], edge[3], 1); love.graphics.setLineWidth(2.5)
    for sgn = -1, 1, 2 do
        local bxA = hx + fwx * hr * 0.7 + pxw * sgn * hr * 0.55
        local byA = hy + fwy * hr * 0.7 + pyw * sgn * hr * 0.55
        local a1 = f + sgn * 0.45 + math.sin(t * 3 + sgn) * 0.22
        local p1x, p1y = bxA + math.cos(a1) * hr * 0.7, byA + math.sin(a1) * hr * 0.7
        local a2 = a1 + sgn * 0.3 + math.sin(t * 4 + sgn) * 0.28
        local p2x, p2y = p1x + math.cos(a2) * hr * 0.6, p1y + math.sin(a2) * hr * 0.6
        local a3 = a2 + sgn * 0.3 + math.sin(t * 5 + sgn) * 0.3
        love.graphics.line(bxA, byA, p1x, p1y, p2x, p2y, p2x + math.cos(a3) * hr * 0.5, p2y + math.sin(a3) * hr * 0.5)
    end
end

-- Drawn in the POST-dark pass: ONLY the chitin face-plate, and only faintly, so
-- it's barely visible through the fog ("a little less dark"). The eyes, teeth,
-- mandibles and antennae are NOT drawn here — they stay swallowed by the dark.
local function drawCrawlerArmor(e, ctx)
    local dark = U.shade(e.color, 0.56)
    local lite = U.shade(e.color, 1.2)
    local hr = e.radius * 1.7
    local f = (e.facing or 0) + (e.headKnock or 0)
    local A = 0.13       -- faint: only a touch of the plate shows through the black
    love.graphics.push(); love.graphics.translate(e.x, e.y); love.graphics.rotate(f)
    -- dark wedge outline of the plate
    love.graphics.setColor(dark[1], dark[2], dark[3], A)
    love.graphics.polygon("fill",
        -hr * 0.92, -hr * 0.95, hr * 0.45, -hr * 0.72, hr * 0.98, -hr * 0.2,
        hr * 0.98, hr * 0.2, hr * 0.45, hr * 0.72, -hr * 0.92, hr * 0.95)
    -- pale chitin face-plate
    love.graphics.setColor(e.color[1], e.color[2], e.color[3], A)
    love.graphics.polygon("fill",
        -hr * 0.78, -hr * 0.8, hr * 0.42, -hr * 0.58, hr * 0.82, -hr * 0.14,
        hr * 0.82, hr * 0.14, hr * 0.42, hr * 0.58, -hr * 0.78, hr * 0.8)
    -- a hint of the glossy sheen
    love.graphics.setColor(lite[1], lite[2], lite[3], A)
    love.graphics.ellipse("fill", -hr * 0.34, -hr * 0.14, hr * 0.4, hr * 0.26)
    -- a deflected shot still flashes the plate brightly so the CLANK reads in the dark
    if (e.headFlash or 0) > 0 then
        local fa = math.min(1, e.headFlash / 0.12)
        love.graphics.setColor(1, 1, 0.9, 0.55 * fa)
        love.graphics.ellipse("fill", -hr * 0.34, -hr * 0.14, hr * 0.42, hr * 0.28)
    end
    love.graphics.pop()
end

E.types.crawler = {
    name = "Husk Crawler", hp = 240, speed = 72, radius = 18, damage = 16, score = 42, things = 11,
    spawnWeight = 0.6, poisonDmg = 92,
    color = { 0.87, 0.83, 0.73 }, glow = { 0.96, 0.92, 0.78 },
    ai = function(e, dt, ctx)
        local pl = ctx.player
        local maxSeg = spec(e, "segs", CRAWL_SEG)
        e.nseg = math.max(0, math.ceil(maxSeg * e.hp / e.maxHp))
        -- a segment just snapped off: crunch + a burst of chitin where the tail was
        e.prevNseg = e.prevNseg or e.nseg
        if e.nseg < e.prevNseg then
            local s = (e.body and e.body[#e.body]) or { e.x, e.y }
            if ctx.particles then ctx.particles:burst(s[1], s[2], 10, e.color, { speed = 130 }) end
            if ctx.sound then ctx.sound("crack", 0.5) end
            if ctx.shake then ctx.shake(3) end
        end
        e.prevNseg = e.nseg
        -- the head tilt + deflect flash from a deflected shot fade back out
        e.headKnock = (e.headKnock or 0) * math.max(0, 1 - 6 * dt)
        e.headFlash = math.max(0, (e.headFlash or 0) - dt)
        -- slow turning so you can get around behind it (editor-tunable)
        local turn = spec(e, "turn", 1.1)
        local want = U.angleTo(e.x, e.y, pl.x, pl.y)
        e.facing = e.facing or want
        e.facing = e.facing + U.clamp(U.angleDiff(e.facing, want), -turn * dt, turn * dt)
        moveToward(e, e.x + math.cos(e.facing) * 100, e.y + math.sin(e.facing) * 100, e.speed, dt)
        clampArena(e, ctx)
        -- BODY as a follower chain: each segment trails the one ahead at a fixed
        -- spacing. Seeded behind the head so it's a full body from the moment it
        -- spawns (no waiting for a movement trail to build).
        local SPACE = e.radius * 0.95
        e.body = e.body or {}
        local leadx, leady = e.x, e.y
        for i = 1, e.nseg do
            local s = e.body[i]
            if not s then
                s = { e.x - math.cos(e.facing) * SPACE * i, e.y - math.sin(e.facing) * SPACE * i }
                e.body[i] = s
            end
            local dx, dy = leadx - s[1], leady - s[2]
            local d = math.sqrt(dx * dx + dy * dy)
            if d > SPACE then s[1] = s[1] + dx * (d - SPACE) / d; s[2] = s[2] + dy * (d - SPACE) / d end
            leadx, leady = s[1], s[2]
        end
        for i = #e.body, e.nseg + 1, -1 do e.body[i] = nil end   -- drop broken-off tail segments
        -- custom bullet collision: ARMORED head vs VULNERABLE spine
        if ctx.bullets and ctx.hurtEnemy then
            for _, b in ipairs(ctx.bullets.list) do
                if b.team == "player" and b.life > 0 then
                    if U.dist(b.x, b.y, e.x, e.y) < e.radius * 1.7 + b.radius then
                        ctx.hurtEnemy(e, b.damage * 0.12, b.x, b.y)    -- head: barely dents
                        local side = (math.cos(e.facing) * (b.y - e.y) - math.sin(e.facing) * (b.x - e.x)) > 0 and 1 or -1
                        e.headKnock = side * 0.34                       -- the head snaps aside — the CLANK tells you it's armored
                        e.headFlash = 0.12                             -- bright deflect spark on the plate
                        ctx.particles:spawn(b.x, b.y, { kind = "spark", size = 6, life = 0.2, color = { 1, 1, 0.8 } })
                        if ctx.sound then ctx.sound("clank", 0.4) end
                        b.life = 0
                    else
                        for i = 1, #e.body do
                            local s = e.body[i]
                            if s and U.dist(b.x, b.y, s[1], s[2]) < e.radius * 1.2 + b.radius then
                                ctx.hurtEnemy(e, b.damage * 1.6, b.x, b.y)   -- spine: heavy damage
                                ctx.particles:spawn(b.x, b.y, { kind = "spark", size = b.crit and 6 or 4, life = 0.25, color = b.color })
                                b.life = 0
                                break
                            end
                        end
                    end
                end
            end
        end
    end,
    render = function(e, ctx)
        local t = e.anim
        local nseg = e.nseg or CRAWL_SEG
        local body = e.body
        if not body or #body == 0 then
            -- bestiary fallback: a tightly-packed, gently curving centipede body
            body = {}
            local px, py, ang = e.x, e.y, math.pi * 0.96
            for i = 1, nseg do
                ang = ang + 0.18 * math.sin(i * 0.8)
                px = px + math.cos(ang) * e.radius * 0.7
                py = py + math.sin(ang) * e.radius * 0.7
                body[i] = { px, py }
            end
        end
        local dark = U.shade(e.color, 0.56)
        local mid = U.shade(e.color, 0.85)
        local edge = U.shade(e.color, 0.72)
        local lite = U.shade(e.color, 1.2)
        -- a gentle taper that never shrinks the tail away to nothing
        local function segW(i)
            local f = (nseg - i + 1) / nseg
            return e.radius * (0.62 + 0.72 * f)
        end
        -- LEGS (behind the plates): a jointed two-part pair per segment, scrabbling
        for i = nseg, 1, -1 do
            local s = body[i]
            if s then
                local prev = body[i - 1] or { e.x, e.y }
                local ang = math.atan2(prev[2] - s[2], prev[1] - s[1])
                local rr = segW(i)
                local beat = math.sin(t * 12 + i * 0.8)
                love.graphics.setColor(edge[1], edge[2], edge[3], 1)
                for sgn = -1, 1, 2 do
                    local hxp = s[1] + math.cos(ang + math.pi / 2 * sgn) * rr * 0.8
                    local hyp = s[2] + math.sin(ang + math.pi / 2 * sgn) * rr * 0.8
                    local ka = ang + math.pi / 2 * sgn + beat * 0.28 * sgn
                    local kx, ky = hxp + math.cos(ka) * rr * 0.95, hyp + math.sin(ka) * rr * 0.95
                    local ta = ka + 0.75 * sgn
                    local tx, ty = kx + math.cos(ta) * rr * 0.7, ky + math.sin(ta) * rr * 0.7
                    love.graphics.setLineWidth(math.max(2, rr * 0.2)); love.graphics.line(hxp, hyp, kx, ky)
                    love.graphics.setLineWidth(math.max(1.5, rr * 0.13)); love.graphics.line(kx, ky, tx, ty)
                end
            end
        end
        -- BODY: overlapping tergite plates — dark seam, darker flanks, a pale
        -- dorsal plate with a glossy ridge, and a spiracle dot on each flank.
        for i = nseg, 1, -1 do
            local s = body[i]
            if s then
                local prev = body[i - 1] or { e.x, e.y }
                local ang = math.atan2(prev[2] - s[2], prev[1] - s[1])
                local rr = segW(i)
                love.graphics.push(); love.graphics.translate(s[1], s[2]); love.graphics.rotate(ang)
                love.graphics.setColor(dark[1], dark[2], dark[3], 1)            -- seam shadow behind the plate
                love.graphics.ellipse("fill", -rr * 0.5, 0, rr * 0.9, rr * 1.24)
                love.graphics.setColor(edge[1], edge[2], edge[3], 1)            -- darker chitin flanks
                love.graphics.ellipse("fill", rr * 0.05, 0, rr * 0.86, rr * 1.12)
                love.graphics.setColor(e.color[1], e.color[2], e.color[3], 1)   -- pale dorsal tergite
                love.graphics.ellipse("fill", rr * 0.08, 0, rr * 0.82, rr * 0.78)
                love.graphics.setColor(lite[1], lite[2], lite[3], 0.85)         -- glossy dorsal ridge
                love.graphics.ellipse("fill", rr * 0.14, 0, rr * 0.46, rr * 0.26)
                love.graphics.setColor(dark[1], dark[2], dark[3], 0.85)         -- spiracles on the flanks
                local sp = math.max(1.2, rr * 0.11)
                love.graphics.circle("fill", rr * 0.12, -rr * 0.94, sp)
                love.graphics.circle("fill", rr * 0.12, rr * 0.94, sp)
                love.graphics.pop()
            end
        end
        -- The WHOLE head (eyes, teeth, mandibles, antennae) draws here in the
        -- normal pass, so the dark swallows it just like the body. Only the bare
        -- chitin face-plate is redrawn faintly after the dark (renderOverlay).
        drawCrawlerHead(e, ctx)
    end,
    -- post-fog pass: ONLY the face armor, and only faintly visible in the dark.
    renderOverlay = function(e, ctx) drawCrawlerArmor(e, ctx) end,
}

----------------------------------------------------------------------
-- spawning + scaling
----------------------------------------------------------------------
-- Which regular enemies are available by depth.
local POOLS = {
    [1] = { "drifter", "darter" },
    [2] = { "drifter", "darter", "snapper", "spitter" },
    [3] = { "drifter", "darter", "snapper", "spitter", "puffer", "lurker" },
    [4] = { "darter", "snapper", "spitter", "puffer", "lurker", "gulper" },
    [5] = { "snapper", "spitter", "puffer", "lurker", "gulper", "wisp" },
    [6] = { "spitter", "puffer", "lurker", "gulper", "wisp", "darter" },
    [7] = { "puffer", "lurker", "gulper", "wisp", "snapper", "spitter" },
    [8] = { "lurker", "gulper", "wisp", "puffer", "spitter", "snapper" },
    -- Hadal Depths (ONLY below the Maw): parasites, terrors, the unseen, mines,
    -- brood sacs, phantoms and worm singularities — the leviathan horrors.
    -- worm singularities stay OUT of the first two Hadal rounds (depths 9 & 10)
    [9]  = { "parasite", "parasite", "terror", "phantom", "brood", "churgspawn" },
    [10] = { "parasite", "terror", "unseen", "phantom", "brood", "churgspawn" },
    [11] = { "parasite", "terror", "unseen", "phantom", "wormsing", "wormsing", "brood", "churgspawn", "crawler" },
    [12] = { "parasite", "terror", "unseen", "phantom", "wormsing", "wormsing", "brood", "churgspawn", "crawler" },
    [13] = { "parasite", "terror", "unseen", "unseen", "phantom", "wormsing", "brood", "churgspawn", "crawler" },
}

function E.poolFor(depth)
    return POOLS[U.clamp(depth, 1, 13)] or POOLS[8]
end

-- Weighted pick: each type's `spawnWeight` (default 1) biases how often it
-- appears. The Snapper is heavy and tanky, so it spawns at half rate.
function E.pickForDepth(depth)
    local pool = E.poolFor(depth)
    local total = 0
    for _, id in ipairs(pool) do total = total + ((E.types[id] and E.types[id].spawnWeight) or 1) end
    local r = love.math.random() * total
    for _, id in ipairs(pool) do
        r = r - ((E.types[id] and E.types[id].spawnWeight) or 1)
        if r <= 0 then return id end
    end
    return pool[1]
end

-- Variant tiers. Any enemy can roll one; deeper depths roll them more often
-- (see game.spawnEnemy). Each is a recolored, beefier, faster, harder version —
-- so you face the same bestiary but in nastier forms as you descend.
E.VARIANTS = {
    elite   = { hp = 1.6, speed = 1.10, dmg = 1.20, radius = 1.10, reward = 1.8, tint = { 1.0, 0.82, 0.3 }, name = "Elite" },
    abyssal = { hp = 2.4, speed = 1.22, dmg = 1.45, radius = 1.20, reward = 2.8, tint = { 0.98, 0.36, 0.78 }, name = "Abyssal" },
}

-- Create an enemy instance. opts.variant = "elite"/"abyssal", opts.mods =
-- aggregated modifier table, opts.depthScale = numeric HP/dmg scaling for depth.
function E.spawn(id, x, y, opts)
    opts = opts or {}
    local def = E.types[id] or E.types.drifter
    local ds = opts.depthScale or 1
    local mods = opts.mods or {}
    -- Damage scales much more gently with depth than HP does, and takes a flat
    -- cut, so the game stays survivable at depth (HP still ramps for longer
    -- fights). dmgScale uses half the depth bonus; 0.62 is the global softener.
    local dmgScale = (1 + (ds - 1) * 0.5) * 0.62
    local e = {
        type = def, typeId = id, x = x, y = y,
        radius = def.radius, damage = def.damage * dmgScale * (mods.enemyDmg or 1),
        speed = def.speed * (mods.enemySpeed or 1),
        baseScore = def.score, baseThings = def.things,
        color = { def.color[1], def.color[2], def.color[3] },
        glow = { def.glow[1], def.glow[2], def.glow[3] },
        anim = U.rand(0, 10), facing = 0, contactTimer = 0, hurtFlash = 0,
        boss = def.boss, finalBoss = def.finalBoss, finalFinal = def.finalFinal,
    }
    -- Base HP. The big scaling (vs the player's firepower) is applied by the
    -- game's spawnEnemy via playerPower(), so this stays a clean baseline.
    local hp = def.hp * ds * (mods.enemyHp or 1)
    -- Variant tiers: tougher, recolored versions that appear more often the
    -- deeper you go. This is the main "enemies get harder as you progress".
    local v = opts.variant and E.VARIANTS[opts.variant]
    if v then
        e.variant = opts.variant; e.variantDef = v
        hp = hp * v.hp
        e.speed = e.speed * v.speed
        e.damage = e.damage * v.dmg
        e.radius = e.radius * v.radius
        e.baseScore = e.baseScore * v.reward
        e.baseThings = e.baseThings * v.reward
        e.color = U.mixColor(e.color, v.tint, 0.4)
        e.glow = U.mixColor(e.glow, v.tint, 0.5)
        -- variant parasites are bloated and SLOW (not faster) so they're fairer
        if id == "parasite" then e.speed = def.speed * (mods.enemySpeed or 1) * 0.7 end
    end
    e.hp = hp; e.maxHp = hp
    return e
end

function E.update(e, dt, ctx)
    e.anim = e.anim + dt
    e.contactTimer = math.max(0, e.contactTimer - dt)
    e.hurtFlash = math.max(0, e.hurtFlash - dt * 4)
    e.type.ai(e, dt, ctx)
end

function E.draw(e, ctx)
    e.type.render(e, ctx)
    if e.variantDef then
        -- variant shimmer ring (gold for Elite, magenta for Abyssal)
        local tc = e.variantDef.tint
        U.setColor(tc, 0.45 + 0.3 * math.sin(e.anim * 4))
        love.graphics.setLineWidth(2)
        love.graphics.circle("line", e.x, e.y, e.radius * 1.4)
    end
    if e.hurtFlash > 0 then
        U.setColor(P.white, e.hurtFlash * 0.7)
        love.graphics.circle("fill", e.x, e.y, e.radius)
    end
    -- (boss health bars are drawn centrally + stacked by the game — see
    --  Game:drawBossBars — so multiple bosses don't overlap)
end

-- Drawn AFTER the Hadal darkness overlay so flagged parts (e.g. the Husk
-- Crawler's armored head) glint through the fog while the body stays dark.
function E.drawOverlay(e, ctx)
    if e.type.renderOverlay then e.type.renderOverlay(e, ctx) end
end

return E
