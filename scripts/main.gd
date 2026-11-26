extends Node3D
## Escena principal: genera el terreno, los árboles y las rocas, y pone al jugador.
## Todo se crea por código para que sea fácil de ajustar con las constantes de abajo.

const PlayerScript := preload("res://scripts/player.gd")
const DayNightScript := preload("res://scripts/day_night.gd")

const WORLD_SIZE := 500.0   # metros por lado
const GRID := 200           # cuadros por lado (más cuadros = terreno más detallado)
const HILL_HEIGHT := 14.0   # altura de las colinas en metros
const TREE_COUNT := 600
const ROCK_COUNT := 200
const CLEARING_RADIUS := 25.0  # claro plano donde aparece el jugador

var _terrain_noise := FastNoiseLite.new()
var _forest_noise := FastNoiseLite.new()
var _day_night
var _clock_label: Label


func _ready() -> void:
	randomize()
	_terrain_noise.seed = randi()
	_terrain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_terrain_noise.frequency = 0.006
	_terrain_noise.fractal_octaves = 4

	_forest_noise.seed = randi()
	_forest_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_forest_noise.frequency = 0.012

	_day_night = DayNightScript.new()
	add_child(_day_night)

	_build_terrain()
	_scatter_nature()
	_spawn_player()
	_build_hud()


func _process(_delta: float) -> void:
	_clock_label.text = "Día %d  ·  %s" % [_day_night.day, _day_night.get_clock_text()]


# ---------------------------------------------------------------- terreno

## Altura del terreno en un punto (x, z). Se usa para el relieve y para ubicar objetos.
func height_at(x: float, z: float) -> float:
	var half := WORLD_SIZE / 2.0
	var h := _terrain_noise.get_noise_2d(x, z) * HILL_HEIGHT
	# Claro plano en el centro, para que el jugador no aparezca dentro de una colina.
	h *= smoothstep(CLEARING_RADIUS, CLEARING_RADIUS + 45.0, Vector2(x, z).length())
	# Montañas muy empinadas en el borde: son la pared del mapa.
	var edge := maxf(absf(x), absf(z))
	h += smoothstep(half - 40.0, half, edge) * 90.0
	return h


func normal_at(x: float, z: float) -> Vector3:
	var e := 1.0
	var hl := height_at(x - e, z)
	var hr := height_at(x + e, z)
	var hd := height_at(x, z - e)
	var hu := height_at(x, z + e)
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()


func _build_terrain() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := WORLD_SIZE / GRID
	var half := WORLD_SIZE / 2.0

	for i in GRID:
		for j in GRID:
			var x0 := -half + i * step
			var z0 := -half + j * step
			var x1 := x0 + step
			var z1 := z0 + step
			var a := Vector3(x0, height_at(x0, z0), z0)
			var b := Vector3(x1, height_at(x1, z0), z0)
			var c := Vector3(x1, height_at(x1, z1), z1)
			var d := Vector3(x0, height_at(x0, z1), z1)
			_add_triangle(st, a, b, c)
			_add_triangle(st, a, c, d)

	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mesh.surface_set_material(0, mat)

	var terrain := MeshInstance3D.new()
	terrain.name = "Terrain"
	terrain.mesh = mesh
	add_child(terrain)
	terrain.create_trimesh_collision()


func _add_triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	# Cada triángulo con su propia normal: da el look "low-poly" facetado.
	var n := (c - a).cross(b - a).normalized()
	var color := _terrain_color((a.y + b.y + c.y) / 3.0, n).darkened(randf() * 0.08)
	var verts: Array[Vector3] = [a, b, c]
	for v in verts:
		st.set_normal(n)
		st.set_color(color)
		st.add_vertex(v)


func _terrain_color(h: float, n: Vector3) -> Color:
	if n.y < 0.80:
		return Color(0.42, 0.40, 0.38)  # roca en las pendientes fuertes
	if h > 9.0:
		return Color(0.55, 0.53, 0.50)  # cumbres peladas
	var t := clampf((h + 4.0) / 12.0, 0.0, 1.0)
	return Color(0.26, 0.45, 0.20).lerp(Color(0.38, 0.55, 0.24), t)


# ---------------------------------------------------------- árboles y rocas

