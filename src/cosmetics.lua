-- Catalog of skins and accessories, plus ownership/equipping helpers.
--
-- kind: "basic"   -> owned from the start, free.
--       "shop"    -> bought with $Things (cost field).
--       "special" -> unlocked by an achievement (ach field = achievement id).
--
-- Accessories add real geometry via .draw(ctx). ctx is in the squid's local
-- space (faces up): { len, w, t, pulse, alpha, eyeX, eyeY, eyeR, baseHalf }.

local U = require("src.util")
local P = require("src.palette")
local C = {}

local function sc(c, a) love.graphics.setColor(c[1], c[2], c[3], (c[4] or 1) * (a or 1)) end

----------------------------------------------------------------------
-- SKINS
----------------------------------------------------------------------
-- belly auto-derives if omitted. glowStrength defaults to 0.5.
C.skins = {
    -- ---- basic (free, from start) ----
    { id="luminer", name="Luminer",   kind="basic", rarity="basic", pattern="solid",
      body={0.95,0.46,0.16}, accent={1.0,0.72,0.30}, glow={1.0,0.55,0.20}, eye={0.10,0.07,0.06},
      desc="The last lit squid. Burns orange in the dark." },
    { id="ember",   name="Ember",     kind="basic", rarity="basic", pattern="gradient",
      body={0.92,0.45,0.22}, accent={1.0,0.8,0.3}, glow={1.0,0.6,0.3}, desc="A warm glow in cold water." },
    { id="mossback",name="Mossback",  kind="basic", rarity="basic", pattern="spots",
      body={0.35,0.70,0.45}, accent={0.8,1.0,0.6}, glow={0.5,1.0,0.6}, desc="Camouflaged in kelp shadows." },
    { id="violet",  name="Violet",    kind="basic", rarity="basic", pattern="solid",
      body={0.58,0.40,0.92}, accent={0.9,0.7,1.0}, glow={0.7,0.5,1.0}, desc="Royal hue of the mid-trench." },
    { id="ashen",   name="Ashen",     kind="basic", rarity="basic", pattern="stripes",
      body={0.55,0.60,0.66}, accent={0.85,0.9,0.95}, glow={0.6,0.7,0.8}, desc="Plain, dependable, gray." },

    -- ---- shop ($Things) ----
    -- plain solid colors — cheap, simple, 500 each
    { id="plain_crimson", name="Crimson", kind="shop", rarity="common", cost=500, pattern="solid",
      body={0.82,0.18,0.20}, accent={1.0,0.5,0.5}, glow={1.0,0.3,0.3}, desc="A plain bold red." },
    { id="plain_seafoam", name="Seafoam", kind="shop", rarity="common", cost=500, pattern="solid",
      body={0.30,0.80,0.66}, accent={0.7,1.0,0.9}, glow={0.4,1.0,0.8}, desc="A plain soft teal." },
    { id="plain_slate",   name="Slate",   kind="shop", rarity="common", cost=500, pattern="solid",
      body={0.40,0.46,0.56}, accent={0.7,0.78,0.88}, glow={0.5,0.6,0.75}, desc="A plain cool gray." },
    { id="plain_sunbeam", name="Sunbeam", kind="shop", rarity="common", cost=500, pattern="solid",
      body={0.98,0.82,0.25}, accent={1.0,0.95,0.6}, glow={1.0,0.85,0.3}, desc="A plain bright yellow." },
    { id="plain_orchid",  name="Orchid",  kind="shop", rarity="common", cost=500, pattern="solid",
      body={0.68,0.36,0.85}, accent={0.9,0.7,1.0}, glow={0.8,0.5,1.0}, desc="A plain rich purple." },
    { id="coral",   name="Coral",     kind="shop", rarity="common", cost=800, pattern="spots",
      body={0.98,0.45,0.55}, accent={1.0,0.8,0.85}, glow={1.0,0.5,0.6}, desc="Reef-bright and bubbly." },
    { id="midnight",name="Midnight",  kind="shop", rarity="common", cost=800, pattern="stripes",
      body={0.14,0.18,0.40}, accent={0.4,0.6,1.0}, glow={0.3,0.5,1.0}, desc="The color of 2am water." },
    { id="goldfish",name="Goldfish",  kind="shop", rarity="rare", cost=2100, pattern="gradient",
      body={1.0,0.78,0.22}, accent={1.0,0.95,0.6}, glow={1.0,0.85,0.3}, desc="Suspiciously not a fish." },
    { id="toxic",   name="Toxic",     kind="shop", rarity="rare", cost=2100, pattern="spots", glowStrength=0.9,
      body={0.55,0.95,0.20}, accent={0.9,1.0,0.4}, glow={0.6,1.0,0.2}, desc="Glows hard enough to taste." },
    { id="frost",   name="Frostbite", kind="shop", rarity="rare", cost=2350, pattern="rings",
      body={0.78,0.92,0.98}, accent={0.5,0.8,1.0}, glow={0.7,0.9,1.0}, desc="Carved from trench ice." },
    { id="magma",   name="Magma",     kind="shop", rarity="epic", cost=3200, pattern="gradient", glowStrength=0.8,
      body={0.85,0.18,0.12}, accent={1.0,0.7,0.2}, glow={1.0,0.4,0.1}, desc="Born by a hydrothermal vent." },
    { id="nebula",  name="Nebula",    kind="shop", rarity="epic", cost=3500, pattern="galaxy", glowStrength=0.8,
      body={0.22,0.16,0.42}, accent={0.9,0.7,1.0}, glow={0.7,0.5,1.0}, desc="A pocket of stolen sky." },
    { id="prism",   name="Prism",     kind="shop", rarity="epic", cost=3850, pattern="rings", glowStrength=0.9,
      body={0.40,0.85,0.95}, accent={1.0,0.5,0.9}, glow={0.5,1.0,0.9}, desc="Refracts the dark itself." },
    { id="abyssking",name="Abyss King",kind="shop", rarity="legendary", cost=6500, pattern="rings", glowStrength=1.1,
      body={0.30,0.10,0.45}, accent={1.0,0.85,0.4}, glow={0.8,0.4,1.0}, eye={1.0,0.85,0.4}, desc="Wears the trench like a crown." },

    -- browns + extra shop colors
    { id="mahogany", name="Mahogany", kind="shop", rarity="common", cost=500, pattern="solid",
      body={0.34,0.14,0.11}, accent={0.74,0.38,0.30}, glow={0.9,0.40,0.30}, desc="Deep red-brown heartwood." },
    { id="driftwood",name="Driftwood",kind="shop", rarity="common", cost=800, pattern="stripes",
      body={0.40,0.27,0.16}, accent={0.78,0.58,0.36}, glow={0.85,0.55,0.28}, eye={0.12,0.08,0.05}, desc="Weathered like timber lost to the deep." },
    { id="verdigris",name="Verdigris",kind="shop", rarity="common", cost=800, pattern="spots",
      body={0.18,0.46,0.42}, accent={0.6,0.95,0.85}, glow={0.4,1.0,0.85}, desc="Aged copper-green of a sunken hull." },
    { id="bronze",   name="Bronze",   kind="shop", rarity="rare", cost=2100, pattern="gradient", glowStrength=0.75,
      body={0.50,0.32,0.16}, accent={0.98,0.74,0.40}, glow={1.0,0.66,0.26}, eye={0.15,0.08,0.03}, desc="Forged in a hydrothermal kiln." },
    { id="obsidian", name="Obsidian", kind="special", rarity="special", ach="depth_11", pattern="stripes", glowStrength=0.8,
      body={0.06,0.07,0.11}, accent={0.45,0.9,1.0}, glow={0.35,0.85,1.0}, eye={0.5,0.95,1.0}, desc="Black glass with a cyan heart. Forged in the deepest dark." },

    -- ---- special (achievement-locked) ----
    { id="voidborn",name="Voidborn",  kind="special", rarity="special", ach="depth_8", pattern="solid", glowStrength=1.0,
      body={0.03,0.03,0.06}, accent={0.2,0.9,1.0}, glow={0.2,0.9,1.0}, eye={0.2,1.0,1.0}, desc="Reached the lightless floor." },
    { id="ghost",   name="Specter",   kind="special", rarity="special", ach="bosses_25", pattern="solid", glowStrength=0.7,
      body={0.85,0.92,1.0}, accent={1.0,1.0,1.0}, glow={0.8,0.95,1.0}, desc="Defeated 25 bosses. A wraith of the deep." },
    { id="inkdemon",name="Ink Demon", kind="special", rarity="special", ach="kills_1000", pattern="stripes", glowStrength=0.8,
      body={0.10,0.02,0.04}, accent={1.0,0.2,0.2}, glow={1.0,0.1,0.1}, eye={1.0,0.3,0.2}, pupil={1.0,0.6,0.2}, desc="1000 souls in the dark." },
    { id="leviathan",name="Leviathan",kind="special", rarity="special", ach="beat_game", pattern="galaxy", glowStrength=1.2,
      body={0.10,0.30,0.35}, accent={0.4,1.0,0.9}, glow={0.3,1.0,0.9}, eye={1.0,0.9,0.4}, desc="Freed the squids. Slayer of the Eldritch." },
    { id="voidkin", name="Voidkin",   kind="special", rarity="special", ach="reach_hadal", pattern="galaxy", glowStrength=1.1,
      body={0.10,0.04,0.18}, accent={0.85,0.3,1.0}, glow={0.7,0.2,1.0}, eye={0.9,0.4,1.0}, desc="Marked by the Hadal dark." },
    { id="goldgod", name="Gilded",    kind="special", rarity="special", ach="curse_win", pattern="gradient", glowStrength=1.0,
      body={1.0,0.84,0.30}, accent={1.0,1.0,0.7}, glow={1.0,0.9,0.4}, eye={0.2,0.1,0.0}, desc="Won while cursed. Greed rewarded." },
    { id="comet",   name="Comet",     kind="special", rarity="special", ach="speedrun", pattern="rings", glowStrength=1.0,
      body={0.20,0.70,1.0}, accent={1.0,1.0,1.0}, glow={0.4,0.9,1.0}, desc="Won in a blistering descent." },
    -- ---- Churgly'nth true-end relic (1 of 3) ----
    { id="churgflesh", name="Churgflesh", kind="special", rarity="special", ach="churgly_slain", pattern="galaxy", glowStrength=1.4,
      body={0.22,0.03,0.40}, accent={1.0,0.4,1.0}, glow={0.9,0.25,1.0}, eye={1.0,0.8,0.15}, pupil={0,0,0}, desc="Wrought from the corrupt god's own flesh." },
}

