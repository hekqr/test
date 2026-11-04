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
- ✅ **Gear-slot inventory** (slots, not space): Head, Armour, Coat, Shirt, Pants, Boots, Back, Hands (extra slot),
  1 Main gun, 2 Secondary, 3 Melee
- ✅ Clothing & backpacks give storage slots (Hoodie 2, Jacket 4, Jeans 2, Cargo pants 4,
  Vest 2, Small backpack 6, Hiking backpack 10; shirts none). One item or one stack per slot. Clothes keep their contents
  when taken off or dropped
- ✅ Coat + shirt can be worn together
- ✅ Weapons & clothing are "big": only fit in a backpack, Hands, or their own slot
- ✅ **Armour points**: 1 point = 10% less damage (8 pts = 20% dmg, 9 pts = 10%). Helmet 2, vest 3, clothes
  0.2–0.8. Best possible gear ≈ 6.7 (hard cap 7.5) — you can never reach 10
- ✅ **Wear**: zombie hits wear down worn clothing — outer layers and sleeves wear more, a shirt under a coat less.
  Worn items keep 60–100% of their armour/warmth; at 0% they're **ruined** (no armour/warmth, can't be worn,
  nothing new fits inside)
- ✅ Head slot takes all head items: helmet, baseball cap, beanie
- ✅ Coat/vest lower bleeding chance; boots make footsteps quieter
- ✅ **Temperature**: body temp drifts toward outside air (35 day / 10 night) + 25 indoors + clothing warmth
  (t-shirt 3 … leather jacket 20, beanie 10). Below 50 = chilly, below 30 = cold, below 15 = freezing (hurts)
- ✅ **Healing** only when warm (≥ 50), hunger ≥ 75%, thirst ≥ 75% and not bleeding
- ✅ Inventory screen: NEARBY (container / ground) | STORAGE cards | GEAR; drag & drop, right-click
  use/wear/equip/take, Take all, drag outside to drop
- ✅ Containers open into the inventory and keep what you store in them
- ✅ Weapon switching 1 / 2 / 3 or mouse wheel (weapon stays in its slot; X = fists)
- ✅ Action button appears automatically near containers ("Search") and ground items ("Pick up …")
- ✅ Loose items lying on floors, dropped items show their own icon (and join a pile at your feet)
- ✅ Night = uniform dark-blue tint (no limited light radius)
- ✅ Melee fights for you (auto-swings at zombies in reach)
- ✅ Baseball bat (melee) and shotgun (6-pellet spread, shells)
- ✅ Roofs over buildings that fade when you walk inside
- ✅ Pixel-art stat bars (health / hunger / thirst) and bullet indicators
- ✅ Stamina removed (sprint is unlimited but loud)
- ✅ **Auto-save** every 20 s, on quit/close and on death (one save file)
- ✅ Death keeps the save but marks it dead — it can't be continued
- ✅ Title menu: Continue / New Game (confirms before replacing a living survivor) / Quit
- 💭 Dev "revive" for dead saves
- 🔜 Item variety: medkit, painkillers, more clothing
- 📌 **Stacking rule:** only items that make sense to stack get a max-stack value (ammo now: pistol 30, shells 12).
  Every new stackable item (e.g. nails, rags, matches) gets its own max stack when it's added; it then merges
  automatically on pickup. Food, water, bandages and weapons stay single items.
- 🔜 Weapon durability
- 🔜 Building interiors: furniture, doors that open/close
- 🔜 Sound + music (after saving)

## Milestone 2.5 — Content & world
- ✅ **All pack weapons**: knife, baseball bat, fire axe (melee); pistol, shotgun, assault rifle, hunting rifle
- ✅ **Separate ammo**: 9mm (pistol), 12ga (shotgun), 5.56 (assault rifle), .308 (hunting rifle) — different
  types never stack together and a gun only loads its own ammo
- ✅ **Food & drink**: canned food (hunger only), canned soup (hunger + thirst), salted / cheese chips, raw meat
  (35% chance of food poisoning), water bottle, soda can
- ✅ **Medical**: bandage only stops bleeding; first aid kit cures bleeding + poisoning and heals a little
- ✅ **Food poisoning** status: slowly hurts, drains thirst faster, stops healing (90 s)
- ✅ **Tear** a T-shirt (2) or flannel shirt (3) into bandages (right-click menu)
- ✅ **Right-click menu** in the inventory: Eat / Drink / Use / Wear / Equip / Take off / Tear / Take / Drop
- ✅ **Random clothing colours** (basic colours per item type); icons and the **character sprite** are recoloured
  (shirt, coat/sleeves, hat over the hair, backpack on the back). Pants & boots are too small on the sprite to show
