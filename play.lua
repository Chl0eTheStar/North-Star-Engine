-- PLAY tab: runs the current scene as a game at 160x120, drawn at 2x so it
-- fills the 320x240 screen pixel-perfectly (and 4:3, like most handhelds).
-- Platformer or top-down rules depending on the project.
--
-- What each sprite kind does:
--   player     where you start            solid     blocks movement
--   decor      scenery                    coin      collect it
--   hazard     hurts on touch             enemy     hurts you; behavior set per sprite
--   goal       next scene (or win)        breakable solid until you hit it
--   platform   moves back and forth; in platformers you can ride it and jump
--              up through it, in top-down games it's a moving wall that pushes
--   melee/gun  pickups: the player switches to its "M." / "G." animations,
--              melee swings further with a slash effect, the gun shoots
--   ladder     hold up / down on it to climb (no gravity); jump lets go
--   falling    a platform that drops if you stand on it too long, then
--              comes back
--   battle     a turn-based fight on touch; the rules match the Arduboy/web
--              engine's battle (see BATTLE below)
--
-- RAYCAST games (P.mode == "raycast") are first-person, Doom-style. Walls are
-- the stacked wall pieces (solid / breakable sprites on the stack layer; see
-- lib/raycast.lua), and everything else stands in its cell as a flat sprite:
-- battle sprites start fights when you walk into them, coins are collected,
-- text shows, goal is the next scene, hazards hurt. Other kinds are scenery.

local gfx     = require("lib.gfx")
local input   = require("lib.input")
local project = require("lib.project")
local app     = require("lib.app")
local RC      = require("lib.raycast")

local floor = math.floor

-- ── GAME FEEL ──────────────────────────────────────────────────────────
-- Every tuning number lives here. Speeds are in pixels per frame for 8px
-- tiles (16px projects scale them up automatically); times are in frames
-- (60 per second). Change one, re-launch, feel the difference.
local FEEL = {
  -- running
  MOVE          = 0.9,   -- top speed (was 1.1: slowed to match his walk animation)
  ACCEL         = 0.22,  -- speed gained per frame on the ground
  AIR_ACCEL     = 0.16,  -- ...and in the air (lower = floatier steering)
  FRICTION      = 0.28,  -- speed lost per frame when you let go, on the ground
  AIR_FRICTION  = 0.06,  -- ...and in the air (low = you keep drifting)

  -- jumping
  JUMP          = 2.2,   -- launch speed (was 2.4: a little weaker)
  GRAVITY_UP    = 0.10,  -- gravity while rising with jump held
  GRAVITY_CUT   = 0.26,  -- gravity while rising after you let go (short hops)
  GRAVITY_DOWN  = 0.13,  -- gravity while falling
  MAX_FALL      = 4.0,   -- terminal velocity
  APEX_RANGE    = 0.45,  -- near the top of a jump (|speed| below this)...
  APEX_GRAVITY  = 0.5,   -- ...gravity is multiplied by this: a little hang time
  COYOTE        = 6,     -- frames you can still jump after walking off a ledge
  BUFFER        = 8,     -- frames a jump press is remembered before landing
  CORNER        = 2,     -- pixels you get nudged sideways around ceiling corners
  DOUBLE_JUMP   = 0.92,  -- double jump strength compared to a normal jump
  WALL_SLIDE    = 0.6,   -- max fall speed while sliding down a wall
  WALL_KICK     = 10,    -- frames a wall jump pushes you away from the wall
  DROP_THROUGH  = 12,    -- frames you fall through a platform after down + jump
  CLIMB         = 0.8,   -- ladders: climbing speed (pixels per frame, 8px tiles)

  -- top-down
  TOPDOWN_MOVE  = 1.0,

  -- impact
  HITSTOP_STOMP = 4,     -- frames the game freezes when you stomp an enemy
  HITSTOP_HIT   = 3,     -- ...when your attack lands
  SHAKE_HURT    = 8,     -- frames the screen shakes when you get hurt
  SHAKE_HIT     = 3,     -- ...when you hit something
  SHAKE_BREAK   = 3,     -- ...when a block breaks

  -- weapons
  ATTACK_TIME   = 14,    -- frames an unarmed attack lasts (reach: 1 tile)
  MELEE_TIME    = 14,    -- frames a melee swing lasts
  MELEE_REACH   = 1.5,   -- melee reach, in tiles
  GUN_TIME      = 10,    -- frames the G.Attack animation plays per shot
  GUN_COOLDOWN  = 14,    -- frames between shots
  BULLET_SPEED  = 3.0,
  BULLET_LIFE   = 80,    -- frames before a bullet fizzles out
  FLASH_TIME    = 4,     -- frames the muzzle flash shows

  -- enemies (behavior, HP and speed are set on each enemy sprite)
  ENEMY_SPEEDS  = {0.3, 0.5, 0.8},   -- slow / medium / fast
  ENEMY_HURT    = 20,    -- frames an enemy is stunned (and plays Hurt) after a hit
  KNOCKBACK     = 3,     -- pixels an enemy is pushed back when hit
  HOP_EVERY     = 70,    -- hopper: frames between hops
  HOP_POWER     = 2.2,   -- hopper: jump strength
  FLY_WAVE      = 0.75,  -- flyer: how far up and down it bobs, in tiles
  FLY_PERIOD    = 120,   -- flyer: frames per full up-and-down
  CHASE_RANGE   = 6,     -- chaser: notices you within this many tiles
  CHASE_BOOST   = 1.4,   -- chaser: speed multiplier while chasing
  SHOOT_RANGE   = 8,     -- shooter: fires when you're within this many tiles
  SHOOT_EVERY   = 90,    -- shooter: frames between shots
  ENEMY_BULLET  = 0.8,   -- shooter: bullet speed (was 1.5: slow enough to dodge)
  ENEMY_ATTACK  = 16,    -- frames a shooter shows its Attack animation after firing

  -- blocks + platforms
  BREAK_FRAME   = 5,     -- frames each Breaking animation frame shows
  PLATFORM_SPEEDS = {0.35, 0.6, 1.0},   -- slow / medium / fast

  -- falling platforms
  FALL_DELAY    = 75,    -- frames you can stand on one before it starts to fall
  FALL_SHAKE    = 20,    -- ...it shakes during the last of those frames
  FALL_GRAVITY  = 0.15,  -- how fast it picks up speed as it drops
  FALL_RESPAWN  = 180,   -- frames after it drops before it comes back
}

local Play = {}
local st = nil

local VIEW_W, VIEW_H, SCALE = 160, 120, 2
local VX, VY = 0, 0                   -- the game view is the whole screen
local STEP = 1 / 60

-- ── RAYCAST MOVEMENT ──────────────────────────────────────────────────
-- Cells and radians per frame (60 frames a second). Left/right turn; hold X
-- to strafe instead.
local RAY = {
  TURN   = 0.045,
  MOVE   = 0.05,
  STRAFE = 0.04,
  RADIUS = 0.22,     -- how close you can get to a wall (in cells)
  HAZARD_INV = 60,   -- frames of safety after a hazard hurts you
}

-- ── text box ───────────────────────────────────────────────────────────
-- Messages from text objects. The game pauses while one is up. Text types
-- itself out; A/B shows it all, then turns the page, then closes it.
-- More messages wait in a queue; st.afterText runs once the queue is empty.
local TYPE_SPEED = 1          -- characters revealed per frame

