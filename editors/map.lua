-- MAP tab: paint your sprites onto a tile grid, one grid per scene.
-- A sprite's KIND decides what it does in play (wall, coin, enemy...).
--
-- Each scene has two layers: MAIN (the level itself) and BACK, a parallax
-- background that scrolls slower than the level. BACK is just pictures:
-- kinds don't matter there, so paint clouds, stars or hills with any sprite.
--
-- In RAYCAST games, walls (solid and breakable sprites) stack instead: each
-- click adds one piece on top of the cell (a tree: trunk, then leaves), and
-- right-click takes the top piece off. Other sprites paint the floor as usual.

local gfx     = require("lib.gfx")
local input   = require("lib.input")
local ui      = require("lib.ui")
local project = require("lib.project")
local app     = require("lib.app")

local floor = math.floor

local M = {
  sel = 1,          -- selected sprite (0 = eraser)
  palScroll = 0,
  camX = 0, camY = 0,
  zoom = 1,
  layer = "main",   -- "main" | "back": which layer you paint on
}

local VX, VY, VW, VH = 50, 16, 268, 207   -- map view
local PAL_ROWS = 8

local function scene()
  local P = app.P
  if app.scene > #P.scenes then app.scene = #P.scenes end
  if app.scene < 1 then app.scene = 1 end
  return P.scenes[app.scene]
end

local function clampCam(sc, ts)
  local maxX = math.max(0, sc.w * ts - VW)
  local maxY = math.max(0, sc.h * ts - VH)
  M.camX = math.max(0, math.min(maxX, M.camX))
  M.camY = math.max(0, math.min(maxY, M.camY))
end

local function setTile(sc, tx, ty, v)
  local i = ty * sc.w + tx + 1
  if M.layer == "back" then
    if sc.bg[i] ~= v then sc.bg[i] = v; app.changed() end
    return
  end
  if sc.tiles[i] == v then return end
  -- only one player start per scene: placing one moves it
  if v > 0 then
    local spr = app.P.sprites[v]
    if spr and spr.kind == "player" then
      for t = 1, #sc.tiles do
        local o = app.P.sprites[sc.tiles[t]]
        if o and o.kind == "player" then sc.tiles[t] = 0 end
      end
    end
  end
  sc.tiles[i] = v
  app.changed()
end

-- Raycast painting: one stack action per cell per press, so dragging paints
-- each cell once instead of stacking every frame
local function paintRay(sc, tx, ty, v, erase)
  local P = app.P
  local i = ty * sc.w + tx + 1
  local key = tx .. "," .. ty .. (erase and "e" or "p")
  if M.rayKey == key then return end
  M.rayKey = key
  if erase then
    if project.stackHeight(sc, i) > 0 then
      project.popStack(sc, i); app.changed()
    else
      setTile(sc, tx, ty, 0)
    end
    return
  end
  local spr = P.sprites[v]
  if spr and (spr.kind == "solid" or spr.kind == "breakable") then
    if project.pushStack(sc, i, v) then app.changed()
    else app.say("TOO TALL, MAX " .. project.MAX_STACK, 1.5) end
  else
    setTile(sc, tx, ty, v)
  end
end

