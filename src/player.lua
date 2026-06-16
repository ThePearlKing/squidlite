-- The in-game player squid. Jet-propelled momentum movement, ink as both ammo
-- and dash fuel, and a big bag of upgrade-driven stats. Renders via the shared
-- Squid renderer so it wears the equipped skin + accessories.
local U = require("src.util")
local P = require("src.palette")
local Squid = require("src.squid")
local Cosmetics = require("src.cosmetics")
local Audio = require("src.audio")

local Player = {}
Player.__index = Player

function Player.new(save, mods)
    local self = setmetatable({}, Player)
    self.skin = Cosmetics.getSkin(save.skin)
    self.accessories, self.trailColor = Cosmetics.equippedAccessories(save)

    -- base stats (upgrades multiply/add to these in-run)
    self.maxHp = 100 * (mods.playerHpMult or 1)
    self.hp = self.maxHp
    self.regen = 2.2 + (mods.playerRegen or 0)   -- passive shell regen

    -- Ink is no longer an ammo resource — shooting is free, limited only by fire
    -- rate, and dashing is gated purely by its cooldown. (These fields are kept
    -- at zero cost so upgrades/modifiers that reference them stay harmless.)
    self.maxInk = 100
    self.ink = self.maxInk
    self.inkRegen = 0
    self.shotCost = 0
    self.dashCost = 0

    self.fireRate = 6.5
    self.fireTimer = 0
    self.inkDamage = 20 * (mods.playerDmgMult or 1)
    self.inkSpeed = 620
    self.inkRange = 700
    self.projectiles = 1
    self.spread = 0.12
    self.pierce = 0
    self.homing = 0
    self.bounce = 0
    self.explosive = false
    self.splitOnKill = false

    self.accel = 2950 * (mods.playerSpeedMult or 1)
    self.maxSpeed = 395 * (mods.playerSpeedMult or 1)
    self.friction = 4.2

    self.dashCooldown = 0.9
    self.dashTimer = 0
    self.dashImpulse = 660
    self.dashInvuln = 0.4         -- you take no damage for the whole dash
    self.invuln = 0
    self.dashCloud = false

    self.magnet = 64
    self.critChance = 0.05
    self.critMult = 2.0
    self.lifesteal = 0
    self.thorns = 0
    self.poison = 0          -- pending poison damage (Husk Crawler bite)
    self.poisonRate = 24     -- poison damage per second (fast enough to out-tick lifesteal)
    self.parasiteLeech = 0   -- remaining parasite drain time (parasites stack TIME, not rate)
    self.parasiteRate = 0    -- parasite drain per second (one parasite's worth)
    self.berserk = false

    self.dmgTakenMult = mods.playerDmgTakenMult or 1

    self.radius = 16
    self.x, self.y = 0, 0
    self.vx, self.vy = 0, 0
    self.angle = -math.pi / 2
    self.anim = 0
    self.hurt = 0
    self.blink = 0
    self.blinkTimer = U.rand(2, 5)
    self.alive = true
    self.dashStretch = 0
    self.tookHit = false   -- for flawless tracking
    return self
end

function Player:applyUpgrade(up) up.apply(self) end

function Player:damageScale()
    if self.berserk then
        local missing = 1 - self.hp / self.maxHp
        return 1 + missing * 0.8
    end
    return 1
end

function Player:tryShoot(ctx)
    if self.fireTimer > 0 or self.ink < self.shotCost then return end
    self.fireTimer = 1 / self.fireRate
    self.ink = self.ink - self.shotCost
    local n = self.projectiles
    local baseSpread = n > 1 and self.spread * (n - 1) or 0
    local crit = U.chance(self.critChance)
    local dmg = self.inkDamage * self:damageScale() * (crit and self.critMult or 1)
    -- Multishot shares damage (sublinear) so it adds coverage, not an infinite
    -- single-target death-ray — bosses can't be melted in 2 seconds anymore.
    if n > 1 then dmg = dmg / (n ^ 0.6) end
    local col = self.trailColor
    if col == "rainbow" then col = { 0.4 + 0.6 * math.abs(math.sin(self.anim * 3)), 0.5, 1 - 0.5 * math.abs(math.sin(self.anim * 3)) }
    elseif col == "fractal" then local h = self.anim * 1.5; col = { 0.6 + 0.35 * math.sin(h), 0.12, 0.75 + 0.25 * math.sin(h + 1.5) }
    elseif col == "matrix" then col = { 0.25, 1.0, 0.35 } end
    for i = 1, n do
        local off = n > 1 and U.lerp(-baseSpread, baseSpread, (i - 1) / (n - 1)) or 0
        off = off + U.rand(-self.spread * 0.3, self.spread * 0.3)
        local a = self.angle + off
        ctx.bullets:spawn({
            x = self.x + math.cos(self.angle) * self.radius,
            y = self.y + math.sin(self.angle) * self.radius,
            vx = math.cos(a) * self.inkSpeed, vy = math.sin(a) * self.inkSpeed,
            team = "player", damage = dmg, radius = crit and 7 or 5, color = col,
            pierce = self.pierce, homing = self.homing, bounce = self.bounce,
            explosive = self.explosive, split = self.splitOnKill, crit = crit,
            life = self.inkRange / self.inkSpeed,
            digit = self.trailColor == "matrix" and love.math.random(0, 1) or nil,  -- hacker bullets are 0/1
        })
    end
    Audio.play("shoot", 0.5)
    -- recoil + muzzle puff
    self.vx = self.vx - math.cos(self.angle) * 30
    self.vy = self.vy - math.sin(self.angle) * 30
end

function Player:tryDash(ctx)
    if self.dashTimer > 0 or self.ink < self.dashCost then
        if self.dashTimer <= 0 then Audio.play("denied", 0.4) end
        return
    end
    self.dashTimer = self.dashCooldown
    self.ink = self.ink - self.dashCost
    -- dash in movement direction, else aim
    local dx, dy = self.dirx or 0, self.diry or 0
    if dx == 0 and dy == 0 then dx, dy = math.cos(self.angle), math.sin(self.angle) end
    local nx, ny = U.normalize(dx, dy)
    self.vx = self.vx + nx * self.dashImpulse
    self.vy = self.vy + ny * self.dashImpulse
    self.invuln = self.dashInvuln
    self.dashStretch = 1
    Audio.play("dash", 0.6)
    ctx.particles:burst(self.x, self.y, 14, self.skin.glow, { speed = 200, kind = "bubble", size = 4 })
    if self.dashCloud then
        ctx.spawnInkCloud(self.x, self.y, self.inkDamage * 0.6)
    end
end

function Player:takeDamage(amount, ctx)
    if ctx.god and ctx.god() then return end       -- debug immortality (F8)
    if self.invuln > 0 or not self.alive then return end
    amount = amount * self.dmgTakenMult
    self.hp = self.hp - amount
    self.hurt = 1
    self.invuln = 0.5
    self.tookHit = true
    self.depthClean = false
    Audio.play("hurt", 0.6)
    ctx.shake(7)
    ctx.particles:burst(self.x, self.y, 10, P.red, { speed = 150 })
    if self.hp <= 0 then
        self.hp = 0
        self.alive = false
        Audio.play("lose")
        ctx.particles:burst(self.x, self.y, 40, self.skin.glow, { speed = 260, life = 1.0 })
        ctx.shake(16)
    end
end

function Player:heal(a)
    self.hp = math.min(self.maxHp, self.hp + a)
end

function Player:update(dt, ctx)
    self.anim = self.anim + dt
    local input = ctx.input

    -- aim toward cursor
    self.angle = U.angleTo(self.x, self.y, input.ax, input.ay)

    -- jet movement (momentum)
    local mx, my = input.mx, input.my
    self.dirx, self.diry = mx, my
    if mx ~= 0 or my ~= 0 then
        local nx, ny = U.normalize(mx, my)
        self.vx = self.vx + nx * self.accel * dt
        self.vy = self.vy + ny * self.accel * dt
    end
    -- drag
    local d = math.exp(-self.friction * dt)
    self.vx = self.vx * d
    self.vy = self.vy * d
    -- clamp speed (but allow dash overspeed to bleed off naturally)
    local sp = math.sqrt(self.vx * self.vx + self.vy * self.vy)
    if sp > self.maxSpeed and self.dashTimer < self.dashCooldown - 0.15 then
        local f = self.maxSpeed / sp
        self.vx = self.vx * f; self.vy = self.vy * f
    end
    self.x = self.x + self.vx * dt
    self.y = self.y + self.vy * dt

    -- arena walls
    local a = ctx.arena
    if self.x < a.x + self.radius then self.x = a.x + self.radius; self.vx = math.abs(self.vx) * 0.3 end
    if self.x > a.x + a.w - self.radius then self.x = a.x + a.w - self.radius; self.vx = -math.abs(self.vx) * 0.3 end
    if self.y < a.y + self.radius then self.y = a.y + self.radius; self.vy = math.abs(self.vy) * 0.3 end
    if self.y > a.y + a.h - self.radius then self.y = a.y + a.h - self.radius; self.vy = -math.abs(self.vy) * 0.3 end

    -- trail while moving
    local tcol = self.trailColor
    if tcol == "fractal" then
        -- FRACTAL WAKE: discrete glowing void RUNES dropped behind you as you
        -- move (spinning glyphs, hue-cycling) — not a flat smear of dots.
        self.runeT = (self.runeT or 0) - dt
        if sp > 90 and self.runeT <= 0 then
            self.runeT = 0.16
            local h = self.anim * 1.6
            local core = { 0.72 + 0.28 * math.sin(h), 0.2, 0.85 + 0.15 * math.sin(h + 1.5) }
            ctx.particles:spawn(self.x - self.vx * 0.03, self.y - self.vy * 0.03, {
                vx = -self.vx * 0.05, vy = -self.vy * 0.05, life = 0.95, size = 8,
                color = core, kind = "rune", drag = 3, spin = U.rand(-1.6, 1.6),
                rot = U.rand(0, 6), seed = U.randi(0, 5),
            })
        end
    elseif tcol == "matrix" then
        -- HACKER WAKE: green binary digits (0/1) trail out behind you and fade
        -- in place (they don't drop/rain)
        self.digitT = (self.digitT or 0) - dt
        if sp > 80 and self.digitT <= 0 then
            self.digitT = 0.07
            ctx.particles:spawn(self.x - self.vx * 0.02 + U.rand(-7, 7), self.y - self.vy * 0.02 + U.rand(-7, 7), {
                vx = -self.vx * 0.06, vy = -self.vy * 0.06, life = 0.85, size = 13,
                color = { 0.6, 1.0, 0.18 }, kind = "digit", drag = 3, seed = U.randi(0, 99),  -- lime
            })
        end
    elseif sp > 120 and U.chance(sp / self.maxSpeed * 0.7) then
        local col = tcol
        -- the whole trail cycles through the rainbow IN UNISON (one color at a
        -- time that shifts over time) — not a random color per particle
        if col == "rainbow" then
            local h = self.anim * 1.2
            col = { 0.5 + 0.5 * math.sin(h), 0.5 + 0.5 * math.sin(h + 2.094), 0.5 + 0.5 * math.sin(h + 4.188) }
        end
        ctx.particles:spawn(self.x - self.vx * 0.02, self.y - self.vy * 0.02, {
            vx = -self.vx * 0.1, vy = -self.vy * 0.1, life = 0.5, size = 5,
            color = col, kind = "ink", drag = 4,
        })
    end

    -- timers + regen
    self.fireTimer = math.max(0, self.fireTimer - dt)
    self.dashTimer = math.max(0, self.dashTimer - dt)
    self.invuln = math.max(0, self.invuln - dt)
    self.hurt = math.max(0, self.hurt - dt * 3)
    self.dashStretch = math.max(0, self.dashStretch - dt * 4)
    self.ink = math.min(self.maxInk, self.ink + self.inkRegen * dt)
    if self.regen > 0 then self:heal(self.regen * dt) end

    -- poison DoT (Husk Crawler bite): drains over time, bypassing i-frames.
    -- Lifesteal is what lets you out-heal it.
    if (self.poison or 0) > 0 and not (ctx.god and ctx.god()) then
        local d = math.min(self.poison, self.poisonRate * dt)
        self.poison = self.poison - d
        self.hp = self.hp - d
        self.hurt = math.max(self.hurt, 0.25)
        self.tookHit = true
        self.depthClean = false
        if self.hp <= 0 then self.hp = 0; self.alive = false end
    end

    -- parasite drain: a single capped rate, fed by latches (more parasites = more
    -- TIME draining, not a bigger hit). Bypasses i-frames.
    if (self.parasiteLeech or 0) > 0 and not (ctx.god and ctx.god()) then
        self.parasiteLeech = math.max(0, self.parasiteLeech - dt)
        local d = (self.parasiteRate or 0) * dt
        self.hp = self.hp - d
        self.hurt = math.max(self.hurt, 0.35)
        self.tookHit = true
        self.depthClean = false
        if self.hp <= 0 then self.hp = 0; self.alive = false end
    end

    -- blink
    self.blinkTimer = self.blinkTimer - dt
    if self.blinkTimer <= 0 then self.blink = 0.16; self.blinkTimer = U.rand(2, 5) end
    self.blink = math.max(0, self.blink - dt)

    if input.shoot then self:tryShoot(ctx) end
    if input.dash then self:tryDash(ctx) end
end

function Player:draw()
    -- invuln flicker
    local alpha = 1
    if self.invuln > 0 and math.floor(self.anim * 30) % 2 == 0 then alpha = 0.5 end
    local breathe = 1 + 0.04 * math.sin(self.anim * 3)
    Squid.draw(self.x, self.y, {
        skin = self.skin,
        accessories = self.accessories,
        angle = self.angle,
        scale = 0.62,
        t = self.anim,
        blink = self.blink / 0.16,
        hurt = self.hurt,
        alpha = alpha,
        squashY = breathe + self.dashStretch * 0.5,
        squashX = breathe - self.dashStretch * 0.25,
    })
end

return Player
