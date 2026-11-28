extends CharacterBody3D
## Jugador en primera persona. Se arma todo por código, no necesita escena propia.
## Controles: WASD o flechas = moverte, Shift = correr, Espacio = saltar,
## clic izquierdo = golpear, 1 / 2 / rueda del mouse = hacha o pico, Esc = soltar el mouse.

signal target_changed(text: String)          # lo que estás apuntando ("" si nada)
signal collected(item: String, amount: int)  # cuando recogés algo
signal tool_changed(tool_id: String)         # cuando cambiás de herramienta

const InventoryScript := preload("res://scripts/inventory.gd")
const ToolFactory := preload("res://scripts/tool_factory.gd")
const BuilderScript := preload("res://scripts/builder.gd")

@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.5
@export var jump_velocity: float = 6.5
@export var mouse_sensitivity: float = 0.0025

const GRAVITY := 20.0
const REACH := 3.4              # alcance de los golpes, en metros
const SWING_COOLDOWN := 0.55    # segundos entre golpes
const SWING_HIT_DELAY := 0.16   # cuándo, dentro del golpe, pega de verdad
const TOOL_IDS := ["axe", "pickaxe", "hammer"]
const TOOL_POS := Vector3(0.38, -0.58, -0.62)   # dónde se ve la herramienta (relativo a la cámara)
const TOOL_REST := Vector3(-0.2, 0.0, 0.15)     # cómo la lleva en reposo

var inventory = InventoryScript.new()
var current_tool := "axe"
var head: Node3D
var camera: Camera3D
var tool_pivot: Node3D
var builder                       # modo construcción (se crea con setup_building)

var _tools := {}
var _pitch := 0.0
var _spawn_position := Vector3.ZERO
var _swing_cd := 0.0
var _swing_tween: Tween
var _equip_tween: Tween
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

	_build_tools()

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
		if key.pressed and not key.echo:
			if key.keycode == KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			elif key.keycode == KEY_1:
				equip("axe")
			elif key.keycode == KEY_2:
				equip("pickaxe")
			elif key.keycode == KEY_3:
				equip("hammer")
			elif key.keycode == KEY_Q and current_tool == "hammer":
				builder.cycle(1)
			elif key.keycode == KEY_R and current_tool == "hammer":
				builder.rotate_piece()
			elif key.keycode == KEY_E:
				interact()
	elif event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.pressed:
			if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				if click.button_index == MOUSE_BUTTON_LEFT:
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
					_swing_cd = 0.4  # que el clic que vuelve al juego no cuente como golpe
			elif click.button_index == MOUSE_BUTTON_RIGHT and current_tool == "hammer":
				_hammer_upgrade()
			elif click.button_index == MOUSE_BUTTON_WHEEL_UP:
				if current_tool == "hammer":
					builder.cycle(-1)
				else:
					_cycle_tool(-1)
			elif click.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				if current_tool == "hammer":
					builder.cycle(1)
				else:
					_cycle_tool(1)


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
		if current_tool != "hammer":
			_start_swing()
		else:
			_hammer_click()


## Lo llaman los objetos sueltos cuando los recogés.
func collect(item: String, amount: int = 1) -> void:
	inventory.add(item, amount)
	collected.emit(item, amount)


# ----------------------------------------------------------- herramientas

func equip(tool_id: String) -> void:
	if tool_id == current_tool or not _tools.has(tool_id):
		return
	current_tool = tool_id
	_show_current_tool()
	if _swing_tween:
		_swing_tween.kill()
	if _equip_tween:
		_equip_tween.kill()
	# La herramienta sube desde abajo de la pantalla.
	tool_pivot.rotation = TOOL_REST
	tool_pivot.position = TOOL_POS + Vector3(0.0, -0.3, 0.0)
	_equip_tween = create_tween()
	_equip_tween.tween_property(tool_pivot, "position", TOOL_POS, 0.22) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_swing_cd = 0.25
	if builder:
		builder.set_active(current_tool == "hammer")
	_target_text = "?"  # fuerza a actualizar el texto, que depende de la herramienta
	tool_changed.emit(current_tool)


