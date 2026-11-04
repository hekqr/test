class_name Crafting
## Crafting recipes. "needs" are used up, "tools" must just be carried (any one of them).
## "station": "workbench" = only at a workbench you built.

const RECIPES := [
	{"id": "bandage", "name": "Bandage", "makes": "bandage", "count": 1, "needs": {"rags": 2}, "tools": []},
	{"id": "rope", "name": "Rope", "makes": "rope", "count": 1, "needs": {"rags": 3}, "tools": []},
	{"id": "sack_backpack", "name": "Sack backpack", "makes": "sack_backpack", "count": 1, "needs": {"sack": 1, "rope": 1}, "tools": []},
	{"id": "spear", "name": "Wooden spear", "makes": "spear", "count": 1, "needs": {"sticks": 3, "rope": 1}, "tools": ["knife", "axe"]},
	{"id": "campfire", "name": "Campfire", "makes": "", "count": 0, "needs": {"sticks": 3, "matches": 1}, "tools": []},
	{"id": "leather_sack", "name": "Sack (leather)", "makes": "sack", "count": 1, "needs": {"leather": 2}, "tools": []},
	{"id": "gourd", "name": "Water gourd", "makes": "gourd", "count": 1, "needs": {"leather": 1}, "tools": []},
	{"id": "fishing_rod", "name": "Fishing rod", "makes": "fishing_rod", "count": 1, "needs": {"sticks": 2, "rope": 1}, "tools": ["knife", "axe"]},
	{"id": "kit_wall", "name": "Wooden wall", "makes": "kit_wall", "count": 1, "needs": {"planks": 3, "nails": 4}, "tools": []},
	{"id": "kit_gate", "name": "Wooden gate", "makes": "kit_gate", "count": 1, "needs": {"planks": 4, "nails": 6, "rope": 1}, "tools": []},
	{"id": "kit_chest", "name": "Chest", "makes": "kit_chest", "count": 1, "needs": {"planks": 4, "nails": 4}, "tools": []},
	{"id": "kit_bed", "name": "Bed", "makes": "kit_bed", "count": 1, "needs": {"planks": 3, "nails": 2, "rags": 3}, "tools": []},
	{"id": "kit_garden", "name": "Garden bed", "makes": "kit_garden", "count": 1, "needs": {"planks": 2, "nails": 2}, "tools": []},
	{"id": "kit_workbench", "name": "Workbench", "makes": "kit_workbench", "count": 1, "needs": {"planks": 6, "nails": 6}, "tools": []},
	{"id": "kit_snare", "name": "Snare", "makes": "kit_snare", "count": 1, "needs": {"sticks": 2, "rope": 1}, "tools": []},
	{"id": "kit_fishtrap", "name": "Fish trap", "makes": "kit_fishtrap", "count": 1, "needs": {"sticks": 4, "rope": 2}, "tools": []},
	{"id": "kit_collector", "name": "Rain collector", "makes": "kit_collector", "count": 1, "needs": {"planks": 4, "nails": 4, "scrap_metal": 1}, "tools": [], "station": "workbench"},
	{"id": "kit_stove", "name": "Stove", "makes": "kit_stove", "count": 1, "needs": {"scrap_metal": 4, "nails": 4}, "tools": [], "station": "workbench"},
	{"id": "kit_shelf", "name": "Shelves", "makes": "kit_shelf", "count": 1, "needs": {"planks": 4, "nails": 4}, "tools": [], "station": "workbench"},
	{"id": "kit_rack", "name": "Weapon rack", "makes": "kit_rack", "count": 1, "needs": {"planks": 3, "nails": 3, "rope": 1}, "tools": [], "station": "workbench"},
	{"id": "scrap_armour", "name": "Improvised armour", "makes": "scrap_armour", "count": 1, "needs": {"scrap_metal": 3, "rope": 2}, "tools": []},
]

## Ideas for later recipes (shown in the docs, not in game yet).
const PLANNED := [
	"Bow (sticks + rope) and arrows (sticks + feathers / scrap)",
	"Splint (sticks + rags) for broken legs",
	"Torch (stick + rags + match) to carry light",
	"Barricade planks (axe + wood) for doors and windows",
	"Boiling dirty water on a campfire",
	"Scrap helmet (scrap metal + rags)",
]


static func get_recipe(id: String) -> Dictionary:
	for r in RECIPES:
		if r["id"] == id:
			return r
	return {}


## "" if the player can craft it, otherwise what's missing.
static func missing(r: Dictionary, inv: Inventory, at_bench := false) -> String:
	var miss := PackedStringArray()
	if r.get("station", "") == "workbench" and not at_bench:
		miss.append("a workbench")
	for item in r["needs"]:
		var have := inv.count_of(item)
		if have < int(r["needs"][item]):
			miss.append("%d %s" % [int(r["needs"][item]) - have, Items.name_of(item).to_lower()])
	if not r["tools"].is_empty():
		var ok := false
		for t in r["tools"]:
			if has_tool(inv, t):
				ok = true
		if not ok:
			miss.append(" or ".join(PackedStringArray(r["tools"])))
	return ", ".join(miss)


static func has_tool(inv: Inventory, id: String) -> bool:
	if inv.count_of(id) > 0:
		return true
	for s in Inventory.WEAPON_SLOTS:
		var g = inv.gear[s]
		if g != null and g["id"] == id:
			return true
	return false
