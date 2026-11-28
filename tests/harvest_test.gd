extends SceneTree
## Prueba automática de la recolección. Se corre sin abrir el editor:
##   godot --headless --path . -s res://tests/harvest_test.gd
## Escribe PASS o FAIL por cada chequeo y termina con código 0 si todo salió bien.

const ToolFactory := preload("res://scripts/tool_factory.gd")

var _fails := 0


func _check(name: String, ok: bool, extra: String = "") -> void:
	print(("PASS  " if ok else "FAIL  ") + name + ("  " + extra if extra != "" else ""))
	if not ok:
		_fails += 1


func _nearest(kind: String, from: Vector3):
	var best = null
	var best_d := 1e9
	for n in get_nodes_in_group("harvestables"):
		if n.kind != kind or n.is_queued_for_deletion():
			continue
		var d: float = n.global_position.distance_to(from)
		if d < best_d:
			best_d = d
			best = n
	return best


## Pone al jugador frente al objeto, a "dist" metros, mirándolo.
func _face(player, target, dist: float) -> void:
	var dir: Vector3 = (target.global_position - player.global_position)
	dir.y = 0.0
	dir = dir.normalized()
	var spot: Vector3 = target.global_position - dir * dist
	player.global_position = Vector3(spot.x, target.global_position.y + 1.0, spot.z)
	player.velocity = Vector3.ZERO
	player.look_at(Vector3(target.global_position.x, player.global_position.y, target.global_position.z))


func _hits(player, n: int) -> void:
	for i in n:
		player._apply_hit()
		await create_timer(0.1).timeout


func _live(group: String, item: String) -> Array:
	return get_nodes_in_group(group).filter(func(n): return n.item == item and not n.is_queued_for_deletion())


func _initialize() -> void:
	# ---- Los modelos de las herramientas
	_check("el hacha tiene silueta válida", Geometry2D.triangulate_polygon(ToolFactory._axe_profile()).size() == 15)
	_check("el pico tiene silueta válida", Geometry2D.triangulate_polygon(ToolFactory._pickaxe_profile()).size() == 24)

	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await create_timer(1.0).timeout

	var player = main.get_node("Player")
	var trees := get_nodes_in_group("harvestables").filter(func(n): return n.kind == "tree")
	var rocks := get_nodes_in_group("harvestables").filter(func(n): return n.kind == "rock")
	_check("hay árboles y rocas", trees.size() > 300 and rocks.size() > 100, "(%d árboles, %d rocas)" % [trees.size(), rocks.size()])
	_check("el jugador existe y está en el suelo", player.is_on_floor())
	_check("arranca con el hacha", player.current_tool == "axe")

	# ---- Herramientas: el cambio funciona
	var changed := []
	player.tool_changed.connect(func(t): changed.append(t))
	player.equip("pickaxe")
	_check("cambiar a pico", player.current_tool == "pickaxe" and changed == ["pickaxe"])
	player._cycle_tool(1)
	_check("la rueda pasa al martillo", player.current_tool == "hammer")
	player._cycle_tool(1)
	_check("la rueda rota entre herramientas", player.current_tool == "axe")

	# ---- Árbol con el pico: lento
	var tree = _nearest("tree", player.global_position)
	_face(player, tree, 2.4)
	await create_timer(0.6).timeout
	_check("con el hacha: texto normal", player._target_text == "Talar árbol", player._target_text)
	player.equip("pickaxe")
	await create_timer(0.2).timeout
	_check("con el pico: avisa que es lento", "lento" in player._target_text, player._target_text)
	await _hits(player, 6)
	_check("6 golpes de pico NO alcanzan para talar", is_instance_valid(tree) and not tree.is_queued_for_deletion() and tree.hp > 2.0, "(le queda %.1f de 6)" % tree.hp)

	# ---- Árbol con el hacha: rápido
	player.equip("axe")
	await _hits(player, 4)
	await create_timer(2.8).timeout   # la caída dura 1.4 s
	var logs := _live("pickups", "Tronco")
	_check("el árbol cayó y soltó troncos", logs.size() >= 2, "(%d troncos)" % logs.size())
	_check("el árbol ya no se puede talar", not is_instance_valid(tree) or tree.is_queued_for_deletion())

	# ---- Recoger troncos
	if logs.size() > 0:
		player.global_position = logs[0].global_position + Vector3(0, 1.0, 0)
		player.velocity = Vector3.ZERO
	await create_timer(2.0).timeout
	_check("recogió troncos en la mochila", player.inventory.get_count("Tronco") >= 1, "(%d)" % player.inventory.get_count("Tronco"))

	# ---- Roca con el hacha: lento
	var rock = _nearest("rock", player.global_position)
	var radius: float = rock.get_child(0).shape.radius
	_face(player, rock, radius + 1.2)
	await create_timer(0.6).timeout
	_check("roca con hacha: avisa que es lento", "lento" in player._target_text, player._target_text)
	await _hits(player, 4)
	_check("4 golpes de hacha NO rompen la roca", is_instance_valid(rock) and not rock.is_queued_for_deletion() and rock.hp > 1.0, "(le queda %.1f de 4)" % rock.hp)

	# ---- Roca con el pico: rápido, y el total de piedras es el mismo
	player.equip("pickaxe")
	await _hits(player, 3)
	await create_timer(1.5).timeout
	_check("la roca se rompió", not is_instance_valid(rock) or rock.is_queued_for_deletion())
	var total: int = _live("pickups", "Piedra").size() + player.inventory.get_count("Piedra")
	_check("rinde 6 piedras en total", total == 6, "(%d)" % total)

	print("RESULTADO: ", "TODO BIEN" if _fails == 0 else "%d FALLAS" % _fails)
	quit(_fails)
