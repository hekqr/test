class_name Buildings
## Hand-made building floor plans. The front door is always on the bottom row; the world rotates
## them so the front faces the road.
##
## Legend
##   #  wall              W  window (see-through for you, blocks zombies' sight)    D  door
##   w  wood floor        t  tile floor        c  concrete floor
##   Containers you can search:
##     F fridge   R wardrobe   M medicine cabinet   U trash can
##     S shop shelf   P pharmacy shelf   V vending machine   L police locker   C tool crate
##   Furniture (blocks walking, can't be searched):
##     B bed (head)   b bed (foot)   T table   Z sofa   O toilet   A bath (with a tap)   K kitchen counter   E desk
## Most village buildings are tiny one-room huts; houses have a bedroom or two, a bathroom and a living room.

const TEMPLATES := {
	# --- one-room huts
	"hut_bed": {"weight": 30, "rows": [
		"##W#W##",
		"#RBwwF#",
		"#wbwwwW",
		"#wwwTU#",
		"###D###",
	]},
	"hut_kitchen": {"weight": 25, "rows": [
		"##W###",
		"#KKFM#",
		"#wwww#",
		"WZwwU#",
		"##D###",
	]},
	"hut_bath": {"weight": 15, "rows": [
		"##W##W#",
		"#AwRwF#",
		"#twwww#",
		"#OwBbU#",
		"##D####",
	]},
	"hut_shed": {"weight": 10, "rows": [
		"######",
		"#CccT#",
		"#cccc#",
		"#Eccc#",
		"###D##",
	]},
	# --- houses
	"house_small": {"weight": 40, "rows": [
		"##W###W##",
		"#RwB#AOM#",
		"#wwb#tttW",
		"##D###D##",
		"WZwwwwwF#",
		"#UwTwwwK#",
		"####D####",
	]},
	"house_large": {"weight": 25, "rows": [
		"##W###W##W#",
		"#RwB#BR#AO#",
		"#wwb#bw#tM#",
		"##D###D#D##",
		"Wwwwwwwwww#",
		"#Zwwww#tKF#",
		"#ZwTww#tUK#",
		"####DD#####",
	]},
	"shop": {"weight": 12, "rows": [
		"####WW####",
		"#SSSSSSSS#",
		"#tttttttt#",
		"#tSStSStt#",
		"#tttttttV#",
		"WKKtttttUW",
		"####DD####",
	]},
	"police": {"weight": 5, "rows": [
		"##W###W###",
		"#LLLL#EwE#",
		"#cccc#www#",
		"#ccccDwwwW",
		"#LccC#wEw#",
		"######www#",
		"#OMtDwwwU#",
		"######DD##",
	]},
	"garage": {"weight": 12, "rows": [
		"##W##W##",
		"#CccccC#",
		"#cccccc#",
		"#cccccE#",
		"Wcccccc#",
		"##DDDD##",
	]},
	"clinic": {"weight": 6, "rows": [
		"##W###W##",
		"#PPP#MtM#",
		"#ttt#tBt#",
		"#tPtDtbt#",
		"#ttt#tttW",
		"#KKtU####",
		"###D#####",
	]},
}

## Container furniture -> loot table key (see Loot.CONTAINERS)
const CONTAINER_CHARS := {
	"F": "fridge", "R": "wardrobe", "M": "medicine", "U": "trash",
	"S": "shelf", "P": "pharmacy", "V": "vending", "L": "locker", "C": "crate",
}
## Furniture you can't search -> drawn sprite
const FURNITURE_CHARS := {"B": "bed_head", "b": "bed_foot", "T": "table", "Z": "sofa", "O": "toilet", "A": "bath",
	"K": "counter", "E": "desk"}
## Floor under each character: 1 wood, 2 tile, 3 concrete
const FLOOR_OF := {
	"w": 1, "D": 1, "R": 1, "E": 1, "B": 1, "b": 1, "T": 1, "Z": 1,
	"t": 2, "F": 2, "K": 2, "M": 2, "S": 2, "P": 2, "V": 2, "U": 2, "O": 2, "A": 2,
	"c": 3, "L": 3, "C": 3,
}


## Picks a building type; `mix` (type -> weight) overrides the default weights.
static func pick(rng: RandomNumberGenerator, mix := {}) -> String:
	var weights := {}
	for k in TEMPLATES:
		weights[k] = mix.get(k, 0) if not mix.is_empty() else int(TEMPLATES[k]["weight"])
	var total := 0
	for k in weights:
		total += int(weights[k])
	var r := rng.randi() % maxi(total, 1)
	for k in weights:
		r -= int(weights[k])
		if r < 0:
			return k
	return "house_small"


## Rotates / mirrors a plan. `front` = side the door should face: "S", "N", "W", "E".
static func oriented(rows: Array, front: String, mirror: bool) -> Array:
	var g: Array = []
	for r in rows:
		g.append(String(r).reverse() if mirror else String(r))
	match front:
		"N":
			g = _rot_cw(_rot_cw(g))
		"W":
			g = _rot_cw(g)
		"E":
			g = _rot_cw(_rot_cw(_rot_cw(g)))
	return g


static func _rot_cw(g: Array) -> Array:
	var h := g.size()
	var w := String(g[0]).length()
	var out: Array = []
	for x in w:
		var line := ""
		for y in range(h - 1, -1, -1):
			line += String(g[y])[x]
		out.append(line)
	return out
