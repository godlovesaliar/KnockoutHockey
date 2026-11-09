class_name RefereeVisual
extends SkaterVisual
## The referee's look: no stick, so the hands are placed freely (the rig's ARMS_FREE,
## like the goalie's glove and blocker): down at the hips while skating, one arm straight
## up for a delayed penalty, or pointing (Referee.signal_arm / point_at).

var _raise := 0.0      ## 0 arms down .. 1 the signal arm fully up / out


func _build_stick() -> void:
	super._build_stick()
	shaft.visible = false


func _update_stick(_delta: float) -> void:
	pass


func _after_rig() -> void:
	shaft.visible = false


func _pose(delta: float) -> void:
	super._pose(delta)
	# Officials skate taller than players: less knee bend, less forward lean.
	rig.hips_drop *= 0.4
	rig.lean *= 0.45
	var ref := skater as Referee
	var sig := ref.signal_arm if ref else ""
	_raise = lerpf(_raise, 1.0 if sig != "" else 0.0, _ease(7.0, delta))
	rig.arm_mode = SkaterRig.Arms.FREE
	rig.free_arm = 0.0
	var mt := model.global_transform
	# Model space: +Z behind, -Z in front; the character's left is -X (see GoalieVisual).
	var swing := sin(_stride) * 0.12 * _stride_amt
	var left := Vector3(-0.3, 0.92, -0.05 + swing)
	var right := Vector3(0.3, 0.92, -0.05 - swing)
	if sig == "up":
		right = right.lerp(Vector3(0.18, 2.15, -0.02), _raise)
	elif sig == "point":
		# Straight out toward the point, at shoulder height.
		var to := ref.point_at - global_position
		to.y = 0.0
		var local := mt.basis.inverse() * (to.normalized() if to.length() > 0.1 else -mt.basis.z)
		local.y = 0.0
		var reach := Vector3(0.22, 1.45, 0.0) + local.normalized() * 0.62
		right = right.lerp(reach, _raise)
	rig.hand_world[0] = mt * left
	rig.hand_world[1] = mt * right
	rig.elbow_pole[0] = Vector3(0.8, -0.6, 0.3)
	rig.elbow_pole[1] = Vector3(-0.8, -0.6, 0.3)
