extends Node3D
## Una pieza construida por un jugador, como en Rust: se coloca de paja y con el martillo
## (clic derecho) se mejora a madera, piedra y metal. Con el hacha o el pico se destruye.

const Catalog := preload("res://scripts/build_catalog.gd")
const PickupScript := preload("res://scripts/pickup.gd")

signal destroyed(piece)

const DAMAGE := {"axe": 15.0, "pickaxe": 8.0}

var id := "floor"
var tier := 0                  # 0 paja, 1 madera, 2 piedra, 3 metal
var key := ""                  # casilla o borde que ocupa (lo usa el Builder)
var built := true
var hp := 1.0
var store: Dictionary = {}     # contenido, si es un cofre
var door_open := false

var _model: Node3D
var _tween: Tween
var _door_tween: Tween


func setup(piece_id: String, piece_tier: int = 0) -> void:
	id = piece_id
	tier = piece_tier
	hp = Catalog.max_hp(id, tier)
	_rebuild_model()


func tier_name() -> String:
	return Catalog.TIERS[tier] if Catalog.is_tiered(id) else ""


func can_upgrade() -> bool:
	return Catalog.is_tiered(id) and tier < Catalog.TIERS.size() - 1


func upgrade_cost() -> Dictionary:
	return Catalog.cost(id, tier + 1) if can_upgrade() else {}


func _rebuild_model() -> void:
	if _tween:
		_tween.kill()
	if _door_tween:
		_door_tween.kill()
	var was_open := door_open
	if _model:
		remove_child(_model)
		_model.queue_free()
	_model = Catalog.make_model(id, tier)
	add_child(_model)
	for body in _model.find_children("*", "StaticBody3D", true, false):
		body.set_meta("piece", self)
	if was_open:
		var pivot: Node3D = _model.get_node_or_null("DoorPivot")
		if pivot:
			pivot.rotation.y = -1.75


# --------------------------------------------------------- lo que ve el jugador

func get_prompt(tool_id: String = "axe") -> String:
	var pname: String = Catalog.PIECES[id]["name"]
	if Catalog.is_tiered(id):
		pname += " de " + tier_name().to_lower()
	var lines := PackedStringArray()
	if tool_id == "hammer":
		if can_upgrade():
			lines.append("@Clic derecho: mejorar %s a %s (%s)" % [
				pname, Catalog.TIERS[tier + 1].to_lower(), Catalog.cost_text(upgrade_cost())])
		elif Catalog.is_tiered(id):
			lines.append("@%s (nivel máximo)" % pname)
	elif tool_id == "axe" or tool_id == "pickaxe":
		lines.append("Destruir %s (%d%%)" % [pname, int(100.0 * hp / Catalog.max_hp(id, tier))])
	if id == "door":
		lines.append("@[E] %s la puerta" % ("Cerrar" if door_open else "Abrir"))
	elif id == "chest":
		lines.append("@[E] Guardar todo / sacar todo  (%s)" % _store_text())
	return "\n".join(lines)


func _store_text() -> String:
	if store.is_empty():
		return "vacío"
	var parts := PackedStringArray()
	for item in store:
		parts.append("%s ×%d" % [item, store[item]])
	return ", ".join(parts)


## Lo llama el jugador en cada golpe con hacha o pico.
func take_hit(_from_pos: Vector3, tool_id: String = "axe") -> void:
	if not DAMAGE.has(tool_id):
		return
	hp -= float(DAMAGE[tool_id])
	if hp <= 0.001:
		_break()
	else:
		_shake()


## Mejora la pieza al siguiente nivel pagando con la mochila. Devuelve "" si salió bien,
## o el motivo si no (para mostrarlo en pantalla).
func try_upgrade(player) -> String:
	if not can_upgrade():
		return "Ya está en el nivel máximo"
	var c := upgrade_cost()
	var lacking := PackedStringArray()
	for item in c:
		if player.inventory.get_count(item) < int(c[item]):
			lacking.append("%d %s" % [int(c[item]) - player.inventory.get_count(item), item])
	if not lacking.is_empty():
		return "Te faltan: " + ", ".join(lacking)
	for item in c:
		player.inventory.remove(item, int(c[item]))
	tier += 1
	hp = Catalog.max_hp(id, tier)
	_rebuild_model()
	_pulse()
	return ""


func _break() -> void:
	if _tween:
		_tween.kill()
	# Al romperse devuelve la mitad de lo que cuesta el nivel actual.
	var c := Catalog.cost(id, tier)
	for item in c:
		_drop(item, int(c[item]) / 2)
	for item in store:
		_drop(item, int(store[item]))
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
	_model.scale = Vector3(1.04, 1.04, 1.04)
	_tween = create_tween()
	_tween.tween_property(_model, "scale", Vector3.ONE, 0.18)


# --------------------------------------------------------------- interacción

func interact(player) -> void:
	if id == "door":
		door_open = not door_open
		var pivot: Node3D = _model.get_node_or_null("DoorPivot")
		if pivot:
			if _door_tween:
				_door_tween.kill()
			var tw := create_tween()
			_door_tween = tw
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
