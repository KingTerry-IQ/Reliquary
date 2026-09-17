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
	_check("quote names the amount", Costs.quote_inscribe("mon", 1000).begins_with("About "))

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
	_check("trial dir is under trials", Cartridge.trial_dir("abc").begins_with("user://trials/"))
	_check("play cache dir is under cartridges", Cartridge.cache_dir("gabc").begins_with("user://cartridges/"))

	var trial_probe := Cartridge.trial_dir("_selftest_trial")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(trial_probe))
	var trial_file := FileAccess.open(trial_probe.path_join("probe.txt"), FileAccess.WRITE)
	_check("can write a trial probe", trial_file != null)
	if trial_file != null:
		trial_file.store_string("trial")
		trial_file.close()
	var play_probe := "gselftestcache00000000000"
	var play_dir := Cartridge.cache_dir(play_probe)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(play_dir))
	var play_file := FileAccess.open(play_dir.path_join("blob.bin"), FileAccess.WRITE)
	_check("can write a play-cache probe", play_file != null)
	if play_file != null:
		play_file.store_buffer(PackedByteArray([1, 2, 3, 4, 5]))
		play_file.close()
	_check("has_play_cache sees extract", Cartridge.has_play_cache(play_probe))
	_check("play cache size is at least the probe", Cartridge.tree_bytes(play_dir) >= 5)
	var cleared := Cartridge.wipe_trials()
	_check("wipe_trials frees the trial probe", cleared >= 5)
	_check(
		"wipe_trials removes trial files",
		not FileAccess.file_exists(trial_probe.path_join("probe.txt"))
	)
	_check("wipe_trials leaves play caches", Cartridge.has_play_cache(play_probe))
	var staging_trial := Cartridge.staging_path("08143aa7-f3ae-45b0-a1d4-afa4ac44c845")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://staging"))
	var st := FileAccess.open(staging_trial, FileAccess.WRITE)
	if st != null:
		st.store_string("zip")
		st.close()
	var cleared_staging := Cartridge.wipe_trials()
	_check("wipe_trials drops trial staging zips", not FileAccess.file_exists(staging_trial) and cleared_staging >= 3)
	var freed := Cartridge.drop_play_cache(play_probe)
	_check("drop_play_cache frees bytes", freed >= 5)
	_check("drop_play_cache removes the extract", not Cartridge.has_play_cache(play_probe))
	_check("empty table has no play cache", not Cartridge.has_play_cache(""))
	_check("kindled drop is a no-op", Cartridge.drop_play_cache("kindled") == 0)

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
	var sas2 := "http://3rdsense.com/Swords and Sandals 2/Swords and Sandals 2.swf"
	_check("unquoted Flash URL keeps spaces", Unzip.movie_url(sas2) == sas2)
	_check(
		"spaced Flash path is host/path",
		Unzip.path_from_launch(sas2)
		== "3rdsense.com/Swords and Sandals 2/Swords and Sandals 2.swf"
	)
	_check("spaced Flash URL has no extra args", Unzip.extra_args(sas2).is_empty())
	var unquoted_flags := Unzip.extra_args("http://farm.maxgames.com/game.dcr --forceTheExitLock 0")
	_check(
		"unquoted URL extra args after --",
		unquoted_flags.size() == 2
		and unquoted_flags[0] == "--forceTheExitLock"
		and unquoted_flags[1] == "0"
	)
	_check(
		"encode launch URL percent-encodes spaces",
		Unzip.encode_launch_url(sas2).find("%20") >= 0
		and Unzip.encode_launch_url(sas2).begins_with("http://3rdsense.com/")
		and Unzip.encode_launch_url(sas2).ends_with(".swf")
	)
	_check(
		"legacy url encodes spaced Flash path",
		Flashpoint.legacy_url(sas2).find("Swords%20and%20Sandals%202") >= 0
	)
	var rargs := Ruffle.cli_args(sas2, "", "http://127.0.0.1:18765", sas2)
	_check("ruffle encodes movie spaces", rargs.size() > 0 and rargs[0].find("%20") >= 0)
	_check("ruffle proxy flag", rargs.find("--proxy") >= 0)
	_check("ruffle spoof-url flag", rargs.find("--spoof-url") >= 0)
	_check("ruffle omits --base when unused", rargs.find("--base") < 0)
	var sargs := Ruffle.cli_args("http://x/a.swf", "", "", "", "C:/saves/ruffle")
	_check("ruffle stores SharedObjects on disk", sargs.find("--save-directory") >= 0 and sargs.find("C:/saves/ruffle") >= 0)
	_check(
		"ruffle for spaced Flash URL",
		Flashpoint.uses_ruffle({"platform": "Flash", "launchCommand": sas2})
	)
	_check(
		"Unity version prefix is not the path",
		Unzip.movie_url("5.x http://chat.kongregate.com/gamez/0016/7201/live/index.html")
		== "http://chat.kongregate.com/gamez/0016/7201/live/index.html"
	)
	_check(
		"Unity prefix path is host/path",
		Unzip.path_from_launch("2.x http://img-hws.y8.com/game/index.html")
		== "img-hws.y8.com/game/index.html"
	)
	_check(
		"Pulse quoted URL after runtime prefix",
		Unzip.movie_url('Pulse "http://localpulse/learningfriends/StartHere.html"')
		== "http://localpulse/learningfriends/StartHere.html"
	)
	_check(
		"ShiVa prefix URL",
		Unzip.movie_url("shiva3d http://www.shotiris.net/file.stk")
		== "http://www.shotiris.net/file.stk"
	)
	var oldcpu := '-t 366 -sw ..\\Shockwave\\PJ101\\SPR.exe http://www.mediamacros.com/item_files/937495492/centipede.dcr'
	_check(
		"OldCPUSimulator launch URL is the dcr",
		Unzip.movie_url(oldcpu) == "http://www.mediamacros.com/item_files/937495492/centipede.dcr"
	)
	_check(
		"OldCPUSimulator extra args skip -t -sw",
		Unzip.extra_args(oldcpu + " --disableGoToNetPage").size() == 1
		and Unzip.extra_args(oldcpu + " --disableGoToNetPage")[0] == "--disableGoToNetPage"
	)
	_check(
		"ActiveX trailing dll is not the URL",
		Unzip.movie_url("http://games.bigfishgames.com/online/index.html mjolauncher\\mjolauncher.dll")
		== "http://games.bigfishgames.com/online/index.html"
	)
	_check(
		"quoted Flash URL with apostrophe",
		Unzip.movie_url("\"http://i.4cdn.org/f/I'm Dead.swf\"")
		== "http://i.4cdn.org/f/I'm Dead.swf"
	)
	_check(
		"hash is not part of the path",
		Unzip.path_from_launch("http://example.com/game.swf#zoom") == "example.com/game.swf"
	)
	_check_launch_resolve()
	_check(
		"inscribed launch field still ruffles",
		Flashpoint.uses_ruffle({"platform": "Flash", "launch": "http://x/a.swf"})
	)
	_check(
		"Unity HTML still needs Flashpoint",
		FlashpointHost.needs_flashpoint({
			"platform": "Unity",
			"launchCommand": "5.x http://x/index.html",
			"applicationPath": "FPSoftware\\startUnity.bat",
		})
	)
	_check(
		"HTML5 does not need CLIFp",
		not FlashpointHost.needs_flashpoint({"platform": "HTML5", "launchCommand": "http://x/index.html"})
	)
	_check(
		"Java needs Flashpoint",
		FlashpointHost.needs_flashpoint({"platform": "Java", "launchCommand": "http://x/index.html"})
	)
	_check(
		"Silverlight needs Flashpoint",
		FlashpointHost.needs_flashpoint({"platform": "Silverlight", "launchCommand": "http://x/index.html"})
	)
	_check(
		"browser is not used for Unity",
		not Flashpoint.uses_browser({"platform": "Unity", "launchCommand": "http://x/index.html"})
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
		"OldCPUSimulator dcr still needs SPR",
		FlashpointHost.needs_shockwave({
			"platform": "Shockwave",
			"applicationPath": "FPSoftware\\OldCPUSimulator\\OldCPUSimulator.exe",
			"launchCommand": oldcpu,
		})
	)
	_check(
		"PJ folder from applicationPath",
		Spr.projector_folder("FPSoftware\\Shockwave\\PJ1159\\SPR.exe") == "PJ1159"
	)
	_check("default PJ is PJ101", Spr.projector_folder("") == "PJ101")
	_check(
		"PJ folder from OldCPUSimulator launch",
		Spr.projector_for({
			"applicationPath": "FPSoftware\\OldCPUSimulator\\OldCPUSimulator.exe",
			"launchCommand": oldcpu,
		})
		== "PJ101"
	)
	var hydrated := Cartridge.hydrate_meta({
		"launch": "http://x/a.dcr",
		"data": "FPSoftware\\Shockwave\\PJ851\\SPR.exe",
	})
	_check(
		"hydrate meta restores applicationPath",
		str(hydrated.get("applicationPath", "")).find("PJ851") >= 0
		and str(hydrated.get("launchCommand", "")) == "http://x/a.dcr"
	)
	_check(
		"meta row stores applicationPath in data",
		str(Cartridge.meta_row(
			{"id": "u", "title": "T", "launchCommand": "http://x/a.dcr", "platform": "Shockwave", "applicationPath": "FPSoftware\\Shockwave\\PJ851\\SPR.exe"},
			"abc",
			12
		).get("data", "")).find("PJ851")
		>= 0
	)
	_check(
		"SPR Windows launch uses a normal window",
		Spr.LAUNCH_PS1.find("ProcessWindowStyle]::Normal") >= 0
	)
	_check(
		"SPR Windows launch restores a minimized window",
		Spr.LAUNCH_PS1.find("ShowWindowAsync(h, 9)") >= 0
	)
	_check(
		"SPR Windows launch allows foreground",
		Spr.LAUNCH_PS1.find("AllowSetForegroundWindow(-1)") >= 0
	)
	var pl := Flashpoint.parse_playlist_ids({
		"title": "X",
		"games": [{"id": "aaa"}, {"gameId": "bbb"}, {"id": "aaa"}],
	})
	_check("playlist ids from games[].id", pl.size() == 2 and pl[0] == "aaa" and pl[1] == "bbb")
	var hof := Flashpoint.parse_playlist_ids(JSON.parse_string(
		'{"games":[{"id":2067,"gameId":"f31407f9-bd4c-4687-9b79-91954433d569"},{"id":2068,"gameId":"5b857b0e-2bb8-4983-a5fd-399bc1db2236"},{"id":2067,"gameId":"f31407f9-bd4c-4687-9b79-91954433d569"}]}'
	))
	_check(
		"playlist prefers gameId over numeric row id",
		hof.size() == 2
		and hof[0] == "f31407f9-bd4c-4687-9b79-91954433d569"
		and hof[1] == "5b857b0e-2bb8-4983-a5fd-399bc1db2236"
	)
	_check("All Games is first playlist", str(Flashpoint.PLAYLISTS[0].get("id", "")) == "all")
	var catalog_rows: Array = [
		{"id": "aaa", "title": "Alpha"},
		{"id": "bbb", "title": "Beta"},
		{"id": "ccc", "title": "Gamma"},
	]
	var picked: Array = Flashpoint.rows_for_ids(
		catalog_rows,
		PackedStringArray(["ccc", "aaa", "zzz", "ccc"])
	)
	_check(
		"playlist rows follow catalog ids in playlist order",
		picked.size() == 2
		and str(picked[0].get("title", "")) == "Gamma"
		and str(picked[1].get("title", "")) == "Alpha"
	)
	var missing: PackedStringArray = Flashpoint.missing_ids(
		picked,
		PackedStringArray(["ccc", "aaa", "zzz"])
	)
	_check("playlist missing ids skip catalog hits", missing.size() == 1 and missing[0] == "zzz")
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
	_check(
		"proxy GET decodes spaced Flash path",
		LocalHttp.target_path(
			"GET http://3rdsense.com/Swords%20and%20Sandals%202/Swords%20and%20Sandals%202.swf HTTP/1.1\r\n\r\n"
		)
		== "3rdsense.com/Swords and Sandals 2/Swords and Sandals 2.swf"
	)
	_check(
		"proxy GET keeps unencoded spaces in request line",
		LocalHttp.target_path(
			"GET http://3rdsense.com/Swords and Sandals 2/Swords and Sandals 2.swf HTTP/1.1\r\n\r\n"
		)
		== "3rdsense.com/Swords and Sandals 2/Swords and Sandals 2.swf"
	)
	_check(
		"ruffle asset ignores host mapping",
		LocalHttp.ruffle_asset_rel("tetrisow-a.akamaihd.net/__ruffle/ruffle.js") == "ruffle.js"
	)
	_check(
		"ruffle asset from origin path",
		LocalHttp.ruffle_asset_rel("__ruffle/core.ruffle.wasm") == "core.ruffle.wasm"
	)
	_check(
		"html injects ruffle before head close",
		LocalHttp.inject_ruffle_html("<html><head></head><body></body></html>").find("/__ruffle/ruffle.js") >= 0
	)
	_check(
		"absolute URLs fold onto this origin",
		LocalHttp.rewrite_absolute_urls('<script src="http://cdn.example.com/game.js"></script>')
		== '<script src="/cdn.example.com/game.js"></script>'
	)
	_check(
		"localhost URLs are not rewritten",
		LocalHttp.rewrite_absolute_urls('http://127.0.0.1:18765/a.js') == "http://127.0.0.1:18765/a.js"
	)
	_check(
		"cartridge hook patches fetch",
		LocalHttp.inject_cartridge_html("<html><head></head></html>").find("window.fetch") >= 0
	)
	_check(
		"html inject is idempotent",
		LocalHttp.inject_ruffle_html("<script src=\"/__ruffle/ruffle.js\"></script>").find("ruffle.js")
		== LocalHttp.inject_ruffle_html(LocalHttp.inject_ruffle_html("<script src=\"/__ruffle/ruffle.js\"></script>")).find("ruffle.js")
	)
	var bargs := LocalHttp.browser_launch_args("http://example.com/game.html", 18765, "C:/tmp/profile")
	var proxy_arg := ""
	for a in bargs:
		if str(a).begins_with("--proxy-server"):
			proxy_arg = str(a)
	_check("browser uses a per-process HTTP proxy", proxy_arg.find("http=127.0.0.1:18765") >= 0)
	_check("browser does not proxy HTTPS probes", proxy_arg.find("https=direct://") >= 0)
	_check("browser opens the original host URL", bargs.find("http://example.com/game.html") >= 0)
	_httpd_survives_dropped_peer()
	_check(
		"HTML5 uses Navigator pack, not Chromium",
		Packs.pack_id_for({"platform": "HTML5", "applicationPath": "FPSoftware\\fpnavigator-portable\\FPNavigator.exe"})
		== "supportpack-common-fpnavigator"
	)
	_check(
		"Unity maps to the Unity support pack",
		Packs.pack_id_for({"platform": "Unity", "applicationPath": "FPSoftware\\startUnity.bat"})
		== "supportpack-unity"
	)
	_check(
		"Java maps to the Java support pack",
		Packs.pack_id_for({"platform": "Java", "launchCommand": "http://x/index.html"})
		== "supportpack-java"
	)
	_check("Navigator prefs pin HTTP proxy", Packs.NAV_PREFS.find("network.proxy.http_port") >= 0)
	var shiva_inv := Packs.secureplayer_invocation(
		{
			"applicationPath": "FPSoftware\\FlashpointSecurePlayer.exe",
			"launchCommand": "shiva3d http://www.shotiris.net/tmp/bubblePipe.stk",
		},
		"http://localhost:22600/www.shotiris.net/tmp/bubblePipe.stk",
		"http://www.shotiris.net/tmp/bubblePipe.stk"
	)
	_check(
		"ShiVa SecurePlayer gets original URL for 22600 rewrite",
		shiva_inv.size() == 2
		and shiva_inv[0] == "shiva3d"
		and shiva_inv[1].begins_with("http://www.shotiris.net/")
	)
	var activex_inv := Packs.secureplayer_invocation(
		{
			"applicationPath": "FPSoftware\\startActiveX.bat",
			"launchCommand": "http://games.bigfishgames.com/online/index.html mjolauncher\\mjolauncher.dll",
		},
		"http://localhost:22600/games.bigfishgames.com/online/index.html",
		"http://games.bigfishgames.com/online/index.html"
	)
	_check(
		"ActiveX SecurePlayer gets template plus local page",
		activex_inv.size() == 2
		and activex_inv[0].find("mjolauncher") >= 0
		and activex_inv[1].begins_with("http://localhost:22600/")
	)
	_check("Unity pack label is readable", Packs.pack_label("supportpack-unity").find("Unity") >= 0)
	var parsed_packs := Packs._parse_components(
		(
			"<list><category id=\"supportpack\"><category id=\"common\">"
			+ "<component id=\"fpnavigator\" hash=\"abc\" />"
			+ "</category><component id=\"unity\" hash=\"def\" depends=\"supportpack-common-fpnavigator\" />"
			+ "</category></list>"
		).to_utf8_buffer()
	)
	_check(
		"component ids nest category prefixes",
		parsed_packs.has("supportpack-common-fpnavigator") and parsed_packs.has("supportpack-unity")
	)
	var parsed := Flashpoint.parse_query("title:Bowman tag:Arcade leftover")
	_check("prefix title", str(parsed.get("title", "")) == "Bowman")
	_check("prefix tag", str(parsed.get("tags", "")) == "Arcade")
	_check("bare words stay smart", str(parsed.get("smartSearch", "")) == "leftover")
	_check("quoted prefix", str(Flashpoint.parse_query("dev:\"Tom Fulp\"").get("developer", "")) == "Tom Fulp")
	_check("bytes format MB", Flashpoint.format_bytes(5379797).find("MB") >= 0)

	var built := TempleTheme.build()
	_check("temple theme builds", built != null)
	_check("chip box is flat", TempleTheme.chip_box(TempleTheme.YELLOW) is StyleBoxFlat)
	var key := TempleTheme.index_button("A", TempleTheme.YELLOW)
	_check("index button is a letter", key != null and key.text == "A")
	key.free()

	var main: Control = (load("res://Scenes/main.gd") as GDScript).new()
	main._build_ui()
	_check("ui tree is not empty", main.get_child_count() > 0)
	_check("archive list exists", main._archive != null)
	_check("library has games and anims only", main._library.item_count == 2)
	_check("library has no BOTH", main._library.get_item_text(0) == "GAMES" and main._library.get_item_text(1) == "ANIMS")
	_check("library defaults to games", main._library.selected == 0 and main._library_filter() == "arcade")
	main._library.select(1)
	_check("library anims is theatre", main._library_filter() == "theatre")
	main._library.select(0)
	_check("library games is arcade", main._library_filter() == "arcade")
	_check("cabinet list exists", main._inscribed_list != null)
	_check("stage actions exist", main._inscribe_btn != null and main._play_btn != null)
	_check("drop cache action exists", main._drop_btn != null)
	_check(
		"drop cache is not a peer of PLAY",
		main._drop_btn.get_parent() != main._play_btn.get_parent()
	)
	_check("drop cache starts hidden", not main._drop_btn.visible)
	var proceed := TempleTheme.primary_button("PROCEED", func() -> void: pass)
	_check(
		"primary focused text is black",
		proceed.has_theme_color_override("font_focus_color")
		and proceed.get_theme_color("font_focus_color") == TempleTheme.BLACK
	)
	proceed.free()
	_check("cabinet cache filter exists", main._cabinet_cached_btn != null)
	_check("letter index is A–Z plus #", main._letter_bar != null and main._letter_bar.get_child_count() == 27)
	_check("cabinet letter index matches", main._cabinet_letters != null and main._cabinet_letters.get_child_count() == 27)
	_check("console starts closed", main._console != null and not main._console.visible)
	_check("grid is the default view", main._view_grid == true and main._view_btn.text == "LIST")
	_check("status chips are wrapped", main._host_label.get_parent() is PanelContainer)
	_check("display name is Reliquary", main.APP_NAME == "Reliquary")
	var icon := FileAccess.get_file_as_string("res://icon.svg")
	_check("icon is not the burning bush", icon.find("M20 96C20 74") < 0)
	var split_names: PackedStringArray = main._facet_names("Tom Fulp; Chris, Newgrounds")
	_check(
		"facet names split commas and semicolons",
		split_names.size() == 3
		and "Tom Fulp" in split_names
		and "Chris" in split_names
		and "Newgrounds" in split_names
	)
	main._fill_credits({
		"developer": "Tom Fulp, Chris",
		"publisher": "Newgrounds",
		"series": "Pico",
		"platform": "Flash",
		"releaseDate": "2004",
	})
	var credit_btns: PackedStringArray = []
	var credit_labels: PackedStringArray = []
	for child in main._meta_box.get_children():
		if child is Button:
			credit_btns.append((child as Button).text)
		elif child is Label and (child as Label).text != "·":
			credit_labels.append((child as Label).text)
	_check("stage developer is clickable", "Tom Fulp" in credit_btns and "Chris" in credit_btns)
	_check("stage publisher is clickable", "Newgrounds" in credit_btns)
	_check("stage series is clickable", "Pico" in credit_btns)
	_check("stage platform stays text", "Flash" in credit_labels)
	_check("stage date stays text", "2004" in credit_labels)
	main._fill_tags({"tags": ["Arcade", "Shooter"]})
	var tag_btns: PackedStringArray = []
	for child in main._tag_box.get_children():
		if child is Button:
			tag_btns.append((child as Button).text)
	_check("stage tags stay clickable", "Arcade" in tag_btns and "Shooter" in tag_btns)
	main._sel_dev = "Tom Fulp"
	main._sel_pub = "Newgrounds"
	main._sel_series = "Pico"
	main._sel_tag = "Arcade"
	main._search.text = "Bowman"
	main._browse_letter = "B"
	main._playlist_id = "playlist-halloffame"
	if main._playlist != null and main._playlist.item_count > 1:
		main._playlist.select(1)
	main._search_facet("tag", "Shooter")
	_check(
		"stage tag click clears other facets",
		main._sel_tag == "Shooter"
		and main._sel_dev.is_empty()
		and main._sel_pub.is_empty()
		and main._sel_series.is_empty()
		and main._search.text.is_empty()
		and main._browse_letter.is_empty()
	)
	_check(
		"stage tag click switches to All Games",
		main._playlist_id == "all"
		and (
			main._playlist == null
			or str(main._playlist.get_item_metadata(main._playlist.selected)) == "all"
		)
	)
	main._playlist_id = "playlist-halloffame"
	if main._playlist != null and main._playlist.item_count > 1:
		main._playlist.select(1)
	main._sel_tag = "Arcade"
	main._search_facet("dev", "Tom Fulp")
	_check(
		"stage developer click clears tags",
		main._sel_dev == "Tom Fulp" and main._sel_tag.is_empty()
	)
	_check(
		"stage developer click switches to All Games",
		main._playlist_id == "all"
	)
	main.free()

	var pick := FacetPick.new()
	_check("facet pick is a container", pick is HBoxContainer)
	_check("facet pick has a row height", pick.custom_minimum_size.y >= 20)
	pick.free()

	print("selftest: %d passed, %d failed" % [_passed, _failed])


