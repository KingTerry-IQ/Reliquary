## Flashpoint's own tag filters, fetched from the same core-configuration
## component the launcher reads.
##
## Flashpoint marks entries with `warning`-category tags and bundles those tags
## into named groups in `.preferences.defaults.json`. A group hides its entries
## when it is switched on, and every group marked `extreme` also hides while
## SHOW EXTREME is off — which is Flashpoint's own out-of-box state.
##
## This filters what the archive pane lists. It is not a claim about what the
## archive contains: the tags are crowd-curated, so treat it as a strong filter,
## not a guarantee. Inscribed cartridges are never hidden from the cabinet.

class_name TagFilter
extends Node

const CONFIG_ZIP := "https://nexus-dev.unstable.life/repository/stable/core-configuration.zip"
const PREFS_NAME := ".preferences.defaults.json"
const UA := "Reliquary/0.1 (GodOnChain; tag filter fetch)"

var groups: Array = []
## Flashpoint's `browsePageShowExtreme`. Off by default, as it ships.
var show_extreme: bool = false
var last_error: String = ""
var fetched: bool = false

var _blocked: Dictionary = {}
var _dirty: bool = true


func _init() -> void:
	groups = defaults()


## The seven groups Flashpoint ships. Kept here so the filter works offline and
## on first run; a successful fetch replaces them with the live lists.
static func defaults() -> Array:
	return [
		{
			"name": "Pornography",
			"extreme": true,
			"enabled": false,
			"tags": [
				"Anal", "Anal Insertion", "Cartoon Porn", "Adult", "Anilingus",
				"Fingering", "Oral", "Sexual Content", "Cunnilingus", "Fellatio",
				"Footjob", "Handjob", "Interspecies", "Masturbation", "Paizuri",
				"Sex Toys", "Tentacles", "Touching", "Tribadism", "Vaginal",
				"Vaginal Insertion", "Futanari", "Male Futanari", "Gynomorph",
				"Andromorph", "Intersex", "Porn", "Fisting", "Hentai", "Group",
				"Solo", "Frottage", "Multiple Penises", "Ambiguous Penetration",
				"Self Oral", "Sex Simulator", "Undressing",
			],
		},
		{
			"name": "Fetishes",
			"extreme": true,
			"enabled": false,
			"tags": [
				"Age Regression", "Asphyxiophilia", "BDSM", "Bestiality",
				"Bimbofication", "Breast Milking", "Cannibalism", "Enema",
				"Expansion", "Flatulence", "Gloryhole", "Hypnosis", "Incest",
				"Interspecies", "Infantilism", "Inflation", "Kabeshiri",
				"Macrophilia", "Muscle Growth", "Necrophilia", "Obesity",
				"Oviposition", "Podophilia", "Popping", "Pregnancy", "Quicksand",
				"Scat", "Selfcest", "Spanking", "Tickling", "Transformation",
				"Urination", "Vomit", "Vore", "Weight Gain", "Gachimuchi",
			],
		},
		{
			"name": "Violence",
			"extreme": true,
			"enabled": false,
			"tags": ["Gore", "Strong Violence", "Strong Language"],
		},
		{
			"name": "Bigotry",
			"extreme": true,
			"enabled": false,
			"tags": ["Homophobia", "Stereotyping", "Racism", "Transphobia"],
		},
		{
			"name": "Pornography Extreme",
			"extreme": true,
			"enabled": true,
			"tags": ["Bestiality", "Necrophilia", "Sexual Violence"],
		},
		{
			"name": "Seizure Warning",
			"extreme": false,
			"enabled": false,
			"tags": ["Seizure Warning"],
		},
		{
			"name": "Otherwise Mature Topics",
			"extreme": false,
			"enabled": false,
			"tags": [
				"Drugs", "Reproductive Health", "Addiction", "Heavy Themes",
				"Suicide", "Nudity", "Moderate Language", "Sexual Harassment",
			],
		},
	]


## A group hides its entries when switched on, or when it is extreme and
## extreme entries are hidden — the same two conditions Flashpoint applies.
func group_hides(group: Dictionary) -> bool:
	if bool(group.get("enabled", false)):
		return true
	return bool(group.get("extreme", false)) and not show_extreme


func active_names() -> PackedStringArray:
	var out := PackedStringArray()
	for entry: Variant in groups:
		if entry is Dictionary and group_hides(entry):
			out.append(str((entry as Dictionary).get("name", "")))
	return out


func is_filtering() -> bool:
	for entry: Variant in groups:
		if entry is Dictionary and group_hides(entry):
			return true
	return false


func mark_dirty() -> void:
	_dirty = true


func set_enabled(name: String, on: bool) -> void:
	for entry: Variant in groups:
		if entry is Dictionary and str((entry as Dictionary).get("name", "")) == name:
			(entry as Dictionary)["enabled"] = on
	mark_dirty()


func set_show_extreme(on: bool) -> void:
	show_extreme = on
	mark_dirty()


func blocked_tags() -> Dictionary:
	if not _dirty:
		return _blocked
	_blocked = {}
	for entry: Variant in groups:
		if not entry is Dictionary or not group_hides(entry):
			continue
		var tags: Variant = (entry as Dictionary).get("tags", [])
		if tags is Array:
			for t: Variant in tags:
				var name := str(t).strip_edges().to_lower()
				if not name.is_empty():
					_blocked[name] = true
	_dirty = false
	return _blocked


