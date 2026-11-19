class_name IceWear
extends Node
## Ice wear over a period: blade cuts, snow and haze build up where the skaters go, and
## the Zamboni sweeps them away between periods (see Zamboni).
##
## Two textures over the rink, read by ice.gdshader:
##   cuts  R8, ~2.5 cm texels: the blade marks. Each skater's two skates draw lines along
##         their stride (the pushing foot carving out and back), so the marks follow how
##         people actually skated; a hockey stop scrapes a wide band.
##   map   RGBA8, ~20 cm texels: R snow (stops, the goalies working their crease),
##         G haze (the shine worn off by traffic), B swept (during a Zamboni pass: where it
##         has been).
## Plus uniforms: `dull` (the whole sheet loses its shine as the period goes on) and `wet`
## (fresh off the Zamboni, glassy, drying over the first minute of play).

const EXT := Vector2(13.06, 30.6)      ## half extents covered (just past the boards)
const CUTS_W := 1024
const CUTS_H := 2400
const MAP_W := 128
const MAP_H := 300
const UPLOAD_EVERY := 0.4              ## seconds between texture uploads while wearing
const DULL_MAX := 0.75                 ## the haze over the whole sheet by the end of a period
const WET_DRY := 50.0                  ## seconds of play for fresh ice to lose its wet gloss

var material: ShaderMaterial
var dull := 0.0:
	set(v):
		dull = v
		if material:
			material.set_shader_parameter("dull", v * DULL_MAX)
var wet := 0.0:
	set(v):
		wet = v
		if material:
			material.set_shader_parameter("wet", v)

var _cuts := PackedByteArray()
var _map := PackedByteArray()
var _cuts_img: Image
var _map_img: Image
var _cuts_tex: ImageTexture
var _map_tex: ImageTexture
var _dirty := false
var _since := 0.0
var _feet := {}        ## skater instance id -> [last left foot, last right foot] (Vector2 or null)
var _sweeping := false
var _inside := PackedByteArray()   ## per map texel: 1 inside the boards (for coverage)
var _inside_total := 0
var _swept := 0                    ## inside texels laid fresh this pass


func setup(mat: ShaderMaterial) -> void:
	material = mat
	_cuts.resize(CUTS_W * CUTS_H)
	_map.resize(MAP_W * MAP_H * 4)
	_cuts_img = Image.create_from_data(CUTS_W, CUTS_H, false, Image.FORMAT_R8, _cuts)
	_cuts_img.generate_mipmaps()
	_cuts_tex = ImageTexture.create_from_image(_cuts_img)
	_map_img = Image.create_from_data(MAP_W, MAP_H, false, Image.FORMAT_RGBA8, _map)
	_map_tex = ImageTexture.create_from_image(_map_img)
	material.set_shader_parameter("wear_cuts", _cuts_tex)
	material.set_shader_parameter("wear_map", _map_tex)
	material.set_shader_parameter("wear_ext", EXT)
	material.set_shader_parameter("sweeping", 0.0)
	dull = 0.0
	wet = 0.0


func _process(delta: float) -> void:
	_since += delta
	if _dirty and _since >= (0.05 if _sweeping else UPLOAD_EVERY):
		upload()


## Pushes the painted wear to the GPU.
func upload() -> void:
	_since = 0.0
	_dirty = false
	_cuts_img.set_data(CUTS_W, CUTS_H, false, Image.FORMAT_R8, _cuts)
	_cuts_img.generate_mipmaps()
	_cuts_tex.update(_cuts_img)
	_map_img.set_data(MAP_W, MAP_H, false, Image.FORMAT_RGBA8, _map)
	_map_tex.update(_map_img)


# --- Wearing ---------------------------------------------------------------------------

## One physics tick of play: everyone on the ice leaves their marks.
func tick(skaters: Array, delta: float) -> void:
	if wet > 0.0:
		wet = maxf(0.0, wet - delta / WET_DRY)
	for s: Skater in skaters:
		if not is_instance_valid(s) or s.benched or not s.visible:
			continue
		if s is Goalie:
			_goalie(s, delta)
		else:
			_skater(s, delta)


