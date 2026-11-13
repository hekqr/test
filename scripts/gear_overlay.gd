class_name GearOverlay
extends Node2D
## Draws worn gear on top of a character sprite (player and bandits): hat details (cap brim, beanie
## band and pom-pom, helmet rim and chin strap), body armour over the chest, and the backpack.
## The outfit shader already recolours hair / shirt / coat; this adds the shapes.
## Positions follow the animation: each frame's head and chest are found once from its pixels.

var sprite: AnimatedSprite2D
var gear: Dictionary = {}
var facing := Vector2.DOWN
var dead := false

const OUTLINE := Color("1a1016")
const PX := 2.0 # one sprite pixel on screen (the sprite is drawn at 2x)

static var _cache := {} # texture instance id -> {"top", "l", "r", "body_l", "body_r", "body_t", "body_b", "w", "h"}

## Shirt / coat / zipper source colours in the character sheet (see outfit.gdshader).
const BODY_COLS := [Color("43735b"), Color("404351"), Color("728591"), Color("9eafad")]


func _process(_d: float) -> void:
	queue_redraw()


static func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) < 0.08


## Head and chest boxes of one animation frame, in sprite pixels.
static func frame_info(tex: Texture2D) -> Dictionary:
	var id := tex.get_instance_id()
	if _cache.has(id):
		return _cache[id]
	var img := tex.get_image()
	var info := {"top": 0, "l": 2, "r": 10, "body_l": 3, "body_r": 9, "body_t": 10, "body_b": 13, "w": 13, "h": 16}
	if img != null:
		if img.is_compressed():
			img.decompress()
		var w := img.get_width()
		var h := img.get_height()
		info["w"] = w
		info["h"] = h
		var top := -1
		for y in h:
			for x in w:
				if img.get_pixel(x, y).a > 0.5:
					top = y
					break
			if top >= 0:
				break
		top = maxi(top, 0)
		# Head width: the widest of the first rows of hair
		var l := w
		var r := -1
		for y in range(top, mini(top + 5, h)):
			for x in w:
				if img.get_pixel(x, y).a > 0.5:
					l = mini(l, x)
					r = maxi(r, x)
		# Chest: where the shirt / coat colours are
		var bl := w
		var br := -1
		var bt := h
		var bb := -1
		for y in h:
			for x in w:
				var c := img.get_pixel(x, y)
				if c.a < 0.5:
					continue
				for bc in BODY_COLS:
					if _near(c, bc):
						bl = mini(bl, x)
						br = maxi(br, x)
						bt = mini(bt, y)
						bb = maxi(bb, y)
						break
		info["top"] = top
		if r >= l:
			info["l"] = l
			info["r"] = r
		if br >= bl:
			info["body_l"] = bl
			info["body_r"] = br
			info["body_t"] = bt
			info["body_b"] = bb
	_cache[id] = info
	return info


## A rectangle given in sprite pixels -> local coordinates.
func _rect(info: Dictionary, x: float, y: float, w: float, h: float) -> Rect2:
	var o := sprite.offset
	var ox := -float(info["w"]) * 0.5 + o.x
	var oy := -float(info["h"]) * 0.5 + o.y
	return Rect2((ox + x) * PX, (oy + y) * PX, w * PX, h * PX)


func _box(r: Rect2, col: Color) -> void:
	draw_rect(r, col)


func _col(slot: String) -> Variant:
	return Player.cloth_color(gear, slot)


func _draw() -> void:
	if sprite == null or dead or not sprite.visible:
		return
	var frames := sprite.sprite_frames
	if frames == null or not frames.has_animation(sprite.animation):
		return
	var tex := frames.get_frame_texture(sprite.animation, sprite.frame)
	if tex == null:
		return
	var info := frame_info(tex)
	var d := Game.dir_name(facing)
	if sprite.animation.begins_with("death"):
		return
	_draw_armour(info, d)
	_draw_pack(info, d)
	_draw_head(info, d)


