extends Node3D
## Escena principal: genera el terreno, los árboles y las rocas, y pone al jugador.
## Todo se crea por código para que sea fácil de ajustar con las constantes de abajo.

const PlayerScript := preload("res://scripts/player.gd")
const DayNightScript := preload("res://scripts/day_night.gd")
const TreeFactory := preload("res://scripts/tree_factory.gd")
const HarvestableScript := preload("res://scripts/harvestable.gd")
const SettlementsScript := preload("res://scripts/settlements.gd")

const WORLD_SIZE := 500.0   # metros por lado
const GRID := 200           # cuadros por lado (más cuadros = terreno más detallado)
const HILL_HEIGHT := 14.0   # altura de las colinas en metros
const TREE_COUNT := 600
const BUSH_COUNT := 350
const ROCK_COUNT := 200
const GRASS_COUNT := 9000   # matas de pasto repartidas por el mapa
const CLEARING_RADIUS := 25.0  # claro plano donde aparece el jugador

const TREE_HITS := 6        # golpes para talar un árbol
const ROCK_HITS := 4        # golpes para romper una roca
const ROCK_DROPS := 2       # piedras extra al romperla (cada golpe ya suelta una)
# Troncos que suelta cada tipo de árbol: 3 pinos, 2 robles, 1 seco.
const TREE_DROPS := [3, 3, 3, 4, 4, 2]

var _terrain_noise := FastNoiseLite.new()
var _forest_noise := FastNoiseLite.new()
var _color_noise := FastNoiseLite.new()
var _site_heights: Array[float] = []   # altura plana de cada zona de Settlements.SITES
var settlement_info := {}              # lo que devuelve Settlements.build (casas, castillo, etc.)
var _day_night
var _player
var _harvest_root: Node3D
var _clock_label: Label
var _inv_label: Label
var _target_label: Label
var _build_label: Label
var _msg_box: VBoxContainer
var _slot_styles := {}   # estilo de cada casilla de herramienta, para marcar la activa


func _ready() -> void:
	randomize()
	_terrain_noise.seed = randi()
	_terrain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_terrain_noise.frequency = 0.006
	_terrain_noise.fractal_octaves = 4

	_forest_noise.seed = randi()
	_forest_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_forest_noise.frequency = 0.012

	_color_noise.seed = randi()
	_color_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_color_noise.frequency = 0.02

	# Altura plana de la aldea y del castillo (el castillo va sobre una loma).
	for s in SettlementsScript.SITES:
		var c: Vector2 = s["pos"]
		_site_heights.append(base_height_at(c.x, c.y) + float(s["lift"]))

	_day_night = DayNightScript.new()
	add_child(_day_night)

	_harvest_root = Node3D.new()
	_harvest_root.name = "Harvestables"
	add_child(_harvest_root)

	_build_terrain()
	settlement_info = SettlementsScript.build(self, self)
	_scatter_nature()
	_scatter_grass()
	_spawn_player()
	var buildings := Node3D.new()
	buildings.name = "Buildings"
	add_child(buildings)
	_player.setup_building(self, buildings)
	_build_hud()


func _process(_delta: float) -> void:
	_clock_label.text = "Día %d  ·  %s" % [_day_night.day, _day_night.get_clock_text()]


# ---------------------------------------------------------------- terreno

## Altura del terreno en un punto (x, z). Se usa para el relieve y para ubicar objetos.
func height_at(x: float, z: float) -> float:
	var h := base_height_at(x, z)
	var p := Vector2(x, z)
	for i in SettlementsScript.SITES.size():
		var s: Dictionary = SettlementsScript.SITES[i]
		var c: Vector2 = s["pos"]
		var wgt := 1.0 - smoothstep(float(s["r"]), float(s["r"]) + float(s["blend"]), p.distance_to(c))
		if wgt > 0.0:
			h = lerpf(h, _site_heights[i], wgt)
	return h


