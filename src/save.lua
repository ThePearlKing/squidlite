-- Persistent profile: $Things currency, owned/equipped cosmetics, unlocked
-- achievements, lifetime stats, and settings. Stored as a serialized Lua table
-- in the LÖVE save directory so nested sets (owned-item maps) round-trip cleanly.
local Save = {}

local PATH = "squidlite_save.lua"

-- Dev modes (selftest/shot/audio) call this BEFORE load so they read/write a
-- throwaway file and can never clobber the player's real save.
function Save.useTestFile()
    PATH = "squidlite_devtest.lua"
end

-- Default profile. New fields added here are auto-merged into older saves on
-- load, so updates never wipe progress.
local function defaults()
    return {
        version = 1,
        things = 0,                 -- $Things currency

        -- Cosmetics: owned/equipped. Basic items are owned implicitly (see cosmetics.lua).
        owned = {},                 -- map id -> true (skins AND accessories)
        skin = "luminer",           -- equipped skin id
        accessories = {},           -- map slot -> accessory id (equipped)

        achievements = {},          -- map achievement id -> true
        bestiary = {},              -- map creature id -> lifetime defeats (leviathan = survives)
        bestiarySeen = {},          -- map creature id -> true once its book page has been opened
        musicTheme = "deepdrive",   -- equipped soundtrack id (depths above the Maw)
        hadalTheme = "hollow",      -- equipped Hadal-Depths soundtrack id

        -- Lifetime stats (drive achievements + score balance).
        stats = {
            totalRuns = 0,
            totalWins = 0,
            totalKills = 0,
            bestDepth = 0,          -- deepest zone reached (1..)
            bestScore = 0,
            totalThingsEarned = 0,
            bestCombo = 0,
            noHitWins = 0,
            deaths = 0,
            bossKills = 0,
            playTime = 0,
            curseWins = 0,          -- wins with a net point-loss modifier active
            maxMods = 0,            -- most modifiers active in one run
        },

        settings = {
            fullscreen = false,
            musicVolume = 0.42,
            sfxVolume = 0.8,
            screenShake = true,
            secret = {},      -- Super Secret Settings (visual-only filter toggles)
        },

        secretUnlocked = false,   -- has the player entered the Konami code?

        seenIntro = false,

        -- Developer/admin mode. Off by default; enable by hand-editing the save
        -- file (set admin = true). Gates F7 (skip wave), F8 (god mode) and the
        -- F9 depth-skip selector.
        admin = false,
    }
end

-- Recursively fill missing keys in `t` from `def`.
local function merge(t, def)
    for k, v in pairs(def) do
        if type(v) == "table" then
            if type(t[k]) ~= "table" then t[k] = {} end
            merge(t[k], v)
        elseif t[k] == nil then
            t[k] = v
        end
    end
    return t
end

-- Minimal serializer for plain data (numbers, strings, bools, tables).
local function serialize(v, indent)
    indent = indent or ""
    local tv = type(v)
    if tv == "number" then
        -- avoid locale-dependent formatting
        return tostring(v)
    elseif tv == "string" then
        return string.format("%q", v)
    elseif tv == "boolean" then
        return tostring(v)
    elseif tv == "table" then
        local out = { "{\n" }
        local ni = indent .. "  "
        -- array part
        local n = #v
        local arrayKeys = {}
        for i = 1, n do arrayKeys[i] = true end
        for k, val in pairs(v) do
            local keyStr
            if type(k) == "number" and arrayKeys[k] then
                keyStr = nil
            elseif type(k) == "string" and k:match("^[%a_][%w_]*$") then
                keyStr = k .. " = "
            else
                keyStr = "[" .. serialize(k) .. "] = "
            end
            out[#out + 1] = ni .. (keyStr or "") .. serialize(val, ni) .. ",\n"
        end
        out[#out + 1] = indent .. "}"
        return table.concat(out)
    end
    return "nil"
end

local data = nil

function Save.load()
    local def = defaults()
    if love.filesystem.getInfo(PATH) then
        local content = love.filesystem.read(PATH)
        if content then
            -- loadstring on Lua 5.1 (the love.js web runtime); load() only takes
            -- a string on 5.2+. Desktop LÖVE is LuaJIT so plain load() worked
            -- there, but the web portal is Lua 5.1 and needs this.
            local chunk = (loadstring or load)("return " .. content)
            if chunk then
                local ok, t = pcall(chunk)
                if ok and type(t) == "table" then
                    data = merge(t, def)
                    return data
                end
            end
        end
    end
    data = def
    return data
end

function Save.get()
    if not data then Save.load() end
    return data
end

function Save.flush()
    if not data then return end
    love.filesystem.write(PATH, serialize(data))
end

-- Wipe everything back to a fresh profile (used by the Settings reset flow).
-- Admin mode is PRESERVED across a reset — once you're an admin you stay one
-- until you set admin = false by hand in the save file.
function Save.reset()
    local wasAdmin = data and data.admin
    data = defaults()
    data.admin = wasAdmin or false
    Save.flush()
    return data
end

return Save
