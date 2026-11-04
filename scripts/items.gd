class_name Items
## Item, clothing and weapon definitions.
##
## kind    consumable | medical | ammo | weapon | clothing
## stack   max per stack; 1 = not stackable. Only the SAME item stacks (9mm never stacks with 12ga).
## equip   gear slot the item is worn / carried in (weapons and clothing)
## cargo   storage slots a piece of clothing / backpack gives
## big     true = only fits in a backpack, the Hands slot or its own gear slot
## armour  armour points (1 point = 10% less damage; best possible gear stays well below 10)
## warmth  how much the item warms you
## sleeves takes extra wear when you're attacked
## tear    rags you get from tearing it up
## repair  "sew" (sewing kit) or "tool" (toolbox): what fixes it. Weapons always use a toolbox.
## uses    repair kits: how many repairs are left in a fresh kit
## colors  random colour picked when the item spawns
## icon    "px:<name>" = drawn in code, "sheet:<tex>:<frames>:<frame>" = frame of a sprite sheet, else a texture

const DEFS := {
	# --- food & drink
	"food": {"name": "Canned food", "icon": "icon_food", "stack": 1, "kind": "consumable", "hunger": 35.0},
	"soup": {"name": "Canned soup", "icon": "icon_soup", "stack": 1, "kind": "consumable", "hunger": 20.0, "thirst": 20.0},
	"chips_salted": {"name": "Salted chips", "icon": "item_chips_red", "stack": 1, "kind": "consumable", "hunger": 15.0, "thirst": -5.0},
	"chips_cheese": {"name": "Cheese chips", "icon": "item_chips_yellow", "stack": 1, "kind": "consumable", "hunger": 15.0, "thirst": -5.0},
	"meat": {"name": "Raw meat", "icon": "px:meat", "stack": 4, "kind": "consumable", "hunger": 20.0, "poison": 0.35},
	"cooked_meat": {"name": "Cooked meat", "icon": "px:cooked_meat", "stack": 4, "kind": "consumable", "hunger": 40.0},
	"water": {"name": "Water bottle", "icon": "px:water", "stack": 1, "kind": "consumable", "thirst": 40.0},
	"soda": {"name": "Soda can", "icon": "px:soda", "stack": 1, "kind": "consumable", "thirst": 25.0, "hunger": 5.0,
		"colors": ["red", "blue", "green", "orange", "purple", "yellow", "black"]},

	# --- medical
	"bandage": {"name": "Bandage", "icon": "icon_bandage", "stack": 5, "kind": "medical", "cures": ["bleeding"]},
	"firstaid": {"name": "First aid kit", "icon": "icon_firstaid", "stack": 1, "kind": "medical", "cures": ["bleeding", "poison"], "heal": 20.0},

	# --- survival (campfires: 3 sticks + 1 match)
	"sticks": {"name": "Sticks", "icon": "nat_stick_1", "stack": 10, "kind": "material"},
	"matches": {"name": "Matches", "icon": "px:matches", "stack": 10, "kind": "material"},
	"rags": {"name": "Rags", "icon": "px:rags", "stack": 6, "kind": "material"},
	"rope": {"name": "Rope", "icon": "px:rope", "stack": 3, "kind": "material"},
	"sack": {"name": "Sack", "icon": "px:sack", "stack": 3, "kind": "material"},
	"map": {"name": "Road map", "icon": "px:map", "stack": 1, "kind": "material"},
	"scrap_metal": {"name": "Scrap metal", "icon": "px:scrap_metal", "stack": 5, "kind": "material"},
	"leather": {"name": "Leather", "icon": "px:leather", "stack": 5, "kind": "material"},
	# Refillable: holds 4 bottles' worth (one drink each). Fill it at taps, lakes and rivers.
	"gourd": {"name": "Water gourd", "icon": "px:gourd", "stack": 1, "kind": "tool", "capacity": 4, "thirst": 40.0},

	# --- repair kits (each repair adds REPAIR_AMOUNT condition; ruined things can't be fixed)
	"sewing_kit": {"name": "Sewing kit", "icon": "px:sewing_kit", "stack": 1, "kind": "tool", "uses": 5, "fixes": "sew"},
	"toolbox": {"name": "Toolbox", "icon": "px:toolbox", "stack": 1, "kind": "tool", "uses": 5, "fixes": "tool"},

	# --- ammo (each gun takes exactly one type)
	"ammo_9mm": {"name": "9mm rounds", "icon": "icon_ammo_pistol", "stack": 30, "kind": "ammo"},
	"ammo_12ga": {"name": "12ga shells", "icon": "icon_ammo_shotgun", "stack": 12, "kind": "ammo"},
	"ammo_556": {"name": "5.56 rounds", "icon": "icon_ammo_rifle", "stack": 30, "kind": "ammo"},
	"ammo_308": {"name": ".308 rounds", "icon": "icon_ammo_308", "stack": 10, "kind": "ammo"},

	# --- weapons
	"knife": {"name": "Knife", "icon": "icon_knife", "stack": 1, "kind": "weapon", "equip": "melee", "big": false},
	"bat": {"name": "Baseball bat", "icon": "icon_bat", "stack": 1, "kind": "weapon", "equip": "melee", "big": true},
	"spear": {"name": "Wooden spear", "icon": "px:spear", "stack": 1, "kind": "weapon", "equip": "melee", "big": true},
	"axe": {"name": "Fire axe", "icon": "sheet:axe_sheet:9:0", "stack": 1, "kind": "weapon", "equip": "melee", "big": true},
	"pistol": {"name": "Pistol", "icon": "icon_pistol", "stack": 1, "kind": "weapon", "equip": "secondary", "big": true},
	"shotgun": {"name": "Shotgun", "icon": "icon_shotgun", "stack": 1, "kind": "weapon", "equip": "primary", "big": true},
	"rifle": {"name": "Assault rifle", "icon": "icon_rifle", "stack": 1, "kind": "weapon", "equip": "primary", "big": true},
	"hunting_rifle": {"name": "Hunting rifle", "icon": "icon_hunting_rifle", "stack": 1, "kind": "weapon", "equip": "primary", "big": true},

	# --- clothing
	"cap": {"name": "Baseball cap", "icon": "px:cap", "stack": 1, "kind": "clothing", "equip": "head", "cargo": 0, "big": true, "warmth": 2.0,
		"colors": ["red", "blue", "black", "green", "yellow", "white", "grey"]},
	"beanie": {"name": "Beanie", "icon": "px:beanie", "stack": 1, "kind": "clothing", "equip": "head", "cargo": 0, "big": true, "warmth": 10.0,
		"colors": ["grey", "black", "red", "blue", "green", "orange", "purple"]},
	"helmet": {"name": "Helmet", "icon": "px:helmet", "stack": 1, "kind": "clothing", "equip": "head", "cargo": 0, "big": true, "warmth": 3.0, "armour": 2.0, "repair": "tool",
		"colors": ["olive", "black", "tan"]},
	"tshirt": {"name": "T-shirt", "icon": "px:tshirt", "stack": 1, "kind": "clothing", "equip": "shirt", "cargo": 0, "big": true, "warmth": 3.0, "tear": 3,
		"colors": ["white", "black", "grey", "red", "blue", "green", "yellow", "orange", "purple", "pink"]},
	"flannel": {"name": "Flannel shirt", "icon": "px:flannel", "stack": 1, "kind": "clothing", "equip": "shirt", "cargo": 0, "big": true, "warmth": 8.0, "armour": 0.2, "sleeves": true, "tear": 4,
		"colors": ["red", "blue", "green", "brown", "black", "grey"]},
	"hoodie": {"name": "Hoodie", "icon": "px:hoodie", "stack": 1, "kind": "clothing", "equip": "coat", "cargo": 2, "big": true, "warmth": 14.0, "armour": 0.3, "sleeves": true,
		"colors": ["black", "grey", "red", "blue", "green", "yellow", "purple", "orange", "white"]},
	"jacket": {"name": "Leather jacket", "icon": "px:jacket", "stack": 1, "kind": "clothing", "equip": "coat", "cargo": 4, "big": true, "warmth": 20.0, "armour": 0.8, "sleeves": true,
		"colors": ["black", "brown", "darkbrown"]},
	"jeans": {"name": "Jeans", "icon": "px:jeans", "stack": 1, "kind": "clothing", "equip": "pants", "cargo": 2, "big": true, "warmth": 7.0, "armour": 0.3,
		"colors": ["blue", "navy", "lightblue", "black", "grey"]},
	"cargo_pants": {"name": "Cargo pants", "icon": "px:cargo_pants", "stack": 1, "kind": "clothing", "equip": "pants", "cargo": 4, "big": true, "warmth": 8.0, "armour": 0.4,
		"colors": ["olive", "tan", "black", "grey", "brown"]},
	"boots": {"name": "Work boots", "icon": "px:boots", "stack": 1, "kind": "clothing", "equip": "boots", "cargo": 0, "big": true, "warmth": 6.0, "armour": 0.3,
		"colors": ["brown", "black", "darkbrown"]},
	"vest": {"name": "Tactical vest", "icon": "px:vest", "stack": 1, "kind": "clothing", "equip": "armour", "cargo": 2, "big": true, "warmth": 4.0, "armour": 3.0,
		"colors": ["olive", "black", "tan"]},
	"scrap_armour": {"name": "Improvised armour", "icon": "px:scrap_armour", "stack": 1, "kind": "clothing", "equip": "armour", "cargo": 0, "big": true, "warmth": 2.0, "armour": 2.2, "repair": "tool"},
	"backpack_small": {"name": "Small backpack", "icon": "px:backpack_small", "stack": 1, "kind": "clothing", "equip": "back", "cargo": 6, "big": true, "warmth": 2.0,
		"colors": ["olive", "black", "blue", "red", "grey", "brown"]},
	"sack_backpack": {"name": "Sack backpack", "icon": "px:sack_backpack", "stack": 1, "kind": "clothing", "equip": "back", "cargo": 4, "big": true, "warmth": 1.0},
	"backpack_large": {"name": "Hiking backpack", "icon": "px:backpack_large", "stack": 1, "kind": "clothing", "equip": "back", "cargo": 10, "big": true, "warmth": 3.0,
		"colors": ["brown", "olive", "orange", "blue", "red", "black"]},
}

