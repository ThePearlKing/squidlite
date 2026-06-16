-- Squidlite — a bioluminescent deep-sea roguelite. You are the last glowing
-- squid, descending the trench to face the Maw.
--
-- main.lua is the shell: it owns the logical 1280x720 coordinate space and
-- renders it with LETTERBOXING (uniform scale + black bars, never stretched),
-- routes input, and switches between the UI (menus) and an active Game run.

local Save     = require("src.save")
local Audio    = require("src.audio")
local UI       = require("src.ui")
local Game     = require("src.game")
local SecretFX = require("src.secretfx")
local Log      = require("src.debuglog")
local U        = require("src.util")

local LW, LH = 1280, 720

local App = {
    state = "ui",        -- "ui" | "playing"
    game = nil,
    lastResult = nil,
    scale = 1, offX = 0, offY = 0,
    mx = 0, my = 0,      -- mouse in logical coordinates
    toasts = {},         -- achievement unlock popups
    debug = false,       -- F9 console
    version = "1.1.3",   -- shown on the title screen; bump when asked to "update"
}

----------------------------------------------------------------------
-- Super Secret Settings post-process shader
----------------------------------------------------------------------
local SECRET_SHADER = [[
extern number time;
extern vec2  texsize;
extern number fx[16];

vec3 hueShift(vec3 c, number a) {
    const vec3 k = vec3(0.57735);
    number cs = cos(a); number sn = sin(a);
    return c*cs + cross(k,c)*sn + k*dot(k,c)*(1.0-cs);
}

vec4 effect(vec4 col, Image tx, vec2 tc, vec2 sc) {
    vec2 uv = tc;
    if (fx[10] > 0.5) uv.x = 1.0 - uv.x;                 // mirror
    if (fx[11] > 0.5) uv.y = 1.0 - uv.y;                 // upside down
    if (fx[7]  > 0.5) {                                  // wobble (seasick)
        uv.x += sin(uv.y*12.0 + time*3.0) * 0.012;
        uv.y += cos(uv.x*10.0 + time*2.5) * 0.012;
    }
    if (fx[5]  > 0.5) {                                  // pixelate
        vec2 px = vec2(96.0, 54.0);
        uv = (floor(uv*px) + 0.5) / px;
    }
    vec4 c;
    if (fx[13] > 0.5) {                                  // chromatic split
        number o = 0.005;
        c.r = Texel(tx, uv + vec2(o,0.0)).r;
        c.g = Texel(tx, uv).g;
        c.b = Texel(tx, uv - vec2(o,0.0)).b;
        c.a = 1.0;
    } else {
        c = Texel(tx, uv);
    }
    if (fx[8]  > 0.5) c.rgb += c.rgb*c.rgb*c.rgb*0.9;     // bloom-ish
    if (fx[0]  > 0.5) c.rgb = 1.0 - c.rgb;               // invert
    number l = dot(c.rgb, vec3(0.299,0.587,0.114));
    if (fx[1]  > 0.5) c.rgb = vec3(l);                   // grayscale
    if (fx[2]  > 0.5) c.rgb = vec3(l)*vec3(1.07,0.78,0.52); // sepia
    if (fx[12] > 0.5) c.rgb = vec3(l*0.15, l*1.3, l*0.2);   // night vision
    if (fx[3]  > 0.5) c.rgb = hueShift(c.rgb, time*0.8);    // rainbow
    if (fx[4]  > 0.5) {                                  // thermal
        c.rgb = vec3(smoothstep(0.2,0.75,l),
                     smoothstep(0.45,0.95,l),
                     smoothstep(0.0,0.3,l)*(1.0-smoothstep(0.3,0.65,l)));
    }
    if (fx[9]  > 0.5) c.rgb = mix(c.rgb, c.rgb*vec3(1.15,0.7,1.2)+vec3(0.12,0.0,0.16), 0.6); // vaporwave
    if (fx[6]  > 0.5) {                                  // CRT
        number scan = 0.82 + 0.18*sin(tc.y*texsize.y*3.14159);
        c.rgb *= scan;
        number vig = smoothstep(0.0,0.35, 0.5-abs(tc.x-0.5)) * smoothstep(0.0,0.35, 0.5-abs(tc.y-0.5));
        c.rgb *= 0.55 + 0.45*vig;
    }
    return c * col;
}
]]

local secretShader, secretCanvas
local fxArray = {}
for i = 1, 16 do fxArray[i] = 0 end

-- true if any secret filter is enabled
function App.secretActive()
    local sec = App.save and App.save.settings.secret
    if not sec then return false end
    for _, e in ipairs(SecretFX) do if sec[e.id] then return true end end
    return false
end

----------------------------------------------------------------------
-- letterbox scaling
----------------------------------------------------------------------
local function updateScale()
    local ww, wh = love.graphics.getDimensions()
    App.scale = math.min(ww / LW, wh / LH)
    App.offX = math.floor((ww - LW * App.scale) / 2)
    App.offY = math.floor((wh - LH * App.scale) / 2)
end

local function toLogical(sx, sy)
    return (sx - App.offX) / App.scale, (sy - App.offY) / App.scale
end

----------------------------------------------------------------------
-- fonts
----------------------------------------------------------------------
local Fonts = {}
local function loadFonts()
    Fonts.small  = love.graphics.newFont(13)
    Fonts.normal = love.graphics.newFont(17)
    Fonts.medium = love.graphics.newFont(22)
    Fonts.big    = love.graphics.newFont(34)
    Fonts.huge   = love.graphics.newFont(64)
    for _, f in pairs(Fonts) do f:setFilter("linear", "linear") end
    love.graphics.setFont(Fonts.normal)
end
App.fonts = Fonts