## El terreno natural, sin aplanar para las construcciones.
func base_height_at(x: float, z: float) -> float:
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
	mat.vertex_color_is_srgb = true
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
	var color := _terrain_color((a.x + b.x + c.x) / 3.0, (a.z + b.z + c.z) / 3.0, (a.y + b.y + c.y) / 3.0, n) \
		.darkened(randf() * 0.07)
	var verts: Array[Vector3] = [a, b, c]
	for v in verts:
		st.set_normal(n)
		st.set_color(color)
		st.add_vertex(v)


## Color del terreno en un punto: pasto con manchas, caminos de tierra y roca en las pendientes.
func _terrain_color(x: float, z: float, h: float, n: Vector3) -> Color:
	var patch := _color_noise.get_noise_2d(x, z)   # -1..1, manchas grandes
	var grass := Color(0.30, 0.40, 0.17).lerp(Color(0.43, 0.46, 0.20), clampf(patch * 0.5 + 0.5, 0.0, 1.0))
	grass = grass.lerp(Color(0.22, 0.32, 0.14), clampf(-patch, 0.0, 1.0) * 0.45)   # zonas de musgo
	var col := grass
	# Caminos de tierra, con el borde irregular
	var rd := SettlementsScript.road_distance(x, z) - _color_noise.get_noise_2d(x * 3.0, z * 3.0) * 0.9
	var road := 1.0 - smoothstep(1.8, 3.4, rd)
	if road > 0.0:
		col = col.lerp(Color(0.40, 0.31, 0.20).lerp(Color(0.47, 0.38, 0.26), patch * 0.5 + 0.5), road)
	# Pendientes: roca
	col = col.lerp(Color(0.42, 0.39, 0.35), 1.0 - smoothstep(0.70, 0.88, n.y))
	# Alturas grandes (las montañas del borde): piedra gris
	col = col.lerp(Color(0.46, 0.44, 0.41), smoothstep(7.0, 14.0, h))
	return col


# ---------------------------------------------------------- árboles y rocas

