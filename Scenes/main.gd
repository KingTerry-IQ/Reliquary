extends Control

const CONFIG_PATH := "user://flash.cfg"
const APP_NAME := "Flash Cartridge"
const PAGE_SIZE := 400
const CABINET_PAGE := 80
const GENRES: PackedStringArray = [
	"Action",
	"Adventure",
	"Arcade",
	"Puzzle",
	"Platformer",
	"Shooter",
	"Racing",
	"Fighting",
	"Strategy",
	"Sports",
	"Simulation",
	"Educational",
	"Rhythm",
	"RPG",
	"Horror",
	"Point and Click",
]

var iq: IQClient
var ruffle: Ruffle
var spr: Spr
var flashpoint: Flashpoint
var cabinet: Cabinet
var shelf := Shelf.new()

var chain: String = "mon"
var kindled: bool = false
var _busy: bool = false
var _last_progress: int = -1
var _shot_ticket: int = 0
var _logo_ticket: int = 0
var _cabinet_logo_ticket: int = 0
var _archive_hits: Array = []
var _inscribed: Array = []
var _inscribed_by_uuid: Dictionary = {}

var _selected_kind: String = ""
var _selected_entry: Dictionary = {}
var _selected_table: String = ""

var _host_label: Label
var _ruffle_label: Label
var _root_label: Label
var _search: LineEdit
var _library: OptionButton
var httpd: LocalHttp
var fp_host := FlashpointHost.new()
var _spr_label: Label
var _letter_bar: HFlowContainer
var _browse_letter: String = ""
var _letter_buttons: Dictionary = {}
var _tag_box: HBoxContainer
var _size_ticket: int = 0
var _preview_bytes: int = -1
var _archive: ItemList
var _view_grid: bool = true
var _view_btn: Button
var _playlist: OptionButton
var _filter_dev: FacetPick
var _filter_pub: FacetPick
var _filter_series: FacetPick
var _filter_tag: FacetPick
var _playlist_id: String = "all"
var _sel_dev: String = ""
var _sel_pub: String = ""
var _sel_series: String = ""
var _sel_tag: String = ""
var _facet_guard: bool = false
var _facet_devs: Dictionary = {}
var _facet_pubs: Dictionary = {}
var _facet_series: Dictionary = {}
var _placeholder_tex: Texture2D
var _logo_next: int = 0
var _search_ticket: int = 0
var _warm_lib: String = ""
var _warm_done: bool = false
var _warm_rows: Array = []
var _facet_ticket: int = 0
var _archive_page: int = 0
var _page_row: HBoxContainer
var _page_label: Label
var _prev_page_btn: Button
var _next_page_btn: Button
var _searching: bool = false
var _search_spin: float = 0.0
var _load_veil: ColorRect
var _load_label: Label
var _cabinet_rows: Array = []
var _cabinet_page: int = 0
var _cabinet_letter: String = ""
var _cabinet_plat: String = ""
var _cabinet_filter: LineEdit
var _cabinet_platform: OptionButton
var _cabinet_letters: HFlowContainer
var _cabinet_letter_buttons: Dictionary = {}
var _cabinet_page_row: HBoxContainer
var _cabinet_page_label: Label
var _cabinet_prev: Button
var _cabinet_next: Button
var _inscribed_list: ItemList
var _archive_empty: Label
var _inscribed_empty: Label
var _archive_header: Label
var _inscribed_header: Label
var _shot: TextureRect
var _shot_empty: Label
var _detail_title: Label
var _detail_chip: Label
var _detail_meta: Label
var _detail_body: RichTextLabel
var _detail_cost: Label
var _guidance: Label
var _console: RichTextLabel
var _job: Label
var _progress: ProgressBar
var _inscribe_btn: Button
var _play_btn: Button
var _search_btn: Button
var _chain: OptionButton


func _ready() -> void:
	theme = TempleTheme.build()
	_load_config()
	shelf.load_index()
	_build_ui()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://staging"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://cartridges"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://thumbs"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://trials"))

	iq = IQClient.new()
	add_child(iq)
	ruffle = Ruffle.new()
	add_child(ruffle)
	spr = Spr.new()
	add_child(spr)
	flashpoint = Flashpoint.new()
	add_child(flashpoint)
	httpd = LocalHttp.new()
	add_child(httpd)
	cabinet = Cabinet.new(iq, chain)

	iq.host_missing.connect(_on_host_missing)
	_warmup_catalog()
	_ensure_ruffle()
	_load_tag_dropdown()
	await _connect_host()
	await _refresh_kindled()
	await _refresh_inscribed()
	_refresh_spr_chip()
	_search.grab_focus()
	if _archive_hits.is_empty():
		_on_search()


func _build_ui() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = SIZE_EXPAND_FILL
	root.size_flags_vertical = SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	root.add_child(_build_topbar())

	var columns := HBoxContainer.new()
	columns.size_flags_horizontal = SIZE_EXPAND_FILL
	columns.size_flags_vertical = SIZE_EXPAND_FILL
	columns.clip_contents = true
	columns.add_theme_constant_override("separation", 12)
	root.add_child(columns)

	columns.add_child(_build_archive_column())
	columns.add_child(_build_stage())
	columns.add_child(_build_cabinet_column())

	root.add_child(_build_footer())
	_clear_detail()
	_log("Search the archive. Inscribe a title. Play what the chain already holds.")


func _build_topbar() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 16)

	var brand := VBoxContainer.new()
	brand.size_flags_horizontal = SIZE_EXPAND_FILL
	brand.add_theme_constant_override("separation", 0)
	var title := TempleTheme.title("FLASH CARTRIDGE")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	brand.add_child(title)
	var tag := TempleTheme.line("PRESS  ·  CABINET  ·  PLAYER", TempleTheme.MUTED, TempleTheme.SIZE_SMALL)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	brand.add_child(tag)
	bar.add_child(brand)

	_host_label = _status_chip("HOST …", TempleTheme.AMBER)
	_ruffle_label = _status_chip("RUFFLE …", TempleTheme.AMBER)
	_root_label = _status_chip("ROOT …", TempleTheme.AMBER)
	bar.add_child(_host_label)
	bar.add_child(_ruffle_label)
	bar.add_child(_root_label)

	_chain = OptionButton.new()
	_chain.add_item("MON", 0)
	_chain.add_item("SOL", 1)
	_chain.add_item("RH", 2)
	_chain.select(_chain_index(chain))
	_chain.item_selected.connect(_on_chain_selected)
	_chain.custom_minimum_size = Vector2(88, 0)
	bar.add_child(_chain)
	_spr_label = _status_chip("SPR  …", TempleTheme.AMBER)
	bar.add_child(_spr_label)
	bar.add_child(TempleTheme.button("REFRESH", _on_refresh))
	return bar


func _status_chip(text: String, colour: Color) -> Label:
	var label := TempleTheme.cell(text, colour, TempleTheme.SIZE_SMALL)
	label.size_flags_horizontal = Control.SIZE_SHRINK_END
	label.custom_minimum_size = Vector2(140, 0)
	return label


func _build_archive_column() -> Control:
	var panel := TempleTheme.panel()
	panel.size_flags_stretch_ratio = 1.15
	var inner := _padded()
	panel.add_child(inner)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = SIZE_EXPAND_FILL
	box.size_flags_vertical = SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	inner.add_child(box)

	_archive_header = TempleTheme.header("ARCHIVE")
	box.add_child(_archive_header)

	var search_row := HBoxContainer.new()
	search_row.add_theme_constant_override("separation", 8)
	box.add_child(search_row)
	_search = LineEdit.new()
	_search.placeholder_text = "Bowman   or   title:Alien  tag:Arcade  dev:\"Tom Fulp\""
	_search.size_flags_horizontal = SIZE_EXPAND_FILL
	_search.text_submitted.connect(func(_t: String) -> void: _on_search())
	search_row.add_child(_search)
	_library = OptionButton.new()
	_library.add_item("GAMES", 0)
	_library.add_item("ANIMS", 1)
	_library.add_item("BOTH", 2)
	_library.select(2)
	_library.custom_minimum_size = Vector2(88, 0)
	_library.item_selected.connect(func(_i: int) -> void: _on_search())
	search_row.add_child(_library)
	_search_btn = TempleTheme.primary_button("SEARCH", _on_search)
	search_row.add_child(_search_btn)
	_view_btn = TempleTheme.button("GRID", _toggle_view)
	search_row.add_child(_view_btn)

	var hint := TempleTheme.line(
		"Playlists · type-to-search filters · A–Z · or title:  dev:  pub:  tag:",
		TempleTheme.MUTED,
		TempleTheme.SIZE_SMALL
	)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(hint)

	var filters := HFlowContainer.new()
	filters.add_theme_constant_override("h_separation", 6)
	filters.add_theme_constant_override("v_separation", 4)
	box.add_child(filters)
	_playlist = _facet_option(180)
	for spec: Variant in Flashpoint.PLAYLISTS:
		var rec: Dictionary = spec
		_playlist.add_item(str(rec.get("title", rec.get("id", "?"))))
		_playlist.set_item_metadata(_playlist.item_count - 1, str(rec.get("id", "")))
	_playlist.select(0)
	_playlist.item_selected.connect(_on_playlist_selected)
	filters.add_child(_playlist)
	_filter_dev = _make_facet("Developer", "dev")
	_filter_pub = _make_facet("Publisher", "pub")
	_filter_series = _make_facet("Series", "series")
	_filter_tag = _make_facet("Tags", "tag")
	filters.add_child(_filter_dev)
	filters.add_child(_filter_pub)
	filters.add_child(_filter_series)
	filters.add_child(_filter_tag)

	_letter_bar = HFlowContainer.new()
	_letter_bar.add_theme_constant_override("h_separation", 2)
	_letter_bar.add_theme_constant_override("v_separation", 2)
	box.add_child(_letter_bar)
	_fill_letter_bar()

	_page_row = HBoxContainer.new()
	_page_row.add_theme_constant_override("separation", 8)
	_page_row.visible = false
	box.add_child(_page_row)
	_prev_page_btn = TempleTheme.button("<  PREV", _on_prev_page)
	_page_row.add_child(_prev_page_btn)
	_page_label = TempleTheme.line("", TempleTheme.YELLOW, TempleTheme.SIZE_SMALL)
	_page_label.size_flags_horizontal = SIZE_EXPAND_FILL
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_row.add_child(_page_label)
	_next_page_btn = TempleTheme.button("NEXT  >", _on_next_page)
	_page_row.add_child(_next_page_btn)

	var stack := Control.new()
	stack.size_flags_horizontal = SIZE_EXPAND_FILL
	stack.size_flags_vertical = SIZE_EXPAND_FILL
	stack.clip_contents = true
	box.add_child(stack)

	_archive = _make_list()
	_archive.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_archive.item_selected.connect(_on_archive_selected)
	_archive.item_activated.connect(func(_i: int) -> void: _on_play())
	stack.add_child(_archive)
	_apply_archive_view()

	_archive_empty = _empty_label("All Games, a playlist, A–Z, or a search.")
	stack.add_child(_archive_empty)

	_load_veil = ColorRect.new()
	_load_veil.color = Color(0, 0, 0, 0.78)
	_load_veil.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_load_veil.visible = false
	_load_veil.mouse_filter = Control.MOUSE_FILTER_STOP
	stack.add_child(_load_veil)
	_load_label = TempleTheme.line("LOADING…", TempleTheme.YELLOW, TempleTheme.SIZE_DISPLAY)
	_load_label.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_load_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_load_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(_load_label)
	_load_label.visible = false
	return panel


