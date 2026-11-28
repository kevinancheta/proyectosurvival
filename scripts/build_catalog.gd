extends RefCounted
## Las piezas que se pueden construir, como en Rust: se colocan de PAJA y después se mejoran
## con el martillo a madera, piedra o metal. Cada nivel cuesta un material distinto.
## Medidas: la grilla es de 3 m. Un muro mide 3 m de largo y 2.6 m de alto sobre el piso.

const MeshBuilder := preload("res://scripts/mesh_builder.gd")
const MedievalFactory := preload("res://scripts/medieval_factory.gd")

const CELL := 3.0
const WALL_H := 2.6

const TIERS := ["Paja", "Madera", "Piedra", "Metal"]
const TIER_ITEM := ["Palo", "Tronco", "Piedra", "Mineral"]   # con qué se paga cada nivel
const TIER_HP := [0.5, 1.0, 2.5, 4.0]                        # cuánto aguanta cada nivel
const TIER_COST := [1.0, 0.8, 1.2, 0.7]                      # multiplicador del costo base

const LOG := Color(0.43, 0.30, 0.18)
const LOG_DARK := Color(0.33, 0.23, 0.14)
const PLANK := Color(0.52, 0.38, 0.23)
const ROOF := Color(0.40, 0.27, 0.17)
const STRAW_A := Color(0.76, 0.63, 0.30)
const STRAW_B := Color(0.66, 0.52, 0.24)
const ROPE := Color(0.30, 0.22, 0.12)
const STONE_A := Color(0.50, 0.48, 0.44)
const STONE_B := Color(0.44, 0.43, 0.41)
const SLATE := Color(0.32, 0.34, 0.38)
const METAL := Color(0.27, 0.29, 0.33)
const METAL_LIGHT := Color(0.42, 0.45, 0.50)

## Orden en el que se recorren con la rueda del mouse.
const ORDER := ["floor", "wall", "door", "roof", "palisade", "campfire", "chest"]

## snap: "cell" = va en una casilla de la grilla, "edge" = en el borde entre casillas,
## "free" = donde apuntes. units: costo base (piezas con niveles). cost: costo fijo (sin niveles).
const PIECES := {
	"floor":    {"name": "Piso",             "units": 8, "hp": 60.0, "snap": "cell"},
	"wall":     {"name": "Pared",            "units": 8, "hp": 60.0, "snap": "edge"},
	"door":     {"name": "Pared con puerta", "units": 6, "hp": 45.0, "snap": "edge"},
	"roof":     {"name": "Techo",            "units": 8, "hp": 40.0, "snap": "cell"},
	"palisade": {"name": "Empalizada",       "units": 6, "hp": 50.0, "snap": "edge"},
	"campfire": {"name": "Fogata",           "cost": {"Tronco": 2, "Piedra": 3}, "hp": 20.0, "snap": "free"},
	"chest":    {"name": "Cofre",            "cost": {"Tronco": 5},              "hp": 40.0, "snap": "free"},
}


static func is_tiered(id: String) -> bool:
	return PIECES[id].has("units")


## Cuánto cuesta tener la pieza en ese nivel (0 = paja ... 3 = metal).
static func cost(id: String, tier: int) -> Dictionary:
	if not is_tiered(id):
		return PIECES[id]["cost"]
	return {TIER_ITEM[tier]: int(ceil(float(PIECES[id]["units"]) * TIER_COST[tier]))}


static func max_hp(id: String, tier: int) -> float:
	return float(PIECES[id]["hp"]) * (TIER_HP[tier] if is_tiered(id) else 1.0)


static func cost_text(c: Dictionary) -> String:
	var parts := PackedStringArray()
	for item in c:
		parts.append("%d %s" % [c[item], item])
	return ", ".join(parts)


## Devuelve el modelo terminado. Siempre trae un nodo "Body" con las colisiones.
static func make_model(id: String, tier: int = 0) -> Node3D:
	match id:
		"floor": return _floor(tier)
		"wall": return _wall(false, tier)
		"door": return _wall(true, tier)
		"roof": return _roof(tier)
		"palisade": return _palisade(tier)
		"campfire":
			var model := MedievalFactory.make_campfire(5)
			_add_body(model, _cyl_shape(0.9, 0.7), Vector3(0.0, 0.35, 0.0))
			return model
	return _chest()


