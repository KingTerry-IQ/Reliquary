## Flashpoint Infinity-style catalog: search metadata, fetch one GameZIP.

class_name Flashpoint
extends Node

const API := "https://db-api.unstable.life"
const UA := "FlashCartridge/0.1 (GodOnChain; archival client)"

var last_error: String = ""


func search(query: String, limit: int = 40) -> Array:
	last_error = ""
	var q := query.strip_edges()
	if q.is_empty():
		last_error = "Type something to search."
		return []
	var url := (
		"%s/search?smartSearch=%s&platform=Flash&limit=%d"
		% [API, q.uri_encode(), limit]
	)
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 30
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


func download_zip(uuid: String, dest: String) -> bool:
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
	var err := http.request(url, PackedStringArray(["User-Agent: %s" % UA]))
	if err != OK:
		last_error = "Could not start GameZIP download."
		http.queue_free()
		return false
	var result: Array = await http.request_completed
	http.queue_free()
	if int(result[1]) != 200:
		last_error = "GameZIP download returned HTTP %s." % str(result[1])
		return false
	if not FileAccess.file_exists(dest):
		last_error = "Download finished but the zip is missing."
		return false
	return true


func is_gamezip(entry: Dictionary) -> bool:
	var zipped: Variant = entry.get("zipped", false)
	if zipped is bool:
		return zipped
	return str(zipped).to_lower() == "true"


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