function Play.showText(text)
  local lines = gfx.wrap(text, project.TEXT_WIDTH)
  local pages = {}
  for i = 1, #lines, project.TEXT_LINES do
    local pg = {}
    for j = i, math.min(#lines, i + project.TEXT_LINES - 1) do pg[#pg + 1] = lines[j] end
    pages[#pages + 1] = pg
  end
  local d = {pages = pages, page = 1, shown = 0, t = 0}
  if st.dialog then st.dqueue[#st.dqueue + 1] = d else st.dialog = d end
end

local function pageLen(pg)
  local n = 0
  for _, l in ipairs(pg) do n = n + #l end
  return n
end

local function updateDialog()
  local d = st.dialog
  d.t = d.t + 1
  local total = pageLen(d.pages[d.page])
  if d.shown < total then d.shown = math.min(total, d.shown + TYPE_SPEED) end
  if input.pressed.a or input.pressed.b then
    if d.shown < total then
      d.shown = total                         -- skip the typing
    elseif d.page < #d.pages then
      d.page, d.shown = d.page + 1, 0
    else
      st.dialog = table.remove(st.dqueue, 1)
      if not st.dialog and st.afterText then
        local f = st.afterText
        st.afterText = nil
        f()
      end
    end
  end
  -- the press that closes the box mustn't also jump or attack
  if st.player then st.player.buffer = 0 end
end

-- ── world building ─────────────────────────────────────────────────────
-- Raycast scene: walls from the stack layer, everything else as entities
-- standing in their cell. Fills st.rc (the view state) and st.ents.
local function loadRaycast(index, keep)
  local P = app.P
  local sc = P.scenes[index]

  st.sceneIdx = index
  local rc = {W = sc.w, H = sc.h, walls = {}, ents = {}, cellEnt = {}, zbuf = {},
              x = 0.5, y = 0.5, a = -math.pi / 2, lastCell = nil,
              atk = 0, atkMax = 1, cool = 0, moving = false}
  st.rc = rc
  st.ents, st.battle = rc.ents, nil
  st.grid, st.solid, st.breaks, st.plats, st.ladder = {}, {}, {}, {}, {}
  st.bullets, st.ebullets = {}, {}
  st.startTexts, st.endTexts = {}, {}
  st.dialog, st.dqueue = nil, {}
  st.coins = keep and st.coins or 0
  if not keep then st.hp = st.maxHp end
  st.state = "noplayer"
  st.player = nil
  st.inv = 0
  st.freeze, st.shake = 0, 0
  st.msg, st.msgT = sc.name, 90

  -- walls: the stacked pieces of each cell, bottom first
  for i = 1, sc.w * sc.h do
    local pieces = {}
    for k = 1, #sc.stack do
      local v = sc.stack[k][i] or 0
      if v == 0 or not P.sprites[v] then break end
      pieces[#pieces + 1] = P.sprites[v]
    end
    if #pieces > 0 then rc.walls[i] = pieces end
  end

  -- everything else, one per cell
  for y = 0, sc.h - 1 do
    for x = 0, sc.w - 1 do
      local i = y * sc.w + x + 1
      local v = sc.tiles[i]
      local spr = P.sprites[v]
      if spr and spr.kind == "player" then
        st.player = {spr = spr, buffer = 0}
        rc.x, rc.y = x + 0.5, y + 0.5
        rc.lastCell = i                       -- standing on a thing at the start doesn't use it
        st.state = "play"
      elseif spr and spr.kind ~= "solid" and spr.kind ~= "breakable" then
        local e = {kind = spr.kind, spr = spr, cx = x + 0.5, cy = y + 0.5, cell = i,
                   alive = true, cool = 0}
        if spr.kind == "enemy" then e.hpLeft = spr.hp or 1 end
        if spr.kind == "battle" then
          e.battle = spr.battle or {}
          e.intro = spr.text or ""
          e.repeatable = e.battle.repeatable and true or false
          e.inside = false
          e.hpLeft = e.battle.hp or 4          -- a weapon hit wears this down
        end
        if spr.kind == "text" then
          e.text, e.trigger, e.once = spr.text or "", spr.trigger or "touch", spr.once
          if e.text ~= "" then
            if e.trigger == "start" then st.startTexts[#st.startTexts + 1] = e.text end
            if e.trigger == "finish" then st.endTexts[#st.endTexts + 1] = e.text end
          end
        end
        rc.ents[#rc.ents + 1] = e
        rc.cellEnt[i] = e
      end
    end
  end
  if st.player then
    for _, t in ipairs(st.startTexts) do Play.showText(t) end
  end
end

local function loadScene(index, keep)
  if app.P.mode == "raycast" then return loadRaycast(index, keep) end
  local P = app.P
  local sc = P.scenes[index]
  local T = P.tile
  local k = T / 8

  st.sceneIdx = index
  st.bg, st.bgSpeed = sc.bg, sc.bgSpeed or 0.5
  st.T, st.k = T, k
  st.W, st.H = sc.w, sc.h
  st.grid, st.solid, st.ents, st.breaks, st.plats, st.bullets, st.ebullets = {}, {}, {}, {}, {}, {}, {}
  st.ladder, st.battle = {}, nil
  st.player = nil
  st.startTexts, st.endTexts = {}, {}   -- messages in reading order (left-right, top-bottom)
  st.dialog, st.dqueue = nil, {}
  st.coins, st.totalCoins = keep and st.coins or 0, 0
  if not keep then st.hp = st.maxHp end

  local platTiles = {}
  for y = 0, sc.h - 1 do
    for x = 0, sc.w - 1 do
      local i = y * sc.w + x + 1
      local v = sc.tiles[i]
      local spr = P.sprites[v]
      st.grid[i], st.solid[i] = 0, false
      if spr then
        local kind = spr.kind
        if kind == "solid" or kind == "decor" or kind == "floor" or kind == "ceiling" then
          st.grid[i] = v
          st.solid[i] = (kind == "solid")
        elseif kind == "breakable" then
          st.grid[i] = v
          st.solid[i] = true
          st.breaks[i] = {spr = spr, state = "idle", t = 0}
        elseif kind == "ladder" then
          st.grid[i] = v
          st.ladder[i] = true
        elseif kind == "platform" or kind == "falling" then
          platTiles[i] = v
        elseif kind == "player" then
          st.player = {x = x * T + 1, y = y * T, w = T - 2, h = T, vx = 0, vy = 0,
                       spr = spr, face = 1, dir = "down", onGround = false, coyote = 0, buffer = 0,
                       atk = 0, atkCD = 0, atkTime = 1, flash = 0, animName = nil, animT = 0,
                       kick = 0, kickDir = 0, onWall = 0, airJumps = 0,
                       ride = nil, dropT = 0, hitsPlats = (P.mode ~= "platformer")}
          st.startX, st.startY = x * T + 1, y * T
        else
          local e = {kind = kind, spr = spr, x = x * T, y = y * T, w = T, h = T, alive = true, vx = 0, vy = 0}
          if kind == "enemy" then
            local speed = (FEEL.ENEMY_SPEEDS[spr.speed or 2] or 0.5) * k
            e.x, e.w = e.x + 1, T - 2
            e.behavior = spr.behavior or "walker"
            e.hp, e.speed, e.face = spr.hp or 1, speed, -1
            e.vx = (e.behavior == "shooter") and 0 or -speed
            e.baseY, e.hurtT, e.atkT = e.y, 0, 0
            e.t = (x * 7 + y * 13) % 60          -- so identical enemies don't move in lockstep
            e.rng = x * 131 + y * 71 + 1
          end
          if kind == "coin" then st.totalCoins = st.totalCoins + 1 end
          if kind == "battle" then
            e.battle = spr.battle or {}        -- hp, atk, def, boss, repeatable
            e.intro = spr.text or ""           -- the line the enemy says first
            e.repeatable = e.battle.repeatable and true or false
            e.inside, e.cool = false, 0        -- cool: frames until a fled fight can restart
          end
          if kind == "text" then
            e.text, e.trigger, e.once = spr.text or "", spr.trigger or "touch", spr.once
            e.inside = false
            if e.text ~= "" then
              if e.trigger == "start" then st.startTexts[#st.startTexts + 1] = e.text end
              if e.trigger == "finish" then st.endTexts[#st.endTexts + 1] = e.text end
            end
          end
          st.ents[#st.ents + 1] = e
        end
      end
    end
  end

  -- side-by-side platform tiles of the same sprite move together as one
  for y = 0, sc.h - 1 do
    local x = 0
    while x < sc.w do
      local v = platTiles[y * sc.w + x + 1]
      if v then
        local n = 1
        while x + n < sc.w and platTiles[y * sc.w + x + n + 1] == v do n = n + 1 end
        local spr = P.sprites[v]
        local speed = FEEL.PLATFORM_SPEEDS[spr.speed or 2] or FEEL.PLATFORM_SPEEDS[2]
        st.plats[#st.plats + 1] = {
          spr = spr, n = n, x = x * T, y = y * T, w = n * T, h = T,
          x0 = x * T, y0 = y * T, axis = spr.axis or "x",
          range = math.max(1, spr.dist or 3) * T, v = speed * k, dir = 1, dx = 0, dy = 0,
          -- falling platforms (kind "falling") don't move until you stand on them
          fall = spr.kind == "falling" or nil,
          stand = 0, vy = 0, state = "idle", hidden = false, respawnT = 0,
        }
        x = x + n
      else
        x = x + 1
      end
    end
  end

  st.state = st.player and "play" or "noplayer"
  st.inv = 0
  st.freeze, st.shake = 0, 0
  st.msg, st.msgT = sc.name, 90
  if st.player then
    for _, t in ipairs(st.startTexts) do Play.showText(t) end
  end
end

function Play.start()
  -- 5 hearts: the same health as the Arduboy/web hero, which battles are tuned to
  st = {maxHp = 5, t = 0, acc = 0, startScene = app.scene, camX = 0, camY = 0,
        weapon = nil,            -- nil | "melee" | "gun"; kept between scenes
        -- upgrades survive a death restart and scene changes; leaving the play
        -- tab (Play.stop) clears them
        upgrades = (st and st.upgrades) or {}}
  st.hp = st.maxHp
  loadScene(app.scene, false)

end

function Play.stop() st = nil end

-- ── collision ──────────────────────────────────────────────────────────
local function solidAt(x, y, w, h)
  local T = st.T
  local platform = app.P.mode == "platformer"
  local tx0, tx1 = floor(x / T), floor((x + w - 0.001) / T)
  local ty0, ty1 = floor(y / T), floor((y + h - 0.001) / T)
  for ty = ty0, ty1 do
    for tx = tx0, tx1 do
      if tx < 0 or tx >= st.W then return true end
      if ty < 0 then
        if not platform then return true end
      elseif ty >= st.H then
        if not platform then return true end      -- platformers can fall out
      elseif st.solid[ty * st.W + tx + 1] then
        return true
      end
    end
  end
  return false
end

local function overlap(a, b, inset)
  inset = inset or 0
  return a.x < b.x + b.w - inset and a.x + a.w > b.x + inset and
         a.y < b.y + b.h - inset and a.y + a.h > b.y + inset
end

-- Top-down: platforms are moving walls. One you're already inside is ignored
-- so you can always walk out of it instead of getting stuck.
local function platAt(e, x, y)
  local box = {x = x, y = y, w = e.w, h = e.h}
  for _, pl in ipairs(st.plats) do
    if overlap(box, pl) and not overlap(e, pl) then return true end
  end
  return false
end

local function blocked(e, x, y)
  return solidAt(x, y, e.w, e.h) or (e.hitsPlats and platAt(e, x, y))
end

-- Move along one axis in <=1px steps; on hitting something, creep up to it.
local function moveAxis(e, d, axis)
  if d == 0 then return false end
  local dir = d > 0 and 1 or -1
  local rem = math.abs(d)
  while rem > 0 do
    local s = math.min(1, rem)
    rem = rem - s
    local nx, ny = e.x, e.y
    if axis == "x" then nx = nx + s * dir else ny = ny + s * dir end
    if blocked(e, nx, ny) then
      local step = s
      for _ = 1, 4 do
        step = step / 2
        local tx, ty = e.x, e.y
        if axis == "x" then tx = tx + step * dir else ty = ty + step * dir end
        if not blocked(e, tx, ty) then e.x, e.y = tx, ty end
      end
      return true
    end
    e.x, e.y = nx, ny
  end
  return false
end

local function say(m) st.msg, st.msgT = m, 90 end

-- Upgrade pickups: once taken they stay for the rest of the game
local UPGRADE_FLAG = {doublejump = "doubleJump", walljump = "wallJump"}
local UPGRADE_TEXT = {doublejump = "GOT DOUBLE JUMP!", walljump = "GOT WALL JUMP!"}
local function grantUpgrade(e)
  st.upgrades = st.upgrades or {}
  st.upgrades[UPGRADE_FLAG[e.kind]] = true
  e.alive = false
  -- picked up in mid-air: the double jump is usable right away, not after landing
  local p = st.player
  if e.kind == "doublejump" and p and not p.onGround then p.airJumps = 1 end
  say(UPGRADE_TEXT[e.kind])
end

local function impact(freeze, shake)
  st.freeze = math.max(st.freeze, freeze or 0)
  st.shake  = math.max(st.shake, shake or 0)
end

local function hurt(force)
  if st.inv > 0 and not force then return end
  st.hp = st.hp - 1
  st.inv = 60
  impact(2, FEEL.SHAKE_HURT)
  if app.P.mode == "platformer" then st.player.vy = -1.6 * st.k; st.player.ride = nil end
  if st.hp <= 0 then st.state = "dead" end
end

-- ── breakable blocks ───────────────────────────────────────────────────
local function breakAt(i)
  local b = st.breaks[i]
  if b and b.state == "idle" then
    b.state, b.t = "breaking", 0
    st.solid[i] = false                 -- you can pass as soon as it starts breaking
    impact(0, FEEL.SHAKE_BREAK)
    return true
  end
  return false
end

local function breakTilesIn(box)
  local T = st.T
  local hit = false
  for ty = floor(box.y / T), floor((box.y + box.h - 0.001) / T) do
    for tx = floor(box.x / T), floor((box.x + box.w - 0.001) / T) do
      if tx >= 0 and ty >= 0 and tx < st.W and ty < st.H then
        if breakAt(ty * st.W + tx + 1) then hit = true end
      end
    end
  end
  return hit
end

local function breakDuration(b)
  local ai = project.findAnim(b.spr, "Breaking")
  if ai then return #b.spr.anims[ai].frames * FEEL.BREAK_FRAME end
  return 12                              -- no Breaking art: blink then vanish
end

local function updateBreaks()
  for i, b in pairs(st.breaks) do
    if b.state == "breaking" then
      b.t = b.t + 1
      if b.t >= breakDuration(b) then
        st.breaks[i] = nil
        st.grid[i] = 0
      end
    end
  end
end

-- ── moving platforms ───────────────────────────────────────────────────
local function updatePlatforms()
  for _, pl in ipairs(st.plats) do
    if not pl.fall then
      local d = pl.v * pl.dir
      local nx, ny = pl.x, pl.y
      if pl.axis == "x" then nx = nx + d else ny = ny + d end
      local off = (pl.axis == "x") and (nx - pl.x0) or (ny - pl.y0)
      if off < 0 or off > pl.range or solidAt(nx, ny, pl.w, pl.h) then
        pl.dir = -pl.dir                  -- end of the track or a wall: turn around
        pl.dx, pl.dy = 0, 0
      else
        pl.dx, pl.dy = nx - pl.x, ny - pl.y
        pl.x, pl.y = nx, ny
      end
    end
  end
end

-- Falling platforms: stand on one for FALL_DELAY frames and it drops out of
-- sight, then it comes back at its start spot once nobody is in the way.
local function updateFalls(p)
  for _, pl in ipairs(st.plats) do
    if pl.fall then
      if pl.hidden then
        pl.respawnT = pl.respawnT - 1
        -- it waits until nobody is standing where it will reappear
        local spot = {x = pl.x0, y = pl.y0, w = pl.w, h = pl.h}
        if pl.respawnT <= 0 and not overlap(p, spot) then
          pl.hidden, pl.state, pl.stand, pl.vy, pl.dy = false, "idle", 0, 0, 0
          pl.x, pl.y = pl.x0, pl.y0
        end
      elseif pl.state == "idle" then
        pl.stand = (p.ride == pl) and pl.stand + 1 or 0   -- stepping off resets it
        if pl.stand >= FEEL.FALL_DELAY then pl.state = "falling" end
      else
        pl.vy = math.min(pl.vy + FEEL.FALL_GRAVITY * st.k, FEEL.MAX_FALL * st.k)
        pl.dy = pl.vy
        if solidAt(pl.x, pl.y + pl.vy, pl.w, pl.h) or pl.y > st.H * st.T then
          -- it hit the ground (or the bottom of the map): out of sight until it respawns
          pl.hidden, pl.state, pl.dx, pl.dy, pl.respawnT = true, "gone", 0, 0, FEEL.FALL_RESPAWN
          if p.ride == pl then p.ride = nil end
        else
          pl.y = pl.y + pl.vy
        end
      end
    end
  end
end

-- Platformer: carry the player along with whatever they're standing on
-- A platform that moves this step has already moved, so "standing on it" means
-- your feet were on its top before the move: pl.y - pl.dy.
local function feetOnTop(p, pl)
  return math.abs((p.y + p.h) - (pl.y - pl.dy)) <= 1.5
end

-- Platformer: carry the player along with whatever they're standing on. Feet
-- on a platform's top count as standing, so a platform moving down or up
-- (vertically or not) never leaves its rider hanging or sinking through.
local function ridePlatform(p)
  if not p.ride and p.onGround then
    for _, pl in ipairs(st.plats) do
      if not pl.hidden and p.x < pl.x + pl.w and p.x + p.w > pl.x and feetOnTop(p, pl) then
        p.ride = pl
        break
      end
    end
  end
  local pl = p.ride
  if not pl or pl.hidden then p.ride = nil; return end
  if p.x + p.w <= pl.x or p.x >= pl.x + pl.w or not feetOnTop(p, pl) then p.ride = nil; return end
  if pl.dx ~= 0 then moveAxis(p, pl.dx, "x") end
  if pl.dy > 0 then
    moveAxis(p, pl.y - p.h - p.y, "y")               -- sinking: move down with the top
  elseif pl.dy < 0 then
    if moveAxis(p, pl.dy, "y") then p.ride = nil end  -- head hit a ceiling
  end
end

-- Top-down: a platform moving into the player shoves them out of the way
local function pushPlayer(p)
  for _, pl in ipairs(st.plats) do
    if (pl.dx ~= 0 or pl.dy ~= 0) and overlap(p, pl) then
      if pl.dx > 0 then moveAxis(p, pl.x + pl.w - p.x, "x")
      elseif pl.dx < 0 then moveAxis(p, pl.x - p.w - p.x, "x")
      elseif pl.dy > 0 then moveAxis(p, pl.y + pl.h - p.y, "y")
      else moveAxis(p, pl.y - p.h - p.y, "y") end
    end
  end
end

-- ── ladders ────────────────────────────────────────────────────────────
-- True if the player's body is in a ladder tile (checked in the middle column)
local function onLadder(p)
  local T = st.T
  local tx = floor((p.x + p.w / 2) / T)
  for ty = floor(p.y / T), floor((p.y + p.h - 0.001) / T) do
    if tx >= 0 and ty >= 0 and tx < st.W and ty < st.H and st.ladder[ty * st.W + tx + 1] then
      return true
    end
  end
  return false
end

-- ── turn-based battle ──────────────────────────────────────────────────
-- A battle sprite on the map is a trigger: walking into it starts a fight that
-- takes over the screen. The rules are the Arduboy/web engine's: the same
-- damage formulas, odds, moves and boss phases. Each fight is a coroutine.
-- Its lines wait for time (A skips the wait) and the menu waits for a move.
local BATTLE = {
  HERO_ATK     = 3,     -- your attack (the hero's default in the web engine)
  RUN          = 0.6,   -- chance to get away (bosses can't be run from)
  CRIT         = 0.15,  -- chance a normal attack is a critical hit...
  CRIT_MULT    = 1.8,   -- ...for this much damage
  HEAVY_MISS   = 0.38,  -- heavy swings miss this often
  POTION       = 0.4,   -- a potion heals this share of max HP
  ENEMY_HIT    = 0.6,   -- enemy turn: a normal attack below this roll...
  ENEMY_HARD   = 0.8,   -- ...a hard strike below this one; the rest it hesitates
  CHARGE_EVERY = 4,     -- bosses wind up a big hit on turns 3, 7, 11...
  PHASE2_AT    = 50,    -- a boss gets enraged at this % of its HP...
  PHASE2_ATK   = 2,     -- ...and its attack rises by this much
  ESCAPE_COOL  = 150,   -- frames before a fight you ran from can start again
}

-- Shows lines of text, four to a page. Each page waits `hold` frames.
local function bsay(b, text, hold)
  local lines = gfx.wrap(text, 42)
  for i = 1, #lines, 4 do
    b.lines = {}
    for j = i, math.min(#lines, i + 3) do b.lines[#b.lines + 1] = lines[j] end
    b.waitT = hold or 40
    coroutine.yield()
  end
end

local function bwait(b, frames)
  b.waitT = frames
  coroutine.yield()
end

-- The moves on the menu. Power Strike is greyed out after one use; bosses
-- can't be run from. (The Lua engine has no hero levels, so Power Strike is
-- available to start with, once per fight.)
local function battleMoves(b)
  return {
    {"attack", "ATTACK", true},
    {"heavy", "HEAVY", true},
    {"power", b.powerUsed and "POWER (USED)" or "POWER STRIKE", not b.powerUsed},
    {"defend", "DEFEND", true},
    {"potion", "POTION", true},
    {"run", b.boss and "NO RUN" or "RUN", not b.boss},
  }
end

-- Waits for the player to pick a move; returns its key
local function bmenu(b)
  local prompt = b.charging and (b.name .. " is about to strike! What will you do?") or "What will you do?"
  b.lines = gfx.wrap(prompt, 42)
  b.menuOpen, b.menuIdx, b.choice = true, 1, nil
  coroutine.yield()
  return b.choice
end

-- Enemy damage roll against the hero (defense = max HP / 4, as in the web engine)
local function enemyHit(b, mult)
  local pDef = math.floor(st.maxHp / 4)
  return math.max(1, math.floor(b.eAtk * mult) - pDef + math.floor(math.random() * 2))
end

-- The enemy's turn. Returns "lost" if the hero went down.
local function enemyTurn(b)
  b.turn = b.turn + 1
  bwait(b, 20)
  local dmg
  if b.charging then
    b.charging = false
    dmg = enemyHit(b, 2)
    bsay(b, b.name .. " unleashes its full power!", 30)
  elseif b.boss and b.turn % BATTLE.CHARGE_EVERY == 3 then
    b.charging = true
    bsay(b, b.name .. " is gathering power...", 60)
    if not b.hinted then
      b.hinted = true
      bsay(b, "Tip: DEFEND halves the next hit.", 60)
    end
  else
    local r = math.random()
    if r < BATTLE.ENEMY_HIT then
      dmg = enemyHit(b, 1)
      bsay(b, b.name .. " attacks!", 25)
    elseif r < BATTLE.ENEMY_HARD then
      dmg = enemyHit(b, 1.3)
      bsay(b, b.name .. " strikes hard!", 25)
    else
      bsay(b, b.name .. (b.boss and " glares at you." or " hesitates..."), 40)
    end
  end
  if dmg then
    local guarded = b.defending
    if guarded then dmg = math.ceil(dmg / 2) end
    b.lungeE = 10
    bwait(b, 14)
    st.hp = math.max(0, st.hp - dmg)
    b.flashP = 20
    b.pops[#b.pops + 1] = {side = "p", text = "-" .. dmg, t = 0}
    bwait(b, 16)
    if guarded then bsay(b, "Your guard took half the blow.", 40) end
  end
  b.defending = false
  if st.hp <= 0 then return "lost" end
  return nil
end

-- Your move. Returns "won", "fled", "lost", or nil when the fight goes on.
local function playerTurn(b, action)
  if action == "run" then
    bsay(b, "You try to run...", 30)
    if math.random() < BATTLE.RUN then
      bsay(b, "You got away!", 40)
      return "fled"
    end
    bsay(b, "Couldn't escape!", 40)
    return enemyTurn(b)
  end

  if action == "potion" then
    local to = math.min(st.maxHp, st.hp + math.ceil(st.maxHp * BATTLE.POTION))
    local got = to - st.hp
    bsay(b, "You drink a potion.", 25)
    st.hp = to
    b.pops[#b.pops + 1] = {side = "p", text = "+" .. got, t = 0, heal = true}
    bsay(b, got > 0 and ("Recovered " .. got .. " HP!") or "Your HP is already full.", 35)
    return enemyTurn(b)
  end

  if action == "defend" then
    b.defending = true
    bsay(b, "You raise your guard!", 40)
    return enemyTurn(b)
  end

  local atk = BATTLE.HERO_ATK
  local dmg, crit, miss, text = 0, false, false, "You attack!"
  if action == "attack" then
    dmg = math.max(1, atk - b.eDef + math.floor(math.random() * 3))
    crit = math.random() < BATTLE.CRIT
    if crit then dmg = math.floor(dmg * BATTLE.CRIT_MULT) end
  elseif action == "heavy" then
    text = "You swing with all your might!"
    miss = math.random() < BATTLE.HEAVY_MISS
    dmg = math.max(2, atk * 2 - b.eDef + math.floor(math.random() * 2))
  else                                    -- power strike (once per fight)
    text = "POWER STRIKE!"
    b.powerUsed = true
    dmg = math.max(3, atk * 3 - b.eDef)
  end

  bsay(b, text, 25)
  b.lungeP = 12
  bwait(b, 16)
  if miss then
    b.pops[#b.pops + 1] = {side = "e", text = "MISS", t = 0}
    bsay(b, "...but it missed!", 40)
    return enemyTurn(b)
  end

  b.eHP = math.max(0, b.eHP - dmg)
  b.flashE = 20
  b.pops[#b.pops + 1] = {side = "e", text = tostring(dmg), t = 0}
  bwait(b, 24)
  if crit then bsay(b, "Critical hit!", 35) end
  if b.eHP <= 0 then return "won" end

  if b.boss and not b.p2 and b.eHP <= b.eMax * BATTLE.PHASE2_AT / 100 then
    b.p2, b.charging = true, false
    bsay(b, b.name .. " is enraged!", 45)
    b.eAtk = b.eAtk + BATTLE.PHASE2_ATK
    bsay(b, b.name .. "'s attack rose by " .. BATTLE.PHASE2_ATK .. "!", 45)
  end
  return enemyTurn(b)
end

-- The whole fight, as one script
local function battleScript(b)
  if b.boss then bsay(b, b.name .. " blocks your path!", 90)
  else bsay(b, "A wild " .. b.name .. " appears!", 50) end
  if b.intro ~= "" then bsay(b, b.intro, 60) end
  while true do
    local res = playerTurn(b, bmenu(b))
    if res == "won" then
      bsay(b, b.name .. " was defeated!", 60)
      bsay(b, "You won the fight!", 60)
      b.result = "won"
      return
    elseif res then
      b.result = res
      if res == "lost" then bsay(b, "You were defeated...", 120) end
      return
    end
  end
end

local function newBattle(e)
  local bt = e.battle or {}
  local hp = math.max(1, bt.hp or 4)
  local b = {
    ent = e, name = string.upper(e.spr.name or "ENEMY"), intro = e.intro or "",
    boss = bt.boss and true or false,
    eHP = hp, eMax = hp, shownE = hp, eAtk = bt.atk or 2, eDef = bt.def or 0,
    shownP = st.hp, turn = 0, charging = false, defending = false,
    powerUsed = false, hinted = false, p2 = false,
    lines = {}, waitT = 0, menuOpen = false, menuIdx = 1, choice = nil,
    pops = {}, flashE = 0, flashP = 0, lungeE = 0, lungeP = 0, t = 0, result = nil,
  }
  b.co = coroutine.create(function() battleScript(b) end)
  return b
end

-- Bars drain toward the real value, so you see the hit land
local function drain(shown, real)
  if shown > real then return math.max(real, shown - 0.25) end
  if shown < real then return math.min(real, shown + 0.25) end
  return shown
end

-- One fixed step of the fight. `first` is true only for the step that gets
-- this frame's button presses, so a slow frame can't count a press twice.
local function updateBattle(first)
  local b = st.battle
  local P = first and input.pressed or {}
  b.t = b.t + 1
  for _, k in ipairs({"flashE", "flashP", "lungeE", "lungeP"}) do
    if b[k] > 0 then b[k] = b[k] - 1 end
  end
  for i = #b.pops, 1, -1 do
    b.pops[i].t = b.pops[i].t + 1
    if b.pops[i].t > 40 then table.remove(b.pops, i) end
  end
  b.shownE = drain(b.shownE, b.eHP)
  b.shownP = drain(b.shownP, st.hp)

  if b.menuOpen then
    local moves = battleMoves(b)
    if P.up then b.menuIdx = (b.menuIdx - 2) % #moves + 1 end
    if P.down then b.menuIdx = b.menuIdx % #moves + 1 end
    if not (P.a and moves[b.menuIdx][3]) then return end
    b.choice, b.menuOpen = moves[b.menuIdx][1], false
  elseif b.waitT > 0 then
    b.waitT = b.waitT - 1
    if P.a then b.waitT = 0 end            -- A skips the wait
    if b.waitT > 0 then return end
  end

  local ok, err = coroutine.resume(b.co)
  if not ok then error(err) end
  if coroutine.status(b.co) == "dead" then
    local e, r = b.ent, b.result
    st.battle = nil
    st.inv = 60
    if r == "won" and not e.repeatable then e.alive = false end
    if r == "fled" then e.cool = BATTLE.ESCAPE_COOL end
    if r == "lost" then st.state = "dead" end
  end
end

local function startBattle(e)
  st.battle = newBattle(e)
  st.acc = 0
end

-- ── battle drawing (full screen, 320x240) ──────────────────────────────
local function bar(x, y, w, shown, max, col)
  gfx.setc(gfx.BLACK); gfx.rect(x, y, w, 6)
  gfx.setc(col); gfx.rect(x, y, math.floor(w * math.max(0, shown) / max), 6)
  gfx.setc(gfx.WHITE); gfx.box(x, y, w, 6)
end

-- A fighter at 64px tall; with no art drawn it's a plain box
local function fighter(spr, x, y, sc, t, col, blink)
  if blink then return end
  local ai = project.findAnim(spr, "Idle") or project.thumbAnim(spr)
  local fi = floor(t / 10) % #spr.anims[ai].frames + 1
  if gfx.isBlank(spr, ai, fi) then
    gfx.setc(col); gfx.box(x, y, spr.size * sc, spr.size * sc)
  else
    gfx.sprite(spr, ai, fi, x, y, sc, 1, false)
  end
end

local function drawBattle()
  local b = st.battle
  local e = b.ent
  gfx.color(18, 16, 34)
  gfx.rect(0, 0, VIEW_W * SCALE, VIEW_H * SCALE)
  gfx.color(60, 56, 100)
  gfx.rect(0, 104, VIEW_W * SCALE, 2)
  if b.boss then
    gfx.setc(project.KIND_COLOR.battle)
    gfx.textCentered("BOSS BATTLE", 0, 2, VIEW_W * SCALE, 1)
  end

  -- the two fighters
  local hero = st.player and st.player.spr
  if hero then
    local sc = math.max(1, floor(64 / hero.size))
    fighter(hero, 40 + (b.lungeP > 0 and 8 or 0), 36, sc, b.t, project.KIND_COLOR.player,
            b.flashP > 0 and floor(b.t / 3) % 2 == 0)
  end
  local esc = math.max(1, floor(64 / e.spr.size))
  fighter(e.spr, 210 - (b.lungeE > 0 and 8 or 0), 36, esc, b.t, project.KIND_COLOR.battle,
          b.flashE > 0 and floor(b.t / 3) % 2 == 0)

  -- damage and heal numbers rise and fade
  for _, p in ipairs(b.pops) do
    local x = (p.side == "e") and 232 or 56
    gfx.setc(p.heal and {120, 255, 160} or ((p.side == "e") and {255, 230, 120} or {255, 110, 110}))
    gfx.text(p.text, x, floor(60 - p.t * 0.5))
  end

  -- names and health
  gfx.setc(gfx.WHITE); gfx.text("YOU", 8, 10)
  bar(8, 20, 130, b.shownP, st.maxHp, project.KIND_COLOR.player)
  gfx.text(st.hp .. "/" .. st.maxHp, 8, 28)
  gfx.setc(gfx.WHITE); gfx.text(b.name, 180, 10)
  bar(180, 20, 130, b.shownE, b.eMax, project.KIND_COLOR.battle)
  gfx.text(b.eHP .. "/" .. b.eMax, 180, 28)

  -- the text box, with the move menu on its right while you choose
  gfx.setc(gfx.BLACK); gfx.rect(4, 160, 312, 76)
  gfx.setc(gfx.WHITE); gfx.box(4, 160, 312, 76)
  for i, line in ipairs(b.lines) do gfx.text(line, 12, 168 + (i - 1) * 10) end
  if b.menuOpen then
    for i, m in ipairs(battleMoves(b)) do
      local y = 166 + (i - 1) * 11
      gfx.setc(m[3] and gfx.WHITE or gfx.DIM)
      gfx.text(m[2], 210, y)
      if i == b.menuIdx then gfx.setc(gfx.ACCENT); gfx.text(">", 200, y) end
    end
  end
end

-- ── one fixed 1/60s step ───────────────────────────────────────────────
local function approach(v, target, amount)
  if v < target then return math.min(v + amount, target) end
  return math.max(v - amount, target)
end

local function stepPlatformer(p, jumpPressed)
  local k = st.k
  local MOVE, JUMP = FEEL.MOVE * k, FEEL.JUMP * k
  local ups = st.upgrades or {}
  local canDouble = ups.doubleJump
  local canWall   = ups.wallJump

  local dir = 0
  if input.down.left then dir = dir - 1 end
  if input.down.right then dir = dir + 1 end

  -- running: speed up toward the target, slow down when you let go
  if p.kick > 0 then
    -- after a wall jump the kick carries you away from the wall for a moment
    p.kick = p.kick - 1
    p.vx = p.kickDir * MOVE * 1.2
  else
    local accel, fric
    if p.onGround then accel, fric = FEEL.ACCEL, FEEL.FRICTION
    else accel, fric = FEEL.AIR_ACCEL, FEEL.AIR_FRICTION end
    if dir ~= 0 then
      -- turning around uses friction too, so changing direction is snappy
      local amt = accel * k
      if p.vx ~= 0 and (p.vx > 0) ~= (dir > 0) then amt = amt + fric * k end
      p.vx = approach(p.vx, dir * MOVE, amt)
      p.face = dir
    else
      p.vx = approach(p.vx, 0, fric * k)
    end
  end

  -- touching a wall in the air while pushing into it?
  p.onWall = 0
  if canWall and not p.onGround and dir ~= 0 and p.kick == 0 and
     solidAt(p.x + dir, p.y + 1, p.w, p.h - 2) then
    p.onWall = dir
  end

  -- ladders: hold up or down on one to climb; jump lets go of it
  local climbDir = (input.down.up and -1 or 0) + (input.down.down and 1 or 0)
  if p.climbing and not onLadder(p) then p.climbing = false end
  if p.climbing and jumpPressed then
    p.climbing = false
    jumpPressed = false                    -- the jump is used up here, not below
    p.vy, p.buffer, p.coyote, p.onGround, p.ride = -JUMP, 0, 0, false, nil
  elseif not p.climbing and climbDir ~= 0 and onLadder(p) then
    p.climbing = true
  end

  -- jump buffer: remember the press for a few frames
  if jumpPressed then p.buffer = FEEL.BUFFER elseif p.buffer > 0 then p.buffer = p.buffer - 1 end
  if p.buffer > 0 then
    if p.ride and p.onGround and input.down.down then  -- down + jump: drop through
      p.dropT = FEEL.DROP_THROUGH
      p.ride, p.onGround, p.coyote, p.buffer = nil, false, 0, 0
    elseif p.onGround or p.coyote > 0 then            -- normal jump (coyote time counts)
      p.vy = -JUMP; p.buffer = 0; p.coyote = 0; p.onGround = false; p.ride = nil
    elseif p.onWall ~= 0 then                          -- wall jump: up and away
      p.vy = -JUMP
      p.kick, p.kickDir = FEEL.WALL_KICK, -p.onWall
      p.face = -p.onWall
      p.buffer = 0
      p.airJumps = canDouble and 1 or 0                -- walls refill the double jump
    elseif canDouble and p.airJumps > 0 then           -- double jump, a bit weaker
      p.vy = -JUMP * FEEL.DOUBLE_JUMP
      p.airJumps = p.airJumps - 1
      p.buffer = 0
    end
  end

  -- gravity: lighter while holding jump, heavier after letting go, floaty at the top
  if p.climbing then
    p.vy = climbDir * FEEL.CLIMB * k      -- on a ladder there's no gravity, just climbing
  else
    local holding = input.down.a or input.down.up
    local g
    if p.vy < 0 then g = holding and FEEL.GRAVITY_UP or FEEL.GRAVITY_CUT
    else g = FEEL.GRAVITY_DOWN end
    if holding and math.abs(p.vy) < FEEL.APEX_RANGE * k then g = g * FEEL.APEX_GRAVITY end
    p.vy = math.min(p.vy + g * k, FEEL.MAX_FALL * k)
  end
  if p.onWall ~= 0 and p.vy > FEEL.WALL_SLIDE * k then p.vy = FEEL.WALL_SLIDE * k end

  if moveAxis(p, p.vx, "x") then
    if p.kick > 0 then p.kick = 0 end
    p.vx = 0
  end

  -- corner correction: clipping a ceiling edge nudges you around it
  if p.vy < 0 and solidAt(p.x, p.y + p.vy, p.w, p.h) then
    for off = 1, FEEL.CORNER * k do
      if not solidAt(p.x + off, p.y + p.vy, p.w, p.h) and not solidAt(p.x + off, p.y, p.w, p.h) then
        p.x = p.x + off; break
      elseif not solidAt(p.x - off, p.y + p.vy, p.w, p.h) and not solidAt(p.x - off, p.y, p.w, p.h) then
        p.x = p.x - off; break
      end
    end
  end

  local prevBottom = p.y + p.h
  local hit = moveAxis(p, p.vy, "y")
  local landed = false
  if hit then
    if p.vy > 0 then landed = true
    else breakTilesIn({x = p.x + 1, y = p.y - 1, w = p.w - 2, h = 1}) end   -- head bump
    p.vy = 0
  end

  -- one-way platforms: land on top when falling onto them
  if p.dropT > 0 then p.dropT = p.dropT - 1 end
  if not landed and p.vy >= 0 and p.dropT == 0 then
    local bottom = p.y + p.h
    for _, pl in ipairs(st.plats) do
      if not pl.hidden and p.x < pl.x + pl.w and p.x + p.w > pl.x and
         prevBottom <= pl.y + 0.5 and bottom >= pl.y then   -- feet were above its (new) top
        p.y, p.vy = pl.y - p.h, 0
        landed = true
        p.ride = pl
        break
      end
    end
  end
  if not landed then p.ride = nil end
  -- standing on the floor at the foot of a ladder with no climb held: stop climbing
  if landed and p.climbing and climbDir >= 0 then p.climbing = false end

  p.onGround = landed
  if p.onGround then
    p.coyote = FEEL.COYOTE
    p.airJumps = canDouble and 1 or 0
  elseif p.coyote > 0 then
    p.coyote = p.coyote - 1
  end

  -- fell off the bottom of the map
  if p.y > st.H * st.T + 16 then
    hurt(true)
    if st.state == "play" then p.x, p.y, p.vx, p.vy, p.ride = st.startX, st.startY, 0, 0, nil end
  end
end

local function stepTopdown(p)
  local MOVE = FEEL.TOPDOWN_MOVE * st.k
  local dx, dy = 0, 0
  if input.down.left then dx = dx - 1 end
  if input.down.right then dx = dx + 1 end
  if input.down.up then dy = dy - 1 end
  if input.down.down then dy = dy + 1 end
  if dx ~= 0 and dy ~= 0 then dx, dy = dx * 0.7071, dy * 0.7071 end
  if dx ~= 0 then p.face = dx > 0 and 1 or -1 end
  -- facing for the 4 walk animations: sideways wins on diagonals
  if dx ~= 0 then p.dir = dx > 0 and "right" or "left"
  elseif dy ~= 0 then p.dir = dy > 0 and "down" or "up" end
  p.vx, p.vy = dx * MOVE, dy * MOVE
  moveAxis(p, p.vx, "x")
  moveAxis(p, p.vy, "y")
end

-- ── enemies ────────────────────────────────────────────────────────────
-- tiny repeatable random numbers (same level = same enemy moves every time)
local function rand(e, n)
  e.rng = (e.rng * 1103515245 + 12345) % 2147483648
  return e.rng % n
end

local function sign(v) return v > 0 and 1 or (v < 0 and -1 or 0) end

-- platformer: is there floor just ahead of this enemy, in direction dir?
local function groundAhead(e, dir)
  local aheadX = (dir > 0) and (e.x + e.w) or (e.x - 1)
  return solidAt(aheadX, e.y + e.h + 1, 1, 1)
end

-- walk in e.vx, turn at walls (and at ledges in platformers)
local function patrol(e, platform)
  if e.vx == 0 then e.vx = -e.speed end
  if moveAxis(e, e.vx, "x") then
    e.vx = -e.vx
  elseif platform and e.onGround and not groundAhead(e, e.vx) then
    e.vx = -e.vx
  end
  e.face = sign(e.vx)
end

local function enemyFire(e, p)
  local cx, cy = e.x + e.w / 2, e.y + e.h / 2
  local dx, dy = (p.x + p.w / 2) - cx, (p.y + p.h / 2) - cy
  local v = FEEL.ENEMY_BULLET * st.k
  local vx, vy
  if app.P.mode == "platformer" then vx, vy = sign(dx) * v, 0          -- straight across
  else
    local d = math.sqrt(dx * dx + dy * dy)
    if d == 0 then return end
    vx, vy = dx / d * v, dy / d * v                                       -- aimed at you
  end
  st.ebullets[#st.ebullets + 1] = {x = cx, y = cy, vx = vx, vy = vy, life = 150}
  e.atkT = FEEL.ENEMY_ATTACK
end

local function stepEnemy(e, p)
  local platform = app.P.mode == "platformer"
  local T, k = st.T, st.k
  e.t = e.t + 1
  if e.atkT > 0 then e.atkT = e.atkT - 1 end

  -- gravity (not for flyers, not in top-down games)
  if platform and e.behavior ~= "flyer" then
    e.vy = math.min((e.vy or 0) + 0.13 * k, 4 * k)
    if moveAxis(e, e.vy, "y") then
      e.onGround = e.vy > 0; e.vy = 0
    else
      e.onGround = false
    end
  end

  -- stunned after a hit: no moving
  if e.hurtT > 0 then e.hurtT = e.hurtT - 1; return end

  local dx = (p.x + p.w / 2) - (e.x + e.w / 2)
  local dy = (p.y + p.h / 2) - (e.y + e.h / 2)
  local dist = math.sqrt(dx * dx + dy * dy)
  local b = e.behavior

  if b == "walker" then
    patrol(e, platform)

  elseif b == "hopper" then
    if platform then
      if e.onGround then
        if e.vx ~= 0 then e.dir = sign(e.vx) end
        e.vx = 0
        e.dir = e.dir or -1
        if e.t % FEEL.HOP_EVERY == 0 then
          if not groundAhead(e, e.dir) or solidAt(e.x + e.dir * 2, e.y, e.w, e.h) then e.dir = -e.dir end
          e.vy = -FEEL.HOP_POWER * k
          e.vx = e.dir * e.speed * 2
        end
      elseif moveAxis(e, e.vx, "x") then
        e.vx = -e.vx
      end
      e.face = e.dir or -1
    else
      -- top-down: dash a short way in a random direction every so often
      if e.t % FEEL.HOP_EVERY == 0 then
        local r = rand(e, 4)
        e.mx, e.my = ({1, -1, 0, 0})[r + 1], ({0, 0, 1, -1})[r + 1]
        e.moveT = 20
      end
      if (e.moveT or 0) > 0 then
        e.moveT = e.moveT - 1
        moveAxis(e, e.mx * e.speed * 2, "x")
        moveAxis(e, e.my * e.speed * 2, "y")
        if e.mx ~= 0 then e.face = e.mx end
      end
    end

  elseif b == "flyer" then
    if e.vx == 0 then e.vx = -e.speed end
    if moveAxis(e, e.vx, "x") then e.vx = -e.vx end
    e.face = sign(e.vx)
    local targetY = e.baseY + math.sin(e.t / FEEL.FLY_PERIOD * math.pi * 2) * FEEL.FLY_WAVE * T
    moveAxis(e, targetY - e.y, "y")

  elseif b == "chaser" then
    local near = dist < FEEL.CHASE_RANGE * T and (not platform or math.abs(dy) < 3 * T)
    if near and platform then
      local d = sign(dx)
      e.face = d
      if d ~= 0 and (not e.onGround or groundAhead(e, d)) then
        moveAxis(e, d * e.speed * FEEL.CHASE_BOOST, "x")
      end
      e.vx = d * e.speed
    elseif near then
      local v = e.speed * FEEL.CHASE_BOOST / math.max(dist, 0.001)
      moveAxis(e, dx * v, "x")
      moveAxis(e, dy * v, "y")
      e.face = sign(dx) ~= 0 and sign(dx) or e.face
    else
      patrol(e, platform)
    end

  elseif b == "shooter" then
    if dist < FEEL.SHOOT_RANGE * T then
      e.face = sign(dx) ~= 0 and sign(dx) or e.face
      if e.t % FEEL.SHOOT_EVERY == 0 then enemyFire(e, p) end
    end
  end
end

-- Hit an enemy for 1 damage. Returns true if the hit counted.
local function damageEnemy(e, fromX)
  if not e.alive or e.hurtT > 0 then return false end
  e.hp = e.hp - 1
  impact(FEEL.HITSTOP_HIT, FEEL.SHAKE_HIT)
  if e.hp <= 0 then
    e.alive = false
    say("DEFEATED!")
  else
    e.hurtT = FEEL.ENEMY_HURT
    moveAxis(e, sign((e.x + e.w / 2) - fromX) * FEEL.KNOCKBACK * st.k, "x")
    say("HIT!")
  end
  return true
end

local function updateEnemyBullets(p)
  for i = #st.ebullets, 1, -1 do
    local b = st.ebullets[i]
    b.x, b.y = b.x + b.vx, b.y + b.vy
    b.life = b.life - 1
    local dead = b.life <= 0 or solidAt(b.x, b.y, 1, 1)
    if not dead and overlap({x = b.x - 1, y = b.y - 1, w = 2, h = 2}, p) then
      hurt(); dead = true
    end
    if dead then table.remove(st.ebullets, i) end
  end
end

local function nextScene()
  -- "scene end" messages first; the scene changes once they're all read
  if #st.endTexts > 0 then
    for _, t in ipairs(st.endTexts) do Play.showText(t) end
    st.endTexts = {}
    st.afterText = nextScene
    return
  end
  if app.P.scenes[st.sceneIdx + 1] then
    loadScene(st.sceneIdx + 1, true)
  else
    st.state = "win"
  end
end

-- ── attacking ──────────────────────────────────────────────────────────
local function facing(p)
  if app.P.mode == "platformer" then return p.face > 0 and "right" or "left" end
  return p.dir
end

-- The area a swing hits: in front of the player. Melee reaches further.
local function attackBox(p)
  local reach = st.T * (st.weapon == "melee" and FEEL.MELEE_REACH or 1)
  local d = facing(p)
  if d == "right" then return {x = p.x + p.w, y = p.y, w = reach, h = p.h} end
  if d == "left"  then return {x = p.x - reach, y = p.y, w = reach, h = p.h} end
  if d == "up"    then return {x = p.x, y = p.y - reach, w = p.w, h = reach} end
  return {x = p.x, y = p.y + p.h, w = p.w, h = reach}
end

-- Where the gun barrel is: the middle of the sprite frame's edge on the side
-- you face (right edge, middle row, for the default facing). Draw the barrel
-- there; the flash and the bullet both come out of this point.
local function muzzle(p)
  local T = st.T
  local fx, fy = p.x - 1, p.y            -- top-left of the drawn frame
  local d = facing(p)
  if d == "right" then return fx + T, fy + floor(T / 2), 1, 0 end
  if d == "left"  then return fx - 1, fy + floor(T / 2), -1, 0 end
  if d == "up"    then return fx + floor(T / 2), fy - 1, 0, -1 end
  return fx + floor(T / 2), fy + T, 0, 1
end

local function shoot(p)
  local mx, my, dx, dy = muzzle(p)
  local v = FEEL.BULLET_SPEED * st.k
  st.bullets[#st.bullets + 1] = {x = mx, y = my, vx = dx * v, vy = dy * v, life = FEEL.BULLET_LIFE}
  p.flash = FEEL.FLASH_TIME
end

local function updateBullets()
  for i = #st.bullets, 1, -1 do
    local b = st.bullets[i]
    local dead = false
    -- move in 1px steps so fast bullets can't skip through thin walls
    local steps = math.max(1, math.ceil(math.max(math.abs(b.vx), math.abs(b.vy))))
    for _ = 1, steps do
      b.x, b.y = b.x + b.vx / steps, b.y + b.vy / steps
      local box = {x = b.x, y = b.y, w = 1, h = 1}
      for _, e in ipairs(st.ents) do
        if e.alive and e.kind == "enemy" and overlap(box, e) then
          damageEnemy(e, b.x - b.vx)
          dead = true; break
        end
      end
      if dead then break end
      if solidAt(b.x, b.y, 1, 1) then
        breakTilesIn(box)
        dead = true; break
      end
    end
    b.life = b.life - 1
    if dead or b.life <= 0 or b.y > st.H * st.T + 8 then table.remove(st.bullets, i) end
  end
end

local function step(jumpPressed, attackPressed)
  st.t = st.t + 1
  if st.msgT > 0 then st.msgT = st.msgT - 1 end
  if st.shake > 0 then st.shake = st.shake - 1 end
  if st.state ~= "play" then return end
  local p = st.player

  -- hit-stop: everything holds still for a few frames on big impacts
  if st.freeze > 0 then
    st.freeze = st.freeze - 1
    if jumpPressed then p.buffer = FEEL.BUFFER end
    return
  end

  if st.inv > 0 then st.inv = st.inv - 1 end

  updatePlatforms()
  updateBreaks()
  if app.P.mode == "platformer" then
    ridePlatform(p)
    stepPlatformer(p, jumpPressed)
    updateFalls(p)
  else
    pushPlayer(p)
    stepTopdown(p)
  end

  if attackPressed and st.weapon and p.atkCD == 0 then   -- no weapon, no attack
    if st.weapon == "gun" then
      p.atkTime = FEEL.GUN_TIME
      p.atk, p.atkCD = FEEL.GUN_TIME, FEEL.GUN_COOLDOWN
      shoot(p)
    else
      p.atkTime = (st.weapon == "melee") and FEEL.MELEE_TIME or FEEL.ATTACK_TIME
      p.atk, p.atkCD = p.atkTime, p.atkTime + 6
    end
  end
  if p.atkCD > 0 then p.atkCD = p.atkCD - 1 end
  if p.flash > 0 then p.flash = p.flash - 1 end
  updateBullets()
  updateEnemyBullets(p)
  if p.atk > 0 then p.atk = p.atk - 1 end
  if p.atk > 0 and st.weapon == "melee" then
    -- a sword breaks blocks; enemies only die to a stomp or a gun
    breakTilesIn(attackBox(p))
  end

  for _, e in ipairs(st.ents) do
    if e.alive then
      if e.cool and e.cool > 0 then e.cool = e.cool - 1 end
      if e.kind == "enemy" then stepEnemy(e, p) end
      if st.state == "play" and overlap(p, e, e.kind == "hazard" and 2 or 0) then
        if e.kind == "coin" then
          e.alive = false
          st.coins = st.coins + 1
        elseif e.kind == "hazard" then
          hurt()
        elseif e.kind == "enemy" then
          local stomp = app.P.mode == "platformer" and p.vy > 0 and (p.y + p.h - e.y) < 4 * st.k
          if stomp then
            damageEnemy(e, p.x + p.w / 2)
            p.vy = -2.0 * st.k
            p.airJumps = (st.upgrades and st.upgrades.doubleJump) and 1 or 0   -- stomps refill it
            impact(FEEL.HITSTOP_STOMP, FEEL.SHAKE_HIT)
          elseif e.hurtT == 0 then              -- a stunned enemy can't hurt you
            hurt()
          end
        elseif e.kind == "doublejump" or e.kind == "walljump" then
          grantUpgrade(e)
        elseif e.kind == "melee" or e.kind == "gun" then
          e.alive = false
          st.weapon = e.kind
          say(e.kind == "melee" and "GOT A MELEE WEAPON!" or "GOT A GUN!")
        elseif e.kind == "goal" then
          nextScene()
          return
        elseif e.kind == "battle" then
          if not e.inside then
            e.inside = true
            if e.cool == 0 then
              startBattle(e)
              return                       -- the fight takes over from here
            end
          end
        elseif e.kind == "text" then
          if not e.inside then
            e.inside = true
            if e.trigger == "touch" and e.text ~= "" and not e.shown then
              Play.showText(e.text)
              if e.once then e.shown = true end
            end
          end
        end
      elseif e.kind == "text" or e.kind == "battle" then
        e.inside = false               -- walked off it: it can show again
      end
    end
  end

  -- camera follows the player, clamped to the map
  local mw, mh = st.W * st.T, st.H * st.T
  local cx = p.x + p.w / 2 - VIEW_W / 2
  local cy = p.y + p.h / 2 - VIEW_H / 2
  if mw <= VIEW_W then cx = (mw - VIEW_W) / 2 else cx = math.max(0, math.min(mw - VIEW_W, cx)) end
  if mh <= VIEW_H then cy = (mh - VIEW_H) / 2 else cy = math.max(0, math.min(mh - VIEW_H, cy)) end
  st.camX, st.camY = cx, cy
end

-- ── raycast play ───────────────────────────────────────────────────────
-- Is cell (x, y) a wall, or off the map? Checked at the four corners of the
-- player's body, so you can't clip into a wall's corner.
local function rayBlocked(rc, x, y)
  local r = RAY.RADIUS
  local corners = {x - r, y - r, x + r, y - r, x - r, y + r, x + r, y + r}
  for c = 1, 7, 2 do
    local cx, cy = floor(corners[c]), floor(corners[c + 1])
    if cx < 0 or cy < 0 or cx >= rc.W or cy >= rc.H or rc.walls[cy * rc.W + cx + 1] then
      return true
    end
  end
  return false
end

-- What happens when you walk into a cell that has something in it
local function enterRayCell(i)
  local e = st.rc.cellEnt[i]
  if not e or not e.alive then return end
  local k = e.kind
  if k == "battle" then
    if e.cool <= 0 and not st.battle then startBattle(e) end
  elseif k == "coin" then
    st.coins = st.coins + 1
    e.alive = false
  elseif k == "goal" then
    nextScene()
  elseif k == "doublejump" or k == "walljump" then
    grantUpgrade(e)
  elseif k == "melee" or k == "gun" then
    e.alive = false
    st.weapon = k
    say(k == "melee" and "GOT A MELEE WEAPON!" or "GOT A GUN!")
  elseif k == "text" then
    if e.trigger == "touch" and e.text ~= "" then
      Play.showText(e.text)
      if e.once then e.alive = false end
    end
  elseif k == "hazard" then
    if st.inv == 0 then
      st.hp = st.hp - 1
      st.inv = RAY.HAZARD_INV
      st.shake = FEEL.SHAKE_HURT
      if st.hp <= 0 then st.state = "dead" end
    end
  end
end

-- How far a gun shot reaches, in cells (it hits the nearest enemy in the
-- middle of the view, if no wall is nearer)
local SHOT_RANGE = 10

-- The nearest enemy (or fight trigger) in front of you within reach. minDot
-- is how close to straight ahead it must be (1 = dead ahead, 0 = to the side).
local function nearestTarget(rc, reach, minDot)
  local dx, dy = math.cos(rc.a), math.sin(rc.a)
  local wall = rc.zbuf[80] or math.huge                 -- the middle column of the view
  local best, bestD = nil, math.huge
  for _, e in ipairs(rc.ents) do
    if e.alive and (e.kind == "enemy" or e.kind == "battle") then
      local vx, vy = e.cx - rc.x, e.cy - rc.y
      local d = math.sqrt(vx * vx + vy * vy)
      if d > 0 and d <= reach and d < wall and d < bestD
         and (vx * dx + vy * dy) / d >= minDot then
        best, bestD = e, d
      end
    end
  end
  return best
end

local function hurtTarget(e, dmg)
  e.hpLeft = (e.hpLeft or 1) - dmg
  if e.hpLeft <= 0 then
    e.alive = false
    say("DEFEATED!")
  end
end

-- One fixed step: turn, walk (with walls in the way), swing or shoot, then
-- cell events
local function rcStep(attackPressed)
  if st.state ~= "play" then return end
  local rc = st.rc
  st.t = st.t + 1
  if st.inv > 0 then st.inv = st.inv - 1 end
  for _, e in ipairs(rc.ents) do
    if e.cool > 0 then e.cool = e.cool - 1 end
  end
  if rc.atk > 0 then rc.atk = rc.atk - 1 end
  if rc.cool > 0 then rc.cool = rc.cool - 1 end

  local down = input.down
  local fwd = (down.up and 1 or 0) - (down.down and 1 or 0)
  local turn, strafe = 0, 0
  if down.x then
    strafe = (down.right and 1 or 0) - (down.left and 1 or 0)
  else
    turn = (down.right and 1 or 0) - (down.left and 1 or 0)
  end
  rc.a = rc.a + turn * RAY.TURN
  local dx, dy = math.cos(rc.a), math.sin(rc.a)
  local mx = dx * fwd * RAY.MOVE - dy * strafe * RAY.STRAFE
  local my = dy * fwd * RAY.MOVE + dx * strafe * RAY.STRAFE

  -- move one axis at a time, so you slide along walls
  local ox, oy = rc.x, rc.y
  if not rayBlocked(rc, rc.x + mx, rc.y) then rc.x = rc.x + mx end
  if not rayBlocked(rc, rc.x, rc.y + my) then rc.y = rc.y + my end
  rc.moving = (rc.x ~= ox or rc.y ~= oy)

  -- swing or shoot, only with a weapon in hand and when the last one is done
  if attackPressed and st.weapon and rc.cool == 0 then
    if st.weapon == "gun" then
      rc.atkMax = FEEL.GUN_TIME
      rc.cool = FEEL.GUN_COOLDOWN
      local e = nearestTarget(rc, SHOT_RANGE, 0.97)
      if e then hurtTarget(e, 1) end
    else
      rc.atkMax = FEEL.MELEE_TIME
      rc.cool = FEEL.MELEE_TIME + 6
      local e = nearestTarget(rc, FEEL.MELEE_REACH, 0.5)
      if e then hurtTarget(e, 1) end
    end
    rc.atk = rc.atkMax
  end

  local i = floor(rc.y) * rc.W + floor(rc.x) + 1
  if i ~= rc.lastCell then
    rc.lastCell = i
    enterRayCell(i)
  end
end

function Play.update(dt)
  if not st then Play.start() end
  local platform = app.P.mode == "platformer"
  -- up on a ladder means climb, not jump
  local onL = platform and st.player and onLadder(st.player)
  local jump = platform and (input.pressed.a or (input.pressed.up and not onL))
  local attack = input.pressed.b or (not platform and input.pressed.a)
  if st.state == "dead" and input.pressed.a then Play.start(); return end
  if st.state == "win" and input.pressed.a then
    app.scene = st.startScene; Play.start(); return
  end
  if st.dialog then
    updateDialog()
    st.acc = 0
    return
  end
  st.acc = math.min(st.acc + dt, STEP * 3)
  local first = true
  while st.acc >= STEP do
    if st.battle then
      updateBattle(first)
    elseif app.P.mode == "raycast" then
      rcStep(first and attack)
    else
      step(first and jump, first and attack)
    end
    first = false
    st.acc = st.acc - STEP
  end
end

-- ── choosing animations ────────────────────────────────────────────────
-- Use the named animation if it's drawn, otherwise the thumbnail one
local function namedOr(spr, name)
  return project.findAnim(spr, name) or project.thumbAnim(spr)
end

-- Try names in order; returns animIndex, mirrored?  ("~Name" = use Name flipped)
local function pick(spr, names)
  for _, n in ipairs(names) do
    local flip = n:sub(1, 1) == "~"
    if flip then n = n:sub(2) end
    local i = project.findAnim(spr, n)
    if i then return i, flip end
  end
  return project.thumbAnim(spr), false
end

local TD_WALK = {
  down  = {"Walk Down", "Idle"},
  up    = {"Walk Up", "Idle"},
  left  = {"Walk Left", "~Walk Right", "Idle"},
  right = {"Walk Right", "~Walk Left", "Idle"},
}

-- Holding a weapon? Try "M.Walk" / "G.Walk" first, then plain "Walk".
local function withWeapon(names)
  local pfx = (st.weapon == "melee" and "M.") or (st.weapon == "gun" and "G.") or nil
  if not pfx then return names end
  local out = {}
  for _, n in ipairs(names) do
    if n:sub(1, 1) == "~" then out[#out + 1] = "~" .. pfx .. n:sub(2)
    else out[#out + 1] = pfx .. n end
  end
  for _, n in ipairs(names) do out[#out + 1] = n end
  return out
end

local function hasAny(spr, names)
  for _, n in ipairs(names) do if project.findAnim(spr, n) then return true end end
  return false
end

-- Which animation + frame to draw for the player this frame
local function playerFrame(p)
  local spr = p.spr
  local platform = app.P.mode == "platformer"
  local moving = math.abs(p.vx) > 0.05 or (not platform and p.vy ~= 0)
  local names, attacking
  -- gun with no G.Attack drawn: keep the gun pose (the flash shows the shot)
  local atkNames = (st.weapon == "gun") and {"G.Attack"} or withWeapon({"Attack"})

  if p.atk > 0 and hasAny(spr, atkNames) then
    names, attacking = atkNames, true
  elseif st.inv > 40 and project.findAnim(spr, "Hurt") then
    names = {"Hurt"}
  elseif platform then
    if p.climbing then names = (p.vy ~= 0) and {"Walk", "Idle"} or {"Idle", "Walk"}
    elseif not p.onGround then names = p.vy < 0 and {"Jump", "Idle"} or {"Fall", "Jump", "Idle"}
    elseif moving then names = {"Walk", "Idle"}
    else names = {"Idle", "Walk"} end
    names = withWeapon(names)
  else
    if moving then names = TD_WALK[p.dir]
    else names = {"Idle"} end
    names = withWeapon(names)
  end

  local ai, mirrored = pick(spr, names)
  -- top-down idle with no Idle drawn: stand on frame 1 of the facing walk
  local still = false
  local aname = spr.anims[ai].name
  if not platform and not moving and not attacking and aname ~= "Idle" and aname ~= "M.Idle" and aname ~= "G.Idle" then
    ai, mirrored = pick(spr, withWeapon(TD_WALK[p.dir])); still = true
  end

  -- restart the animation clock whenever the animation changes
  local key = ai .. (mirrored and "m" or "")
  if p.animName ~= key then p.animName, p.animT = key, 0 end
  p.animT = p.animT + 1

  local n = #spr.anims[ai].frames
  local fi
  if attacking then fi = math.min(n, floor((p.atkTime - p.atk) / p.atkTime * n) + 1)
  elseif still then fi = 1
  else fi = floor(p.animT / 8) % n + 1 end

  local flip
  if platform then flip = p.face < 0 else flip = mirrored end
  return ai, fi, flip
end

-- ── drawing ────────────────────────────────────────────────────────────
local camX, camY = 0, 0     -- camera for this frame, including shake

local function drawThing(spr, ai, fi, wx, wy, col, flip)
  local sx = VX + floor((wx - camX) * SCALE)
  local sy = VY + floor((wy - camY) * SCALE)
  local T = st.T
  if sx > VX + VIEW_W * SCALE or sy > VY + VIEW_H * SCALE or sx < VX - T * SCALE or sy < VY - T * SCALE then return end
  if gfx.isBlank(spr, ai, fi) then
    gfx.color(col[1] * 0.6, col[2] * 0.6, col[3] * 0.6)
    gfx.rect(sx + 2, sy + 2, T * SCALE - 4, T * SCALE - 4)
  else
    gfx.sprite(spr, ai, fi, sx, sy, SCALE, 1, flip)     -- col only colors empty placeholders
  end
end

local function drawBreakable(b, x, y)
  local col = project.KIND_COLOR.breakable
  if b.state == "idle" then
    local ai = namedOr(b.spr, "Idle")
    drawThing(b.spr, ai, floor(st.t / 10) % #b.spr.anims[ai].frames + 1, x, y, col)
  else
    local ai = project.findAnim(b.spr, "Breaking")
    if ai then
      local fi = math.min(#b.spr.anims[ai].frames, floor(b.t / FEEL.BREAK_FRAME) + 1)
      drawThing(b.spr, ai, fi, x, y, col)
    elseif floor(b.t / 2) % 2 == 0 then
      drawThing(b.spr, namedOr(b.spr, "Idle"), 1, x, y, col)
    end
  end
end

-- one game pixel at world position (wx, wy)
local function px(wx, wy, w, h)
  gfx.rect(VX + floor((wx - camX) * SCALE), VY + floor((wy - camY) * SCALE), (w or 1) * SCALE, (h or 1) * SCALE)
end

-- Melee: a sweeping arc in front of the player, drawn over the sprite
local function drawSlash(p)
  local t = 1 - p.atk / p.atkTime                -- 0 → 1 over the swing
  local cx, cy = p.x + p.w / 2, p.y + p.h / 2
  local r = st.T * 1.1
  local d = facing(p)
  local head = -70 + 140 * t                      -- degrees, sweeping top to bottom
  gfx.setc(gfx.WHITE)
  for a = head - 60, head, 6 do
    local rad = math.rad(a)
    local fx, fy = math.cos(rad), math.sin(rad)  -- arc facing right
    local ox, oy
    if d == "right" then ox, oy = fx, fy
    elseif d == "left" then ox, oy = -fx, fy
    elseif d == "up" then ox, oy = fy, -fx
    else ox, oy = -fy, fx end
    px(cx + ox * r, cy + oy * r)
    if a > head - 30 then px(cx + ox * (r - 1), cy + oy * (r - 1)) end   -- thicker near the tip
  end
end

-- Gun: a little star-shaped flash just outside the muzzle point
local function drawFlash(p)
  local mx, my, dx, dy = muzzle(p)
  local fx, fy = mx + dx, my + dy
  gfx.setc(gfx.WHITE)
  px(fx - 1, fy); px(fx + 1, fy); px(fx, fy - 1); px(fx, fy + 1)
  if p.flash > FEEL.FLASH_TIME / 2 then px(fx, fy) end
end

-- The text box: bottom of the screen, or the top when the player is down there
local function drawDialog()
  local d = st.dialog
  local pg = d.pages[d.page]
  local bh = 12 + project.TEXT_LINES * 9
  local by = 240 - bh - 4
  local p = st.player
  if p and (p.y - st.camY) > VIEW_H * 0.55 then by = 4 end
  gfx.setc(gfx.BLACK); gfx.rect(4, by, 312, bh)
  gfx.setc(gfx.WHITE); gfx.box(4, by, 312, bh)
  gfx.setc(gfx.DIM); gfx.box(6, by + 2, 308, bh - 4)
  local left = d.shown
  gfx.setc(gfx.WHITE)
  for i, line in ipairs(pg) do
    if left <= 0 then break end
    gfx.text(line:sub(1, left), 12, by + 7 + (i - 1) * 9)
    left = left - #line
  end
  -- blinking marker once the page is fully shown: more pages, or close
  if d.shown >= pageLen(pg) and floor(d.t / 20) % 2 == 0 then
    local more = d.page < #d.pages or #st.dqueue > 0
    gfx.setc(gfx.ACCENT)
    if more then gfx.text("V", 304, by + bh - 9) else gfx.text("A", 304, by + bh - 9) end
  end
end

local function centered(s, y, col, scale)
  gfx.setc(col or gfx.WHITE)
  gfx.textCentered(s, VX, y, VIEW_W * SCALE, scale or 1)
end

-- The weapon in your hands, at the bottom of the screen: the player sprite's
-- "M." (melee) or "G." (gun) animations. Idle, Walk while you move, Attack
-- while you swing or shoot. Your own body is never drawn in first person.
local function drawViewModel()
  local rc, spr = st.rc, st.player and st.player.spr
  if not spr or not st.weapon or st.state ~= "play" then return end
  local pfx = (st.weapon == "gun") and "G." or "M."
  local names = (rc.atk > 0 and {"Attack"}) or (rc.moving and {"Walk", "Walk Down"}) or {"Idle"}
  local cand = {}
  for _, n in ipairs(names) do cand[#cand + 1] = pfx .. n end
  for _, n in ipairs(names) do cand[#cand + 1] = n end
  local ai = pick(spr, cand)
  local n = #spr.anims[ai].frames
  local fi
  if rc.atk > 0 then
    fi = math.min(n, floor((1 - rc.atk / rc.atkMax) * n) + 1)   -- the swing, start to end
  else
    fi = floor(st.t / 8) % n + 1
  end
  local sc = (spr.size == 8) and 6 or 4
  local w = spr.size * sc
  gfx.sprite(spr, ai, fi, floor((320 - w) / 2), 240 - w, sc)
end

function Play.draw()
  if not st then Play.start() end
  if st.battle then drawBattle(); return end
  local P = app.P
  local T = st.T

  camX, camY = st.camX, st.camY
  if st.shake > 0 then
    camX = camX + ((st.t * 13) % 3) - 1
    camY = camY + ((st.t * 7) % 3) - 1
  end

  gfx.setc(gfx.BLACK); gfx.rect(VX, VY, VIEW_W * SCALE, VIEW_H * SCALE)

  gfx.clip(VX, VY, VIEW_W * SCALE, VIEW_H * SCALE)
  local anim = floor(st.t / 10)

  if P.mode == "raycast" then
    if st.state ~= "noplayer" then
      RC.draw(st.rc, st.t)
      drawViewModel()
    end
  elseif st.state ~= "noplayer" then
    -- parallax background: same grid as the map, scrolled slower (bgSpeed)
    -- and drawn dimmer so it reads as far away
    if st.bg then
      local bx, by = camX * st.bgSpeed, camY * st.bgSpeed
      local bx0, by0 = math.max(0, floor(bx / T)), math.max(0, floor(by / T))
      local bx1 = math.min(st.W - 1, floor((bx + VIEW_W) / T))
      local by1 = math.min(st.H - 1, floor((by + VIEW_H) / T))
      for y = by0, by1 do
        for x = bx0, bx1 do
          local v = st.bg[y * st.W + x + 1]
          local spr = v > 0 and P.sprites[v]
          if spr then
            local ta = gfx.memo(spr, "thumb", project.thumbAnim)
            if not gfx.isBlank(spr, ta, 1) then
              local c = project.KIND_COLOR[spr.kind] or gfx.WHITE
              if spr.kind == "solid" or spr.kind == "decor" then c = gfx.WHITE end
              gfx.sprite(spr, ta, anim % #spr.anims[ta].frames + 1,
                         VX + floor((x * T - bx) * SCALE), VY + floor((y * T - by) * SCALE), SCALE, 0.55)
            end
          end
        end
      end
    end
    -- tiles
    local x0 = math.max(0, floor(camX / T))
    local y0 = math.max(0, floor(camY / T))
    local x1 = math.min(st.W - 1, floor((camX + VIEW_W) / T))
    local y1 = math.min(st.H - 1, floor((camY + VIEW_H) / T))
    for y = y0, y1 do
      for x = x0, x1 do
        local i = y * st.W + x + 1
        local b = st.breaks[i]
        if b then
          drawBreakable(b, x * T, y * T)
        else
          local v = st.grid[i]
          if v > 0 then
            local spr = P.sprites[v]
            if spr then
              local col = spr.kind == "decor" and {170, 170, 170} or gfx.WHITE
              local ta = gfx.memo(spr, "thumb", project.thumbAnim)
              drawThing(spr, ta, anim % #spr.anims[ta].frames + 1, x * T, y * T, col)
            end
          end
        end
      end
    end
    -- moving platforms
    for _, pl in ipairs(st.plats) do
      if not pl.hidden then
        local ta = gfx.memo(pl.spr, "thumb", project.thumbAnim)
        local fi = anim % #pl.spr.anims[ta].frames + 1
        -- a falling platform jitters just before it drops
        local jit = (pl.fall and pl.state == "idle" and pl.stand >= FEEL.FALL_DELAY - FEEL.FALL_SHAKE
                     and st.t % 2 == 0) and 1 or 0
        local col = pl.fall and project.KIND_COLOR.falling or project.KIND_COLOR.platform
        for j = 0, pl.n - 1 do
          drawThing(pl.spr, ta, fi, pl.x + j * T + jit, pl.y, col)
        end
      end
    end
    -- things
    for _, e in ipairs(st.ents) do
      if e.alive then
        local col = project.KIND_COLOR[e.kind] or gfx.WHITE
        if e.kind == "enemy" then
          -- Hurt while stunned, Attack after firing, else Walk. Enemy art faces LEFT.
          local ai
          if e.hurtT > 0 then ai = project.findAnim(e.spr, "Hurt") end
          if not ai and e.atkT > 0 then ai = project.findAnim(e.spr, "Attack") end
          ai = ai or gfx.memo(e.spr, "play", namedOr, "Walk")
          local blink = e.hurtT > 0 and not project.findAnim(e.spr, "Hurt") and floor(st.t / 3) % 2 == 0
          if not blink then
            drawThing(e.spr, ai, floor(st.t / 6) % #e.spr.anims[ai].frames + 1, e.x - 1, e.y, col, e.face > 0)
          end
        else
          local ai = gfx.memo(e.spr, "play", namedOr, "Spin")
          local fi = anim % #e.spr.anims[ai].frames + 1
          -- a text object with no art is an invisible trigger
          if not ((e.kind == "text" or e.kind == "battle") and gfx.isBlank(e.spr, ai, fi)) then
            drawThing(e.spr, ai, fi, e.x, e.y, col)
          end
        end
      end
    end
    -- player (blinks while invincible)
    local p = st.player
    if p and (st.inv == 0 or floor(st.t / 4) % 2 == 0) then
      local ai, fi, flip = playerFrame(p)
      drawThing(p.spr, ai, fi, p.x - 1, p.y, project.KIND_COLOR.player, flip)
      if p.atk > 0 and st.weapon == "melee" then
        drawSlash(p)
      elseif p.flash > 0 then
        drawFlash(p)
      -- unarmed with no Attack animation drawn? a simple line so attacks still read
      elseif p.atk > 0 and st.weapon == nil and not project.findAnim(p.spr, "Attack") then
        local hb = attackBox(p)
        gfx.setc(gfx.WHITE)
        local sx = VX + floor((hb.x - camX) * SCALE)
        local sy = VY + floor((hb.y - camY) * SCALE)
        if hb.w > hb.h then gfx.rect(sx + 2, sy + hb.h, hb.w * SCALE - 4, 2)
        else gfx.rect(sx + hb.w, sy + 2, 2, hb.h * SCALE - 4) end
      end
    end
  end
  -- enemy bullets
  gfx.setc(project.KIND_COLOR.enemy)
  for _, b in ipairs(st.ebullets) do px(b.x - 1, b.y - 1, 2, 2) end
  -- bullets
  gfx.setc(gfx.WHITE)
  for _, b in ipairs(st.bullets) do
    if b.vx ~= 0 then px(b.x - 1, b.y, 2, 1) else px(b.x, b.y - 1, 1, 2) end
  end
  gfx.clip()

  -- HUD, drawn over the game with a shadow so it reads on any background
  local function hud(str, x, y, col)
    gfx.setc(gfx.BLACK); gfx.text(str, x + 1, y + 1)
    gfx.setc(col); gfx.text(str, x, y)
  end
  hud("HP " .. math.max(0, st.hp) .. "/" .. st.maxHp, 4, 4, gfx.WHITE)
  hud("COINS " .. st.coins, 52, 4, project.KIND_COLOR.coin)
  if st.weapon then hud(st.weapon == "melee" and "MELEE" or "GUN", 112, 4, project.KIND_COLOR[st.weapon]) end
  local sl = "SCENE " .. st.sceneIdx .. "/" .. #P.scenes
  hud(sl, 316 - gfx.textWidth(sl), 4, gfx.TEXT)

  -- overlays
  local mid = VY + VIEW_H
  if st.state == "noplayer" then
    centered("NO PLAYER ON THIS MAP", mid - 12, gfx.WARN, 2)
    centered("MAKE A SPRITE WITH KIND: PLAYER", mid + 8, gfx.TEXT)
    centered("AND PLACE IT IN THE MAP TAB", mid + 16, gfx.TEXT)
  elseif st.state == "dead" then
    gfx.color(0, 0, 0); gfx.rect(VX, mid - 18, VIEW_W * SCALE, 30)
    centered("GAME OVER", mid - 14, gfx.WARN, 2)
    centered("A: TRY AGAIN", mid + 2, gfx.TEXT)
  elseif st.state == "win" then
    gfx.color(0, 0, 0); gfx.rect(VX, mid - 18, VIEW_W * SCALE, 38)
    centered("YOU WIN!", mid - 14, gfx.ACCENT, 2)
    centered("COINS " .. st.coins, mid + 2, project.KIND_COLOR.coin)
    centered("A: PLAY AGAIN", mid + 10, gfx.TEXT)
  elseif st.msgT > 0 then
    gfx.setc(gfx.BLACK); gfx.textCentered(st.msg, VX + 1, VY + 15, VIEW_W * SCALE, 1)
    centered(st.msg, VY + 14, gfx.WHITE)
  end

  if st.dialog then drawDialog() end

  -- controls reminder for the first few seconds
  if st.t < 240 and not st.dialog then
    local help = P.mode == "platformer" and "D-PAD MOVE  A JUMP  B ATTACK  DOWN+A DROP  START: EDITOR"
                                         or (P.mode == "raycast" and "D-PAD MOVE/TURN  X+D-PAD STRAFE  START: EDITOR"
                                         or "D-PAD MOVE   A/B ATTACK   START: BACK TO EDITOR")
    gfx.setc(gfx.BLACK); gfx.textCentered(help, 1, 25, 320, 1)
    gfx.setc(gfx.TEXT); gfx.textCentered(help, 0, 24, 320, 1)
  end
end

return Play
