-- On-screen keyboard, full screen, for typing with a d-pad (or a mouse).
--
--   keyboard.open(text, opts)   opts = {title, max, width, lines, onDone(text)}
--   keyboard.active             true while it's up (main.lua blocks tabs etc.)
--   keyboard.draw()             draws it and handles input; call every frame
--
-- D-pad moves the highlight, A types it, B deletes, Y types a space, X flips
-- letters/symbols, L/R move the text cursor, START is done, SELECT cancels.
-- The preview wraps the text exactly like the in-game text box, with a line
-- marking where each new page starts.

local gfx   = require("lib.gfx")
local input = require("lib.input")

local K = {active = false}

local KW, KH, KGAP = 26, 18, 2           -- one key unit
local KX, KY = 6, 108                    -- top-left of the key grid

-- Each key: {label, value or action, width in units}. Rows add up to 11.
local function chars(str)
  local row = {}
  for i = 1, #str do local c = str:sub(i, i); row[#row + 1] = {c, c, 1} end
  return row
end
local function plus(row, key) row[#row + 1] = key; return row end

local BOTTOM = {{"SYM", "sym", 2}, {"SPACE", " ", 4}, {"ENTER", "\n", 2},
                {"<", "left", 1}, {">", "right", 1}, {"DONE", "done", 1}}
local PAGES = {
  letters = {
    plus(chars("1234567890"), {"DEL", "del", 1}),
    chars("QWERTYUIOP'"),
    chars("ASDFGHJKL!?"),
    chars("ZXCVBNM,.-:"),
    BOTTOM,
  },
  symbols = {
    plus(chars("1234567890"), {"DEL", "del", 1}),
    chars("()[]<>+=/*%"),
    chars("#\"_^'!?,.-:"),
    {{"CLEAR ALL TEXT", "clear", 11}},
    BOTTOM,
  },
}

local function keyRect(row, i)
  local x = KX
  for j = 1, i - 1 do x = x + row[j][3] * (KW + KGAP) end
  local w = row[i][3] * (KW + KGAP) - KGAP
  return x, w
end

local hold = {up = 0, down = 0, left = 0, right = 0}
local function repeatPress(d)
  if input.down[d] then hold[d] = hold[d] + 1 else hold[d] = 0 end
  local h = hold[d]
  return h == 1 or (h > 14 and h % 4 == 0)
end

function K.open(text, opts)
  K.active = true
  K.text = text or ""
  K.orig = K.text
  K.opts = opts or {}
  K.max = K.opts.max or 300
  K.width = K.opts.width or 74
  K.lines = K.opts.lines or 4
  K.caret = #K.text
  K.page = "letters"
  K.row, K.col = 2, 1
  K.blink = 0
  K.wasCursor = input.cursorOn
  input.cursorOn = false              -- the d-pad drives the highlight instead
  K.lastMX, K.lastMY = input.cx, input.cy
  input.pressBlocked = true           -- the press that opened it mustn't type
  for d in pairs(hold) do hold[d] = 1 end
end

local function close(save)
  K.active = false
  input.cursorOn = K.wasCursor
  input.pressBlocked = true
  input.consumed = true
  if save and K.opts.onDone then K.opts.onDone(K.text) end
end

local function insert(s)
  if #K.text + #s > K.max then return end
  K.text = K.text:sub(1, K.caret) .. s .. K.text:sub(K.caret + 1)
  K.caret = K.caret + #s
end

local function act(v)
  if v == nil then return end
  K.blink = 0
  if v == "del" then
    if K.caret > 0 then
      K.text = K.text:sub(1, K.caret - 1) .. K.text:sub(K.caret + 1)
      K.caret = K.caret - 1
    end
  elseif v == "left" then K.caret = math.max(0, K.caret - 1)
  elseif v == "right" then K.caret = math.min(#K.text, K.caret + 1)
  elseif v == "sym" then K.page = (K.page == "letters") and "symbols" or "letters"
  elseif v == "clear" then K.text, K.caret = "", 0
  elseif v == "done" then close(true)
  else insert(v) end
end

-- column in `toRow` whose key is closest to the middle of the current key
local function closestCol(fromRow, fromCol, toRow)
  local x, w = keyRect(fromRow, fromCol)
  local mid = x + w / 2
  local best, bestD = 1, 1e9
  for i = 1, #toRow do
    local kx, kw = keyRect(toRow, i)
    local d = math.abs(kx + kw / 2 - mid)
    if d < bestD then best, bestD = i, d end
  end
  return best
end

local function keyAt(px, py)
  local rows = PAGES[K.page]
  for r, row in ipairs(rows) do
    local y = KY + (r - 1) * (KH + KGAP)
    if py >= y and py < y + KH then
      for i = 1, #row do
        local x, w = keyRect(row, i)
        if px >= x and px < x + w then return r, i end
      end
    end
  end
  return nil
end

local function handleInput()
  local rows = PAGES[K.page]
  if K.row > #rows then K.row = #rows end
  if K.col > #rows[K.row] then K.col = #rows[K.row] end

  -- d-pad: move the highlight (wraps around)
  if repeatPress("left") then K.col = (K.col - 2) % #rows[K.row] + 1 end
  if repeatPress("right") then K.col = K.col % #rows[K.row] + 1 end
  if repeatPress("up") then
    local r = (K.row - 2) % #rows + 1
    K.col = closestCol(rows[K.row], K.col, rows[r]); K.row = r
  end
  if repeatPress("down") then
    local r = K.row % #rows + 1
    K.col = closestCol(rows[K.row], K.col, rows[r]); K.row = r
  end

  -- mouse: hovering a key highlights it, clicking types it
  local mouseMoved = input.cx ~= K.lastMX or input.cy ~= K.lastMY
  K.lastMX, K.lastMY = input.cx, input.cy
  if mouseMoved then
    local r, c = keyAt(input.cx, input.cy)
    if r then K.row, K.col = r, c end
  end

  if input.pressBlocked and not input.held then input.pressBlocked = false end
  if input.click and not input.pressBlocked then
    input.consumed, input.pressBlocked = true, true
    if input.down.a then
      act(rows[K.row][K.col][2])
    else
      local r, c = keyAt(input.cx, input.cy)
      if r then K.row, K.col = r, c; act(rows[r][c][2]) end
    end
  end
  if not K.active then return end
  if input.pressed.b then act("del") end
  if input.pressed.y then act(" ") end
  if input.pressed.x then act("sym") end
  if input.pressed.l then act("left") end
  if input.pressed.r then act("right") end
  if input.pressed.start then close(true)
  elseif input.pressed.select then K.text = K.orig; close(false) end
end

local function drawPreview()
  local bx, by, bw, bh = 6, 16, 308, 86
  gfx.setc(gfx.BLACK); gfx.rect(bx, by, bw, bh)
  gfx.setc(gfx.BORDER); gfx.box(bx, by, bw, bh)

  local lines, starts = gfx.wrap(K.text, K.width)
  -- which line the caret is on
  local cl, cc = 1, 0
  for i = 1, #lines do
    if starts[i] <= K.caret + 1 then cl, cc = i, K.caret + 1 - starts[i] end
  end
  if cc > #lines[cl] then cc = #lines[cl] end

  -- show up to 9 lines, scrolled so the caret is visible
  local VISIBLE = 9
  local first = math.max(1, cl - VISIBLE + 1)
  local tx, ty = bx + 6, by + 5
  for i = first, math.min(#lines, first + VISIBLE - 1) do
    local y = ty + (i - first) * 9
    if i > 1 and (i - 1) % K.lines == 0 then      -- a new text-box page starts here
      gfx.setc(gfx.BORDER); gfx.rect(bx + 2, y - 3, bw - 4, 1)
    end
    gfx.setc(gfx.WHITE); gfx.text(lines[i], tx, y)
    if i == cl and math.floor(K.blink / 20) % 2 == 0 then
      gfx.setc(gfx.ACCENT); gfx.rect(tx + cc * 4 - 1, y - 1, 1, 7)
    end
  end
  K.pages = math.ceil(#lines / K.lines)
  K.caretPage = math.floor((cl - 1) / K.lines) + 1
  if #K.text == 0 then
    gfx.setc(gfx.DIM); gfx.text("START TYPING...", tx + 4, ty)
  end
end

function K.draw()
  if not K.active then return end
  K.blink = K.blink + 1
  handleInput()
  if not K.active then return end

  gfx.setc(gfx.BG); gfx.rect(0, 0, 320, 240)
  gfx.setc(gfx.PANEL); gfx.rect(0, 0, 320, 13)
  gfx.setc(gfx.ACCENT); gfx.text(K.opts.title or "TYPE TEXT", 4, 4)
  local count = #K.text .. "/" .. K.max
  if (K.pages or 1) > 1 then count = "PAGE " .. K.caretPage .. "/" .. K.pages .. "   " .. count end
  gfx.setc(#K.text >= K.max and gfx.WARN or gfx.DIM)
  gfx.text(count, 316 - gfx.textWidth(count), 4)
  drawPreview()

  local rows = PAGES[K.page]
  for r, row in ipairs(rows) do
    local y = KY + (r - 1) * (KH + KGAP)
    for i, key in ipairs(row) do
      if key[2] ~= nil then
        local x, w = keyRect(row, i)
        local sel = (r == K.row and i == K.col)
        local special = #key[2] ~= 1 or key[2] == "\n" or key[2] == " "
        gfx.setc(sel and gfx.ACCENT or (special and gfx.PANEL2 or gfx.WHITE))
        gfx.rect(x, y, w, KH)
        gfx.setc(sel and gfx.BLACK or (special and gfx.TEXT or gfx.BLACK))
        local lab = key[1]
        if key[2] == "sym" then lab = (K.page == "letters") and "#+=" or "ABC" end
        gfx.textCentered(lab, x, y + 7, w, 1)
        if not sel then gfx.setc(gfx.BORDER); gfx.box(x, y, w, KH) end
      end
    end
  end

  gfx.setc(gfx.DIM)
  gfx.textCentered("A TYPE  B DEL  Y SPACE  X SYMBOLS  L/R MOVE  START DONE  SELECT CANCEL", 0, 230, 320, 1)
end

return K
