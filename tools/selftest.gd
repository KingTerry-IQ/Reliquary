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
	_check_flash_runtime()
	_check_tag_filter()
	_check_mime_sniffing()
	_check_navigator_proxy()
	_check_favorites()
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
		"Vitalize uses the plugin host",
		FlashpointHost.needs_flashpoint({
			"platform": "Vitalize",
			"applicationPath": "FPSoftware\\fpnavigator-portable\\FPNavigator.exe",
			"launchCommand": "http://koti.mbnet.fi/~wicked/skede_hacked.ccn",
		})
	)
	_check(
		"WildTangent template prefix uses the plugin host",
		FlashpointHost.needs_flashpoint({
			"platform": "WildTangent",
			"applicationPath": "FPSoftware\\FlashpointSecurePlayer.exe",
			"launchCommand": "wildtangent http://localwt/speedway/INDEX.HTM",
		})
	)
	_check(
		"SVG plugin prefix uses the plugin host",
		FlashpointHost.needs_flashpoint({
			"platform": "SVG",
			"applicationPath": "FPSoftware\\FlashpointSecurePlayer.exe",
			"launchCommand": "svg http://www.adobe.com/svg/demos/chart.html",
		})
	)
	_check(
		"Netscape start bat uses the plugin host",
		FlashpointHost.needs_flashpoint({
			"platform": "EVA",
			"applicationPath": "FPSoftware\\startNetscape.bat",
			"launchCommand": "http://www.sharp.co.jp/sc/excite/evademo/try/scr/girl.eva",
		})
	)
	_check(
		"Flash HTML stays local",
		not FlashpointHost.needs_flashpoint({
			"platform": "Flash",
			"applicationPath": "FPSoftware\\Flash\\flashplayer_32_sa.exe",
			"launchCommand": "http://x/game.html",
		})
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
	_check(
		"SPR Windows launch raises child process windows",
		Spr.LAUNCH_PS1.find("ParentProcessId") >= 0
	)
	_check(
		"era-speed host console stays hidden",
		Spr.LAUNCH_PS1.find("CreateNoWindow") >= 0 and Spr.LAUNCH_PS1.find("HideHost") >= 0
	)
	_check(
		"era-speed skips raising the console window",
		Spr.LAUNCH_PS1.find("ConsoleWindowClass") >= 0
	)
	_check(
		"player ready file is written when a window appears",
		Spr.LAUNCH_PS1.find("ReadyFile") >= 0 and Spr.LAUNCH_PS1.find("HasVisible") >= 0
	)
	_check(
		"missing runtime prompt has a heading",
		preload("res://Scenes/main.gd").MISSING_RUNTIME == "MISSING RUNTIME"
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
		"proxy FTP GET maps host/path",
		LocalHttp.target_path("GET ftp://cache.lego.com/eng/game.dcr HTTP/1.0\r\n\r\n")
		== "cache.lego.com/eng/game.dcr"
	)
	_check(
		"http version echoes HTTP/1.0",
		LocalHttp.http_version("GET http://x/a.dcr HTTP/1.0\r\n\r\n") == "HTTP/1.0"
	)
	_check(
		"http version defaults to HTTP/1.1",
		LocalHttp.http_version("GET /a.dcr HTTP/1.1\r\n\r\n") == "HTTP/1.1"
	)
	_check(
		"http date is RFC 1123 GMT",
		LocalHttp.http_date(0).ends_with(" GMT") and LocalHttp.http_date(0).find(",") > 0
	)
	_check(
		"director unpublished cast maps to cct",
		LocalHttp.director_alt_rel("spynet/sound_level_1.cst") == "spynet/sound_level_1.cct"
	)
	_check(
		"director published movie maps to dir",
		LocalHttp.director_alt_rel("game.dcr") == "game.dir"
	)
	_check(
		"windows authoring path is a filesystem rel",
		LocalHttp.is_filesystem_rel(
			"C:/Documents and Settings/Administrator/Desktop/SPYBOTS/CODE/phase_6_GOLD_FINAL/807/sound_level_1.cst"
		)
	)
	_check(
		"archive host path is not a filesystem rel",
		not LocalHttp.is_filesystem_rel("cache.lego.com/eng/games/spybotics/spynet/sound_level_1.cct")
	)
	_check(
		"htm folds onto html",
		LocalHttp.alt_rels("game/INDEX.HTM").find("game/INDEX.html") >= 0
	)
	_check(
		"www fold strips the www prefix",
		LocalHttp.www_fold_rel("www.lego.com/eng/game.swf") == "lego.com/eng/game.swf"
	)
	_check(
		"www fold adds the www prefix",
		LocalHttp.www_fold_rel("lego.com/eng/game.swf") == "www.lego.com/eng/game.swf"
	)
	_check(
		"crossdomain stub is a policy file",
		LocalHttp.policy_body("site/crossdomain.xml").find("allow-access-from") >= 0
	)
	_check(
		"swa is a Director type",
		LocalHttp.mime_for("music.swa") == "application/x-director"
	)
	_check(
		"w3d is a Director type",
		LocalHttp.mime_for("mesh.w3d") == "application/x-director"
	)
	_check("html mime has no charset", LocalHttp.mime_for("index.html") == "text/html")
	_check(
		"cpu mhz from OldCPUSimulator -t",
		Unzip.cpu_mhz(oldcpu) == 366
	)
	_check(
		"curation -t wins when authentic is off",
		Unzip.era_mhz({"releaseDate": "2008"}, oldcpu, false) == 366
	)
	_check(
		"era mhz follows release year",
		Unzip.era_mhz({"releaseDate": "2002-06-01", "launchCommand": "http://x/a.dcr"}, "", true)
		== 800
	)
	_check(
		"modern speed skips throttle without -t",
		Unzip.era_mhz({"releaseDate": "2002", "launchCommand": "http://x/a.swf"}, "", false) == 0
	)
	var oc_args := Spr.oldcpu_args(800, "C:/SPR.exe", PackedStringArray(["http://x/a.dcr"]))
	_check(
		"oldcpu wraps the player after -sw",
		oc_args.size() >= 7
		and oc_args[0] == "-t"
		and oc_args[1] == "800"
		and oc_args[5] == "-sw"
		and oc_args[6] == "C:/SPR.exe"
		and oc_args[7] == "http://x/a.dcr"
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
	_check(
		"Netscape start bat maps to the Netscape pack",
		Packs.pack_id_for({
			"platform": "EVA",
			"applicationPath": "FPSoftware\\startNetscape.bat",
		})
		== "supportpack-common-netscape"
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

	## A filter belongs to the list it was typed against.
	main._sel_dev = "Tom Fulp"
	main._sel_pub = "Newgrounds"
	main._sel_series = "Pico"
	main._sel_tag = "Arcade"
	main._search.text = "Bowman"
	main._browse_letter = "B"
	if main._playlist != null and main._playlist.item_count > 1:
		main._playlist.select(1)
		main._on_playlist_selected(1)
	_check(
		"collection switch clears the search",
		main._search.text.is_empty() and main._browse_letter.is_empty()
	)
	_check(
		"collection switch clears the facets",
		main._sel_dev.is_empty()
		and main._sel_pub.is_empty()
		and main._sel_series.is_empty()
		and main._sel_tag.is_empty()
	)
	main._select_playlist("all")

	## Marking a favourite must not move the browse out from under the operator.
	var star_rows: Array = []
	for n in 5:
		star_rows.append({"id": "selftest-star-%d" % n, "title": "Star %d" % n})
	main._archive.clear()
	for entry: Variant in star_rows:
		var rec: Dictionary = entry
		var at: int = main._archive.add_item(main._archive_label(rec))
		main._archive.set_item_metadata(at, rec)
	main._archive.select(3)
	_check("archive row reports the selection", main._archive_row() == 3)
	## Marked in memory only — the selftest never touches the saved index.
	main.favorites.entries["selftest-star-3"] = {"id": "selftest-star-3"}
	main._repaint_archive_row("selftest-star-3")
	_check("favourite stars the row it was pressed on", main._archive.get_item_text(3).begins_with("★"))
	_check("favourite leaves the other rows alone", not main._archive.get_item_text(0).begins_with("★"))
	_check("favourite keeps the row selected", main._archive_row() == 3)
	_check("favourite keeps the list as it was", main._archive.item_count == 5)
	main.favorites.entries.erase("selftest-star-3")

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
	_write_probe(root.path_join("content/cache.lego.com/eng/games/spybotics/spynet/spybot_0807_sw.dcr"))
	_write_probe(root.path_join("content/cache.lego.com/eng/games/spybotics/spynet/sound_level_1.cct"))
	_write_probe(root.path_join("content/www.example.com/game/index.htm"))
	_check(
		"www host request finds the archive without www",
		LocalHttp.file_in_tree(root.path_join("content"), "example.com/game/index.htm")
		.replace("\\", "/")
		.ends_with("/www.example.com/game/index.htm")
	)
	_check(
		"directory index prefers htm when html is absent",
		LocalHttp.index_file(
			ProjectSettings.globalize_path(root.path_join("content/www.example.com/game"))
		)
		.replace("\\", "/")
		.ends_with("/index.htm")
	)
	var spy_root := root.path_join("content")
	_check(
		"director cst request folds onto the published cct",
		LocalHttp.file_in_tree(spy_root, "cache.lego.com/eng/games/spybotics/spynet/sound_level_1.cst")
		.replace("\\", "/")
		.ends_with("/spynet/sound_level_1.cct")
	)
	var spy_hint := ProjectSettings.globalize_path(
		spy_root.path_join("cache.lego.com/eng/games/spybotics/spynet")
	)
	_check(
		"authoring-path cast resolves next to the movie",
		LocalHttp.file_in_tree(
			spy_root,
			"C:/Documents and Settings/Administrator/Desktop/SPYBOTS/CODE/phase_6_GOLD_FINAL/807/sound_level_1.cst",
			spy_hint
		)
		.replace("\\", "/")
		.ends_with("/spynet/sound_level_1.cct")
	)


## Flashpoint runs Flash in the projector its applicationPath names. We have to
## pick the same one, or we are not running the archive the way it was curated.
func _check_flash_runtime() -> void:
	var plain := {
		"platform": "Flash",
		"applicationPath": "FPSoftware\\Flash\\flashplayer_32_sa.exe",
		"launchCommand": "http://www.andkon.com/arcade/sport/bowman/bowman.swf",
	}
	_check("default Flash entry uses the projector", Flash.projector_entry(plain))
	_check("default projector is Flash 32", Flash.projector_name(plain) == "flashplayer_32_sa.exe")

	var pinned := {
		"platform": "Flash",
		"applicationPath": "FPSoftware\\Flash\\flashplayer9r277_win_sa.exe",
		"launchCommand": "http://example.com/old.swf",
	}
	_check(
		"a pinned projector is honoured, not replaced by Flash 32",
		Flash.projector_name(pinned) == "flashplayer9r277_win_sa.exe"
	)

	var versioned := {
		"platform": "Flash",
		"applicationPath": "FPSoftware\\Flash\\8r22\\SAFlashPlayer.exe",
		"launchCommand": "http://example.com/old.swf",
	}
	_check(
		"a versioned projector folder maps onto the pack's filename",
		Flash.projector_name(versioned) == "SAFlashPlayer_8r22.exe"
	)

	var throttled := {
		"platform": "Flash",
		"applicationPath": "FPSoftware\\OldCPUSimulator\\OldCPUSimulator.exe",
		"launchCommand": "-t 65 -sw ..\\Flash\\flashplayer_32_sa.exe http://example.com/slow.swf",
	}
	_check("OldCPUSimulator entries still play in the projector", Flash.projector_entry(throttled))
	_check(
		"the projector comes from -sw, not from OldCPUSimulator",
		Flash.projector_name(throttled) == "flashplayer_32_sa.exe"
	)
	_check("-sw target is read off the launch command", Unzip.sw_exe(
		"-t 65 -sw ..\\Flash\\flashplayer_32_sa.exe http://example.com/slow.swf"
	) == "..\\Flash\\flashplayer_32_sa.exe")
	_check("curation -t still wins the clock", Unzip.cpu_mhz(
		"-t 65 -sw ..\\Flash\\flashplayer_32_sa.exe http://example.com/slow.swf"
	) == 65)
	_check(
		"the movie URL survives the OldCPUSimulator prefix",
		Unzip.movie_url("-t 65 -sw ..\\Flash\\flashplayer_32_sa.exe http://example.com/slow.swf")
		== "http://example.com/slow.swf"
	)

	var in_page := {
		"platform": "Flash",
		"applicationPath": "FPSoftware\\fpnavigator-portable\\FPNavigator.exe",
		"launchCommand": "http://example.com/game.html",
	}
	_check("browser-embedded Flash stays out of the projector", not Flash.projector_entry(in_page))
	_check("browser-embedded Flash goes to Navigator", FlashpointHost.needs_flashpoint(in_page))
	_check("Navigator gets the Flash plugin pack", Packs.pack_id_for(in_page) == "supportpack-flash")

	## Flashpoint opens every FPNavigator entry in Navigator, HTML5 included.
	var html5 := {
		"platform": "HTML5",
		"applicationPath": "FPSoftware\\fpnavigator-portable\\FPNavigator.exe",
		"launchCommand": "http://example.com/game.html",
	}
	_check("HTML5 on Navigator goes to Navigator", FlashpointHost.needs_flashpoint(html5))
	_check("HTML5 on Navigator needs no Flash plugin", Packs.pack_id_for(html5) == "supportpack-common-fpnavigator")
	_check("an HTML5 page is browser-renderable", FlashpointHost.page_entry(html5))
	_check("Flash in a page is browser-renderable", FlashpointHost.page_entry(in_page))

	## …but a plugin entry has no browser alternative, so the toggle must not
	## be allowed to divert it.
	var unity := {
		"platform": "Unity",
		"applicationPath": "FPSoftware\\startUnity.bat",
		"launchCommand": "5.x http://example.com/game.unity3d",
	}
	_check("Unity still needs Flashpoint", FlashpointHost.needs_flashpoint(unity))
	_check("Unity is not browser-renderable", not FlashpointHost.page_entry(unity))
	_check("Unity is not a page despite the html launch", not FlashpointHost.page_entry({
		"platform": "Silverlight",
		"applicationPath": "FPSoftware\\fpnavigator-portable\\FPNavigator.exe",
		"launchCommand": "http://example.com/game.xap",
	}))

	## An entry with no applicationPath is unchanged: still our own page path.
	var bare_html5 := {"platform": "HTML5", "launchCommand": "http://example.com/index.html"}
	_check("a plain HTML5 row stays on the local page path", not FlashpointHost.needs_flashpoint(bare_html5))
	_check("a plain HTML5 row is still a browser entry", Flashpoint.uses_browser(bare_html5))

	## "FlashpointSecurePlayer" starts with "Flashp", not "FlashPla" — the
	## projector test has to stay narrow enough to tell them apart.
	var secure := {
		"platform": "3D Groove GX",
		"applicationPath": "FPSoftware\\FlashpointSecurePlayer.exe",
		"launchCommand": "3dgroovegx http://example.com/game.gx",
	}
	_check(
		"Secure Player entries are not mistaken for Flash",
		Packs.pack_id_for(secure) == "supportpack-common-secureplayer"
	)
	_check("Secure Player is not a projector", not Flash.projector_entry(secure))

	var shockwave := {
		"platform": "Shockwave",
		"applicationPath": "FPSoftware\\Shockwave\\PJ101\\SPR.exe",
		"launchCommand": "http://example.com/movie.dcr",
	}
	_check("Shockwave never reaches the Flash projector", not Flash.projector_entry(shockwave))

	var root := "user://selftest_flash"
	_write_probe(root.path_join("content/www.example.com/files/game.swf"))
	_check(
		"the projector is handed the archived URL, not a file path",
		Flash.movie_for(root, "http://www.example.com/files/game.swf")
		== "http://www.example.com/files/game.swf"
	)
	_check(
		"flashvars in the launch query survive",
		Flash.movie_for(root, "http://www.example.com/files/game.swf?lang=fr")
		== "http://www.example.com/files/game.swf?lang=fr"
	)
	_check(
		"our proxy maps that URL back onto the extract",
		LocalHttp.target_path("GET http://www.example.com/files/game.swf HTTP/1.1\r\n\r\n")
		== "www.example.com/files/game.swf"
	)


## Flashpoint's tag filters decide what the archive pane lists. Off by default
## except the group Flashpoint itself ships enabled.
func _check_tag_filter() -> void:
	var tf := TagFilter.new()
	_check("ships Flashpoint's seven groups", tf.groups.size() == 7)
	_check("extreme is hidden out of the box", not tf.show_extreme)
	_check("filtering is on out of the box", tf.is_filtering())

	var porn := {"title": "x", "tags": ["Hentai", "Anime"]}
	var gore := {"title": "x", "tags": ["Gore"]}
	var plain := {"title": "x", "tags": ["Arcade", "Platformer"]}
	var beast := {"title": "x", "tags": ["Bestiality"]}
	_check("extreme groups hide while SHOW EXTREME is off", tf.blocks(porn))
	_check("violence is extreme too", tf.blocks(gore))
	_check("ordinary entries are untouched", not tf.blocks(plain))
	_check("the group Flashpoint ships enabled hides", tf.blocks(beast))

	tf.set_show_extreme(true)
	_check("SHOW EXTREME reveals the extreme groups", not tf.blocks(porn))
	_check(
		"the enabled group still hides with SHOW EXTREME on",
		tf.blocks(beast)
	)
	_check("ordinary entries stay visible either way", not tf.blocks(plain))

	tf.set_enabled("Pornography Extreme", false)
	_check("nothing hides once every group is off", not tf.is_filtering())
	_check("apply is a no-op when nothing is on", not tf.blocks(beast))
	var rows: Array = [porn, gore, plain, beast]
	_check("apply returns the rows untouched", tf.apply(rows).size() == 4)

	tf.set_show_extreme(false)
	_check("apply drops exactly the blocked rows", tf.apply(rows).size() == 1)
	_check(
		"the survivor is the ordinary entry",
		str((tf.apply(rows)[0] as Dictionary).get("tags", [])).find("Arcade") >= 0
	)

	## A catalog cached before tags were a list stores them joined.
	var joined := {"title": "x", "tags": "Arcade; Hentai"}
	_check("joined tag strings are read too", tf.blocks(joined))
	_check("tag matching ignores case", tf.blocks({"tags": ["hEnTaI"]}))
	_check("an untagged row is never blocked", not tf.blocks({"title": "x"}))

	var names := tf.active_names()
	_check("active groups are nameable for the chip", names.size() >= 4)

	## Round-trip the operator's choices the way the config file does.
	tf.set_enabled("Otherwise Mature Topics", true)
	var saved := tf.to_config()
	var fresh := TagFilter.new()
	fresh.from_config(saved)
	_check(
		"saved groups come back on",
		fresh.blocks({"tags": ["Suicide"]})
	)
	_check("saved SHOW EXTREME comes back", fresh.show_extreme == tf.show_extreme)
	var default_fresh := TagFilter.new()
	_check(
		"mature topics are not hidden by default",
		not default_fresh.blocks({"tags": ["Suicide"]})
	)
	tf.free()
	fresh.free()
	default_fresh.free()


## Favourites are a local bookmark, not an inscription: free, off-chain, and
## still listable when the archive cannot be reached.
func _check_favorites() -> void:
	if FileAccess.file_exists(Favorites.INDEX_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Favorites.INDEX_PATH))
	var fav := Favorites.new()
	fav.load_index()
	_check("a fresh shelf is empty", fav.size() == 0)

	var game := {
		"id": "abc-123",
		"title": "Bowman",
		"platform": "Flash",
		"launchCommand": "http://www.andkon.com/arcade/sport/bowman/bowman.swf",
		"applicationPath": "FPSoftware\\Flash\\flashplayer_32_sa.exe",
		"zipped": true,
		"screenshotUrlThatShouldNotBeKept": "x",
	}
	_check("marking returns the new state", fav.toggle(game))
	_check("the title is now a favourite", fav.has(game))
	_check("and is findable by id", fav.has_id("abc-123"))
	_check("one favourite is held", fav.size() == 1)
	_check("unmarking returns the new state", not fav.toggle(game))
	_check("the title is no longer a favourite", not fav.has(game))
	_check("the shelf is empty again", fav.size() == 0)

	## Only what listing and launching need is kept.
	var slim := Favorites.slim(game)
	_check("the launch command is kept", str(slim.get("launchCommand", "")).find("bowman.swf") >= 0)
	_check("the projector is kept", slim.has("applicationPath"))
	_check("unknown fields are dropped", not slim.has("screenshotUrlThatShouldNotBeKept"))

	## A row with no id cannot be a favourite — nothing could resolve it later.
	_check("an id-less row is refused", not fav.add({"title": "nameless"}))
	_check("refusing it changed nothing", fav.size() == 0)

	## Survives a restart.
	fav.add(game)
	fav.add({"id": "def-456", "title": "Samorost", "platform": "Flash"})
	var reopened := Favorites.new()
	reopened.load_index()
	_check("favourites survive a restart", reopened.size() == 2)
	_check("and keep their identity", reopened.has_id("abc-123") and reopened.has_id("def-456"))
	_check("rows come back as records", reopened.rows().size() == 2)

	## The live catalog row wins; the saved copy is only a fallback.
	var fresh := {"id": "abc-123", "title": "Bowman (rescanned)", "platform": "Flash"}
	var merged := reopened.rows_merged([fresh])
	var found := ""
	for entry: Variant in merged:
		if str((entry as Dictionary).get("id", "")) == "abc-123":
			found = str((entry as Dictionary).get("title", ""))
	_check("the catalog row is preferred when present", found == "Bowman (rescanned)")
	_check("titles absent from the catalog still list", merged.size() == 2)
	_check("with no catalog at all, the saved rows list", reopened.rows_merged([]).size() == 2)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(Favorites.INDEX_PATH))


## Navigator ships pointed at Flashpoint's proxy port and keeps its real
## profile somewhere no Firefox convention would look. Getting either wrong
## means every page entry dies on "the proxy server is refusing connections".
func _check_navigator_proxy() -> void:
	var nav := {
		"platform": "HTML5",
		"applicationPath": "FPSoftware\\fpnavigator-portable\\FPNavigator.exe",
		"launchCommand": "http://example.com/game.html",
	}
	var shiva := {
		"platform": "ShiVa3D",
		"applicationPath": "FPSoftware\\FlashpointSecurePlayer.exe",
		"launchCommand": "shiva3d http://example.com/game.swf",
	}
	_check("Navigator entries use the proxy port", not Packs.wants_plugin_port(nav))
	_check("ShiVa entries use the plugin port", Packs.wants_plugin_port(shiva))
	_check("the proxy port is Flashpoint's own", LocalHttp.SPR_PORT == 22500)
	_check("the plugin port is Flashpoint's own", LocalHttp.PLUGIN_PORT == 22600)

	## The X-Launcher layout: User/<AppName>/Profiles/<Profile>.
	var root := ProjectSettings.globalize_path("user://selftest_nav")
	var prof := root.path_join("User/flashpointnavigator/Profiles/Default")
	DirAccess.make_dir_recursive_absolute(prof)
	_write_probe("user://selftest_nav/User/flashpointnavigator/Profiles/Default/prefs.js")
	var ini := FileAccess.open(root.path_join("FPNavigator.ini"), FileAccess.WRITE)
	if ini != null:
		ini.store_string("[Setup]\nAppName=flashpointnavigator\nProfile=Default\n")
		ini.close()
	var found := Packs.live_profile_dirs(root)
	_check(
		"the real profile is found from FPNavigator.ini",
		found.size() > 0 and str(found[0]).replace("\\", "/").ends_with("Profiles/Default")
	)

	## prefs.js already pins Flashpoint's port, so our port has to replace it.
	var pj := prof.path_join("prefs.js")
	var f := FileAccess.open(pj, FileAccess.WRITE)
	if f != null:
		f.store_string(
			"user_pref(\"browser.cache.disk.parent_directory\", \"x\");\n"
			+ "user_pref(\"network.proxy.http_port\", 22500);\n"
			+ "user_pref(\"network.proxy.type\", 1);\n"
		)
		f.close()
	_check("prefs.js is patched", Packs._patch_prefs(pj, 24680))
	var text := FileAccess.get_file_as_string(pj)
	_check("the new port replaces the shipped one", text.find("24680") >= 0)
	_check("the shipped port is gone", text.find("22500") < 0)
	_check("unrelated preferences survive", text.find("browser.cache.disk.parent_directory") >= 0)
	_check("the proxy stays enabled", text.find("\"network.proxy.type\", 1") >= 0)


## Archived pages often have no extension or a server-page one. Handing those
## to a browser as octet-stream makes it download the game instead of playing it.
func _check_mime_sniffing() -> void:
	var page := "<!DOCTYPE html>\n<html><head><title>x</title></head></html>".to_utf8_buffer()
	var bare := "<html><body>hi</body></html>".to_utf8_buffer()
	_check(
		"an extensionless page is served as HTML",
		LocalHttp.mime_for_body("/web3-arcade.herokuapp.com/2048", page) == "text/html"
	)
	_check(
		"a .jsp page is served as HTML",
		LocalHttp.mime_for_body("/arcane2/arcane/index.jsp", page) == "text/html"
	)
	_check(
		"a .php page is served as HTML",
		LocalHttp.mime_for_body("/x/game.php", bare) == "text/html"
	)
	_check(
		"the old behaviour was octet-stream",
		LocalHttp.mime_for("/arcane2/arcane/index.jsp") == "application/octet-stream"
	)

	## A name we do know always wins: never let a sniff relabel a known type.
	_check(
		"a known extension is not overridden",
		LocalHttp.mime_for_body("/x/style.css", page) == "text/css"
	)
	_check(
		"swf stays swf",
		LocalHttp.mime_for_body("/x/game.swf", "FWS\u0006junk".to_utf8_buffer())
		== "application/x-shockwave-flash"
	)

	## Binary without a useful name still gets identified where we can.
	var png := PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
	var gif := "GIF89a".to_utf8_buffer()
	var swf := PackedByteArray([0x46, 0x57, 0x53, 0x06, 0x00, 0x00])
	_check("png magic is recognised", LocalHttp.mime_for_body("/x/blob", png) == "image/png")
	_check("gif magic is recognised", LocalHttp.mime_for_body("/x/blob", gif) == "image/gif")
	_check(
		"swf magic is recognised",
		LocalHttp.mime_for_body("/x/blob", swf) == "application/x-shockwave-flash"
	)
	_check(
		"unknown binary stays octet-stream",
		LocalHttp.mime_for_body("/x/blob", PackedByteArray([1, 2, 3, 4, 5, 6]))
		== "application/octet-stream"
	)
	_check("an empty file stays octet-stream", LocalHttp.mime_for_body("/x/blob", PackedByteArray()) == "application/octet-stream")

	## Real captures rarely start at the first tag.
	_check(
		"leading whitespace does not hide the page",
		LocalHttp.mime_for_body("/x/p", "\n\n   <html></html>".to_utf8_buffer()) == "text/html"
	)
	_check(
		"a leading comment does not hide the page",
		LocalHttp.mime_for_body("/x/p", "<!-- saved from url -->\n<html></html>".to_utf8_buffer())
		== "text/html"
	)
	_check(
		"an xml prolog does not hide xhtml",
		LocalHttp.mime_for_body("/x/p", "<?xml version=\"1.0\"?><html></html>".to_utf8_buffer())
		== "text/html"
	)
	_check(
		"plain text is not mistaken for a page",
		LocalHttp.mime_for_body("/x/p", "just some notes".to_utf8_buffer())
		== "application/octet-stream"
	)

	## Directory index has to find the server-page names too.
	var idir := "user://selftest_index"
	_write_probe(idir.path_join("only-jsp/index.jsp"))
	_write_probe(idir.path_join("both/index.html"))
	_write_probe(idir.path_join("both/index.php"))
	_check(
		"index.jsp is a directory index",
		LocalHttp.index_file(ProjectSettings.globalize_path(idir.path_join("only-jsp")))
		.replace("\\", "/")
		.ends_with("/index.jsp")
	)
	_check(
		"index.html still wins over index.php",
		LocalHttp.index_file(ProjectSettings.globalize_path(idir.path_join("both")))
		.replace("\\", "/")
		.ends_with("/index.html")
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
	var dcr := FileAccess.open(root.path_join("probe.dcr"), FileAccess.WRITE)
	_check("httpd director probe file", dcr != null)
	if dcr:
		dcr.store_buffer(PackedByteArray([0x58, 0x46, 0x49, 0x52, 0x08, 0x00, 0x00, 0x00]))
		dcr.close()
	var sw := StreamPeerTCP.new()
	sw.connect_to_host("127.0.0.1", hp)
	_check("httpd shockwave client connects", _tcp_wait(sw, StreamPeerTCP.STATUS_CONNECTED, 1000))
	var sw_body := ""
	if sw.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		sw.put_data("GET /probe.dcr HTTP/1.0\r\nHost: 127.0.0.1\r\n\r\n".to_utf8_buffer())
		var sw_resp := PackedByteArray()
		var sw_start := Time.get_ticks_msec()
		while Time.get_ticks_msec() - sw_start < 1000:
			httpd._process(0.0)
			sw.poll()
			if sw.get_status() != StreamPeerTCP.STATUS_CONNECTED:
				break
			var sn := sw.get_available_bytes()
			if sn > 0:
				sw_resp.append_array(sw.get_data(sn)[1])
				if sw_resp.get_string_from_utf8().find("\r\n\r\n") >= 0 and sw_resp.size() >= 8:
					break
			OS.delay_msec(1)
		sw_body = sw_resp.get_string_from_utf8()
		sw.disconnect_from_host()
	_check("httpd echoes HTTP/1.0 for Shockwave", sw_body.begins_with("HTTP/1.0 200"))
	_check("httpd sends Last-Modified for Director files", sw_body.find("Last-Modified:") >= 0)
	_check(
		"httpd omits CORP header Shockwave treats as a bad movie",
		sw_body.find("Cross-Origin-Resource-Policy") < 0
	)
	_check("httpd omits Connection close for Shockwave", sw_body.find("Connection: close") < 0)
	httpd.stop()
	httpd.free()


func _check(name: String, ok: bool) -> void:
	if ok:
		_passed += 1
		print("  ok  ", name)
	else:
		_failed += 1
		print("  FAIL  ", name)