func _draw_armour(info: Dictionary, d: String) -> void:
	var a = gear.get("armour")
	if a == null:
		return
	var c: Color = _col("armour")
	var l: int = info["body_l"]
	var r: int = info["body_r"]
	var t: int = info["body_t"]
	var b: int = info["body_b"]
	# Keep the arms out: armour covers the middle of the chest
	var inset := 1 if d in ["down", "up"] else 0
	var x0 := l + inset + 1
	var x1 := r - inset - 1
	if x1 < x0:
		return
	var rect := _rect(info, x0, t, x1 - x0 + 1, maxi(b - t, 2))
	draw_rect(rect.grow(1.0), OUTLINE)
	draw_rect(rect, c)
	if String(a["id"]) == "scrap_armour":
		# Bolted plates
		draw_rect(Rect2(rect.position.x, rect.position.y + rect.size.y * 0.5 - 1.0, rect.size.x, 1.0), c.darkened(0.4))
		draw_rect(Rect2(rect.position + Vector2(1, 1), Vector2(1, 1)), c.lightened(0.5))
		draw_rect(Rect2(rect.end - Vector2(2, 2), Vector2(1, 1)), c.lightened(0.5))
	else:
		# Tactical vest: pouches across the front, straps at the back
		if d == "up":
			draw_rect(Rect2(rect.position.x + rect.size.x * 0.5 - 1.0, rect.position.y, 2.0, rect.size.y), c.darkened(0.35))
		else:
			var pw := maxf(rect.size.x / 3.0 - 1.0, 1.0)
			for i in 3:
				draw_rect(Rect2(rect.position.x + 0.5 + i * (pw + 1.0), rect.end.y - 3.0, pw, 2.5), c.darkened(0.3))
			draw_rect(Rect2(rect.position.x, rect.position.y, rect.size.x, 1.0), c.lightened(0.2))


func _draw_pack(info: Dictionary, d: String) -> void:
	var col = _col("back")
	if col == null:
		return
	var c: Color = col
	var l: int = info["body_l"]
	var r: int = info["body_r"]
	var t: int = info["body_t"] - 1
	var b: int = info["body_b"]
	var rect: Rect2
	match d:
		"up":
			rect = _rect(info, l + 1, t, r - l - 1, b - t + 1)
		"side":
			rect = _rect(info, l - 2, t, 3, b - t)
		"side-left":
			rect = _rect(info, r, t, 3, b - t)
		_:
			# Facing the camera: shoulder straps only
			var s1 := _rect(info, l + 1, info["body_t"], 1, 2)
			var s2 := _rect(info, r - 1, info["body_t"], 1, 2)
			draw_rect(s1, c.darkened(0.2))
			draw_rect(s2, c.darkened(0.2))
			return
	draw_rect(rect.grow(1.0), OUTLINE)
	draw_rect(rect, c)
	draw_rect(Rect2(rect.position.x, rect.position.y + rect.size.y * 0.45, rect.size.x, 2), c.darkened(0.3))


func _draw_head(info: Dictionary, d: String) -> void:
	var h = gear.get("head")
	if h == null:
		return
	var c: Color = _col("head")
	var id := String(h["id"])
	var top: int = info["top"]
	var l: int = info["l"]
	var r: int = info["r"]
	var w := r - l + 1
	var cx := (l + r) * 0.5
	match id:
		"cap":
			# Brim sticking out in front
			var brim := c.darkened(0.3)
			match d:
				"down":
					draw_rect(_rect(info, l + 1, top + 3, w - 2, 1), brim)
				"side":
					draw_rect(_rect(info, r - 1, top + 3, 3, 1).grow(0.5), OUTLINE)
					draw_rect(_rect(info, r - 1, top + 3, 3, 1), brim)
				"side-left":
					draw_rect(_rect(info, l - 2, top + 3, 3, 1).grow(0.5), OUTLINE)
					draw_rect(_rect(info, l - 2, top + 3, 3, 1), brim)
				"up":
					draw_rect(_rect(info, cx - 1, top + 3, 2, 1), c.lightened(0.4)) # strap
		"beanie":
			# Folded band and a pom-pom
			draw_rect(_rect(info, l, top + 3, w, 1), c.lightened(0.25))
			draw_rect(_rect(info, cx - 1, top - 1, 2, 1).grow(0.5), OUTLINE)
			draw_rect(_rect(info, cx - 1, top - 1, 2, 1), c.lightened(0.45))
		"helmet":
			# Rim wider than the head, highlight on the dome, chin strap
			var rim := c.darkened(0.35)
			draw_rect(_rect(info, l, top + 3, w, 1), rim)
			draw_rect(_rect(info, cx - 2, top + 1, 2, 1), c.lightened(0.3))
			if d == "down":
				draw_rect(_rect(info, l + 1, top + 4, 1, 4), rim)
				draw_rect(_rect(info, r - 1, top + 4, 1, 4), rim)
			elif d == "side":
				draw_rect(_rect(info, l + 3, top + 4, 1, 4), rim)
			elif d == "side-left":
				draw_rect(_rect(info, r - 3, top + 4, 1, 4), rim)
