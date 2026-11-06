class_name LootSpot
extends Node2D
## Something you can search: furniture (fridge, wardrobe, locker...), a car, a garbage bin,
## or a pile of items on the ground. Containers keep whatever you put in them.
## Ground piles disappear when empty.

var kind := "box" # key in Loot.CONTAINERS, or "pile" for items on the ground
var is_bag := false # true = items lying on the ground
var contents: Array = [] # item stacks
var opened := false # has the player looked inside
var loaded := false # restored from a save: don't roll new contents
var tex_name := "" # sprite override (cars, bins)
var flip := false
var reach := 44.0 # how close the player must be
var animal := "" # for carcasses: "rabbit" / "deer"
var _sprite: Sprite2D
var _outline: Node2D
var _display: Node2D # shelves / weapon rack: what's on them
static var _silhouette: Shader
const STORES := ["chest", "store_shelf", "store_rack"]
## Every loot spot in the world, by 128 px square: finding what's near you looks at a few squares
## instead of all ~2500 spots (that cost a few ms every tenth of a second).
const BUCKET := 128.0
static var _grid := {}
var _bucket := Vector2i(1 << 30, 0)


func _enter_tree() -> void:
	_bucket = Vector2i((global_position / BUCKET).floor())
	if not _grid.has(_bucket):
		_grid[_bucket] = []
	_grid[_bucket].append(self)


func _exit_tree() -> void:
	if _grid.has(_bucket):
		_grid[_bucket].erase(self)
		if _grid[_bucket].is_empty():
			_grid.erase(_bucket)


## Loot spots within `r` px of `pos` (roughly: whole squares; check the distance yourself).
static func around(pos: Vector2, r: float) -> Array:
	var out := []
	var a := Vector2i(((pos - Vector2(r, r)) / BUCKET).floor())
	var b := Vector2i(((pos + Vector2(r, r)) / BUCKET).floor())
	for y in range(a.y, b.y + 1):
		for x in range(a.x, b.x + 1):
			var k := Vector2i(x, y)
			if _grid.has(k):
				out.append_array(_grid[k])
	return out


## Storage you built (chest, shelves, weapon rack): keeps what you put in, never "searched".
static func is_store_kind(k: String) -> bool:
	return k in STORES


func is_store() -> bool:
	return kind in STORES


## Weapon racks only hold weapons and ammo.
static func rack_takes(id: String) -> bool:
	return Items.is_weapon(id) or Items.kind(id) == "ammo"


static func _silhouette_shader() -> Shader:
	if _silhouette == null:
		_silhouette = Shader.new()
		_silhouette.code = "shader_type canvas_item;\nvoid fragment() { COLOR = vec4(1.0, 1.0, 1.0, COLOR.a); }\n"
	return _silhouette


## The item's shape in white, nudged 1.5 px in 8 directions (drawn under the sprite = an outline).
func _draw_outline() -> void:
	if _sprite == null or _sprite.texture == null:
		return
	var t := _sprite.texture
	for d in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1), Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		_outline.draw_set_transform(d * 1.5 + _sprite.offset * _sprite.scale, _sprite.rotation, _sprite.scale * Vector2(-1 if _sprite.flip_h else 1, 1))
		_outline.draw_texture(t, -t.get_size() / 2.0)


## A container counts as "looted" once it's empty.
var looted: bool:
	get:
		return contents.is_empty() and not is_bag


func _ready() -> void:
	add_to_group("loot")
	if is_bag:
		kind = "pile"
	if not loaded:
		if is_bag:
			if contents.is_empty():
				contents = Loot.roll("floor")
				if contents.is_empty():
					contents = [Items.make("food")]
		elif contents.is_empty():
			contents = Loot.roll(kind)
	_sprite = Sprite2D.new()
	if kind == "carcass":
		# A dead animal lying on its side
		_sprite.texture = Game.pixel_icon(animal + "_1")
		_sprite.scale = Vector2(2, 2)
		_sprite.rotation = PI * 0.5 * (-1.0 if flip else 1.0)
		_sprite.modulate = Color(0.85, 0.7, 0.7)
	elif is_bag:
		_sprite.scale = Vector2(1.5, 1.5)
	else:
		var spec := tex_name if tex_name != "" else String(Loot.CONTAINERS[kind]["sprite"])
		if spec != "":
			_sprite.texture = Items.icon_of(spec if spec.begins_with("px:") else spec)
			_sprite.scale = Vector2(2, 2)
			_sprite.flip_h = flip
			# Stand on the bottom of the tile.
			_sprite.offset = Vector2(0, 7.5 - _sprite.texture.get_height() / 2.0)
	if is_bag or (kind != "carcass" and not opened and not is_store()):
		# White outline around items on the ground and unsearched containers, so they're easy to spot
		_outline = Node2D.new()
		var om := ShaderMaterial.new()
		om.shader = _silhouette_shader()
		_outline.material = om
		_outline.draw.connect(_draw_outline)
		add_child(_outline)
	add_child(_sprite)
	if kind == "store_shelf" or kind == "store_rack":
		_display = Node2D.new()
		_display.draw.connect(_draw_display)
		add_child(_display)
	set_process(false)
	refresh()


## Shelves show the first 6 things on them, a weapon rack its first 3 weapons.
func _draw_display() -> void:
	var slots: Array = []
	if kind == "store_shelf":
		for row in 2:
			for c in 3:
				slots.append(Rect2(-13 + c * 9, -13 + row * 14, 8, 8))
	else:
		for y in [-14, -4, 6]:
			slots.append(Rect2(-10, y, 20, 7))
	for i in mini(contents.size(), slots.size()):
		var tex := Items.item_icon(contents[i])
		var r: Rect2 = slots[i]
		var k := minf(r.size.x / tex.get_width(), r.size.y / tex.get_height())
		var sz := tex.get_size() * k
		_display.draw_texture_rect(tex, Rect2(r.get_center() - sz / 2.0, sz), false)


