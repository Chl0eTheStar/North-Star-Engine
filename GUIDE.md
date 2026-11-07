# LutroFX IDE

A small game maker that runs inside Lutro (RetroArch's LÖVE-style Lua core).
You draw 16-color sprites, paint them onto tile maps, and play-test the result on
the device. It works with a mouse, and with just the d-pad.

## Install

- **Easiest:** copy `lutrofx.lutro` into the ROM folder Onion uses for Lutro and
  launch it like a game.
- **To read or tweak the code:** copy the whole `lutrofx` folder instead and
  launch its `main.lua`.

### Saving and your games

You can keep up to **12 games**. Each one is its own file in RetroArch's
**save folder** (on Onion that's usually `/mnt/SDCARD/Saves/CurrentProfile/saves/`,
sometimes in a `Lutro` subfolder), not next to the game:

```
lutrofx_game_1.lua      game 1
lutrofx_game_1.lua.bak  game 1 as it was one save ago
lutrofx_game_2.lua      game 2 ...
lutrofx_last.txt        which game to open on launch
```

That way they survive both ways of launching (a `.lutro` file gets unpacked to
a temporary folder that Lutro deletes on exit). They're plain text, so you can
back them up or copy them to another device.

Tap **GAMES** (top right) to see them all as cards with the player sprite,
game type and size. Tap a card to select it, tap it again (or **OPEN**) to
switch to it. The game you leave is saved first. An empty card says
**+ NEW GAME** and takes you to the new-game screen for that slot.
**COPY** duplicates the selected game into the first empty slot (handy before
trying something risky), and **DELETE** asks "SURE?" first. A deleted game
isn't gone yet: it's renamed to `lutrofx_game_N.lua.bak`, and renaming it back
on the SD card restores it. The sprite clipboard stays when you switch games,
so you can copy a frame from one game and paste it into another.

LutroFX opens the game you had open last. A save from older versions
(`lutrofx_project.lua`) becomes game 1 the first time you launch this one.

## Controls

| | Editor | Play |
|---|---|---|
| D-pad | move cursor (tap = 1px, hold = faster) | move |
| A / left mouse | click, draw, place | jump (platformer) / attack (top-down) |
| B / right mouse | erase | attack |
| Y | next palette color (sprite tab) | — |
| X + d-pad | scroll the map | — |
| L2 + d-pad | nudge this frame 1px (sprite tab) | — |
| R2 + d-pad | nudge every frame of the animation 1px | — |
| L / R | previous / next tab | — |
| Start | play / back to editor | back to editor |
| Select | save | — |

Projects saved by the first version load fine: their frames become the Idle
animation.

The cursor jumps to the mouse whenever the mouse moves, so you can mix both.
It also autosaves every 30 seconds when there are changes.

**Touchscreen (e.g. RetroArch on Android):** set the core option
*Mouse Input Device* to **Pointer**. The default (*Mouse*) reads a real mouse.

## How it works

- **Sprites tab:** draw, and set each sprite's **kind** (tap the KIND bar to
  pick from all of them, or step with `< >`):
  player, solid, decor, coin, hazard, enemy, goal, breakable, platform, melee,
  gun, text, ladder, falling, battle. Each sprite has named
  **animations** (pick one with the second `< >` row), each with up to 7 frames.
  The previous frame shows faintly as an onion skin.
  - Platformer player: Idle, Walk, Jump, Fall, Attack, Hurt
  - Top-down player: Idle, Walk Down, Walk Up, Walk Left, Walk Right, Attack, Hurt
  - Enemy: Walk, Attack, Hurt · Coin: Spin · Breakable: Idle, Breaking
  - Platform: Idle · everything else: Default

  Empty animations fall back to something sensible: Fall uses Jump, Walk Right
  mirrors Walk Left (or press MIRROR to copy it over and edit), and a top-down
  player with no Idle stands on the first frame of the direction it faces.
  Platformer animations should face right; they flip when you walk left.

  **Colors:** the swatch row under the grid holds the 16-color palette. Tap a
  swatch or press **Y** to step through colors; **B** always erases to
  transparent (shown as a dark checkerboard). **FILL** fills with the current
  color and **PICK** is an eyedropper: tap a pixel to grab its color, then
  you're back on the pen. Projects from before colors convert automatically:
  each sprite's pixels take the palette color closest to its old kind tint.
  The palette lives in `gfx.PALETTE` in `lib/gfx.lua`.

  **COPY** puts the current frame on the clipboard (the little preview box
  shows what's on it). **PASTE** replaces the current frame with it, and
  **PASTE NEW** adds it as a new frame after the current one. The clipboard
  stays while you switch animations or sprites, so you can copy an Idle
  frame into Walk, or between two sprites. Pastes can be undone.

  Under the grid, the **arrow** button picks a direction (tap to cycle
  up → down → left → right) and **NUDGE 1PX** shifts the drawing that way,
  wrapping around the edges. Turn on **ALL FRAMES** to move the whole
  animation together. Nudges can be undone.

  **Upgrade** pickups (platformers) unlock jump moves for the rest of the
  game, and they carry into later scenes: **DOUBLE JUMP** (one extra jump in
  mid-air; stomping an enemy also refills it) and **WALL JUMP** (hold toward
  a wall in the air to slide down it slowly, press jump to kick off; touching
  a wall also refills the double jump). Put them where you want the player to
  get them, so you can build progression: a double jump early, the wall jump
  behind a gap that needs it.
  **Breakable** blocks are solid until you attack them, or head-bump them from
  below in a platformer. Breaking plays once, then the block is gone. With no
  Breaking art it blinks and vanishes.

  **Platform** sprites get three settings: HORIZ/VERT, how many tiles they
  travel (- / +), and SLOW/MED/FAST. They go back and forth and turn around
  early if they hit a wall. Platform tiles placed side by side move as one
  wide platform. In platformers you can stand on them and jump up through
  them; hold down + jump to drop through. In top-down games they're moving
  walls that shove you along.
  **Ladder** sprites (platformers): hold up or down while touching one to
  climb it, with no gravity. Jump lets go. Up on a ladder climbs rather than
  jumps.
  **Falling** platforms (platformers) look and ride like a platform, but stay
  put until you've stood on them for about 1¼ seconds. They shake, drop out of
  sight, and come back at their start spot about 3 seconds later, once nothing
  is standing there. Stepping off resets the wait.
  **Battle** sprites start a turn-based fight when you touch them. Settings:
  HP, ATK and DEF (tap to step through each), and ONCE / REPEAT / BOSS. The
  text you type for the sprite is the line the enemy says first. The enemy
  is the sprite's own art. The fight uses the Arduboy/web engine's rules:
  ATTACK, HEAVY, POWER STRIKE (once per fight), DEFEND, POTION and RUN, with
  the same odds and damage. A boss can't be run from; it charges a big hit
  every fourth turn and gets enraged at half HP. Running out of HP is
  game over. The hero has 5 HP (it used to be 3), the same as the web hero. Winning a ONCE fight clears it from the map.
  **Enemy** sprites get a behavior, HP (1–9) and SLOW/MED/FAST, so every
  enemy sprite you draw is its own enemy type. Draw enemies **facing left**;
  they flip when they turn.
  - **Walker:** back and forth, turns at walls and ledges.
  - **Hopper:** hops along (top-down: dashes in random directions).
  - **Flyer:** flies in a wave, no gravity.
  - **Chaser:** patrols, then comes after you when you're close.
  - **Shooter:** stands still, faces you and shoots (straight across in
    platformers, aimed at you in top-down).

  Enemies lose 1 HP per **stomp** (jump on them) or **gun bullet**. Melee
  swings don't hurt enemies. A hurt enemy is
  stunned for a moment, gets knocked back and plays its Hurt animation (or
  blinks), and can't hurt you while stunned. Shooters play Attack when firing.
  **Melee** and **gun** sprites are pickups. Once your project has one, every
  player sprite gets extra animation slots: `M.Idle`, `M.Walk`, `M.Attack`...
  and `G.Idle`, `G.Walk`, `G.Attack`... (one for each normal animation except
  Hurt). Touch a pickup in play and the player switches to that set; any slot
  you leave empty falls back to the normal one, so only draw what changes.
  One weapon at a time: the latest pickup wins, and it carries into the next
  scene. Without a weapon, the attack button does nothing.
  - **Melee:** longer reach (1.5 tiles) with a sweeping slash arc drawn over
    your M.Attack. It breaks breakable blocks, but doesn't hurt enemies.
  - **Gun:** B shoots a bullet. The barrel point is the **middle of the
    frame's right edge** (top/bottom/left edge when facing those ways in
    top-down). Draw your barrel there: the muzzle flash appears just outside
    it and bullets come out of it. Bullets hurt enemies and break breakables.
  **Text** sprites show a message in a text box. When you set a sprite's
  kind to text, an on-screen keyboard comes up so you can type the message
  (**EDIT TEXT** brings it back later). On the keyboard:

  | | |
  |---|---|
  | D-pad | move the highlight (or point with the mouse) |
  | A | type the highlighted key |
  | B | delete |
  | Y | space |
  | X | letters / symbols |
  | L / R | move the text cursor |
  | Start / DONE | keep it |
  | Select | cancel, keeping the old text |

  The preview wraps exactly like the in-game box: 74 characters a line,
  4 lines a page, with a line where each new page starts. ENTER starts a new
  line. Messages can be up to 300 characters. The font is capitals only.

  The second button picks when the message shows:
  - **ON TOUCH:** when the player walks into it. **EVERY TIME** shows it
    again each time you walk back onto it; **ONCE** only the first time.
  - **SCENE START:** as soon as the scene begins.
  - **SCENE END:** when the player reaches the goal, before the next scene
    (or before YOU WIN on the last one).

  Draw art on a text sprite and it's a visible sign. Leave it blank and it's
  an invisible trigger zone (the map shows it as a **T**). Start and end
  messages can go anywhere in the scene. Several of them show one after
  another, left to right, top to bottom. The game pauses while a box is up.
  The text types itself out; A or B shows the rest, then turns the page or
  closes it. The box sits at the bottom of the screen, or at the top when
  the player is down there.