----------------------------------------------------------------------
-- achievement toasts
----------------------------------------------------------------------
function App.checkAchievements()
    local Ach = require("src.achievements")
    local newly = Ach.check(App.save)
    for _, a in ipairs(newly) do
        App.toasts[#App.toasts + 1] = { a = a, t = 5 }
        Audio.play("upgrade", 0.8)
    end
    if #newly > 0 then Save.flush() end
end

function App.fireAchievement(id)
    local Ach = require("src.achievements")
    if Ach.fire(App.save, id) then
        App.toasts[#App.toasts + 1] = { a = Ach.byId[id], t = 5 }
        Audio.play("upgrade", 0.8)
        Save.flush()
    end
end

----------------------------------------------------------------------
-- run lifecycle
----------------------------------------------------------------------
function App.startRun(modIds, difficulty)
    App.game = Game.new(App.save, {
        modIds = modIds,
        difficulty = difficulty,
        onEnd = function(result) App.finishRun(result) end,
    })
    App.game:setFonts(Fonts.big, Fonts.normal)
    App.state = "playing"
    Audio.playMusic(App.save.musicTheme)
    Log.add(("run start · mods=%d · x%.2f payout"):format(#modIds, App.game.mods.pointMult))
end

-- Play a player-built custom campaign. `startNode` is a NODE index (title or
-- depth) so the editor's "Play Here" can begin on any node — including a title.
function App.startCustomRun(campaign, startNode, fromEditor)
    -- remember if this was launched from the editor so a test run returns there
    -- (preserving unsaved edits) instead of dumping to the run-end screen.
    App.customFromEditor = fromEditor or false
    App.lastCustomCampaign = campaign            -- for "RESTART CAMPAIGN" on the death screen
    App.game = Game.new(App.save, {
        modIds = {}, difficulty = "normal", campaign = campaign,
        onEnd = function(result) App.finishRun(result) end,
    })
    App.game:setFonts(Fonts.big, Fonts.normal)
    Audio.playMusic(App.save.musicTheme)        -- default; enterDepth overrides per-depth (e.g. Hadal)
    local n = math.max(1, math.min(startNode or 1, #App.game.cNodes))
    App.game:advanceCampaign(n)                 -- walk in from the chosen node (title or depth)
    App.state = "playing"
    Log.add("custom campaign: " .. (campaign.name or "?") .. " @ depth " .. App.game.depth)
end

function App.finishRun(result)
    -- TRUE-END resolution (Churgly'nth). The primary win was already banked at
    -- the continue screen, so this only carries the secondary reward.
    if result.churgly then
        if result.churglyWon then
            App.save.things = App.save.things + (result.payout or 0)
            App.save.stats.totalThingsEarned = App.save.stats.totalThingsEarned + (result.payout or 0)
            App.fireAchievement("churgly_slain")    -- unlocks the 3 true-end cosmetics
            App.checkAchievements()
        end
        Save.flush()
        App.lastResult = result
        App.state = "ui"
        App.ui:setScreen("runend")
        Audio.playMusic(App.save.musicTheme)
        Log.add(result.churglyWon and "TRUE END — Churgly'nth slain" or "consumed by the Churgly'nth")
        return
    end

    -- CUSTOM CAMPAIGNS are a sandbox: winning or dying there banks NO real
    -- progress — no wins, runs, kills, stats, achievements, bestiary, or
    -- $Things. Just show the run-end screen and return to the menu.
    if result.custom then
        App.lastResult = result
        App.state = "ui"
        -- launched from the editor? go straight back to it with edits intact —
        -- never strand unsaved work behind the run-end screen.
        if App.customFromEditor and App.ui.editCamp then
            App.ui:setScreen("editor")
        else
            App.ui:setScreen("runend")
        end
        Audio.playMusic(App.save.musicTheme)
        Log.add(("custom campaign %s · %s at depth %d (no progress banked)")
            :format(result.campaignName or "?", result.won and "won" or "ended", result.depth))
        return
    end

    -- GOO-GOO BABY still earns $Things (its x0.35 payout) but grants NO
    -- achievements and no progression stats. Bank the cash, then bail.
    local googoo = (result.difficulty == "googoobaby")
    if googoo then
        App.save.things = App.save.things + result.payout
        Save.flush()
        App.lastResult = result
        App.state = "ui"
        App.ui:setScreen("runend")
        Audio.playMusic(App.save.musicTheme)
        Log.add(("GOO-GOO BABY run ended · +$%d · no achievements"):format(result.payout))
        return
    end

    -- bank the run into the save + lifetime stats
    local s = App.save.stats
    App.save.things = App.save.things + result.payout
    s.totalRuns = s.totalRuns + 1
    s.totalKills = s.totalKills + result.kills
    s.totalThingsEarned = s.totalThingsEarned + result.payout
    s.bestDepth = math.max(s.bestDepth, result.depth)
    s.bestScore = math.max(s.bestScore, result.score)
    s.bestCombo = math.max(s.bestCombo, result.bestCombo or 0)
    s.bossKills = (s.bossKills or 0) + (result.bossKills or 0)
    s.maxMods = math.max(s.maxMods, result.modCount or 0)
    if result.cleanDepth then s.noHitDepth = math.max(s.noHitDepth or 0, 1) end
    -- bestiary progress (lifetime defeats per type; leviathan = survives)
    App.save.bestiary = App.save.bestiary or {}
    for id, c in pairs(result.killsByType or {}) do
        App.save.bestiary[id] = (App.save.bestiary[id] or 0) + c
    end
    if (result.leviSurvived or 0) > 0 then
        App.save.bestiary.leviathan = (App.save.bestiary.leviathan or 0) + result.leviSurvived
    end
    if result.won and not googoo then
        s.totalWins = s.totalWins + 1
        if result.flawless then s.noHitWins = s.noHitWins + 1 end
        if result.pointMult < 1 then s.curseWins = s.curseWins + 1 end
        if result.time and result.time < 540 then App.fireAchievement("speedrun") end
        if result.difficulty == "terror" then App.fireAchievement("terror_win") end
        if not result.usedLifesteal then App.fireAchievement("no_lifesteal_win") end
    elseif not result.won then
        s.deaths = s.deaths + 1
    end
    Save.flush()
    if not googoo then App.checkAchievements() end    -- GOO-GOO BABY earns no achievements

    -- "Continue Run" was chosen on the victory screen: the primary win is banked
    -- but the run keeps going (into the fractalspace). Don't surface the UI yet.
    if result.keepPlaying then return end

    App.lastResult = result
    App.state = "ui"
    App.ui:setScreen("runend")
    Audio.playMusic(App.save.musicTheme)    -- back to the normal soundtrack (out of the Hollow)
    Log.add((result.won and "WON" or "lost") .. (" at depth %d · +$%d · kills %d")
        :format(result.depth, result.payout, result.kills))
end

----------------------------------------------------------------------
-- LÖVE callbacks
----------------------------------------------------------------------
function love.load()
    love.graphics.setDefaultFilter("linear", "linear")
    loadFonts()
    -- Dev modes use a throwaway save so they never touch real progress.
    local devMode = false
    for _, a in ipairs(arg or {}) do
        if a == "selftest" or a == "shot" or a == "audio" or a == "savetest" then devMode = true end
    end
    if devMode then Save.useTestFile() end
    App.save = Save.load()
    Audio.init(App.save)
    if App.save.settings.fullscreen then
        love.window.setFullscreen(true, "desktop")
    end
    updateScale()
    -- secret-settings post-process pipeline (best-effort; ok if shaders absent)
    pcall(function()
        secretShader = love.graphics.newShader(SECRET_SHADER)
        secretCanvas = love.graphics.newCanvas(LW, LH)
    end)
    App.ui = UI.new(App)
    -- first-time players see the story intro
    App.ui:setScreen(App.save.seenIntro and "menu" or "story")
    Audio.playMusic(App.save.musicTheme)
    Log.add("Squidlite booted. LOVE " .. table.concat({ love.getVersion() }, "."))

    -- Headless smoke test: `love . selftest` exercises every screen and the
    -- whole run lifecycle, then reports and quits. Not reached in normal play.
    local testmode, shotmode = false, false
    for _, a in ipairs(arg or {}) do
        if a == "selftest" then testmode = true end
        if a == "shot" then shotmode = true end
    end
    if testmode then App.selfTest() end
    if shotmode then App.screenshots() end
    for _, a in ipairs(arg or {}) do if a == "audio" then App.analyzeAudio() end end
    for _, a in ipairs(arg or {}) do if a == "savetest" then App.saveTest() end end
    for _, a in ipairs(arg or {}) do if a == "balance" then App.balanceCheck() end end
end

-- Compute time-to-kill across representative build power levels so the
-- difficulty curve can be checked numerically (not by feel).
function App.balanceCheck()
    local function power(dmg, fr, proj, crit)
        local d = dmg * fr * (1 + (proj - 1) * 0.45) * (1 + crit * 1)
        return math.min(20, math.max(1, d / 130)), d
    end
    -- {label, inkDmg, fireRate, projectiles, critChance, depth, bossBase}
    local rows = {
        { "Fresh squid (d1)",        20,  6.5, 1, 0.05, 1 },
        { "Light build (d3)",        28,  7.5, 1, 0.05, 3 },
        { "Warden fight (d4)",       32,  8.0, 2, 0.05, 4, 1600 },
        { "Mid build (d6)",          38,  9.0, 2, 0.10, 6 },
        { "MAW fight (d8)",          48, 11.0, 3, 0.15, 8, 2700 },
        { "Strong build (d10)",      58, 13.0, 3, 0.20, 10 },
        { "ELDRITCH deathray (d13)", 80, 17.0, 4, 0.25, 13, 3800 },
    }
    print("=== BALANCE: time-to-kill (s) ===")
    for _, r in ipairs(rows) do
        local p, dps = power(r[2], r[3], r[4], r[5])
        local depth = r[6]
        local terrorHP = 120 * (1 + (depth - 1) * 0.14) * (1 + (p - 1) * 0.85)
        local terrorTTK = terrorHP / dps
        local line = ("%-26s power=%4.1f dps=%5.0f  terror=%4.1fs"):format(r[1], p, dps, terrorTTK)
        if r[7] then
            local bossHP = r[7] * (1 + (p - 1) * 0.6)
            line = line .. ("  BOSS=%5.0fhp -> %4.1fs"):format(bossHP, bossHP / dps)
        end
        print(line)
    end
    love.event.quit()
end

-- Proves persistence round-trips: write values, reload from disk, compare.
function App.saveTest()
    local before = App.save.things
    App.save.things = before + 1234
    App.save.owned["coral"] = true
    App.save.skin = "violet"
    App.save.stats.totalWins = (App.save.stats.totalWins or 0) + 3
    Save.flush()
    local re = Save.load()        -- re-reads the file from disk
    local ok = re.things == before + 1234 and re.owned.coral == true
        and re.skin == "violet" and re.stats.totalWins >= 3
    print(("SAVETEST %s  things=%d owned.coral=%s skin=%s wins=%d")
        :format(ok and "OK" or "FAIL", re.things, tostring(re.owned.coral), re.skin, re.stats.totalWins))
    love.event.quit()
end

-- Prints a coarse energy envelope of a theme so we can confirm it actually has
-- rhythmic drum punch (peaks on the beat) instead of being a flat drone.
function App.analyzeAudio()
    for _, id in ipairs({ "deepdrive", "abyssal" }) do
        local data, theme = Audio.buildData(id)
        local n = data:getSampleCount()
        local steps = 32
        local peak, rms = 0, 0
        local bars = {}
        for s = 0, steps - 1 do
            local a, b = math.floor(s / steps * n), math.floor((s + 1) / steps * n)
            local mx = 0
            for i = a, b - 1 do
                local v = math.abs(data:getSample(i))
                if v > mx then mx = v end
                peak = math.max(peak, v); rms = rms + v * v
            end
            bars[#bars + 1] = mx
        end
        rms = math.sqrt(rms / n)
        local line = ""
        for _, v in ipairs(bars) do
            local h = math.floor(v * 8 + 0.5)
            line = line .. (h >= 6 and "#" or h >= 3 and "+" or h >= 1 and "." or " ")
        end
        print(("[%s] %s  bpm=%d  peak=%.2f rms=%.3f"):format(id, theme.genre, theme.spec.bpm, peak, rms))
        print("  energy |" .. line .. "|")
    end
    love.event.quit()
end

-- Render each screen to a PNG (in the save dir) for visual review.
function App.screenshots()
  local ok, err = xpcall(function()
    local canvas = love.graphics.newCanvas(LW, LH)
    local function snap(name)
        love.graphics.setCanvas({ canvas, stencil = true })
        love.graphics.clear(0, 0, 0, 1)
        App.drawLogicalContent()
        love.graphics.setCanvas()
        canvas:newImageData():encode("png", "shot_" .. name .. ".png")
    end
    App.state = "ui"
    for _, scr in ipairs({ "menu", "story", "customize", "shop", "modifiers",
                           "settings", "music", "achievements", "secret" }) do
        App.ui:setScreen(scr)
        if scr == "secret" then App.save.settings.secret = {} end
        for _ = 1, 20 do App.ui:update(0.05, 700, 360) end
        snap(scr)
    end
    -- reset-data modal (confirm stage)
    App.ui:setScreen("settings")
    App.ui.resetStage = "confirm"
    for _ = 1, 5 do App.ui:update(0.05, 0, 0) end
    snap("reset"); App.ui.resetStage = nil
    -- custom campaign list + editor
    App.ui:setScreen("campaigns"); App.ui:update(0.05, 700, 360); App.ui:draw(); snap("campaigns")
    do
        local Campaign = require("src.campaign")
        App.ui.editCamp = Campaign.example(); App.ui.editSel = 2; App.ui.scroll.editor = 0
        App.ui:setScreen("editor"); for _ = 1, 3 do App.ui:update(0.05, 700, 360) end; App.ui:draw(); snap("editor")
    end
    -- run-end
    App.lastResult = { won = true, depth = 8, depthName = "The Maw's Lair", kills = 142,
        score = 8800, collected = 96, payout = 5120, pointMult = 2.31, modCount = 3,
        flawless = true, bestCombo = 41, time = 388 }
    App.ui:setScreen("runend"); for _ = 1, 10 do App.ui:update(0.05, 0, 0) end; snap("runend")
    -- gameplay
    App.startRun({ "frenzy", "swarm" })
    local g = App.game
    g.phase = "playing"; g:startNextWave()
    for _ = 1, 160 do g:update(0.03, 760, 420) end
    App.state = "playing"; snap("game")
    -- a boss frame
    g.depth = 8; g:startDepth(); g.phase = "playing"; g.bossPending = true
    for _ = 1, 120 do g:update(0.03, 760, 420) end
    snap("boss")
    -- crab close-up: clear and place snappers (one mid-windup) around the player
    g.enemies = {}; g.bullets.list = {}; g.phase = "playing"; g.bossAlive = false; g.bossPending = false
    g.player.x, g.player.y = 640, 380
    local c1 = g:spawnEnemy("snapper", 460, 300); c1.radius = 48; c1.state = "windup"; c1.st = 0.5; c1.anim = 1.2
    local c2 = g:spawnEnemy("snapper", 840, 440); c2.radius = 44; c2.anim = 3.0
    for _ = 1, 2 do g:update(0.016, 640, 380) end
    snap("crab")
    -- lurker scene: anglers planting armed light-lures around the player
    g.enemies = {}; g.bullets.list = {}; g.player.x, g.player.y = 640, 360
    g:spawnEnemy("lurker", 360, 240); g:spawnEnemy("lurker", 920, 480)
    for _ = 1, 70 do g:update(0.03, 640, 360) end   -- let lures get planted + arm
    snap("lurker")
    -- warden close-up
    g.enemies = {}; g.bullets.list = {}; g.player.x, g.player.y = 640, 470
    g.depth = 4; g.bossDefeated = false
    local wd = g:spawnEnemy("warden", 640, 240); wd.attackCd = 0.2; wd.anim = 1.5
    for _ = 1, 3 do g:update(0.016, 640, 470) end
    snap("warden")
    -- Hadal Depths: darkness + new horrors + background monsters
    g.depth = 10; g.hadal = true; g.hadalDark = 0.78; g:spawnBgMonsters()
    g.enemies = {}; g.bullets.list = {}; g.phase = "playing"; g.bossAlive = false; g.bossPending = false
    g.player.x, g.player.y = 640, 380
    for _, id in ipairs({ "parasite", "terror", "unseen", "mine", "phantom", "wormsing" }) do
        g:spawnEnemy(id, 640 + U.rand(-180, 180), 380 + U.rand(-140, 140))
    end
    for _ = 1, 40 do g:update(0.03, 700, 420) end
    snap("hadal")
    -- leviathan flyby
    g.enemies = {}; g.bullets.list = {}; g.leviDone = 0; g.leviCap = 4
    g.player.x, g.player.y = 640, 560
    g:spawnLeviathan(); g.leviathans[1].x = 420; g.leviathans[1].dir = 1; g.leviathans[1].top = true; g.leviathans[1].band = 240
    for _ = 1, 60 do g:update(0.03, 640, 560) end
    snap("leviathan")
    -- the rare DARK-BLUE armed leviathan (cursed face + clawing arms)
    g.god = true; g.phase = "playing"
    g.player.hp = g.player.maxHp; g.player.alive = true
    g.enemies = {}; g.bullets.list = {}; g.leviathans = {}; g.player.x, g.player.y = 640, 520
    g:spawnLeviathan()
    local bl = g.leviathans[1]
    bl.blue = true; bl.fire = nil; bl.color = { 0.08, 0.12, 0.36 }; bl.glow = { 0.32, 0.5, 1.0 }
    bl.x = 520; bl.dir = 1; bl.top = true; bl.band = 280
    for _ = 1, 30 do g:update(0.03, 640, 520) end
    snap("leviathan_blue")
    -- bestiary screen (unlock a few entries for the shot)
    App.save.bestiary = { drifter = 20, snapper = 20, maw = 1, leviathan = 3 }
    App.state = "ui"; App.ui:setScreen("bestiary"); App.ui:update(0.05, 700, 300); App.ui:draw(); snap("bestiary")
    -- bestiary book portraits
    App.ui:openBook("snapper"); App.ui:cycleBookVariant(2)   -- show the Abyssal variant
    for _ = 1, 3 do App.ui:update(0.05, 700, 300) end; App.ui:draw(); snap("book_crab")
    App.ui:openBook("eldritch"); for _ = 1, 3 do App.ui:update(0.05, 700, 300) end; App.ui:draw(); snap("book_eldritch")
    App.ui:openBook("leviathan"); for _ = 1, 3 do App.ui:update(0.05, 700, 300) end; App.ui:draw(); snap("book_leviathan")
    App.ui:openBook("crawler"); for _ = 1, 3 do App.ui:update(0.05, 700, 300) end; App.ui:draw(); snap("book_crawler")
    App.ui:closeBook()
    App.state = "playing"
    -- Eldritch Squid finale + trapped squids
    g.enemies = {}; g.bullets.list = {}; g.hadalDark = 0.4
    g.depth = 11; g.revealDone = true
    g.trappedSquids = {}
    local sks = { "ember", "mossback", "violet", "coral", "toxic" }
    for i = 1, 5 do
        g.trappedSquids[#g.trappedSquids + 1] = { x = 200 + i * 170, y = 560,
            skin = require("src.cosmetics").getSkin(sks[i]), t = i }
    end
    g.leviathans = {}; g.leviDone = 99; g.hadalDark = 0   -- no leviathan flyby / dark obscuring the boss
    local el = g:spawnEnemy("eldritch", 640, 250); el.attackCd = 0.3; el.anim = 2
    for _ = 1, 6 do g:update(0.016, 640, 380); g.leviathans = {} end
    snap("eldritch")
    -- cutscene
    g.phase = "cutscene"; g.phaseTimer = 3.0
    for _ = 1, 4 do g:update(0.03, 640, 360) end
    snap("cutscene")
  end, debug.traceback)
  if ok then print("SHOTS SAVED: " .. love.filesystem.getSaveDirectory())
  else print("SHOT FAIL:\n" .. tostring(err)) end
  love.event.quit()       -- never leave a hanging error window
end

function App.selfTest()
    local ok, err = xpcall(function()
        local screens = { "menu", "story", "customize", "shop", "achievements",
                          "bestiary", "music", "settings", "modifiers" }
        for _, scr in ipairs(screens) do
            App.ui:setScreen(scr)
            for _ = 1, 3 do App.ui:update(0.016, 640, 360); App.ui:draw() end
        end
        -- bestiary book: render a living portrait for a creature, a boss, the leviathan
        App.save.bestiary = { drifter = 99, snapper = 99, lurker = 99, wormsing = 99,
            eldritch = 9, warden = 9, leviathan = 9, terror = 99 }
        App.ui:setScreen("bestiary")
        for _, id in ipairs({ "drifter", "snapper", "lurker", "wormsing", "warden", "eldritch", "leviathan" }) do
            App.ui:openBook(id)
            for _ = 1, 3 do App.ui:cycleBookVariant(1); App.ui:draw() end  -- base→elite→abyssal
            for _ = 1, 2 do App.ui:update(0.05, 700, 360); App.ui:draw() end
        end
        App.ui:closeBook()

        -- exercise customize slots + reset modal + scrolling
        App.ui:setScreen("customize")
        for _, slot in ipairs(require("src.cosmetics").SLOTS) do
            App.ui.custSlot = slot; App.ui:update(0.016, 700, 300); App.ui:draw()
        end
        App.ui:setScreen("settings"); App.ui.resetStage = "type"; App.ui.resetText = "Reset"
        App.ui:draw(); App.ui.resetStage = "confirm"; App.ui:draw(); App.ui.resetStage = nil

        -- modifier toggling
        App.ui:setScreen("modifiers")
        App.ui:toggleMod("glass"); App.ui:toggleMod("frenzy"); App.ui:toggleMod("swarm")
        App.ui:draw()

        -- run-end summary
        App.lastResult = { won = true, depth = 8, depthName = "The Maw's Lair", kills = 120,
            score = 5400, collected = 88, payout = 4210, pointMult = 2.31, modCount = 3,
            flawless = true, bestCombo = 34, time = 410 }
        App.ui:setScreen("runend"); App.ui:draw()

        -- full run on HARD (god mode so the passive test pilot survives to the end)
        App.startRun({ "glass", "frenzy", "swarm", "darkness" }, "hard")
        local g = App.game
        g.god = true
        for _ = 1, 400 do g:update(0.016, 640, 360); g:draw() end
        g:depthCleared(); g:update(0.016, 640, 360); g:draw(); g:pickUpgrade(1)
        for _ = 1, 100 do g:update(0.016, 640, 360); g:draw() end
        -- 1st Warden (depth 4): ring beat after a 2s warmup
        g.depth = 4; g:startDepth(); g.phase = "playing"; g.bossPending = true
        for _ = 1, 200 do g:update(0.016, 640, 360); g:draw() end
        for _, e in ipairs(g.enemies) do g:damageEnemy(e, 99999, e.x, e.y) end
        g:update(0.016, 640, 360); g:draw()
        -- 2nd Warden (depth 6): exercise the spinning-arm sweep
        g.depth = 6; g:startDepth(); g.phase = "playing"; g.enemies = {}
        local w2 = g:spawnEnemy("warden", 640, 360); w2.tier2 = true
        w2.armActive = true; w2.armT = 3.2; w2.armLen = 230; w2.armAngle = 0; w2.armDir = 1
        for _ = 1, 200 do g:update(0.016, 700, 400); g:draw() end
        for _, e in ipairs(g.enemies) do g:damageEnemy(e, 99999, e.x, e.y) end
        g:update(0.016, 640, 360); g:draw()
        -- the Maw (gatekeeper) → cutscene → Hadal Depths
        g.depth = 8; g:startDepth(); g.phase = "playing"; g.bossPending = true
        for _ = 1, 200 do g:update(0.05, 640, 360); g:draw() end
        for _, e in ipairs(g.enemies) do g:damageEnemy(e, 999999, e.x, e.y) end  -- kill Maw → cutscene
        for _ = 1, 220 do g:update(0.05, 640, 360); g:draw() end                  -- cutscene (6s @ clamped dt)
        assert(g.phase == "upgrade", "expected upgrade after cutscene, got " .. tostring(g.phase))
        g:pickUpgrade(1)                                                          -- enter depth 9 (Hadal)
        assert(g.hadal, "expected hadal active at depth " .. g.depth)
        -- Hadal Depths: exercise the new enemies + darkness + bg horrors
        for _ = 1, 250 do g:update(0.05, 700, 420); g:draw() end
        -- force a leviathan flyby (toxic pools, terrifying head, collision, despawn)
        g.depth = 10; g.leviDone = 0; g.leviCap = 4
        g:spawnLeviathan()
        for _ = 1, 540 do g:update(0.05, 700, 420); g:draw() end
        assert(g.leviSurvived >= 1, "leviathan never completed its flyby")
        -- jump to the final depth, trigger the trapped-squids reveal + Eldritch
        g.depth = 13; g:startDepth(); g.phase = "playing"; g.wave = g.waveCount; g.toSpawn = 0; g.bossPending = true
        g.enemies = {}    -- clear leftover passive-test enemies so the reveal can trigger
        local tries = 0
        while not (g.bossAlive and g.phase == "playing") and tries < 600 do
            g:update(0.05, 640, 360); g:draw(); tries = tries + 1
        end
        assert(g.bossAlive, "Eldritch Squid never spawned (phase=" .. tostring(g.phase) .. ")")
        for _, e in ipairs(g.enemies) do g:damageEnemy(e, 999999, e.x, e.y) end   -- slay Eldritch
        local ft = 0
        while g.phase ~= "won" and ft < 200 do g:update(0.05, 640, 360); g:draw(); ft = ft + 1 end  -- detonation finale
        assert(g.phase == "won", "expected win after Eldritch Squid, got " .. tostring(g.phase))
        -- spawn every new enemy directly to exercise AI + render
        App.startRun({}, "normal"); g = App.game; g.god = true; g.phase = "playing"; g.hadal = true
        for _, id in ipairs({ "parasite", "terror", "unseen", "mine", "brood", "phantom", "wormsing", "churgspawn", "crawler" }) do
            g:spawnEnemy(id, 700, 400)
        end
        for _ = 1, 120 do g:update(0.03, 640, 360); g:draw() end
        -- TERROR mode: red fire-breathing leviathan + parasite floor + no base regen
        App.startRun({}, "terror"); g = App.game; g.god = true; g.depth = 2; g.phase = "playing"
        assert(g.terror and g.player.regen == 0, "terror flags wrong")
        local pz = g:spawnEnemy("parasite", 700, 400); assert(pz.hp >= 480, "terror parasite hp floor failed")
        g.leviDone = 0; g.leviCap = 4; g:spawnLeviathan(); assert(g.leviathans[1].fire, "terror leviathan not a fire-breather")
        for _ = 1, 220 do g:update(0.05, 640, 360); g:draw() end
        -- TERROR end-game: side leviathans + corner arms, then continue into the
        -- fractalspace for the Churgly'nth final-final boss.
        App.startRun({}, "terror"); g = App.game; g.god = true
        g.depth = 13; g:startDepth(); g.phase = "playing"; g.wave = g.waveCount; g.toSpawn = 0; g.bossPending = true
        g.enemies = {}
        local tt2 = 0
        while not (g.bossAlive and g.phase == "playing") and tt2 < 700 do g:update(0.05, 640, 360); g:draw(); tt2 = tt2 + 1 end
        assert(g.bossAlive, "terror Eldritch never spawned (phase=" .. tostring(g.phase) .. ")")
        g:summonBossLevis(); g:spawnCornerArms()
        assert(#g.cornerArms == 4, "corner arms not spawned")
        assert(#g.leviathans >= 2, "boss leviathans not summoned")
        for _ = 1, 60 do g:update(0.03, 500, 300); g:draw() end          -- parked levis + arms
        for _, e in ipairs(g.enemies) do if e.finalBoss then g:damageEnemy(e, 9e9, e.x, e.y) end end
        local vt = 0
        while g.phase ~= "victory_choice" and vt < 200 do g:update(0.05, 640, 360); g:draw(); vt = vt + 1 end
        assert(g.phase == "victory_choice", "expected victory_choice, got " .. tostring(g.phase))
        local vb = g:victoryButtonRects()
        g:mousepressed(vb.cont.x + 5, vb.cont.y + 5, 1)                  -- "Continue Run"
        assert(g.phase == "fractal" and g.churglyMode, "continue did not enter fractalspace")
        local ct = 0
        while not (g.churgly and g.phase == "playing") and ct < 200 do g:update(0.05, 640, 360); g:draw(); ct = ct + 1 end
        assert(g.churgly, "Churgly'nth never appeared")
        for _ = 1, 8 do g:update(0.03, 640, 360); g:draw() end          -- the monologue overlay
        g.churgly.introT = 0                                            -- then skip the rest
        for _ = 1, 120 do g:update(0.03, 640, 360); g:draw() end        -- the bullet storm + render
        g:damageEnemy(g.churgly, 9e9, g.churgly.x, g.churgly.y)
        local et = 0
        while g.phase ~= "churgly_over" and et < 200 do g:update(0.05, 640, 360); g:draw(); et = et + 1 end
        assert(g.phase == "churgly_over", "expected churgly_over (true end), got " .. tostring(g.phase))
        -- build every music theme (incl. the new Hollow horror track)
        for _, th in ipairs(Audio.themes) do Audio.buildTheme(th.id) end

        -- secret settings + shader composite path + debug console
        App.state = "ui"
        App.ui:setScreen("secret")
        App.save.settings.secret.invert = true
        App.save.settings.secret.crt = true
        App.save.settings.secret.rainbow = true
        App.ui:draw()
        App.debug = true
        love.draw()       -- exercises canvas->shader composite + debug overlay
        App.save.settings.secret = {}
        love.draw()       -- non-shader path

        -- custom campaign editor + a full custom run
        local Campaign = require("src.campaign")
        App.state = "ui"; App.ui:setScreen("campaigns"); App.ui:draw()
        local ex = Campaign.example()
        App.ui.editCamp = ex; App.ui.editSel = 1; App.ui.scroll.editor = 0
        App.ui:setScreen("editor"); App.ui:draw()
        App.ui.editSel = nil; App.ui:draw()                 -- "nothing selected" + globals
        App.ui.pickerOpen = true; App.ui:draw(); App.ui.pickerOpen = false
        App.startCustomRun(ex, 1); g = App.game; g.god = true
        assert(g.campaign and #g.cDepths >= 1, "campaign did not compile")
        for _ = 1, 200 do g:update(0.05, 640, 360); g:draw() end
        App.startCustomRun(ex, 3)                           -- "Play Here" from depth 3
        for _ = 1, 80 do App.game:update(0.05, 640, 360); App.game:draw() end
    end, debug.traceback)
    if ok then print("SELFTEST OK") else print("SELFTEST FAIL:\n" .. tostring(err)) end
    love.event.quit()
end

function love.resize() updateScale() end

function love.update(dt)
    App.mx, App.my = toLogical(love.mouse.getPosition())
    App.save.stats.playTime = (App.save.stats.playTime or 0) + dt
    if App.state == "playing" and App.game then
        App.game:update(dt, App.mx, App.my)
    else
        App.ui:update(dt, App.mx, App.my)
    end
    -- toasts
    local i = 1
    while i <= #App.toasts do
        App.toasts[i].t = App.toasts[i].t - dt
        if App.toasts[i].t <= 0 then table.remove(App.toasts, i) else i = i + 1 end
    end
end

-- Draws the logical 1280x720 scene (game or menus) at the current origin.
function App.drawLogicalContent()
    if App.state == "playing" and App.game then
        App.game:draw()
    else
        App.ui:draw()
    end
end

function love.draw()
    love.graphics.clear(0, 0, 0)
    local useSecret = App.secretActive() and secretShader and secretCanvas

    if useSecret then
        -- render scene to canvas, then composite through the silly shader.
        -- stencil = true so the squid's pattern clip + Lights Out darkness
        -- (which use love.graphics.stencil) work while the canvas is active.
        love.graphics.setCanvas({ secretCanvas, stencil = true })
        love.graphics.clear(0, 0, 0, 1)
        App.drawLogicalContent()
        love.graphics.setCanvas()

        local sec = App.save.settings.secret
        for i, e in ipairs(SecretFX) do fxArray[i] = sec[e.id] and 1 or 0 end
        secretShader:send("time", App.ui and App.ui.t or 0)
        secretShader:send("texsize", { LW, LH })
        secretShader:send("fx", unpack(fxArray))
        love.graphics.setShader(secretShader)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.push()
        love.graphics.translate(App.offX, App.offY)
        love.graphics.scale(App.scale)
        love.graphics.draw(secretCanvas, 0, 0)
        love.graphics.pop()
        love.graphics.setShader()
    else
        love.graphics.push()
        love.graphics.translate(App.offX, App.offY)
        love.graphics.scale(App.scale)
        love.graphics.setScissor(App.offX, App.offY, LW * App.scale, LH * App.scale)
        App.drawLogicalContent()
        love.graphics.setScissor()
        love.graphics.pop()
    end

    -- overlays drawn crisp (no shader): toasts + debug console
    love.graphics.push()
    love.graphics.translate(App.offX, App.offY)
    love.graphics.scale(App.scale)
    App.drawToasts()
    if App.debug then App.drawDebug() end
    love.graphics.pop()
end

function App.drawDebug()
    local f = App.fonts.small
    love.graphics.setFont(f)
    local lines = {}
    lines[#lines + 1] = string.format("FPS %d   frame %.1f ms", love.timer.getFPS(), love.timer.getAverageDelta() * 1000)
    local st = love.graphics.getStats()
    lines[#lines + 1] = string.format("draws %d   canvasswitch %d   vram %.1f MB", st.drawcalls, st.canvasswitches, st.texturememory / 1048576)
    lines[#lines + 1] = string.format("lua mem %.0f KB", collectgarbage("count"))
    if App.state == "playing" and App.game then
        local g = App.game
        lines[#lines + 1] = string.format("state PLAYING  phase %s  depth %d  wave %d/%d", g.phase, g.depth, g.wave, g.waveCount)
        lines[#lines + 1] = string.format("enemies %d  bullets %d  particles %d  pickups %d",
            #g.enemies, #g.bullets.list, g.particles:count(), #g.pickups)
        lines[#lines + 1] = string.format("player hp %.0f/%.0f  dmg %.0f  fr %.1f  combo %d   god %s",
            g.player.hp, g.player.maxHp, g.player.inkDamage, g.player.fireRate, g.combo, g.god and "ON" or "off")
    else
        lines[#lines + 1] = string.format("state UI  screen %s  $Things %d", App.ui.screen, App.save.things)
    end
    lines[#lines + 1] = "secret fx: " .. (App.secretActive() and "ON" or "off")
    lines[#lines + 1] = "ADMIN: " .. (App.save.admin and "ON" or "off  —  set admin=true in the save file")

    local w, lh = 560, f:getHeight() + 3
    local textH = #lines * lh
    local btnH = 8 + 26 + 8 + (App.save.admin and (18 + 24) or 0)
    local h = textH + 16 + btnH
    love.graphics.setColor(0, 0, 0, 0.78)
    love.graphics.rectangle("fill", 8, 8, w, h, 6)
    love.graphics.setColor(0.3, 1.0, 0.5, 0.9)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", 8, 8, w, h, 6)
    for i, l in ipairs(lines) do
        love.graphics.setColor(i <= 3 and { 0.5, 1.0, 0.7 } or { 0.8, 0.9, 0.95 })
        love.graphics.print(l, 18, 14 + (i - 1) * lh)
    end

    -- interactive buttons (hit-tested in love.mousepressed via App.debugRects)
    local mx, my = toLogical(love.mouse.getPosition())
    local function dbtn(x, y, bw, bh, label, col)
        local hov = mx >= x and mx <= x + bw and my >= y and my <= y + bh
        love.graphics.setColor(col[1], col[2], col[3], hov and 0.5 or 0.22)
        love.graphics.rectangle("fill", x, y, bw, bh, 4)
        love.graphics.setColor(col[1], col[2], col[3], 1)
        love.graphics.rectangle("line", x, y, bw, bh, 4)
        love.graphics.setColor(1, 1, 1, 0.95)
        love.graphics.printf(label, x, y + bh / 2 - f:getHeight() / 2, bw, "center")
    end

    App.debugRects = { depths = {} }
    local by = 14 + textH + 6
    App.debugRects.saveDir = { x = 18, y = by, w = 260, h = 26 }
    dbtn(18, by, 260, 26, "OPEN SAVE FOLDER", { 0.4, 0.8, 1.0 })
    by = by + 34
    if App.save.admin then
        love.graphics.setColor(0.7, 0.9, 0.8, 0.9)
        love.graphics.print("SKIP TO DEPTH:", 18, by)
        by = by + 18
        for d = 1, 13 do
            local bx = 18 + (d - 1) * 40
            App.debugRects.depths[d] = { x = bx, y = by, w = 36, h = 24 }
            local cur = (App.state == "playing" and App.game and App.game.depth == d)
            dbtn(bx, by, 36, 24, tostring(d), cur and { 1.0, 0.85, 0.3 } or { 0.4, 1.0, 0.6 })
        end
    end
    love.graphics.setFont(App.fonts.normal)
end

-- Admin depth-skip: restart the run at the chosen depth (F9 selector).
function App.debugSkipToDepth(d)
    if not App.save.admin or App.state ~= "playing" or not App.game then return end
    local g = App.game
    d = math.max(1, math.min(13, d))
    g.bullets:clearTeam("enemy"); g.bullets:clearTeam("player")
    g.enemies = {}; g.leviathans = {}; g.cornerArms = {}; g.hazards = {}
    g.churglyMode = false; g.churgly = nil
    g.bossAlive = false; g.bossPending = false; g.bossDefeated = false
    g.depth = d
    g:startDepth()
    Log.add("debug: skipped to depth " .. d)
end

local P = require("src.palette")
function App.drawToasts()
    local y = 70
    for _, toast in ipairs(App.toasts) do
        local a = math.min(1, toast.t)
        local w = 420
        local x = LW / 2 - w / 2
        love.graphics.setColor(P.rarity.special[1], P.rarity.special[2], P.rarity.special[3], 0.9 * a)
        love.graphics.rectangle("fill", x, y, w, 54, 8)
        love.graphics.setColor(0, 0, 0, 0.85 * a)
        love.graphics.setFont(App.fonts.medium)
        love.graphics.printf("ACHIEVEMENT", x, y + 6, w, "center")
        love.graphics.setFont(App.fonts.normal)
        love.graphics.printf(toast.a.name, x, y + 30, w, "center")
        y = y + 62
    end
    love.graphics.setFont(App.fonts.normal)
end

function love.mousepressed(sx, sy, button)
    local mx, my = toLogical(sx, sy)
    -- F9 debug overlay buttons take clicks first
    if App.debug and App.debugRects then
        local function hit(r) return r and mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h end
        if hit(App.debugRects.saveDir) then
            love.system.openURL("file://" .. love.filesystem.getSaveDirectory())
            return
        end
        for d, r in pairs(App.debugRects.depths) do
            if hit(r) then App.debugSkipToDepth(d); return end
        end
    end
    if App.state == "playing" and App.game then
        App.game:mousepressed(mx, my, button)
    else
        App.ui:mousepressed(mx, my, button)
    end
end

function love.mousereleased(sx, sy, button)
    if App.state == "ui" then
        local mx, my = toLogical(sx, sy)
        App.ui:mousereleased(mx, my, button)
    end
end

function love.wheelmoved(dx, dy)
    if App.state == "ui" then App.ui:wheelmoved(dx, dy) end
end

function love.keypressed(key)
    if key == "f9" then
        App.debug = not App.debug
        Log.add(App.debug and "debug console opened" or "debug console closed")
        return
    end
    if key == "f11" then
        App.save.settings.fullscreen = not App.save.settings.fullscreen
        love.window.setFullscreen(App.save.settings.fullscreen, "desktop")
        Save.flush(); updateScale()
        return
    end
    if App.state == "playing" and App.game then
        App.game:keypressed(key)
    else
        App.ui:keypressed(key)
    end
end

function love.textinput(t)
    if App.state == "ui" then App.ui:textinput(t) end
end

function love.quit()
    Save.flush()
end