func _scatter_nature() -> void:
	var limit := WORLD_SIZE / 2.0 - 50.0

	var trunk_xf: Array[Transform3D] = []
	var low_cone_xf: Array[Transform3D] = []
	var high_cone_xf: Array[Transform3D] = []
	var tree_body := StaticBody3D.new()
	tree_body.name = "TreeColliders"
	var trunk_shape := CylinderShape3D.new()
	trunk_shape.radius = 0.5
	trunk_shape.height = 6.0

	var placed := 0
	var attempts := 0
	while placed < TREE_COUNT and attempts < TREE_COUNT * 20:
		attempts += 1
		var x := randf_range(-limit, limit)
		var z := randf_range(-limit, limit)
		if Vector2(x, z).length() < CLEARING_RADIUS:
			continue
		# Bosques densos donde el ruido es alto, claros donde es bajo.
		if _forest_noise.get_noise_2d(x, z) < -0.15 and randf() > 0.15:
			continue
		if normal_at(x, z).y < 0.85 or height_at(x, z) > 10.0:
			continue

		var y := height_at(x, z)
		var s := randf_range(0.8, 1.5)
		var yaw := randf() * TAU
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s))
		trunk_xf.append(Transform3D(basis, Vector3(x, y + 1.5 * s, z)))
		low_cone_xf.append(Transform3D(basis, Vector3(x, y + 4.2 * s, z)))
		high_cone_xf.append(Transform3D(basis, Vector3(x, y + 6.2 * s, z)))

		var cs := CollisionShape3D.new()
		cs.shape = trunk_shape
		cs.position = Vector3(x, y + 3.0, z)
		tree_body.add_child(cs)
		placed += 1

	add_child(tree_body)

	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.3
	trunk_mesh.bottom_radius = 0.45
	trunk_mesh.height = 3.0
	trunk_mesh.radial_segments = 6
	trunk_mesh.rings = 1

	var low_cone := CylinderMesh.new()
	low_cone.top_radius = 0.0
	low_cone.bottom_radius = 2.4
	low_cone.height = 4.0
	low_cone.radial_segments = 7
	low_cone.rings = 1

	var high_cone := CylinderMesh.new()
	high_cone.top_radius = 0.0
	high_cone.bottom_radius = 1.7
	high_cone.height = 3.2
	high_cone.radial_segments = 7
	high_cone.rings = 1

	_add_multimesh(trunk_mesh, Color(0.36, 0.24, 0.14), trunk_xf)
	_add_multimesh(low_cone, Color(0.12, 0.35, 0.16), low_cone_xf)
	_add_multimesh(high_cone, Color(0.16, 0.42, 0.20), high_cone_xf)

	# Rocas
	var rock_xf: Array[Transform3D] = []
	var rock_body := StaticBody3D.new()
	rock_body.name = "RockColliders"
	var rocks := 0
	attempts = 0
	while rocks < ROCK_COUNT and attempts < ROCK_COUNT * 20:
		attempts += 1
		var x := randf_range(-limit, limit)
		var z := randf_range(-limit, limit)
		if Vector2(x, z).length() < CLEARING_RADIUS * 0.6:
			continue
		var y := height_at(x, z)
		var sx := randf_range(0.8, 2.4)
		var sy := randf_range(0.6, 1.5)
		var sz := randf_range(0.8, 2.4)
		var basis := Basis(Vector3.UP, randf() * TAU) * Basis.from_scale(Vector3(sx, sy, sz))
		rock_xf.append(Transform3D(basis, Vector3(x, y + sy * 0.3, z)))

		var sphere := SphereShape3D.new()
		sphere.radius = maxf(sx, sz) * 0.85
		var cs := CollisionShape3D.new()
		cs.shape = sphere
		cs.position = Vector3(x, y + sy * 0.3, z)
		rock_body.add_child(cs)
		rocks += 1

	add_child(rock_body)

	var rock_mesh := SphereMesh.new()
	rock_mesh.radius = 1.0
	rock_mesh.height = 2.0
	rock_mesh.radial_segments = 6
	rock_mesh.rings = 4
	_add_multimesh(rock_mesh, Color(0.48, 0.47, 0.46), rock_xf)


func _add_multimesh(mesh: Mesh, color: Color, transforms: Array[Transform3D]) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0

	var instance := MultiMeshInstance3D.new()
	instance.multimesh = mm
	instance.material_override = mat
	add_child(instance)


# ------------------------------------------------------------ jugador y HUD

func _spawn_player() -> void:
	var player := PlayerScript.new()
	player.name = "Player"
	player.position = Vector3(0.0, height_at(0.0, 0.0) + 2.0, 0.0)
	add_child(player)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	_clock_label = _make_label(Vector2(16, 12), 24)
	layer.add_child(_clock_label)

	var help := _make_label(Vector2(16, 48), 15)
	help.text = "WASD moverte  ·  Shift correr  ·  Espacio saltar  ·  Esc soltar el mouse"
	layer.add_child(help)


func _make_label(pos: Vector2, size: int) -> Label:
	var label := Label.new()
	label.position = pos
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.82))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 5)
	return label
