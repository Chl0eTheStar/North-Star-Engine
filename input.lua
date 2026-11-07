-- One input layer for gamepad, mouse and (on desktop) keyboard.
--
-- Buttons use RetroPad names: a b x y up down left right start select l r.
-- The editor cursor follows the real mouse whenever it moves; otherwise the
-- d-pad pushes a virtual cursor around. A / left mouse = "click" and draw,
-- B / right mouse = "alt" (erase).
--
-- Lutro has no mousepressed callback, so mouse clicks are found by comparing
-- isDown() with last frame. Gamepad presses arrive through gamepadpressed.

local input = {}

local G = lutro or love

local W, H = 320, 240
input.cx, input.cy = W / 2, H / 2      -- cursor position (screen pixels)
input.down     = {}                    -- held right now
input.pressed  = {}                    -- went down this frame
input.released = {}                    -- went up this frame
input.cursorOn = true                  -- false in play mode (d-pad drives the game)
input.mouseUsed = false
input.consumed = false                 -- a UI button already took this frame's click
input.pressBlocked = false             -- ...and stays blocked until released

local queueDown, queueUp = {}, {}

-- RetroPad button ids as Lutro reports them (RETRO_DEVICE_ID_JOYPAD_*)
local RETRO = {[0] = "b", "y", "select", "start", "up", "down", "left", "right",
               "a", "x", "l", "r", "l2", "r2", "l3", "r3"}
-- Desktop LÖVE gamepad names
local LOVEPAD = {a = "a", b = "b", x = "x", y = "y", dpup = "up", dpdown = "down",
                 dpleft = "left", dpright = "right", start = "start", back = "select",
                 leftshoulder = "l", rightshoulder = "r"}
-- Keyboard (desktop testing, or RetroArch keyboard)
local KEYS = {up = "up", down = "down", left = "left", right = "right",
              x = "a", z = "b", s = "x", a = "y", space = "a",
              ["return"] = "start", tab = "select", q = "l", w = "r", e = "l2", r = "r2"}

local function nameFrom(a, b)
  if type(a) == "number" then return RETRO[a] end
  if type(b) == "string" then return LOVEPAD[b] end
  return nil
end

function input.padPressed(a, b)  local n = nameFrom(a, b); if n then queueDown[#queueDown + 1] = n end end
function input.padReleased(a, b) local n = nameFrom(a, b); if n then queueUp[#queueUp + 1] = n end end
function input.keyPressed(k)  local n = KEYS[k]; if n then queueDown[#queueDown + 1] = n end end
function input.keyReleased(k) local n = KEYS[k]; if n then queueUp[#queueUp + 1] = n end end

-- Desktop LÖVE draws at 2x, so mouse coordinates are divided by this
input.mouseScale = 1

local lastMX, lastMY
local m1, m2 = false, false
local holdFrames = {up = 0, down = 0, left = 0, right = 0}

function input.update()
  input.pressed, input.released = {}, {}
  for i = 1, #queueDown do
    local n = queueDown[i]
    input.down[n] = true
    input.pressed[n] = true
  end
  for i = 1, #queueUp do
    local n = queueUp[i]
    input.down[n] = false
    input.released[n] = true
  end
  queueDown, queueUp = {}, {}
  input.consumed = false

  -- ── mouse ──
  local mx, my, n1, n2 = nil, nil, false, false
  if G.mouse then
    mx, my = G.mouse.getPosition()
    mx, my = mx / input.mouseScale, my / input.mouseScale
    n1 = G.mouse.isDown(1) and true or false
    n2 = G.mouse.isDown(2) and true or false
  end
  if mx and lastMX and (mx ~= lastMX or my ~= lastMY) then
    input.mouseUsed = true
    input.cx, input.cy = mx, my
  end
  lastMX, lastMY = mx, my

  -- ── d-pad cursor: 1px taps, speeds up while held ──
    -- (and L2/R2 + d-pad nudges sprite pixels in the sprite editor)
  if input.cursorOn and not input.down.x and not input.down.l2 and not input.down.r2 then
    local dx, dy = 0, 0
    for _, d in ipairs({"up", "down", "left", "right"}) do
      if input.down[d] then holdFrames[d] = holdFrames[d] + 1 else holdFrames[d] = 0 end
    end
    -- tap = 1px for precision, then it ramps up quickly while held
    local function spd(h)
      if h == 0 then return 0 end
      if h == 1 then return 1 end
      if h < 6 then return 0 end           -- short pause so single taps stay precise
      if h < 14 then return 2 end
      if h < 28 then return 3 end
      return 5
    end
    dx = spd(holdFrames.right) - spd(holdFrames.left)
    dy = spd(holdFrames.down) - spd(holdFrames.up)
    if dx ~= 0 or dy ~= 0 then
      input.cx = math.max(0, math.min(W - 1, input.cx + dx))
      input.cy = math.max(0, math.min(H - 1, input.cy + dy))
    end
  end

  -- ── click / alt: A or left mouse, B or right mouse ──
  local held = (input.down.a or n1) and true or false
  local alt  = (input.down.b or n2) and true or false
  input.click     = held and not input.held
  input.altClick  = alt and not input.altHeld
  input.unclick   = input.held and not held
  input.held, input.altHeld = held, alt
  -- a press that hit a button must not keep drawing after the screen changes
  if not held then input.pressBlocked = false end
  m1, m2 = n1, n2
end

function input.over(x, y, w, h)
  return input.cx >= x and input.cx < x + w and input.cy >= y and input.cy < y + h
end

-- A click that no UI button has claimed yet
function input.takeClick()
  if input.click and not input.consumed then
    input.consumed = true
    input.pressBlocked = true
    return true
  end
  return false
end

-- Pushing the cursor against an edge (used to scroll the map)
function input.edgePush(x, y, w, h, margin)
  margin = margin or 4
  local dx, dy = 0, 0
  if input.cx < x + margin then dx = -1 elseif input.cx >= x + w - margin then dx = 1 end
  if input.cy < y + margin then dy = -1 elseif input.cy >= y + h - margin then dy = 1 end
  return dx, dy
end

return input