## Call after contents change.
func refresh() -> void:
	if kind == "carcass" and contents.is_empty():
		remove_from_group("loot")
		queue_free()
		return
	if is_bag:
		if contents.is_empty():
			remove_from_group("loot")
			queue_free()
			return
		# Items on the ground show the icon of the first item.
		if _sprite:
			_sprite.texture = Items.item_icon(contents[0])
			# Same size on the ground whether it's a small pack icon or a bigger drawn one
			var m := maxf(_sprite.texture.get_width(), _sprite.texture.get_height())
			_sprite.scale = Vector2.ONE * clampf(22.0 / m, 0.6, 1.5)
		if _outline:
			_outline.queue_redraw()
	if _display:
		_display.queue_redraw()
	queue_redraw()


func title() -> String:
	return "Ground" if is_bag else Loot.title(kind)


## Only what differs from the defaults (saves stay small and quick to write).
func to_save() -> Dictionary:
	var d := {"pos": [roundf(position.x * 10.0) / 10.0, roundf(position.y * 10.0) / 10.0], "bag": is_bag, "kind": kind, "contents": contents}
	if opened:
		d["opened"] = true
	if tex_name != "":
		d["tex"] = tex_name
	if flip:
		d["flip"] = true
	if reach != 44.0:
		d["reach"] = reach
	if animal != "":
		d["animal"] = animal
	return d


static func from_save(d: Dictionary) -> LootSpot:
	var l := LootSpot.new()
	l.loaded = true
	l.position = SaveGame.vec(d["pos"])
	l.is_bag = d["bag"]
	l.kind = String(d["kind"])
	l.opened = d.get("opened", false)
	l.tex_name = d.get("tex", "")
	l.flip = d.get("flip", false)
	l.reach = d.get("reach", 44.0)
	l.animal = d.get("animal", "")
	for it in d["contents"]:
		l.contents.append(SaveGame.fix_item(it))
	return l


func label() -> String:
	if is_store():
		return "Open " + title().to_lower()
	if kind == "carcass":
		return "Skin " + animal
	if is_bag and not contents.is_empty():
		var it: Dictionary = contents[0]
		var n := Items.display_name(it)
		if contents.size() > 1:
			n += " +%d" % (contents.size() - 1)
		elif int(it["count"]) > 1:
			n += " x%d" % it["count"]
		return "Pick up " + n
	if opened and contents.is_empty():
		return title() + " (searched)"
	return "Search " + title().to_lower()


## Takes everything that fits (Take all / picking up a ground pile).
func search(p: Player) -> String:
	opened = true
	var found := PackedStringArray()
	var left := []
	for it in contents:
		var before: int = it["count"]
		var rest := p.inv.pickup(it)
		var took := before - rest
		if took > 0:
			found.append(Items.display_name(it) + ("" if took == 1 else " x%d" % took))
		if rest > 0:
			var r: Dictionary = it.duplicate(true)
			r["count"] = rest
			left.append(r)
	var had_items := not contents.is_empty()
	contents = left
	refresh()
	var verb := "Picked up: " if is_bag else "Took: "
	var msg := "Nothing here" if not had_items else (verb + ", ".join(found) if not found.is_empty() else "")
	if not left.is_empty():
		msg = (msg + "  -  " if msg != "" else "") + "No free slots!"
	return msg


## Searching a container (or skinning a carcass): what's inside drops on the ground in front of it,
## as a pile you can pick up. Returns what was found.
func spill(p: Player) -> String:
	opened = true
	if contents.is_empty():
		queue_redraw()
		return "Nothing here" if kind != "carcass" else "Nothing left"
	var names := PackedStringArray()
	for it in contents:
		names.append(Items.display_name(it) + ("" if int(it["count"]) == 1 else " x%d" % it["count"]))
	var toward := (p.global_position - global_position)
	var at := global_position + (toward.normalized() * minf(toward.length(), 22.0) if toward.length() > 1.0 else Vector2(0, 18))
	var pile: LootSpot = null
	for n in LootSpot.around(at, 40.0):
		var l := n as LootSpot
		if l != self and l.is_in_group("loot") and l.is_bag and not l.is_queued_for_deletion() and l.global_position.distance_to(at) < 26.0:
			pile = l
			break
	if pile == null:
		pile = LootSpot.new()
		pile.is_bag = true
		pile.loaded = true
		pile.position = at
		pile.contents = contents.duplicate()
		get_parent().add_child(pile)
	else:
		pile.contents.append_array(contents)
		pile.refresh()
	contents = []
	refresh()
	queue_redraw()
	return "Found: " + ", ".join(names)


func _draw() -> void:
	if kind == "carcass":
		draw_set_transform(Vector2(0, 4), 0.0, Vector2(1.0, 0.5))
		draw_circle(Vector2.ZERO, 16.0 if animal == "deer" else 9.0, Color(0.45, 0.05, 0.08, 0.7))
		draw_set_transform(Vector2.ZERO)
		return
	if is_bag:
		draw_set_transform(Vector2(0, 5), 0.0, Vector2(1.0, 0.4))
		draw_circle(Vector2.ZERO, 10.0, Color(0, 0, 0, 0.3))
		draw_set_transform(Vector2.ZERO)
		return
	if _sprite and _sprite.texture:
		_sprite.modulate = Color(0.6, 0.56, 0.6) if (opened and contents.is_empty()) else Color.WHITE
	if _outline:
		_outline.visible = is_bag or not opened # searched containers lose their outline



