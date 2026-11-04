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

## Milestone 3 — World, buildings, map, crafting
- ✅ **Settlements**: a bigger map (200 × 200 tiles) with a city (street grid; shops, police, clinic, houses),
  two towns (main street + cross streets) and ~5 villages (one road), each with its own name and building mix,
  all connected by highways. Wilderness (forests, animals, nature) in between. You start in a village
- ✅ Zombies gather in settlements (most in the city); fewer out in the wild
- ✅ **3/4 view buildings**: from outside you see a raised roof and a 2-tile front wall with windows and an
  open door (pack wall tiles in 4 colours); zombies inside are hidden behind it. Inside, walls with floor in front
  of them show their face (with windows), the rest are thin dark tops. Buildings cast a shadow
- ✅ **Less loot in houses**: ~45% of house furniture has already been looted; fewer loose items
- ✅ **Map** (M): paper map of roads, buildings and forests with town names, your position and a compass.
  Only explored areas are drawn — a **Road map** item (cars, desks, garages, police) shows everything. Saved
- ✅ **Crafting** (K or the CRAFTING tab in the inventory):
  - Bandage = 2 rags
  - Rope = 3 rags
  - Sack backpack (4 slots) = sack + rope
  - Wooden spear (melee, longest reach) = 3 sticks + rope, needs a knife or axe
  - Campfire = 3 sticks + 1 match
  - Shirts / flannels now tear into **rags** (3 / 4)
- 💭 **Crafting ideas for later**: bow & arrows, splint (for broken legs), torch, barricade planks for doors &
  windows, boiling dirty water, scrap helmet

## Milestone 4 — Enemies, wear & repair
- ✅ **Melee nerf**: all melee damage −20% (fists 14, knife 22, spear 27, bat 34, axe 48)
- ✅ **Weapon wear**: weapons have condition. Melee weapons wear on every hit, guns on every shot.
  Worn melee weapons hit up to 25% softer; guns below 50% can **jam**. At 0% a weapon is broken (fists)
- ✅ Found clothes and weapons are used (35–100% condition)
- ✅ **Repairs** (right-click → Repair): +40% condition per use, ruined things can't be fixed
  - **Sewing kit** (5 uses): clothing, backpacks — wardrobes, boxes, desks
  - **Toolbox** (5 uses): weapons, helmets, improvised armour — tool crates, cars, police lockers
- ✅ **Improvised armour** (armour slot, 2.2 armour) = 3 scrap metal + 2 rope. Scrap metal: crates, cars, bins
- ✅ **Zombie types**:
  - Walker — the usual
  - Runner — fast (faster than walking, slower than sprinting), weak; more at night
  - Brute — big, slow, very tough
  - Axe zombie — throws its axe from a distance, then walks over to pick it up (grab it first!)
  - Armed zombie — dead soldier / cop that shoots until its magazine is empty, drops the gun; more in the city
- ✅ **Bandits** (hostile survivors): groups of 1–3 in towns and along roads (up to 8 alive). They wear random
  clothes, carry a gun and/or melee weapon, spare ammo and supplies. They attack you on sight, shoot zombies
  that get close (zombies attack them too), keep their distance with guns, reload, run away and bandage up when
  hurt, and drop **everything** they carry when killed. Gunfights are loud — zombies come running
- ✅ Kills only count when you land the killing blow

## Milestone 5 — Wildlife & water
- ✅ **Quieter guns**: gunshots carry about half as far as before (pistol 380 px, shotgun 480, rifle 440,
  hunting rifle 520, armed zombies 350)
- ✅ **Zombie stats** (each zombie varies ±10% in health, speed and damage):
  walker 100 hp · runner 80 hp, runs 190 (about your sprint speed), hits a bit softer · brute 300 hp, a bit slower, hits 50% harder ·
  axe zombie 100 hp · armed zombie 100 hp + vest (armour 3 = 30% less damage, sometimes drops it)
- ✅ **Wolves** (40 hp, run 210 — faster than runners and than you, bite 9–16): packs of 2–3 roam the wilderness. They hunt you (and bandits) on sight — further at
  night — bite and back off, call the pack when one is hurt, and run when badly wounded.
  Bandits shoot them. Skin a dead wolf for **2 meat + 1 leather** (deer now give 1 leather too)
- ✅ **Leather crafting**: 2 leather = sack, 1 leather = **water gourd**
- ✅ **Water gourd**: holds 4 drinks (each = a water bottle, +40 thirst). Right-click → Drink, or G when
  you have no bottles. Refill it at water sources
- ✅ **Lakes & a river**: 3–5 lakes in the wilderness and usually a river across the map; roads cross it on
  bridges. Water blocks walking but not bullets or sight. Shown on the map. E at the bank: drink your fill
  and fill your gourds
- ✅ **Bathroom taps** in houses: about half still have a little water left (1–6 drinks), saved per tap

