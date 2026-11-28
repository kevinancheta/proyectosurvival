extends SceneTree
## Prueba automática de la recolección. Se corre sin abrir el editor:
##   godot --headless --path . -s tests/harvest_test.gd
## Escribe PASS o FAIL por cada chequeo y termina con código 0 si todo salió bien.

var _fails := 0


func _check(name: String, ok: bool, extra: String = "") -> void:
	print(("PASS  " if ok else "FAIL  ") + name + ("  " + extra if extra != "" else ""))
	if not ok:
		_fails += 1


func _nearest(group: String, kind: String, from: Vector3):
	var best = null
	var best_d := 1e9
	for n in get_nodes_in_group(group):
		if n.kind != kind:
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


func _initialize() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await create_timer(1.0).timeout

	var player = main.get_node("Player")
	var trees := get_nodes_in_group("harvestables").filter(func(n): return n.kind == "tree")
	var rocks := get_nodes_in_group("harvestables").filter(func(n): return n.kind == "rock")
	_check("hay árboles y rocas", trees.size() > 300 and rocks.size() > 100, "(%d árboles, %d rocas)" % [trees.size(), rocks.size()])
	_check("el jugador existe y está en el suelo", player.is_on_floor())

	# ---- Talar un árbol
	var tree = _nearest("harvestables", "tree", player.global_position)
	_face(player, tree, 2.4)
	await create_timer(0.6).timeout
	var seen := []
	player.target_changed.connect(func(t): seen.append(t))
	await create_timer(0.2).timeout
	_check("al apuntar sale el texto del árbol", "Talar árbol" in seen or player._target_text == "Talar árbol", str(player._target_text))

	for i in 6:
		player._apply_hit()
		await create_timer(0.15).timeout
	await create_timer(2.8).timeout   # la caída dura 1.4 s
	var logs := get_nodes_in_group("pickups").filter(func(n): return n.item == "Tronco")
	_check("el árbol cayó y soltó troncos", logs.size() >= 2, "(%d troncos)" % logs.size())
	_check("el árbol ya no existe como talable", not is_instance_valid(tree) or tree.is_queued_for_deletion())

	# ---- Recoger troncos
	if logs.size() > 0:
		player.global_position = logs[0].global_position + Vector3(0, 1.0, 0)
		player.velocity = Vector3.ZERO
	await create_timer(2.0).timeout
	_check("recogió troncos en la mochila", player.inventory.get_count("Tronco") >= 1, "(%d)" % player.inventory.get_count("Tronco"))

	# ---- Picar una roca
	var rock = _nearest("harvestables", "rock", player.global_position)
	_face(player, rock, 2.0 + 0.0)
	await create_timer(0.6).timeout
	for i in 4:
		player._apply_hit()
		await create_timer(0.15).timeout
	await create_timer(0.5).timeout
	var stones := get_nodes_in_group("pickups").filter(func(n): return n.item == "Piedra")
	var have: int = player.inventory.get_count("Piedra")
	_check("la roca soltó piedras", stones.size() + have >= 4, "(%d sueltas, %d en mochila)" % [stones.size(), have])
	_check("la roca se rompió", not is_instance_valid(rock) or rock.is_queued_for_deletion())

	print("RESULTADO: ", "TODO BIEN" if _fails == 0 else "%d FALLAS" % _fails)
	quit(_fails)
