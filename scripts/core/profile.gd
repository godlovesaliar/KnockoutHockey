class_name Profile
## The player's save (`user://profile.json`): the pucks they hold, what they've bought, and
## what they've done that pays only once.
##   `pucks`       the balance (Pucks pays in, the store spends)
##   `earned`      every puck ever paid in
##   `owned`       store item ids bought
##   `first_wins`  team codes beaten at least once (the first win over each league team pays extra)
##   `teams`       locked teams unlocked by winning their challenge (Store), by `call`
##   `extras_on`   the bought extras (Store, by item id) that are switched on
##
## `-- profile=<name>` uses `user://profile_<name>.json` instead (testing). `-- pucks=<n>`
## sets the balance. Screenshot runs (`-- shot=...`) without `profile=` never write the
## real save: what they earn lives for that run only.

const SAVE_PATH := "user://profile.json"

static var _data := {}
static var _loaded := false
static var _path := SAVE_PATH
static var _dry := false


static func pucks() -> int:
	_load()
	return int(_data.pucks)


static func earned() -> int:
	_load()
	return int(_data.earned)


static func add_pucks(n: int) -> void:
	_load()
	if n <= 0:
		return
	_data.pucks = pucks() + n
	_data.earned = earned() + n
	_write()


## Takes `n` pucks if the balance covers it.
static func spend(n: int) -> bool:
	_load()
	if n < 0 or n > pucks():
		return false
	_data.pucks = pucks() - n
	_write()
	return true


## Buys a store item: takes its price and marks it owned, in one write. False (and
## nothing changes) if it's owned already or the balance doesn't cover it.
static func buy(id: String, price: int) -> bool:
	_load()
	if id in _data.owned or price < 0 or price > pucks():
		return false
	_data.pucks = pucks() - price
	_data.owned.append(id)
	_write()
	return true


static func owns(id: String) -> bool:
	_load()
	return id in _data.owned


static func grant(id: String) -> void:
	_load()
	if not (id in _data.owned):
		_data.owned.append(id)
		_write()


static func team_unlocked(call: String) -> bool:
	_load()
	return call in _data.teams


static func unlock_team(call: String) -> void:
	_load()
	if not (call in _data.teams):
		_data.teams.append(call)
		_write()


static func extra_on(id: String) -> bool:
	_load()
	return id in _data.extras_on


static func set_extra(id: String, on: bool) -> void:
	_load()
	if on == (id in _data.extras_on):
		return
	if on:
		_data.extras_on.append(id)
	else:
		_data.extras_on.erase(id)
	_write()


static func has_beaten(abbr: String) -> bool:
	_load()
	return abbr in _data.first_wins


static func mark_beaten(abbr: String) -> void:
	_load()
	if not (abbr in _data.first_wins):
		_data.first_wins.append(abbr)
		_write()


## Tests: switch to `user://profile_<name>.json`, starting it empty.
static func use_fresh(name: String) -> void:
	_path = "user://profile_%s.json" % name.validate_filename()
	_dry = false
	_loaded = true
	_data = _blank()
	_write()


static func _blank() -> Dictionary:
	return {"pucks": 0, "earned": 0, "owned": [], "first_wins": [], "teams": [], "extras_on": []}


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_data = _blank()
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	if str(args.get("profile", "")) != "":
		_path = "user://profile_%s.json" % str(args.profile).validate_filename()
	elif args.has("shot"):
		_dry = true
	if FileAccess.file_exists(_path):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(_path))
		if data is Dictionary:
			for k: String in _data:
				if typeof(data.get(k)) == (TYPE_ARRAY if _data[k] is Array else TYPE_FLOAT):
					_data[k] = data[k]
	if args.has("pucks"):
		_data.pucks = maxi(0, int(args.pucks))
		_write()


static func _write() -> void:
	if _dry:
		return
	var f := FileAccess.open(_path, FileAccess.WRITE)
	if f == null:
		push_warning("Profile: can't write %s" % _path)
	else:
		f.store_string(JSON.stringify(_data, "\t"))
