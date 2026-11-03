# Ashfall

Top-down 2D zombie survival game for PC, made with [Godot 4.7](https://godotengine.org).

- Feature plan: [docs/FEATURES.md](docs/FEATURES.md)

## Play
Download `Ashfall.exe` (Windows) and double-click it. No install needed.

## Controls
| Key | Action |
|---|---|
| WASD | Move |
| Shift | Sprint (louder — attracts zombies) |
| Mouse / Left click | Aim / Attack |
| E | Search container |
| R | Reload (restart when dead) |
| 1–6 | Use / equip hotbar slot |
| Tab or I | Inventory (drag to move, right-click use/equip, drag outside to drop) |
| F / G / H | Eat / Drink / Bandage |
| Esc | Pause (Q to quit) |
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
