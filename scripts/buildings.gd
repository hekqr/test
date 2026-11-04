class_name Buildings
## Hand-made building floor plans. The front door is always on the bottom row; the world rotates
## them so the front faces the road.
##
## Legend
##   #  wall              W  window (see-through, can't walk through)    D  door
##   w  wood floor        t  tile floor        c  concrete floor
##   Furniture (blocks walking). Containers you can search:
##     F fridge   K kitchen cupboard / counter   R wardrobe   M medicine cabinet   X washing machine
##     E desk     S shop shelf   P pharmacy shelf   V vending machine   L police locker
##     C tool crate   Q cardboard box   U trash can
##   Furniture you can't search:
##     B bed (head)   b bed (foot)   T table   Z sofa   O toilet   A bath

const TEMPLATES := {
	"house_small": {"weight": 34, "rows": [
		"##W##W###W#",
		"#RwB#AO#KF#",
		"#wwb#tM#tt#",
		"#www#tt#ttW",
		"##D###D##D#",
		"#Zwwwwwwww#",
		"WZwwwTwwwwW",
		"#QwwwwwwwU#",
		"####DD#####",
	]},
	"house_large": {"weight": 24, "rows": [
		"##W###W####W##",
		"#RwwB#Bw#KKKF#",
		"#wwwb#bw#tttt#",
		"#wwww#Rw#tttUW",
		"##D####D###D##",
		"#wwwwwwwwwwww#",
		"###D#####D####",
		"#ZZwwwww#tAOM#",
		"WwwwTwww#ttttW",
		"#Qwwwwww#ttXU#",
		"####DD########",
	]},
	"shop": {"weight": 12, "rows": [
		"############",
		"#SSSSSS#QCQ#",
		"#tttttt#ccc#",
		"#tSStSS#ccc#",
		"#tSStttDccc#",
		"#tSStSS#####",
		"#tttttttttV#",
		"WKKttttttttW",
		"####DDWWW###",
	]},
	"police": {"weight": 6, "rows": [
		"##W####W##W##",
		"#LLLL#EwwwwE#",
		"#cccc#wwwwww#",
		"#ccccDwwEwww#",
		"#LccC#wwwwwwW",
		"######wwwEww#",
		"#Ottt#wwwwww#",
		"#UtMtDwwwwwwW",
		"######wwQwww#",
		"#######DD####",
	]},
	"garage": {"weight": 12, "rows": [
		"##W####W##",
		"#CccccccC#",
		"#cccccccc#",
		"#QccccccQ#",
		"#cccccccc#",
		"Wcccccccc#",
		"#ccccccEc#",
		"##DDDDDD##",
	]},
	"clinic": {"weight": 8, "rows": [
		"##W##W##W##",
		"#PPPP#MttM#",
		"#tttt#tttt#",
		"#tPPtDtBtB#",
		"#tttt#tbtb#",
		"#tttt#ttttW",
		"#KKttt#####",
		"###DD######",
	]},
}

## Container furniture -> loot table key (see Loot.CONTAINERS)
const CONTAINER_CHARS := {
	"F": "fridge", "K": "cupboard", "R": "wardrobe", "M": "medicine", "X": "washer", "E": "desk",
	"S": "shelf", "P": "pharmacy", "V": "vending", "L": "locker", "C": "crate", "Q": "box", "U": "trash",
}
## Furniture you can't search -> drawn sprite
const FURNITURE_CHARS := {"B": "bed_head", "b": "bed_foot", "T": "table", "Z": "sofa", "O": "toilet", "A": "bath"}
## Floor under each character: 1 wood, 2 tile, 3 concrete
const FLOOR_OF := {
	"w": 1, "D": 1, "R": 1, "E": 1, "Q": 1, "B": 1, "b": 1, "T": 1, "Z": 1,
	"t": 2, "F": 2, "K": 2, "M": 2, "X": 2, "S": 2, "P": 2, "V": 2, "U": 2, "O": 2, "A": 2,
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
