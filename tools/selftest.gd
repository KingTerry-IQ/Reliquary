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
	_check("kindled hex is ignored", Cartridge.is_kindled_table("6b696e646c6564"))
	_check("kindled plaintext is ignored", Cartridge.is_kindled_table("kindled"))
	_check("game tables are not kindled", not Cartridge.is_kindled_table("g" + "a".repeat(23)))
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

	_check(
		"launch URL strips scheme",
		Unzip.path_from_launch("http://uploads.ungrounded.net/59000/game.swf")
		== "uploads.ungrounded.net/59000/game.swf"
	)
	_check(
		"https launch strips too",
		Unzip.path_from_launch("https://example.com/a.swf") == "example.com/a.swf"
	)
	_check("empty launch is empty path", Unzip.path_from_launch("").is_empty())
	var fp := Flashpoint.new()
	_check("Flashpoint GameZIP flag", fp.is_gamezip({"zipped": true}))
	_check("legacy titles are not GameZIP", not fp.is_gamezip({"zipped": false}))
	_check("Flash zip is playable", fp.playable_here({"zipped": true, "platform": "Flash", "launchCommand": "http://x/a.swf"}))
	_check("HTML5 zip is playable", fp.playable_here({"zipped": true, "platform": "HTML5", "launchCommand": "http://x/index.html"}))
	_check("legacy with a launch path is playable", fp.playable_here({"zipped": false, "platform": "Flash", "launchCommand": "http://farm.maxgames.com/game.swf"}))
	_check("legacy url is Infinity htdocs", Flashpoint.legacy_url("http://farm.maxgames.com/a.swf").find("Legacy/htdocs/farm.maxgames.com/a.swf") >= 0)
	_check("ruffle for swf", Flashpoint.uses_ruffle({"platform": "Flash", "launchCommand": "http://x/a.swf"}))
	_check("browser for html5", Flashpoint.uses_browser({"platform": "HTML5", "launchCommand": "http://x/index.html"}))
	_check(
		"quoted launch URL is the movie",
		Unzip.movie_url('"http://www.miniclip.com/games/bprally/en/game.dcr" --setTheRunMode "Plugin" --do "go(2)"')
		== "http://www.miniclip.com/games/bprally/en/game.dcr"
	)
	var extra := Unzip.extra_args('"http://x/game.dcr" --do "go(2)"')
	_check("launch extra args keep --do text", extra.size() == 2 and extra[0] == "--do" and extra[1] == "go(2)")
	_check(
		"path_from_launch ignores SPR flags",
		Unzip.path_from_launch('"http://farm.maxgames.com/game.dcr" --forceTheExitLock 0')
		== "farm.maxgames.com/game.dcr"
	)
	_check(
		"shockwave dcr needs SPR",
		FlashpointHost.needs_shockwave({"platform": "Shockwave", "launchCommand": "http://x/a.dcr"})
	)
	_check(
		"shockwave does not need CLIFp",
		not FlashpointHost.needs_flashpoint({"platform": "Shockwave", "launchCommand": "http://x/a.dcr"})
	)
	_check(
		"PJ folder from applicationPath",
		Spr.projector_folder("FPSoftware\\Shockwave\\PJ1159\\SPR.exe") == "PJ1159"
	)
	_check("default PJ is PJ101", Spr.projector_folder("") == "PJ101")
	var pl := Flashpoint.parse_playlist_ids({
		"title": "X",
		"games": [{"id": "aaa"}, {"gameId": "bbb"}, {"id": "aaa"}],
	})
	_check("playlist ids from games[].id", pl.size() == 2 and pl[0] == "aaa" and pl[1] == "bbb")
	_check("All Games is first playlist", str(Flashpoint.PLAYLISTS[0].get("id", "")) == "all")
	var alpha: Array = [{"title": "Zed"}, {"title": "alpha"}, {"title": "Beta"}]
	Flashpoint.sort_titles(alpha)
	_check(
		"titles sort A-Z case-insensitive",
		str(alpha[0].get("title", "")) == "alpha"
		and str(alpha[1].get("title", "")) == "Beta"
		and str(alpha[2].get("title", "")) == "Zed"
	)
	_check(
		"library: prefix is a field not smart search",
		str(Flashpoint.parse_query("library:arcade").get("library", "")) == "arcade"
		and not Flashpoint.parse_query("library:arcade").has("smartSearch")
	)
	_check(
		"proxy absolute GET maps host/path",
		LocalHttp.target_path("GET http://www.bigideafun.com/veggietales/arcade/scuba/Scuba.dcr HTTP/1.0\r\n\r\n")
		== "www.bigideafun.com/veggietales/arcade/scuba/Scuba.dcr"
	)
	_check(
		"origin GET keeps path",
		LocalHttp.target_path("GET /foo/bar.swf HTTP/1.1\r\nHost: 127.0.0.1:18765\r\n\r\n") == "foo/bar.swf"
	)
	_check(
		"origin GET plus Host becomes archive path",
		LocalHttp.target_path("GET /game.dcr HTTP/1.1\r\nHost: www.miniclip.com\r\n\r\n")
		== "www.miniclip.com/game.dcr"
	)
	var parsed := Flashpoint.parse_query("title:Bowman tag:Arcade leftover")
	_check("prefix title", str(parsed.get("title", "")) == "Bowman")
	_check("prefix tag", str(parsed.get("tags", "")) == "Arcade")
	_check("bare words stay smart", str(parsed.get("smartSearch", "")) == "leftover")
	_check("quoted prefix", str(Flashpoint.parse_query("dev:\"Tom Fulp\"").get("developer", "")) == "Tom Fulp")
	_check("bytes format MB", Flashpoint.format_bytes(5379797).find("MB") >= 0)

	print("selftest: %d passed, %d failed" % [_passed, _failed])


func _check(name: String, ok: bool) -> void:
	if ok:
		_passed += 1
		print("  ok  ", name)
	else:
		_failed += 1
		print("  FAIL  ", name)
