# Ashfall

Top-down 2D zombie survival game for PC, made with [Godot 4.7](https://godotengine.org).

- Feature plan: [docs/FEATURES.md](docs/FEATURES.md)

## Play
Download `Ashfall.exe` (Windows) and double-click it. No install needed.

## Controls
| Key | Action |
|---|---|
| WASD | Move |
| Shift | Sprint |
| Mouse / Left click | Aim / Attack |
| E | Search container |
| R | Reload (restart when dead) |
| 1 / 2 | Knife / Pistol |
| F / G / H | Eat / Drink / Bandage |
| Esc | Pause (Q to quit) |
| F11 | Fullscreen |
| F1 | Toggle help |

## Development
- Open the folder in Godot 4.7 to edit.
- Smoke test: `godot --headless --path . res://tests/smoke_test.tscn`
- Windows build: `godot --headless --path . --export-release "Windows Desktop" build/windows/Ashfall.exe`