func _build_cabinet_column() -> Control:
	var panel := TempleTheme.panel()
	panel.size_flags_stretch_ratio = 0.95
	var inner := _padded()
	panel.add_child(inner)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	inner.add_child(box)

	_inscribed_header = TempleTheme.header("ON CHAIN")
	box.add_child(_inscribed_header)

	var cab_row := HBoxContainer.new()
	cab_row.add_theme_constant_override("separation", 6)
	box.add_child(cab_row)
	_cabinet_filter = LineEdit.new()
	_cabinet_filter.placeholder_text = "filter cabinet…"
	_cabinet_filter.size_flags_horizontal = SIZE_EXPAND_FILL
	_cabinet_filter.text_changed.connect(func(_t: String) -> void:
		_cabinet_page = 0
		_paint_cabinet()
	)
	cab_row.add_child(_cabinet_filter)
	_cabinet_platform = _facet_option(110)
	_cabinet_platform.item_selected.connect(func(_i: int) -> void: _on_cabinet_platform())
	cab_row.add_child(_cabinet_platform)
	_fill_option(_cabinet_platform, "Platform", PackedStringArray(), "")

	_cabinet_letters = HFlowContainer.new()
	_cabinet_letters.add_theme_constant_override("h_separation", 2)
	_cabinet_letters.add_theme_constant_override("v_separation", 2)
	box.add_child(_cabinet_letters)
	_fill_cabinet_letters()

	_cabinet_page_row = HBoxContainer.new()
	_cabinet_page_row.add_theme_constant_override("separation", 8)
	_cabinet_page_row.visible = false
	box.add_child(_cabinet_page_row)
	_cabinet_prev = TempleTheme.button("<", _on_cabinet_prev)
	_cabinet_page_row.add_child(_cabinet_prev)
	_cabinet_page_label = TempleTheme.line("", TempleTheme.CYAN, TempleTheme.SIZE_SMALL)
	_cabinet_page_label.size_flags_horizontal = SIZE_EXPAND_FILL
	_cabinet_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cabinet_page_row.add_child(_cabinet_page_label)
	_cabinet_next = TempleTheme.button(">", _on_cabinet_next)
	_cabinet_page_row.add_child(_cabinet_next)

	var stack := Control.new()
	stack.size_flags_horizontal = SIZE_EXPAND_FILL
	stack.size_flags_vertical = SIZE_EXPAND_FILL
	stack.clip_contents = true
	box.add_child(stack)

	_inscribed_list = _make_list()
	_inscribed_list.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_inscribed_list.item_selected.connect(_on_inscribed_selected)
	_inscribed_list.item_activated.connect(func(_i: int) -> void: _on_play())
	stack.add_child(_inscribed_list)

	_inscribed_empty = _empty_label("Nothing inscribed\non this chain yet.")
	stack.add_child(_inscribed_empty)
	return panel


func _build_stage() -> Control:
	var panel := TempleTheme.panel()
	panel.size_flags_stretch_ratio = 1.45
	var inner := _padded()
	panel.add_child(inner)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	inner.add_child(box)

	box.add_child(TempleTheme.header("STAGE"))

	var shot_wrap := Control.new()
	shot_wrap.custom_minimum_size = Vector2(0, 250)
	shot_wrap.size_flags_horizontal = SIZE_EXPAND_FILL
	box.add_child(shot_wrap)

	var frame := ColorRect.new()
	frame.color = Color("111111")
	frame.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	shot_wrap.add_child(frame)

	_shot = TextureRect.new()
	_shot.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_shot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	shot_wrap.add_child(_shot)

	_shot_empty = TempleTheme.line("NO CARTRIDGE SELECTED", TempleTheme.DARK_GREY, TempleTheme.SIZE_SMALL)
	_shot_empty.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_shot_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	shot_wrap.add_child(_shot_empty)

	_detail_chip = TempleTheme.cell("", TempleTheme.CYAN, TempleTheme.SIZE_SMALL)
	box.add_child(_detail_chip)

	_detail_title = TempleTheme.line("", TempleTheme.YELLOW, TempleTheme.SIZE_DISPLAY)
	_detail_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(_detail_title)

	_detail_meta = TempleTheme.line("", TempleTheme.GREY, TempleTheme.SIZE_SMALL)
	_detail_meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(_detail_meta)

	_detail_body = RichTextLabel.new()
	_detail_body.fit_content = false
	_detail_body.scroll_following = false
	_detail_body.bbcode_enabled = false
	_detail_body.size_flags_vertical = SIZE_EXPAND_FILL
	_detail_body.custom_minimum_size = Vector2(0, 80)
	box.add_child(_detail_body)

	_tag_box = HBoxContainer.new()
	_tag_box.add_theme_constant_override("separation", 6)
	box.add_child(_tag_box)

	_detail_cost = TempleTheme.line("", TempleTheme.AMBER, TempleTheme.SIZE_SMALL)
	_detail_cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(_detail_cost)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	box.add_child(actions)
	_inscribe_btn = TempleTheme.primary_button("INSCRIBE", _on_inscribe)
	_play_btn = TempleTheme.button("PLAY", _on_play)
	_inscribe_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	_play_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	actions.add_child(_inscribe_btn)
	actions.add_child(_play_btn)
	return panel


func _build_footer() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	var job_row := HBoxContainer.new()
	job_row.add_theme_constant_override("separation", 10)
	box.add_child(job_row)
	_progress = ProgressBar.new()
	_progress.min_value = 0
	_progress.max_value = 100
	_progress.value = 0
	_progress.show_percentage = false
	_progress.custom_minimum_size = Vector2(0, 14)
	_progress.size_flags_horizontal = SIZE_EXPAND_FILL
	job_row.add_child(_progress)
	_job = TempleTheme.cell("Ready.", TempleTheme.MUTED, TempleTheme.SIZE_SMALL)
	_job.custom_minimum_size = Vector2(280, 0)
	job_row.add_child(_job)

	_guidance = TempleTheme.line(
		"There is no unpublish. Inscribing pays createTable to the operators.",
		TempleTheme.AMBER,
		TempleTheme.SIZE_SMALL
	)
	_guidance.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(_guidance)

	_console = RichTextLabel.new()
	_console.fit_content = false
	_console.scroll_following = true
	_console.bbcode_enabled = false
	_console.custom_minimum_size = Vector2(0, 72)
	_console.size_flags_vertical = Control.SIZE_SHRINK_END
	box.add_child(_console)
	return box


func _padded() -> MarginContainer:
	var m := MarginContainer.new()
	m.size_flags_horizontal = SIZE_EXPAND_FILL
	m.size_flags_vertical = SIZE_EXPAND_FILL
	m.clip_contents = true
	m.add_theme_constant_override("margin_left", 10)
	m.add_theme_constant_override("margin_right", 10)
	m.add_theme_constant_override("margin_top", 8)
	m.add_theme_constant_override("margin_bottom", 8)
	return m


func _make_list() -> ItemList:
	var list := ItemList.new()
	list.size_flags_horizontal = SIZE_EXPAND_FILL
	list.size_flags_vertical = SIZE_EXPAND_FILL
	list.select_mode = ItemList.SELECT_SINGLE
	list.fixed_icon_size = Vector2i(48, 48)
	list.same_column_width = true
	list.auto_width = false
	list.auto_height = false
	list.clip_contents = true
	list.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return list


