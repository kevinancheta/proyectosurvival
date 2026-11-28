extends SceneTree
## Prueba la construcción estilo Rust: colocar de paja -> mejorar con martillo -> destruir.
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
	var C = b.Catalog
	_check("el jugador tiene constructor", b != null)
	_check("costos de paja del piso: 8 palos", C.cost("floor", 0) == {"Palo": 8})
	_check("costos del piso: madera, piedra, metal",
		C.cost("floor", 1) == {"Tronco": 7} and C.cost("floor", 2) == {"Piedra": 10} and C.cost("floor", 3) == {"Mineral": 6})

	player.global_position = Vector3(0.0, main.height_at(0.0, 0.0) + 0.5, 0.0)
	player.rotation = Vector3.ZERO
	player.head.rotation.x = -0.6
	player.equip("hammer")
	await physics_frame
	await physics_frame
	b.piece_index = 0
	_check("el piso apuntando al suelo es válido", b.compute()["valid"])

	# Sin palos no se puede colocar
	var notices := []
	b.notice.connect(func(t): notices.append(t))
	_check("sin palos no coloca", not b.try_place())
	_check("avisa qué falta", notices.size() == 1 and "8 Palo" in notices[0], str(notices))

	player.inventory.add("Palo", 10)
	_check("con palos coloca el piso", b.try_place())
	_check("se pagaron 8 palos", player.inventory.get_count("Palo") == 2)
	var floor_piece = b.pieces.values()[0]
	_check("nace de paja", floor_piece.tier == 0 and floor_piece.tier_name() == "Paja")
	_check("no se puede poner otro en la misma casilla", not b.try_place())

	# Mejoras con el martillo
	_check("sin troncos no mejora", floor_piece.try_upgrade(player) != "" and floor_piece.tier == 0)
	player.inventory.add("Tronco", 7)
	_check("mejora a madera", floor_piece.try_upgrade(player) == "" and floor_piece.tier == 1)
	_check("se pagaron 7 troncos", player.inventory.get_count("Tronco") == 0)
	player.inventory.add("Piedra", 10)
	_check("mejora a piedra", floor_piece.try_upgrade(player) == "" and floor_piece.tier == 2)
	player.inventory.add("Mineral", 6)
	_check("mejora a metal", floor_piece.try_upgrade(player) == "" and floor_piece.tier == 3)
	_check("en metal ya no mejora", floor_piece.try_upgrade(player) != "" and not floor_piece.can_upgrade())
	_check("el metal aguanta más", floor_piece.hp > 200.0, "hp=%.0f" % floor_piece.hp)

	# Aguanta el peso del jugador
	player.global_position = floor_piece.global_position + Vector3(0.0, 1.5, 0.0)
	player.velocity = Vector3.ZERO
	for i in 40:
		await physics_frame
	_check("el jugador se para sobre el piso", player.global_position.y > floor_piece.global_position.y - 0.05)

	# Todos los materiales se dibujan sin error
	var fx: float = floor_piece.global_position.x
	var fy: float = floor_piece.global_position.y
	var fz: float = floor_piece.global_position.z
	var made := 0
	for id in ["wall", "door", "roof", "palisade"]:
		for t in 4:
			var m = C.make_model(id, t)
			if m.get_child_count() > 0 and m.find_children("*", "MeshInstance3D", true, false).size() > 0:
				made += 1
			m.free()
	_check("16 modelos (4 piezas x 4 niveles)", made == 16)

	# Puerta
	var door = b.place_at("door", Transform3D(Basis.IDENTITY, Vector3(fx, fy, fz + 1.5)), "e:z:test:1", 0)
	door.interact(player)
	_check("la puerta se abre", door.door_open)
	door.try_upgrade(player)
	player.inventory.add("Tronco", 5)
	_check("la puerta mejorada sigue abierta", door.try_upgrade(player) == "" and door.door_open)
	door.interact(player)
	_check("la puerta se cierra", not door.door_open)

	# Cofre (sin niveles)
	var chest = b.place_at("chest", Transform3D(Basis.IDENTITY, Vector3(fx + 0.5, fy, fz - 0.5)), "", 0)
	_check("el cofre no se mejora", not chest.can_upgrade())
	player.inventory.add("Piedra", 2)
	chest.interact(player)
	_check("el cofre guarda todo", player.inventory.items.is_empty() and chest.store.size() >= 1)
	chest.interact(player)
	_check("el cofre lo devuelve", player.inventory.get_count("Piedra") >= 2 and chest.store.is_empty())

	# Destruir con hacha: el piso de metal aguanta; uno de paja cae en 2 hachazos
	var straw = b.place_at("wall", Transform3D(Basis.IDENTITY, Vector3(fx + 6.0, fy, fz)), "e:z:test:2", 0)
	var before := get_nodes_in_group("pickups").size()
	straw.take_hit(player.global_position, "axe")
	_check("la paja aguanta 1 hachazo", is_instance_valid(straw))
	straw.take_hit(player.global_position, "axe")
	await physics_frame
	await physics_frame
	_check("la paja cae al 2º hachazo", not is_instance_valid(straw))
	_check("soltó palos", get_nodes_in_group("pickups").size() == before + 4)
	for i in 5:
		floor_piece.take_hit(player.global_position, "axe")
	_check("el piso de metal sigue en pie tras 5 hachazos", not floor_piece.is_queued_for_deletion())

	# Recursos nuevos: arbustos, árboles finos y rocas con mineral
	var counts := {"bush": 0, "sapling": 0, "ore": 0, "tree_sticks": 0}
	var sample := {}
	for h in get_nodes_in_group("harvestables"):
		if h.kind == "bush":
			counts["bush"] += 1
			sample["bush"] = h
		elif h.kind == "tree" and h.item_drop == "Palo":
			counts["sapling"] += 1
			sample["sapling"] = h
		elif h.kind == "tree" and h.stick_drops > 0:
			counts["tree_sticks"] += 1
		elif h.kind == "rock" and h.ore_drops > 0:
			counts["ore"] += 1
			sample["ore"] = h
	_check("hay arbustos, árboles finos y rocas con mineral", counts["bush"] > 100 and counts["sapling"] > 20 and counts["ore"] > 10, str(counts))
	_check("los árboles normales dan palos", counts["tree_sticks"] > 100)
	var bush = sample["bush"]
	var n0 := get_nodes_in_group("pickups").size()
	bush.take_hit(player.global_position, "axe")
	await physics_frame
	_check("un arbusto suelta 2 palos de un golpe", get_nodes_in_group("pickups").size() == n0 + 2)
	var ore = sample["ore"]
	var n1 := get_nodes_in_group("pickups").size()
	for i in 12:
		if is_instance_valid(ore):
			ore.take_hit(player.global_position, "pickaxe")
	await physics_frame
	var items := {}
	for pk in get_nodes_in_group("pickups"):
		items[pk.item] = int(items.get(pk.item, 0)) + 1
	_check("la roca con mineral suelta mineral", items.get("Mineral", 0) == 2, str(items))

	print("TODO OK" if _fails == 0 else "HAY %d FALLAS" % _fails)
	quit(_fails)
