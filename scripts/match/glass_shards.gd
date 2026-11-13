class_name GlassShards
extends Node3D
## Broken rink glass (Rink.shatter_glass): a burst of shards from the pane that fall,
## tumble, skitter and settle, most out into the seats and some onto the ice. They lie
## there until the repair sweeps them up (Rink.repair_glass frees this node).
##
## One MultiMesh of small flat slivers moved in code: gravity, a bounce and a slide on the
## floor (y = 0 on the ice and outside the boards alike), then they stop.

const COUNT := 150
const GRAVITY := 9.8
const FLOOR := 0.004

var _mm: MultiMesh
var _pos: PackedVector3Array
var _vel: PackedVector3Array
var _axis: PackedVector3Array
var _spin: PackedFloat32Array
var _angle: PackedFloat32Array
var _size: PackedFloat32Array
var _rest: PackedByteArray
var _rng := RandomNumberGenerator.new()


## `c`: the pane's center; `n`: level, toward the ice; `w` x `h`: the pane.
func burst(c: Vector3, n: Vector3, w: float, h: float) -> void:
	_rng.randomize()
	var side := n.cross(Vector3.UP).normalized()
	var mesh := PrismMesh.new()   # a thin wedge reads as a sliver from any side
	mesh.size = Vector3(0.09, 0.07, 0.006)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.86, 0.93, 1.0, 0.5)
	mat.metallic = 0.4
	mat.roughness = 0.04
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material = mat
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.mesh = mesh
	_mm.instance_count = COUNT
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = _mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_pos.resize(COUNT)
	_vel.resize(COUNT)
	_axis.resize(COUNT)
	_spin.resize(COUNT)
	_angle.resize(COUNT)
	_size.resize(COUNT)
	_rest.resize(COUNT)
	for i in COUNT:
		var into_ice := _rng.randf() < 0.35   # the hit drives most of it out into the seats
		var off := side * _rng.randf_range(-w * 0.5, w * 0.5) + Vector3.UP * _rng.randf_range(-h * 0.5, h * 0.5)
		_pos[i] = c + off + n * (0.05 if into_ice else -0.05)
		var out := n if into_ice else -n
		_vel[i] = out * _rng.randf_range(0.6, 3.6) + side * _rng.randf_range(-1.6, 1.6) + Vector3.UP * _rng.randf_range(-0.4, 2.2)
		_axis[i] = Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized()
		_spin[i] = _rng.randf_range(4.0, 18.0)
		_angle[i] = _rng.randf() * TAU
		_size[i] = _rng.randf_range(0.35, 1.7)
		_rest[i] = 0
	_update_instances()


func _physics_process(delta: float) -> void:
	if _mm == null:
		return
	var moving := false
	for i in COUNT:
		if _rest[i] == 1:
			continue
		moving = true
		var v := _vel[i]
		v.y -= GRAVITY * delta
		var p := _pos[i] + v * delta
		if p.y <= FLOOR:
			p.y = FLOOR
			if absf(v.y) > 0.6:
				v.y = -v.y * 0.25           # a little bounce...
				v.x *= 0.55
				v.z *= 0.55
				_spin[i] *= 0.5
			else:
				v.y = 0.0                    # ...then a slide that dies out
				v.x *= maxf(0.0, 1.0 - 3.5 * delta)
				v.z *= maxf(0.0, 1.0 - 3.5 * delta)
				_spin[i] *= maxf(0.0, 1.0 - 6.0 * delta)
				if Vector2(v.x, v.z).length() < 0.05:
					_rest[i] = 1
					_axis[i] = Vector3.RIGHT  # lying flat
					_angle[i] = PI * 0.5
		_vel[i] = v
		_pos[i] = p
		_angle[i] += _spin[i] * delta
	if moving:
		_update_instances()


func _update_instances() -> void:
	for i in COUNT:
		var b := Basis(_axis[i], _angle[i]).scaled(Vector3.ONE * _size[i])
		_mm.set_instance_transform(i, Transform3D(b, _pos[i]))
