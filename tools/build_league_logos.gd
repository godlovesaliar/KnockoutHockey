extends SceneTree
## Cuts the KHL league logos out of their white backgrounds into transparent PNGs:
##   godot --headless --path . -s res://tools/build_league_logos.gd
##
## Near-white pixels connected to the image border become transparent (the logos' black
## outer outline stops the fill), the edge gets a soft one-pixel alpha, then the logo is
## cropped and scaled to at most MAX_SIZE.
##   logo_khlmain.jfif -> khl_main.png (the stinger), logo_khlknockout.jfif -> khl_belt.png,
##   logo_khlmono.jfif -> khl_mono.png (the on-screen bugs), all in assets/images/

const LOGOS := {
	"res://assets/images/logo_khlmain.jfif": "res://assets/images/khl_main.png",
	"res://assets/images/logo_khlknockout.jfif": "res://assets/images/khl_belt.png",   # Knockout Mode's on-screen bug
	"res://assets/images/logo_khlmono.jfif": "res://assets/images/khl_mono.png",       # the regular games' on-screen bug
}
const MAX_SIZE := 768
const LUM := 0.82
const SAT := 0.12
const PAD := 4


func _init() -> void:
	for src: String in LOGOS:
		var img := Image.new()
		if img.load_jpg_from_buffer(FileAccess.get_file_as_bytes(src)) != OK:
			push_error("can't read " + src)
			continue
		img.convert(Image.FORMAT_RGBA8)
		# The monogram: its closed white pockets cleared too, and recolored once it's cut
		# (recolored first, its white K would read as background).
		var mono := src.ends_with("logo_khlmono.jfif")
		_cut(img, LOGOS[src], mono, _mono_colors if mono else Callable())
	quit()


## The monogram, recolored to the broadcast's navy / red / white / silver (the main logo's
## wordmark): the light-blue K to ice white, the charcoal H to silver, shading kept. The
## red L and the black outline stay.
const MONO_K := Color(0.95, 0.97, 1.0)
const MONO_H := Color(0.72, 0.74, 0.79)

func _mono_colors(img: Image) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var lum := c.get_luminance()
			var spread := maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b))
			if c.b > c.r + 0.15 and lum > 0.3:
				img.set_pixel(x, y, MONO_K * clampf(lum / 0.72, 0.0, 1.05))   # light-blue K (lum ~0.72)
			elif spread < 0.1 and lum > 0.13 and lum < 0.5:
				var k := clampf((lum - 0.06) / (0.26 - 0.06), 0.0, 1.15)     # charcoal H (lum ~0.26)
				img.set_pixel(x, y, Color(0.05, 0.05, 0.06).lerp(MONO_H, minf(k, 1.0)) * maxf(k, 1.0))


func _is_bg(c: Color) -> bool:
	return c.get_luminance() > LUM and maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b)) < SAT


## `pockets`: also clear closed near-white areas narrower than POCKET_W of the image (the
## gaps between letters), keeping wide ones (the monogram's slash). `post` recolors the
## logo once the background is gone.
const POCKET_W := 0.25

func _cut(img: Image, out_path: String, pockets := false, post := Callable()) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var bg := PackedByteArray()
	bg.resize(w * h)
	var stack := PackedInt32Array()
	for x in w:
		stack.append(x)
		stack.append((h - 1) * w + x)
	for y in h:
		stack.append(y * w)
		stack.append(y * w + w - 1)
	while not stack.is_empty():
		var i := stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		if bg[i] == 1:
			continue
		var x := i % w
		var y := i / w
		if not _is_bg(img.get_pixel(x, y)):
			continue
		bg[i] = 1
		if x > 0: stack.append(i - 1)
		if x < w - 1: stack.append(i + 1)
		if y > 0: stack.append(i - w)
		if y < h - 1: stack.append(i + w)
	if pockets:
		_clear_pockets(img, bg, w, h)
	var x0 := w
	var y0 := h
	var x1 := 0
	var y1 := 0
	for y in h:
		for x in w:
			var i := y * w + x
			if bg[i] == 1:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			# Soft edge: a logo pixel touching the background is half see-through.
			var edge := (x > 0 and bg[i - 1] == 1) or (x < w - 1 and bg[i + 1] == 1) or (y > 0 and bg[i - w] == 1) or (y < h - 1 and bg[i + w] == 1)
			if edge:
				var c := img.get_pixel(x, y)
				c.a = 0.5
				img.set_pixel(x, y, c)
			x0 = mini(x0, x)
			y0 = mini(y0, y)
			x1 = maxi(x1, x)
			y1 = maxi(y1, y)
	if post.is_valid():
		post.call(img)
	var r := Rect2i(maxi(x0 - PAD, 0), maxi(y0 - PAD, 0), 0, 0)
	r.end = Vector2i(mini(x1 + PAD + 1, w), mini(y1 + PAD + 1, h))
	var out := img.get_region(r)
	var k := float(MAX_SIZE) / maxf(out.get_width(), out.get_height())
	if k < 1.0:
		out.resize(roundi(out.get_width() * k), roundi(out.get_height() * k), Image.INTERPOLATE_LANCZOS)
	out.save_png(out_path)
	print("wrote %s (%dx%d)" % [out_path, out.get_width(), out.get_height()])


func _clear_pockets(img: Image, bg: PackedByteArray, w: int, h: int) -> void:
	var seen := PackedByteArray()
	seen.resize(w * h)
	for start in w * h:
		if bg[start] == 1 or seen[start] == 1 or not _is_bg(img.get_pixel(start % w, start / w)):
			continue
		var comp := PackedInt32Array()
		var stack := PackedInt32Array([start])
		seen[start] = 1
		var minx := w
		var maxx := 0
		while not stack.is_empty():
			var i := stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			comp.append(i)
			var x := i % w
			minx = mini(minx, x)
			maxx = maxi(maxx, x)
			for n: int in [i - 1 if x > 0 else -1, i + 1 if x < w - 1 else -1, i - w, i + w]:
				if n < 0 or n >= w * h or seen[n] == 1 or bg[n] == 1:
					continue
				if _is_bg(img.get_pixel(n % w, n / w)):
					seen[n] = 1
					stack.append(n)
		if maxx - minx < w * POCKET_W:
			for i in comp:
				bg[i] = 1
