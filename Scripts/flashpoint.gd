## Flashpoint Infinity-style catalog: search metadata, fetch one GameZIP.

class_name Flashpoint
extends Node

const API := "https://db-api.unstable.life"
const UA := "Reliquary/0.1 (GodOnChain; archival client)"
## Same tree Infinity pulls missing Legacy/htdocs files from.
const LEGACY_HTDOCS := "https://infinity.unstable.life/Flashpoint/Legacy/htdocs/"
const PLAYLIST_ZIP := "https://nexus-dev.unstable.life/repository/stable/%s.zip"
## Official Flashpoint playlists (Manager component ids) plus All Games.
const PLAYLISTS: Array = [
	{"id": "all", "title": "All Games"},
	{"id": "playlist-halloffame", "title": "Super Hall of Fame"},
	{"id": "playlist-animhalloffame", "title": "Animation Hall of Fame"},
	{"id": "playlist-1001games", "title": "1001 Video Games"},
	{"id": "playlist-adultswim", "title": "Best of Adult Swim"},
	{"id": "playlist-shockwave", "title": "Shockwave Shockers"},
	{"id": "playlist-firstgames", "title": "First Past the Post"},
	{"id": "playlist-kongregatekongs", "title": "Kongregate Kongs"},
	{"id": "playlist-gamehousegames", "title": "Gamehouse Games"},
	{"id": "playlist-molleindustria", "title": "Molleindustria"},
	{"id": "playlist-tony", "title": "Tony's Favorites"},
	{"id": "playlist-tasselfoot", "title": "Tasselfoot's Favorites"},
	{"id": "playlist-pico8", "title": "Pico Gr8s"},
	{"id": "playlist-java", "title": "Hot Java Beans"},
	{"id": "playlist-ragegames", "title": "Rage for the Ages"},
	{"id": "playlist-foodgames", "title": "Flash Food"},
	{"id": "playlist-toys", "title": "Toys to Enjoy"},
	{"id": "playlist-christmas", "title": "Jingle Jollies"},
	{"id": "playlist-halloween", "title": "Halloween Haunts"},
	{"id": "playlist-usergenerated", "title": "Player-Produced Perils"},
	{"id": "playlist-gotd2023", "title": "GOTD 2023"},
]
const LIST_FIELDS := "id,title,developer,publisher,series,tags,platform,launchCommand,zipped,applicationPath,library,releaseDate"
const CATALOG_DIR := "user://catalog"
const CATALOG_MAX_AGE := 6 * 60 * 60
const PREFIXES := {
	"title": "title",
	"developer": "developer",
	"dev": "developer",
	"publisher": "publisher",
	"pub": "publisher",
	"series": "series",
	"tag": "tags",
	"tags": "tags",
	"source": "source",
	"src": "source",
	"id": "id",
	"platform": "platform",
	"status": "status",
	"language": "language",
	"lang": "language",
	"library": "library",
}

var last_error: String = ""
var _size_cache: Dictionary = {}
var _playlist_ids: Dictionary = {}
var _tag_names: PackedStringArray = PackedStringArray()
var _io_busy: bool = false
var _io_library: String = ""
var _io_rows: Array = []


## Flashpoint-launcher syntax: `title:Bowman tag:Arcade` plus bare words as
## smart search. Does not hide legacy or other platforms unless asked.
## `limit` 0 means no cap (same as the official search tool).
func search(query: String, library: String = "", limit: int = 0, platform: String = "", any: bool = false, field_list: String = "") -> Array:
	last_error = ""
	var fields := parse_query(query)
	if not platform.is_empty() and not fields.has("platform"):
		fields["platform"] = platform
	if not library.is_empty() and not fields.has("library"):
		fields["library"] = library
	return await _request_search(fields, limit, any, field_list)


