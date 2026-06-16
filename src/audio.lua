-- Procedural audio. All SFX and music are synthesized at runtime into LÖVE
-- SoundData — no asset files. Music is a small library of looping themes, each
-- a different genre (abyssal ambient, lofi, synthwave, drum & bass, jazz, deep
-- choir), built lazily on first play and cached. Themes unlock via progress.

local Audio = {}
local RATE = 44100

----------------------------------------------------------------------
-- Low-level oscillators (operate on a plain Lua float buffer, mixed once
-- into a SoundData at the end — far faster than read-modify-write per sample).
----------------------------------------------------------------------
local function osc(wave, phase)
    if wave == "sine" then
        return math.sin(phase)
    elseif wave == "tri" then
        local p = (phase / (2 * math.pi)) % 1
        return p < 0.5 and (4 * p - 1) or (3 - 4 * p)
    elseif wave == "saw" then
        local p = (phase / (2 * math.pi)) % 1
        return 2 * p - 1
    elseif wave == "square" then
        return math.sin(phase) >= 0 and 1 or -1
    elseif wave == "pulse" then
        local p = (phase / (2 * math.pi)) % 1
        return p < 0.30 and 1 or -1
    end
    return math.sin(phase)
end

-- ADSR-ish note into buffer `b` (Lua array indexed 1..N).
local function note(b, N, freq, startT, dur, vol, wave, atk, rel, vib)
    wave = wave or "sine"; vol = vol or 0.2
    atk = atk or 0.005; rel = rel or 0.06
    local s0 = math.floor(startT * RATE)
    local sN = math.floor(dur * RATE)
    local w = 2 * math.pi * freq
    for i = 0, sN - 1 do
        local t = i / RATE
        local e
        if t < atk then e = t / atk
        elseif t > dur - rel then e = math.max(0, (dur - t) / rel)
        else e = 1 end
        local ph = w * t
        if vib then ph = ph + vib * math.sin(2 * math.pi * 5.5 * t) end
        local idx = s0 + i + 1
        if idx >= 1 and idx <= N then
            b[idx] = b[idx] + osc(wave, ph) * vol * e
        end
    end
end

