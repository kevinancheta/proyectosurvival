extends RefCounted
## Arma estructuras (casas, torres, castillos) combinando cajas, techos, cilindros y conos
## en UNA sola malla con colores por vértice, y recuerda las colisiones para armarlas después.
## Todas las funciones reciben un Transform3D "t" con la posición y el giro de la pieza.

const AXES := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]

var st := SurfaceTool.new()
var colliders: Array = []        # cada uno: {"type": "box"|"cyl", "xf": Transform3D, ...}
var shade_jitter := 0.045        # variación de tono entre caras, para el aspecto "pintado a mano"
var _rng := RandomNumberGenerator.new()


func _init(seed_value: int = 1) -> void:
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_rng.seed = seed_value


# ------------------------------------------------------------ primitivas

## Caja. t.origin es el centro. Si collide es true, también suma una colisión.
func box(t: Transform3D, size: Vector3, col: Color, collide: bool = true) -> void:
	var h := size * 0.5
	for axis in AXES:
		var n: Vector3 = axis
		var u := Vector3(n.y, n.z, n.x)
		var v := n.cross(u)
		var hu := absf(u.x) * h.x + absf(u.y) * h.y + absf(u.z) * h.z
		var hv := absf(v.x) * h.x + absf(v.y) * h.y + absf(v.z) * h.z
		var c := n * h
		var f := _face_color(col, n)
		var want := t.basis * n
		var p0 := t * (c - u * hu - v * hv)
		var p1 := t * (c + u * hu - v * hv)
		var p2 := t * (c + u * hu + v * hv)
		var p3 := t * (c - u * hu + v * hv)
		_tri(p0, p1, p2, f, want)
		_tri(p0, p2, p3, f, want)
	if collide:
		add_box_collider(t, size)


## Cilindro (o tronco de cono) parado sobre t.origin, con "sides" lados.
func cylinder(t: Transform3D, radius: float, height: float, sides: int, col: Color,
		collide: bool = true, top_radius: float = -1.0, cap: bool = true) -> void:
	var r2 := radius if top_radius < 0.0 else top_radius
	var phase := PI / sides
	for i in sides:
		var a0 := phase + TAU * i / sides
		var a1 := phase + TAU * (i + 1) / sides
		var b0 := t * Vector3(cos(a0) * radius, 0.0, sin(a0) * radius)
		var b1 := t * Vector3(cos(a1) * radius, 0.0, sin(a1) * radius)
		var t0 := t * Vector3(cos(a0) * r2, height, sin(a0) * r2)
		var t1 := t * Vector3(cos(a1) * r2, height, sin(a1) * r2)
		var am := (a0 + a1) * 0.5
		var out := Vector3(cos(am), 0.0, sin(am))
		var f := _face_color(col, out)
		_tri(b0, b1, t1, f, t.basis * out)
		_tri(b0, t1, t0, f, t.basis * out)
		if cap and r2 > 0.0:
			var tc := t * Vector3(0.0, height, 0.0)
			_tri(t0, t1, tc, _face_color(col, Vector3.UP), t.basis * Vector3.UP)
	if collide:
		colliders.append({
			"type": "cyl",
			"xf": Transform3D(t.basis, t * Vector3(0.0, height * 0.5, 0.0)),
			"radius": radius, "height": height,
		})


## Cono (techo de torre). Con sides = 4 sale una pirámide de base cuadrada.
func cone(t: Transform3D, radius: float, height: float, sides: int, col: Color) -> void:
	cylinder(t, radius, height, sides, col, false, 0.0, false)


## Techo a dos aguas. t.origin es el centro de la parte de arriba de las paredes y
## la cumbrera corre a lo largo de Z. "rise" es lo que sube la cumbrera.
func gable_roof(t: Transform3D, width: float, depth: float, rise: float, col: Color,
		overhang: float = 0.55, thick: float = 0.2) -> void:
	var half_w := width * 0.5
	var ang := atan2(rise, half_w)
	var run := half_w + overhang
	var length := run / cos(ang)
	for side in [-1.0, 1.0]:
		var s: float = side
		var eave := Vector2(s * run, rise - run * tan(ang))
		var ridge := Vector2(0.0, rise)
		var mid := (eave + ridge) * 0.5 + Vector2(s * sin(ang), cos(ang)) * thick * 0.5
		var basis := Basis(Vector3.BACK, -s * ang)
		box(t * Transform3D(basis, Vector3(mid.x, mid.y, 0.0)),
			Vector3(length, thick, depth + overhang * 2.0), col, false)
	box(t * Transform3D(Basis.IDENTITY, Vector3(0.0, rise + 0.08, 0.0)),
		Vector3(0.34, 0.26, depth + overhang * 2.0 + 0.1), col.darkened(0.3), false)


