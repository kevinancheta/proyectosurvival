extends Node
## Modo construcción: muestra el plano fantasma (verde = se puede, rojo = no) pegado a la grilla
## y coloca los planos. Los materiales se entregan después con el martillo.

const Catalog := preload("res://scripts/build_catalog.gd")
const PieceScript := preload("res://scripts/piece.gd")
const SettlementsScript := preload("res://scripts/settlements.gd")

signal info_changed(text: String)
signal notice(text: String)      # avisos tipo "Te faltan: 3 Palo"

const CELL := Catalog.CELL
const BUILD_REACH := 9.0
const MAX_SLOPE := 1.1      # desnivel máximo (m) bajo un piso

var player
var world                     # el nodo principal: tiene height_at(x, z)
var root: Node3D              # acá cuelgan las piezas
var active := false
var piece_index := 0
var rotation_steps := 0
var pieces: Dictionary = {}   # key -> Piece (solo pisos, bordes y techos)

var _ghost: Node3D
var _ghost_id := ""
var _ghost_mat_ok: StandardMaterial3D
var _ghost_mat_bad: StandardMaterial3D
var _current := {"valid": false}


func setup(p, w, container: Node3D) -> void:
	player = p
	world = w
	root = container
	_ghost_mat_ok = _make_ghost_mat(Color(0.3, 1.0, 0.4, 0.45))
	_ghost_mat_bad = _make_ghost_mat(Color(1.0, 0.25, 0.2, 0.45))


func _make_ghost_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	return m


func current_id() -> String:
	return Catalog.ORDER[piece_index]


func set_active(on: bool) -> void:
	active = on
	if not on and _ghost:
		_ghost.queue_free()
		_ghost = null
		_ghost_id = ""
	_emit_info()


func cycle(step: int) -> void:
	piece_index = (piece_index + step + Catalog.ORDER.size()) % Catalog.ORDER.size()
	_emit_info()


func rotate_piece() -> void:
	rotation_steps = (rotation_steps + 1) % 4


func _emit_info() -> void:
	if not active:
		info_changed.emit("")
		return
	var id := current_id()
	var how := "se coloca de paja; mejorala con clic derecho" if Catalog.is_tiered(id) else "se coloca al instante"
	info_changed.emit("%s  ·  cuesta %s  (%s)\nRueda / Q cambiar pieza  ·  R girar  ·  Clic izquierdo: colocar" % [
		Catalog.PIECES[id]["name"], Catalog.cost_text(Catalog.cost(id, 0)), how])


func _process(_delta: float) -> void:
	if not active or player == null:
		return
	_current = compute()
	_update_ghost()


# --------------------------------------------------------------- colocar

## Coloca la pieza donde está el fantasma, pagándola con la mochila. Devuelve true si lo logró.
func try_place() -> bool:
	if not active:
		return false
	_current = compute()
	if not _current["valid"]:
		return false
	var id := current_id()
	var c := Catalog.cost(id, 0)
	var lacking := PackedStringArray()
	for item in c:
		var have: int = player.inventory.get_count(item)
		if have < int(c[item]):
			lacking.append("%d %s" % [int(c[item]) - have, item])
	if not lacking.is_empty():
		notice.emit("Te faltan: " + ", ".join(lacking))
		return false
	for item in c:
		player.inventory.remove(item, int(c[item]))
	place_at(id, _current["xf"], _current["key"], 0)
	return true


## Pone una pieza ya hecha (lo usan try_place y las pruebas).
func place_at(id: String, xf: Transform3D, key: String, tier: int = 0) -> Node3D:
	var piece := PieceScript.new()
	piece.name = "Piece_" + id
	piece.key = key
	root.add_child(piece)
	piece.global_transform = xf
	piece.setup(id, tier)
	if key != "":
		pieces[key] = piece
	piece.destroyed.connect(_on_piece_destroyed)
	return piece


