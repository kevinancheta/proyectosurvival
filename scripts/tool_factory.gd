extends RefCounted
## Fabrica las herramientas que se ven en primera persona: hacha y pico de piedra.
## El origen de cada herramienta es el extremo de abajo del mango, que apunta hacia +Y.
## Uso: ToolFactory.make("axe") o ToolFactory.make("pickaxe").

const WOOD := Color(0.46, 0.31, 0.18)
const STONE := Color(0.38, 0.40, 0.44)


static func make(tool_id: String) -> Node3D:
	var root := Node3D.new()
	root.name = tool_id
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 1.0

	_add(root, _extrude(_handle_profile(), 0.04, WOOD), mat)
	if tool_id == "pickaxe":
		_add(root, _extrude(_pickaxe_profile(), 0.035, STONE), mat)
	else:
		_add(root, _extrude(_axe_profile(), 0.045, STONE), mat)
	return root


static func _add(root: Node3D, mesh: Mesh, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


# ---------------------------------------------------------------- perfiles
# Cada herramienta es una silueta plana (en X e Y) a la que se le da grosor.

static func _handle_profile() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-0.024, -0.03), Vector2(0.024, -0.03), Vector2(0.017, 0.06),
		Vector2(0.015, 0.44), Vector2(-0.015, 0.44), Vector2(-0.017, 0.06),
	])


## Hoja del hacha: se ensancha desde el mango hacia el filo, que sale a la derecha.
static func _axe_profile() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-0.035, 0.31), Vector2(0.035, 0.31), Vector2(0.17, 0.235),
		Vector2(0.195, 0.35), Vector2(0.17, 0.465), Vector2(0.035, 0.42),
		Vector2(-0.035, 0.42),
	])


## Cabeza del pico: una barra curvada con las dos puntas hacia abajo.
static func _pickaxe_profile() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-0.21, 0.365), Vector2(-0.12, 0.40), Vector2(-0.04, 0.412),
		Vector2(0.04, 0.412), Vector2(0.12, 0.40), Vector2(0.21, 0.365),
		Vector2(0.135, 0.435), Vector2(0.045, 0.462), Vector2(-0.045, 0.462),
		Vector2(-0.135, 0.435),
	])


# ------------------------------------------------------------- geometría

## Triángulo con normal plana. "want" es hacia dónde debe mirar la cara (se corrige el giro si hace falta).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color, want: Vector3) -> void:
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


## Convierte una silueta plana en un sólido con grosor "thick" (en Z).
static func _extrude(pts: PackedVector2Array, thick: float, col: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := thick * 0.5

	var idx := Geometry2D.triangulate_polygon(pts)
	for i in range(0, idx.size(), 3):
		var a := pts[idx[i]]
		var b := pts[idx[i + 1]]
		var c := pts[idx[i + 2]]
		_tri(st, Vector3(a.x, a.y, h), Vector3(b.x, b.y, h), Vector3(c.x, c.y, h), col, Vector3.BACK)
		_tri(st, Vector3(a.x, a.y, -h), Vector3(b.x, b.y, -h), Vector3(c.x, c.y, -h), col.darkened(0.12), Vector3.FORWARD)

	# Los costados. El signo del área dice hacia qué lado está "afuera".
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
		var want := Vector3(out.x, out.y, 0.0)
		var side_col := col.lightened(0.08) if out.y > 0.0 else col.darkened(0.22)
		var pf := Vector3(p.x, p.y, h)
		var qf := Vector3(q.x, q.y, h)
		var qb := Vector3(q.x, q.y, -h)
		var pb := Vector3(p.x, p.y, -h)
		_tri(st, pf, qf, qb, side_col, want)
		_tri(st, pf, qb, pb, side_col, want)
	return st.commit()
