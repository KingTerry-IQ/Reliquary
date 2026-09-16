## One Flash game on-chain: a table under the shared root whose rows are
## the metadata and the GameZIP.

class_name Cartridge
extends RefCounted

const PROTOCOL := "flash-cartridge/1"
const APP_ROOT := "GodOnChain-KingTerry-FlashCartridge"
const KINDLED_TABLE := "kindled"
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