local function pad(b, N, freqs, startT, dur, vol)
    vol = vol or 0.05
    local s0 = math.floor(startT * RATE)
    local sN = math.floor(dur * RATE)
    for i = 0, sN - 1 do
        local t = i / RATE
        local e = math.min(1, t / 0.4) * math.max(0, math.min(1, (dur - t) / 0.5))
        local wob = 1 + 0.12 * math.sin(2 * math.pi * 0.5 * t)
        local s = 0
        for _, f in ipairs(freqs) do
            s = s + math.sin(2 * math.pi * f * t)
            s = s + 0.6 * math.sin(2 * math.pi * f * 1.004 * t)  -- detune
        end
        s = s / (#freqs * 1.5)
        local idx = s0 + i + 1
        if idx >= 1 and idx <= N then b[idx] = b[idx] + s * vol * e * wob end
    end
end

local function kick(b, N, startT, vol)
    vol = vol or 0.6
    local s0 = math.floor(startT * RATE)
    local sN = math.floor(0.18 * RATE)
    for i = 0, sN - 1 do
        local t = i / RATE
        local f = 45 + 120 * math.exp(-t * 32)
        local env = math.exp(-t * 13)
        local s = math.sin(2 * math.pi * f * t) * env
        if i < 70 then s = s + (love.math.random() * 2 - 1) * 0.35 * (1 - i / 70) end
        local idx = s0 + i + 1
        if idx >= 1 and idx <= N then b[idx] = b[idx] + s * vol end
    end
end

local function snare(b, N, startT, vol, tone)
    vol = vol or 0.32
    local s0 = math.floor(startT * RATE)
    local sN = math.floor(0.16 * RATE)
    for i = 0, sN - 1 do
        local t = i / RATE
        local env = math.exp(-t * (tone == "brush" and 16 or 24))
        local noise = (love.math.random() * 2 - 1) * (tone == "brush" and 0.5 or 0.8)
        local body = math.sin(2 * math.pi * 190 * t) * 0.28
        local idx = s0 + i + 1
        if idx >= 1 and idx <= N then b[idx] = b[idx] + (noise + body) * vol * env end
    end
end

local function hat(b, N, startT, vol, open)
    vol = vol or 0.13
    local s0 = math.floor(startT * RATE)
    local sN = math.floor((open and 0.13 or 0.04) * RATE)
    for i = 0, sN - 1 do
        local t = i / RATE
        local env = math.exp(-t * (open and 24 or 70))
        local idx = s0 + i + 1
        if idx >= 1 and idx <= N then b[idx] = b[idx] + (love.math.random() * 2 - 1) * vol * env end
    end
end

local function bass(b, N, freq, startT, dur, vol, wave)
    vol = vol or 0.26; wave = wave or "saw"
    local s0 = math.floor(startT * RATE)
    local sN = math.floor(dur * RATE)
    for i = 0, sN - 1 do
        local t = i / RATE
        local e = math.min(1, t / 0.01) * math.max(0, math.min(1, (dur - t) / 0.04))
        local main = osc(wave, 2 * math.pi * freq * t)
        local sub = math.sin(2 * math.pi * freq * 0.5 * t)
        local idx = s0 + i + 1
        if idx >= 1 and idx <= N then b[idx] = b[idx] + (main * 0.6 + sub * 0.45) * vol * e end
    end
end

-- Simple feedback echo over the whole buffer (adds depth/space).
local function echo(b, N, delaySec, feedback, mix)
    local d = math.floor(delaySec * RATE)
    for i = d + 1, N do
        b[i] = b[i] + b[i - d] * feedback * mix
    end
end

----------------------------------------------------------------------
-- Music: scales + theme composition
----------------------------------------------------------------------
local function midi(n) return 440 * 2 ^ ((n - 69) / 12) end

-- scale step -> midi note, given a root midi and a scale interval table
local SCALES = {
    minor      = { 0, 2, 3, 5, 7, 8, 10 },
    dorian     = { 0, 2, 3, 5, 7, 9, 10 },
    pentatonic = { 0, 3, 5, 7, 10 },
    majpenta   = { 0, 2, 4, 7, 9 },
    phrygian   = { 0, 1, 3, 5, 7, 8, 10 },   -- dark b2 (gothic / metal dread)
}
local function scaleNote(root, scale, degree)
    local s = SCALES[scale]
    local oct = math.floor(degree / #s)
    local idx = degree % #s + 1
    return midi(root + s[idx] + 12 * oct)
end

-- chord (triad) midi freqs from scale degree
local function chord(root, scale, degree)
    return {
        scaleNote(root, scale, degree),
        scaleNote(root, scale, degree + 2),
        scaleNote(root, scale, degree + 4),
    }
end

-- Each theme returns a function(rng) -> SoundData loop.
-- spec-driven composer keeps the genres compact yet distinct.
local function compose(spec)
    local rng = love.math.newRandomGenerator(spec.seed or 1)
    local oldRandom = love.math.random
    -- temporarily route love.math.random through our deterministic generator
    love.math.random = function(a, b)
        if a and b then return rng:random(a, b)
        elseif a then return rng:random(a) else return rng:random() end
    end

    local bpm = spec.bpm
    local beat = 60 / bpm
    local bars = spec.bars
    local beats = bars * 4
    local loopLen = beats * beat
    local N = math.floor(loopLen * RATE) + RATE  -- a little tail for echo
    -- two buses: melodic content (ducked by the kick) and the drum kit (punchy).
    local bMus, bDrum = {}, {}
    for i = 1, N do bMus[i] = 0; bDrum[i] = 0 end

    local root = spec.root
    local sc = spec.scale
    local prog = spec.prog  -- chord degrees per bar

    -- Pads / chord stabs
    for bar = 0, bars - 1 do
        local deg = prog[(bar % #prog) + 1]
        local ch = chord(root, sc, deg)
        if spec.pad then
            pad(bMus, N, ch, bar * 4 * beat, 4 * beat * spec.padSus, spec.padVol or 0.05)
        end
        if spec.comp then
            for _, off in ipairs(spec.compBeats or { 1, 2.5 }) do
                for _, f in ipairs(ch) do
                    note(bMus, N, f, (bar * 4 + off) * beat, beat * 0.4, spec.compVol or 0.05,
                         spec.compWave or "tri", 0.01, 0.18)
                end
            end
        end
    end

    -- Bassline
    if spec.bass then
        for bar = 0, bars - 1 do
            local deg = prog[(bar % #prog) + 1]
            for _, pat in ipairs(spec.bassPat) do
                local f = scaleNote(root - 12, sc, deg + (pat.deg or 0))
                bass(bMus, N, f, (bar * 4 + pat.t) * beat, pat.d * beat, spec.bassVol or 0.25, spec.bassWave)
            end
        end
    end

    -- Arpeggiator — fast driving 16ths cycling the chord tones (energy).
    if spec.arp then
        local notesPerBeat = spec.arp.rate or 4
        local stepDur = beat / notesPerBeat
        for bar = 0, bars - 1 do
            local deg = prog[(bar % #prog) + 1]
            local oct = spec.arp.oct or 1
            local tones = {
                scaleNote(root + 12 * oct, sc, deg),
                scaleNote(root + 12 * oct, sc, deg + 2),
                scaleNote(root + 12 * oct, sc, deg + 4),
                scaleNote(root + 12 * oct, sc, deg + 2),
            }
            for stp = 0, notesPerBeat * 4 - 1 do
                local f = tones[(stp % #tones) + 1]
                note(bMus, N, f, bar * 4 * beat + stp * stepDur, stepDur * 0.92,
                     spec.arp.vol or 0.06, spec.arp.wave or "pulse", 0.002, 0.03)
            end
        end
    end

    -- Lead melody
    if spec.lead then
        local degCur = 4
        for bar = 0, bars - 1 do
            local steps = spec.leadDensity or 4
            for st = 0, steps - 1 do
                if rng:random() < (spec.leadProb or 0.55) then
                    degCur = degCur + rng:random(-2, 2)
                    if degCur < 0 then degCur = 2 end
                    if degCur > 12 then degCur = 10 end
                    local t = (bar * 4 + st * (4 / steps)) * beat
                    local dur = (4 / steps) * beat * (spec.leadSus or 0.9)
                    note(bMus, N, scaleNote(root + 12, sc, degCur), t, dur,
                         spec.leadVol or 0.10, spec.leadWave or "tri", 0.01, 0.12,
                         spec.leadVib)
                end
            end
        end
    end

    if spec.echo then echo(bMus, N, spec.echo.t, spec.echo.fb, spec.echo.mix) end

    -- Drums (own bus so the sidechain pump doesn't duck the kick itself).
    local kickTimes = {}
    if spec.drums then
        for bar = 0, bars - 1 do
            for _, d in ipairs(spec.drums) do
                local t = (bar * 4 + d.t) * beat
                if d.k then kick(bDrum, N, t, spec.kickVol); kickTimes[#kickTimes + 1] = t end
                if d.s then snare(bDrum, N, t, spec.snareVol, spec.snareTone) end
                if d.h then hat(bDrum, N, t, spec.hatVol, d.open) end
            end
        end
    end

    -- Sidechain pump: duck the melodic bus right after every kick, then recover.
    -- This is what gives the track its driving, breathing groove.
    local depthSC = spec.sidechain or 0
    if depthSC > 0 and #kickTimes > 0 then
        table.sort(kickTimes)
        local rate = spec.sidechainRate or 9
        local ki, lastK = 1, -10
        for i = 1, N do
            local t = i / RATE
            while ki <= #kickTimes and kickTimes[ki] <= t do lastK = kickTimes[ki]; ki = ki + 1 end
            local g = 1 - depthSC * math.exp(-(t - lastK) * rate)
            bMus[i] = bMus[i] * g
        end
    end

    -- Overdrive: waveshape the melodic bus into fuzzy, distorted-guitar
    -- territory (breakcore / terror boss themes). Done pre-normalize so the
    -- saturation actually bites.
    if spec.distort and spec.distort > 0 then
        local drive = spec.distort
        for i = 1, N do
            local s = bMus[i] * drive
            bMus[i] = s / (1 + math.abs(s))     -- soft tanh-ish saturator
        end
    end

    -- Seamless loop: fold the tail that rings PAST the loop point (echo/delay
    -- ring, note releases) back into the start, so when the source loops the
    -- decaying echo bleeds into the beginning instead of being chopped off.
    local loopN = math.floor(loopLen * RATE)
    for i = loopN + 1, N do
        local j = i - loopN
        if j <= loopN then bMus[j] = bMus[j] + bMus[i]; bDrum[j] = bDrum[j] + bDrum[i] end
    end

    -- Mix buses, normalize, soft-clip into the loop region.
    local data = love.sound.newSoundData(loopN, RATE, 16, 1)
    local peak = 0.0001
    for i = 1, loopN do
        bMus[i] = bMus[i] + bDrum[i]
        local a = math.abs(bMus[i])
        if a > peak then peak = a end
    end
    local norm = (peak > 1 and (1 / peak) or 1) * 0.80   -- headroom so music sits under SFX
    for i = 1, loopN do
        local s = bMus[i] * norm
        -- gentle tanh-ish soft clip for warmth/loudness
        if s > 1 then s = 1 elseif s < -1 then s = -1 end
        s = s - (s * s * s) * 0.16
        data:setSample(i - 1, s)
    end

    love.math.random = oldRandom
    return data
end

----------------------------------------------------------------------
-- Theme library
----------------------------------------------------------------------
-- 4-on-the-floor kit: kick every beat, snare on 2 & 4, hats on every off-beat.
local DRIVING_DRUMS = {
    { t = 0, k = true, h = true }, { t = 0.5, h = true, open = true },
    { t = 1, k = true, s = true, h = true }, { t = 1.5, h = true, open = true },
    { t = 2, k = true, h = true }, { t = 2.5, h = true, open = true },
    { t = 3, k = true, s = true, h = true }, { t = 3.5, h = true, open = true },
}
-- driving eighth-note bassline
local DRIVE_BASS = {
    { t = 0, d = 0.5 }, { t = 0.5, d = 0.5 }, { t = 1, d = 0.5 }, { t = 1.5, d = 0.5 },
    { t = 2, d = 0.5 }, { t = 2.5, d = 0.5 }, { t = 3, d = 0.5, deg = 3 }, { t = 3.5, d = 0.5, deg = 3 },
}

-- GENESIS: a faithful port of the ambient exploration theme from ClaudeTheGame
-- (the player's first game). 16-bar E-minor loop: sparse sine melody over a deep
-- sine drone + sub-octave, slow pad chords (Em/D/C/Am), a soft once-a-bar kick
-- and a whisper of hi-hat. Reproduced note-for-note; normalized to the engine's
-- loudness so it sits with the rest of the soundtrack.
local function composeGenesis()
    local bpm, bars, beatsPerBar = 100, 16, 4
    local beatLen = 60 / bpm
    local totalBeats = bars * beatsPerBar
    local samples = math.floor(RATE * totalBeats * beatLen)
    local TAU = 2 * math.pi
    local mel = { 329.6,0,0,0, 0,0,293.7,0, 329.6,0,0,0, 0,0,0,0,
                  440.0,0,0,0, 0,0,392.0,0, 329.6,0,0,0, 0,0,0,293.7,
                  493.9,0,0,0, 0,0,440.0,0, 392.0,0,0,0, 0,0,329.6,0,
                  329.6,0,0,0, 0,0,293.7,0, 329.6,0,0,0, 0,0,0,0 }
    local bass = { 82.41,82.41,82.41,82.41, 82.41,82.41,82.41,82.41,
                   82.41,82.41,82.41,82.41, 73.42,73.42,82.41,82.41,
                   110.0,110.0,110.0,110.0, 110.0,110.0,98.00,98.00,
                   82.41,82.41,82.41,82.41, 110.0,110.0,98.00,98.00,
                   98.00,98.00,110.0,110.0, 98.00,98.00,82.41,82.41,
                   73.42,73.42,73.42,73.42, 110.0,110.0,82.41,82.41,
                   82.41,82.41,82.41,82.41, 65.41,65.41,65.41,65.41,
                   82.41,82.41,82.41,82.41, 73.42,73.42,82.41,82.41 }
    local pad = { {164.8,196.0,246.9}, {146.8,174.6,220.0}, {130.8,164.8,196.0}, {110.0,130.8,164.8} }
    local buf, peak = {}, 0.0001
    for i = 0, samples - 1 do
        local t = i / RATE
        local beatIndex = math.floor(t / beatLen)
        local beatFrac = (t / beatLen) - beatIndex
        local noteIdx = (beatIndex % totalBeats) + 1
        local barIdx = math.floor(beatIndex / beatsPerBar) % bars
        local v = 0
        local mf = mel[noteIdx] or 0
        if mf > 0 then
            local env = math.min(beatFrac * 3, 1) * math.max(0, 1 - beatFrac * 0.15)
            v = v + math.sin(TAU * mf * t) * 0.09 * env
        end
        local bf = bass[noteIdx] or 82.41
        v = v + math.sin(TAU * bf * t) * 0.07 * (0.85 + math.sin(t * 0.3) * 0.15)
        v = v + math.sin(TAU * bf * 0.5 * t) * 0.04
        local ch = pad[(math.floor(barIdx / 4) % #pad) + 1]
        for _, f in ipairs(ch) do v = v + math.sin(TAU * f * t) * 0.02 end
        if beatIndex % 4 == 0 then
            local ke = math.max(0, 1 - beatFrac * 4)
            v = v + math.sin(TAU * (50 * (1 + (1 - beatFrac) * 2)) * t) * ke * 0.06
        end
        if beatIndex % 2 == 0 then
            v = v + (love.math.random() * 2 - 1) * math.max(0, 1 - beatFrac * 10) * 0.01
        end
        buf[i + 1] = v
        local a = v < 0 and -v or v
        if a > peak then peak = a end
    end
    local data = love.sound.newSoundData(samples, RATE, 16, 1)
    -- a touch hotter than the engine's 0.80 default — this sparse ambient track
    -- reads quieter than the busier Squidlite themes at the same peak
    local norm = (peak > 1 and (1 / peak) or 1) * 0.94
    for i = 1, samples do
        local s = buf[i] * norm
        if s > 1 then s = 1 elseif s < -1 then s = -1 end
        data:setSample(i - 1, s)
    end
    return data
end

Audio.themes = {
    {
        id = "deepdrive", name = "Undertow", genre = "Deep Downtempo",
        desc = "Mid-tempo groove with a soft pulse. Built to ride under the dive.", hint = "Default",
        unlock = function() return true end,
        spec = { seed = 3, bpm = 96, bars = 4, root = 43, scale = "minor",
            prog = { 0, 0, 5, 3 }, pad = true, padSus = 1.0, padVol = 0.08,
            bass = true, bassWave = "saw", bassVol = 0.24,
            bassPat = { { t = 0, d = 1.5 }, { t = 2, d = 1 }, { t = 3, d = 0.5, deg = 3 }, { t = 3.5, d = 0.5, deg = 3 } },
            arp = { rate = 2, wave = "tri", vol = 0.04, oct = 1 },
            -- relaxed backbeat, drums mixed well under the pads/bass
            drums = { { t = 0, k = true, h = true }, { t = 0.5, h = true },
                      { t = 1, s = true, h = true }, { t = 1.5, h = true },
                      { t = 2, k = true, h = true }, { t = 2.5, h = true },
                      { t = 3, s = true, h = true }, { t = 3.5, h = true, open = true } },
            kickVol = 0.42, snareVol = 0.16, snareTone = "brush", hatVol = 0.06,
            lead = true, leadWave = "tri", leadVol = 0.07, leadDensity = 4,
            leadProb = 0.4, leadVib = 0.3, leadSus = 1.0,
            sidechain = 0.32, sidechainRate = 7,
            echo = { t = 60 / 96 / 2, fb = 0.35, mix = 0.45 } },
    },
    {
        id = "abyssal", name = "Abyssal Pulse", genre = "Deep Techno",
        desc = "A slow, heavy heartbeat in the lightless deep.", hint = "Default",
        unlock = function() return true end,
        spec = { seed = 7, bpm = 92, bars = 4, root = 43, scale = "minor",
            prog = { 0, 0, 5, 3 }, pad = true, padSus = 1.0, padVol = 0.07,
            bass = true, bassWave = "saw", bassVol = 0.30,
            bassPat = { { t = 0, d = 0.9 }, { t = 1, d = 0.9 }, { t = 2, d = 0.9 }, { t = 3, d = 0.9, deg = 3 } },
            drums = { { t = 0, k = true, h = true }, { t = 1, k = true, s = true, h = true },
                      { t = 1.5, h = true }, { t = 2, k = true, h = true },
                      { t = 3, k = true, s = true, h = true }, { t = 3.5, h = true, open = true } },
            kickVol = 0.7, snareVol = 0.28, hatVol = 0.10,
            arp = { rate = 2, wave = "tri", vol = 0.05, oct = 1 },
            lead = true, leadWave = "sine", leadVol = 0.07, leadDensity = 4,
            leadProb = 0.4, leadVib = 0.4, leadSus = 1.0,
            sidechain = 0.5, sidechainRate = 8,
            echo = { t = 0.32, fb = 0.4, mix = 0.5 } },
    },
    {
        id = "lofi", name = "Sunken Lo-Fi", genre = "Lo-Fi Hip-Hop",
        desc = "Warm, dusty beats for the slow descent.", hint = "Win 1 run",
        unlock = function(s) return (s.stats.totalWins or 0) >= 1 end,
        spec = { seed = 12, bpm = 78, bars = 4, root = 48, scale = "dorian",
            prog = { 0, 3, 5, 4 }, pad = true, padSus = 1.0, padVol = 0.05,
            comp = true, compWave = "tri", compVol = 0.05, compBeats = { 0.5, 2.5 },
            bass = true, bassWave = "sine", bassVol = 0.24,
            bassPat = { { t = 0, d = 1.5 }, { t = 2, d = 1.5, deg = 2 } },
            drums = { { t = 0, k = true, h = true }, { t = 0.5, h = true },
                      { t = 1, s = true, h = true }, { t = 1.5, h = true, open = true },
                      { t = 2, k = true, h = true }, { t = 2.5, h = true },
                      { t = 3, s = true, h = true }, { t = 3.5, h = true } },
            kickVol = 0.5, snareVol = 0.26, snareTone = "brush", hatVol = 0.09,
            lead = true, leadWave = "tri", leadVol = 0.08, leadDensity = 8,
            leadProb = 0.4, leadSus = 0.7,
            echo = { t = 0.30, fb = 0.3, mix = 0.4 } },
    },
    {
        id = "synthwave", name = "Neon Trench", genre = "Synthwave",
        desc = "Retro-futuristic glow at depth.", hint = "Reach depth 4",
        unlock = function(s) return (s.stats.bestDepth or 0) >= 4 end,
        spec = { seed = 21, bpm = 104, bars = 4, root = 45, scale = "minor",
            prog = { 0, 5, 3, 4 }, pad = true, padSus = 1.0, padVol = 0.06,
            bass = true, bassWave = "saw", bassVol = 0.24,
            bassPat = { { t = 0, d = 0.5 }, { t = 1, d = 0.5 }, { t = 2, d = 0.5 },
                        { t = 3, d = 0.5 }, { t = 0.5, d = 0.5, deg = 4 } },
            drums = { { t = 0, k = true }, { t = 0.5, h = true }, { t = 1, s = true, h = true },
                      { t = 1.5, h = true }, { t = 2, k = true }, { t = 2.5, h = true },
                      { t = 3, s = true, h = true }, { t = 3.5, h = true, open = true } },
            kickVol = 0.62, snareVol = 0.3, hatVol = 0.12,
            arp = { rate = 4, wave = "saw", vol = 0.05, oct = 1 },
            lead = true, leadWave = "saw", leadVol = 0.09, leadDensity = 8,
            leadProb = 0.6, leadSus = 0.85,
            sidechain = 0.45, sidechainRate = 9,
            echo = { t = 60 / 104 / 2, fb = 0.35, mix = 0.45 } },
    },
    {
        id = "dnb", name = "Pressure Break", genre = "Drum & Bass",
        desc = "Frantic breaks under crushing depth.", hint = "Reach a 25 combo",
        unlock = function(s) return (s.stats.bestCombo or 0) >= 25 end,
        spec = { seed = 33, bpm = 172, bars = 2, root = 41, scale = "minor",
            prog = { 0, 3 }, pad = true, padSus = 1.0, padVol = 0.04,
            bass = true, bassWave = "saw", bassVol = 0.30,
            bassPat = { { t = 0, d = 2 }, { t = 2.5, d = 1.5, deg = 3 } },
            drums = { { t = 0, k = true, h = true }, { t = 0.5, h = true },
                      { t = 1, s = true }, { t = 1.75, k = true }, { t = 2, h = true },
                      { t = 2.5, k = true }, { t = 3, s = true }, { t = 3.5, h = true, open = true } },
            kickVol = 0.62, snareVol = 0.34, hatVol = 0.12,
            lead = true, leadWave = "square", leadVol = 0.07, leadDensity = 8,
            leadProb = 0.5, leadSus = 0.5,
            sidechain = 0.4, sidechainRate = 11,
            echo = { t = 60 / 172, fb = 0.3, mix = 0.35 } },
    },
    {
        id = "jazz", name = "Midnight Current", genre = "Noir Jazz",
        desc = "Smoky, brushed, walking the dark.", hint = "Win 3 runs",
        unlock = function(s) return (s.stats.totalWins or 0) >= 3 end,
        spec = { seed = 44, bpm = 96, bars = 4, root = 46, scale = "dorian",
            prog = { 0, 3, 4, 1 }, comp = true, compWave = "tri", compVol = 0.06,
            compBeats = { 0.66, 1.66, 2.66, 3.66 },
            bass = true, bassWave = "sine", bassVol = 0.26,
            bassPat = { { t = 0, d = 1 }, { t = 1, d = 1, deg = 2 },
                        { t = 2, d = 1, deg = 4 }, { t = 3, d = 1, deg = 1 } },
            drums = { { t = 0, k = true, h = true }, { t = 0.66, h = true },
                      { t = 1, s = true }, { t = 1.66, h = true, open = true },
                      { t = 2, k = true, h = true }, { t = 2.66, h = true },
                      { t = 3, s = true }, { t = 3.66, h = true } },
            kickVol = 0.4, snareVol = 0.22, snareTone = "brush", hatVol = 0.08,
            lead = true, leadWave = "saw", leadVol = 0.08, leadDensity = 6,
            leadProb = 0.55, leadVib = 0.6, leadSus = 0.8,
            echo = { t = 0.33, fb = 0.25, mix = 0.3 } },
    },
    {
        id = "choir", name = "Hymn of the Deep", genre = "Abyssal Choir",
        desc = "Sacred voices singing into the dark.", hint = "Defeat the Maw",
        unlock = function(s) return (s.stats.totalWins or 0) >= 1 end,
        spec = { seed = 55, bpm = 58, bars = 4, root = 43, scale = "minor",
            prog = { 0, 5, 3, 6 }, pad = true, padSus = 1.0, padVol = 0.12,
            bass = true, bassWave = "sine", bassVol = 0.18,
            bassPat = { { t = 0, d = 4 } },
            lead = true, leadWave = "sine", leadVol = 0.08, leadDensity = 2,
            leadProb = 0.6, leadVib = 0.5, leadSus = 1.4,
            echo = { t = 0.55, fb = 0.5, mix = 0.7 } },
    },
    -- HADAL themes (hadal = true): the eerie music for the deep below the Maw.
    -- These live in their own picker, not the main soundtrack list.
    {
        id = "hollow", name = "The Hollow", genre = "Abyssal Horror", hadal = true, hadalDefault = true,
        desc = "The original dread from below the trench — the default Hadal track.",
        hint = "Beat 1 run",
        unlock = function(s) return (s.stats.totalWins or 0) >= 1 end,
        spec = { seed = 66, bpm = 72, bars = 4, root = 39, scale = "minor",
            prog = { 0, 1, 5, 1 },                 -- the minor-2nd gives the unease
            pad = true, padSus = 1.0, padVol = 0.14,
            bass = true, bassWave = "saw", bassVol = 0.24, bassPat = { { t = 0, d = 4 } },
            drums = { { t = 0, k = true }, { t = 2.5, k = true }, { t = 3, s = true } },
            kickVol = 0.6, snareVol = 0.2, snareTone = "brush",
            lead = true, leadWave = "sine", leadVol = 0.06, leadDensity = 2,
            leadProb = 0.5, leadVib = 0.85, leadSus = 1.7,
            sidechain = 0.3, sidechainRate = 6,
            echo = { t = 0.5, fb = 0.55, mix = 0.7 } },
    },
    {
        id = "unblinking", name = "The Unblinking", genre = "Stalking Dread", hadal = true,
        desc = "Creeping, unresolved tension — hiding while unblinking eyes drift past.",
        hint = "Defeat 30 Churgspawn",
        unlock = function(s) return (s.bestiary and (s.bestiary.churgspawn or 0) or 0) >= 30 end,
        -- Same tense Hadal family as The Hollow, but RHYTHMIC instead of ambient:
        -- a nervous ticking pulse + a creeping syncopated bass + stabs that never
        -- resolve. The feeling of holding still while something circles.
        spec = { seed = 77, bpm = 76, bars = 4, root = 40, scale = "minor",
            prog = { 0, 6, 1, 5 }, pad = true, padSus = 1.0, padVol = 0.13,
            bass = true, bassWave = "pulse", bassVol = 0.30,
            bassPat = { { t = 0, d = 0.5 }, { t = 0.75, d = 0.5 }, { t = 2, d = 0.5, deg = 1 }, { t = 2.75, d = 0.5 } },
            drums = { { t = 0, k = true, h = true }, { t = 0.5, h = true }, { t = 1, h = true },
                      { t = 1.5, h = true }, { t = 2, k = true, h = true }, { t = 2.5, h = true },
                      { t = 3, h = true }, { t = 3.5, h = true } },
            kickVol = 0.55, hatVol = 0.06,
            lead = true, leadWave = "tri", leadVol = 0.07, leadDensity = 4,
            leadProb = 0.35, leadVib = 0.7, leadSus = 0.9,
            sidechain = 0.32, sidechainRate = 7,
            echo = { t = 0.5, fb = 0.5, mix = 0.65 } },
    },
    {
        id = "duskmaw", name = "Duskmaw", genre = "Drone Horror", hadal = true,
        desc = "A free gift for surfacing alive — a slow, suffocating drone.",
        hint = "Free — beat 1 run",
        unlock = function(s) return (s.stats.totalWins or 0) >= 1 end,
        -- No drums: loud transients would just normalize the drone DOWN. Instead
        -- the sustained pad/bass/lead are cranked so the drone itself is loud.
        spec = { seed = 201, bpm = 56, bars = 4, root = 41, scale = "minor",
            prog = { 0, 5, 1, 6 }, pad = true, padSus = 1.0, padVol = 0.55,
            bass = true, bassWave = "sine", bassVol = 0.55, bassPat = { { t = 0, d = 4 } },
            lead = true, leadWave = "sine", leadVol = 0.26, leadDensity = 2,
            leadProb = 0.55, leadVib = 0.9, leadSus = 2.0,
            echo = { t = 0.62, fb = 0.55, mix = 0.7 } },
    },
    {
        id = "leviathong", name = "Leviathan", genre = "Abyssal Groan", hadal = true,
        desc = "The slow, rhythmic groan of something vast turning over in the dark.",
        hint = "Reach depth 13 (the Eldritch Squid)",
        unlock = function(s) return (s.stats.bestDepth or 0) >= 13 end,
        -- Distinct from Hollow: lower, RHYTHMIC and churning — a heartbeat pulse,
        -- a pumping low saw bass, a churning undercurrent arp and a buzzy groan.
        spec = { seed = 202, bpm = 60, bars = 4, root = 33, scale = "minor",
            prog = { 0, 0, 6, 1 }, pad = true, padSus = 1.0, padVol = 0.13,
            bass = true, bassWave = "saw", bassVol = 0.38,
            bassPat = { { t = 0, d = 0.75 }, { t = 1, d = 0.75 }, { t = 2, d = 0.75, deg = 1 }, { t = 3, d = 0.75 } },
            arp = { rate = 1, wave = "saw", vol = 0.08, oct = 0 },        -- low churning undercurrent
            drums = { { t = 0, k = true }, { t = 1.5, k = true }, { t = 2, k = true }, { t = 3.5, k = true } },
            kickVol = 0.72,
            lead = true, leadWave = "saw", leadVol = 0.09, leadDensity = 2,
            leadProb = 0.5, leadVib = 1.5, leadSus = 1.5,
            echo = { t = 0.5, fb = 0.48, mix = 0.55 } },
    },
    {
        id = "thalasso", name = "Thalassophobia", genre = "Dread Ambient", hadal = true,
        desc = "The cold certainty that you are not alone down here.",
        hint = "Win 3 runs",
        unlock = function(s) return (s.stats.totalWins or 0) >= 3 end,
        -- sustained levels cranked (no drum transients to normalize it down)
        spec = { seed = 203, bpm = 64, bars = 4, root = 38, scale = "dorian",
            prog = { 0, 3, 1, 5 }, pad = true, padSus = 1.0, padVol = 0.62,
            comp = true, compWave = "tri", compVol = 0.26, compBeats = { 1.5, 3.5 },
            bass = true, bassWave = "sine", bassVol = 0.58, bassPat = { { t = 0, d = 2 }, { t = 2, d = 2, deg = 1 } },
            lead = true, leadWave = "tri", leadVol = 0.34, leadDensity = 2,
            leadProb = 0.5, leadVib = 0.8, leadSus = 1.8,
            echo = { t = 0.58, fb = 0.5, mix = 0.68 } },
    },
    {
        id = "sonar", name = "Lost Sonar", genre = "Isolation Ambient", hadal = true,
        desc = "Clean pings into the void — and the long wait for an echo that means harm.",
        hint = "Reach depth 11",
        unlock = function(s) return (s.stats.bestDepth or 0) >= 11 end,
        -- Unique: sparse, clean sonar PINGS (short sine notes) over a deep drone,
        -- with a huge echo tail. Nothing else in the deep sounds like it.
        -- raise the AMBIENCE (pad/bass) so the pings don't normalize it into silence
        spec = { seed = 205, bpm = 52, bars = 4, root = 45, scale = "pentatonic",
            prog = { 0, 0, 4, 0 }, pad = true, padSus = 1.0, padVol = 0.46,
            bass = true, bassWave = "sine", bassVol = 0.46, bassPat = { { t = 0, d = 4 } },
            lead = true, leadWave = "sine", leadVol = 0.18, leadDensity = 2,
            leadProb = 0.4, leadVib = 0.1, leadSus = 0.22,
            echo = { t = 0.66, fb = 0.62, mix = 0.82 } },
    },
    {
        id = "fractalrot", name = "Fractal Rot", genre = "Void Eerie", hadal = true,
        desc = "Music from a place that should not have any. The god's own quiet.",
        hint = "Slay the Churgly'nth",
        unlock = function(s) return s.achievements and s.achievements.churgly_slain == true end,
        spec = { seed = 204, bpm = 68, bars = 4, root = 37, scale = "minor",
            prog = { 0, 1, 6, 1 }, pad = true, padSus = 1.0, padVol = 0.13,
            -- smooth tri sub (was a buzzy saw); the eerie melody/arp sit on top
            bass = true, bassWave = "tri", bassVol = 0.16, bassPat = { { t = 0, d = 4 } },
            arp = { rate = 2, wave = "sine", vol = 0.085, oct = 2 },
            -- a soft triangle lead (woodwind/ocarina-ish) instead of pure sine,
            -- with a deeper wavering vibrato for the void-eerie character
            lead = true, leadWave = "tri", leadVol = 0.13, leadDensity = 3,
            leadProb = 0.6, leadVib = 1.8, leadSus = 1.6,
            sidechain = 0.2, sidechainRate = 5, distort = 1.0,
            echo = { t = 0.5, fb = 0.55, mix = 0.72 } },
    },
    -- BOSS-ONLY themes (hidden from the music picker). Played by the Eldritch
    -- Squid fight: distorted, breakneck breakcore — and a hellish terror variant.
    {
        id = "breakcore", name = "Core Breach", genre = "Dark Driving", hidden = true,
        desc = "", hint = "", unlock = function() return false end,
        spec = { seed = 91, bpm = 138, bars = 4, root = 38, scale = "minor",
            -- a graver, more menacing progression (the b2 gives the dread)
            prog = { 0, 0, 1, 5 }, pad = true, padSus = 1.0, padVol = 0.13,
            bass = true, bassWave = "saw", bassVol = 0.34,
            -- heavy, deliberate bassline — weight over flash
            bassPat = { { t = 0, d = 1.5 }, { t = 2, d = 1 }, { t = 3, d = 0.5, deg = 1 }, { t = 3.5, d = 0.5 } },
            arp = { rate = 2, wave = "tri", vol = 0.035, oct = 1 },
            -- a solid, pounding driving beat (not chaotic) — controlled menace
            drums = { { t = 0, k = true, h = true }, { t = 0.5, h = true },
                      { t = 1, s = true, h = true }, { t = 1.5, h = true },
                      { t = 2, k = true, h = true }, { t = 2.5, k = true },
                      { t = 3, s = true, h = true }, { t = 3.5, h = true, open = true } },
            kickVol = 0.78, snareVol = 0.3, snareTone = "brush", hatVol = 0.08,
            -- a sparse, ominous lead rather than a frantic one
            lead = true, leadWave = "tri", leadVol = 0.08, leadDensity = 2,
            leadProb = 0.5, leadVib = 0.5, leadSus = 1.3,
            sidechain = 0.4, sidechainRate = 7, distort = 1.3,
            echo = { t = 60 / 138, fb = 0.4, mix = 0.5 } },
    },
    {
        id = "terrorcore", name = "Hell Below", genre = "Terrorcore", hidden = true,
        desc = "", hint = "", unlock = function() return false end,
        spec = { seed = 666, bpm = 166, bars = 2, root = 38, scale = "minor",
            prog = { 0, 1, 5, 1 }, pad = true, padSus = 1.0, padVol = 0.05,
            bass = true, bassWave = "saw", bassVol = 0.36,
            bassPat = { { t = 0, d = 0.5 }, { t = 1, d = 0.5, deg = 1 }, { t = 1.5, d = 0.5 },
                        { t = 2, d = 0.5, deg = 3 }, { t = 3, d = 0.5 }, { t = 3.5, d = 0.5, deg = 1 } },
            arp = { rate = 2, wave = "saw", vol = 0.06, oct = 2 },
            -- harder, darker break with a gabber double-kick, still groovy
            drums = { { t = 0, k = true, h = true }, { t = 0.5, h = true },
                      { t = 1, s = true, h = true }, { t = 1.5, k = true }, { t = 1.75, k = true },
                      { t = 2, k = true, h = true }, { t = 2.5, h = true },
                      { t = 3, s = true, h = true }, { t = 3.5, k = true, h = true, open = true } },
            kickVol = 0.82, snareVol = 0.38, hatVol = 0.12,
            -- overdriven saw lead = a distorted-guitar wail (now tasteful, not pure fuzz)
            lead = true, leadWave = "saw", leadVol = 0.11, leadDensity = 4,
            leadProb = 0.55, leadVib = 0.2, leadSus = 0.55,
            sidechain = 0.45, sidechainRate = 10, distort = 2.4,
            echo = { t = 60 / 166 / 2, fb = 0.24, mix = 0.28 } },
    },
    -- The Churgly'nth (final-final boss): a dissonant, heavier void-breakcore.
    {
        id = "voidcore", name = "Fractal Throat", genre = "Voidcore", hidden = true,
        desc = "", hint = "", unlock = function() return false end,
        spec = { seed = 1313, bpm = 158, bars = 2, root = 37, scale = "minor",
            prog = { 0, 1, 6, 1 }, pad = true, padSus = 1.0, padVol = 0.06,
            bass = true, bassWave = "saw", bassVol = 0.36,
            bassPat = { { t = 0, d = 0.75 }, { t = 1, d = 0.5, deg = 1 }, { t = 1.5, d = 0.5, deg = 4 },
                        { t = 2, d = 0.75, deg = 3 }, { t = 3, d = 0.5, deg = 1 }, { t = 3.5, d = 0.5 } },
            arp = { rate = 2, wave = "saw", vol = 0.07, oct = 2 },
            drums = { { t = 0, k = true, h = true }, { t = 0.5, h = true, open = true },
                      { t = 1, s = true, h = true }, { t = 1.5, k = true }, { t = 1.75, k = true },
                      { t = 2, k = true, h = true }, { t = 2.5, h = true },
                      { t = 3, s = true, h = true }, { t = 3.5, s = true, h = true, open = true } },
            kickVol = 0.84, snareVol = 0.4, hatVol = 0.12,
            lead = true, leadWave = "saw", leadVol = 0.12, leadDensity = 4,
            leadProb = 0.62, leadVib = 0.5, leadSus = 0.5,
            sidechain = 0.48, sidechainRate = 11, distort = 2.8,
            echo = { t = 60 / 158 / 2, fb = 0.3, mix = 0.32 } },
    },
    -- ---- extra themed boss tracks for custom campaigns (music selector) ----
    {   -- slow, crushing abyssal doom
        id = "tidalwrath", name = "Tidal Wrath", genre = "Abyssal Doom", hidden = true,
        desc = "", hint = "", unlock = function() return false end,
        spec = { seed = 207, bpm = 84, bars = 4, root = 38, scale = "minor",
            prog = { 0, 0, 6, 5 }, pad = true, padSus = 1.5, padVol = 0.20,   -- vast dread atmosphere
            bass = true, bassWave = "tri", bassVol = 0.38,     -- clean, HEAVY tri sub (no saw crackle)
            -- slow, weighty low end that heaves rather than pulses
            bassPat = { { t = 0, d = 1.5 }, { t = 1.5, d = 0.5, deg = 1 }, { t = 2, d = 1, deg = 3 },
                        { t = 3, d = 0.5 }, { t = 3.5, d = 0.5, deg = 1 } },
            arp = { rate = 1, wave = "tri", vol = 0.025, oct = 1 },           -- subtle, NOT a synthy saw arp
            -- a full, groovy backbeat: kick 1&3 (+a syncopated kick for swing),
            -- snare 2&4, steady 8th-note hats with an open-hat accent. Slow & heavy,
            -- not machine-gun fast and not a bare boom-ch.
            drums = { { t = 0, k = true, h = true }, { t = 0.5, h = true },
                      { t = 1, s = true, h = true }, { t = 1.5, h = true },
                      { t = 2, k = true, h = true }, { t = 2.5, k = true, h = true },
                      { t = 3, s = true, h = true }, { t = 3.5, h = true, open = true } },
            kickVol = 0.9, snareVol = 0.4, snareTone = "brush", hatVol = 0.08,
            -- a slow, brooding, menacing lead (a dread melody, not a fast wail)
            lead = true, leadWave = "tri", leadVol = 0.11, leadDensity = 2,
            leadProb = 0.5, leadVib = 0.7, leadSus = 2.4,
            sidechain = 0.55, sidechainRate = 5, distort = 1.4,
            echo = { t = 60 / 84, fb = 0.5, mix = 0.58 } },
    },
    {   -- driving darksynth / outrun predator
        id = "neonhunt", name = "Neon Predator", genre = "Darksynth", hidden = true,
        desc = "", hint = "", unlock = function() return false end,
        spec = { seed = 84, bpm = 122, bars = 4, root = 40, scale = "minor",
            prog = { 0, 5, 3, 4 }, pad = true, padSus = 0.9, padVol = 0.10,
            bass = true, bassWave = "saw", bassVol = 0.32,
            bassPat = { { t = 0, d = 0.5 }, { t = 0.5, d = 0.5 }, { t = 1, d = 0.5 }, { t = 1.5, d = 0.5 },
                        { t = 2, d = 0.5 }, { t = 2.5, d = 0.5 }, { t = 3, d = 0.5, deg = 1 }, { t = 3.5, d = 0.5 } },
            arp = { rate = 4, wave = "saw", vol = 0.07, oct = 2 },
            drums = { { t = 0, k = true, h = true }, { t = 0.5, h = true },
                      { t = 1, s = true, h = true }, { t = 1.5, h = true },
                      { t = 2, k = true, h = true }, { t = 2.5, h = true },
                      { t = 3, s = true, h = true }, { t = 3.5, h = true } },
            kickVol = 0.74, snareVol = 0.3, hatVol = 0.10,
            lead = true, leadWave = "saw", leadVol = 0.12, leadDensity = 3,
            leadProb = 0.6, leadVib = 0.6, leadSus = 0.9,
            sidechain = 0.5, sidechainRate = 8, distort = 1.4,
            echo = { t = 60 / 122 / 2, fb = 0.4, mix = 0.42 } },
    },
    {   -- gothic phrygian dread, choir-like sustained lead
        id = "bonechoir", name = "Bone Choir", genre = "Gothic Dread", hidden = true,
        desc = "", hint = "", unlock = function() return false end,
        spec = { seed = 313, bpm = 96, bars = 4, root = 37, scale = "phrygian",
            prog = { 0, 1, 0, 6 }, pad = true, padSus = 1.5, padVol = 0.18,
            bass = true, bassWave = "tri", bassVol = 0.34,
            bassPat = { { t = 0, d = 1.5 }, { t = 2, d = 1, deg = 1 }, { t = 3, d = 1 } },
            arp = { rate = 2, wave = "sine", vol = 0.04, oct = 1 },
            drums = { { t = 0, k = true }, { t = 1.5, s = true }, { t = 2, k = true }, { t = 3.5, s = true } },
            kickVol = 0.7, snareVol = 0.3, snareTone = "brush", hatVol = 0.05,
            lead = true, leadWave = "sine", leadVol = 0.10, leadDensity = 1,
            leadProb = 0.45, leadVib = 0.8, leadSus = 2.2,
            sidechain = 0.3, sidechainRate = 5, distort = 1.1,
            echo = { t = 60 / 96, fb = 0.5, mix = 0.6 } },
    },
    {   -- fast, savage neurofunk / drum & bass
        id = "bloodtide", name = "Bloodtide", genre = "Neurofunk", hidden = true,
        desc = "", hint = "", unlock = function() return false end,
        spec = { seed = 174, bpm = 174, bars = 2, root = 39, scale = "minor",
            prog = { 0, 0, 5, 1 }, pad = true, padSus = 0.8, padVol = 0.06,
            bass = true, bassWave = "saw", bassVol = 0.38,
            bassPat = { { t = 0, d = 0.5 }, { t = 1, d = 0.5, deg = 1 }, { t = 2, d = 0.5, deg = 3 },
                        { t = 2.5, d = 0.5 }, { t = 3, d = 0.5, deg = 1 } },
            arp = { rate = 4, wave = "saw", vol = 0.05, oct = 2 },
            drums = { { t = 0, k = true, h = true }, { t = 0.5, h = true },
                      { t = 1, s = true, h = true }, { t = 1.75, k = true },
                      { t = 2.5, k = true, h = true }, { t = 2.75, s = true },
                      { t = 3, h = true }, { t = 3.5, s = true, h = true, open = true } },
            kickVol = 0.8, snareVol = 0.4, hatVol = 0.12,
            lead = true, leadWave = "saw", leadVol = 0.10, leadDensity = 4,
            leadProb = 0.5, leadVib = 0.3, leadSus = 0.5,
            sidechain = 0.5, sidechainRate = 12, distort = 2.2,
            echo = { t = 60 / 174 / 2, fb = 0.25, mix = 0.3 } },
    },
    -- a regular soundtrack ported from the player's first game — earned, not given
    {
        id = "genesis", name = "Genesis", genre = "Ambient Exploration",
        desc = "The first song — carried in from the dawn of the Claude universe.",
        hint = "Win 5 runs",
        unlock = function(s) return (s.stats.totalWins or 0) >= 5 end,
        build = composeGenesis,   -- custom builder (faithful port), not a spec
    },
}
Audio.themeById = {}
for _, t in ipairs(Audio.themes) do Audio.themeById[t.id] = t end

----------------------------------------------------------------------
-- SFX
----------------------------------------------------------------------
local function sfxData(builder)
    return builder()
end

-- A short SFX synth: returns SoundData.
local function tone(freq, dur, vol, wave, fall, sweep)
    local n = math.floor(dur * RATE)
    local data = love.sound.newSoundData(n, RATE, 16, 1)
    for i = 0, n - 1 do
        local t = i / RATE
        local env = math.max(0, 1 - t / dur) ^ (fall or 1)
        local f = freq * (sweep and (1 + sweep * (t / dur)) or 1)
        data:setSample(i, osc(wave or "sine", 2 * math.pi * f * t) * (vol or 0.3) * env)
    end
    return data
end

local function noiseBurst(dur, vol, fall)
    local n = math.floor(dur * RATE)
    local data = love.sound.newSoundData(n, RATE, 16, 1)
    for i = 0, n - 1 do
        local t = i / RATE
        local env = math.max(0, 1 - t / dur) ^ (fall or 2)
        data:setSample(i, (love.math.random() * 2 - 1) * (vol or 0.3) * env)
    end
    return data
end

Audio.sfx = {}
Audio.sources = {}

local function defSfx(name, builder)
    Audio.sfx[name] = builder
end

defSfx("shoot",   function() return tone(620, 0.10, 0.25, "square", 2, -0.5) end)
defSfx("dash",    function() return tone(180, 0.22, 0.30, "saw", 1.5, 3.0) end)
defSfx("hit",     function() return tone(300, 0.08, 0.22, "square", 2, -0.4) end)
defSfx("enemyDie",function() return noiseBurst(0.20, 0.30, 2) end)
defSfx("hurt",    function() return tone(150, 0.30, 0.35, "saw", 1.5, -0.6) end)
defSfx("pickup",  function() return tone(880, 0.12, 0.22, "sine", 2, 0.8) end)
defSfx("coin",    function() return tone(1320, 0.10, 0.20, "square", 2, 0.5) end)
defSfx("upgrade", function() return tone(523, 0.30, 0.25, "tri", 1.5, 1.0) end)
defSfx("click",   function() return tone(440, 0.05, 0.18, "square", 2) end)
defSfx("hover",   function() return tone(660, 0.03, 0.10, "sine", 2) end)
defSfx("win",     function() return tone(523, 0.6, 0.3, "tri", 1.2, 1.5) end)
defSfx("lose",    function() return tone(220, 0.8, 0.32, "saw", 1.2, -0.55) end)
defSfx("boss",    function() return tone(60, 1.0, 0.45, "saw", 1.0, 0.3) end)
defSfx("buy",     function() return tone(700, 0.25, 0.25, "square", 1.5, 1.2) end)
defSfx("denied",  function() return tone(160, 0.18, 0.25, "square", 2, -0.3) end)
defSfx("screech", function() return tone(1500, 0.34, 0.26, "saw", 2.2, -0.78) end)   -- husk crawler death
defSfx("clank",   function() return tone(1250, 0.09, 0.22, "square", 3.5, -0.5) end)  -- bullet off chitin head armor
defSfx("crack",   function() return noiseBurst(0.16, 0.30, 3) end)                    -- husk crawler segment breaks off

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------
local musicSrc = nil
local musicTheme = nil
local musicVol = 0.7
local sfxVol = 0.8
local musicCache = {}

function Audio.init(save)
    if save then
        musicVol = save.settings.musicVolume or 0.7
        sfxVol = save.settings.sfxVolume or 0.8
    end
    -- Pre-build SFX sources (cheap; short buffers).
    for name, builder in pairs(Audio.sfx) do
        Audio.sources[name] = love.audio.newSource(sfxData(builder), "static")
    end
end

local recent = {}
function Audio.play(name, vol)
    local base = Audio.sources[name]
    if not base then return end
    -- de-dupe very rapid identical triggers to avoid clipping
    local now = love.timer.getTime()
    if recent[name] and now - recent[name] < 0.02 then return end
    recent[name] = now
    local s = base:clone()
    s:setVolume((vol or 1) * sfxVol)
    s:play()
end

-- Build raw SoundData for a theme (used by the audio analyzer / tooling).
function Audio.buildData(id)
    local theme = Audio.themeById[id] or Audio.themeById["deepdrive"]
    return (theme.build and theme.build() or compose(theme.spec)), theme
end

function Audio.buildTheme(id)
    if musicCache[id] then return musicCache[id] end
    local theme = Audio.themeById[id] or Audio.themeById["deepdrive"]
    local data = theme.build and theme.build() or compose(theme.spec)   -- custom builder or spec
    local src = love.audio.newSource(data, "static")
    src:setLooping(true)
    musicCache[id] = src
    return src
end

function Audio.playMusic(id)
    if musicTheme == id and musicSrc and musicSrc:isPlaying() then return end
    if musicSrc then musicSrc:stop() end
    musicTheme = id
    musicSrc = Audio.buildTheme(id)
    musicSrc:setVolume(musicVol)
    musicSrc:play()
end

function Audio.stopMusic()
    if musicSrc then musicSrc:stop() end
    musicTheme = nil
end

function Audio.setMusicVolume(v)
    musicVol = v
    if musicSrc then musicSrc:setVolume(musicVol) end
end

function Audio.setSfxVolume(v) sfxVol = v end
function Audio.getMusicVolume() return musicVol end
function Audio.getSfxVolume() return sfxVol end

-- Main-soundtrack themes (the depths above the Maw) available given save.
function Audio.unlockedThemes(save)
    local out = {}
    for _, t in ipairs(Audio.themes) do
        if not t.hidden and not t.hadal then       -- boss + hadal themes aren't here
            out[#out + 1] = { theme = t, unlocked = t.unlock(save) }
        end
    end
    return out
end

-- The separate, eerier HADAL picker (depths past the Maw).
function Audio.hadalThemes(save)
    local out = {}
    for _, t in ipairs(Audio.themes) do
        if t.hadal then
            out[#out + 1] = { theme = t, unlocked = t.unlock(save) }
        end
    end
    return out
end

return Audio
