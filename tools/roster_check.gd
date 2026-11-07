extends SceneTree
## Prints each team's roster as the game reads it (lines, pairs, starting goalie, ratings).
##   godot --headless --path . -s res://tools/roster_check.gd [-- team=BOS]

func _init() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("team="):
			only = a.substr(5)
	var missing := []
	for i in Teams.count():
		var t := Teams.team(i)
		var rows := Rosters.for_team(t.abbr)
		if rows.is_empty():
			missing.append(t.abbr)
			continue
		if only != "" and t.abbr != only:
			print("%s %-22s %d players" % [t.abbr, Teams.full_name(i), rows.size()])
			continue
		print("== %s (%s): %d players" % [Teams.full_name(i), t.abbr, rows.size()])
		for p: Dictionary in Rosters.forward_lines(rows) + Rosters.defense_pairs(rows) + Rosters.goalies(rows):
			var s := Rosters.stats(p)
			print("  #%-2s %-3s %-12s %-14s ovr %s  spd %d sht %d pas %d chk %d def %d fgt %d agg %d  | ref %d pos %d" % [
				p.number, p.position, p.last, p.playstyle, p.overall, s.speed, s.shot_power, s.passing, s.checking, s.defense, s.fighting, s.aggression, s.reflexes, s.positioning])
	print("generated (no roster): ", missing)
	quit()