func _scatter_nature() -> void:
	var limit := WORLD_SIZE / 2.0 - 50.0

	# --- Árboles: varias formas distintas (3 pinos, 2 robles, 1 seco) para que no se repitan.
	var meshes: Array[Mesh] = []
	for i in 3:
		meshes.append(TreeFactory.make_pine(randi()))
	for i in 2:
		meshes.append(TreeFactory.make_oak(randi()))
	meshes.append(TreeFactory.make_dead(randi()))
	for i in 2:
		meshes.append(TreeFactory.make_sapling(randi()))   # árboles finos: dan palos

	var xforms: Array = []
	var tints: Array = []
	for i in meshes.size():
		xforms.append([])
		tints.append([])

	var pine_shape := CylinderShape3D.new()
	pine_shape.radius = 0.5
	pine_shape.height = 6.0
	var oak_shape := CylinderShape3D.new()
	oak_shape.radius = 0.75
	oak_shape.height = 4.0

	var sapling_shape := CylinderShape3D.new()
	sapling_shape.radius = 0.3
	sapling_shape.height = 3.0

	var tree_records: Array = []   # uno por árbol: qué forma es, cuál instancia, dónde
	var placed := 0
	var attempts := 0
	while placed < TREE_COUNT and attempts < TREE_COUNT * 20:
		attempts += 1
		var x := randf_range(-limit, limit)
		var z := randf_range(-limit, limit)
		if Vector2(x, z).length() < CLEARING_RADIUS or SettlementsScript.blocked(x, z, 3.0):
			continue
		# Bosques densos donde el ruido es alto, claros donde es bajo.
		if _forest_noise.get_noise_2d(x, z) < -0.15 and randf() > 0.15:
			continue
		if normal_at(x, z).y < 0.85 or height_at(x, z) > 10.0:
			continue

		var y := height_at(x, z)
		var roll := randf()
		var kind := randi() % 3        # pinos
		var shape := pine_shape
		if roll < 0.04:
			kind = 5                   # árbol seco
		elif y < 2.5 and roll < 0.55:
			kind = 3 + randi() % 2     # robles en las partes bajas
			shape = oak_shape

		if kind != 5 and randf() < 0.22:
			kind = 6 + randi() % 2     # árbol fino
			shape = sapling_shape

		var s := randf_range(0.8, 1.5)
		var basis := Basis(Vector3.UP, randf() * TAU) \
			* Basis(Vector3.RIGHT, randf_range(-0.05, 0.05)) \
			* Basis(Vector3.BACK, randf_range(-0.05, 0.05)) \
			* Basis.from_scale(Vector3(s, s, s))
		var xform := Transform3D(basis, Vector3(x, y, z))
		var tint := Color(randf_range(0.85, 1.0), randf_range(0.88, 1.0), randf_range(0.82, 0.98))
		xforms[kind].append(xform)
		tints[kind].append(tint)
		tree_records.append({
			"kind": kind, "index": xforms[kind].size() - 1,
			"xf": xform, "tint": tint, "shape": shape,
		})
		placed += 1

	var tree_mat := TreeFactory.make_material()
	var tree_mms: Array = []
	for i in meshes.size():
		tree_mms.append(_add_multimesh(meshes[i], tree_mat, xforms[i], tints[i]))

	# Cada árbol se vuelve algo que se puede talar.
	for r in tree_records:
		var k: int = r["kind"]
		var shape: CylinderShape3D = r["shape"]
		var t: Transform3D = r["xf"]
		var h = HarvestableScript.new()
		h.kind = "tree"
		if k >= 6:
			h.max_hp = 2.0
			h.drops = 4
			h.item_drop = "Palo"
			h.label = "Talar árbol fino (palos)"
		else:
			h.max_hp = TREE_HITS
			h.drops = TREE_DROPS[k]
			h.stick_drops = 2
		h.mm = tree_mms[k]
		h.index = r["index"]
		h.xf = t
		h.mesh = meshes[k]
		h.material = tree_mat
		h.tint = r["tint"]
		h.position = t.origin
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = Vector3(0.0, shape.height * 0.5, 0.0)
		h.add_child(cs)
		_harvest_root.add_child(h)

	# --- Arbustos (sin colisión, para decorar el suelo del bosque)
	var bush_meshes: Array[Mesh] = [TreeFactory.make_bush(randi()), TreeFactory.make_bush(randi())]
	var bush_xf: Array = [[], []]
	var bush_tint: Array = [[], []]
	var bush_records: Array = []
	var bushes := 0
	attempts = 0
	while bushes < BUSH_COUNT and attempts < BUSH_COUNT * 20:
		attempts += 1
		var x := randf_range(-limit, limit)
		var z := randf_range(-limit, limit)
		if Vector2(x, z).length() < 10.0 or SettlementsScript.blocked(x, z, 1.0):
			continue
		if _forest_noise.get_noise_2d(x, z) < -0.25:
			continue
		if normal_at(x, z).y < 0.85 or height_at(x, z) > 10.0:
			continue
		var k := randi() % 2
		var s := randf_range(0.8, 1.6)
		var basis := Basis(Vector3.UP, randf() * TAU) * Basis.from_scale(Vector3(s, s, s))
		bush_xf[k].append(Transform3D(basis, Vector3(x, height_at(x, z), z)))
		bush_records.append({"k": k, "index": bush_xf[k].size() - 1, "xf": bush_xf[k][-1], "s": s})
		bush_tint[k].append(Color(randf_range(0.8, 1.0), randf_range(0.85, 1.05), randf_range(0.8, 1.0)))
		bushes += 1
	var bush_mms: Array = []
	for k in 2:
		bush_mms.append(_add_multimesh(bush_meshes[k], tree_mat, bush_xf[k], bush_tint[k]))
	# Los arbustos se cortan con cualquier herramienta y dan palos. Su colisión está en la capa 16:
	# la ven los golpes pero el jugador la atraviesa.
	for r in bush_records:
		var bk: int = r["k"]
		if bush_mms[bk] == null:
			continue
		var bt: Transform3D = r["xf"]
		var bh = HarvestableScript.new()
		bh.kind = "bush"
		bh.drops = 2
		bh.mm = bush_mms[bk]
		bh.index = r["index"]
		bh.xf = bt
		bh.position = bt.origin
		bh.collision_layer = 16
		var bs := SphereShape3D.new()
		bs.radius = 0.7 * float(r["s"])
		var bcs := CollisionShape3D.new()
		bcs.shape = bs
		bcs.position = Vector3(0.0, 0.5, 0.0)
		bh.add_child(bcs)
		_harvest_root.add_child(bh)

	# --- Rocas
	var rock_xf: Array[Transform3D] = []
	var rock_radius: Array[float] = []
	var rock_color: Array = []
	var rock_ore: Array[bool] = []
	var rocks := 0
	attempts = 0
	while rocks < ROCK_COUNT and attempts < ROCK_COUNT * 20:
		attempts += 1
		var x := randf_range(-limit, limit)
		var z := randf_range(-limit, limit)
		if Vector2(x, z).length() < CLEARING_RADIUS * 0.6 or SettlementsScript.blocked(x, z, 2.0):
			continue
		var y := height_at(x, z)
		var sx := randf_range(0.8, 2.4)
		var sy := randf_range(0.6, 1.5)
		var sz := randf_range(0.8, 2.4)
		var basis := Basis(Vector3.UP, randf() * TAU) * Basis.from_scale(Vector3(sx, sy, sz))
		rock_xf.append(Transform3D(basis, Vector3(x, y + sy * 0.3, z)))
		rock_radius.append(maxf(sx, sz) * 0.85)
		var is_ore := randf() < 0.22   # roca con mineral: más oscura y rojiza
		rock_ore.append(is_ore)
		var g := randf_range(0.92, 1.05)
		rock_color.append(Color(0.40 * g, 0.27 * g, 0.24 * g) if is_ore else Color(0.48 * g, 0.47 * g, 0.46 * g))
		rocks += 1

	var rock_mesh := SphereMesh.new()
	rock_mesh.radius = 1.0
	rock_mesh.height = 2.0
	rock_mesh.radial_segments = 6
	rock_mesh.rings = 4
	var rock_mat := StandardMaterial3D.new()
	rock_mat.vertex_color_use_as_albedo = true
	rock_mat.vertex_color_is_srgb = true
	rock_mat.roughness = 1.0
	var rock_mm := _add_multimesh(rock_mesh, rock_mat, rock_xf, rock_color)

	for i in rock_xf.size():
		var h = HarvestableScript.new()
		h.kind = "rock"
		h.max_hp = ROCK_HITS
		h.drops = ROCK_DROPS
		if rock_ore[i]:
			h.ore_drops = 2
			h.label = "Picar roca con mineral"
		h.mm = rock_mm
		h.index = i
		h.xf = rock_xf[i]
		h.position = rock_xf[i].origin
		var sphere := SphereShape3D.new()
		sphere.radius = rock_radius[i]
		var cs := CollisionShape3D.new()
		cs.shape = sphere
		h.add_child(cs)
		_harvest_root.add_child(h)


