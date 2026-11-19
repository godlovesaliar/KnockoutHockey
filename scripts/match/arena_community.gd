class_name ArenaCommunity
## Community Rink (an Arena style): the local barn.
##   - aluminum bleachers down both sides (Arena's lower-bowl sizes give the rows), fans
##     on the planks;
##   - painted block walls with a stripe in the home color, high windows down the sides;
##   - an arched wood roof on glulam arches, rows of hanging lights over the ice;
##   - the Zamboni door at one end with a lamp scoreboard over it, the lobby windows and
##     the home banners at the other.
## The roof is low (the game cameras fly above it), so it hides whenever the camera isn't
## under it (Arena.roof_covers) and every wall faces in only: from outside you look
## straight in, like a cutaway.

const SIDE_GAP := 1.3        ## walkway behind the top row of bleachers
const END_GAP := 7.5         ## behind the end boards to the end walls
const EAVE := 7.0
const PEAK := 16.5
const ARCH_SEGS := 24
const ARCH_EVERY := 6.0      ## meters between the glulam arches
const BLEACHER_HALF := 21.0  ## the bleachers run this far either side of center
const BLOCK := Color(0.84, 0.82, 0.77)


static func build(a: Arena) -> void:
	var w := half_w(a)
	var l := RinkSpec.HALF_L + END_GAP
	var seats := bleachers(a, BLEACHER_HALF)
	a.seat_crowd(seats, [0.85, 0.5, 0.5], [null, null, null])
	a.crowd_look = Vector2(a.low_o(4), a.low_y(4) + 1.2)
	_walls(a, w, l)
	_roof(a, w, l)
	_lights(a, w, l)
	_ends(a, w, l)
	a.roof_covers = func(p: Vector3) -> bool:
		return absf(p.x) < w and absf(p.z) < l and p.y < roof_y(a, p.x) - 1.0


static func half_w(a: Arena) -> float:
	return RinkSpec.HALF_W + a.low_o(a.LOW_ROWS) + SIDE_GAP


## The underside of the roof over x: a circular arch from the eaves to the peak.
static func roof_y(a: Arena, x: float) -> float:
	var c := half_w(a)
	var s := PEAK - EAVE
	var r := (c * c + s * s) / (2.0 * s)
	return PEAK - r + sqrt(maxf(r * r - x * x, 0.0))


# --- Bleachers (shared with the outdoor rink) -------------------------------------------

