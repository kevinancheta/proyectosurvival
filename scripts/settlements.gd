extends RefCounted
## Dónde van la aldea, el castillo, los caminos y las torres de vigilancia, y cómo se arman.
## Las posiciones están en metros, con el centro del mapa en (0, 0). El eje Z de arriba a abajo
## es la segunda coordenada de cada Vector2.

const MedievalFactory := preload("res://scripts/medieval_factory.gd")

const VILLAGE := Vector2(70.0, 35.0)
const CASTLE := Vector2(125.0, -130.0)

## Zonas que se aplanan: r = radio plano, blend = qué tan suave se mezcla con el terreno,
## lift = cuánto se levanta (el castillo está sobre una loma).
const SITES := [
	{"pos": VILLAGE, "r": 40.0, "blend": 28.0, "lift": 0.0},
	{"pos": CASTLE, "r": 46.0, "blend": 34.0, "lift": 6.0},
]

## Camino de tierra: del claro del jugador a la aldea, y de la aldea a la puerta del castillo.
const ROAD := [
	Vector2(0.0, 0.0), Vector2(30.0, 12.0), Vector2(55.0, 28.0), Vector2(70.0, 35.0),
	Vector2(85.0, 10.0), Vector2(100.0, -30.0), Vector2(115.0, -70.0), Vector2(125.0, -105.0),
	Vector2(125.0, -113.0),
]

## Puestos de vigilancia aislados.
const OUTPOSTS := [Vector2(-95.0, -70.0), Vector2(-140.0, 80.0), Vector2(40.0, -150.0)]

## Círculos ocupados por construcciones: Vector3(x, z, radio). Se llena en build().
static var _footprints: Array = []


# ------------------------------------------------------------- consultas

