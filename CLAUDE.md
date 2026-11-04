# Project 0 — notes for Claude

Top-down 2D zombie survival game for Windows. Godot 4.7.2, GDScript. The user does not code: Claude writes everything, the user plays the exported .exe.

## How to work with this user
- While working: **no running log in normal text**. Only tool calls (the small grey text) and screenshots/photos. No commentary between tool calls.
- Final reply: short. Don't explain much — list the changes made and give clear instructions.
- Original art and style only — similar theme to DayZ/MiniDayZ, never copy their art.

## Repo rules
- Work on branch `ashfall-prototype`; push with `git push -u origin ashfall-prototype`.
- No pull requests unless asked.
- Never commit `assets/thirdparty` (licensed, non-commercial, no redistribution; gitignored). `tools/import_assets.py` extracts it from the uploaded zips.

## Commands
- Tests: `timeout 500 godot --headless --path . res://tests/smoke_test.tscn`
- Screenshots: `xvfb-run -a -s "-screen 0 1600x900x24" godot --path . res://tests/screenshot.tscn -- <out_dir>`
- After adding a new `class_name` script: `godot --headless --path . --import`
- Windows build: `godot --headless --path . --export-release "Windows Desktop" build/windows/Project0.exe`, zip to `build/Project0-windows.zip` and send it to the user.
- Bump `SaveGame.VERSION` when the save format changes.

## Design decisions (from the user)
- Base walls/gates are unbreakable: the base is a fully safe, sustainable place. No raids on bases.
- No food spoilage mechanic (for now).
- Later (when asked): renewable supplies (rain collector, snares, fish trap) and utility (workbench, stove/fireplace, shelves/weapon rack).
- Rejected: fortifying/boarding up existing houses.
