extends Control

const CONFIG_PATH := "user://flash.cfg"
const APP_NAME := "Flash Cartridge"

var iq: IQClient
var ruffle: Ruffle
var flashpoint: Flashpoint
var cabinet: Cabinet
var shelf := Shelf.new()

var chain: String = "mon"
var kindled: bool = false
var _busy: bool = false
var _archive_hits: Array = []
var _inscribed: Array = []

var _host_label: Label
var _kindle_label: Label
var _ruffle_label: Label
var _search: LineEdit
var _archive: ItemList
var _inscribed_list: ItemList
var _guidance: Label
var _console: RichTextLabel
var _inscribe_btn: Button
var _play_btn: Button
var _kindle_btn: Button
var _chain: OptionButton


func _ready() -> void:
	theme = TempleTheme.build()
	_load_config()
	shelf.load_index()
	_build_ui()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://staging"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://cartridges"))

	iq = IQClient.new()
	add_child(iq)
	ruffle = Ruffle.new()
	add_child(ruffle)
	flashpoint = Flashpoint.new()
	add_child(flashpoint)
	cabinet = Cabinet.new(iq, chain)

	iq.host_missing.connect(_on_host_missing)
	await _connect_host()
	await _refresh_kindled()
	await _refresh_inscribed()
	await _ensure_ruffle()


func _build_ui() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	root.add_child(top)
	var title := TempleTheme.title("FLASH CARTRIDGE")
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	top.add_child(title)

	_chain = OptionButton.new()
	_chain.add_item("MON", 0)
	_chain.add_item("SOL", 1)
	_chain.add_item("RH", 2)
	_chain.select(_chain_index(chain))
	_chain.item_selected.connect(_on_chain_selected)
	top.add_child(_chain)

	_kindle_btn = TempleTheme.button("KINDLE ROOT", _on_kindle)
	top.add_child(_kindle_btn)
	top.add_child(TempleTheme.button("REFRESH", _on_refresh))

	_host_label = TempleTheme.line("Looking for GodOnChain…", TempleTheme.AMBER, TempleTheme.SIZE_SMALL)
	_host_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	root.add_child(_host_label)
	_kindle_label = TempleTheme.line("", TempleTheme.GREY, TempleTheme.SIZE_SMALL)
	_kindle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	root.add_child(_kindle_label)
	_ruffle_label = TempleTheme.line("Ruffle: checking…", TempleTheme.GREY, TempleTheme.SIZE_SMALL)
	_ruffle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	root.add_child(_ruffle_label)

	var search_row := HBoxContainer.new()
	search_row.add_theme_constant_override("separation", 8)
	root.add_child(search_row)
	_search = LineEdit.new()
	_search.placeholder_text = "Search Flashpoint (Flash GameZIPs)"
	_search.size_flags_horizontal = SIZE_EXPAND_FILL
	_search.text_submitted.connect(func(_t: String) -> void: _on_search())
	search_row.add_child(_search)
	search_row.add_child(TempleTheme.primary_button("SEARCH", _on_search))

	var lists := HBoxContainer.new()
	lists.size_flags_vertical = SIZE_EXPAND_FILL
	lists.add_theme_constant_override("separation", 12)
	root.add_child(lists)

	_archive = _make_list("ARCHIVE — not yet on-chain")
	_inscribed_list = _make_list("INSCRIBED — play from the chain")
	lists.add_child(_wrap_list("ARCHIVE", _archive))
	lists.add_child(_wrap_list("INSCRIBED", _inscribed_list))

	_archive.item_selected.connect(func(_i: int) -> void: _inscribed_list.deselect_all())
	_inscribed_list.item_selected.connect(func(_i: int) -> void: _archive.deselect_all())
	_archive.item_activated.connect(func(_i: int) -> void: _on_inscribe())
	_inscribed_list.item_activated.connect(func(_i: int) -> void: _on_play())

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	root.add_child(actions)
	_inscribe_btn = TempleTheme.primary_button("INSCRIBE", _on_inscribe)
	_play_btn = TempleTheme.button("PLAY", _on_play)
	actions.add_child(_inscribe_btn)
	actions.add_child(_play_btn)

	_guidance = TempleTheme.line(
		"There is no unpublish. Inscribing pays createTable to the root, then writes the GameZIP.",
		TempleTheme.AMBER,
		TempleTheme.SIZE_SMALL
	)
	_guidance.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	root.add_child(_guidance)

	_console = RichTextLabel.new()
	_console.fit_content = false
	_console.scroll_following = true
	_console.custom_minimum_size = Vector2(0, 140)
	_console.size_flags_vertical = SIZE_EXPAND_FILL
	_console.bbcode_enabled = false
	root.add_child(_console)
	_log("Flash Cartridge. Search the archive, inscribe a title, play what is already on-chain.")