func _skater(s: Skater, delta: float) -> void:
	var p := Vector2(s.global_position.x, s.global_position.z)
	var v := Vector2(s.velocity.x, s.velocity.z)
	var spd := v.length()
	var id := s.get_instance_id()
	var last: Array = _feet.get(id, [null, null])
	if s.is_down():
		# Sliding on the backside: a broad smear of haze.
		if spd > 1.0:
			_map_add(p, 1, spd * delta * 60.0, 0.5)
		_feet[id] = [null, null]
		return
	var h := Vector2(s.heading.x, s.heading.z)
	if h.length_squared() < 0.01:
		h = Vector2(0, -1)
	h = h.normalized()
	var r := Vector2(-h.y, h.x)
	var rig: SkaterRig = s.visual.rig if s.visual else null
	var phase := rig.stride_phase if rig else 0.0
	var amt := rig.stride_amt if rig else 0.0
	var stance := rig.stance if rig else 0.15
	var dir := rig.stride_dir if rig else 1.0
	if s.stopping and spd > 2.5:
		# Hockey stop: both blades skid sideways, scraping a wide band and throwing snow.
		var along := v / spd
		var across := Vector2(-along.y, along.x)
		# Each blade skids sideways: a solid band about a blade's length wide.
		for k in 3:
			var off := across * (float(k) - 1.0) * 0.03
			for f in 2:
				var foot := p + r * (stance if f == 0 else -stance)
				_cut_line(foot + off - along * spd * delta, foot + off, 26)
		_map_add(p + v.normalized() * 0.4, 0, spd * delta * 90.0, 0.55)
		_feet[id] = [null, null]
		return
	if spd < 0.4:
		_feet[id] = [null, null]
		return
	# Haze where people skate.
	_map_add(p, 1, spd * delta * 1.6, 0.35)
	var cur := [null, null]
	for f in 2:
		var sx := 1.0 if f == 0 else -1.0
		var ph := phase + (0.0 if f == 0 else PI)
		var lifted := amt > 0.15 and sin(ph) < -0.1
		if lifted:
			continue
		var push := maxf(0.0, sin(ph))
		var foot := p + r * sx * (stance + amt * 0.3 * push) + h * dir * amt * 0.32 * cos(ph)
		cur[f] = foot
		var prev: Variant = last[f]
		if prev != null and (prev as Vector2).distance_squared_to(foot) < 1.0:
			# Deeper cuts on a hard push; a glide just leaves a faint line.
			_cut_line(prev, foot, int(14.0 + 40.0 * push * amt + spd * 1.5))
	_feet[id] = cur


func _goalie(g: Skater, delta: float) -> void:
	var p := Vector2(g.global_position.x, g.global_position.z)
	var v := Vector2(g.velocity.x, g.velocity.z)
	var spd := v.length()
	# Goalies scrape their crease all game: a slow build of snow where they stand, more
	# when they shuffle and push across.
	_map_add(p, 0, delta * 3.0 + spd * delta * 10.0, 0.6)
	if spd > 0.5:
		var across := Vector2(-v.y, v.x) / spd
		for k in 3:
			var off := across * (float(k) - 1.0) * 0.25
			_cut_line(p + off - v * delta, p + off, 30)


