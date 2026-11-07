-- LutroFX IDE configuration.
-- Lutro reads lutro.conf; desktop LÖVE (handy for testing) reads love.conf.
-- Lutro sets `love = lutro`, so we check for `lutro` first.

if lutro then
  function lutro.conf(t)
    t.width  = 320   -- the Miyoo shows this doubled to 640x480
    t.height = 240
  end
else
  function love.conf(t)
    t.identity      = "lutrofx"
    t.window.title  = "LutroFX IDE"
    t.window.width  = 640           -- main.lua draws everything at 2x on desktop
    t.window.height = 480
  end
end
