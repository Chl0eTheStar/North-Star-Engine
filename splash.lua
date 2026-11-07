-- Opening splash: NORTH STAR ENGINE types itself out, a star pings above it,
-- then PRESS START opens the editor. A press during the typing skips ahead.

local gfx   = require("lib.gfx")
local input = require("lib.input")

local splash = {active = true}

local TITLE      = "NORTH STAR ENGINE"
local SCALE      = 2
local TYPE_EVERY = 0.09                       -- seconds per letter
local TYPED_AT   = #TITLE * TYPE_EVERY        -- when the last letter lands
local PING_AT    = TYPED_AT + 0.3             -- the star pings after a short pause
local PING_LEN   = 0.6                        -- how long the ping ring takes
local READY_AT   = PING_AT + PING_LEN + 0.3   -- then PRESS START blinks

local TITLE_Y = 104
local STAR_X, STAR_Y = 160, TITLE_Y - 26      -- where the star sits above the title

-- a twinkle, 9x7 pixels, drawn bigger when it grows
local SPARK = {
  "....#....",
  "....#....",
  "...###...",
  "#########",
  "...###...",
  "....#....",
  "....#....",
}

local t = 0

-- Press start (or A) to skip, and again to open the editor
function splash.update(dt)
  t = t + dt
  if input.pressed.start or input.pressed.a then
    if t >= READY_AT then
      splash.active = false
    else
      t = READY_AT
    end
  end
end

local function drawPing(p)            -- p: seconds since the ping began
  -- the star grows from a single pixel to double size
  local s = (p < 0.15) and 1 or 2
  local x0, y0 = STAR_X - 4 * s, STAR_Y - 3 * s
  gfx.setc(gfx.WARN)
  for r = 1, #SPARK do
    local row = SPARK[r]
    for c = 1, #row do
      if row:sub(c, c) == "#" then gfx.rect(x0 + (c - 1) * s, y0 + (r - 1) * s, s, s) end
    end
  end
  -- a ring of dots spreads out from the star and fades
  local k = math.min(1, p / PING_LEN)
  local radius = 6 + k * 22
  gfx.setc(gfx.DIM)
  for i = 0, 15 do
    local a = i / 16 * math.pi * 2
    gfx.rect(math.floor(STAR_X + math.cos(a) * radius), math.floor(STAR_Y + math.sin(a) * radius), 1, 1)
  end
end

function splash.draw()
  gfx.setc(gfx.BG)
  gfx.rect(0, 0, 320, 240)

  -- the title, typed out one letter at a time (the width is fixed so nothing shifts)
  local count = math.min(#TITLE, math.floor(t / TYPE_EVERY) + 1)
  local typed = TITLE:sub(1, count)
  local x = math.floor((320 - gfx.textWidth(TITLE, SCALE)) / 2)
  gfx.setc(gfx.ACCENT)
  gfx.text(typed, x, TITLE_Y, SCALE)
  if count < #TITLE and math.floor(t * 6) % 2 == 0 then      -- typing cursor
    gfx.rect(x + gfx.textWidth(typed, SCALE) + 2 * SCALE, TITLE_Y, 2 * SCALE, 5 * SCALE)
  end

  if t >= PING_AT then drawPing(t - PING_AT) end

  if t >= READY_AT and math.floor(t * 2) % 2 == 0 then
    gfx.setc(gfx.TEXT)
    gfx.textCentered("PRESS START", 0, 170, 320, 1)
  end
end

return splash
