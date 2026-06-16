-- The Bestiary: lore entries unlocked by defeating enough of each creature
-- (lifetime, across runs). Bosses need few (Warden 3, others 1); the Leviathan
-- unlocks by SURVIVING 3 of its flyby encounters. `progress` is stored in
-- save.bestiary[id] (kills, or survives for the leviathan).
local B = {}

B.list = {
    -- ---- the trench (depths 1-8) ----
    { id = "drifter",  name = "Drifter",   need = 12, kind = "creature",
      lore = "A bell of living light that drifts toward any glow. Harmless alone; suffocating in a bloom." },
    { id = "darter",   name = "Darter",    need = 14, kind = "creature",
      lore = "A sliver of muscle and panic. Darts in straight, reckless bursts — fast, fragile, endless." },
    { id = "snapper",  name = "Snapper",   need = 10, kind = "creature",
      lore = "Armored ambusher. It reads your drift, winds back, and CHARGES across the dark with its claws." },
    { id = "spitter",  name = "Spitter",   need = 10, kind = "creature",
      lore = "A drifting urchin that coughs rings of spines. Keep moving and the gaps are always there." },
    { id = "lurker",   name = "Lurker",    need = 10, kind = "creature",
      lore = "Anglerfish of the mid-trench. It plants light-lures where you stand, then they bloom into shrapnel." },
    { id = "gulper",   name = "Gulper",    need = 10, kind = "creature",
      lore = "All mouth and hunger. Lunges in sudden bursts, trailing its own slack body behind it." },
    { id = "puffer",   name = "Puffer",    need = 10, kind = "creature",
      lore = "A swimming bomb. Gets close, inflates, and detonates. The trench's most committed creature." },
    { id = "wisp",     name = "Wisp",      need = 10, kind = "creature",
      lore = "A ghost-light that blinks across the water to reappear at your shoulder." },

    -- ---- the Hadal Depths (post-Maw) ----
    { id = "parasite", name = "Flesh Parasite", need = 16, kind = "creature",
      lore = "Dark-red leech of the hollow. Adrift, it thrashes in a constant, mindless panic — and only goes still once it has latched onto a host and begun to drink. You can't shake it off, so don't let it bite." },
    { id = "terror",   name = "Abyssal Terror", need = 8, kind = "creature",
      lore = "An amalgamation of biomass — countless dead things crushed and fused into one roiling knot of eyes and tendrils. The signature horror below the Maw: fast, and it hits hard." },
    { id = "unseen",   name = "The Unseen", need = 8, kind = "creature",
      lore = "You never make it out — only two dim eyes drifting at you in the black. Best you don't." },
    { id = "brood",    name = "Brood Sac", need = 8, kind = "creature",
      lore = "A swollen host. Kill it carelessly in a crowd and it bursts into a writhing knot of parasites." },
    { id = "phantom",  name = "Phantom",   need = 8, kind = "creature",
      lore = "A wraith that blinks toward you and leaves a rift of ink where it stood. Read the flicker." },
    { id = "wormsing", name = "Worm Singularity", need = 6, kind = "creature",
      lore = "Everything about this thing is unknown. All anyone can say is that its worms seem to be swimming away from something — frantically, forever — though there SEEMS to be nothing there at the center they flee. It drags you toward it all the same." },
    { id = "churgspawn", name = "Churgspawn", need = 8, kind = "creature",
      lore = "A castoff of the corruption beyond the gate. It drags itself along on long, boneless arms that whip out to seize you, and it leaves a smear of glowing bile wherever it crawls — a toxic trail that lingers and burns long after the thing is gone. Cut it down quickly, then mind where it has been." },
    { id = "crawler",  name = "Husk Crawler", need = 1, kind = "creature",
      lore = "A long, pale roach-thing of the deep. Its head is plated in armor — shots barely scratch it and only knock it aside. Strike the SEGMENTS along its back instead: they tear away one by one, shortening it, until the last falls and it screeches into nothing. It turns slowly, so circle behind it and shred the spine. Its bite carries a foul venom that keeps draining you — bring LIFESTEAL or you will rot before it dies." },

    -- ---- bosses ----
    { id = "warden",   name = "The Warden", need = 3, kind = "boss",
      lore = "Armored guardian of the mid-trench. It rings the arena in fire on a steady, merciless beat." },
    { id = "maw",      name = "The Maw",    need = 1, kind = "boss",
      lore = "Gatekeeper of the Challenger Deep — the trench floor the charts call Site: Acheron. It coils before a vast, ancient gate, and it was never the end. Only the door to what waits below." },
    { id = "eldritch", name = "The Eldritch Squid", need = 1, kind = "boss",
      lore = "The thing that ate the light, wearing a squid's shape. Slay it and the trapped squids go free." },

    -- ---- the leviathans (survive their flyby) ----
    { id = "leviathan", name = "Hadal Leviathan", need = 3, kind = "event",
      lore = "Vast beyond reckoning. It passes through the deep on its own errand, spitting toxic bile, and is gone. You do not fight it. You get out of its way." },
}

B.byId = {}
for _, e in ipairs(B.list) do B.byId[e.id] = e end

function B.progress(save, id) return (save.bestiary and save.bestiary[id]) or 0 end
function B.isUnlocked(save, id)
    local e = B.byId[id]; if not e then return false end
    return B.progress(save, id) >= e.need
end
function B.countUnlocked(save)
    local n = 0
    for _, e in ipairs(B.list) do if B.isUnlocked(save, e.id) then n = n + 1 end end
    return n
end

return B
