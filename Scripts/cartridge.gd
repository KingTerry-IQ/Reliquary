## One Flash game on-chain: a table under the shared root whose rows are
## the metadata and the GameZIP.

class_name Cartridge
extends RefCounted

const PROTOCOL := "flash-cartridge/1"
## Kindled under this path. The display name is Reliquary; the root does not move.
const APP_ROOT := "GodOnChain-KingTerry-FlashCartridge"
const KINDLED_TABLE := "kindled"
## Solana lists table seeds as hex(utf-8(name)). "kindled" → this.
const KINDLED_HEX := "6b696e646c6564"
const COLUMNS := [
	"id",
	"uuid",
	"title",
	"launch",
	"sha256",
	"bytes",
	"kind",
	"platform",
	"data",
]
const ID_COLUMN := "id"
const META_ID := "meta"
const BLOB_ID := "blob"
const SETTLE_SECONDS := 2.5
const SETTLE_TRIES := 8


static func is_kindled_table(name: String) -> bool:
	var n := name.strip_edges().to_lower()
	return n == KINDLED_TABLE or n == KINDLED_HEX


static func table_name(uuid: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(uuid.strip_edges().to_utf8_buffer())
	return "g" + ctx.finish().hex_encode().substr(0, 23)


static func sha256_bytes(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()


static func sha256_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	while not file.eof_reached():
		var chunk: PackedByteArray = file.get_buffer(1024 * 1024)
		if chunk.is_empty():
			break
		ctx.update(chunk)
	file.close()
	return ctx.finish().hex_encode()


static func staging_path(uuid: String) -> String:
	return "user://staging/%s.zip" % uuid.strip_edges()


static func cache_dir(table: String) -> String:
	return "user://cartridges/%s" % table


static func trial_dir(uuid: String) -> String:
	return "user://trials/%s" % uuid.strip_edges()


static func trials_root() -> String:
	return "user://trials"


static func has_play_cache(table: String) -> bool:
	var n := table.strip_edges()
	return not n.is_empty() and DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(cache_dir(n)))


## Bytes on disk under path (file or directory). Missing paths are 0.
static func tree_bytes(path: String) -> int:
	var abs := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path) or FileAccess.file_exists(abs):
		return _file_bytes(path)
	if not DirAccess.dir_exists_absolute(abs):
		return 0
	var total := 0
	var d := DirAccess.open(abs)
	if d == null:
		return 0
	d.list_dir_begin()
	var fname := d.get_next()
	while fname != "":
		if fname != "." and fname != "..":
			var child := path.path_join(fname)
			if d.current_is_dir():
				total += tree_bytes(child)
			else:
				total += _file_bytes(child)
		fname = d.get_next()
	d.list_dir_end()
	return total


## Recursively delete path. Returns bytes removed.
static func remove_tree(path: String) -> int:
	var abs := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path) or FileAccess.file_exists(abs):
		var n := _file_bytes(path)
		DirAccess.remove_absolute(abs)
		return n
	if not DirAccess.dir_exists_absolute(abs):
		return 0
	var total := 0
	var d := DirAccess.open(abs)
	if d == null:
		return 0
	d.list_dir_begin()
	var fname := d.get_next()
	while fname != "":
		if fname != "." and fname != "..":
			var child := path.path_join(fname)
			if d.current_is_dir():
				total += remove_tree(child)
			else:
				total += _file_bytes(child)
				d.remove(fname)
		fname = d.get_next()
	d.list_dir_end()
	DirAccess.remove_absolute(abs)
	return total


## Extracted TRY copies plus their staging zips. Play caches stay.
static func wipe_trials() -> int:
	var total := remove_tree(trials_root())
	var staging := ProjectSettings.globalize_path("user://staging")
	var d := DirAccess.open(staging)
	if d != null:
		d.list_dir_begin()
		var fname := d.get_next()
		while fname != "":
			if fname != "." and fname != ".." and not d.current_is_dir() and _is_trial_staging_name(fname):
				var child := "user://staging".path_join(fname)
				total += _file_bytes(child)
				d.remove(fname)
			fname = d.get_next()
		d.list_dir_end()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(trials_root()))
	return total


## Extracted PLAY copy and its staging zip. The chain still holds the GameZIP.
static func drop_play_cache(table: String) -> int:
	var n := table.strip_edges()
	if n.is_empty() or is_kindled_table(n):
		return 0
	var total := remove_tree(cache_dir(n))
	var zip := staging_path(n)
	if FileAccess.file_exists(zip):
		total += remove_tree(zip)
	return total


static func _is_trial_staging_name(fname: String) -> bool:
	return fname.get_basename().contains("-")


static func _file_bytes(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		f = FileAccess.open(ProjectSettings.globalize_path(path), FileAccess.READ)
	if f == null:
		return 0
	var n := f.get_length()
	f.close()
	return n


static func meta_row(entry: Dictionary, sha: String, raw_bytes: int) -> Dictionary:
	return {
		"id": META_ID,
		"uuid": str(entry.get("id", "")),
		"title": str(entry.get("title", "")),
		"launch": str(entry.get("launchCommand", "")),
		"sha256": sha,
		"bytes": str(raw_bytes),
		"kind": "zip",
		"platform": str(entry.get("platform", "Flash")),
		"data": "",
	}


static func blob_row(sha: String, raw_bytes: int, b64: String) -> Dictionary:
	return {
		"id": BLOB_ID,
		"uuid": "",
		"title": "",
		"launch": "",
		"sha256": sha,
		"bytes": str(raw_bytes),
		"kind": "zip",
		"platform": "Flash",
		"data": b64,
	}


static func row_of(rows: Array, id: String) -> Dictionary:
	for row: Variant in rows:
		if row is Dictionary and str((row as Dictionary).get("id", "")) == id:
			return row
	return {}
