-- Achievement catalog + unlocking. Unlocking an achievement that gates a
-- special cosmetic also grants that cosmetic into save.owned, so the rest of
-- the game only ever needs to check ownership.
local Cosmetics = require("src.cosmetics")
local A = {}

A.list = {
    { id="first_blood", name="First Ink",      desc="Defeat your first creature." },
    { id="kills_100",   name="Swarm Sweeper",  desc="Defeat 100 creatures (lifetime)." },
    { id="kills_500",   name="Trench Cleaner",  desc="Defeat 500 creatures (lifetime)." },
    { id="kills_1000",  name="Ink Demon",      desc="Defeat 1000 creatures. Unlocks the Ink Demon skin." },
    { id="beat_game",   name="Liberator",      desc="WIN — slay the Eldritch Squid and free the trapped squids. Unlocks Leviathan." },
    { id="wins_5",      name="Veteran Diver",  desc="Win 5 runs. Unlocks the Mustache." },
    { id="wins_10",     name="Trench Lord",    desc="Win 10 runs. Unlocks the Golden Mustache." },
    { id="wins_25",     name="Trench Sovereign", desc="Win 25 runs. Unlocks the Diamond Mustache." },
    { id="depth_4",     name="The Midnight Drop", desc="Reach depth 4 — face the Warden." },
    { id="depth_8",     name="Slayer of the Maw", desc="Reach the Maw at depth 8. Unlocks Voidborn." },
    { id="reach_hadal", name="Below the Maw",  desc="Pass the Maw into the Hadal Depths (depth 9). Unlocks Voidkin." },
    { id="depth_11",    name="The Hollow Throne", desc="Reach depth 11, the deepest dark. Unlocks Obsidian." },
    { id="flawless",    name="Untouched",      desc="Win a run without taking a single hit." },
    { id="curse_win",   name="Greed Rewarded", desc="Win with a net point-loss modifier. Unlocks Gilded." },
    { id="speedrun",    name="Comet Descent",  desc="Win in under 9 minutes. Unlocks Comet." },
    { id="rich_5000",   name="Trench Tycoon",  desc="Earn 5,000 $Things total. Unlocks the Trench Crown." },
    { id="combo_50",    name="Frenzy",         desc="Reach a 50 combo. Unlocks the Crimson Wake." },
    { id="boss_first",  name="Giant Slayer",   desc="Defeat any boss creature. Unlocks the Pirate Hat." },
    { id="bosses_8",    name="Boss Breaker",   desc="Defeat 8 bosses (lifetime). Unlocks the Fancy Top Hat." },
    { id="bosses_25",   name="Titanbane",      desc="Defeat 25 bosses (lifetime). Unlocks the Specter skin." },
    { id="mods_3",      name="Thrill Seeker",  desc="Win with 3+ modifiers active. Unlocks War Paint." },
    { id="terror_win",  name="Hell Survivor",  desc="Win a run on TERROR difficulty. Unlocks the Halo." },
    { id="no_lifesteal_win", name="No Crutch", desc="Win a run (not GOO-GOO BABY) without ever taking Lifesteal." },
    { id="churgly_slain", name="Godkiller",    desc="Slay the Churgly'nth in the fractalspace. Unlocks 3 cosmic relics." },

    -- Extended catalog (also published to the games.brassey.io online portal).
    { id="kills_5000", name="Abyssal Annihilator", desc="Defeat 5,000 creatures (lifetime)." },
    { id="wins_50",    name="Trench Eternal",   desc="Win 50 runs." },
    { id="combo_100",  name="Maelstrom",        desc="Reach a 100 combo." },
    { id="rich_25000", name="Trench Croesus",   desc="Earn 25,000 $Things total." },
    { id="bosses_50",  name="Worldender",       desc="Defeat 50 bosses (lifetime)." },
    { id="playtime_5h", name="Tideworn",        desc="Play for 5 hours." },
    { id="deaths_50",  name="Unsinkable",       desc="Die 50 times and keep diving." },
    { id="mods_5",     name="Chaos Theory",     desc="Win with 5+ modifiers active." },
    { id="flawless_terror", name="Immaculate",  desc="Win on TERROR without taking a single hit." },
    { id="speedrun_6", name="Lightspeed Descent", desc="Win in under 6 minutes." },
}

A.byId = {}
for _, a in ipairs(A.list) do A.byId[a.id] = a end

