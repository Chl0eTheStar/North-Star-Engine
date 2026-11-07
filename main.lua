-- LutroFX IDE: a mouse/d-pad friendly game maker that runs inside Lutro
-- (RetroArch) on handhelds, and in desktop LÖVE for testing.
--
-- Screens: SPRITES (draw), MAP (place), PLAY (test), GAMES (save slots) and
-- a setup screen for new games. L/R switch tabs, START toggles play, SELECT saves.

local G = lutro or love

local gfx      = require("lib.gfx")
local input    = require("lib.input")
local ui       = require("lib.ui")
local project  = require("lib.project")
local app      = require("lib.app")
local spriteEd = require("editors.sprite")
local mapEd    = require("editors.map")
local play     = require("editors.play")
local games    = require("editors.games")
local keyboard = require("lib.keyboard")
local splash   = require("lib.splash")

local DESKTOP_SCALE = gfx.IS_LUTRO and 1 or 2
local AUTOSAVE_SECONDS = 30
local TABS = {"sprite", "map", "play"}

-- new-game choices; `slot` is where the new game will be saved
local setup = {mode = "platformer", tile = 8, slot = 1}

local function goTab(t)
  if t == app.tab then return end
  if app.tab == "play" then play.stop() end
  if t == "games" and app.dirty then app.save(true) end
  app.tab = t
  input.cursorOn = (t ~= "play")
  if t == "play" then play.start() end
  if t == "games" then games.open() end
end

app.onOpen = function() spriteEd.reset(); mapEd.reset() end
games.onLeave = function() goTab("sprite") end
games.onNew = function(n)
  setup.slot = n
  setup.cancelable = true
  goTab("setup")
end

function G.load()
  if G.graphics.setDefaultFilter then G.graphics.setDefaultFilter("nearest", "nearest") end
  input.mouseScale = DESKTOP_SCALE
  if not project.lastSlot() then project.migrateLegacy() end   -- pre-slot save -> game 1
  local slot = project.lastSlot()
  if not slot then
    setup.slot = 1                    -- first run: straight to making a game
    app.tab = "setup"
    return
  end
  local P = project.loadSlot(slot)
  if P then
    app.open(P, slot)
    app.tab = "sprite"
    app.say("GAME " .. slot .. " LOADED")
  else
    app.tab = "games"                 -- unreadable: let them pick another
    games.open()
    app.say("GAME " .. slot .. " CAN'T BE READ", 5)
  end
end