static func road_distance(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var best := 1e9
	for i in ROAD.size() - 1:
		var a: Vector2 = ROAD[i]
		var b: Vector2 = ROAD[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


static func in_site(x: float, z: float, margin: float = 0.0) -> bool:
	var p := Vector2(x, z)
	for s in SITES:
		var c: Vector2 = s["pos"]
		if p.distance_to(c) < float(s["r"]) + margin:
			return true
	return false


static func near_structure(x: float, z: float, margin: float = 0.0) -> bool:
	for f in _footprints:
		var fp: Vector3 = f
		if Vector2(x, z).distance_to(Vector2(fp.x, fp.y)) < fp.z + margin:
			return true
	return false


## Para árboles y rocas: no van sobre las zonas aplanadas, los caminos ni los puestos de vigilancia.
static func blocked(x: float, z: float, margin: float = 0.0) -> bool:
	if in_site(x, z, margin) or road_distance(x, z) < 3.5 + margin * 0.3:
		return true
	for o in OUTPOSTS:
		var op: Vector2 = o
		if Vector2(x, z).distance_to(op) < 12.0 + margin:
			return true
	return false


# ---------------------------------------------------------------- armado

## Arma todo y devuelve {"houses": [Node3D], "castle": Node3D, "village": Node3D, "outposts": [Node3D]}.
static func build(world: Node3D, parent: Node3D) -> Dictionary:
	_footprints.clear()
	var info := {"houses": [], "castle": null, "village": null, "outposts": []}
	var root := Node3D.new()
	root.name = "Settlements"
	parent.add_child(root)

	# ---------------------------------------------------------- aldea
	var vy: float = world.height_at(VILLAGE.x, VILLAGE.y)
	var village := Node3D.new()
	village.name = "Village"
	village.position = Vector3(VILLAGE.x, vy, VILLAGE.y)
	root.add_child(village)
	info["village"] = village
	_footprints.append(Vector3(VILLAGE.x, VILLAGE.y, 2.5))
	_place(village, MedievalFactory.make_well(), Vector3.ZERO)
	_place(village, MedievalFactory.make_campfire(3), Vector3(5.0, 0.0, 5.5))
	_footprints.append(Vector3(VILLAGE.x + 5.0, VILLAGE.y + 5.5, 1.8))
	_place(village, MedievalFactory.make_stall(1), Vector3(-8.0, 0.0, 7.0), atan2(8.0, -7.0))
	_place(village, MedievalFactory.make_stall(2), Vector3(9.0, 0.0, -8.0), atan2(-9.0, 8.0))
	_footprints.append(Vector3(VILLAGE.x - 8.0, VILLAGE.y + 7.0, 3.0))
	_footprints.append(Vector3(VILLAGE.x + 9.0, VILLAGE.y - 8.0, 3.0))
	for i in 3:
		_place(village, MedievalFactory.make_barrel(20 + i), Vector3(-2.0 + i * 0.95, 0.0, -2.8))
	_place(village, MedievalFactory.make_hay(4), Vector3(-5.0, 0.0, -4.0), 0.5)

	# Casas: [x, z, ancho, fondo, con piso de arriba]. Todas miran hacia el pozo.
	var houses := [
		[-13.0, -17.0, 6.5, 5.0, false],
		[-4.0, -25.0, 7.0, 5.5, true],
		[22.0, -12.0, 8.0, 6.0, true],
		[25.0, 4.0, 6.0, 4.8, false],
		[16.0, 20.0, 6.5, 5.2, false],
		[-3.0, 26.0, 7.0, 5.5, true],
		[-14.0, 15.0, 6.0, 5.0, false],
	]
	for i in houses.size():
		var h: Array = houses[i]
		var hx: float = h[0]
		var hz: float = h[1]
		var hw: float = h[2]
		var hd: float = h[3]
		var house := MedievalFactory.make_house(100 + i, hw, hd, h[4])
		_place(village, house, Vector3(hx, 0.0, hz), atan2(-hx, -hz))
		_footprints.append(Vector3(VILLAGE.x + hx, VILLAGE.y + hz, maxf(hw, hd) * 0.5 + 3.5))
		info["houses"].append(house)
		# Barril y cajas del lado contrario a la puerta
		var side := -signf(float(house.get_meta("door_x"))) if absf(float(house.get_meta("door_x"))) > 0.2 else 1.0
		var lx: float = side * (hw * 0.5 - 0.7)
		var lz := hd * 0.5 + 0.9
		_place(village, MedievalFactory.make_barrel(40 + i), house.transform * Vector3(lx, 0.0, lz))
		_place(village, MedievalFactory.make_crate(50 + i), house.transform * Vector3(lx - side * 1.0, 0.0, lz + 0.2), 0.4 * i)

	# --------------------------------------------------------- castillo
	var cy: float = world.height_at(CASTLE.x, CASTLE.y)
	var castle := MedievalFactory.make_castle(7)
	castle.position = Vector3(CASTLE.x, cy, CASTLE.y)
	root.add_child(castle)
	info["castle"] = castle
	_footprints.append(Vector3(CASTLE.x, CASTLE.y, 44.0))

	# ------------------------------------------------- puestos de vigilancia
	for i in OUTPOSTS.size():
		var o: Vector2 = OUTPOSTS[i]
		var oy: float = world.height_at(o.x, o.y)
		var camp := Node3D.new()
		camp.name = "Outpost%d" % i
		camp.position = Vector3(o.x, oy, o.y)
		root.add_child(camp)
		var tower := MedievalFactory.make_tower(200 + i, 3.0, 12.0, MedievalFactory.RED if i % 2 == 0 else MedievalFactory.SLATE)
		_place(camp, tower, Vector3.ZERO)
		_place(camp, MedievalFactory.make_campfire(60 + i), _on_ground(world, o, Vector2(6.0, 4.0)))
		_place(camp, MedievalFactory.make_crate(70 + i), _on_ground(world, o, Vector2(5.0, -4.5)), 0.5)
		_place(camp, MedievalFactory.make_barrel(80 + i), _on_ground(world, o, Vector2(6.2, -3.6)))
		var pal := MedievalFactory.make_palisade(8.0, 90 + i)
		_place(camp, pal, _on_ground(world, o, Vector2(0.0, 8.0)))
		_footprints.append(Vector3(o.x, o.y, 9.0))
		info["outposts"].append(camp)
	return info


static func _place(parent: Node3D, node: Node3D, pos: Vector3, yaw: float = 0.0) -> void:
	node.position = pos
	node.rotation.y = yaw
	parent.add_child(node)


## Posición local (respecto de "center") puesta sobre el terreno.
static func _on_ground(world: Node3D, center: Vector2, offset: Vector2) -> Vector3:
	var gy: float = world.height_at(center.x + offset.x, center.y + offset.y) - world.height_at(center.x, center.y)
	return Vector3(offset.x, gy, offset.y)
