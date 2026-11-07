# North-Star-Engine
Make your own games on your retro handheld or even android device and play them right there as well. Runs on RetroArchs's Lutro core
# North Star Engine

**Make games on your handheld, and play them right there.**

North Star Engine is a game maker that runs *on the device itself*. You draw sprites, build levels, and play-test them on a Miyoo Mini or any other handheld that runs RetroArch, using only the d-pad and buttons. You don't need a PC or any code.

<!-- TODO: add a GIF or screenshot here: drawing a sprite, then playing it -->
<!-- TODO: link your first YouTube video here -->

## Why

when i first discovered the wonderful world of handheld game consoles I saw handhelds like the playdate, and the miyoo mini and I thought "wouldn't it be cool to make the game and play them both on the handheld. 
I started looking into that option and I quickly realized it didn't really exist in the way I imagined. I couldn't afford a steam deck and there are ways to emulate retro engines through dos etc. but nothing
like I had hoped for. so i decided to make one myself. my engine is inspired by object oriented game engines and is designed around a game pad. so no keyboards or external perifersls are required. I always liked lua, love2d and pico8 so
I decided to use lutro to make my engine. it runs on basically any retro Linux handheld with retroarch or libreto. I plan to add alot more to it. any feedback would be amazing! enjoy.
## Features

- **Three game types:** platformer (gravity, jumping, stomping enemies), top-down (8-direction movement), or **first-person** (Doom-style 3D dungeons with stackable walls)
- **Sprite editor:** 16 colors, 8×8 or 16×16 sprites, named animations, onion skin, fill, flip, rotate, mirror, copy/paste
- **Map editor:** tile painting, multiple scenes, and a parallax background layer
- **19 sprite kinds**, each with its own behavior: player, solid, decor, coin, hazard, enemy, goal, breakable, moving platform, falling platform, ladder, melee pickup, gun pickup, double-jump pickup, wall-jump pickup, text, turn-based battle, and first-person floor and ceiling decorations
- **Enemy behaviors:** walker, hopper, flyer, chaser, shooter
- **Text boxes and dialogue** with an on-screen keyboard for typing on the device
- **Turn-based battles**, including bosses
- **Platformer controls that feel good:** coyote time, jump buffering, variable jump height, and double jump and wall jump as pickups you place to build progression
- **12 save slots**, autosave, and a backup of the previous save

## Install

1. Download the `.lutro` file from the [Releases](../../releases) page.
2. Copy it into the ROM folder your handheld uses for Lutro.
3. Launch it like any game, with RetroArch's **Lutro** core.

Your games are saved to RetroArch's save folder as `lutrofx_game_1.lua` … `lutrofx_game_12.lua`. On Onion OS that's usually `/mnt/SDCARD/Saves/CurrentProfile/saves/`, sometimes inside a `Lutro` subfolder. They're plain text, so you can back them up or copy them to another device.

The full how-to for every tab and sprite kind is in **[GUIDE.md](GUIDE.md)**.

**Desktop testing:** you can also run the source folder with [LÖVE](https://love2d.org): `love .`

## Controls

| Where | Controls |
|---|---|
| Everywhere | **L / R** switch tabs · **START** play / back to editor · **SELECT** save |
| Sprites | **A** draw · **B** erase · **Y** next color · **L2/R2 + d-pad** nudge pixels |
| Map | **A** place · **B** erase · **X + d-pad** scroll |
| Play (platformer) | **D-pad** move · **A** jump · **B** attack (with a weapon) · **Down + A** drop through platforms |
| Play (top-down) | **D-pad** move · **A / B** attack (with a weapon) |
| Play (first-person) | **Left / right** turn · **Up / down** walk · **X + left / right** strafe |
| Keyboard | **A** type · **B** delete · **Y** space · **X** symbols · **START** done · **SELECT** cancel |

A mouse also works wherever there's a cursor.

## Project layout

```
main.lua            entry point: boot, tabs, screen switching
conf.lua            screen size (320x240)
lib/                drawing, input, UI, keyboard, project data + saving
lib/raycast.lua     first-person view
lib/splash.lua      opening splash screen
editors/sprite.lua  sprite editor
editors/map.lua     map editor
editors/games.lua   save slots
editors/play.lua    the game runtime (physics, enemies, battles, text, first-person)
```

Want to change how the game feels? Every tuning number lives in the `FEEL` table at the top of `editors/play.lua`.

## License

- **The engine** is licensed under the [GNU GPL v3](LICENSE).
- **Your games are yours.** Sprites, maps, and save files you make with North Star Engine aren't covered by the GPL. Use, share, or sell them under any license you like. See [GAMES-EXCEPTION.md](GAMES-EXCEPTION.md).

## Contact

<!-- TODO: YouTube, Reddit, itch.io, etc. -->

Made by Our Stars Inc.