## Default colours for items without a random colour (matches their icons).
const ICON_DEFAULTS := {"tshirt": "6b7a4a", "jeans": "3b5a8c"}

## Basic colours used for clothing / cans.
const COLORS := {
	"white": "d8d4cc", "black": "2e2a30", "grey": "7a7a80", "red": "a83838", "blue": "3a5a9c",
	"green": "4a7a44", "yellow": "c8a838", "orange": "c8702e", "purple": "6e4a8c", "pink": "c87a98",
	"brown": "6e4a32", "darkbrown": "4a3020", "navy": "2a3e63", "lightblue": "6a8cc0",
	"olive": "5a6438", "tan": "a08a60",
}

const WEAPONS := {
	"fists": {"name": "Fists", "melee": true, "damage": 14.0, "range": 34.0, "cooldown": 0.55, "noise": 90.0, "held": ""},
	"knife": {"name": "Knife", "melee": true, "damage": 22.0, "range": 34.0, "cooldown": 0.38, "noise": 70.0, "wear": 0.8, "held": "icon_knife"},
	"bat": {"name": "Baseball bat", "melee": true, "damage": 34.0, "range": 48.0, "cooldown": 0.75, "noise": 140.0, "wear": 0.6, "held": "item_bat"},
	"spear": {"name": "Wooden spear", "melee": true, "damage": 27.0, "range": 60.0, "cooldown": 0.8, "noise": 100.0, "wear": 1.4, "held": "px:spear"},
	"axe": {"name": "Fire axe", "melee": true, "damage": 48.0, "range": 50.0, "cooldown": 1.0, "noise": 150.0, "wear": 0.5, "held": "sheet:axe_sheet:9:0"},
	"pistol": {"name": "Pistol", "melee": false, "damage": 45.0, "mag": 8, "ammo": "ammo_9mm",
		"cooldown": 0.32, "reload": 1.4, "pellets": 1, "spread": 0.0, "range": 750.0, "noise": 380.0, "wear": 0.25,
		"aim_time": 0.7, "spread_max": 0.45, "spread_min": 0.03, "recoil": 0.14,
		"held": "item_pistol", "bullet_ui": "ui_bullet_pistol"},
	"shotgun": {"name": "Shotgun", "melee": false, "damage": 24.0, "mag": 5, "ammo": "ammo_12ga",
		"cooldown": 0.8, "reload": 2.4, "pellets": 6, "spread": 0.16, "range": 380.0, "noise": 480.0, "wear": 0.4,
		"aim_time": 1.5, "spread_max": 0.6, "spread_min": 0.1, "recoil": 0.35,
		"held": "item_shotgun", "bullet_ui": "ui_bullet_shotgun"},
	"rifle": {"name": "Assault rifle", "melee": false, "damage": 32.0, "mag": 30, "ammo": "ammo_556",
		"cooldown": 0.11, "reload": 2.2, "pellets": 1, "spread": 0.0, "range": 850.0, "noise": 440.0, "wear": 0.08,
		"aim_time": 1.1, "spread_max": 0.5, "spread_min": 0.04, "recoil": 0.06,
		"held": "item_rifle", "bullet_ui": "ui_bullet_rifle"},
	"hunting_rifle": {"name": "Hunting rifle", "melee": false, "damage": 120.0, "mag": 5, "ammo": "ammo_308",
		"cooldown": 1.1, "reload": 2.6, "pellets": 1, "spread": 0.0, "range": 1200.0, "noise": 520.0, "wear": 0.3,
		"aim_time": 2.2, "spread_max": 0.55, "spread_min": 0.008, "recoil": 0.45,
		"held": "icon_hunting_rifle", "bullet_ui": "ui_bullet_rifle"},
}


