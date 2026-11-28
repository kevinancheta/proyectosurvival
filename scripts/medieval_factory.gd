extends RefCounted
## Fabrica las construcciones medievales del mundo: casas, torres, castillo, pozo, puestos, etc.
## Todo se arma por código con MeshBuilder. Cada función devuelve un Node3D con el origen en el
## suelo, el frente mirando hacia +Z y las colisiones ya incluidas.

const MeshBuilder := preload("res://scripts/mesh_builder.gd")
const FlickerScript := preload("res://scripts/flicker.gd")

# Paleta apagada y terrosa, para que todo se vea como de otra época.
const STONE := Color(0.50, 0.48, 0.44)
const STONE_DARK := Color(0.36, 0.35, 0.34)
const STONE_LIGHT := Color(0.60, 0.58, 0.53)
const KEEP_STONE := Color(0.54, 0.51, 0.46)
const TIMBER := Color(0.25, 0.17, 0.10)
const WOOD := Color(0.43, 0.30, 0.18)
const STRAW := Color(0.72, 0.60, 0.30)
const GLASS := Color(0.07, 0.09, 0.12)
const SHUTTER := Color(0.30, 0.20, 0.13)
const RED := Color(0.55, 0.10, 0.09)
const GOLD := Color(0.82, 0.65, 0.22)
const SLATE := Color(0.30, 0.33, 0.38)
const CREAM := Color(0.82, 0.76, 0.62)
const PLASTERS := [Color(0.78, 0.72, 0.58), Color(0.70, 0.64, 0.50), Color(0.82, 0.75, 0.62), Color(0.64, 0.58, 0.45)]
const ROOFS := [Color(0.58, 0.45, 0.22), Color(0.52, 0.22, 0.16), Color(0.30, 0.33, 0.38)]

## Altura del piso sobre el suelo. Un escalón de más de unos 10 cm frena al jugador.
const FLOOR_Y := 0.05