func _write_probe(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_buffer(PackedByteArray([1, 2, 3]))
		f.close()


func _check_launch_resolve() -> void:
	var root := "user://selftest_launch"
	var abs := ProjectSettings.globalize_path(root)
	DirAccess.make_dir_recursive_absolute(abs)
	_write_probe(root.path_join("content/amanita-design.net/samorost-1/main.swf"))
	_write_probe(root.path_join("content/amanita-design.net/samorost-1/lyzar1.swf"))
	_write_probe(root.path_join("content/games.bigfishgames.com/en_samorost-1/online/Samorost1.swf"))
	_write_probe(root.path_join("content/localflash/fishy.swf"))
	_write_probe(root.path_join("content/cache.armorgames.com/files/games/shift-751.swf"))
	var stale := "http://localflash/samorost/main.swf"
	_check(
		"stale launch maps onto the extract host path",
		Unzip.resolved_rel(root, stale) == "amanita-design.net/samorost-1/main.swf"
	)
	_check(
		"stale launch movie is the extract URL",
		Unzip.resolved_movie(root, stale) == "http://amanita-design.net/samorost-1/main.swf"
	)
	_check(
		"stale launch does not pick a sibling scene",
		Unzip.file_matching(root, stale).replace("\\", "/").ends_with("/samorost-1/main.swf")
	)
	_check(
		"proxy GET of resolved movie stays on the extract path",
		LocalHttp.target_path("GET http://amanita-design.net/samorost-1/main.swf HTTP/1.1\r\n\r\n")
		== "amanita-design.net/samorost-1/main.swf"
	)
	_check(
		"exact localflash launch still wins",
		Unzip.resolved_rel(root, "http://localflash/fishy.swf") == "localflash/fishy.swf"
	)
	_check(
		"renamed pack still finds the movie by path tokens",
		Unzip.resolved_rel(root, "http://localflash/shift-751817f.swf")
		== "cache.armorgames.com/files/games/shift-751.swf"
	)


func _tcp_wait(peer: StreamPeerTCP, want: int, ms: int) -> bool:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < ms:
		peer.poll()
		if peer.get_status() == want:
			return true
		if peer.get_status() == StreamPeerTCP.STATUS_ERROR:
			return false
		OS.delay_msec(1)
	return peer.get_status() == want


func _httpd_survives_dropped_peer() -> void:
	var httpd := LocalHttp.new()
	var root := "user://selftest_http"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root))
	var idx := FileAccess.open(root.path_join("index.html"), FileAccess.WRITE)
	_check("httpd probe file", idx != null)
	if idx:
		idx.store_string("<html>ok</html>")
		idx.close()
	var hp := httpd.serve(root)
	_check("httpd listens", hp > 0)
	if hp <= 0:
		httpd.free()
		return
	var abort := StreamPeerTCP.new()
	abort.connect_to_host("127.0.0.1", hp)
	_tcp_wait(abort, StreamPeerTCP.STATUS_CONNECTED, 1000)
	abort.disconnect_from_host()
	httpd._process(0.0)
	var client := StreamPeerTCP.new()
	client.connect_to_host("127.0.0.1", hp)
	_check("httpd client connects after a dropped peer", _tcp_wait(client, StreamPeerTCP.STATUS_CONNECTED, 1000))
	var body := ""
	if client.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		client.put_data("GET /index.html HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n".to_utf8_buffer())
		var resp := PackedByteArray()
		var start := Time.get_ticks_msec()
		while Time.get_ticks_msec() - start < 1000:
			httpd._process(0.0)
			client.poll()
			if client.get_status() != StreamPeerTCP.STATUS_CONNECTED:
				break
			var n := client.get_available_bytes()
			if n > 0:
				resp.append_array(client.get_data(n)[1])
				if resp.get_string_from_utf8().find("ok</html>") >= 0:
					break
			OS.delay_msec(1)
		body = resp.get_string_from_utf8()
		client.disconnect_from_host()
	_check("httpd serves after a dropped peer", body.find("HTTP/1.1 200") >= 0 and body.find("ok</html>") >= 0)
	httpd.stop()
	httpd.free()


func _check(name: String, ok: bool) -> void:
	if ok:
		_passed += 1
		print("  ok  ", name)
	else:
		_failed += 1
		print("  FAIL  ", name)
