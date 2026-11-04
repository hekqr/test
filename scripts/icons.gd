class_name Icons
## Higher-resolution (32x32) item icons drawn in code: clothing, soda, meat, matches,
## and the two-colour slot symbols shown in empty inventory slots.
## Shapes are polygons rasterised to pixels, then shaded and outlined.

const SIZE := 32
const OUTLINE := Color("1a1016")

const NAMES := ["tshirt", "flannel", "hoodie", "jacket", "jeans", "cargo_pants", "boots", "vest",
	"helmet", "cap", "beanie", "backpack_small", "backpack_large", "soda", "meat", "cooked_meat", "matches", "water",
	"rags", "rope", "sack", "sack_backpack", "spear", "map", "sewing_kit", "toolbox", "scrap_metal", "scrap_armour", "leather", "gourd",
	"fish", "cooked_fish", "tomato", "potato", "tomato_seeds", "planks", "nails", "fishing_rod",
	"kit_wall", "kit_gate", "kit_chest", "kit_bed", "kit_garden"]

## Default colours for items without a random colour.
const DEFAULT := {
	"tshirt": "6b7a4a", "flannel": "8c3b3b", "hoodie": "5a5f6e", "jacket": "6e4a32", "jeans": "3b5a8c",
	"cargo_pants": "6a6440", "boots": "5a4030", "vest": "4e5434", "helmet": "4e5a3a", "cap": "8a3030",
	"beanie": "3a4a5a", "backpack_small": "5a6a3a", "backpack_large": "6a4a30", "soda": "a83838",
	"meat": "a83a3a", "cooked_meat": "7a4a2a", "matches": "a83838", "water": "7ab8e0",
	"rags": "b8ae98", "rope": "a08458", "sack": "a08a60", "sack_backpack": "8a7450", "spear": "7a5a38", "map": "d8ccaa",
	"leather": "a0703e", "gourd": "7a5030",
	"fish": "7e9aa8", "cooked_fish": "b07a44", "tomato": "c8382e", "potato": "b08a58", "tomato_seeds": "d8c8a0",
	"planks": "a07448", "nails": "9aa0a8", "fishing_rod": "8a6a44",
	"kit_wall": "9a6e44", "kit_gate": "8a6440", "kit_chest": "8a5a34", "kit_bed": "8a6a50", "kit_garden": "6a4a30",
	"sewing_kit": "5a7aa8", "toolbox": "b83a3a", "scrap_metal": "8a8e94", "scrap_armour": "767a80",
}

## Slot symbol shapes (drawn as silhouettes)
const SLOT_SHAPE := {
	"head": "cap", "armour": "vest", "coat": "hoodie", "shirt": "tshirt", "pants": "jeans",
	"boots": "boots", "back": "backpack_small", "hands": "hand", "primary": "rifle",
	"secondary": "pistol", "melee": "knife",
}


static func make(name: String, color := "") -> ImageTexture:
	var base := Color(color if color != "" else DEFAULT.get(name, "7a7a80"))
	var img := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	_draw_item(img, name, base, false)
	_shade(img)
	_outline(img, OUTLINE)
	return ImageTexture.create_from_image(img)


## Two-colour symbol for an empty gear slot.
static func slot_symbol(slot: String, fill: Color, line: Color) -> ImageTexture:
	var img := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	_draw_item(img, SLOT_SHAPE[slot], fill, true)
	_outline(img, line)
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------- shapes