## Aluminum bleachers down both sides, |z| <= z_half: per row a foot plank in front and
## a seat plank behind (seat color), dark between, steel posts and a top rail. Returns the
## seats for Arena.seat_crowd (bowl 0, no seat mesh: the plank is the seat).
static func bleachers(a: Arena, z_half: float) -> Array:
	var seats := []
	var alu := Arena._st()
	var seat := Arena._st()
	var dark := Arena._st()
	var steel := Arena._st()
	var aisles := [-z_half * 0.5, 0.0, z_half * 0.5]
	for side: float in [-1.0, 1.0]:
		var inward := Vector3(-side, 0.0, 0.0)
		for i in a.LOW_ROWS:
			var o := a.low_o(i)
			var y := a.low_y(i)
			var xf := side * (RinkSpec.HALF_W + o)
			var xb := side * (RinkSpec.HALF_W + o + a.LOW_DEPTH)
			# The riser below this row (the front wall for the first), and the dark under the planks.
			var y0 := 0.0 if i == 0 else a.low_y(i - 1)
			MeshUtil.quad(dark if i > 0 else alu, Vector3(xf, y0, -z_half), Vector3(xf, y0, z_half),
					Vector3(xf, y, z_half), Vector3(xf, y, -z_half), inward)
			MeshUtil.quad(dark, Vector3(xf, y - 0.07, -z_half), Vector3(xb, y - 0.07, -z_half),
					Vector3(xb, y - 0.07, z_half), Vector3(xf, y - 0.07, z_half), Vector3.UP)
			# Foot plank, seat plank.
			Arena._box(alu, Vector3(minf(xf, xf + side * 0.34), y - 0.05, -z_half), Vector3(maxf(xf, xf + side * 0.34), y, z_half))
			var s0 := side * (RinkSpec.HALF_W + o + a.LOW_DEPTH - 0.86)
			var s1 := side * (RinkSpec.HALF_W + o + a.LOW_DEPTH - 0.46)
			Arena._box(seat, Vector3(minf(s0, s1), y + 0.4, -z_half), Vector3(maxf(s0, s1), y + 0.46, z_half))
			# The fans: a seat every SEAT_W along the plank, gaps at the aisles.
			var ox := side * (RinkSpec.HALF_W + o + a.LOW_DEPTH - 0.44)
			var z := -z_half + 0.4
			while z < z_half - 0.3:
				var clear := true
				for az: float in aisles:
					if absf(z - az) < Arena.AISLE_W * 0.5:
						clear = false
				if clear:
					var p := Vector2(ox, z)
					seats.append([0, Arena._seat_xf([p, Vector2(-side, 0.0)], y), Arena._sector(p), Arena._chunk(0, p, i / Arena.CHUNK_ROWS)])
				z += Arena.SEAT_W
		# The back of the top row: a riser to the rail, the rail and its posts.
		var ot := a.low_o(a.LOW_ROWS)
		var top := a.low_y(a.LOW_ROWS - 1)
		var xt := side * (RinkSpec.HALF_W + ot)
		MeshUtil.quad(dark, Vector3(xt, 0.0, -z_half), Vector3(xt, 0.0, z_half), Vector3(xt, top + 0.5, z_half),
				Vector3(xt, top + 0.5, -z_half), inward)
		Arena._box(steel, Vector3(xt - 0.03, top + 1.0, -z_half), Vector3(xt + 0.03, top + 1.06, z_half))
		# Front rail along the first row.
		var x0 := side * (RinkSpec.HALF_W + a.START)
		Arena._box(steel, Vector3(x0 - 0.025, a.LOW_Y0 + 0.82, -z_half), Vector3(x0 + 0.025, a.LOW_Y0 + 0.87, z_half))
		var pz := -z_half
		while pz <= z_half + 0.01:
			Arena._box(steel, Vector3(xt - 0.03, 0.0, pz - 0.03), Vector3(xt + 0.03, top + 1.06, pz + 0.03))
			Arena._box(steel, Vector3(x0 - 0.025, a.LOW_Y0, pz - 0.025), Vector3(x0 + 0.025, a.LOW_Y0 + 0.87, pz + 0.025))
			pz += 2.4
		# The open ends of the stand: stepped side panels.
		for end: float in [-1.0, 1.0]:
			var ez := end * z_half
			for i in a.LOW_ROWS:
				var xa := side * (RinkSpec.HALF_W + a.low_o(i))
				var xc := side * (RinkSpec.HALF_W + a.low_o(i + 1))
				MeshUtil.quad(dark, Vector3(xa, 0.0, ez), Vector3(xc, 0.0, ez), Vector3(xc, a.low_y(i), ez),
						Vector3(xa, a.low_y(i), ez), Vector3(0.0, 0.0, end))
	a._commit(alu, MeshUtil.material(Color(0.7, 0.72, 0.74), 0.35, 0.6), "BleacherPlanks", false)
	a._commit(seat, a._seat_mats[0], "BleacherSeats", false)
	a._commit(dark, MeshUtil.material(Color(0.07, 0.07, 0.08), 0.9), "BleacherDark", false)
	a._commit(steel, MeshUtil.material(Color(0.42, 0.44, 0.47), 0.4, 0.7), "BleacherRails", false)
	return seats


# --- The building ---------------------------------------------------------------------

## Painted concrete block: 0.4 x 0.2 m blocks in running bond, a 2 m tile (UV in meters / 2).
static func block_texture() -> ImageTexture:
	var px := 256
	var img := Image.create(px, px, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	var bw := px / 5
	var bh := px / 10
	for row in 10:
		var shift := (bw / 2) * (row % 2)
		for col in 6:
			var shade := 1.0 - rng.randf() * 0.06
			var x0 := col * bw - shift
			img.fill_rect(Rect2i(x0, row * bh, bw, bh).intersection(Rect2i(0, 0, px, px)), Color(shade, shade, shade * 0.99))
			img.fill_rect(Rect2i(x0, row * bh, 2, bh).intersection(Rect2i(0, 0, px, px)), Color(0.72, 0.72, 0.71))
		img.fill_rect(Rect2i(0, row * bh, px, 2), Color(0.72, 0.72, 0.71))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _block_mat(tex: Texture2D, c: Color) -> StandardMaterial3D:
	var m := MeshUtil.material(c, 0.9)
	m.albedo_texture = tex
	m.uv1_scale = Vector3(0.5, 0.5, 1.0)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


## A wall quad from (x0, z0) to (x1, z1), y0..y1, facing `n`, UV in meters.
static func _wall(st: SurfaceTool, x0: float, z0: float, x1: float, z1: float, y0: float, y1: float, n: Vector3, u0 := 0.0) -> void:
	var len := Vector2(x0, z0).distance_to(Vector2(x1, z1))
	MeshUtil.quad(st, Vector3(x0, y0, z0), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z0), n,
			Vector2(u0, -y0), Vector2(u0 + len, -y0), Vector2(u0 + len, -y1), Vector2(u0, -y1))


