# Project 0

Top-down 2D zombie survival game for PC, made with [Godot 4.7](https://godotengine.org).

- Feature plan: [docs/FEATURES.md](docs/FEATURES.md)

## Play
Download `Project0.exe` (Windows) and double-click it. No install needed.

The game saves automatically (every 20 s, when you quit, and when you die) to
`%APPDATA%\Godot\app_userdata\Project 0\save.json`. A dead survivor's save is kept but can't be continued.

## Controls
| Key | Action |
|---|---|
| WASD | Move |
| Shift | Sprint (louder — attracts zombies) |
| Space | Shoot — guns aim at the nearest enemy by themselves (stand still to steady the aim); melee attacks automatically |
| T | Switch between auto aim (Space, no mouse needed) and mouse aim (aim with the mouse, click to shoot) |
| Q (or the on-screen button) | Search (1 s — what you find drops on the floor) / pick up / skin / cook / drink & fill gourd / open chest / sleep / plant / harvest / chop wood (with an axe) |
| F | Fish (at a lake or river, with a fishing rod) |
| B | Build: place a building kit in front of you (Q to place, B for the next kit, X to stop). Q on something you built takes it apart |
| C | Build campfire (3 sticks + 1 match) |
| K | Crafting |
| M | Map (scroll to zoom, drag to move) |
| R | Reload (restart when dead) |
| 1 / 2 / 3 | Primary / secondary / melee weapon |
| Mouse wheel | Zoom in / out |
| X | Lower weapon (fists) |
| E (or Tab / I) | Inventory (E again closes it): click an item to see what you can do with it (Eat, Drink, Use, Wear, Repair, Tear into rags, Drop...), double-click for its main action, drag to move, drag outside to drop |
| Esc | Pause (Backspace = save & quit to menu) |
| F11 | Fullscreen |
| F1 | Toggle help |

## Art assets (not in this repo)
The game uses two third-party pixel-art packs. Their licenses allow **non-commercial use only** and
forbid redistribution, so the image files are **not** committed (`assets/thirdparty/` is git-ignored).

- Post-Apocalypse Pixel Art Asset Pack by TheLazyStone — https://thelazystone.itch.io/post-apocalypse-pixel-art-asset-pack
- Zombie Apocalypse Tileset by ittaimanero — https://ittaimanero.itch.io/zombie-apocalypse-tileset

To set up on a new machine, download both zips and run:

```
python3 tools/import_assets.py <PostApocalypse_AssetPack.zip> <Zombie_Apocalypse_Tileset.zip>
```

**Before selling the game:** pay for the Post-Apocalypse pack's commercial license (min $2) and get
commercial permission for the Zombie Apocalypse Tileset, or replace those assets.

## Development
- Open the folder in Godot 4.7 to edit.
- Smoke test: `godot --headless --path . res://tests/smoke_test.tscn`
- Windows build: `godot --headless --path . --export-release "Windows Desktop" build/windows/Project0.exe`
