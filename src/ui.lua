-- All non-gameplay screens: main menu, story, run modifiers, character
-- customization, the kraken shop, achievements, soundtrack picker, settings
-- (fullscreen + data reset), and the run-end summary.
--
-- Visual language: bioluminescent deep-sea abyss — near-black gradients,
-- drifting marine snow, faint kraken-tentacle silhouettes, cyan/magenta glow.
-- Layout rule: every screen is laid out so no elements overlap and rows/cards
-- are evenly spaced.

local U = require("src.util")
local P = require("src.palette")
local Squid = require("src.squid")
local Cosmetics = require("src.cosmetics")
local Achievements = require("src.achievements")
local Bestiary = require("src.bestiary")
local Enemies = require("src.enemies")
local Modifiers = require("src.modifiers")
local Audio = require("src.audio")
local Save = require("src.save")
local SecretFX = require("src.secretfx")
local Campaign = require("src.campaign")
local Upgrades = require("src.upgrades")

local KONAMI = { "up", "up", "down", "down", "left", "right", "left", "right", "b", "a" }

local LW, LH = 1280, 720

local UI = {}
UI.__index = UI

function UI.new(app)
    local self = setmetatable({}, UI)
    self.app = app
    self.save = app.save
    self.screen = "menu"
    self.t = 0
    self.mx, self.my = 0, 0
    self.hot = {}
    self.hoverKey = nil
    self.scroll = {}
    self.custSlot = "skin"
    self.selectedMods = {}
    self.difficulty = "normal"
    self.bookOpen = nil          -- open bestiary entry id
    self.bookEnemy = nil
    self.modalStart = nil
    -- reset-data flow: nil | "type" | "confirm"
    self.resetStage = nil
    self.resetText = ""
    -- kraken shop state
    self.kraken = { excite = 0, eye = 0.2 }
    self.coins = {}
    self.dragSlider = nil
    self.konami = {}     -- rolling buffer for the secret-settings code
    -- ambient marine snow shared by all screens
    self.snow = {}
    for _ = 1, 90 do
        self.snow[#self.snow + 1] = { x = U.rand(0, LW), y = U.rand(0, LH),
            s = U.rand(0.4, 1.6), v = U.rand(5, 20), r = U.rand(1, 2.6) }
    end
    return self
end

function UI:setScreen(name)
    self.screen = name
    self.bookOpen = nil
    self.numEdit = nil; self.editField = nil   -- don't carry a half-typed field across screens
    self.scroll[name] = self.scroll[name] or 0
    if name == "modifiers" then self.selectedMods = {} end
end

----------------------------------------------------------------------
-- widgets
----------------------------------------------------------------------
local function fonts(self) return self.app.fonts end

