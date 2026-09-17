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
	main._sel_tag = "Arcade"
	main._search_facet("dev", "Tom Fulp")
	_check(
		"stage developer click clears tags",
		main._sel_dev == "Tom Fulp" and main._sel_tag.is_empty()
	)
	main.free()

	var pick := FacetPick.new()
	_check("facet pick is a container", pick is HBoxContainer)
	_check("facet pick has a row height", pick.custom_minimum_size.y >= 20)
	pick.free()

	print("selftest: %d passed, %d failed" % [_passed, _failed])


func _check(name: String, ok: bool) -> void:
	if ok:
		_passed += 1
		print("  ok  ", name)
	else:
		_failed += 1
		print("  FAIL  ", name)