func _make_list(_caption: String) -> ItemList:
	var list := ItemList.new()
	list.size_flags_horizontal = SIZE_EXPAND_FILL
	list.size_flags_vertical = SIZE_EXPAND_FILL
	list.select_mode = ItemList.SELECT_SINGLE
	list.add_theme_color_override("font_color", TempleTheme.GREY)
	list.add_theme_color_override("font_hovered_color", TempleTheme.YELLOW)
	list.add_theme_color_override("font_selected_color", TempleTheme.WHITE)
	return list


func _wrap_list(caption: String, list: ItemList) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = SIZE_EXPAND_FILL
	box.size_flags_vertical = SIZE_EXPAND_FILL
	var label := TempleTheme.line(caption, TempleTheme.YELLOW, TempleTheme.SIZE_SMALL)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(label)
	box.add_child(list)
	return box


func _connect_host() -> void:
	if await iq.discover(APP_NAME):
		_host_label.text = "GodOnChain host: %s" % iq.base_url
		_host_label.add_theme_color_override("font_color", TempleTheme.CYAN)
	else:
		_on_host_missing(iq.last_error)


func _on_host_missing(reason: String) -> void:
	_host_label.text = reason
	_host_label.add_theme_color_override("font_color", TempleTheme.BRIGHT_RED)
	kindled = false
	_update_kindle_label()


func _ensure_ruffle() -> void:
	_ruffle_label.text = "Ruffle: fetching latest stable…"
	var ok := await ruffle.ensure()
	if ok:
		_ruffle_label.text = "Ruffle %s" % ruffle.tag
		_ruffle_label.add_theme_color_override("font_color", TempleTheme.CYAN)
	else:
		_ruffle_label.text = "Ruffle unavailable: %s" % ruffle.last_error
		_ruffle_label.add_theme_color_override("font_color", TempleTheme.BRIGHT_RED)


func _refresh_kindled() -> void:
	if not iq.is_available():
		kindled = false
		_update_kindle_label()
		return
	cabinet = Cabinet.new(iq, chain)
	kindled = await cabinet.is_kindled()
	_update_kindle_label()


func _update_kindle_label() -> void:
	if not iq.is_available():
		_kindle_label.text = "On-chain access is optional. Inscribe needs a host."
		return
	if kindled:
		_kindle_label.text = "Root %s is kindled on %s. createTable fees go to the operators." % [
			Cartridge.APP_ROOT, chain.to_upper()
		]
		_kindle_label.add_theme_color_override("font_color", TempleTheme.CYAN)
	else:
		_kindle_label.text = (
			"Root is not kindled on %s. Inscribe is refused until the operators create it."
			% chain.to_upper()
		)
		_kindle_label.add_theme_color_override("font_color", TempleTheme.AMBER)


func _on_chain_selected(index: int) -> void:
	var names := ["mon", "sol", "rh"]
	chain = names[clampi(index, 0, 2)]
	_save_config()
	_log("Chain set to %s." % chain.to_upper())
	await _refresh_kindled()
	await _refresh_inscribed()


func _chain_index(code: String) -> int:
	match code:
		"sol":
			return 1
		"rh":
			return 2
		_:
			return 0


