extends StaticBody3D
## Un árbol o una roca que el jugador puede golpear.
## Los árboles y las rocas se dibujan todos juntos con MultiMesh (es mucho más rápido).
## Este nodo aporta la colisión y la lógica, y modifica su propia instancia del MultiMesh
## cuando lo golpean: lo sacude, lo achica o lo hace caer.

const PickupScript := preload("res://scripts/pickup.gd")

var kind: String = "tree"        # "tree" o "rock"
var max_hp: int = 6              # golpes que aguanta
var hp: int = 6
var drops: int = 3               # cuántos objetos suelta al terminar
var mm: MultiMesh                # el MultiMesh donde se dibuja
var index: int = 0               # qué instancia del MultiMesh es
var xf: Transform3D              # posición, giro y tamaño originales de la instancia
var mesh: Mesh                   # forma del árbol, para animar la caída
var material: Material
var tint: Color = Color.WHITE

var _busy := false               # ya se está cayendo o rompiendo
var _tween: Tween


func _ready() -> void:
	add_to_group("harvestables")
	hp = max_hp


## Texto que se muestra al apuntarle.
func get_prompt() -> String:
	return "Talar árbol" if kind == "tree" else "Picar roca"


## Lo llama el jugador en cada golpe. from_pos es dónde está el jugador.
func take_hit(from_pos: Vector3) -> void:
	if _busy:
		return
	hp -= 1
	var away := global_position - from_pos
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else Vector3.RIGHT
	if kind == "tree":
		if hp <= 0:
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
		_drop("Tronco", _ground_point(spot) + Vector3(0.0, 0.5, 0.0),
			Vector3(randf_range(-0.6, 0.6), 1.0, randf_range(-0.6, 0.6)))
	if is_instance_valid(falling):
		falling.queue_free()
	queue_free()


# -------------------------------------------------------------------- rocas

func _chip(away: Vector3) -> void:
	# Cada golpe suelta una piedra hacia el jugador, y la roca se achica.
	var toward_player := -away
	_drop("Piedra", global_position + toward_player * 1.4 + Vector3(0.0, 1.0, 0.0),
		toward_player * 1.5 + Vector3(randf_range(-0.5, 0.5), 2.5, randf_range(-0.5, 0.5)))

	if hp <= 0:
		_busy = true
		collision_layer = 0
		_hide_instance()
		for i in drops:
			_drop("Piedra", global_position + toward_player * 1.4 + Vector3(0.0, 1.2 + i * 0.3, 0.0),
				toward_player * 1.5 + Vector3(randf_range(-1.0, 1.0), 2.5, randf_range(-1.0, 1.0)))
		queue_free()
	else:
		var f := 0.55 + 0.45 * float(hp) / float(max_hp)
		mm.set_instance_transform(index, Transform3D(xf.basis * Basis.from_scale(Vector3.ONE * f), xf.origin))


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