static func _draw_item(img: Image, name: String, c: Color, silhouette: bool) -> void:
	var d := c.darkened(0.3)
	var dd := c.darkened(0.5)
	var l := c.lightened(0.25)
	match name:
		"tshirt":
			_poly(img, [Vector2(10, 4), Vector2(13, 4), Vector2(16, 6.5), Vector2(19, 4), Vector2(22, 4), Vector2(29.5, 9), Vector2(26.5, 15), Vector2(23, 13), Vector2(23, 28.5), Vector2(9, 28.5), Vector2(9, 13), Vector2(5.5, 15), Vector2(2.5, 9)], c)
			if not silhouette:
				_line(img, Vector2i(13, 4), Vector2i(16, 7), d)
				_line(img, Vector2i(16, 7), Vector2i(19, 4), d)
				_line(img, Vector2i(9, 13), Vector2i(9, 9), d)
				_line(img, Vector2i(23, 13), Vector2i(23, 9), d)
				_line(img, Vector2i(10, 27), Vector2i(22, 27), d)
		"flannel", "hoodie", "jacket":
			_poly(img, [Vector2(10, 4), Vector2(13, 4), Vector2(16, 6.5), Vector2(19, 4), Vector2(22, 4), Vector2(28, 8.5), Vector2(30.5, 26), Vector2(26.5, 27), Vector2(23.5, 15), Vector2(23.5, 28.5), Vector2(8.5, 28.5), Vector2(8.5, 15), Vector2(5.5, 27), Vector2(1.5, 26), Vector2(4, 8.5)], c)
			if silhouette:
				return
			if name == "flannel":
				_plaid(img, c)
				for y in [10, 14, 18, 22, 26]:
					_px(img, 16, y, l.lightened(0.3))
				_line(img, Vector2i(13, 4), Vector2i(16, 7), dd)
				_line(img, Vector2i(16, 7), Vector2i(19, 4), dd)
			elif name == "hoodie":
				_poly(img, [Vector2(11, 4), Vector2(13, 1), Vector2(19, 1), Vector2(21, 4), Vector2(19, 7.5), Vector2(13, 7.5)], d)
				_rect(img, 11, 19, 10, 6, d)
				_line(img, Vector2i(11, 19), Vector2i(20, 19), dd)
				_line(img, Vector2i(14, 8), Vector2i(14, 12), l)
				_line(img, Vector2i(18, 8), Vector2i(18, 12), l)
			else:
				_poly(img, [Vector2(12.5, 4), Vector2(16, 13), Vector2(11, 9)], d)
				_poly(img, [Vector2(19.5, 4), Vector2(16, 13), Vector2(21, 9)], d)
				_line(img, Vector2i(16, 13), Vector2i(16, 28), Color("b0b0b8"))
				_line(img, Vector2i(10, 20), Vector2i(13, 20), dd)
				_line(img, Vector2i(19, 20), Vector2i(22, 20), dd)
			# cuffs
			_line(img, Vector2i(2, 25), Vector2i(5, 26), dd)
			_line(img, Vector2i(27, 26), Vector2i(30, 25), dd)
			_line(img, Vector2i(9, 27), Vector2i(23, 27), d)
		"jeans", "cargo_pants":
			_poly(img, [Vector2(7.5, 3), Vector2(24.5, 3), Vector2(26, 29.5), Vector2(18, 29.5), Vector2(16.5, 12), Vector2(15.5, 12), Vector2(14, 29.5), Vector2(6, 29.5)], c)
			if silhouette:
				return
			_rect(img, 8, 3, 16, 3, d)
			for x in [10, 16, 22]:
				_px(img, x, 4, l)
			_line(img, Vector2i(16, 6), Vector2i(16, 11), dd)
			_line(img, Vector2i(9, 6), Vector2i(12, 9), dd)
			_line(img, Vector2i(23, 6), Vector2i(20, 9), dd)
			_line(img, Vector2i(7, 28), Vector2i(14, 28), l)
			_line(img, Vector2i(18, 28), Vector2i(25, 28), l)
			if name == "cargo_pants":
				_rect(img, 6, 15, 5, 7, d)
				_rect(img, 22, 15, 5, 7, d)
				_line(img, Vector2i(6, 15), Vector2i(10, 15), dd)
				_line(img, Vector2i(22, 15), Vector2i(26, 15), dd)
		"boots":
			_poly(img, [Vector2(15, 3), Vector2(22, 3), Vector2(22, 17), Vector2(28.5, 19), Vector2(29.5, 24.5), Vector2(14, 24.5)], c.darkened(0.15))
			_poly(img, [Vector2(4, 7), Vector2(11, 7), Vector2(11, 21), Vector2(17.5, 23), Vector2(18.5, 28.5), Vector2(3, 28.5)], c)
			if silhouette:
				return
			_line(img, Vector2i(4, 27), Vector2i(18, 27), dd)
			_line(img, Vector2i(15, 23), Vector2i(29, 23), dd)
			for y in [10, 13, 16]:
				_line(img, Vector2i(6, y), Vector2i(9, y), l)
		"vest":
			_poly(img, [Vector2(8.5, 3), Vector2(13, 3), Vector2(13.5, 8), Vector2(18.5, 8), Vector2(19, 3), Vector2(23.5, 3), Vector2(24, 9), Vector2(27, 11), Vector2(27, 29), Vector2(5, 29), Vector2(5, 11), Vector2(8, 9)], c)
			if silhouette:
				return
			_line(img, Vector2i(16, 9), Vector2i(16, 28), dd)
			for r in [Vector4i(7, 13, 7, 6), Vector4i(18, 13, 7, 6), Vector4i(7, 21, 7, 6), Vector4i(18, 21, 7, 6)]:
				_rect(img, r.x, r.y, r.z, r.w, d)
				_line(img, Vector2i(r.x, r.y), Vector2i(r.x + r.z - 1, r.y), l)
		"helmet":
			_poly(img, _semi_ellipse(Vector2(16, 19), 13, 14), c)
			_rect(img, 2, 18, 28, 4, c.darkened(0.15))
			if silhouette:
				return
			_line(img, Vector2i(2, 21), Vector2i(29, 21), dd)
			_line(img, Vector2i(9, 9), Vector2i(12, 7), l)
			_line(img, Vector2i(7, 22), Vector2i(10, 28), dd)
		"cap":
			_poly(img, _semi_ellipse(Vector2(13, 21), 11, 14), c)
			_poly(img, [Vector2(13, 18), Vector2(28, 19), Vector2(30.5, 22.5), Vector2(13, 22.5)], d)
			if silhouette:
				return
			_px(img, 13, 7, l)
			_line(img, Vector2i(13, 8), Vector2i(13, 20), d)
			_line(img, Vector2i(6, 12), Vector2i(8, 10), l)
		"beanie":
			_poly(img, _semi_ellipse(Vector2(16, 20), 12, 14), c)
			_rect(img, 4, 18, 24, 8, d)
			_circle(img, Vector2(16, 5), 3.6, Color("e0d8c8") if not silhouette else c)
			if silhouette:
				return
			for x in range(5, 27, 2):
				_line(img, Vector2i(x, 19), Vector2i(x, 24), l.darkened(0.15))
		"backpack_small", "backpack_large":
			var big := name == "backpack_large"
			var top := 4 if big else 8
			_rect(img, 7, top, 18, 30 - top, c)
			if big:
				_rect(img, 5, 1, 22, 5, Color("8a7a50") if not silhouette else c)
			if silhouette:
				return
			_rect(img, 7, top, 18, 8, d)
			_line(img, Vector2i(8, top + 8), Vector2i(23, top + 8), dd)
			_rect(img, 11, top + 6, 2, 4, Color("c9a46a"))
			_rect(img, 19, top + 6, 2, 4, Color("c9a46a"))
			_rect(img, 10, 21, 12, 7, d)
			_line(img, Vector2i(10, 21), Vector2i(21, 21), l)
			_line(img, Vector2i(13, top - 2), Vector2i(19, top - 2), dd)
			_px(img, 12, top - 1, dd)
			_px(img, 20, top - 1, dd)
		"soda":
			_rect(img, 10, 5, 12, 23, c)
			_rect(img, 10, 4, 12, 2, Color("b8b8c0"))
			_rect(img, 10, 27, 12, 2, Color("9a9aa2"))
			if silhouette:
				return
			_rect(img, 10, 12, 12, 8, Color("e8e4dc"))
			_line(img, Vector2i(12, 7), Vector2i(12, 25), l)
			_line(img, Vector2i(13, 15), Vector2i(19, 15), c)
			_line(img, Vector2i(13, 17), Vector2i(17, 17), c)
		"meat", "cooked_meat":
			var cooked := name == "cooked_meat"
			_poly(img, [Vector2(4, 11), Vector2(9, 6), Vector2(18, 5), Vector2(24, 8), Vector2(26, 15), Vector2(22, 22), Vector2(14, 25), Vector2(7, 23), Vector2(3.5, 17)], c)
			_rect(img, 22, 18, 7, 4, Color("e8e0d0"))
			_circle(img, Vector2(28.5, 18.5), 2.2, Color("e8e0d0"))
			_circle(img, Vector2(28.5, 22), 2.2, Color("e8e0d0"))
			if silhouette:
				return
			if cooked:
				for i in 4:
					_line(img, Vector2i(6 + i * 5, 20), Vector2i(12 + i * 5, 8), d)
			else:
				_line(img, Vector2i(8, 12), Vector2i(15, 10), Color("e8c8b8"))
				_line(img, Vector2i(11, 17), Vector2i(19, 14), Color("e8c8b8"))
		"water":
			# Plastic bottle of clear water
			_rect(img, 13, 1, 6, 3, Color("3a6aa8"))
			_rect(img, 14, 4, 4, 3, Color("cfe4f0"))
			_poly(img, [Vector2(14, 7), Vector2(18, 7), Vector2(23, 11.5), Vector2(23, 30), Vector2(9, 30), Vector2(9, 11.5)], Color("cfe4f0"))
			_rect(img, 9, 13, 14, 17, c)
			if silhouette:
				return
			_rect(img, 9, 13, 14, 2, c.lightened(0.35))
			_rect(img, 9, 25, 14, 5, c.darkened(0.2))
			_rect(img, 9, 17, 14, 6, Color("e8eef2"))
			_line(img, Vector2i(10, 19), Vector2i(21, 19), Color("3a6aa8"))
			_line(img, Vector2i(12, 21), Vector2i(19, 21), Color("6a9ac8"))
			_line(img, Vector2i(11, 9), Vector2i(11, 28), Color(1, 1, 1, 0.9))
		"rags":
			# A few torn cloth strips in a pile
			_poly(img, [Vector2(4, 20), Vector2(14, 15), Vector2(26, 17), Vector2(28, 22), Vector2(18, 27), Vector2(6, 26)], c)
			_poly(img, [Vector2(7, 14), Vector2(18, 9), Vector2(25, 12), Vector2(14, 18), Vector2(8, 18)], c.lightened(0.12))
			if silhouette:
				return
			_line(img, Vector2i(6, 23), Vector2i(26, 20), d)
			_line(img, Vector2i(10, 15), Vector2i(22, 11), d)
			for p in [Vector2i(5, 26), Vector2i(9, 27), Vector2i(27, 22)]:
				_px(img, p.x, p.y, dd)
		"rope":
			# Coiled rope
			for r in [11.5, 8.5, 5.5]:
				_ring(img, Vector2(16, 17), r, 2.6, c if r != 8.5 else c.darkened(0.12))
			_rect(img, 24, 23, 6, 3, c)
			if silhouette:
				return
			for a in range(0, 360, 30):
				var v := Vector2.from_angle(deg_to_rad(a))
				_px(img, int(16 + v.x * 11.5), int(17 + v.y * 11.5), d)
				_px(img, int(16 + v.x * 5.5), int(17 + v.y * 5.5), d)
		"sack", "sack_backpack":
			# Burlap sack tied at the top (backpack version has straps)
			_poly(img, [Vector2(13, 3), Vector2(19, 3), Vector2(18, 8), Vector2(25, 13), Vector2(27, 24), Vector2(23, 30), Vector2(9, 30), Vector2(5, 24), Vector2(7, 13), Vector2(14, 8)], c)
			if silhouette:
				return
			_line(img, Vector2i(13, 8), Vector2i(19, 8), Color("5a4630"))
			_line(img, Vector2i(12, 9), Vector2i(20, 9), Color("5a4630"))
			for y in range(12, 29, 3):
				_line(img, Vector2i(8, y), Vector2i(24, y), c.darkened(0.12))
			if name == "sack_backpack":
				_line(img, Vector2i(10, 10), Vector2i(8, 29), Color("4a3828"))
				_line(img, Vector2i(11, 10), Vector2i(9, 29), Color("4a3828"))
				_line(img, Vector2i(22, 10), Vector2i(24, 29), Color("4a3828"))
				_line(img, Vector2i(21, 10), Vector2i(23, 29), Color("4a3828"))
		"spear":
			# Sharpened pole with a knife lashed to the tip
			_poly(img, [Vector2(3, 28), Vector2(21, 10), Vector2(23, 12), Vector2(5, 30)], c)
			_poly(img, [Vector2(21, 9), Vector2(29, 2), Vector2(30, 3), Vector2(23, 11)], Color("b8bcc4"))
			if silhouette:
				return
			_line(img, Vector2i(19, 12), Vector2i(22, 15), Color("c8b088"))
			_line(img, Vector2i(18, 13), Vector2i(21, 16), Color("c8b088"))
			_line(img, Vector2i(24, 7), Vector2i(29, 3), Color("e8ecf0"))
		"map":
			# Folded paper road map
			_poly(img, [Vector2(3, 7), Vector2(11, 4), Vector2(21, 7), Vector2(29, 4), Vector2(29, 26), Vector2(21, 29), Vector2(11, 26), Vector2(3, 29)], c)
			if silhouette:
				return
			_line(img, Vector2i(11, 5), Vector2i(11, 26), d)
			_line(img, Vector2i(21, 8), Vector2i(21, 28), d)
			_line(img, Vector2i(5, 20), Vector2i(27, 12), Color("8a8478"))
			_line(img, Vector2i(14, 9), Vector2i(17, 26), Color("8a8478"))
			_rect(img, 6, 10, 3, 3, Color("6a8a4a"))
			_rect(img, 23, 19, 4, 3, Color("6a8a4a"))
			_circle(img, Vector2(18, 17), 1.6, Color("b83a3a"))
		"matches":
			for x in [10, 14, 18, 22]:
				_line(img, Vector2i(x, 3), Vector2i(x, 12), Color("e0c890"))
				_rect(img, x, 2, 2, 2, Color("c84a2a"))
			_rect(img, 5, 11, 22, 16, c)
			if silhouette:
				return
			_rect(img, 5, 16, 22, 6, Color("e8e0c8"))
			_line(img, Vector2i(8, 19), Vector2i(23, 19), c)
		"sewing_kit":
			# Round biscuit tin with a spool of thread and a needle on top
			_circle(img, Vector2(16, 18), 12.5, c)
			if silhouette:
				return
			_ring(img, Vector2(16, 18), 10.0, 1.2, l)
			_rect(img, 10, 13, 9, 10, Color("e8e0c8"))
			_rect(img, 10, 15, 9, 6, Color("c83a4a"))
			_line(img, Vector2i(10, 16), Vector2i(18, 16), Color("e05a6a"))
			_line(img, Vector2i(10, 19), Vector2i(18, 19), Color("a02a3a"))
			_line(img, Vector2i(19, 9), Vector2i(26, 26), Color("d8dce4"))
			_px(img, 19, 9, Color("8a8e94"))
			_line(img, Vector2i(18, 18), Vector2i(22, 16), Color("c83a4a"))
		"toolbox":
			# Red metal toolbox with a handle
			_ring(img, Vector2(16, 10), 5.0, 2.0, Color("4a4a52"))
			_rect(img, 3, 12, 26, 16, c)
			_poly(img, [Vector2(3, 12), Vector2(6, 9), Vector2(26, 9), Vector2(29, 12)], l)
			if silhouette:
				return
			_line(img, Vector2i(3, 16), Vector2i(28, 16), d)
			_rect(img, 7, 15, 3, 3, Color("c8ccd4"))
			_rect(img, 22, 15, 3, 3, Color("c8ccd4"))
			_line(img, Vector2i(4, 26), Vector2i(27, 26), dd)
		"scrap_metal":
			# Two bent, riveted metal plates
			_poly(img, [Vector2(3, 10), Vector2(19, 5), Vector2(22, 19), Vector2(6, 24)], d)
			_poly(img, [Vector2(10, 14), Vector2(28, 11), Vector2(29, 27), Vector2(12, 29)], c)
			if silhouette:
				return
			for r in [Vector2(7, 12), Vector2(17, 9), Vector2(14, 17), Vector2(25, 14), Vector2(26, 24)]:
				_px(img, int(r.x), int(r.y), Color("3a3a42"))
			_line(img, Vector2i(12, 20), Vector2i(27, 18), l)
			_rect(img, 19, 23, 3, 2, Color("9a5a32"))
			_rect(img, 8, 19, 2, 2, Color("9a5a32"))
		"scrap_armour":
			# Metal plates strapped together with rope, worn like a vest
			_poly(img, [Vector2(8, 3), Vector2(12, 3), Vector2(16, 8), Vector2(20, 3), Vector2(24, 3), Vector2(27, 9), Vector2(27, 29), Vector2(5, 29), Vector2(5, 9)], c)
			if silhouette:
				return
			_rect(img, 7, 11, 8, 8, l)
			_rect(img, 17, 11, 8, 8, d)
			_rect(img, 7, 20, 18, 7, c.darkened(0.12))
			_line(img, Vector2i(5, 19), Vector2i(27, 19), Color("a08458"))
			_line(img, Vector2i(5, 10), Vector2i(27, 10), Color("a08458"))
			_line(img, Vector2i(16, 10), Vector2i(16, 28), Color("a08458"))
			for r in [Vector2(9, 13), Vector2(13, 17), Vector2(19, 13), Vector2(23, 17), Vector2(10, 24), Vector2(22, 24)]:
				_px(img, int(r.x), int(r.y), Color("2e2a30"))
			_rect(img, 20, 21, 3, 2, Color("9a5a32"))
		"leather":
			# A stretched hide
			_poly(img, [Vector2(6, 4), Vector2(11, 7), Vector2(16, 5), Vector2(21, 7), Vector2(26, 4), Vector2(28, 10), Vector2(25, 16),
				Vector2(28, 22), Vector2(25, 28), Vector2(20, 25), Vector2(16, 28), Vector2(12, 25), Vector2(7, 28), Vector2(4, 22), Vector2(7, 16), Vector2(4, 10)], c)
			if silhouette:
				return
			_poly(img, [Vector2(10, 10), Vector2(16, 9), Vector2(22, 10), Vector2(22, 22), Vector2(16, 24), Vector2(10, 22)], l)
			for y in [11, 15, 19]:
				_px(img, 9, y, d)
				_px(img, 23, y, d)
		"gourd":
			# Leather water flask with a cork and a strap
			_ring(img, Vector2(16, 13), 11.0, 1.4, Color("4a3828"))
			_circle(img, Vector2(16, 19), 10.0, c)
			_rect(img, 13, 5, 6, 6, c)
			_rect(img, 13, 2, 6, 4, Color("c8a070"))
			if silhouette:
				return
			_ring(img, Vector2(16, 19), 7.5, 1.0, l)
			for a in [0.0, 0.8, 1.6, 2.4, 3.2, 4.0, 4.8, 5.6]:
				_px(img, int(16 + cos(a) * 7.5), int(19 + sin(a) * 7.5), dd)
			_line(img, Vector2i(13, 10), Vector2i(18, 10), dd)
		"fish", "cooked_fish":
			# A fish lying on its side
			_poly(img, [Vector2(4, 16), Vector2(10, 10), Vector2(19, 9), Vector2(24, 13), Vector2(29, 8), Vector2(29, 24), Vector2(24, 19), Vector2(19, 23), Vector2(10, 22)], c)
			if silhouette:
				return
			_poly(img, [Vector2(12, 10), Vector2(16, 6), Vector2(19, 9)], d)
			_line(img, Vector2i(6, 18), Vector2i(19, 20), l if name == "fish" else dd)
			_circle(img, Vector2(9, 15), 1.3, Color("1a1016"))
			if name == "cooked_fish":
				for x in [12, 16, 20]:
					_line(img, Vector2i(x, 11), Vector2i(x - 2, 21), dd)
		"tomato":
			_circle(img, Vector2(16, 18), 10.5, c)
			if silhouette:
				return
			_circle(img, Vector2(12, 14), 2.5, l)
			_poly(img, [Vector2(11, 8), Vector2(16, 10), Vector2(21, 8), Vector2(18, 12), Vector2(14, 12)], Color("3e7a32"))
			_line(img, Vector2i(16, 4), Vector2i(16, 9), Color("3e7a32"))
		"potato":
			_poly(img, [Vector2(5, 15), Vector2(9, 9), Vector2(17, 7), Vector2(25, 10), Vector2(28, 17), Vector2(24, 24), Vector2(15, 26), Vector2(8, 23)], c)
			if silhouette:
				return
			for e in [Vector2(11, 14), Vector2(19, 12), Vector2(22, 19), Vector2(14, 21)]:
				_px(img, int(e.x), int(e.y), dd)
			_line(img, Vector2i(10, 10), Vector2i(17, 9), l)
		"tomato_seeds":
			# A paper seed packet with a tomato on it
			_rect(img, 7, 4, 18, 25, c)
			if silhouette:
				return
			_rect(img, 7, 4, 18, 3, d)
			_circle(img, Vector2(16, 18), 5.5, Color("c8382e"))
			_poly(img, [Vector2(13, 12), Vector2(16, 13), Vector2(19, 12), Vector2(17, 14), Vector2(15, 14)], Color("3e7a32"))
		"planks":
			for i in 3:
				_rect(img, 3, 7 + i * 7, 26, 5, c.darkened(i * 0.08))
			if silhouette:
				return
			for i in 3:
				_line(img, Vector2i(3, 7 + i * 7), Vector2i(28, 7 + i * 7), l)
				_px(img, 8 + i * 6, 9 + i * 7, dd)
		"nails":
			for k in 4:
				var x := 7 + k * 5
				_rect(img, x, 6 + (k % 2) * 3, 4, 2, c.lightened(0.15))
				_rect(img, x + 1, 8 + (k % 2) * 3, 2, 17, c)
			if silhouette:
				return
			for k in 4:
				_line(img, Vector2i(8 + k * 5, 9 + (k % 2) * 3), Vector2i(8 + k * 5, 24 + (k % 2) * 3), l)
		"fishing_rod":
			_line(img, Vector2i(3, 29), Vector2i(28, 3), c)
			_line(img, Vector2i(4, 29), Vector2i(29, 3), c)
			_rect(img, 4, 22, 5, 4, Color("3a3a42"))
			if silhouette:
				return
			_line(img, Vector2i(28, 3), Vector2i(28, 22), Color("d8dce4"))
			_rect(img, 27, 22, 3, 3, Color("c83a3a"))
		"kit_wall", "kit_gate", "kit_chest", "kit_bed", "kit_garden":
			# A bundle of planks tied with rope, with a picture of what it builds
			_rect(img, 3, 18, 26, 10, Color("a07448"))
			_line(img, Vector2i(3, 22), Vector2i(28, 22), Color("7a5432"))
			_line(img, Vector2i(10, 18), Vector2i(10, 27), Color("c8b088"))
			_line(img, Vector2i(22, 18), Vector2i(22, 27), Color("c8b088"))
			if silhouette:
				return
			match name:
				"kit_wall":
					_rect(img, 7, 3, 18, 13, c)
					for x in [11, 15, 19]:
						_line(img, Vector2i(x, 3), Vector2i(x, 15), dd)
				"kit_gate":
					_rect(img, 7, 3, 18, 13, c)
					_line(img, Vector2i(7, 3), Vector2i(24, 15), dd)
					_line(img, Vector2i(16, 3), Vector2i(16, 15), dd)
				"kit_chest":
					_rect(img, 8, 6, 16, 10, c)
					_rect(img, 8, 6, 16, 3, l)
					_rect(img, 15, 9, 2, 3, Color("d8c070"))
				"kit_bed":
					_rect(img, 6, 7, 20, 8, Color("5a7aa8"))
					_rect(img, 6, 7, 6, 8, Color("e8e0d0"))
					_rect(img, 6, 14, 20, 2, c)
				"kit_garden":
					_rect(img, 6, 8, 20, 8, Color("5a3e28"))
					for x in [10, 16, 22]:
						_line(img, Vector2i(x, 4), Vector2i(x, 9), Color("4a9a3a"))
						_px(img, x - 1, 5, Color("4a9a3a"))
						_px(img, x + 1, 6, Color("4a9a3a"))
		# --- symbols only
		"hand":
			_rect(img, 10, 13, 13, 14, c)
			for f in [Vector4i(10, 5, 3, 9), Vector4i(13, 3, 3, 11), Vector4i(16, 4, 3, 10), Vector4i(19, 6, 3, 8)]:
				_rect(img, f.x, f.y, f.z, f.w, c)
			_poly(img, [Vector2(10, 17), Vector2(4, 11), Vector2(2.5, 13.5), Vector2(9.5, 23)], c)
		"rifle":
			_poly(img, [Vector2(1, 17), Vector2(8, 14), Vector2(8, 20), Vector2(2, 23)], c)
			_rect(img, 8, 13, 16, 5, c)
			_rect(img, 24, 14, 7, 2, c)
			_rect(img, 15, 18, 3, 7, c)
			_rect(img, 10, 18, 3, 5, c)
		"pistol":
			_rect(img, 5, 9, 20, 6, c)
			_poly(img, [Vector2(7, 15), Vector2(13, 15), Vector2(12, 26), Vector2(6, 26)], c)
			_rect(img, 13, 15, 4, 2, c)
		"knife":
			_poly(img, [Vector2(3, 27), Vector2(17, 11), Vector2(20, 14), Vector2(6, 29)], c)
			_poly(img, [Vector2(17, 11), Vector2(25, 3), Vector2(29, 7), Vector2(20, 14)], c.lightened(0.15) if silhouette else c)