- **Map tab:** pick a sprite from the left column and paint. There's one player
  start per scene, so placing a new one moves it. Use +SCENE for more levels;
  a goal sends you to the next scene, and on the last scene it means you win.
  Platforms show a faint line and outline where they travel to.

  The **MAIN / BACK** button at the top of the tile column switches layers.
  BACK is a parallax background: paint clouds, stars or a skyline with any
  sprite (kinds don't apply there). The layer you're not painting shows
  dimmed. On BACK, the **BG** button sets how fast it scrolls compared to the
  level: fixed, x0.25, x0.5 or x0.75. In play the background is drawn darker
  so it reads as far away.
- **Play tab:** runs the current scene full screen at 160x120, drawn at 2x
  (pixel-perfect on a 320x240 screen; 20x15 tiles at 8px). The HUD sits on top.
  Platformer projects get gravity, enemy stomping and a B attack, plus the
  game-feel set: coyote time, jump buffering, variable jump height, apex hang,
  corner correction, acceleration/friction, hit-stop and screen shake. Top-down projects get 8-way movement and an A/B
  attack in the facing direction. An attack defeats enemies one tile in front;
  without an Attack animation you see a simple slash instead.

## Raycast (first-person) games

Pick **FIRST-PERSON** on the new-game screen for a Doom-style dungeon. The
same map grid is used, but you look at it from inside:

- **Walls are stacks.** On the MAP tab in a first-person game, solid and
  breakable sprites stack instead of painting one tile: each click adds a
  piece on top of the cell, and **right-click** takes the top piece off
  (dragging paints one piece per cell). A tree is a trunk with leaves on top;
  a building is walls with a roof. Up to 6 high. Each stack shows its height
  in its corner, and the footer shows the height of the tile under the cursor.
- **Everything else stands in its cell** as a sprite that faces you: monsters,
  coins, text, the goal and hazards. Anything you paint on the map that isn't
  a wall is one of these.
- **Controls:** left/right turn, up/down walk, X + left/right strafe.
- **Dungeon crawling:** a **battle** sprite starts a turn-based fight when you
  walk into its cell (same rules as platformers; ONCE / REPEAT / BOSS work the
  same). Coins are picked up when walked into, the **goal** moves you to the
  next scene, **text** shows its message and **hazards** hurt you.
- **The player sprite** is where you start, and which direction you face at
  the start is north. Your own body is never drawn.
- **Weapons:** walk onto a **melee** or **gun** pickup to take it. Then the
  weapon's view appears at the bottom of the screen, drawn from the player
  sprite's animations: `M.Idle`, `M.Walk`, `M.Attack` for a sword or
  `G.Idle`, `G.Walk`, `G.Attack` for a gun (plain `Idle`/`Walk`/`Attack` are
  the fallback). Walking plays Walk; the attack button plays Attack from start
  to end. Melee hits the nearest enemy within 1.5 cells in front of you; a gun
  hits the nearest enemy straight ahead within 10 cells, unless a wall is nearer.
  Enemies and fight triggers lose 1 hit point per hit and are defeated at 0
  (a fight trigger defeated this way never starts its fight).
- **Floor and ceiling objects** lie flat: a **floor** object is a flat sprite on
  the ground and a **ceiling** object is flat on the ceiling. Their pixels are
  drawn in perspective, so a rug or a lamp reads as part of the room. Walls
  and other things cover them, and you walk over them. In side-view and
  top-down games they act as scenery.
- Enemy behaviors (walker, shooter...) don't apply here: monsters are battles,
  and other enemy sprites are just decoration.

## Tuning the feel

Every physics and feel number is in the `FEEL` table at the top of
`editors/play.lua`, with a comment on each: jump height, gravity, coyote and
buffer frames, how floaty the air control is, how hard hits freeze and shake,
platform speeds. Edit the loose `lutrofx` folder version, launch its
`main.lua`, and you'll feel the change right away. Re-zip it as `.lutro` once
you're happy.

## Files

```
conf.lua            screen size (320x240)
main.lua            tabs, top bar, new-game screen, save hotkeys
lib/gfx.lua         colours, 3x5 pixel font, sprite canvas cache
lib/input.lua       gamepad + mouse + virtual cursor
lib/ui.lua          buttons
lib/keyboard.lua    on-screen keyboard
lib/project.lua     project data, save slots
lib/app.lua         shared state
lib/raycast.lua     first-person view for FIRST-PERSON games
lib/splash.lua      the opening splash screen
editors/sprite.lua  sprite editor
editors/map.lua     map editor
editors/play.lua    play-test engine
editors/games.lua   games screen (save slots)
```

## Lutro quirks this works around

- `setColor` takes 0-255 integers.
- There's no default font, so `print` errors; the editor draws its own font.
- `draw()` ignores scaling, so sprites are pre-rendered per zoom level and cached.
- There's no `mousepressed` callback, so clicks are detected by polling `isDown`.
- `filesystem.write` only writes inside the game folder, so saves go through
  Lua's `io` into the save folder instead.
- On desktop LÖVE it should also run (colours and the mouse are converted),
  but that path hasn't been tested.