static func _walls(a: Arena, w: float, l: float) -> void:
	var tex := block_texture()
	var block := Arena._st()
	var stripe := Arena._st()
	var glass := Arena._st()
	var frames := Arena._st()
	for side: float in [-1.0, 1.0]:
		var x := side * w
		var n := Vector3(-side, 0.0, 0.0)
		_wall(block, x, -l, x, l, 0.0, EAVE, n)
		_wall(stripe, x - side * 0.01, -l, x - side * 0.01, l, 0.0, 1.3, n)
		_wall(stripe, x - side * 0.01, -l, x - side * 0.01, l, 1.45, 1.6, n)
		# High windows: daylight through frosted panes.
		var z := -l + 5.0
		while z < l - 4.0:
			_wall(glass, x - side * 0.02, z, x - side * 0.02, z + 2.4, EAVE - 2.0, EAVE - 0.8, n)
			Arena._box(frames, Vector3(x - 0.12, EAVE - 2.08, z - 0.08), Vector3(x + 0.12, EAVE - 0.72, z))
			Arena._box(frames, Vector3(x - 0.12, EAVE - 2.08, z + 2.4), Vector3(x + 0.12, EAVE - 0.72, z + 2.48))
			z += 6.0
	# The end walls up to the arch.
	for end: float in [-1.0, 1.0]:
		var z := end * l
		var n := Vector3(0.0, 0.0, -end)
		for j in ARCH_SEGS:
			var x0 := -w + 2.0 * w * j / ARCH_SEGS
			var x1 := -w + 2.0 * w * (j + 1) / ARCH_SEGS
			# A strip up to the lower of its two roof heights, the sliver above as a triangle.
			var y0 := roof_y(a, x0)
			var y1 := roof_y(a, x1)
			var lo := minf(y0, y1)
			_wall(block, x0, z, x1, z, 0.0, lo, n, x0 + w)
			var hi := Vector3(x0 if y0 > y1 else x1, maxf(y0, y1), z)
			var p0 := Vector3(x0, lo, z)
			var p1 := Vector3(x1, lo, z)
			MeshUtil.quad(block, p0, p1, hi, hi, n, Vector2(x0 + w, -lo), Vector2(x1 + w, -lo), Vector2(hi.x + w, -hi.y), Vector2(hi.x + w, -hi.y))
		_wall(stripe, -w, z - end * 0.01, w, z - end * 0.01, 0.0, 1.3, n)
		_wall(stripe, -w, z - end * 0.01, w, z - end * 0.01, 1.45, 1.6, n)
	a._commit(block, _block_mat(tex, BLOCK), "Walls", false)
	var home := _block_mat(tex, Color(0.3, 0.3, 0.6))
	a.home_mats.append(home)
	a._commit(stripe, home, "WallStripe", false)
	a._commit(glass, Arena._emissive(Color(0.7, 0.78, 0.86), 0.5), "HighWindows", false)
	a._commit(frames, MeshUtil.material(Color(0.2, 0.2, 0.22), 0.5, 0.5), "WindowFrames", false)


