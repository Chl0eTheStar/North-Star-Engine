-- Shared editor state, so every screen sees the same project.

local project = require("lib.project")

local app = {
  P      = nil,        -- the project table (see lib/project.lua)
  slot   = nil,        -- which saved game (1..project.MAX_SLOTS) is open
  tab    = "sprite",   -- "sprite" | "map" | "play" | "setup" | "games"
  scene  = 1,          -- scene being edited / played
  sprite = 1,          -- sprite being edited
  dirty  = false,      -- unsaved changes
  status = "",
  statusT = 0,
  time   = 0,          -- seconds since start
  lastSave = 0,
}

function app.say(msg, seconds)
  app.status = string.upper(msg)
  app.statusT = seconds or 3
end

function app.changed() app.dirty = true end

function app.save(quiet)
  if not app.P or not app.slot then return end
  local ok, where = project.saveSlot(app.P, app.slot)
  if ok then
    app.dirty = false
    app.lastSave = app.time
    project.setLastSlot(app.slot)
    if not quiet then app.say("SAVED") else app.say("AUTOSAVED", 1.5) end
  else
    app.say("SAVE FAILED: " .. tostring(where), 5)
  end
end

-- Switch to another game (P already loaded from slot n)
function app.open(P, n)
  app.P, app.slot = P, n
  app.scene, app.sprite = 1, 1
  app.dirty = false
  app.lastSave = app.time
  project.setLastSlot(n)
  if app.onOpen then app.onOpen() end   -- editors reset their per-game state
end

return app