## Tags arrive as a list from the API and can be a joined string from an older
## cached catalog, so read both shapes.
static func tag_names(raw: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if raw is Array:
		for item: Variant in raw:
			out.append_array(tag_names(item))
		return out
	var text := str(raw).strip_edges()
	if text.is_empty() or text == "[]":
		return out
	for chunk in text.replace(";", ",").split(","):
		var name := chunk.strip_edges()
		if not name.is_empty():
			out.append(name)
	return out


func blocks(entry: Dictionary) -> bool:
	var set := blocked_tags()
	if set.is_empty():
		return false
	for name in tag_names(entry.get("tags", [])):
		if set.has(name.to_lower()):
			return true
	return false


## Drop what the active groups hide. Returns the same array when nothing is on,
## so the common case costs nothing.
func apply(rows: Array) -> Array:
	if not is_filtering() or rows.is_empty():
		return rows
	var out: Array = []
	for entry: Variant in rows:
		if not entry is Dictionary:
			continue
		if blocks(entry):
			continue
		out.append(entry)
	return out


## Pull the live filter lists out of Flashpoint's configuration component,
## keeping whatever the operator has switched on here.
func ensure(progress: Callable = Callable()) -> bool:
	last_error = ""
	var archive := "user://bin/core-configuration.zip"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://bin"))
	if not await _download(CONFIG_ZIP, archive, progress):
		return false
	var parsed := _prefs_from_zip(archive)
	if parsed.is_empty():
		return false
	var live: Variant = parsed.get("tagFilters", [])
	if not live is Array or (live as Array).is_empty():
		last_error = "Flashpoint configuration had no tag filters."
		return false
	if parsed.has("browsePageShowExtreme"):
		## Only adopt Flashpoint's default the first time; after that the
		## operator's own choice wins.
		if not fetched:
			show_extreme = bool(parsed.get("browsePageShowExtreme", false))
	groups = _merge(live as Array)
	fetched = true
	mark_dirty()
	return true


## Keep the operator's enabled flags across a refresh; take names, tags and the
## extreme marking from Flashpoint.
func _merge(live: Array) -> Array:
	var was := {}
	for entry: Variant in groups:
		if entry is Dictionary:
			was[str((entry as Dictionary).get("name", ""))] = bool(
				(entry as Dictionary).get("enabled", false)
			)
	var out: Array = []
	for entry: Variant in live:
		if not entry is Dictionary:
			continue
		var rec: Dictionary = entry
		var name := str(rec.get("name", "")).strip_edges()
		if name.is_empty():
			continue
		var tags: Array = []
		var raw: Variant = rec.get("tags", [])
		if raw is Array:
			for t: Variant in raw:
				var tag := str(t).strip_edges()
				if not tag.is_empty():
					tags.append(tag)
		if tags.is_empty():
			continue
		out.append({
			"name": name,
			"description": str(rec.get("description", "")),
			"extreme": bool(rec.get("extreme", false)),
			"enabled": bool(was.get(name, rec.get("enabled", false))),
			"tags": tags,
		})
	return out if not out.is_empty() else groups


func to_config() -> Dictionary:
	var on: Array = []
	for entry: Variant in groups:
		if entry is Dictionary and bool((entry as Dictionary).get("enabled", false)):
			on.append(str((entry as Dictionary).get("name", "")))
	return {"show_extreme": show_extreme, "groups_on": on}


func from_config(raw: Variant) -> void:
	if not raw is Dictionary:
		return
	var rec: Dictionary = raw
	if rec.has("show_extreme"):
		show_extreme = bool(rec.get("show_extreme", false))
	var on: Variant = rec.get("groups_on", null)
	if on is Array:
		var want := {}
		for name: Variant in on:
			want[str(name)] = true
		for entry: Variant in groups:
			if entry is Dictionary:
				var g: Dictionary = entry
				g["enabled"] = want.has(str(g.get("name", "")))
	mark_dirty()


func _prefs_from_zip(archive: String) -> Dictionary:
	var zip := ZIPReader.new()
	if zip.open(ProjectSettings.globalize_path(archive)) != OK:
		last_error = "Could not open the Flashpoint configuration zip."
		return {}
	for name in zip.get_files():
		if not name.get_file() == PREFS_NAME:
			continue
		var parsed: Variant = JSON.parse_string(zip.read_file(name).get_string_from_utf8())
		if parsed is Dictionary:
			return parsed
	last_error = "Flashpoint configuration had no preferences file."
	return {}


func _download(url: String, dest: String, progress: Callable = Callable()) -> bool:
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 60
	http.download_file = dest
	var err := http.request(url, PackedStringArray(["User-Agent: %s" % UA]))
	if err != OK:
		last_error = "Could not start the Flashpoint configuration download."
		http.queue_free()
		return false
	var result: Array = await http.request_completed
	http.queue_free()
	if int(result[1]) != 200:
		last_error = "Flashpoint configuration returned HTTP %s." % str(result[1])
		return false
	if progress.is_valid():
		progress.call(100.0)
	return FileAccess.file_exists(dest)
