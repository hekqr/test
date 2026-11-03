class_name LootSpot
extends Node2D
## A searchable container (cabinet / fridge / crate) inside buildings.

const KINDS := ["loot_box_1", "loot_box_2", "loot_trash_1", "loot_trash_2"]

var looted := false
var kind := 0
var _sprite: Sprite2D


func _ready() -> void:
	add_to_group("loot")
	kind = randi() % KINDS.size()
	_sprite = Game.make_sprite(KINDS[kind])
	_sprite.offset = Vector2(0, -_sprite.texture.get_height() / 2.0 + 3.0)
	add_child(_sprite)


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
	draw_set_transform(Vector2(0, 5), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 12.0, Color(0, 0, 0, 0.35))
	draw_set_transform(Vector2.ZERO)
	if _sprite:
		_sprite.modulate = Color(0.45, 0.42, 0.45) if looted else Color.WHITE
	if not looted:
		# small glint so searchable containers stand out
		var t := Time.get_ticks_msec() / 400.0 + position.x
		if fmod(t, 6.0) < 0.6:
			draw_circle(Vector2(6, -16), 2.0, Color(1, 0.95, 0.6, 0.9))


func _process(_delta: float) -> void:
	if not looted:
		queue_redraw()
