extends RefCounted
## Fabrica árboles y arbustos low-poly con irregularidades, para que el bosque no se vea repetido.
## Cada función devuelve una malla con colores por vértice. El origen de la malla está en el suelo.
## Uso: TreeFactory.make_pine(semilla), make_oak(semilla), make_dead(semilla), make_bush(semilla).

static func make_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 1.0
	return mat


# ------------------------------------------------------------------ pino

static func make_pine(seed_value: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var h := rng.randf_range(8.5, 11.0)
	var lean := Vector3(rng.randf_range(-0.3, 0.3), 0.0, rng.randf_range(-0.3, 0.3))
	var bark_dark := Color(0.20, 0.13, 0.08)
	var bark_light := Color(0.36, 0.25, 0.16)

	var centers: Array[Vector3] = [
		Vector3(0.0, -0.4, 0.0),
		Vector3(0.0, 0.5, 0.0),
		lean * 0.3 + Vector3(0.0, h * 0.5, 0.0),
		lean + Vector3(0.0, h * 0.9, 0.0),
	]
	var radii: Array[float] = [0.85, 0.52, 0.38, 0.16]
	var colors: Array[Color] = [bark_dark, bark_dark.lerp(bark_light, 0.3), bark_light.lerp(bark_dark, 0.3), bark_light]
	_rings(st, centers, radii, colors, 7, rng, 0.08)

	var tiers := rng.randi_range(6, 7)
	for k in tiers:
		var t := float(k) / float(tiers - 1)
		var y := lerpf(2.0, h * 0.86, t)
		var radius := lerpf(2.7, 0.8, t) * rng.randf_range(0.9, 1.1)
		var height := lerpf(2.6, 1.7, t)
		var base := Vector3(lean.x * t + rng.randf_range(-0.2, 0.2), y, lean.z * t + rng.randf_range(-0.2, 0.2))
		var c_low := Color(0.08, 0.25, 0.11).lerp(Color(0.11, 0.32, 0.15), t)
		var c_high := Color(0.14, 0.38, 0.18).lerp(Color(0.20, 0.47, 0.22), t)
		_cone(st, base, radius, height, 9, rng, c_low, c_high, 0.5)

	return st.commit()


# ------------------------------------------------------------------ roble

static func make_oak(seed_value: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var h := rng.randf_range(3.2, 4.4)
	var lean := Vector3(rng.randf_range(-0.25, 0.25), 0.0, rng.randf_range(-0.25, 0.25))
	var bark_dark := Color(0.22, 0.15, 0.09)
	var bark_light := Color(0.40, 0.29, 0.19)

	var centers: Array[Vector3] = [
		Vector3(0.0, -0.4, 0.0),
		Vector3(0.0, 0.6, 0.0),
		lean * 0.5 + Vector3(0.0, h * 0.6, 0.0),
		lean + Vector3(0.0, h, 0.0),
	]
	var radii: Array[float] = [1.0, 0.7, 0.55, 0.42]
	var colors: Array[Color] = [bark_dark, bark_dark.lerp(bark_light, 0.4), bark_light, bark_light.lerp(bark_dark, 0.3)]
	_rings(st, centers, radii, colors, 7, rng, 0.1)

	# Ramas gruesas que salen del tronco hacia la copa
	for i in 3:
		var ang := TAU * i / 3.0 + rng.randf() * 0.8
		var dir := Vector3(cos(ang), 0.8, sin(ang)).normalized()
		var p0 := lean * 0.6 + Vector3(0.0, h * 0.7, 0.0)
		var p1 := p0 + dir * rng.randf_range(1.6, 2.4)
		_limb(st, p0, p1, 0.28, 0.12, 5, bark_light, bark_dark)

	# Copa: varias masas de hojas irregulares y apiladas
	var low := Color(0.15, 0.31, 0.09)
	var high := Color(0.38, 0.56, 0.17)
	_blob(st, lean + Vector3(0.0, h + 1.3, 0.0), 2.4, 0.85, rng, low, high)
	var blobs := rng.randi_range(5, 7)
	for i in blobs:
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.6, 2.2)
		var c := lean + Vector3(cos(a) * d, h + rng.randf_range(0.5, 2.7), sin(a) * d)
		_blob(st, c, rng.randf_range(1.4, 2.2), 0.85, rng, low, high)

	return st.commit()


# ------------------------------------------------------------ árbol seco

static func make_dead(seed_value: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var h := rng.randf_range(6.0, 8.0)
	var lean := Vector3(rng.randf_range(-0.4, 0.4), 0.0, rng.randf_range(-0.4, 0.4))
	var wood_dark := Color(0.22, 0.19, 0.16)
	var wood_light := Color(0.42, 0.37, 0.31)

	var centers: Array[Vector3] = [
		Vector3(0.0, -0.4, 0.0),
		Vector3(0.0, 0.5, 0.0),
		lean * 0.5 + Vector3(0.0, h * 0.5, 0.0),
		lean + Vector3(0.0, h, 0.0),
	]
	var radii: Array[float] = [0.8, 0.5, 0.32, 0.1]
	var colors: Array[Color] = [wood_dark, wood_dark.lerp(wood_light, 0.4), wood_light, wood_light]
	_rings(st, centers, radii, colors, 6, rng, 0.1)

	var limbs := rng.randi_range(4, 5)
	for i in limbs:
		var f := rng.randf_range(0.35, 0.85)
		var ang := rng.randf() * TAU
		var dir := Vector3(cos(ang), rng.randf_range(0.3, 0.9), sin(ang)).normalized()
		var p0 := lean * f + Vector3(0.0, h * f, 0.0)
		var p1 := p0 + dir * rng.randf_range(1.5, 2.8)
		_limb(st, p0, p1, 0.16, 0.04, 5, wood_light, wood_dark)
		# Ramita que sale de la rama
		var dir2 := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(0.2, 0.8), rng.randf_range(-1.0, 1.0)).normalized()
		var p2 := p0.lerp(p1, 0.6)
		_limb(st, p2, p2 + dir2 * rng.randf_range(0.8, 1.4), 0.06, 0.02, 4, wood_light, wood_dark)

	return st.commit()


# --------------------------------------------------------------- arbusto

static func make_bush(seed_value: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var low := Color(0.12, 0.27, 0.09)
	var high := Color(0.28, 0.46, 0.15)
	var blobs := rng.randi_range(2, 3)
	for i in blobs:
		var c := Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(0.3, 0.5), rng.randf_range(-0.5, 0.5))
		_blob(st, c, rng.randf_range(0.6, 0.95), 0.75, rng, low, high, 3, 6)
	return st.commit()


# ---------------------------------------------------------------- pasto

## Mata de pasto: unas hojas finas inclinadas, oscuras en la base y claras en la punta.
static func make_grass(seed_value: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var blades := 6
	for i in blades:
		var a := TAU * i / blades + rng.randf_range(-0.3, 0.3)
		var dist := rng.randf_range(0.0, 0.18)
		var base := Vector3(cos(a) * dist, 0.0, sin(a) * dist)
		var h := rng.randf_range(0.28, 0.6)
		var lean := Vector3(rng.randf_range(-0.12, 0.12), 0.0, rng.randf_range(-0.12, 0.12))
		var side := Vector3(-sin(a), 0.0, cos(a)) * 0.05
		var c0 := Color(0.17, 0.26, 0.09)
		var c1 := Color(0.48, 0.56, 0.22)
		var pts := [base - side, base + side, base + Vector3(0.0, h, 0.0) + lean]
		var cols := [c0, c0, c1]
		for k in 3:
			st.set_normal(Vector3.UP)
			st.set_color(cols[k])
			st.add_vertex(pts[k])
	return st.commit()


## El pasto se ve de los dos lados, por eso no se descartan las caras traseras.
static func make_grass_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	return mat


# ------------------------------------------------------------ geometría

## Agrega un triángulo con normal plana. Se orienta solo hacia afuera, alejándose del punto "inside".
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color, inside: Vector3) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 0.000001:
		return
	n = n.normalized()
	if n.dot((a + b + c) / 3.0 - inside) < 0.0:
		var tmp := b
		b = c
		c = tmp
		var tmp_c := cb
		cb = cc
		cc = tmp_c
		n = -n
	st.set_normal(n)
	st.set_color(ca)
	st.add_vertex(a)
	st.set_normal(n)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_normal(n)
	st.set_color(cc)
	st.add_vertex(c)


## Tronco hecho con anillos horizontales unidos entre sí.
static func _rings(st: SurfaceTool, centers: Array[Vector3], radii: Array[float], colors: Array[Color], sides: int, rng: RandomNumberGenerator, jitter: float) -> void:
	var rings: Array = []
	var phase := rng.randf() * TAU
	for k in centers.size():
		var ring: Array[Vector3] = []
		for i in sides:
			var a := phase + TAU * i / sides + rng.randf_range(-0.12, 0.12)
			var r := radii[k] * (1.0 + rng.randf_range(-jitter, jitter))
			ring.append(centers[k] + Vector3(cos(a) * r, 0.0, sin(a) * r))
		rings.append(ring)

	for k in centers.size() - 1:
		var inside := (centers[k] + centers[k + 1]) * 0.5
		for i in sides:
			var j := (i + 1) % sides
			var a0: Vector3 = rings[k][i]
			var a1: Vector3 = rings[k][j]
			var b0: Vector3 = rings[k + 1][i]
			var b1: Vector3 = rings[k + 1][j]
			_tri(st, a0, a1, b1, colors[k], colors[k], colors[k + 1], inside)
			_tri(st, a0, b1, b0, colors[k], colors[k + 1], colors[k + 1], inside)

	# Tapa de arriba
	var last := centers.size() - 1
	var top_ring: Array = rings[last]
	for i in sides:
		var p: Vector3 = top_ring[i]
		var q: Vector3 = top_ring[(i + 1) % sides]
		_tri(st, p, q, centers[last], colors[last], colors[last], colors[last], centers[last - 1])


## Rama: un cilindro fino entre dos puntos cualesquiera.
static func _limb(st: SurfaceTool, p0: Vector3, p1: Vector3, r0: float, r1: float, sides: int, c0: Color, c1: Color) -> void:
	var axis := (p1 - p0).normalized()
	var ref := Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT
	var u := axis.cross(ref).normalized()
	var v := axis.cross(u).normalized()
	var inside := (p0 + p1) * 0.5
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var d0 := u * cos(a0) + v * sin(a0)
		var d1 := u * cos(a1) + v * sin(a1)
		var q00 := p0 + d0 * r0
		var q01 := p0 + d1 * r0
		var q10 := p1 + d0 * r1
		var q11 := p1 + d1 * r1
		_tri(st, q00, q01, q11, c0, c0, c1, inside)
		_tri(st, q00, q11, q10, c0, c1, c1, inside)
		_tri(st, q10, q11, p1 + axis * 0.05, c1, c1, c1, inside)


## Cono irregular: una "capa" de ramas de pino, con puntas caídas.
static func _cone(st: SurfaceTool, base: Vector3, radius: float, height: float, sides: int, rng: RandomNumberGenerator, c_low: Color, c_high: Color, droop: float) -> void:
	var apex := base + Vector3(rng.randf_range(-0.2, 0.2), height, rng.randf_range(-0.2, 0.2))
	var ring: Array[Vector3] = []
	var phase := rng.randf() * TAU
	for i in sides:
		var a := phase + TAU * i / sides + rng.randf_range(-0.12, 0.12)
		var r := radius * rng.randf_range(0.75, 1.15)
		var dy := -droop * (1.0 if i % 2 == 0 else 0.25) * rng.randf_range(0.5, 1.2)
		ring.append(base + Vector3(cos(a) * r, dy, sin(a) * r))
	var inside := base + Vector3(0.0, height * 0.3, 0.0)
	var bottom := base + Vector3(0.0, -droop * 0.3, 0.0)
	for i in sides:
		var p := ring[i]
		var q := ring[(i + 1) % sides]
		var shade := rng.randf_range(0.0, 0.1)
		_tri(st, p, q, apex, c_low.darkened(shade), c_low.darkened(shade), c_high, inside)
		_tri(st, p, q, bottom, c_low.darkened(0.35), c_low.darkened(0.35), c_low.darkened(0.45), inside)


## Masa de hojas: una esfera de pocos lados con los vértices movidos al azar.
static func _blob(st: SurfaceTool, center: Vector3, radius: float, squash: float, rng: RandomNumberGenerator, low: Color, high: Color, ring_count: int = 4, segs: int = 7) -> void:
	var grid: Array = []
	for r in ring_count + 1:
		var phi := PI * r / ring_count
		var row: Array[Vector3] = []
		var pole_jitter := rng.randf_range(0.8, 1.15)
		for s in segs:
			var theta := TAU * s / segs
			var j := pole_jitter if (r == 0 or r == ring_count) else rng.randf_range(0.78, 1.18)
			var rr := radius * j
			row.append(center + Vector3(sin(phi) * cos(theta) * rr, cos(phi) * rr * squash, sin(phi) * sin(theta) * rr))
		grid.append(row)

	for r in ring_count:
		for s in segs:
			var s2 := (s + 1) % segs
			var p00: Vector3 = grid[r][s]
			var p01: Vector3 = grid[r][s2]
			var p10: Vector3 = grid[r + 1][s]
			var p11: Vector3 = grid[r + 1][s2]
			var shade := rng.randf_range(0.0, 0.08)
			_tri(st, p00, p01, p11, _blob_color(p00, center, radius, low, high).darkened(shade), _blob_color(p01, center, radius, low, high).darkened(shade), _blob_color(p11, center, radius, low, high).darkened(shade), center)
			_tri(st, p00, p11, p10, _blob_color(p00, center, radius, low, high).darkened(shade), _blob_color(p11, center, radius, low, high).darkened(shade), _blob_color(p10, center, radius, low, high).darkened(shade), center)


static func _blob_color(p: Vector3, center: Vector3, radius: float, low: Color, high: Color) -> Color:
	var t := clampf((p.y - center.y) / radius * 0.5 + 0.5, 0.0, 1.0)
	return low.lerp(high, t)