## The arched roof: wood decking on glulam arches that come down the walls as posts.
static func _roof(a: Arena, w: float, l: float) -> void:
	var deck := Arena._st()
	var u := 0.0
	for j in ARCH_SEGS:
		var x0 := -w + 2.0 * w * j / ARCH_SEGS
		var x1 := -w + 2.0 * w * (j + 1) / ARCH_SEGS
		var p0 := Vector3(x0, roof_y(a, x0), 0.0)
		var p1 := Vector3(x1, roof_y(a, x1), 0.0)
		var len := p0.distance_to(p1)
		var d := (p1 - p0).normalized()
		var n := Vector3(d.y, -d.x, 0.0)   # toward the arch's center (down and in)
		MeshUtil.quad(deck, Vector3(x0, p0.y, -l), Vector3(x1, p1.y, -l), Vector3(x1, p1.y, l), Vector3(x0, p0.y, l), n,
				Vector2(u, -l), Vector2(u + len, -l), Vector2(u + len, l), Vector2(u, l))
		u += len
	var wood := MeshUtil.material(Color(0.66, 0.5, 0.33), 0.8)
	wood.albedo_texture = _plank_texture()
	wood.uv1_scale = Vector3(0.5, 0.5, 1.0)
	var roof := a._commit(deck, wood, "Roof", false)
	# Glulam arches, every ARCH_EVERY meters, down the walls to the floor.
	var arches := Arena._st()
	var posts := Arena._st()
	var z := -l + 2.0
	while z <= l - 1.9:
		for j in ARCH_SEGS:
			var x0 := -w + 0.3 + (2.0 * w - 0.6) * j / ARCH_SEGS
			var x1 := -w + 0.3 + (2.0 * w - 0.6) * (j + 1) / ARCH_SEGS
			var y0 := roof_y(a, x0)
			var y1 := roof_y(a, x1)
			Arena._hex(arches, [Vector3(x0, y0 - 0.85, z - 0.13), Vector3(x1, y1 - 0.85, z - 0.13), Vector3(x1, y1 - 0.85, z + 0.13), Vector3(x0, y0 - 0.85, z + 0.13),
					Vector3(x0, y0, z - 0.13), Vector3(x1, y1, z - 0.13), Vector3(x1, y1, z + 0.13), Vector3(x0, y0, z + 0.13)])
		for side: float in [-1.0, 1.0]:
			var x := side * w
			Arena._box(posts, Vector3(minf(x, x - side * 0.6), 0.0, z - 0.15), Vector3(maxf(x, x - side * 0.6), EAVE - 0.4, z + 0.15))
		z += ARCH_EVERY
	var glulam := MeshUtil.material(Color(0.55, 0.36, 0.2), 0.6)
	var arch_mi := a._commit(arches, glulam, "Arches", false)
	a._commit(posts, glulam, "ArchPosts", false)
	a.roof_nodes.append(roof)
	a.roof_nodes.append(arch_mi)