## How much damage a weapon deals, e.g. "45 damage" or "24 - 144 damage (1 - 6 pellets)".
static func damage_text(id: String) -> String:
	if not WEAPONS.has(id):
		return ""
	var w: Dictionary = WEAPONS[id]
	var dmg := int(w["damage"])
	var pellets := int(w.get("pellets", 1))
	if pellets > 1:
		return "%d - %d damage (1 - %d pellets)" % [dmg, dmg * pellets, pellets]
	return "%d damage" % dmg


const REPAIR_AMOUNT := 40.0


## Which kit repairs it: "tool" (toolbox) for weapons and metal, "sew" (sewing kit) for other clothing, "" = can't.
static func repair_kind(id: String) -> String:
	if is_weapon(id):
		return "tool"
	if is_clothing(id):
		return DEFS[id].get("repair", "sew")
	return ""


## Worn weapons hit a bit softer: 100% at full condition, 75% just before breaking.
static func weapon_factor(it) -> float:
	if it == null or not it.has("cond"):
		return 1.0
	return 0.75 + 0.25 * clampf(float(it["cond"]), 0.0, 100.0) / 100.0


static func def(id: String) -> Dictionary:
	return DEFS[id]


static func name_of(id: String) -> String:
	return DEFS[id]["name"]


## Name including colour, e.g. "T-shirt (red)".
static func display_name(it: Dictionary) -> String:
	var n := name_of(it["id"])
	if it.has("color_name"):
		n += " (%s)" % it["color_name"]
	return n


