extends CharacterBody3D
## Jugador en primera persona. Se arma todo por código, no necesita escena propia.
## Controles: WASD o flechas = moverte, Shift = correr, Espacio = saltar, Esc = soltar el mouse.

@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.5
@export var jump_velocity: float = 6.5
@export var mouse_sensitivity: float = 0.0025

const GRAVITY := 20.0

var head: Node3D
var camera: Camera3D
var _pitch := 0.0
var _spawn_position := Vector3.ZERO


func _ready() -> void:
	_setup_inputs()

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