function G.update(dt)
  if not dt or dt <= 0 or dt > 0.25 then dt = 1 / 60 end   -- some frontends report 0
  app.time = app.time + dt
  if app.statusT > 0 then app.statusT = app.statusT - dt end
  input.update()
  ui.tick()

  if splash.active then splash.update(dt); return end   -- the splash has the screen first

  if app.P and app.tab ~= "setup" and app.tab ~= "games" and not keyboard.active then
    -- tab switching on shoulder buttons
    local idx = 1
    for i, t in ipairs(TABS) do if t == app.tab then idx = i end end
    if input.pressed.l then goTab(TABS[(idx - 2) % #TABS + 1]) end
    if input.pressed.r then goTab(TABS[idx % #TABS + 1]) end
    if input.pressed.start then goTab(app.tab == "play" and "map" or "play") end
    if input.pressed.select then app.save(false) end

    if app.dirty and app.time - app.lastSave > AUTOSAVE_SECONDS and app.tab ~= "play" then
      app.save(true)
    end
  end

  if app.tab == "play" then play.update(dt) end
end

-- ── top bar ─────────────────────────────────────────────────────────────
local function drawTopBar()
  gfx.setc(gfx.PANEL); gfx.rect(0, 0, 320, 14)
  gfx.setc(gfx.BORDER); gfx.rect(0, 14, 320, 1)
  if ui.button(2, 2, 42, 10, "SPRITES", {on = app.tab == "sprite", col = gfx.ACCENT}) then goTab("sprite") end
  if ui.button(46, 2, 28, 10, "MAP", {on = app.tab == "map", col = gfx.ACCENT}) then goTab("map") end
  if ui.button(76, 2, 30, 10, "PLAY", {on = app.tab == "play", col = gfx.ACCENT2}) then goTab("play") end

  if app.statusT > 0 then
    gfx.setc(gfx.ACCENT)
    gfx.text(app.status, 110, 5)
  else
    gfx.setc(gfx.DIM)
    gfx.text("GAME " .. (app.slot or "?") .. " " .. string.upper(app.P.mode) .. " " .. app.P.tile .. "PX"
      .. (app.dirty and " *" or ""), 110, 5)
  end

  if ui.button(248, 2, 30, 10, "SAVE", {col = gfx.PURPLE, on = app.dirty}) then app.save(false) end
  if ui.button(280, 2, 38, 10, "GAMES", {col = gfx.ACCENT2}) then goTab("games") end
end

-- ── new project screen ──────────────────────────────────────────────────
local function drawSetup()
  gfx.setc(gfx.ACCENT)
  gfx.textCentered("LUTROFX IDE", 0, 30, 320, 3)
  gfx.setc(gfx.DIM)
  gfx.textCentered("NEW GAME IN SLOT " .. setup.slot, 0, 52, 320, 1)

  gfx.setc(gfx.TEXT); gfx.text("GAME TYPE", 22, 74)
  if ui.button(22, 82, 92, 18, "PLATFORMER", {on = setup.mode == "platformer", col = gfx.ACCENT}) then setup.mode = "platformer" end
  if ui.button(114, 82, 92, 18, "TOP-DOWN", {on = setup.mode == "topdown", col = gfx.ACCENT}) then setup.mode = "topdown" end
  if ui.button(206, 82, 92, 18, "FIRST-PERSON", {on = setup.mode == "raycast", col = gfx.ACCENT}) then setup.mode = "raycast" end
  gfx.setc(gfx.DIM)
  local hint = {platformer = "GRAVITY, JUMPING, STOMP ENEMIES",
                topdown = "MOVE IN 8 DIRECTIONS, NO GRAVITY",
                raycast = "DOOM-STYLE 3D. STACK WALLS, FIGHT IN DUNGEONS"}
  gfx.text(hint[setup.mode], 22, 104)

  gfx.setc(gfx.TEXT); gfx.text("TILE + SPRITE SIZE", 80, 120)
  if ui.button(80, 128, 78, 18, "8X8", {on = setup.tile == 8, col = gfx.ACCENT}) then setup.tile = 8 end
  if ui.button(162, 128, 78, 18, "16X16", {on = setup.tile == 16, col = gfx.ACCENT}) then setup.tile = 16 end
  gfx.setc(gfx.DIM)
  gfx.text(setup.tile == 8 and "PLAY SCREEN SHOWS 20X15 TILES" or "PLAY SCREEN SHOWS 10X7 TILES", 80, 150)

  if ui.button(110, 170, 100, 22, "CREATE", {col = gfx.ACCENT, on = true}) then
    if app.dirty then app.save(true) end          -- keep the game you were in
    app.open(project.new(setup.mode, setup.tile), setup.slot)
    gfx.invalidateAll()
    app.changed()
    app.save(true)
    goTab("sprite")
    app.say("NEW " .. setup.mode .. " GAME")
  end
  if setup.cancelable then
    if ui.button(110, 198, 100, 14, "CANCEL") then goTab("games") end
  end
  gfx.setc(gfx.DIM)
  gfx.textCentered("SAVES TO RETROARCH'S SAVE FOLDER", 0, 226, 320, 1)
end

-- ── cursor ──────────────────────────────────────────────────────────────
local ARROW = {
  "B......", "BB.....", "BWB....", "BWWB...", "BWWWB..", "BWWWWB.",
  "BWWWWWB", "BWWBBBB", "BWB....", "BB.....",
}
local function drawCursor()
  local x, y = math.floor(input.cx), math.floor(input.cy)
  for r = 1, #ARROW do
    local row = ARROW[r]
    for c = 1, #row do
      local ch = row:sub(c, c)
      if ch == "B" then gfx.setc(gfx.BLACK); gfx.rect(x + c - 1, y + r - 1, 1, 1)
      elseif ch == "W" then gfx.setc(gfx.WHITE); gfx.rect(x + c - 1, y + r - 1, 1, 1) end
    end
  end
end

function G.draw()
  local lg = G.graphics
  if DESKTOP_SCALE ~= 1 then lg.push(); lg.scale(DESKTOP_SCALE, DESKTOP_SCALE) end
  if splash.active then
    splash.draw()
    if DESKTOP_SCALE ~= 1 then lg.pop() end
    return
  end

  gfx.setc(gfx.BG)
  gfx.rect(0, 0, 320, 240)

  if keyboard.active then
    keyboard.draw()                   -- full screen while typing
  elseif app.tab == "games" then
    games.draw()
  elseif app.tab == "setup" or not app.P then
    drawSetup()
  else
    -- draw the active screen first so its clicks are handled before the bar
    if app.tab == "sprite" then spriteEd.draw()
    elseif app.tab == "map" then mapEd.draw()
    elseif app.tab == "play" then play.draw() end
    if app.tab ~= "play" then drawTopBar() end     -- play mode gets the whole screen
  end

  if input.cursorOn or (keyboard.active and input.mouseUsed) then drawCursor() end
  if DESKTOP_SCALE ~= 1 then lg.pop() end
end

-- ── input callbacks ─────────────────────────────────────────────────────
function G.gamepadpressed(a, b)  input.padPressed(a, b) end
function G.gamepadreleased(a, b) input.padReleased(a, b) end
function G.keypressed(k)  input.keyPressed(k) end
function G.keyreleased(k) input.keyReleased(k) end