func _facet_option(width: int) -> OptionButton:
	var btn := OptionButton.new()
	btn.custom_minimum_size = Vector2(width, 0)
	btn.size_flags_horizontal = SIZE_EXPAND_FILL
	btn.fit_to_longest_item = false
	btn.clip_text = true
	return btn


func _apply_archive_view() -> void:
	if _archive == null:
		return
	if _view_grid:
		_archive.icon_mode = ItemList.ICON_MODE_TOP
		_archive.fixed_icon_size = Vector2i(72, 72)
		_archive.max_columns = 0
		_archive.fixed_column_width = 120
		_archive.max_text_lines = 2
		if _view_btn:
			_view_btn.text = "GRID"
	else:
		_archive.icon_mode = ItemList.ICON_MODE_LEFT
		_archive.fixed_icon_size = Vector2i(48, 48)
		_archive.max_columns = 1
		_archive.fixed_column_width = 0
		_archive.max_text_lines = 1
		if _view_btn:
			_view_btn.text = "LIST"


func _toggle_view() -> void:
	_view_grid = not _view_grid
	_apply_archive_view()
	_save_config()
	for i in _archive.item_count:
		var rec: Variant = _archive.get_item_metadata(i)
		if rec is Dictionary:
			_archive.set_item_text(i, _archive_label(rec))


func _archive_label(rec: Dictionary) -> String:
	if _view_grid:
		return str(rec.get("title", "?"))
	return _list_line(rec)


func _placeholder_icon() -> Texture2D:
	if _placeholder_tex != null:
		return _placeholder_tex
	var img := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	img.fill(Color("111111"))
	var edge := TempleTheme.YELLOW
	for x in 48:
		img.set_pixel(x, 0, edge)
		img.set_pixel(x, 47, edge)
	for y in 48:
		img.set_pixel(0, y, edge)
		img.set_pixel(47, y, edge)
	_placeholder_tex = ImageTexture.create_from_image(img)
	return _placeholder_tex


func _make_facet(label: String, kind: String) -> FacetPick:
	var pick := FacetPick.new()
	pick.all_label = label
	pick.picked.connect(func(v: String) -> void: _on_facet(kind, v))
	return pick


func _fill_option(btn: OptionButton, all_label: String, values: PackedStringArray, current: String) -> void:
	if btn == null:
		return
	btn.clear()
	btn.add_item(all_label)
	var idx := 0
	var n := 1
	for v in values:
		if v.strip_edges().is_empty():
			continue
		btn.add_item(v)
		if v == current:
			idx = n
		n += 1
	if not current.is_empty() and idx == 0:
		btn.add_item(current)
		idx = n
	btn.select(idx)


func _on_facet(kind: String, v: String) -> void:
	if _facet_guard:
		return
	match kind:
		"dev":
			_sel_dev = v
		"pub":
			_sel_pub = v
		"series":
			_sel_series = v
		"tag":
			_sel_tag = v
	_on_search()


func _facet_value(btn: OptionButton) -> String:
	if btn == null or btn.selected <= 0:
		return ""
	return btn.get_item_text(btn.selected)


func _on_playlist_selected(index: int) -> void:
	if _facet_guard:
		return
	var id := str(_playlist.get_item_metadata(index))
	_playlist_id = id if not id.is_empty() else "all"
	_on_search()


func _playlist_title() -> String:
	if _playlist == null:
		return "All Games"
	return _playlist.get_item_text(_playlist.selected)


func _composed_query() -> String:
	var parts: PackedStringArray = []
	var typed := _search.text.strip_edges()
	if not typed.is_empty():
		parts.append(typed)
	if not _sel_dev.is_empty():
		parts.append("dev:\"%s\"" % _sel_dev)
	if not _sel_pub.is_empty():
		parts.append("pub:\"%s\"" % _sel_pub)
	if not _sel_series.is_empty():
		parts.append("series:\"%s\"" % _sel_series)
	if not _sel_tag.is_empty():
		parts.append("tag:\"%s\"" % _sel_tag)
	return " ".join(parts)


func _library_filter_or_arcade() -> String:
	var lib := _library_filter()
	return lib if not lib.is_empty() else "arcade"


func _list_line(rec: Dictionary) -> String:
	var title := str(rec.get("title", "?"))
	var dev := str(rec.get("developer", ""))
	var plat := Flashpoint.platform_label(rec)
	var line := "%s  ·  %s" % [title, plat]
	if not dev.is_empty():
		line = "%s  —  %s  ·  %s" % [title, dev, plat]
	if not flashpoint.is_gamezip(rec):
		line = "[LEGACY]  " + line
	var tags := _tag_summary(rec)
	if not tags.is_empty():
		line += "  ·  " + tags
	return line


func _entry_has_tag(rec: Dictionary, want: String) -> bool:
	var needle := want.to_lower()
	var tags: Variant = rec.get("tags", [])
	if tags is Array:
		for t: Variant in tags:
			if str(t).to_lower() == needle:
				return true
		return false
	return str(tags).to_lower().find(needle) >= 0


func _harvest_facets(hits: Array) -> void:
	_facet_ticket += 1
	var ticket := _facet_ticket
	var n := 0
	for entry: Variant in hits:
		if ticket != _facet_ticket:
			return
		if entry is Dictionary:
			var rec: Dictionary = entry
			_note_facet(_facet_devs, rec.get("developer", ""))
			_note_facet(_facet_pubs, rec.get("publisher", ""))
			_note_facet(_facet_series, rec.get("series", ""))
		n += 1
		if n % 2500 == 0:
			await get_tree().process_frame
	if ticket != _facet_ticket:
		return
	if _filter_dev:
		_filter_dev.set_names(_sorted_keys(_facet_devs))
	if _filter_pub:
		_filter_pub.set_names(_sorted_keys(_facet_pubs))
	if _filter_series:
		_filter_series.set_names(_sorted_keys(_facet_series))


func _note_facet(into: Dictionary, raw: Variant) -> void:
	var text := str(raw).strip_edges()
	if text.is_empty() or text == "[]":
		return
	for chunk in text.replace(";", ",").split(","):
		var name := chunk.strip_edges()
		if not name.is_empty():
			into[name] = true


func _sorted_keys(d: Dictionary) -> PackedStringArray:
	var keys: PackedStringArray = []
	for k: Variant in d.keys():
		keys.append(str(k))
	keys.sort()
	return keys


func _load_tag_dropdown() -> void:
	var names: PackedStringArray = await flashpoint.fetch_tags()
	if _filter_tag:
		_filter_tag.set_names(names)
	if names.is_empty() and not flashpoint.last_error.is_empty():
		_log(flashpoint.last_error)


func _empty_label(text: String) -> Label:
	var label := TempleTheme.line(text, TempleTheme.DARK_GREY, TempleTheme.SIZE_SMALL)
	label.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _connect_host() -> void:
	if await iq.discover(APP_NAME):
		_host_label.text = "HOST  OK"
		_host_label.add_theme_color_override("font_color", TempleTheme.GREEN)
	else:
		_on_host_missing(iq.last_error)


func _on_host_missing(reason: String) -> void:
	_host_label.text = "HOST  OFF"
	_host_label.add_theme_color_override("font_color", TempleTheme.BRIGHT_RED)
	kindled = false
	_update_root_chip()
	_log(reason)


func _ensure_ruffle() -> void:
	_ruffle_label.text = "RUFFLE  …"
	_ruffle_label.add_theme_color_override("font_color", TempleTheme.AMBER)
	_set_job("Fetching Ruffle…")
	var ok := await ruffle.ensure()
	if ok:
		_ruffle_label.text = "RUFFLE  %s" % ruffle.tag
		_ruffle_label.add_theme_color_override("font_color", TempleTheme.GREEN)
		_set_job("Ready.")
	else:
		_ruffle_label.text = "RUFFLE  OFF"
		_ruffle_label.add_theme_color_override("font_color", TempleTheme.BRIGHT_RED)
		_set_job(ruffle.last_error)
		_log(ruffle.last_error)


func _refresh_kindled() -> void:
	if not iq.is_available():
		kindled = false
		_update_root_chip()
		return
	cabinet = Cabinet.new(iq, chain)
	kindled = await cabinet.is_kindled()
	_update_root_chip()


func _update_root_chip() -> void:
	if not iq.is_available():
		_root_label.text = "ROOT  —"
		_root_label.add_theme_color_override("font_color", TempleTheme.MUTED)
		return
	if kindled:
		_root_label.text = "ROOT  %s" % chain.to_upper()
		_root_label.add_theme_color_override("font_color", TempleTheme.GREEN)
	else:
		_root_label.text = "ROOT  WAIT"
		_root_label.add_theme_color_override("font_color", TempleTheme.AMBER)


func _on_chain_selected(index: int) -> void:
	var names := ["mon", "sol", "rh"]
	chain = names[clampi(index, 0, 2)]
	_save_config()
	_log("Chain set to %s." % chain.to_upper())
	await _refresh_kindled()
	await _refresh_inscribed()
	_refresh_detail_actions()


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
	# Re-discover only if the host dropped. A second discover() used to mint a
	# new session token and GodOnChain would ask for reads again.
	if not iq.is_available():
		await _connect_host()
	await _refresh_kindled()
	await _refresh_inscribed()
	await _ensure_ruffle()
	_refresh_spr_chip()