func search_ids(ids: PackedStringArray, progress: Callable = Callable()) -> Array:
	last_error = ""
	var out: Array = []
	var seen := {}
	var i := 0
	var total := ids.size()
	while i < total:
		var chunk: PackedStringArray = []
		var stop := mini(i + 25, total)
		while i < stop:
			var id := ids[i].strip_edges()
			if not id.is_empty():
				chunk.append(id)
			i += 1
		if chunk.is_empty():
			continue
		if progress.is_valid():
			progress.call(out.size(), total)
		var hits: Array = await _request_search(
			{"id": ",".join(chunk)},
			0,
			true,
			LIST_FIELDS
		)
		for row: Variant in hits:
			if not row is Dictionary:
				continue
			var id := str((row as Dictionary).get("id", ""))
			if id.is_empty() or seen.has(id):
				continue
			seen[id] = true
			out.append(row)
	return out


## Pull playlist rows out of a local catalog dump, in playlist order.
static func rows_for_ids(rows: Array, ids: PackedStringArray) -> Array:
	if ids.is_empty() or rows.is_empty():
		return []
	var by_id := {}
	for entry: Variant in rows:
		if not entry is Dictionary:
			continue
		var rec: Dictionary = entry
		var id := str(rec.get("id", "")).strip_edges()
		if id.is_empty() or by_id.has(id):
			continue
		by_id[id] = rec
	var out: Array = []
	var seen := {}
	for raw in ids:
		var id := raw.strip_edges()
		if id.is_empty() or seen.has(id) or not by_id.has(id):
			continue
		seen[id] = true
		out.append(by_id[id])
	return out


static func missing_ids(rows: Array, ids: PackedStringArray) -> PackedStringArray:
	var have := {}
	for entry: Variant in rows:
		if not entry is Dictionary:
			continue
		var id := str((entry as Dictionary).get("id", "")).strip_edges()
		if not id.is_empty():
			have[id] = true
	var out := PackedStringArray()
	var seen := {}
	for raw in ids:
		var id := raw.strip_edges()
		if id.is_empty() or seen.has(id) or have.has(id):
			continue
		seen[id] = true
		out.append(id)
	return out


func _request_search(fields: Dictionary, limit: int = 0, any: bool = false, field_list: String = "") -> Array:
	last_error = ""
	var parts: PackedStringArray = []
	for key: Variant in fields.keys():
		var val := str(fields[key]).strip_edges()
		if val.is_empty():
			continue
		parts.append("%s=%s" % [str(key), val.uri_encode()])
	if any:
		parts.append("any=true")
	if not field_list.is_empty():
		parts.append("fields=%s" % field_list.uri_encode())
	if limit > 0:
		parts.append("limit=%d" % limit)
	if parts.is_empty():
		last_error = "Search needs a filter."
		return []
	var url := "%s/search?%s" % [API, "&".join(parts)]
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 240 if limit <= 0 else 90
	var err := http.request(url, PackedStringArray(["User-Agent: %s" % UA]))
	if err != OK:
		last_error = "Could not start search."
		http.queue_free()
		return []
	var result: Array = await http.request_completed
	http.queue_free()
	if int(result[1]) != 200:
		last_error = "Search returned HTTP %s." % str(result[1])
		return []
	var parsed: Variant = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())
	if parsed is Array:
		return _dedupe(parsed)
	last_error = "Search did not return a list."
	return []


func has_catalog(library: String) -> bool:
	return FileAccess.file_exists(catalog_path(library))


func catalog_path(library: String) -> String:
	var lib := library.strip_edges()
	if lib.is_empty():
		lib = "arcade"
	return "%s/%s.bin" % [CATALOG_DIR, lib]


func catalog_age_sec(library: String) -> int:
	var path := ProjectSettings.globalize_path(catalog_path(library))
	if not FileAccess.file_exists(path):
		return -1
	return int(Time.get_unix_time_from_system()) - int(FileAccess.get_modified_time(path))


func load_catalog_async(library: String) -> Array:
	while _io_busy:
		await get_tree().process_frame
	_io_busy = true
	_io_library = library
	_io_rows = []
	var task := WorkerThreadPool.add_task(_io_load)
	while not WorkerThreadPool.is_task_completed(task):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	var out: Array = _io_rows
	_io_busy = false
	return out


