-- SPRITES tab: draw 16-color sprites with named animations and pick what kind of
-- thing each sprite is (player, wall, coin...).
--
-- A sprite holds several animations (spr.anims), each a list of frames. Which
-- animations it gets depends on its kind and the game type, see
-- project.presets(). The play-test picks animations by name.

local gfx     = require("lib.gfx")
local input   = require("lib.input")
local ui      = require("lib.ui")
local project = require("lib.project")
local app     = require("lib.app")
local keyboard = require("lib.keyboard")

local floor = math.floor

local S = {
  anim = 1,         -- animation being edited
  frame = 1,        -- frame being edited (within that animation)
  tool = "pen",     -- "pen" | "fill" | "pick" (eyedropper)
  color = 4,        -- palette color you draw with (1-16; 0 = transparent)
  undo = {},        -- { {spr, animTable, frameIndex, copyOfPixels}, ... }
  stroking = false,
  listScroll = 0,   -- first visible row of the sprite list
  nudgeDir = "up",  -- direction the arrow button points
  nudgeAll = false, -- nudge every frame of the animation, not just this one
  clip = nil,       -- copied frame: {size, pixels}. Survives switching sprite/animation
  tick = 0,
}

local GX, GY, GS = 6, 18, 160          -- drawing grid position + size
local RX = 172                         -- right panel x
local MAX_FRAMES = 7

local function copyFrame(f) local c = {}; for i = 1, #f do c[i] = f[i] end; return c end

local function current()
  local P = app.P
  if #P.sprites == 0 then return nil end
  if app.sprite > #P.sprites then app.sprite = #P.sprites end
  if app.sprite < 1 then app.sprite = 1 end
  local spr = P.sprites[app.sprite]
  if S.anim > #spr.anims then S.anim = #spr.anims end
  if S.anim < 1 then S.anim = 1 end
  local frames = spr.anims[S.anim].frames
  if S.frame > #frames then S.frame = #frames end
  if S.frame < 1 then S.frame = 1 end
  return spr
end

local function anim(spr) return spr.anims[S.anim] end
local function frames(spr) return spr.anims[S.anim].frames end

local function selectSprite(i)
  app.sprite, S.anim, S.frame = i, 1, 1
end

local function edited(spr)
  gfx.invalidate(spr)
  app.changed()
end

