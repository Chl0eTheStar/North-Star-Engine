-- Drawing helpers that work the same on Lutro and on desktop LÖVE.
--
-- Lutro facts this file is built around:
--   * setColor takes 0-255 INTEGERS (LÖVE 11 wants 0-1), so all colour goes
--     through gfx.color().
--   * There is no built-in font (print errors without one), so text is drawn
--     with our own 3x5 pixel font made of rectangles.
--   * draw() ignores scale unless Lutro was built with transforms, so every
--     sprite is pre-rendered into a Canvas at each size we need and cached.
--   * Canvas pixels that were never drawn have alpha 0 and are skipped when the
--     canvas is drawn, which gives us free transparency.

local gfx = {}

local G  = lutro or love
local lg = G.graphics
gfx.IS_LUTRO = (lutro ~= nil)

local floor = math.floor

-- ── colour + shapes ─────────────────────────────────────────────────────
function gfx.color(r, g, b, a)
  a = a or 255
  if gfx.IS_LUTRO then
    lg.setColor(floor(r), floor(g), floor(b), floor(a))
  else
    lg.setColor(r / 255, g / 255, b / 255, a / 255)
  end
end

function gfx.setc(c) gfx.color(c[1], c[2], c[3], c[4]) end

function gfx.rect(x, y, w, h)
  if w > 0 and h > 0 then
    lg.rectangle("fill", floor(x), floor(y), floor(w), floor(h))
  end
end