func _on_search() -> void:
	_search_ticket += 1
	var ticket := _search_ticket
	_set_busy(true)
	var q := _composed_query()
	if _playlist_id != "all":
		_set_searching(true, "Loading  %s" % _playlist_title())
		_log("Playlist %s…" % _playlist_title())
		_set_job("Fetching %s…" % _playlist_title())
		var ids: PackedStringArray = await flashpoint.playlist_game_ids(_playlist_id)
		if ticket != _search_ticket:
			return
		if ids.is_empty():
			_set_searching(false)
			_set_busy(false)
			var why := flashpoint.last_error if not flashpoint.last_error.is_empty() else "Playlist was empty."
			_set_job(why)
			_log(why)
			return
		var hits: Array = await flashpoint.search_ids(ids, func(have: int, total: int) -> void:
			if ticket == _search_ticket:
				_set_job("%s  %d / %d" % [_playlist_title(), have, total])
		)
		if ticket != _search_ticket:
			return
		_show_search_hits(hits)
		return
	var limit := 0
	var library := _library_filter()
	if q.is_empty() and _browse_letter.is_empty():
		library = _library_filter_or_arcade()
		if not flashpoint.has_catalog(library):
			_set_searching(true, "Loading All Games…")
		await _load_all_games(ticket, library)
		return
	var wait := "Searching…"
	if not _browse_letter.is_empty():
		wait = "Loading letter %s…" % _browse_letter
	_set_searching(true, wait)
	if q.is_empty() and _browse_letter == "#":
		_log("Browsing titles 0–9…")
		var digit_hits: Array = await _browse_digits()
		if ticket != _search_ticket:
			return
		_show_search_hits(digit_hits)
		return
	if q.is_empty() and not _browse_letter.is_empty():
		q = "title:%s" % _browse_letter
	_log(_search_log_line(q if not q.is_empty() else "All Games"))
	var found: Array = await flashpoint.search(q, library, limit, "", false, Flashpoint.LIST_FIELDS)
	if ticket != _search_ticket:
		return
	_show_search_hits(found)


func _warmup_catalog() -> void:
	_warm_lib = _library_filter_or_arcade()
	_warm_done = false
	_warm_rows = []
	if flashpoint.has_catalog(_warm_lib):
		_set_job("Opening catalog…")
		_warm_rows = await flashpoint.load_catalog_async(_warm_lib)
		_warm_done = true
		if _still_all_games() and _archive_hits.is_empty() and not _warm_rows.is_empty():
			_show_search_hits(_warm_rows, true)
		if not flashpoint.catalog_is_fresh(_warm_lib):
			_refresh_catalog_background(_warm_lib)
		return
	_set_searching(true, "Loading All Games…")
	var first: Array = await flashpoint.search("", _warm_lib, PAGE_SIZE, "", false, Flashpoint.LIST_FIELDS)
	_warm_rows = first
	_warm_done = true
	if _still_all_games() and not first.is_empty():
		_show_search_hits(first)
	_set_job("%d titles on this page. Fetching the full catalog…" % first.size())
	var rest: Array = await flashpoint.search("", _warm_lib, 0, "", false, Flashpoint.LIST_FIELDS)
	if rest.size() > first.size():
		await flashpoint.save_catalog_async(_warm_lib, rest)
		_warm_rows = rest
		if _still_all_games():
			_show_search_hits(rest, true)


func _refresh_catalog_background(library: String) -> void:
	_set_job("%d titles. Checking for updates…" % _warm_rows.size())
	var fresh: Array = await flashpoint.search("", library, 0, "", false, Flashpoint.LIST_FIELDS)
	if fresh.size() <= 1000:
		return
	await flashpoint.save_catalog_async(library, fresh)
	_warm_rows = fresh
	if _still_all_games():
		var keep := _archive_page
		_show_search_hits(fresh, true)
		_archive_page = keep
		_paint_archive_page()


func _load_all_games(ticket: int, library: String) -> void:
	if library == _warm_lib:
		while not _warm_done:
			if ticket != _search_ticket:
				return
			await get_tree().process_frame
		if not _warm_rows.is_empty():
			_show_search_hits(_warm_rows, true)
			return
	_log("All Games — local index first, same idea as Flashpoint’s on-disk database.")
	var cached: Array = await flashpoint.load_catalog_async(library)
	if not cached.is_empty():
		_show_search_hits(cached, true)
		if flashpoint.catalog_is_fresh(library):
			_set_job("%d titles." % cached.size())
			return
		_refresh_catalog_background(library)
		return
	var first: Array = await flashpoint.search("", library, PAGE_SIZE, "", false, Flashpoint.LIST_FIELDS)
	if ticket != _search_ticket:
		return
	_show_search_hits(first)
	_set_job("%d titles on this page. Fetching the full catalog…" % first.size())
	var rest: Array = await flashpoint.search("", library, 0, "", false, Flashpoint.LIST_FIELDS)
	if ticket != _search_ticket:
		return
	if rest.size() <= first.size():
		_set_job("%d titles." % first.size())
		return
	await flashpoint.save_catalog_async(library, rest)
	if _still_all_games():
		_show_search_hits(rest, true)


func _still_all_games() -> bool:
	return (
		_playlist_id == "all"
		and _composed_query().is_empty()
		and _browse_letter.is_empty()
	)


func _show_search_hits(hits: Array, already_sorted: bool = false) -> void:
	_set_searching(false)
	_set_busy(false)
	hits = _filter_browse(hits)
	if not already_sorted and hits.size() <= 8000:
		Flashpoint.sort_titles(hits)
	_archive_hits = hits
	_archive_page = 0
	if hits.is_empty():
		var why := flashpoint.last_error if not flashpoint.last_error.is_empty() else "Nothing matched."
		_archive.clear()
		_archive_header.text = "ARCHIVE"
		_archive_empty.visible = true
		if _page_row:
			_page_row.visible = false
		_set_job(why)
		_log(why)
		return
	_paint_archive_page()
	_set_job("%d titles." % hits.size())
	_log("%d titles." % hits.size())
	_harvest_facets(hits)


func _paint_archive_page() -> void:
	var total := _archive_hits.size()
	var pages := maxi(1, ceili(float(total) / float(PAGE_SIZE)))
	_archive_page = clampi(_archive_page, 0, pages - 1)
	var start := _archive_page * PAGE_SIZE
	var stop := mini(start + PAGE_SIZE, total)
	_logo_ticket += 1
	_archive.clear()
	var placeholder := _placeholder_icon()
	var i := start
	while i < stop:
		var entry: Variant = _archive_hits[i]
		i += 1
		if not entry is Dictionary:
			continue
		var rec: Dictionary = entry
		var uuid := str(rec.get("id", ""))
		var inscribed := _inscribed_by_uuid.has(uuid)
		var idx := _archive.add_item(_archive_label(rec), placeholder)
		_archive.set_item_metadata(idx, rec)
		_archive.set_item_tooltip(idx, _tooltip_for(rec, inscribed))
		if inscribed:
			_archive.set_item_custom_fg_color(idx, TempleTheme.CYAN)
		elif not flashpoint.is_gamezip(rec):
			_archive.set_item_custom_fg_color(idx, TempleTheme.MUTED)
	var head := "ARCHIVE  ·  %d" % total
	if _playlist_id != "all":
		head += "  ·  %s" % _playlist_title()
	elif _search.text.strip_edges().is_empty() and _sel_dev.is_empty() and _sel_pub.is_empty() and _sel_series.is_empty() and _sel_tag.is_empty():
		head += "  ·  ALL GAMES"
	if not _browse_letter.is_empty():
		head += "  ·  %s" % _browse_letter
	if total > PAGE_SIZE:
		head += "  ·  %d–%d" % [start + 1, stop]
	_archive_header.text = head
	_archive_empty.visible = total == 0
	if _page_row:
		_page_row.visible = total > PAGE_SIZE
		if _page_label:
			_page_label.text = "PAGE  %d  /  %d" % [_archive_page + 1, pages]
		if _prev_page_btn:
			_prev_page_btn.disabled = _archive_page <= 0
		if _next_page_btn:
			_next_page_btn.disabled = _archive_page >= pages - 1
	_load_archive_logos()
	if _archive.item_count > 0:
		_archive.select(0)
		_on_archive_selected(0)


func _on_prev_page() -> void:
	if _archive_page <= 0:
		return
	_archive_page -= 1
	_paint_archive_page()


func _on_next_page() -> void:
	var pages := ceili(float(_archive_hits.size()) / float(PAGE_SIZE))
	if _archive_page >= pages - 1:
		return
	_archive_page += 1
	_paint_archive_page()


func _tooltip_for(rec: Dictionary, inscribed: bool) -> String:
	var bits: PackedStringArray = []
	if inscribed:
		bits.append("INSCRIBED")
	bits.append(str(rec.get("title", "")))
	var pub := str(rec.get("publisher", ""))
	if not pub.is_empty():
		bits.append(pub)
	var date := str(rec.get("releaseDate", ""))
	if not date.is_empty():
		bits.append(date)
	return "  ·  ".join(bits)


func _load_archive_logos() -> void:
	_logo_ticket += 1
	var ticket := _logo_ticket
	_logo_next = 0
	for _w in 8:
		_logo_worker(ticket)


