class_name Items
## Item, clothing and weapon definitions.
##
## kind   consumable | ammo | weapon | clothing
## stack  max per stack; 1 = not stackable. Stackable items merge automatically when picked up.
## equip  gear slot the item is worn / carried in (weapons and clothing)
## cargo  storage slots a piece of clothing / backpack gives
## big    true = only fits in a backpack, the Hands slot or its own gear slot
## protect fraction of zombie damage absorbed (helmet / armour)

const DEFS := {
	"food": {"name": "Canned food", "icon": "icon_food", "stack": 1, "kind": "consumable"},
	"water": {"name": "Water bottle", "icon": "item_water", "stack": 1, "kind": "consumable"},
	"bandage": {"name": "Bandage", "icon": "icon_bandage", "stack": 1, "kind": "consumable"},
	"ammo_pistol": {"name": "Pistol ammo", "icon": "icon_ammo_pistol", "stack": 30, "kind": "ammo"},
	"ammo_shotgun": {"name": "Shotgun shells", "icon": "icon_ammo_shotgun", "stack": 12, "kind": "ammo"},

	"pistol": {"name": "Pistol", "icon": "icon_pistol", "stack": 1, "kind": "weapon", "equip": "secondary", "big": true},
	"bat": {"name": "Baseball bat", "icon": "icon_bat", "stack": 1, "kind": "weapon", "equip": "melee", "big": true},
	"shotgun": {"name": "Shotgun", "icon": "icon_shotgun", "stack": 1, "kind": "weapon", "equip": "primary", "big": true},

	"tshirt": {"name": "T-shirt", "icon": "px:tshirt", "stack": 1, "kind": "clothing", "equip": "shirt", "cargo": 1, "big": true},
	"flannel": {"name": "Flannel shirt", "icon": "px:flannel", "stack": 1, "kind": "clothing", "equip": "shirt", "cargo": 2, "big": true},
	"hoodie": {"name": "Hoodie", "icon": "px:hoodie", "stack": 1, "kind": "clothing", "equip": "coat", "cargo": 2, "big": true},
	"jacket": {"name": "Leather jacket", "icon": "px:jacket", "stack": 1, "kind": "clothing", "equip": "coat", "cargo": 4, "big": true, "protect": 0.05},
	"jeans": {"name": "Jeans", "icon": "px:jeans", "stack": 1, "kind": "clothing", "equip": "pants", "cargo": 2, "big": true},
	"cargo_pants": {"name": "Cargo pants", "icon": "px:cargo_pants", "stack": 1, "kind": "clothing", "equip": "pants", "cargo": 4, "big": true},
	"boots": {"name": "Work boots", "icon": "px:boots", "stack": 1, "kind": "clothing", "equip": "boots", "cargo": 0, "big": true},
	"vest": {"name": "Tactical vest", "icon": "px:vest", "stack": 1, "kind": "clothing", "equip": "armour", "cargo": 2, "big": true, "protect": 0.3},
	"helmet": {"name": "Helmet", "icon": "px:helmet", "stack": 1, "kind": "clothing", "equip": "head", "cargo": 0, "big": true, "protect": 0.15},
	"backpack_small": {"name": "Small backpack", "icon": "px:backpack_small", "stack": 1, "kind": "clothing", "equip": "back", "cargo": 6, "big": true},
	"backpack_large": {"name": "Hiking backpack", "icon": "px:backpack_large", "stack": 1, "kind": "clothing", "equip": "back", "cargo": 10, "big": true},
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
	["bat", 5, 1, 1], ["pistol", 4, 1, 1], ["shotgun", 2, 1, 1],
	["tshirt", 4, 1, 1], ["flannel", 4, 1, 1], ["hoodie", 4, 1, 1], ["jacket", 2, 1, 1],
	["jeans", 4, 1, 1], ["cargo_pants", 3, 1, 1], ["boots", 3, 1, 1],
	["vest", 1, 1, 1], ["helmet", 2, 1, 1], ["backpack_small", 3, 1, 1], ["backpack_large", 1, 1, 1],
]


static func def(id: String) -> Dictionary:
	return DEFS[id]


static func name_of(id: String) -> String:
	return DEFS[id]["name"]


static func icon(id: String) -> Texture2D:
	var ic: String = DEFS[id]["icon"]
	return Game.pixel_icon(ic.substr(3)) if ic.begins_with("px:") else Game.tex(ic)


static func kind(id: String) -> String:
	return DEFS[id]["kind"]


static func is_weapon(id: String) -> bool:
	return DEFS[id]["kind"] == "weapon"


static func is_clothing(id: String) -> bool:
	return DEFS[id]["kind"] == "clothing"


## Gear slot the item belongs in ("" if none).
static func equip_of(id: String) -> String:
	return DEFS[id].get("equip", "")


static func is_big(id: String) -> bool:
	return DEFS[id].get("big", false)


static func cargo_of(id: String) -> int:
	return DEFS[id].get("cargo", 0)


static func max_stack(id: String) -> int:
	return DEFS[id]["stack"]


## Returns a new item, e.g. {"id": "pistol", "count": 1, "mag": 3} or
## {"id": "jeans", "count": 1, "cond": 100, "cargo": [null, null]}
static func make(id: String, count := 1) -> Dictionary:
	var it := {"id": id, "count": count}
	if WEAPONS.has(id) and not WEAPONS[id]["melee"]:
		it["mag"] = randi_range(0, int(WEAPONS[id]["mag"]) / 2)
	if is_clothing(id):
		it["cond"] = 100.0
		var c := []
		c.resize(cargo_of(id))
		it["cargo"] = c
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
