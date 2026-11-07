-- Games screen: every game lives in its own save slot. Pick a card to open
-- it, start a new game in an empty one, copy or delete games.
--
-- Tap a card to select it, tap it again (or OPEN) to open it.

local gfx     = require("lib.gfx")
local input   = require("lib.input")
local ui      = require("lib.ui")
local project = require("lib.project")
local app     = require("lib.app")

local GM = {
  sel = 1,
  cards = {},        -- cards[n] = {P = project} | {err = "..."} | false (empty)
  onNew = nil,       -- set by main.lua: function(slot) opens new-game setup
  onLeave = nil,     -- set by main.lua: back to the editor
}

local COLS, ROWS = 3, 4
local CW, CH, GAP = 102, 46, 4
local X0, Y0 = 3, 20

-- Re-read every slot from disk (only when the screen opens or files change,
-- never per frame). The open game uses app.P so unsaved edits show too.
function GM.refresh()
  for n = 1, project.MAX_SLOTS do
    if n == app.slot and app.P then
      GM.cards[n] = {P = app.P}
    elseif project.slotExists(n) then
      local P, err = project.loadSlot(n)
      GM.cards[n] = P and {P = P} or {err = err or "bad save"}
    else
      GM.cards[n] = false
    end
  end
end

function GM.open()
  GM.refresh()
  GM.sel = app.slot or project.firstEmptySlot() or 1
end

-- The sprite that best represents a game: a player with art, else any sprite
-- with art.
local function coverSprite(P)
  local any
  for _, spr in ipairs(P.sprites) do
    local ta = gfx.memo(spr, "thumb", project.thumbAnim)
    if project.animHasArt(spr.anims[ta]) then
      if spr.kind == "player" then return spr, ta end
      if not any then any = {spr, ta} end
    end
  end
  if any then return any[1], any[2] end
  return nil
end

local function cardXY(n)
  local i = n - 1
  return X0 + (i % COLS) * (CW + GAP), Y0 + math.floor(i / COLS) * (CH + GAP)
end

local function plural(c, word) return c .. " " .. word .. (c == 1 and "" or "S") end

local function openSlot(n)
  local card = GM.cards[n]
  if card == false then
    if GM.onNew then GM.onNew(n) end
    return
  end
  if card.err then app.say("GAME " .. n .. " CAN'T BE READ", 4); return end
  if n == app.slot then GM.onLeave(); return end
  if app.dirty then app.save(true) end          -- never lose the game you leave
  app.open(card.P, n)
  gfx.invalidateAll()
  GM.onLeave()
  app.say("OPENED GAME " .. n)
end

local function copySlot(n)
  local card = GM.cards[n]
  if not card or not card.P then return end
  local to = project.firstEmptySlot()
  if not to then app.say("ALL " .. project.MAX_SLOTS .. " SLOTS ARE FULL", 4); return end
  local ok = project.saveSlot(card.P, to)
  GM.refresh()
  if ok then GM.sel = to; app.say("COPIED TO GAME " .. to)
  else app.say("COPY FAILED", 4) end
end

local function deleteSlot(n)
  if not project.deleteSlot(n) then app.say("DELETE FAILED", 4); return end
  if n == app.slot then
    app.P, app.slot, app.dirty = nil, nil, false
  end
  GM.refresh()
  app.say("DELETED GAME " .. n)
end

local function drawCard(n)
  local x, y = cardXY(n)
  local card = GM.cards[n]
  local sel = (n == GM.sel)
  local hover = input.over(x, y, CW, CH)

  if hover and input.takeClick() then
    if sel then openSlot(n) else GM.sel = n end
  end

  gfx.setc(sel and gfx.PANEL2 or gfx.PANEL); gfx.rect(x, y, CW, CH)
  gfx.setc(sel and gfx.ACCENT or (hover and gfx.DIM or gfx.BORDER)); gfx.box(x, y, CW, CH)
  if sel then gfx.box(x + 1, y + 1, CW - 2, CH - 2) end

  gfx.setc(n == app.slot and gfx.ACCENT or (card == false and gfx.DIM or gfx.TEXT))
  gfx.text("GAME " .. n, x + 5, y + 4)
  if n == app.slot then
    gfx.setc(gfx.ACCENT); gfx.text(app.dirty and "OPEN *" or "OPEN", x + CW - 29, y + 4)
  end

  if card == false then
    gfx.setc(gfx.DIM)
    gfx.textCentered("+ NEW GAME", x, y + 24, CW, 1)
    return
  end

  -- cover art in a 32x32 box
  gfx.setc(gfx.BG); gfx.rect(x + 5, y + 11, 32, 32)
  if card.P then
    local spr, ta = coverSprite(card.P)
    if spr then
      local sc = math.max(1, math.floor(32 / spr.size))
      local off = math.floor((32 - spr.size * sc) / 2)
      gfx.sprite(spr, ta, 1, x + 5 + off, y + 11 + off, sc)
    end
  end

  if card.err then
    gfx.setc(gfx.WARN); gfx.text("CAN'T READ", x + 42, y + 14)
    return
  end
  local P = card.P
  gfx.setc(gfx.ACCENT2)
  local names = {topdown = "TOP-DOWN", raycast = "FIRST-PERSON"}
  gfx.text(names[P.mode] or "PLATFORMER", x + 42, y + 14)
  gfx.setc(gfx.DIM)
  gfx.text(plural(#P.sprites, "SPRITE"), x + 42, y + 24)
  gfx.text(plural(#P.scenes, "SCENE") .. " " .. P.tile .. "PX", x + 42, y + 33)
end

function GM.draw()
  gfx.setc(gfx.PANEL); gfx.rect(0, 0, 320, 14)
  gfx.setc(gfx.BORDER); gfx.rect(0, 14, 320, 1)
  gfx.setc(gfx.ACCENT); gfx.text("MY GAMES", 4, 5)
  if app.statusT > 0 then
    gfx.setc(gfx.ACCENT); gfx.text(app.status, 44, 5)
  else
    gfx.setc(gfx.DIM); gfx.text("TAP A GAME, TAP AGAIN TO OPEN", 44, 5)
  end

  for n = 1, project.MAX_SLOTS do drawCard(n) end

  local card = GM.cards[GM.sel]
  local empty = (card == false)
  local by = 222
  if ui.button(3, by, 74, 14, empty and "NEW GAME" or "OPEN", {col = gfx.ACCENT, on = true}) then
    openSlot(GM.sel)
  end
  if ui.button(81, by, 74, 14, "COPY", {off = empty or (card and card.err ~= nil)}) then
    copySlot(GM.sel)
  end
  if ui.confirmButton("delgame" .. GM.sel, 159, by, 74, 14, "DELETE", {off = empty}) then
    deleteSlot(GM.sel)
  end
  if ui.button(237, by, 80, 14, "BACK", {off = not app.P}) then GM.onLeave() end
end

return GM