func _logo_worker(ticket: int) -> void:
	while ticket == _logo_ticket:
		var i := _logo_next
		_logo_next += 1
		if i >= _archive.item_count:
			return
		var rec: Variant = _archive.get_item_metadata(i)
		if not rec is Dictionary:
			continue
		var uuid := str((rec as Dictionary).get("id", ""))
		if uuid.is_empty():
			continue
		var tex := await flashpoint.fetch_texture(flashpoint.logo_url(uuid), "logo-%s" % uuid)
		if ticket != _logo_ticket:
			return
		if tex != null and i < _archive.item_count:
			_archive.set_item_icon(i, tex)


func _on_archive_selected(index: int) -> void:
	_inscribed_list.deselect_all()
	var rec: Variant = _archive.get_item_metadata(index)
	if not rec is Dictionary:
		return
	_selected_kind = "archive"
	_selected_entry = rec
	_selected_table = Cartridge.table_name(str((rec as Dictionary).get("id", "")))
	_fill_detail_from_archive(rec)


func _on_inscribed_selected(index: int) -> void:
	_archive.deselect_all()
	var rec: Variant = _inscribed_list.get_item_metadata(index)
	if not rec is Dictionary:
		return
	_selected_kind = "inscribed"
	_selected_table = str((rec as Dictionary).get("table", ""))
	_selected_entry = (rec as Dictionary).get("meta", {})
	_fill_detail_from_inscribed(_selected_table, _selected_entry)


func _fill_detail_from_archive(rec: Dictionary) -> void:
	var uuid := str(rec.get("id", ""))
	var inscribed := _inscribed_by_uuid.has(uuid)
	_detail_title.text = str(rec.get("title", "Untitled"))
	_detail_chip.text = "INSCRIBED" if inscribed else "AVAILABLE"
	_detail_chip.add_theme_color_override(
		"font_color", TempleTheme.CYAN if inscribed else TempleTheme.GREEN
	)
	_detail_meta.text = _meta_line(rec)
	_detail_body.text = _description(rec)
	_fill_tags(rec)
	_preview_bytes = -1
	if inscribed:
		_detail_cost.text = "Already on this chain. Play it."
	else:
		_detail_cost.text = "Checking size…"
		_load_size(uuid, str(rec.get("launchCommand", "")))
	_shot_empty.text = "LOADING ART…"
	_shot.texture = null
	_shot_empty.visible = true
	_refresh_detail_actions()
	_load_shot(uuid)


func _fill_detail_from_inscribed(table: String, meta: Dictionary) -> void:
	var title := str(meta.get("title", table))
	_detail_title.text = title
	_detail_chip.text = "ON CHAIN  ·  %s" % chain.to_upper()
	_detail_chip.add_theme_color_override("font_color", TempleTheme.CYAN)
	var uuid := str(meta.get("uuid", ""))
	_detail_meta.text = _meta_line(meta)
	var sha := str(meta.get("sha256", ""))
	_detail_body.text = "Table %s\nSHA-256  %s" % [table, sha if not sha.is_empty() else "—"]
	_clear_tags()
	if str(meta.get("uuid", "")).is_empty() and sha.is_empty():
		_detail_cost.text = (
			"Incomplete inscription — no GameZIP on this table. "
			+ "Search the original title in ARCHIVE and Inscribe again to finish it."
		)
	else:
		var n := int(meta.get("bytes", 0))
		if n > 0:
			_detail_cost.text = (
				"On-chain GameZIP %s. Play from cache, or fetch from the chain."
				% Flashpoint.format_bytes(n)
			)
		else:
			_detail_cost.text = "Play from the local cache, or fetch the zip from the chain."
	_shot.texture = null
	_shot_empty.text = "LOADING ART…"
	_shot_empty.visible = true
	_refresh_detail_actions()
	if not uuid.is_empty():
		_load_shot(uuid)
	else:
		_shot_empty.text = "NO SCREENSHOT"
		_shot_empty.visible = true


func _clear_detail() -> void:
	_selected_kind = ""
	_selected_entry = {}
	_selected_table = ""
	_detail_title.text = "Select a title"
	_detail_chip.text = ""
	_detail_meta.text = "The stage shows art, credits, and the action for whatever you pick."
	_detail_body.text = ""
	_detail_cost.text = ""
	_preview_bytes = -1
	_clear_tags()
	_shot.texture = null
	_shot_empty.text = "NO CARTRIDGE SELECTED"
	_shot_empty.visible = true
	_refresh_detail_actions()


func _meta_line(rec: Dictionary) -> String:
	var bits: PackedStringArray = []
	var plat := Flashpoint.platform_label(rec)
	if plat != "Unknown":
		bits.append(plat)
	for key in ["developer", "publisher", "releaseDate"]:
		var value := str(rec.get(key, "")).strip_edges()
		if not value.is_empty():
			bits.append(value)
	return "  ·  ".join(bits)


func _description(rec: Dictionary) -> String:
	var text := str(rec.get("originalDescription", rec.get("notes", ""))).strip_edges()
	if text.is_empty():
		return "No description in the archive record."
	return text


func _library_filter() -> String:
	match _library.selected:
		0:
			return "arcade"
		1:
			return "theatre"
		_:
			return ""


func _format_mark(rec: Dictionary) -> String:
	return Flashpoint.platform_label(rec)


func _fill_letter_bar() -> void:
	_letter_buttons.clear()
	for child in _letter_bar.get_children():
		child.queue_free()
	var keys: PackedStringArray = ["#"]
	for i in range(26):
		keys.append(String.chr(65 + i))
	for letter in keys:
		var b := Button.new()
		b.text = letter
		b.custom_minimum_size = Vector2(26, 22)
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(_on_letter.bind(letter))
		_letter_bar.add_child(b)
		_letter_buttons[letter] = b
	_paint_letters()


func _on_letter(letter: String) -> void:
	if _browse_letter == letter:
		_browse_letter = ""
	else:
		_browse_letter = letter
	_paint_letters()
	_on_search()


func _paint_letters() -> void:
	for letter: Variant in _letter_buttons.keys():
		var b: Button = _letter_buttons[letter]
		if str(letter) == _browse_letter:
			b.add_theme_stylebox_override("normal", TempleTheme._solid(TempleTheme.YELLOW))
			b.add_theme_color_override("font_color", TempleTheme.BLACK)
		else:
			b.remove_theme_stylebox_override("normal")
			b.add_theme_color_override("font_color", TempleTheme.YELLOW)


func _search_log_line(q: String) -> String:
	var bits: PackedStringArray = []
	if _playlist_id != "all":
		bits.append(_playlist_title())
	if not q.is_empty():
		bits.append("“%s”" % q)
	if not _browse_letter.is_empty():
		bits.append("letter %s" % _browse_letter)
	if bits.is_empty():
		return "Browsing All Games…"
	return "Searching Flashpoint %s…" % " · ".join(bits)


func _title_letter(title: String) -> String:
	var t := title.strip_edges()
	if t.is_empty():
		return "#"
	var ch := t.substr(0, 1).to_upper()
	if ch < "A" or ch > "Z":
		return "#"
	return ch


func _filter_browse(hits: Array) -> Array:
	var need := not _browse_letter.is_empty() or _playlist_id != "all"
	if not need:
		return hits
	var out: Array = []
	for entry: Variant in hits:
		if not entry is Dictionary:
			continue
		var rec: Dictionary = entry
		if not _browse_letter.is_empty():
			if _title_letter(str(rec.get("title", ""))) != _browse_letter:
				continue
		if _playlist_id != "all":
			if not _sel_dev.is_empty() and str(rec.get("developer", "")).to_lower().find(_sel_dev.to_lower()) < 0:
				continue
			if not _sel_pub.is_empty() and str(rec.get("publisher", "")).to_lower().find(_sel_pub.to_lower()) < 0:
				continue
			if not _sel_series.is_empty() and str(rec.get("series", "")).to_lower().find(_sel_series.to_lower()) < 0:
				continue
			if not _sel_tag.is_empty() and not _entry_has_tag(rec, _sel_tag):
				continue
			var typed := _search.text.strip_edges()
			if not typed.is_empty() and str(rec.get("title", "")).to_lower().find(typed.to_lower()) < 0:
				continue
		out.append(rec)
	return out


func _browse_digits() -> Array:
	var merged: Array = []
	var seen := {}
	for d in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]:
		var chunk: Array = await flashpoint.search("title:%s" % d, _library_filter(), 400)
		for entry: Variant in chunk:
			if not entry is Dictionary:
				continue
			var id := str((entry as Dictionary).get("id", ""))
			if id.is_empty() or seen.has(id):
				continue
			seen[id] = true
			merged.append(entry)
	return merged


func _tag_summary(rec: Dictionary) -> String:
	var tags: Variant = rec.get("tags", [])
	if not tags is Array:
		return str(tags)
	var bits: PackedStringArray = []
	for t: Variant in tags:
		bits.append(str(t))
		if bits.size() >= 3:
			break
	return ", ".join(bits)


func _fill_tags(rec: Dictionary) -> void:
	_clear_tags()
	var tags: Variant = rec.get("tags", [])
	if not tags is Array:
		return
	var n := 0
	for t: Variant in tags:
		if n >= 6:
			break
		var label := str(t).strip_edges()
		if label.is_empty():
			continue
		var b := TempleTheme.button(label, _search_tag.bind(label))
		b.add_theme_font_size_override("font_size", TempleTheme.SIZE_SMALL)
		_tag_box.add_child(b)
		n += 1


