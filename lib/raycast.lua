-- First-person view for "raycast" games (Doom-style).
--
-- The map is the same grid as always. A cell with wall pieces in it is a wall
-- as tall as its stack: each piece is one cell of height, drawn with its
-- sprite's own pixels on its face, so a tree is a trunk with leaves on top.
-- Everything else in a cell (monsters, coins, the goal...) stands in the cell
-- as a flat sprite that always faces you, hidden behind nearer walls.
--
-- Drawn in a 160x120 view at 2x, one thin column per ray. Rows are drawn as
-- runs of same-colored pixels, so a flat-colored wall costs one rectangle.

local gfx     = require("lib.gfx")
local project = require("lib.project")

local RC = {}

local floor, cos, sin, abs, huge = math.floor, math.cos, math.sin, math.abs, math.huge

local COLS, ROWS, SCALE = 160, 120, 2
local HOR      = 60      -- horizon row
local CAM_Z    = 0.5     -- eye height, in cells
local PROJ     = 120     -- rows a one-cell-tall wall takes at distance 1
local FOV      = 0.66    -- camera plane length (about 66 degrees)
local FOG      = 9       -- distance (cells) where walls fade to 20% brightness
local SIDE     = 0.7     -- faces turned to the side are a bit darker
local BILL_H   = 0.8     -- billboard height, in cells
local MAX_STEP = 160     -- ray steps before a ray gives up (a very long view)

RC.CEIL  = {28, 26, 44}
RC.FLOOR = {46, 36, 30}

local PAL = gfx.PALETTE

-- Fallback wall for rays that leave the map: one plain-colored piece
local FALLBACK = {{size = 1, px = {0}, blank = true, avg = {70, 70, 96}}}

-- The pixels of one frame of a sprite, ready to sample. avg is the sprite's
-- average color, shown where a wall's sprite is transparent.
local function frameTexture(spr, fi)
  local ta = gfx.memo(spr, "thumb", project.thumbAnim)
  local anim = spr.anims[ta] or spr.anims[1]
  local f = anim.frames[fi] or anim.frames[1]
  local r, g, b, n, blank = 0, 0, 0, 0, true
  for i = 1, #f do
    local v = f[i]
    if v ~= 0 then
      local c = PAL[v] or gfx.WHITE
      r, g, b, n, blank = r + c[1], g + c[2], b + c[3], n + 1, false
    end
  end
  local avg = (n > 0) and {r / n, g / n, b / n} or {128, 128, 128}
  return {size = spr.size, px = f, blank = blank, avg = avg}
end

-- Cached on the sprite (gfx.invalidate clears it when the sprite is edited)
local function texOf(spr, fi)
  return gfx.memo(spr, "rc" .. fi, frameTexture, fi)
end

local function box(x, y, w, h)
  gfx.rect(x * SCALE, y * SCALE, w * SCALE, h * SCALE)
end

-- Color of palette index v (0 = clear, which uses the average color) at
-- brightness k, as r,g,b
local function colorOf(tex, v, k)
  local c = (v == 0) and tex.avg or (PAL[v] or gfx.WHITE)
  return floor(c[1] * k), floor(c[2] * k), floor(c[3] * k)
end

-- One wall piece on one column: texel rows run from `top` to `bot` (screen
-- rows, may be off the view), sampled at texel column tx. Same-colored texel
-- rows are merged into one rectangle.
local function drawFace(tex, tx, top, bot, col, k)
  local n, px = tex.size, tex.px
  local hh = (bot - top) / n
  local runV, runStart = nil, 0
  for j = 0, n do
    local v
    if j < n then v = px[j * n + tx + 1] or 0 end
    if j == n or v ~= runV then
      if runV ~= nil then
        local y0 = math.max(0, floor(top + runStart * hh))
        local y1 = math.min(ROWS, floor(top + j * hh))
        if y1 > y0 then
          gfx.color(colorOf(tex, runV, k))
          gfx.rect(col * SCALE, y0 * SCALE, SCALE, (y1 - y0) * SCALE)
        end
      end
      runStart, runV = j, v
    end
  end
end

