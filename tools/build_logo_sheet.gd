extends SceneTree
## Lays every team's logo out on one sheet, grouped by conference, with team names:
##   godot --path . -s res://tools/build_logo_sheet.gd
## (Not headless: it renders through a SubViewport.)  -> res://docs/logo_sheet.png

const OUT := "res://docs/logo_sheet.png"
const COLS := 5
const CELL := Vector2(320, 360)     ## logo box + name below it
const LOGO := 280
const MARGIN := 40
const HEADER := 80
const TITLE := 110
const BG := Color(0.09, 0.1, 0.12)
const PANEL := Color(0.14, 0.15, 0.18)


func _init() -> void:
	var font := SystemFont.new()   # (PLAYB___.TTF maps letters to pad-button glyphs)
	font.font_names = PackedStringArray(["Arial", "Segoe UI", "sans-serif"])
	font.font_weight = 700
	var rows_per_conf := ceili(10.0 / COLS)
	var size := Vector2i(MARGIN * 2 + COLS * int(CELL.x),
		TITLE + Teams.CONFERENCES.size() * (HEADER + rows_per_conf * int(CELL.y)) + MARGIN)

	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)

	var bg := ColorRect.new()
	bg.color = BG
	bg.size = size
	vp.add_child(bg)

	var title := _label("KNOCKOUT HOCKEY — LEAGUE TEAMS", font, 56, Color.WHITE)
	title.position = Vector2(0, 24)
	title.size = Vector2(size.x, 70)
	vp.add_child(title)

	var y := float(TITLE)
	for conf: String in Teams.CONFERENCES:
		var head := _label(conf.to_upper() + " CONFERENCE", font, 40, Color(1, 0.8, 0.25))
		head.position = Vector2(0, y + 14)
		head.size = Vector2(size.x, 56)
		vp.add_child(head)
		y += HEADER
		var idx := Teams.in_conference(conf)
		for n in idx.size():
			var t: Dictionary = Teams.LIST[idx[n]]
			var cell := Vector2(MARGIN + (n % COLS) * CELL.x, y + (n / COLS) * CELL.y)
			var panel := ColorRect.new()
			panel.color = PANEL
			panel.position = cell + Vector2(8, 8)
			panel.size = CELL - Vector2(16, 16)
			vp.add_child(panel)
			var tr := TextureRect.new()
			tr.texture = load(t.logo)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.position = cell + Vector2((CELL.x - LOGO) / 2, 18)
			tr.size = Vector2(LOGO, LOGO)
			vp.add_child(tr)
			var name := _label("%s %s" % [t.city, t.name], font, 22, Color.WHITE)
			name.position = cell + Vector2(8, 18 + LOGO + 6)
			name.size = Vector2(CELL.x - 16, 30)
			vp.add_child(name)
		y += rows_per_conf * CELL.y

	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs"))
	var err := img.save_png(OUT)
	print("saved %s (%dx%d): %s" % [OUT, img.get_width(), img.get_height(), error_string(err)])
	quit()


func _label(text: String, font: Font, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.clip_text = true
	return l
