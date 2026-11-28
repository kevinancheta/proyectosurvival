extends StaticBody3D
## Un árbol o una roca que el jugador puede golpear. El hacha rinde con los árboles y el pico con las rocas
## (ver POWER); con la herramienta equivocada hacen falta más golpes.
## Los árboles y las rocas se dibujan todos juntos con MultiMesh (es mucho más rápido).
## Este nodo aporta la colisión y la lógica, y modifica su propia instancia del MultiMesh
## cuando lo golpean: lo sacude, lo achica o lo hace caer.

const PickupScript := preload("res://scripts/pickup.gd")

const EPS := 0.001
## Cuánto avanza cada golpe según la herramienta (1.0 = la herramienta adecuada).
const POWER := {
	"axe": {"tree": 1.0, "rock": 0.4},
	"pickaxe": {"tree": 0.4, "rock": 1.0},
}

var kind: String = "tree"        # "tree", "rock" o "bush"
var item_drop: String = "Tronco" # lo que suelta un árbol al caer (los finos sueltan palos)
var stick_drops: int = 0         # palos extra al caer
var ore_drops: int = 0           # mineral de hierro extra al romper una roca
var label: String = ""           # texto al apuntarle (si está vacío se usa el de siempre)
var max_hp: float = 6.0          # golpes que aguanta con la herramienta adecuada
var hp: float = 6.0
var drops: int = 3               # cuántos objetos suelta al terminar
var mm: MultiMesh                # el MultiMesh donde se dibuja
var index: int = 0               # qué instancia del MultiMesh es
var xf: Transform3D              # posición, giro y tamaño originales de la instancia
var mesh: Mesh                   # forma del árbol, para animar la caída
var material: Material
var tint: Color = Color.WHITE

var _busy := false               # ya se está cayendo o rompiendo
var _tween: Tween
var _stones_dropped := 0         # piedras que ya soltó esta roca


func _ready() -> void:
	add_to_group("harvestables")
	hp = max_hp


func power_of(tool_id: String) -> float:
	if kind == "bush":
		return 1.0 if tool_id == "axe" or tool_id == "pickaxe" else 0.0
	if not POWER.has(tool_id):
		return 0.0   # el martillo no corta nada
	return float(POWER[tool_id][kind])


## Texto que se muestra al apuntarle, según la herramienta que llevás.
func get_prompt(tool_id: String = "axe") -> String:
	if kind == "bush":
		return label if label != "" else "Cortar arbusto (palos)"
	var text := "Talar árbol" if kind == "tree" else "Picar roca"
	if label != "":
		text = label
	if power_of(tool_id) < 1.0 and kind != "bush":
		text += " (lento, mejor con " + ("el hacha" if kind == "tree" else "el pico") + ")"
	return text


## Lo llama el jugador en cada golpe. from_pos es dónde está el jugador.
func take_hit(from_pos: Vector3, tool_id: String = "axe") -> void:
	if _busy or power_of(tool_id) <= 0.0:
		return
	hp -= power_of(tool_id)
	var away := global_position - from_pos
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else Vector3.RIGHT
	if kind == "bush":
		_cut_bush()
	elif kind == "tree":
		if hp <= EPS:
			_fell(away)
		else:
			_wobble(away)
	else:
		_chip(away)


# ------------------------------------------------------------------ árboles

func _wobble(away: Vector3) -> void:
	var axis := Vector3.UP.cross(away).normalized()
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_set_wobble.bind(axis), 0.0, 1.0, 0.35)


func _set_wobble(t: float, axis: Vector3) -> void:
	var angle := sin(t * PI * 5.0) * (1.0 - t) * 0.045
	mm.set_instance_transform(index, Transform3D(Basis(axis, angle) * xf.basis, xf.origin))


