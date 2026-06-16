-- Run modifiers. Chosen before a run, they tweak gameplay AND scale the
-- $Things / score payout. "Perils" make the run harder and pay MORE (pointMult
-- > 1). "Mercies" make it easier and pay LESS (pointMult < 1). The net payout
-- multiplier is the product of every active modifier's pointMult. Winning with
-- a net multiplier below 1 counts as a "curse win".
local P = require("src.palette")
local M = {}

-- effect fields default to 1 (multiplicative) or false (flags) when omitted.
M.list = {
    -- ---------- PERILS (harder, pay more) ----------
    { id="bloodthirst", name="Bloodthirst", kind="peril", pointMult=1.30, color=P.red,
      enemyDmg=1.35, desc="Creatures hit 35% harder." },
    { id="ironhide", name="Ironhide", kind="peril", pointMult=1.30, color=P.coral,
      enemyHp=1.45, desc="Creatures have 45% more health." },
    { id="frenzy", name="Frenzy", kind="peril", pointMult=1.40, color=P.gold,
      enemySpeed=1.30, spawnMult=1.20, desc="Creatures are faster and more numerous." },
    { id="swarm", name="The Swarm", kind="peril", pointMult=1.50, color=P.magenta,
      spawnMult=1.60, desc="60% more creatures per wave." },
    { id="glass", name="Glass Squid", kind="peril", pointMult=1.55, color=P.aqua,
      playerHpMult=0.5, desc="Your shell is half as strong." },
    { id="fragile", name="Fragile", kind="peril", pointMult=1.65, color=P.purple,
      playerDmgTakenMult=2.0, desc="You take double damage." },
    { id="darkness", name="Lights Out", kind="peril", pointMult=1.45, color={0.3,0.3,0.45},
      darkness=0.62, desc="The abyss closes in. Vision is dimmed." },
    { id="nomercy", name="No Mercy", kind="peril", pointMult=1.35, color={0.8,0.4,0.4},
      noHeal=true, desc="No healing between depths." },
    { id="thinink", name="Dull Edge", kind="peril", pointMult=1.40, color={0.5,0.7,1.0},
      playerDmgMult=0.78, desc="Your ink hits 22% softer." },
    { id="gamble", name="Double or Nothing", kind="peril", pointMult=2.00, color={1.0,0.5,0.0},
      enemyHp=1.25, enemyDmg=1.25, enemySpeed=1.15, desc="Everything +25%. Payout doubled." },

    -- ---------- MERCIES (easier, pay less) ----------
    { id="calm", name="Calm Waters", kind="mercy", pointMult=0.70, color={0.4,0.9,0.7},
      enemySpeed=0.75, spawnMult=0.85, desc="Creatures are slow and sparse." },
    { id="vitality", name="Vitality", kind="mercy", pointMult=0.65, color=P.lime,
      playerHpMult=1.6, desc="60% more shell health." },
    { id="overflow", name="Field Medic", kind="mercy", pointMult=0.70, color=P.cyan,
      playerRegen=2.5, desc="Slowly regenerate shell over time." },
    { id="featherfin", name="Featherfin", kind="mercy", pointMult=0.75, color={0.7,0.9,1.0},
      playerSpeedMult=1.25, desc="You jet 25% faster." },
}

M.byId = {}
for _, m in ipairs(M.list) do M.byId[m.id] = m end

-- Aggregate a list of selected ids into a single effect table.
function M.aggregate(ids)
    local r = {
        pointMult = 1, enemyHp = 1, enemyDmg = 1, enemySpeed = 1, spawnMult = 1,
        playerHpMult = 1, playerDmgTakenMult = 1, playerSpeedMult = 1,
        playerDmgMult = 1, playerRegen = 0,
        inkRegenMult = 1, darkness = 0, noHeal = false, count = 0,
    }
    -- Payout multiplier is ADDITIVE (1 + sum of each modifier's bonus), then
    -- clamped — so stacking every peril can't balloon to a 50x exploit.
    local bonus = 0
    for _, id in ipairs(ids or {}) do
        local m = M.byId[id]
        if m then
            r.count = r.count + 1
            bonus = bonus + ((m.pointMult or 1) - 1)
            r.enemyHp = r.enemyHp * (m.enemyHp or 1)
            r.enemyDmg = r.enemyDmg * (m.enemyDmg or 1)
            r.enemySpeed = r.enemySpeed * (m.enemySpeed or 1)
            r.spawnMult = r.spawnMult * (m.spawnMult or 1)
            r.playerHpMult = r.playerHpMult * (m.playerHpMult or 1)
            r.playerDmgTakenMult = r.playerDmgTakenMult * (m.playerDmgTakenMult or 1)
            r.playerSpeedMult = r.playerSpeedMult * (m.playerSpeedMult or 1)
            r.playerDmgMult = r.playerDmgMult * (m.playerDmgMult or 1)
            r.playerRegen = r.playerRegen + (m.playerRegen or 0)
            r.inkRegenMult = r.inkRegenMult * (m.inkRegenMult or 1)
            r.darkness = math.max(r.darkness, m.darkness or 0)
            if m.noHeal then r.noHeal = true end
        end
    end
    r.pointMult = math.max(0.3, math.min(4.0, 1 + bonus))   -- additive, capped 0.3x..4x
    return r
end

return M