func _clear_tags() -> void:
	if _tag_box == null:
		return
	for child in _tag_box.get_children():
		child.queue_free()


func _search_tag(tag: String) -> void:
	_sel_tag = tag.strip_edges()
	if _filter_tag:
		_filter_tag.set_value(_sel_tag)
	_on_search()


func _load_size(uuid: String, launch: String = "") -> void:
	_size_ticket += 1
	var ticket := _size_ticket
	var n := await flashpoint.zip_size(uuid, launch)
	if ticket != _size_ticket:
		return
	if _selected_kind != "archive" or str(_selected_entry.get("id", "")) != uuid:
		return
	if n <= 0:
		_preview_bytes = -1
		_detail_cost.text = (
			"Table %s — size unknown. Inscribe will measure after download."
			% Cartridge.table_name(uuid)
		)
		return
	_preview_bytes = n
	_detail_cost.text = (
		"GameZIP %s\n%s\nTable %s"
		% [Flashpoint.format_bytes(n), Costs.quote_inscribe(chain, n), Cartridge.table_name(uuid)]
	)
	_guidance.text = "There is no unpublish. %s" % Costs.quote_inscribe(chain, n)


func _load_shot(uuid: String) -> void:
	_shot_ticket += 1
	var ticket := _shot_ticket
	var tex := await flashpoint.fetch_texture(flashpoint.screenshot_url(uuid), "shot-%s" % uuid)
	if ticket != _shot_ticket:
		return
	if tex == null:
		_shot_empty.text = "NO SCREENSHOT"
		_shot_empty.visible = true
		return
	_shot.texture = tex
	_shot_empty.visible = false


func _refresh_detail_actions() -> void:
	var can_write := iq != null and iq.is_available() and kindled and not _busy
	var archive_pick := _selected_kind == "archive"
	var inscribed_pick := _selected_kind == "inscribed"
	var uuid := str(_selected_entry.get("id", _selected_entry.get("uuid", "")))
	var already := (not uuid.is_empty() and _inscribed_by_uuid.has(uuid)) or inscribed_pick
	var can_try := (
		archive_pick
		and flashpoint != null
		and flashpoint.playable_here(_selected_entry)
	)
	_inscribe_btn.disabled = _busy or not can_write or not archive_pick or already
	_play_btn.disabled = _busy or not (already or can_try)
	if already:
		_inscribe_btn.text = "INSCRIBED"
		_play_btn.text = "PLAY"
	else:
		_inscribe_btn.text = "INSCRIBE"
		_play_btn.text = "TRY"
	if archive_pick and FlashpointHost.needs_flashpoint(_selected_entry):
		_play_btn.text = "TRY IN FP"


func _on_inscribe() -> void:
	if _busy:
		return
	if not iq.is_available():
		_log("No host. Launch this from GodOnChain.")
		return
	if not kindled:
		_log("This chain's dbRoot is not ready. Inscribe is refused.")
		return
	if _selected_kind != "archive":
		_log("Pick a title in ARCHIVE.")
		return
	var entry := _selected_entry
	if not flashpoint.playable_here(entry):
		_log("That title is not a GameZIP we can download.")
		return
	var uuid := str(entry.get("id", ""))
	var table_id := Cartridge.table_name(uuid)
	_log("This title maps to table %s." % table_id)

	if _preview_bytes <= 0:
		_set_job("Checking GameZIP size…")
		_preview_bytes = await flashpoint.zip_size(uuid)
	if _preview_bytes > 0:
		var quote := Costs.quote_inscribe(chain, _preview_bytes)
		_detail_cost.text = (
			"GameZIP %s\n%s"
			% [Flashpoint.format_bytes(_preview_bytes), quote]
		)
		_guidance.text = "There is no unpublish. %s" % quote
		_log("%s — %s" % [Flashpoint.format_bytes(_preview_bytes), quote])
		if not await _confirm(
			(
				"There is no unpublish.\n\nGameZIP %s\n%s\ncreateTable pays the operators, not you.\n\nInscribe “%s” on %s?"
				% [
					Flashpoint.format_bytes(_preview_bytes),
					quote,
					str(entry.get("title", uuid)),
					chain.to_upper(),
				]
			)
		):
			_set_job("Inscribe cancelled.")
			_log("Inscribe cancelled.")
			return

	_set_busy(true)
	_last_progress = -1
	_progress.value = 0
	var zip_path := Cartridge.staging_path(uuid)
	if flashpoint.is_gamezip(entry):
		_set_job("Downloading %s…" % str(entry.get("title", uuid)))
		_log("Downloading GameZIP for %s…" % str(entry.get("title", uuid)))
		if not await flashpoint.download_zip(uuid, zip_path, _on_progress):
			_set_busy(false)
			_set_job(flashpoint.last_error)
			_log("Download failed: %s" % flashpoint.last_error)
			return
	else:
		_set_job("Fetching legacy and packing a zip…")
		_log("Legacy title — pulling Infinity htdocs, then inscribing as a zip.")
		var tree := Cartridge.trial_dir(uuid)
		var got := await flashpoint.fetch_legacy(str(entry.get("launchCommand", "")), tree, _on_progress)
		if got.is_empty():
			_set_busy(false)
			_set_job(flashpoint.last_error)
			_log("Legacy fetch failed: %s" % flashpoint.last_error)
			return
		if not flashpoint.pack_dir(tree, zip_path):
			_set_busy(false)
			_set_job(flashpoint.last_error)
			_log("Could not pack legacy files: %s" % flashpoint.last_error)
			return

	var raw_bytes := FileAccess.get_file_as_bytes(zip_path)
	if _preview_bytes <= 0:
		var quote := Costs.quote_inscribe(chain, raw_bytes.size())
		_detail_cost.text = quote
		_guidance.text = "There is no unpublish. %s" % quote
		_log(quote)
		if not await _confirm(
			(
				"There is no unpublish.\n\n%s\ncreateTable pays the operators, not you.\n\nInscribe “%s” on %s?"
				% [quote, str(entry.get("title", uuid)), chain.to_upper()]
			)
		):
			_set_busy(false)
			_set_job("Inscribe cancelled.")
			_log("Inscribe cancelled.")
			return

	_set_job("Inscribing… approve each spend in GodOnChain.")
	_log("Inscribing. Approve each spend in GodOnChain (createTable, then two rows).")
	var result = await cabinet.inscribe(entry, zip_path, _on_progress)
	_set_busy(false)
	if result == null:
		_set_job(cabinet.last_error)
		_log("Inscribe failed: %s" % cabinet.last_error)
		return
	var table := str((result as Dictionary).get("table", Cartridge.table_name(uuid)))
	if result.get("already", false):
		_log("Already on-chain as %s." % table)
	else:
		_log("Inscribed as %s." % table)
		shelf.remember(
			table,
			{
				"uuid": uuid,
				"title": str(entry.get("title", "")),
				"sha256": str(result.get("sha256", "")),
			}
		)
	_set_job("Inscribed.")
	await _refresh_inscribed()
	if not _inscribed.has(table):
		_log("Chain listing lagged; showing %s from this write." % table)
		_add_inscribed_row(
			table,
			{
				"uuid": uuid,
				"title": str(entry.get("title", "")),
				"sha256": str(result.get("sha256", "")),
			}
		)
	_fill_detail_from_archive(entry)


func _on_play() -> void:
	if _busy:
		return
	if _selected_kind == "archive":
		var uuid := str(_selected_entry.get("id", ""))
		var already := not uuid.is_empty() and _inscribed_by_uuid.has(uuid)
		if not already:
			await _trial_play(_selected_entry)
			return
	await _play_inscribed()


func _trial_play(entry: Dictionary) -> void:
	if not flashpoint.playable_here(entry):
		_log("That title is not a GameZIP we can download.")
		return
	var uuid := str(entry.get("id", "")).strip_edges()
	if uuid.is_empty():
		_log("Entry has no id.")
		return
	if FlashpointHost.needs_flashpoint(entry):
		_launch_via_flashpoint(entry, true)
		return
	_set_busy(true)
	_last_progress = -1
	if ruffle.exe_path.is_empty() and not FlashpointHost.needs_shockwave(entry):
		await ruffle.ensure()
	var dest := Cartridge.trial_dir(uuid)
	var dest_abs := ProjectSettings.globalize_path(dest)
	var launch := str(entry.get("launchCommand", ""))
	if not DirAccess.dir_exists_absolute(dest_abs) or Unzip.file_for_launch(dest, launch).is_empty():
		if flashpoint.is_gamezip(entry):
			var zip_path := Cartridge.staging_path(uuid)
			if not FileAccess.file_exists(zip_path):
				_set_job("Downloading trial…")
				_log("Trial play — downloading GameZIP (not inscribed).")
				if not await flashpoint.download_zip(uuid, zip_path, _on_progress):
					_set_busy(false)
					_set_job(flashpoint.last_error)
					_log("Download failed: %s" % flashpoint.last_error)
					return
			if not Unzip.extract(zip_path, dest):
				_set_busy(false)
				_set_job("Could not extract the GameZIP.")
				_log("Could not extract the GameZIP.")
				return
		else:
			_set_job("Fetching legacy file (Infinity htdocs)…")
			_log("Trial play — Infinity Legacy/htdocs (not inscribed).")
			var got := await flashpoint.fetch_legacy(launch, dest, _on_progress)
			if got.is_empty():
				_set_busy(false)
				_set_job(flashpoint.last_error)
				_log("Legacy fetch failed: %s" % flashpoint.last_error)
				return
	await _launch_entry(dest, entry, true)


