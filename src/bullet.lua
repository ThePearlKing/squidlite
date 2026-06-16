-- Projectiles for both teams. Player "ink" supports pierce / homing / bounce /
-- explosive / split-on-kill (driven by upgrades). Enemy projectiles are simpler.
local U = require("src.util")
local Bullets = {}
Bullets.__index = Bullets

function Bullets.new()
    return setmetatable({ list = {} }, Bullets)
end

-- spec fields: x,y,vx,vy,team("player"/"enemy"),damage,radius,color,
-- pierce,homing,bounce,explosive,split,life,glow
function Bullets:spawn(spec)
    spec.life = spec.life or 2.5
    spec.radius = spec.radius or 5
    spec.pierce = spec.pierce or 0
    spec.bounce = spec.bounce or 0
    spec.hitSet = {}
    self.list[#self.list + 1] = spec
    return spec
end

function Bullets:update(dt, ctx)
    local list = self.list
    local arena = ctx.arena
    local i = 1
    while i <= #list do
        local b = list[i]
        b.life = b.life - dt
        local dead = b.life <= 0

        -- homing toward nearest enemy (player ink only)
        if not dead and b.team == "player" and b.homing and b.homing > 0 then
            local tx, ty = ctx.nearestEnemy(b.x, b.y)
            if tx then
                local desired = U.angleTo(b.x, b.y, tx, ty)
                local cur = math.atan2(b.vy, b.vx)
                local d = U.angleDiff(cur, desired)
                local na = cur + d * math.min(1, b.homing * 4 * dt)
                local spd = math.sqrt(b.vx * b.vx + b.vy * b.vy)
                b.vx, b.vy = math.cos(na) * spd, math.sin(na) * spd
            end
        end

        if not dead then
            b.x = b.x + b.vx * dt
            b.y = b.y + b.vy * dt

            -- wall bounce or cull
            if arena then
                local bounced = false
                if b.x < arena.x then b.x = arena.x; b.vx = math.abs(b.vx); bounced = true end
                if b.x > arena.x + arena.w then b.x = arena.x + arena.w; b.vx = -math.abs(b.vx); bounced = true end
                if b.y < arena.y then b.y = arena.y; b.vy = math.abs(b.vy); bounced = true end
                if b.y > arena.y + arena.h then b.y = arena.y + arena.h; b.vy = -math.abs(b.vy); bounced = true end
                if bounced then
                    if b.bounce > 0 then b.bounce = b.bounce - 1
                    else dead = true end
                end
            end
        end

        if dead then
            if b.explosive and b.team == "player" and not b.noExplodeOnDeath then
                ctx.explode(b.x, b.y, b.damage * 0.8, b.color)
            end
            list[i] = list[#list]; list[#list] = nil
        else
            i = i + 1
        end
    end
end

local MX_GREEN, MX_GRAY = { 0.2, 1.0, 0.3 }, { 0.55, 0.6, 0.6 }
-- a binary-digit bullet: a round bullet that's a 0 or a 1. 1 = green circle w/
-- gray digit, 0 = gray circle w/ green digit.
local function drawDigit(x, y, s, one)
    local bg = one and MX_GREEN or MX_GRAY
    local fg = one and MX_GRAY or MX_GREEN
    love.graphics.setColor(MX_GREEN[1], MX_GREEN[2], MX_GREEN[3], 0.28)
    love.graphics.circle("fill", x, y, s * 1.05)              -- green glow halo
    love.graphics.setColor(bg[1], bg[2], bg[3], 1)
    love.graphics.circle("fill", x, y, s * 0.72)              -- the round bullet
    love.graphics.setColor(fg[1], fg[2], fg[3], 1)
    love.graphics.setLineWidth(math.max(1.5, s * 0.16))
    if one then
        love.graphics.line(x, y - s * 0.4, x, y + s * 0.4)
        love.graphics.line(x, y - s * 0.4, x - s * 0.18, y - s * 0.22)
    else
        love.graphics.ellipse("line", x, y, s * 0.24, s * 0.38)
    end
end
Bullets.drawDigit = drawDigit

function Bullets:draw()
    for _, b in ipairs(self.list) do
        if b.digit then
            drawDigit(b.x, b.y, b.radius * 2.0, b.digit == 1)
        else
            local c = b.color
            love.graphics.setColor(c[1], c[2], c[3], 0.25)
            love.graphics.circle("fill", b.x, b.y, b.radius * 2.1)   -- glow
            love.graphics.setColor(c[1], c[2], c[3], 1)
            love.graphics.circle("fill", b.x, b.y, b.radius)
            if b.team == "player" then
                love.graphics.setColor(1, 1, 1, 0.7)
                love.graphics.circle("fill", b.x - b.vx * 0.004, b.y - b.vy * 0.004, b.radius * 0.45)
            end
        end
    end
end

function Bullets:clearTeam(team)
    local kept = {}
    for _, b in ipairs(self.list) do
        if b.team ~= team then kept[#kept + 1] = b end
    end
    self.list = kept
end

return Bullets
