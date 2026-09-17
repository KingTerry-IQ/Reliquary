## The inscribed cabinet: every game table under the app root, minus the
## operator sentinel.

class_name Cabinet
extends RefCounted

var space: IQSpace
var last_error: String = ""


func _init(iq: IQClient = null, chain: String = "mon") -> void:
	space = IQSpace.new(iq, Cartridge.APP_ROOT, chain)


func on(chain: String) -> Cabinet:
	var next := Cabinet.new()
	next.space = space.on(chain)
	return next


func is_kindled() -> bool:
	return await space.table_exists(Cartridge.KINDLED_TABLE)


## Operator-only. Creates the sentinel that stamps this wallet as root creator.
## The guest app must not call this unless the user is that operator.
func kindle(progress: Callable = Callable()) -> Variant:
	if await is_kindled():
		return {"already": true}
	var result = await space.create_table(
		Cartridge.KINDLED_TABLE,
		PackedStringArray(["id", "note"]),
		"id",
		PackedStringArray(),
		progress
	)
	if result != null:
		return result
	# Solana inits the db_root in a separate tx from createTable. If the
	# first call created the root and then raced, a second createTable finds
	# it and only mints `kindled`.
	if IQSpace.is_evm(space.chain) or not _looks_like_missing_root(space.last_error):
		last_error = space.last_error
		return null
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		await tree.create_timer(3.0).timeout
	result = await space.create_table(
		Cartridge.KINDLED_TABLE,
		PackedStringArray(["id", "note"]),
		"id",
		PackedStringArray(),
		progress
	)
	if result == null:
		last_error = space.last_error
	return result


func _looks_like_missing_root(message: String) -> bool:
	var lower := message.to_lower()
	return lower.find("db_root not found") >= 0 or lower.find("dbroot not found") >= 0


func table_names() -> PackedStringArray:
	var out: PackedStringArray = []
	if space.client == null or not space.client.is_available():
		last_error = "Not attached to a host."
		return out
	var listing: Dictionary = await space.client.get_db_table_list(Cartridge.APP_ROOT, space.chain)
	if listing.is_empty():
		last_error = space.client.last_error
		return out
	var raw: Array = []
	# EVM: `tables` is the public list; `globalTables` is every table under
	# the root. A just-created table can land in the latter first.
	for key in ["tables", "globalTables", "tableNames", "tableSeeds", "globalTableSeeds"]:
		if listing.get(key) is Array:
			for item: Variant in listing[key]:
				raw.append(item)
	if raw.is_empty() and not listing.is_empty():
		last_error = "Table list had no names. Keys: %s" % ", ".join(listing.keys())
	for item: Variant in raw:
		var name := ""
		if item is Dictionary:
			name = str((item as Dictionary).get("name", (item as Dictionary).get("tableName", (item as Dictionary).get("seedHex", ""))))
		else:
			name = str(item)
		name = _as_table_name(name)
		if name.is_empty() or Cartridge.is_kindled_table(name):
			continue
		if out.has(name):
			continue
		out.append(name)
	return out


func _as_table_name(raw: String) -> String:
	var name := raw.strip_edges()
	if Cartridge.is_kindled_table(name):
		return Cartridge.KINDLED_TABLE
	# Game tables are "g" + 23 hex chars. Do not treat that as a seed blob.
	if name.begins_with("g") and name.length() == 24:
		return name
	# Solana lists seeds as hex(utf-8(name)), including short names like kindled.
	if name.is_valid_hex_number() and name.length() % 2 == 0:
		var decoded := name.hex_decode().get_string_from_utf8()
		if Cartridge.is_kindled_table(decoded):
			return Cartridge.KINDLED_TABLE
		if not decoded.is_empty() and decoded.length() >= name.length() / 2:
			return decoded
	return name


func exists_for(uuid: String) -> bool:
	return await space.table_exists(Cartridge.table_name(uuid))


## Newest row only. After blob-then-meta writes, that is the cheap meta row.
func read_meta(table: String, progress: Callable = Callable()) -> Dictionary:
	var problem: Array = []
	var rows: Array = await space.read_rows(table, 1, problem, progress)
	if rows.is_empty():
		last_error = str(problem[0]) if not problem.is_empty() else "Empty table."
		return {}
	var meta := Cartridge.hydrate_meta(Cartridge.row_of(rows, Cartridge.META_ID))
	if not meta.is_empty():
		meta.erase("data")
		return meta
	var first: Dictionary = rows[0] if rows[0] is Dictionary else {}
	if str(first.get("id", "")) == Cartridge.BLOB_ID:
		# Older tables wrote meta first, so the blob is newest. Do not
		# reconstruct it just to paint a title.
		return {}
	first.erase("data")
	return first


func read_game(table: String, progress: Callable = Callable()) -> Dictionary:
	var problem: Array = []
	var rows: Array = await space.read_rows(table, 20, problem, progress)
	if rows.is_empty():
		last_error = str(problem[0]) if not problem.is_empty() else "Empty table."
		return {}
	return {
		"meta": Cartridge.hydrate_meta(Cartridge.row_of(rows, Cartridge.META_ID)),
		"blob": Cartridge.row_of(rows, Cartridge.BLOB_ID),
		"table": table,
	}


func inscribe(
	entry: Dictionary,
	zip_path: String,
	progress: Callable = Callable()
) -> Variant:
	var uuid := str(entry.get("id", "")).strip_edges()
	if uuid.is_empty():
		last_error = "Entry has no id."
		return null
	if not await is_kindled():
		last_error = "This chain has not been kindled."
		return null

	var table := Cartridge.table_name(uuid)
	var existed := await space.table_exists(table)
	if existed:
		var existing: Dictionary = await read_game(table, progress)
		var blob_data := str((existing.get("blob", {}) as Dictionary).get("data", ""))
		if not blob_data.is_empty():
			last_error = "Already inscribed as %s." % table
			return {"already": true, "table": table}

	var raw_bytes := FileAccess.get_file_as_bytes(zip_path)
	if raw_bytes.is_empty():
		last_error = "Could not read %s." % zip_path
		return null
	var sha := Cartridge.sha256_bytes(raw_bytes)
	var b64 := Marshalls.raw_to_base64(raw_bytes)

	if not existed:
		var created = await space.create_table(
			table,
			PackedStringArray(Cartridge.COLUMNS),
			Cartridge.ID_COLUMN,
			PackedStringArray(),
			progress
		)
		if created == null:
			last_error = space.last_error
			return null

		if not await _wait_until_exists(table):
			last_error = "Table was not visible on-chain after createTable."
			return null

	# Blob first, meta last: listing reads newest-first with limit 1 and
	# must not reconstruct the zip just to show a title.
	var blob = await space.write_row(
		table, Cartridge.blob_row(sha, raw_bytes.size(), b64), progress
	)
	if blob == null:
		last_error = space.last_error
		return null

	var meta = await space.write_row(table, Cartridge.meta_row(entry, sha, raw_bytes.size()), progress)
	if meta == null:
		last_error = space.last_error
		return null

	return {"table": table, "sha256": sha, "bytes": raw_bytes.size()}


func _wait_until_exists(table: String) -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	for _i in Cartridge.SETTLE_TRIES:
		if tree != null:
			await tree.create_timer(Cartridge.SETTLE_SECONDS).timeout
		if await space.table_exists(table):
			return true
	return false