-- A flat sprite standing in its cell, facing the camera. tx is how far it is
-- to the right of the view centre, tz how far ahead it is.
local function drawBillboard(e, tx, tz, t, zbuf)
  local spr = e.spr
  local ta = gfx.memo(spr, "thumb", project.thumbAnim)
  local frames = #spr.anims[ta].frames
  local fi = floor(t / 10) % frames + 1
  local tex = texOf(spr, fi)
  local lineH = PROJ / tz
  local h = BILL_H * lineH                       -- on screen: square, in view rows
  local bot = HOR + CAM_Z * lineH
  local top = bot - h
  local x0 = COLS / 2 * (1 + tx / tz) - h / 2
  local k = 1 - tz / FOG
  if k < 0.2 then k = 0.2 end

  if tex.blank then
    if e.kind == "text" then return end           -- invisible trigger
    -- no art yet: a block in the kind's color, so it can still be seen
    local c = project.KIND_COLOR[e.kind] or gfx.WHITE
    local cx = floor(x0 + h / 2)
    if cx < 0 or cx >= COLS or tz >= (zbuf[cx] or huge) then return end
    local s = h * 0.5
    gfx.color(floor(c[1] * k), floor(c[2] * k), floor(c[3] * k))
    box(cx - floor(s / 2), floor(bot - s), math.max(1, floor(s)), math.max(1, floor(s)))
    return
  end

  local size, px = tex.size, tex.px
  local sw, hh = h / size, h / size
  for sx = 0, size - 1 do
    local c0 = floor(x0 + sx * sw)
    local c1 = floor(x0 + (sx + 1) * sw)
    if c1 <= c0 then c1 = c0 + 1 end
    local ca, cb = math.max(0, c0), math.min(COLS, c1)
    -- skip the strip if a nearer wall covers it
    if cb > ca and tz < (zbuf[ca] or huge) then
      local runV, runStart = nil, 0
      for j = 0, size do
        local v
        if j < size then v = px[j * size + sx + 1] or 0 end
        if j == size or v ~= runV then
          if runV ~= nil and runV ~= 0 then
            local y0 = math.max(0, floor(top + runStart * hh))
            local y1 = math.min(ROWS, floor(top + j * hh))
            if y1 > y0 then
              local c = PAL[runV] or gfx.WHITE
              gfx.color(floor(c[1] * k), floor(c[2] * k), floor(c[3] * k))
              box(ca, y0, cb - ca, y1 - y0)
            end
          end
          runStart, runV = j, v
        end
      end
    end
  end
end

-- Where a world point (wx, wy) at height z lands on screen. Returns the
-- logical screen x and y, its depth tz and its sideways offset tx; nil when
-- the point is behind you. Shared with the play code (shots, melee).
function RC.project(rc, wx, wy, z)
  local a = rc.a
  local dx, dy = cos(a), sin(a)
  local plx, ply = -dy * FOV, dx * FOV
  local sx, sy = wx - rc.x, wy - rc.y
  local inv = 1 / (plx * dy - dx * ply)
  local tx = inv * (dy * sx - dx * sy)
  local tz = inv * (-ply * sx + plx * sy)
  if tz <= 0.05 then return nil end
  return COLS / 2 * (1 + tx / tz), HOR + (CAM_Z - z) * PROJ / tz, tz, tx
end

-- A flat decal lying on the floor (z = 0) or the ceiling (z = 1 cell): each
-- texel is projected as a quad, so it foreshortens like the floor does.
-- Same-colored texels in a row merge into one rectangle.
local function drawDecal(e, rc, t, z)
  local spr = e.spr
  local ta = gfx.memo(spr, "thumb", project.thumbAnim)
  local frames = #spr.anims[ta].frames
  local tex = texOf(spr, floor(t / 10) % frames + 1)
  if tex.blank then return end
  local n = tex.size
  local SX, SY, TZ = {}, {}, {}
  local stride = n + 1
  for v = 0, n do
    for u = 0, n do
      local sx, sy, tz = RC.project(rc, e.cx - 0.5 + u / n, e.cy - 0.5 + v / n, z)
      if not sx then return end                  -- partly behind you: skip it this frame
      local k = v * stride + u + 1
      SX[k], SY[k], TZ[k] = sx, sy, tz
    end
  end
  local px, zbuf = tex.px, rc.zbuf
  for v = 0, n - 1 do
    local u = 0
    while u < n do
      local val = px[v * n + u + 1] or 0
      if val == 0 then
        u = u + 1
      else
        local u0 = u
        while u < n and (px[v * n + u + 1] or 0) == val do u = u + 1 end
        -- the run covers texels u0 .. u-1; its four corners bound it on screen
        local c1, c2 = v * stride + u0 + 1, v * stride + u + 1
        local c3, c4 = (v + 1) * stride + u0 + 1, (v + 1) * stride + u + 1
        local x0 = math.min(SX[c1], SX[c2], SX[c3], SX[c4])
        local x1 = math.max(SX[c1], SX[c2], SX[c3], SX[c4])
        local y0 = math.min(SY[c1], SY[c2], SY[c3], SY[c4])
        local y1 = math.max(SY[c1], SY[c2], SY[c3], SY[c4])
        local tz = (TZ[c1] + TZ[c2] + TZ[c3] + TZ[c4]) / 4
        local cx = floor((x0 + x1) / 2)
        if cx >= 0 and cx < COLS and tz < (zbuf[cx] or huge) then
          local k = 1 - tz / FOG
          if k < 0.2 then k = 0.2 end
          local c = PAL[val] or gfx.WHITE
          gfx.color(floor(c[1] * k), floor(c[2] * k), floor(c[3] * k))
          local bx0, by0 = math.max(0, floor(x0)), math.max(0, floor(y0))
          local bx1, by1 = math.min(COLS, math.ceil(x1)), math.min(ROWS, math.ceil(y1))
          if bx1 > bx0 and by1 > by0 then box(bx0, by0, bx1 - bx0, by1 - by0) end
        end
      end
    end
  end