func _cycle_tool(step: int) -> void:
	var i := TOOL_IDS.find(current_tool)
	equip(TOOL_IDS[(i + step + TOOL_IDS.size()) % TOOL_IDS.size()])


## Activa la construcción. "world" es el nodo principal; "container" es donde cuelgan las piezas.
func setup_building(world: Node3D, container: Node3D) -> void:
	builder = BuilderScript.new()
	builder.name = "Builder"
	add_child(builder)
	builder.setup(self, world, container)
	builder.set_active(current_tool == "hammer")


func _show_current_tool() -> void:
	for id in _tools:
		_tools[id].visible = (id == current_tool)


func _build_tools() -> void:
	tool_pivot = Node3D.new()
	tool_pivot.position = TOOL_POS
	tool_pivot.rotation = TOOL_REST
	camera.add_child(tool_pivot)
	for id in TOOL_IDS:
		var t = ToolFactory.make(id)
		tool_pivot.add_child(t)
		_tools[id] = t
	_show_current_tool()


# ---------------------------------------------------------------- golpes

## Lanza un rayo desde la cámara hacia adelante y devuelve lo que toca (vacío si nada).
func _cast() -> Dictionary:
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * REACH
	var query := PhysicsRayQueryParameters3D.create(from, to, 1 | 16, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query)


func _update_target() -> void:
	var text := ""
	var hit := _cast()
	if not hit.is_empty():
		var c = _target_of(hit["collider"])
		if c != null and c.has_method("get_prompt"):
			text = c.get_prompt(current_tool)
	if text != _target_text:
		_target_text = text
		target_changed.emit(text)


## Las piezas construidas tienen su propio cuerpo de colisión: se resuelven a la pieza.
func _target_of(c):
	if c != null and c.has_meta("piece"):
		return c.get_meta("piece")
	return c


## Tecla E: abrir una puerta, usar un cofre.
func interact() -> void:
	var hit := _cast()
	if hit.is_empty():
		return
	var c = _target_of(hit["collider"])
	if c != null and c.has_method("interact"):
		c.interact(self)


func _start_swing() -> void:
	_swing_cd = SWING_COOLDOWN
	if _swing_tween:
		_swing_tween.kill()
	_swing_tween = create_tween()
	_swing_tween.tween_property(tool_pivot, "rotation:x", -1.3, SWING_HIT_DELAY) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_swing_tween.tween_property(tool_pivot, "rotation:x", TOOL_REST.x, 0.3) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	get_tree().create_timer(SWING_HIT_DELAY).timeout.connect(_apply_hit)


## Martillo, clic izquierdo: coloca la pieza que elegiste (de paja).
func _hammer_click() -> void:
	if builder.try_place():
		_start_swing_visual()
	else:
		_swing_cd = 0.4


## Martillo, clic derecho: mejora la pieza que apuntás al siguiente nivel.
func _hammer_upgrade() -> void:
	var hit := _cast()
	if hit.is_empty():
		return
	var target = _target_of(hit["collider"])
	if target == null or not target.has_method("try_upgrade"):
		return
	var problem: String = target.try_upgrade(self)
	if problem == "":
		_start_swing_visual()
		_target_text = "?"   # que se actualice el texto con el nuevo nivel
	else:
		builder.notice.emit(problem)


func _start_swing_visual() -> void:
	_swing_cd = SWING_COOLDOWN
	if _swing_tween:
		_swing_tween.kill()
	_swing_tween = create_tween()
	_swing_tween.tween_property(tool_pivot, "rotation:x", -1.3, SWING_HIT_DELAY)
	_swing_tween.tween_property(tool_pivot, "rotation:x", TOOL_REST.x, 0.3)


func _apply_hit() -> void:
	var hit := _cast()
	if hit.is_empty():
		return
	var c = _target_of(hit["collider"])
	if c != null and c.has_method("take_hit"):
		c.take_hit(global_position, current_tool)


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