## Matas de pasto repartidas por el mapa (no van sobre construcciones ni caminos).
func _scatter_grass() -> void:
	var tufts: Array[Mesh] = [TreeFactory.make_grass(randi()), TreeFactory.make_grass(randi()), TreeFactory.make_grass(randi())]
	var xforms: Array = [[], [], []]
	var tints: Array = [[], [], []]
	var limit := 215.0
	var count := 0
	var attempts := 0
	while count < GRASS_COUNT and attempts < GRASS_COUNT * 6:
		attempts += 1
		var x := randf_range(-limit, limit)
		var z := randf_range(-limit, limit)
		if SettlementsScript.near_structure(x, z, 1.0) or SettlementsScript.road_distance(x, z) < 2.2:
			continue
		if normal_at(x, z).y < 0.85 or height_at(x, z) > 9.0:
			continue
		var k := randi() % 3
		var s := randf_range(0.8, 1.7)
		var basis := Basis(Vector3.UP, randf() * TAU) * Basis.from_scale(Vector3(s, s * randf_range(0.8, 1.3), s))
		xforms[k].append(Transform3D(basis, Vector3(x, height_at(x, z) - 0.02, z)))
		tints[k].append(Color(randf_range(0.75, 1.0), randf_range(0.8, 1.0), randf_range(0.7, 0.95)))
		count += 1
	var mat := TreeFactory.make_grass_material()
	for k in 3:
		_add_multimesh(tufts[k], mat, xforms[k], tints[k])


