-- Tiny immediate-mode UI: call ui.button() while drawing, it draws itself and
-- returns true on the frame it gets clicked.

local gfx   = require("lib.gfx")
local input = require("lib.input")

local ui = {}

-- opt.on = highlighted, opt.col = accent colour, opt.off = disabled
function ui.button(x, y, w, h, label, opt)
  opt = opt or {}
  local col   = opt.col or gfx.ACCENT2
  local hover = input.over(x, y, w, h) and not opt.off
  local clicked = hover and input.takeClick()

  if opt.on then
    gfx.color(col[1] * 0.25, col[2] * 0.25, col[3] * 0.25)
  elseif hover then
    gfx.setc(gfx.PANEL2)
  else
    gfx.setc(gfx.PANEL)
  end
  gfx.rect(x, y, w, h)
  if opt.off then gfx.setc(gfx.BORDER)
  elseif opt.on or hover then gfx.setc(col)
  else gfx.setc(gfx.BORDER) end
  gfx.box(x, y, w, h)

  if opt.off then gfx.setc(gfx.DIM)
  elseif opt.on then gfx.setc(col)
  else gfx.setc(hover and gfx.TEXT or gfx.DIM) end
  gfx.textCentered(label, x, y + math.floor((h - 5) / 2), w, 1)
  return clicked
end

function ui.label(s, x, y, col)
  gfx.setc(col or gfx.DIM)
  gfx.text(s, x, y, 1)
end

-- Two-tap confirm for destructive buttons: first click arms (label changes),
-- second click within ~2s fires.
local armed, armedAt = nil, 0
local frame = 0
function ui.tick() frame = frame + 1 end

function ui.confirmButton(id, x, y, w, h, label, opt)
  opt = opt or {}
  local isArmed = armed == id and frame - armedAt < 120
  local o = {col = gfx.WARN, on = isArmed, off = opt.off}
  if ui.button(x, y, w, h, isArmed and "SURE?" or label, o) then
    if isArmed then armed = nil; return true end
    armed, armedAt = id, frame
  end
  return false
end

return ui