func _on_refresh() -> void:
	if _busy:
		return
	await _connect_host()
	await _refresh_kindled()
	await _refresh_inscribed()
	await _ensure_ruffle()


func _on_search() -> void:
	if _busy:
		return
	_set_busy(true)
	_log("Searching Flashpoint for “%s”…" % _search.text)
	var hits: Array = await flashpoint.search(_search.text)
	_set_busy(false)
	if hits.is_empty():
		_log(flashpoint.last_error if not flashpoint.last_error.is_empty() else "Nothing matched.")
		return
	_archive_hits = hits
	_archive.clear()
	for entry: Variant in hits:
		if not entry is Dictionary:
			continue
		var rec: Dictionary = entry
		if not flashpoint.is_gamezip(rec):
			continue
		var title := str(rec.get("title", "?"))
		var uuid := str(rec.get("id", ""))
		var table := Cartridge.table_name(uuid)
		var badge := "AVAILABLE"
		if shelf.entries.has(table):
			badge = "CACHED"
		var line := "[%s]  %s  —  %s" % [badge, title, str(rec.get("developer", ""))]
		var i := _archive.add_item(line)
		_archive.set_item_metadata(i, rec)
	_log("%d Flash GameZIPs." % _archive.item_count)
	await _badge_archive()


func _badge_archive() -> void:
	if not iq.is_available() or not kindled:
		return
	for i in _archive.item_count:
		var rec: Variant = _archive.get_item_metadata(i)
		if rec is Dictionary:
			var uuid := str((rec as Dictionary).get("id", ""))
			if await cabinet.exists_for(uuid):
				var title := str((rec as Dictionary).get("title", "?"))
				_archive.set_item_text(i, "[INSCRIBED]  %s  —  %s" % [title, str((rec as Dictionary).get("developer", ""))])


func _refresh_inscribed() -> void:
	_inscribed_list.clear()
	_inscribed = []
	if not iq.is_available():
		return
	var names: PackedStringArray = await cabinet.table_names()
	for table in names:
		var game: Dictionary = await cabinet.read_game(table)
		var meta: Dictionary = game.get("meta", {})
		var title := str(meta.get("title", table))
		var i := _inscribed_list.add_item(title)
		_inscribed_list.set_item_metadata(i, {"table": table, "meta": meta, "blob": game.get("blob", {})})
		_inscribed.append(table)
	_log("%d inscribed tables on %s." % [_inscribed_list.item_count, chain.to_upper()])


func _on_kindle() -> void:
	if _busy:
		return
	if not iq.is_available():
		_log("No host. Launch this from GodOnChain.")
		return
	_set_busy(true)
	_log("Kindling %s on %s. Approve it in GodOnChain." % [Cartridge.APP_ROOT, chain.to_upper()])
	var result = await cabinet.kindle(_on_progress)
	_set_busy(false)
	if result == null:
		_log("Kindle failed: %s" % cabinet.last_error)
		return
	_log("Root kindled.")
	await _refresh_kindled()


func _on_inscribe() -> void:
	if _busy:
		return
	if not iq.is_available():
		_log("No host. Launch this from GodOnChain.")
		return
	if not kindled:
		_log("Root is not kindled on this chain. Inscribe is refused.")
		return
	var selected := _archive.get_selected_items()
	if selected.is_empty():
		_log("Pick a title in ARCHIVE.")
		return
	var rec: Variant = _archive.get_item_metadata(selected[0])
	if not rec is Dictionary:
		return
	var entry: Dictionary = rec
	if not flashpoint.is_gamezip(entry):
		_log("That title is not a GameZIP. v1 will not inscribe it.")
		return
	var uuid := str(entry.get("id", ""))
	if await cabinet.exists_for(uuid):
		_log("Already inscribed. Play it from INSCRIBED.")
		await _refresh_inscribed()
		return

	_set_busy(true)
	var zip_path := Cartridge.staging_path(uuid)
	_log("Downloading GameZIP for %s…" % str(entry.get("title", uuid)))
	if not await flashpoint.download_zip(uuid, zip_path):
		_set_busy(false)
		_log("Download failed: %s" % flashpoint.last_error)
		return

	var raw_bytes := FileAccess.get_file_as_bytes(zip_path)
	_guidance.text = (
		"There is no unpublish. %s"
		% Costs.quote_inscribe(chain, raw_bytes.size())
	)
	_log(Costs.quote_inscribe(chain, raw_bytes.size()))
	_log("Inscribing. Approve each spend in GodOnChain (createTable, then two rows).")

	var result = await cabinet.inscribe(entry, zip_path, _on_progress)
	_set_busy(false)
	if result == null:
		_log("Inscribe failed: %s" % cabinet.last_error)
		return
	if result is Dictionary and result.get("already", false):
		_log("Already on-chain as %s." % str(result.get("table", "")))
	else:
		_log("Inscribed as %s." % str(result.get("table", "")))
		var table := str(result.get("table", ""))
		shelf.remember(table, {"uuid": uuid, "title": str(entry.get("title", "")), "sha256": str(result.get("sha256", ""))})
	await _refresh_inscribed()
	_badge_archive()