## Igual que el modelo pero sin fuego, luces ni colisiones: para el fantasma.
static func make_preview(id: String) -> Node3D:
	var model := make_model(id, 0)
	for n in model.find_children("*", "CPUParticles3D", true, false):
		n.queue_free()
	for n in model.find_children("*", "OmniLight3D", true, false):
		n.queue_free()
	for n in model.find_children("*", "StaticBody3D", true, false):
		n.get_parent().remove_child(n)
		n.queue_free()
	return model


# ------------------------------------------------------------ superficies

## Rellena un tramo de muro (de x0 a x1, de y0 a y1) con el material del nivel.
static func _surface(b, tier: int, x0: float, x1: float, y0: float, y1: float, seed_v: int = 0) -> void:
	var span := x1 - x0
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v + int(x0 * 10.0) + tier * 7
	match tier:
		0:
			# Palitos parados, atados con una soga.
			var n := maxi(int(span / 0.11), 1)
			for i in n:
				var x := x0 + (i + 0.5) * span / n
				var extra := rng.randf_range(-0.05, 0.12)
				b.cylinder(Transform3D(Basis.IDENTITY, Vector3(x, y0, rng.randf_range(-0.03, 0.03))),
					0.055, y1 - y0 + extra, 5, STRAW_A if i % 2 == 0 else STRAW_B, false)
			for f in [0.28, 0.68]:
				b.box(Transform3D(Basis.IDENTITY, Vector3((x0 + x1) * 0.5, y0 + (y1 - y0) * f, 0.0)),
					Vector3(span, 0.07, 0.2), ROPE, false)
		1:
			var y := y0
			while y < y1 - 0.1:
				b.cylinder(Transform3D(Basis(Vector3.BACK, -PI / 2.0), Vector3(x0, y, 0.0)),
					0.17, span, 7, LOG if int(y * 10.0) % 2 == 0 else LOG_DARK, false)
				y += 0.34
		2:
			var row := 0
			var y := y0
			while y < y1 - 0.05:
				var x := x0
				var w := 0.45 if row % 2 == 1 else 0.7
				while x < x1 - 0.01:
					var bw := minf(w, x1 - x)
					b.box(Transform3D(Basis.IDENTITY, Vector3(x + bw * 0.5, y + 0.17, 0.0)),
						Vector3(bw - 0.03, minf(0.31, y1 - y), 0.32), STONE_A if (int(x * 3.0) + row) % 2 == 0 else STONE_B, false)
					x += bw
					w = 0.7
				y += 0.34
				row += 1
		_:
			b.box(Transform3D(Basis.IDENTITY, Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, 0.0)),
				Vector3(span, y1 - y0, 0.2), METAL, false)
			var ribs := maxi(int(span / 0.5), 1)
			for i in ribs + 1:
				var x := x0 + i * span / ribs
				b.box(Transform3D(Basis.IDENTITY, Vector3(x, (y0 + y1) * 0.5, 0.0)),
					Vector3(0.07, y1 - y0, 0.27), METAL_LIGHT, false)
			for f in [0.3, 0.7]:
				b.box(Transform3D(Basis.IDENTITY, Vector3((x0 + x1) * 0.5, y0 + (y1 - y0) * f, 0.0)),
					Vector3(span, 0.07, 0.27), METAL_LIGHT, false)


static func _floor(tier: int) -> Node3D:
	var b := MeshBuilder.new(11 + tier)
	var cols := [STRAW_B, PLANK, STONE_B, METAL]
	var lines := [STRAW_A, LOG_DARK, Color(0.30, 0.30, 0.30), METAL_LIGHT]
	b.box(Transform3D(Basis.IDENTITY, Vector3(0.0, -0.25, 0.0)), Vector3(CELL, 0.5, CELL), cols[tier])
	for i in 5:
		var x := -1.2 + i * 0.6
		b.box(Transform3D(Basis.IDENTITY, Vector3(x, 0.005, 0.0)), Vector3(0.04, 0.02, CELL), lines[tier], false)
	if tier >= 2:
		for i in 5:
			var z := -1.2 + i * 0.6
			b.box(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.006, z)), Vector3(CELL, 0.02, 0.04), lines[tier], false)
	return b.build("Floor")