function A.isUnlocked(save, id) return save.achievements[id] == true end

-- Mark an achievement unlocked in the save and grant any special cosmetic it
-- gates. Returns true only when it was NOT already unlocked. Does NOT report to
-- the online portal — callers decide whether to (A.fire does; portal-sync does
-- not, to avoid echoing a portal-sourced unlock straight back).
local function grant(save, id)
    if save.achievements[id] then return false end
    if not A.byId[id] then return false end
    save.achievements[id] = true
    for _, item in ipairs(Cosmetics.skins) do
        if item.ach == id then save.owned[item.id] = true end
    end
    for _, item in ipairs(Cosmetics.accessories) do
        if item.ach == id then save.owned[item.id] = true end
    end
    return true
end

-- Report an unlock to the games.brassey.io online build. The LÖVE-web runtime
-- watches stdout for the "[[LOVEWEB_ACH]]" prefix and records the unlock
-- server-side (keys must match achievements.json at the repo root). On the
-- desktop build this is just an inert stdout line.
function A.report(id)
    if A.byId[id] then print("[[LOVEWEB_ACH]]unlock " .. id) end
end

-- Unlock one achievement. Returns true if it was newly unlocked. Grants any
-- special cosmetic gated by this achievement, and reports it to the portal.
function A.fire(save, id)
    if not grant(save, id) then return false end
    A.report(id)
    return true
end

-- On the web build the portal pre-populates <save-dir>/__loveweb__/achievements.json
-- with the player's already-earned unlocks before main.lua runs. Fold those into
-- the local save so the in-game achievements screen and cosmetic unlocks reflect
-- online progress. No-op on desktop (file absent). We mark locally only — never
-- re-report, or we'd bounce portal unlocks back at the portal. No JSON lib is
-- bundled, so we pluck the unlock keys with a pattern match.
function A.syncFromPortal(save)
    local path = "__loveweb__/achievements.json"
    if not (love and love.filesystem and love.filesystem.getInfo
            and love.filesystem.getInfo(path)) then return end
    local raw = love.filesystem.read(path)
    if not raw then return end
    for key in raw:gmatch('"key"%s*:%s*"([a-z0-9_]+)"') do
        grant(save, key)
    end
end

-- Scan lifetime stats and fire any threshold achievements now satisfied.
-- Returns a list of newly-unlocked achievement tables (for toasts).
function A.check(save)
    local s = save.stats
    local newly = {}
    local function try(cond, id) if cond and A.fire(save, id) then newly[#newly+1] = A.byId[id] end end

    try(s.totalKills >= 1,    "first_blood")
    try(s.totalKills >= 100,  "kills_100")
    try(s.totalKills >= 500,  "kills_500")
    try(s.totalKills >= 1000, "kills_1000")
    try(s.totalWins >= 1,     "beat_game")
    try(s.totalWins >= 5,     "wins_5")
    try(s.totalWins >= 10,    "wins_10")
    try(s.totalWins >= 25,    "wins_25")
    try(s.bestDepth >= 4,     "depth_4")
    try(s.bestDepth >= 8,     "depth_8")
    try(s.bestDepth >= 9,     "reach_hadal")
    try(s.bestDepth >= 11,    "depth_11")
    try(s.noHitWins >= 1,     "flawless")
    try(s.curseWins >= 1,     "curse_win")
    try(s.totalThingsEarned >= 5000, "rich_5000")
    try(s.bestCombo >= 50,    "combo_50")
    try(s.bossKills >= 1,     "boss_first")
    try(s.bossKills >= 8,     "bosses_8")
    try(s.bossKills >= 25,    "bosses_25")
    try(s.maxMods >= 3,       "mods_3")
    -- Extended catalog
    try(s.totalKills >= 5000,        "kills_5000")
    try(s.totalWins >= 50,           "wins_50")
    try(s.bestCombo >= 100,          "combo_100")
    try(s.totalThingsEarned >= 25000, "rich_25000")
    try(s.bossKills >= 50,           "bosses_50")
    try((s.playTime or 0) >= 18000,  "playtime_5h")  -- 5 hours
    try((s.deaths or 0) >= 50,       "deaths_50")
    try(s.maxMods >= 5,              "mods_5")
    return newly
end

function A.countUnlocked(save)
    local n = 0
    for _, a in ipairs(A.list) do if save.achievements[a.id] then n = n + 1 end end
    return n
end

return A