func _play_inscribed() -> void:
	var table := _selected_table
	var meta := _selected_entry
	if table.is_empty():
		_log("Pick a title to play.")
		return
	_set_busy(true)
	_last_progress = -1
	if ruffle.exe_path.is_empty() and not FlashpointHost.needs_shockwave(meta):
		await ruffle.ensure()
	var dest := Cartridge.cache_dir(table)
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dest)):
		if not iq.is_available():
			_set_busy(false)
			_set_job("No cached copy, and no host to fetch one.")
			_log("No cached copy, and no host to fetch one.")
			return
		_set_job("Reading from chain…")
		_log("Reading %s from chain…" % table)
		var game: Dictionary = await cabinet.read_game(table, _on_progress)
		var blob: Dictionary = game.get("blob", {})
		var b64 := str(blob.get("data", ""))
		if b64.is_empty():
			_set_busy(false)
			_set_job("No blob on that table.")
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
	await _launch_entry(dest, meta, false)


func _refresh_spr_chip() -> void:
	if spr != null and spr.has_runtime():
		_spr_label.text = "SPR  %s" % (spr.tag if not spr.tag.is_empty() else "OK")
		_spr_label.add_theme_color_override("font_color", TempleTheme.GREEN)
	else:
		_spr_label.text = "SPR  —"
		_spr_label.add_theme_color_override("font_color", TempleTheme.AMBER)


func _launch_via_flashpoint(entry: Dictionary, trial: bool) -> bool:
	var uuid := str(entry.get("id", entry.get("uuid", ""))).strip_edges()
	if uuid.is_empty():
		return false
	if fp_host.clifp().is_empty():
		if not fp_host.autodetect():
			_log("That platform still needs a Flashpoint install (Unity/Java). Shockwave uses auto-fetched SPR.")
			_set_job("No Flashpoint install for this platform.")
			return true
	var pid := fp_host.play_id(uuid)
	if pid == -1:
		_log(fp_host.last_error)
		_set_job(fp_host.last_error)
		return true
	var tag := "Trial" if trial else "Play"
	_set_job("%s via Flashpoint." % tag)
	_log("%s CLIFp pid %d — %s" % [tag, pid, uuid])
	return true


func _launch_via_spr(dest: String, meta: Dictionary, trial: bool) -> void:
	_set_job("Fetching Shockwave projector…")
	_spr_label.text = "SPR  …"
	_spr_label.add_theme_color_override("font_color", TempleTheme.AMBER)
	var ok := await spr.ensure(_on_progress)
	_refresh_spr_chip()
	if not ok:
		_log(spr.last_error)
		if fp_host.clifp().is_empty():
			fp_host.autodetect()
		if not fp_host.clifp().is_empty():
			_set_busy(false)
			_launch_via_flashpoint(meta, trial)
			return
		_set_busy(false)
		_set_job(spr.last_error)
		return
	var launch := str(meta.get("launch", meta.get("launchCommand", "")))
	var dest_abs := ProjectSettings.globalize_path(dest)
	var serve_root := dest_abs
	if DirAccess.dir_exists_absolute(dest_abs.path_join("content")):
		serve_root = dest_abs.path_join("content")
	var port := httpd.serve(serve_root, LocalHttp.SPR_PORT, Flashpoint.LEGACY_HTDOCS)
	if port < 0:
		_set_busy(false)
		_set_job("Could not start local HTTP.")
		_log("Could not start local HTTP for SPR.")
		return
	var pj := Spr.projector_folder(str(meta.get("applicationPath", "")))
	if not spr.configure_proxy(port, pj):
		_set_busy(false)
		_set_job(spr.last_error)
		_log(spr.last_error)
		return
	var movie := Unzip.movie_url(launch)
	if movie.begins_with("https://"):
		movie = "http://" + movie.substr(8)
	elif not movie.begins_with("http://") and not movie.begins_with("ftp://"):
		var rel := Unzip.path_from_launch(launch)
		if rel.is_empty():
			_set_busy(false)
			_set_job("No launch URL for SPR.")
			return
		movie = "http://" + rel
	var extra := Unzip.extra_args(launch)
	var pid := spr.play(movie, extra, pj)
	_set_busy(false)
	var tag := "Trial" if trial else "Play"
	if pid == -1:
		_set_job(spr.last_error)
		_log("SPR failed: %s" % spr.last_error)
	else:
		_set_job("%s in SPR (%s)%s." % [tag, pj, " — not inscribed" if trial else ""])
		_log("%s SPR pid %d proxy %d — %s" % [tag, pid, port, movie])


func _launch_entry(dest: String, meta: Dictionary, trial: bool) -> void:
	var launch := str(meta.get("launch", meta.get("launchCommand", "")))
	if FlashpointHost.needs_shockwave(meta):
		await _launch_via_spr(dest, meta, trial)
		return
	if FlashpointHost.needs_flashpoint(meta):
		_set_busy(false)
		_launch_via_flashpoint(meta, trial)
		return
	var file := Unzip.file_for_launch(dest, launch)
	if file.is_empty():
		_set_busy(false)
		_set_job("No launch file in that cartridge.")
		_log("No launch file in that cartridge.")
		return
	var tag := "Trial" if trial else "Play"
	if Flashpoint.uses_ruffle(meta) or file.to_lower().ends_with(".swf"):
		var dest_abs := ProjectSettings.globalize_path(dest)
		var has_content := DirAccess.dir_exists_absolute(dest_abs.path_join("content"))
		var pid := -1
		if has_content:
			pid = ruffle.play(file, dest)
		else:
			var port := httpd.serve(dest_abs, 18765, Flashpoint.LEGACY_HTDOCS)
			if port < 0:
				_set_busy(false)
				_set_job("Could not start local HTTP.")
				return
			var rel := Unzip.path_from_launch(launch)
			pid = ruffle.play(httpd.url_for(rel), "http://127.0.0.1:%d/" % port)
		_set_busy(false)
		if pid == -1:
			_set_job(ruffle.last_error)
			_log("Play failed: %s" % ruffle.last_error)
		else:
			_set_job("%s in Ruffle%s." % [tag, " — not inscribed" if trial else ""])
			_log("%s Ruffle pid %d — %s" % [tag, pid, file.get_file()])
		return
	if Flashpoint.uses_browser(meta) or file.get_extension().to_lower() in ["html", "htm"]:
		var dest_abs := ProjectSettings.globalize_path(dest)
		var remote := "" if DirAccess.dir_exists_absolute(dest_abs.path_join("content")) else Flashpoint.LEGACY_HTDOCS
		var port := httpd.serve(file.get_base_dir(), 18765, remote)
		_set_busy(false)
		if port < 0:
			_set_job("Could not start local HTTP.")
			_log("Could not start local HTTP.")
			return
		var url := httpd.url_for(file.get_file())
		OS.shell_open(url)
		_set_job("%s in browser (%s)%s." % [tag, Flashpoint.platform_label(meta), " — not inscribed" if trial else ""])
		_log("%s browser %s" % [tag, url])
		return
	_set_busy(false)
	OS.shell_open(file)
	_set_job("%s via system open (%s)." % [tag, Flashpoint.platform_label(meta)])
	_log("%s opened %s" % [tag, file])


func _refresh_inscribed() -> void:
	_inscribed = []
	_inscribed_by_uuid = {}
	_cabinet_rows = []
	if not iq.is_available():
		_paint_cabinet()
		_inscribed_empty.text = "No host.\nCached play still works."
		return
	var names: PackedStringArray = await cabinet.table_names()
	if names.is_empty() and not cabinet.last_error.is_empty():
		_log("Could not list tables: %s" % cabinet.last_error)
	for table in names:
		var meta: Dictionary = await cabinet.read_meta(table)
		_register_cabinet_row(table, meta)
	_cabinet_page = 0
	_rebuild_cabinet_platforms()
	_paint_cabinet()
	_log("%d inscribed tables on %s." % [_cabinet_rows.size(), chain.to_upper()])
	_badge_archive_from_map()
	_refresh_detail_actions()


func _add_inscribed_row(table: String, meta: Dictionary) -> void:
	if Cartridge.is_kindled_table(table) or _inscribed.has(table):
		return
	_register_cabinet_row(table, meta)
	_rebuild_cabinet_platforms()
	_paint_cabinet()
	_badge_archive_from_map()
	_refresh_detail_actions()


func _register_cabinet_row(table: String, meta: Dictionary) -> void:
	if Cartridge.is_kindled_table(table) or _inscribed.has(table):
		return
	var title := str(meta.get("title", table)).strip_edges()
	if title.is_empty() and shelf.entries.has(table):
		title = str((shelf.entries[table] as Dictionary).get("title", ""))
	if title.is_empty():
		title = table
	var uuid := str(meta.get("uuid", meta.get("id", "")))
	var rec := {"table": table, "meta": meta, "title": title}
	_cabinet_rows.append(rec)
	_inscribed.append(table)
	if not uuid.is_empty():
		_inscribed_by_uuid[uuid] = rec


