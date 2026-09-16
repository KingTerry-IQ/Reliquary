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
	if result == null:
		last_error = space.last_error
	return result


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
	if listing.get("tables") is Array:
		raw = listing["tables"]
	elif listing.get("tableNames") is Array:
		raw = listing["tableNames"]
	elif listing.get("tableSeeds") is Array:
		raw = listing["tableSeeds"]
	for item: Variant in raw:
		var name := ""
		if item is Dictionary:
			name = str((item as Dictionary).get("name", (item as Dictionary).get("tableName", (item as Dictionary).get("seedHex", ""))))
		else:
			name = str(item)
		name = _as_table_name(name)
		if name.is_empty() or name == Cartridge.KINDLED_TABLE:
			continue
		out.append(name)
	return out


func _as_table_name(raw: String) -> String:
	var name := raw.strip_edges()
	if name.begins_with("g") and name.length() == 24:
		return name
	if name == Cartridge.KINDLED_TABLE:
		return name
	# Solana lists seeds as hex(utf-8(name)).
	if name.is_valid_hex_number() and name.length() % 2 == 0 and name.length() > 24:
		var decoded := name.hex_decode().get_string_from_utf8()
		if not decoded.is_empty():
			return decoded
	return name


func exists_for(uuid: String) -> bool:
	return await space.table_exists(Cartridge.table_name(uuid))


func read_game(table: String, progress: Callable = Callable()) -> Dictionary:
	var problem: Array = []
	var rows: Array = await space.read_rows(table, 20, problem, progress)
	if rows.is_empty():
		last_error = str(problem[0]) if not problem.is_empty() else "Empty table."
		return {}
	return {
		"meta": Cartridge.row_of(rows, Cartridge.META_ID),
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
		last_error = (
			"This chain has not been kindled. The operators must create the "
			+ "dbRoot before anyone can inscribe."
		)
		return null

	var table := Cartridge.table_name(uuid)
	if await space.table_exists(table):
		last_error = "Already inscribed as %s." % table
		return {"already": true, "table": table}

	var raw_bytes := FileAccess.get_file_as_bytes(zip_path)
	if raw_bytes.is_empty():
		last_error = "Could not read %s." % zip_path
		return null
	var sha := Cartridge.sha256_bytes(raw_bytes)
	var b64 := Marshalls.raw_to_base64(raw_bytes)

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

	var meta = await space.write_row(table, Cartridge.meta_row(entry, sha, raw_bytes.size()), progress)
	if meta == null:
		last_error = space.last_error
		return null

	var blob = await space.write_row(
		table, Cartridge.blob_row(sha, raw_bytes.size(), b64), progress
	)
	if blob == null:
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