func _on_piece_destroyed(piece) -> void:
	if piece.key != "" and pieces.get(piece.key) == piece:
		pieces.erase(piece.key)


# ------------------------------------------------------------- cálculo

func _ground(x: float, z: float) -> float:
	return world.height_at(x, z)


func _cell_of(v: float) -> int:
	return int(floorf(v / CELL))


func _cell_center(cx: int, cz: int) -> Vector3:
	return Vector3((cx + 0.5) * CELL, 0.0, (cz + 0.5) * CELL)


func _floor_at(cx: int, cz: int):
	var p = pieces.get("f:%d:%d" % [cx, cz])
	return p if is_instance_valid(p) else null


func _corner_heights(c: Vector3) -> Vector2:
	var lo := 1e9
	var hi := -1e9
	for dx in [-1.5, 0.0, 1.5]:
		for dz in [-1.5, 0.0, 1.5]:
			var h := _ground(c.x + dx, c.z + dz)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	return Vector2(lo, hi)


## Mira hacia donde apunta el jugador y calcula dónde iría la pieza.
## Devuelve {"valid", "xf", "key"}.
func compute() -> Dictionary:
	var cam: Camera3D = player.camera
	var from := cam.global_position
	var to := from - cam.global_transform.basis.z * BUILD_REACH
	var query := PhysicsRayQueryParameters3D.create(from, to, 1, [player.get_rid()])
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {"valid": false, "xf": Transform3D(Basis.IDENTITY, to), "key": ""}
	var aim: Vector3 = hit["position"]
	var normal: Vector3 = hit["normal"]
	var id := current_id()
	match Catalog.PIECES[id]["snap"]:
		"cell":
			return _compute_cell(id, aim, normal)
		"edge":
			return _compute_edge(id, aim)
		_:
			return _compute_free(id, aim)


func _compute_cell(id: String, aim: Vector3, normal: Vector3) -> Dictionary:
	var p := aim
	if absf(normal.y) < 0.5:
		p += normal * 0.3   # apuntando al costado de algo: la casilla de al lado
	var cx := _cell_of(p.x)
	var cz := _cell_of(p.z)
	var c := _cell_center(cx, cz)
	var fkey := "f:%d:%d" % [cx, cz]
	if id == "floor" and _floor_at(cx, cz) != null:
		# Apuntando a un piso ya hecho: seguí por la casilla vecina más cercana a la mira.
		var d := Vector2(p.x - c.x, p.z - c.z)
		if absf(d.x) > absf(d.y):
			cx += 1 if d.x > 0.0 else -1
		else:
			cz += 1 if d.y > 0.0 else -1
		c = _cell_center(cx, cz)
		fkey = "f:%d:%d" % [cx, cz]

	var y := _surface_y(cx, cz, c)
	if id == "floor":
		var hs := _corner_heights(c)
		var ok := pieces.get(fkey) == null and hs.y - hs.x <= MAX_SLOPE \
			and _free_space(Vector3(c.x, y + 1.2, c.z), Vector3(2.5, 1.4, 2.5)) and not _in_settlement(c)
		return {"valid": ok, "xf": Transform3D(Basis.IDENTITY, Vector3(c.x, y, c.z)), "key": fkey if ok else ""}
	# techo: encima de las paredes
	var rkey := "r:%d:%d" % [cx, cz]
	var basis := Basis(Vector3.UP, rotation_steps * PI / 2.0)
	var ok2 := pieces.get(rkey) == null and not _in_settlement(c)
	return {"valid": ok2, "xf": Transform3D(basis, Vector3(c.x, y + Catalog.WALL_H, c.z)), "key": rkey if ok2 else ""}


## Altura del piso de esa casilla: la del piso hecho, o la del terreno más alto debajo.
func _surface_y(cx: int, cz: int, c: Vector3) -> float:
	var f = _floor_at(cx, cz)
	if f != null:
		return f.global_position.y
	for n in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nf = _floor_at(cx + n.x, cz + n.y)
		if nf != null:
			return nf.global_position.y
	return _corner_heights(c).y + 0.05


