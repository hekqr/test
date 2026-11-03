class_name Items
## Item and weapon definitions.

## size  = pocket space the item (or one stack of it) takes
## stack = max per stack; 1 = not stackable. Stackable items merge automatically when picked up.
const DEFS := {
	"food": {"name": "Canned food", "icon": "icon_food", "size": 1, "stack": 1, "kind": "consumable"},
	"water": {"name": "Water bottle", "icon": "item_water", "size": 1, "stack": 1, "kind": "consumable"},
	"bandage": {"name": "Bandage", "icon": "icon_bandage", "size": 1, "stack": 1, "kind": "consumable"},
	"ammo_pistol": {"name": "Pistol ammo", "icon": "icon_ammo_pistol", "size": 1, "stack": 30, "kind": "ammo"},
	"ammo_shotgun": {"name": "Shotgun shells", "icon": "icon_ammo_shotgun", "size": 1, "stack": 12, "kind": "ammo"},
	"pistol": {"name": "Pistol", "icon": "icon_pistol", "size": 3, "stack": 1, "kind": "weapon"},
	"bat": {"name": "Baseball bat", "icon": "icon_bat", "size": 5, "stack": 1, "kind": "weapon"},
	"shotgun": {"name": "Shotgun", "icon": "icon_shotgun", "size": 6, "stack": 1, "kind": "weapon"},
}

const WEAPONS := {
	"fists": {"name": "Fists", "melee": true, "damage": 18.0, "range": 34.0, "cooldown": 0.55, "noise": 90.0, "held": ""},
	"bat": {"name": "Baseball bat", "melee": true, "damage": 42.0, "range": 48.0, "cooldown": 0.75, "noise": 140.0, "held": "item_bat"},
	"pistol": {"name": "Pistol", "melee": false, "damage": 45.0, "mag": 8, "ammo": "ammo_pistol",
		"cooldown": 0.32, "reload": 1.4, "pellets": 1, "spread": 0.03, "range": 750.0, "noise": 750.0,
		"held": "item_pistol", "bullet_ui": "ui_bullet_pistol"},
	"shotgun": {"name": "Shotgun", "melee": false, "damage": 24.0, "mag": 5, "ammo": "ammo_shotgun",
		"cooldown": 0.8, "reload": 2.4, "pellets": 6, "spread": 0.32, "range": 380.0, "noise": 1000.0,
		"held": "item_shotgun", "bullet_ui": "ui_bullet_shotgun"},
}

## Weighted container loot: [id, weight, min, max]
const LOOT_TABLE := [
	["food", 22, 1, 1], ["water", 22, 1, 1], ["bandage", 14, 1, 1],
	["ammo_pistol", 14, 4, 10], ["ammo_shotgun", 8, 2, 6],
	["bat", 6, 1, 1], ["pistol", 5, 1, 1], ["shotgun", 3, 1, 1],
]


static func name_of(id: String) -> String:
	return DEFS[id]["name"]


static func icon(id: String) -> Texture2D:
	return Game.tex(DEFS[id]["icon"])


static func is_weapon(id: String) -> bool:
	return DEFS[id]["kind"] == "weapon"


static func size_of(id: String) -> int:
	return DEFS[id]["size"]


static func max_stack(id: String) -> int:
	return DEFS[id]["stack"]


## Returns a new item stack, e.g. {"id": "pistol", "count": 1, "mag": 3}
static func make(id: String, count := 1) -> Dictionary:
	var it := {"id": id, "count": count}
	if WEAPONS.has(id) and not WEAPONS[id]["melee"]:
		it["mag"] = randi_range(0, int(WEAPONS[id]["mag"]) / 2)
	return it


static func roll_loot() -> Array:
	var out := []
	var total := 0
	for row in LOOT_TABLE:
		total += int(row[1])
	for i in randi_range(1, 3):
		if randf() < 0.12:
			continue
		var r := randi() % total
		for row in LOOT_TABLE:
			r -= int(row[1])
			if r < 0:
				out.append(make(row[0], randi_range(row[2], row[3])))
				break
	return out