static func _wall(with_door: bool, tier: int) -> Node3D:
	var b := MeshBuilder.new(20 + tier + (4 if with_door else 0))
	var top := WALL_H
	if with_door:
		_surface(b, tier, -CELL * 0.5, -0.6, -0.6, top, 1)
		_surface(b, tier, 0.6, CELL * 0.5, -0.6, top, 2)
		_surface(b, tier, -0.6, 0.6, 2.05, top, 3)
		b.add_box_collider(Transform3D(Basis.IDENTITY, Vector3(-1.05, 0.7, 0.0)), Vector3(0.9, 2.6, 0.34))
		b.add_box_collider(Transform3D(Basis.IDENTITY, Vector3(1.05, 0.7, 0.0)), Vector3(0.9, 2.6, 0.34))
		b.add_box_collider(Transform3D(Basis.IDENTITY, Vector3(0.0, 2.3, 0.0)), Vector3(1.2, 0.8, 0.34))
	else:
		_surface(b, tier, -CELL * 0.5, CELL * 0.5, -0.6, top)
		b.add_box_collider(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.9, 0.0)), Vector3(CELL, 3.4, 0.34))
	var model := b.build("Door" if with_door else "Wall")
	if with_door:
		# La hoja gira sobre una bisagra a la izquierda del hueco.
		var leaf_cols := [STRAW_B, PLANK, LOG_DARK, METAL]
		var pivot := Node3D.new()
		pivot.name = "DoorPivot"
		pivot.position = Vector3(-0.58, 0.0, 0.0)
		var lb := MeshBuilder.new(14 + tier)
		lb.box(Transform3D(Basis.IDENTITY, Vector3(0.58, 1.0, 0.0)), Vector3(1.14, 2.0, 0.1), leaf_cols[tier])
		var band := METAL_LIGHT if tier >= 2 else LOG_DARK
		lb.box(Transform3D(Basis.IDENTITY, Vector3(0.58, 0.55, 0.0)), Vector3(1.14, 0.1, 0.14), band, false)
		lb.box(Transform3D(Basis.IDENTITY, Vector3(0.58, 1.55, 0.0)), Vector3(1.14, 0.1, 0.14), band, false)
		lb.box(Transform3D(Basis.IDENTITY, Vector3(1.0, 1.0, 0.07)), Vector3(0.08, 0.16, 0.06), MedievalFactory.GOLD, false)
		pivot.add_child(lb.build("Leaf"))
		model.add_child(pivot)
	return model


static func _roof(tier: int) -> Node3D:
	var b := MeshBuilder.new(30 + tier)
	var cols := [STRAW_A, ROOF, SLATE, METAL]
	var thick := 0.26 if tier == 0 else 0.16
	b.gable_roof(Transform3D.IDENTITY, CELL, CELL, 1.1, cols[tier], 0.3, thick)
	var tri := PackedVector2Array([Vector2(-CELL * 0.5, 0.0), Vector2(CELL * 0.5, 0.0), Vector2(0.0, 1.1)])
	var fill := [STRAW_B, LOG, STONE_B, METAL_LIGHT]
	for z in [-CELL * 0.5, CELL * 0.5]:
		b.extrude(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, z)), tri, 0.1, fill[tier])
	b.add_box_collider(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.5, 0.0)), Vector3(CELL, 1.0, CELL))
	return b.build("Roof")


static func _palisade(tier: int) -> Node3D:
	var b := MeshBuilder.new(40 + tier)
	var rng := RandomNumberGenerator.new()
	rng.seed = 16 + tier
	if tier == 0:
		for i in 22:
			var x := -1.45 + i * (2.9 / 21.0)
			b.cylinder(Transform3D(Basis.IDENTITY, Vector3(x, -0.6, rng.randf_range(-0.04, 0.04))),
				0.07, 3.0 + rng.randf_range(-0.2, 0.3), 5, STRAW_A if i % 2 == 0 else STRAW_B, false, 0.02)
		for f in [0.3, 0.65]:
			b.box(Transform3D(Basis.IDENTITY, Vector3(0.0, 3.0 * f - 0.6, 0.0)), Vector3(CELL, 0.07, 0.22), ROPE, false)
	elif tier == 1:
		for i in 7:
			var x := -1.2 + i * 0.4
			var h := 3.0 + rng.randf_range(-0.2, 0.35)
			b.cylinder(Transform3D(Basis.IDENTITY, Vector3(x, -0.6, 0.0)), 0.2, h, 7,
				LOG if i % 2 == 0 else LOG_DARK, false, 0.06)
	else:
		_surface(b, tier, -CELL * 0.5, CELL * 0.5, -0.6, 2.8)
		if tier == 3:
			for i in 7:
				b.cone(Transform3D(Basis.IDENTITY, Vector3(-1.2 + i * 0.4, 2.8, 0.0)), 0.1, 0.35, 4, METAL_LIGHT)
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