----------------------------------------------------------------------
-- ACCESSORIES
----------------------------------------------------------------------
-- slots: hat, eyes, face, back, aura, trail
-- trail accessories carry a .trail color used by the in-game ink trail; they
-- draw nothing on the body.
C.accessories = {
    -- ---- hats ----
    { id="topper", name="Top Hat", slot="hat", kind="basic", rarity="basic", desc="Dapper little chap.",
      draw=function(c)
        sc({0.06,0.06,0.09}, c.alpha)
        love.graphics.rectangle("fill", -c.w*0.32, -c.len*0.78, c.w*0.64, c.len*0.18)
        love.graphics.rectangle("fill", -c.w*0.55, -c.len*0.62, c.w*1.10, c.len*0.05)
        sc(P.red, c.alpha); love.graphics.rectangle("fill", -c.w*0.32, -c.len*0.64, c.w*0.64, c.len*0.04)
      end },
    { id="antenna", name="Anglerlure", slot="hat", kind="basic", rarity="basic", desc="A light to fish by.",
      draw=function(c)
        local sway = math.sin(c.t*2)*c.w*0.25
        sc({0.2,0.25,0.3}, c.alpha); love.graphics.setLineWidth(c.w*0.08)
        love.graphics.line(0,-c.len*0.55, sway*0.5,-c.len*0.8, sway,-c.len*0.95)
        U.glow(sway, -c.len*0.98, c.w*0.55, c.skin.glow, 0.9*c.pulse*c.alpha)
        sc(c.skin.glow, c.alpha); love.graphics.circle("fill", sway, -c.len*0.98, c.w*0.16)
      end },
    { id="bubblehelm", name="Dive Helm", slot="hat", kind="shop", rarity="common", cost=1150, desc="Brassy diving bell.",
      draw=function(c)
        sc({0.75,0.85,1.0}, 0.22*c.alpha); love.graphics.circle("fill", 0, -c.len*0.05, c.w*1.25)
        sc({0.85,0.7,0.3}, c.alpha); love.graphics.setLineWidth(c.w*0.14)
        love.graphics.circle("line", 0, -c.len*0.05, c.w*1.25)
        love.graphics.setColor(1,1,1,0.5*c.alpha)
        love.graphics.circle("line", -c.w*0.4, -c.len*0.3, c.w*0.4)
      end },
    { id="crown", name="Trench Crown", slot="hat", kind="special", rarity="special", ach="rich_5000", desc="For the wealthiest squid.",
      draw=function(c)
        sc(P.gold, c.alpha)
        local y=-c.len*0.62
        love.graphics.polygon("fill", -c.w*0.5,y, -c.w*0.5,y-c.len*0.14, -c.w*0.25,y-c.len*0.05,
            0,y-c.len*0.18, c.w*0.25,y-c.len*0.05, c.w*0.5,y-c.len*0.14, c.w*0.5,y)
        sc(P.magenta, c.alpha); love.graphics.circle("fill",0,y-c.len*0.06,c.w*0.09)
      end },
    { id="tophat_fancy", name="Fancy Top Hat", slot="hat", kind="special", rarity="special", ach="bosses_8", desc="Slay 8 bosses, dress like a gentleman.",
      draw=function(c)
        -- tall glossy black top hat with a gold band, buckle and gem
        sc({0.05,0.05,0.08}, c.alpha)
        love.graphics.rectangle("fill", -c.w*0.34, -c.len*0.86, c.w*0.68, c.len*0.26)       -- crown
        love.graphics.rectangle("fill", -c.w*0.6, -c.len*0.62, c.w*1.2, c.len*0.055)         -- wide brim
        sc(P.gold, c.alpha)
        love.graphics.rectangle("fill", -c.w*0.34, -c.len*0.66, c.w*0.68, c.len*0.05)        -- gold band
        love.graphics.rectangle("fill", -c.w*0.08, -c.len*0.67, c.w*0.16, c.len*0.07)        -- buckle
        sc(P.cyan, (0.7+0.3*math.sin(c.t*4))*c.alpha)
        love.graphics.circle("fill", 0, -c.len*0.635, c.w*0.04)                              -- gem
        love.graphics.setColor(1,1,1,0.35*c.alpha)
        love.graphics.rectangle("fill", -c.w*0.28, -c.len*0.84, c.w*0.1, c.len*0.22)         -- sheen
      end },
    { id="party", name="Party Hat", slot="hat", kind="shop", rarity="common", cost=950, desc="One squid party.",
      draw=function(c)
        sc(P.magenta, c.alpha)
        love.graphics.polygon("fill", 0,-c.len*0.92, -c.w*0.42,-c.len*0.55, c.w*0.42,-c.len*0.55)
        sc(P.gold, c.alpha); love.graphics.circle("fill",0,-c.len*0.92,c.w*0.12)
      end },
    { id="strawhat", name="Straw Hat", slot="hat", kind="shop", rarity="common", cost=1000, desc="A summer on the surface.",
      draw=function(c)
        sc({0.85,0.72,0.38}, c.alpha)
        love.graphics.ellipse("fill", 0, -c.len*0.55, c.w*1.5, c.w*0.35)         -- wide brim
        love.graphics.arc("fill", 0, -c.len*0.55, c.w*0.8, math.pi, math.pi*2, 16) -- crown
        sc({0.6,0.48,0.22}, c.alpha); love.graphics.setLineWidth(c.w*0.06)
        love.graphics.line(-c.w*0.7,-c.len*0.55, c.w*0.7,-c.len*0.55)
        sc(P.red, c.alpha); love.graphics.rectangle("fill", -c.w*0.6,-c.len*0.6, c.w*1.2, c.w*0.14)  -- band
      end },
    { id="strawhat_blue", name="Asbestos Hat", slot="hat", kind="shop", rarity="rare", cost=2000, desc="A straw hat, but ominously blue.",
      draw=function(c)
        sc({0.35,0.55,0.85}, c.alpha)
        love.graphics.ellipse("fill", 0, -c.len*0.55, c.w*1.5, c.w*0.35)
        love.graphics.arc("fill", 0, -c.len*0.55, c.w*0.8, math.pi, math.pi*2, 16)
        sc({0.2,0.35,0.6}, c.alpha); love.graphics.setLineWidth(c.w*0.06)
        love.graphics.line(-c.w*0.7,-c.len*0.55, c.w*0.7,-c.len*0.55)
        sc(P.white, c.alpha); love.graphics.rectangle("fill", -c.w*0.6,-c.len*0.6, c.w*1.2, c.w*0.14)
      end },
    { id="halo_crown", name="Trench Halo", slot="hat", kind="shop", rarity="legendary", cost=6900, desc="A floating ring of pure light. Worth a fortune.",
      draw=function(c)
        local t = c.t
        for i=1,16 do
          local a = i/16*math.pi*2 + t
          U.glow(math.cos(a)*c.w*0.9, -c.len*0.72 + math.sin(a)*c.w*0.22, c.w*0.18, P.gold, 0.5*c.alpha)
        end
        sc(P.gold, (0.7+0.3*math.sin(t*3))*c.alpha); love.graphics.setLineWidth(c.w*0.14)
        love.graphics.ellipse("line", 0, -c.len*0.72, c.w*0.9, c.w*0.22)
      end },

    { id="wizard", name="Wizard Hat", slot="hat", kind="shop", rarity="rare", cost=2200, desc="Arcane squid of the abyss.",
      draw=function(c)
        local tipx = math.sin(c.t*1.1)*c.w*0.28                 -- the floppy tip curls
        sc({0.16,0.12,0.40}, c.alpha)                            -- midnight cone
        love.graphics.polygon("fill", -c.w*0.52,-c.len*0.58, c.w*0.52,-c.len*0.58, tipx,-c.len*1.06)
        love.graphics.ellipse("fill", 0, -c.len*0.58, c.w*0.64, c.w*0.17)   -- brim
        sc(P.gold, c.alpha); love.graphics.rectangle("fill", -c.w*0.44,-c.len*0.66, c.w*0.88, c.len*0.05)  -- band
        for i=1,4 do                                             -- twinkling stars
          local tw = 0.4+0.6*math.abs(math.sin(c.t*3+i*1.7))
          love.graphics.setColor(1,1,0.7, tw*c.alpha)
          love.graphics.circle("fill", -c.w*0.16+(i%2)*c.w*0.22, -c.len*(0.72+i*0.055), c.w*0.045*tw)
        end
      end },
    { id="pirate", name="Pirate Hat", slot="hat", kind="special", rarity="special", ach="boss_first", desc="Defeat a boss — captain of the trench. Yarr.",
      draw=function(c)
        sc({0.08,0.07,0.09}, c.alpha)                            -- black tricorn
        love.graphics.polygon("fill", -c.w*0.9,-c.len*0.58, -c.w*0.2,-c.len*0.8, c.w*0.2,-c.len*0.8, c.w*0.9,-c.len*0.58, 0,-c.len*0.5)
        love.graphics.ellipse("fill", 0, -c.len*0.67, c.w*0.42, c.len*0.12)
        sc(P.white, c.alpha); love.graphics.circle("fill", 0, -c.len*0.68, c.w*0.13)  -- skull
        love.graphics.polygon("fill", -c.w*0.13,-c.len*0.6, c.w*0.13,-c.len*0.6, 0,-c.len*0.56)  -- jaw
        sc({0.08,0.07,0.09}, c.alpha)
        love.graphics.circle("fill", -c.w*0.05,-c.len*0.69, c.w*0.032); love.graphics.circle("fill", c.w*0.05,-c.len*0.69, c.w*0.032)
      end },

    -- ---- eyes (eyewear) ----
    { id="shades", name="Shades", slot="eyes", kind="basic", rarity="basic", desc="Too cool for sunlight (there is none).",
      draw=function(c)
        local hw, hh = c.eyeR*1.18, c.eyeR*0.84
        for s=-1,1,2 do
          local cx = s*c.eyeX
          -- angular sport lens — sharp, swept UP at the outer corner (not oval)
          local p = {
            cx + s*(-hw*0.74), c.eyeY - hh*0.42,   -- inner top
            cx + s*( hw),      c.eyeY - hh,         -- outer top (sharp sweep)
            cx + s*( hw*0.86), c.eyeY + hh*0.62,    -- outer bottom
            cx + s*(-hw*0.98), c.eyeY + hh*0.40,    -- inner bottom
          }
          sc({0.02,0.02,0.04}, c.alpha)            -- near-black tinted lens
          love.graphics.polygon("fill", p)
          sc({0.13,0.14,0.18}, c.alpha)            -- glossy metal frame
          love.graphics.setLineWidth(c.w*0.055); love.graphics.polygon("line", p)
          -- reflective glints sweeping across the lens
          sc({0.45,0.7,1.0}, 0.55*c.alpha); love.graphics.setLineWidth(c.w*0.05)
          love.graphics.line(cx + s*(-hw*0.45), c.eyeY - hh*0.18, cx + s*(hw*0.25), c.eyeY + hh*0.45)
          sc({1,1,1}, 0.9*c.alpha); love.graphics.setLineWidth(c.w*0.03)
          love.graphics.line(cx + s*(-hw*0.6), c.eyeY - hh*0.34, cx + s*(-hw*0.2), c.eyeY + hh*0.1)
        end
        -- low, angled bridge across the nose
        sc({0.10,0.11,0.14}, c.alpha); love.graphics.setLineWidth(c.w*0.09)
        love.graphics.line(-c.eyeX*0.5, c.eyeY - c.eyeR*0.32, c.eyeX*0.5, c.eyeY - c.eyeR*0.32)
      end },
    { id="visor", name="Cyber Visor", slot="eyes", kind="shop", rarity="rare", cost=1950, desc="HUD not included.",
      draw=function(c)
        local x0, y0 = -c.eyeX-c.eyeR, c.eyeY-c.eyeR*0.7
        local ww, hh = (c.eyeX+c.eyeR)*2, c.eyeR*1.45
        local blue = { 0.3, 0.7, 1.0 }
        -- housing
        sc({0.05,0.07,0.10}, c.alpha)
        love.graphics.rectangle("fill", x0-c.eyeR*0.2, y0-c.eyeR*0.15, ww+c.eyeR*0.4, hh+c.eyeR*0.3, c.eyeR*0.25)
        -- translucent glowing BLUE screen
        sc(blue, 0.32*c.alpha)
        love.graphics.rectangle("fill", x0, y0, ww, hh, c.eyeR*0.2)
        -- scanlines + a sweeping readout tick
        sc(blue, 0.45*c.alpha); love.graphics.setLineWidth(1)
        for i=1,3 do local yy=y0+hh*(i/4); love.graphics.line(x0+2, yy, x0+ww-2, yy) end
        local tx = x0 + ww*(0.5+0.42*math.sin(c.t*2))
        sc(P.white, 0.85*c.alpha); love.graphics.setLineWidth(c.w*0.05); love.graphics.line(tx, y0+2, tx, y0+hh-2)
        -- bright blue frame + HUD corner brackets
        sc(blue, c.alpha); love.graphics.setLineWidth(c.w*0.05)
        love.graphics.rectangle("line", x0, y0, ww, hh, c.eyeR*0.2)
        love.graphics.setLineWidth(c.w*0.07)
        love.graphics.line(x0, y0+hh*0.32, x0, y0, x0+ww*0.16, y0)
        love.graphics.line(x0+ww, y0+hh*0.68, x0+ww, y0+hh, x0+ww*0.84, y0+hh)
      end },
    { id="monocle", name="Monocle", slot="eyes", kind="shop", rarity="common", cost=1050, desc="Distinguished.",
      draw=function(c)
        sc(P.gold, c.alpha); love.graphics.setLineWidth(c.w*0.08)
        love.graphics.circle("line", c.eyeX, c.eyeY, c.eyeR*1.15)
        love.graphics.line(c.eyeX, c.eyeY+c.eyeR, c.eyeX+c.eyeR, c.eyeY+c.eyeR*2.2)
      end },

    { id="eyepatch", name="Eyepatch", slot="eyes", kind="shop", rarity="common", cost=900, desc="Saw something it shouldn't have.",
      draw=function(c)
        sc({0.05,0.05,0.07}, c.alpha)                            -- dark patch over one eye
        love.graphics.ellipse("fill", c.eyeX, c.eyeY, c.eyeR*1.25, c.eyeR*1.05)
        sc({0.16,0.16,0.2}, c.alpha); love.graphics.setLineWidth(c.w*0.05) -- strap across the head
        love.graphics.line(-c.eyeX*0.9, c.eyeY-c.eyeR*1.4, c.eyeX+c.eyeR*1.1, c.eyeY-c.eyeR*0.1)
        sc(P.white, 0.18*c.alpha); love.graphics.circle("fill", c.eyeX-c.eyeR*0.35, c.eyeY-c.eyeR*0.35, c.eyeR*0.22)
      end },
    { id="heartshades", name="Heart Shades", slot="eyes", kind="shop", rarity="common", cost=1100, desc="Lovestruck in the lightless deep.",
      draw=function(c)
        for s=-1,1,2 do
          local cx = s*c.eyeX
          sc({1.0,0.3,0.5}, 0.85*c.alpha)                        -- heart lens (2 lobes + point)
          love.graphics.circle("fill", cx-c.eyeR*0.34, c.eyeY-c.eyeR*0.18, c.eyeR*0.5)
          love.graphics.circle("fill", cx+c.eyeR*0.34, c.eyeY-c.eyeR*0.18, c.eyeR*0.5)
          love.graphics.polygon("fill", cx-c.eyeR*0.76,c.eyeY, cx+c.eyeR*0.76,c.eyeY, cx,c.eyeY+c.eyeR*0.85)
          sc(P.white, 0.5*c.alpha); love.graphics.circle("fill", cx-c.eyeR*0.28, c.eyeY-c.eyeR*0.32, c.eyeR*0.14)
        end
        sc({0.8,0.2,0.4}, c.alpha); love.graphics.setLineWidth(c.w*0.06)
        love.graphics.line(-c.eyeX*0.4, c.eyeY-c.eyeR*0.2, c.eyeX*0.4, c.eyeY-c.eyeR*0.2)
      end },
    { id="threed", name="3D Glasses", slot="eyes", kind="shop", rarity="common", cost=850, desc="The trench in glorious 3D.",
      draw=function(c)
        local hw, hh = c.eyeR*1.05, c.eyeR*0.82
        sc({1,0.1,0.15}, 0.5*c.alpha); love.graphics.rectangle("fill", -c.eyeX-hw, c.eyeY-hh, hw*2, hh*2, c.eyeR*0.2)
        sc({0.1,0.4,1}, 0.5*c.alpha);  love.graphics.rectangle("fill",  c.eyeX-hw, c.eyeY-hh, hw*2, hh*2, c.eyeR*0.2)
        sc(P.white, c.alpha); love.graphics.setLineWidth(c.w*0.06)
        love.graphics.rectangle("line", -c.eyeX-hw, c.eyeY-hh, hw*2, hh*2, c.eyeR*0.2)
        love.graphics.rectangle("line",  c.eyeX-hw, c.eyeY-hh, hw*2, hh*2, c.eyeR*0.2)
        love.graphics.line(-c.eyeX+hw, c.eyeY, c.eyeX-hw, c.eyeY)
      end },

    -- ---- face ----
    { id="fangs", name="Fangs", slot="face", kind="shop", rarity="common", cost=900, desc="All the better to ink you with.",
      draw=function(c)
        sc(P.white, c.alpha)
        love.graphics.polygon("fill", -c.w*0.18,c.len*0.16, -c.w*0.30,c.len*0.30, -c.w*0.06,c.len*0.18)
        love.graphics.polygon("fill",  c.w*0.18,c.len*0.16,  c.w*0.30,c.len*0.30,  c.w*0.06,c.len*0.18)
      end },
    { id="snorkel", name="Snorkel", slot="face", kind="shop", rarity="common", cost=850, desc="Redundant but stylish.",
      draw=function(c)
        -- a dive mask over the eyes + a curved snorkel tube up the side
        local x0 = -c.eyeX - c.eyeR*0.9
        local mw = (c.eyeX + c.eyeR*0.9) * 2
        sc({0.5,0.8,0.95}, 0.34*c.alpha)                                  -- glass
        love.graphics.rectangle("fill", x0, c.eyeY-c.eyeR*0.7, mw, c.eyeR*1.5, c.eyeR*0.4)
        sc({0.12,0.14,0.18}, c.alpha); love.graphics.setLineWidth(c.w*0.06)  -- frame
        love.graphics.rectangle("line", x0, c.eyeY-c.eyeR*0.7, mw, c.eyeR*1.5, c.eyeR*0.4)
        sc(P.white, 0.5*c.alpha); love.graphics.circle("fill", x0+c.eyeR*0.4, c.eyeY-c.eyeR*0.25, c.eyeR*0.18)  -- glint
        -- the snorkel tube (orange) up the right side + a dark mouthpiece
        sc({1.0,0.5,0.15}, c.alpha); love.graphics.setLineWidth(c.w*0.13)
        love.graphics.line(c.eyeX+c.eyeR*0.9, c.eyeY+c.eyeR*0.5, c.eyeX+c.eyeR*1.3, c.eyeY-c.len*0.12, c.eyeX+c.eyeR*1.05, -c.len*0.55)
        sc({0.2,0.2,0.25}, c.alpha); love.graphics.circle("fill", c.eyeX+c.eyeR*0.9, c.eyeY+c.eyeR*0.55, c.w*0.1)
      end },
    { id="bandana", name="Bandana", slot="face", kind="shop", rarity="common", cost=900, desc="Bandit of the abyss.",
      draw=function(c)
        sc({0.72,0.16,0.18}, c.alpha)                            -- cloth over the lower face
        love.graphics.polygon("fill", -c.w*0.56,c.len*0.05, c.w*0.56,c.len*0.05, c.w*0.4,c.len*0.36, -c.w*0.4,c.len*0.36)
        sc({0.52,0.10,0.12}, c.alpha); love.graphics.setLineWidth(c.w*0.04)  -- folds
        love.graphics.line(-c.w*0.28,c.len*0.12, -c.w*0.18,c.len*0.32)
        love.graphics.line( c.w*0.28,c.len*0.12,  c.w*0.18,c.len*0.32)
        sc(P.white, 0.5*c.alpha); love.graphics.circle("fill", -c.w*0.12, c.len*0.14, c.w*0.03)  -- dots
        love.graphics.circle("fill", c.w*0.1, c.len*0.16, c.w*0.03)
      end },
    { id="cigar", name="Cigar", slot="face", kind="shop", rarity="common", cost=950, desc="Smooth operator of the deep.",
      draw=function(c)
        sc({0.42,0.26,0.13}, c.alpha)
        love.graphics.rectangle("fill", c.w*0.04, c.len*0.16, c.w*0.42, c.len*0.07, c.w*0.02)
        sc({1,0.45,0.12}, (0.6+0.4*math.abs(math.sin(c.t*3)))*c.alpha)      -- ember
        love.graphics.circle("fill", c.w*0.47, c.len*0.195, c.w*0.05)
        local sy = (c.t*0.5)%1                                              -- smoke puff
        sc({0.82,0.82,0.88}, 0.22*(1-sy)*c.alpha)
        love.graphics.circle("fill", c.w*0.5+math.sin(c.t*2)*c.w*0.06, c.len*0.19 - sy*c.len*0.4, c.w*0.06*(0.6+sy))
      end },
    { id="warpaint", name="War Paint", slot="face", kind="special", rarity="special", ach="mods_3", desc="Win with 3+ modifiers — painted for the hunt.",
      draw=function(c)
        sc(c.skin.glow, 0.85*c.alpha); love.graphics.setLineWidth(c.w*0.06)
        for s=-1,1,2 do                                                     -- three glowing streaks under each eye
          for i=0,2 do
            local x = s*c.eyeX + (i-1)*c.w*0.10
            love.graphics.line(x, c.eyeY+c.eyeR*0.7, x, c.eyeY+c.eyeR*1.7)
          end
        end
      end },
    { id="mustache", name="Mustache", slot="face", kind="special", rarity="special", ach="wins_5", desc="Refined gentleman of the deep.",
      draw=function(c)
        sc({0.1,0.08,0.06}, c.alpha)
        love.graphics.ellipse("fill", -c.w*0.2, c.len*0.16, c.w*0.22, c.w*0.10)
        love.graphics.ellipse("fill",  c.w*0.2, c.len*0.16, c.w*0.22, c.w*0.10)
      end },
    { id="mustache_gold", name="Golden Mustache", slot="face", kind="special", rarity="special", ach="wins_10", desc="10 wins of dapper. Shines.",
      draw=function(c)
        -- always-bright gold (a faint shimmer that never dips dark)
        local sh = 0.92 + 0.08*math.sin(c.t*4)
        sc({1.0*sh,0.82*sh,0.3*sh}, c.alpha)
        love.graphics.ellipse("fill", -c.w*0.2, c.len*0.16, c.w*0.24, c.w*0.11)
        love.graphics.ellipse("fill",  c.w*0.2, c.len*0.16, c.w*0.24, c.w*0.11)
        -- bright specular glints that sweep across for a polished shine
        local g = 0.65 + 0.35*math.abs(math.sin(c.t*3))
        love.graphics.setColor(1,1,0.92, g*c.alpha)
        love.graphics.circle("fill", -c.w*0.28, c.len*0.14, c.w*0.05)
        love.graphics.circle("fill",  c.w*0.13, c.len*0.135, c.w*0.035)
      end },
    { id="mustache_diamond", name="Diamond Mustache", slot="face", kind="special", rarity="special", ach="wins_25", desc="25 wins. Carved from pressure itself.",
      draw=function(c)
        sc({0.75,0.95,1.0}, c.alpha)
        love.graphics.ellipse("fill", -c.w*0.2, c.len*0.16, c.w*0.25, c.w*0.11)
        love.graphics.ellipse("fill",  c.w*0.2, c.len*0.16, c.w*0.25, c.w*0.11)
        for s=-1,1,2 do
          local sp = 0.5+0.5*math.sin(c.t*6 + s)
          love.graphics.setColor(1,1,1,sp*c.alpha)
          love.graphics.circle("fill", s*c.w*0.28, c.len*0.13, c.w*0.05)
        end
      end },

    -- ---- back ----
    { id="shell", name="Hermit Shell", slot="back", kind="shop", rarity="common", cost=1300, desc="Borrowed housing.",
      draw=function(c)
        -- a big spiral shell the squid pokes out of — frames the whole body
        local cx, cy, R = 0, c.len * 0.06, c.w * 1.75
        sc({0.82,0.62,0.42}, c.alpha); love.graphics.circle("fill", cx, cy, R)
        sc({0.92,0.74,0.54}, c.alpha); love.graphics.circle("fill", cx, cy, R * 0.66)
        -- spiral ridges
        sc({0.55,0.38,0.24}, c.alpha); love.graphics.setLineWidth(c.w * 0.12)
        for r = 1, 4 do love.graphics.arc("line", "open", cx, cy, r * R * 0.22, -2.6, 1.0) end
        -- darker rim
        sc({0.5,0.34,0.2}, c.alpha); love.graphics.setLineWidth(c.w * 0.1)
        love.graphics.circle("line", cx, cy, R)
      end },
    { id="cape", name="Abyssal Cape", slot="back", kind="shop", rarity="epic", cost=3250, desc="Drama, in cloth form.",
      draw=function(c)
        local sway = math.sin(c.t*1.5)*c.w*0.4
        sc({0.35,0.05,0.10}, 0.92*c.alpha)
        love.graphics.polygon("fill", -c.w*0.7,-c.len*0.2, c.w*0.7,-c.len*0.2,
            c.w*1.1+sway, c.len*0.6, -c.w*1.1+sway, c.len*0.6)
      end },
    { id="trenchcoat", name="Trench Coat", slot="back", kind="shop", rarity="rare", cost=1350, desc="For the trench. It's a pun. You're welcome.",
      draw=function(c)
        local sway = math.sin(c.t*1.3)*c.w*0.12
        local khaki = {0.6,0.5,0.32}
        local lite  = {0.72,0.62,0.42}
        local dark  = {0.45,0.37,0.23}
        -- two coat panels WRAPPING the body sides (they flare out past the squid's
        -- edges, framing it like a worn open coat instead of a hanging cape)
        sc(khaki, 0.96*c.alpha)
        love.graphics.polygon("fill",                                   -- left panel
            -c.w*0.30, -c.len*0.28, -c.w*1.15, -c.len*0.12,
            -c.w*1.5+sway, c.len*0.5, -c.w*0.25, c.len*0.46)
        love.graphics.polygon("fill",                                   -- right panel
             c.w*0.30, -c.len*0.28,  c.w*1.15, -c.len*0.12,
             c.w*1.5+sway, c.len*0.5,  c.w*0.25, c.len*0.46)
        -- darker inner-edge lining where the coat opens down the front
        sc(dark, 0.9*c.alpha)
        love.graphics.polygon("fill", -c.w*0.30,-c.len*0.28, -c.w*0.12,-c.len*0.26, -c.w*0.08,c.len*0.46, -c.w*0.25,c.len*0.46)
        love.graphics.polygon("fill",  c.w*0.30,-c.len*0.28,  c.w*0.12,-c.len*0.26,  c.w*0.08,c.len*0.46,  c.w*0.25,c.len*0.46)
        -- popped collar beside the neck
        sc(lite, c.alpha)
        love.graphics.polygon("fill", -c.w*0.30,-c.len*0.28, -c.w*0.72,-c.len*0.34, -c.w*0.5,-c.len*0.12)
        love.graphics.polygon("fill",  c.w*0.30,-c.len*0.28,  c.w*0.72,-c.len*0.34,  c.w*0.5,-c.len*0.12)
        -- belt cinched around the middle (shows on both sides of the body)
        sc(dark, c.alpha)
        love.graphics.rectangle("fill", -c.w*1.3, c.len*0.13, c.w*2.6, c.len*0.06)
        -- buttons running down each visible coat edge
        sc({0.85,0.8,0.6}, c.alpha)
        for i=0,2 do
            love.graphics.circle("fill", -c.w*0.9, c.len*(-0.05+i*0.15), c.w*0.05)
            love.graphics.circle("fill",  c.w*0.9, c.len*(-0.05+i*0.15), c.w*0.05)
        end
      end },
    { id="jetpack", name="Bubble Jets", slot="back", kind="shop", rarity="rare", cost=2200, desc="Extra propulsion (cosmetic).",
      draw=function(c)
        -- two chunky thruster pods with metal nozzles
        sc({0.55,0.62,0.72}, c.alpha)
        love.graphics.rectangle("fill", -c.w*0.95, -c.len*0.05, c.w*0.42, c.len*0.46, c.w*0.12)
        love.graphics.rectangle("fill",  c.w*0.53, -c.len*0.05, c.w*0.42, c.len*0.46, c.w*0.12)
        sc({0.35,0.4,0.5}, c.alpha)
        love.graphics.rectangle("fill", -c.w*0.9, c.len*0.39, c.w*0.32, c.len*0.09)
        love.graphics.rectangle("fill",  c.w*0.58, c.len*0.39, c.w*0.32, c.len*0.09)
        -- streaming bubble plumes out the back
        for _, sx in ipairs({ -0.74, 0.74 }) do
            for b = 1, 5 do
                local ph = (c.t * 1.5 + b * 0.4 + (sx > 0 and 0.5 or 0)) % 1
                local by = c.len * 0.48 + ph * c.len * 0.7
                local bx = c.w * sx + math.sin(ph * 8 + b) * c.w * 0.12
                sc({0.8,0.9,1.0}, (1 - ph) * 0.7 * c.alpha)
                love.graphics.setLineWidth(1.5)
                love.graphics.circle("line", bx, by, c.w * (0.08 + ph * 0.2))
            end
        end
        -- bright thrust glow at the nozzles
        sc(c.skin.glow, 0.85 * c.pulse * c.alpha)
        love.graphics.circle("fill", -c.w*0.74, c.len*0.47, c.w*0.22*c.pulse)
        love.graphics.circle("fill",  c.w*0.74, c.len*0.47, c.w*0.22*c.pulse)
      end },

    -- ---- aura ----
    { id="halo", name="Halo", slot="aura", kind="special", rarity="special", ach="terror_win", desc="Survived TERROR. A saintly squid.",
      draw=function(c)
        sc(P.gold, (0.5+0.4*c.pulse)*c.alpha); love.graphics.setLineWidth(c.w*0.12)
        love.graphics.ellipse("line", 0, -c.len*0.7, c.w*0.6, c.w*0.22)
      end },
    -- ---- Churgly'nth true-end relic (2 of 3) ----
    { id="fractal_veil", name="Fractal Veil", slot="aura", kind="special", rarity="special", ach="churgly_slain", desc="Nested geometry orbits you, forever folding.",
      draw=function(c)
        for layer=1,4 do
          local sides = 2+layer
          local rr = c.w*(0.8+layer*0.22)*(1+0.06*math.sin(c.t*2+layer))
          local rot = c.t*(0.5+layer*0.4)*(layer%2==0 and -1 or 1)
          sc({0.55+0.1*layer, 0.12, 0.8}, (0.5+0.3*c.pulse)*c.alpha)
          love.graphics.setLineWidth(c.w*0.05)
          local pts={}
          for i=0,sides-1 do
            local a=rot+i/sides*math.pi*2
            pts[#pts+1]=math.cos(a)*rr; pts[#pts+1]=math.sin(a)*rr-c.len*0.05
          end
          love.graphics.polygon("line", pts)
        end
      end },
    { id="sparks", name="Static Field", slot="aura", kind="shop", rarity="epic", cost=3650, desc="Crackling with charge.",
      draw=function(c)
        sc(c.skin.glow, 0.8*c.alpha); love.graphics.setLineWidth(c.w*0.05)
        for i=1,6 do
            local a = i/6*math.pi*2 + c.t*3
            local r1, r2 = c.w*1.1, c.w*(1.3+0.3*math.sin(c.t*8+i))
            love.graphics.line(math.cos(a)*r1, math.sin(a)*r1-c.len*0.1,
                               math.cos(a)*r2, math.sin(a)*r2-c.len*0.1)
        end
      end },
    { id="starfield", name="Starfield", slot="aura", kind="shop", rarity="legendary", cost=6900, desc="A galaxy orbits you. Absurdly expensive.",
      draw=function(c)
        for i=1,22 do
          local a = i*2.39963 + c.t*0.6
          local rr = c.w*(0.9 + (i%5)*0.16)
          local tw = 0.4+0.6*math.abs(math.sin(c.t*3 + i))
          local col = (i%3==0) and P.cyan or (i%3==1) and P.magenta or P.gold
          love.graphics.setColor(col[1],col[2],col[3], tw*c.alpha)
          love.graphics.circle("fill", math.cos(a)*rr, math.sin(a)*rr - c.len*0.05, c.w*0.05*tw)
        end
      end },

    -- ---- trail (ink trail color; no body geometry) ----
    { id="trail_cyan", name="Cyan Wake", slot="trail", kind="basic", rarity="basic", desc="Classic ink.", trail={0.3,0.9,1.0} },
    { id="trail_gold", name="Golden Wake", slot="trail", kind="shop", rarity="rare", cost=1950, desc="Leave wealth behind you.", trail={1.0,0.82,0.3} },
    { id="trail_matrix", name="Hacker Wake", slot="trail", kind="shop", rarity="rare", cost=2200, desc="A stream of green 01010 in your wake. Very l33t.", trail="matrix" },
    { id="trail_rainbow", name="Prismfall", slot="trail", kind="shop", rarity="epic", cost=3900, desc="A spectrum in your wake.", trail="rainbow" },
    { id="trail_blood", name="Crimson Wake", slot="trail", kind="special", rarity="special", ach="combo_50", desc="50-combo carnage.", trail={1.0,0.15,0.2} },
    -- ---- Churgly'nth true-end relic (3 of 3) ----
    { id="trail_void", name="Fractal Wake", slot="trail", kind="special", rarity="special", ach="churgly_slain", desc="Self-similar shards of the fractalspace bleed from your wake.", trail="fractal" },
}

----------------------------------------------------------------------
-- Lookups + helpers
----------------------------------------------------------------------
C.skinById = {}
for _, s in ipairs(C.skins) do
    s.belly = s.belly or U.shade(s.body, 1.4)
    s.glowStrength = s.glowStrength or 0.5
    C.skinById[s.id] = s
end
C.accById = {}
for _, a in ipairs(C.accessories) do C.accById[a.id] = a end

function C.getSkin(id) return C.skinById[id] or C.skinById["luminer"] end
function C.getAccessory(id) return C.accById[id] end

-- Owned if basic, or recorded in save.owned.
function C.isOwned(save, id)
    local item = C.skinById[id] or C.accById[id]
    if not item then return false end
    if item.kind == "basic" then return true end
    return save.owned[id] == true
end

-- Resolve the player's equipped accessory tables (skips trail-only items,
-- which the renderer doesn't draw). Returns list + the active trail spec.
function C.equippedAccessories(save)
    local list = {}
    local trail = { 0.3, 0.9, 1.0 }
    for slot, id in pairs(save.accessories or {}) do
        local a = C.accById[id]
        if a then
            if a.slot == "trail" then
                trail = a.trail or trail
            elseif a.draw then
                list[#list + 1] = a
            end
        end
    end
    return list, trail
end

-- Catalog grouped by slot for the customizer UI.
function C.accessoriesBySlot(slot)
    local r = {}
    for _, a in ipairs(C.accessories) do
        if a.slot == slot then r[#r + 1] = a end
    end
    return r
end

C.SLOTS = { "hat", "eyes", "face", "back", "aura", "trail" }

return C
