class_name LootSpot
extends Node2D
## A searchable container (cabinet / fridge / crate) inside buildings.

const COLORS := [Color(0.52, 0.36, 0.20), Color(0.75, 0.78, 0.80), Color(0.40, 0.32, 0.22)]

var looted := false
var kind := 0


func _ready() -> void:
	add_to_group("loot")
	kind = randi() % COLORS.size()


func search(p: Player) -> String:
	if looted:
		return "Already searched"
	looted = true
	queue_redraw()
	var found := PackedStringArray()
	for i in randi_range(1, 2):
		var r := randf()
		if r < 0.15:
			continue
		elif r < 0.38:
			p.inventory["food"] += 1
			found.append("food")
		elif r < 0.60:
			p.inventory["water"] += 1
			found.append("water")
		elif r < 0.75:
			p.inventory["bandage"] += 1
			found.append("bandage")
		elif r < 0.96 or p.has_pistol:
			var n := randi_range(4, 10)
			p.inventory["ammo"] += n
			found.append("%d ammo" % n)
		else:
			p.has_pistol = true
			p.mag = 4
			found.append("PISTOL (press 2)")
	if found.is_empty():
		return "Nothing useful here"
	return "Found: " + ", ".join(found)


func _draw() -> void:
	var c: Color = COLORS[kind]
	if looted:
		c = c.darkened(0.55)
	draw_rect(Rect2(-11, -8, 22, 16), Color(0, 0, 0, 0.35))
	draw_rect(Rect2(-10, -9, 20, 16), c)
	draw_rect(Rect2(-10, -9, 20, 16), c.darkened(0.4), false, 1.5)
	if not looted:
		draw_circle(Vector2(0, -1), 2.0, Color(1, 0.9, 0.4))