func save_catalog_async(library: String, rows: Array) -> void:
	if rows.is_empty():
		return
	while _io_busy:
		await get_tree().process_frame
	_io_busy = true
	_io_library = library
	_io_rows = rows
	var task := WorkerThreadPool.add_task(_io_save)
	while not WorkerThreadPool.is_task_completed(task):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	_io_busy = false


func _io_load() -> void:
	_io_rows = load_catalog(_io_library)


func _io_save() -> void:
	save_catalog(_io_library, _io_rows)


func load_catalog(library: String) -> Array:
	last_error = ""
	var path := catalog_path(library)
	if not FileAccess.file_exists(path):
		return []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = file.get_var(false)
	file.close()
	var rows: Array = []
	var sorted := false
	if parsed is Dictionary:
		var pack: Dictionary = parsed
		if pack.get("rows") is Array:
			rows = pack.get("rows")
			sorted = bool(pack.get("sorted", false))
	elif parsed is Array:
		rows = parsed
	if rows.is_empty():
		return []
	if not sorted:
		sort_titles(rows)
		save_catalog(library, rows)
	return rows


func save_catalog(library: String, rows: Array) -> void:
	if rows.is_empty():
		return
	sort_titles(rows)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CATALOG_DIR))
	var file := FileAccess.open(catalog_path(library), FileAccess.WRITE)
	if file == null:
		return
	file.store_var({"v": 2, "sorted": true, "rows": rows}, false)
	file.close()


static func sort_titles(rows: Array) -> void:
	rows.sort_custom(func(a: Variant, b: Variant) -> bool:
		var ta := str((a as Dictionary).get("title", "")).to_lower() if a is Dictionary else ""
		var tb := str((b as Dictionary).get("title", "")).to_lower() if b is Dictionary else ""
		return ta < tb
	)


func catalog_is_fresh(library: String) -> bool:
	var age := catalog_age_sec(library)
	return age >= 0 and age < CATALOG_MAX_AGE


static func parse_query(raw: String) -> Dictionary:
	var fields := {}
	var smart: PackedStringArray = []
	var s := raw.strip_edges()
	var i := 0
	while i < s.length():
		while i < s.length() and s[i] == " ":
			i += 1
		if i >= s.length():
			break
		var rest := s.substr(i)
		var colon := rest.find(":")
		var space := rest.find(" ")
		var key := ""
		if colon > 0 and (space == -1 or colon < space):
			key = rest.substr(0, colon).to_lower()
		if PREFIXES.has(key):
			i += colon + 1
			while i < s.length() and s[i] == " ":
				i += 1
			var val := _read_token(s, i)
			i = int(val.pos)
			var field: String = str(PREFIXES[key])
			if fields.has(field):
				fields[field] = str(fields[field]) + "," + str(val.text)
			else:
				fields[field] = str(val.text)
			continue
		var tok := _read_token(s, i)
		i = int(tok.pos)
		if not str(tok.text).is_empty():
			smart.append(str(tok.text))
	if not smart.is_empty():
		fields["smartSearch"] = " ".join(smart)
	return fields


static func _read_token(s: String, start: int) -> Dictionary:
	var i := start
	if i >= s.length():
		return {"text": "", "pos": i}
	if s[i] == '"':
		var end := s.find('"', i + 1)
		if end == -1:
			return {"text": s.substr(i + 1), "pos": s.length()}
		return {"text": s.substr(i + 1, end - i - 1), "pos": end + 1}
	var end2 := s.find(" ", i)
	if end2 == -1:
		return {"text": s.substr(i), "pos": s.length()}
	return {"text": s.substr(i, end2 - i), "pos": end2}


## Size of the download: GameZIP /get, or the main Legacy htdocs file.
func zip_size(uuid: String, launch: String = "") -> int:
	var id := uuid.strip_edges()
	if id.is_empty() and launch.is_empty():
		return -1
	var cache_key := id if not id.is_empty() else launch
	if _size_cache.has(cache_key):
		return int(_size_cache[cache_key])
	var n := await _head_length("%s/get?id=%s" % [API, id.uri_encode()]) if not id.is_empty() else -1
	if n <= 0 and not launch.is_empty():
		n = await _head_length(legacy_url(launch))
	if n > 0:
		_size_cache[cache_key] = n
	return n


