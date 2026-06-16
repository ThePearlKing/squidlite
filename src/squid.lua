-- The customizable squid renderer. Draws a bioluminescent cephalopod from
-- LÖVE primitives so it scales crisply and tints to any skin. Shared by the
-- menu (big preview), the customizer, the shop, and the in-game player.
--
-- Local space: the squid faces UP (-Y). The mantle (pointed end) is forward,
-- big expressive eyes sit just behind the tip, and 8 tentacles trail down and
-- wiggle. We rotate the whole thing by (angle + pi/2) so angle=0 faces +X.
--
-- Skins define color + pattern + glow; accessories (from cosmetics.lua) draw
-- extra geometry in this same local space via their .draw(ctx) callback.

local U = require("src.util")
local Squid = {}

-- Sample the mantle outline (forward = up). Returns flat {x1,y1,x2,y2,...}
-- going down the left edge from tip to base, then back up the right edge.
-- Also returns the half-width at the base so callers can place tentacles.
local function mantleOutline(len, w)
    local left, right = {}, {}
    local N = 16
    local baseHalf
    for i = 0, N do
        local p = i / N                       -- 0 = tip (top), 1 = base (bottom)
        local y = -len * 0.62 + p * (len * 0.92)
        local half
        if p < 0.25 then
            half = w * (p / 0.25) ^ 0.75       -- taper out from the pointed tip
        else
            local q = (p - 0.25) / 0.75
            half = w * (1 - 0.30 * q * q)       -- gentle narrowing toward base
        end
        if i == N then baseHalf = half end
        local li, ri = #left, #right
        left[li + 1] = -half
        left[li + 2] = y
        right[ri + 1] = half
        right[ri + 2] = y
    end
    -- Stitch left edge (tip->base) then right edge (base->tip).
    local poly = {}
    for i = 1, #left do poly[#poly + 1] = left[i] end
    local pts = #right / 2
    for pt = pts, 1, -1 do
        poly[#poly + 1] = right[2 * pt - 1]
        poly[#poly + 1] = right[2 * pt]
    end
    return poly, baseHalf
end

-- One tapered, wiggling tentacle drawn as a chain of quads (each quad is
-- convex so the fill is always correct).
local function drawTentacle(bx, by, length, baseW, curl, phase, t, col, segs, wavy)
    segs = segs or 9
    local px, py = bx, by
    local ang = math.pi / 2 + curl          -- pointing roughly downward
    for i = 1, segs do
        local f = i / segs
        -- traveling wave + per-tentacle phase gives the gentle flow
        local wob = math.sin(t * 2.4 + phase + f * 4.5) * wavy * (0.3 + f)
        ang = ang + wob * 0.06 + curl * 0.10
        local segLen = length / segs
        local nx = px + math.cos(ang) * segLen
        local ny = py + math.sin(ang) * segLen
        local w0 = baseW * (1 - (f - 1 / segs)) ^ 1.3
        local w1 = baseW * (1 - f) ^ 1.3
        local perp = ang + math.pi / 2
        local ox0, oy0 = math.cos(perp) * w0 * 0.5, math.sin(perp) * w0 * 0.5
        local ox1, oy1 = math.cos(perp) * w1 * 0.5, math.sin(perp) * w1 * 0.5
        love.graphics.polygon("fill",
            px - ox0, py - oy0,
            px + ox0, py + oy0,
            nx + ox1, ny + oy1,
            nx - ox1, ny - oy1)
        px, py = nx, ny
    end
    return px, py  -- tip position (for suction-light decoration)
end

-- Draw the pattern overlay, clipped to the mantle via a stencil.
local function drawPattern(skin, len, w, mantle, t)
    local pat = skin.pattern or "solid"
    if pat == "solid" then return end

    love.graphics.stencil(function()
        love.graphics.polygon("fill", mantle)
    end, "replace", 1)
    love.graphics.setStencilTest("greater", 0)

    local acc = skin.accent
    if pat == "stripes" then
        love.graphics.setColor(acc[1], acc[2], acc[3], 0.55)
        for y = -len * 0.6, len * 0.3, len * 0.13 do
            love.graphics.rectangle("fill", -w * 1.2, y, w * 2.4, len * 0.05)
        end
    elseif pat == "spots" then
        love.graphics.setColor(acc[1], acc[2], acc[3], 0.6)
        local seeds = { {-0.4,-0.3,0.18},{0.3,-0.4,0.14},{-0.2,0.05,0.16},
                        {0.35,0.0,0.13},{0.0,-0.55,0.12},{0.15,0.18,0.12},{-0.45,0.12,0.1} }
        for _, s in ipairs(seeds) do
            love.graphics.circle("fill", s[1] * w * 1.4, s[2] * len, s[3] * w)
        end
    elseif pat == "rings" then
        love.graphics.setLineWidth(w * 0.10)
        for ri = 1, 4 do
            local pulse = 0.45 + 0.25 * math.sin(t * 2 + ri)
            love.graphics.setColor(acc[1], acc[2], acc[3], pulse)
            love.graphics.circle("line", 0, -len * 0.18, ri * w * 0.34)
        end
    elseif pat == "gradient" then
        for i = 0, 10 do
            local f = i / 10
            love.graphics.setColor(acc[1], acc[2], acc[3], 0.5 * (1 - f))
            love.graphics.rectangle("fill", -w * 1.3, -len * 0.62 + f * len * 0.9, w * 2.6, len * 0.12)
        end
    elseif pat == "galaxy" then
        -- shimmering star-flecks
        local seeds = { {-0.3,-0.4},{0.2,-0.5},{-0.1,-0.2},{0.3,-0.1},{0.0,-0.6},
                        {0.15,0.1},{-0.35,0.0},{0.4,-0.35},{-0.2,0.18},{0.05,-0.35} }
        for i, s in ipairs(seeds) do
            local tw = 0.4 + 0.6 * math.abs(math.sin(t * 3 + i * 1.7))
            love.graphics.setColor(acc[1], acc[2], acc[3], tw)
            love.graphics.circle("fill", s[1] * w * 1.4, s[2] * len, w * 0.06 * tw)
        end
    end
    love.graphics.setStencilTest()
end

-- Main entry. opts: {skin, accessories(list), angle, scale, t, blink, hurt,
-- alpha, squashX, squashY, noGlow}.
function Squid.draw(x, y, opts)
    opts = opts or {}
    local skin = opts.skin or Squid.fallbackSkin
    local accs = opts.accessories or {}
    local scale = opts.scale or 1
    local t = opts.t or 0
    local angle = opts.angle or (-math.pi / 2)   -- default: face up
    local alpha = opts.alpha or 1
    local hurt = opts.hurt or 0

    local len = 65 * scale
    local w = 21 * scale

    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.rotate(angle + math.pi / 2)
    love.graphics.scale(opts.squashX or 1, opts.squashY or 1)

    local body = skin.body
    local belly = skin.belly or U.shade(body, 1.35)
    local glow = skin.glow or { 0.4, 0.9, 1.0 }
    local pulse = 0.6 + 0.4 * math.sin(t * 2.0)

    -- Bioluminescent halo behind everything.
    if not opts.noGlow then
        local gs = (skin.glowStrength or 0.5) * (0.7 + 0.3 * pulse) * alpha
        U.glow(0, -len * 0.1, len * 0.95, glow, gs * 0.5)
    end

    local mantle, baseHalf = mantleOutline(len, w)

    -- Back accessories (capes, shells) draw behind the body.
    for _, a in ipairs(accs) do
        if a.slot == "back" and a.draw then
            a.draw({ len = len, w = w, t = t, skin = skin, pulse = pulse, alpha = alpha })
        end
    end

    -- Tentacles — same color as the body for one solid silhouette.
    local tentColor = body
    local tcount = 6
    for i = 1, tcount do
        local f = (i - 1) / (tcount - 1)
        local bx = U.lerp(-baseHalf * 0.8, baseHalf * 0.8, f)
        local by = len * 0.24
        local curl = (f - 0.5) * 0.9
        local long = (i == 2 or i == tcount - 1)     -- two long feeding arms
        local length = (long and len * 0.92 or len * 0.58)
        local bw = w * (long and 0.26 or 0.36)
        love.graphics.setColor(tentColor[1], tentColor[2], tentColor[3], alpha)
        local tx, ty = drawTentacle(bx, by, length, bw, curl, i * 1.3, t, tentColor, 9, 0.6)
        love.graphics.setColor(glow[1], glow[2], glow[3], 0.4 * pulse * alpha)
        love.graphics.circle("fill", tx, ty, w * 0.06)
    end

    -- Fins — small, swept-back blades near the tip (kept minimal/simple).
    local finc = U.shade(body, 1.12)
    love.graphics.setColor(finc[1], finc[2], finc[3], 0.9 * alpha)
    for s = -1, 1, 2 do
        love.graphics.polygon("fill",
            s * w * 0.5, -len * 0.40,
            s * w * 1.15, -len * 0.34,
            s * w * 0.6, -len * 0.16)
    end

    -- Mantle body.
    love.graphics.setColor(body[1], body[2], body[3], alpha)
    love.graphics.polygon("fill", mantle)
    -- belly highlight (a lighter inner shape)
    love.graphics.setColor(belly[1], belly[2], belly[3], 0.55 * alpha)
    local inner = mantleOutline(len * 0.86, w * 0.62)
    love.graphics.push()
    love.graphics.translate(0, len * 0.02)
    love.graphics.polygon("fill", inner)
    love.graphics.pop()

    drawPattern(skin, len, w, mantle, t)

    -- hurt flash overlay
    if hurt > 0 then
        love.graphics.setColor(1, 1, 1, hurt * 0.8 * alpha)
        love.graphics.polygon("fill", mantle)
    end

    -- No eyes are drawn — the squid reads cleaner as a solid silhouette. These
    -- coordinates are kept only so eyewear accessories know where to sit.
    local eyeX = w * 0.45
    local eyeY = -len * 0.02
    local eyeR = w * 0.40

    -- Accessories layered front-to-back over the body.
    local order = { eyes = 1, face = 2, hat = 3, trail = 0, aura = 0 }
    for _, a in ipairs(accs) do
        if a.draw and a.slot ~= "back" then
            a.draw({ len = len, w = w, t = t, skin = skin, pulse = pulse,
                     alpha = alpha, eyeX = eyeX, eyeY = eyeY, eyeR = eyeR, baseHalf = baseHalf })
        end
    end

    love.graphics.pop()
end

-- A neutral skin so the renderer never errors if a skin id is missing.
Squid.fallbackSkin = {
    body = { 0.45, 0.55, 0.95 }, belly = { 0.7, 0.78, 1.0 },
    accent = { 0.9, 0.95, 1.0 }, glow = { 0.4, 0.8, 1.0 },
    eye = { 0.96, 0.99, 1.0 }, pupil = { 0.05, 0.05, 0.12 },
    pattern = "solid", glowStrength = 0.5,
}

return Squid
