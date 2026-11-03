class_name Hud
extends Control
## On-screen UI: stat bars, inventory, clock, messages, help, pause and death screens.

var main: Node
var show_help := true
var _font: Font


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font


func _process(_delta: float) -> void:
	if main and main.survived > 30.0 and show_help and not get_tree().paused:
		show_help = false
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	var p: Player = main.player
	if event.is_action_pressed("fullscreen"):
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif event.is_action_pressed("help"):
		show_help = not show_help
	elif p.dead and event.is_action_pressed("reload"):
		main.restart()
	elif event.is_action_pressed("pause") and not p.dead:
		get_tree().paused = not get_tree().paused
	elif get_tree().paused and event.is_action_pressed("quit"):
		get_tree().quit()


func _text(pos: Vector2, s: String, size_px := 16, col := Color.WHITE, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	if align == HORIZONTAL_ALIGNMENT_RIGHT and width <= 0.0:
		pos.x -= _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
		align = HORIZONTAL_ALIGNMENT_LEFT
		width = -1.0
	draw_string(_font, pos + Vector2(1, 1), s, align, width, size_px, Color(0, 0, 0, 0.7))
	draw_string(_font, pos, s, align, width, size_px, col)


func _bar(pos: Vector2, label: String, value: float, col: Color) -> void:
	var w := 200.0
	draw_rect(Rect2(pos, Vector2(w, 14)), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(pos, Vector2(w * clampf(value / 100.0, 0.0, 1.0), 14)), col)
	_text(pos + Vector2(w + 8, 12), "%s %d" % [label, int(value)], 13)


func _draw() -> void:
	if main == null or main.player == null:
		return
	var p: Player = main.player
	var vs := get_viewport_rect().size

	# Stat bars
	var y := vs.y - 104.0
	_bar(Vector2(20, y), "Health", p.health, Color(0.82, 0.2, 0.2))
	_bar(Vector2(20, y + 22), "Hunger", p.hunger, Color(0.9, 0.6, 0.2))
	_bar(Vector2(20, y + 44), "Thirst", p.thirst, Color(0.25, 0.55, 0.95))
	_bar(Vector2(20, y + 66), "Stamina", p.stamina, Color(0.9, 0.85, 0.3))
	if p.bleeding:
		_text(Vector2(20, y - 10), "BLEEDING", 15, Color(1, 0.3, 0.3))

	# Weapon + inventory
	var inv: Dictionary = p.inventory
	var wx := vs.x - 290.0
	var wname := "Pistol  %d / %d" % [p.mag, inv["ammo"]] if p.weapon == 1 else "Knife"
	if p.reloading:
		wname += "  (reloading)"
	_text(Vector2(wx, vs.y - 86), wname, 20)
	_text(Vector2(wx, vs.y - 60), "Food %d [F]   Water %d [G]" % [inv["food"], inv["water"]], 15)
	_text(Vector2(wx, vs.y - 38), "Bandages %d [H]   Ammo %d" % [inv["bandage"], inv["ammo"]], 15)
	_text(Vector2(wx, vs.y - 16), "[1] Knife   [2] Pistol%s" % ("" if p.has_pistol else " (not found)"), 13, Color(0.8, 0.8, 0.8))

	# Clock / stats
	var st := int(main.survived)
	_text(Vector2(vs.x - 20, 30), "Day %d  %s" % [main.day, main.clock_text()], 20, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, 0)
	_text(Vector2(vs.x - 20, 52), "Survived %d:%02d   Kills %d" % [st / 60, st % 60, main.kills], 14, Color(0.85, 0.85, 0.85), HORIZONTAL_ALIGNMENT_RIGHT, 0)

	# Search prompt above the player
	if p.nearest_loot and not p.dead:
		var sp := p.get_global_transform_with_canvas().origin
		_text(sp + Vector2(-60, -34), "[E] Search", 15, Color(1, 0.95, 0.6), HORIZONTAL_ALIGNMENT_CENTER, 120)

	# Message
	if p.message_t > 0.0:
		_text(Vector2(0, vs.y - 140), p.message, 18, Color(1, 1, 1, clampf(p.message_t, 0, 1)), HORIZONTAL_ALIGNMENT_CENTER, vs.x)

	# Help
	if show_help:
		var lines := [
			"WASD move   Shift sprint   Mouse aim   Left click attack",
			"E search   R reload   1/2 switch weapon",
			"F eat   G drink   H bandage",
			"Esc pause   F11 fullscreen   F1 hide help",
		]
		draw_rect(Rect2(14, 14, 470, 104), Color(0, 0, 0, 0.5))
		for i in lines.size():
			_text(Vector2(24, 38 + i * 22), lines[i], 15)
	else:
		_text(Vector2(20, 28), "F1 help", 13, Color(0.8, 0.8, 0.8))

	# Pause
	if get_tree().paused:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.55))
		_text(Vector2(0, vs.y * 0.45), "PAUSED", 48, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, vs.x)
		_text(Vector2(0, vs.y * 0.45 + 40), "Esc resume   Q quit", 18, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, vs.x)

	# Death
	if p.dead:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0.25, 0, 0, 0.6))
		_text(Vector2(0, vs.y * 0.42), "YOU DIED", 56, Color(1, 0.85, 0.85), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
		_text(Vector2(0, vs.y * 0.42 + 44), "Survived %d:%02d   Day %d   Kills %d" % [st / 60, st % 60, main.day, main.kills], 20, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, vs.x)
		_text(Vector2(0, vs.y * 0.42 + 80), "Press R to try again", 18, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, vs.x)