func _cabinet_filtered() -> Array:
	var needle := ""
	if _cabinet_filter:
		needle = _cabinet_filter.text.strip_edges().to_lower()
	var out: Array = []
	for row: Variant in _cabinet_rows:
		if not row is Dictionary:
			continue
		var rec: Dictionary = row
		var title := str(rec.get("title", ""))
		var meta: Dictionary = rec.get("meta", {})
		var plat := Flashpoint.platform_label(meta)
		if not _cabinet_letter.is_empty() and _title_letter(title) != _cabinet_letter:
			continue
		if not _cabinet_plat.is_empty() and plat != _cabinet_plat:
			continue
		if not needle.is_empty():
			var blob := "%s %s %s" % [title, plat, str(meta.get("developer", ""))]
			if blob.to_lower().find(needle) < 0:
				continue
		out.append(rec)
	out.sort_custom(func(a: Variant, b: Variant) -> bool:
		return str((a as Dictionary).get("title", "")).nocasecmp_to(str((b as Dictionary).get("title", ""))) < 0
	)
	return out


func _paint_cabinet() -> void:
	if _inscribed_list == null:
		return
	var rows := _cabinet_filtered()
	var total := rows.size()
	var pages := maxi(1, ceili(float(total) / float(CABINET_PAGE)))
	_cabinet_page = clampi(_cabinet_page, 0, pages - 1)
	var start := _cabinet_page * CABINET_PAGE
	var stop := mini(start + CABINET_PAGE, total)
	_cabinet_logo_ticket += 1
	_inscribed_list.clear()
	var placeholder := _placeholder_icon()
	var i := start
	while i < stop:
		var rec: Dictionary = rows[i]
		i += 1
		var meta: Dictionary = rec.get("meta", {})
		var title := str(rec.get("title", rec.get("table", "?")))
		var plat := Flashpoint.platform_label(meta)
		var line := title if plat == "Unknown" else "%s  ·  %s" % [title, plat]
		var idx := _inscribed_list.add_item(line, placeholder)
		_inscribed_list.set_item_metadata(idx, rec)
		_inscribed_list.set_item_custom_fg_color(idx, TempleTheme.CYAN)
	var head := "ON CHAIN  ·  %d" % total
	if not _cabinet_plat.is_empty():
		head += "  ·  %s" % _cabinet_plat
	if total > CABINET_PAGE:
		head += "  ·  %d–%d" % [start + 1, stop]
	_inscribed_header.text = head
	_inscribed_empty.visible = total == 0
	if _cabinet_page_row:
		_cabinet_page_row.visible = total > CABINET_PAGE
		if _cabinet_page_label:
			_cabinet_page_label.text = "%d  /  %d" % [_cabinet_page + 1, pages]
		if _cabinet_prev:
			_cabinet_prev.disabled = _cabinet_page <= 0
		if _cabinet_next:
			_cabinet_next.disabled = _cabinet_page >= pages - 1
	_load_cabinet_logos()


func _rebuild_cabinet_platforms() -> void:
	var names: PackedStringArray = []
	var seen := {}
	for row: Variant in _cabinet_rows:
		if not row is Dictionary:
			continue
		var plat := Flashpoint.platform_label((row as Dictionary).get("meta", {}))
		if plat == "Unknown" or seen.has(plat):
			continue
		seen[plat] = true
		names.append(plat)
	names.sort()
	var keep := _cabinet_plat
	_fill_option(_cabinet_platform, "Platform", names, keep)
	if keep != "" and not seen.has(keep):
		_cabinet_plat = ""


func _fill_cabinet_letters() -> void:
	if _cabinet_letters == null:
		return
	_cabinet_letter_buttons.clear()
	for child in _cabinet_letters.get_children():
		child.queue_free()
	var keys: PackedStringArray = ["#"]
	for n in range(26):
		keys.append(String.chr(65 + n))
	for letter in keys:
		var b := Button.new()
		b.text = letter
		b.custom_minimum_size = Vector2(22, 20)
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(_on_cabinet_letter.bind(letter))
		_cabinet_letters.add_child(b)
		_cabinet_letter_buttons[letter] = b
	_paint_cabinet_letters()


func _on_cabinet_letter(letter: String) -> void:
	if _cabinet_letter == letter:
		_cabinet_letter = ""
	else:
		_cabinet_letter = letter
	_cabinet_page = 0
	_paint_cabinet_letters()
	_paint_cabinet()


func _paint_cabinet_letters() -> void:
	for letter: Variant in _cabinet_letter_buttons.keys():
		var b: Button = _cabinet_letter_buttons[letter]
		if str(letter) == _cabinet_letter:
			b.add_theme_stylebox_override("normal", TempleTheme._solid(TempleTheme.CYAN))
			b.add_theme_color_override("font_color", TempleTheme.BLACK)
		else:
			b.remove_theme_stylebox_override("normal")
			b.add_theme_color_override("font_color", TempleTheme.CYAN)


func _on_cabinet_platform() -> void:
	_cabinet_plat = _facet_value(_cabinet_platform)
	_cabinet_page = 0
	_paint_cabinet()


func _on_cabinet_prev() -> void:
	if _cabinet_page <= 0:
		return
	_cabinet_page -= 1
	_paint_cabinet()


func _on_cabinet_next() -> void:
	var pages := ceili(float(_cabinet_filtered().size()) / float(CABINET_PAGE))
	if _cabinet_page >= pages - 1:
		return
	_cabinet_page += 1
	_paint_cabinet()


func _load_cabinet_logos() -> void:
	_cabinet_logo_ticket += 1
	var ticket := _cabinet_logo_ticket
	for i in _inscribed_list.item_count:
		if ticket != _cabinet_logo_ticket:
			return
		var rec: Variant = _inscribed_list.get_item_metadata(i)
		if not rec is Dictionary:
			continue
		var meta: Dictionary = (rec as Dictionary).get("meta", {})
		var uuid := str(meta.get("uuid", ""))
		if uuid.is_empty():
			continue
		var tex := await flashpoint.fetch_texture(flashpoint.logo_url(uuid), "logo-%s" % uuid)
		if ticket != _cabinet_logo_ticket:
			return
		if tex != null and i < _inscribed_list.item_count:
			_inscribed_list.set_item_icon(i, tex)


func _badge_archive_from_map() -> void:
	for i in _archive.item_count:
		var rec: Variant = _archive.get_item_metadata(i)
		if not rec is Dictionary:
			continue
		var uuid := str((rec as Dictionary).get("id", ""))
		if _inscribed_by_uuid.has(uuid):
			_archive.set_item_custom_fg_color(i, TempleTheme.CYAN)
			_archive.set_item_tooltip(i, _tooltip_for(rec, true))


func _on_progress(value: float) -> void:
	_progress.value = value
	var step := int(value / 10.0) * 10
	if step == _last_progress:
		return
	_last_progress = step
	_job.text = "%d%%" % step


func _set_searching(on: bool, message: String = "LOADING…") -> void:
	_searching = on
	_search_spin = 0.0
	if _load_veil:
		_load_veil.visible = on
	if _load_label:
		_load_label.visible = on
		if on:
			_load_label.text = message.to_upper()
	if _search_btn:
		_search_btn.text = "WAIT" if on else "SEARCH"
	if _archive:
		_archive.modulate.a = 0.25 if on else 1.0
	if on:
		if _archive_header:
			_archive_header.text = "ARCHIVE  ·  LOADING"
		if _archive_empty:
			_archive_empty.visible = false
		_set_job(message)
	set_process(on)


func _process(dt: float) -> void:
	if not _searching:
		return
	_search_spin += dt * 3.2
	if _load_veil:
		_load_veil.color.a = 0.62 + 0.18 * sin(_search_spin)
	if _load_label:
		_load_label.modulate.a = 0.7 + 0.3 * abs(sin(_search_spin * 1.4))
	if _last_progress < 0:
		_progress.value = 50.0 + 42.0 * sin(_search_spin * 0.65)


func _set_job(text: String) -> void:
	_job.text = text
	if not _busy and not _searching:
		_progress.value = 0


func _confirm(body: String) -> bool:
	var dialog := ConfirmationDialog.new()
	dialog.title = "No unpublish"
	dialog.dialog_text = body
	dialog.ok_button_text = "PROCEED"
	dialog.cancel_button_text = "CANCEL"
	add_child(dialog)
	dialog.popup_centered()
	var state := {"done": false, "ok": false}
	dialog.confirmed.connect(func() -> void:
		state.ok = true
		state.done = true
	)
	dialog.canceled.connect(func() -> void:
		state.done = true
	)
	dialog.visibility_changed.connect(func() -> void:
		if not dialog.visible and not bool(state.done):
			state.done = true
	)
	while not state.done:
		await get_tree().process_frame
	dialog.queue_free()
	return bool(state.ok)


func _set_busy(on: bool) -> void:
	_busy = on
	if _search_btn:
		_search_btn.disabled = on
	_chain.disabled = on
	if not on and not _searching:
		_progress.value = 0
		_last_progress = -1
	_refresh_detail_actions()


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
		var fp := str((parsed as Dictionary).get("flashpoint_root", ""))
		if not fp.is_empty():
			fp_host.set_root(fp)
		if (parsed as Dictionary).has("view_grid"):
			_view_grid = bool((parsed as Dictionary).get("view_grid", true))
	if fp_host.root.is_empty():
		fp_host.autodetect()


func _save_config() -> void:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(
		JSON.stringify({"chain": chain, "flashpoint_root": fp_host.root, "view_grid": _view_grid})
	)
	file.close()
