extends SceneTree
## Cuts the board ads out of the ad sheets into one PNG per sponsor:
##   godot --headless --path . -s res://tools/build_ads.gd
##
## Each sheet (assets/images/ads*.jfif) is a 2 x 3 grid of ad panels on a black
## background. Panels are found from the black gutters (sheet-wide column and row
## projections). Each panel is trimmed a few pixels inside its edge so no gutter shows.
## Sheets repeat some ads; a panel named "" is a repeat and is skipped, so every
## sponsor is written once.
##   -> res://assets/images/ads/<name>.png   (rink.gd shows every image in that folder)

const SHEETS := [
	{"file": "res://assets/images/ads.jfif", "names": [
		"handy_andys", "antonios",
		"olneyville", "madeira_feast",
		"", "expiration_nation"]},          # Squeezin' Joe's: ads2 has the newer take
	{"file": "res://assets/images/ads2.jfif", "names": [
		"dels_lemonade", "hoo_mee",
		"", "",                              # Olneyville, Madeira: repeats of ads.jfif
		"squeezin_joes", ""]},               # Expiration Nation: repeat
	{"file": "res://assets/images/ads3.jfif", "names": [
		"animal_attorney", "haunting_real_estate",
		"funkin_coffee", "ice_rink_doctor",
		"loose_dentistry", "gravity_reversal"]},
]   ## names: panels in reading order (row by row, left then right)
const OUT := "res://assets/images/ads/%s.png"
const DARK := 0.09     ## a pixel brighter than this (max channel) is part of a panel
const FILL := 0.1      ## share of bright pixels that makes a row/column part of a panel (gutters are ~0)
const MIN_RUN := 150   ## shorter bright runs are noise, not panels
const INSET := 4       ## pixels trimmed inside each panel's edge


func _init() -> void:
	for sheet: Dictionary in SHEETS:
		var img := Image.new()
		var err := img.load_jpg_from_buffer(FileAccess.get_file_as_bytes(sheet.file))
		if err != OK:
			push_error("can't read %s: %s" % [sheet.file, error_string(err)])
			continue
		img.convert(Image.FORMAT_RGB8)
		var panels := _panels(img)
		if panels.size() != (sheet.names as Array).size():
			push_error("%s: found %d panels, expected %d: %s" % [sheet.file, panels.size(), sheet.names.size(), panels])
			continue
		for i in panels.size():
			var name: String = sheet.names[i]
			if name == "":
				print("%s panel %d: repeat, skipped" % [sheet.file, i])
				continue
			var r: Rect2i = panels[i].grow(-INSET)
			var out := img.get_region(r)
			out.save_png(OUT % name)
			print("%s panel %d -> %s  %s" % [sheet.file, i, name, r])
	quit()


## Panels in reading order.
func _panels(img: Image) -> Array[Rect2i]:
	var w := img.get_width()
	var h := img.get_height()
	# Gutters are black the whole way across, so whole-sheet projections find them even
	# when a panel has dark areas of its own.
	var cols := _runs(func(x: int) -> float: return _share(img, Rect2i(x, 0, 1, h)), w, FILL)
	var rows := _runs(func(y: int) -> float: return _share(img, Rect2i(0, y, w, 1)), h, FILL)
	var out: Array[Rect2i] = []
	for rr: Vector2i in rows:
		for c: Vector2i in cols:
			out.append(Rect2i(c.x, rr.x, c.y - c.x, rr.y - rr.x))
	return out


## Runs [start, end) where share(i) >= fill, at least MIN_RUN long.
func _runs(share: Callable, n: int, fill: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var start := -1
	for i in n + 1:
		var on := i < n and float(share.call(i)) >= fill
		if on and start < 0:
			start = i
		elif not on and start >= 0:
			if i - start >= MIN_RUN:
				out.append(Vector2i(start, i))
			start = -1
	return out


func _share(img: Image, r: Rect2i) -> float:
	var bright := 0
	var total := 0
	var step := 2
	for y in range(r.position.y, r.end.y, step if r.size.y > 1 else 1):
		for x in range(r.position.x, r.end.x, step if r.size.x > 1 else 1):
			var c := img.get_pixel(x, y)
			if maxf(c.r, maxf(c.g, c.b)) > DARK:
				bright += 1
			total += 1
	return bright / float(maxi(total, 1))