static func icon_of(icon_spec: String, color := "") -> Texture2D:
	if icon_spec.begins_with("px:"):
		return Game.pixel_icon(icon_spec.substr(3), color)
	if icon_spec.begins_with("sheet:"):
		var p := icon_spec.split(":")
		return Game.sheet_frame(p[1], int(p[2]), int(p[3]))
	return Game.tex(icon_spec)


static func icon(id: String) -> Texture2D:
	return icon_of(DEFS[id]["icon"])


## Icon for a specific item (uses its colour).
static func item_icon(it: Dictionary) -> Texture2D:
	return icon_of(DEFS[it["id"]]["icon"], it.get("color", ""))


static func kind(id: String) -> String:
	return DEFS[id]["kind"]


static func is_weapon(id: String) -> bool:
	return DEFS[id]["kind"] == "weapon"


static func is_clothing(id: String) -> bool:
	return DEFS[id]["kind"] == "clothing"


static func is_usable(id: String) -> bool:
	return DEFS[id]["kind"] in ["consumable", "medical"]


## Gear slot the item belongs in ("" if none).
static func equip_of(id: String) -> String:
	return DEFS[id].get("equip", "")


static func is_big(id: String) -> bool:
	return DEFS[id].get("big", false)


static func cargo_of(id: String) -> int:
	return DEFS[id].get("cargo", 0)