func _head_length(url: String) -> int:
	last_error = ""
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 20
	var err := http.request(url, PackedStringArray(["User-Agent: %s" % UA]), HTTPClient.METHOD_HEAD)
	if err != OK:
		last_error = "Could not start size check."
		http.queue_free()
		return -1
	var result: Array = await http.request_completed
	http.queue_free()
	if int(result[1]) != 200:
		return -1
	var headers: PackedStringArray = result[2]
	for line in headers:
		if line.to_lower().begins_with("content-length:"):
			return int(line.split(":")[1].strip_edges())
	return -1


static func legacy_url(launch: String) -> String:
	var path := Unzip.path_from_launch(launch)
	if path.contains("?"):
		path = path.split("?")[0]
	var bits := path.split("/")
	var enc: PackedStringArray = []
	for b in bits:
		if not b.is_empty():
			enc.append(b.uri_encode())
	return LEGACY_HTDOCS + "/".join(enc)


static func format_bytes(n: int) -> String:
	if n < 1024:
		return "%d B" % n
	if n < 1024 * 1024:
		return "%.1f KB" % (float(n) / 1024.0)
	return "%.2f MB" % (float(n) / (1024.0 * 1024.0))


func download_zip(uuid: String, dest: String, progress: Callable = Callable()) -> bool:
	last_error = ""
	var id := uuid.strip_edges()
	if id.is_empty():
		last_error = "No Flashpoint id."
		return false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dest.get_base_dir()))
	var url := "%s/get?id=%s" % [API, id.uri_encode()]
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 0
	http.download_file = dest
	var ticker := Timer.new()
	ticker.wait_time = 0.4
	ticker.timeout.connect(func() -> void:
		if not progress.is_valid():
			return
		var total := http.get_body_size()
		if total > 0:
			progress.call(100.0 * float(http.get_downloaded_bytes()) / float(total))
	)
	add_child(ticker)
	var err := http.request(url, PackedStringArray(["User-Agent: %s" % UA]))
	if err != OK:
		last_error = "Could not start GameZIP download."
		ticker.queue_free()
		http.queue_free()
		return false
	ticker.start()
	var result: Array = await http.request_completed
	ticker.stop()
	ticker.queue_free()
	http.queue_free()
	if int(result[1]) != 200:
		last_error = "GameZIP download returned HTTP %s." % str(result[1])
		return false
	if not FileAccess.file_exists(dest):
		last_error = "Download finished but the zip is missing."
		return false
	if progress.is_valid():
		progress.call(100.0)
	return true


## Infinity-style: pull the launch file from Legacy/htdocs into dest/{host/path}.
func fetch_legacy(launch: String, dest_dir: String, progress: Callable = Callable()) -> String:
	last_error = ""
	var rel := Unzip.path_from_launch(launch)
	if rel.contains("?"):
		rel = rel.split("?")[0]
	if rel.is_empty():
		last_error = "No launch path."
		return ""
	var dest := ProjectSettings.globalize_path(dest_dir).path_join(rel)
	if FileAccess.file_exists(dest):
		return dest
	DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
	var url := legacy_url(launch)
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 0
	http.download_file = dest
	var err := http.request(url, PackedStringArray(["User-Agent: %s" % UA]))
	if err != OK:
		last_error = "Could not start legacy download."
		http.queue_free()
		return ""
	if progress.is_valid():
		progress.call(10.0)
	var result: Array = await http.request_completed
	http.queue_free()
	if int(result[1]) != 200:
		last_error = "Legacy download HTTP %s." % str(result[1])
		return ""
	if not FileAccess.file_exists(dest):
		last_error = "Legacy download wrote nothing."
		return ""
	if progress.is_valid():
		progress.call(100.0)
	return dest


## Pack a legacy tree into a zip so it can be inscribed like a GameZIP.
func pack_dir(src_dir: String, zip_path: String) -> bool:
	var abs := ProjectSettings.globalize_path(src_dir)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(zip_path.get_base_dir()))
	var zip := ZIPPacker.new()
	if zip.open(ProjectSettings.globalize_path(zip_path)) != OK:
		last_error = "Could not create zip."
		return false
	_zip_walk(zip, abs, "")
	zip.close()
	return FileAccess.file_exists(zip_path)