# ---------------------------------------------------------------- raster helpers

static func _px(img: Image, x: int, y: int, col: Color) -> void:
	if x >= 0 and y >= 0 and x < SIZE and y < SIZE:
		img.set_pixel(x, y, col)


static func _rect(img: Image, x: int, y: int, w: int, h: int, col: Color) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			_px(img, xx, yy, col)


static func _poly(img: Image, pts: Array, col: Color) -> void:
	var poly := PackedVector2Array(pts)
	for y in SIZE:
		for x in SIZE:
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), poly):
				img.set_pixel(x, y, col)


static func _circle(img: Image, c: Vector2, r: float, col: Color) -> void:
	for y in SIZE:
		for x in SIZE:
			if Vector2(x + 0.5, y + 0.5).distance_to(c) <= r:
				img.set_pixel(x, y, col)


static func _ring(img: Image, c: Vector2, r: float, w: float, col: Color) -> void:
	for y in SIZE:
		for x in SIZE:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			if absf(d - r) <= w * 0.5:
				img.set_pixel(x, y, col)


static func _semi_ellipse(c: Vector2, rx: float, ry: float) -> Array:
	var pts := []
	for i in 17:
		var a := PI * i / 16.0
		pts.append(Vector2(c.x + cos(a) * rx, c.y - sin(a) * ry))
	return pts