static func armour_of(id: String) -> float:
	return DEFS[id].get("armour", 0.0)


static func warmth_of(id: String) -> float:
	return DEFS[id].get("warmth", 0.0)


static func is_ruined(it: Dictionary) -> bool:
	return it.has("cond") and float(it["cond"]) <= 0.0


## Worn-down clothing keeps most of its value: 100% at full condition, 60% just before ruined, 0 when ruined.
static func cond_factor(it: Dictionary) -> float:
	if not it.has("cond"):
		return 1.0
	var c := float(it["cond"])
	return 0.0 if c <= 0.0 else 0.6 + 0.4 * c / 100.0


static func max_stack(id: String) -> int:
	return DEFS[id]["stack"]


## Two stacks can merge only if they're the same item (and same colour).
static func can_stack(a: Dictionary, b: Dictionary) -> bool:
	return a["id"] == b["id"] and max_stack(a["id"]) > 1 and a.get("color", "") == b.get("color", "")


## Returns a new item, e.g. {"id": "pistol", "count": 1, "mag": 3} or
## {"id": "jeans", "count": 1, "cond": 100, "cargo": [null, null], "color": "3a5a9c", "color_name": "blue"}
static func make(id: String, count := 1) -> Dictionary:
	var it := {"id": id, "count": count}
	if WEAPONS.has(id) and not WEAPONS[id]["melee"]:
		it["mag"] = randi_range(0, int(WEAPONS[id]["mag"]) / 2)
	if is_weapon(id):
		it["cond"] = 100.0
	if DEFS[id].has("uses"):
		it["uses"] = int(DEFS[id]["uses"])
	if DEFS[id].has("capacity"):
		it["water"] = 0
	if is_clothing(id):
		it["cond"] = 100.0
		var c := []
		c.resize(cargo_of(id))
		it["cargo"] = c
	if DEFS[id].has("colors"):
		var cols: Array = DEFS[id]["colors"]
		var cn: String = cols[randi() % cols.size()]
		it["color_name"] = cn
		it["color"] = COLORS[cn]
	return it


## Found items have been used: clothing and weapons 35-100% condition, repair kits partly used.
static func used(it: Dictionary, lo := 35.0, hi := 100.0) -> Dictionary:
	if it.has("cond"):
		it["cond"] = float(roundi(randf_range(lo, hi)))
	if it.has("uses"):
		it["uses"] = randi_range(maxi(1, int(it["uses"]) - 3), int(it["uses"]))
	return it


## Rolls items from a weighted table: [[id, weight, min, max], ...]. `rolls` = [min, max] attempts.
static func roll(table: Array, rolls: Vector2i, empty_chance := 0.15) -> Array:
	var out := []
	var total := 0
	for row in table:
		total += int(row[1])
	for i in randi_range(rolls.x, rolls.y):
		if randf() < empty_chance:
			continue
		var r := randi() % total
		for row in table:
			r -= int(row[1])
			if r < 0:
				out.append(used(make(row[0], randi_range(row[2], row[3]))))
				break
	return out
