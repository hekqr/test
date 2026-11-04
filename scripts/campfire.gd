class_name Campfire
extends Node2D
## A campfire: built from 3 sticks + 1 match. Burns while it has fuel; add sticks to keep it going.
## Warms you up nearby, lights up the night and cooks raw meat.

const BURN_PER_STICK := 60.0 # seconds of fire per stick
const MAX_FUEL := 300.0
const WARM_RADIUS := 110.0
const WARMTH := 35.0 # extra target temperature right next to the fire

var fuel := 0.0 # seconds left
var permanent := false # a stove: never goes out, drawn by the stove itself (just the flames in its window)
var lit: bool:
	get:
		return fuel > 0.0
var _light: PointLight2D
var _t := 0.0


func _ready() -> void:
	add_to_group("fires")
	if permanent:
		fuel = MAX_FUEL
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.7, 0.35, 1))
	g.set_color(1, Color(1.0, 0.5, 0.2, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	_light = PointLight2D.new()
	_light.texture = tex
	_light.texture_scale = 2.4
	_light.position = Vector2(0, -6)
	if permanent:
		_light.texture_scale = 1.6
	add_child(_light)


func _process(delta: float) -> void:
	_t += delta
	if lit:
		if not permanent:
			fuel = maxf(fuel - delta, 0.0)
		_light.energy = (0.9 + 0.12 * sin(_t * 11.0) + 0.08 * sin(_t * 23.0)) * (1.0 if fuel > 20.0 else fuel / 20.0)
	else:
		_light.energy = 0.0
	queue_redraw()


func add_sticks(n: int) -> void:
	fuel = minf(fuel + n * BURN_PER_STICK, MAX_FUEL)


## Extra warmth for something standing at `pos`.
func warmth_at(pos: Vector2) -> float:
	if not lit:
		return 0.0
	var d := pos.distance_to(global_position)
	return 0.0 if d > WARM_RADIUS else WARMTH * (1.0 - d / WARM_RADIUS * 0.6)


func label(p: Player) -> String:
	if permanent:
		var raw := p.inv.count_of("meat") + p.inv.count_of("fish")
		return "Cook on the stove (%d)" % raw if raw > 0 else "Stove (burning)"
	if lit and p.inv.count_of("meat") > 0:
		return "Cook meat (%d)" % p.inv.count_of("meat")
	if lit:
		return "Add wood (%ds left)" % int(fuel)
	return "Light fire"


func to_save() -> Dictionary:
	return {"pos": [position.x, position.y], "fuel": fuel}


func _draw() -> void:
	if permanent:
		# Flames behind the stove's little window
		var glow := Color("e8902a").lerp(Color("f8e070"), 0.5 + 0.5 * sin(_t * 9.0))
		draw_rect(Rect2(-5, 1, 10, 6), Color("c84a2a"))
		draw_rect(Rect2(-4, 3 + sin(_t * 13.0), 8, 4), glow)
		return
	# Stone ring
	var stone := Color("8a8690")
	var stone_d := Color("5a5660")
	for i in 8:
		var a := TAU * i / 8.0
		var p := Vector2(cos(a) * 13.0, sin(a) * 7.0)
		draw_circle(p, 4.0, Color("1a1016"))
		draw_circle(p, 3.0, stone if i % 2 == 0 else stone_d)
	# Logs
	var wood := Color("6e4a32") if lit else Color("3a2a22")
	draw_line(Vector2(-9, 3), Vector2(9, -3), Color("1a1016"), 5.0)
	draw_line(Vector2(-9, -3), Vector2(9, 3), Color("1a1016"), 5.0)
	draw_line(Vector2(-8, 3), Vector2(8, -3), wood, 3.0)
	draw_line(Vector2(-8, -3), Vector2(8, 3), wood, 3.0)
	if not lit:
		draw_circle(Vector2(0, 0), 3.0, Color("2a2224"))
		return
	# Flickering flames
	var f := 1.0 if fuel > 20.0 else 0.5 + fuel / 40.0
	for i in 3:
		var wob := sin(_t * (9.0 + i * 3.0) + i) * 2.0
		var h := (14.0 - i * 4.0) * f + sin(_t * 13.0 + i * 2.0) * 1.5
		var w := (7.0 - i * 2.0) * f
		var col: Color = [Color("c84a2a"), Color("e8902a"), Color("f8e070")][i]
		draw_colored_polygon(PackedVector2Array([Vector2(-w, 0), Vector2(wob, -h), Vector2(w, 0)]), col)