end

-- rc: {W, H, x, y, a (angle; 0 = east, pi/2 = south), walls[i] = pieces
--      bottom first (sprites), ents (list with spr, cx, cy, alive), zbuf}
-- t: the frame counter, for animation
function RC.draw(rc, t)
  local px, py, a = rc.x, rc.y, rc.a
  local dx, dy = cos(a), sin(a)
  local plx, ply = -dy * FOV, dx * FOV       -- camera plane, to the right of view
  local W, H, walls, zbuf = rc.W, rc.H, rc.walls, rc.zbuf

  gfx.setc(RC.CEIL);  box(0, 0, COLS, HOR)
  gfx.setc(RC.FLOOR); box(0, HOR, COLS, ROWS - HOR)

  for col = 0, COLS - 1 do
    local camx = 2 * col / COLS - 1
    local rdx, rdy = dx + plx * camx, dy + ply * camx

    -- DDA: step from cell to cell until a ray meets a wall
    local mx, my = floor(px), floor(py)
    local ddx = (rdx ~= 0) and abs(1 / rdx) or huge
    local ddy = (rdy ~= 0) and abs(1 / rdy) or huge
    local stx, sty, sdx, sdy
    if rdx < 0 then stx = -1; sdx = (px - mx) * ddx else stx = 1; sdx = (mx + 1 - px) * ddx end
    if rdy < 0 then sty = -1; sdy = (py - my) * ddy else sty = 1; sdy = (my + 1 - py) * ddy end
    local side, pieces = 0, nil
    for _ = 1, MAX_STEP do
      if sdx < sdy then sdx = sdx + ddx; mx = mx + stx; side = 0
      else sdy = sdy + ddy; my = my + sty; side = 1 end
      if mx < 0 or my < 0 or mx >= W or my >= H then pieces = FALLBACK; break end
      pieces = walls[my * W + mx + 1]
      if pieces then break end
    end
    pieces = pieces or FALLBACK

    local dist
    if side == 0 then dist = (mx - px + (1 - stx) / 2) / rdx
    else dist = (my - py + (1 - sty) / 2) / rdy end
    if dist < 0.05 then dist = 0.05 end
    zbuf[col] = dist

    -- where on the wall the ray hit (0..1 across the face), for the texture column
    local wx
    if side == 0 then wx = py + dist * rdy else wx = px + dist * rdx end
    wx = wx - floor(wx)

    local lineH = PROJ / dist
    local k = 1 - dist / FOG
    if k < 0.2 then k = 0.2 end
    if side == 1 then k = k * SIDE end

    for lvl = 1, #pieces do
      local spr = pieces[lvl]
      local tex = spr.px and spr or texOf(spr, 1)
      -- piece lvl sits from lvl-1 to lvl cells above the floor
      local top = HOR + (CAM_Z - lvl) * lineH
      local bot = HOR + (CAM_Z - (lvl - 1)) * lineH
      if bot > 0 and top < ROWS then
        local n = tex.size
        local tx = floor(wx * n)
        if tx >= n then tx = n - 1 end
        if (side == 0 and rdx > 0) or (side == 1 and rdy < 0) then tx = n - 1 - tx end
        drawFace(tex, tx, top, bot, col, k)
      end
    end
  end

  -- flat decals on the floor and the ceiling: under the billboards
  for _, e in ipairs(rc.ents) do
    if e.alive and e.spr then
      if e.kind == "floor" then drawDecal(e, rc, t, 0)
      elseif e.kind == "ceiling" then drawDecal(e, rc, t, 1) end
    end
  end

  -- billboards: far to near, each one checked against the walls in front of it
  local list = {}
  local inv_den
  for _, e in ipairs(rc.ents) do
    if e.alive and e.spr and e.kind ~= "floor" and e.kind ~= "ceiling" then
      local sx, sy = e.cx - px, e.cy - py
      inv_den = 1 / (plx * dy - dx * ply)
      local tx = inv_den * (dy * sx - dx * sy)
      local tz = inv_den * (-ply * sx + plx * sy)
      if tz > 0.2 then list[#list + 1] = {e = e, tx = tx, tz = tz} end
    end
  end
  table.sort(list, function(p, q) return p.tz > q.tz end)
  for _, b in ipairs(list) do drawBillboard(b.e, b.tx, b.tz, t, zbuf) end
end

return RC