function UI:reg(x, y, w, h, action, disabled, action2)
    self.hot[#self.hot + 1] = { x = x, y = y, w = w, h = h, action = action, disabled = disabled, action2 = action2 }
end

function UI:button(x, y, w, h, label, action, opts)
    opts = opts or {}
    local hov = U.inRect(self.mx, self.my, x, y, w, h) and not opts.disabled
    local key = label .. ":" .. x .. "," .. y
    if hov and self.hoverKey ~= key then self.hoverKey = key; Audio.play("hover", 0.5) end
    local col = opts.color or P.cyan
    local bg = opts.disabled and { 0.08, 0.10, 0.14 } or (hov and U.shade(P.panel, 1.4) or P.panel)
    love.graphics.setColor(bg[1], bg[2], bg[3], 0.95)
    love.graphics.rectangle("fill", x, y, w, h, 8)
    if hov then U.glow(x + w / 2, y + h / 2, w * 0.6, col, 0.18) end
    love.graphics.setColor(col[1], col[2], col[3], opts.disabled and 0.3 or (hov and 1 or 0.65))
    love.graphics.setLineWidth(hov and 3 or 2)
    love.graphics.rectangle("line", x, y, w, h, 8)
    love.graphics.setFont(opts.font or fonts(self).medium)
    love.graphics.setColor(opts.disabled and P.textFaint or P.text)
    love.graphics.printf(label, x, y + h / 2 - (opts.font and opts.font:getHeight() or 22) / 2, w, "center")
    self:reg(x, y, w, h, action, opts.disabled)
    return hov
end

function UI:title(text, y, color)
    love.graphics.setFont(fonts(self).big)
    color = color or P.cyan
    love.graphics.setColor(color[1], color[2], color[3], 0.25)
    love.graphics.printf(text, 0, y + 2, LW, "center")
    love.graphics.setColor(color)
    love.graphics.printf(text, 0, y, LW, "center")
    love.graphics.setFont(fonts(self).normal)
end

----------------------------------------------------------------------
-- ambient background
----------------------------------------------------------------------
function UI:drawBackground()
    for i = 0, 24 do
        local f = i / 24
        love.graphics.setColor(U.lerp(P.deep[1], P.abyss[1], f), U.lerp(P.deep[2], P.abyss[2], f),
            U.lerp(P.deep[3], P.abyss[3], f))
        love.graphics.rectangle("fill", 0, f * LH, LW, LH / 24 + 1)
    end
    -- faint giant tentacle silhouettes swaying at the bottom edges
    love.graphics.setColor(0.05, 0.10, 0.16, 0.6)
    for s = -1, 1, 2 do
        local bx = s < 0 and 120 or LW - 120
        for i = 1, 4 do
            local sway = math.sin(self.t * 0.6 + i + s) * 40
            love.graphics.setLineWidth(26 - i * 4)
            love.graphics.line(bx + (i - 2) * 40, LH + 20,
                bx + (i - 2) * 40 + sway, LH - 220 - i * 30)
        end
    end
    -- marine snow
    for _, sn in ipairs(self.snow) do
        love.graphics.setColor(0.6, 0.8, 1.0, 0.10 * sn.s)
        love.graphics.circle("fill", sn.x, sn.y, sn.r)
    end
    -- god-ray shimmer from the surface
    love.graphics.setColor(0.3, 0.6, 0.9, 0.03)
    for i = 1, 6 do
        local x = (i / 7) * LW + math.sin(self.t * 0.3 + i) * 30
        love.graphics.polygon("fill", x - 40, 0, x + 40, 0, x + 120, LH, x - 120, LH)
    end
end

----------------------------------------------------------------------
-- main update / draw
----------------------------------------------------------------------
function UI:update(dt, mx, my)
    self.t = self.t + dt
    self.mx, self.my = mx, my
    -- held-backspace repeat for text fields: one delete on press (handled in
    -- keypressed), then after a short delay it auto-repeats like a real keyboard.
    if (self.editField or self.numEdit or self.resetStage == "type") and love.keyboard.isDown("backspace") then
        self.bsHeld = (self.bsHeld or 0) + dt
        if self.bsHeld > 0.4 then
            self.bsRepeat = (self.bsRepeat or 0) - dt
            if self.bsRepeat <= 0 then
                self.bsRepeat = 0.04
                if self.numEdit then self.numEdit.buf = self.numEdit.buf:sub(1, -2)
                elseif self.editField then self.editField.set(self.editField.get():sub(1, -2))
                elseif self.resetStage == "type" then self.resetText = self.resetText:sub(1, -2) end
            end
        end
    else
        self.bsHeld = 0; self.bsRepeat = 0
    end
    for _, sn in ipairs(self.snow) do
        sn.y = sn.y + sn.v * dt
        if sn.y > LH then sn.y = -4; sn.x = U.rand(0, LW) end
    end
    -- kraken excitement decays
    self.kraken.excite = math.max(0, self.kraken.excite - dt)
    self.kraken.eye = U.approach(self.kraken.eye, self.kraken.excite > 0 and 1 or 0.22, 6, dt)
    -- coin animation
    local i = 1
    while i <= #self.coins do
        local c = self.coins[i]
        c.t = c.t + dt * 1.3   -- half speed
        if c.t >= 1 then
            self.kraken.excite = 1.2
            Audio.play("coin", 0.5)
            table.remove(self.coins, i)
        else i = i + 1 end
    end
    -- slider drag
    if self.dragSlider and love.mouse.isDown(1) then
        self:applySlider(self.dragSlider, mx)
    end
end

function UI:draw()
    self.hot = {}
    self.modalStart = nil
    self.frameHover = nil
    self.hoverTip = nil
    self:drawBackground()
    love.graphics.setFont(fonts(self).normal)
    local fn = self["screen_" .. self.screen]
    if fn then fn(self) end
    if self.bookOpen then self:drawBestiaryBook() end
    if self.hoverTip and not self.bookOpen then self:drawTooltip(self.hoverTip) end
    -- reset-data modal sits above everything
    if self.resetStage then self:drawResetModal() end
end

local BOOK_VARIANTS = { { nil, "Base" }, { "elite", "Elite" }, { "abyssal", "Abyssal" } }

function UI:openBook(id)
    self.bookOpen = id
    self.bookVariant = 1
    self:buildBookEnemy()
    -- mark this page as read (clears its red "!" in the list)
    self.save.bestiarySeen = self.save.bestiarySeen or {}
    if not self.save.bestiarySeen[id] then self.save.bestiarySeen[id] = true; Save.flush() end
    Audio.play("click", 0.6)
end
function UI:closeBook() self.bookOpen = nil; self.bookEnemy = nil end

-- (re)create the portrait instance for the current variant. Bosses & the
-- leviathan have no variants (bookEnemy may be nil for the leviathan).
function UI:buildBookEnemy()
    local et = Enemies.types[self.bookOpen]
    if not et then self.bookEnemy = nil; return end
    local v = (not et.boss) and BOOK_VARIANTS[self.bookVariant][1] or nil
    self.bookEnemy = Enemies.spawn(self.bookOpen, 0, 0, { variant = v })
end
function UI:cycleBookVariant(dir)
    local n = (self.bookOpen == "leviathan") and 2 or #BOOK_VARIANTS
    self.bookVariant = (self.bookVariant - 1 + dir) % n + 1
    self:buildBookEnemy()
    Audio.play("hover", 0.6)
end

function UI:drawBestiaryBook()
    local entry = Bestiary.byId[self.bookOpen]
    if not entry then self:closeBook(); return end
    love.graphics.setColor(0, 0, 0.02, 0.82); love.graphics.rectangle("fill", 0, 0, LW, LH)
    self.modalStart = #self.hot + 1
    self:reg(0, 0, LW, LH, function() self:closeBook() end)   -- click outside closes

    local mw, mh = 860, 470
    local mx, my = LW / 2 - mw / 2, LH / 2 - mh / 2
    love.graphics.setColor(0.10, 0.08, 0.07, 0.99); love.graphics.rectangle("fill", mx, my, mw, mh, 12)
    love.graphics.setColor(P.gold[1], P.gold[2], P.gold[3], 0.7); love.graphics.setLineWidth(3)
    love.graphics.rectangle("line", mx, my, mw, mh, 12)
    love.graphics.setColor(0, 0, 0, 0.4); love.graphics.rectangle("fill", mx + mw / 2 - 3, my + 14, 6, mh - 28)

    -- LEFT PAGE: living portrait of the beast
    love.graphics.setColor(0.04, 0.07, 0.11, 0.7)
    love.graphics.rectangle("fill", mx + 20, my + 20, mw / 2 - 36, mh - 40, 8)
    local pcx, pcy = mx + mw * 0.25, my + mh * 0.5
    local e = self.bookEnemy
    if e then
        e.anim = self.t
        local s = 80 / (e.radius or 30)
        love.graphics.push(); love.graphics.translate(pcx, pcy + 20); love.graphics.scale(s)
        e.x, e.y, e.facing = 0, 0, -math.pi / 2
        local stub = { player = { x = 0, y = -150 },
            arena = { x = -600, y = -600, w = 1200, h = 1200 },
            particles = { burst = function() end, spawn = function() end },
            time = function() return self.t end }
        pcall(function() e.type.render(e, stub) end)
        love.graphics.pop()
    else
        self:drawLeviathanIcon(pcx, pcy, self.bookVariant == 2)   -- the leviathan (pale / dark-blue)
    end

    -- variant cycler — creatures (◄ Base / Elite / Abyssal ►) and the leviathan
    -- (◄ Pale / Dark Blue ►)
    local et = Enemies.types[self.bookOpen]
    local isLevi = (self.bookOpen == "leviathan")
    if (e and et and not et.boss) or isLevi then
        local vname, vtint
        if isLevi then
            vname = (self.bookVariant == 2) and "Dark Blue" or "Pale"
            vtint = (self.bookVariant == 2) and { 0.4, 0.6, 1.0 } or P.textDim
        else
            vname = BOOK_VARIANTS[self.bookVariant][2]
            vtint = (self.bookVariant == 2) and { 1.0, 0.82, 0.3 }
                or (self.bookVariant == 3) and { 0.98, 0.36, 0.78 } or P.textDim
        end
        local cy = my + mh - 46
        local lx, rx2 = mx + 40, mx + mw / 2 - 76
        love.graphics.setFont(fonts(self).medium)
        for _, b in ipairs({ { lx, "<", -1 }, { rx2, ">", 1 } }) do
            local hov = U.inRect(self.mx, self.my, b[1], cy, 36, 36)
            love.graphics.setColor(P.panel[1], P.panel[2], P.panel[3], 0.95)
            love.graphics.rectangle("fill", b[1], cy, 36, 36, 6)
            love.graphics.setColor(hov and P.gold or P.textDim); love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", b[1], cy, 36, 36, 6)
            love.graphics.printf(b[2], b[1], cy + 4, 36, "center")
            self:reg(b[1], cy, 36, 36, function() self:cycleBookVariant(b[3]) end)
        end
        love.graphics.setColor(vtint)
        love.graphics.printf(vname:upper(), lx + 40, cy + 4, rx2 - lx - 40, "center")
    end

    -- RIGHT PAGE: name, kind, lore, tally
    local tx, tw = mx + mw * 0.55, mw * 0.4 - 24
    love.graphics.setFont(fonts(self).big); love.graphics.setColor(P.text)
    love.graphics.printf(entry.name, tx, my + 44, tw, "left")
    love.graphics.setFont(fonts(self).small)
    local kc = entry.kind == "boss" and P.gold or (entry.kind == "event" and P.lime or P.cyan)
    love.graphics.setColor(kc); love.graphics.printf(entry.kind:upper(), tx, my + 92, tw, "left")
    love.graphics.setColor(P.textDim); love.graphics.printf(entry.lore, tx, my + 134, tw, "left")
    love.graphics.setColor(P.textFaint)
    local verb = entry.kind == "event" and "Survived" or "Defeated"
    love.graphics.printf(verb .. ": " .. Bestiary.progress(self.save, self.bookOpen), tx, my + mh - 56, tw, "left")

    -- close X
    local cx, cy = mx + mw - 40, my + 14
    love.graphics.setColor(P.textDim); love.graphics.setLineWidth(3)
    love.graphics.line(cx + 6, cy + 6, cx + 20, cy + 20); love.graphics.line(cx + 20, cy + 6, cx + 6, cy + 20)
    self:reg(cx, cy, 30, 30, function() self:closeBook() end)
end

-- The pale uncanny leviathan head for its bestiary page: tall open maw with
-- flat human teeth, and a long sinister eye-slit to the side.
function UI:drawLeviathanIcon(cx, cy, blue)
    local r = 60
    if blue then
        -- the rare DARK-BLUE leviathan: eyeless, a forward-gaping fanged maw
        U.glow(cx, cy, r * 1.4, { 0.32, 0.5, 1.0 }, 0.4)
        love.graphics.setColor(0.08, 0.12, 0.36, 1)
        love.graphics.polygon("fill",
            cx - 1.0 * r, cy - 0.3 * r, cx - 0.2 * r, cy - 1.0 * r, cx + 0.6 * r, cy - 0.95 * r, cx + 1.3 * r, cy - 0.1 * r,
            cx + 1.25 * r, cy + 0.6 * r, cx + 0.5 * r, cy + 1.1 * r, cx - 0.5 * r, cy + 0.9 * r, cx - 1.0 * r, cy + 0.3 * r)
        local hux, huy, hlx, hly = cx - 0.3 * r, cy - 0.1 * r, cx - 0.3 * r, cy + 0.1 * r
        local fux, fuy, flx, fly = cx + 1.22 * r, cy - 0.72 * r, cx + 1.22 * r, cy + 0.72 * r
        love.graphics.setColor(0.01, 0.01, 0.04, 1)
        love.graphics.polygon("fill", hux, huy, fux, fuy, cx + 1.42 * r, cy, flx, fly, hlx, hly)
        love.graphics.setColor(0.86, 0.91, 0.98, 1)
        local function jaw(ax, ay, bx, by, sign)
            local dx, dy = bx - ax, by - ay
            local len = math.sqrt(dx * dx + dy * dy)
            local nx, ny = -dy / len * sign, dx / len * sign
            for i = 0, 8 do
                local tc = (i + 0.5) / 9
                local px, py = ax + dx * tc, ay + dy * tc
                local hwd = (len / 9) * 0.26
                local bxv, byv = dx / len * hwd, dy / len * hwd
                local vary = (i % 2 == 0 and 1.0 or 0.55) * (0.75 + 0.5 * math.abs(math.sin(i * 2.7)))
                local tl = (0.34 * r) * (0.5 + 0.8 * tc) * vary
                love.graphics.polygon("fill", px - bxv, py - byv, px + bxv, py + byv, px + nx * tl, py + ny * tl)
            end
        end
        jaw(hux, huy, fux, fuy, 1)
        jaw(hlx, hly, flx, fly, -1)
        return
    end
    U.glow(cx, cy - 0.1 * r, r * 1.4, { 0.7, 0.55, 0.95 }, 0.4)
    -- upper head + snout
    love.graphics.setColor(0.82, 0.76, 0.90, 1)
    love.graphics.polygon("fill", cx - 1.0 * r, cy - 0.3 * r, cx - 0.3 * r, cy - 1.0 * r, cx + 0.5 * r, cy - 0.9 * r,
        cx + 0.85 * r, cy - 0.45 * r, cx + 1.3 * r, cy - 0.05 * r, cx + 1.15 * r, cy + 0.15 * r,
        cx + 0.2 * r, cy + 0.15 * r, cx - 0.45 * r, cy)
    -- long dropped lower jaw
    love.graphics.setColor(0.68, 0.62, 0.78, 1)
    love.graphics.polygon("fill", cx - 0.35 * r, cy + 0.25 * r, cx + 1.05 * r, cy + 0.9 * r, cx + 1.32 * r, cy + 1.15 * r,
        cx + 0.6 * r, cy + 1.45 * r, cx - 0.45 * r, cy + 1.1 * r)
    -- tall black mouth
    love.graphics.setColor(0.04, 0.02, 0.06, 1)
    love.graphics.polygon("fill", cx + 0.18 * r, cy + 0.13 * r, cx + 1.18 * r, cy + 0.1 * r, cx + 1.05 * r, cy + 0.95 * r, cx + 0.2 * r, cy + 0.92 * r)
    -- flat human teeth, top and bottom
    love.graphics.setColor(0.95, 0.93, 0.9, 1)
    for j = 0, 6 do
        local tu = U.lerp(cx + 0.28 * r, cx + 1.04 * r, j / 6)
        love.graphics.rectangle("fill", tu, cy + 0.13 * r, r * 0.09, r * 0.16, 2)
        local tl = U.lerp(cx + 0.33 * r, cx + 0.99 * r, j / 6)
        love.graphics.rectangle("fill", tl, cy + 0.92 * r - r * 0.16, r * 0.09, r * 0.16, 2)
    end
    -- long eye-slit to the side
    love.graphics.push(); love.graphics.translate(cx + 0.38 * r, cy - 0.52 * r); love.graphics.rotate(-0.14)
    love.graphics.setColor(0.05, 0.02, 0.07, 1); love.graphics.ellipse("fill", 0, 0, r * 0.44, r * 0.11)
    love.graphics.setColor(0.7, 0.55, 0.95, 0.9); love.graphics.ellipse("fill", 0, 0, r * 0.36, r * 0.035)
    love.graphics.pop()
end

-- Floating tooltip near the cursor (used to show how to unlock locked items).
function UI:drawTooltip(text)
    local f = fonts(self).small
    love.graphics.setFont(f)
    local w = math.min(380, f:getWidth(text) + 24)
    local _, wrapped = f:getWrap(text, w - 20)
    local h = #wrapped * (f:getHeight() + 2) + 16
    local x = U.clamp(self.mx + 18, 4, LW - w - 4)
    local y = U.clamp(self.my + 18, 4, LH - h - 4)
    love.graphics.setColor(0, 0, 0.02, 0.92)
    love.graphics.rectangle("fill", x, y, w, h, 6)
    love.graphics.setColor(P.rarity.special[1], P.rarity.special[2], P.rarity.special[3], 0.9)
    love.graphics.setLineWidth(1); love.graphics.rectangle("line", x, y, w, h, 6)
    love.graphics.setColor(P.text)
    love.graphics.printf(text, x + 10, y + 8, w - 20, "left")
end

----------------------------------------------------------------------
-- input routing
----------------------------------------------------------------------
function UI:mousepressed(mx, my, button)
    self.mx, self.my = mx, my
    local start = self.modalStart or 1
    -- right-click: trigger the topmost region that has a right-click action
    if button == 2 then
        for i = #self.hot, start, -1 do
            local b = self.hot[i]
            if not b.disabled and b.action2 and U.inRect(mx, my, b.x, b.y, b.w, b.h) then
                b.action2(); return
            end
        end
        return
    end
    if button ~= 1 then return end
    for i = #self.hot, start, -1 do
        local b = self.hot[i]
        if not b.disabled and U.inRect(mx, my, b.x, b.y, b.w, b.h) then
            Audio.play("click", 0.6)
            if b.action then b.action() end
            return
        end
    end
end

function UI:mousereleased() self.dragSlider = nil end

function UI:wheelmoved(_, dy)
    -- the starting-cards picker scrolls its own list while open
    if self.cardPickerOpen then
        self.cardScroll = math.max(0, math.min((self.cardScroll or 0) - dy * 52, self.cardScrollMax or 0))
        return
    end
    -- in the editor, scrolling over the bottom "Depths & Titles" bar pans it
    -- horizontally (the cards run left-to-right); elsewhere scrolls vertically.
    if self.screen == "editor" and (self.my or 0) >= 560 then
        self.timelineScroll = math.max(0, math.min((self.timelineScroll or 0) - dy * 64, self.timelineMax or 0))
        return
    end
    self.scroll[self.screen] = (self.scroll[self.screen] or 0) - dy * 48
    if self.scroll[self.screen] < 0 then self.scroll[self.screen] = 0 end
    if self.maxScroll then self.scroll[self.screen] = math.min(self.scroll[self.screen], self.maxScroll) end
end

function UI:keypressed(key)
    -- typing a number into a config stepper value
    if self.numEdit then
        if key == "backspace" then self.numEdit.buf = self.numEdit.buf:sub(1, -2)
        elseif key == "return" or key == "kpenter" then self:commitNumEdit()
        elseif key == "escape" then self.numEdit = nil end
        return
    end
    -- editing a campaign text field (name / depth name / title text)
    if self.editField then
        if key == "backspace" then
            local v = self.editField.get()
            self.editField.set(v:sub(1, -2))
        elseif key == "return" or key == "escape" then
            self.editField = nil
        end
        return
    end
    if self.bookOpen then
        if key == "escape" then self:closeBook() end
        return
    end
    if self.resetStage == "type" then
        if key == "backspace" then self.resetText = self.resetText:sub(1, -2)
        elseif key == "escape" then self:closeReset() end
        return
    elseif self.resetStage == "confirm" then
        if key == "escape" then self:closeReset() end
        return
    end
    -- Konami code → Super Secret Settings (works on any normal menu)
    self.konami[#self.konami + 1] = key
    while #self.konami > #KONAMI do table.remove(self.konami, 1) end
    local match = #self.konami == #KONAMI
    for i = 1, #KONAMI do if self.konami[i] ~= KONAMI[i] then match = false break end end
    if match then
        self.konami = {}
        self.save.secretUnlocked = true
        Save.flush()
        Audio.play("win", 0.7)
        require("src.debuglog").add("KONAMI! Super Secret Settings unlocked")
        self.app.toasts[#self.app.toasts + 1] = { a = { name = "Super Secret Settings!" }, t = 4 }
        self:setScreen("secret")
        return
    end

    if key == "escape" then
        if self.screen ~= "menu" and self.screen ~= "story" then self:setScreen("menu") end
    end
end

function UI:textinput(t)
    if self.numEdit then
        if t:match("[%d%.%-]") and #self.numEdit.buf < 9 then self.numEdit.buf = self.numEdit.buf .. t end
        return
    end
    if self.editField then
        local v = self.editField.get()
        if #v < (self.editField.max or 40) then self.editField.set(v .. t) end
        return
    end
    if self.resetStage == "type" and #self.resetText < 12 then
        self.resetText = self.resetText .. t
    end
end

----------------------------------------------------------------------
-- helper: current equipped loadout preview
----------------------------------------------------------------------
function UI:drawPlayerPreview(cx, cy, scale)
    local skin = Cosmetics.getSkin(self.save.skin)
    local accs = Cosmetics.equippedAccessories(self.save)
    Squid.draw(cx, cy, {
        skin = skin, accessories = accs, angle = -math.pi / 2, scale = scale,
        t = self.t, blink = (math.sin(self.t * 0.8) > 0.97) and 1 or 0,
    })
end

----------------------------------------------------------------------
-- SCREEN: main menu
----------------------------------------------------------------------
function UI:screen_menu()
    local f = fonts(self)
    -- title
    love.graphics.setFont(f.huge)
    love.graphics.setColor(P.cyan[1], P.cyan[2], P.cyan[3], 0.25)
    love.graphics.printf("SQUIDLITE", 0, 64, LW, "center")
    love.graphics.setColor(P.cyan)
    love.graphics.printf("SQUIDLITE", 0, 60, LW, "center")
    love.graphics.setFont(f.normal)
    love.graphics.setColor(P.textDim)
    love.graphics.printf("descend the trench · face the Maw", 0, 138, LW, "center")
    -- version number, bottom-right
    love.graphics.setFont(fonts(self).small)
    love.graphics.setColor(P.textFaint)
    love.graphics.printf("v" .. (self.app.version or "?"), LW - 130, LH - 30, 110, "right")

    -- squid preview (left)
    self:drawPlayerPreview(360, 430, 2.6)

    -- $Things balance (top-right): white cube token + count
    love.graphics.setFont(f.medium)
    local balTxt = U.commafy(self.save.things)
    local balW = f.medium:getWidth(balTxt)
    love.graphics.setColor(P.white)
    love.graphics.print(balTxt, LW - 30 - balW, 28)
    U.drawThing(LW - 30 - balW - 17, 28 + f.medium:getHeight() / 2, 10)
    love.graphics.setFont(f.small)
    love.graphics.setColor(P.textFaint)
    local s = self.save.stats
    love.graphics.printf(("Wins %d   ·   Best Depth %d   ·   %d/%d achievements")
        :format(s.totalWins, s.bestDepth, Achievements.countUnlocked(self.save), #Achievements.list),
        LW - 540, 58, 510, "right")

    -- menu buttons (right column, evenly spaced). Nudged up one button height
    -- so the QUIT button isn't sitting right on the floor.
    local bx, bw, bh, gap = 820, 380, 48, 12
    local by = 184 - bh
    local items = {
        { "DESCEND", function() self:setScreen("modifiers") end, P.teal },
        { "CUSTOMIZE", function() self:setScreen("customize") end, P.cyan },
        { "SHOP", function() self:setScreen("shop") end, P.gold },
        { "BESTIARY", function() self:setScreen("bestiary") end, P.lime },
        { "ACHIEVEMENTS", function() self:setScreen("achievements") end, P.magenta },
        { "SOUNDTRACK", function() self:setScreen("music") end, P.purple },
        { "CUSTOM CAMPAIGN", function() self:setScreen("campaigns") end, P.teal },
        { "SETTINGS", function() self:setScreen("settings") end, P.aqua },
        { "QUIT", function() love.event.quit() end, P.coral },
    }
    for i, it in ipairs(items) do
        self:button(bx, by + (i - 1) * (bh + gap), bw, bh, it[1], it[2], { color = it[3], font = fonts(self).medium })
    end

    -- small circular LORE button, bottom-left — reopen the intro story anytime
    local lcx, lcy, lr = 58, LH - 58, 26
    local lhov = U.dist(self.mx, self.my, lcx, lcy) < lr
    love.graphics.setColor(P.aqua[1], P.aqua[2], P.aqua[3], lhov and 0.28 or 0.12)
    love.graphics.circle("fill", lcx, lcy, lr)
    love.graphics.setColor(P.aqua[1], P.aqua[2], P.aqua[3], 1); love.graphics.setLineWidth(2)
    love.graphics.circle("line", lcx, lcy, lr)
    -- open-book glyph (no font glyphs, just strokes)
    love.graphics.line(lcx, lcy - 7, lcx, lcy + 7)
    love.graphics.line(lcx, lcy - 7, lcx - 11, lcy - 5); love.graphics.line(lcx - 11, lcy - 5, lcx - 11, lcy + 7); love.graphics.line(lcx - 11, lcy + 7, lcx, lcy + 7)
    love.graphics.line(lcx, lcy - 7, lcx + 11, lcy - 5); love.graphics.line(lcx + 11, lcy - 5, lcx + 11, lcy + 7); love.graphics.line(lcx + 11, lcy + 7, lcx, lcy + 7)
    love.graphics.setFont(fonts(self).small)
    love.graphics.setColor(P.textFaint); love.graphics.printf("LORE", lcx - 40, lcy + lr + 4, 80, "center")
    self:reg(lcx - lr, lcy - lr, lr * 2, lr * 2, function() Audio.play("click", 0.5); self:setScreen("story") end)
end

----------------------------------------------------------------------
-- SCREEN: story / intro
----------------------------------------------------------------------
local STORY = {
    "The sea drank the light. Whatever warmth once reached the trench floor is",
    "long gone, and the glowing folk — the Luminers — went out, one by one.",
    "",
    "You are the last of them still lit. The others did not simply die —",
    "they vanished. Drawn down into the dark, and not one ever came back.",
    "",
    "At the Challenger Deep — the charts mark it only as SITE: ACHERON —",
    "the MAW coils before a sealed gate, and lets nothing past.",
    "",
    "That is as far as anyone has ever charted. What lies beyond the gate,",
    "and where your kin were taken, no one living knows.",
    "",
    "Descend. Ink the dark. Find them.",
}
function UI:screen_story()
    self:title("THE DARKENING", 44, P.aqua)
    self:drawPlayerPreview(LW / 2, 198, 1.6)
    love.graphics.setFont(fonts(self).normal)
    local y = 304
    for _, line in ipairs(STORY) do
        love.graphics.setColor(P.text[1], P.text[2], P.text[3], 0.9)
        love.graphics.printf(line, 0, y, LW, "center")
        y = y + 24
    end
    -- "BEGIN" the very first time; just "BACK" when revisiting from the menu
    local first = not self.save.seenIntro
    self:button(LW / 2 - 160, 640, 320, 54, first and "BEGIN" or "BACK", function()
        self.save.seenIntro = true
        Save.flush()
        self:setScreen("menu")
    end, { color = P.teal })
end

----------------------------------------------------------------------
-- SCREEN: run modifiers (pre-run)
----------------------------------------------------------------------
function UI:isModSelected(id)
    for _, m in ipairs(self.selectedMods) do if m == id then return true end end
    return false
end
function UI:toggleMod(id)
    if self:isModSelected(id) then
        for i, m in ipairs(self.selectedMods) do if m == id then table.remove(self.selectedMods, i); return end end
    else
        self.selectedMods[#self.selectedMods + 1] = id
    end
end

function UI:drawModCard(m, x, y, w, h)
    local sel = self:isModSelected(m.id)
    local hov = U.inRect(self.mx, self.my, x, y, w, h)
    love.graphics.setColor(P.panel[1], P.panel[2], P.panel[3], 0.95)
    love.graphics.rectangle("fill", x, y, w, h, 8)
    love.graphics.setColor(m.color[1], m.color[2], m.color[3], sel and 1 or (hov and 0.8 or 0.4))
    love.graphics.setLineWidth(sel and 3 or 2)
    love.graphics.rectangle("line", x, y, w, h, 8)
    if sel then U.glow(x + w / 2, y + h / 2, w * 0.5, m.color, 0.12) end
    love.graphics.setFont(fonts(self).normal)
    love.graphics.setColor(P.text)
    love.graphics.print(m.name, x + 12, y + 8)
    love.graphics.setFont(fonts(self).small)
    love.graphics.setColor(P.textDim)
    love.graphics.printf(m.desc, x + 12, y + 30, w - 108, "left")
    -- payout badge
    local pm = m.pointMult
    local txt = (pm >= 1 and "+" or "") .. math.floor((pm - 1) * 100 + 0.5) .. "%"
    love.graphics.setColor(pm >= 1 and P.lime or P.coral)
    love.graphics.setFont(fonts(self).medium)
    love.graphics.printf(txt, x + w - 96, y + h / 2 - 12, 90, "right")
    self:reg(x, y, w, h, function() Audio.play("click", 0.5); self:toggleMod(m.id) end)
end

function UI:screen_modifiers()
    self:title("CHART YOUR DESCENT", 30)
    love.graphics.setFont(fonts(self).normal)
    love.graphics.setColor(P.textDim)
    love.graphics.printf("Perils make the trench deadlier and pay MORE. Mercies make it gentler and pay LESS.",
        0, 76, LW, "center")

    -- section headers
    love.graphics.setFont(fonts(self).medium)
    love.graphics.setColor(P.red)
    love.graphics.printf("PERILS", 60, 108, 540, "center")
    love.graphics.setColor(P.lime)
    love.graphics.printf("MERCIES", 720, 108, 500, "center")

    -- perils: two columns of up to 5 on the left
    local perils, mercies = {}, {}
    for _, m in ipairs(Modifiers.list) do
        if m.kind == "peril" then perils[#perils + 1] = m else mercies[#mercies + 1] = m end
    end
    local cw, ch, vgap = 268, 60, 8
    for i, m in ipairs(perils) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        self:drawModCard(m, 60 + col * (cw + 14), 142 + row * (ch + vgap), cw, ch)
    end
    for i, m in ipairs(mercies) do
        self:drawModCard(m, 760, 142 + (i - 1) * (ch + vgap), cw + 60, ch)
    end

    -- difficulty selector
    local DIFF_PAY = { googoobaby = 0.35, easy = 0.8, normal = 1.0, hard = 1.7, terror = 2.5 }
    local DIFF_COL = { googoobaby = P.magenta, easy = P.lime, normal = P.aqua, hard = P.coral, terror = P.red }
    local DIFF_LBL = { googoobaby = "GOO-GOO BABY", easy = "EASY", normal = "NORMAL", hard = "HARD" }
    love.graphics.setFont(fonts(self).normal)
    love.graphics.setColor(P.textDim)
    love.graphics.printf("DIFFICULTY", 0, 486, LW, "center")
    local dlabels = { "googoobaby", "easy", "normal", "hard" }
    local dw, dgap = 158, 10
    local dx0 = LW / 2 - (4 * dw + 3 * dgap) / 2
    for i, d in ipairs(dlabels) do
        local active = self.difficulty == d
        self:button(dx0 + (i - 1) * (dw + dgap), 510, dw, 42, DIFF_LBL[d],
            function() self.difficulty = d end,
            { color = active and DIFF_COL[d] or P.textFaint, font = fonts(self).small })
        if active then
            love.graphics.setColor(DIFF_COL[d]); love.graphics.setLineWidth(3)
            love.graphics.rectangle("line", dx0 + (i - 1) * (dw + dgap), 510, dw, 42, 8)
        end
    end
    -- note that GOO-GOO BABY (the first button) earns $Things but no achievements
    love.graphics.setFont(fonts(self).small)
    love.graphics.setColor(DIFF_COL.googoobaby[1], DIFF_COL.googoobaby[2], DIFF_COL.googoobaby[3], 0.85)
    love.graphics.printf("no achievements", dx0 + dw / 2 - 110, 495, 220, "center")
    -- the SECRET TERROR mode: a bare outline to the right of HARD until you
    -- hover or select it, when it reveals itself in blood red.
    local tx = dx0 + 4 * (dw + dgap)
    local tw = 120
    local thov = U.inRect(self.mx, self.my, tx, 510, tw, 42)
    local tsel = self.difficulty == "terror"
    -- completely invisible until you hover or it's selected
    if thov or tsel then
        love.graphics.setColor(P.red[1], P.red[2], P.red[3], thov and 0.18 or 0.1)
        love.graphics.rectangle("fill", tx, 510, tw, 42, 8)
        love.graphics.setColor(P.red); love.graphics.setLineWidth(tsel and 3 or 2)
        love.graphics.rectangle("line", tx, 510, tw, 42, 8)
        love.graphics.setFont(fonts(self).small); love.graphics.setColor(P.red)
        love.graphics.printf("TERROR", tx, 522, tw, "center")
    end
    self:reg(tx, 510, tw, 42, function() self.difficulty = "terror"; Audio.play("denied", 0.6) end)

    -- combined payout preview (modifiers x difficulty)
    local pm = Modifiers.aggregate(self.selectedMods).pointMult * (DIFF_PAY[self.difficulty] or 1)
    love.graphics.setColor(P.panel[1], P.panel[2], P.panel[3], 0.92)
    love.graphics.rectangle("fill", LW / 2 - 200, 562, 400, 60, 10)
    love.graphics.setFont(fonts(self).small)
    love.graphics.setColor(P.textDim)
    love.graphics.printf("PAYOUT MULTIPLIER", LW / 2 - 200, 570, 400, "center")
    love.graphics.setFont(fonts(self).big)
    love.graphics.setColor(pm >= 1 and P.gold or P.coral)
    love.graphics.printf(string.format("x %.2f", pm), LW / 2 - 200, 588, 400, "center")

    self:button(LW / 2 - 330, 644, 300, 56, "DESCEND", function()
        self.app.startRun(U.deepcopy(self.selectedMods), self.difficulty)
    end, { color = P.teal })
    self:button(LW / 2 + 30, 644, 300, 56, "BACK", function() self:setScreen("menu") end, { color = P.textDim })
end

----------------------------------------------------------------------
-- shared item card (used by customize + shop)
----------------------------------------------------------------------
-- Draw a mini squid wearing `item` (or showing a skin) inside a card.
function UI:drawItemPreview(item, cx, cy, scale, isSkin)
    if isSkin then
        Squid.draw(cx, cy, { skin = item, angle = -math.pi / 2, scale = scale, t = self.t, noGlow = false })
    elseif item.slot == "trail" then
        local col = item.trail
        if col == "rainbow" then col = { 0.5 + 0.5 * math.sin(self.t * 3), 0.6, 1 }
        elseif col == "fractal" then col = { 0.7 + 0.3 * math.sin(self.t * 1.6), 0.18, 0.9 }
        elseif col == "matrix" then col = { 0.6, 1.0, 0.18 } end
        if item.trail == "matrix" then
            -- a little row of floating lime binary digits for the preview
            love.graphics.setColor(col[1], col[2], col[3], 0.95); love.graphics.setLineWidth(2)
            for i = 0, 4 do
                local x = cx - 26 + i * 13
                if i % 2 == 1 then love.graphics.line(x, cy - 7, x, cy + 7); love.graphics.line(x, cy - 7, x - 3, cy - 3)
                else love.graphics.ellipse("line", x, cy, 4, 7) end
            end
        elseif item.trail == "fractal" then
            -- a little branching fractal sprig for the preview
            local function twig(x, y, a, l, d)
                if d <= 0 then return end
                local x2, y2 = x + math.cos(a) * l, y + math.sin(a) * l
                love.graphics.setColor(col[1], col[2], col[3], 0.4 + 0.15 * d)
                love.graphics.setLineWidth(d)
                love.graphics.line(x, y, x2, y2)
                twig(x2, y2, a - 0.6, l * 0.62, d - 1)
                twig(x2, y2, a + 0.6, l * 0.62, d - 1)
            end
            twig(cx - 24, cy, 0, 18, 3)
        else
            for i = 1, 6 do
                love.graphics.setColor(col[1], col[2], col[3], 0.8 - i * 0.1)
                love.graphics.circle("fill", cx - 20 + i * 8, cy + math.sin(self.t * 2 + i) * 4, 8 - i)
            end
        end
    else
        local skin = Cosmetics.getSkin(self.save.skin)
        Squid.draw(cx, cy, { skin = skin, accessories = item.draw and { item } or {},
            angle = -math.pi / 2, scale = scale, t = self.t })
    end
end

-- mode: "customize" | "shop"
function UI:drawItemCard(item, x, y, w, h, isSkin, mode)
    local owned = Cosmetics.isOwned(self.save, item.id)
    local equipped = false
    if isSkin then equipped = (self.save.skin == item.id)
    else equipped = (self.save.accessories[item.slot] == item.id) end
    local hov = U.inRect(self.mx, self.my, x, y, w, h)
    local rc = P.rarity[item.rarity] or P.textDim

    -- hovering shows how a special item is earned — even once you own it
    if hov then
        if item.kind == "special" and item.ach and Achievements.byId[item.ach] then
            local ac = Achievements.byId[item.ach]
            self.hoverTip = (owned and "Unlocked by: " or "LOCKED  ·  Achievement: ") .. ac.name .. "\n" .. ac.desc
        elseif not owned and item.kind == "shop" and mode ~= "shop" then
            self.hoverTip = "Buy in the Shop for $" .. item.cost
        end
    end

    love.graphics.setColor(P.panel[1], P.panel[2], P.panel[3], 0.95)
    love.graphics.rectangle("fill", x, y, w, h, 10)
    love.graphics.setColor(rc[1], rc[2], rc[3], equipped and 1 or (hov and 0.85 or 0.45))
    love.graphics.setLineWidth(equipped and 3 or 2)
    love.graphics.rectangle("line", x, y, w, h, 10)

    -- preview (sits in the upper portion; smaller so tentacles stay clear)
    self:drawItemPreview(item, x + w / 2, y + h * 0.34, w / 110, isSkin)

    -- in the customize menu, DIM items you don't own yet so the ones you DO own
    -- clearly stand out (drawn inset so the rarity border + text stay crisp)
    if mode ~= "shop" and not owned then
        love.graphics.setColor(0.02, 0.03, 0.05, 0.58)
        love.graphics.rectangle("fill", x + 2, y + 2, w - 4, h - 4, 9)
    end

    -- solid label band so text never clashes with the squid's tentacles
    love.graphics.setColor(P.abyss[1], P.abyss[2], P.abyss[3], 0.82)
    love.graphics.rectangle("fill", x + 3, y + h - 48, w - 6, 45, 8)

    -- name
    love.graphics.setFont(fonts(self).small)
    love.graphics.setColor(P.text)
    love.graphics.printf(item.name, x + 4, y + h - 44, w - 8, "center")

    -- status line
    local showPrice = (mode == "shop" and not owned and item.kind == "shop")
    if showPrice then
        -- white cube token + price, centered as one unit
        local sf = fonts(self).small
        local numTxt = U.commafy(item.cost)
        local nw = sf:getWidth(numTxt)
        local totw = nw + 16
        local startx = x + w / 2 - totw / 2
        U.drawThing(startx + 6, y + h - 24 + sf:getHeight() / 2, 6)
        love.graphics.setFont(sf)
        love.graphics.setColor(self.save.things >= item.cost and P.white or P.coral)
        love.graphics.print(numTxt, startx + 16, y + h - 24)
    else
        local status, scol
        if equipped then status, scol = "EQUIPPED", P.teal
        elseif not owned then
            if item.kind == "shop" then status, scol = "IN SHOP", P.gold
            else status, scol = "LOCKED", P.textFaint end
        else status, scol = (mode == "shop" and "OWNED" or "EQUIP"), P.textDim end
        love.graphics.setColor(scol)
        love.graphics.printf(status, x + 4, y + h - 24, w - 8, "center")
    end

    -- lock hint for special (achievement) items — a small star-gem, drawn
    if item.kind == "special" then
        local gx, gy = x + w - 16, y + 16
        love.graphics.setColor(P.rarity.special)
        love.graphics.circle("fill", gx, gy, 6)
        love.graphics.setColor(1, 1, 1, 0.8)
        love.graphics.circle("fill", gx - 1.5, gy - 1.5, 2)
    end

    -- action
    self:reg(x, y, w, h, function()
        if mode == "customize" then
            if owned then
                if isSkin then self.save.skin = item.id
                else self.save.accessories[item.slot] = (equipped and nil or item.id) end
                Save.flush(); Audio.play("click", 0.7)
            else Audio.play("denied", 0.5) end
        elseif mode == "shop" then
            self:tryBuy(item, x + w / 2, y + h / 2)
        end
    end)
end

----------------------------------------------------------------------
-- SCREEN: customize
----------------------------------------------------------------------
function UI:screen_customize()
    self:title("CUSTOMIZE", 28)
    -- big live preview on the left
    love.graphics.setColor(0.04, 0.07, 0.12, 0.6)
    love.graphics.rectangle("fill", 40, 90, 560, 600, 14)
    love.graphics.setColor(P.panelEdge[1], P.panelEdge[2], P.panelEdge[3], 0.4)
    love.graphics.setLineWidth(2); love.graphics.rectangle("line", 40, 90, 560, 600, 14)
    self:drawPlayerPreview(320, 380, 3.1)
    love.graphics.setFont(fonts(self).medium)
    love.graphics.setColor(P.text)
    love.graphics.printf(Cosmetics.getSkin(self.save.skin).name .. " Squid", 40, 600, 560, "center")
    love.graphics.setFont(fonts(self).small)
    love.graphics.setColor(P.textFaint)
    love.graphics.printf("Mix skins, hats, eyewear, backs, auras & ink trails into your own squid.", 60, 636, 520, "center")

    -- item grid (right, scrollable) — drawn FIRST so the tab/back buttons below
    -- register last and win clicks even when a card has scrolled up under them.
    local items = {}
    if self.custSlot == "skin" then
        for _, sk in ipairs(Cosmetics.skins) do items[#items + 1] = sk end
    else
        -- "none" pseudo-item to unequip
        items[#items + 1] = { id = "__none", name = "None", slot = self.custSlot, rarity = "basic", none = true }
        for _, a in ipairs(Cosmetics.accessoriesBySlot(self.custSlot)) do items[#items + 1] = a end
    end
    self:drawItemGrid(items, 640, 150, 580, 540, self.custSlot == "skin", "customize")

    -- mask any sliver of a scrolled card peeking above the grid, then draw tabs
    love.graphics.setColor(P.abyss[1], P.abyss[2], P.abyss[3], 1)
    love.graphics.rectangle("fill", 636, 84, 600, 62)

    -- slot tabs (top-right) — registered after the grid so they take priority
    local tabs = { "skin", "hat", "eyes", "face", "back", "aura", "trail" }
    local tx, tw, tgap = 640, 78, 6
    for i, slot in ipairs(tabs) do
        local x = tx + (i - 1) * (tw + tgap)
        local active = self.custSlot == slot
        self:button(x, 96, tw, 40, slot:upper(), function() self.custSlot = slot; self.scroll.customize = 0 end,
            { color = active and P.cyan or P.textDim, font = fonts(self).small })
    end
    self:button(LW - 220, 28, 180, 44, "BACK", function() self:setScreen("menu") end, { color = P.textDim, font = fonts(self).normal })
end

-- generic scrollable grid of item cards within a clipped region
function UI:drawItemGrid(items, rx, ry, rw, rh, isSkin, mode)
    local cols = 3
    local cw, chh, gap = 170, 168, 14
    local rowH = chh + gap
    local rows = math.ceil(#items / cols)
    local content = rows * rowH
    self.maxScroll = math.max(0, content - rh)
    local sc = math.min(self.scroll[self.screen] or 0, self.maxScroll)
    self.scroll[self.screen] = sc

    love.graphics.setScissor(self.app.offX + rx * self.app.scale, self.app.offY + ry * self.app.scale,
        rw * self.app.scale, rh * self.app.scale)
    for i, item in ipairs(items) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local x = rx + col * (cw + gap) + (rw - (cols * cw + (cols - 1) * gap)) / 2
        local y = ry + row * rowH - sc
        if y + chh > ry - rowH and y < ry + rh + rowH then
            if item.none then
                self:drawNoneCard(item, x, y, cw, chh, mode)
            else
                self:drawItemCard(item, x, y, cw, chh, isSkin, mode)
            end
        end
    end
    love.graphics.setScissor()

    -- scrollbar
    if self.maxScroll > 0 then
        local bh = rh * (rh / content)
        local by = ry + (sc / self.maxScroll) * (rh - bh)
        love.graphics.setColor(P.panelEdge[1], P.panelEdge[2], P.panelEdge[3], 0.5)
        love.graphics.rectangle("fill", rx + rw + 6, by, 6, bh, 3)
    end
end

function UI:drawNoneCard(item, x, y, w, h, mode)
    local equipped = (self.save.accessories[item.slot] == nil)
    local hov = U.inRect(self.mx, self.my, x, y, w, h)
    love.graphics.setColor(P.panel[1], P.panel[2], P.panel[3], 0.95)
    love.graphics.rectangle("fill", x, y, w, h, 10)
    love.graphics.setColor(P.textDim[1], P.textDim[2], P.textDim[3], equipped and 1 or (hov and 0.8 or 0.4))
    love.graphics.setLineWidth(equipped and 3 or 2)
    love.graphics.rectangle("line", x, y, w, h, 10)
    love.graphics.setColor(P.textFaint)
    love.graphics.setFont(fonts(self).big)
    love.graphics.printf("—", x, y + h * 0.3, w, "center")
    love.graphics.setFont(fonts(self).small)
    love.graphics.setColor(P.text)
    love.graphics.printf("None", x, y + h - 44, w, "center")
    love.graphics.setColor(equipped and P.teal or P.textDim)
    love.graphics.printf(equipped and "EQUIPPED" or "REMOVE", x, y + h - 24, w, "center")
    self:reg(x, y, w, h, function()
        self.save.accessories[item.slot] = nil; Save.flush(); Audio.play("click", 0.6)
    end)
end

----------------------------------------------------------------------
-- SCREEN: shop (with the kraken)
----------------------------------------------------------------------
function UI:tryBuy(item, fromx, fromy)
    if Cosmetics.isOwned(self.save, item.id) then Audio.play("denied", 0.4); return end
    if item.kind ~= "shop" then Audio.play("denied", 0.4); return end
    if self.save.things < item.cost then Audio.play("denied", 0.5); return end
    self.save.things = self.save.things - item.cost
    self.save.owned[item.id] = true
    Save.flush()
    Audio.play("buy", 0.8)
    -- fling coins from the item into the kraken's void
    for i = 1, 8 do
        self.coins[#self.coins + 1] = {
            x = fromx + U.rand(-10, 10), y = fromy + U.rand(-10, 10),
            sx = fromx, sy = fromy, t = -i * 0.05,
        }
    end
    self.kraken.excite = 1.4
end

function UI:drawKraken(cx, cy)
    local k = self.kraken
    local thrash = 0.5 + k.excite
    -- void
    love.graphics.setColor(0, 0, 0.02, 0.85)
    love.graphics.circle("fill", cx, cy, 230)
    for i = 1, 5 do
        love.graphics.setColor(0.02, 0.04, 0.08, 0.5 - i * 0.08)
        love.graphics.circle("fill", cx, cy, 230 - i * 30)
    end
    -- tentacles reaching from the dark
    love.graphics.setColor(0.03, 0.06, 0.10, 0.95)
    for i = 1, 7 do
        local base = i / 7 * math.pi * 2
        local px, py = cx, cy
        local ang = base
        love.graphics.setLineWidth(20)
        for seg = 1, 7 do
            local wob = math.sin(self.t * (1.5 + thrash) + i + seg) * (8 + thrash * 10)
            ang = ang + 0.18 + wob * 0.01
            local nx = px + math.cos(base + seg * 0.1) * 34
            local ny = py + math.sin(base + seg * 0.1) * 34 + math.sin(self.t + seg) * 4
            love.graphics.setLineWidth(20 - seg * 2)
            love.graphics.line(px, py, nx + wob, ny)
            px, py = nx + wob, ny
        end
    end
    -- two glowing eyes that flare when excited
    local eg = k.eye
    local ec = U.mixColor({ 0.4, 0.7, 1.0 }, { 1.0, 0.4, 0.8 }, k.excite / 1.4)
    for s = -1, 1, 2 do
        U.glow(cx + s * 46, cy - 10, 40 * (0.6 + eg), ec, 0.4 + eg * 0.5)
        love.graphics.setColor(ec[1], ec[2], ec[3], 0.5 + eg * 0.5)
        love.graphics.ellipse("fill", cx + s * 46, cy - 10, 16, 10 + eg * 6)
        love.graphics.setColor(0, 0, 0, 0.8)
        love.graphics.ellipse("fill", cx + s * 46, cy - 10, 5, 8)
    end
    -- excited grin
    if k.excite > 0.2 then
        love.graphics.setColor(ec[1], ec[2], ec[3], k.excite)
        love.graphics.setLineWidth(4)
        love.graphics.arc("line", "open", cx, cy + 36, 60, 0.2, math.pi - 0.2, 16)
    end
    love.graphics.setFont(fonts(self).small)
    love.graphics.setColor(P.textFaint)
    love.graphics.printf("the trench-keeper trades in $Things...", cx - 180, cy + 210, 360, "center")
end

function UI:screen_shop()
    self:title("THE TRENCH SHOP", 28, P.gold)
    -- kraken void on the left
    self:drawKraken(290, 380)

    -- balance (top-left so it never collides with the BACK button): cube + count
    local fm = fonts(self).medium
    U.drawThing(52, 34 + fm:getHeight() / 2, 10)
    love.graphics.setFont(fm); love.graphics.setColor(P.white)
    love.graphics.print(U.commafy(self.save.things), 70, 34)

    -- purchasable items (skins + accessories of kind shop)
    local items = {}
    for _, sk in ipairs(Cosmetics.skins) do if sk.kind == "shop" then items[#items + 1] = sk end end
    for _, a in ipairs(Cosmetics.accessories) do if a.kind == "shop" then items[#items + 1] = a end end
    -- skins flagged so preview knows
    for _, it in ipairs(items) do it._isSkin = (Cosmetics.skinById[it.id] ~= nil) end
    self:drawShopGrid(items, 600, 110, 640, 540)

    -- flying $Things (white cubes) arcing into the kraken's void
    for _, c in ipairs(self.coins) do
        local tt = U.clamp(c.t, 0, 1)
        local x = U.lerp(c.sx, 290, tt)
        local y = U.lerp(c.sy, 370, tt) - math.sin(tt * math.pi) * 80
        U.drawThing(x, y, 8 - tt * 2, 1 - tt * 0.25)
    end

    self:button(LW - 220, 28, 180, 44, "BACK", function() self:setScreen("menu") end, { color = P.textDim, font = fonts(self).normal })
end

function UI:drawShopGrid(items, rx, ry, rw, rh)
    local cols = 3
    local cw, chh, gap = 190, 178, 14
    local rowH = chh + gap
    local rows = math.ceil(#items / cols)
    local content = rows * rowH
    self.maxScroll = math.max(0, content - rh)
    local sc = math.min(self.scroll[self.screen] or 0, self.maxScroll)
    self.scroll[self.screen] = sc
    love.graphics.setScissor(self.app.offX + rx * self.app.scale, self.app.offY + ry * self.app.scale,
        rw * self.app.scale, rh * self.app.scale)
    for i, item in ipairs(items) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local x = rx + col * (cw + gap)
        local y = ry + row * rowH - sc
        if y + chh > ry - rowH and y < ry + rh + rowH then
            self:drawItemCard(item, x, y, cw, chh, item._isSkin, "shop")
        end
    end
    love.graphics.setScissor()
    if self.maxScroll > 0 then
        local bh = rh * (rh / content)
        local by = ry + (sc / self.maxScroll) * (rh - bh)
        love.graphics.setColor(P.gold[1], P.gold[2], P.gold[3], 0.5)
        love.graphics.rectangle("fill", rx + rw + 6, by, 6, bh, 3)
    end
end

----------------------------------------------------------------------
-- SCREEN: achievements
----------------------------------------------------------------------
function UI:screen_achievements()
    self:title("ACHIEVEMENTS", 28, P.magenta)
    love.graphics.setFont(fonts(self).normal)
    love.graphics.setColor(P.textDim)
    love.graphics.printf(Achievements.countUnlocked(self.save) .. " / " .. #Achievements.list .. " unlocked",
        0, 74, LW, "center")

    local rx, ry, rw, rh = 120, 110, LW - 240, 540
    local cw, chh, gap = (rw - 16) / 2, 64, 12
    local rowH = chh + gap
    local rows = math.ceil(#Achievements.list / 2)
    local content = rows * rowH
    self.maxScroll = math.max(0, content - rh)
    local sc = math.min(self.scroll[self.screen] or 0, self.maxScroll)
    self.scroll[self.screen] = sc

    love.graphics.setScissor(self.app.offX + rx * self.app.scale, self.app.offY + ry * self.app.scale,
        rw * self.app.scale, rh * self.app.scale)
    for i, a in ipairs(Achievements.list) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local x = rx + col * (cw + 16)
        local y = ry + row * rowH - sc
        local unlocked = self.save.achievements[a.id]
        love.graphics.setColor(P.panel[1], P.panel[2], P.panel[3], 0.92)
        love.graphics.rectangle("fill", x, y, cw, chh, 8)
        love.graphics.setColor(unlocked and P.gold or P.textFaint)
        love.graphics.setLineWidth(2); love.graphics.rectangle("line", x, y, cw, chh, 8)
        -- status medallion (drawn, not a glyph, to avoid missing-font tofu)
        local mcx, mcy = x + 26, y + chh / 2
        if unlocked then
            U.glow(mcx, mcy, 16, P.gold, 0.5)
            love.graphics.setColor(P.gold); love.graphics.circle("fill", mcx, mcy, 10)
            love.graphics.setColor(P.abyss); love.graphics.circle("fill", mcx, mcy, 4)
        else
            love.graphics.setColor(P.textFaint); love.graphics.setLineWidth(2)
            love.graphics.circle("line", mcx, mcy, 10)
        end
        love.graphics.setFont(fonts(self).normal)
        love.graphics.setColor(unlocked and P.text or P.textDim)
        love.graphics.print(a.name, x + 50, y + 10)
        love.graphics.setFont(fonts(self).small)
        love.graphics.setColor(P.textFaint)
        love.graphics.printf(a.desc, x + 50, y + 34, cw - 60, "left")
    end
    love.graphics.setScissor()

    self:button(LW - 220, 28, 180, 44, "BACK", function() self:setScreen("menu") end, { color = P.textDim, font = fonts(self).normal })
end

----------------------------------------------------------------------
-- SCREEN: bestiary
----------------------------------------------------------------------
function UI:screen_bestiary()
    self:title("BESTIARY", 28, P.lime)
    love.graphics.setFont(fonts(self).normal)
    love.graphics.setColor(P.textDim)
    love.graphics.printf(Bestiary.countUnlocked(self.save) .. " / " .. #Bestiary.list ..
        " discovered  ·  defeat creatures (or survive leviathans) to unlock their lore", 0, 74, LW, "center")

    local rx, ry, rw, rh = 120, 110, LW - 240, 548
    local rowH = 92
    local content = #Bestiary.list * rowH
    self.maxScroll = math.max(0, content - rh)
    local sc = math.min(self.scroll[self.screen] or 0, self.maxScroll)
    self.scroll[self.screen] = sc

    love.graphics.setScissor(self.app.offX + rx * self.app.scale, self.app.offY + ry * self.app.scale,
        rw * self.app.scale, rh * self.app.scale)
    for i, e in ipairs(Bestiary.list) do
        local y = ry + (i - 1) * rowH - sc
        if y + rowH > ry - rowH and y < ry + rh + rowH then
            local unlocked = Bestiary.isUnlocked(self.save, e.id)
            local prog = Bestiary.progress(self.save, e.id)
            local et = Enemies.types[e.id]
            local col = (e.id == "leviathan") and { 0.7, 1.0, 0.3 } or (et and et.glow) or P.textDim
            love.graphics.setColor(P.panel[1], P.panel[2], P.panel[3], 0.92)
            love.graphics.rectangle("fill", rx, y, rw, rowH - 10, 8)
            love.graphics.setColor(unlocked and col or P.textFaint)
            love.graphics.setLineWidth(2); love.graphics.rectangle("line", rx, y, rw, rowH - 10, 8)
            -- emblem
            if unlocked then U.glow(rx + 44, y + 38, 26, col, 0.5) end
            love.graphics.setColor(unlocked and col or { 0.2, 0.22, 0.26 })
            love.graphics.circle("fill", rx + 44, y + 38, 20)
            love.graphics.setColor(0, 0, 0, 0.6); love.graphics.circle("fill", rx + 44, y + 38, 8)
            -- red "!" badge on entries you've unlocked but never opened the page for
            if unlocked and not (self.save.bestiarySeen and self.save.bestiarySeen[e.id]) then
                love.graphics.setColor(0.92, 0.16, 0.16, 1)
                love.graphics.circle("fill", rx + 62, y + 20, 11)
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.setFont(fonts(self).small)
                love.graphics.printf("!", rx + 51, y + 12, 22, "center")
            end
            -- text
            love.graphics.setFont(fonts(self).medium)
            love.graphics.setColor(unlocked and P.text or P.textDim)
            love.graphics.print(unlocked and e.name or "? ? ?", rx + 86, y + 12)
            love.graphics.setFont(fonts(self).small)
            if unlocked then
                love.graphics.setColor(P.textDim)
                love.graphics.printf(e.lore, rx + 86, y + 42, rw - 110, "left")
            else
                love.graphics.setColor(P.textFaint)
                local verb = (e.kind == "event") and "Survive" or "Defeat"
                love.graphics.printf(("%s %d to unlock   (%d / %d)"):format(verb, e.need, math.min(prog, e.need), e.need),
                    rx + 86, y + 44, rw - 110, "left")
            end
            -- tag + "open book" hint
            love.graphics.setFont(fonts(self).small)
            love.graphics.setColor(e.kind == "boss" and P.gold or (e.kind == "event" and P.lime or P.textFaint))
            love.graphics.printf(e.kind:upper(), rx, y + 12, rw - 16, "right")
            if unlocked then
                local hov = U.inRect(self.mx, self.my, rx, y, rw, rowH - 10)
                love.graphics.setColor(P.gold[1], P.gold[2], P.gold[3], hov and 0.9 or 0.5)
                love.graphics.printf("OPEN ►", rx, y + rowH - 34, rw - 16, "right")
                self:reg(rx, y, rw, rowH - 10, function() self:openBook(e.id) end)
            end
        end
    end
    love.graphics.setScissor()

    self:button(LW - 220, 28, 180, 44, "BACK", function() self:setScreen("menu") end, { color = P.textDim, font = fonts(self).normal })
end

----------------------------------------------------------------------
-- SCREEN: soundtrack
----------------------------------------------------------------------
function UI:screen_music()
    self:title("SOUNDTRACK", 28, P.purple)
    love.graphics.setFont(fonts(self).normal)
    love.graphics.setColor(P.textDim)
    love.graphics.printf("Each theme is synthesized live. Unlock more by descending.", 0, 74, LW, "center")

    local list = Audio.unlockedThemes(self.save)
    local x, w, h, gap = LW / 2 - 360, 720, 56, 12
    local y0, listBot = 120, 628          -- clip above the HADAL TRACKS button
    local sc = math.min(self.scroll[self.screen] or 0, math.max(0, #list * (h + gap) - (listBot - y0)))
    self.scroll[self.screen] = sc
    self.maxScroll = math.max(0, #list * (h + gap) - (listBot - y0))
    love.graphics.setScissor(self.app.offX + (x - 12) * self.app.scale, self.app.offY + (y0 - 6) * self.app.scale,
        (w + 24) * self.app.scale, (listBot - y0 + 10) * self.app.scale)
    for i, entry in ipairs(list) do
        local th = entry.theme
        local y = y0 + (i - 1) * (h + gap) - sc
        if y + h > y0 - 4 and y < listBot then
        local equipped = (self.save.musicTheme == th.id)
        local hov = U.inRect(self.mx, self.my, x, y, w, h)
        love.graphics.setColor(P.panel[1], P.panel[2], P.panel[3], 0.94)
        love.graphics.rectangle("fill", x, y, w, h, 8)
        love.graphics.setColor(equipped and P.purple or (entry.unlocked and P.textDim or P.textFaint),
            nil)
        love.graphics.setLineWidth(equipped and 3 or 2)
        love.graphics.rectangle("line", x, y, w, h, 8)
        love.graphics.setFont(fonts(self).medium)
        love.graphics.setColor(entry.unlocked and P.text or P.textFaint)
        love.graphics.print(th.name, x + 16, y + 8)
        love.graphics.setFont(fonts(self).small)
        love.graphics.setColor(P.purple[1], P.purple[2], P.purple[3], 0.8)
        love.graphics.print(th.genre, x + 16, y + 33)
        love.graphics.setColor(P.textFaint)
        love.graphics.printf(entry.unlocked and th.desc or ("LOCKED — " .. th.hint), x + 220, y + 18, w - 360, "left")
        love.graphics.setColor(equipped and P.purple or (entry.unlocked and P.teal or P.textFaint))
        love.graphics.printf(equipped and "PLAYING" or (entry.unlocked and "PLAY" or "LOCKED"), x + w - 110, y + h / 2 - 10, 96, "right")
        if entry.unlocked then
            self:reg(x, y, w, h, function()
                self.save.musicTheme = th.id; Save.flush(); Audio.playMusic(th.id); Audio.play("click", 0.6)
            end)
        end
        end   -- visible-row guard
    end
    love.graphics.setScissor()
    if self.maxScroll > 0 then
        local vis = listBot - y0
        local bh = vis * (vis / (#list * (h + gap)))
        local byy = y0 + (sc / self.maxScroll) * (vis - bh)
        love.graphics.setColor(P.purple[1], P.purple[2], P.purple[3], 0.5)
        love.graphics.rectangle("fill", x + w + 6, byy, 5, bh, 2)
    end

    -- 2nd menu (bottom-right): the eerier HADAL-DEPTHS soundtrack. Locked until
    -- you've beaten a run.
    local hadalOk = (self.save.stats.totalWins or 0) >= 1
    local bx, by, bw, bh = LW - 372, 648, 332, 54
    love.graphics.setColor(P.panel[1], P.panel[2], P.panel[3], 0.95)
    love.graphics.rectangle("fill", bx, by, bw, bh, 8)
    love.graphics.setColor(hadalOk and P.purple or P.textFaint); love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", bx, by, bw, bh, 8)
    love.graphics.setFont(fonts(self).normal)
    love.graphics.setColor(hadalOk and P.text or P.textFaint)
    if hadalOk then
        love.graphics.printf("HADAL TRACKS  ►", bx, by + bh / 2 - 10, bw, "center")
        self:reg(bx, by, bw, bh, function() Audio.play("click", 0.6); self:setScreen("hadalmusic") end)
    else
        -- padlock glyph + hint
        local lx, ly = bx + 40, by + bh / 2
        love.graphics.setColor(P.textFaint)
        love.graphics.rectangle("fill", lx - 7, ly - 1, 14, 11, 2)
        love.graphics.setLineWidth(2); love.graphics.arc("line", "open", lx, ly - 1, 6, math.pi, math.pi * 2)
        love.graphics.printf("HADAL TRACKS", bx + 30, by + 8, bw - 30, "center")
        love.graphics.setFont(fonts(self).small)
        love.graphics.setColor(P.textFaint)
        love.graphics.printf("LOCKED — beat 1 run first", bx, by + bh - 20, bw, "center")
    end

    self:button(LW - 220, 28, 180, 44, "BACK", function() self:setScreen("menu") end, { color = P.textDim, font = fonts(self).normal })
end

----------------------------------------------------------------------
-- SCREEN: HADAL soundtrack (2nd, eerier picker — unlocked by beating a run)
----------------------------------------------------------------------
function UI:screen_hadalmusic()
    self:title("HADAL SOUNDTRACK", 28, P.purple)
    love.graphics.setFont(fonts(self).normal)
    love.graphics.setColor(P.textDim)
    love.graphics.printf("Eerier music for the deep below the Maw. Unlock more by going deeper.", 0, 74, LW, "center")

    local list = Audio.hadalThemes(self.save)
    local x, w, h, gap = LW / 2 - 360, 720, 56, 12
    local y0, listBot = 120, 686
    local sc = math.min(self.scroll[self.screen] or 0, math.max(0, #list * (h + gap) - (listBot - y0)))
    self.scroll[self.screen] = sc
    self.maxScroll = math.max(0, #list * (h + gap) - (listBot - y0))
    love.graphics.setScissor(self.app.offX + (x - 12) * self.app.scale, self.app.offY + (y0 - 6) * self.app.scale,
        (w + 24) * self.app.scale, (listBot - y0 + 10) * self.app.scale)
    for i, entry in ipairs(list) do
        local th = entry.theme
        local y = y0 + (i - 1) * (h + gap) - sc
        if y + h > y0 - 4 and y < listBot then
        local equipped = (self.save.hadalTheme == th.id)
        love.graphics.setColor(P.panel[1], P.panel[2], P.panel[3], 0.94)
        love.graphics.rectangle("fill", x, y, w, h, 8)
        love.graphics.setColor(equipped and P.purple or (entry.unlocked and P.textDim or P.textFaint))
        love.graphics.setLineWidth(equipped and 3 or 2)
        love.graphics.rectangle("line", x, y, w, h, 8)
        love.graphics.setFont(fonts(self).medium)
        love.graphics.setColor(entry.unlocked and P.text or P.textFaint)
        love.graphics.print(th.name, x + 16, y + 8)
        if th.hadalDefault then
            love.graphics.setFont(fonts(self).small); love.graphics.setColor(P.teal)
            love.graphics.print("DEFAULT", x + 16 + fonts(self).medium:getWidth(th.name) + 12, y + 16)
        end
        love.graphics.setFont(fonts(self).small)
        love.graphics.setColor(P.purple[1], P.purple[2], P.purple[3], 0.8)
        love.graphics.print(th.genre, x + 16, y + 33)
        love.graphics.setColor(P.textFaint)
        love.graphics.printf(entry.unlocked and th.desc or ("LOCKED — " .. th.hint), x + 220, y + 18, w - 360, "left")
        love.graphics.setColor(equipped and P.purple or (entry.unlocked and P.teal or P.textFaint))
        love.graphics.printf(equipped and "EQUIPPED" or (entry.unlocked and "EQUIP" or "LOCKED"), x + w - 110, y + h / 2 - 10, 96, "right")
        if entry.unlocked then
            self:reg(x, y, w, h, function()
                self.save.hadalTheme = th.id; Save.flush(); Audio.playMusic(th.id); Audio.play("click", 0.6)
            end)
        end
        end   -- visible-row guard
    end
    love.graphics.setScissor()
    if self.maxScroll > 0 then
        local vis = listBot - y0
        local bh = vis * (vis / (#list * (h + gap)))
        local byy = y0 + (sc / self.maxScroll) * (vis - bh)
        love.graphics.setColor(P.purple[1], P.purple[2], P.purple[3], 0.5)
        love.graphics.rectangle("fill", x + w + 6, byy, 5, bh, 2)
    end

    self:button(LW - 220, 28, 180, 44, "BACK", function()
        Audio.playMusic(self.save.musicTheme)   -- stop previewing the eerie track
        self:setScreen("music")
    end, { color = P.textDim, font = fonts(self).normal })
end

----------------------------------------------------------------------
-- SCREEN: settings (fullscreen, volumes, shake, reset data)
----------------------------------------------------------------------
function UI:applySlider(key, mx)
    local x0, w = self.sliderX, self.sliderW
    local v = U.clamp((mx - x0) / w, 0, 1)
    if key == "music" then
        self.save.settings.musicVolume = v; Audio.setMusicVolume(v)
    elseif key == "sfx" then
        self.save.settings.sfxVolume = v; Audio.setSfxVolume(v)
    end
end

function UI:slider(key, label, x, y, w, value)
    self.sliderX, self.sliderW = x, w
    love.graphics.setFont(fonts(self).normal)
    love.graphics.setColor(P.text)
    love.graphics.print(label, x, y - 28)
    love.graphics.setColor(P.deep)
    love.graphics.rectangle("fill", x, y, w, 10, 5)
    love.graphics.setColor(P.cyan)
    love.graphics.rectangle("fill", x, y, w * value, 10, 5)
    local hx = x + w * value
    love.graphics.setColor(P.white)
    love.graphics.circle("fill", hx, y + 5, 11)
    love.graphics.setColor(P.textDim)
    love.graphics.printf(math.floor(value * 100) .. "%", x + w + 14, y - 6, 60, "left")
    self:reg(x - 6, y - 12, w + 22, 34, function() self.dragSlider = key; self:applySlider(key, self.mx) end)
end

function UI:toggle(label, x, y, w, value, action)
    love.graphics.setFont(fonts(self).normal)
    love.graphics.setColor(P.text)
    love.graphics.print(label, x, y + 8)
    local bx = x + w - 92
    self:button(bx, y, 92, 38, value and "ON" or "OFF", action,
        { color = value and P.teal or P.textDim, font = fonts(self).normal })
end

function UI:screen_settings()
    self:title("SETTINGS", 28, P.aqua)
    local panelX, panelW = LW / 2 - 320, 640
    love.graphics.setColor(0.05, 0.08, 0.13, 0.7)
    love.graphics.rectangle("fill", panelX, 110, panelW, 480, 14)
    love.graphics.setColor(P.panelEdge[1], P.panelEdge[2], P.panelEdge[3], 0.4)
    love.graphics.setLineWidth(2); love.graphics.rectangle("line", panelX, 110, panelW, 480, 14)

    local ix = panelX + 40
    local iw = panelW - 80

    self:toggle("Fullscreen  (F11)", ix, 150, iw, self.save.settings.fullscreen, function()
        self.save.settings.fullscreen = not self.save.settings.fullscreen
        love.window.setFullscreen(self.save.settings.fullscreen, "desktop")
        Save.flush()
    end)
    love.graphics.setFont(fonts(self).small)
    love.graphics.setColor(P.textFaint)
    love.graphics.print("Black bars preserve the picture — never stretched.", ix, 194)

    self:slider("music", "Music Volume", ix, 256, iw - 80, self.save.settings.musicVolume)
    self:slider("sfx", "Sound Effects", ix, 326, iw - 80, self.save.settings.sfxVolume)

    self:toggle("Screen Shake", ix, 372, iw, self.save.settings.screenShake, function()
        self.save.settings.screenShake = not self.save.settings.screenShake; Save.flush()
    end)

    -- danger zone
    love.graphics.setColor(P.red[1], P.red[2], P.red[3], 0.5)
    love.graphics.setLineWidth(1)
    love.graphics.line(ix, 440, ix + iw, 440)
    love.graphics.setFont(fonts(self).small)
    love.graphics.setColor(P.textFaint)
    love.graphics.print("DANGER ZONE — this wipes ALL progress, $Things, skins & achievements.", ix, 452)
    self:button(ix, 480, 280, 50, "RESET DATA", function()
        self.resetStage = "type"; self.resetText = ""
        love.keyboard.setKeyRepeat(true)
    end, { color = P.red })

    -- save info
    love.graphics.setFont(fonts(self).small)
    love.graphics.setColor(P.textFaint)
    local s = self.save.stats
    love.graphics.printf(("Saved · %d runs · %s playtime · $%s earned all-time")
        :format(s.totalRuns, self:fmtTime(s.playTime), U.commafy(s.totalThingsEarned)),
        panelX, 548, panelW, "center")

    self:button(LW - 220, 28, 180, 44, "BACK", function() self:setScreen("menu") end, { color = P.textDim, font = fonts(self).normal })
end

function UI:fmtTime(sec)
    sec = math.floor(sec or 0)
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    if h > 0 then return h .. "h " .. m .. "m" end
    return m .. "m"
end

function UI:closeReset()
    self.resetStage = nil
    self.resetText = ""
    love.keyboard.setKeyRepeat(false)
end

function UI:doReset()
    local fresh = Save.reset()
    self.app.save = fresh
    self.save = fresh
    Audio.setMusicVolume(fresh.settings.musicVolume)
    Audio.setSfxVolume(fresh.settings.sfxVolume)
    Audio.playMusic(fresh.musicTheme)
    self:closeReset()
    self.app.toasts[#self.app.toasts + 1] = { a = { name = "Data reset — fresh trench" }, t = 4 }
end

function UI:drawResetModal()
    -- backdrop swallows clicks to underlying screen
    love.graphics.setColor(0, 0, 0.02, 0.78)
    love.graphics.rectangle("fill", 0, 0, LW, LH)
    -- mark where modal hot-rects begin so only these are clickable
    self.modalStart = #self.hot + 1
    self:reg(0, 0, LW, LH, function() end) -- absorb outside clicks

    local mw, mh = 560, 300
    local mx, my = LW / 2 - mw / 2, LH / 2 - mh / 2
    love.graphics.setColor(P.panel[1], P.panel[2], P.panel[3], 0.99)
    love.graphics.rectangle("fill", mx, my, mw, mh, 14)
    love.graphics.setColor(P.red[1], P.red[2], P.red[3], 0.9)
    love.graphics.setLineWidth(3); love.graphics.rectangle("line", mx, my, mw, mh, 14)

    -- X close (works at any stage, no typing needed)
    local cx, cy = mx + mw - 42, my + 12
    local xhov = U.inRect(self.mx, self.my, cx, cy, 30, 30)
    love.graphics.setColor(xhov and P.red or P.textDim)
    love.graphics.setLineWidth(3)
    love.graphics.line(cx + 8, cy + 8, cx + 22, cy + 22)
    love.graphics.line(cx + 22, cy + 8, cx + 8, cy + 22)
    self:reg(cx, cy, 30, 30, function() self:closeReset() end)

    love.graphics.setFont(fonts(self).big)
    love.graphics.setColor(P.red)
    love.graphics.printf("RESET DATA", mx, my + 26, mw, "center")

    if self.resetStage == "type" then
        love.graphics.setFont(fonts(self).normal)
        love.graphics.setColor(P.text)
        love.graphics.printf('Type the word  "Reset"  to continue.', mx, my + 90, mw, "center")
        -- input box
        local bx, bw = mx + mw / 2 - 130, 260
        love.graphics.setColor(P.deep)
        love.graphics.rectangle("fill", bx, my + 130, bw, 48, 8)
        local match = (self.resetText == "Reset")
        love.graphics.setColor(match and P.teal or P.panelEdge)
        love.graphics.setLineWidth(2); love.graphics.rectangle("line", bx, my + 130, bw, 48, 8)
        love.graphics.setColor(P.text)
        love.graphics.setFont(fonts(self).medium)
        local caret = (math.floor(self.t * 2) % 2 == 0) and "|" or ""
        love.graphics.printf(self.resetText .. caret, bx, my + 142, bw, "center")
        -- continue (enabled only when typed exactly) + cancel
        self:button(mx + 60, my + 210, 200, 52, "CONTINUE", function()
            if match then self.resetStage = "confirm" end
        end, { color = match and P.red or P.textFaint, disabled = not match })
        self:button(mx + mw - 260, my + 210, 200, 52, "CANCEL", function() self:closeReset() end,
            { color = P.textDim })
    else -- confirm
        love.graphics.setFont(fonts(self).medium)
        love.graphics.setColor(P.text)
        love.graphics.printf("Are you sure?", mx, my + 96, mw, "center")
        love.graphics.setFont(fonts(self).normal)
        love.graphics.setColor(P.textDim)
        love.graphics.printf("This permanently deletes everything. It cannot be undone.", mx + 30, my + 140, mw - 60, "center")
        self:button(mx + 60, my + 200, 200, 56, "YES, WIPE IT", function() self:doReset() end, { color = P.red })
        self:button(mx + mw - 260, my + 200, 200, 56, "NO", function() self:closeReset() end, { color = P.teal })
    end
end

----------------------------------------------------------------------
-- SCREEN: Super Secret Settings (Konami-unlocked, visual-only)
----------------------------------------------------------------------
function UI:screen_secret()
    -- wobbly rainbow title for maximum silliness
    love.graphics.setFont(fonts(self).big)
    local txt = "SUPER SECRET SETTINGS"
    local fw = fonts(self).big:getWidth(txt)
    local x0 = LW / 2 - fw / 2
    for i = 1, #txt do
        local ch = txt:sub(i, i)
        local cw = fonts(self).big:getWidth(txt:sub(1, i - 1))
        local hue = (self.t * 2 + i * 0.3)
        love.graphics.setColor(0.5 + 0.5 * math.sin(hue), 0.5 + 0.5 * math.sin(hue + 2), 0.5 + 0.5 * math.sin(hue + 4))
        love.graphics.print(ch, x0 + cw, 34 + math.sin(self.t * 4 + i * 0.5) * 5)
    end
    love.graphics.setFont(fonts(self).normal)
    love.graphics.setColor(P.textDim)
    love.graphics.printf("Purely cosmetic filters — they change how you SEE the game, never how it plays.",
        0, 86, LW, "center")

    local sec = self.save.settings.secret
    local cols = 2
    local cw, chh, gap = 540, 64, 14
    local rowH = chh + gap
    local x0c = LW / 2 - (cols * cw + (cols - 1) * 30) / 2
    for i, e in ipairs(SecretFX) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local x = x0c + col * (cw + 30)
        local y = 120 + row * rowH
        local on = sec[e.id]
        local hov = U.inRect(self.mx, self.my, x, y, cw, chh)
        love.graphics.setColor(P.panel[1], P.panel[2], P.panel[3], 0.94)
        love.graphics.rectangle("fill", x, y, cw, chh, 8)
        love.graphics.setColor(on and P.magenta or (hov and P.cyan or P.textFaint))
        love.graphics.setLineWidth(on and 3 or 2)
        love.graphics.rectangle("line", x, y, cw, chh, 8)
        love.graphics.setFont(fonts(self).normal)
        love.graphics.setColor(P.text)
        love.graphics.print(e.name, x + 16, y + 10)
        love.graphics.setFont(fonts(self).small)
        love.graphics.setColor(P.textDim)
        love.graphics.print(e.desc, x + 16, y + 36)
        love.graphics.setColor(on and P.magenta or P.textFaint)
        love.graphics.setFont(fonts(self).medium)
        love.graphics.printf(on and "ON" or "OFF", x + cw - 80, y + chh / 2 - 12, 64, "right")
        self:reg(x, y, cw, chh, function()
            sec[e.id] = not sec[e.id]; Save.flush()
            Audio.play(sec[e.id] and "buy" or "click", 0.6)
        end)
    end

    self:button(LW / 2 - 330, 654, 300, 50, "TURN ALL OFF", function()
        for _, e in ipairs(SecretFX) do sec[e.id] = nil end
        Save.flush(); Audio.play("denied", 0.5)
    end, { color = P.coral })
    self:button(LW / 2 + 30, 654, 300, 50, "BACK", function() self:setScreen("menu") end, { color = P.textDim })
end

----------------------------------------------------------------------
-- SCREEN: run end summary
----------------------------------------------------------------------
function UI:screen_runend()
    local r = self.app.lastResult
    if not r then self:setScreen("menu"); return end
    local won = r.won
    self:title(won and "THE LIGHT RETURNS" or "SWALLOWED BY THE DARK", 50, won and P.gold or P.coral)
    if won then self:drawPlayerPreview(LW / 2, 210, 1.8) end
    if r.custom then
        love.graphics.setFont(fonts(self).normal); love.graphics.setColor(P.teal)
        love.graphics.printf("CUSTOM CAMPAIGN · " .. (r.campaignName or ""), 0, won and 286 or 150, LW, "center")
    end

    local panelX, panelW = LW / 2 - 300, 600
    local y = won and 320 or 180
    love.graphics.setColor(0.05, 0.08, 0.13, 0.8)
    love.graphics.rectangle("fill", panelX, y, panelW, 280, 14)
    love.graphics.setColor(P.panelEdge[1], P.panelEdge[2], P.panelEdge[3], 0.4)
    love.graphics.setLineWidth(2); love.graphics.rectangle("line", panelX, y, panelW, 280, 14)

    love.graphics.setFont(fonts(self).normal)
    local function row(label, val, color, ry)
        love.graphics.setColor(P.textDim)
        love.graphics.print(label, panelX + 36, ry)
        love.graphics.setColor(color or P.text)
        love.graphics.printf(val, panelX + 36, ry, panelW - 72, "right")
    end
    row("Reached", "Depth " .. r.depth .. " · " .. (r.depthName or ""), P.cyan, y + 24)
    row("Creatures defeated", U.commafy(r.kills), P.text, y + 52)
    row("Score", U.commafy(r.score), P.text, y + 80)
    row("Best combo", r.bestCombo .. "x", P.magenta, y + 108)
    row("$Things collected", U.commafy(r.collected), P.gold, y + 136)
    row("Modifier multiplier", string.format("x %.2f", r.pointMult), r.pointMult >= 1 and P.lime or P.coral, y + 164)
    if r.flawless then row("FLAWLESS", "no hits taken!", P.teal, y + 192) end

    -- big payout (white cube + count, centered as one unit)
    love.graphics.setColor(P.gold[1], P.gold[2], P.gold[3], 0.4)
    love.graphics.line(panelX + 36, y + 224, panelX + panelW - 36, y + 224)
    local bigf = fonts(self).big
    if r.custom then
        -- sandbox: nothing is banked, so don't dangle a fake payout
        love.graphics.setFont(bigf); love.graphics.setColor(P.teal)
        love.graphics.printf("SANDBOX RUN", panelX, y + 232, panelW, "center")
        love.graphics.setFont(fonts(self).small); love.graphics.setColor(P.textDim)
        love.graphics.printf("custom campaigns don't bank $Things, wins, or stats",
            panelX, y + 232 + bigf:getHeight() + 2, panelW, "center")
    elseif r.noReward then
        -- earned nothing — explain why (bailed/died in the early trench)
        love.graphics.setFont(bigf); love.graphics.setColor(P.coral)
        love.graphics.printf("NO REWARDS", panelX, y + 232, panelW, "center")
        love.graphics.setFont(fonts(self).small); love.graphics.setColor(P.textDim)
        love.graphics.printf("you have to clear the first 4 depths before a run pays out",
            panelX, y + 232 + bigf:getHeight() + 2, panelW, "center")
    else
        local payTxt = "+ " .. U.commafy(r.payout) .. " EARNED"
        local pw = bigf:getWidth(payTxt)
        local cx = panelX + panelW / 2
        local total = pw + 34
        local sx = cx - total / 2
        U.drawThing(sx + 12, y + 234 + bigf:getHeight() / 2, 12)
        love.graphics.setFont(bigf); love.graphics.setColor(P.gold)
        love.graphics.print(payTxt, sx + 34, y + 234)
    end

    local nf = fonts(self).normal
    local label = "Balance:  "
    local num = U.commafy(self.save.things)
    local lw = nf:getWidth(label)
    local nw = nf:getWidth(num)
    local tot = lw + 16 + nw                       -- label + cube + number
    local bsx = LW / 2 - tot / 2
    love.graphics.setFont(nf)
    love.graphics.setColor(P.textDim); love.graphics.print(label, bsx, y + 292)
    U.drawThing(bsx + lw + 7, y + 292 + nf:getHeight() / 2, 7)
    love.graphics.setColor(P.white); love.graphics.print(num, bsx + lw + 17, y + 292)

    if r.custom then
        self:button(LW / 2 - 330, 648, 300, 54, "RESTART CAMPAIGN", function()
            if self.app.lastCustomCampaign then self.app.startCustomRun(self.app.lastCustomCampaign, 1, false)
            else self:setScreen("campaigns") end
        end, { color = P.teal })
        self:button(LW / 2 + 30, 648, 300, 54, "EXIT", function() self:setScreen("campaigns") end, { color = P.textDim })
    else
        self:button(LW / 2 - 330, 648, 300, 54, "DESCEND AGAIN", function() self:setScreen("modifiers") end, { color = P.teal })
        self:button(LW / 2 + 30, 648, 300, 54, "MENU", function() self:setScreen("menu") end, { color = P.textDim })
    end
end

----------------------------------------------------------------------
-- CUSTOM CAMPAIGNS — list + editor
----------------------------------------------------------------------
-- commit the value currently being typed into a stepper (clamps unless noLimits)
function UI:commitNumEdit()
    local ne = self.numEdit
    if not ne then return end
    local n = tonumber(ne.buf)
    if n then
        if not self.noLimits then n = math.max(ne.min, math.min(ne.max, n)) end
        ne.set(n)
    end
    self.numEdit = nil
end

-- small "[-] value [+]" stepper. dec/inc are called on the arrows. Pass `num`
-- = {val, min, max, set} to make the value itself click-to-TYPE (clamped to
-- [min,max] on commit unless Remove Limits is on).
function UI:stepper(x, y, w, label, valStr, dec, inc, num)
    love.graphics.setFont(fonts(self).small)
    love.graphics.setColor(P.textDim); love.graphics.print(label, x, y + 4)
    local bw = 22
    local minus, plus = x + w - bw * 2 - 64, x + w - bw
    for _, b in ipairs({ { minus, "-", dec }, { plus, "+", inc } }) do
        local hov = U.inRect(self.mx, self.my, b[1], y, bw, 22)
        love.graphics.setColor(P.panel[1], P.panel[2], P.panel[3], 0.95); love.graphics.rectangle("fill", b[1], y, bw, 22, 4)
        love.graphics.setColor(hov and P.teal or P.textDim); love.graphics.setLineWidth(1.5); love.graphics.rectangle("line", b[1], y, bw, 22, 4)
        love.graphics.printf(b[2], b[1], y + 3, bw, "center")
        self:reg(b[1], y, bw, 22, function() Audio.play("click", 0.4); b[3]() end)
    end
    local editing = num and self.numEdit and self.numEdit.key == label
    if editing then
        love.graphics.setColor(P.panel[1], P.panel[2], P.panel[3], 0.95); love.graphics.rectangle("fill", minus + bw, y, 64, 22, 4)
        love.graphics.setColor(P.teal); love.graphics.setLineWidth(1); love.graphics.rectangle("line", minus + bw, y, 64, 22, 4)
        love.graphics.setColor(P.text); love.graphics.printf(self.numEdit.buf .. "_", minus + bw, y + 4, 64, "center")
    else
        love.graphics.setColor(P.text); love.graphics.printf(valStr, minus + bw, y + 4, 64, "center")
        if num then
            self:reg(minus + bw, y, 64, 22, function()
                self:commitNumEdit()                  -- close any other typed field first
                self.numEdit = { key = label, buf = tostring(num.val), min = num.min, max = num.max, set = num.set }
                Audio.play("click", 0.4)
            end)
        end
    end
end

function UI:campaignPlayDepth()
    -- map the selected timeline node to a depth index (for "Play Here")
    local d = 0
    for i = 1, (self.editSel or 0) do
        if self.editCamp.nodes[i] and self.editCamp.nodes[i].kind == "depth" then d = d + 1 end
    end
    return math.max(1, d)
end

function UI:screen_campaigns()
    self:title("CUSTOM CAMPAIGNS", 28, P.teal)
    local list = Campaign.list()
    if #list == 0 then                       -- seed an example so it's never empty
        local ex = Campaign.example(); Campaign.save(ex); list = Campaign.list()
    end
    love.graphics.setFont(fonts(self).normal); love.graphics.setColor(P.textDim)
    love.graphics.printf("Build your own runs. Files live in the campaigns folder — copy them to share.", 0, 74, LW, "center")

    local x, w, rh = LW / 2 - 380, 760, 64
    local y0, listBot = 120, 586
    local sc = math.min(self.scroll[self.screen] or 0, math.max(0, #list * (rh + 10) - (listBot - y0)))
    self.scroll[self.screen] = sc
    self.maxScroll = math.max(0, #list * (rh + 10) - (listBot - y0))
    love.graphics.setScissor(self.app.offX + (x - 12) * self.app.scale, self.app.offY + (y0 - 6) * self.app.scale,
        (w + 24) * self.app.scale, (listBot - y0 + 8) * self.app.scale)
    for i, c in ipairs(list) do
        local y = y0 + (i - 1) * (rh + 10) - sc
        if y + rh > y0 - 4 and y < listBot then     -- only draw/click visible rows
            love.graphics.setColor(P.panel[1], P.panel[2], P.panel[3], 0.95); love.graphics.rectangle("fill", x, y, w, rh, 8)
            love.graphics.setColor(P.teal[1], P.teal[2], P.teal[3], 0.5); love.graphics.setLineWidth(2); love.graphics.rectangle("line", x, y, w, rh, 8)
            love.graphics.setFont(fonts(self).medium); love.graphics.setColor(P.text)
            love.graphics.print(c.name, x + 18, y + 10)
            love.graphics.setFont(fonts(self).small); love.graphics.setColor(P.textFaint)
            love.graphics.print(c.depths .. " depth" .. (c.depths == 1 and "" or "s"), x + 18, y + 38)
            local bx = x + w - 330
            self:button(bx, y + 12, 96, 40, "PLAY", function() self.app.startCustomRun(c.camp, 1) end, { color = P.teal, font = fonts(self).small })
            self:button(bx + 104, y + 12, 96, 40, "EDIT", function()
                self.editCamp = c.camp; self.editCamp._file = c.file; self.editSel = nil
                self.scroll.editor = 0; self:setScreen("editor")
            end, { color = P.cyan, font = fonts(self).small })
            self:button(bx + 208, y + 12, 96, 40, "DELETE", function() Campaign.delete(c.file); Audio.play("denied", 0.5) end, { color = P.coral, font = fonts(self).small })
        end
    end
    love.graphics.setScissor()
    if self.maxScroll > 0 then                      -- scrollbar
        local vis = listBot - y0
        local bh = vis * (vis / (#list * (rh + 10)))
        local byy = y0 + (sc / self.maxScroll) * (vis - bh)
        love.graphics.setColor(P.teal[1], P.teal[2], P.teal[3], 0.5)
        love.graphics.rectangle("fill", x + w + 6, byy, 5, bh, 2)
    end

    self:button(LW / 2 - 392, 600, 188, 50, "+ NEW", function()
        local c = Campaign.newCampaign("New Campaign")
        self.editCamp = c; self.editSel = 1; self.scroll.editor = 0; self:setScreen("editor")
    end, { color = P.teal })
    self:button(LW / 2 - 196, 600, 168, 50, "ONLINE", function()
        self.onlineOpen = true; self.onlineMsg = nil
        self.onlineURL = self.onlineURL or ""
    end, { color = P.lime })
    self:button(LW / 2 - 20, 600, 188, 50, "OPEN FOLDER", function()
        love.system.openURL("file://" .. Campaign.dirPath())
    end, { color = P.aqua })
    self:button(LW / 2 + 204, 600, 188, 50, "BACK", function() self:setScreen("menu") end, { color = P.textDim })

    if self.onlineOpen then self:drawOnlineModal() end
end

-- download a campaign from a URL (http://host:port/file.lua)
function UI:drawOnlineModal()
    love.graphics.setColor(0, 0, 0.02, 0.82); love.graphics.rectangle("fill", 0, 0, LW, LH)
    self:reg(0, 0, LW, LH, function() self.editField = nil; self.onlineOpen = false end)
    local mw, mh = 720, 300
    local mx, my = LW / 2 - mw / 2, LH / 2 - mh / 2
    self:reg(mx, my, mw, mh, function() end)   -- swallow clicks
    love.graphics.setColor(0.08, 0.1, 0.14, 0.99); love.graphics.rectangle("fill", mx, my, mw, mh, 10)
    love.graphics.setColor(P.lime); love.graphics.setLineWidth(2); love.graphics.rectangle("line", mx, my, mw, mh, 10)
    love.graphics.setFont(fonts(self).medium); love.graphics.setColor(P.text)
    love.graphics.printf("DOWNLOAD CAMPAIGN", mx, my + 16, mw, "center")
    love.graphics.setFont(fonts(self).small); love.graphics.setColor(P.textFaint)
    love.graphics.printf("Paste a campaign URL (http only), e.g.  127.0.0.1:5050/cool_campaign.lua", mx + 30, my + 56, mw - 60, "center")
    -- URL field
    local fx, fy, fw = mx + 30, my + 92, mw - 60
    local editing = self.editField and self.editField.tag == "onlineurl"
    love.graphics.setColor(P.panel[1], P.panel[2], P.panel[3], 0.95); love.graphics.rectangle("fill", fx, fy, fw, 34, 6)
    love.graphics.setColor(editing and P.lime or P.textDim); love.graphics.setLineWidth(1.5); love.graphics.rectangle("line", fx, fy, fw, 34, 6)
    local shown = (self.onlineURL ~= "" and self.onlineURL) or "http://"
    love.graphics.setColor((self.onlineURL ~= "") and P.text or P.textFaint)
    love.graphics.print(shown .. (editing and "_" or ""), fx + 8, fy + 8)
    self:reg(fx, fy, fw, 34, function()
        self.onlineURL = self.onlineURL or ""
        self.editField = { tag = "onlineurl", max = 200, get = function() return self.onlineURL end, set = function(v) self.onlineURL = v end }
    end)
    -- status message
    if self.onlineMsg then
        love.graphics.setColor(self.onlineOk and P.lime or P.coral)
        love.graphics.printf(self.onlineMsg, mx + 30, my + 138, mw - 60, "center")
    end
    -- buttons
    self:button(mx + mw / 2 - 220, my + mh - 56, 200, 40, "DOWNLOAD", function()
        self.editField = nil
        local file, err = Campaign.download(self.onlineURL or "")
        if file then self.onlineOk = true; self.onlineMsg = "Downloaded! Saved to your campaigns."
        else self.onlineOk = false; self.onlineMsg = err or "download failed" end
    end, { color = P.lime, font = fonts(self).small })
    self:button(mx + mw / 2 + 20, my + mh - 56, 200, 40, "CLOSE", function()
        self.editField = nil; self.onlineOpen = false
    end, { color = P.textDim, font = fonts(self).small })
end

-- ---- the editor ----
function UI:screen_editor()
    local c = self.editCamp
    if not c then self:setScreen("campaigns"); return end
    local node = self.editSel and c.nodes[self.editSel]

    -- top bar: name (click to rename) + actions
    love.graphics.setColor(P.panel[1], P.panel[2], P.panel[3], 0.95); love.graphics.rectangle("fill", 0, 0, LW, 56)
    love.graphics.setFont(fonts(self).medium)
    local editingName = self.editField and self.editField.tag == "campname"
    love.graphics.setColor(editingName and P.teal or P.text)
    love.graphics.print("✎ " .. c.name .. (editingName and "_" or ""), 20, 14)
    self:reg(20, 12, 420, 36, function()
        self.editField = { tag = "campname", max = 28, get = function() return c.name end, set = function(v) c.name = v end }
    end)
    -- starting loadout: always visible so it's easy to find (campaign-wide)
    c.startCards = c.startCards or {}
    self:button(448, 10, 210, 38, "STARTING CARDS (" .. #c.startCards .. ")",
        function() self.cardPickerOpen = true; self.cardScroll = 0 end, { color = P.gold, font = fonts(self).small })
    -- danger toggle: lift all the config caps so you can build absurd OP/huge
    -- enemies (warned that something too big can crash the game)
    self:button(LW - 560, 10, 156, 38, self.noLimits and "LIMITS: OFF !" or "REMOVE LIMITS",
        function() self.noLimits = not self.noLimits; Audio.play(self.noLimits and "denied" or "click", 0.5) end,
        { color = self.noLimits and P.coral or P.textDim, font = fonts(self).small })
    self:button(LW - 92, 10, 80, 38, "BACK", function() self.editField = nil; self:setScreen("campaigns") end, { color = P.textDim, font = fonts(self).small })
    self:button(LW - 184, 10, 84, 38, "SAVE", function() Campaign.save(c); Audio.play("buy", 0.6) end, { color = P.lime, font = fonts(self).small })
    self:button(LW - 300, 10, 108, 38, "▶ PLAY HERE", function() self.app.startCustomRun(c, self.editSel or 1, true) end, { color = P.gold, font = fonts(self).small })
    self:button(LW - 392, 10, 84, 38, "▶ PLAY", function() self.app.startCustomRun(c, 1, true) end, { color = P.teal, font = fonts(self).small })

    -- LEFT properties panel
    local px, py, pw, ph = 20, 64, 384, 486
    love.graphics.setColor(0.05, 0.08, 0.12, 0.85); love.graphics.rectangle("fill", px, py, pw, ph, 8)
    love.graphics.setColor(P.panelEdge[1], P.panelEdge[2], P.panelEdge[3], 0.5); love.graphics.setLineWidth(2); love.graphics.rectangle("line", px, py, pw, ph, 8)
    love.graphics.setScissor(self.app.offX + px * self.app.scale, self.app.offY + py * self.app.scale, pw * self.app.scale, ph * self.app.scale)
    local sc = self.scroll.editor or 0
    self:drawEditorProps(px + 14, py + 12 - sc, pw - 28, node)
    love.graphics.setScissor()
    self.maxScroll = math.max(0, (self.editContentH or 0) - (ph - 24))

    -- BOTTOM timeline of nodes
    self:drawEditorTimeline()

    if self.pickerOpen then self:drawEnemyPicker() end
    if self.cfgSpawn then self:drawSpawnConfig() end
    if self.cfgLevi then self:drawLeviConfig() end
    if self.cardPickerOpen then self:drawCardPicker() end
end

-- pick the upgrade cards the player STARTS the run with. Click a card to add it;
-- stackable cards add another copy, uniques can only be held once. The right
-- column lists the current loadout with stack counts (click to remove one).
function UI:drawCardPicker()
    local c = self.editCamp
    c.startCards = c.startCards or {}
    love.graphics.setColor(0, 0, 0.02, 0.82); love.graphics.rectangle("fill", 0, 0, LW, LH)
    self:reg(0, 0, LW, LH, function() self.cardPickerOpen = false end)
    local mw, mh = 980, 560
    local mx, my = LW / 2 - mw / 2, LH / 2 - mh / 2
    self:reg(mx, my, mw, mh, function() end)
    love.graphics.setColor(0.08, 0.1, 0.14, 0.99); love.graphics.rectangle("fill", mx, my, mw, mh, 10)
    love.graphics.setColor(P.gold); love.graphics.setLineWidth(2); love.graphics.rectangle("line", mx, my, mw, mh, 10)
    love.graphics.setFont(fonts(self).medium); love.graphics.setColor(P.text)
    love.graphics.printf("STARTING CARDS", mx, my + 14, mw, "center")
    local rcol = { common = P.textDim, rare = P.cyan, epic = P.purple, legendary = P.gold }
    -- count how many of each id are in the loadout
    local counts = {}
    for _, id in ipairs(c.startCards) do counts[id] = (counts[id] or 0) + 1 end
    -- LEFT: every card in the game (scrollable — wheel over the list to scroll)
    local lx, lw = mx + 20, mw * 0.6 - 30
    love.graphics.setFont(fonts(self).small); love.graphics.setColor(P.textFaint)
    love.graphics.print("ALL CARDS  (left-click adds · right-click removes · scroll for more)", lx, my + 50)
    local cw, ch, gap = (lw - 12) / 2, 44, 8
    local visTop, visBot = my + 72, my + mh - 92   -- leave a footer band for the description
    local visH = visBot - visTop
    local hoverUp = nil
    local rows = math.ceil(#Upgrades.list / 2)
    self.cardScrollMax = math.max(0, rows * (ch + gap) - visH)
    local sc = math.max(0, math.min(self.cardScroll or 0, self.cardScrollMax))
    self.cardScroll = sc
    love.graphics.setScissor(self.app.offX + lx * self.app.scale, self.app.offY + visTop * self.app.scale,
        (lw + 6) * self.app.scale, visH * self.app.scale)
    for i, up in ipairs(Upgrades.list) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local bx = lx + col * (cw + 12)
        local by = visTop + 2 + row * (ch + gap) - sc
        if by + ch > visTop and by < visBot then          -- only draw/click visible rows
            local owned = counts[up.id] or 0
            local isUnique = up.unique
            local locked = isUnique and owned > 0
            love.graphics.setColor(P.panel[1], P.panel[2], P.panel[3], locked and 0.4 or 0.9)
            love.graphics.rectangle("fill", bx, by, cw, ch, 6)
            local rc = rcol[up.rarity] or P.textDim
            love.graphics.setColor(rc[1], rc[2], rc[3], locked and 0.4 or 0.9); love.graphics.setLineWidth(1.5)
            love.graphics.rectangle("line", bx, by, cw, ch, 6)
            love.graphics.setColor(P.text[1], P.text[2], P.text[3], locked and 0.4 or 1)
            love.graphics.print(up.name .. (isUnique and "  *" or ""), bx + 8, by + 5)
            love.graphics.setColor(rc[1], rc[2], rc[3], locked and 0.4 or 0.8)
            love.graphics.print(up.rarity:upper() .. (owned > 0 and ("  x" .. owned) or ""), bx + 8, by + 24)
            if U.inRect(self.mx, self.my, bx, math.max(by, visTop), cw, math.min(by + ch, visBot) - math.max(by, visTop)) then hoverUp = up end
            local addFn = (not locked) and function()
                c.startCards[#c.startCards + 1] = up.id; Audio.play("click", 0.5)
            end or nil
            local removeFn = function()                     -- right-click removes one
                for k = #c.startCards, 1, -1 do
                    if c.startCards[k] == up.id then table.remove(c.startCards, k); Audio.play("denied", 0.4); break end
                end
            end
            self:reg(bx, by, cw, ch, addFn, false, removeFn)
        end
    end
    love.graphics.setScissor()
    -- scrollbar hint
    if self.cardScrollMax > 0 then
        local bh = visH * (visH / (rows * (ch + gap)))
        local byy = visTop + (sc / self.cardScrollMax) * (visH - bh)
        love.graphics.setColor(P.gold[1], P.gold[2], P.gold[3], 0.5)
        love.graphics.rectangle("fill", lx + lw + 2, byy, 4, bh, 2)
    end
    -- RIGHT: current loadout (unique list with counts), click to remove one
    local rx = mx + mw * 0.6 + 6
    love.graphics.setColor(P.gold); love.graphics.setFont(fonts(self).small)
    love.graphics.print("LOADOUT (" .. #c.startCards .. ")  — click to remove", rx, my + 50)
    -- distinct ids in insertion order
    local order, seen = {}, {}
    for _, id in ipairs(c.startCards) do if not seen[id] then seen[id] = true; order[#order + 1] = id end end
    local ry = my + 74
    for _, id in ipairs(order) do
        local up = Upgrades.byId[id]
        if up then
            love.graphics.setColor(P.panel[1], P.panel[2], P.panel[3], 0.9); love.graphics.rectangle("fill", rx, ry, mw * 0.4 - 26, 30, 5)
            love.graphics.setColor(P.text)
            love.graphics.print(up.name .. "  x" .. counts[id], rx + 8, ry + 6)
            love.graphics.setColor(P.coral); love.graphics.print("remove", rx + mw * 0.4 - 90, ry + 6)
            if U.inRect(self.mx, self.my, rx, ry, mw * 0.4 - 26, 30) then hoverUp = up end
            self:reg(rx, ry, mw * 0.4 - 26, 30, function()
                for k = #c.startCards, 1, -1 do if c.startCards[k] == id then table.remove(c.startCards, k); break end end
                Audio.play("denied", 0.4)
            end)
            ry = ry + 34
        end
    end
    -- description footer: details of whatever card is under the cursor
    local fy = my + mh - 84
    love.graphics.setColor(P.panel[1], P.panel[2], P.panel[3], 0.6); love.graphics.rectangle("fill", mx + 20, fy, mw - 40, 34, 6)
    love.graphics.setFont(fonts(self).small)
    if hoverUp then
        local rc = rcol[hoverUp.rarity] or P.text
        love.graphics.setColor(rc); love.graphics.print(hoverUp.name, mx + 30, fy + 8)
        love.graphics.setColor(P.text); love.graphics.print(hoverUp.desc or "", mx + 30 + fonts(self).small:getWidth(hoverUp.name) + 14, fy + 8)
    else
        love.graphics.setColor(P.textFaint); love.graphics.print("Hover a card to see what it does.", mx + 30, fy + 8)
    end
    self:button(mx + mw / 2 - 80, my + mh - 44, 160, 32, "DONE", function() self.cardPickerOpen = false end, { color = P.gold, font = fonts(self).small })
end

-- per-entity configuration: count, variant, stat multipliers, and any
-- type-specific special knobs (ring/shrapnel counts, arm length, leech, sludge…).
-- Works for a wave spawn OR a depth boss (self.cfgSpawn.bossConfig hides count).
function UI:drawSpawnConfig()
    local sp = self.cfgSpawn
    sp.cfg = sp.cfg or Campaign.defaultCfg()
    local cfg = sp.cfg
    cfg.special = cfg.special or {}
    local isBossCfg = sp.bossConfig
    local isAddCfg = sp.addCfgEdit
    love.graphics.setColor(0, 0, 0.02, 0.8); love.graphics.rectangle("fill", 0, 0, LW, LH)
    self:reg(0, 0, LW, LH, function() self:closeCfgSpawn() end)
    local mw, mh = 520, 560
    local mx, my = LW / 2 - mw / 2, LH / 2 - mh / 2
    self:reg(mx, my, mw, mh, function() self:commitNumEdit() end)   -- panel swallows clicks (commits a typed value)
    love.graphics.setColor(0.08, 0.1, 0.14, 0.99); love.graphics.rectangle("fill", mx, my, mw, mh, 10)
    love.graphics.setColor(P.teal); love.graphics.setLineWidth(2); love.graphics.rectangle("line", mx, my, mw, mh, 10)
    love.graphics.setFont(fonts(self).medium); love.graphics.setColor(P.text)
    local tagpfx = isBossCfg and "BOSS · " or isAddCfg and "ADD · " or ""
    love.graphics.printf(tagpfx .. Campaign.niceName(sp.id), mx, my + 14, mw, "center")
    local NL = self.noLimits
    if NL then
        love.graphics.setColor(P.coral); love.graphics.setFont(fonts(self).small)
        love.graphics.printf("!! LIMITS OFF - extreme values can crash the game", mx, my + 40, mw, "center")
    end
    local x, w, yy = mx + 30, mw - 60, my + (NL and 64 or 56)
    local isBoss = false; for _, b in ipairs(Campaign.BOSSES) do if b == sp.id then isBoss = true end end
    -- how many of this exact enemy spawn (bosses spawn once; adds use their knob)
    if not isBossCfg and not isAddCfg then
        local cmax = NL and 9999 or 99
        self:stepper(x, yy, w, "Count (how many spawn)", tostring(sp.count or 1),
            function() sp.count = math.max(1, (sp.count or 1) - 1) end, function() sp.count = math.min(cmax, (sp.count or 1) + 1) end,
            { val = sp.count or 1, min = 1, max = cmax, set = function(n) sp.count = math.max(1, math.floor(n + 0.5)) end }); yy = yy + 32
    end
    -- custom health-bar name for wave-spawned bosses (the depth-end boss is named
    -- on the depth panel instead)
    if (isBoss or sp.asBoss) and not isBossCfg and not isAddCfg then
        local editing = self.editField and self.editField.tag == "spawnbossname"
        love.graphics.setColor(P.textDim); love.graphics.setFont(fonts(self).small); love.graphics.print("Bar name", x, yy + 4)
        love.graphics.setColor(P.panel[1], P.panel[2], P.panel[3], 0.9); love.graphics.rectangle("fill", x + 90, yy - 1, w - 90, 24, 5)
        love.graphics.setColor(editing and P.teal or P.textFaint); love.graphics.setLineWidth(1.5); love.graphics.rectangle("line", x + 90, yy - 1, w - 90, 24, 5)
        local realsn = sp.name ~= nil and sp.name ~= ""
        love.graphics.setColor(realsn and P.text or P.textFaint)
        love.graphics.print((realsn and sp.name or Campaign.niceName(sp.id)) .. (editing and "_" or ""), x + 96, yy + 3)
        self:reg(x + 90, yy - 1, w - 90, 24, function()
            sp.name = sp.name or ""
            self.editField = { tag = "spawnbossname", max = 28, get = function() return sp.name end, set = function(v) sp.name = v end }
        end)
        yy = yy + 32
    end
    -- variant tier — regular enemies only (bosses/mines have no variants)
    if not isBoss and sp.id ~= "mine" then
        local cyc = { "base", "elite", "abyssal" }
        self:stepper(x, yy, w, "Variant", (cfg.variant or "base"):upper(), function()
            local i = 1; for k, v in ipairs(cyc) do if v == cfg.variant then i = k end end
            cfg.variant = cyc[(i - 2) % 3 + 1]
        end, function()
            local i = 1; for k, v in ipairs(cyc) do if v == cfg.variant then i = k end end
            cfg.variant = cyc[i % 3 + 1]
        end); yy = yy + 32
    end
    -- universal stat multipliers. Damage and Speed can go to 0 (a harmless or
    -- stationary enemy); Health and Size keep a 0.1 floor (0 = instantly dead /
    -- invisible).
    local statMax = NL and 999 or 6
    for _, m in ipairs({ { "hp", "Health", 0.1 }, { "dmg", "Damage", 0 }, { "speed", "Speed", 0 }, { "size", "Size", 0.1 } }) do
        local k, lo = m[1], m[3]
        cfg[k] = cfg[k] or 1
        self:stepper(x, yy, w, m[2], string.format("x%.2f", cfg[k]),
            function() cfg[k] = math.max(lo, cfg[k] - 0.1) end, function() cfg[k] = math.min(statMax, cfg[k] + 0.1) end,
            { val = cfg[k], min = lo, max = statMax, set = function(n) cfg[k] = n end }); yy = yy + 30
    end
    -- type-specific specials, split into a general SPECIAL group and a separate
    -- SPAWNED ADDS group (what a brood sac / boss spawns).
    local specs = Campaign.specialsFor(sp.id)
    if specs then
        local SPAWN_KEYS = { adds = true, splitN = true }
        local function drawSpec(s)
            local key, label, def, lo, hi, step = s[1], s[2], s[3], s[4], s[5], s[6]
            local cap = NL and (hi * 100) or hi
            local v = cfg.special[key] or def
            local lbl = (v == def) and (label .. " (default)") or label
            local fmt = (step < 1) and string.format("%.2f", v) or tostring(v)
            self:stepper(x, yy, w, lbl, fmt,
                function() cfg.special[key] = math.max(lo, (cfg.special[key] or def) - step) end,
                function() cfg.special[key] = math.min(cap, (cfg.special[key] or def) + step) end,
                { val = v, min = lo, max = cap, set = function(n) cfg.special[key] = n end }); yy = yy + 28
        end
        local hasReg, hasSpawn = false, false
        for _, s in ipairs(specs) do if SPAWN_KEYS[s[1]] then hasSpawn = true else hasReg = true end end
        if hasReg then
            love.graphics.setColor(P.purple); love.graphics.setFont(fonts(self).small)
            love.graphics.print("SPECIAL  (0 = this enemy's default)", x, yy + 4); yy = yy + 24
            for _, s in ipairs(specs) do if not SPAWN_KEYS[s[1]] then drawSpec(s) end end
        end
        if hasSpawn then
            love.graphics.setColor(P.lime); love.graphics.setFont(fonts(self).small)
            love.graphics.print("SPAWNED ADDS", x, yy + 6); yy = yy + 26
            for _, s in ipairs(specs) do if SPAWN_KEYS[s[1]] then drawSpec(s) end end
            -- configure the STATS of the spawned creatures (size/hp/dmg/specials)
            local at = Campaign.addType(sp.id)
            if at then
                self:button(x, yy, w, 26, "CONFIGURE " .. Campaign.niceName(at):upper() .. " STATS", function()
                    cfg.addCfg = cfg.addCfg or Campaign.defaultCfg()
                    self:commitNumEdit()
                    self.cfgSpawnParent = self.cfgSpawn
                    self.cfgSpawn = { id = at, cfg = cfg.addCfg, addCfgEdit = true }
                end, { color = P.lime, font = fonts(self).small }); yy = yy + 30
            end
        end
    end
    self:button(mx + mw / 2 - 70, my + mh - 44, 140, 32, "DONE", function() self:closeCfgSpawn() end, { color = P.teal, font = fonts(self).small })
end

-- close the config modal (or, if it's the nested ADD-stats modal, return to the
-- parent boss/sac config that opened it)
function UI:closeCfgSpawn()
    self:commitNumEdit()
    if self.cfgSpawnParent then
        self.cfgSpawn = self.cfgSpawnParent; self.cfgSpawnParent = nil
    else
        self.cfgSpawn = nil
    end
end

-- leviathan flyby configuration: variant + its toxic-sludge / arm overrides.
-- (which wave it surfaces on is just the wave you added it to)
function UI:drawLeviConfig()
    local lv = self.cfgLevi
    love.graphics.setColor(0, 0, 0.02, 0.8); love.graphics.rectangle("fill", 0, 0, LW, LH)
    self:reg(0, 0, LW, LH, function() self:commitNumEdit(); self.cfgLevi = nil end)
    local mw, mh = 520, 360
    local mx, my = LW / 2 - mw / 2, LH / 2 - mh / 2
    self:reg(mx, my, mw, mh, function() self:commitNumEdit() end)   -- panel swallows clicks (commits a typed value)
    local NL = self.noLimits
    love.graphics.setColor(0.08, 0.1, 0.14, 0.99); love.graphics.rectangle("fill", mx, my, mw, mh, 10)
    love.graphics.setColor(P.purple); love.graphics.setLineWidth(2); love.graphics.rectangle("line", mx, my, mw, mh, 10)
    love.graphics.setFont(fonts(self).medium); love.graphics.setColor(P.text)
    love.graphics.printf("LEVIATHAN", mx, my + 14, mw, "center")
    local x, w, yy = mx + 30, mw - 60, my + 60
    -- variant
    local cyc = { "pale", "blue", "red" }
    self:stepper(x, yy, w, "Variant", (lv.variant or "pale"):upper(), function()
        local i = 1; for k, v in ipairs(cyc) do if v == lv.variant then i = k end end
        lv.variant = cyc[(i - 2) % 3 + 1]
    end, function()
        local i = 1; for k, v in ipairs(cyc) do if v == lv.variant then i = k end end
        lv.variant = cyc[i % 3 + 1]
    end); yy = yy + 38
    -- sludge + arm overrides (0 = built-in default)
    love.graphics.setColor(P.purple); love.graphics.setFont(fonts(self).small)
    love.graphics.print("OVERRIDES  (0 = default)", x, yy + 4); yy = yy + 24
    local dmgMax, lifeMax, armMax = NL and 6000 or 60, NL and 3000 or 30, NL and 600 or 6
    self:stepper(x, yy, w, "Sludge damage", tostring(lv.sludgeDmg or 0),
        function() lv.sludgeDmg = math.max(0, (lv.sludgeDmg or 0) - 1) end, function() lv.sludgeDmg = math.min(dmgMax, (lv.sludgeDmg or 0) + 1) end,
        { val = lv.sludgeDmg or 0, min = 0, max = dmgMax, set = function(n) lv.sludgeDmg = n end }); yy = yy + 30
    self:stepper(x, yy, w, "Sludge lifetime", string.format("%.1f", lv.sludgeLife or 0),
        function() lv.sludgeLife = math.max(0, (lv.sludgeLife or 0) - 0.5) end, function() lv.sludgeLife = math.min(lifeMax, (lv.sludgeLife or 0) + 0.5) end,
        { val = lv.sludgeLife or 0, min = 0, max = lifeMax, set = function(n) lv.sludgeLife = n end }); yy = yy + 30
    self:stepper(x, yy, w, "Arm reach (blue) x", string.format("%.2f", lv.armLen or 0),
        function() lv.armLen = math.max(0, (lv.armLen or 0) - 0.25) end, function() lv.armLen = math.min(armMax, (lv.armLen or 0) + 0.25) end,
        { val = lv.armLen or 0, min = 0, max = armMax, set = function(n) lv.armLen = n end }); yy = yy + 30
    self:button(mx + mw / 2 - 70, my + mh - 44, 140, 32, "DONE", function() self:commitNumEdit(); self.cfgLevi = nil end, { color = P.purple, font = fonts(self).small })
end

-- a labelled ON/OFF toggle row; returns the y advance (used in the props panel)
function UI:toggleRow(x, y, w, label, val, onclick)
    love.graphics.setColor(P.textDim); love.graphics.setFont(fonts(self).small)
    love.graphics.print(label, x, y + 4)
    love.graphics.setColor(val and P.teal or P.textFaint); love.graphics.setLineWidth(1.5)
    love.graphics.rectangle("line", x + w - 50, y, 40, 20, 4)
    if val then love.graphics.setColor(P.teal); love.graphics.rectangle("fill", x + w - 50, y, 40, 20, 4) end
    love.graphics.setColor(P.text); love.graphics.printf(val and "ON" or "OFF", x + w - 50, y + 2, 40, "center")
    self:reg(x + w - 50, y, 40, 20, function() Audio.play("click", 0.4); onclick() end)
end

function UI:drawEditorProps(x, y, w, node)
    local f = fonts(self)
    if not node then
        love.graphics.setFont(f.medium); love.graphics.setColor(P.textDim)
        love.graphics.print("Nothing selected", x, y)
        love.graphics.setFont(f.small); love.graphics.setColor(P.textFaint)
        love.graphics.printf("Select a depth below, or set the campaign-wide multipliers (applied to every enemy, like a difficulty):", x, y + 30, w, "left")
        love.graphics.setColor(P.teal); love.graphics.setFont(f.normal)
        love.graphics.print("GLOBAL MULTIPLIERS", x, y + 96)
        local m = self.editCamp.mult
        m.enemySize = m.enemySize or 1
        local yy = y + 126
        self:stepper(x, yy, w, "Enemy HP", string.format("x%.2f", m.enemyHp), function() m.enemyHp = math.max(0.1, m.enemyHp - 0.1) end, function() m.enemyHp = math.min(5, m.enemyHp + 0.1) end); yy = yy + 30
        self:stepper(x, yy, w, "Enemy DMG", string.format("x%.2f", m.enemyDmg), function() m.enemyDmg = math.max(0, m.enemyDmg - 0.1) end, function() m.enemyDmg = math.min(5, m.enemyDmg + 0.1) end); yy = yy + 30
        self:stepper(x, yy, w, "Enemy SPD", string.format("x%.2f", m.enemySpeed), function() m.enemySpeed = math.max(0, m.enemySpeed - 0.1) end, function() m.enemySpeed = math.min(4, m.enemySpeed + 0.1) end); yy = yy + 30
        self:stepper(x, yy, w, "Enemy SIZE", string.format("x%.2f", m.enemySize), function() m.enemySize = math.max(0.3, m.enemySize - 0.1) end, function() m.enemySize = math.min(4, m.enemySize + 0.1) end); yy = yy + 30
        self:stepper(x, yy, w, "Payout", string.format("x%.2f", m.payMult), function() m.payMult = math.max(0, m.payMult - 0.1) end, function() m.payMult = math.min(5, m.payMult + 0.1) end); yy = yy + 42
        -- starting loadout: the cards the player begins the run holding
        self.editCamp.startCards = self.editCamp.startCards or {}
        self:button(x, yy, w, 36, "STARTING CARDS (" .. #self.editCamp.startCards .. ")",
            function() self.cardPickerOpen = true; self.cardScroll = 0 end, { color = P.gold, font = f.normal })
        self.editContentH = 380
        return
    end
    if node.kind == "title" then
        love.graphics.setFont(f.normal); love.graphics.setColor(P.aqua); love.graphics.print("TITLE CARD", x, y)
        love.graphics.setFont(f.small); love.graphics.setColor(P.textFaint)
        love.graphics.printf("Story text shown before the next depth.", x, y + 26, w, "left")
        local editing = self.editField and self.editField.tag == "title"
        love.graphics.setColor(P.panel[1], P.panel[2], P.panel[3], 0.9); love.graphics.rectangle("fill", x, y + 52, w, 90, 6)
        love.graphics.setColor(editing and P.teal or P.textDim); love.graphics.setLineWidth(1.5); love.graphics.rectangle("line", x, y + 52, w, 90, 6)
        love.graphics.setColor(P.text); love.graphics.printf(node.text .. (editing and "_" or ""), x + 8, y + 58, w - 16, "left")
        self:reg(x, y + 52, w, 90, function() self.editField = { tag = "title", max = 160, get = function() return node.text end, set = function(v) node.text = v end } end)
        node.dur = node.dur or 5
        self:stepper(x, y + 152, w, "Duration (sec)", string.format("%.1f", node.dur),
            function() node.dur = math.max(0.5, node.dur - 0.5) end, function() node.dur = math.min(60, node.dur + 0.5) end,
            { val = node.dur, min = 0.5, max = 60, set = function(n) node.dur = n end });
        self.editContentH = 200
        return
    end
    -- DEPTH properties
    Campaign.normalizeDepth(node)        -- keep fields present (waves/cards/bossCfg)
    love.graphics.setFont(f.normal); love.graphics.setColor(P.teal); love.graphics.print("DEPTH", x, y)
    local editing = self.editField and self.editField.tag == "depthname"
    love.graphics.setColor(P.panel[1], P.panel[2], P.panel[3], 0.9); love.graphics.rectangle("fill", x + 64, y - 2, w - 64, 26, 5)
    love.graphics.setColor(editing and P.teal or P.textDim); love.graphics.setLineWidth(1.5); love.graphics.rectangle("line", x + 64, y - 2, w - 64, 26, 5)
    love.graphics.setColor(P.text); love.graphics.print(node.name .. (editing and "_" or ""), x + 72, y + 2)
    self:reg(x + 64, y - 2, w - 64, 26, function() self.editField = { tag = "depthname", max = 24, get = function() return node.name end, set = function(v) node.name = v end } end)
    local yy = y + 34
    self:stepper(x, yy, w, "Fog", string.format("%d%%", math.floor(node.fog * 100)), function() node.fog = math.max(0, node.fog - 0.1) end, function() node.fog = math.min(0.95, node.fog + 0.1) end); yy = yy + 28
    self:stepper(x, yy, w, "Mines", tostring(node.mines), function() node.mines = math.max(0, node.mines - 1) end, function() node.mines = math.min(8, node.mines + 1) end); yy = yy + 28
    self:toggleRow(x, yy, w, "Card pick after clearing", node.cards ~= false, function() node.cards = (node.cards == false) end); yy = yy + 28
    node.music = node.music or "normal"
    self:stepper(x, yy, w, "Music", Campaign.musicLabel(node.music),
        function() node.music = Campaign.musicCycle(node.music, -1) end,
        function() node.music = Campaign.musicCycle(node.music, 1) end); yy = yy + 28
    self:toggleRow(x, yy, w, "Corner arms", node.cornerArms, function() node.cornerArms = not node.cornerArms end); yy = yy + 28
    if node.cornerArms then
        node.cornerArmLen = node.cornerArmLen or 0.24
        self:stepper(x, yy, w, "  Arm length", string.format("%.2f", node.cornerArmLen), function() node.cornerArmLen = math.max(0.05, node.cornerArmLen - 0.02) end, function() node.cornerArmLen = math.min(0.9, node.cornerArmLen + 0.02) end); yy = yy + 28
    end
    -- boss cycle (spawns after the last wave) + custom name + config
    local bosses = { false, "warden", "maw", "eldritch", "churglynth" }
    self:stepper(x, yy, w, "Finale boss (after last wave)", node.boss and Campaign.niceName(node.boss) or "none", function()
        local i = 1; for k, b in ipairs(bosses) do if b == node.boss then i = k end end
        node.boss = bosses[(i - 2) % #bosses + 1]
    end, function()
        local i = 1; for k, b in ipairs(bosses) do if b == node.boss then i = k end end
        node.boss = bosses[i % #bosses + 1]
    end); yy = yy + 28
    if node.boss then
        -- custom boss title (click to rename)
        local bediting = self.editField and self.editField.tag == "bossname"
        love.graphics.setColor(P.textDim); love.graphics.setFont(f.small); love.graphics.print("Boss name", x, yy + 4)
        love.graphics.setColor(P.panel[1], P.panel[2], P.panel[3], 0.9); love.graphics.rectangle("fill", x + 96, yy - 1, w - 96, 24, 5)
        love.graphics.setColor(bediting and P.teal or P.textFaint); love.graphics.setLineWidth(1.5); love.graphics.rectangle("line", x + 96, yy - 1, w - 96, 24, 5)
        local realbn = node.bossName ~= nil and node.bossName ~= ""
        love.graphics.setColor(realbn and P.text or P.textFaint)
        love.graphics.print((realbn and node.bossName or Campaign.niceName(node.boss)) .. (bediting and "_" or ""), x + 102, yy + 3)
        self:reg(x + 96, yy - 1, w - 96, 24, function()
            node.bossName = node.bossName or ""
            self.editField = { tag = "bossname", max = 28, get = function() return node.bossName end, set = function(v) node.bossName = v end }
        end)
        yy = yy + 30
        self:button(x, yy, w, 26, "CONFIGURE BOSS", function()
            node.bossCfg = node.bossCfg or Campaign.defaultCfg()
            self.cfgSpawn = { id = node.boss, cfg = node.bossCfg, bossConfig = true }
        end, { color = P.gold, font = f.small }); yy = yy + 34
    end

    -- WAVE selector: which wave's spawns you're editing
    self.editWave = math.max(1, math.min(self.editWave or 1, #node.waves))
    local wsel = self.editWave
    love.graphics.setColor(P.lime); love.graphics.setFont(f.normal)
    love.graphics.print("WAVE " .. wsel .. " / " .. #node.waves, x, yy)
    -- < > switch
    love.graphics.setFont(f.small)
    love.graphics.setColor(P.teal); love.graphics.print("<", x + w - 150, yy + 2); love.graphics.print(">", x + w - 128, yy + 2)
    self:reg(x + w - 154, yy, 22, 22, function() self.editWave = (wsel - 2) % #node.waves + 1 end)
    self:reg(x + w - 132, yy, 22, 22, function() self.editWave = wsel % #node.waves + 1 end)
    -- + wave / - wave (delete current)
    love.graphics.setColor(P.lime); love.graphics.print("+wave", x + w - 100, yy + 2)
    self:reg(x + w - 100, yy, 48, 22, function() node.waves[#node.waves + 1] = Campaign.newWave(); self.editWave = #node.waves; Audio.play("click", 0.4) end)
    love.graphics.setColor(P.coral); love.graphics.print("-wave", x + w - 46, yy + 2)
    self:reg(x + w - 46, yy, 48, 22, function()
        if #node.waves > 1 then table.remove(node.waves, wsel); self.editWave = math.min(wsel, #node.waves); Audio.play("denied", 0.4) end
    end)
    yy = yy + 26
    -- copy this wave's full contents (enemies/bosses/leviathans) and paste over
    -- another wave (navigate with < > then PASTE)
    local hasClip = self.waveClipboard ~= nil
    local hbw2 = (w - 8) / 2
    self:button(x, yy, hbw2, 24, "COPY WAVE", function()
        self.waveClipboard = Campaign.copyWave(node.waves[wsel]); Audio.play("click", 0.5)
    end, { color = P.teal, font = f.small })
    self:button(x + hbw2 + 8, yy, hbw2, 24, hasClip and "PASTE WAVE" or "PASTE (none)", function()
        if self.waveClipboard then node.waves[wsel] = Campaign.copyWave(self.waveClipboard); Audio.play("buy", 0.5) end
    end, { color = hasClip and P.aqua or P.textFaint, font = f.small, disabled = not hasClip })
    yy = yy + 30

    -- SPAWNS for the selected wave — each entry is ONE configurable enemy group
    local waveDef = node.waves[wsel]
    if #waveDef.spawns == 0 then
        love.graphics.setColor(P.textFaint); love.graphics.setFont(f.small)
        love.graphics.print("(empty wave — add enemies below)", x, yy + 2); yy = yy + 24
    end
    for si, sp in ipairs(waveDef.spawns) do
        sp.cfg = sp.cfg or Campaign.defaultCfg()
        love.graphics.setColor(P.panel[1], P.panel[2], P.panel[3], 0.8); love.graphics.rectangle("fill", x, yy, w, 26, 4)
        love.graphics.setColor(P.text); love.graphics.setFont(f.small)
        local vtag = (sp.cfg.variant and sp.cfg.variant ~= "base") and (" [" .. sp.cfg.variant:sub(1, 3) .. "]") or ""
        love.graphics.print("x" .. (sp.count or 1) .. "  " .. Campaign.niceName(sp.id) .. vtag, x + 6, yy + 5)
        self:reg(x, yy, w - 150, 26, function() self.cfgSpawn = sp end)         -- click → full config
        -- compact count stepper
        love.graphics.setColor(P.teal); love.graphics.print("-", x + w - 142, yy + 4); love.graphics.print("+", x + w - 120, yy + 4)
        self:reg(x + w - 146, yy, 20, 24, function() sp.count = math.max(1, (sp.count or 1) - 1) end)
        self:reg(x + w - 124, yy, 20, 24, function() sp.count = math.min(99, (sp.count or 1) + 1) end)
        -- config / duplicate / delete
        love.graphics.setColor(P.cyan); love.graphics.print("cfg", x + w - 100, yy + 5)
        self:reg(x + w - 102, yy, 30, 24, function() self.cfgSpawn = sp end)
        love.graphics.setColor(P.aqua); love.graphics.print("dup", x + w - 64, yy + 5)
        self:reg(x + w - 66, yy, 30, 24, function() table.insert(waveDef.spawns, si + 1, Campaign.copySpawn(sp)); Audio.play("click", 0.4) end)
        love.graphics.setColor(P.coral); love.graphics.print("x", x + w - 22, yy + 4)
        self:reg(x + w - 26, yy, 22, 24, function() table.remove(waveDef.spawns, si) end)
        yy = yy + 30
    end
    local hbw = (w - 8) / 2
    self:button(x, yy, hbw, 28, "+ ENEMY", function() self.pickerOpen = true; self.pickerBoss = false end, { color = P.lime, font = f.small })
    self:button(x + hbw + 8, yy, hbw, 28, "+ BOSS", function() self.pickerOpen = true; self.pickerBoss = true end, { color = P.gold, font = f.small })
    yy = yy + 36

    -- LEVIATHAN events for THIS wave (click a row to configure variant/sludge/arms)
    waveDef.levis = waveDef.levis or {}
    love.graphics.setColor(P.purple); love.graphics.setFont(f.normal); love.graphics.print("LEVIATHANS (wave " .. wsel .. ")", x, yy); yy = yy + 26
    for li, lv in ipairs(waveDef.levis) do
        love.graphics.setColor(P.panel[1], P.panel[2], P.panel[3], 0.8); love.graphics.rectangle("fill", x, yy, w, 26, 4)
        love.graphics.setColor(P.text); love.graphics.setFont(f.small)
        love.graphics.print(lv.variant:upper() .. " leviathan", x + 6, yy + 5)
        self:reg(x, yy, w - 100, 26, function() self.cfgLevi = lv end)
        love.graphics.setColor(P.cyan); love.graphics.print("cfg", x + w - 96, yy + 5)
        self:reg(x + w - 98, yy, 30, 24, function() self.cfgLevi = lv end)
        love.graphics.setColor(P.aqua); love.graphics.print("dup", x + w - 60, yy + 5)
        self:reg(x + w - 62, yy, 30, 24, function()
            local nl = {}; for k, v in pairs(lv) do nl[k] = v end
            table.insert(waveDef.levis, li + 1, nl); Audio.play("click", 0.4)
        end)
        love.graphics.setColor(P.coral); love.graphics.print("x", x + w - 22, yy + 4)
        self:reg(x + w - 26, yy, 22, 24, function() table.remove(waveDef.levis, li) end)
        yy = yy + 30
    end
    self:button(x, yy, w, 28, "+ ADD LEVIATHAN TO WAVE " .. wsel, function()
        waveDef.levis[#waveDef.levis + 1] = Campaign.newLevi()
    end, { color = P.purple, font = f.small }); yy = yy + 32

    self.editContentH = (yy - y) + 40
end

function UI:drawEditorTimeline()
    local ty, th = 566, 146
    love.graphics.setColor(0.04, 0.06, 0.1, 0.9); love.graphics.rectangle("fill", 0, ty, LW, th)
    love.graphics.setColor(P.textFaint); love.graphics.setFont(fonts(self).small)
    love.graphics.print("DEPTHS & TITLES", 20, ty + 6)
    local c = self.editCamp
    local cw, gap, x0 = 150, 12, 20
    local sc = self.timelineScroll or 0
    love.graphics.setScissor(self.app.offX, self.app.offY + (ty + 26) * self.app.scale, LW * self.app.scale, (th - 26) * self.app.scale)
    local x = x0 - sc
    for i, n in ipairs(c.nodes) do
        local isTitle = n.kind == "title"
        local sel = (self.editSel == i)
        local col = isTitle and P.aqua or P.teal
        love.graphics.setColor(P.panel[1], P.panel[2], P.panel[3], 0.96); love.graphics.rectangle("fill", x, ty + 30, cw, 100, 8)
        love.graphics.setColor(col[1], col[2], col[3], sel and 1 or 0.5); love.graphics.setLineWidth(sel and 3 or 2); love.graphics.rectangle("line", x, ty + 30, cw, 100, 8)
        love.graphics.setColor(col); love.graphics.setFont(fonts(self).small)
        love.graphics.printf(isTitle and "TITLE" or "DEPTH", x + 6, ty + 36, cw - 12, "left")
        love.graphics.setColor(P.text)
        love.graphics.printf(isTitle and (n.text:sub(1, 40)) or n.name, x + 6, ty + 54, cw - 12, "left")
        -- row buttons
        local by = ty + 104
        self:reg(x + 4, by, 44, 22, function() self.editSel = i; self.editWave = 1; self.scroll.editor = 0 end)
        love.graphics.setColor(sel and P.gold or P.textDim); love.graphics.print("select", x + 6, by + 4)
        self:reg(x + 52, by, 40, 22, function()                                   -- duplicate (deep copy)
            table.insert(c.nodes, i + 1, Campaign.copyNode(n))
        end)
        love.graphics.setColor(P.cyan); love.graphics.print("dup", x + 54, by + 4)
        self:reg(x + 96, by, 24, 22, function() table.remove(c.nodes, i); if self.editSel == i then self.editSel = nil end end)
        love.graphics.setColor(P.coral); love.graphics.print("del", x + 98, by + 4)
        x = x + cw + gap
    end
    -- add buttons
    love.graphics.setColor(P.panel[1], P.panel[2], P.panel[3], 0.96); love.graphics.rectangle("fill", x, ty + 30, 70, 100, 8)
    love.graphics.setColor(P.teal); love.graphics.setLineWidth(2); love.graphics.rectangle("line", x, ty + 30, 70, 46, 8)
    love.graphics.printf("+ Depth", x, ty + 44, 70, "center")
    self:reg(x, ty + 30, 70, 46, function() c.nodes[#c.nodes + 1] = Campaign.newDepth(); self.editSel = #c.nodes; self.editWave = 1; self.scroll.editor = 0 end)
    love.graphics.setColor(P.aqua); love.graphics.rectangle("line", x, ty + 84, 70, 46, 8)
    love.graphics.printf("+ Title", x, ty + 98, 70, "center")
    self:reg(x, ty + 84, 70, 46, function() c.nodes[#c.nodes + 1] = Campaign.newTitle(); self.editSel = #c.nodes; self.scroll.editor = 0 end)
    love.graphics.setScissor()
    -- x is already shifted by -scroll, so add it back to get the true content
    -- width (otherwise the max shrinks as you scroll and snaps you back).
    self.timelineMax = math.max(0, (x + (self.timelineScroll or 0) + 90) - LW)
end

function UI:drawEnemyPicker()
    love.graphics.setColor(0, 0, 0.02, 0.8); love.graphics.rectangle("fill", 0, 0, LW, LH)
    self:reg(0, 0, LW, LH, function() self.pickerOpen = false; self.pickerBoss = false end)
    local mw, mh = 720, 520
    local mx, my = LW / 2 - mw / 2, LH / 2 - mh / 2
    self:reg(mx, my, mw, mh, function() end)   -- panel swallows clicks so slips don't close it
    love.graphics.setColor(0.08, 0.1, 0.14, 0.99); love.graphics.rectangle("fill", mx, my, mw, mh, 10)
    love.graphics.setColor(P.teal); love.graphics.setLineWidth(2); love.graphics.rectangle("line", mx, my, mw, mh, 10)
    love.graphics.setFont(fonts(self).medium); love.graphics.setColor(P.text)
    love.graphics.printf(self.pickerBoss and "ADD BOSS" or "ADD ENEMY", mx, my + 14, mw, "center")
    local node = self.editSel and self.editCamp.nodes[self.editSel]
    if not node or node.kind ~= "depth" then self.pickerOpen = false; self.pickerBoss = false; return end
    Campaign.normalizeDepth(node)
    local wsel = math.max(1, math.min(self.editWave or 1, #node.waves))
    love.graphics.setFont(fonts(self).small); love.graphics.setColor(P.textDim)
    love.graphics.printf("adding to WAVE " .. wsel, mx, my + 44, mw, "center")
    local function addRow(label, ids, gy, asBoss)
        love.graphics.setFont(fonts(self).small); love.graphics.setColor(P.textFaint); love.graphics.print(label, mx + 24, gy)
        local bx, by = mx + 24, gy + 20
        for _, id in ipairs(ids) do
            local bw = 150
            self:button(bx, by, bw, 30, Campaign.niceName(id), function()
                local sp = Campaign.newSpawn(id)
                if asBoss then sp.asBoss = true end       -- give it a boss health bar
                node.waves[wsel].spawns[#node.waves[wsel].spawns + 1] = sp
                self.pickerOpen = false; self.pickerBoss = false; Audio.play("click", 0.5)
                self.cfgSpawn = sp                       -- jump straight into configuring it
            end, { color = asBoss and P.gold or P.teal, font = fonts(self).small })
            bx = bx + bw + 8
            if bx + bw > mx + mw - 20 then bx = mx + 24; by = by + 36 end
        end
        return by + 50
    end
    local gy = my + 70
    if self.pickerBoss then
        gy = addRow("BOSSES (each gets its own stacked health bar)", Campaign.BOSSES, gy)
        -- the joke: crown ANY enemy as a boss, health bar and all (a Drifter boss!)
        addRow("JOKE - any enemy as a boss", Campaign.REGULAR, gy, true)
    else
        gy = addRow("REGULAR", Campaign.REGULAR, gy)
        addRow("MINES & HAZARDS", { "mine" }, gy)
    end
    -- close
    love.graphics.setColor(P.textDim); love.graphics.setLineWidth(3)
    love.graphics.line(mx + mw - 34, my + 16, mx + mw - 20, my + 30); love.graphics.line(mx + mw - 20, my + 16, mx + mw - 34, my + 30)
    self:reg(mx + mw - 38, my + 12, 30, 30, function() self.pickerOpen = false; self.pickerBoss = false end)
end

return UI
