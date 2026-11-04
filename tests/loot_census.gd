extends Node
## Dev tool: counts the food / drink lying around in a fresh world.
## godot --headless --path . res://tests/loot_census.tscn

var main: Node
var frame := 0


func _ready() -> void:
	Game.save_path = "user://census_save.json"
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)


func _process(_delta: float) -> void:
	frame += 1
	if frame != 3:
		return
	var hunger := 0.0
	var thirst := 0.0
	var by_kind := {}
	for n in get_tree().get_nodes_in_group("loot"):
		var l := n as LootSpot
		for it in l.contents:
			var d := Items.def(it["id"])
			if Items.kind(it["id"]) != "consumable":
				continue
			var k := l.kind
			by_kind[k] = by_kind.get(k, 0) + int(it["count"])
			hunger += maxf(float(d.get("hunger", 0.0)), 0.0) * int(it["count"])
			thirst += maxf(float(d.get("thirst", 0.0)), 0.0) * int(it["count"])
	print("buildings %d, settlements %d" % [main.world.buildings.size(), main.world.settlements.size()])
	print("food/drink items by container: ", by_kind)
	print("total hunger points %d (= %.0f min of hunger), thirst points %d (= %.0f min of thirst)" % [hunger, hunger / 100.0 * 15.0, thirst, thirst / 100.0 * 10.0])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path))
	get_tree().quit()
