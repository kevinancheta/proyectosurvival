extends SceneTree
## Prueba que se puede entrar a una casa por la puerta y cruzar el portón del castillo.
##   godot --headless --path . -s res://tests/structures_test.gd

var _fails := 0


func _check(name: String, ok: bool, extra: String = "") -> void:
	print(("PASS  " if ok else "FAIL  ") + name + ("  " + extra if extra != "" else ""))
	if not ok:
		_fails += 1


## Camina desde "start" hacia "goal" (en el plano) con la tecla de avanzar, hasta llegar o agotar el tiempo.
func _walk(player, start: Vector3, goal: Vector3, secs: float) -> float:
	player.global_position = start + Vector3(0, 1.0, 0)
	player.velocity = Vector3.ZERO
	player.look_at(Vector3(goal.x, player.global_position.y, goal.z))
	Input.action_press("move_forward")
	var t := 0.0
	while t < secs:
		await physics_frame
		t += 1.0 / 60.0
		if Vector2(player.global_position.x - goal.x, player.global_position.z - goal.z).length() < 0.6:
			break
	Input.action_release("move_forward")
	return Vector2(player.global_position.x - goal.x, player.global_position.z - goal.z).length()


func _init() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame
	var player = get_nodes_in_group("player")[0]
	var info: Dictionary = main.settlement_info
	_check("hay 7 casas", info["houses"].size() == 7)
	_check("hay castillo", info["castle"] != null)

	var ok_houses := 0
	for house in info["houses"]:
		var sz: Vector2 = house.get_meta("size")
		var dx: float = house.get_meta("door_x")
		var out: Vector3 = house.to_global(Vector3(dx, 0.0, sz.y * 0.5 + 4.0))
		var inside: Vector3 = house.to_global(Vector3(dx, 0.0, 0.0))
		out.y = house.global_position.y
		inside.y = house.global_position.y
		var left := await _walk(player, out, inside, 4.0)
		if left < 1.0:
			ok_houses += 1
		else:
			print("   casa en ", house.global_position, " quedó a ", left, " m")
	_check("se puede entrar a todas las casas", ok_houses == info["houses"].size(), "%d/7" % ok_houses)

	var castle: Node3D = info["castle"]
	var cd: float = castle.get_meta("size").y
	var start: Vector3 = castle.to_global(Vector3(0.0, 0.0, cd * 0.5 + 8.0))
	var goal: Vector3 = castle.to_global(Vector3(0.0, 0.0, 0.0))
	start.y = castle.global_position.y
	goal.y = castle.global_position.y
	var left := await _walk(player, start, goal, 8.0)
	_check("se cruza el portón y se llega al patio", left < 1.5, "faltaron %.1f m" % left)

	print("TODO OK" if _fails == 0 else "HAY %d FALLAS" % _fails)
	quit(_fails)
