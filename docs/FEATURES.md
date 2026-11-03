# Ashfall — Feature Plan

Working title. Top-down 2D zombie survival for PC (Windows first), built in Godot 4.

Status: ✅ done · 🔜 next · 💭 idea / undecided

## Milestone 1 — Playable prototype ✅
- ✅ Random map: roads, buildings with doors & rooms, forests, map border
- ✅ Top-down movement, mouse aim, sprint
- ✅ Needs: health, hunger, thirst, bleeding
- ✅ Loot containers in buildings (food, water, bandages, ammo, pistol)
- ✅ Knife (melee) + pistol (ammo, magazine, reload)
- ✅ Zombies: wander, hear noise (walking/sprinting/gunshots), chase on sight, pathfind around walls
- ✅ Day/night cycle — darker nights, more zombies, flashlight
- ✅ HUD, help, pause, death screen + restart
- ✅ Windows .exe build, automated smoke test

## Milestone 1.5 — Pixel art pass ✅
- ✅ Pixel-art tiles: grass, asphalt roads, wooden floors, brick walls
- ✅ Animated player (idle / run / punch / death, 4 directions)
- ✅ Animated zombies (walk / attack / death) + **big zombie** variant (slow, tanky, hits hard)
- ✅ Trees, bushes, blood stains, corpses that stay for a while
- ✅ Item icons in HUD, container sprites
- ✅ Deep-colour grading + vignette shader

## Milestone 2 — Core survival loop
- ✅ Inventory screen: 18 slots, stacking, drag & drop, right-click use/equip, drop as bag
- ✅ 6-slot hotbar (keys 1–6)
- ✅ Baseball bat (melee) and shotgun (6-pellet spread, shells)
- ✅ Roofs over buildings that fade when you walk inside
- ✅ Pixel-art stat bars (health / hunger / thirst) and bullet indicators
- ✅ Stamina removed (sprint is unlimited but loud)
- 🔜 **Save & load** (next)
- 🔜 Item variety: medkit, painkillers, backpacks (bigger inventory)
- 🔜 Weapon durability
- 🔜 Building interiors: furniture, doors that open/close
- 🔜 Sound + music (after saving)

## Milestone 3 — World & content
- 💭 Hand-designed + generated towns, named locations, a world map
- 💭 Zombie types: runner, tank, crawler
- 💭 Vehicles (car with fuel)
- 💭 Weather (rain, fog)
- 💭 Crafting & base building (barricades)
- 💭 Infection / sickness system

## Milestone 4 — Polish & release
- 💭 Real art (sprites, animations) and effects (blood, muzzle flash, footprints)
- 💭 Main menu, settings (keybinds, volume, resolution)
- 💭 Controller support
- 💭 Steam / itch.io release

## Open questions (decide these)
1. **Multiplayer?** Co-op or PvP changes a lot of the code — best decided early.
2. **Permadeath** (one life, new map) or **persistent world** with saves?
3. **Real name** for the game.
4. **Commercial release?** Current art packs are non-commercial only — buy licenses or replace art before selling.