## Fills the sheet with a period's worth of skating (testing, the arena viewer).
func prewear(amount: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var strokes := int(amount * 900.0)
	for i in strokes:
		var a := Vector2(rng.randf_range(-11.5, 11.5), rng.randf_range(-28.0, 28.0))
		var ang := rng.randf() * TAU
		var heading := Vector2.from_angle(ang)
		var bend := rng.randf_range(-0.25, 0.25)
		var stride := rng.randf_range(0.0, 1.0)
		var pos := a
		var ph := rng.randf() * TAU
		var last := [pos, pos]
		for step in 40:
			heading = heading.rotated(bend * 0.08)
			pos += heading * 0.18
			if RinkSpec.sdf(pos.x, pos.y) > -0.3:
				break
			ph += 0.45
			var r := Vector2(-heading.y, heading.x)
			for f in 2:
				var q := ph + (0.0 if f == 0 else PI)
				var foot := pos + r * (1.0 if f == 0 else -1.0) * (0.15 + 0.3 * stride * maxf(0.0, sin(q))) + heading * stride * 0.3 * cos(q)
				if stride > 0.15 and sin(q) < -0.1:
					last[f] = foot
					continue
				_cut_line(last[f], foot, int(14.0 + 40.0 * stride))
				last[f] = foot
			_map_add(pos, 1, 0.5, 0.35)
		if rng.randf() < 0.12:
			_map_add(pos, 0, 40.0, 0.5)
	for n in 2:
		var cz := (RinkSpec.GOAL_LINE_Z - 0.9) * (1.0 if n == 0 else -1.0)
		for k in 30:
			_map_add(Vector2(rng.randf_range(-1.0, 1.0), cz), 0, 6.0 * amount, 0.6)
	dull = amount
	upload()


# --- Zamboni ---------------------------------------------------------------------------

## A Zamboni pass begins: the sheet as it is, nothing swept yet.
func begin_sweep() -> void:
	_sweeping = true
	for i in range(2, _map.size(), 4):
		_map[i] = 0
	if _inside.is_empty():
		_inside.resize(MAP_W * MAP_H)
		for y in MAP_H:
			for x in MAP_W:
				var p := Vector2(((x + 0.5) / MAP_W * 2.0 - 1.0) * EXT.x, ((y + 0.5) / MAP_H * 2.0 - 1.0) * EXT.y)
				var inside := RinkSpec.sdf(p.x, p.y) < -0.1
				_inside[y * MAP_W + x] = 1 if inside else 0
				_inside_total += 1 if inside else 0
	_swept = 0
	material.set_shader_parameter("sweeping", 1.0)
	wet = 1.0
	_dirty = true


## The conditioner lays fresh ice `half_width` either side of `at`, from `from`.
func sweep(from: Vector2, at: Vector2, half_width: float) -> void:
	var step := 0.15
	var n := maxi(1, int(ceil(from.distance_to(at) / step)))
	for k in n + 1:
		var q := from.lerp(at, float(k) / n)
		_map_set_b(q, half_width)
	_dirty = true


## How much of the sheet this pass has laid fresh (0..1). Going over ice again adds nothing.
func coverage() -> float:
	return float(_swept) / maxf(1.0, float(_inside_total))


## The coarse map (B: where this pass has been), for a minimap.
func map_texture() -> Texture2D:
	return _map_tex


## The pass is done (or skipped): a clean, shiny sheet.
func reset() -> void:
	_sweeping = false
	_cuts.fill(0)
	_map.fill(0)
	_feet.clear()
	if material:
		material.set_shader_parameter("sweeping", 0.0)
	dull = 0.0
	wet = 1.0
	upload()


# --- Painting --------------------------------------------------------------------------

func _cuts_px(p: Vector2) -> Vector2:
	return Vector2((p.x / EXT.x * 0.5 + 0.5) * CUTS_W, (p.y / EXT.y * 0.5 + 0.5) * CUTS_H)


func _cut_line(a: Vector2, b: Vector2, strength: int) -> void:
	var pa := _cuts_px(a)
	var pb := _cuts_px(b)
	var n := int(ceil(maxf(absf(pb.x - pa.x), absf(pb.y - pa.y))))
	if n <= 0:
		return
	n = mini(n, 200)
	var wide_x := absf(pb.y - pa.y) >= absf(pb.x - pa.x)
	for k in n + 1:
		var q := pa.lerp(pb, float(k) / n)
		var x := int(q.x)
		var y := int(q.y)
		if x < 0 or y < 0 or x >= CUTS_W or y >= CUTS_H:
			continue
		# Two texels across (~5 cm): a cut that still reads from the broadcast camera.
		var i := y * CUTS_W + x
		_cuts[i] = mini(255, _cuts[i] + strength)
		if wide_x and x + 1 < CUTS_W:
			_cuts[i + 1] = mini(255, _cuts[i + 1] + (strength >> 1))
		elif not wide_x and y + 1 < CUTS_H:
			_cuts[i + CUTS_W] = mini(255, _cuts[i + CUTS_W] + (strength >> 1))
	_dirty = true


func _map_add(p: Vector2, ch: int, amount: float, radius: float) -> void:
	var cx := (p.x / EXT.x * 0.5 + 0.5) * MAP_W
	var cy := (p.y / EXT.y * 0.5 + 0.5) * MAP_H
	var rx := radius / (EXT.x * 2.0) * MAP_W
	var ry := radius / (EXT.y * 2.0) * MAP_H
	for y in range(int(cy - ry), int(cy + ry) + 1):
		if y < 0 or y >= MAP_H:
			continue
		for x in range(int(cx - rx), int(cx + rx) + 1):
			if x < 0 or x >= MAP_W:
				continue
			var d := Vector2((x + 0.5 - cx) / maxf(rx, 0.5), (y + 0.5 - cy) / maxf(ry, 0.5)).length()
			if d > 1.0:
				continue
			var i := (y * MAP_W + x) * 4 + ch
			var add := amount * (1.0 - d)
			if add > 0.0:
				# Fractions round up now and then so slow builds still build.
				_map[i] = mini(255, _map[i] + int(add) + (1 if randf() < fmod(add, 1.0) else 0))
	_dirty = true


func _map_set_b(p: Vector2, half_width: float) -> void:
	var cx := (p.x / EXT.x * 0.5 + 0.5) * MAP_W
	var cy := (p.y / EXT.y * 0.5 + 0.5) * MAP_H
	var rx := half_width / (EXT.x * 2.0) * MAP_W
	var ry := half_width / (EXT.y * 2.0) * MAP_H
	for y in range(int(cy - ry), int(cy + ry) + 1):
		if y < 0 or y >= MAP_H:
			continue
		for x in range(int(cx - rx), int(cx + rx) + 1):
			if x < 0 or x >= MAP_W:
				continue
			if Vector2((x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry).length() <= 1.0:
				var i := (y * MAP_W + x) * 4 + 2
				if _map[i] == 0 and not _inside.is_empty() and _inside[y * MAP_W + x] == 1:
					_swept += 1
				_map[i] = 255
