function love.conf(t)
    -- The LÖVE save directory name. Keep stable forever — changing it orphans
    -- every player's save (progress, $Things, unlocks).
    t.identity = "squidlite"
    t.version  = "11.5"
    t.console  = false

    t.window.title     = "Squidlite"
    -- 16:9 logical resolution. main.lua scales internally with letterboxing
    -- (black bars) so nothing is ever stretched, in windowed or fullscreen.
    t.window.width     = 1280
    t.window.height    = 720
    t.window.resizable = true
    t.window.vsync     = 1
    t.window.msaa      = 0
    t.window.highdpi   = true
    t.window.minwidth  = 640
    t.window.minheight = 360

    t.modules.video  = false
    t.modules.thread = false
end
