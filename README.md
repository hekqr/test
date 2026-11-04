# Ashfall

Top-down 2D zombie survival game for PC, made with [Godot 4.7](https://godotengine.org).

- Feature plan: [docs/FEATURES.md](docs/FEATURES.md)

## Play
Download `Ashfall.exe` (Windows) and double-click it. No install needed.

The game saves automatically (every 20 s, when you quit, and when you die) to
`%APPDATA%\Godot\app_userdata\Ashfall\save.json`. A dead survivor's save is kept but can't be continued.

## Controls
| Key | Action |
|---|---|
| WASD | Move |
| Shift | Sprint (louder — attracts zombies) |
| Left click | Shoot (guns aim by themselves — stand still to steady the aim; melee attacks automatically) |
| E (or the on-screen button) | Search container / pick up item / skin animal / use campfire / drink & fill gourd at water or taps |
| C | Build campfire (3 sticks + 1 match) |
| K | Crafting |
| M | Map |
| R | Reload (restart when dead) |
| 1 / 2 / 3, mouse wheel | Primary / secondary / melee weapon |
| X | Lower weapon (fists) |
| Tab or I | Inventory: nearby / storage / gear (drag to move, double-click to equip/use, right-click for actions like Repair / Tear into rags, drag outside to drop) |
| F / G / H | Eat / Drink / Bandage or first aid |
| Esc | Pause (Q = save & quit to menu) |
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
- Windows build: `godot --headless --path . --export-release "Windows Desktop" build/windows/Ashfall.exe`
