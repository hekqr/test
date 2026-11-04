extends SceneTree
## Dev tool: renders all drawn icons to one PNG. godot --headless --path . -s tests/icon_preview.gd -- <out.png>
func _initialize() -> void:
	var names := ["tshirt", "flannel", "hoodie", "jacket", "jeans", "cargo_pants", "boots", "vest", "helmet", "cap", "beanie", "backpack_small", "backpack_large", "soda", "meat", "cooked_meat", "matches", "water"]
	var slots := ["head", "armour", "coat", "shirt", "pants", "boots", "back", "hands", "primary", "secondary", "melee"]
	var sc := 4
	var out := Image.create_empty(names.size() * 34 * sc, 3 * 34 * sc, false, Image.FORMAT_RGBA8)
	out.fill(Color("3b2f3a"))
	for i in names.size():
		var img := (Icons.make(names[i], "") as ImageTexture).get_image()
		img.resize(32 * sc, 32 * sc, Image.INTERPOLATE_NEAREST)
		out.blend_rect(img, Rect2i(0, 0, 32 * sc, 32 * sc), Vector2i(i * 34 * sc, 0))
		var img2 := (Icons.make(names[i], "3a5a9c") as ImageTexture).get_image()
		img2.resize(32 * sc, 32 * sc, Image.INTERPOLATE_NEAREST)
		out.blend_rect(img2, Rect2i(0, 0, 32 * sc, 32 * sc), Vector2i(i * 34 * sc, 34 * sc))
	for i in slots.size():
		var img := (Icons.slot_symbol(slots[i], Color("4a3e4a"), Color("6e6070")) as ImageTexture).get_image()
		img.resize(32 * sc, 32 * sc, Image.INTERPOLATE_NEAREST)
		out.blend_rect(img, Rect2i(0, 0, 32 * sc, 32 * sc), Vector2i(i * 34 * sc, 68 * sc))
	out.save_png(OS.get_cmdline_user_args()[0])
	quit()
