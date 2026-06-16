-- Custom campaigns: a player-built sequence of depths (waves of configurable
-- enemy spawns) and title cards (story text shown between depths). Saved as
-- plain, human-readable Lua tables under  <save dir>/campaigns/*.lua  so they're
-- trivial to copy out of the game and share with friends.

local C = {}
C.DIR = "campaigns"

-- ---------------------------------------------------------------------------
-- The enemy roster the editor can place. Grouped for the picker.
-- ---------------------------------------------------------------------------
C.REGULAR = { "drifter", "darter", "snapper", "spitter", "lurker", "gulper",
              "puffer", "wisp", "parasite", "terror", "unseen", "brood",
              "phantom", "wormsing", "churgspawn", "crawler" }
C.BOSSES  = { "warden", "maw", "eldritch", "churglynth" }
-- leviathan flyby variants (events, not pool enemies)
C.LEVIATHANS = { "pale", "blue", "red" }

C.NICE = {
    drifter = "Drifter", darter = "Darter", snapper = "Snapper", spitter = "Spitter",
    lurker = "Lurker", gulper = "Gulper", puffer = "Puffer", wisp = "Wisp",
    parasite = "Flesh Parasite", terror = "Abyssal Terror", unseen = "The Unseen",
    brood = "Brood Sac", phantom = "Phantom", wormsing = "Worm Singularity",
    churgspawn = "Churgspawn", crawler = "Husk Crawler", mine = "Deep Mine",
    warden = "The Warden", maw = "The Maw", eldritch = "The Eldritch Squid",
    churglynth = "Churgly'nth",
}
function C.niceName(id) return C.NICE[id] or id end

-- Per-enemy special knobs surfaced in the editor. Each: {key, label, default,
-- min, max, step}. Only shown for the enemy that has them.
-- key, label, default(0=use built-in), min, max, step
C.SPECIALS = {
    spitter    = { { "rings", "Ring bullets", 0, 0, 40, 1 }, { "fireCd", "Fire cooldown", 0, 0, 8, 0.1 } },
    lurker     = { { "shrapnel", "Lure shrapnel", 0, 0, 40, 1 }, { "fireCd", "Lure cooldown", 0, 0, 8, 0.1 } },
    puffer     = { { "boomR", "Explosion radius", 0, 0, 300, 5 } },
    churgspawn = { { "armLen", "Arm length", 0, 0, 8, 0.25 }, { "arms", "Arm count", 0, 0, 8, 1 }, { "sludgeDmg", "Trail damage", 0, 0, 40, 1 }, { "sludgeLife", "Trail lifetime", 0, 0, 30, 0.5 }, { "trailSize", "Trail size x", 0, 0, 4, 0.25 } },
    crawler    = { { "segs", "Segments", 0, 0, 16, 1 }, { "turn", "Turn speed", 0, 0, 8, 0.1 }, { "poisonDmg", "Poison damage", 92, 0, 600, 5 }, { "poisonLen", "Poison length x", 1, 0.25, 8, 0.25 } },
    wormsing   = { { "pull", "Blackhole range", 0, 0, 800, 10 } },
    gulper     = { { "segs", "Segments", 0, 0, 16, 1 } },
    parasite   = { { "leech", "Leech/sec", 0, 0, 60, 1 }, { "latch", "Latch time", 0, 0, 10, 0.2 }, { "segs", "Segments", 0, 0, 16, 1 } },
    warden     = { { "ringBullets", "Ring bullets", 0, 0, 60, 1 }, { "ringDelay", "Ring cooldown", 0, 0, 4, 0.1 } },
    maw        = { { "ringBullets", "Ring bullets", 0, 0, 80, 1 }, { "ringDelay", "Ring cooldown", 0, 0, 4, 0.1 } },
    eldritch   = { { "ringBullets", "Ring bullets", 0, 0, 60, 1 }, { "ringDelay", "Ring cooldown", 0, 0, 4, 0.1 }, { "adds", "Adds per burst (0=off)", 1, 0, 99, 1 } },
    brood      = { { "splitN", "Spawns on death (0=none)", 3, 0, 99, 1 } },
    churglynth = { { "ringBullets", "Ring bullets", 0, 0, 80, 1 }, { "ringDelay", "Ring cooldown", 0, 0, 4, 0.1 }, { "segs", "Segments", 0, 0, 30, 1 } },
}
function C.specialsFor(id) return C.SPECIALS[id] end

-- Per-depth music options (cycled in the editor). "normal"/"hadal" resolve to
-- the player's chosen themes at runtime; the rest are direct track ids.
C.MUSIC = {
    { id = "normal",    label = "Normal" },
    { id = "hadal",     label = "Hadal" },
    { id = "breakcore", label = "Boss: Core Breach" },
    { id = "terrorcore",label = "Boss: Hell Below" },
    { id = "voidcore",  label = "Boss: Fractal Throat" },
    { id = "tidalwrath",label = "Boss: Tidal Wrath" },
    { id = "neonhunt",  label = "Boss: Neon Predator" },
    { id = "bonechoir", label = "Boss: Bone Choir" },
    { id = "bloodtide", label = "Boss: Bloodtide" },
}
function C.musicLabel(id)
    for _, m in ipairs(C.MUSIC) do if m.id == id then return m.label end end
    return "Normal"
end
function C.musicCycle(id, dir)
    local i = 1
    for k, m in ipairs(C.MUSIC) do if m.id == id then i = k end end
    return C.MUSIC[(i - 1 + dir) % #C.MUSIC + 1].id
end

-- what a spawner spits out, so its adds' stats can be configured (nil if none)
C.ADDS = { eldritch = "parasite", brood = "parasite" }
function C.addType(id) return C.ADDS[id] end

-- ---------------------------------------------------------------------------
-- Defaults / constructors
-- ---------------------------------------------------------------------------
function C.defaultCfg()
    return { hp = 1, dmg = 1, speed = 1, size = 1, variant = "base", special = {} }
end

-- One entry = a specific enemy, spawned EXACTLY `count` times with this entry's
-- own config. Want two differently-tuned parasites? Add two entries. Deterministic
-- — what you place is what spawns, no random pools.
function C.newSpawn(id)
    return { id = id, count = 1, cfg = C.defaultCfg() }
end

-- deep-ish copy of a spawn entry so duplicated waves/depths don't alias cfgs.
function C.copySpawn(s)
    local cs = {}
    for k, v in pairs(s) do cs[k] = v end
    cs.cfg = {}
    for k, v in pairs(s.cfg or {}) do cs.cfg[k] = v end
    cs.cfg.special = {}
    for k, v in pairs((s.cfg and s.cfg.special) or {}) do cs.cfg.special[k] = v end
    return cs
end

-- A wave owns its spawns AND its leviathan flybys; each wave is independent.
function C.newWave()
    return { spawns = {}, levis = {} }
end

-- Deep copy a wave (its spawns + leviathans) for copy/paste between waves.
function C.copyWave(w)
    local nw = { spawns = {}, levis = {} }
    for _, s in ipairs(w.spawns or {}) do nw.spawns[#nw.spawns + 1] = C.copySpawn(s) end
    for _, l in ipairs(w.levis or {}) do
        local nl = {}; for k, v in pairs(l) do nl[k] = v end
        nw.levis[#nw.levis + 1] = nl
    end
    return nw
end

-- Deep copy a timeline node (depth or title) so duplicates never alias.
function C.copyNode(n)
    if n.kind == "title" then return { kind = "title", text = n.text } end
    local d = {}
    for k, v in pairs(n) do d[k] = v end           -- scalars (name, fog, boss, …)
    d.waves = {}
    for _, w in ipairs(n.waves or {}) do
        local nw = { spawns = {}, levis = {} }
        for _, s in ipairs(w.spawns or {}) do nw.spawns[#nw.spawns + 1] = C.copySpawn(s) end
        for _, l in ipairs(w.levis or {}) do
            local nl = {}; for k, v in pairs(l) do nl[k] = v end
            nw.levis[#nw.levis + 1] = nl
        end
        d.waves[#d.waves + 1] = nw
    end
    d.levis = nil
    d.bossCfg = {}
    for k, v in pairs(n.bossCfg or C.defaultCfg()) do d.bossCfg[k] = v end
    d.bossCfg.special = {}
    for k, v in pairs((n.bossCfg and n.bossCfg.special) or {}) do d.bossCfg.special[k] = v end
    return d
end

-- A leviathan belongs to the wave it's added to (no wave list needed).
function C.newLevi()
    return { variant = "pale", sludgeDmg = 0, sludgeLife = 0, armLen = 0 }
end

function C.newDepth(name)
    return {
        kind = "depth", name = name or "New Depth",
        fog = 0,                  -- 0 = clear … 1 = near-blind (custom visibility)
        waves = { C.newWave(), C.newWave(), C.newWave() },   -- per-wave spawn sets
        cards = true,             -- offer an upgrade card pick after clearing this depth
        music = "normal",         -- normal / hadal / a boss track (see C.MUSIC)
        boss = nil,               -- optional boss id (spawns after the last wave)
        bossName = nil,           -- optional custom boss title (overrides its name)
        bossCfg = C.defaultCfg(), -- the boss's own size/hp/dmg/speed + specials
        levis = {},               -- scripted leviathan flybys (per wave)
        mines = 0,                -- placed mine hazards
        cornerArms = false, cornerArmLen = 0.24,   -- terror-style corner arms
    }
end

-- Upgrade an OLD-format depth (numeric wave count + a single shared spawn list)
-- to the per-wave model, in place. Each wave inherits a copy of the old shared
-- pool so existing campaigns keep playing the same and stay independently
-- editable. Safe to call on already-new depths (no-op).
function C.normalizeDepth(d)
    if not d or d.kind ~= "depth" then return d end
    if type(d.waves) == "number" then
        local n = math.max(1, d.waves)
        local shared = d.spawns or {}
        d.waves = {}
        for _ = 1, n do
            local w = C.newWave()
            for _, s in ipairs(shared) do w.spawns[#w.spawns + 1] = C.copySpawn(s) end
            d.waves[#d.waves + 1] = w
        end
        d.spawns = nil
    elseif type(d.waves) ~= "table" then
        d.waves = { C.newWave() }
    end
    if #d.waves == 0 then d.waves[1] = C.newWave() end
    -- spawn entries: drop the old weight/pool model — every entry now spawns an
    -- exact count (>=1). Old weighted entries (count 0) become a single enemy.
    for _, w in ipairs(d.waves) do
        w.levis = w.levis or {}
        for _, s in ipairs(w.spawns or {}) do
            s.count = (s.count and s.count > 0) and s.count or 1
            s.weight = nil
            s.cfg = s.cfg or C.defaultCfg()
            s.cfg.special = s.cfg.special or {}
        end
    end
    -- migrate OLD depth-level leviathans (each carried a list of wave indices)
    -- into the per-wave model: a copy lands in every wave it used to fly on.
    if d.levis then
        for _, l in ipairs(d.levis) do
            for _, wi in ipairs(l.waves or { 1 }) do
                local w = d.waves[wi]
                if w then
                    w.levis[#w.levis + 1] = { variant = l.variant or "pale",
                        sludgeDmg = l.sludgeDmg or 0, sludgeLife = l.sludgeLife or 0, armLen = l.armLen or 0 }
                end
            end
        end
        d.levis = nil
    end
    if d.cards == nil then d.cards = true end
    -- migrate the old hadalMusic boolean → the music selector
    if d.music == nil then
        d.music = d.hadalMusic and "hadal" or "normal"
        d.hadalMusic = nil
    end
    if not d.bossCfg then d.bossCfg = C.defaultCfg() end
    d.bossCfg.special = d.bossCfg.special or {}
    return d
end

function C.normalize(camp)
    for _, n in ipairs(camp.nodes or {}) do
        if n.kind == "depth" then C.normalizeDepth(n)
        elseif n.kind == "title" and not n.dur then n.dur = 5 end
    end
    return camp
end

function C.newTitle()
    return { kind = "title", text = "Something stirs in the dark...", dur = 5 }
end

function C.newCampaign(name)
    return {
        name = name or "New Campaign",
        mult = { enemyHp = 1, enemyDmg = 1, enemySpeed = 1, enemySize = 1, payMult = 1 },  -- global, like a difficulty
        startCards = {},          -- upgrade card ids the player begins the run with
        nodes = { C.newDepth("The Shallows") },
    }
end

-- A ready-made example so the list is never empty and players see the format.
-- Shows off per-wave spawns: each depth's waves escalate independently, and
-- each entry spawns an EXACT count (no random pools).
local function spawn(id, count) return { id = id, count = count or 1, cfg = C.defaultCfg() } end
function C.example()
    local c = C.newCampaign("Example: Trench Run")
    c.mult = { enemyHp = 1, enemyDmg = 1, enemySpeed = 1, enemySize = 1, payMult = 1 }

    local d1 = C.newDepth("The Shallows"); d1.fog = 0
    d1.waves = {
        { spawns = { spawn("drifter", 3) } },                          -- wave 1: 3 drifters
        { spawns = { spawn("drifter", 3), spawn("darter", 2) } },      -- wave 2: 3 drifters + 2 darters
    }

    local d2 = C.newDepth("The Crush"); d2.fog = 0.3
    d2.waves = {
        { spawns = { spawn("snapper", 3) }, levis = {} },
        { spawns = { spawn("snapper", 2), spawn("spitter", 2) }, levis = {} },
        { spawns = { spawn("spitter", 2), spawn("puffer", 1) },                 -- wave 3: one puffer
          levis = { { variant = "pale", sludgeDmg = 0, sludgeLife = 0, armLen = 0 } } },   -- + a pale leviathan
    }

    local t1 = C.newTitle(); t1.text = "The water turns black. The Warden wakes."

    local d3 = C.newDepth("The Warden's Gate"); d3.fog = 0.5; d3.cards = false   -- no card pick before the boss
    d3.waves = {
        { spawns = { spawn("puffer", 2) } },
        { spawns = { spawn("lurker", 1), spawn("spitter", 2) } },
    }
    d3.boss = "warden"

    c.nodes = { d1, d2, t1, d3 }
    return c
end

-- ---------------------------------------------------------------------------
-- Serialization (plain Lua table -> readable text)
-- ---------------------------------------------------------------------------
local function ser(v, ind)
    ind = ind or ""
    local tv = type(v)
    if tv == "number" then return tostring(v)
    elseif tv == "boolean" then return tostring(v)
    elseif tv == "string" then return string.format("%q", v)
    elseif tv == "table" then
        local out, ni = { "{\n" }, ind .. "  "
        -- array part first
        local n = #v
        for i = 1, n do out[#out + 1] = ni .. ser(v[i], ni) .. ",\n" end
        -- hash part
        local keys = {}
        for k in pairs(v) do
            if not (type(k) == "number" and k >= 1 and k <= n and k == math.floor(k)) then keys[#keys + 1] = k end
        end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, k in ipairs(keys) do
            local ks = type(k) == "string" and (k:match("^[%a_][%w_]*$") and k .. " = " or "[" .. string.format("%q", k) .. "] = ")
                or ("[" .. tostring(k) .. "] = ")
            out[#out + 1] = ni .. ks .. ser(v[k], ni) .. ",\n"
        end
        out[#out + 1] = ind .. "}"
        return table.concat(out)
    end
    return "nil"
end

function C.dirPath() return love.filesystem.getSaveDirectory() .. "/" .. C.DIR end

local function slug(name)
    local s = (name or "campaign"):lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
    if s == "" then s = "campaign" end
    return s
end

-- List saved campaigns: { {file=, name=, depths=, camp=} ... }
function C.list()
    love.filesystem.createDirectory(C.DIR)
    local out = {}
    for _, f in ipairs(love.filesystem.getDirectoryItems(C.DIR)) do
        if f:match("%.lua$") then
            local camp = C.load(f)
            if camp then
                local depths = 0
                for _, n in ipairs(camp.nodes or {}) do if n.kind == "depth" then depths = depths + 1 end end
                out[#out + 1] = { file = f, name = camp.name or f, depths = depths, camp = camp }
            end
        end
    end
    table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
    return out
end

function C.load(file)
    local path = C.DIR .. "/" .. file
    if not love.filesystem.getInfo(path) then return nil end
    local chunk = love.filesystem.load(path)
    if not chunk then return nil end
    local ok, camp = pcall(chunk)
    if ok and type(camp) == "table" and camp.nodes then return C.normalize(camp) end
    return nil
end

-- Save a campaign; returns its filename. Reuses camp._file if set so editing
-- doesn't spawn duplicates.
function C.save(camp)
    love.filesystem.createDirectory(C.DIR)
    local file = camp._file
    if not file then
        file = slug(camp.name) .. ".lua"
        local n = 1
        while love.filesystem.getInfo(C.DIR .. "/" .. file) do
            n = n + 1; file = slug(camp.name) .. "_" .. n .. ".lua"
        end
    end
    camp._file = nil
    love.filesystem.write(C.DIR .. "/" .. file, "return " .. ser(camp) .. "\n")
    camp._file = file
    return file
end

function C.delete(file)
    love.filesystem.remove(C.DIR .. "/" .. file)
end

-- Download a campaign over HTTP and save it locally. LÖVE bundles LuaSocket, so
-- plain http:// works (no https without luasec). The downloaded chunk is run in
-- an EMPTY sandbox env — a campaign file is just `return {table}`, so it never
-- needs globals, and this stops a malicious file from doing anything. Returns
-- (filename) on success or (nil, errormessage).
function C.download(url)
    if type(url) ~= "string" or url:gsub("%s", "") == "" then return nil, "enter a URL first" end
    url = url:gsub("%s", "")
    if not url:match("^https?://") then url = "http://" .. url end
    if url:match("^https://") then return nil, "https isn't supported — use http://" end
    local ok, http = pcall(require, "socket.http")
    if not ok then return nil, "no network library available" end
    http.TIMEOUT = 5
    local okreq, body, code = pcall(http.request, url)
    if not okreq then return nil, "request failed (" .. tostring(body) .. ")" end
    if not body then return nil, "could not reach server (" .. tostring(code) .. ")" end
    if code ~= 200 then return nil, "server returned HTTP " .. tostring(code) end
    local chunk, perr = (loadstring or load)(body, "downloaded-campaign")
    if not chunk then return nil, "file isn't valid Lua: " .. tostring(perr) end
    if setfenv then setfenv(chunk, {}) end          -- sandbox: no globals for the downloaded file
    local okc, camp = pcall(chunk)
    if not okc or type(camp) ~= "table" or not camp.nodes then return nil, "that file isn't a campaign" end
    C.normalize(camp)
    camp._file = nil
    if not camp.name or camp.name == "" then camp.name = url:match("([^/]+)%.lua$") or "Downloaded Campaign" end
    return C.save(camp)
end

-- The ordered depth nodes (for play / progression) + the title text that
-- precedes each depth index.
function C.compile(camp)
    local depths, titleBefore, pending = {}, {}, nil
    for _, n in ipairs(camp.nodes or {}) do
        if n.kind == "title" then
            pending = (pending and (pending .. "\n") or "") .. (n.text or "")
        elseif n.kind == "depth" then
            depths[#depths + 1] = n
            if pending then titleBefore[#depths] = pending; pending = nil end
        end
    end
    return depths, titleBefore
end

return C