static func _line(img: Image, a: Vector2i, b: Vector2i, col: Color) -> void:
	var n := maxi(absi(b.x - a.x), absi(b.y - a.y))
	for i in n + 1:
		var t := float(i) / maxf(n, 1)
		var p := Vector2(a).lerp(Vector2(b), t).round()
		_px(img, int(p.x), int(p.y), col)


## Checked pattern (flannel)
static func _plaid(img: Image, c: Color) -> void:
	for y in SIZE:
		for x in SIZE:
			var p := img.get_pixel(x, y)
			if p.a < 0.5 or not p.is_equal_approx(c):
				continue
			var vx := x % 6 < 2
			var vy := y % 6 < 2
			if vx and vy:
				img.set_pixel(x, y, c.darkened(0.45))
			elif vx or vy:
				img.set_pixel(x, y, c.darkened(0.22))


## Soft volume: light top edges, dark bottom / right edges.
static func _shade(img: Image) -> void:
	var src := img.duplicate() as Image
	for y in SIZE:
		for x in SIZE:
			var p := src.get_pixel(x, y)
			if p.a < 0.5:
				continue
			var up := y == 0 or src.get_pixel(x, y - 1).a < 0.5
			var down := y == SIZE - 1 or src.get_pixel(x, y + 1).a < 0.5
			var right := x == SIZE - 1 or src.get_pixel(x + 1, y).a < 0.5
			var left := x == 0 or src.get_pixel(x - 1, y).a < 0.5
			if up or left:
				img.set_pixel(x, y, p.lightened(0.18))
			elif down or right:
				img.set_pixel(x, y, p.darkened(0.25))


## 1px outline around everything drawn.
static func _outline(img: Image, col: Color) -> void:
	var src := img.duplicate() as Image
	for y in SIZE:
		for x in SIZE:
			if src.get_pixel(x, y).a > 0.5:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = Vector2i(x, y) + d
				if n.x >= 0 and n.y >= 0 and n.x < SIZE and n.y < SIZE and src.get_pixel(n.x, n.y).a > 0.5:
					img.set_pixel(x, y, col)
					break