## Pine decking boards running along the building (UV.y), 2 m tile.
static func _plank_texture() -> ImageTexture:
	var px := 256
	var img := Image.create(px, px, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var bw := px / 14
	for b in 15:
		var shade := 0.88 + rng.randf() * 0.18
		img.fill_rect(Rect2i(b * bw, 0, bw, px).intersection(Rect2i(0, 0, px, px)), Color(shade, shade * 0.97, shade * 0.93))
		img.fill_rect(Rect2i(b * bw, 0, 2, px).intersection(Rect2i(0, 0, px, px)), Color(0.45, 0.38, 0.3))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Three rows of lights hung over the ice on cables, a few spots for the shine.
static func _lights(a: Arena, _w: float, _l: float) -> void:
	var housing := Arena._st()
	var lens := Arena._st()
	var y := 11.0
	for x: float in [-8.5, 0.0, 8.5]:
		var z := -27.5
		while z <= 27.6:
			Arena._box(housing, Vector3(x - 0.24, y, z - 0.65), Vector3(x + 0.24, y + 0.14, z + 0.65))
			MeshUtil.quad(lens, Vector3(x - 0.2, y - 0.01, z - 0.6), Vector3(x + 0.2, y - 0.01, z - 0.6),
					Vector3(x + 0.2, y - 0.01, z + 0.6), Vector3(x - 0.2, y - 0.01, z + 0.6), Vector3.DOWN)
			for dz: float in [-0.5, 0.5]:
				Arena._box(housing, Vector3(x - 0.01, y + 0.14, z + dz - 0.01), Vector3(x + 0.01, roof_y(a, x) - 0.8, z + dz + 0.01))
			z += 5.5
	var tint := a.light_color()
	var h := a._commit(housing, MeshUtil.material(Color(0.18, 0.18, 0.19), 0.5, 0.6), "LightHousings", false)
	var l := a._commit(lens, Arena._emissive(Color(0.95, 0.97, 1.0) * tint / Color(0.94, 0.96, 1.0), 7.0), "IceLights", false)
	a.roof_nodes.append(h)
	a.roof_nodes.append(l)
	for sx: float in [-5.0, 5.0]:
		for sz: float in [-18.0, 0.0, 18.0]:
			var s := SpotLight3D.new()
			s.name = "IceSpot"
			s.position = Vector3(sx, y - 0.2, sz)
			s.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
			s.spot_range = 16.0
			s.spot_angle = 50.0
			s.spot_attenuation = 0.6
			s.light_energy = 1.4
			s.light_specular = 0.0
			s.light_color = tint
			a.add_child(s)


## The Zamboni door and the lamp scoreboard over it at +Z; the lobby windows and the home
## banners at -Z.
static func _ends(a: Arena, _w: float, l: float) -> void:
	var trim := Arena._st()
	# Zamboni door: a roll-up door in slats, a dark frame.
	var door := Arena._st()
	var dz := l - 0.03
	for k in 18:
		var y0 := k * 0.25
		MeshUtil.quad(door, Vector3(-2.8, y0, dz), Vector3(2.8, y0, dz), Vector3(2.8, y0 + 0.23, dz), Vector3(-2.8, y0 + 0.23, dz), Vector3(0, 0, -1))
	a._commit(door, MeshUtil.material(Color(0.6, 0.62, 0.64), 0.45, 0.5), "ZamboniDoor", false)
	Arena._box(trim, Vector3(-3.1, 0.0, l - 0.25), Vector3(-2.8, 4.8, l))
	Arena._box(trim, Vector3(2.8, 0.0, l - 0.25), Vector3(3.1, 4.8, l))
	Arena._box(trim, Vector3(-3.1, 4.5, l - 0.25), Vector3(3.1, 4.8, l))
	# Lobby windows at -Z: warm light from the snack bar and lobby.
	var lobby := Arena._st()
	var wz := -l + 0.03
	MeshUtil.quad(lobby, Vector3(-7.0, 1.0, wz), Vector3(7.0, 1.0, wz), Vector3(7.0, 3.3, wz), Vector3(-7.0, 3.3, wz), Vector3(0, 0, 1))
	a._commit(lobby, Arena._emissive(Color(1.0, 0.82, 0.6), 0.7), "LobbyWindows", false)
	var mx := -7.0
	while mx <= 7.01:
		Arena._box(trim, Vector3(mx - 0.06, 0.95, -l), Vector3(mx + 0.06, 3.35, -l + 0.12))
		mx += 1.75
	Arena._box(trim, Vector3(-7.06, 0.9, -l), Vector3(7.06, 1.0, -l + 0.14))
	Arena._box(trim, Vector3(-7.06, 3.3, -l), Vector3(7.06, 3.4, -l + 0.14))
	# Exit signs over the corner doors.
	var exits := Arena._st()
	for ex: float in [-1.0, 1.0]:
		for ez: float in [-1.0, 1.0]:
			var x := ex * (RinkSpec.HALF_W + 4.0)
			var z := ez * (l - 0.08)
			Arena._box(exits, Vector3(x - 0.3, 2.6, z - 0.06), Vector3(x + 0.3, 2.85, z + 0.06))
			Arena._box(trim, Vector3(x - 0.55, 0.0, z - ez * 0.05 - 0.05), Vector3(x + 0.55, 2.2, z - ez * 0.05 + 0.05))
	a._commit(exits, Arena._emissive(Color(1.0, 0.1, 0.05), 2.0), "ExitSigns", false)
	a._commit(trim, MeshUtil.material(Color(0.12, 0.12, 0.13), 0.6), "Trim", false)
	if a.spec.get("scoreboard", true):
		wall_board(a, Vector3(0.0, 7.4, l - 0.3), Vector3(0, 0, -1), Vector2(7.0, 3.2))
	if a.spec.get("banners", false):
		var root := Node3D.new()
		root.name = "WallBanners"
		a.add_child(root)
		for i in 5:
			a.hang_banner(root, Vector2(1.7, 3.4), Vector3((i - 2) * 2.7, 7.6, -l + 0.12), Vector3(0, 0, 1))


## A lamp scoreboard (ArenaScreen.classic) of `size` centered at `at`, facing `n`, in a
## dark case. Sets the arena's board_at for the scoreboard cutaway.
static func wall_board(a: Arena, at: Vector3, n: Vector3, size: Vector2) -> Node3D:
	var root := Node3D.new()
	root.name = "WallScoreboard"
	root.transform = Transform3D(Basis.looking_at(-n, Vector3.UP), at)
	a.add_child(root)
	a._block(Vector3(size.x + 0.5, size.y + 0.5, 0.4), Vector3(0, 0, -0.22), MeshUtil.material(Color(0.05, 0.05, 0.06), 0.5, 0.3), "Case", root)
	var vp := a._screen_viewport(Vector2i(int(size.x * 110), int(size.y * 110)), "LampBoard", true)
	a._screen_quad(root, vp, size, Vector3(0, 0, 0.0), Vector3(0, 0, 1))
	a.board_at = at
	return root