## Silueta plana (en X e Y) con grosor "thick" en Z. Sirve para los triángulos de los
## frentes del techo, las hojas de las herramientas, etc.
func extrude(t: Transform3D, pts: PackedVector2Array, thick: float, col: Color) -> void:
	var h := thick * 0.5
	var idx := Geometry2D.triangulate_polygon(pts)
	for i in range(0, idx.size(), 3):
		var a := pts[idx[i]]
		var b := pts[idx[i + 1]]
		var c := pts[idx[i + 2]]
		_tri(t * Vector3(a.x, a.y, h), t * Vector3(b.x, b.y, h), t * Vector3(c.x, c.y, h),
			_face_color(col, Vector3.BACK), t.basis * Vector3.BACK)
		_tri(t * Vector3(a.x, a.y, -h), t * Vector3(b.x, b.y, -h), t * Vector3(c.x, c.y, -h),
			_face_color(col, Vector3.FORWARD), t.basis * Vector3.FORWARD)
	var area := 0.0
	for i in pts.size():
		var p := pts[i]
		var q := pts[(i + 1) % pts.size()]
		area += p.x * q.y - q.x * p.y
	var winding := 1.0 if area > 0.0 else -1.0
	for i in pts.size():
		var p := pts[i]
		var q := pts[(i + 1) % pts.size()]
		var e := q - p
		var out := Vector2(e.y, -e.x) * winding
		var want := t.basis * Vector3(out.x, out.y, 0.0)
		var f := _face_color(col, Vector3(out.x, out.y, 0.0).normalized())
		var pf := t * Vector3(p.x, p.y, h)
		var qf := t * Vector3(q.x, q.y, h)
		var qb := t * Vector3(q.x, q.y, -h)
		var pb := t * Vector3(p.x, p.y, -h)
		_tri(pf, qf, qb, f, want)
		_tri(pf, qb, pb, f, want)


# ------------------------------------------------------------- colisiones

func add_box_collider(t: Transform3D, size: Vector3) -> void:
	colliders.append({"type": "box", "xf": t, "size": size})


# ----------------------------------------------------------- resultado

## Devuelve un Node3D con la malla y, si hay, un StaticBody3D con todas las colisiones.
func build(node_name: String = "Structure") -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 1.0
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	root.add_child(mi)
	if not colliders.is_empty():
		var body := StaticBody3D.new()
		body.name = "Body"
		for c in colliders:
			var cs := CollisionShape3D.new()
			if c["type"] == "box":
				var shape := BoxShape3D.new()
				shape.size = c["size"]
				cs.shape = shape
			else:
				var shape := CylinderShape3D.new()
				shape.radius = c["radius"]
				shape.height = c["height"]
				cs.shape = shape
			cs.transform = c["xf"]
			body.add_child(cs)
		root.add_child(body)
	return root


# ---------------------------------------------------------------- interno

## Triángulo plano. "want" es hacia dónde debe mirar la cara; el giro se corrige solo.
func _tri(a: Vector3, b: Vector3, c: Vector3, col: Color, want: Vector3) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 0.0000001:
		return
	if n.dot(want) < 0.0:
		var tmp := b
		b = c
		c = tmp
		n = -n
	n = n.normalized()
	for v in [a, b, c]:
		st.set_normal(n)
		st.set_color(col)
		st.add_vertex(v)


func _face_color(col: Color, n: Vector3) -> Color:
	var s := _rng.randf_range(-shade_jitter, shade_jitter)
	if n.y > 0.5:
		s += 0.07
	elif n.y < -0.5:
		s -= 0.2
	else:
		s -= 0.03 * absf(n.x)
	return col.lightened(s) if s >= 0.0 else col.darkened(-s)
