## Titles the operator marked to come back to.
##
## A favourite is a local bookmark, not an inscription: it costs nothing, it is
## not on the chain, and marking one does not download anything. It keeps the
## catalog row it was marked from so the Favourites collection can be listed
## without the archive being loaded — or reachable at all.

class_name Favorites
extends RefCounted

const INDEX_PATH := "user://favorites.json"
const VERSION := 1
## Enough to list and launch a title; the rest comes from the catalog.
const KEEP_FIELDS: PackedStringArray = [
	"id",
	"title",
	"developer",
	"publisher",
	"series",
	"platform",
	"library",
	"launchCommand",
	"applicationPath",
	"zipped",
	"tags",
	"releaseDate",
]

var entries: Dictionary = {}


func load_index() -> void:
	entries = {}
	if not FileAccess.file_exists(INDEX_PATH):
		return
	var file := FileAccess.open(INDEX_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return
	var pack: Dictionary = parsed
	var rows: Variant = pack.get("entries", null)
	if rows is Dictionary:
		entries = rows
	elif pack.has("v"):
		entries = {}
	else:
		## A bare map written before the wrapper existed.
		entries = pack


func save_index() -> bool:
	var file := FileAccess.open(INDEX_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"v": VERSION, "entries": entries}))
	file.close()
	return true


static func uuid_of(entry: Dictionary) -> String:
	var id := str(entry.get("id", "")).strip_edges()
	if id.is_empty():
		id = str(entry.get("uuid", "")).strip_edges()
	return id


func has(entry: Dictionary) -> bool:
	var id := uuid_of(entry)
	return not id.is_empty() and entries.has(id)


func has_id(uuid: String) -> bool:
	return entries.has(uuid.strip_edges())


## Keep only what listing and launching need, so the file stays small and does
## not rot into a stale second copy of the catalog.
static func slim(entry: Dictionary) -> Dictionary:
	var out := {}
	for key in KEEP_FIELDS:
		if entry.has(key):
			out[key] = entry[key]
	if not out.has("launchCommand") and entry.has("launch"):
		out["launchCommand"] = entry["launch"]
	return out


func add(entry: Dictionary) -> bool:
	var id := uuid_of(entry)
	if id.is_empty():
		return false
	var rec := slim(entry)
	rec["id"] = id
	rec["marked"] = int(Time.get_unix_time_from_system())
	entries[id] = rec
	return save_index()


func remove(entry: Dictionary) -> bool:
	var id := uuid_of(entry)
	if id.is_empty() or not entries.has(id):
		return false
	entries.erase(id)
	return save_index()


## Returns the new state, so a caller can repaint without asking again.
func toggle(entry: Dictionary) -> bool:
	if has(entry):
		remove(entry)
		return false
	add(entry)
	return true


func size() -> int:
	return entries.size()


func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for key: Variant in entries.keys():
		out.append(str(key))
	return out


## Newest mark first — the order someone building a collection expects.
func rows() -> Array:
	var out: Array = []
	for key: Variant in entries.keys():
		var rec: Variant = entries[key]
		if rec is Dictionary:
			out.append(rec)
	out.sort_custom(func(a: Variant, b: Variant) -> bool:
		return int((a as Dictionary).get("marked", 0)) > int((b as Dictionary).get("marked", 0))
	)
	return out


## Prefer the live catalog row when we have one: the saved copy is a fallback
## for titles the archive cannot reach right now, not a source of truth.
func rows_merged(catalog: Array) -> Array:
	if catalog.is_empty():
		return rows()
	var live := {}
	for entry: Variant in catalog:
		if not entry is Dictionary:
			continue
		var id := uuid_of(entry)
		if not id.is_empty() and entries.has(id):
			live[id] = entry
	var out: Array = []
	for entry: Variant in rows():
		var rec: Dictionary = entry
		var id := uuid_of(rec)
		out.append(live.get(id, rec))
	return out
