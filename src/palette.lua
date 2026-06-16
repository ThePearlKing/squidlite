-- Shared color palette. The whole game lives in a bioluminescent deep-sea look:
-- near-black blues, with cyan/teal/magenta glow accents.
local P = {}

P.abyss      = {0.03, 0.05, 0.09}   -- deepest background
P.abyss2     = {0.05, 0.08, 0.14}
P.deep       = {0.07, 0.12, 0.20}
P.panel      = {0.09, 0.14, 0.22}
P.panelEdge  = {0.20, 0.40, 0.55}

P.ink        = {0.04, 0.02, 0.10}   -- the squid's ink (near-black violet)
P.text       = {0.86, 0.94, 0.98}
P.textDim    = {0.55, 0.66, 0.74}
P.textFaint  = {0.36, 0.44, 0.52}

P.cyan       = {0.30, 0.92, 0.98}
P.teal       = {0.20, 0.95, 0.78}
P.aqua       = {0.45, 0.85, 1.00}
P.magenta    = {0.98, 0.36, 0.78}
P.purple     = {0.62, 0.42, 0.98}
P.gold       = {1.00, 0.82, 0.36}
P.coral      = {1.00, 0.50, 0.42}
P.lime       = {0.62, 0.98, 0.45}
P.red        = {1.00, 0.32, 0.36}
P.white      = {0.96, 0.99, 1.00}

-- Rarity tints for cosmetics/shop.
P.rarity = {
    basic    = {0.62, 0.72, 0.80},
    common   = {0.55, 0.90, 0.70},
    rare     = {0.40, 0.70, 1.00},
    epic     = {0.72, 0.45, 1.00},
    legendary= {1.00, 0.80, 0.30},
    special  = {0.98, 0.40, 0.80},  -- achievement-locked
}

return P