## Dibuja muchas copias de una malla de una sola vez (rápido). Si se pasan colores, cada copia lleva el suyo.
func _add_multimesh(mesh: Mesh, mat: Material, transforms: Array, colors: Array = []) -> MultiMesh:
	if transforms.is_empty():
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, colors[i])

	var instance := MultiMeshInstance3D.new()
	instance.multimesh = mm
	instance.material_override = mat
	add_child(instance)
	return mm


# ------------------------------------------------------------ jugador y HUD

func _spawn_player() -> void:
	_player = PlayerScript.new()
	_player.name = "Player"
	_player.position = Vector3(0.0, height_at(0.0, 0.0) + 2.0, 0.0)
	add_child(_player)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	_clock_label = _make_label(Vector2(16, 12), 24)
	layer.add_child(_clock_label)

	var help := _make_label(Vector2(16, 48), 15)
	help.text = "WASD moverte  ·  Shift correr  ·  Espacio saltar  ·  Clic izquierdo golpear  ·  1 / 2 / 3 cambiar herramienta (3 = martillo, para construir)  ·  E usar  ·  Esc soltar el mouse"
	layer.add_child(help)

	# Mira en el centro de la pantalla
	var dot := ColorRect.new()
	dot.color = Color(1.0, 1.0, 1.0, 0.8)
	dot.anchor_left = 0.5
	dot.anchor_right = 0.5
	dot.anchor_top = 0.5
	dot.anchor_bottom = 0.5
	dot.offset_left = -2.0
	dot.offset_right = 2.0
	dot.offset_top = -2.0
	dot.offset_bottom = 2.0
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(dot)

	# Qué estás apuntando ("Talar árbol", "Picar roca")
	_target_label = _make_label(Vector2.ZERO, 18)
	_target_label.anchor_left = 0.5
	_target_label.anchor_right = 0.5
	_target_label.anchor_top = 0.5
	_target_label.anchor_bottom = 0.5
	_target_label.offset_left = -300.0
	_target_label.offset_right = 300.0
	_target_label.offset_top = 16.0
	_target_label.offset_bottom = 44.0
	_target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(_target_label)

	# Qué pieza estás por construir (solo con el martillo)
	_build_label = _make_label(Vector2.ZERO, 17)
	_build_label.anchor_left = 0.5
	_build_label.anchor_right = 0.5
	_build_label.anchor_top = 1.0
	_build_label.anchor_bottom = 1.0
	_build_label.offset_left = -420.0
	_build_label.offset_right = 420.0
	_build_label.offset_top = -120.0
	_build_label.offset_bottom = -64.0
	_build_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(_build_label)

	# Avisos tipo "+1 Tronco"
	_msg_box = VBoxContainer.new()
	_msg_box.anchor_left = 0.5
	_msg_box.anchor_right = 0.5
	_msg_box.anchor_top = 0.72
	_msg_box.anchor_bottom = 0.72
	_msg_box.offset_left = -120.0
	_msg_box.offset_right = 120.0
	_msg_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_msg_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_msg_box)

	# Mochila, abajo a la izquierda
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.04, 0.55)
	style.set_corner_radius_all(6)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	panel.add_theme_stylebox_override("panel", style)
	panel.anchor_left = 0.0
	panel.anchor_right = 0.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 16.0
	panel.offset_bottom = -16.0
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(panel)
	_inv_label = _make_label(Vector2.ZERO, 18)
	panel.add_child(_inv_label)

	# Herramientas, abajo al centro
	var bar := HBoxContainer.new()
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = -200.0
	bar.offset_right = 200.0
	bar.offset_bottom = -16.0
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 8)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(bar)
	for entry in [["axe", "1  Hacha"], ["pickaxe", "2  Pico"], ["hammer", "3  Martillo"]]:
		var slot := PanelContainer.new()
		var slot_style := StyleBoxFlat.new()
		slot_style.bg_color = Color(0.05, 0.05, 0.04, 0.55)
		slot_style.set_corner_radius_all(6)
		slot_style.set_border_width_all(2)
		slot_style.content_margin_left = 14.0
		slot_style.content_margin_right = 14.0
		slot_style.content_margin_top = 8.0
		slot_style.content_margin_bottom = 8.0
		slot.add_theme_stylebox_override("panel", slot_style)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var slot_label := _make_label(Vector2.ZERO, 17)
		slot_label.text = entry[1]
		slot.add_child(slot_label)
		bar.add_child(slot)
		_slot_styles[entry[0]] = slot_style

	_player.target_changed.connect(_on_target_changed)
	_player.collected.connect(_on_collected)
	_player.tool_changed.connect(_refresh_hotbar)
	_player.builder.notice.connect(_show_message)
	_player.builder.info_changed.connect(func(t: String): _build_label.text = t)
	_refresh_hotbar(_player.current_tool)
	_player.inventory.changed.connect(_refresh_inventory)
	_refresh_inventory()