const BANNER_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform float amp = 0.09;
uniform float hang = 3.0;
void vertex() {
	float w = clamp(-VERTEX.y / hang, 0.0, 1.0);
	VERTEX.z += sin(TIME * 2.4 + VERTEX.x * 2.2 - VERTEX.y * 1.4) * amp * w;
}
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
}
"""


static func xf(x: float, y: float, z: float, yaw: float = 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), Vector3(x, y, z))


# =========================================================== CASA

## Casa de entramado de madera. Se puede entrar por la puerta. Con upper = true tiene
## un piso de arriba (macizo) que sobresale, como las casas medievales.
## Guarda en el metadato "door_x" dónde está la puerta (en el frente, a lo largo de X).
static func make_house(seed_value: int, w: float = 6.0, d: float = 5.0, upper: bool = false) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var b := MeshBuilder.new(seed_value)
	var plaster: Color = PLASTERS[rng.randi() % PLASTERS.size()]
	var roof: Color = ROOFS[rng.randi() % ROOFS.size()]
	var wt := 0.3
	var y0 := FLOOR_Y
	var wh := 2.8
	var door_w := 1.4
	var door_h := 2.2
	var door_x := rng.randf_range(-w * 0.2, w * 0.2)
	var top := y0 + wh
	var xl := door_x - door_w * 0.5
	var xr := door_x + door_w * 0.5

	# Piso (colisiona, y baja bajo tierra por si el suelo tiene pendiente)
	b.box(xf(0.0, y0 - (y0 + 0.9) * 0.5, 0.0), Vector3(w, y0 + 0.9, d), WOOD)
	# Zócalo de piedra (solo se ve)
	var ph := 1.26
	var py := -0.27
	b.box(xf(0.0, py, -d * 0.5 - 0.05), Vector3(w + 0.3, ph, 0.2), STONE_DARK, false)
	b.box(xf(-w * 0.5 - 0.05, py, 0.0), Vector3(0.2, ph, d), STONE_DARK, false)
	b.box(xf(w * 0.5 + 0.05, py, 0.0), Vector3(0.2, ph, d), STONE_DARK, false)
	b.box(xf((-w * 0.5 - 0.15 + xl) * 0.5, py, d * 0.5 + 0.05), Vector3(xl + w * 0.5 + 0.15, ph, 0.2), STONE_DARK, false)
	b.box(xf((xr + w * 0.5 + 0.15) * 0.5, py, d * 0.5 + 0.05), Vector3(w * 0.5 + 0.15 - xr, ph, 0.2), STONE_DARK, false)

	# Paredes
	var ym := y0 + wh * 0.5
	b.box(xf(0.0, ym, -d * 0.5 + wt * 0.5), Vector3(w, wh, wt), plaster)
	b.box(xf(-w * 0.5 + wt * 0.5, ym, 0.0), Vector3(wt, wh, d - 2.0 * wt), plaster)
	b.box(xf(w * 0.5 - wt * 0.5, ym, 0.0), Vector3(wt, wh, d - 2.0 * wt), plaster)
	var zf := d * 0.5 - wt * 0.5
	b.box(xf((-w * 0.5 + xl) * 0.5, ym, zf), Vector3(xl + w * 0.5, wh, wt), plaster)
	b.box(xf((xr + w * 0.5) * 0.5, ym, zf), Vector3(w * 0.5 - xr, wh, wt), plaster)
	b.box(xf(door_x, y0 + door_h + (wh - door_h) * 0.5, zf), Vector3(door_w, wh - door_h, wt), plaster)

	# Entramado de madera y ventanas en las cuatro caras
	var fy := y0 + wh * 0.5
	_timber_face(b, Transform3D(Basis.IDENTITY, Vector3(0.0, fy, d * 0.5)), w, wh, seed_value, xl - 0.1, xr + 0.1)
	_timber_face(b, Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, fy, -d * 0.5)), w, wh, seed_value + 1)
	_timber_face(b, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(w * 0.5, fy, 0.0)), d, wh, seed_value + 2)
	_timber_face(b, Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-w * 0.5, fy, 0.0)), d, wh, seed_value + 3)
	var wy := y0 + 1.7
	if xl + w * 0.5 > 1.9:
		_window(b, Transform3D(Basis.IDENTITY, Vector3((-w * 0.5 + xl) * 0.5, wy, d * 0.5)))
	if w * 0.5 - xr > 1.9:
		_window(b, Transform3D(Basis.IDENTITY, Vector3((xr + w * 0.5) * 0.5, wy, d * 0.5)))
	_window(b, Transform3D(Basis(Vector3.UP, PI), Vector3(-w * 0.22, wy, -d * 0.5)))
	_window(b, Transform3D(Basis(Vector3.UP, PI), Vector3(w * 0.22, wy, -d * 0.5)))
	_window(b, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(w * 0.5, wy, 0.0)))
	_window(b, Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-w * 0.5, wy, 0.0)))

	# Marco de la puerta y escalón
	b.box(xf(xl - 0.08, y0 + door_h * 0.5, d * 0.5 + 0.02), Vector3(0.18, door_h, 0.4), TIMBER, false)
	b.box(xf(xr + 0.08, y0 + door_h * 0.5, d * 0.5 + 0.02), Vector3(0.18, door_h, 0.4), TIMBER, false)
	b.box(xf(door_x, y0 + door_h + 0.1, d * 0.5 + 0.02), Vector3(door_w + 0.5, 0.24, 0.4), TIMBER, false)
	b.box(xf(door_x, 0.03, d * 0.5 + 0.45), Vector3(door_w + 0.4, 0.08, 0.8), STONE, false)

	# Techo
	var rw := w
	var rd := d
	var rtop := top
	if upper:
		b.box(xf(0.0, top + 0.15, 0.0), Vector3(w, 0.3, d), WOOD)
		rw = w + 0.6
		rd = d + 0.6
		b.box(xf(0.0, top + 0.3 + 1.3, 0.0), Vector3(rw, 2.6, rd), plaster)
		var uy := top + 0.3 + 1.3
		_timber_face(b, Transform3D(Basis.IDENTITY, Vector3(0.0, uy, rd * 0.5)), rw, 2.6, seed_value + 4)
		_timber_face(b, Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, uy, -rd * 0.5)), rw, 2.6, seed_value + 5)
		_timber_face(b, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(rw * 0.5, uy, 0.0)), rd, 2.6, seed_value + 6)
		_timber_face(b, Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-rw * 0.5, uy, 0.0)), rd, 2.6, seed_value + 7)
		_window(b, Transform3D(Basis.IDENTITY, Vector3(-rw * 0.25, uy, rd * 0.5)))
		_window(b, Transform3D(Basis.IDENTITY, Vector3(rw * 0.25, uy, rd * 0.5)))
		_window(b, Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, uy, -rd * 0.5)))
		_window(b, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(rw * 0.5, uy, 0.0)))
		_window(b, Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-rw * 0.5, uy, 0.0)))
		rtop = top + 0.3 + 2.6
	var rise := rw * 0.5
	b.gable_roof(xf(0.0, rtop, 0.0), rw, rd, rise, roof, 0.6)
	var gable := PackedVector2Array([Vector2(-rw * 0.5, 0.0), Vector2(rw * 0.5, 0.0), Vector2(0.0, rise)])
	b.extrude(xf(0.0, rtop, rd * 0.5 - wt * 0.5), gable, wt, plaster)
	b.extrude(xf(0.0, rtop, -rd * 0.5 + wt * 0.5), gable, wt, plaster)
	for gz in [rd * 0.5 + 0.02, -rd * 0.5 - 0.02]:
		b.box(xf(0.0, rtop + rise * 0.4, gz), Vector3(0.18, rise * 0.8, 0.12), TIMBER, false)
		b.box(xf(0.0, rtop + 0.12, gz), Vector3(rw, 0.2, 0.12), TIMBER, false)
	# Vigas que se ven bajo el techo
	var beam_z := -rd * 0.5 + 1.0
	while beam_z < rd * 0.5 - 0.5:
		b.box(xf(0.0, rtop + 0.2, beam_z), Vector3(rw - 0.2, 0.18, 0.18), TIMBER, false)
		beam_z += 1.7
	# Chimenea
	var ch := rise * 0.44 + 1.5
	b.box(xf(rw * 0.28, rtop - 0.2 + ch * 0.5, -rd * 0.2), Vector3(0.9, ch, 0.9), STONE_DARK, false)
	b.box(xf(rw * 0.28, rtop - 0.2 + ch + 0.1, -rd * 0.2), Vector3(1.1, 0.2, 1.1), STONE, false)

	var root := b.build("House")
	root.set_meta("door_x", door_x)
	root.set_meta("size", Vector2(w, d))
	return root


## Entramado: postes, vigas y diagonales sobre una cara. t está en el centro de la cara,
## con +Z hacia afuera y X a lo largo de la pared.
static func _timber_face(b, t: Transform3D, width: float, height: float, seed_v: int,
		skip_x0: float = 1e9, skip_x1: float = 1e9) -> void:
	var n := maxi(2, int(round(width / 1.8)))
	var step := width / n
	var pz := 0.05
	for i in n + 1:
		var x := -width * 0.5 + i * step
		if x > skip_x0 and x < skip_x1:
			continue
		b.box(t * Transform3D(Basis.IDENTITY, Vector3(x, 0.0, pz)), Vector3(0.2, height, 0.14), TIMBER, false)
	for yy in [-height * 0.5 + 0.12, height * 0.5 - 0.12]:
		b.box(t * Transform3D(Basis.IDENTITY, Vector3(0.0, yy, pz)), Vector3(width, 0.24, 0.14), TIMBER, false)
	var ang := atan2(height - 0.5, step)
	var diag_len := Vector2(step, height - 0.5).length()
	for i in n:
		var cx := -width * 0.5 + (i + 0.5) * step
		if cx + step * 0.5 > skip_x0 and cx - step * 0.5 < skip_x1:
			continue
		if (i + seed_v) % 2 == 0:
			continue
		var dir := 1.0 if ((i + seed_v) % 4 == 1) else -1.0
		b.box(t * Transform3D(Basis(Vector3.BACK, dir * ang), Vector3(cx, 0.0, pz + 0.01)),
			Vector3(diag_len, 0.13, 0.12), TIMBER, false)


## Ventana con marco, cruz y postigos. t está en la pared, con +Z hacia afuera.
static func _window(b, t: Transform3D, w: float = 0.8, h: float = 1.0) -> void:
	b.box(t * xf(0.0, 0.0, 0.05), Vector3(w + 0.2, h + 0.2, 0.08), WOOD, false)
	b.box(t * xf(0.0, 0.0, 0.1), Vector3(w, h, 0.06), GLASS, false)
	b.box(t * xf(0.0, 0.0, 0.14), Vector3(0.06, h, 0.04), WOOD, false)
	b.box(t * xf(0.0, 0.0, 0.14), Vector3(w, 0.06, 0.04), WOOD, false)
	for side in [-1.0, 1.0]:
		var s: float = side
		b.box(t * Transform3D(Basis(Vector3.UP, s * 0.55), Vector3(s * (w * 0.5 + 0.3), 0.0, 0.2)),
			Vector3(0.38, h + 0.1, 0.05), SHUTTER, false)


# =========================================================== TORRES

static func make_tower(seed_value: int = 3, radius: float = 3.0, height: float = 12.0,
		roof_col: Color = SLATE) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var b := MeshBuilder.new(seed_value)
	var banners: Array = []
	_tower_into(b, rng, 0.0, 0.0, radius, height, roof_col, banners)
	var root := b.build("Tower")
	_attach_banners(root, banners)
	return root


## Agrega una torre redonda con techo cónico al builder. Anota las banderas en "banners".
static func _tower_into(b, rng: RandomNumberGenerator, x: float, z: float, radius: float, height: float,
		roof_col: Color, banners: Array) -> void:
	var r_top := radius * 0.92
	var top := height + 0.4
	b.cylinder(xf(x, -1.2, z), radius * 1.1, 1.6, 12, STONE_DARK, false)
	b.cylinder(xf(x, -1.2, z), radius, height + 1.6, 12, STONE, true, r_top)
	var rad_at := func(y: float) -> float:
		return lerpf(radius, r_top, (y + 1.2) / (height + 1.6))
	var ring_y := top * 0.5
	var rr: float = rad_at.call(ring_y) * 1.03
	b.cylinder(xf(x, ring_y, z), rr, 0.3, 12, STONE_LIGHT, false)
	var cr: float = rad_at.call(top - 0.8)
	b.cylinder(xf(x, top - 0.8, z), cr * 1.2, 0.8, 12, STONE_LIGHT, false, rad_at.call(top) * 1.3)
	var roof_r: float = rad_at.call(top) * 1.5
	b.cone(xf(x, top, z), roof_r, radius * 2.4, 12, roof_col)
	# Troneras
	for k in 4:
		var a := deg_to_rad(30.0 * (rng.randi() % 12))
		var y := top * rng.randf_range(0.25, 0.8)
		var rd: float = rad_at.call(y) * 0.966 + 0.02
		b.box(Transform3D(Basis(Vector3.UP, PI * 0.5 - a), Vector3(x + cos(a) * rd, y, z + sin(a) * rd)),
			Vector3(0.22, 1.1, 0.14), GLASS, false)
	# Banderas colgando de la pared
	for ang in [30.0, 150.0]:
		var a := deg_to_rad(ang)
		var rd: float = rad_at.call(top - 1.2) * 0.966
		banners.append([Vector3(x + cos(a) * (rd + 0.1), top - 1.4, z + sin(a) * (rd + 0.1)),
			PI * 0.5 - a, 1.0, 3.0, RED])


# =========================================================== BANDERAS

## Bandera de tela que se mueve con el viento. Cuelga hacia abajo desde el origen.
static func make_banner(width: float = 1.4, height: float = 3.0, base: Color = RED, trim: Color = GOLD) -> Node3D:
	var cols := 7
	var rows := 14
	var cw := width / cols
	var ch := height / rows
	var mid := (cols - 1) * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in rows:
		for c in cols:
			if r >= rows - 3 and absf(c - mid) < (r - (rows - 4)) * 0.9:
				continue   # muesca en V abajo
			var col := base
			var dx := absf(c - mid) / (cols * 0.30)
			var dy := absf(r - rows * 0.42) / (rows * 0.20)
			if c == 0 or c == cols - 1 or r == 0 or dx + dy <= 1.0:
				col = trim
			var x0 := -width * 0.5 + c * cw
			var y0 := -r * ch
			var q := [Vector3(x0, y0, 0.0), Vector3(x0 + cw, y0, 0.0),
				Vector3(x0 + cw, y0 - ch, 0.0), Vector3(x0, y0 - ch, 0.0)]
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_normal(Vector3.BACK)
				st.set_color(col)
				st.add_vertex(q[idx])
	var shader := Shader.new()
	shader.code = BANNER_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("hang", height)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var root := Node3D.new()
	root.name = "Banner"
	root.add_child(mi)
	return root


## Cada banner: [posición, giro, ancho, alto, color]. Se agregan después de armar la malla.
static func _attach_banners(root: Node3D, banners: Array) -> void:
	for e in banners:
		var banner := make_banner(e[2], e[3], e[4])
		banner.position = e[0]
		banner.rotation.y = e[1]
		root.add_child(banner)


# =========================================================== FUEGO Y LUZ

static func _flame(parent: Node3D, pos: Vector3, size: float = 1.0) -> void:
	var p := CPUParticles3D.new()
	p.position = pos
	p.amount = 14
	p.lifetime = 0.8
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.12 * size
	p.direction = Vector3.UP
	p.spread = 10.0
	p.initial_velocity_min = 0.5 * size
	p.initial_velocity_max = 1.1 * size
	p.gravity = Vector3(0.0, 0.4, 0.0)
	p.scale_amount_min = 0.22 * size
	p.scale_amount_max = 0.38 * size
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.85, 0.35, 0.95))
	grad.set_color(1, Color(0.9, 0.25, 0.05, 0.0))
	p.color_ramp = grad
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = m
	p.mesh = q
	parent.add_child(p)


static func _light(parent: Node3D, pos: Vector3, range_m: float = 14.0, energy: float = 2.2) -> void:
	var l := FlickerScript.new()
	l.position = pos
	l.light_color = Color(1.0, 0.62, 0.30)
	l.light_energy = energy
	l.omni_range = range_m
	l.omni_attenuation = 1.4
	l.shadow_enabled = false
	parent.add_child(l)


## Antorcha de pared: palo, llama y luz que titila.
static func make_torch() -> Node3D:
	var b := MeshBuilder.new(5)
	b.box(xf(0.0, 0.0, 0.0), Vector3(0.09, 0.6, 0.09), WOOD, false)
	b.box(xf(0.0, 0.34, 0.0), Vector3(0.16, 0.12, 0.16), STONE_DARK, false)
	var root := b.build("Torch")
	_flame(root, Vector3(0.0, 0.5, 0.0), 0.8)
	_light(root, Vector3(0.0, 0.7, 0.2), 13.0, 2.0)
	return root


static func make_campfire(seed_value: int = 1) -> Node3D:
	var b := MeshBuilder.new(seed_value)
	for i in 9:
		var a := TAU * i / 9.0
		b.box(Transform3D(Basis(Vector3.UP, -a), Vector3(cos(a) * 0.65, 0.12, sin(a) * 0.65)),
			Vector3(0.32, 0.26, 0.24), STONE, false)
	for i in 5:
		var a := TAU * i / 5.0 + 0.3
		var t := Transform3D(Basis(Vector3.UP, -a) * Basis(Vector3.BACK, 1.1), Vector3(cos(a) * 0.5, 0.05, sin(a) * 0.5))
		b.cylinder(t, 0.1, 1.0, 6, WOOD, false)
	var root := b.build("Campfire")
	_flame(root, Vector3(0.0, 0.35, 0.0), 1.3)
	_light(root, Vector3(0.0, 1.0, 0.0), 18.0, 2.6)
	return root


# =========================================================== PROPS

static func make_well(seed_value: int = 2) -> Node3D:
	var b := MeshBuilder.new(seed_value)
	b.cylinder(xf(0.0, -0.4, 0.0), 1.15, 1.35, 10, STONE, true)
	b.cylinder(xf(0.0, 0.93, 0.0), 0.85, 0.02, 10, Color(0.08, 0.12, 0.18), false)
	b.box(xf(-1.0, 1.1, 0.0), Vector3(0.16, 2.2, 0.16), WOOD, false)
	b.box(xf(1.0, 1.1, 0.0), Vector3(0.16, 2.2, 0.16), WOOD, false)
	b.box(xf(0.0, 2.2, 0.0), Vector3(2.3, 0.16, 0.16), WOOD, false)
	b.gable_roof(xf(0.0, 2.28, 0.0), 2.4, 1.6, 0.9, ROOFS[0], 0.35, 0.12)
	b.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.18, 1.6, 0.0)), 0.07, 0.6, 6, WOOD, false)
	return b.build("Well")


static func make_barrel(seed_value: int = 1) -> Node3D:
	var b := MeshBuilder.new(seed_value)
	b.cylinder(xf(0.0, 0.0, 0.0), 0.42, 0.95, 8, WOOD, true, 0.38)
	b.cylinder(xf(0.0, 0.2, 0.0), 0.45, 0.06, 8, STONE_DARK, false)
	b.cylinder(xf(0.0, 0.7, 0.0), 0.43, 0.06, 8, STONE_DARK, false)
	return b.build("Barrel")


static func make_crate(seed_value: int = 1) -> Node3D:
	var b := MeshBuilder.new(seed_value)
	b.box(xf(0.0, 0.42, 0.0), Vector3(0.85, 0.85, 0.85), WOOD)
	for s in [-1.0, 1.0]:
		var sg: float = s
		b.box(xf(sg * 0.38, 0.42, 0.0), Vector3(0.1, 0.9, 0.9), TIMBER, false)
	b.box(xf(0.0, 0.88, 0.0), Vector3(0.9, 0.08, 0.9), TIMBER, false)
	return b.build("Crate")


static func make_hay(seed_value: int = 1) -> Node3D:
	var b := MeshBuilder.new(seed_value)
	b.box(xf(0.0, 0.4, 0.0), Vector3(1.3, 0.8, 0.9), STRAW)
	b.box(xf(0.0, 0.5, 0.0), Vector3(1.34, 0.07, 0.94), WOOD, false)
	return b.build("Hay")


## Puesto de mercado con toldo a rayas.
static func make_stall(seed_value: int = 1) -> Node3D:
	var b := MeshBuilder.new(seed_value)
	for sx in [-1.3, 1.3]:
		for sz in [-0.8, 0.8]:
			b.box(xf(sx, 1.25, sz), Vector3(0.14, 2.5, 0.14), WOOD, false)
	b.box(xf(0.0, 0.45, 0.5), Vector3(2.5, 0.9, 0.9), WOOD)
	b.box(xf(0.0, 0.95, 0.5), Vector3(2.6, 0.08, 1.0), TIMBER, false)
	for i in 6:
		var col := RED if i % 2 == 0 else CREAM
		b.box(Transform3D(Basis(Vector3.RIGHT, 0.2), Vector3(-1.15 + i * 0.46, 2.55, 0.0)),
			Vector3(0.46, 0.06, 2.0), col, false)
	# Mercadería
	b.box(xf(-0.7, 1.08, 0.5), Vector3(0.4, 0.2, 0.4), STRAW, false)
	b.box(xf(0.1, 1.1, 0.4), Vector3(0.3, 0.24, 0.3), Color(0.55, 0.15, 0.12), false)
	b.box(xf(0.7, 1.06, 0.55), Vector3(0.5, 0.16, 0.35), Color(0.35, 0.40, 0.18), false)
	return b.build("Stall")


## Tramo de empalizada recto a lo largo de X, con troncos puntiagudos.
static func make_palisade(length: float = 8.0, seed_value: int = 1) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var b := MeshBuilder.new(seed_value)
	var n := int(length / 0.4)
	for i in n:
		var x := -length * 0.5 + (i + 0.5) * (length / n)
		var h := rng.randf_range(3.0, 3.8)
		b.cylinder(xf(x, -0.5, rng.randf_range(-0.05, 0.05)), 0.21, h + 0.5, 6, WOOD, false)
		b.cone(xf(x, h, 0.0), 0.21, 0.55, 6, WOOD)
	b.box(xf(0.0, 1.0, 0.2), Vector3(length, 0.18, 0.16), TIMBER, false)
	b.box(xf(0.0, 2.2, 0.2), Vector3(length, 0.18, 0.16), TIMBER, false)
	b.add_box_collider(xf(0.0, 1.7, 0.0), Vector3(length, 3.4, 0.5))
	return b.build("Palisade")


# =========================================================== CASTILLO

## Castillo con muros, torres, puerta, salón del trono y patio. El frente (la puerta) mira a +Z.
## Hay una rampa a cada lado para subir a los muros.
static func make_castle(seed_value: int = 7) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var b := MeshBuilder.new(seed_value)
	var banners: Array = []
	var torches: Array = []
	var W := 46.0
	var D := 38.0
	var wt := 2.0
	var wh := 8.5
	var G := 6.0
	var hw := W * 0.5
	var hd := D * 0.5

	# --- Patio
	b.box(xf(0.0, FLOOR_Y - 1.0, 0.0), Vector3(W + 1.0, 2.0, D + 1.0), Color(0.47, 0.45, 0.41))
	for i in 70:
		var sc := STONE.lerp(STONE_DARK, rng.randf())
		b.box(xf(rng.randf_range(-hw + 3.0, hw - 3.0), FLOOR_Y + 0.012, rng.randf_range(-hd + 3.0, hd - 3.0), rng.randf() * PI),
			Vector3(rng.randf_range(1.0, 2.0), 0.03, rng.randf_range(0.8, 1.5)), sc, false)

	# --- Muros
	_wall(b, 0.0, -hd + wt * 0.5, W, wt, wh)
	_wall(b, -hw + wt * 0.5, 0.0, wt, D - wt * 2.0, wh)
	_wall(b, hw - wt * 0.5, 0.0, wt, D - wt * 2.0, wh)
	var seg := hw - G * 0.5
	_wall(b, -(hw + G * 0.5) * 0.5, hd - wt * 0.5, seg, wt, wh)
	_wall(b, (hw + G * 0.5) * 0.5, hd - wt * 0.5, seg, wt, wh)
	b.box(xf(0.0, 5.5 + (wh - 5.5) * 0.5, hd - wt * 0.5), Vector3(G, wh - 5.5, wt), STONE)

	# Almenas en el borde de afuera
	var my := wh + 0.5
	var msz := Vector3(0.7, 1.0, 1.2)
	_merlons(b, Vector3(-hw, my, -hd + 0.35), Vector3(hw, my, -hd + 0.35), 1.2, msz, STONE_LIGHT)
	_merlons(b, Vector3(-hw + 0.35, my, -hd), Vector3(-hw + 0.35, my, hd), 1.2, msz, STONE_LIGHT)
	_merlons(b, Vector3(hw - 0.35, my, -hd), Vector3(hw - 0.35, my, hd), 1.2, msz, STONE_LIGHT)
	_merlons(b, Vector3(-hw, my, hd - 0.35), Vector3(-G * 0.5, my, hd - 0.35), 1.2, msz, STONE_LIGHT)
	_merlons(b, Vector3(G * 0.5, my, hd - 0.35), Vector3(hw, my, hd - 0.35), 1.2, msz, STONE_LIGHT)

	# --- Torres de las esquinas
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var roof := RED if (sx * sz) > 0.0 else SLATE
			_tower_into(b, rng, sx * hw, sz * hd, 4.3, 13.0, roof, banners)

	# --- Puerta con dos torres cuadradas
	for sx in [-1.0, 1.0]:
		var gx: float = sx * (G * 0.5 + 3.5)
		var gz := hd + 0.3
		b.box(xf(gx, 5.25, gz), Vector3(7.0, 14.5, 7.0), STONE)
		b.box(xf(gx, 2.8, gz), Vector3(7.2, 0.25, 7.2), STONE_LIGHT, false)
		b.box(xf(gx, 8.2, gz), Vector3(7.2, 0.25, 7.2), STONE_LIGHT, false)
		b.box(xf(gx, 12.2, gz), Vector3(7.5, 0.5, 7.5), STONE_LIGHT, false)
		var ty := 12.5 + 0.5
		_merlons(b, Vector3(gx - 3.6, ty, gz - 3.6), Vector3(gx + 3.6, ty, gz - 3.6), 1.1, Vector3(0.7, 1.0, 1.1), STONE_LIGHT)
		_merlons(b, Vector3(gx - 3.6, ty, gz + 3.6), Vector3(gx + 3.6, ty, gz + 3.6), 1.1, Vector3(0.7, 1.0, 1.1), STONE_LIGHT)
		_merlons(b, Vector3(gx - 3.6, ty, gz - 3.6), Vector3(gx - 3.6, ty, gz + 3.6), 1.1, Vector3(0.7, 1.0, 1.1), STONE_LIGHT)
		_merlons(b, Vector3(gx + 3.6, ty, gz - 3.6), Vector3(gx + 3.6, ty, gz + 3.6), 1.1, Vector3(0.7, 1.0, 1.1), STONE_LIGHT)
		b.cone(xf(gx, 12.5, gz), 5.4, 5.0, 4, SLATE)
		_window(b, xf(gx, 9.8, gz + 3.5), 0.6, 1.4)
		banners.append([Vector3(gx, 11.0, gz + 3.6), 0.0, 1.6, 4.2, RED])
		torches.append([Vector3(sx * (G * 0.5 - 0.1), 3.0, hd + 0.4), -sx * PI * 0.5])
		torches.append([Vector3(sx * (G * 0.5 + 0.7), 3.0, gz + 3.55), 0.0])
	# Rastrillo levantado
	var bar_x := -G * 0.5 + 0.4
	while bar_x < G * 0.5:
		b.box(xf(bar_x, 4.6, hd - 0.9), Vector3(0.12, 1.8, 0.12), STONE_DARK, false)
		b.cone(xf(bar_x, 3.4, hd - 0.9), 0.1, 0.35, 4, STONE_DARK)
		bar_x += 0.55
	for yy in [4.2, 5.2]:
		b.box(xf(0.0, yy, hd - 0.9), Vector3(G, 0.1, 0.1), STONE_DARK, false)

	# --- Salón del trono (torreón)
	var kz := -6.0
	var kw := 18.0
	var kd := 14.0
	var kh := 10.0
	var kt := 1.4
	var dg := 3.6
	_hall_wall(b, 0.0, kz - kd * 0.5 + kt * 0.5, kw, kt, kh)
	_hall_wall(b, -kw * 0.5 + kt * 0.5, kz, kt, kd - kt * 2.0, kh)
	_hall_wall(b, kw * 0.5 - kt * 0.5, kz, kt, kd - kt * 2.0, kh)
	var fseg := (kw - dg) * 0.5
	var fz := kz + kd * 0.5 - kt * 0.5
	_hall_wall(b, -(kw + dg) * 0.25, fz, fseg, kt, kh)
	_hall_wall(b, (kw + dg) * 0.25, fz, fseg, kt, kh)
	b.box(xf(0.0, 4.6 + (kh - 4.6) * 0.5, fz), Vector3(dg, kh - 4.6, kt), KEEP_STONE)
	b.box(xf(-dg * 0.5 - 0.1, 2.3, kz + kd * 0.5 + 0.1), Vector3(0.3, 4.6, 0.5), TIMBER, false)
	b.box(xf(dg * 0.5 + 0.1, 2.3, kz + kd * 0.5 + 0.1), Vector3(0.3, 4.6, 0.5), TIMBER, false)
	b.box(xf(0.0, 4.75, kz + kd * 0.5 + 0.1), Vector3(dg + 0.9, 0.35, 0.5), TIMBER, false)
	b.gable_roof(xf(0.0, kh, kz), kw, kd, 6.0, SLATE, 0.9, 0.25)
	var kgable := PackedVector2Array([Vector2(-kw * 0.5, 0.0), Vector2(kw * 0.5, 0.0), Vector2(0.0, 6.0)])
	b.extrude(xf(0.0, kh, kz + kd * 0.5 - kt * 0.5), kgable, kt, KEEP_STONE)
	b.extrude(xf(0.0, kh, kz - kd * 0.5 + kt * 0.5), kgable, kt, KEEP_STONE)
	for i in 5:
		b.box(xf(0.0, kh + 0.25, kz - kd * 0.5 + 1.5 + i * 2.6), Vector3(kw - 0.2, 0.32, 0.32), TIMBER, false)
	for wz in [-4.0, 0.0, 4.0]:
		_window(b, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(kw * 0.5, 5.5, kz + wz)), 0.7, 1.9)
		_window(b, Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-kw * 0.5, 5.5, kz + wz)), 0.7, 1.9)
	for sx in [-1.0, 1.0]:
		var sg: float = sx
		_window(b, xf(sg * 6.5, 6.0, kz + kd * 0.5), 0.8, 2.0)
		banners.append([Vector3(sg * 4.0, kh - 1.2, kz + kd * 0.5 + 0.1), 0.0, 1.8, 5.0, RED])
	# Torretas en las esquinas del torreón
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var tx: float = sx * kw * 0.5
			var tz: float = kz + sz * kd * 0.5
			b.cylinder(xf(tx, -1.0, tz), 1.5, kh + 4.0, 8, KEEP_STONE, true, 1.4)
			b.cone(xf(tx, kh + 3.0, tz), 2.1, 3.6, 8, RED)

	# --- Interior del salón: alfombra, tarima, trono, pilares, banderas y antorchas
	var zb := kz - kd * 0.5 + kt
	b.box(xf(0.0, FLOOR_Y + 0.015, kz + 0.5), Vector3(2.6, 0.03, kd - 2.0), RED, false)
	b.box(xf(0.0, FLOOR_Y + 0.05, zb + 2.2), Vector3(9.0, 0.1, 4.4), STONE_LIGHT, false)
	b.box(xf(0.0, FLOOR_Y + 0.15, zb + 1.6), Vector3(6.4, 0.1, 3.2), STONE, false)
	b.box(xf(0.0, 0.7, zb + 1.3), Vector3(1.4, 0.9, 1.2), WOOD)
	b.box(xf(0.0, 1.0, zb + 1.35), Vector3(1.1, 0.14, 0.9), RED, false)
	b.box(xf(0.0, 1.9, zb + 0.8), Vector3(1.6, 3.0, 0.3), TIMBER, false)
	for sx in [-1.0, 1.0]:
		var sg: float = sx
		b.box(xf(sg * 0.8, 1.2, zb + 1.3), Vector3(0.22, 0.9, 1.1), TIMBER, false)
		b.cone(xf(sg * 0.7, 3.4, zb + 0.8), 0.18, 0.7, 4, GOLD)
		b.box(xf(sg * 5.0, 3.0, zb + 0.2), Vector3(0.1, 0.1, 0.1), GOLD, false)
		banners.append([Vector3(sg * 5.0, kh - 1.0, zb + 0.15), 0.0, 2.0, 5.2, RED])
		torches.append([Vector3(sg * 3.4, 3.0, zb + 0.15), 0.0])
		torches.append([Vector3(sg * 3.4, 3.0, kz + kd * 0.5 - kt - 0.12), PI])
		for pz in [-2.5, 2.5]:
			b.box(xf(sg * 5.5, kh * 0.5, kz + pz), Vector3(0.6, kh, 0.6), TIMBER)
	b.cone(xf(0.0, 3.0, zb + 0.8), 0.22, 0.9, 4, GOLD)

	# --- Rampas para subir a los muros (una a cada lado)
	var a := deg_to_rad(24.0)
	var run := wh / tan(a)
	var length := wh / sin(a)
	for side in [-1.0, 1.0]:
		var s: float = side
		var rx: float = s * (hw - wt - 1.6)
		var z_low := hd - wt - 3.0
		var z_mid := z_low - run * 0.5
		b.box(Transform3D(Basis(Vector3.RIGHT, a), Vector3(rx, wh * 0.5 - 0.25 * cos(a), z_mid - 0.25 * sin(a))),
			Vector3(3.2, 0.5, length), STONE_LIGHT)
		b.box(xf(rx, wh - 0.25, z_low - run - 1.5), Vector3(3.2, 0.5, 3.0), STONE_LIGHT)

	var root := b.build("Castle")
	_attach_banners(root, banners)
	for t in torches:
		var torch := make_torch()
		torch.position = t[0]
		torch.rotation.y = t[1]
		root.add_child(torch)

	# Patio: pozo, barriles, cajas y heno
	_put(root, make_well(), Vector3(-8.0, 0.0, 9.0))
	_put(root, make_stall(seed_value + 1), Vector3(9.0, 0.0, 10.0), -0.4)
	_put(root, make_campfire(seed_value), Vector3(0.0, 0.0, 6.0))
	for i in 5:
		_put(root, make_barrel(seed_value + i), Vector3(-15.0 + (i % 3) * 0.95, 0.0, -2.0 + (i / 3) * 0.95))
	for i in 3:
		_put(root, make_crate(seed_value + i), Vector3(15.0 - i * 0.9, 0.0, -13.0), rng.randf() * PI)
	_put(root, make_crate(seed_value + 9), Vector3(14.6, 0.85, -13.0), 0.4)
	_put(root, make_hay(seed_value), Vector3(-15.0, 0.0, -13.0), 0.3)
	root.set_meta("size", Vector2(W, D))
	return root


static func _put(parent: Node3D, node: Node3D, pos: Vector3, yaw: float = 0.0) -> void:
	node.position = pos
	node.rotation.y = yaw
	parent.add_child(node)


## Muro recto del castillo. Baja bajo tierra por si el suelo tiene pendiente y lleva dos franjas de piedra clara.
static func _wall(b, cx: float, cz: float, sx: float, sz: float, wh: float) -> void:
	b.box(xf(cx, (wh - 2.0) * 0.5, cz), Vector3(sx, wh + 2.0, sz), STONE)
	for y in [2.6, 5.4]:
		if sx >= sz:
			b.box(xf(cx, y, cz), Vector3(sx, 0.22, sz + 0.14), STONE_LIGHT, false)
		else:
			b.box(xf(cx, y, cz), Vector3(sx + 0.14, 0.22, sz), STONE_LIGHT, false)


static func _hall_wall(b, cx: float, cz: float, sx: float, sz: float, kh: float) -> void:
	b.box(xf(cx, (kh - 2.0) * 0.5, cz), Vector3(sx, kh + 2.0, sz), KEEP_STONE)
	for y in [3.4, 7.0]:
		if sx >= sz:
			b.box(xf(cx, y, cz), Vector3(sx, 0.2, sz + 0.12), STONE_LIGHT, false)
		else:
			b.box(xf(cx, y, cz), Vector3(sx + 0.12, 0.2, sz), STONE_LIGHT, false)


## Almenas: bloques separados a lo largo de una línea. size = (grosor, alto, largo).
static func _merlons(b, a: Vector3, c: Vector3, spacing: float, size: Vector3, col: Color) -> void:
	var dir := c - a
	var length := dir.length()
	if length < 0.01:
		return
	var dn := dir / length
	var yaw := atan2(dn.x, dn.z)
	var n := int(length / spacing)
	for i in n:
		if i % 2 == 1:
			continue
		b.box(Transform3D(Basis(Vector3.UP, yaw), a + dn * (spacing * (i + 0.5))), size, col, false)
