class_name Loot
## Where loot comes from. Every container type has its own table, so loot isn't equal everywhere:
## police lockers have guns, fridges have food, wardrobes have clothes, cars give one item, etc.
## In houses only fridges, wardrobes, medicine cabinets and trash cans can be searched.
## (cupboard / washer / desk / box tables are kept for old saves but no longer placed.)
## Rows: [item id, weight, min count, max count]. For ammo the counts are MAGAZINES of the gun that uses it
## (9mm: 8 rounds, 12ga: 5, 5.56: 30, .308: 5) - you never find a handful of loose rounds.

const CONTAINERS := {
	# --- houses
	"fridge": {"name": "Fridge", "sprite": "prop_fridge", "rolls": Vector2i(1, 3), "empty": 0.3, "table": [
		["water", 6, 1, 1], ["soda", 5, 1, 1], ["meat", 4, 1, 1], ["soup", 3, 1, 1], ["food", 3, 1, 1],
		["tomato", 2, 1, 2], ["potato", 2, 1, 3]]},
	"cupboard": {"name": "Kitchen cupboard", "sprite": "px:counter", "rolls": Vector2i(0, 2), "empty": 0.45, "table": [
		["food", 6, 1, 1], ["soup", 5, 1, 1], ["chips_salted", 3, 1, 1], ["chips_cheese", 3, 1, 1], ["water", 2, 1, 1], ["knife", 2, 1, 1], ["matches", 3, 2, 6]]},
	"wardrobe": {"name": "Wardrobe", "sprite": "px:wardrobe", "rolls": Vector2i(1, 3), "empty": 0.3, "table": [["rags", 2, 1, 3], ["sack", 1, 1, 1], 
		["tshirt", 6, 1, 1], ["flannel", 5, 1, 1], ["hoodie", 5, 1, 1], ["jacket", 2, 1, 1], ["jeans", 5, 1, 1],
		["cargo_pants", 3, 1, 1], ["boots", 3, 1, 1], ["cap", 4, 1, 1], ["beanie", 3, 1, 1], ["backpack_small", 2, 1, 1], ["sewing_kit", 2, 1, 1]]},
	"medicine": {"name": "Medicine cabinet", "sprite": "px:medcabinet", "rolls": Vector2i(0, 1), "empty": 0.5, "table": [
		["bandage", 6, 1, 1], ["firstaid", 2, 1, 1]]},
	"washer": {"name": "Washing machine", "sprite": "prop_washer", "rolls": Vector2i(0, 1), "empty": 0.5, "table": [
		["tshirt", 5, 1, 1], ["flannel", 3, 1, 1], ["jeans", 3, 1, 1], ["hoodie", 2, 1, 1], ["beanie", 1, 1, 1]]},
	"desk": {"name": "Desk", "sprite": "px:desk", "rolls": Vector2i(0, 1), "empty": 0.45, "table": [["map", 2, 1, 1], 
		["ammo_9mm", 3, 1, 2], ["bandage", 3, 1, 1], ["chips_salted", 2, 1, 1], ["knife", 2, 1, 1], ["pistol", 1, 1, 1], ["cap", 2, 1, 1], ["matches", 2, 2, 5], ["sewing_kit", 1, 1, 1]]},
	"box": {"name": "Cardboard box", "sprite": "loot_box_1", "rolls": Vector2i(0, 2), "empty": 0.5, "table": [["sack", 2, 1, 1], ["rags", 2, 1, 3], ["scrap_metal", 1, 1, 2], ["sewing_kit", 1, 1, 1], 
		["food", 3, 1, 1], ["water", 3, 1, 1], ["bandage", 2, 1, 1], ["tshirt", 2, 1, 1], ["cap", 1, 1, 1],
		["ammo_9mm", 1, 1, 1], ["bat", 1, 1, 1], ["backpack_small", 1, 1, 1]]},
	"trash": {"name": "Trash can", "sprite": "loot_trash_1", "rolls": Vector2i(0, 1), "empty": 0.55, "table": [["rags", 3, 1, 2], ["scrap_metal", 1, 1, 1], ["matches", 2, 1, 3], ["sack", 1, 1, 1], ["nails", 1, 2, 6], 
		["chips_salted", 3, 1, 1], ["soda", 3, 1, 1], ["tshirt", 2, 1, 1], ["bandage", 1, 1, 1], ["meat", 1, 1, 1]]},

	# --- shops
	"shelf": {"name": "Shop shelf", "sprite": "px:shelf", "rolls": Vector2i(0, 1), "empty": 0.5, "table": [["map", 1, 1, 1], ["matches", 1, 1, 4], ["tomato_seeds", 1, 1, 2], ["potato", 1, 1, 2], 
		["food", 5, 1, 1], ["soup", 4, 1, 1], ["chips_salted", 4, 1, 1], ["chips_cheese", 4, 1, 1], ["water", 5, 1, 1],
		["soda", 5, 1, 1], ["bandage", 1, 1, 1]]},
	"vending": {"name": "Vending machine", "sprite": "prop_vending_red", "rolls": Vector2i(0, 1), "empty": 0.4, "table": [
		["soda", 6, 1, 1], ["chips_salted", 3, 1, 1], ["chips_cheese", 3, 1, 1], ["water", 2, 1, 1]]},
	"pharmacy": {"name": "Pharmacy shelf", "sprite": "px:shelf_white", "rolls": Vector2i(0, 2), "empty": 0.35, "table": [
		["bandage", 6, 1, 1], ["firstaid", 4, 1, 1], ["water", 2, 1, 1]]},

	# --- police / military
	"locker": {"name": "Police locker", "sprite": "px:locker", "rolls": Vector2i(0, 2), "empty": 0.35, "table": [["map", 1, 1, 1], ["rope", 1, 1, 1], ["toolbox", 1, 1, 1], 
		["pistol", 4, 1, 1], ["ammo_9mm", 6, 1, 3], ["shotgun", 2, 1, 1], ["ammo_12ga", 4, 1, 3],
		["rifle", 1, 1, 1], ["ammo_556", 2, 1, 2], ["vest", 2, 1, 1], ["helmet", 2, 1, 1], ["boots", 2, 1, 1],
		["bandage", 2, 1, 1], ["firstaid", 1, 1, 1]]},

	# A chest you built (storage; never filled by itself)
	"chest": {"name": "Chest", "sprite": "px:chest", "rolls": Vector2i(0, 0), "empty": 1.0, "table": []},
	"store_shelf": {"name": "Shelves", "sprite": "px:storage_shelf", "rolls": Vector2i(0, 0), "empty": 1.0, "table": []},
	"store_rack": {"name": "Weapon rack", "sprite": "px:weapon_rack", "rolls": Vector2i(0, 0), "empty": 1.0, "table": []},

	# --- military camps: plenty of supplies, guns, and 2-4 magazines of ammo
	"military": {"name": "Military crate", "sprite": "px:milcrate", "rolls": Vector2i(1, 3), "empty": 0.15, "table": [
		["pistol", 3, 1, 1], ["rifle", 4, 1, 1], ["shotgun", 2, 1, 1], ["hunting_rifle", 2, 1, 1],
		["ammo_9mm", 4, 2, 4], ["ammo_556", 5, 2, 4], ["ammo_12ga", 3, 2, 4], ["ammo_308", 3, 2, 4],
		["vest", 3, 1, 1], ["helmet", 3, 1, 1], ["cargo_pants", 2, 1, 1], ["boots", 2, 1, 1], ["backpack_large", 2, 1, 1],
		["food", 6, 1, 3], ["water", 6, 1, 3], ["bandage", 4, 1, 3], ["firstaid", 3, 1, 1], ["map", 1, 1, 1],
		["toolbox", 1, 1, 1], ["matches", 2, 2, 6], ["nails", 1, 10, 20], ["planks", 1, 2, 4]]},

	# --- garages / workshops
	"crate": {"name": "Tool crate", "sprite": "prop_pallet_1", "rolls": Vector2i(0, 2), "empty": 0.45, "table": [["sack", 3, 1, 1], ["rope", 3, 1, 1], ["map", 1, 1, 1], ["scrap_metal", 5, 1, 3], ["toolbox", 3, 1, 1],
		["planks", 4, 2, 4], ["nails", 4, 5, 15], ["tomato_seeds", 2, 1, 2], ["fishing_rod", 1, 1, 1], 
		["bat", 4, 1, 1], ["axe", 3, 1, 1], ["knife", 3, 1, 1], ["hunting_rifle", 1, 1, 1], ["ammo_308", 2, 1, 2],
		["boots", 3, 1, 1], ["cargo_pants", 2, 1, 1], ["cap", 2, 1, 1], ["water", 2, 1, 1], ["backpack_large", 1, 1, 1], ["matches", 2, 2, 6], ["sticks", 2, 2, 5]]},

	# --- outside
	"bin": {"name": "Garbage bin", "sprite": "prop_bin_1", "rolls": Vector2i(0, 1), "empty": 0.6, "table": [["rags", 2, 1, 2], ["sack", 1, 1, 1], ["scrap_metal", 2, 1, 2], 
		["chips_salted", 3, 1, 1], ["chips_cheese", 2, 1, 1], ["soda", 3, 1, 1], ["tshirt", 2, 1, 1], ["meat", 1, 1, 1],
		["bandage", 1, 1, 1], ["cap", 1, 1, 1]]},
	# Cars give at most one item.
	"car": {"name": "Car", "sprite": "", "rolls": Vector2i(1, 1), "empty": 0.55, "table": [["map", 3, 1, 1], ["rope", 1, 1, 1], ["toolbox", 2, 1, 1], ["scrap_metal", 2, 1, 2], ["nails", 1, 3, 8], ["fishing_rod", 1, 1, 1], 
		["water", 5, 1, 1], ["soda", 4, 1, 1], ["chips_salted", 3, 1, 1], ["bandage", 3, 1, 1], ["firstaid", 1, 1, 1],
		["ammo_9mm", 3, 1, 2], ["ammo_12ga", 1, 1, 2], ["pistol", 1, 1, 1], ["bat", 2, 1, 1], ["cap", 2, 1, 1],
		["jacket", 1, 1, 1], ["backpack_small", 1, 1, 1], ["matches", 2, 1, 4]]},
	# A dead animal: skin it with a knife or axe to get its meat.
	"carcass": {"name": "Carcass", "sprite": "", "rolls": Vector2i(0, 0), "empty": 1.0, "table": [["meat", 1, 1, 1]]},
	# Rare finds in the woods.
	"wild": {"name": "Ground", "sprite": "", "rolls": Vector2i(1, 1), "empty": 0.0, "table": [
		["water", 1, 1, 1], ["meat", 1, 1, 1], ["knife", 2, 1, 1], ["axe", 1, 1, 1], ["hunting_rifle", 1, 1, 1],
		["ammo_308", 2, 1, 2], ["beanie", 2, 1, 1], ["boots", 1, 1, 1], ["backpack_large", 1, 1, 1], ["matches", 2, 2, 5]]},
	# Loose items on house floors.
	"floor": {"name": "Ground", "sprite": "", "rolls": Vector2i(1, 1), "empty": 0.0, "table": [
		["food", 4, 1, 1], ["water", 4, 1, 1], ["soda", 3, 1, 1], ["chips_salted", 2, 1, 1], ["bandage", 3, 1, 1],
		["tshirt", 2, 1, 1], ["cap", 2, 1, 1], ["ammo_9mm", 2, 1, 1], ["knife", 1, 1, 1], ["matches", 2, 1, 4]]},
}


## Containers you just open and look into are searched instantly; bins, car trunks, medicine boxes,
## lockers and crates take a second (search_time).
const QUICK_SEARCH := ["fridge", "cupboard", "wardrobe", "shelf", "pharmacy", "desk", "washer", "box"]


static func search_time(kind: String) -> float:
	return 0.0 if kind in QUICK_SEARCH else 1.0


static func title(kind: String) -> String:
	return CONTAINERS[kind]["name"]


static func roll(kind: String) -> Array:
	var c: Dictionary = CONTAINERS[kind]
	return Items.roll(c["table"], c["rolls"], c["empty"])
