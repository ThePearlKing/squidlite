-- A single run: the descent through 8 depths of the trench. Owns the player,
-- enemies, projectiles, particles, waves, scoring, and the modifier-scaled
-- $Things payout. main.lua drives it via update/draw/keypressed/mousepressed
-- (mouse already converted to logical 1280x720 coordinates).
local U = require("src.util")
local P = require("src.palette")
local Player = require("src.player")
local Enemies = require("src.enemies")
local Bullets = require("src.bullet")
local Particles = require("src.particles")
local Upgrades = require("src.upgrades")
local Modifiers = require("src.modifiers")
local Audio = require("src.audio")
local Cosmetics = require("src.cosmetics")
local Squid = require("src.squid")

local Game = {}
Game.__index = Game

local LW, LH = 1280, 720
local MAX_DEPTH = 13
local HADAL_FROM = 9          -- depths 9+ are the pitch-black horror act
local DEPTH_NAMES = {
    "The Shallows", "The Kelp Reach", "Twilight Zone", "The Midnight Drop",
    "The Abyssal Plain", "The Crushing Deep", "The Whispering Dark", "The Maw's Lair",
    -- Hadal Depths (below the Maw) — five levels of escalating horror
    "The Black Gate", "The Unseen Deep", "The Drowning", "The Devouring Dark", "The Hollow Throne",
}
-- The Maw (8) is the gatekeeper; the Eldritch Squid (13) is the true final boss.
local BOSS_DEPTHS = { [4] = "warden", [6] = "warden", [8] = "maw", [13] = "eldritch" }

-- Global difficulty, chosen before a run. Scales enemy HP/damage and payout.
local DIFFS = {
    googoobaby = { id = "googoobaby", name = "GOO-GOO BABY", enemyHp = 0.35, enemyDmg = 0.2, payMult = 0.35, color = { 1.0, 0.7, 0.85 } },
    easy   = { id = "easy",   name = "EASY",   enemyHp = 0.8,  enemyDmg = 0.65, payMult = 0.8,  color = { 0.5, 1.0, 0.5 } },
    normal = { id = "normal", name = "NORMAL", enemyHp = 1.0,  enemyDmg = 1.0,  payMult = 1.0,  color = { 0.85, 0.9, 1.0 } },
    hard   = { id = "hard",   name = "HARD",   enemyHp = 1.6,  enemyDmg = 1.35, payMult = 1.7,  color = { 1.0, 0.55, 0.3 } },
    -- secret mode (unlocked separately). Hellish: parasites from the start, no
    -- passive regen, and fire-breathing RED leviathans in any round.
    terror = { id = "terror", name = "TERROR", enemyHp = 2.0,  enemyDmg = 1.6,  payMult = 2.5,  color = { 1.0, 0.12, 0.12 }, terror = true },
}