func _fell(away: Vector3) -> void:
	_busy = true
	collision_layer = 0
	if _tween:
		_tween.kill()
	_hide_instance()

	var parent := get_parent()
	var s := xf.basis.get_scale().x

	# Queda el tocón
	var stump := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.42
	cyl.bottom_radius = 0.55
	cyl.height = 0.6
	cyl.radial_segments = 7
	cyl.rings = 1
	stump.mesh = cyl
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.30, 0.20, 0.12)
	smat.roughness = 1.0
	stump.material_override = smat
	parent.add_child(stump)
	stump.global_position = xf.origin + Vector3(0.0, 0.25 * s, 0.0)
	stump.scale = Vector3(s, s, s)

	# Copia del árbol que se cae
	var falling := MeshInstance3D.new()
	falling.mesh = mesh
	var fmat = material.duplicate() if material else null
	if fmat is StandardMaterial3D:
		fmat.albedo_color = tint
	falling.material_override = fmat
	parent.add_child(falling)
	falling.global_transform = xf

	var axis := Vector3.UP.cross(away).normalized()
	_tween = create_tween()
	_tween.tween_method(_set_fall.bind(falling, axis), 0.0, 1.0, 1.4) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_callback(_finish_fall.bind(falling, away))


func _set_fall(t: float, node: Node3D, axis: Vector3) -> void:
	if not is_instance_valid(node):
		return
	node.global_transform = Transform3D(Basis(axis, t * 1.5) * xf.basis, xf.origin)


func _finish_fall(falling: Node3D, away: Vector3) -> void:
	var s := xf.basis.get_scale().x
	for i in drops:
		var spot := xf.origin + away * (1.6 + i * 1.5) * s
		_drop(item_drop, _ground_point(spot) + Vector3(0.0, 0.5, 0.0),
			Vector3(randf_range(-0.6, 0.6), 1.0, randf_range(-0.6, 0.6)))
	for i in stick_drops:
		var spot2 := xf.origin + away * (0.8 + i * 0.7) * s + Vector3(randf_range(-0.8, 0.8), 0.0, randf_range(-0.8, 0.8))
		_drop("Palo", _ground_point(spot2) + Vector3(0.0, 0.5, 0.0),
			Vector3(randf_range(-0.6, 0.6), 1.0, randf_range(-0.6, 0.6)))
	if is_instance_valid(falling):
		falling.queue_free()
	queue_free()


# -------------------------------------------------------------------- rocas

func _chip(away: Vector3) -> void:
	# La roca suelta piedras a medida que se rompe, hacia el jugador. El total es el mismo
	# con cualquier herramienta: con la equivocada solo hacen falta más golpes.
	var toward_player := -away
	var broken := hp <= EPS
	var total := int(max_hp) + drops
	var owed := total if broken else int(clampf((max_hp - hp) / max_hp, 0.0, 1.0) * total)
	for i in owed - _stones_dropped:
		_drop("Piedra", global_position + toward_player * 1.4 + Vector3(0.0, 1.0 + i * 0.3, 0.0),
			toward_player * 1.5 + Vector3(randf_range(-0.7, 0.7), 2.5, randf_range(-0.7, 0.7)))
	_stones_dropped = owed

	if broken:
		for i in ore_drops:
			_drop("Mineral", global_position + toward_player * 1.2 + Vector3(0.0, 1.2 + i * 0.3, 0.0),
				toward_player * 1.2 + Vector3(randf_range(-0.7, 0.7), 2.5, randf_range(-0.7, 0.7)))
		_busy = true
		collision_layer = 0
		_hide_instance()
		queue_free()
	else:
		var f := 0.55 + 0.45 * hp / max_hp
		mm.set_instance_transform(index, Transform3D(xf.basis * Basis.from_scale(Vector3.ONE * f), xf.origin))


# ----------------------------------------------------------------- arbustos

func _cut_bush() -> void:
	_busy = true
	collision_layer = 0
	_hide_instance()
	for i in drops:
		_drop("Palo", global_position + Vector3(randf_range(-0.5, 0.5), 0.8 + i * 0.2, randf_range(-0.5, 0.5)),
			Vector3(randf_range(-1.0, 1.0), 2.0, randf_range(-1.0, 1.0)))
	queue_free()


# ------------------------------------------------------------------- común

func _hide_instance() -> void:
	mm.set_instance_transform(index, Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), xf.origin))


## Baja desde arriba hasta encontrar el suelo, para no soltar nada adentro de una colina.
func _ground_point(p: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(p + Vector3(0.0, 12.0, 0.0), p - Vector3(0.0, 12.0, 0.0), 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit["position"] if not hit.is_empty() else p


func _drop(item: String, pos: Vector3, impulse: Vector3) -> void:
	var p = PickupScript.new()
	p.item = item
	get_parent().add_child(p)
	p.global_position = pos
	p.apply_central_impulse(impulse)
