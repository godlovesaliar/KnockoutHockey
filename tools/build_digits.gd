extends SceneTree
## Renders the jersey number digits 0-9 into one sheet (needs a window, not --headless):
##   godot --path . -s res://tools/build_digits.gd
## Each cell is CELL pixels; white = the digit's face, black = its outline, alpha =
## coverage. SkaterVisual tints face and outline per team and projects the result onto
## the jersey with a Decal.
##   -> res://assets/characters/digits.png

const CELL := Vector2i(160, 210)
const FONT_SIZE := 190
const OUTLINE := 26
const FONTS := ["Arial Black", "Impact", "Arial"]
const OUT := "res://assets/characters/digits.png"


func _init() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(CELL.x * 10, CELL.y)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	root.add_child(vp)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(FONTS)
	font.font_weight = 900
	for d in 10:
		var l := Label.new()
		l.text = str(d)
		l.position = Vector2(d * CELL.x, 0)
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