-- ── palette ─────────────────────────────────────────────────────────────
local function drawPalette(sc)
  local P = app.P
  -- which layer you're painting on
  local back = M.layer == "back"
  if ui.button(2, 14, 44, 11, back and "BACK" or "MAIN", {on = true, col = back and gfx.PURPLE or gfx.ACCENT}) then
    M.layer = back and "main" or "back"
    app.say(M.layer == "back" and "PAINTING THE BACKGROUND" or "PAINTING THE LEVEL", 1.5)
  end
  -- background scroll speed (only matters on the BACK layer)
  if back then
    local speeds = project.BG_SPEEDS
    local cur = sc.bgSpeed or 0.5
    local si = 1
    for i, v in ipairs(speeds) do if math.abs(v - cur) < 0.01 then si = i end end
    local label = (cur == 0) and "BG FIXED" or ("BG X" .. cur)
    if ui.button(2, 211, 44, 12, label, {col = gfx.PURPLE}) then
      sc.bgSpeed = speeds[si % #speeds + 1]; app.changed()
      app.say(sc.bgSpeed == 0 and "BACKGROUND STAYS STILL" or ("BACKGROUND SCROLLS AT X" .. sc.bgSpeed), 2)
    end
  end
  local total = #P.sprites + 1               -- +1 for the eraser
  local maxScroll = math.max(0, math.ceil(total / 2) - PAL_ROWS)
  if M.palScroll > maxScroll then M.palScroll = maxScroll end
  if M.sel > #P.sprites then M.sel = #P.sprites end

  for r = 0, PAL_ROWS - 1 do
    for c = 0, 1 do
      local i = (M.palScroll + r) * 2 + c      -- 0 = eraser
      if i < total then
        local x, y = 2 + c * 23, 26 + r * 22
        if input.over(x, y, 20, 20) and input.takeClick() then M.sel = i end
        gfx.setc(gfx.BLACK); gfx.rect(x, y, 20, 20)
        if i == 0 then
          gfx.setc(gfx.WARN); gfx.textCentered("DEL", x, y + 8, 20, 1)
        else
          local spr = P.sprites[i]
          local col = project.KIND_COLOR[spr.kind] or gfx.WHITE
          local ta = gfx.memo(spr, "thumb", project.thumbAnim)
          if gfx.isBlank(spr, ta, 1) then
            gfx.color(col[1] * 0.3, col[2] * 0.3, col[3] * 0.3); gfx.rect(x + 4, y + 4, 12, 12)
          else
            gfx.sprite(spr, ta, 1, x + 2, y + 2, (spr.size == 8) and 2 or 1)
          end
        end
        gfx.setc(i == M.sel and gfx.ACCENT or gfx.BORDER)
        gfx.box(x, y, 20, 20)
      end
    end
  end
  if ui.button(2, 226, 21, 11, "^", {off = M.palScroll == 0}) then M.palScroll = M.palScroll - 1 end
  if ui.button(25, 226, 21, 11, "V", {off = M.palScroll >= maxScroll}) then M.palScroll = M.palScroll + 1 end
end

-- ── map view ────────────────────────────────────────────────────────────
local function drawView(sc)
  local P = app.P
  local T = P.tile
  local ts = T * M.zoom

  -- scrolling: X + d-pad, or the mouse near an edge
  local sp = 3
  if input.down.x then
    if input.down.left then M.camX = M.camX - sp end
    if input.down.right then M.camX = M.camX + sp end
    if input.down.up then M.camY = M.camY - sp end
    if input.down.down then M.camY = M.camY + sp end
  elseif input.mouseUsed and input.over(VX, VY, VW, VH) then
    local dx, dy = input.edgePush(VX, VY, VW, VH, 5)
    M.camX, M.camY = M.camX + dx * sp, M.camY + dy * sp
  end
  clampCam(sc, ts)

  -- painting
  local hx, hy
  local raycast = P.mode == "raycast" and M.layer ~= "back"
  if not (input.held or input.altHeld) then M.rayKey = nil end
  if input.over(VX, VY, VW, VH) then
    local tx = floor((input.cx - VX + M.camX) / ts)
    local ty = floor((input.cy - VY + M.camY) / ts)
    if tx >= 0 and ty >= 0 and tx < sc.w and ty < sc.h then
      hx, hy = tx, ty
      if not input.consumed then
        if raycast then
          if input.altHeld then paintRay(sc, tx, ty, M.sel, true)
          elseif input.held and not input.pressBlocked then paintRay(sc, tx, ty, M.sel, M.sel == 0) end
        elseif input.held and not input.pressBlocked then setTile(sc, tx, ty, M.sel)
        elseif input.altHeld then setTile(sc, tx, ty, 0) end
      end
    end
  end

  gfx.clip(VX, VY, VW, VH)
  gfx.color(4, 5, 8); gfx.rect(VX, VY, VW, VH)
  local ox, oy = VX - M.camX, VY - M.camY
  gfx.color(10, 13, 20); gfx.rect(ox, oy, sc.w * ts, sc.h * ts)

  local x0 = math.max(0, floor(M.camX / ts))
  local y0 = math.max(0, floor(M.camY / ts))
  local x1 = math.min(sc.w - 1, floor((M.camX + VW) / ts))
  local y1 = math.min(sc.h - 1, floor((M.camY + VH) / ts))

  -- grid
  if ts >= 8 then
    gfx.color(22, 28, 40)
    for x = x0, x1 + 1 do gfx.rect(ox + x * ts, oy + y0 * ts, 1, (y1 - y0 + 1) * ts) end
    for y = y0, y1 + 1 do gfx.rect(ox + x0 * ts, oy + y * ts, (x1 - x0 + 1) * ts, 1) end
  end

  -- tiles: the layer you're NOT painting is drawn dimmed behind/under
  local anim = floor(app.time * 60 / 10)
  local back = M.layer == "back"
  local function tileColor(spr, dim)
    local col = project.KIND_COLOR[spr.kind] or gfx.WHITE
    if spr.kind == "solid" or spr.kind == "decor" then col = gfx.WHITE end
    if dim ~= 1 then col = {floor(col[1] * dim), floor(col[2] * dim), floor(col[3] * dim)} end
    return col
  end
  local function drawLayer(layer, dim, showBlank)
    for y = y0, y1 do
      for x = x0, x1 do
        local v = layer[y * sc.w + x + 1]
        local spr = v > 0 and P.sprites[v]
        if spr then
          local col = tileColor(spr, dim)
          local ta = gfx.memo(spr, "thumb", project.thumbAnim)
          if gfx.isBlank(spr, ta, 1) then
            if showBlank then
              gfx.color(col[1] * 0.35, col[2] * 0.35, col[3] * 0.35)
              gfx.rect(ox + x * ts + 1, oy + y * ts + 1, ts - 2, ts - 2)
            end
          else
            gfx.sprite(spr, ta, anim % #spr.anims[ta].frames + 1, ox + x * ts, oy + y * ts, M.zoom, dim)
          end
        end
      end
    end
  end
  drawLayer(sc.bg, back and 1 or 0.35, back)
  if back then drawLayer(sc.tiles, 0.25, false) end

  -- raycast stacks: the top piece of each stack, with its height
  if P.mode == "raycast" and not back then
    for y = y0, y1 do
      for x = x0, x1 do
        local i = y * sc.w + x + 1
        local h = project.stackHeight(sc, i)
        local spr = h > 0 and P.sprites[sc.stack[h][i]]
        if spr then
          local ta = gfx.memo(spr, "thumb", project.thumbAnim)
          if gfx.isBlank(spr, ta, 1) then
            gfx.color(90, 90, 110); gfx.rect(ox + x * ts + 1, oy + y * ts + 1, ts - 2, ts - 2)
          else
            gfx.sprite(spr, ta, anim % #spr.anims[ta].frames + 1, ox + x * ts, oy + y * ts, M.zoom)
          end
          gfx.setc(gfx.WARN)
          gfx.text(tostring(h), ox + x * ts + 1, oy + y * ts + 1)
        end
      end
    end
  end

  for y = y0, y1 do
    local row = y * sc.w
    for x = x0, x1 do
      local v = back and 0 or sc.tiles[row + x + 1]
      if v > 0 then
        local spr = P.sprites[v]
        if spr then
          local col = tileColor(spr, 1)
          local ta = gfx.memo(spr, "thumb", project.thumbAnim)
          if gfx.isBlank(spr, ta, 1) then
            gfx.color(col[1] * 0.35, col[2] * 0.35, col[3] * 0.35)
            gfx.rect(ox + x * ts + 1, oy + y * ts + 1, ts - 2, ts - 2)
            if spr.kind == "text" then          -- invisible text trigger: mark it
              gfx.setc(col)
              local c = math.max(1, floor(ts / 8))
              gfx.text("T", ox + x * ts + floor((ts - 3 * c) / 2), oy + y * ts + floor((ts - 5 * c) / 2), c)
            end
          else
            gfx.sprite(spr, ta, anim % #spr.anims[ta].frames + 1, ox + x * ts, oy + y * ts, M.zoom)
          end
          -- moving platform: a dim ghost where it ends up, and a line to it
          if spr.kind == "platform" then
            local d = (spr.dist or 3) * ts
            local ex, ey = ox + x * ts, oy + y * ts
            gfx.color(col[1] * 0.35, col[2] * 0.35, col[3] * 0.35)
            if (spr.axis or "x") == "x" then
              gfx.rect(ex + ts, ey + floor(ts / 2), d, 1)
              gfx.box(ex + d, ey, ts, ts)
            else
              gfx.rect(ex + floor(ts / 2), ey + ts, 1, d)
              gfx.box(ex, ey + d, ts, ts)
            end
          end
        end
      end
    end
  end

  -- hover
  if hx then
    gfx.setc(input.altHeld and gfx.WARN or gfx.ACCENT)
    gfx.box(ox + hx * ts, oy + hy * ts, ts + 1, ts + 1)
  end

  -- map edge
  gfx.setc(back and gfx.PURPLE or gfx.ACCENT2)
  gfx.box(ox - 1, oy - 1, sc.w * ts + 2, sc.h * ts + 2)
  gfx.clip()

  -- footer info inside the view
  gfx.color(0, 0, 0, 255); gfx.rect(VX, VY + VH - 8, VW, 8)
  local info
  if M.sel == 0 then info = "ERASER"
  else
    local s = P.sprites[M.sel]
    info = s and (s.name .. " (" .. s.kind .. ")") or ""
  end
  gfx.setc(gfx.DIM)
  if back then info = "BACK: " .. info end
  gfx.text(info .. "   X+DPAD SCROLL  B ERASE", VX + 2, VY + VH - 7)
  if hx then
    local t = "TILE " .. hx .. "," .. hy
    if P.mode == "raycast" then t = t .. "  HEIGHT " .. project.stackHeight(sc, hy * sc.w + hx + 1) end
    gfx.text(t, VX + VW - gfx.textWidth(t) - 2, VY + VH - 7)
  end
end

-- ── bottom bar ──────────────────────────────────────────────────────────
local function drawBar(sc)
  local P = app.P
  local by = 226
  if ui.button(50, by, 12, 11, "<", {off = app.scene <= 1}) then app.scene = app.scene - 1 end
  gfx.setc(gfx.TEXT)
  gfx.textCentered("S" .. app.scene .. "/" .. #P.scenes .. " " .. sc.w .. "X" .. sc.h, 63, by + 3, 78, 1)
  if ui.button(142, by, 12, 11, ">", {off = app.scene >= #P.scenes}) then app.scene = app.scene + 1 end
  if ui.button(157, by, 30, 11, "+SCENE", {col = gfx.ACCENT}) then
    P.scenes[#P.scenes + 1] = project.newScene(P, sc.w, sc.h)
    app.scene = #P.scenes; app.changed(); app.say("SCENE " .. app.scene .. " ADDED")
  end
  if ui.confirmButton("delscene", 190, by, 22, 11, "DEL", {off = #P.scenes <= 1}) and #P.scenes > 1 then
    table.remove(P.scenes, app.scene)
    app.changed(); app.say("SCENE DELETED")
    return
  end
  if ui.button(215, by, 34, 11, "ZOOM " .. M.zoom .. "X") then
    local cxw = (M.camX + VW / 2) / M.zoom
    local cyw = (M.camY + VH / 2) / M.zoom
    M.zoom = (M.zoom == 1) and 2 or ((M.zoom == 2 and P.tile == 8) and 3 or 1)
    M.camX, M.camY = cxw * M.zoom - VW / 2, cyw * M.zoom - VH / 2
  end
  local function resize(dw, dh)
    local w = math.max(8, math.min(128, sc.w + dw))
    local h = math.max(4, math.min(64, sc.h + dh))
    if w ~= sc.w or h ~= sc.h then project.resizeScene(sc, w, h); app.changed() end
  end
  if ui.button(252, by, 15, 11, "W-") then resize(-1, 0) end
  if ui.button(268, by, 15, 11, "W+") then resize(1, 0) end
  if ui.button(285, by, 15, 11, "H-") then resize(0, -1) end
  if ui.button(301, by, 15, 11, "H+") then resize(0, 1) end
end

function M.reset()
  M.sel, M.palScroll, M.camX, M.camY, M.layer = 1, 0, 0, 0, "main"
  M.rayKey = nil
end

function M.draw()
  local P = app.P
  if #P.sprites == 0 then
    ui.label("DRAW SOME SPRITES FIRST", 112, 100, gfx.TEXT)
    if ui.button(120, 112, 80, 16, "GO TO SPRITES", {col = gfx.ACCENT}) then app.tab = "sprite" end
    return
  end
  local sc = scene()
  drawPalette(sc)
  drawView(sc)
  drawBar(sc)
end

return M
