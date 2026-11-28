extends RigidBody3D
## Objeto suelto en el suelo (tronco o piedra). Se recoge acercándose.
## Para crear uno: instanciar, poner "item" y agregarlo a la escena.

const PICK_RADIUS := 1.5      # a esta distancia del jugador se recoge
const MAGNET_RADIUS := 3.0    # a esta distancia empieza a ir hacia el jugador

var item: String = "Tronco"
var amount: int = 1
var _age := 0.0


func _ready() -> void:
	# Capa 2: los objetos sueltos chocan con el mundo (capa 1) pero no con el jugador.
	collision_layer = 2
	collision_mask = 1
	angular_damp = 2.0
	linear_damp = 0.3
	add_to_group("pickups")

	var mat := StandardMaterial3D.new()
	mat.roughness = 1.0
	var mi := MeshInstance3D.new()
	var cs := CollisionShape3D.new()

	if item == "Tronco":
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.16
		cyl.bottom_radius = 0.16
		cyl.height = 0.9
		cyl.radial_segments = 6
		cyl.rings = 1
		mi.mesh = cyl
		mi.rotation_degrees = Vector3(0.0, 0.0, 90.0)
		mat.albedo_color = Color(0.38, 0.25, 0.14)
		var box := BoxShape3D.new()
		box.size = Vector3(0.9, 0.32, 0.32)
		cs.shape = box
		mass = 2.0
	else:
		var sph := SphereMesh.new()
		sph.radius = 0.22
		sph.height = 0.36
		sph.radial_segments = 6
		sph.rings = 3
		mi.mesh = sph
		mi.scale = Vector3(1.0, 0.8, 0.9)
		mat.albedo_color = Color(0.52, 0.51, 0.50)
		var ball := SphereShape3D.new()
		ball.radius = 0.2
		cs.shape = ball
		mass = 1.0

	mi.material_override = mat
	add_child(mi)
	add_child(cs)


func _physics_process(delta: float) -> void:
	_age += delta
	if global_position.y < -50.0 or _age > 300.0:
		queue_free()
		return
	if _age < 0.8:
		return  # un momento para que salga volando antes de poder recogerlo

	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var target: Vector3 = player.global_position + Vector3(0.0, 0.9, 0.0)
	var dist := global_position.distance_to(target)
	if dist < PICK_RADIUS:
		player.collect(item, amount)
		queue_free()
	elif dist < MAGNET_RADIUS:
		sleeping = false
		linear_velocity = (target - global_position).normalized() * 6.0
