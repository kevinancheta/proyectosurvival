extends Node3D
## Una pieza construida por un jugador. Nace como "plano" (transparente, sin colisión para el
## jugador) y se completa entregándole los materiales con el martillo.
## Las piezas terminadas se pueden destruir con el hacha o el pico.

const Catalog := preload("res://scripts/build_catalog.gd")
const PickupScript := preload("res://scripts/pickup.gd")

signal destroyed(piece)

const LAYER_WORLD := 1
const LAYER_BLUEPRINT := 16    # solo lo ven los rayos, el jugador lo atraviesa
const DAMAGE := {"axe": 15.0, "pickaxe": 8.0}

var id := "floor"
var key := ""                  # casilla o borde que ocupa (lo usa el Builder)
var built := false
var delivered: Dictionary = {}
var hp := 1.0
var store: Dictionary = {}     # contenido, si es un cofre
var door_open := false

var _model: Node3D
var _tween: Tween


## Pone la pieza como plano o ya terminada.
func setup(piece_id: String, as_built: bool) -> void:
	id = piece_id
	hp = float(Catalog.PIECES[id]["hp"])
	if as_built:
		_complete()
	else:
		_show_blueprint()


func cost() -> Dictionary:
	return Catalog.PIECES[id]["cost"]


func missing(item: String) -> int:
	return int(cost().get(item, 0)) - int(delivered.get(item, 0))


func progress() -> float:
	var total := 0
	var done := 0
	for item in cost():
		total += int(cost()[item])
		done += int(delivered.get(item, 0))
	return float(done) / float(maxi(total, 1))


# ------------------------------------------------------------- apariencia

func _set_model(m: Node3D, layer: int) -> void:
	if _tween:
		_tween.kill()
	if _model:
		remove_child(_model)
		_model.queue_free()
	_model = m
	add_child(_model)
	for body in _model.find_children("*", "StaticBody3D", true, false):
		body.collision_layer = layer
		body.set_meta("piece", self)


func _show_blueprint() -> void:
	built = false
	_set_model(Catalog.make_model(id), LAYER_BLUEPRINT)
	# Sin fuego ni luz hasta que esté terminado.
	for n in _model.find_children("*", "CPUParticles3D", true, false):
		n.queue_free()
	for n in _model.find_children("*", "OmniLight3D", true, false):
		n.queue_free()
	_refresh_blueprint()


func _refresh_blueprint() -> void:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.45, 0.72, 1.0, 0.30 + 0.45 * progress())
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _complete() -> void:
	built = true
	_set_model(Catalog.make_model(id), LAYER_WORLD)


# --------------------------------------------------------- lo que ve el jugador

func get_prompt(tool_id: String = "axe") -> String:
	var pname: String = Catalog.PIECES[id]["name"]
	if not built:
		var parts := PackedStringArray()
		for item in cost():
			parts.append("%s %d/%d" % [item, int(delivered.get(item, 0)), int(cost()[item])])
		if tool_id == "hammer":
			return "Entregar materiales a: %s (%s)" % [pname, ", ".join(parts)]
		return "Deshacer plano de %s (devuelve lo entregado)" % pname
	var text := ""
	if tool_id == "axe" or tool_id == "pickaxe":
		text = "Destruir %s (%d%%)" % [pname, int(100.0 * hp / float(Catalog.PIECES[id]["hp"]))]
	if id == "door":
		text += "\n[E] %s la puerta" % ("Cerrar" if door_open else "Abrir")
	elif id == "chest":
		text += "\n[E] Guardar todo / sacar todo  (%s)" % _store_text()
	return text


func _store_text() -> String:
	if store.is_empty():
		return "vacío"
	var parts := PackedStringArray()
	for item in store:
		parts.append("%s ×%d" % [item, store[item]])
	return ", ".join(parts)


## Lo llama el jugador en cada golpe. El martillo entrega materiales; el resto daña.
func take_hit(from_pos: Vector3, tool_id: String = "axe") -> void:
	var player = get_tree().get_first_node_in_group("player")
	if not built:
		if tool_id == "hammer":
			_deliver(player)
		elif tool_id == "axe" or tool_id == "pickaxe":
			_refund_and_remove()
		return
	if not DAMAGE.has(tool_id):
		return
	hp -= float(DAMAGE[tool_id])
	_shake()
	if hp <= 0.001:
		_break()


func _deliver(player) -> void:
	if player == null:
		return
	for item in cost():
		if missing(item) > 0 and player.inventory.remove(item, 1):
			delivered[item] = int(delivered.get(item, 0)) + 1
			_pulse()
			if progress() >= 1.0:
				_complete()
			else:
				_refresh_blueprint()
			return


func _refund_and_remove() -> void:
	for item in delivered:
		_drop(item, int(delivered[item]))
	_remove()


func _break() -> void:
	# Al romperse devuelve la mitad de los materiales.
	for item in cost():
		_drop(item, int(cost()[item]) / 2)
	for item in store:
		_drop(item, int(store[item]))
	_remove()


func _remove() -> void:
	destroyed.emit(self)
	queue_free()


func _drop(item: String, amount: int) -> void:
	for i in amount:
		var p = PickupScript.new()
		p.item = item
		get_parent().add_child(p)
		p.global_position = global_position + Vector3(randf_range(-0.6, 0.6), 1.2 + i * 0.25, randf_range(-0.6, 0.6))
		p.apply_central_impulse(Vector3(randf_range(-1.0, 1.0), 2.0, randf_range(-1.0, 1.0)))


func _shake() -> void:
	if _tween:
		_tween.kill()
	_model.position = Vector3.ZERO
	_tween = create_tween()
	_tween.tween_property(_model, "position", Vector3(0.05, 0.0, 0.03), 0.04)
	_tween.tween_property(_model, "position", Vector3(-0.05, 0.0, -0.03), 0.06)
	_tween.tween_property(_model, "position", Vector3.ZERO, 0.05)


func _pulse() -> void:
	if _tween:
		_tween.kill()
	_model.scale = Vector3.ONE
	_tween = create_tween()
	_tween.tween_property(_model, "scale", Vector3(1.03, 1.03, 1.03), 0.06)
	_tween.tween_property(_model, "scale", Vector3.ONE, 0.08)


# --------------------------------------------------------------- interacción

func interact(player) -> void:
	if not built:
		return
	if id == "door":
		door_open = not door_open
		var pivot: Node3D = _model.get_node_or_null("DoorPivot")
		if pivot:
			var tw := create_tween()
			tw.tween_property(pivot, "rotation:y", -1.75 if door_open else 0.0, 0.25) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	elif id == "chest":
		if player.inventory.items.is_empty():
			for item in store.keys():
				player.collect(item, int(store[item]))
			store.clear()
		else:
			for item in player.inventory.items.keys():
				var n: int = player.inventory.get_count(item)
				player.inventory.remove(item, n)
				store[item] = int(store.get(item, 0)) + n
