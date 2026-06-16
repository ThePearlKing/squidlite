-- In-run mutations. Between depths the player picks 1 of 3 offered upgrades.
-- apply(p) mutates the live player. `unique` upgrades are removed from the pool
-- once taken; others can stack. `weight` biases the random offer.
local Up = {}

Up.list = {
    -- ---- common stat stacks ----
    { id="power",     name="Toxin Glands",   rarity="common", weight=10,
      desc="+28% ink damage.", apply=function(p) p.inkDamage = p.inkDamage * 1.28 end },
    { id="rapid",     name="Hair Trigger",   rarity="common", weight=10,
      desc="+22% fire rate.", apply=function(p) p.fireRate = p.fireRate * 1.22 end },
    { id="firerate",  name="Twitch Reflex",  rarity="common", weight=10,
      desc="+25% fire rate.", apply=function(p) p.fireRate = p.fireRate * 1.25 end },
    { id="damage",    name="Caustic Ink",    rarity="common", weight=10,
      desc="+32% ink damage.", apply=function(p) p.inkDamage = p.inkDamage * 1.32 end },
    { id="speed",     name="Streamlined",    rarity="common", weight=9,
      desc="+14% move speed.", apply=function(p) p.maxSpeed = p.maxSpeed * 1.14; p.accel = p.accel * 1.14 end },
    { id="hp",        name="Thick Mantle",   rarity="common", weight=9,
      desc="+30 max shell (healed).", apply=function(p) p.maxHp = p.maxHp + 30; p.hp = p.hp + 30 end },
    { id="proj_speed",name="High Pressure",  rarity="common", weight=8,
      desc="+30% ink velocity & range.", apply=function(p) p.inkSpeed = p.inkSpeed * 1.30; p.inkRange = p.inkRange * 1.2 end },

    -- ---- rare ----
    { id="multishot", name="Split Stream",   rarity="rare", weight=6,
      desc="+1 ink projectile (more spread).", apply=function(p) p.projectiles = p.projectiles + 1 end },
    { id="pierce",    name="Needle Ink",     rarity="rare", weight=6,
      desc="Ink pierces +1 enemy.", apply=function(p) p.pierce = p.pierce + 1 end },
    { id="regenhp",   name="Regenerator",    rarity="rare", weight=5,
      desc="Slowly heal +1.5 shell/sec.", apply=function(p) p.regen = p.regen + 1.5 end },
    { id="dashcd",    name="Twin Siphon",    rarity="rare", weight=5,
      desc="-32% dash cooldown.", apply=function(p) p.dashCooldown = p.dashCooldown * 0.68 end },
    { id="magnet",    name="Lure Field",     rarity="rare", weight=6,
      desc="+80% pickup range.", apply=function(p) p.magnet = p.magnet * 1.8 end },
    { id="crit",      name="Weak Points",    rarity="rare", weight=6,
      desc="+15% crit chance (2x dmg).", apply=function(p) p.critChance = p.critChance + 0.15 end },

    -- ---- epic (build-defining, mostly unique) ----
    { id="homing",    name="Hunter Ink",     rarity="epic", weight=4, unique=true,
      desc="Ink curves toward enemies.", apply=function(p) p.homing = math.min(1, p.homing + 0.6) end },
    { id="explosive", name="Bursting Ink",   rarity="epic", weight=4, unique=true,
      desc="Ink explodes on impact.", apply=function(p) p.explosive = true end },
    { id="cloud",     name="Ink Veil",       rarity="epic", weight=4, unique=true,
      desc="Dashing leaves a damaging ink cloud.", apply=function(p) p.dashCloud = true end },
    { id="lifesteal", name="Vampire Squid",  rarity="epic", weight=4, unique=true,
      desc="Heal 4% of damage dealt.", apply=function(p) p.lifesteal = p.lifesteal + 0.04 end },
    { id="thorns",    name="Barbed Skin",    rarity="epic", weight=4, unique=true,
      desc="Attackers take 50% of their damage back.", apply=function(p) p.thorns = p.thorns + 0.5 end },
    { id="split",     name="Spawnbomb",      rarity="epic", weight=3, unique=true,
      desc="Kills burst 3 homing ink shards.", apply=function(p) p.splitOnKill = true end },
    { id="bounce",    name="Ricochet",       rarity="epic", weight=4, unique=true,
      desc="Ink bounces off walls once.", apply=function(p) p.bounce = p.bounce + 1 end },

    -- ---- legendary (rare, powerful) ----
    { id="overload",  name="Overcharge",     rarity="legendary", weight=2, unique=true,
      desc="Big damage & fire rate — but fragile (-25% shell).",
      apply=function(p) p.inkDamage = p.inkDamage * 1.6; p.fireRate = p.fireRate * 1.4
          p.maxHp = p.maxHp * 0.75; p.hp = math.min(p.hp, p.maxHp) end },
    { id="berserk",   name="Trench Rage",    rarity="legendary", weight=2, unique=true,
      desc="The lower your shell, the more damage you deal (up to +80%).",
      apply=function(p) p.berserk = true end },
}

Up.byId = {}
for _, u in ipairs(Up.list) do Up.byId[u.id] = u end

local rarityRoll = {
    common = 10, rare = 5, epic = 2, legendary = 1,
}

-- Offer `n` distinct upgrades, excluding uniques already taken.
function Up.offer(taken, n, force)
    n = n or 3
    local pool = {}
    for _, u in ipairs(Up.list) do
        if not (u.unique and taken[u.id]) then
            pool[#pool + 1] = u
        end
    end
    -- weighted sampling without replacement
    local picks = {}
    for _ = 1, math.min(n, #pool) do
        local total = 0
        for _, u in ipairs(pool) do total = total + (u.weight or 5) end
        local r = love.math.random() * total
        local idx = 1
        for i, u in ipairs(pool) do
            r = r - (u.weight or 5)
            if r <= 0 then idx = i; break end
        end
        picks[#picks + 1] = pool[idx]
        table.remove(pool, idx)
    end
    -- force a specific upgrade into the offer (if available and not already shown)
    if force and not taken[force] then
        local has = false
        for _, u in ipairs(picks) do if u.id == force then has = true; break end end
        if not has then
            for _, u in ipairs(Up.list) do
                if u.id == force then picks[#picks] = u; break end
            end
        end
    end
    return picks
end

return Up
