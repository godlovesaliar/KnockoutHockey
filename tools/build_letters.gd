extends SceneTree
## Renders the jersey nameplate letters into one sheet (needs a window, not --headless):
##   godot --path . -s res://tools/build_letters.gd
## One cell per character in CHARS, CELL pixels each, in a single row. White = the
## letter's face, black = its outline, alpha = coverage, the same scheme as the digit
## sheet (tools/build_digits.gd). SkaterVisual.name_texture() crops each letter tight,
## spaces them, tints face and outline per team and projects the name onto the jersey.
##   -> res://assets/characters/letters.png

const CHARS := "ABCDEFGHIJKLMNOPQRSTUVWXYZÉÑÔÚÛ0123456789-'.!"
const CELL := Vector2i(120, 150)
const FONT_SIZE := 120
const OUTLINE := 18
const FONTS := ["Arial Black", "Impact", "Arial"]
const OUT := "res://assets/characters/letters.png"


func _init() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(CELL.x * CHARS.length(), CELL.y)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	root.add_child(vp)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(FONTS)
	font.font_weight = 900
	for i in CHARS.length():
		var l := Label.new()
		l.text = CHARS[i]
		l.position = Vector2(i * CELL.x, 0)
		l.size = Vector2(CELL)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_font_override("font", font)
		l.add_theme_font_size_override("font_size", FONT_SIZE)
		l.add_theme_color_override("font_color", Color.WHITE)
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", OUTLINE)
		vp.add_child(l)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var err := img.save_png(OUT)
	print("%s: %s  %s" % [OUT, error_string(err), img.get_size()])
	quit()
