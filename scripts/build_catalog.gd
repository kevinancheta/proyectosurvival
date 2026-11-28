extends RefCounted
## Las piezas que se pueden construir: qué cuestan, cuánto aguantan y cómo se ven.
## Medidas: la grilla es de 3 m. Un muro mide 3 m de largo y 2.6 m de alto sobre el piso.

const MeshBuilder := preload("res://scripts/mesh_builder.gd")
const MedievalFactory := preload("res://scripts/medieval_factory.gd")

const CELL := 3.0
const WALL_H := 2.6

const LOG := Color(0.43, 0.30, 0.18)
const LOG_DARK := Color(0.33, 0.23, 0.14)
const PLANK := Color(0.52, 0.38, 0.23)
const ROOF := Color(0.40, 0.27, 0.17)

## Orden en el que se recorren con la rueda del mouse.
const ORDER := ["floor", "wall", "door", "roof", "palisade", "campfire", "chest"]

## snap: "cell" = va en una casilla de la grilla, "edge" = en el borde entre casillas,
## "free" = donde apuntes.
const PIECES := {
	"floor":    {"name": "Piso",            "cost": {"Tronco": 4},                 "hp": 60.0, "snap": "cell"},
	"wall":     {"name": "Pared de troncos", "cost": {"Tronco": 4},                "hp": 60.0, "snap": "edge"},
	"door":     {"name": "Pared con puerta", "cost": {"Tronco": 5},                "hp": 45.0, "snap": "edge"},
	"roof":     {"name": "Techo",           "cost": {"Tronco": 4},                 "hp": 40.0, "snap": "cell"},
	"palisade": {"name": "Empalizada",      "cost": {"Tronco": 3},                 "hp": 50.0, "snap": "edge"},
	"campfire": {"name": "Fogata",          "cost": {"Tronco": 2, "Piedra": 3},    "hp": 20.0, "snap": "free"},
	"chest":    {"name": "Cofre",           "cost": {"Tronco": 5},                 "hp": 40.0, "snap": "free"},
}


static func cost_text(id: String) -> String:
	var parts := PackedStringArray()
	var cost: Dictionary = PIECES[id]["cost"]
	for item in cost:
		parts.append("%d %s" % [cost[item], item])
	return ", ".join(parts)


## Devuelve el modelo terminado. Siempre trae un nodo "Body" con las colisiones.
static func make_model(id: String) -> Node3D:
	var model: Node3D
	match id:
		"floor": model = _floor()
		"wall": model = _wall(false)
		"door": model = _wall(true)
		"roof": model = _roof()
		"palisade": model = _palisade()
		"campfire":
			model = MedievalFactory.make_campfire(5)
			_add_body(model, _cyl_shape(0.9, 0.7), Vector3(0.0, 0.35, 0.0))
		_:
			model = _chest()
	return model


## Igual que el modelo terminado pero sin fuego, luces ni colisiones: para el fantasma y el plano.
static func make_preview(id: String) -> Node3D:
	var model := make_model(id)
	for n in model.find_children("*", "CPUParticles3D", true, false):
		n.queue_free()
	for n in model.find_children("*", "OmniLight3D", true, false):
		n.queue_free()
	for n in model.find_children("*", "StaticBody3D", true, false):
		n.get_parent().remove_child(n)
		n.queue_free()
	return model


static func _log_along_x(b, x0: float, length: float, y: float, z: float = 0.0) -> void:
	var t := Transform3D(Basis(Vector3.BACK, -PI / 2.0), Vector3(x0, y, z))
	b.cylinder(t, 0.17, length, 7, LOG if int(y * 10.0) % 2 == 0 else LOG_DARK, false)


static func _floor() -> Node3D:
	var b := MeshBuilder.new(11)
	b.box(Transform3D(Basis.IDENTITY, Vector3(0.0, -0.25, 0.0)), Vector3(CELL, 0.5, CELL), PLANK)
	for i in 5:
		var x := -1.2 + i * 0.6
		b.box(Transform3D(Basis.IDENTITY, Vector3(x, 0.005, 0.0)), Vector3(0.04, 0.02, CELL), LOG_DARK, false)
	return b.build("Floor")