local function pushUndo(spr)
  S.undo[#S.undo + 1] = {spr, anim(spr), S.frame, copyFrame(frames(spr)[S.frame])}
  if #S.undo > 30 then table.remove(S.undo, 1) end
end

local function doUndo()
  local u = table.remove(S.undo)
  if not u then app.say("NOTHING TO UNDO"); return end
  local spr, a, fi, pix = u[1], u[2], u[3], u[4]
  if fi == "all" then
    a.frames = pix
    edited(spr)
    app.say("UNDONE", 1)
  elseif a.frames[fi] then
    a.frames[fi] = pix
    edited(spr)
    app.say("UNDONE", 1)
  end
end

local function flood(spr, f, x, y, v)
  local sz = spr.size
  local target = f[y * sz + x + 1]
  if target == v then return end
  local stack = {{x, y}}
  while #stack > 0 do
    local p = table.remove(stack)
    local px, py = p[1], p[2]
    if px >= 0 and py >= 0 and px < sz and py < sz and f[py * sz + px + 1] == target then
      f[py * sz + px + 1] = v
      stack[#stack + 1] = {px + 1, py}; stack[#stack + 1] = {px - 1, py}
      stack[#stack + 1] = {px, py + 1}; stack[#stack + 1] = {px, py - 1}
    end
  end
end

local function transformed(f, sz, fn)
  local out = {}
  for y = 0, sz - 1 do
    for x = 0, sz - 1 do
      local sx, sy = fn(x, y, sz)
      out[y * sz + x + 1] = f[sy * sz + sx + 1]
    end
  end
  return out
end

local function transform(spr, fn)
  pushUndo(spr)
  frames(spr)[S.frame] = transformed(frames(spr)[S.frame], spr.size, fn)
  edited(spr)
end

local function flipX(x, y, sz) return sz - 1 - x, y end

-- Shift the drawing 1px, wrapping around the edges (nothing gets lost)
local NUDGE = {up = {0, -1}, down = {0, 1}, left = {-1, 0}, right = {1, 0}}
local NUDGE_NEXT = {up = "down", down = "left", left = "right", right = "up"}
local NUDGE_ARROW = {up = "^", down = "V", left = "<", right = ">"}

local function nudge(spr, dir, all)
  local d = NUDGE[dir]
  local function shift(x, y, sz) return (x - d[1]) % sz, (y - d[2]) % sz end
  local a = anim(spr)
  if all then
    local old = {}
    for i, f in ipairs(a.frames) do old[i] = copyFrame(f) end
    S.undo[#S.undo + 1] = {spr, a, "all", old}
    for i, f in ipairs(a.frames) do a.frames[i] = transformed(f, spr.size, shift) end
  else
    pushUndo(spr)
    a.frames[S.frame] = transformed(a.frames[S.frame], spr.size, shift)
  end
  edited(spr)
end

local function newSprite()
  local P = app.P
  local hasPlayer = false
  for _, s in ipairs(P.sprites) do if s.kind == "player" then hasPlayer = true end end
  local spr = project.newSprite(P, hasPlayer and "solid" or "player")
  P.sprites[#P.sprites + 1] = spr
  selectSprite(#P.sprites)
  app.changed()
  app.say("NEW " .. string.upper(spr.kind) .. " SPRITE")
end

-- Bring up the on-screen keyboard for a text sprite's message
local function editText(spr)
  keyboard.open(spr.text or "", {
    title = "TEXT FOR " .. spr.name,
    max = project.TEXT_MAX, width = project.TEXT_WIDTH, lines = project.TEXT_LINES,
    onDone = function(t)
      if t ~= (spr.text or "") then spr.text = t; app.changed() end
      app.say(#t > 0 and "TEXT SAVED" or "NO TEXT YET", 1.5)
    end,
  })
end

local function setKind(spr, kind)
  spr.kind = kind
  project.ensureAnims(spr, app.P.mode, app.P)
  -- adding/removing a melee or gun pickup changes which slots players get
  for _, s in ipairs(app.P.sprites) do
    if s.kind == "player" and s ~= spr then project.ensureAnims(s, app.P.mode, app.P); gfx.invalidate(s) end
  end
  S.anim, S.frame = 1, 1
  edited(spr)
  -- a new text object goes straight to typing its message
  if kind == "text" and (spr.text or "") == "" then editText(spr) end
end

-- "Walk Left" <-> "Walk Right": the other one, if it's a mirror pair
local MIRROR = {["Walk Left"] = "Walk Right", ["Walk Right"] = "Walk Left"}

-- ── the drawing grid ───────────────────────────────────────────────────
local function drawGrid(spr)
  local sz = spr.size
  local cell = floor(GS / sz)
  local f = frames(spr)[S.frame]

  -- transparent cells show a dark checkerboard, so black pixels stand out
  gfx.color(20, 20, 26)
  gfx.rect(GX, GY, cell * sz, cell * sz)
  gfx.color(30, 30, 38)
  local half = floor(cell / 2)
  for y = 0, sz - 1 do
    for x = 0, sz - 1 do
      gfx.rect(GX + x * cell, GY + y * cell, half, half)
      gfx.rect(GX + x * cell + half, GY + y * cell + half, cell - half, cell - half)
    end
  end

  -- painting
  if input.over(GX, GY, cell * sz, cell * sz) then
    local px = floor((input.cx - GX) / cell)
    local py = floor((input.cy - GY) / cell)
    if S.tool == "pen" then
      if (input.held and not input.pressBlocked) or input.altHeld then
        if not S.stroking then pushUndo(spr); S.stroking = true end
        local v = (input.held and not input.pressBlocked) and S.color or 0
        local i = py * sz + px + 1
        if f[i] ~= v then f[i] = v; edited(spr) end
      end
    elseif S.tool == "pick" then
      -- eyedropper: take the color under the cursor, then go back to the pen
      if input.click and not input.consumed then
        input.consumed = true
        local v = f[py * sz + px + 1]
        if v ~= 0 then S.color = v end
        S.tool = "pen"
      end
    elseif (input.click or input.altClick) and not input.consumed then
      input.consumed = true
      pushUndo(spr)
      flood(spr, f, px, py, input.click and S.color or 0)
      edited(spr)
    end
  end
  if not (input.held or input.altHeld) then S.stroking = false end

  -- onion skin: previous frame shown faintly
  if S.frame > 1 then
    local prev = frames(spr)[S.frame - 1]
    gfx.color(40, 50, 70)
    for y = 0, sz - 1 do
      for x = 0, sz - 1 do
        if prev[y * sz + x + 1] ~= 0 and f[y * sz + x + 1] == 0 then
          gfx.rect(GX + x * cell + 1, GY + y * cell + 1, cell - 2, cell - 2)
        end
      end
    end
  end

  local pal = gfx.PALETTE
  for y = 0, sz - 1 do
    for x = 0, sz - 1 do
      local v = f[y * sz + x + 1]
      if v ~= 0 then
        gfx.setc(pal[v])
        gfx.rect(GX + x * cell, GY + y * cell, cell, cell)
      end
    end
  end

  -- grid lines (brighter every 4 cells)
  for i = 0, sz do
    if i % 4 == 0 then gfx.color(45, 58, 82) else gfx.color(24, 30, 42) end
    gfx.rect(GX + i * cell, GY, 1, cell * sz)
    gfx.rect(GX, GY + i * cell, cell * sz + 1, 1)
  end

  -- hovered cell
  if input.over(GX, GY, cell * sz, cell * sz) then
    local px = floor((input.cx - GX) / cell)
    local py = floor((input.cy - GY) / cell)
    gfx.setc(gfx.ACCENT)
    gfx.box(GX + px * cell, GY + py * cell, cell + 1, cell + 1)
  end
end

-- ── right panel ─────────────────────────────────────────────────────────
local function drawPanel(spr)
  local P = app.P

  -- tools + transforms
  if ui.button(RX, 17, 34, 11, "PEN", {on = S.tool == "pen", col = gfx.ACCENT}) then S.tool = "pen" end
  if ui.button(RX + 36, 17, 34, 11, "FILL", {on = S.tool == "fill", col = gfx.ACCENT}) then S.tool = "fill" end
  if ui.button(RX + 72, 17, 34, 11, "UNDO", {off = #S.undo == 0}) then doUndo() end
  if ui.button(RX + 108, 17, 36, 11, "PICK", {on = S.tool == "pick", col = gfx.ACCENT}) then S.tool = "pick" end
  if ui.confirmButton("clear", RX, 31, 34, 11, "CLEAR") then
    pushUndo(spr)
    local f = frames(spr)[S.frame]
    for i = 1, #f do f[i] = 0 end
    edited(spr)
  end
  if ui.button(RX + 36, 31, 34, 11, "FLIP H") then transform(spr, flipX) end
  if ui.button(RX + 72, 31, 34, 11, "FLIP V") then transform(spr, function(x, y, sz) return x, sz - 1 - y end) end
  if ui.button(RX + 108, 31, 36, 11, "ROTATE") then transform(spr, function(x, y, sz) return y, sz - 1 - x end) end

  -- kind picker
  local kinds = project.KINDS
  local ki = 1
  for i, k in ipairs(kinds) do if k == spr.kind then ki = i end end
  local kcol = project.KIND_COLOR[spr.kind] or gfx.WHITE
  if ui.button(RX, 45, 14, 12, "<") then setKind(spr, kinds[ki > 1 and ki - 1 or #kinds]) end
  if ui.button(RX + 130, 45, 14, 12, ">") then setKind(spr, kinds[ki < #kinds and ki + 1 or 1]) end
  -- tap the bar itself to see every kind at once
  local hoverBar = input.over(RX + 16, 45, 112, 12)
  if hoverBar and input.takeClick() then S.kindPick = true end
  gfx.color(kcol[1] * 0.2, kcol[2] * 0.2, kcol[3] * 0.2)
  gfx.rect(RX + 16, 45, 112, 12)
  gfx.setc(kcol)
  gfx.box(RX + 16, 45, 112, 12)
  gfx.textCentered("KIND: " .. spr.kind .. (hoverBar and " (PICK)" or ""), RX + 16, 48, 112, 1)
  if spr.kind == "platform" then
    -- which way it moves, how many tiles, how fast
    local axis = spr.axis or "x"
    if ui.button(RX, 58, 34, 9, axis == "x" and "HORIZ" or "VERT", {on = true, col = kcol}) then
      spr.axis = (axis == "x") and "y" or "x"; app.changed()
    end
    local dist = spr.dist or 3
    if ui.button(RX + 36, 58, 11, 9, "-", {off = dist <= 1}) then spr.dist = dist - 1; app.changed() end
    gfx.setc(gfx.TEXT); gfx.textCentered(dist .. " TILES", RX + 48, 60, 40, 1)
    if ui.button(RX + 89, 58, 11, 9, "+", {off = dist >= 16}) then spr.dist = dist + 1; app.changed() end
    local SPEED_NAME = {"SLOW", "MED", "FAST"}
    local sp = spr.speed or 2
    if ui.button(RX + 102, 58, 42, 9, SPEED_NAME[sp], {on = true, col = kcol}) then
      spr.speed = sp % 3 + 1; app.changed()
    end
  elseif spr.kind == "enemy" then
    -- behavior, hit points, speed: each enemy sprite is its own enemy type
    local B = project.BEHAVIORS
    local beh = spr.behavior or "walker"
    if ui.button(RX, 58, 54, 9, beh, {on = true, col = kcol}) then
      local bi = 1
      for i, b in ipairs(B) do if b == beh then bi = i end end
      spr.behavior = B[bi % #B + 1]; app.changed()
      app.say(spr.behavior .. ": " .. project.BEHAVIOR_HINT[spr.behavior], 2.5)
    end
    local hp = spr.hp or 1
    if ui.button(RX + 56, 58, 11, 9, "-", {off = hp <= 1}) then spr.hp = hp - 1; app.changed() end
    gfx.setc(gfx.TEXT); gfx.textCentered("HP " .. hp, RX + 67, 60, 26, 1)
    if ui.button(RX + 93, 58, 11, 9, "+", {off = hp >= 9}) then spr.hp = hp + 1; app.changed() end
    local SPEED_NAME = {"SLOW", "MED", "FAST"}
    local sp = spr.speed or 2
    if ui.button(RX + 106, 58, 38, 9, SPEED_NAME[sp], {on = true, col = kcol}) then
      spr.speed = sp % 3 + 1; app.changed()
    end
  elseif spr.kind == "text" then
    -- the message, when it shows, and (for touch) whether it repeats
    if ui.button(RX, 58, 46, 9, "EDIT TEXT", {on = true, col = kcol}) then editText(spr) end
    local trig = spr.trigger or "touch"
    if ui.button(RX + 48, 58, 50, 9, project.TRIGGER_NAME[trig], {on = true, col = kcol}) then
      local T = project.TRIGGERS
      local ti = 1
      for i, t in ipairs(T) do if t == trig then ti = i end end
      spr.trigger = T[ti % #T + 1]; app.changed()
    end
    if ui.button(RX + 100, 58, 44, 9, spr.once and "ONCE" or "EVERY TIME",
                 {on = trig == "touch", off = trig ~= "touch", col = kcol}) then
      spr.once = not spr.once or nil; app.changed()
    end
  elseif spr.kind == "battle" then
    -- a fight on touch: the intro line (the text), the enemy's health, attack
    -- and defense, and whether it's a boss, a repeat fight, or once only
    local bt = spr.battle or {}
    spr.battle = bt
    if ui.button(RX, 58, 30, 9, "TEXT", {on = true, col = kcol}) then editText(spr) end
    local hp = bt.hp or 4
    if ui.button(RX + 32, 58, 25, 9, "HP " .. hp, {on = true, col = kcol}) then
      bt.hp = hp % 9 + 1; app.changed()
    end
    local atk = bt.atk or 2
    if ui.button(RX + 59, 58, 25, 9, "AT " .. atk, {on = true, col = kcol}) then
      bt.atk = (atk + 1) % 10; app.changed()
    end
    local def = bt.def or 0
    if ui.button(RX + 86, 58, 25, 9, "DF " .. def, {on = true, col = kcol}) then
      bt.def = (def + 1) % 10; app.changed()
    end
    local ty = bt.boss and "BOSS" or (bt.repeatable and "REPEAT" or "ONCE")
    if ui.button(RX + 113, 58, 31, 9, ty, {on = true, col = kcol}) then
      if ty == "ONCE" then bt.repeatable = true
      elseif ty == "REPEAT" then bt.repeatable, bt.boss = nil, true
      else bt.boss = nil end
      app.changed()
    end
  else
    ui.label(project.KIND_HINT[spr.kind] or "", RX, 59)
  end

  -- animation picker
  local a = anim(spr)
  local drawn = project.animHasArt(a)
  local na = #spr.anims
  if ui.button(RX, 68, 14, 12, "<", {off = na <= 1}) then S.anim = (S.anim > 1) and S.anim - 1 or na; S.frame = 1 end
  if ui.button(RX + 130, 68, 14, 12, ">", {off = na <= 1}) then S.anim = (S.anim < na) and S.anim + 1 or 1; S.frame = 1 end
  gfx.setc(gfx.PANEL2); gfx.rect(RX + 16, 68, 112, 12)
  gfx.setc(drawn and gfx.ACCENT2 or gfx.BORDER); gfx.box(RX + 16, 68, 112, 12)
  gfx.setc(drawn and gfx.TEXT or gfx.DIM)
  gfx.textCentered(S.anim .. "/" .. na .. " " .. a.name .. (drawn and "" or " (EMPTY)"), RX + 16, 71, 112, 1)

  -- frames of this animation
  local fr = frames(spr)
  local tsc = (spr.size == 8) and 2 or 1
  for i = 1, #fr do
    local x, y = RX + (i - 1) * 20, 83
    if input.over(x, y, 18, 18) and input.takeClick() then S.frame = i end
    gfx.setc(gfx.BLACK); gfx.rect(x, y, 18, 18)
    gfx.sprite(spr, S.anim, i, x + 1, y + 1, tsc)
    gfx.setc(i == S.frame and gfx.ACCENT or gfx.BORDER); gfx.box(x, y, 18, 18)
  end
  if ui.button(RX, 103, 46, 11, "+ FRAME", {off = #fr >= MAX_FRAMES}) then
    table.insert(fr, S.frame + 1, project.blankFrame(spr.size))
    S.frame = S.frame + 1; edited(spr)
  end
  if ui.button(RX + 49, 103, 46, 11, "DUP FRAME", {off = #fr >= MAX_FRAMES}) then
    table.insert(fr, S.frame + 1, copyFrame(fr[S.frame]))
    S.frame = S.frame + 1; edited(spr)
  end
  if ui.confirmButton("delframe", RX + 98, 103, 46, 11, "DEL FRAME", {off = #fr <= 1}) and #fr > 1 then
    table.remove(fr, S.frame)
    if S.frame > #fr then S.frame = #fr end
    edited(spr)
  end

  -- animated preview of this animation
  local psc = floor(32 / spr.size)
  gfx.setc(gfx.BLACK); gfx.rect(RX, 117, 36, 36)
  local af = floor(S.tick / 8) % #fr + 1
  gfx.sprite(spr, S.anim, af, RX + 2, 119, psc)
  gfx.setc(gfx.BORDER); gfx.box(RX, 117, 36, 36)
  ui.label("SPRITE " .. app.sprite .. "/" .. #P.sprites, RX + 42, 118, gfx.TEXT)
  ui.label(spr.name .. "  " .. spr.size .. "X" .. spr.size, RX + 42, 126)
  ui.label("FRAME " .. S.frame .. "/" .. #fr, RX + 42, 134)

  -- Walk Left / Walk Right: build one from the other
  local other = MIRROR[a.name]
  if other then
    local oi
    for i, x in ipairs(spr.anims) do if x.name == other then oi = i end end
    local src = oi and spr.anims[oi]
    if ui.button(RX + 42, 142, 102, 10, "MIRROR " .. other, {off = not (src and project.animHasArt(src))}) then
      S.undo[#S.undo + 1] = {spr, a, 1, copyFrame(a.frames[1])}
      local out = {}
      for i, f in ipairs(src.frames) do out[i] = transformed(f, spr.size, flipX) end
      a.frames = out
      S.frame = 1; edited(spr)
      app.say("MIRRORED " .. other)
    end
  else
    ui.label(drawn and "" or "EMPTY: USES A FALLBACK", RX + 42, 142)
  end
end

-- ── kind picker: every kind at once, replaces the right panel while open ──
local function drawKindPicker(spr)
  local kinds = project.KINDS
  gfx.setc(gfx.PANEL); gfx.rect(RX - 2, 15, 150, 210)
  gfx.setc(gfx.BORDER); gfx.box(RX - 2, 15, 150, 210)
  ui.label("PICK A KIND FOR " .. spr.name, RX + 4, 21, gfx.TEXT)
  local hovered
  for i, k in ipairs(kinds) do
    local c, r = (i - 1) % 2, floor((i - 1) / 2)
    local x, y = RX + 4 + c * 72, 32 + r * 18
    local col = project.KIND_COLOR[k] or gfx.WHITE
    if input.over(x, y, 68, 15) then hovered = k end
    if ui.button(x, y, 68, 15, k, {on = (k == spr.kind), col = col}) then
      if k ~= spr.kind then setKind(spr, k); app.say("KIND: " .. k, 1.5) end
      S.kindPick = false
    end
  end
  local k = hovered or spr.kind
  gfx.setc(project.KIND_COLOR[k] or gfx.WHITE)
  gfx.text(string.upper(k), RX + 4, 145)
  gfx.setc(gfx.DIM)
  gfx.text(project.KIND_HINT[k] or "", RX + 4, 155)
  if k == "melee" or k == "gun" then
    gfx.text("ADDS " .. (k == "melee" and "M." or "G.") .. " SLOTS TO YOUR PLAYER", RX + 4, 165)
  end
  if ui.button(RX + 4, 205, 60, 14, "CANCEL") then S.kindPick = false end
  -- clicking anywhere outside the picker closes it
  if input.click and not input.consumed and not input.over(RX - 2, 15, 150, 210) then
    input.consumed = true
    input.pressBlocked = true          -- so the closing click doesn't also paint
    S.kindPick = false
  end
end

-- ── sprite list ────────────────────────────────────────────────────────
local function drawList()
  local P = app.P
  ui.label("SPRITES", RX, 158, gfx.TEXT)
  if ui.button(RX + 32, 156, 26, 10, "NEW") then newSprite() end
  if ui.button(RX + 60, 156, 26, 10, "DUP", {off = #P.sprites == 0}) then
    local src = P.sprites[app.sprite]
    local anims = {}
    for i, an in ipairs(src.anims) do
      local fr = {}
      for j, f in ipairs(an.frames) do fr[j] = copyFrame(f) end
      anims[i] = {name = an.name, frames = fr}
    end
    local copy = {}
    for key, val in pairs(src) do if type(val) ~= "table" then copy[key] = val end end
    copy.name, copy.anims = src.name .. "B", anims
    table.insert(P.sprites, app.sprite + 1, copy)
    -- inserting shifts later sprite numbers on the map
    for _, sc in ipairs(P.scenes) do
      for _, layer in ipairs(project.layers(sc)) do
        for t = 1, #layer do if layer[t] > app.sprite then layer[t] = layer[t] + 1 end end
      end
    end
    selectSprite(app.sprite + 1); app.changed()
  end
  if ui.confirmButton("delspr", RX + 88, 156, 28, 10, "DEL", {off = #P.sprites == 0}) and #P.sprites > 0 then
    project.deleteSprite(P, app.sprite)
    S.undo = {}
    app.changed(); app.say("SPRITE DELETED")
  end

  local cols, rows = 7, 3
  local totalRows = math.max(1, math.ceil(#P.sprites / cols))
  local maxScroll = math.max(0, totalRows - rows)
  if ui.button(RX + 118, 156, 12, 10, "^", {off = S.listScroll == 0}) then S.listScroll = S.listScroll - 1 end
  if ui.button(RX + 132, 156, 12, 10, "V", {off = S.listScroll >= maxScroll}) then S.listScroll = S.listScroll + 1 end
  if S.listScroll > maxScroll then S.listScroll = maxScroll end

  for r = 0, rows - 1 do
    for c = 0, cols - 1 do
      local i = (S.listScroll + r) * cols + c + 1
      local spr = P.sprites[i]
      if spr then
        local x, y = RX + c * 20 + 1, 170 + r * 20
        if input.over(x, y, 18, 18) and input.takeClick() then selectSprite(i) end
        gfx.setc(gfx.BLACK); gfx.rect(x, y, 18, 18)
        local col = project.KIND_COLOR[spr.kind] or gfx.WHITE
        local ta = gfx.memo(spr, "thumb", project.thumbAnim)
        if gfx.isBlank(spr, ta, 1) then
          gfx.color(col[1] * 0.3, col[2] * 0.3, col[3] * 0.3); gfx.rect(x + 3, y + 3, 12, 12)
        else
          gfx.sprite(spr, ta, 1, x + 1, y + 1, (spr.size == 8) and 2 or 1)
        end
        if i == app.sprite then gfx.setc(gfx.ACCENT) else gfx.color(col[1] * 0.4, col[2] * 0.4, col[3] * 0.4) end
        gfx.box(x, y, 18, 18)
      end
    end
  end
end

-- Forget per-game state when another game is opened (the clipboard stays,
-- so you can copy a frame from one game into another).
function S.reset()
  S.anim, S.frame, S.undo, S.listScroll, S.stroking = 1, 1, {}, 0, false
end

function S.draw()
  S.tick = S.tick + 1
  local spr = current()
  if not spr then
    ui.label("NO SPRITES YET", 120, 90, gfx.TEXT)
    if ui.button(110, 104, 100, 20, "+ NEW SPRITE", {col = gfx.ACCENT}) then newSprite() end
    ui.label("YOUR FIRST SPRITE WILL BE THE PLAYER", 88, 132)
    return
  end
  -- Y steps through the palette (quick color changes on a d-pad)
  if input.pressed.y then S.color = S.color % #gfx.PALETTE + 1 end

  -- L2/R2 + d-pad: nudge this frame (L2) or the whole animation (R2)
  if input.down.l2 or input.down.r2 then
    for dir in pairs(NUDGE) do
      if input.pressed[dir] then
        S.nudgeDir = dir
        nudge(spr, dir, input.down.r2 or S.nudgeAll)
      end
    end
  end

  if S.kindPick then
    drawKindPicker(spr)
    drawGrid(spr)
  else
    drawGrid(spr)
    drawPanel(spr)
    drawList()
  end

  -- color swatches under the grid (Y also steps through them)
  local pal = gfx.PALETTE
  for i = 1, #pal do
    local x, y = GX + (i - 1) * 10, 181
    if input.over(x, y, 10, 10) and input.takeClick() then
      S.color = i
      if S.tool == "pick" then S.tool = "pen" end
    end
    gfx.setc(pal[i]); gfx.rect(x, y, 10, 10)
  end
  gfx.setc(gfx.WHITE); gfx.box(GX + (S.color - 1) * 10 - 1, 180, 12, 12)
  gfx.setc(gfx.BLACK); gfx.box(GX + (S.color - 1) * 10, 181, 10, 10)

  -- nudge row: arrow picks a direction, NUDGE moves 1px
  ui.label("MOVE", GX, 197, gfx.TEXT)
  if ui.button(GX + 20, 194, 14, 11, NUDGE_ARROW[S.nudgeDir], {col = gfx.ACCENT2, on = true}) then
    S.nudgeDir = NUDGE_NEXT[S.nudgeDir]
  end
  if ui.button(GX + 36, 194, 40, 11, "NUDGE 1PX") then nudge(spr, S.nudgeDir, S.nudgeAll) end
  if ui.button(GX + 78, 194, 52, 11, "ALL FRAMES", {on = S.nudgeAll, col = gfx.ACCENT}) then
    S.nudgeAll = not S.nudgeAll
  end

  -- copy / paste: works across animations and sprites (same size)
  ui.label("CLIP", GX, 210, gfx.TEXT)
  local fr = frames(spr)
  local canPaste = S.clip and S.clip.size == spr.size
  if ui.button(GX + 20, 207, 30, 11, "COPY") then
    S.clip = {size = spr.size, pix = copyFrame(fr[S.frame])}
    app.say("FRAME COPIED", 1.5)
  end
  if ui.button(GX + 52, 207, 32, 11, "PASTE", {off = not canPaste}) then
    pushUndo(spr)
    fr[S.frame] = copyFrame(S.clip.pix)
    edited(spr); app.say("PASTED", 1.5)
  end
  if ui.button(GX + 86, 207, 44, 11, "PASTE NEW", {off = not canPaste or #fr >= MAX_FRAMES}) then
    table.insert(fr, S.frame + 1, copyFrame(S.clip.pix))
    S.frame = S.frame + 1
    edited(spr); app.say("PASTED AS NEW FRAME", 1.5)
  end
  -- tiny preview of what's on the clipboard
  gfx.setc(gfx.BLACK); gfx.rect(GX + 142, 194, 18, 18)
  gfx.setc(gfx.BORDER); gfx.box(GX + 142, 194, 18, 18)
  if S.clip then
    local sz = S.clip.size
    local sc = (sz == 8) and 2 or 1
    for i = 1, #S.clip.pix do
      local v = S.clip.pix[i]
      if v ~= 0 then
        local x, y = (i - 1) % sz, floor((i - 1) / sz)
        gfx.setc(pal[v])
        gfx.rect(GX + 143 + x * sc, 195 + y * sc, sc, sc)
      end
    end
  end

  gfx.setc(gfx.DIM)
  gfx.text("A DRAW  B ERASE  Y NEXT COLOR", GX, 223)
  gfx.text("L2/R2+DPAD NUDGE  START PLAY", GX, 231)
end

return S