-- 1px outline built from fills (Lutro's "line" rectangles come out 1px bigger)
function gfx.box(x, y, w, h)
  gfx.rect(x, y, w, 1)
  gfx.rect(x, y + h - 1, w, 1)
  gfx.rect(x, y, 1, h)
  gfx.rect(x + w - 1, y, 1, h)
end

function gfx.clip(x, y, w, h)
  if x then lg.setScissor(floor(x), floor(y), floor(w), floor(h))
  else lg.setScissor() end
end

-- ── 3x5 pixel font ──────────────────────────────────────────────────────
local GLYPHS = {
  A={".#.","#.#","###","#.#","#.#"}, B={"##.","#.#","##.","#.#","##."},
  C={".##","#..","#..","#..",".##"}, D={"##.","#.#","#.#","#.#","##."},
  E={"###","#..","##.","#..","###"}, F={"###","#..","##.","#..","#.."},
  G={".##","#..","#.#","#.#",".##"}, H={"#.#","#.#","###","#.#","#.#"},
  I={"###",".#.",".#.",".#.","###"}, J={"..#","..#","..#","#.#",".#."},
  K={"#.#","#.#","##.","#.#","#.#"}, L={"#..","#..","#..","#..","###"},
  M={"#.#","###","###","#.#","#.#"}, N={"##.","#.#","#.#","#.#","#.#"},
  O={".#.","#.#","#.#","#.#",".#."}, P={"##.","#.#","##.","#..","#.."},
  Q={".#.","#.#","#.#","##.",".##"}, R={"##.","#.#","##.","#.#","#.#"},
  S={".##","#..",".#.","..#","##."}, T={"###",".#.",".#.",".#.",".#."},
  U={"#.#","#.#","#.#","#.#","###"}, V={"#.#","#.#","#.#","#.#",".#."},
  W={"#.#","#.#","###","###","#.#"}, X={"#.#","#.#",".#.","#.#","#.#"},
  Y={"#.#","#.#",".#.",".#.",".#."}, Z={"###","..#",".#.","#..","###"},
  ["0"]={"###","#.#","#.#","#.#","###"}, ["1"]={".#.","##.",".#.",".#.","###"},
  ["2"]={"##.","..#",".#.","#..","###"}, ["3"]={"##.","..#",".#.","..#","##."},
  ["4"]={"#.#","#.#","###","..#","..#"}, ["5"]={"###","#..","##.","..#","##."},
  ["6"]={".##","#..","###","#.#","###"}, ["7"]={"###","..#",".#.",".#.",".#."},
  ["8"]={"###","#.#","###","#.#","###"}, ["9"]={"###","#.#","###","..#","##."},
  ["."]={"...","...","...","...",".#."}, [","]={"...","...","...",".#.","#.."},
  [":"]={"...",".#.","...",".#.","..."}, ["-"]={"...","...","###","...","..."},
  ["+"]={"...",".#.","###",".#.","..."}, ["/"]={"..#","..#",".#.","#..","#.."},
  ["!"]={".#.",".#.",".#.","...",".#."}, ["?"]={"##.","..#",".#.","...",".#."},
  ["<"]={"..#",".#.","#..",".#.","..#"}, [">"]={"#..",".#.","..#",".#.","#.."},
  ["("]={".#.","#..","#..","#..",".#."}, [")"]={".#.","..#","..#","..#",".#."},
  ["'"]={".#.",".#.","...","...","..."}, ["="]={"...","###","...","###","..."},
  ["_"]={"...","...","...","...","###"}, ["#"]={"#.#","###","#.#","###","#.#"},
  ["*"]={"...","#.#",".#.","#.#","..."}, ["%"]={"#.#","..#",".#.","#..","#.#"},
  ["["]={"##.","#..","#..","#..","##."}, ["]"]={".##","..#","..#","..#",".##"},
  ["^"]={".#.","#.#","...","...","..."}, ["\""]={"#.#","#.#","...","...","..."},
}

-- Turn each glyph into horizontal runs so a letter is 1-5 rectangles
local RUNS = {}
for ch, rows in pairs(GLYPHS) do
  local runs = {}
  for y = 1, 5 do
    local row, x = rows[y], 1
    while x <= 3 do
      if row:sub(x, x) == "#" then
        local s = x
        while x <= 3 and row:sub(x, x) == "#" do x = x + 1 end
        runs[#runs + 1] = {s - 1, y - 1, x - s}
      else
        x = x + 1
      end
    end
  end
  RUNS[ch] = runs
end

-- Width in pixels of a string at a given scale
function gfx.textWidth(s, scale)
  scale = scale or 1
  local n = #s
  if n == 0 then return 0 end
  return (n * 4 - 1) * scale
end

function gfx.text(s, x, y, scale)
  scale = scale or 1
  s = string.upper(tostring(s))
  local cx = floor(x)
  y = floor(y)
  for i = 1, #s do
    local runs = RUNS[s:sub(i, i)]
    if runs then
      for r = 1, #runs do
        local run = runs[r]
        lg.rectangle("fill", cx + run[1] * scale, y + run[2] * scale, run[3] * scale, scale)
      end
    end
    cx = cx + 4 * scale
  end
end

function gfx.textCentered(s, x, y, w, scale)
  gfx.text(s, x + floor((w - gfx.textWidth(string.upper(s), scale)) / 2), y, scale)
end

-- Word-wrap text into lines of at most `width` characters. "\n" starts a
-- new line; a word longer than a line is cut. Returns the lines plus, for
-- each line, the index in `s` where it starts (for drawing a caret).
function gfx.wrap(s, width)
  local lines, starts = {}, {}
  local i, n = 1, #s
  if n == 0 then return {""}, {1} end
  while i <= n do
    local nl = s:find("\n", i, true)
    local stop = nl or (n + 1)                  -- end of this paragraph
    if stop - i <= width then
      lines[#lines + 1], starts[#starts + 1] = s:sub(i, stop - 1), i
      i = stop + 1
      if nl and i > n then lines[#lines + 1], starts[#starts + 1] = "", i end
    else
      -- break at the last space that fits, else cut the word
      local cut = i + width
      local sp
      for j = cut, i + 1, -1 do if s:sub(j, j) == " " then sp = j; break end end
      if sp then
        lines[#lines + 1], starts[#starts + 1] = s:sub(i, sp - 1), i
        i = sp + 1
      else
        lines[#lines + 1], starts[#starts + 1] = s:sub(i, cut - 1), i
        i = cut
      end
    end
  end
  return lines, starts
end

-- Which characters the pixel font can draw (everything else is skipped)
function gfx.hasGlyph(ch) return ch == " " or RUNS[string.upper(ch)] ~= nil end

-- ── sprite canvases ─────────────────────────────────────────────────────
-- cache[spriteTable][key] = canvas. Keys are weak so deleted sprites vanish.
local cache = setmetatable({}, {__mode = "k"})

function gfx.invalidate(spr) cache[spr] = nil end
function gfx.invalidateAll() cache = setmetatable({}, {__mode = "k"}) end

local function sprCache(spr)
  local c = cache[spr]
  if not c then c = {}; cache[spr] = c end
  return c
end

-- Remember a per-sprite value until the sprite is edited (e.g. which
-- animation to show on the map), so it isn't recomputed every frame.
function gfx.memo(spr, key, fn, arg)
  local c = sprCache(spr)
  local k = "m:" .. key
  local v = c[k]
  if v == nil then v = fn(spr, arg) or false; c[k] = v end
  return v
end

local function frameOf(spr, ai, fi)
  local a = spr.anims[ai] or spr.anims[1]
  return a.frames[fi] or a.frames[1]
end
gfx.frameOf = frameOf

-- True when a frame has no pixels drawn (shown as a placeholder in the editors)
function gfx.isBlank(spr, ai, fi)
  local c = sprCache(spr)
  local key = "blank" .. ai .. ":" .. fi
  if c[key] == nil then
    local f = frameOf(spr, ai, fi)
    local blank = true
    for i = 1, #f do if f[i] ~= 0 then blank = false; break end end
    c[key] = blank
  end
  return c[key]
end

-- Pixels hold a palette index: 0 = transparent, 1..16 = gfx.PALETTE colors.
-- `shade` scales brightness (1 = true colors, 0.5 = half as bright: used for
-- dimmed layers and the parallax background).
local function buildCanvas(spr, ai, fi, scale, shade, flip)
  local sz = spr.size
  local f  = frameOf(spr, ai, fi)
  local cv = lg.newCanvas(sz * scale, sz * scale)

  -- On desktop LÖVE a scissor would clip drawing into the canvas
  local sx, sy, sw, sh
  if not gfx.IS_LUTRO then sx, sy, sw, sh = lg.getScissor(); lg.setScissor() end

  lg.setCanvas(cv)
  if not gfx.IS_LUTRO then lg.clear(0, 0, 0, 0) end
  local pal = gfx.PALETTE
  for y = 0, sz - 1 do
    local row = y * sz
    local x = 0
    while x < sz do
      local src = flip and (sz - 1 - x) or x
      local v = f[row + src + 1]
      if v ~= 0 then
        -- one rectangle per run of same-colored pixels
        local s = x
        repeat
          x = x + 1
          src = flip and (sz - 1 - x) or x
        until x >= sz or f[row + src + 1] ~= v
        local c = pal[v] or gfx.WHITE
        gfx.color(c[1] * shade, c[2] * shade, c[3] * shade)
        lg.rectangle("fill", s * scale, y * scale, (x - s) * scale, scale)
      else
        x = x + 1
      end
    end
  end
  lg.setCanvas()

  if not gfx.IS_LUTRO and sx then lg.setScissor(sx, sy, sw, sh) end
  return cv
end

-- Draw frame `fi` of animation `ai` at (x,y), `scale` screen pixels per sprite
-- pixel, in its own colors (`shade` < 1 draws it darker).
function gfx.sprite(spr, ai, fi, x, y, scale, shade, flip)
  if not spr then return end
  ai = ai or 1
  fi = fi or 1
  scale = scale or 1
  shade = shade or 1
  local c = sprCache(spr)
  local key = ai .. ":" .. fi .. ":" .. scale .. ":" .. shade .. (flip and "f" or "")
  local cv = c[key]
  if not cv then
    cv = buildCanvas(spr, ai, fi, scale, shade, flip)
    c[key] = cv
  end
  if not gfx.IS_LUTRO then lg.setColor(1, 1, 1, 1) end
  lg.draw(cv, floor(x), floor(y))
end

-- ── sprite palette (16 colors; index 0 in a frame = transparent) ─────────
gfx.PALETTE = {
  {0x00, 0x00, 0x00}, {0x57, 0x57, 0x57}, {0xa0, 0xa0, 0xa0}, {0xff, 0xff, 0xff},
  {0x2a, 0x4b, 0xd7}, {0x1d, 0x69, 0x14}, {0x81, 0x4a, 0x19}, {0x81, 0x26, 0xc0},
  {0x9d, 0xaf, 0xff}, {0x81, 0xc5, 0x7a}, {0xe9, 0xde, 0xbb}, {0xad, 0x23, 0x23},
  {0x29, 0xd0, 0xd0}, {0xff, 0xee, 0x33}, {0xff, 0x92, 0x33}, {0xff, 0xcd, 0xf3},
}

-- ── UI colors ─────────────────────────────────────────────────────────────
gfx.WHITE  = {255, 255, 255}
gfx.BLACK  = {0, 0, 0}
gfx.BG     = {11, 13, 18}
gfx.PANEL  = {16, 20, 28}
gfx.PANEL2 = {22, 28, 38}
gfx.BORDER = {30, 39, 56}
gfx.TEXT   = {200, 214, 229}
gfx.DIM    = {74, 90, 112}
gfx.ACCENT = {0, 255, 136}
gfx.ACCENT2= {0, 204, 255}
gfx.WARN   = {255, 107, 53}
gfx.PURPLE = {192, 132, 252}

return gfx