func _refresh_hotbar(active: String) -> void:
	for id in _slot_styles:
		var style: StyleBoxFlat = _slot_styles[id]
		style.border_color = Color(1.0, 0.82, 0.40, 1.0) if id == active else Color(1.0, 1.0, 1.0, 0.12)


func _on_target_changed(text: String) -> void:
	if text == "":
		_target_label.text = ""
		return
	# La primera línea es la acción del clic; las siguientes (por ejemplo "[E] Abrir") van tal cual.
	# Las líneas que empiezan con "@" se muestran tal cual.
	var lines := text.split("\n")
	for i in lines.size():
		if lines[i].begins_with("@"):
			lines[i] = lines[i].substr(1)
		elif i == 0 and lines[i] != "":
			lines[i] = "Clic izquierdo: " + lines[i]
	_target_label.text = "\n".join(lines).strip_edges()


func _on_collected(item: String, amount: int) -> void:
	_show_message("+%d %s" % [amount, item])


func _show_message(text: String) -> void:
	var label := _make_label(Vector2.ZERO, 20)
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg_box.add_child(label)
	var tw := label.create_tween()
	tw.tween_interval(0.9)
	tw.tween_property(label, "modulate:a", 0.0, 0.6)
	tw.tween_callback(label.queue_free)


func _refresh_inventory() -> void:
	var items: Dictionary = _player.inventory.items
	var lines := PackedStringArray(["MOCHILA"])
	if items.is_empty():
		lines.append("vacía")
	else:
		for item in items:
			lines.append("%s  ×%d" % [item, items[item]])
	_inv_label.text = "\n".join(lines)


func _make_label(pos: Vector2, size: int) -> Label:
	var label := Label.new()
	label.position = pos
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.82))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 5)
	return label
