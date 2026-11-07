class_name MeshUtil
extends RefCounted
## Small helpers for building gray-box geometry with SurfaceTool.


## Adds quad v0-v1-v2-v3 facing `n`, swapping winding as needed
## (Godot treats clockwise triangles as front faces).
static func quad(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3, n: Vector3,
		uv0 := Vector2.ZERO, uv1 := Vector2.ZERO, uv2 := Vector2.ZERO, uv3 := Vector2.ZERO) -> void:
	var verts := [v0, v1, v2, v0, v2, v3]
	var uvs := [uv0, uv1, uv2, uv0, uv2, uv3]
	if (v1 - v0).cross(v2 - v0).dot(n) > 0.0:
		verts = [v0, v2, v1, v0, v3, v2]
		uvs = [uv0, uv2, uv1, uv0, uv3, uv2]
	for i in 6:
		st.set_normal(n)
		st.set_uv(uvs[i])
		st.add_vertex(verts[i])


static func material(color: Color, roughness := 0.5, metallic := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m


## Orthonormal, right-handed basis with x along `along` and z along `normal` (both horizontal-ish).
static func basis_from(along: Vector3, up: Vector3, normal: Vector3) -> Basis:
	var x := along.normalized()
	var z := normal.normalized()
	var y := z.cross(x).normalized()
	if y.dot(up) < 0.0:
		x = -x
		y = -y
	return Basis(x, y, z)
