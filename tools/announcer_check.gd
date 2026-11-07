extends SceneTree
## Announcer coverage: for every line (AnnouncerLines), who records its new takes, how
## many takes it has from each voice (all of them play) against the target, and the scripts data/hockey_announcer_lines.csv has for it (rows whose exact file name
## is already recorded are left out; rows the CSV gives to the other voice are marked).
##
##   Godot --headless --path . -s res://tools/announcer_check.gd
##   ... -- md=<path>   also writes the report as Markdown

const CSV := "res://data/hockey_announcer_lines.csv"


func _initialize() -> void:
	await process_frame
	var sfx = root.get_node("Sfx")
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var v_name := func(v: String) -> String: return "Both" if v == "both" else AnnouncerLines.VOICES[v].name.get_slice(" ", 0)
	var known := {}
	for g: Array in AnnouncerLines.GROUPS:
		for l: Array in g[1]:
			known[l[0]] = true
	# CSV scripts by the line they'd count toward.
	var todo := {}
	var stray := []
	var f := FileAccess.open(CSV, FileAccess.READ)
	if f:
		f.get_csv_line()
		while not f.eof_reached():
			var row := f.get_csv_line()
			if row.size() < 5:
				continue
			var name := row[0].strip_edges()
			if sfx.has_file(name.to_lower()):
				continue
			var line := AnnouncerLines.line_for_file(name)
			var text := row[4].strip_edges()
			if text.begins_with("["):
				text = text.substr(text.find("]") + 1).strip_edges()
			var entry := "%s \"%s\"" % [name, text]
			if not known.has(line):
				stray.append(entry)
				continue
			var csv_voice := row[2].strip_edges()
			if csv_voice in AnnouncerLines.VOICES and csv_voice != AnnouncerLines.voice_of(line):
				entry += " *(CSV: %s)*" % v_name.call(csv_voice)
			todo.get_or_add(line, []).append(entry)
	var t := AnnouncerLines.TARGET
	var need := {"pbp": 0, "color": 0, "both": 0}
	var body := PackedStringArray()
	for g: Array in AnnouncerLines.GROUPS:
		body.append("\n## %s\n" % g[0])
		body.append("| Line | Records new takes | Takes (Steve / Bobby / duet) | Still needed | CSV scripts | Plays when |")
		body.append("|---|---|---|---|---|---|")
		for l: Array in g[1]:
			var line: String = l[0]
			var v: String = l[1]
			var counts := [sfx.voice_take_count(line, "pbp"), sfx.voice_take_count(line, "color"), sfx.voice_take_count(line, "both")]
			var total: int = counts[0] + counts[1] + counts[2]
			var n := maxi(0, t - total)
			need[v] += n
			var rows: Array = todo.get(line, [])
			var rec := "%d" % total if total == 0 else "%d (%d / %d / %d)" % [total, counts[0], counts[1], counts[2]]
			body.append("| `%s` | %s | %s | %s | %s | %s |" % [line, v_name.call(v), rec,
					str(n) if n > 0 else "—", "<br>".join(rows), l[3]])
	# Recordings whose name doesn't match any line: the game never plays them.
	var orphans := []
	for v: String in sfx._voice_takes:
		for line: String in sfx._voice_takes[v]:
			if not known.has(line):
				orphans.append("`%s` (%s, %d file(s))" % [line, AnnouncerLines.VOICES[v].dir, sfx._voice_takes[v][line].size()])
	if not orphans.is_empty():
		body.append("\n## Recorded, but the name matches no line (never plays)\n")
		for o: String in orphans:
			body.append("- %s" % o)
	if not stray.is_empty():
		body.append("\n## In the CSV, not used by the game\n")
		for s: String in stray:
			body.append("- %s" % s)
	var head := PackedStringArray()
	head.append("# Announcer lines: takes still needed (target %d per line)\n" % t)
	for v: String in ["pbp", "color", "both"]:
		var vv: Dictionary = AnnouncerLines.VOICES[v]
		head.append("- **%s** (%s, `assets/sound/announcer/%s`): %d takes needed" % [vv.name, vv.role, vv.dir, need[v]])
	var text := "\n".join(head) + "\n" + "\n".join(body)
	print(text)
	if args.has("md"):
		var w := FileAccess.open(args.md, FileAccess.WRITE)
		w.store_string(text + "\n")
	quit()