static func _wall(with_door: bool) -> Node3D:
	var b := MeshBuilder.new(12 if not with_door else 13)
	var y := -0.6
	while y < WALL_H - 0.1:
		if with_door and y < 2.05:
			_log_along_x(b, -CELL * 0.5, 0.9, y)
			_log_along_x(b, 0.6, 0.9, y)
		else:
			_log_along_x(b, -CELL * 0.5, CELL, y)
		y += 0.34
	if with_door:
		b.add_box_collider(Transform3D(Basis.IDENTITY, Vector3(-1.05, 0.7, 0.0)), Vector3(0.9, 2.6, 0.34))
		b.add_box_collider(Transform3D(Basis.IDENTITY, Vector3(1.05, 0.7, 0.0)), Vector3(0.9, 2.6, 0.34))
		b.add_box_collider(Transform3D(Basis.IDENTITY, Vector3(0.0, 2.3, 0.0)), Vector3(1.2, 0.8, 0.34))
	else:
		b.add_box_collider(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.9, 0.0)), Vector3(CELL, 3.4, 0.34))
	var model := b.build("Door" if with_door else "Wall")
	if with_door:
		# La hoja gira sobre una bisagra a la izquierda del hueco.
		var pivot := Node3D.new()
		pivot.name = "DoorPivot"
		pivot.position = Vector3(-0.58, 0.0, 0.0)
		var lb := MeshBuilder.new(14)
		lb.box(Transform3D(Basis.IDENTITY, Vector3(0.58, 1.0, 0.0)), Vector3(1.14, 2.0, 0.1), PLANK)
		lb.box(Transform3D(Basis.IDENTITY, Vector3(0.58, 0.55, 0.0)), Vector3(1.14, 0.1, 0.14), LOG_DARK, false)
		lb.box(Transform3D(Basis.IDENTITY, Vector3(0.58, 1.55, 0.0)), Vector3(1.14, 0.1, 0.14), LOG_DARK, false)
		lb.box(Transform3D(Basis.IDENTITY, Vector3(1.0, 1.0, 0.07)), Vector3(0.08, 0.16, 0.06), MedievalFactory.GOLD, false)
		pivot.add_child(lb.build("Leaf"))
		model.add_child(pivot)
	return model


static func _roof() -> Node3D:
	var b := MeshBuilder.new(15)
	b.gable_roof(Transform3D.IDENTITY, CELL, CELL, 1.1, ROOF, 0.3, 0.16)
	var tri := PackedVector2Array([Vector2(-CELL * 0.5, 0.0), Vector2(CELL * 0.5, 0.0), Vector2(0.0, 1.1)])
	for z in [-CELL * 0.5, CELL * 0.5]:
		b.extrude(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, z)), tri, 0.1, LOG)
	b.add_box_collider(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.5, 0.0)), Vector3(CELL, 1.0, CELL))
	return b.build("Roof")


static func _palisade() -> Node3D:
	var b := MeshBuilder.new(16)
	var rng := RandomNumberGenerator.new()
	rng.seed = 16
	for i in 7:
		var x := -1.2 + i * 0.4
		var h := 3.0 + rng.randf_range(-0.2, 0.35)
		b.cylinder(Transform3D(Basis.IDENTITY, Vector3(x, -0.6, 0.0)), 0.2, h, 7,
			LOG if i % 2 == 0 else LOG_DARK, false, 0.06)
	b.add_box_collider(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.9, 0.0)), Vector3(CELL, 3.2, 0.4))
	return b.build("Palisade")


static func _chest() -> Node3D:
	var b := MeshBuilder.new(17)
	b.box(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.3, 0.0)), Vector3(1.1, 0.6, 0.65), PLANK)
	b.box(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.66, 0.0)), Vector3(1.14, 0.14, 0.69), LOG, false)
	for s in [-0.4, 0.4]:
		b.box(Transform3D(Basis.IDENTITY, Vector3(s, 0.4, 0.0)), Vector3(0.1, 0.8, 0.72), MedievalFactory.SLATE, false)
	b.box(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.5, 0.35)), Vector3(0.14, 0.2, 0.05), MedievalFactory.GOLD, false)
	return b.build("Chest")


static func _cyl_shape(radius: float, height: float) -> Shape3D:
	var s := CylinderShape3D.new()
	s.radius = radius
	s.height = height
	return s


static func _add_body(model: Node3D, shape: Shape3D, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "Body"
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = pos
	body.add_child(cs)
	model.add_child(body)
