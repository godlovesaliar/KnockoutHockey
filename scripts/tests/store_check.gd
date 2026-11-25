extends Node
## Checks for the store: the shelves (Store), buying with pucks (Profile, on a throwaway
## save), and what stays locked until it's bought: rinks, goalie masks and head gear.
##   godot --headless --path . res://scenes/tests/StoreCheck.tscn
## Exits 0 on pass, 1 on failure.

const SKATER_SCENE := preload("res://scenes/actors/Skater.tscn")
const GOALIE_SCENE := preload("res://scenes/actors/Goalie.tscn")

var failures := 0


func _ready() -> void:
	Profile.use_fresh("check")
	_shelves()
	_locked()
	_buying()
	await _wearing()
	print("STORE CHECK %s — %d failure(s)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _check(ok: bool, msg: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + msg)
	if not ok:
		failures += 1


func _built_in_ids(list: Array) -> Array:
	var out := []
	for a: Dictionary in list:
		if a.get("built_in", false):
			out.append(str(a.id))
	return out


func _shelves() -> void:
	var ids := {}
	var ok := true
	for it: Dictionary in Store.ITEMS:
		ok = ok and not ids.has(it.id) and int(it.price) > 0 and str(it.name) != "" and str(it.text) != "" and it.cat in Store.CATEGORIES
		ids[it.id] = true
	_check(ok, "every item has its own id, a category, a name, a description and a price")
	var sold := Store.RINK_ITEMS.values() + Store.MASK_ITEMS.values() + Store.HEADGEAR_ITEMS.values() \
			+ Store.HELMET_ITEMS.values() + Store.FACE_ITEMS.values() + [Store.TINT_ITEM]
	_check(sold.all(func(id: String) -> bool: return ids.has(id)), "everything that's locked is on a shelf")
	_check(Store.RINK_ITEMS.keys().all(func(s: String) -> bool: return s in Arenas.STYLES), "the rinks sold are arena styles")
	_check(Store.MASK_ITEMS.keys().all(func(i: int) -> bool: return i >= 0 and i < GoalieVisual.MASKS.size()), "the masks sold are goalie mask models")
	_check(Store.HEADGEAR_ITEMS.keys().all(func(k: String) -> bool: return SkaterVisual.TEAM_MASKS.has(k) or SkaterVisual.HATS.has(k) or k == SkaterVisual.NO_HELMET), "the head gear sold is real head gear")
	_check(Store.COSMETIC_ITEMS.keys().all(func(k: String) -> bool: return SkaterVisual.CRESTS.has(k) or SkaterVisual.EYE_FX.has(k) or SkaterVisual.DANGLERS.has(k))
			and Store.COSMETIC_ITEMS.values().all(func(id: String) -> bool: return ids.has(id)), "the cosmetics sold are real cosmetics, each on a shelf")
	for cat: String in Store.CATEGORIES:
		_check(not Store.in_category(cat).is_empty(), "the %s shelf has something on it" % cat)
	var total := 0
	for it: Dictionary in Store.ITEMS:
		total += int(it.price)
	print("        everything on the shelves: %s pucks" % Pucks.fmt(total))
	# (The classic teams, 500 each, aren't balanced in yet: the 50-game target is some 13,000.)
	_check(total >= 12000 and total <= 16800, "which is 12,000 to 16,800 until the classic teams are balanced in")


func _locked() -> void:
	_check(Store.rink_open("modern") and Store.rink_open("dome") and not Store.rink_open("community") and not Store.rink_open("outdoor"),
			"a new profile: the arena and the dome are open, the two rinks locked")
	_check(_built_in_ids(Arenas.pickable()) == ["modern", "dome"], "only those two are offered for a game (%s)" % str(_built_in_ids(Arenas.pickable())))
	_check("outdoor" in _built_in_ids(Arenas.pickable("outdoor")), "a rink that's already picked stays on the list")
	_check(_built_in_ids(Arenas.all()).size() == 4, "all four still exist")
	_check(Store.goalie_mask_open(0) and Store.goalie_mask_open(2) and not Store.goalie_mask_open(1) and not Store.goalie_mask_open(3),
			"the Modern and '80s masks are open, the cage and the molded mask locked")
	_check(Store.headgear_choices() == [[""], ["None"]], "no head gear on offer yet")
	_check(Store.headgear_choices("lucha")[0] == ["", "lucha"], "head gear already worn stays on offer")
	_check(not Store.oldtime_open() and Store.oldtime_choices()[0] == [""], "the Old-Time Set is locked: only the standard gear on offer")
	_check(Store.helmet_open(0) and Store.helmet_open(1) and not Store.helmet_open(2), "the Modern and Classic helmets are open, the '80s Bucket locked")
	_check(not Store.face_gear_open() and not Store.tints_open(), "the cage, the full shield and the visor tints are locked")
	_check(Store.FACE_ITEMS.keys().all(func(k: String) -> bool: return SkaterVisual.FACE_GEAR.has(k)) and SkaterVisual.FACE_GEAR.keys().all(func(k: String) -> bool: return Store.FACE_ITEMS.has(k))
			and not Store.face_open("alien") and Store.team_face_choices() == [[""], ["Each Their Own"]], "every piece of face gear is sold, the alien visor too, and none is on offer yet")
	_check(Store.cosmetic_choices("crest") == [[""], ["None"]] and Store.cosmetic_choices("eye_fx")[0] == [""] and Store.cosmetic_choices("dangler")[0] == [""]
			and Store.cosmetic_choices("dangler", "fangs")[0] == ["", "fangs"], "no cosmetics on offer yet, but one already worn stays")
	_check(Store.HELMET_ITEMS.keys().all(func(i: int) -> bool: return i >= SkaterVisual.HELMET_ROLLS and i < SkaterVisual.HELMETS.size()),
			"the helmets sold are helmet models no league player rolls")
	var rolled := {}
	for r in 400:
		rolled[SkaterVisual.helmet_index(SkaterVisual.gear_roll(r * 7919 + 13))] = true
	_check(rolled.keys().all(func(i: int) -> bool: return i < SkaterVisual.HELMET_ROLLS) and rolled.size() == SkaterVisual.HELMET_ROLLS,
			"a rolled helmet is always one of the first two, and both come up")
	_check(Store.oldtime_choices("old")[0] == ["", "old"], "an old-time piece already worn stays on offer")
	_check(Store.sock_choices()[0] == ["", "taped"] and Store.pants_choices()[0] == [""] and not Store.longpants_open(),
			"socks: standard or taped; pants: only the standard ones, long pants locked")
	_check(Store.sock_choices("old")[0] == ["", "taped", "old"] and Store.pants_choices("long")[0] == ["", "long"], "wool socks and long pants already worn stay on offer")


func _buying() -> void:
	_check(not Store.buy("rink_outdoor") and not Store.owns("rink_outdoor"), "nothing to buy with no pucks")
	Profile.add_pucks(800)
	_check(Store.can_afford("rink_outdoor") and Store.buy("rink_outdoor"), "800 pucks buy the Outdoor Rink")
	_check(Profile.pucks() == 300 and Store.owns("rink_outdoor") and Store.rink_open("outdoor"), "it costs 500 and it's open")
	_check(_built_in_ids(Arenas.pickable()) == ["modern", "dome", "outdoor"], "and offered for a game")
	_check(not Store.buy("rink_outdoor") and Profile.pucks() == 300, "it can't be bought twice")
	_check(not Store.can_afford("rink_community") and not Store.buy("rink_community") and Profile.pucks() == 300, "300 doesn't cover the other rink")
	_check(Store.buy("mask_molded") and Profile.pucks() == 100 and Store.goalie_mask_open(3) and not Store.goalie_mask_open(1), "200 of it buy the Molded Mask, and only that")
	_check(not Store.buy("nothing"), "an item that doesn't exist can't be bought")
	_check(Store.buy("gear_vintage") and Store.headgear_choices()[0] == ["", "vintage"], "the last 100 buy the Vintage Face Mask, which goes on offer")
	_check(Profile.earned() == 800 and Profile.pucks() == 0, "spending doesn't touch the lifetime total")
	Profile.add_pucks(500)
	_check(Store.buy("gear_oldtime") and Profile.pucks() == 0 and Store.oldtime_open() and Store.oldtime_choices()[0] == ["", "old"], "500 pucks buy the Old-Time Set, and its pieces go on offer")
	_check(Store.headgear_choices()[0] == ["", "vintage", "none", "leather", "guard"], "a bare head and the two leather helmets with them")
	_check(Store.sock_choices()[0] == ["", "taped", "old"] and Store.pants_choices()[0] == ["", "old"] and Store.pants_choices("", false)[0] == [""],
			"and wool socks and canvas pants (a whole team gets those with the kit, not as a pants cut)")
	Profile.add_pucks(200)
	_check(Store.buy("gear_longpants") and Profile.pucks() == 0 and Store.longpants_open() and Store.pants_choices()[0] == ["", "old", "long"] and Store.pants_choices("", false)[0] == ["", "long"],
			"200 pucks buy the Long Pants, for a player or a whole team")
	Profile.add_pucks(600)
	_check(Store.buy("helmet_bucket") and Store.helmet_open(2), "200 pucks buy the '80s Bucket")
	_check(Store.buy("face_full") and Store.face_gear_open() and not Store.tints_open(), "200 the cage and full shield, and only them")
	_check(Store.buy("visor_tints") and Store.tints_open() and Profile.pucks() == 0, "200 the visor tints")
	Profile.add_pucks(300)
	_check(Store.buy("gear_florida") and Store.buy("gear_cowboy") and Store.buy("gear_chupa") and Profile.pucks() == 0
			and Store.headgear_choices()[0] == ["", "vintage", "none", "leather", "guard", "florida", "cowboy"],
			"100 each the Cap & Shades, the Cowboy Hat and the Spines, Eyes & Fangs, and the hats go on offer")
	Profile.add_pucks(100)
	_check(Store.buy("gear_stunt") and Profile.pucks() == 0 and Store.headgear_choices()[0] == ["", "vintage", "none", "leather", "guard", "florida", "cowboy", "stunt"],
			"100 the Stunt Helmet, which goes on offer with the hats")
	Profile.add_pucks(100)
	_check(Store.buy("gear_watch") and Profile.pucks() == 0 and Store.headgear_choices()[0] == ["", "vintage", "none", "leather", "guard", "florida", "cowboy", "stunt", "watch"],
			"100 the Watch Cap, on offer with the hats too")
	Profile.add_pucks(100)
	_check(Store.buy("gear_beanie") and Profile.pucks() == 0 and Store.headgear_choices()[0] == ["", "vintage", "none", "leather", "guard", "florida", "cowboy", "stunt", "watch", "beanie"],
			"100 the Pom Beanie")
	Profile.add_pucks(100)
	_check(Store.buy("gear_golf") and Profile.pucks() == 0 and Store.headgear_choices()[0] == ["", "vintage", "none", "leather", "guard", "florida", "cowboy", "stunt", "watch", "golf", "beanie"],
			"100 the Golf Visor, the last of the hats")
	Profile.add_pucks(100)
	_check(Store.buy("gear_grays") and Store.face_open("alien") and Profile.pucks() == 0 and Store.team_face_choices()[0] == ["", "shield", "cage", "alien"],
			"100 the Alien Visor, and a whole team can wear any face gear that's bought")
	_check(Store.cosmetic_choices("crest")[0] == ["", "spines"] and Store.cosmetic_choices("eye_fx")[0] == ["", "red"] and Store.cosmetic_choices("dangler")[0] == ["", "fangs"],
			"and the three cosmetics, each in its own slot")


## A player's own head gear is worn whatever the team wears; without it, the team's way.
func _wearing() -> void:
	var u := Teams.uniform_vs(0, 1, false)
	u.erase("headgear")
	var p := CustomPlayers.blank()
	p.headgear = "vintage"
	var s := await _dress(SKATER_SCENE, p, u)
	_check(s.visual._mask == "vintage", "a skater with their own face mask wears it")
	s.queue_free()
	p.headgear = ""
	s = await _dress(SKATER_SCENE, p, u)
	_check(s.visual._mask == "", "one without wears a helmet")
	s.queue_free()
	u["headgear"] = "lucha"
	s = await _dress(SKATER_SCENE, p, u)
	_check(s.visual._mask == "lucha", "on a hooded team they wear the hood")
	s.queue_free()
	CustomPlayers.set_position(p, "G")
	p.headgear = "vintage"
	s = await _dress(GOALIE_SCENE, p, u)
	_check(s.visual._mask == "vintage", "a goalie's own face mask wins over the team's hood")
	s.queue_free()
	# Helmets, face gear and tints.
	u.erase("headgear")
	p = CustomPlayers.blank()
	p.helmet = 2
	CustomPlayers.set_face_pick(p, "cage")
	s = await _dress(SKATER_SCENE, p, u)
	var fg := s.visual._helmet.get_node_or_null("FaceGear") as MeshInstance3D
	_check(s.visual._helmet.mesh.get_surface_count() == 3 and fg != null and fg.mesh == SkaterVisual.FACE_GEAR["cage"][2],
			"a skater in the '80s Bucket with a cage: no visor on the helmet, that helmet's cage hung on it")
	s.queue_free()
	CustomPlayers.set_face_pick(p, "shield")
	p.visor_tint = "smoke"
	p.helmet = 0
	s = await _dress(SKATER_SCENE, p, u)
	fg = s.visual._helmet.get_node_or_null("FaceGear") as MeshInstance3D
	_check(fg != null and fg.mesh == SkaterVisual.FACE_GEAR["shield"][0] and fg.get_surface_override_material(0) == SkaterVisual.visor_material("smoke", true),
			"a full shield on the Modern helmet, in the visor's tint")
	s.queue_free()
	CustomPlayers.set_face_pick(p, "visor")
	p.visor_tint = "mirror"
	s = await _dress(SKATER_SCENE, p, u)
	_check(CustomPlayers.face_pick(p) == "visor" and s.visual._helmet.get_node_or_null("FaceGear") == null
			and s.visual._helmet.get_surface_override_material(3) == SkaterVisual.visor_material("mirror") and SkaterVisual.visor_material("mirror") is ShaderMaterial,
			"back to a visor: nothing hung on the helmet, the visor a mirror")
	s.queue_free()
	CustomPlayers.set_face_pick(p, "none")
	_check(not bool(p.visor) and str(p.face) == "" and CustomPlayers.face_pick(p) == "none", "and none is no visor at all")
	# Hats: worn as a helmet is (not a mask), Florida Man's with its sunglasses hung on it.
	p = CustomPlayers.blank()
	p.headgear = "florida"
	s = await _dress(SKATER_SCENE, p, u)
	_check(s.visual._mask == "" and s.visual._helmet != null and s.visual._helmet.mesh == SkaterVisual.HATS["florida"].mesh
			and s.visual._helmet.get_node_or_null("Shades") != null and s.visual.helmet_on(),
			"a skater in the Cap & Shades wears the cap as a helmet, the sunglasses hung on it")
	s.visual.set_helmet(false)
	_check(not s.visual.helmet_on() and not (s.visual._helmet.get_node("Shades") as Node3D).is_visible_in_tree(), "off it comes, sunglasses and all")
	s.queue_free()
	p.headgear = "cowboy"
	CustomPlayers.set_position(p, "G")
	s = await _dress(GOALIE_SCENE, p, u)
	_check(s.visual._helmet != null and s.visual._helmet.mesh == SkaterVisual.HATS["cowboy"].mesh and s.visual._helmet.get_node_or_null("Shades") == null,
			"a goalie can tend net in a cowboy hat")
	s.queue_free()
	var stu := Teams.uniform_vs(Store.team_index("team_stuntmen"), 0, false)
	p = CustomPlayers.blank()
	s = await _dress(SKATER_SCENE, p, stu)
	var paint := s.visual._helmet.get_surface_override_material(0) as ShaderMaterial
	_check(str(stu.get("headgear", "")) == "stunt" and s.visual._mask == "" and s.visual._helmet.mesh == SkaterVisual.HATS["stunt"].mesh
			and paint != null and paint.shader == SkaterVisual.FLAME_SHADER and paint == SkaterVisual.flame_material(stu),
			"a Stuntman wears the stunt helmet as a helmet, flames painted on it in the team's colors")
	_check(Color(paint.get_shader_parameter("flame_color")).is_equal_approx(stu.trim) and Color(paint.get_shader_parameter("base_color")).is_equal_approx(stu.helmet),
			"their trim color for the flames, on their helmet color")
	s.queue_free()
	var wha := Teams.uniform_vs(Store.team_index("team_whalers"), 0, false)
	p = CustomPlayers.blank()
	s = await _dress(SKATER_SCENE, p, wha)
	_check(str(wha.get("headgear", "")) == "watch" and s.visual._mask == "" and s.visual._helmet.mesh == SkaterVisual.HATS["watch"].mesh
			and (s.visual._helmet.get_surface_override_material(0) as StandardMaterial3D).albedo_color.is_equal_approx(wha.jersey)
			and (s.visual._helmet.get_surface_override_material(1) as StandardMaterial3D).albedo_color.is_equal_approx(wha.trim),
			"a Whaler wears the watch cap as a helmet, the knit in the jersey color, the stripe in the trim color")
	s.queue_free()
	var tea := Teams.uniform_vs(Store.team_index("team_sweettea"), 0, false)
	p = CustomPlayers.blank()
	p.hair_style = "messy"
	s = await _dress(SKATER_SCENE, p, tea)
	var brim := s.visual._helmet.get_surface_override_material(1) as StandardMaterial3D
	_check(str(tea.get("headgear", "")) == "golf" and s.visual._mask == "" and s.visual._helmet.mesh == SkaterVisual.HATS["golf"].mesh
			and (s.visual._helmet.get_surface_override_material(0) as StandardMaterial3D).albedo_color.is_equal_approx(tea.jersey)
			and brim != null and brim.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and brim.albedo_color.a < 0.9
			and is_equal_approx(brim.albedo_color.r, tea.trim.r) and s.visual._helmet.get_surface_override_material(2) != null,
			"a Sweet Tea player wears the golf visor as a helmet, the band in the jersey color, the bill see-through in the trim color")
	var under := s.visual.skel.find_child("HairHat", true, false) as MeshInstance3D
	_check(under != null and under.material_override is ShaderMaterial
			and float((under.material_override as ShaderMaterial).get_shader_parameter("open_d")) < 1.0,
			"and their hair shows out of the top of it, cut away only behind the band")
	s.queue_free()
	for hat in ["beanie", "leather", "guard"]:
		p = CustomPlayers.blank()
		p.headgear = hat
		s = await _dress(SKATER_SCENE, p, u)
		_check(s.visual._mask == "" and s.visual._helmet != null and s.visual._helmet.mesh == SkaterVisual.HATS[hat].mesh
				and s.visual._helmet.get_surface_override_material(s.visual._helmet.mesh.get_surface_count() - 1) != null,
				"the %s is worn as a helmet, every part of it given its material" % hat)
		s.queue_free()
	var fla := Store.team_index("team_floridaman")
	_check(str(Teams.uniform_vs(fla, 0, false).get("headgear", "")) == "florida", "Florida Man wear their caps and shades")
	# The Grays' alien visor: face gear for the whole team, whatever each player's visor.
	var gry := Teams.uniform_vs(Store.team_index("team_grays"), 0, false)
	p = CustomPlayers.blank()
	CustomPlayers.set_face_pick(p, "none")
	s = await _dress(SKATER_SCENE, p, gry)
	fg = s.visual._helmet.get_node_or_null("FaceGear") as MeshInstance3D
	_check(str(gry.get("face", "")) == "alien" and fg != null and fg.mesh == SkaterVisual.FACE_GEAR["alien"][0] and s.visual._helmet.mesh.get_surface_count() == 3
			and fg.get_surface_override_material(0) == SkaterVisual.alien_lens_material(), "a Gray wears the alien visor in place of their own, a black mirror")
	s.queue_free()
	CustomPlayers.set_face_pick(p, "cage")
	s = await _dress(SKATER_SCENE, p, gry)
	_check((s.visual._helmet.get_node_or_null("FaceGear") as MeshInstance3D).mesh == SkaterVisual.FACE_GEAR["cage"][0], "unless they have face gear of their own")
	s.queue_free()
	CustomPlayers.set_face_pick(p, "alien")
	_check(CustomPlayers.face_pick(p) == "alien" and str(p.face) == "alien" and bool(p.visor), "and anyone can pick it as their own")
	# Cosmetics: three slots, each on its own; the Chupacabras wear one of each.
	var chu := Teams.uniform_vs(Store.team_index("team_chupacabras"), 0, false)
	_check(not chu.has("headgear") and str(chu.get("crest", "")) == "spines" and str(chu.get("eye_fx", "")) == "red" and str(chu.get("dangler", "")) == "fangs"
			and str(chu.get("visor_tint", "")) == "smoke", "the Chupacabras wear spines, glowing red eyes and fangs, behind smoked visors")
	p = CustomPlayers.blank()
	p.helmet = 1
	CustomPlayers.set_face_pick(p, "none")
	s = await _dress(SKATER_SCENE, p, chu)
	var hm: MeshInstance3D = s.visual._helmet
	_check(s.visual._mask == "" and hm.mesh == SkaterVisual.HELMETS[1].mesh
			and (hm.get_node_or_null("Crest") as MeshInstance3D).mesh == SkaterVisual.CRESTS["spines"][1]
			and (hm.get_node_or_null("Dangler") as MeshInstance3D).mesh == SkaterVisual.DANGLERS["fangs"].meshes[1],
			"a Chupacabra in the Classic helmet: that helmet's spines and fangs hung on it")
	_check(hm.get_surface_override_material(3) == SkaterVisual.visor_material("smoke"), "a visor to hang the fangs from though they chose none, smoked as the team's are")
	_check(hm.find_children("*EyeGlow*", "", true, false).is_empty() and s.visual.skel.find_children("EyeGlow*", "MeshInstance3D", true, false).size() == 2
			and s.visual.skel.find_child("EyeLight", true, false) is OmniLight3D, "a glow on each eye and their light, on the head and not the helmet")
	s.queue_free()
	CustomPlayers.set_position(p, "G")
	s = await _dress(GOALIE_SCENE, p, chu)
	var gm := s.visual.find_child("Helmet", true, false) as MeshInstance3D
	_check(gm != null and gm.mesh == GoalieVisual.MASKS[GoalieVisual.mask_index(s.gear_style)].mesh and gm.get_child_count() == 0
			and s.visual.skel.find_children("EyeGlow*", "MeshInstance3D", true, false).size() == 2,
			"their goalie's mask is as it was, with the eyes glowing behind it")
	s.queue_free()
	# Each on its own, on any team: one player's fangs and nothing else.
	u.erase("headgear")
	p = CustomPlayers.blank()
	p.dangler = "fangs"
	s = await _dress(SKATER_SCENE, p, u)
	hm = s.visual._helmet
	_check(hm.get_node_or_null("Dangler") != null and hm.get_node_or_null("Crest") == null and s.visual.skel.find_children("EyeGlow*", "MeshInstance3D", true, false).is_empty(),
			"fangs alone: no spines, no glow")
	p.dangler = ""
	p.eye_fx = "red"
	p.headgear = "cowboy"
	s.queue_free()
	s = await _dress(SKATER_SCENE, p, u)
	_check(s.visual._helmet.get_node_or_null("Dangler") == null and s.visual.skel.find_children("EyeGlow*", "MeshInstance3D", true, false).size() == 2,
			"glowing eyes alone, under a cowboy hat")
	s.queue_free()
	CustomPlayers.set_face_pick(p, "cage")
	p.headgear = ""
	p.eye_fx = ""
	p.dangler = "fangs"
	p.crest = "spines"
	s = await _dress(SKATER_SCENE, p, u)
	_check(s.visual._helmet.get_node_or_null("Dangler") == null and s.visual._helmet.get_node_or_null("Crest") != null, "behind a cage there's nowhere to hang fangs; the spines stay")
	s.queue_free()
	# The Geese's: one player's hat.
	_check(Rosters.signature_gear({"display_name": "Dwayne Robertson"}) == "cowboy" and Rosters.signature_gear({"first": "Dag", "last": "Bakken"}) == "",
			"Dwayne Robertson plays in a cowboy hat, and nobody else")
	var dwayne := {}
	for row: Dictionary in Rosters.for_team("MIN"):
		if Rosters.display_name(row) == "Dwayne Robertson":
			dwayne = row
	s = SKATER_SCENE.instantiate()
	s.uniform = Teams.uniform_vs(Store.team_index("team_geese"), 0, false)
	s.team_color = s.uniform.jersey
	s.headgear = Rosters.signature_gear(dwayne)   # (as MatchDirector and MenuArena dress a sheet player)
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not dwayne.is_empty() and s.visual._helmet != null and s.visual._helmet.mesh == SkaterVisual.HATS["cowboy"].mesh,
			"he is on the Geese's sheet, and dressed from it he wears the hat")
	s.queue_free()
	# The Old-Time Set: a player's own pieces, bare heads, and a whole team's kit.
	u.erase("headgear")
	p = CustomPlayers.blank()
	p.gloves = "old"
	p.headgear = "none"
	p.stick = "oldtime"
	s = await _dress(SKATER_SCENE, p, u)
	_check(s.visual._gloves[0].mesh == SkaterVisual.GLOVE_OLD_MESH and s.visual._cuffs[0].mesh == SkaterVisual.CUFF_OLD_MESH, "a skater with their own gauntlets wears them")
	_check(s.visual._mask == "none" and s.visual._helmet == null and not s.visual.helmet_on(), "bare-headed: no helmet at all")
	_check(s.visual.shaft.mesh == SkaterVisual.STICK_OLD_MESH, "and carries the wooden stick")
	_check((s.visual.skel.get_node("LeftSkate") as MeshInstance3D).mesh.get_surface_count() == 2 and not s.visual.old_time(s.skate_style), "on standard skates, which they didn't change")
	s.queue_free()
	u["kit"] = "old"
	p = CustomPlayers.blank()
	s = await _dress(SKATER_SCENE, p, u)
	_check(s.visual._gloves[0].mesh == SkaterVisual.GLOVE_OLD_MESH and s.visual.old_time(s.skate_style) and s.visual.shaft.mesh == SkaterVisual.STICK_OLD_MESH,
			"on a team in the old-time kit everyone wears the gauntlets and tube skates and carries the wooden stick")
	_check(s.visual._helmet != null, "under a helmet, unless the team goes bare-headed too")
	_check(s.visual.sock_kind() == 2 and s.visual.pants_kind() == 1 and _leg_wear(s) == Vector2(1, 2), "in wool socks and canvas pants")
	s.queue_free()
	# Leg wear: a player's own beats the team's; a team's pants cut dresses everyone.
	p.socks = "taped"
	p.pants = "long"
	s = await _dress(SKATER_SCENE, p, u)
	_check(s.visual.sock_kind() == 1 and s.visual.pants_kind() == 2 and _leg_wear(s) == Vector2(2, 1), "a player with their own taped socks and long pants wears them on that team too")
	s.queue_free()
	p = CustomPlayers.blank()
	u.erase("kit")
	s = await _dress(SKATER_SCENE, p, u)
	_check(_leg_wear(s) == Vector2.ZERO, "the standard pants and socks otherwise")
	s.queue_free()
	u["pants_style"] = "long"
	s = await _dress(SKATER_SCENE, p, u)
	_check(_leg_wear(s) == Vector2(2, 0), "a team in long pants: everyone wears them")
	s.queue_free()
	u.erase("pants_style")
	u["kit"] = "old"
	CustomPlayers.set_position(p, "G")
	s = await _dress(GOALIE_SCENE, p, u)
	_check((s.visual.find_child("LeftPad", true, false) as MeshInstance3D).mesh == GoalieVisual.PAD_OLD_MESH
			and (s.visual.find_child("Blocker", true, false) as MeshInstance3D).mesh == GoalieVisual.BLOCKER_OLD_MESH, "and its goalie the leather pads and the waffle board")
	s.queue_free()
	u.erase("kit")
	var t := CustomTeams.blank()
	_check(not Teams.uniform_of(t, t, false).has("headgear"), "a new team wears helmets")
	_check(not Teams.uniform_of(t, t, false).has("kit"), "and the standard gear")
	t.kit = "old"
	_check(str(Teams.uniform_of(t, t, false).get("kit", "")) == "old", "a team given the old-time kit wears it")
	t.kit = ""
	t.socks = "barber"
	t.pants_style = "long"
	var tu := Teams.uniform_of(t, t, false)
	_check(int(Teams.design_params(tu).get("sock_pattern", 0)) == 1 and str(tu.get("pants_style", "")) == "long"
			and SkaterVisual.uniform_material(tu) != SkaterVisual.uniform_material(Teams.uniform_of(CustomTeams.blank(), t, false)),
			"a team given barber-pole socks and long pants wears them, in a material of its own")
	t.socks = ""
	t.pants_style = ""
	var set_u := Uniforms.from_uniform(tu, "classic")
	_check(int(set_u.sock_pattern) == 1 and int(Uniforms.params(set_u).sock_pattern) == 1, "and Create Uniform starts from that pattern")
	var socks_of := {}
	for call: String in ["beacon", "anchor", "boxcar", "copper", "clipper", "jalopy"]:
		var ti := Store.team_index("team_" + call)
		var d := Teams.design_params(Teams.uniform_vs(ti, 0, false))
		socks_of["%d %d %s" % [int(d.get("sock_pattern", 0)), int(d.get("sock_stripes", 1)), str(d.get("alternate", false))]] = true
	_check(socks_of.size() == 6, "no two classic teams wear the same socks")
	# The classic teams: the old-time kit and leather helmets, home and away, at the dome.
	for id: String in ["team_beacon", "team_anchor", "team_boxcar", "team_copper", "team_clipper", "team_jalopy"]:
		var ci := Store.team_index(id)
		var cu := Teams.uniform_vs(ci, 0, true)
		_check(ci >= 0 and str(Teams.base_team(ci).conference) == Teams.CLASSIC and str(cu.get("kit", "")) == SkaterVisual.OLD
				and str(cu.get("headgear", "")) in ["guard", "none"] and Arenas.home_id(ci) == "dome" and Rosters.for_team(str(Teams.base_team(ci).abbr)).size() == 15,
				"%s: a classic team in the Old-Time Set (head gear: %s), 15 players, at home in the dome" % [Teams.full_name(ci), str(cu.get("headgear", ""))])
	var classics := Teams.in_conference(Teams.CLASSIC)
	var order := Teams.menu_order()
	_check(order.size() == Teams.count() and classics.size() == 6 and order.slice(order.size() - 6).map(func(i: int) -> String: return str(Teams.base_team(i).abbr)) == ["BOS", "NAR", "OMA", "DET", "BUT", "HON"],
			"the classic teams come up after the three conferences, East to West")
	t.headgear = "lucha"
	_check(str(Teams.uniform_of(t, t, false).get("headgear", "")) == "lucha", "a team given hoods wears them")


## What the uniform shader is told a skater wears on the legs: (pants_style, sock_style)
## on their jersey layer, which must agree with every other piece the uniform is drawn on.
func _leg_wear(s: Skater) -> Vector2:
	var out := Vector2(-1, -1)
	for mi: MeshInstance3D in s.visual.skel.find_children("*", "MeshInstance3D", true, false):
		var m := mi.material_override as ShaderMaterial
		if m == null or m.shader != SkaterVisual.UNIFORM_SHADER:
			continue
		var v := Vector2(float(mi.get_instance_shader_parameter("pants_style")), float(mi.get_instance_shader_parameter("sock_style")))
		if out.x >= 0.0 and v != out:
			return Vector2(-2, -2)
		out = v
	return out


func _dress(scene: PackedScene, p: Dictionary, uniform: Dictionary) -> Skater:
	var s: Skater = scene.instantiate()
	s.uniform = uniform.duplicate()
	s.team_color = uniform.jersey
	CustomPlayers.apply(s, p)
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	return s