- ✅ **Hand-made buildings** with real rooms, interior doors, windows (see-through), tiled / wooden / concrete floors
  and furniture: small house, family house, grocery shop, police station, garage, clinic. Placed facing the roads
- ✅ **Street props**: street lights, stop signs, hydrants, benches, garbage bins (searchable), trash bags, barrels,
  manholes, traffic cones, shopping carts outside shops
- ✅ **Cars** parked on roads (cars, vans, buses, scrap cars, motorcycles) — each can be searched once, max one item
- ✅ **Wilderness**: rocks, stumps, logs, sticks, flowers, mushrooms, dead trees, rare item finds
- ✅ **Loot depends on location**: fridges = drinks/meat, cupboards = canned food, wardrobes = clothes,
  medicine cabinets = bandages/first aid, police lockers = guns/ammo/vests, garages = tools/melee/hunting rifle,
  shops = food & drinks, clinics = medical, bins/cars = little, wilderness = rare

## Milestone 2.6 — Hunting & fire
- ✅ **Animals**: rabbits and deer (drawn — the packs have none) wander the wilderness, run from you
  (walking lets you get closer than sprinting) and from noise; they respawn over time
- ✅ **Hunting & skinning**: shoot or hit an animal; skin the carcass with a knife or axe for raw meat
  (rabbit 1, deer 3)
- ✅ **Campfires**: 3 sticks + 1 match (C key, or right-click sticks/matches). Burns 60 s per stick (max 5 min),
  add wood to keep it going, relight with a match. Warms you a lot nearby and lights up the night
- ✅ **Cooking**: use a lit fire to cook all your raw meat into cooked meat (more food, never poisons)
- ✅ Sticks lie around in the woods; matches in kitchens, desks, garages, cars
- ✅ **Stacking**: bandages 5, sticks 10, matches 10, raw/cooked meat 4 (plus ammo)
- ✅ **Loot nerfed**: most containers now often hold nothing; fewer loose items; smaller ammo finds
- ✅ **Double-click** an item: wear / equip / use (or take it from a nearby container)
- ✅ **Keybind fix**: key presses are handled as events (never missed between frames); letter keys follow the
  printed key on any keyboard layout; F/G/H/1/2/3/R/X also work with the inventory open

## Milestone 2.7 — Inventory redesign
- ✅ Inventory screen in **two areas**: NEARBY (a list of what's in the container / on the ground, with icons
  and a short info line: count, rounds loaded, condition, slots, warmth, food value...) and INVENTORY
- ✅ Every gear slot is a big **two-colour symbol** of its item type (shirt shape for the shirt slot, etc.)
- ✅ Each clothing slot has **fixed room** for the most storage that kind of item can give, so putting on a
  coat or backpack never moves the menu
- ✅ **Shirts give no storage** (coat, armour, pants and backpack do)
- ✅ Drawn icons (clothing, soda, meat, matches) redone at **4× the detail** with smooth shapes and shading

## Milestone 2.8 — Gun aiming
- ✅ **Guns aim for you**: they lock onto the nearest zombie you can see in range (animals if no zombies,
  the mouse direction if nothing), keeping the same target unless another gets clearly closer
- ✅ **Aim cone** shows where the shot can land; it narrows while you stand still (red → green) and opens up
  when you walk (more when sprinting), shoot (recoil) or switch targets. You click to fire whenever you like
- ✅ Settle time per gun: pistol 0.7 s, assault rifle 1.1 s (tiny recoil), shotgun 1.5 s (never fully tight),
  hunting rifle 2.2 s (pin-point when settled, big recoil)
- ✅ **Damage shown** for every weapon (item info, tooltips, inventory, HUD); shotgun shows
  "24 - 144 damage (1 - 6 pellets)"

## Planned
- 📌 **Base building** (wooden & reinforced walls and gates are in the art pack)

## Ideas to borrow (inspired by other survival games, built our own way)
- 💭 Show worn clothing / helmet on the character sprite
- 💭 Character portrait in the HUD
- 💭 Notebook menu: local map (towns/roads), guides, crafting, tasks
- 💭 Temperature / warmth bar

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