func _zip_walk(zip: ZIPPacker, abs_dir: String, rel: String) -> void:
	var d := DirAccess.open(abs_dir)
	if d == null:
		return
	d.list_dir_begin()
	var fname := d.get_next()
	while fname != "":
		if fname != "." and fname != "..":
			var child_abs := abs_dir.path_join(fname)
			var child_rel := fname if rel.is_empty() else rel.path_join(fname)
			if d.current_is_dir():
				_zip_walk(zip, child_abs, child_rel)
			else:
				zip.start_file("content/" + child_rel.replace("\\", "/"))
				zip.write_file(FileAccess.get_file_as_bytes(child_abs))
				zip.close_file()
		fname = d.get_next()
	d.list_dir_end()


func screenshot_url(uuid: String) -> String:
	return "%s/screenshot?id=%s&height=420&format=png" % [API, uuid.strip_edges().uri_encode()]


func logo_url(uuid: String) -> String:
	return "%s/logo?id=%s&height=72&format=png" % [API, uuid.strip_edges().uri_encode()]


func fetch_texture(url: String, cache_name: String) -> Texture2D:
	last_error = ""
	var path := "user://thumbs/%s.png" % cache_name.strip_edges()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://thumbs"))
	if FileAccess.file_exists(path):
		var cached := _texture_from_file(path)
		if cached != null:
			return cached
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 20
	http.download_file = path
	var err := http.request(url, PackedStringArray(["User-Agent: %s" % UA]))
	if err != OK:
		last_error = "Could not start image request."
		http.queue_free()
		return null
	var result: Array = await http.request_completed
	http.queue_free()
	if int(result[1]) != 200:
		last_error = "Image returned HTTP %s." % str(result[1])
		return null
	return _texture_from_file(path)


func _texture_from_file(path: String) -> Texture2D:
	var img := Image.new()
	if img.load(ProjectSettings.globalize_path(path)) != OK:
		return null
	return ImageTexture.create_from_image(img)


func is_gamezip(entry: Dictionary) -> bool:
	var zipped: Variant = entry.get("zipped", false)
	if zipped is bool:
		return zipped
	return str(zipped).to_lower() == "true"


## GameZIP via /get, or Legacy via Infinity's htdocs tree.
func playable_here(entry: Dictionary) -> bool:
	if is_gamezip(entry):
		return true
	return not Unzip.path_from_launch(launch_of(entry)).is_empty()


static func launch_of(entry: Dictionary) -> String:
	var cmd := str(entry.get("launchCommand", "")).strip_edges()
	if not cmd.is_empty():
		return cmd
	return str(entry.get("launch", "")).strip_edges()


static func platform_label(entry: Dictionary) -> String:
	var plat := str(entry.get("platform", "")).strip_edges()
	if plat.is_empty():
		return "Unknown"
	return plat.split(";")[0].strip_edges()


static func uses_ruffle(entry: Dictionary) -> bool:
	var launch := launch_of(entry).to_lower()
	if launch.find(".swf") >= 0:
		return true
	var plat := str(entry.get("platform", "")).to_lower()
	return plat.find("flash") >= 0 and launch.find(".html") < 0 and launch.find(".htm") < 0


static func uses_browser(entry: Dictionary) -> bool:
	if FlashpointHost.needs_flashpoint(entry) or FlashpointHost.needs_shockwave(entry):
		return false
	var launch := launch_of(entry).to_lower()
	var plat := str(entry.get("platform", "")).to_lower()
	if launch.find(".html") >= 0 or launch.find(".htm") >= 0:
		return true
	return plat.find("html") >= 0


