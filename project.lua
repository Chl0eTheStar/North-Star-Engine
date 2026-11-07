-- Project data + saving/loading.
--
-- A project is a plain Lua table:
--   P.mode    "platformer", "topdown" or "raycast" (first-person, Doom-style)
--   P.tile    8 or 16  (every sprite is this size, and so is the map grid)
--   P.sprites { {name, kind, size, frames = { {0,1,0,...}, ... }}, ... }
--   P.scenes  { {name, w, h, tiles = {spriteIndex or 0, ...},          (row-major, w*h)
--                bg = {...same shape: the parallax background layer},
--                bgSpeed = 0..1  (how fast the background scrolls vs the map),
--                stack = { level1, level2, ... }  (raycast: each level is a grid
--                  like tiles; level k sits on top of level k-1 in that cell)}, ... }
--
-- It is saved as a Lua file ("return { ... }") and loaded back by running it.
-- A frame is a list of palette indexes (0 = transparent, 1..16 = a color),
-- written as one character per pixel to keep the file small: "." for
-- transparent and 0-9 a-f for colors 1-16 (the color's hex digit, minus one).
--
-- Where it saves: Lutro's filesystem.write only writes inside the game's own
-- folder, and a zipped .lutro is deleted when you quit. So on Lutro we write
-- with Lua's io library into RetroArch's save folder instead, which survives
-- both ways of launching. Desktop LÖVE uses its normal save folder.

local project = {}

local G  = lutro or love
local fs = G.filesystem

project.FILE = "lutrofx_project.lua"

-- ── sprite kinds (what a sprite DOES when placed on the map) ──────────────
project.KINDS = {"player", "solid", "decor", "coin", "hazard", "enemy", "goal",
                 "breakable", "platform", "melee", "gun", "text",
                 "ladder", "falling", "battle", "floor", "ceiling",
                 "doublejump", "walljump"}
project.KIND_COLOR = {
  player = {0, 204, 255},  solid = {220, 220, 220}, decor = {140, 150, 170},
  coin   = {255, 215, 0},  hazard = {255, 130, 60}, enemy = {255, 90, 90},
  goal   = {0, 255, 136},  breakable = {215, 170, 120}, platform = {175, 145, 255},
  melee  = {255, 140, 200}, gun = {200, 255, 120}, text = {255, 238, 150},
  ladder = {215, 165, 95}, falling = {150, 200, 255}, battle = {255, 110, 200},
  floor = {120, 160, 110}, ceiling = {200, 190, 150},
  doublejump = {120, 255, 230}, walljump = {255, 200, 120},
}
project.KIND_HINT = {
  player = "WHERE YOU START", solid = "WALLS + FLOOR", decor = "SCENERY, NO COLLISION",
  coin = "COLLECT IT", hazard = "HURTS ON TOUCH", enemy = "HURTS YOU. PICK A BEHAVIOR",
  goal = "NEXT SCENE / WIN", breakable = "SOLID. ATTACK OR HEAD-BUMP IT",
  platform = "MOVES BACK AND FORTH",
  melee = "PICKUP: USE M. ANIMATIONS", gun = "PICKUP: USE G. ANIMATIONS",
  text = "SHOWS A MESSAGE",
  ladder = "CLIMB WITH UP / DOWN (PLATFORMER)",
  falling = "DROPS IF YOU STAND ON IT TOO LONG",
  battle = "TURN-BASED FIGHT WHEN YOU TOUCH IT",
  floor = "FLAT ON THE FLOOR (FIRST-PERSON)",
  ceiling = "FLAT ON THE CEILING (FIRST-PERSON)",
  doublejump = "PICKUP: DOUBLE JUMP FOR THE REST OF THE GAME",
  walljump = "PICKUP: WALL JUMP FOR THE REST OF THE GAME",
}

-- ── text objects ─────────────────────────────────────────────────────────
-- A text sprite holds one message (spr.text) and when it shows (spr.trigger):
--   touch  when the player walks into it (spr.once: only the first time)
--   start  as soon as the scene begins
--   finish when the player reaches the goal, before the next scene
-- With no art drawn it's invisible in play: an invisible trigger zone.
project.TRIGGERS = {"touch", "start", "finish"}
project.TRIGGER_NAME = {touch = "ON TOUCH", start = "SCENE START", finish = "SCENE END"}
project.TEXT_MAX = 300      -- characters per message
project.TEXT_WIDTH = 74     -- characters per line in the text box
project.TEXT_LINES = 4      -- lines per page of the text box

-- ── enemy behaviors (set per enemy sprite; each sprite is one enemy type) ──
project.BEHAVIORS = {"walker", "hopper", "flyer", "chaser", "shooter"}
project.BEHAVIOR_HINT = {
  walker  = "WALKS BACK AND FORTH",
  hopper  = "HOPS AROUND",
  flyer   = "FLIES IN A WAVE, NO GRAVITY",
  chaser  = "COMES AFTER YOU WHEN CLOSE",
  shooter = "STANDS STILL AND SHOOTS AT YOU",
}

-- ── animations ───────────────────────────────────────────────────────────
-- Every sprite has a list of named animations: spr.anims = { {name, frames}, ... }
-- The play-test picks one by name, so a player sprite gets a preset list that
-- matches the game type. Anything you leave blank falls back to something
-- sensible (Walk Right mirrors Walk Left, Fall uses Jump, empty uses Idle...).
local PRESETS = {
  player_platformer = {"Idle", "Walk", "Jump", "Fall", "Attack", "Hurt"},
  player_topdown    = {"Idle", "Walk Down", "Walk Up", "Walk Left", "Walk Right", "Attack", "Hurt"},
  enemy  = {"Walk", "Attack", "Hurt"},
  coin   = {"Spin"},
  breakable = {"Idle", "Breaking"},
  platform  = {"Idle"},
}

-- Does the project have a melee / gun pickup? Then players get those sets.
function project.weaponSets(P)
  local melee, gun = false, false
  for _, s in ipairs(P and P.sprites or {}) do
    if s.kind == "melee" then melee = true elseif s.kind == "gun" then gun = true end
  end
  return melee, gun
end

-- Player animations: the base set, plus "M." and "G." copies of it (minus
-- Hurt) when the project has a melee or gun pickup. An empty "M.Walk" falls
-- back to "Walk" in play, so you only draw what changes when holding it.
function project.presets(kind, mode, P)
  if kind == "player" then
    -- raycast games look at the world from above-less first person: their player
  -- has no sprite on screen, so it uses the top-down set
  local m = (mode == "raycast") and "topdown" or (mode or "platformer")
  local base = PRESETS["player_" .. m]
    local out = {}
    for _, n in ipairs(base) do out[#out + 1] = n end
    local melee, gun = project.weaponSets(P)
    local function add(prefix)
      for _, n in ipairs(base) do if n ~= "Hurt" then out[#out + 1] = prefix .. n end end
    end
    if melee then add("M.") end
    if gun then add("G.") end
    return out
  end
  return PRESETS[kind] or {"Default"}
end

local function frameHasArt(f)
  for i = 1, #f do if f[i] ~= 0 then return true end end
  return false
end
function project.animHasArt(a)
  if not a then return false end
  for _, f in ipairs(a.frames) do if frameHasArt(f) then return true end end
  return false
end

-- Index of the named animation if it has any drawing in it, else nil
function project.findAnim(spr, name)
  for i, a in ipairs(spr.anims) do
    if a.name == name and project.animHasArt(a) then return i end
  end
  return nil
end

-- The animation used for thumbnails and map tiles: first one with art
function project.thumbAnim(spr)
  for i, a in ipairs(spr.anims) do if project.animHasArt(a) then return i end end
  return 1
end

-- Make sure a sprite has every preset animation for its kind (keeps drawings,
-- adds blank ones, keeps extra ones at the end so nothing is ever lost)
function project.ensureAnims(spr, mode, P)
  local want = project.presets(spr.kind, mode, P)
  local byName, out, used = {}, {}, {}
  for _, a in ipairs(spr.anims or {}) do byName[a.name] = byName[a.name] or a end
  for _, name in ipairs(want) do
    local a = byName[name]
    if not a then a = {name = name, frames = {project.blankFrame(spr.size)}} end
    out[#out + 1] = a; used[a] = true
  end
  -- changing kind: the drawing in the old first animation moves to the new first
  local first = spr.anims and spr.anims[1]
  if first and not used[first] and project.animHasArt(first) and not project.animHasArt(out[1]) then
    out[1].frames = first.frames
    used[first] = true
  end
  -- any other drawn animation that no longer has a preset slot is kept at the end
  for _, a in ipairs(spr.anims or {}) do
    if not used[a] and project.animHasArt(a) then out[#out + 1] = a; used[a] = true end
  end
  spr.anims = out
end

-- ── constructors ─────────────────────────────────────────────────────────
function project.blankFrame(size)
  local f = {}
  for i = 1, size * size do f[i] = 0 end
  return f
end
local blankFrame = project.blankFrame

function project.newSprite(P, kind)
  local spr = {name = "SPR" .. (#P.sprites + 1), kind = kind or "solid", size = P.tile, anims = {}}
  project.ensureAnims(spr, P.mode, P)
  return spr
end

-- parallax speeds you can pick for a scene's background (0 = stays put)
project.BG_SPEEDS = {0, 0.25, 0.5, 0.75}

function project.newScene(P, w, h)
  local tiles, bg = {}, {}
  for i = 1, w * h do tiles[i] = 0; bg[i] = 0 end
  return {name = "SCENE " .. (#P.scenes + 1), w = w, h = h, tiles = tiles, bg = bg, bgSpeed = 0.5,
          stack = {}}
end

-- ── raycast stacks ────────────────────────────────────────────────────────
-- In raycast games a cell can hold several wall pieces, one on top of another
-- (a tree is a trunk with leaves on top; a building is walls with a roof).
-- sc.stack[k][i] is the sprite at level k of cell i; levels are filled from the
-- bottom, so the height is the number of levels that are filled.
project.MAX_STACK = 6

function project.stackHeight(sc, i)
  local h = 0
  while sc.stack[h + 1] and (sc.stack[h + 1][i] or 0) ~= 0 do h = h + 1 end
  return h
end

-- Put sprite v on top of cell i. False when the cell is already MAX_STACK tall.
function project.pushStack(sc, i, v)
  local h = project.stackHeight(sc, i)
  if h >= project.MAX_STACK then return false end
  local k = h + 1
  if not sc.stack[k] then
    local grid = {}
    for n = 1, sc.w * sc.h do grid[n] = 0 end
    sc.stack[k] = grid
  end
  sc.stack[k][i] = v
  return true
end

-- Take the top piece off cell i. Returns the sprite index it was (0 = none).
function project.popStack(sc, i)
  local h = project.stackHeight(sc, i)
  if h == 0 then return 0 end
  local v = sc.stack[h][i]
  sc.stack[h][i] = 0
  return v
end

-- every tile layer in a scene (main + background), for code that edits all of them
function project.layers(sc)
  local out = {sc.tiles, sc.bg}
  for _, grid in ipairs(sc.stack or {}) do out[#out + 1] = grid end
  return out
end

function project.new(mode, tile)
  local P = {version = 3, mode = mode, tile = tile, sprites = {}, scenes = {}}
  -- 20x12 tiles of 8px = 160x96: a bit bigger than the Arduboy's 128x64 screen
  local w, h = 32, 16
  if tile == 16 then w, h = 24, 12 end
  P.scenes[1] = project.newScene(P, w, h)
  return P
end

-- Resize a scene, keeping whatever fits
function project.resizeScene(sc, w, h)
  local function resized(layer)
    local out = {}
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        local v = 0
        if x < sc.w and y < sc.h then v = layer[y * sc.w + x + 1] or 0 end
        out[y * w + x + 1] = v
      end
    end
    return out
  end
  sc.tiles, sc.bg = resized(sc.tiles), resized(sc.bg)
  for k, grid in ipairs(sc.stack or {}) do sc.stack[k] = resized(grid) end
  sc.w, sc.h = w, h
end

-- Deleting sprite i shifts every later sprite down one slot, so fix up maps
function project.deleteSprite(P, i)
  table.remove(P.sprites, i)
  for _, sc in ipairs(P.scenes) do
    for _, layer in ipairs(project.layers(sc)) do
      for t = 1, #layer do
        local v = layer[t]
        if v == i then layer[t] = 0
        elseif v > i then layer[t] = v - 1 end
      end
    end
  end
end

-- Projects saved before colors (version 1-2) were 1-bit and tinted by kind;
-- their lit pixels become the palette color closest to that old tint.
project.KIND_DEFAULT_COLOR = {
  player = 13, solid = 4, decor = 3, coin = 14, hazard = 15, enemy = 12,
  goal = 10, breakable = 7, platform = 8, melee = 16, gun = 10, text = 11,
}

local HEX = "0123456789abcdef"
local function encodeFrame(f)
  local out = {}
  for i = 1, #f do
    local v = f[i]
    out[i] = (v == 0) and "." or HEX:sub(v, v)
  end
  return table.concat(out)
end

local function decodeFrame(str, oneBitColor)
  local frame = {}
  for i = 1, #str do
    local ch = str:sub(i, i)
    if oneBitColor then
      frame[i] = (ch == "1") and oneBitColor or 0          -- old 1-bit save
    elseif ch == "." then
      frame[i] = 0
    else
      frame[i] = (HEX:find(ch, 1, true) or 4)
    end
  end
  return frame
end

-- ── serialising ──────────────────────────────────────────────────────────
local function isArray(t)
  local n = #t
  local count = 0
  for _ in pairs(t) do count = count + 1 end
  return count == n
end

local function ser(v, out, indent)
  local tv = type(v)
  if tv == "number" then
    if v == math.floor(v) then out[#out + 1] = string.format("%d", v)
    else out[#out + 1] = string.format("%.4f", v) end
  elseif tv == "string" then
    out[#out + 1] = string.format("%q", v)
  elseif tv == "boolean" then
    out[#out + 1] = v and "true" or "false"
  elseif tv == "table" then
    if isArray(v) then
      -- arrays of numbers go on one line
      local flat = true
      for i = 1, #v do if type(v[i]) == "table" then flat = false; break end end
      out[#out + 1] = "{"
      for i = 1, #v do
        if not flat then out[#out + 1] = "\n" .. indent .. "  " end
        ser(v[i], out, indent .. "  ")
        out[#out + 1] = ","
      end
      if not flat then out[#out + 1] = "\n" .. indent end
      out[#out + 1] = "}"
    else
      local keys = {}
      for k in pairs(v) do keys[#keys + 1] = k end
      table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
      out[#out + 1] = "{"
      for _, k in ipairs(keys) do
        out[#out + 1] = "\n" .. indent .. "  "
        if type(k) == "string" and k:match("^[%a_][%w_]*$") then out[#out + 1] = k
        else out[#out + 1] = "["; ser(k, out, indent); out[#out + 1] = "]" end
        out[#out + 1] = " = "
        ser(v[k], out, indent .. "  ")
        out[#out + 1] = ","
      end
      out[#out + 1] = "\n" .. indent .. "}"
    end
  end
end

-- Copy of P ready for writing: frames become "0101..." strings
local function packed(P)
  local copy = {version = P.version, mode = P.mode, tile = P.tile, sprites = {}, scenes = P.scenes}
  for i, s in ipairs(P.sprites) do
    local anims = {}
    for a, an in ipairs(s.anims) do
      local frames = {}
      for f = 1, #an.frames do frames[f] = encodeFrame(an.frames[f]) end
      anims[a] = {name = an.name, frames = frames}
    end
    local out = {}
    for key, val in pairs(s) do
      if key ~= "anims" and type(val) ~= "table" then out[key] = val end   -- name, kind, settings...
    end
    out.anims = anims
    copy.sprites[i] = out
  end
  return copy
end

local function unpacked(D)
  local oldOneBit = (D.version or 1) < 3
  local function decode(list, kind)
    local oneBit = oldOneBit and (project.KIND_DEFAULT_COLOR[kind] or 4) or nil
    for f = 1, #list do
      if type(list[f]) == "string" then list[f] = decodeFrame(list[f], oneBit) end
    end
  end
  for _, s in ipairs(D.sprites or {}) do
    if s.frames and not s.anims then          -- saves from v1: one frame list
      s.anims = {{name = project.presets(s.kind, D.mode)[1], frames = s.frames}}
      s.frames = nil
    end
    for _, a in ipairs(s.anims) do decode(a.frames, s.kind) end
    project.ensureAnims(s, D.mode, D)
  end
  D.sprites = D.sprites or {}
  D.scenes  = D.scenes or {}
  D.version = 3                          -- converted: saves in the new format from now on
  for _, sc in ipairs(D.scenes) do       -- older saves have no background layer
    if not sc.bg then
      sc.bg = {}
      for i = 1, sc.w * sc.h do sc.bg[i] = 0 end
    end
    sc.bgSpeed = sc.bgSpeed or 0.5
    sc.stack = sc.stack or {}              -- older saves have no raycast stacks
  end
  return D
end

function project.serialize(P)
  local out = {"-- LutroFX IDE project\nreturn "}
  ser(packed(P), out, "")
  out[#out + 1] = "\n"
  return table.concat(out)
end

-- ── storage ──────────────────────────────────────────────────────────────
-- Every game is its own file in RetroArch's save folder:
--   lutrofx_game_1.lua ... lutrofx_game_12.lua   (plus a .bak of the last save)
--   lutrofx_last.txt                             (which game was open last)
-- Lutro can't list folders, so slots are found by trying to open each file.
local loadChunk = loadstring or load

project.MAX_SLOTS = 12
project.LEGACY_FILE = project.FILE        -- single-project saves from before slots
project.LAST_FILE = "lutrofx_last.txt"

function project.slotFile(n) return "lutrofx_game_" .. n .. ".lua" end

-- Absolute path in RetroArch's save folder, or nil (desktop LÖVE)
local function savePath(name)
  if lutro and fs.getUserDirectory then
    local ok, dir = pcall(fs.getUserDirectory)
    if ok and dir and dir ~= "" then return dir .. name end
  end
  return nil
end

function project.wherePath(name)
  name = name or project.slotFile(1)
  return savePath(name) or name
end

local function fsExists(name)
  if fs.getInfo then return fs.getInfo(name) ~= nil end
  if fs.exists then return fs.exists(name) end
  return false
end

local function readFile(name)
  local p = savePath(name)
  if p then
    local f = io.open(p, "r")
    if f then local d = f:read("*a"); f:close(); return d end
    return nil
  end
  if fsExists(name) then
    local d = fs.read(name)
    if type(d) == "string" then return d end
  end
  return nil
end

-- backup: keep the file being replaced as name.bak
local function writeFile(name, data, backup)
  local p = savePath(name)
  if p then
    if backup then os.remove(p .. ".bak"); os.rename(p, p .. ".bak") end
    local f = io.open(p, "w")
    if f then f:write(data); f:close(); return true, p end
    return false, "could not write " .. name
  end
  local ok, res = pcall(fs.write, name, data)
  if ok and res then return true, name end
  return false, "could not write " .. name
end

local function fileExists(name)
  local p = savePath(name)
  if p then
    local f = io.open(p, "r")
    if f then f:close(); return true end
    return false
  end
  return fsExists(name)
end

local function parse(data)
  local chunk, err = loadChunk(data, "project")
  if not chunk then return nil, "bad save: " .. tostring(err) end
  local ok, D = pcall(chunk)
  if not ok or type(D) ~= "table" then return nil, "bad save" end
  local ok2, P = pcall(unpacked, D)
  if not ok2 or type(P) ~= "table" then return nil, "bad save" end
  return P
end

function project.slotExists(n) return fileExists(project.slotFile(n)) end

-- Returns P or nil, errorMessage
function project.loadSlot(n)
  local data = readFile(project.slotFile(n))
  if not data then return nil, "empty slot" end
  return parse(data)
end

-- Returns true, where or false, errorMessage. Keeps the previous save as .bak
function project.saveSlot(P, n)
  return writeFile(project.slotFile(n), project.serialize(P), true)
end

-- Moves the game to lutrofx_game_N.lua.bak, so a slip can still be rescued
-- by renaming the file on the SD card.
function project.deleteSlot(n)
  local name = project.slotFile(n)
  local p = savePath(name)
  if p then
    os.remove(p .. ".bak")
    return os.rename(p, p .. ".bak") ~= nil
  end
  if fs.remove then return fs.remove(name) end
  return false
end

function project.firstEmptySlot()
  for n = 1, project.MAX_SLOTS do
    if not project.slotExists(n) then return n end
  end
  return nil
end

function project.lastSlot()
  local d = readFile(project.LAST_FILE)
  local n = d and tonumber(d:match("%d+"))
  if n and n >= 1 and n <= project.MAX_SLOTS and project.slotExists(n) then return n end
  for i = 1, project.MAX_SLOTS do
    if project.slotExists(i) then return i end
  end
  return nil
end

function project.setLastSlot(n)
  writeFile(project.LAST_FILE, tostring(n) .. "\n", false)
end

-- A save from before slots (lutrofx_project.lua) becomes game 1. The old
-- file is renamed to .migrated so it isn't imported a second time.
function project.migrateLegacy()
  local data = readFile(project.LEGACY_FILE)
  if not data then return false end
  local n = project.firstEmptySlot()
  if not n then return false end
  if not writeFile(project.slotFile(n), data, false) then return false end
  local p = savePath(project.LEGACY_FILE)
  if p then os.remove(p .. ".migrated"); os.rename(p, p .. ".migrated") end
  return n
end

return project