## Milestone 6 — Inventory-first actions
- ✅ Eating, drinking and bandaging are done from the inventory: **click an item** to see what you can do
  with it (double-click = its main action, drag = move). The F / G / H hotkeys are gone
- ✅ Your survivor speaks up: "I'm hungry" / "I'm thirsty" below 25% (every minute, "I'm starving!" /
  "I'm dehydrated!" at 0), "I'm bleeding!"
- ✅ Action button text centred on the button face, no text shadow

## Milestone 7 — Doors & sneaking
- ✅ **Doors** on every doorway (front, back and inside). They open by themselves when a person — you or a
  bandit — walks up, and close once the doorway is clear. **Zombies and animals can't open doors**: a closed
  door blocks them and their pathfinding, so they only get inside if they're right behind you
- ✅ Zombies no longer spot you through walls: walls, **windows** and closed doors block their sight
- ✅ Walls muffle noise: through a wall or closed door a sound only carries half as far
- ✅ Zombies never spawn in a doorway

## Milestone 8 — Rations first
- ✅ **Clusters**: settlements are small clusters of 4–7 buildings close together on one street (the "city" cluster
  has police, a clinic and a shop; town clusters a shop), at least 42 tiles of wilderness apart, linked by long
  roads with nothing on them. Map is 256 × 256
- ✅ **Smaller houses** (9×7 and 11×8): bedroom(s), bathroom, living room with a kitchen corner
- ✅ **Only sensible things can be searched** in houses: fridge, wardrobe, medicine cabinet, trash can.
  Kitchen counters and desks are just furniture; boxes and washing machines are gone.
  Shops, pharmacies, police lockers and tool crates still have their own loot
- ✅ **Fridges and wardrobes** always have 1–3 tries (30% empty each); shop shelves give less
- ✅ **Rations are the main problem**: hunger / thirst drain the same as before, but a whole map now holds only
  about 1.5–2 hours of food (mostly in fridges). Hunt, cook, and refill at lakes and taps to stretch it.
  Rare finds in the woods are much rarer
- ✅ **Far fewer zombies**: 30 by day / 45 at night (was 110 / 160), a new one every 12 s at most
- ✅ **Zombie health bars** once they're hurt
- ✅ **Everyone ~40% slower**: you 84 / 117 (walk / sprint), walker chase 67, runner 114, brute 60,
  wolves 126, bandits 37 / 83, deer 105, rabbits 99. Animations slowed to match
- ✅ **Hitbox at the feet**: characters collide where their feet are (a flat capsule) instead of a circle that
  stuck out below the sprite — no more stopping short of walls when walking down
- 🔧 Dev tool: `tests/loot_census.tscn` counts how much food / water a new world has

## Milestone 9 — Big world, settlements, performance
- ✅ **Map 4× bigger** (512 × 512 tiles) with ~20 settlements: hamlets (4–7 buildings on one street), villages
  (~9–12 on a main street with a side street), towns (~11–13, a small street grid with a shop and a clinic) and
  one city (16: police, clinic, shops, garages). Far apart, linked by long roads
- ✅ **Tiny one-room huts** make up most villages: bedroom hut (wardrobe, fridge, trash), kitchen hut (fridge,
  medicine cabinet, trash), bathroom hut (bath with tap, wardrobe, fridge, trash), tool shed (crate)
- ✅ **Paper map** (M): forests, lakes and the river, roads and streets, each settlement as an icon (4 blocks =
  city, 3 = town, 2 = village, 1 = hamlet) with its name, a lettered / numbered grid, a legend and a compass.
  **Scroll to zoom, drag to move.** Fog over places you haven't been (a Road map shows everything)
- ✅ **Mouse wheel zooms the camera** (weapons stay on 1 / 2 / 3)
- ✅ **White outline** around items lying on the ground
- ✅ **Performance**
  - World generation ~6 s → ~2 s on the 4× map ("Generating the world..." screen while it runs)
  - Trees, props and decor only exist near you (streamed in chunks); overlays are drawn per region
  - Zombies, animals and bandits live around you: they spawn out of sight and are removed far away
  - Zombies after you inside a house head for its door instead of searching the whole map (was ~10–50 ms)
  - Autosave every 30 s runs in the background (~10 ms on the game thread instead of ~140 ms), and only
    saves containers you've opened
  - Ground items and containers no longer redraw every frame
- 🔧 Dev tools: `tests/perf_probe.tscn` (startup, autosave, frame spikes), `tests/loot_census.tscn`

## Planned
- 📌 **Base building** (wooden & reinforced walls and gates are in the art pack)

## Ideas to borrow (inspired by other survival games, built our own way)
- 💭 Show worn clothing / helmet on the character sprite
- 💭 Character portrait in the HUD
- 💭 Notebook menu: local map (towns/roads), guides, crafting, tasks
- 💭 Temperature / warmth bar

## Milestone 3 — World & content
- 💭 Hand-designed + generated towns, named locations, a world map
- ✅ Zombie types: runner, brute, axe, armed (crawler still an idea)
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