func _on_play() -> void:
	if _busy:
		return
	var table := ""
	var meta := {}
	var selected_i := _inscribed_list.get_selected_items()
	if not selected_i.is_empty():
		var rec: Variant = _inscribed_list.get_item_metadata(selected_i[0])
		if rec is Dictionary:
			table = str((rec as Dictionary).get("table", ""))
			meta = (rec as Dictionary).get("meta", {})
	else:
		var selected_a := _archive.get_selected_items()
		if not selected_a.is_empty():
			var entry: Variant = _archive.get_item_metadata(selected_a[0])
			if entry is Dictionary:
				table = Cartridge.table_name(str((entry as Dictionary).get("id", "")))
				meta = entry
	if table.is_empty():
		_log("Pick an inscribed title to play.")
		return

	_set_busy(true)
	if ruffle.exe_path.is_empty():
		await ruffle.ensure()
	var dest := Cartridge.cache_dir(table)
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dest)):
		if not iq.is_available():
			_set_busy(false)
			_log("No cached copy, and no host to fetch one.")
			return
		_log("Reading %s from chain…" % table)
		var game: Dictionary = await cabinet.read_game(table, _on_progress)
		var blob: Dictionary = game.get("blob", {})
		var b64 := str(blob.get("data", ""))
		if b64.is_empty():
			_set_busy(false)
			_log("No blob on that table.")
			return
		var zip_path := Cartridge.staging_path(table)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://staging"))
		var zip_file := FileAccess.open(zip_path, FileAccess.WRITE)
		if zip_file == null:
			_set_busy(false)
			_log("Could not write staging zip.")
			return
		zip_file.store_buffer(Marshalls.base64_to_raw(b64))
		zip_file.close()
		if not Unzip.extract(zip_path, dest):
			_set_busy(false)
			_log("Could not extract the GameZIP.")
			return
		meta = game.get("meta", meta)

	var launch := str(meta.get("launch", meta.get("launchCommand", "")))
	var swf := Unzip.swf_for_launch(dest, launch)
	if swf.is_empty():
		_set_busy(false)
		_log("No SWF in that cartridge.")
		return
	var pid := ruffle.play(swf, dest)
	_set_busy(false)
	if pid == -1:
		_log("Play failed: %s" % ruffle.last_error)
	else:
		_log("Ruffle pid %d — %s" % [pid, swf.get_file()])


func _on_progress(value: float) -> void:
	if int(value) % 10 == 0:
		_log("… %d%%" % int(value))


func _set_busy(on: bool) -> void:
	_busy = on
	_inscribe_btn.disabled = on
	_play_btn.disabled = on
	_kindle_btn.disabled = on
	_search.editable = not on


func _log(line: String) -> void:
	_console.append_text(line + "\n")


func _load_config() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		return
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		var c := str((parsed as Dictionary).get("chain", "mon"))
		if c in ["mon", "sol", "rh"]:
			chain = c


func _save_config() -> void:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"chain": chain}))
	file.close()
