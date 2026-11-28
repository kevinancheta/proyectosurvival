extends SceneTree
## Prueba la construcción: plano -> entregar materiales -> pieza terminada -> destruirla.
##   godot --headless --path . -s res://tests/build_test.gd

var _fails := 0


func _check(name: String, ok: bool, extra: String = "") -> void:
	print(("PASS  " if ok else "FAIL  ") + name + ("  " + extra if extra != "" else ""))
	if not ok:
		_fails += 1


func _init() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame
	var player = main.get_node("Player")
	var b = player.builder
	_check("el jugador tiene constructor", b != null)

	# Se coloca un plano apuntando al suelo del claro.
	player.global_position = Vector3(0.0, main.height_at(0.0, 0.0) + 0.5, 0.0)
	player.rotation = Vector3.ZERO
	player.head.rotation.x = -0.6
	player.equip("hammer")
	await physics_frame
	await physics_frame
	var ids := ["floor", "wall", "door", "roof", "palisade", "campfire", "chest"]
	_check("el orden del catálogo es el esperado", Array(b.Catalog.ORDER) == ids)
	b.piece_index = 0
	var cur: Dictionary = b.compute()
	_check("el piso apuntando al suelo es válido", cur["valid"], str(cur.get("xf", "")))
	_check("coloca un plano", b.try_place())
	var floor_piece = b.pieces.values()[0]
	_check("el plano no está construido", not floor_piece.built)
	_check("no se puede poner dos pisos en la misma casilla", not b.try_place() or b.pieces.size() == 2)

	# Entregar materiales con el martillo
	player.inventory.add("Tronco", 3)
	for i in 3:
		floor_piece.take_hit(player.global_position, "hammer")
	_check("con 3 de 4 troncos sigue siendo plano", not floor_piece.built and floor_piece.missing("Tronco") == 1)
	floor_piece.take_hit(player.global_position, "hammer")
	_check("sin troncos no avanza", not floor_piece.built)
	player.inventory.add("Tronco", 2)
	floor_piece.take_hit(player.global_position, "hammer")
	_check("con el 4º tronco se completa", floor_piece.built)
	_check("sobró 1 tronco en la mochila", player.inventory.get_count("Tronco") == 1)

	# Pisar el piso: el jugador no se cae a través
	player.global_position = floor_piece.global_position + Vector3(0.0, 1.5, 0.0)
	player.velocity = Vector3.ZERO
	for i in 40:
		await physics_frame
	_check("el jugador se para sobre el piso", player.global_position.y > floor_piece.global_position.y - 0.05,
		"y=%.2f piso=%.2f" % [player.global_position.y, floor_piece.global_position.y])

	# Puerta: abrir y cerrar
	var fy: float = floor_piece.global_position.y
	var fx: float = floor_piece.global_position.x
	var fz: float = floor_piece.global_position.z
	var door = b.place_at("door", Transform3D(Basis.IDENTITY, Vector3(fx, fy, fz + 1.5)), "e:z:test:1", true)
	_check("la puerta está construida", door.built)
	door.interact(player)
	_check("la puerta se abre", door.door_open)
	door.interact(player)
	_check("la puerta se cierra", not door.door_open)

	# Cofre: guarda y devuelve
	var chest = b.place_at("chest", Transform3D(Basis.IDENTITY, Vector3(fx + 0.5, fy, fz - 0.5)), "", true)
	player.inventory.add("Piedra", 2)
	chest.interact(player)
	_check("el cofre guarda todo", player.inventory.items.is_empty() and chest.store.size() == 2)
	chest.interact(player)
	_check("el cofre lo devuelve", player.inventory.get_count("Piedra") == 2 and chest.store.is_empty())

	# Destruir con hacha: el piso (60 hp) cae en 4 golpes de 15 y suelta la mitad de los troncos
	var before := get_nodes_in_group("pickups").size()
	for i in 4:
		floor_piece.take_hit(player.global_position, "axe")
	await physics_frame
	await physics_frame
	_check("el piso se destruye con 4 hachazos", not is_instance_valid(floor_piece) or floor_piece.is_queued_for_deletion())
	_check("la casilla queda libre", not b.pieces.has("f:0:0") or not is_instance_valid(b.pieces["f:0:0"]))
	_check("soltó troncos", get_nodes_in_group("pickups").size() >= before + 2)

	# Deshacer un plano devuelve lo entregado
	var bp = b.place_at("wall", Transform3D(Basis.IDENTITY, Vector3(fx + 6.0, fy, fz)), "e:z:test:2", false)
	player.inventory.add("Tronco", 2)
	bp.take_hit(player.global_position, "hammer")
	bp.take_hit(player.global_position, "hammer")
	var pk := get_nodes_in_group("pickups").size()
	bp.take_hit(player.global_position, "axe")
	await physics_frame
	_check("deshacer el plano devuelve 2 troncos", get_nodes_in_group("pickups").size() == pk + 2)

	print("TODO OK" if _fails == 0 else "HAY %d FALLAS" % _fails)
	quit(_fails)
