extends SceneTree

## Headless checks that do not need a host or the network.
##
##   Godot --headless --path . --script res://tools/selftest.gd

var _failed := 0
var _passed := 0


func _init() -> void:
	_run()
	quit(1 if _failed > 0 else 0)


func _run() -> void:
	_check(
		"table names are 24 chars and stable",
		Cartridge.table_name("08143aa7-f3ae-45b0-a1d4-afa4ac44c845").length() == 24
	)
	_check(
		"same uuid always the same table",
		Cartridge.table_name("abc") == Cartridge.table_name("abc")
	)
	_check(
		"different uuids different tables",
		Cartridge.table_name("abc") != Cartridge.table_name("abd")
	)
	_check("table name starts with g", Cartridge.table_name("x").begins_with("g"))

	var hello := "flash".to_utf8_buffer()
	_check(
		"sha256 of known bytes",
		Cartridge.sha256_bytes(hello)
		== "851e43bd44a2c3d30e5f3acadc9240c12d9f1c610dba34761e8c47ba82d1daea"
	)

	_check("base64 of 1 byte is 4", Costs.base64_bytes(1) == 4)
	_check("base64 of 3 bytes is 4", Costs.base64_bytes(3) == 4)
	_check("base64 of 1MB is 4/3", Costs.base64_bytes(1_048_576) == 1_398_104)

	_check("Monad createTable is 19.5", is_equal_approx(Costs.create_table("mon"), 19.5))
	_check("inscribe costs more than createTable", Costs.inscribe("mon", 1_048_576) > Costs.create_table("mon"))
	_check("SOL inscribe is far cheaper than MON", Costs.inscribe("sol", 1_048_576) < 1.0)
	_check("quote mentions createTable", Costs.quote_inscribe("mon", 1000).find("createTable") >= 0)

	_check("kindled table name is kindled", Cartridge.KINDLED_TABLE == "kindled")
	_check(
		"root string is load-bearing",
		Cartridge.APP_ROOT == "GodOnChain-KingTerry-FlashCartridge"
	)
	_check("id column is id", Cartridge.ID_COLUMN == "id")
	_check("columns include data", Cartridge.COLUMNS.has("data"))

	var meta := Cartridge.meta_row(
		{"id": "u", "title": "T", "launchCommand": "http://x/a.swf", "platform": "Flash"},
		"abc",
		12
	)
	_check("meta row id", meta["id"] == Cartridge.META_ID)
	_check("blob row carries data", Cartridge.blob_row("abc", 12, "Zg==")["data"] == "Zg==")

	print("selftest: %d passed, %d failed" % [_passed, _failed])


func _check(name: String, ok: bool) -> void:
	if ok:
		_passed += 1
		print("  ok  ", name)
	else:
		_failed += 1
		print("  FAIL  ", name)