func _compute_edge(id: String, aim: Vector3) -> Dictionary:
	var ix := roundi(aim.x / CELL)
	var iz := roundi(aim.z / CELL)
	var dx := absf(aim.x - ix * CELL)
	var dz := absf(aim.z - iz * CELL)
	var center: Vector3
	var yaw: float
	var key: String
	var sides: Array
	if dx < dz:
		# El muro corre a lo largo de Z, sobre la línea x = ix * 3.
		var cz := _cell_of(aim.z)
		center = Vector3(ix * CELL, 0.0, (cz + 0.5) * CELL)
		yaw = PI / 2.0
		key = "e:x:%d:%d" % [ix, cz]
		sides = [Vector2i(ix - 1, cz), Vector2i(ix, cz)]
	else:
		var cx := _cell_of(aim.x)
		center = Vector3((cx + 0.5) * CELL, 0.0, iz * CELL)
		yaw = 0.0
		key = "e:z:%d:%d" % [cx, iz]
		sides = [Vector2i(cx, iz - 1), Vector2i(cx, iz)]
	var base := -1e9
	for s in sides:
		var f = _floor_at(s.x, s.y)
		if f != null:
			base = maxf(base, f.global_position.y)
	if base < -1e8:
		var along := Vector3(cos(yaw), 0.0, -sin(yaw)) * 1.5
		base = maxf(_ground(center.x, center.z), maxf(_ground(center.x + along.x, center.z + along.z),
			_ground(center.x - along.x, center.z - along.z)))
		if id == "palisade":
			base -= 0.15
	var ok := pieces.get(key) == null and not _in_settlement(center)
	var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(center.x, base, center.z))
	if ok:
		ok = _free_space((xf * Vector3(0.0, 1.5, 0.0)), Vector3(2.7, 1.5, 0.22), yaw)
	return {"valid": ok, "xf": xf, "key": key if ok else ""}


func _compute_free(id: String, aim: Vector3) -> Dictionary:
	var yaw: float = player.rotation.y + PI + rotation_steps * PI / 2.0
	yaw = roundf(yaw / (PI / 12.0)) * (PI / 12.0)
	var ok := not _in_settlement(aim) and _free_space(aim + Vector3(0.0, 0.8, 0.0), Vector3(1.2, 1.0, 1.2))
	return {"valid": ok, "xf": Transform3D(Basis(Vector3.UP, yaw), aim), "key": ""}


func _in_settlement(p: Vector3) -> bool:
	return SettlementsScript.near_structure(p.x, p.z, 1.0)


## Nada del mundo (árboles, rocas, casas) ocupa esa caja.
func _free_space(center: Vector3, size: Vector3, yaw: float = 0.0) -> bool:
	var shape := BoxShape3D.new()
	shape.size = size
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(Vector3.UP, yaw), center)
	q.collision_mask = 1
	q.exclude = [player.get_rid()]
	# Las otras piezas no estorban (las paredes se encuentran en las esquinas).
	for r in player.get_world_3d().direct_space_state.intersect_shape(q, 16):
		var c = r["collider"]
		if c != null and not c.has_meta("piece"):
			return false
	return true


# --------------------------------------------------------------- fantasma

func _update_ghost() -> void:
	var id := current_id()
	if _ghost == null or _ghost_id != id:
		if _ghost:
			_ghost.queue_free()
		_ghost = Catalog.make_preview(id)
		_ghost_id = id
		root.add_child(_ghost)
	var xf: Transform3D = _current["xf"]
	_ghost.visible = _current.has("key")
	_ghost.global_transform = xf
	var mat := _ghost_mat_ok if _current["valid"] else _ghost_mat_bad
	for mi in _ghost.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
