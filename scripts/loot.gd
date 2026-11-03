class_name Loot
## Where loot comes from. Every container type has its own table, so loot isn't equal everywhere:
## police lockers have guns, kitchens have food, wardrobes have clothes, cars give one item, etc.
## Rows: [item id, weight, min count, max count]

const CONTAINERS := {
	# --- houses
	"fridge": {"name": "Fridge", "sprite": "prop_fridge", "rolls": Vector2i(1, 3), "empty": 0.25, "table": [
		["water", 6, 1, 1], ["soda", 6, 1, 1], ["meat", 4, 1, 1], ["soup", 2, 1, 1], ["food", 2, 1, 1]]},
	"cupboard": {"name": "Kitchen cupboard", "sprite": "px:counter", "rolls": Vector2i(1, 2), "empty": 0.2, "table": [
		["food", 6, 1, 1], ["soup", 5, 1, 1], ["chips_salted", 3, 1, 1], ["chips_cheese", 3, 1, 1], ["water", 2, 1, 1], ["knife", 2, 1, 1]]},
	"wardrobe": {"name": "Wardrobe", "sprite": "px:wardrobe", "rolls": Vector2i(1, 3), "empty": 0.2, "table": [
		["tshirt", 6, 1, 1], ["flannel", 5, 1, 1], ["hoodie", 5, 1, 1], ["jacket", 2, 1, 1], ["jeans", 5, 1, 1],
		["cargo_pants", 3, 1, 1], ["boots", 3, 1, 1], ["cap", 4, 1, 1], ["beanie", 3, 1, 1], ["backpack_small", 2, 1, 1]]},
	"medicine": {"name": "Medicine cabinet", "sprite": "px:medcabinet", "rolls": Vector2i(1, 2), "empty": 0.3, "table": [
		["bandage", 6, 1, 1], ["firstaid", 2, 1, 1]]},
	"washer": {"name": "Washing machine", "sprite": "prop_washer", "rolls": Vector2i(0, 2), "empty": 0.3, "table": [
		["tshirt", 5, 1, 1], ["flannel", 3, 1, 1], ["jeans", 3, 1, 1], ["hoodie", 2, 1, 1], ["beanie", 1, 1, 1]]},
	"desk": {"name": "Desk", "sprite": "px:desk", "rolls": Vector2i(0, 2), "empty": 0.35, "table": [
		["ammo_9mm", 3, 3, 8], ["bandage", 3, 1, 1], ["chips_salted", 2, 1, 1], ["knife", 2, 1, 1], ["pistol", 1, 1, 1], ["cap", 2, 1, 1]]},
	"box": {"name": "Cardboard box", "sprite": "loot_box_1", "rolls": Vector2i(1, 2), "empty": 0.3, "table": [
		["food", 3, 1, 1], ["water", 3, 1, 1], ["bandage", 2, 1, 1], ["tshirt", 2, 1, 1], ["cap", 1, 1, 1],
		["ammo_9mm", 1, 2, 6], ["bat", 1, 1, 1], ["backpack_small", 1, 1, 1]]},
	"trash": {"name": "Trash can", "sprite": "loot_trash_1", "rolls": Vector2i(0, 1), "empty": 0.5, "table": [
		["chips_salted", 3, 1, 1], ["soda", 3, 1, 1], ["tshirt", 2, 1, 1], ["bandage", 1, 1, 1], ["meat", 1, 1, 1]]},

	# --- shops
	"shelf": {"name": "Shop shelf", "sprite": "px:shelf", "rolls": Vector2i(1, 3), "empty": 0.2, "table": [
		["food", 5, 1, 1], ["soup", 4, 1, 1], ["chips_salted", 4, 1, 1], ["chips_cheese", 4, 1, 1], ["water", 5, 1, 1],
		["soda", 5, 1, 1], ["bandage", 1, 1, 1]]},
	"vending": {"name": "Vending machine", "sprite": "prop_vending_red", "rolls": Vector2i(1, 2), "empty": 0.2, "table": [
		["soda", 6, 1, 1], ["chips_salted", 3, 1, 1], ["chips_cheese", 3, 1, 1], ["water", 2, 1, 1]]},
	"pharmacy": {"name": "Pharmacy shelf", "sprite": "px:shelf_white", "rolls": Vector2i(1, 3), "empty": 0.15, "table": [
		["bandage", 6, 1, 1], ["firstaid", 4, 1, 1], ["water", 2, 1, 1]]},

	# --- police / military
	"locker": {"name": "Police locker", "sprite": "px:locker", "rolls": Vector2i(1, 3), "empty": 0.15, "table": [
		["pistol", 4, 1, 1], ["ammo_9mm", 6, 6, 16], ["shotgun", 2, 1, 1], ["ammo_12ga", 4, 4, 10],
		["rifle", 1, 1, 1], ["ammo_556", 2, 10, 25], ["vest", 2, 1, 1], ["helmet", 2, 1, 1], ["boots", 2, 1, 1],
		["bandage", 2, 1, 1], ["firstaid", 1, 1, 1]]},

	# --- garages / workshops
	"crate": {"name": "Tool crate", "sprite": "prop_pallet_1", "rolls": Vector2i(1, 2), "empty": 0.25, "table": [
		["bat", 4, 1, 1], ["axe", 3, 1, 1], ["knife", 3, 1, 1], ["hunting_rifle", 1, 1, 1], ["ammo_308", 2, 2, 6],
		["boots", 3, 1, 1], ["cargo_pants", 2, 1, 1], ["cap", 2, 1, 1], ["water", 2, 1, 1], ["backpack_large", 1, 1, 1]]},

	# --- outside
	"bin": {"name": "Garbage bin", "sprite": "prop_bin_1", "rolls": Vector2i(0, 2), "empty": 0.45, "table": [
		["chips_salted", 3, 1, 1], ["chips_cheese", 2, 1, 1], ["soda", 3, 1, 1], ["tshirt", 2, 1, 1], ["meat", 1, 1, 1],
		["bandage", 1, 1, 1], ["cap", 1, 1, 1]]},
	# Cars give at most one item.
	"car": {"name": "Car", "sprite": "", "rolls": Vector2i(1, 1), "empty": 0.35, "table": [
		["water", 5, 1, 1], ["soda", 4, 1, 1], ["chips_salted", 3, 1, 1], ["bandage", 3, 1, 1], ["firstaid", 1, 1, 1],
		["ammo_9mm", 3, 3, 10], ["ammo_12ga", 1, 2, 6], ["pistol", 1, 1, 1], ["bat", 2, 1, 1], ["cap", 2, 1, 1],
		["jacket", 1, 1, 1], ["backpack_small", 1, 1, 1]]},
	# Rare finds in the woods.
	"wild": {"name": "Ground", "sprite": "", "rolls": Vector2i(1, 1), "empty": 0.0, "table": [
		["water", 3, 1, 1], ["meat", 2, 1, 1], ["knife", 2, 1, 1], ["axe", 1, 1, 1], ["hunting_rifle", 1, 1, 1],
		["ammo_308", 2, 2, 5], ["beanie", 2, 1, 1], ["boots", 1, 1, 1], ["backpack_large", 1, 1, 1]]},
	# Loose items on house floors.
	"floor": {"name": "Ground", "sprite": "", "rolls": Vector2i(1, 1), "empty": 0.0, "table": [
		["food", 4, 1, 1], ["water", 4, 1, 1], ["soda", 3, 1, 1], ["chips_salted", 2, 1, 1], ["bandage", 3, 1, 1],
		["tshirt", 2, 1, 1], ["cap", 2, 1, 1], ["ammo_9mm", 2, 2, 6], ["knife", 1, 1, 1]]},
}


static func title(kind: String) -> String:
	return CONTAINERS[kind]["name"]


static func roll(kind: String) -> Array:
	var c: Dictionary = CONTAINERS[kind]
	return Items.roll(c["table"], c["rolls"], c["empty"])
