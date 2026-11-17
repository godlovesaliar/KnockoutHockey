class_name Uniforms
## Uniforms changed in CUSTOMIZE > CREATE UNIFORM, saved to `user://uniforms.json` by team
## code: {abbr: {"home": set, "road": set}}. Teams.team(i) wears them (apply), so players,
## the crowd's shirts and the arena all follow.
##
## A set: `colors` (every Teams colors key as an HTML color), `style` (the Teams.DESIGNS
## preset it started from) and the stripe settings on top: `hem` / `sleeve` / `sock`
## (stripes per band, 0 = none), `alternate` (every other stripe in the accent color),
## `yoke` (0 none, 1 small, 2 large) and `width` (0 thin, 1 normal, 2 wide).
## Without a road set, a team's road uniform is still worked out from the home one
## (Teams.uniform_of): white, or the trim color for light jerseys.

const SAVE_PATH := "user://uniforms.json"
const COLOR_KEYS := ["jersey", "trim", "number_outline", "pants", "gloves", "helmet", "skates", "number"]
const MAX_STRIPES := 4
const YOKES := [0.0, 0.22, 0.3]
const WIDTHS := [0.7, 1.0, 1.4]
## The uniform shader's bands when a design doesn't set them.
const BANDS := {"hem_band": Vector2(0.17, 0.25), "sleeve_band": Vector2(0.6, 0.68), "sock_band": Vector2(0.62, 0.69)}

static var _data := {}
static var _loaded := false


static func has_any(abbr: String) -> bool:
	_load()
	return _data.has(abbr)


## The saved set ({} if none). `which`: "home" or "road".
static func get_set(abbr: String, which: String) -> Dictionary:
	_load()
	return _data.get(abbr, {}).get(which, {})


static func save_set(abbr: String, which: String, u: Dictionary) -> void:
	_load()
	var team: Dictionary = _data.get_or_add(abbr, {})
	team[which] = u.duplicate(true)
	_write()


static func clear_set(abbr: String, which: String) -> void:
	_load()
	if _data.has(abbr):
		_data[abbr].erase(which)
		if _data[abbr].is_empty():
			_data.erase(abbr)
		_write()


## A created team's code changed / it was deleted.
static func rename(old: String, new: String) -> void:
	_load()
	if _data.has(old):
		_data[new] = _data[old]
		_data.erase(old)
		_write()


static func remove(abbr: String) -> void:
	_load()
	if _data.erase(abbr):
		_write()


## A set from a colors dictionary and a design (what a team wears before any editing).
static func from_uniform(colors: Dictionary, style: String) -> Dictionary:
	var u := {"colors": {}, "style": style}
	for k: String in COLOR_KEYS:
		u.colors[k] = (colors.get(k, Color.BLACK) as Color).to_html(false)
	set_style(u, style)
	return u


## Stripe settings back to a preset's.
static func set_style(u: Dictionary, style: String) -> void:
	var d: Dictionary = Teams.DESIGNS.get(style, {})
	u.style = style
	u.hem = int(d.get("hem_stripes", 1))
	u.sleeve = int(d.get("sleeve_stripes", 1))
	u.sock = int(d.get("sock_stripes", 1))
	u.alternate = bool(d.get("alternate", false))
	var y := float(d.get("yoke_r", 0.0))
	u.yoke = 0 if y <= 0.0 else (1 if y < 0.26 else 2)
	u.width = 1


static func colors_of(u: Dictionary) -> Dictionary:
	var c := {}
	for k: String in COLOR_KEYS:
		c[k] = Color.html(str(u.colors.get(k, "000000")))
	return c


## The uniform shader's design parameters for a set.
static func params(u: Dictionary) -> Dictionary:
	var d: Dictionary = Teams.DESIGNS.get(str(u.get("style", "classic")), {}).duplicate()
	d.hem_stripes = clampi(int(u.get("hem", 1)), 0, MAX_STRIPES)
	d.sleeve_stripes = clampi(int(u.get("sleeve", 1)), 0, MAX_STRIPES)
	d.sock_stripes = clampi(int(u.get("sock", 1)), 0, MAX_STRIPES)
	d.alternate = bool(u.get("alternate", false))
	d.yoke_r = YOKES[clampi(int(u.get("yoke", 0)), 0, 2)]
	var k: float = WIDTHS[clampi(int(u.get("width", 1)), 0, 2)]
	for band: String in BANDS:
		var b: Vector2 = d.get(band, BANDS[band])
		# Wider or narrower from the band's start (the hem stays at the jersey's bottom).
		var len := (b.y - b.x) * k
		if band == "sock_band":
			var mid := (b.x + b.y) * 0.5
			d[band] = Vector2(mid - len * 0.5, mid + len * 0.5)
		else:
			d[band] = Vector2(b.x, b.x + len)
	return d


## The uniform a set describes (Teams colors format, with `design` and `design_params`).
static func uniform(u: Dictionary) -> Dictionary:
	var c := colors_of(u)
	c.design = str(u.get("style", "classic"))
	c.design_params = params(u)
	return c


## `team` (a Teams entry) wearing its saved sets: a copy with its colors, design and
## design_params from the home set, and `road` from the road set.
static func apply(team: Dictionary) -> Dictionary:
	var abbr := str(team.get("abbr", ""))
	if not has_any(abbr):
		return team
	var t := team.duplicate()
	var home := get_set(abbr, "home")
	if not home.is_empty():
		var hu := uniform(home)
		t.design = hu.design
		t.design_params = hu.design_params
		hu.erase("design")
		hu.erase("design_params")
		t.colors = hu
	var road := get_set(abbr, "road")
	if not road.is_empty():
		t.road = uniform(road)
	return t


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if FileAccess.file_exists(SAVE_PATH):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
		if data is Dictionary:
			_data = data
			for abbr: String in _data:
				for which: String in _data[abbr]:
					var u: Dictionary = _data[abbr][which]
					for k: String in ["hem", "sleeve", "sock", "yoke", "width"]:
						u[k] = int(u.get(k, 1))


static func _write() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Uniforms: can't write %s" % SAVE_PATH)
	else:
		f.store_string(JSON.stringify(_data, "\t"))
	Teams.changed()
