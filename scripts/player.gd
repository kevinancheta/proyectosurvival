extends CharacterBody3D
## Jugador en primera persona. Se arma todo por código, no necesita escena propia.
## Controles: WASD o flechas = moverte, Shift = correr, Espacio = saltar,
## clic izquierdo = golpear (talar, picar), Esc = soltar el mouse.

signal target_changed(text: String)          # lo que estás apuntando ("" si nada)
signal collected(item: String, amount: int)  # cuando recogés algo

const InventoryScript := preload("res://scripts/inventory.gd")

@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.5
@export var jump_velocity: float = 6.5
@export var mouse_sensitivity: float = 0.0025

const GRAVITY := 20.0
const REACH := 3.4              # alcance de los golpes, en metros
const SWING_COOLDOWN := 0.55    # segundos entre golpes
const SWING_HIT_DELAY := 0.16   # cuándo, dentro del golpe, pega de verdad
const TOOL_REST := Vector3(0.15, 0.0, -0.2)

var inventory = InventoryScript.new()
var head: Node3D
var camera: Camera3D
var tool_pivot: Node3D

var _pitch := 0.0
var _spawn_position := Vector3.ZERO
var _swing_cd := 0.0
var _swing_tween: Tween
var _target_text := ""


func _ready() -> void:
	_setup_inputs()
	# Capa 4: el jugador choca con el mundo (capa 1), pero no con los objetos sueltos (capa 2).
	collision_layer = 4
	collision_mask = 1
	add_to_group("player")

	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.8
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = 0.9
	add_child(col)

	head = Node3D.new()
	head.position.y = 1.65
	add_child(head)

	camera = Camera3D.new()
	camera.fov = 75.0
	camera.far = 700.0
	head.add_child(camera)
	camera.current = true

	_build_tool()

	floor_snap_length = 0.5
	_spawn_position = global_position
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		rotate_y(-motion.relative.x * mouse_sensitivity)
		_pitch = clampf(_pitch - motion.relative.y * mouse_sensitivity, -1.5, 1.5)
		head.rotation.x = _pitch
	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and key.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			_swing_cd = 0.4  # que el clic que vuelve al juego no cuente como golpe


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	var speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	var response := clampf((12.0 if is_on_floor() else 3.0) * delta, 0.0, 1.0)

	velocity.x = lerpf(velocity.x, direction.x * speed, response)
	velocity.z = lerpf(velocity.z, direction.z * speed, response)
	move_and_slide()

	# Red de seguridad por si algo sale mal y te caés del mapa.
	if global_position.y < -60.0:
		global_position = _spawn_position
		velocity = Vector3.ZERO

	_swing_cd = maxf(0.0, _swing_cd - delta)
	_update_target()
	if _swing_cd <= 0.0 and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_start_swing()


## Lo llaman los objetos sueltos cuando los recogés.
func collect(item: String, amount: int = 1) -> void:
	inventory.add(item, amount)
	collected.emit(item, amount)


# ---------------------------------------------------------------- golpes

## Lanza un rayo desde la cámara hacia adelante y devuelve lo que toca (vacío si nada).
func _cast() -> Dictionary:
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * REACH
	var query := PhysicsRayQueryParameters3D.create(from, to, 1, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query)


func _update_target() -> void:
	var text := ""
	var hit := _cast()
	if not hit.is_empty():
		var c = hit["collider"]
		if c != null and c.has_method("get_prompt"):
			text = c.get_prompt()
	if text != _target_text:
		_target_text = text
		target_changed.emit(text)


func _start_swing() -> void:
	_swing_cd = SWING_COOLDOWN
	if _swing_tween:
		_swing_tween.kill()
	_swing_tween = create_tween()
	_swing_tween.tween_property(tool_pivot, "rotation:x", -1.2, SWING_HIT_DELAY) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_swing_tween.tween_property(tool_pivot, "rotation:x", TOOL_REST.x, 0.3) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	get_tree().create_timer(SWING_HIT_DELAY).timeout.connect(_apply_hit)


func _apply_hit() -> void:
	var hit := _cast()
	if hit.is_empty():
		return
	var c = hit["collider"]
	if c != null and c.has_method("take_hit"):
		c.take_hit(global_position)


## Hacha de piedra que se ve abajo a la derecha de la pantalla.
func _build_tool() -> void:
	tool_pivot = Node3D.new()
	tool_pivot.position = Vector3(0.42, -0.45, -0.6)
	tool_pivot.rotation = TOOL_REST
	camera.add_child(tool_pivot)

	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.40, 0.27, 0.15)
	wood.roughness = 1.0
	var rock := StandardMaterial3D.new()
	rock.albedo_color = Color(0.50, 0.50, 0.52)
	rock.roughness = 1.0

	var handle := MeshInstance3D.new()
	var handle_mesh := BoxMesh.new()
	handle_mesh.size = Vector3(0.06, 0.55, 0.06)
	handle.mesh = handle_mesh
	handle.material_override = wood
	handle.position = Vector3(0.0, 0.2, 0.0)
	handle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tool_pivot.add_child(handle)

	var head_part := MeshInstance3D.new()
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.26, 0.13, 0.06)
	head_part.mesh = head_mesh
	head_part.material_override = rock
	head_part.position = Vector3(0.1, 0.42, 0.0)
	head_part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tool_pivot.add_child(head_part)


# ---------------------------------------------------------------- teclas

func _setup_inputs() -> void:
	_add_action("move_forward", [KEY_W, KEY_UP])
	_add_action("move_back", [KEY_S, KEY_DOWN])
	_add_action("move_left", [KEY_A, KEY_LEFT])
	_add_action("move_right", [KEY_D, KEY_RIGHT])
	_add_action("jump", [KEY_SPACE])
	_add_action("sprint", [KEY_SHIFT])


func _add_action(action: StringName, keycodes: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for code in keycodes:
		var ev := InputEventKey.new()
		ev.physical_keycode = code
		InputMap.action_add_event(action, ev)