func fetch_tags() -> PackedStringArray:
	last_error = ""
	if not _tag_names.is_empty():
		return _tag_names
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 60
	var err := http.request("%s/tags" % API, PackedStringArray(["User-Agent: %s" % UA]))
	if err != OK:
		last_error = "Could not start tags request."
		http.queue_free()
		return PackedStringArray()
	var result: Array = await http.request_completed
	http.queue_free()
	if int(result[1]) != 200:
		last_error = "Tags returned HTTP %s." % str(result[1])
		return PackedStringArray()
	var parsed: Variant = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())
	if not parsed is Array:
		last_error = "Tags did not return a list."
		return PackedStringArray()
	var names: PackedStringArray = []
	var seen := {}
	for row: Variant in parsed:
		if not row is Dictionary:
			continue
		var aliases: Variant = (row as Dictionary).get("aliases", [])
		var name := ""
		if aliases is Array and not (aliases as Array).is_empty():
			name = str((aliases as Array)[0]).strip_edges()
		if name.is_empty() or seen.has(name.to_lower()):
			continue
		seen[name.to_lower()] = true
		names.append(name)
	names.sort()
	_tag_names = names
	return names


func playlist_game_ids(component_id: String) -> PackedStringArray:
	last_error = ""
	var id := component_id.strip_edges()
	if id.is_empty() or id == "all":
		return PackedStringArray()
	if _playlist_ids.has(id):
		return _playlist_ids[id]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://playlists"))
	var zip_path := "user://playlists/%s.zip" % id
	if not FileAccess.file_exists(zip_path):
		if not await _download_file(PLAYLIST_ZIP % id, zip_path):
			return PackedStringArray()
	var ids := _ids_from_playlist_zip(zip_path)
	if ids.is_empty():
		last_error = "Playlist %s had no games." % id
		return PackedStringArray()
	_playlist_ids[id] = ids
	return ids


static func parse_playlist_ids(parsed: Variant) -> PackedStringArray:
	var games: Array = []
	if parsed is Dictionary:
		var g: Variant = (parsed as Dictionary).get("games", [])
		if g is Array:
			games = g
	elif parsed is Array:
		games = parsed
	var out := PackedStringArray()
	var seen := {}
	for row: Variant in games:
		var gid := _playlist_entry_game_id(row)
		if gid.is_empty() or seen.has(gid):
			continue
		seen[gid] = true
		out.append(gid)
	return out


## PlaylistGame.id is the row index; gameId is the catalog UUID.
static func _playlist_entry_game_id(row: Variant) -> String:
	if row is Dictionary:
		var rec: Dictionary = row
		var gid := _catalog_id_text(rec.get("gameId", null))
		if gid.is_empty():
			gid = _catalog_id_text(rec.get("id", null))
		return gid
	return _catalog_id_text(row)


static func _catalog_id_text(raw: Variant) -> String:
	if raw == null:
		return ""
	var t := typeof(raw)
	if t == TYPE_INT or t == TYPE_FLOAT:
		return ""
	return str(raw).strip_edges()


func _ids_from_playlist_zip(zip_path: String) -> PackedStringArray:
	var zip := ZIPReader.new()
	if zip.open(ProjectSettings.globalize_path(zip_path)) != OK:
		last_error = "Could not open playlist zip."
		return PackedStringArray()
	for name in zip.get_files():
		if not name.to_lower().ends_with(".json"):
			continue
		var parsed: Variant = JSON.parse_string(zip.read_file(name).get_string_from_utf8())
		var ids := parse_playlist_ids(parsed)
		if not ids.is_empty():
			return ids
	return PackedStringArray()


func _download_file(url: String, dest: String) -> bool:
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 60
	http.download_file = dest
	var err := http.request(url, PackedStringArray(["User-Agent: %s" % UA]))
	if err != OK:
		last_error = "Could not start playlist download."
		http.queue_free()
		return false
	var result: Array = await http.request_completed
	http.queue_free()
	if int(result[1]) != 200:
		last_error = "Playlist download HTTP %s." % str(result[1])
		return false
	return FileAccess.file_exists(dest)


func _dedupe(rows: Array) -> Array:
	var seen := {}
	var out: Array = []
	for row: Variant in rows:
		if not row is Dictionary:
			continue
		var id := str((row as Dictionary).get("id", ""))
		if id.is_empty() or seen.has(id):
			continue
		seen[id] = true
		out.append(row)
	return out