function Game.new(save, opts)
    local self = setmetatable({}, Game)
    self.save = save
    self.modIds = opts.modIds or {}
    self.mods = Modifiers.aggregate(self.modIds)
    self.diff = DIFFS[opts.difficulty or "normal"] or DIFFS.normal
    self.terror = self.diff.terror == true
    -- Custom campaign: a player-built sequence of depths overrides the default
    -- progression. A campaign's global multiplier acts like a difficulty.
    self.campaign = opts.campaign
    if self.campaign then
        local Campaign = require("src.campaign")
        self.cDepths, self.cTitle = Campaign.compile(self.campaign)
        self.cNodes = self.campaign.nodes        -- titles + depths, in order (node-based progression)
        if #self.cDepths == 0 then self.cDepths = { Campaign.newDepth("Depth 1") } end
        local m = self.campaign.mult or {}
        self.diff = { id = "custom", name = self.campaign.name or "CUSTOM",
            enemyHp = m.enemyHp or 1, enemyDmg = m.enemyDmg or 1, payMult = m.payMult or 1 }
        self.cSpeedMult = m.enemySpeed or 1
        self.cSizeMult = m.enemySize or 1
        self.terror = false
    end
    self.onEnd = opts.onEnd
    self.arena = { x = 30, y = 64, w = LW - 60, h = LH - 94 }

    self.player = Player.new(save, self.mods)
    self.player.x = self.arena.x + self.arena.w / 2
    self.player.y = self.arena.y + self.arena.h / 2
    -- TERROR: no passive regen until you earn health cards (Regenerator / Field Medic)
    if self.terror then self.player.regen = (self.mods.playerRegen or 0) end

    self.bullets = Bullets.new()
    self.particles = Particles.new()
    self.enemies = {}
    self.inkClouds = {}
    self.pickups = {}
    self.floaters = {}
    self.snow = {}
    for _ = 1, 70 do
        self.snow[#self.snow + 1] = { x = U.rand(0, LW), y = U.rand(0, LH),
            s = U.rand(0.4, 1.6), v = U.rand(6, 22), r = U.rand(1, 2.4) }
    end

    self.depth = 1
    self.wave = 0
    self.waveCount = 3
    self.toSpawn = 0
    self.spawnTimer = 0
    self.bossPending = false
    self.bossAlive = false

    -- Hadal act (depths 9+): pitch black, background horrors, trapped squids.
    self.hadal = false
    self.hadalDark = 0
    self.bgMonsters = {}
    self.trappedSquids = {}
    self.noiseTimer = U.rand(2, 4)
    self.revealDone = false

    -- roaming leviathans + the toxic pools they spit (deep depths)
    self.leviathans = {}
    self.cornerArms = {}
    self.hazards = {}
    self.leviTimer = U.rand(8, 14)
    self.leviCap = U.randi(4, 7)        -- visits per run in the deep (frequent, not rare)
    self.leviDone = 0
    self.leviSurvived = 0               -- flybys that passed while you lived
    self.killsByType = {}               -- bestiary progress this run

    self.score = 0
    self.kills = 0
    self.collected = 0
    self.combo = 0
    self.comboTimer = 0
    self.bestCombo = 0
    self.time = 0
    self.takenUnique = {}
    self.takenUpgrades = {}
    -- custom campaign: apply the chosen STARTING CARDS up front (stackable cards
    -- can appear multiple times; uniques are marked taken so they aren't re-offered)
    if self.campaign and self.campaign.startCards then
        for _, id in ipairs(self.campaign.startCards) do
            local up = Upgrades.byId[id]
            if up then
                self.player:applyUpgrade(up)
                self.takenUpgrades[#self.takenUpgrades + 1] = up.id
                if up.unique then self.takenUnique[up.id] = true end
            end
        end
    end

    self.shake = 0
    self.flash = 0
    self.phase = "intro"
    self.phaseTimer = 2.4
    self.banner = DEPTH_NAMES[1]
    self.bannerSub = "Depth 1"
    self.paused = false

    return self
end

----------------------------------------------------------------------
-- context shared with subsystems
----------------------------------------------------------------------
function Game:ctx()
    if self._ctx then return self._ctx end
    local g = self
    self._ctx = {
        arena = g.arena,
        particles = g.particles,
        bullets = g.bullets,
        player = g.player,
        time = function() return g.time end,
        shake = function(m) g.shake = math.max(g.shake, m) end,
        sound = function(name, vol) Audio.play(name, vol) end,
        shoot = function(x, y, vx, vy, dmg, color, radius, life)
            g.bullets:spawn({ x = x, y = y, vx = vx, vy = vy, team = "enemy",
                damage = dmg, color = color, radius = radius or 5, life = life or 4 })
        end,
        spawnAdd = function(id, x, y, o)
            g:spawnEnemy(id, x, y, o)
        end,
        spawnInkCloud = function(x, y, dmg)
            g.inkClouds[#g.inkClouds + 1] = { x = x, y = y, r = 50, dmg = dmg, life = 3.0, max = 3.0 }
        end,
        -- a lingering toxic pool that hurts the PLAYER (leviathan spit, churg trail).
        -- `arming` (optional) makes it a harmless green-fire TELEGRAPH for that many
        -- seconds before the sludge actually appears.
        spawnHazard = function(x, y, r, dmg, life, color, owner, arming)
            g.hazards[#g.hazards + 1] = { x = x, y = y, r = r or 34, dmg = dmg or 12,
                life = life or 6, max = life or 6, t = U.rand(0, 6), color = color, owner = owner,
                arming = arming }
        end,
        -- direct health drain that bypasses i-frames (parasite leech). Respects
        -- god mode. The squid shakes parasites off by dashing (handled in AI).
        leech = function(amt)
            if g.god or not g.player.alive then return end
            g.player.hp = g.player.hp - amt
            g.player.hurt = math.min(1, g.player.hurt + 0.4)
            g.player.tookHit = true
            g.player.depthClean = false
            if g.player.hp <= 0 then g.player.hp = 0; g.player.alive = false end
        end,
        explode = function(x, y, dmg, color)
            g.particles:spawn(x, y, { kind = "ring", size = 30, life = 0.4, color = color or P.cyan })
            g.particles:burst(x, y, 14, color or P.cyan, { speed = 220 })
            for _, e in ipairs(g.enemies) do
                if U.dist(x, y, e.x, e.y) < 70 + e.radius then
                    g:damageEnemy(e, dmg, x, y)
                end
            end
            g.shake = math.max(g.shake, 5)
        end,
        god = function() return g.god end,
        -- deal damage to a specific enemy (used by the Husk Crawler's custom
        -- head-vs-spine hit handling).
        hurtEnemy = function(e, dmg, fx, fy) g:damageEnemy(e, dmg, fx, fy) end,
        -- inject poison into the player: a lingering DoT that bypasses i-frames.
        -- optional `rate` sets the drain speed (damage/sec) for this poison so a
        -- creature can tune total damage and duration independently.
        poison = function(amt, rate)
            g.player.poison = math.max(g.player.poison or 0, amt)
            if rate then g.player.poisonRate = rate end
        end,
        -- a parasite latched on: parasites STACK by adding drain TIME, not rate —
        -- the drain rate stays one parasite's worth no matter how many cling on.
        parasiteLatch = function(secs, rate)
            g.player.parasiteRate = rate
            g.player.parasiteLeech = math.min(9, (g.player.parasiteLeech or 0) + secs)
        end,
        -- Eldritch fight: leviathans surface at the sides to bombard you.
        summonBossLevis = function() g:summonBossLevis() end,
        -- TERROR: long churg-arms claw in from the screen corners.
        spawnCornerArms = function() g:spawnCornerArms() end,
        nearestEnemy = function(x, y)
            local best, bd
            for _, e in ipairs(g.enemies) do
                local d = U.dist2(x, y, e.x, e.y)
                if not bd or d < bd then bd = d; best = e end
            end
            if best then return best.x, best.y end
        end,
    }
    return self._ctx
end

----------------------------------------------------------------------
-- spawning / waves
----------------------------------------------------------------------
function Game:depthScale()
    return 1 + (self.depth - 1) * 0.14
end

-- How strong the player has become, relative to a fresh squid (~1.0). Driven by
-- their actual offensive stats (damage x fire rate, plus multishot/crit). Enemy
-- HP scales off this so the game stays hard as you stack cards, but is fair the
-- moment you start (no upgrades = factor ~1 = baseline HP).
function Game:playerPower()
    local p = self.player
    local dps = p.inkDamage * p.fireRate
    dps = dps * (1 + (p.projectiles - 1) * 0.45)             -- multishot (hits big targets)
    dps = dps * (1 + (p.critChance or 0) * ((p.critMult or 2) - 1))
    if (p.lifesteal or 0) > 0 then dps = dps * 1.08 end
    if (p.pierce or 0) > 0 then dps = dps * (1 + p.pierce * 0.06) end
    return U.clamp(dps / 130, 1, 20)                          -- 130 = base DPS
end

function Game:randomEdgePos()
    local a = self.arena
    local side = love.math.random(4)
    if side == 1 then return U.rand(a.x, a.x + a.w), a.y + 20
    elseif side == 2 then return U.rand(a.x, a.x + a.w), a.y + a.h - 20
    elseif side == 3 then return a.x + 20, U.rand(a.y, a.y + a.h)
    else return a.x + a.w - 20, U.rand(a.y, a.y + a.h) end
end

function Game:spawnEnemy(id, x, y, o)
    o = o or {}
    o.depthScale = o.depthScale or self:depthScale()
    o.mods = self.mods
    -- never spawn on top of the player: push the spawn out to a safe radius.
    local minD = 190
    local pd = U.dist(x, y, self.player.x, self.player.y)
    if pd < minD then
        local ang = pd < 1 and U.rand(0, math.pi * 2) or U.angleTo(self.player.x, self.player.y, x, y)
        x = self.player.x + math.cos(ang) * minD
        y = self.player.y + math.sin(ang) * minD
        local a = self.arena
        x = U.clamp(x, a.x + 24, a.x + a.w - 24)
        y = U.clamp(y, a.y + 24, a.y + a.h - 24)
    end
    -- Variant roll: deeper = more Elites, and eventually Abyssals. This is how
    -- the roster gets harder as you progress (tougher forms, not just numbers).
    if not o.variant and not o.noVariant and not (Enemies.types[id] and Enemies.types[id].boss) then
        local abyss = U.clamp((self.depth - 5) * 0.06, 0, 0.32)
        local elite = U.clamp((self.depth - 2) * 0.09, 0, 0.5)
        local r = love.math.random()
        if r < abyss then o.variant = "abyssal"
        elseif r < abyss + elite then o.variant = "elite" end
    end
    local e = Enemies.spawn(id, x, y, o)
    if id == "mine" then e.isHazard = true end   -- mines don't count as wave enemies
    if o.asBoss then e.boss = true end                          -- "drifter boss" joke: any enemy gets a bar
    if o.name and o.name ~= "" then e.customName = o.name end   -- custom boss-bar title
    -- Adaptive HP: scale with the player's firepower so it stays hard as you
    -- stack cards but is fair when fresh. Bosses scale a little gentler so they
    -- stay beatable. Then apply the chosen difficulty.
    local power = self:playerPower()
    local hpMult = e.boss and (1 + (power - 1) * 0.6) or (1 + (power - 1) * 0.85)
    -- The Eldritch Squid keeps a FIXED health across difficulties (it doesn't get
    -- easier on EASY or harder on HARD) — only TERROR still scales it.
    local diffHp = self.diff.enemyHp
    if id == "eldritch" and not self.terror then diffHp = 1 end
    e.hp = e.hp * hpMult * diffHp
    e.maxHp = e.maxHp * hpMult * diffHp
    e.damage = e.damage * self.diff.enemyDmg
    -- TERROR: parasites are at least 480 HP (keep higher if scaling exceeds it)
    if self.terror and id == "parasite" then
        e.hp = math.max(e.hp, 480); e.maxHp = math.max(e.maxHp, 480)
    end
    -- campaign global speed/size multipliers + per-enemy editor config (cfg)
    if self.cSpeedMult and e.speed then e.speed = e.speed * self.cSpeedMult end
    if self.cSizeMult and self.cSizeMult ~= 1 and e.radius then e.radius = e.radius * self.cSizeMult end
    if o.cfg then
        local c = o.cfg
        if c.hp and c.hp ~= 1 then e.hp = e.hp * c.hp; e.maxHp = e.maxHp * c.hp end
        if c.dmg and c.dmg ~= 1 then e.damage = e.damage * c.dmg end
        if c.speed and c.speed ~= 1 and e.speed then e.speed = e.speed * c.speed end
        if c.size and c.size ~= 1 and e.radius then e.radius = e.radius * c.size end
        e.cfg = c.special        -- enemy-specific knobs read by some AIs
        e.addCfg = c.addCfg      -- config applied to anything THIS enemy spawns
    end
    self.enemies[#self.enemies + 1] = e
    return e
end

-- Count enemies that block wave progress (everything except placed mine hazards).
function Game:combatantCount()
    local n = 0
    for _, e in ipairs(self.enemies) do if not e.isHazard then n = n + 1 end end
    return n
end

-- Mines are placed level hazards (1-2 per deep level), not wave enemies. They sit
-- in the dark; you eliminate or avoid them. They don't block clearing a wave.
function Game:placeMines()
    local a = self.arena
    for _ = 1, U.randi(1, 2) do
        local mx = U.rand(a.x + 80, a.x + a.w - 80)
        local my = U.rand(a.y + 80, a.y + a.h - 80)
        self:spawnEnemy("mine", mx, my)
    end
end

-- campaign helpers (fall back to the default progression when not in a campaign)
function Game:maxDepth() return self.campaign and #self.cDepths or MAX_DEPTH end
function Game:bossAt(d)
    -- `or nil` so a stored `boss = false` ("none") reads as no finale boss —
    -- otherwise `false ~= nil` makes bossPending true and spawns a fallback drifter.
    if self.campaign then local n = self.cDepths[d]; return (n and n.boss) or nil end
    return BOSS_DEPTHS[d]
end
function Game:depthName(d)
    if self.campaign then local n = self.cDepths[d]; return n and n.name or ("Depth " .. d) end
    return DEPTH_NAMES[d] or ("Depth " .. d)
end

function Game:startDepth()
    -- titles are handled by the node walker now; this just enters the depth.
    self:enterDepth()
end

-- 1-based count of DEPTH nodes up to and including node index i.
function Game:depthOrdAt(i)
    local d = 0
    for k = 1, math.min(i, #self.cNodes) do
        if self.cNodes[k].kind == "depth" then d = d + 1 end
    end
    return math.max(1, d)
end

function Game:hasMoreDepthsAfter(i)
    for k = i + 1, #self.cNodes do
        if self.cNodes[k].kind == "depth" then return true end
    end
    return false
end

-- Walk the campaign to node `i`. Title nodes show a story card (then auto-walk
-- to the next node); depth nodes are entered as gameplay. Walking PAST the last
-- node is the win — the goal is to reach the point where nothing is left.
function Game:advanceCampaign(i)
    self.nodeI = i
    if i > #self.cNodes then self:endRun(true); return end
    local node = self.cNodes[i]
    if node.kind == "title" then
        self.bullets:clearTeam("enemy")
        self.enemies = {}; self.leviathans = {}; self.hazards = {}; self.cornerArms = {}
        self.titleText = node.text or ""
        self.titleDur = math.max(0.5, node.dur or 5)
        -- backdrop = the next node's depth fog, or "blank" if the next is a title/end
        local nxt = self.cNodes[i + 1]
        self.titleBgFog = (nxt and nxt.kind == "depth") and (nxt.fog or 0) or nil
        self.phase = "ctitle"; self.phaseTimer = self.titleDur
    else
        self.depth = self:depthOrdAt(i)
        self:enterDepth()
    end
end

function Game:enterDepth()
    self.wave = 0
    self.bossPending = (self:bossAt(self.depth) ~= nil)
    self.bossAlive = false
    self.bossDefeated = false
    self.revealDone = false
    if self.player then self.player.depthClean = true end   -- track no-hit clears
    self.phase = "intro"
    self.phaseTimer = 2.4
    self.banner = self:depthName(self.depth)
    self.bannerSub = "Depth " .. self.depth

    if self.campaign then
        -- custom depth: fog (visibility), wave count, placed mines, corner arms
        local node = self.cDepths[self.depth]
        self.waveCount = math.max(1, #node.waves)   -- per-wave spawn sets
        self.hadalDark = node.fog or 0
        self.bannerSub = "Depth " .. self.depth .. " / " .. #self.cDepths
        self.leviathans = {}; self.hazards = {}; self.enemies = {}; self.cornerArms = {}
        if (node.fog or 0) > 0.35 then self:spawnBgMonsters() else self.bgMonsters = {} end
        for _ = 1, (node.mines or 0) do
            local a = self.arena
            self:spawnEnemy("mine", U.rand(a.x + 80, a.x + a.w - 80), U.rand(a.y + 80, a.y + a.h - 80))
        end
        if node.cornerArms then self:spawnCornerArms() end
        -- per-depth music selector: normal / hadal / a boss track. playMusic
        -- de-dupes, so unchanged depths don't restart the track.
        local mid = node.music or "normal"
        local track = (mid == "normal" and self.save.musicTheme)
            or (mid == "hadal" and (self.save.hadalTheme or "hollow"))
            or mid
        Audio.playMusic(track)
        Audio.play("upgrade", 0.4)
        return
    end

    -- Entering the Hadal Depths: pitch black, horror score, looming shapes.
    if self.depth >= HADAL_FROM and not self.hadal then
        self.hadal = true
        Audio.playMusic(self.save.hadalTheme or "hollow")
        self:spawnBgMonsters()
        -- one EXTRA leviathan visit on this first Hadal round (makes up for the
        -- Maw fight no longer being interrupted by a flyby)
        self.leviCap = self.leviCap + 1
        self.leviTimer = U.rand(5, 9)
    end
    if self.hadal then
        self.hadalDark = 0.78           -- moderate vision radius around the squid
        self.bannerSub = "HADAL DEPTH " .. self.depth
        self:spawnBgMonsters()          -- refresh + escalate the background dread
    end
    self.leviathans = {}
    self.hazards = {}
    self.enemies = {}
    if self.depth >= 8 then self:placeMines() end   -- hidden mine hazards in the deep
    Audio.play("upgrade", 0.4)
end

-- Far-background horrors: huge silhouettes drifting in the black. More of them
-- the deeper you go, so the dread peaks near the end.
function Game:spawnBgMonsters()
    self.bgMonsters = {}
    local n = 4 + (self.depth - HADAL_FROM) * 2     -- 4 at depth 9 up to ~12 at 13
    for _ = 1, n do
        self.bgMonsters[#self.bgMonsters + 1] = {
            x = U.rand(0, LW), y = U.rand(80, LH - 80),
            vx = U.rand(-8, 8), vy = U.rand(-4, 4),
            r = U.rand(80, 180), eyes = U.randi(2, 6), t = U.rand(0, 10),
        }
    end
end

-- A leviathan flyby: a huge creature crosses the arena along the top or bottom,
-- from the left or right, spitting toxic pools, then leaves. Get to the other
-- lane. Visits a few times in the deep.
-- `forced` (optional) pins the variant ("pale"/"blue"/"red") for campaign events;
-- `lv` (optional) carries per-event overrides (sludge dmg/lifetime, arm length).
function Game:spawnLeviathan(forced, lv)
    local a = self.arena
    local fromLeft = U.chance(0.5)
    local top = U.chance(0.5)
    local L = {
        dir = fromLeft and 1 or -1, top = top,
        x = fromLeft and (a.x - a.h * 0.7) or (a.x + a.w + a.h * 0.7),
        band = top and (a.y + a.h * 0.26) or (a.y + a.h * 0.74),
        amp = a.h * 0.04, freq = 0.004, speed = 200,
        r = a.h * 0.22, len = 7, spacing = a.h * 0.20,    -- huge: fills its half
        spitT = 0.25, anim = U.rand(0, 6), contactCd = 0,
        color = { 0.82, 0.76, 0.90 },   -- pale purplish-white flesh
        glow = { 0.70, 0.55, 0.95 },
    }
    local variant = forced or (self.terror and "red")
        or (U.chance(({ hard = 0.30, normal = 0.15, easy = 0.10, googoobaby = 0.05 })[self.diff.id] or 0.15) and "blue")
    if variant == "red" then
        L.fire = true; L.fireT = 1.0
        L.color = { 0.55, 0.06, 0.08 }; L.glow = { 1.0, 0.25, 0.15 }
        L.fireGlow = { 0.45, 1.0, 0.25 }   -- green fire
    elseif variant == "blue" then
        L.blue = true; L.armCd = 0
        L.color = { 0.08, 0.12, 0.36 }; L.glow = { 0.32, 0.5, 1.0 }
    end
    L.y = L.band     -- seed y so it's drawable the same frame it spawns (update refines it)
    -- per-event editor overrides (0 = keep the built-in default)
    if lv then
        if (lv.sludgeDmg or 0) > 0 then L.sludgeDmg = lv.sludgeDmg end
        if (lv.sludgeLife or 0) > 0 then L.sludgeLife = lv.sludgeLife end
        if (lv.armLen or 0) > 0 then L.armMul = lv.armLen end
    end
    self.leviathans[#self.leviathans + 1] = L
    Audio.play("boss")
    self.shake = 14
end

-- Eldritch fight, halfway point: two leviathans surface at the LEFT and RIGHT
-- edges. They don't cross — they hang back, swivel their heads to look around,
-- and spit a lot of bullets from their gaping maws. RED & buffed in TERROR.
function Game:summonBossLevis()
    local a = self.arena
    for _, dir in ipairs({ 1, -1 }) do
        local r = a.h * 0.16
        local L = {
            parked = true, dir = dir, anim = U.rand(0, 6),
            x = dir > 0 and (a.x + r * 0.5) or (a.x + a.w - r * 0.5),
            y = a.y + a.h * 0.5, band = a.y + a.h * 0.5,
            r = r, len = 6, spacing = a.h * 0.16, freq = 0.004, amp = 0,
            speed = 0, contactCd = 0,
            lookA = 0, lookTarget = 0, lookTimer = U.rand(0.5, 1.5),
            mouth = 0, fireT = U.rand(0.3, 1.0),
            fireRate = self.terror and 0.55 or 0.85,
            dmg = self.terror and 20 or 15,
            color = { 0.82, 0.76, 0.90 }, glow = { 0.70, 0.55, 0.95 },
        }
        if self.terror then
            L.color = { 0.55, 0.06, 0.08 }; L.glow = { 1.0, 0.25, 0.15 }
            L.r = r * 1.18; L.dmg = 26                 -- buffed red ones
        end
        self.leviathans[#self.leviathans + 1] = L
    end
    Audio.play("boss")
    self.shake = 16
end

-- TERROR eldritch fight: super-long arms reach in from the four screen corners,
-- bending toward you to grab — same idea as the Churgspawn's limbs.
function Game:spawnCornerArms()
    local a = self.arena
    -- custom depths set their own corner-arm reach; the terror eldritch uses 0.24
    local node = self.campaign and self.cDepths[self.depth]
    self.cornerArmLen = (node and node.cornerArmLen) or 0.24
    self.cornerArms = self.cornerArms or {}
    local corners = {
        { a.x, a.y }, { a.x + a.w, a.y }, { a.x, a.y + a.h }, { a.x + a.w, a.y + a.h },
    }
    for i, c in ipairs(corners) do
        self.cornerArms[#self.cornerArms + 1] = {
            cx = c[1], cy = c[2], baseA = U.angleTo(c[1], c[2], a.x + a.w / 2, a.y + a.h / 2),
            t = U.rand(0, 4), phase = i * 1.7, hitCd = 0, path = {},
        }
    end
end

-- A parked side leviathan: swivel its head to look around, and spit volleys of
-- bullets from its maw on a fast cadence.
function Game:updateBossLevi(L, dt, ctx)
    L.anim = L.anim + dt
    L.contactCd = math.max(0, (L.contactCd or 0) - dt)
    L.lookTimer = L.lookTimer - dt
    if L.lookTimer <= 0 then
        L.lookTimer = U.rand(0.7, 1.7)
        L.lookTarget = U.rand(-0.7, 0.7)       -- pick a new random gaze
    end
    L.lookA = U.approach(L.lookA, L.lookTarget, 3, dt)
    L.mouth = math.max(0, L.mouth - dt * 3)
    self.shake = math.max(self.shake, L.fire and 2 or 1.2)
    -- contact: don't let the player tuck inside its head
    if L.contactCd <= 0 and U.dist(L.x, L.y, self.player.x, self.player.y) < L.r + self.player.radius then
        L.contactCd = 0.6; self.player:takeDamage(L.dmg, ctx)
    end
    -- spit a volley from the maw (which points inward, biased by its gaze)
    L.fireT = L.fireT - dt
    if L.fireT <= 0 then
        L.fireT = L.fireRate
        L.mouth = 1
        local baseA = (L.dir > 0 and 0 or math.pi) + L.lookA
        local mx = L.x + math.cos(baseA) * L.r * 0.7
        local my = L.y + math.sin(baseA) * L.r * 0.7
        local n = L.fire and 5 or 3
        for j = 1, n do
            local aa = baseA + (j - (n + 1) / 2) * 0.16 + U.rand(-0.05, 0.05)
            ctx.shoot(mx, my, math.cos(aa) * 300, math.sin(aa) * 300, L.dmg, L.glow, 7, 6)
        end
        self.particles:burst(mx, my, 5, L.glow, { speed = 80, color = L.glow })
        Audio.play("boss", 0.3)
    end
end

-- Long churg-arms clawing in from the corners, bending toward the player.
function Game:updateCornerArms(dt, ctx)
    local pl = self.player
    local a = self.arena
    local maxLen = math.sqrt(a.w * a.w + a.h * a.h) * (self.cornerArmLen or 0.24)   -- editor-tunable reach
    local steps = 12
    for _, arm in ipairs(self.cornerArms) do
        arm.t = arm.t + dt
        arm.hitCd = math.max(0, arm.hitCd - dt)
        local toP = U.angleTo(arm.cx, arm.cy, pl.x, pl.y)
        local reach = maxLen * (0.5 + 0.5 * (0.5 + 0.5 * math.sin(arm.t * 0.7 + arm.phase)))
        local seg = reach / steps
        local px, py = arm.cx, arm.cy
        arm.path[1] = arm.path[1] or {}; arm.path[1][1] = px; arm.path[1][2] = py
        local td = U.angleDiff(arm.baseA, toP)
        for i = 1, steps do
            local f = i / steps
            local dir = arm.baseA + td * f * f * 0.95 + math.sin(arm.t * 2.5 + f * 5 + arm.phase) * (1 - f) * 0.2
            px = px + math.cos(dir) * seg; py = py + math.sin(dir) * seg
            arm.path[i + 1] = arm.path[i + 1] or {}
            arm.path[i + 1][1] = px; arm.path[i + 1][2] = py
        end
        for i = 4, steps + 1 do
            local p = arm.path[i]
            if U.dist(p[1], p[2], pl.x, pl.y) < pl.radius + 12 then
                if arm.hitCd <= 0 then arm.hitCd = 0.6; pl:takeDamage(20, ctx) end
                break
            end
        end
    end
end

function Game:drawCornerArms()
    for _, arm in ipairs(self.cornerArms or {}) do
        local path = arm.path
        if path and #path > 1 then
            for i = 1, #path - 1 do
                local f = (i - 1) / (#path - 1)
                love.graphics.setColor(0.13, 0.03, 0.2, 1)
                love.graphics.setLineWidth((1 - f) * 22 + 3)
                love.graphics.line(path[i][1], path[i][2], path[i + 1][1], path[i + 1][2])
                love.graphics.setColor(0.5, 0.12, 0.72, 0.9)
                love.graphics.setLineWidth((1 - f) * 12 + 1)
                love.graphics.line(path[i][1], path[i][2], path[i + 1][1], path[i + 1][2])
            end
            local tip = path[#path]
            U.glow(tip[1], tip[2], 22, { 0.8, 0.25, 1.0 }, 0.7)
            love.graphics.setColor(0.9, 0.3, 1.0, 1); love.graphics.circle("fill", tip[1], tip[2], 6)
        end
    end
end

-- The vast ancient gate the Maw guards at the bottom of the Challenger Deep —
-- Site: Acheron. A stone archway around a churning void portal into the unknown.
function Game:drawMawGate()
    local a = self.arena
    local t = self.time
    local gx, gy = a.x + a.w * 0.5, a.y + a.h * 0.46
    local gw, gh = a.w * 0.34, a.h * 0.64
    local hw = gw * 0.5
    -- the void beyond the gate
    love.graphics.setColor(0.0, 0.0, 0.02, 0.92)
    love.graphics.ellipse("fill", gx, gy, hw * 0.86, gh * 0.46)
    -- swirling unknown inside the portal
    for i = 1, 11 do
        local f = i / 11
        local sa = t * 0.5 + i * 0.7
        love.graphics.setColor(0.32 * f, 0.05, 0.42 * f, 0.22 * (1 - f))
        love.graphics.setLineWidth(2)
        love.graphics.ellipse("line", gx + math.cos(sa) * hw * 0.12 * f, gy + math.sin(sa) * gh * 0.1 * f,
            hw * 0.8 * f, gh * 0.42 * f)
    end
    -- two massive stone pillars
    love.graphics.setColor(0.09, 0.09, 0.12, 1)
    love.graphics.rectangle("fill", gx - hw - gw * 0.12, gy - gh * 0.42, gw * 0.16, gh * 0.95)
    love.graphics.rectangle("fill", gx + hw - gw * 0.04, gy - gh * 0.42, gw * 0.16, gh * 0.95)
    -- the arch across the top
    love.graphics.setColor(0.09, 0.09, 0.12, 1)
    love.graphics.setLineWidth(gw * 0.16)
    love.graphics.arc("line", "open", gx, gy - gh * 0.42, hw + gw * 0.04, math.pi, math.pi * 2)
    love.graphics.setLineWidth(1)
    -- faint glowing glyphs carved down the pillars
    love.graphics.setColor(0.55, 0.2, 0.85, 0.35 + 0.2 * math.sin(t * 1.5))
    love.graphics.setLineWidth(2)
    for side = -1, 1, 2 do
        local px = gx + side * (hw + gw * 0.04)
        for j = 0, 4 do
            local py = gy - gh * 0.34 + j * gh * 0.16
            love.graphics.line(px - 5, py, px + 5, py)
            love.graphics.line(px, py - 6, px, py + 6)
            love.graphics.circle("line", px, py + 9, 3)
        end
    end
    -- the location stamped above the gate (restore the prior font afterwards so
    -- the big font doesn't leak into the HUD / later depths)
    local prevFont = love.graphics.getFont()
    love.graphics.setFont(self.fontBig or prevFont)
    love.graphics.setColor(0.7, 0.2, 0.25, 0.5 + 0.2 * math.sin(t * 2))
    love.graphics.printf("SITE: ACHERON", gx - 240, gy - gh * 0.52, 480, "center")
    love.graphics.setFont(prevFont)
end

function Game:startCutscene()
    self.phase = "cutscene"
    self.phaseTimer = 6.0
    self.bullets:clearTeam("enemy")
    Audio.playMusic(self.save.hadalTheme or "hollow")
    Audio.play("boss")
    self.shake = 20
end

function Game:startNextWave()
    -- breather heal between waves (not on the first wave) unless No Mercy
    if self.wave >= 1 and self.player and not self.mods.noHeal then
        self.player:heal(self.player.maxHp * 0.12)
    end
    self.wave = self.wave + 1
    if self.campaign then
        local node = self.cDepths[self.depth]
        -- DETERMINISTIC: this wave spawns EXACTLY the enemies placed in it — each
        -- entry contributes `count` copies carrying that entry's own config. No
        -- random pools, no auto-fill. What you placed is what you get.
        local waveDef = node.waves[self.wave] or { spawns = {} }
        local q = {}
        for _, sp in ipairs(waveDef.spawns or {}) do
            for _ = 1, math.max(1, sp.count or 1) do q[#q + 1] = { id = sp.id, cfg = sp.cfg, name = sp.name, asBoss = sp.asBoss } end
        end
        -- light shuffle so identical types don't all arrive back-to-back (order
        -- only — the exact set/counts are untouched)
        for i = #q, 2, -1 do local j = love.math.random(i); q[i], q[j] = q[j], q[i] end
        self.waveQueue = q
        self.toSpawn = #q
        self.maxAlive = math.max(8, #q)        -- let the whole wave be on-screen if small
        self.spawnTimer = 0
        -- announce any bosses placed in this wave: WARNING: MAW, WARDEN, …
        local bn = {}
        for _, sp in ipairs(waveDef.spawns or {}) do
            local def = Enemies.types[sp.id]
            if (def and def.boss) or sp.asBoss then
                bn[#bn + 1] = ((sp.name and sp.name ~= "") and sp.name or (def and def.name) or sp.id):upper()
            end
        end
        if #bn > 0 then
            self.bossWarnText = "WARNING: " .. table.concat(bn, ", ")
            self.bossWarnT = 2.8
            Audio.play("boss"); self.shake = math.max(self.shake, 10)
        end
        -- scripted leviathan flybys placed on THIS wave
        for _, lv in ipairs(waveDef.levis or {}) do self:spawnLeviathan(lv.variant, lv) end
        return
    end
    if self.hadal then
        -- Hadal: fewer-but-nastier. Hard cap on alive so the dark never fills
        -- with a wall of mines + swarms at once.
        -- escalating: the deepest Hadal levels throw more, faster.
        self.toSpawn = math.floor((9 + (self.depth - HADAL_FROM) * 2.5) * (self.mods.spawnMult or 1))
        self.maxAlive = 10 + (self.depth - HADAL_FROM)
    else
        local base = 4 + self.depth * 1.6    -- leaner waves so rounds don't drag
        self.toSpawn = math.floor(base * (self.mods.spawnMult or 1))
        self.maxAlive = 6 + self.depth * 1.5
    end
    self.spawnTimer = 0
    -- DEPTH 11: a guaranteed leviathan encounter — always on waves 2 and 3
    -- (random flybys are suppressed on depth 11's waves 2 & 3 so they don't double).
    if self.depth == 11 and (self.wave == 2 or self.wave == 3) then
        self:spawnLeviathan()
    end
end

function Game:spawnBoss()
    local id = self:bossAt(self.depth)
    local bx, by = self.arena.x + self.arena.w / 2, self.arena.y + 120
    -- enter every boss healthier — heal up to ~75% (never down), unless No Mercy
    if not self.mods.noHeal then
        self.player.hp = math.max(self.player.hp, self.player.maxHp * 0.75)
    end
    -- Bosses use their own base HP (no global depth scaling). The 2nd Warden
    -- (depth 6) is NOT buffed beyond the first — same fight.
    local o = { depthScale = 1 }
    -- custom campaigns: apply this depth's boss config (size/hp/dmg/speed + specials)
    if self.campaign then
        local node = self.cDepths[self.depth]
        if node then o.cfg = node.bossCfg end
    end
    local boss = self:spawnEnemy(id, bx, by, o)
    boss.isFinaleBoss = true     -- the post-last-wave boss; its death advances/ends the depth
    if self.campaign then
        local node = self.cDepths[self.depth]
        if node and node.bossName and node.bossName ~= "" then boss.customName = node.bossName end
    end
    if id == "warden" and self.depth >= 6 then        -- 2nd Warden: bigger, twice the HP, faster rings
        boss.tier2 = true
        boss.hp = boss.hp * 2; boss.maxHp = boss.maxHp * 2
        boss.radius = boss.radius * 1.35
    end
    if id == "eldritch" then
        boss.terror = self.terror                      -- so it knows to spawn the corner-arms
        -- breakneck breakcore for the final fight — a distorted-guitar terror mix in TERROR
        Audio.playMusic(self.terror and "terrorcore" or "breakcore")
    end
    -- clear placed mine hazards so they don't clutter the boss arena (the Maw fight)
    for i = #self.enemies, 1, -1 do
        if self.enemies[i].typeId == "mine" then table.remove(self.enemies, i) end
    end
    self.bossAlive = true
    self.bossPending = false
    self.banner = boss.customName or boss.type.name
    self.bannerSub = "!! WARNING !!"
    self.phase = "boss_intro"
    self.phaseTimer = 2.0
    Audio.play("boss")
    self.shake = 14
end

-- Depth 11 only: after the last wave, the monsters (and the background horrors)
-- all vanish, and you find the other squids — caged in the dark. Then the
-- Eldritch Squid appears.
function Game:startReveal()
    self.phase = "reveal"
    self.phaseTimer = 5.0
    self.revealDone = true
    self.bossPending = false
    self.enemies = {}
    self.bgMonsters = {}                 -- the background terrors are gone
    self.bullets:clearTeam("enemy")
    self.hadalDark = 0.32                -- lift the dark so you can see your kin
    -- reveal the trapped squids around the arena
    self.trappedSquids = {}
    local skins = { "ember", "mossback", "violet", "ashen", "coral", "frost", "toxic" }
    for i = 1, 7 do
        local a = self.arena
        self.trappedSquids[#self.trappedSquids + 1] = {
            x = U.rand(a.x + 80, a.x + a.w - 80), y = U.rand(a.y + 80, a.y + a.h - 80),
            skin = Cosmetics.getSkin(skins[i]), t = U.rand(0, 6), freed = false,
        }
    end
    Audio.playMusic(self.save.hadalTheme or "hollow")
end

----------------------------------------------------------------------
-- damage / death
----------------------------------------------------------------------
function Game:damageEnemy(e, dmg, fromx, fromy)
    if e.dead then return end
    if e.typeId == "mine" then return end   -- mines are indestructible hazards
    e.hp = e.hp - dmg
    e.hurtFlash = 1
    if self.player.lifesteal > 0 then
        -- lifesteal heals far less off bosses and flesh parasites, so the deep
        -- (and boss fights) actually counter a lifesteal build.
        local lsMult = e.boss and 0.33 or (e.typeId == "parasite" and 0.3 or 1)
        self.player:heal(dmg * self.player.lifesteal * lsMult)
    end
    if e.hp <= 0 then self:killEnemy(e, fromx, fromy) end
end

function Game:killEnemy(e, fx, fy)
    if e.dead then return end
    e.dead = true
    self.kills = self.kills + 1
    self.killsByType[e.typeId] = (self.killsByType[e.typeId] or 0) + 1   -- bestiary
    self.combo = self.combo + 1
    self.comboTimer = 2.6
    self.bestCombo = math.max(self.bestCombo, self.combo)
    local comboMult = 1 + self.combo * 0.03
    self.score = self.score + math.floor(e.baseScore * comboMult)
    Audio.play("enemyDie", 0.4)
    if e.typeId == "crawler" then Audio.play("screech", 0.55) end   -- the husk crawler's last screech
    self.particles:burst(e.x, e.y, e.boss and 60 or 14, e.glow or e.type.glow, { speed = e.boss and 320 or 200, life = e.boss and 1.0 or 0.6 })

    -- drop $Things motes
    local n = math.max(1, math.floor(e.baseThings))
    for _ = 1, n do
        self.pickups[#self.pickups + 1] = {
            x = e.x + U.rand(-10, 10), y = e.y + U.rand(-10, 10),
            vx = U.rand(-60, 60), vy = U.rand(-60, 60), val = 1, life = 12,
            t = U.rand(0, 6),
        }
    end

    -- enemies that burst into a swarm on death (Brood Sac). Editor can set how
    -- many it spawns (0 = none) via the splitN knob.
    if e.type.splitInto and not e.boss then
        local sp = e.type.splitInto
        local n = (e.cfg and e.cfg.splitN) or sp.n
        for _ = 1, n do
            self:spawnEnemy(sp.id, e.x + U.rand(-16, 16), e.y + U.rand(-16, 16), { noVariant = true, cfg = e.addCfg })
        end
    end

    -- spawn-on-kill shards
    if self.player.splitOnKill and not e.boss then
        for i = 1, 3 do
            local a = i / 3 * math.pi * 2
            self.bullets:spawn({ x = e.x, y = e.y, vx = math.cos(a) * 320, vy = math.sin(a) * 320,
                team = "player", damage = self.player.inkDamage * 0.5, radius = 4,
                color = self.player.skin.glow, homing = 0.5, life = 0.8, noExplodeOnDeath = true })
        end
    end

    if e.boss then
        self.bossAlive = false
        -- (boss kills are tallied via self._bossKilledThisRun and banked at run
        -- end — and skipped entirely for custom campaigns, which earn no stats)
        self.shake = 18
        self.flash = 0.6
        for _ = 1, 5 do
            self.particles:spawn(e.x + U.rand(-40, 40), e.y + U.rand(-40, 40),
                { kind = "ring", size = 40, life = 0.8, color = e.glow })
        end
        self._bossKilledThisRun = (self._bossKilledThisRun or 0) + 1
        if self.campaign then
            -- CUSTOM CAMPAIGN: bosses are just powerful enemies — no cinematic
            -- endings. Only the FINALE boss (the one placed after the last wave)
            -- arms the depth-clear; a boss dropped INTO a wave just dies and the
            -- wave carries on. Winning = clearing the LAST thing, not any boss.
            if e.isFinaleBoss then
                self.bossDefeated = true
                self:depthCleared()
            end
            -- wave bosses: combatantCount drop lets the wave clear normally
        else
            self.bossDefeated = true            -- this depth's boss is done — don't re-arm it
            if e.finalFinal then
                self:startChurglyFinale(e.x, e.y)   -- the corrupt god falls → the TRUE end
            elseif e.finalBoss then
                self.freedSquids = true
                self:startEldritchFinale(e.x, e.y)  -- it detonates before the victory screen
            elseif e.typeId == "maw" then
                self:startCutscene()            -- the Maw is the gatekeeper: get dragged deeper
            else
                self:depthCleared()             -- straight to the upgrade pick
            end
        end
    end
end

----------------------------------------------------------------------
-- run end + payout
----------------------------------------------------------------------
function Game:computePayout(won)
    -- No rewards for bailing out or dying in the first 4 depths — you have to
    -- get past the early trench before a run pays anything.
    if not won and self.depth <= 4 then return 0 end
    -- lean base so $Things are earned over several runs, not minted in two
    local progress = self.depth * 18 + self.kills * 0.6 + self.score * 0.015 + self.collected * 1.2
    if won then progress = progress + 350 end
    local total = math.floor(progress * self.mods.pointMult * self.diff.payMult + 0.5)
    return math.max(0, total)
end

function Game:buildResult(won)
    return {
        won = won,
        custom = self.campaign ~= nil,          -- sandbox run: banks no real progress
        campaignName = self.campaign and self.campaign.name or nil,
        depth = self.depth,
        depthName = self:depthName(self.depth),
        kills = self.kills,
        score = self.score,
        collected = self.collected,
        payout = self:computePayout(won),
        pointMult = self.mods.pointMult,
        modIds = self.modIds,
        modCount = self.mods.count,
        flawless = won and (not self.player.tookHit),
        bossKills = self._bossKilledThisRun or 0,
        bestCombo = self.bestCombo,
        time = self.time,
        freedSquids = self.freedSquids or false,
        difficulty = self.diff.id,
        reachedHadal = self.depth >= HADAL_FROM,
        cleanDepth = self.cleanDepth or false,
        killsByType = self.killsByType,
        leviSurvived = self.leviSurvived,
        usedLifesteal = self.usedLifesteal or false,
        -- why no $Things were earned (shown on the run-end screen)
        noReward = (not won and self.depth <= 4),
    }
end

function Game:endRun(won)
    if self.phase == "won" or self.phase == "lost" then return end
    self.phase = won and "won" or "lost"
    self.phaseTimer = 0
    if won then Audio.play("win") end
    self.result = self:buildResult(won)
    if self.onEnd then self.onEnd(self.result) end
end

-- The Eldritch Squid detonates, THEN the victory screen. In TERROR the screen
-- offers to continue the run down into the fractalspace (the Churgly'nth).
function Game:startEldritchFinale(x, y)
    self.phase = "finale_eldritch"
    self.phaseTimer = 2.2
    self.fxCenter = { x = x, y = y }
    self.bullets:clearTeam("enemy")
    self.leviathans = {}
    self.cornerArms = {}
    self.shake = 26
    self.flash = 1.0
    Audio.play("boss")
end

-- TERROR-only: the victory screen's "Continue Run" was chosen — bank the win
-- now, then sink into the fractalspace for the final-final confrontation.
function Game:beginChurglyFight()
    self.churglyMode = true
    self.churglyBanked = true                 -- primary win already paid out
    self.phase = "fractal"
    self.phaseTimer = 3.0                      -- 3s of empty fractal space first
    self.fractalT = 0
    self.bullets:clearTeam("enemy")
    self.enemies = {}
    self.leviathans = {}
    self.cornerArms = {}
    self.hazards = {}
    self.bossDefeated = false
    self.bossAlive = false
    self.hadalDark = 0                          -- the void is lit by the fractals
    self.player.hp = self.player.maxHp          -- full heal for the insane fight
    self.player.alive = true
    self.banner = nil
    Audio.playMusic("voidcore")
    Audio.play("boss")
    self.shake = 24
end

-- The corrupt god surfaces in the fractalspace. It looms and speaks before the
-- bullet storm begins (its `introT` gates the attacks).
function Game:spawnChurgly()
    self.phase = "playing"
    local a = self.arena
    local boss = self:spawnEnemy("churglynth", a.x + a.w / 2, a.y + a.h / 2, { depthScale = 1, noVariant = true })
    boss.introT = 13.0
    self.churgly = boss
    self.bossAlive = true
    self.bossPending = false
    self.bossDefeated = false
    self.banner = nil
    self.toSpawn = 0
    -- It mocks your victory, then "justifies" caging the squids. Don't listen.
    self.dialogue = {
        "CHURGLY'NTH:  So. The little squid unmakes my Eldritch herald.",
        "CHURGLY'NTH:  Foolish, brittle thing — you swam DOWN here to die.",
        "CHURGLY'NTH:  I caged your kin to spare them the fractal rot.",
        "CHURGLY'NTH:  I am the only thing between them and the hungry geometry.",
        "( Do not listen.  There is no mercy in a corrupt god. )",
    }
    self.dialogueLen = 13.0
    Audio.play("boss")
    self.shake = 22
end

-- Churgly'nth slain: explosion, then the secondary (TRUE END) reward screen.
function Game:startChurglyFinale(x, y)
    self.phase = "finale_churgly"
    self.phaseTimer = 2.6
    self.fxCenter = { x = x, y = y }
    self.bullets:clearTeam("enemy")
    self.shake = 30
    self.flash = 1.0
    Audio.play("boss")
end

-- End of the Churgly'nth chapter. Primary rewards were already banked at the
-- continue screen, so this only carries the SECONDARY (true-end) reward flag.
function Game:endChurglyRun(won)
    if self.phase == "churgly_over" then return end
    self.phase = "churgly_over"
    self.phaseTimer = 0
    local result = self:buildResult(true)       -- the run itself is still a win
    result.churgly = true                       -- App: do not re-bank primary stats
    result.churglyWon = won                      -- secondary rewards only if true
    result.payout = won and 4500 or 0            -- bonus $Things for the true end
    self.result = result
    if won then Audio.play("win") end
    if self.onEnd then self.onEnd(result) end
end

----------------------------------------------------------------------
-- update
----------------------------------------------------------------------
function Game:update(dt, mx, my)
    if self.paused then return end
    self._mx, self._my = mx, my
    dt = math.min(dt, 1 / 30)
    self.time = self.time + dt

    -- ambient marine snow always drifts
    for _, s in ipairs(self.snow) do
        s.y = s.y + s.v * dt
        s.x = s.x + math.sin(self.time + s.y * 0.01) * 4 * dt
        if s.y > LH then s.y = -4; s.x = U.rand(0, LW) end
    end

    self.shake = math.max(0, self.shake - dt * 40)
    self.flash = math.max(0, self.flash - dt * 2)

    -- Hadal ambience: drifting background horrors + sporadic loud noises.
    if self.hadal then
        for _, m in ipairs(self.bgMonsters) do
            m.x = m.x + m.vx * dt; m.y = m.y + m.vy * dt; m.t = m.t + dt
            if m.x < -220 then m.x = LW + 220 elseif m.x > LW + 220 then m.x = -220 end
            if m.y < 60 then m.vy = math.abs(m.vy) elseif m.y > LH - 60 then m.vy = -math.abs(m.vy) end
        end
        self.noiseTimer = self.noiseTimer - dt
        if self.noiseTimer <= 0 then
            self.noiseTimer = U.rand(3.5, 6.5)
            Audio.play("boss", U.rand(0.25, 0.5))      -- distant roar
        end
    end
    for _, sq in ipairs(self.trappedSquids) do sq.t = sq.t + dt end

    -- cutscene: dragged below the Maw into the Hadal Depths
    if self.phase == "cutscene" then
        self.phaseTimer = self.phaseTimer - dt
        self.particles:update(dt)
        if self.phaseTimer <= 0 then self:depthCleared() end
        return
    end
    -- campaign title card: story text. When it ends, walk to the next node
    -- (another title, the depth it precedes, or the win if nothing's left).
    if self.phase == "ctitle" then
        self.phaseTimer = self.phaseTimer - dt
        self.particles:update(dt)
        if self.phaseTimer <= 0 then self:advanceCampaign((self.nodeI or 1) + 1) end
        return
    end
    -- reveal: monsters gone, the trapped squids found, before the Eldritch Squid
    if self.phase == "reveal" then
        self.phaseTimer = self.phaseTimer - dt
        self.particles:update(dt)
        if self.phaseTimer <= 0 then self:spawnBoss() end
        return
    end

    if self.phase == "intro" or self.phase == "boss_intro" then
        self.phaseTimer = self.phaseTimer - dt
        -- let the world keep simmering a touch during boss intro
        self.particles:update(dt)
        if self.phaseTimer <= 0 then
            if self.phase == "boss_intro" then
                self.phase = "playing"
            else
                self.phase = "playing"
                self:startNextWave()
            end
        end
        return
    end

    -- Eldritch detonation, then the victory screen (or the continue choice).
    if self.phase == "finale_eldritch" then
        self.phaseTimer = self.phaseTimer - dt
        self.particles:update(dt)
        if self.fxCenter and U.chance(0.6) then
            self.particles:burst(self.fxCenter.x + U.rand(-90, 90), self.fxCenter.y + U.rand(-90, 90),
                8, { 0.9, 0.3, 1.0 }, { speed = 320 })
            self.shake = math.max(self.shake, 12)
        end
        if self.phaseTimer <= 0 then
            if self.terror then self.phase = "victory_choice"; Audio.play("win")
            else self:endRun(true) end
        end
        return
    end
    -- TERROR: holding on the Continue / Exit choice (clicks in mousepressed)
    if self.phase == "victory_choice" then self.particles:update(dt); return end
    -- the descent: 3s of drifting fractalspace, then the corrupt god appears
    if self.phase == "fractal" then
        self.fractalT = (self.fractalT or 0) + dt
        self.phaseTimer = self.phaseTimer - dt
        self.particles:update(dt)
        if self.phaseTimer <= 0 then self:spawnChurgly() end
        return
    end
    -- Churgly detonation, then the true-end reward screen.
    if self.phase == "finale_churgly" then
        self.fractalT = (self.fractalT or 0) + dt
        self.phaseTimer = self.phaseTimer - dt
        self.particles:update(dt)
        if self.fxCenter and U.chance(0.7) then
            self.particles:burst(self.fxCenter.x + U.rand(-110, 110), self.fxCenter.y + U.rand(-110, 110),
                10, { 1.0, 0.35, 1.0 }, { speed = 360 })
            self.shake = math.max(self.shake, 14)
        end
        if self.phaseTimer <= 0 then self:endChurglyRun(true) end
        return
    end
    if self.phase == "churgly_over" then self.particles:update(dt); return end

    if self.phase == "upgrade" then return end           -- waiting on player pick
    if self.phase == "won" or self.phase == "lost" then
        self.particles:update(dt)
        return
    end

    -- ---- playing ----
    local ctx = self:ctx()
    if self.churglyMode then self.fractalT = (self.fractalT or 0) + dt end

    -- input
    self.player.alive = self.player.hp > 0
    local input = {
        ax = mx, ay = my,
        mx = (love.keyboard.isDown("d", "right") and 1 or 0) - (love.keyboard.isDown("a", "left") and 1 or 0),
        my = (love.keyboard.isDown("s", "down") and 1 or 0) - (love.keyboard.isDown("w", "up") and 1 or 0),
        shoot = love.mouse.isDown(1),
        dash = self.dashQueued or false,
    }
    self.dashQueued = false
    ctx.input = input

    if self.player.alive then
        self.player:update(dt, ctx)
        if (self.player.lifesteal or 0) > 0 then self.usedLifesteal = true end   -- for the No Crutch run
    else
        if self.churglyMode then self:endChurglyRun(false) else self:endRun(false) end
        return
    end

    -- combo decay
    if self.comboTimer > 0 then
        self.comboTimer = self.comboTimer - dt
        if self.comboTimer <= 0 then self.combo = 0 end
    end
    if (self.bossWarnT or 0) > 0 then self.bossWarnT = self.bossWarnT - dt end

    -- wave spawning
    if self.phase == "playing" and not self.bossPending and not self.bossAlive then
        if self.toSpawn > 0 then
            self.spawnTimer = self.spawnTimer - dt
            local alive = self:combatantCount()   -- mines/hazards don't count toward the cap
            if self.spawnTimer <= 0 and alive < (self.maxAlive or 12) then
                self.spawnTimer = U.rand(0.3, 0.75)
                if self.campaign then
                    -- pop the next enemy from this wave's queue (built in startNextWave)
                    local nx = self.waveQueue and table.remove(self.waveQueue)
                    if nx then
                        local x, y = self:randomEdgePos()
                        local v = (nx.cfg and nx.cfg.variant and nx.cfg.variant ~= "base") and nx.cfg.variant or nil
                        self:spawnEnemy(nx.id, x, y, { cfg = nx.cfg, variant = v, noVariant = (v == nil), name = nx.name, asBoss = nx.asBoss })
                    end
                    self.toSpawn = self.toSpawn - 1
                else
                local id = Enemies.pickForDepth(self.depth)
                if self.terror and U.chance(0.35) then id = "parasite" end   -- flesh parasites from the start
                -- cap concurrent hazards/shooters so levels are bullet HELL, not
                -- bullet IMPOSSIBLE (no wall of every-enemy-firing-at-once).
                local caps = { mine = 4, terror = 3, wormsing = 2, churgspawn = 2, crawler = 2, spitter = 2, lurker = 2 }
                if caps[id] then
                    local c = 0
                    for _, e in ipairs(self.enemies) do if e.typeId == id then c = c + 1 end end
                    if c >= caps[id] then
                        id = self.hadal and "parasite" or U.pick({ "drifter", "darter", "gulper" })
                    end
                end
                -- hard cap on TOTAL shooters alive, regardless of type
                local SHOOTERS = { spitter = true, lurker = true, terror = true }
                if SHOOTERS[id] then
                    local sc = 0
                    for _, e in ipairs(self.enemies) do if SHOOTERS[e.typeId] then sc = sc + 1 end end
                    if sc >= (self.hadal and 4 or 3) then
                        id = self.hadal and "parasite" or U.pick({ "drifter", "darter", "gulper", "snapper" })
                    end
                end
                local x, y = self:randomEdgePos()
                self:spawnEnemy(id, x, y)
                self.toSpawn = self.toSpawn - 1
                end
            end
        elseif self:combatantCount() == 0 then
            -- wave cleared (placed mines are hazards, not combatants)
            if self.wave < self.waveCount then
                self:startNextWave()
            elseif self:bossAt(self.depth) and not self.bossDefeated then
                self.bossPending = true
            else
                self:depthCleared()
            end
        end
    elseif self.bossPending and not self.bossDefeated and self:combatantCount() == 0 then
        if not self.campaign and self.depth == MAX_DEPTH and not self.revealDone then
            self:startReveal()       -- monsters vanish, trapped squids found, then the boss
        else
            self:spawnBoss()
        end
    end

    -- enemies
    for _, e in ipairs(self.enemies) do
        Enemies.update(e, dt, ctx)
        -- puffer explosion
        if e.explodeNow then
            e.explodeNow = false
            -- editor-tunable blast radius (boomR special); default ~95
            local boomR = (e.cfg and (e.cfg.boomR or 0) > 0) and e.cfg.boomR or 95
            self.particles:spawn(e.x, e.y, { kind = "ring", size = boomR * 0.84, life = 0.5, color = e.glow })
            self.particles:burst(e.x, e.y, 24, e.glow, { speed = 260 })
            if U.dist(e.x, e.y, self.player.x, self.player.y) < boomR then
                self.player:takeDamage(e.damage, ctx)
            end
            self.shake = math.max(self.shake, 7)
            e.dead = true
            self.kills = self.kills + 1
        end
        -- contact damage (latched parasites leech instead of bumping)
        if not e.dead and not e.latched and U.dist(e.x, e.y, self.player.x, self.player.y) < e.radius + self.player.radius then
            if e.contactTimer <= 0 then
                e.contactTimer = 0.6
                self.player:takeDamage(e.damage, ctx)
                if e.type.poisonDmg then                                     -- venomous bite (Husk Crawler)
                    -- editor knobs: total poison damage + a length multiplier on
                    -- the stock duration (rate = damage / desired duration).
                    local pdmg = (e.cfg and (e.cfg.poisonDmg or 0) > 0) and e.cfg.poisonDmg or e.type.poisonDmg
                    local plen = (e.cfg and (e.cfg.poisonLen or 0) > 0) and e.cfg.poisonLen or 1
                    local baseDur = e.type.poisonDmg / 24                     -- the crawler's stock duration
                    ctx.poison(pdmg, pdmg / (baseDur * plen))
                end
                if self.player.thorns > 0 then self:damageEnemy(e, e.damage * self.player.thorns, self.player.x, self.player.y) end
            end
        end
    end

    -- bullets
    self.bullets:update(dt, ctx)
    self:resolveBullets(ctx)

    -- ink clouds
    local ic = 1
    while ic <= #self.inkClouds do
        local c = self.inkClouds[ic]
        c.life = c.life - dt
        if c.life <= 0 then
            table.remove(self.inkClouds, ic)
        else
            for _, e in ipairs(self.enemies) do
                if not e.dead and U.dist(c.x, c.y, e.x, e.y) < c.r + e.radius then
                    self:damageEnemy(e, c.dmg * dt, c.x, c.y)
                end
            end
            ic = ic + 1
        end
    end

    -- leviathan flybys: random across the whole Hadal range (depths 9-12), or
    -- ANY round in TERROR (as red dragons). Depth 10's waves 2 & 3 are the
    -- guaranteed scripted ones, so no RANDOM there — but wave 1 can still roll.
    -- Hadal range (9-12) for everyone; in TERROR red leviathans crash earlier too
    -- (depths 4-12). NEVER in the shallows (depths 1-3) — depth 2 stays clean.
    -- custom campaigns NEVER get random flybys — only the leviathans you place
    -- in the editor (which keep their chosen variant, e.g. a pale stays pale).
    local leviOk = not self.campaign and (self.depth >= 9 or (self.terror and self.depth >= 4)) and self.depth <= 12
    if self.depth == 11 and self.wave >= 2 then leviOk = false end   -- depth 11's are scripted
    -- Normally no leviathans during a boss fight. In TERROR red leviathans MAY
    -- visit boss fights too — except the Eldritch Squid & Churgly'nth (depth 13).
    local duringBoss = self.bossAlive and not (self.terror and self.depth < 13)
    if leviOk and self.phase == "playing" and not duringBoss
        and self.leviDone < self.leviCap and #self.leviathans == 0 then
        self.leviTimer = self.leviTimer - dt
        if self.leviTimer <= 0 then
            self.leviTimer = self.terror and U.rand(6, 11) or U.rand(9, 16)
            self:spawnLeviathan(); self.leviDone = self.leviDone + 1
        end
    end
    local lvi = 1
    while lvi <= #self.leviathans do
        local L = self.leviathans[lvi]
        if L.parked then
            self:updateBossLevi(L, dt, ctx)
            lvi = lvi + 1
        else
        L.anim = L.anim + dt
        L.x = L.x + L.dir * L.speed * dt
        L.y = L.band + math.sin(L.x * L.freq + L.anim) * L.amp
        L.contactCd = math.max(0, L.contactCd - dt)
        -- the ground rumbles as it passes (the red dragon shakes harder)
        if L.x > self.arena.x - 120 and L.x < self.arena.x + self.arena.w + 120 then
            self.shake = math.max(self.shake, L.fire and 4.5 or 3)
        end
        -- it floods its ENTIRE half with toxic bile: drop big pools centered on
        -- its half as it crosses, forming a continuous toxic band. Get to the
        -- other half of the screen.
        local a = self.arena
        local halfY = L.top and (a.y + a.h * 0.25) or (a.y + a.h * 0.75)
        L.spitT = L.spitT - dt
        if L.spitT <= 0 and L.x > a.x - 60 and L.x < a.x + a.w + 60 then
            L.spitT = 0.22
            local tx = U.clamp(L.x, a.x + 10, a.x + a.w - 10)
            ctx.spawnHazard(tx, halfY, a.h * 0.30, L.sludgeDmg or 13, L.sludgeLife or (L.blue and 11 or 5.5))   -- blue's bile lingers 2x
            self.particles:burst(tx, halfY + U.rand(-a.h * 0.2, a.h * 0.2), 4, L.glow, { speed = 50, color = L.glow })
        end
        -- DARK-BLUE leviathan: short clawing arms reach out of every 3rd segment
        -- toward you — contact hurts (on a short cooldown).
        if L.blue then
            L.armCd = math.max(0, (L.armCd or 0) - dt)
            local armLen = L.r * 2.6 * (L.armMul or 1)   -- 1.75x base reach, editor-scalable
            for s = 0, L.len, 3 do
                local bx = L.x - L.dir * s * L.spacing
                local by = L.band + math.sin(bx * L.freq + L.anim) * L.amp
                -- only the arm TIP grabs (must be near where the claw actually
                -- reaches) — not the whole reach radius — and it can't instakill
                if U.dist(bx, by, self.player.x, self.player.y) < armLen + self.player.radius then
                    if L.armCd <= 0 then L.armCd = 0.85; self.player:takeDamage(12, ctx) end
                    break
                end
            end
        end
        -- RED dragon breathes ONE big spray of green fire straight at you as it
        -- reaches the middle: a real flame cone (not just bullets), eating health,
        -- that leaves huge toxic splotches where it lands.
        if L.fire and not L.firedOnce and L.x > a.x + a.w * 0.32 and L.x < a.x + a.w * 0.68 then
            L.firedOnce = true
            local fa = U.angleTo(L.x, L.y, self.player.x, self.player.y)
            -- the flame: a dense stream of green fire particles in a cone
            for _ = 1, 60 do
                local fad = fa + U.rand(-0.35, 0.35)
                local spd = U.rand(220, 520)
                self.particles:spawn(L.x, L.y, {
                    vx = math.cos(fad) * spd, vy = math.sin(fad) * spd,
                    life = U.rand(0.5, 1.1), size = U.rand(5, 12), drag = 1.5,
                    color = U.chance(0.5) and L.fireGlow or { 0.8, 1.0, 0.3 }, kind = "ink",
                })
            end
            -- a few fire bolts ride the stream (the damaging core)
            for j = -2, 2 do
                ctx.shoot(L.x, L.y, math.cos(fa + j * 0.10) * 380, math.sin(fa + j * 0.10) * 380, 18, L.fireGlow, 10, 4)
            end
            -- huge toxic splotches along the player's lane where the fire lands.
            -- The green fire MARKS the spot for 2 seconds (telegraph) before the
            -- toxic sludge actually settles there — so you can clear out.
            for k = -1, 1 do
                local hx = self.player.x + math.cos(fa) * 80 + k * 70
                local hy = self.player.y + math.sin(fa) * 40 + U.rand(-30, 30)
                ctx.spawnHazard(hx, hy, a.h * 0.22, L.sludgeDmg or 16, L.sludgeLife or 5.5, L.fireGlow, nil, 2.0)
            end
            self.shake = math.max(self.shake, 14)   -- the roar of fire-breath
        end
        -- body collision (move to the other half!)
        for s = 0, L.len do
            local bx = L.x - L.dir * s * L.spacing
            local by = L.band + math.sin(bx * L.freq + L.anim) * L.amp
            local rr = L.r * (1 - s / (L.len + 3) * 0.4)
            if U.dist(bx, by, self.player.x, self.player.y) < rr + self.player.radius then
                if L.contactCd <= 0 then L.contactCd = 0.5; self.player:takeDamage(55, ctx) end   -- the leviathan body itself HURTS
                break
            end
        end
        local a = self.arena
        if (L.dir > 0 and L.x - L.len * L.spacing > a.x + a.w + 320)
            or (L.dir < 0 and L.x + L.len * L.spacing < a.x - 320) then
            -- only the true (non-fire) leviathan counts toward the bestiary
            if self.player.alive and not L.fire then self.leviSurvived = self.leviSurvived + 1 end
            table.remove(self.leviathans, lvi)
        else lvi = lvi + 1 end
        end
    end

    -- long churg-arms clawing in from the corners (TERROR eldritch fight)
    if self.cornerArms and #self.cornerArms > 0 then self:updateCornerArms(dt, ctx) end

    -- toxic hazard pools (damage the player while standing in them)
    local hz = 1
    while hz <= #self.hazards do
        local h = self.hazards[hz]
        -- a churg trail pool lingers ~2s after its source dies, THEN clears out fast
        local decay = dt
        if h.owner and h.owner.dead then
            h.deadT = (h.deadT or 0) + dt
            if h.deadT > 2 then decay = dt * 6 end
        end
        -- ARMING phase: a harmless green-fire telegraph that hasn't become sludge yet
        if h.arming and h.arming > 0 then
            h.arming = h.arming - dt
            h.t = h.t + dt
            hz = hz + 1
        else
            h.life = h.life - decay; h.t = h.t + dt
            if h.life <= 0 then
                table.remove(self.hazards, hz)
            else
                if h.life > 0.4 and U.dist(h.x, h.y, self.player.x, self.player.y) < h.r + self.player.radius * 0.5 then
                    -- TERROR sludge bites harder (leviathan bile, fire splotches, churg trail)
                    local dmgMult = self.terror and 1.7 or 1
                    ctx.leech(h.dmg * dmgMult * dt)   -- DoT, bypasses i-frames: don't stand in it
                end
                hz = hz + 1
            end
        end
    end

    -- pickups (magnet + collect)
    local pk = 1
    while pk <= #self.pickups do
        local m = self.pickups[pk]
        m.life = m.life - dt
        m.t = m.t + dt
        local d = U.dist(m.x, m.y, self.player.x, self.player.y)
        if d < self.player.magnet then
            local nx, ny = U.normalize(self.player.x - m.x, self.player.y - m.y)
            local pull = U.lerp(120, 520, 1 - d / self.player.magnet)
            m.vx = m.vx + nx * pull * dt * 6
            m.vy = m.vy + ny * pull * dt * 6
        end
        m.vx = m.vx * math.exp(-2 * dt); m.vy = m.vy * math.exp(-2 * dt)
        m.x = m.x + m.vx * dt; m.y = m.y + m.vy * dt
        if d < self.player.radius + 6 or m.life <= 0 and d < self.player.magnet then
            if d < self.player.radius + 10 then
                self.collected = self.collected + m.val
                Audio.play("coin", 0.3)
                self.particles:spawn(m.x, m.y, { kind = "spark", size = 4, life = 0.3, color = P.gold })
            end
            table.remove(self.pickups, pk)
        elseif m.life <= 0 then
            table.remove(self.pickups, pk)
        else
            pk = pk + 1
        end
    end

    -- cull dead enemies
    local i = 1
    while i <= #self.enemies do
        if self.enemies[i].dead then table.remove(self.enemies, i) else i = i + 1 end
    end

    self.particles:update(dt)
end

function Game:resolveBullets(ctx)
    for _, b in ipairs(self.bullets.list) do
        if b.team == "player" then
            for _, e in ipairs(self.enemies) do
                if not e.dead and e.typeId ~= "mine" and e.typeId ~= "crawler" and not b.hitSet[e] and U.dist(b.x, b.y, e.x, e.y) < b.radius + e.radius then
                    b.hitSet[e] = true
                    self:damageEnemy(e, b.damage, b.x, b.y)
                    self.particles:spawn(b.x, b.y, { kind = "spark", size = b.crit and 6 or 4,
                        life = 0.25, color = b.crit and P.gold or b.color })
                    if b.explosive then ctx.explode(b.x, b.y, b.damage * 0.7, b.color); b.life = 0; break end
                    if b.pierce > 0 then b.pierce = b.pierce - 1 else b.life = 0; break end
                end
            end
        else -- enemy bullet vs player
            if self.player.alive and U.dist(b.x, b.y, self.player.x, self.player.y) < b.radius + self.player.radius then
                self.player:takeDamage(b.damage, ctx)
                b.life = 0
            end
        end
    end
end

function Game:depthCleared()
    -- cleared this depth without being touched? remember it for the achievement
    if self.player.depthClean then self.cleanDepth = true end
    if self.campaign then
        -- node-based: if no depth remains after this one, run out any trailing
        -- title cards then WIN. Otherwise optionally offer a card, then walk on.
        if not self:hasMoreDepthsAfter(self.nodeI or 1) then
            self:advanceCampaign((self.nodeI or 1) + 1)   -- trailing titles → win
            return
        end
        local node = self.cDepths[self.depth]
        if node and node.cards == false then
            if not self.mods.noHeal then self.player:heal(self.player.maxHp * 0.35) end
            self.bullets:clearTeam("enemy")
            self:advanceCampaign((self.nodeI or 1) + 1)
            return
        end
    else
        if self.depth >= self:maxDepth() then self:endRun(true); return end
    end
    self.phase = "upgrade"
    -- ONE last-second recommendation: on the final card select before the Maw
    -- (the depth-7 clear), if you still don't OWN the Vampire Squid, force it into
    -- the offer that one time. Not before, not after — no spamming it every round.
    local force = nil
    if self.depth == 7 and not self.takenUnique["lifesteal"] then
        force = "lifesteal"
    end
    self.offered = Upgrades.offer(self.takenUnique, 3, force)
    self.recommended = nil
    for _, u in ipairs(self.offered) do
        if u.id == "lifesteal" then
            self.offeredLifesteal = true
            if force == "lifesteal" then self.recommended = "lifesteal" end
        end
    end
    self.upgradeHover = nil
    Audio.play("upgrade", 0.6)
end

function Game:pickUpgrade(idx)
    local up = self.offered and self.offered[idx]
    if not up then return end
    self.player:applyUpgrade(up)
    self.takenUpgrades[#self.takenUpgrades + 1] = up.id
    if up.unique then self.takenUnique[up.id] = true end
    Audio.play("pickup", 0.7)
    if not self.mods.noHeal then self.player:heal(self.player.maxHp * 0.35) end
    self.bullets:clearTeam("enemy")
    if self.campaign then
        self:advanceCampaign((self.nodeI or 1) + 1)
    else
        self.depth = self.depth + 1
        self:startDepth()
    end
end

----------------------------------------------------------------------
-- input
----------------------------------------------------------------------
function Game:keypressed(key)
    -- F7 / F8 are ADMIN-only (enable admin by editing the save file).
    if key == "f8" then     -- debug: toggle immortality
        if not (self.save.admin or self.campaign) then return end   -- campaign test mode enables it too
        self.god = not self.god
        require("src.debuglog").add(self.god and "GOD MODE on (F8)" or "GOD MODE off")
        return
    end
    if key == "f7" then     -- debug: skip the current wave (clears all enemies)
        if not (self.save.admin or self.campaign) then return end   -- campaign test mode enables it too
        self.toSpawn = 0
        for _, e in ipairs(self.enemies) do self:damageEnemy(e, 1e9, e.x, e.y) end
        require("src.debuglog").add("debug: skipped wave (F7)")
        return
    end
    if self.phase == "won" or self.phase == "lost" then return end
    if key == "escape" then
        self.paused = not self.paused
        return
    end
    if self.paused then
        if key == "q" then self:endRun(false) end
        return
    end
    if key == "space" or key == "lshift" or key == "rshift" then
        self.dashQueued = true
    elseif self.phase == "upgrade" then
        if key == "1" then self:pickUpgrade(1)
        elseif key == "2" then self:pickUpgrade(2)
        elseif key == "3" then self:pickUpgrade(3) end
    end
end

function Game:victoryButtonRects()
    local bw, bh = 320, 64
    local cx = LW / 2
    return {
        cont = { x = cx - bw - 20, y = LH / 2 + 70, w = bw, h = bh },
        exit = { x = cx + 20, y = LH / 2 + 70, w = bw, h = bh },
    }
end

function Game:mousepressed(mx, my, button)
    if self.paused then return end
    -- click anywhere to skip the Churgly'nth's monologue and start the fight
    if self.churglyMode and self.churgly and (self.churgly.introT or 0) > 0 then
        self.churgly.introT = 0
        return
    end
    if self.phase == "victory_choice" then
        local b = self:victoryButtonRects()
        if U.inRect(mx, my, b.cont.x, b.cont.y, b.cont.w, b.cont.h) then
            -- bank the primary win NOW, then sink into the fractalspace
            local r = self:buildResult(true)
            r.keepPlaying = true
            self.result = r
            if self.onEnd then self.onEnd(r) end
            self:beginChurglyFight()
        elseif U.inRect(mx, my, b.exit.x, b.exit.y, b.exit.w, b.exit.h) then
            self:endRun(true)
        end
        return
    end
    if self.phase == "upgrade" then
        local cards = self:upgradeCardRects()
        for i, r in ipairs(cards) do
            if U.inRect(mx, my, r.x, r.y, r.w, r.h) then self:pickUpgrade(i); return end
        end
    elseif button == 2 then
        self.dashQueued = true
    end
end

----------------------------------------------------------------------
-- drawing
----------------------------------------------------------------------
function Game:drawLeviathans()
    for _, L in ipairs(self.leviathans) do
        local dark = U.shade(L.color, 0.7)
        -- long body trailing behind the head
        for s = L.len, 1, -1 do
            local bx = L.x - L.dir * s * L.spacing
            local by = L.band + math.sin(bx * L.freq + L.anim) * L.amp
            local rr = L.r * (1 - s / (L.len + 3) * 0.5)
            U.glow(bx, by, rr * 1.3, L.glow, 0.18)
            love.graphics.setColor(L.color[1], L.color[2], L.color[3], 1)
            love.graphics.circle("fill", bx, by, rr)
            -- fins
            love.graphics.setColor(dark[1], dark[2], dark[3], 1)
            local fa = bx * L.freq + L.anim
            love.graphics.polygon("fill", bx, by - rr, bx - L.dir * rr * 0.8, by - rr * 1.8 - math.sin(fa) * 6, bx - L.dir * rr * 0.3, by - rr)
            love.graphics.polygon("fill", bx, by + rr, bx - L.dir * rr * 0.8, by + rr * 1.8 + math.sin(fa) * 6, bx - L.dir * rr * 0.3, by + rr)
            -- DARK-BLUE leviathan: a clawing arm reaches toward you out of every
            -- 3rd segment. Built as a smooth bending PATH and rendered like the
            -- Eldritch corner-arms (dark outline + tapering core), in the
            -- leviathan's own blue. The tip hurts on contact.
            if L.blue and s % 3 == 0 then
                local pa = U.angleTo(bx, by, self.player.x, self.player.y)
                local steps = 12
                local seg = (L.r * 2.6 * (L.armMul or 1)) / steps   -- 1.75x base, editor-scalable
                local px, py = bx, by
                local path = { { bx, by } }
                for k = 1, steps do
                    local dir = pa + math.sin(L.anim * 3 + s + k * 0.5) * 0.3 * (1 - k / steps)
                    px, py = px + math.cos(dir) * seg, py + math.sin(dir) * seg
                    path[#path + 1] = { px, py }
                end
                local outline = U.shade(L.color, 0.55)
                local core = U.shade(L.color, 1.5)
                for i = 1, #path - 1 do
                    local f = (i - 1) / (#path - 1)
                    love.graphics.setColor(outline[1], outline[2], outline[3], 1)
                    love.graphics.setLineWidth((1 - f) * 16 + 3)
                    love.graphics.line(path[i][1], path[i][2], path[i + 1][1], path[i + 1][2])
                    love.graphics.setColor(core[1], core[2], core[3], 1)
                    love.graphics.setLineWidth((1 - f) * 9 + 1)
                    love.graphics.line(path[i][1], path[i][2], path[i + 1][1], path[i + 1][2])
                end
                local tip = path[#path]
                U.glow(tip[1], tip[2], L.r * 0.35, L.glow, 0.6)
                love.graphics.setColor(L.glow[1], L.glow[2], L.glow[3], 1)
                love.graphics.circle("fill", tip[1], tip[2], L.r * 0.1)
            end
        end
        -- UNCANNY HUMAN HEAD (profile, facing travel direction; open jaw with
        -- human teeth, eyes closed). Pale purplish-white flesh.
        love.graphics.push(); love.graphics.translate(L.x, L.y)
        if L.parked then love.graphics.rotate((L.lookA or 0) * (L.dir < 0 and -1 or 1)) end
        if L.dir < 0 then love.graphics.scale(-1, 1) end
        local r = L.r
        local skin = L.color
        if L.parked and (L.mouth or 0) > 0 then     -- maw flares as it spits
            U.glow(0.62 * r, 0.52 * r, r * 0.6 * L.mouth, L.glow, 0.9 * L.mouth)
        end
        local shade = U.shade(skin, 0.82)
        U.glow(0, 0, r * 1.6, L.glow, 0.35)
        if L.blue then
            -- No eyes — a deep-sea predator's head that is one huge GAPING MAW,
            -- hinged at the back and yawning open at the front, lined with slim,
            -- uneven needle fangs. Scary, not goofy.
            love.graphics.setColor(skin[1], skin[2], skin[3], 1)
            love.graphics.polygon("fill",
                -1.0 * r, -0.3 * r, -0.2 * r, -1.0 * r, 0.6 * r, -0.95 * r, 1.3 * r, -0.1 * r,
                1.25 * r, 0.6 * r, 0.5 * r, 1.1 * r, -0.5 * r, 0.9 * r, -1.0 * r, 0.3 * r)
            -- the black throat / open maw (a forward-opening wedge)
            local hux, huy, hlx, hly = -0.3 * r, -0.1 * r, -0.3 * r, 0.1 * r
            local fux, fuy, flx, fly = 1.22 * r, -0.72 * r, 1.22 * r, 0.72 * r
            love.graphics.setColor(0.01, 0.01, 0.04, 1)
            love.graphics.polygon("fill", hux, huy, fux, fuy, 1.42 * r, 0, flx, fly, hlx, hly)
            -- slim pointy fangs of VARYING length seated flush along each jaw line
            love.graphics.setColor(0.86, 0.91, 0.98, 1)
            local function jaw(ax, ay, bx, by, sign)
                local dx, dy = bx - ax, by - ay
                local len = math.sqrt(dx * dx + dy * dy)
                local nx, ny = -dy / len * sign, dx / len * sign
                local count = 9
                for i = 0, count - 1 do
                    local tc = (i + 0.5) / count
                    local cx2, cy2 = ax + dx * tc, ay + dy * tc
                    local hwd = (len / count) * 0.26                 -- slim base
                    local bxv, byv = dx / len * hwd, dy / len * hwd
                    local vary = (i % 2 == 0 and 1.0 or 0.55) * (0.75 + 0.5 * math.abs(math.sin(i * 2.7)))
                    local tl = (0.34 * r) * (0.5 + 0.8 * tc) * vary  -- longer toward the front, uneven
                    love.graphics.polygon("fill", cx2 - bxv, cy2 - byv, cx2 + bxv, cy2 + byv,
                        cx2 + nx * tl, cy2 + ny * tl)
                end
            end
            jaw(hux, huy, fux, fuy, 1)    -- upper fangs point down into the maw
            jaw(hlx, hly, flx, fly, -1)   -- lower fangs point up into the maw
        else
        -- upper head + snout (down to the upper jaw line)
        love.graphics.setColor(skin[1], skin[2], skin[3], 1)
        love.graphics.polygon("fill",
            -1.0 * r, -0.3 * r, -0.3 * r, -1.0 * r, 0.5 * r, -0.9 * r, 0.85 * r, -0.45 * r,
            1.3 * r, -0.05 * r, 1.15 * r, 0.15 * r, 0.2 * r, 0.15 * r, -0.45 * r, 0.0 * r)
        -- long DROPPED lower jaw — a tall, wide-open maw
        love.graphics.setColor(shade[1], shade[2], shade[3], 1)
        love.graphics.polygon("fill",
            -0.35 * r, 0.25 * r, 1.05 * r, 0.9 * r, 1.32 * r, 1.15 * r, 0.6 * r, 1.45 * r, -0.45 * r, 1.1 * r)
        -- the big black mouth cavity (tall)
        love.graphics.setColor(0.04, 0.02, 0.06, 1)
        love.graphics.polygon("fill", 0.18 * r, 0.13 * r, 1.18 * r, 0.1 * r, 1.05 * r, 0.95 * r, 0.2 * r, 0.92 * r)
        if L.fire then    -- a green glowing fireball charging in the open jaw
            local fbr = r * (0.34 + 0.05 * math.sin(L.anim * 10))
            U.glow(0.62 * r, 0.52 * r, fbr * 2.0, L.fireGlow, 0.9)
            love.graphics.setColor(L.fireGlow[1], L.fireGlow[2], L.fireGlow[3], 1)
            love.graphics.circle("fill", 0.62 * r, 0.52 * r, fbr)
            love.graphics.setColor(0.9, 1.0, 0.6, 1)
            love.graphics.circle("fill", 0.62 * r, 0.52 * r, fbr * 0.5)
        end
        -- flat HUMAN teeth: a top row and a bottom row, with the jaw held open
        love.graphics.setColor(0.95, 0.93, 0.9, 1)
        for j = 0, 6 do
            local tu = U.lerp(0.28 * r, 1.04 * r, j / 6)
            love.graphics.rectangle("fill", tu, 0.13 * r, r * 0.09, r * 0.16, 2)            -- upper
            local tl = U.lerp(0.33 * r, 0.99 * r, j / 6)
            love.graphics.rectangle("fill", tl, 0.92 * r - r * 0.16, r * 0.09, r * 0.16, 2)  -- lower
        end
        love.graphics.setColor(shade[1], shade[2], shade[3], 1)   -- nostril
        love.graphics.circle("fill", 1.12 * r, -0.02 * r, r * 0.05)
        -- long sinister eye-slit, set high and to the side (not human)
        love.graphics.push(); love.graphics.translate(0.38 * r, -0.52 * r); love.graphics.rotate(-0.14)
        love.graphics.setColor(0.05, 0.02, 0.07, 1); love.graphics.ellipse("fill", 0, 0, r * 0.44, r * 0.11)
        love.graphics.setColor(L.glow[1], L.glow[2], L.glow[3], 0.9)
        love.graphics.ellipse("fill", 0, 0, r * 0.36, r * 0.035)   -- glowing slit pupil
        love.graphics.pop()
        end   -- end blue / human head branch
        love.graphics.pop()
    end
end

function Game:upgradeCardRects()
    local n = self.offered and #self.offered or 3
    local cw, ch, gap = 300, 360, 36
    local totalW = n * cw + (n - 1) * gap
    local x0 = LW / 2 - totalW / 2
    local y = LH / 2 - ch / 2 + 20
    local rects = {}
    for i = 1, n do
        rects[i] = { x = x0 + (i - 1) * (cw + gap), y = y, w = cw, h = ch }
    end
    return rects
end

local rarityColor = P.rarity

function Game:draw()
    local sx, sy = 0, 0
    if self.shake > 0 then
        sx = U.rand(-self.shake, self.shake); sy = U.rand(-self.shake, self.shake)
    end
    love.graphics.push()
    love.graphics.translate(sx, sy)

    if self.churglyMode then
    -- the fractalspace: animated fractals where the depth used to be
    self:drawFractalBg()
    else
    -- background gradient (gets darker with depth)
    local topc = U.mixColor(P.deep, P.abyss, (self.depth - 1) / 8)
    local botc = U.mixColor(P.abyss2, { 0.02, 0.02, 0.05 }, (self.depth - 1) / 8)
    for i = 0, 24 do
        local f = i / 24
        love.graphics.setColor(U.lerp(topc[1], botc[1], f), U.lerp(topc[2], botc[2], f), U.lerp(topc[3], botc[3], f))
        love.graphics.rectangle("fill", 0, f * LH, LW, LH / 24 + 1)
    end

    -- marine snow
    for _, s in ipairs(self.snow) do
        love.graphics.setColor(0.6, 0.8, 1.0, 0.10 * s.s)
        love.graphics.circle("fill", s.x, s.y, s.r)
    end

    -- background horrors: huge half-seen shapes drifting in the black
    for _, m in ipairs(self.bgMonsters) do
        love.graphics.setColor(0.0, 0.0, 0.0, 0.5)
        love.graphics.circle("fill", m.x, m.y, m.r)
        love.graphics.setColor(0.03, 0.05, 0.09, 0.5)
        for i = 1, 5 do
            local a = i / 5 * math.pi * 2
            local sway = math.sin(m.t + i) * 20
            love.graphics.setLineWidth(10)
            love.graphics.line(m.x, m.y, m.x + math.cos(a) * (m.r * 1.5) + sway, m.y + math.sin(a) * (m.r * 1.5))
        end
        for i = 1, m.eyes do            -- dim, unblinking eyes
            local a = i / m.eyes * math.pi * 2 + m.t * 0.2
            love.graphics.setColor(0.7, 0.2, 0.25, 0.25 + 0.15 * math.sin(m.t * 2 + i))
            love.graphics.circle("fill", m.x + math.cos(a) * m.r * 0.4, m.y + math.sin(a) * m.r * 0.4, 4)
        end
    end
    end  -- end normal background / fractalspace

    -- the ancient gate behind the Maw — Site: Acheron, the door into the unknown
    -- (story scenery only — never in custom campaigns)
    if self.depth == 8 and not self.campaign then self:drawMawGate() end

    -- arena border
    love.graphics.setColor(P.panelEdge[1], P.panelEdge[2], P.panelEdge[3], 0.5)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", self.arena.x, self.arena.y, self.arena.w, self.arena.h, 8)

    local ctx = self:ctx()

    -- ink clouds
    for _, c in ipairs(self.inkClouds) do
        local a = c.life / c.max
        love.graphics.setColor(P.ink[1] + 0.1, P.ink[2] + 0.05, P.ink[3] + 0.2, 0.4 * a)
        love.graphics.circle("fill", c.x, c.y, c.r)
        love.graphics.setColor(0.4, 0.7, 1.0, 0.2 * a)
        love.graphics.circle("line", c.x, c.y, c.r)
    end

    -- toxic pools (leviathan spit / churgspawn trail) — do not touch
    for _, h in ipairs(self.hazards) do
        if h.arming and h.arming > 0 then
            -- GREEN-FIRE telegraph: warns where the sludge will land (no damage yet)
            local fg = { 0.45, 1.0, 0.25 }
            local flick = 0.6 + 0.4 * math.sin(h.t * 16) * math.sin(h.t * 7)
            U.glow(h.x, h.y, h.r * 1.3, fg, 0.5 * flick)
            love.graphics.setColor(fg[1], fg[2], fg[3], 0.5 * flick)
            love.graphics.setLineWidth(3); love.graphics.circle("line", h.x, h.y, h.r * (0.85 + 0.1 * flick))
            -- licking flames around the ring
            for b = 1, 8 do
                local ba = b / 8 * math.pi * 2 + h.t * 2
                local fr = h.r * (0.7 + 0.3 * math.abs(math.sin(h.t * 9 + b)))
                love.graphics.setColor(fg[1], fg[2], fg[3], 0.7 * flick)
                love.graphics.circle("fill", h.x + math.cos(ba) * fr, h.y + math.sin(ba) * fr, 3 + 2 * flick)
            end
        else
            local a = math.min(1, h.life / 1.0)
            local pulse = 0.5 + 0.3 * math.sin(h.t * 4)
            local c = h.color or { 0.6, 1.0, 0.3 }
            love.graphics.setColor(c[1], c[2], c[3], 0.22 * a)
            love.graphics.circle("fill", h.x, h.y, h.r * (0.92 + 0.08 * pulse))
            love.graphics.setColor(c[1], c[2], c[3], 0.55 * a)
            love.graphics.setLineWidth(2); love.graphics.circle("line", h.x, h.y, h.r)
            for b = 1, 3 do
                local ba = h.t * 1.3 + b * 2.1
                love.graphics.setColor(c[1], c[2], c[3], 0.5 * a)
                love.graphics.circle("fill", h.x + math.cos(ba) * h.r * 0.5, h.y + math.sin(ba) * h.r * 0.5, 2.5)
            end
        end
    end

    -- pickups
    for _, m in ipairs(self.pickups) do
        local bob = math.sin(m.t * 6) * 2
        love.graphics.setColor(1, 1, 1, 0.16)
        love.graphics.circle("fill", m.x, m.y + bob, 9)        -- soft glow
        U.drawThing(m.x, m.y + bob, 5)                         -- white cube blob
    end

    -- trapped squids — suspended in trippy eldritch forcefields
    for _, sq in ipairs(self.trappedSquids) do
        if not sq.freed then
            local tt, R = sq.t, 34
            U.glow(sq.x, sq.y, R * 1.9, P.purple, 0.35 + 0.2 * math.sin(tt * 3))
            -- the squid inside, dim and wobbling in the field
            Squid.draw(sq.x + math.sin(tt * 2) * 2, sq.y, { skin = sq.skin, angle = -math.pi / 2,
                scale = 0.38, t = tt, alpha = 0.7, noGlow = true })
            love.graphics.setColor(P.purple[1], P.purple[2], P.purple[3], 0.12)
            love.graphics.circle("fill", sq.x, sq.y, R)
            -- warping, counter-rotating glyph rings
            for layer = 1, 3 do
                local sides = 6
                local rr = R * (0.7 + layer * 0.17) * (1 + 0.08 * math.sin(tt * 4 + layer))
                local rot = tt * (0.6 + layer * 0.4) * (layer % 2 == 0 and -1 or 1)
                local pts = {}
                for i = 0, sides - 1 do
                    local a = rot + i / sides * math.pi * 2
                    local jit = 1 + 0.13 * math.sin(tt * 8 + i * 2 + layer)
                    pts[#pts + 1] = sq.x + math.cos(a) * rr * jit
                    pts[#pts + 1] = sq.y + math.sin(a) * rr * jit
                end
                local c = (layer % 2 == 0) and P.magenta or P.cyan
                love.graphics.setColor(c[1], c[2], c[3], 0.4)
                love.graphics.setLineWidth(2)
                love.graphics.polygon("line", pts)
            end
            -- crackle
            love.graphics.setColor(P.purple[1], P.purple[2], P.purple[3], 0.5)
            love.graphics.setLineWidth(1)
            for i = 1, 3 do
                local a = tt * 2 + i * 2.1
                love.graphics.line(sq.x, sq.y, sq.x + math.cos(a) * R * 1.1, sq.y + math.sin(a) * R * 1.1)
            end
        end
    end

    self.particles:draw()
    self.bullets:draw()
    for _, e in ipairs(self.enemies) do Enemies.draw(e, ctx) end
    if self.player.alive or self.phase ~= "lost" then self.player:draw() end

    -- darkness: Lights Out modifier OR the pitch-black Hadal Depths. A lit
    -- circle of MODERATE radius follows the squid — you see enemies when fairly
    -- close, but not so tight you can't react.
    local dark = math.max(self.mods.darkness or 0, self.hadalDark or 0)
    if dark > 0 then
        local r = U.lerp(330, 200, dark)
        love.graphics.stencil(function()
            love.graphics.circle("fill", self.player.x, self.player.y, r)
        end, "replace", 1)
        love.graphics.setStencilTest("equal", 0)
        love.graphics.setColor(0, 0, 0.01, math.min(0.97, dark + 0.18))
        love.graphics.rectangle("fill", 0, 0, LW, LH)
        love.graphics.setStencilTest()
        love.graphics.setColor(0.3, 0.55, 0.9, 0.10)
        love.graphics.circle("line", self.player.x, self.player.y, r)
    end

    -- enemy overlay parts drawn AFTER the darkness so they glint through the
    -- black — the Husk Crawler's armored head, while its body stays fogged.
    for _, e in ipairs(self.enemies) do Enemies.drawOverlay(e, ctx) end

    -- leviathans drawn AFTER the darkness so they loom through the black
    self:drawLeviathans()
    self:drawCornerArms()

    love.graphics.pop()  -- end shake

    -- screen flash
    if self.flash > 0 then
        love.graphics.setColor(1, 1, 1, self.flash * 0.4)
        love.graphics.rectangle("fill", 0, 0, LW, LH)
    end

    -- steady DARK-red vignette while a parasite is latched onto you and draining
    -- (subtle, no pulsing — it shouldn't read like an emergency alarm)
    local latchN = 0
    for _, e in ipairs(self.enemies) do if e.latched then latchN = latchN + 1 end end
    if latchN > 0 then
        local a = math.min(0.3, 0.15 + 0.06 * latchN)
        self:drawVignette({ 0.38, 0.0, 0.03 }, a)
    end

    self:drawHUD()

    -- banners
    if self.phase == "intro" or self.phase == "boss_intro" then
        local a = U.clamp(self.phaseTimer, 0, 1)
        love.graphics.setColor(0, 0, 0, 0.35 * math.min(1, self.phaseTimer))
        love.graphics.rectangle("fill", 0, LH / 2 - 90, LW, 180)
        local big = self.phase == "boss_intro" and P.red or P.cyan
        love.graphics.setColor(big[1], big[2], big[3], 1)
        love.graphics.setFont(self.fontBig or love.graphics.getFont())
        love.graphics.printf(self.bannerSub, 0, LH / 2 - 70, LW, "center")
        love.graphics.setColor(P.text)
        love.graphics.printf(self.banner, 0, LH / 2 - 20, LW, "center")
    end

    -- transient wave-boss warning (custom campaigns can drop bosses into a wave)
    if (self.bossWarnT or 0) > 0 then
        local a = U.clamp(self.bossWarnT, 0, 1)
        love.graphics.setColor(0, 0, 0, 0.35 * a)
        love.graphics.rectangle("fill", 0, LH / 2 - 70, LW, 70)
        love.graphics.setFont(self.fontBig or love.graphics.getFont())
        love.graphics.setColor(P.red[1], P.red[2], P.red[3], a)
        love.graphics.printf(self.bossWarnText or "WARNING", 0, LH / 2 - 56, LW, "center")
    end

    if self.phase == "ctitle" then self:drawTitleCard() end
    if self.phase == "cutscene" then self:drawCutscene() end
    if self.phase == "reveal" then self:drawReveal() end
    if self.phase == "upgrade" then self:drawUpgrade() end
    if self.phase == "victory_choice" then self:drawVictoryChoice() end
    -- the corrupt god's monologue, while it looms before the storm
    if self.churglyMode and self.churgly and (self.churgly.introT or 0) > 0 and self.dialogue then
        self:drawChurglyDialogue()
    end
    if self.paused then self:drawPause() end
end

-- Animated fractals filling the void where the Churgly'nth lives.
function Game:drawFractalBg()
    local t = self.fractalT or 0
    love.graphics.setColor(0.05, 0.0, 0.09, 1)
    love.graphics.rectangle("fill", 0, 0, LW, LH)
    local cx, cy = LW / 2, LH / 2
    -- nested, counter-rotating self-similar polygons (the fractal "throat")
    for layer = 1, 11 do
        local f = layer / 11
        local sides = 3 + (layer % 5)
        local rr = (30 + layer * 64) * (1 + 0.06 * math.sin(t * 1.4 + layer))
        local rot = t * (0.18 + layer * 0.07) * (layer % 2 == 0 and -1 or 1)
        local pulse = 0.5 + 0.5 * math.sin(t * 2 + layer * 0.7)
        love.graphics.setColor(0.35 + 0.3 * pulse, 0.06, 0.45 + 0.3 * (1 - pulse), 0.10 + 0.05 * pulse)
        love.graphics.setLineWidth(2)
        local pts = {}
        for i = 0, sides - 1 do
            local a = rot + i / sides * math.pi * 2
            pts[#pts + 1] = cx + math.cos(a) * rr
            pts[#pts + 1] = cy + math.sin(a) * rr
        end
        love.graphics.polygon("line", pts)
    end
    -- recursive fractal branches radiating from the centre, breathing in time
    local function branch(x, y, ang, len, depth)
        if depth <= 0 or len < 6 then return end
        local wob = math.sin(t * 1.6 + depth + x * 0.01) * 0.5
        local x2 = x + math.cos(ang) * len
        local y2 = y + math.sin(ang) * len
        love.graphics.setColor(0.5, 0.12, 0.7, 0.06 + depth * 0.03)
        love.graphics.setLineWidth(depth * 0.6)
        love.graphics.line(x, y, x2, y2)
        branch(x2, y2, ang - 0.5 + wob, len * 0.66, depth - 1)
        branch(x2, y2, ang + 0.5 + wob, len * 0.66, depth - 1)
    end
    for i = 1, 6 do
        branch(cx, cy, t * 0.3 + i / 6 * math.pi * 2, 150, 5)
    end
    -- the central singularity dot-spiral
    for i = 1, 16 do
        local ff = 1 - i / 16
        local tw = t * 0.9 + i * 0.35
        love.graphics.setColor(0.4 * ff, 0.04, 0.55 * ff, ff * 0.7)
        love.graphics.circle("fill", cx + math.cos(tw) * (4 + i * 1.6) * ff, cy + math.sin(tw) * (4 + i * 1.6) * ff, 3 * ff + 0.5)
    end
end

-- The TERROR victory screen: continue into the fractalspace, or take the win.
function Game:drawVictoryChoice()
    love.graphics.setColor(0, 0, 0.01, 0.82)
    love.graphics.rectangle("fill", 0, 0, LW, LH)
    love.graphics.setFont(self.fontBig or love.graphics.getFont())
    love.graphics.setColor(P.magenta or P.purple)
    love.graphics.printf("THE ELDRITCH SQUID FALLS", 0, LH / 2 - 170, LW, "center")
    love.graphics.setFont(self.fontNormal or love.graphics.getFont())
    love.graphics.setColor(P.text)
    love.graphics.printf("You freed the others. The run is won — your rewards are banked.",
        0, LH / 2 - 110, LW, "center")
    love.graphics.setColor(P.textDim)
    love.graphics.printf("But the trench keeps falling. Something vast still waits in the fractalspace below.",
        0, LH / 2 - 80, LW, "center")
    local b = self:victoryButtonRects()
    local mx, my = self._mx or -1, self._my or -1
    local function btn(r, label, sub, col)
        local hot = U.inRect(mx, my, r.x, r.y, r.w, r.h)
        love.graphics.setColor(col[1], col[2], col[3], hot and 0.5 or 0.28)
        love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 8)
        love.graphics.setColor(col[1], col[2], col[3], 1)
        love.graphics.setLineWidth(2); love.graphics.rectangle("line", r.x, r.y, r.w, r.h, 8)
        love.graphics.setColor(P.text)
        love.graphics.printf(label, r.x, r.y + 12, r.w, "center")
        love.graphics.setColor(P.textDim)
        love.graphics.printf(sub, r.x, r.y + 38, r.w, "center")
    end
    btn(b.cont, "CONTINUE RUN", "descend into the fractalspace", P.magenta or P.purple)
    btn(b.exit, "EXIT", "take the victory", P.aqua or P.cyan)
end

function Game:drawChurglyDialogue()
    local elapsed = (self.dialogueLen or 7) - (self.churgly.introT or 0)
    local per = (self.dialogueLen or 7) / #self.dialogue
    local idx = U.clamp(math.floor(elapsed / per) + 1, 1, #self.dialogue)
    local line = self.dialogue[idx]
    love.graphics.setColor(0, 0, 0, 0.72)
    love.graphics.rectangle("fill", LW * 0.08, LH - 150, LW * 0.84, 86, 8)
    love.graphics.setColor(0.85, 0.3, 1.0, 1)
    love.graphics.setLineWidth(2); love.graphics.rectangle("line", LW * 0.08, LH - 150, LW * 0.84, 86, 8)
    love.graphics.setColor(0.95, 0.85, 1.0)
    love.graphics.printf(line, LW * 0.1, LH - 124, LW * 0.8, "center")
end

-- a custom-campaign story card between depths (configurable text)
function Game:drawTitleCard()
    -- backdrop: a hint of the coming depth (darker the foggier it is), or a plain
    -- blank void when the next node is another title / the end.
    local f = self.titleBgFog
    if f then
        love.graphics.setColor(0, 0.03, 0.06, 1); love.graphics.rectangle("fill", 0, 0, LW, LH)
        love.graphics.setColor(0, 0, 0.01, 0.45 + 0.5 * f); love.graphics.rectangle("fill", 0, 0, LW, LH)
    else
        love.graphics.setColor(0, 0, 0.01, 0.95); love.graphics.rectangle("fill", 0, 0, LW, LH)
    end
    local p = 1 - self.phaseTimer / (self.titleDur or 5.5)
    love.graphics.setFont(self.fontBig or love.graphics.getFont())
    love.graphics.setColor(P.aqua[1], P.aqua[2], P.aqua[3], math.min(1, p * 3))
    love.graphics.printf(self.titleText or "", LW * 0.12, LH / 2 - 80, LW * 0.76, "center")
end

function Game:drawCutscene()
    love.graphics.setColor(0, 0, 0, 0.92)
    love.graphics.rectangle("fill", 0, 0, LW, LH)
    local p = 1 - self.phaseTimer / 6.0
    love.graphics.setColor(P.red[1], P.red[2], P.red[3], 0.8)
    love.graphics.setFont(self.fontBig or love.graphics.getFont())
    love.graphics.printf("THE MAW WAS ONLY A GATE.", 0, LH / 2 - 110, LW, "center")
    love.graphics.setFont(self.fontNormal or love.graphics.getFont())
    love.graphics.setColor(P.text[1], P.text[2], P.text[3], math.min(1, p * 2))
    local lines = {
        "At the Challenger Deep — Site: Acheron — it kept its gate.",
        "Now the gate yawns open. Something vast inhales,",
        "and drags you below the Hadal line into the unknown,",
        "deeper than any trench should go.",
        "",
        "Here the water is solid black. Here, things wait.",
    }
    for i, l in ipairs(lines) do
        love.graphics.printf(l, 0, LH / 2 - 50 + i * 26, LW, "center")
    end
    -- being pulled down: faint descending streaks
    love.graphics.setColor(0.5, 0.2, 0.3, 0.3)
    for i = 1, 20 do
        local x = (i / 20) * LW
        local y = ((self.time * 200 + i * 80) % LH)
        love.graphics.rectangle("fill", x, y, 2, 40)
    end
end

function Game:drawReveal()
    -- somber: the squids you came to save, caged in the dark
    love.graphics.setColor(0, 0, 0.01, 0.45)
    love.graphics.rectangle("fill", 0, 0, LW, LH)
    love.graphics.setColor(P.aqua)
    love.graphics.setFont(self.fontBig or love.graphics.getFont())
    love.graphics.printf("THE OTHERS", 0, 90, LW, "center")
    love.graphics.setFont(self.fontNormal or love.graphics.getFont())
    love.graphics.setColor(P.textDim)
    love.graphics.printf("You found them. Caged in the hollow... and you are trapped here too.",
        0, 150, LW, "center")
end

function Game:bar(x, y, w, h, frac, color, label, val)
    love.graphics.setColor(P.abyss[1], P.abyss[2], P.abyss[3], 0.8)
    love.graphics.rectangle("fill", x - 2, y - 2, w + 4, h + 4, 4)
    love.graphics.setColor(P.deep)
    love.graphics.rectangle("fill", x, y, w, h, 3)
    love.graphics.setColor(color)
    love.graphics.rectangle("fill", x, y, w * U.clamp(frac, 0, 1), h, 3)
    love.graphics.setColor(P.text)
    love.graphics.print(label, x + 6, y + h / 2 - 8)
    if val then
        love.graphics.printf(val, x, y + h / 2 - 8, w - 6, "right")
    end
end

-- Soft red (or any color) vignette: darkens the screen edges, eased toward
-- the centre. Used while a parasite is latched and draining you.
function Game:drawVignette(col, alpha)
    local steps = 40
    local bandY, bandX = LH * 0.30, LW * 0.22
    for i = 0, steps - 1 do
        local f = (1 - i / steps); f = f * f
        love.graphics.setColor(col[1], col[2], col[3], alpha * f)
        local hY, hX = bandY / steps + 1, bandX / steps + 1
        local y, x = (i / steps) * bandY, (i / steps) * bandX
        love.graphics.rectangle("fill", 0, y, LW, hY)              -- top
        love.graphics.rectangle("fill", 0, LH - y - hY, LW, hY)    -- bottom
        love.graphics.rectangle("fill", x, 0, hX, LH)              -- left
        love.graphics.rectangle("fill", LW - x - hX, 0, hX, LH)    -- right
    end
end

-- Boss health bars, stacked. Multiple bosses can be alive at once (custom
-- campaigns can place several in one wave); we show at most 3, prioritising the
-- ones CLOSEST to dying (least health on top), so a big pack doesn't wall off
-- the screen. Each bar carries that boss's own (possibly custom) name.
function Game:drawBossBars()
    local bosses = {}
    for _, e in ipairs(self.enemies) do
        if e.boss and not e.dead and (e.hp or 0) > 0 then bosses[#bosses + 1] = e end
    end
    if #bosses == 0 then return end
    table.sort(bosses, function(a, b)
        return (a.hp / a.maxHp) < (b.hp / b.maxHp)   -- least health first (on top)
    end)
    local w, h = 360, 10
    local bx = self.arena.x + self.arena.w / 2 - w / 2
    local shown = math.min(3, #bosses)
    for i = 1, shown do
        local e = bosses[i]
        local by = self.arena.y + 16 + (i - 1) * 30
        U.setColor(P.abyss, 0.8); love.graphics.rectangle("fill", bx - 2, by - 2, w + 4, h + 4, 4)
        U.setColor(P.deep); love.graphics.rectangle("fill", bx, by, w, h, 3)
        U.setColor(e.enraged and P.red or e.glow)
        love.graphics.rectangle("fill", bx, by, w * U.clamp(e.hp / e.maxHp, 0, 1), h, 3)
        U.setColor(P.text)
        love.graphics.setFont(self.fontSmall or love.graphics.getFont())
        love.graphics.printf(e.customName or e.type.name, bx, by - 15, w, "center")
    end
    if #bosses > shown then
        U.setColor(P.textDim)
        love.graphics.printf("+" .. (#bosses - shown) .. " more", bx, self.arena.y + 16 + shown * 30, w, "center")
    end
end

function Game:drawHUD()
    self:drawBossBars()
    -- top bar background
    love.graphics.setColor(P.abyss[1], P.abyss[2], P.abyss[3], 0.55)
    love.graphics.rectangle("fill", 0, 0, LW, 56)

    -- Shell (HP) bar — ink is no longer a resource, so it's the only bar.
    self:bar(16, 18, 280, 22, self.player.hp / self.player.maxHp, P.coral, "SHELL", math.ceil(self.player.hp))

    if self.god then
        love.graphics.setColor(P.lime)
        love.graphics.printf("GOD MODE (F8)", 0, 44, LW, "center")
    end
    -- center: depth + wave
    love.graphics.setColor(P.text)
    local depthText = "DEPTH " .. self.depth .. "  ·  " .. (self:depthName(self.depth) or "")
    love.graphics.printf(depthText, LW / 2 - 240, 8, 480, "center")
    local waveText
    if self.bossAlive then waveText = "BOSS"
    elseif self.bossPending then waveText = "BOSS INCOMING"
    else waveText = "Wave " .. math.max(1, self.wave) .. " / " .. self.waveCount end
    love.graphics.setColor(P.textDim)
    love.graphics.printf(waveText, LW / 2 - 240, 30, 480, "center")

    -- right: things (white cube + count), score, combo
    local fnt = love.graphics.getFont()
    local cntTxt = U.commafy(self.collected)
    local cntW = fnt:getWidth(cntTxt)
    love.graphics.setColor(P.white)
    love.graphics.print(cntTxt, LW - 20 - cntW, 8)
    U.drawThing(LW - 20 - cntW - 14, 8 + fnt:getHeight() / 2, 8)
    love.graphics.setColor(P.textDim)
    love.graphics.printf("Score " .. U.commafy(self.score), LW - 420, 30, 400, "right")
    if self.combo > 1 then
        love.graphics.setColor(P.magenta[1], P.magenta[2], P.magenta[3], U.clamp(self.comboTimer / 2.6, 0.3, 1))
        love.graphics.printf(self.combo .. "x COMBO", LW - 420, 30, 200, "left")
    end

    -- modifier pills (bottom-left) — width measured from the actual font
    local fnt = love.graphics.getFont()
    local px = 16
    for _, id in ipairs(self.modIds) do
        local m = Modifiers.byId[id]
        if m then
            local w = fnt:getWidth(m.name) + 20
            love.graphics.setColor(m.color[1], m.color[2], m.color[3], 0.85)
            love.graphics.rectangle("fill", px, LH - 28, w, 20, 10)
            love.graphics.setColor(0, 0, 0, 0.85)
            love.graphics.print(m.name, px + 10, LH - 27)
            px = px + w + 8
        end
    end

    -- dash cooldown indicator (near player handled simply at bottom-right)
    local dcd = 1 - self.player.dashTimer / self.player.dashCooldown
    love.graphics.setColor(P.textFaint)
    love.graphics.printf("DASH", LW - 120, LH - 30, 60, "right")
    love.graphics.setColor(dcd >= 1 and P.teal or P.textFaint)
    love.graphics.rectangle("fill", LW - 56, LH - 28, 40 * U.clamp(dcd, 0, 1), 12, 3)
    love.graphics.setColor(P.textFaint); love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", LW - 56, LH - 28, 40, 12, 3)
end

function Game:drawUpgrade()
    love.graphics.setColor(0, 0, 0.02, 0.72)
    love.graphics.rectangle("fill", 0, 0, LW, LH)
    love.graphics.setColor(P.cyan)
    love.graphics.printf("CHOOSE A MUTATION", 0, 90, LW, "center")
    love.graphics.setColor(P.textDim)
    love.graphics.printf("Depth " .. self.depth .. " cleared  ·  click or press 1 / 2 / 3", 0, 120, LW, "center")

    local rects = self:upgradeCardRects()
    local mx, my = love.mouse.getX(), love.mouse.getY()
    for i, up in ipairs(self.offered or {}) do
        local r = rects[i]
        local rc = rarityColor[up.rarity] or P.textDim
        love.graphics.setColor(P.panel[1], P.panel[2], P.panel[3], 0.96)
        love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 12)
        love.graphics.setColor(rc[1], rc[2], rc[3], 0.9)
        love.graphics.setLineWidth(3)
        love.graphics.rectangle("line", r.x, r.y, r.w, r.h, 12)
        love.graphics.setColor(rc)
        love.graphics.printf(string.upper(up.rarity), r.x, r.y + 18, r.w, "center")
        love.graphics.setColor(P.text)
        love.graphics.printf(up.name, r.x + 16, r.y + 60, r.w - 32, "center")
        love.graphics.setColor(P.textDim)
        love.graphics.printf(up.desc, r.x + 22, r.y + 140, r.w - 44, "center")
        love.graphics.setColor(rc[1], rc[2], rc[3], 0.8)
        love.graphics.printf("[ " .. i .. " ]", r.x, r.y + r.h - 48, r.w, "center")
        -- RECOMMENDED tag on the guaranteed pre-Maw Vampire Squid
        if self.recommended and up.id == self.recommended then
            local bw = 168
            love.graphics.setColor(P.teal[1], P.teal[2], P.teal[3], 0.92)
            love.graphics.rectangle("fill", r.x + r.w / 2 - bw / 2, r.y - 16, bw, 28, 6)
            love.graphics.setColor(0, 0.05, 0.05)
            love.graphics.printf("RECOMMENDED", r.x + r.w / 2 - bw / 2, r.y - 10, bw, "center")
        end
    end
end

function Game:drawPause()
    love.graphics.setColor(0, 0, 0.02, 0.78)
    love.graphics.rectangle("fill", 0, 0, LW, LH)
    love.graphics.setColor(P.cyan)
    love.graphics.printf("PAUSED", 0, LH / 2 - 80, LW, "center")
    love.graphics.setColor(P.text)
    love.graphics.printf("ESC  —  Resume", 0, LH / 2 - 10, LW, "center")
    love.graphics.setColor(P.coral)
    love.graphics.printf("Q  —  Abandon run (keep what you collected)", 0, LH / 2 + 24, LW, "center")
end

function Game:setFonts(big, normal) self.fontBig = big; self.fontNormal = normal end

return Game
