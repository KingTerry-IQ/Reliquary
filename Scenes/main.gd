extends Control

const CONFIG_PATH := "user://flash.cfg"
const APP_NAME := "Reliquary"
const INSCRIBE_GUIDE := "This game stays permanently accessible."
const MISSING_RUNTIME := "MISSING RUNTIME"
## The operator's own collection, alongside Flashpoint's curated playlists.
const FAVORITES_ID := "favorites"
const FAVORITES_TITLE := "★ Favourites"
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
var flash: Flash
var spr: Spr
var packs: Packs
var flashpoint: Flashpoint
var tag_filter := TagFilter.new()
var cabinet: Cabinet
var shelf := Shelf.new()
var favorites := Favorites.new()

var chain: String = "mon"
var kindled: bool = false
var _busy: bool = false
var _last_progress: int = -1
var _job_base: String = ""
var _shot_ticket: int = 0
var _logo_ticket: int = 0
var _cabinet_logo_ticket: int = 0
var _archive_hits: Array = []
## Row the next repaint should land on instead of the top of the page; -1 to
## let it fall back to the first row, as a fresh search should.
var _archive_keep_row: int = -1
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
var _nav_btn: Button
var _page_in_navigator: bool = true
var _letter_bar: VBoxContainer
var _browse_letter: String = ""
var _letter_buttons: Dictionary = {}
var _meta_box: HFlowContainer
var _tag_box: HFlowContainer
var _shot_marquee: Label
var _shot_marquee_bg: ColorRect
var _log_btn: Button
var _log_open: bool = false
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
var _cabinet_cached: bool = false
var _cabinet_cached_btn: Button
var _cabinet_filter: LineEdit
var _cabinet_platform: OptionButton
var _cabinet_letters: VBoxContainer
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
var _detail_body: RichTextLabel
var _detail_cost: Label
var _guidance: Label
var _console: RichTextLabel
var _job: Label
var _progress: ProgressBar
var _inscribe_btn: Button
var _play_btn: Button
var _fav_btn: Button
var _drop_btn: Button
var _search_btn: Button
var _chain: OptionButton
var _authentic: bool = true
var _time_btn: Button
var _flash_first: bool = true
var _flash_btn: Button
var _safe_btn: Button
var _safe_menu: PopupMenu
var _player_veil: ColorRect
var _player_wait_label: Label
var _player_waiting: bool = false


func _ready() -> void:
	theme = TempleTheme.build()
	_load_config()
	shelf.load_index()
	favorites.load_index()
	_build_ui()
	var trial_bytes := Cartridge.wipe_trials()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://staging"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://cartridges"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://thumbs"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://trials"))
	if trial_bytes > 0:
		_log("Cleared trial cache (%s)." % Flashpoint.format_bytes(trial_bytes))

	iq = IQClient.new()
	add_child(iq)
	ruffle = Ruffle.new()
	add_child(ruffle)
	flash = Flash.new()
	add_child(flash)
	spr = Spr.new()
	add_child(spr)
	packs = Packs.new()
	add_child(packs)
	flashpoint = Flashpoint.new()
	add_child(flashpoint)
	add_child(tag_filter)
	httpd = LocalHttp.new()
	add_child(httpd)
	cabinet = Cabinet.new(iq, chain)

	## The runtime chips are built before these nodes exist, so they start amber.
	## Repaint now rather than after the host handshake, which may never land.
	_refresh_spr_chip()

	iq.host_missing.connect(_on_host_missing)
	_refresh_tag_filters()
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


func _unhandled_input(event: InputEvent) -> void:
	if _search == null or not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.keycode == KEY_SLASH and not _search.has_focus():
		_search.grab_focus()
		_search.select_all()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)

	var background := ColorRect.new()
	background.color = TempleTheme.BLACK
	background.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = SIZE_EXPAND_FILL
	root.size_flags_vertical = SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	root.add_child(_build_topbar())
	root.add_child(TempleTheme.rule(TempleTheme.YELLOW))

	var columns := HBoxContainer.new()
	columns.size_flags_horizontal = SIZE_EXPAND_FILL
	columns.size_flags_vertical = SIZE_EXPAND_FILL
	columns.clip_contents = true
	columns.add_theme_constant_override("separation", 10)
	root.add_child(columns)

	columns.add_child(_build_archive_column())
	columns.add_child(_build_stage())
	columns.add_child(_build_cabinet_column())

	root.add_child(_build_footer())
	_player_veil = ColorRect.new()
	_player_veil.color = Color(0, 0, 0, 0.78)
	_player_veil.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_player_veil.visible = false
	_player_veil.mouse_filter = Control.MOUSE_FILTER_STOP
	_player_veil.z_index = 70
	add_child(_player_veil)
	_player_wait_label = TempleTheme.line("LOADING PLAYER…", TempleTheme.YELLOW, TempleTheme.SIZE_DISPLAY)
	_player_wait_label.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_player_wait_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_player_wait_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player_veil.add_child(_player_wait_label)
	_apply_archive_view()
	_clear_detail()
	_log("Search the archive. Inscribe a title. Play what the chain already holds.")


func _build_topbar() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	bar.alignment = BoxContainer.ALIGNMENT_BEGIN

	var mark := TextureRect.new()
	if ResourceLoader.exists("res://icon.svg"):
		mark.texture = load("res://icon.svg")
	mark.custom_minimum_size = Vector2(40, 40)
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(mark)

	var brand := VBoxContainer.new()
	brand.size_flags_horizontal = SIZE_EXPAND_FILL
	brand.add_theme_constant_override("separation", 0)
	var title := TempleTheme.title(APP_NAME.to_upper())
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.clip_text = true
	brand.add_child(title)
	var tag := TempleTheme.line("PRESS  ·  CABINET  ·  PLAYER", TempleTheme.MUTED, TempleTheme.SIZE_SMALL)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	brand.add_child(tag)
	bar.add_child(brand)

	_host_label = _status_chip(bar, "HOST  …", TempleTheme.AMBER)
	_host_label.tooltip_text = "GodOnChain host. Writes need it; cached play does not."
	_ruffle_label = _status_chip(bar, "RUFFLE  …", TempleTheme.AMBER)
	_ruffle_label.tooltip_text = "Ruffle, the fallback Flash player. Latest stable desktop build."
	_root_label = _status_chip(bar, "ROOT  …", TempleTheme.AMBER)
	_root_label.tooltip_text = "Operator dbRoot on this chain. Inscribe is refused without it."
	_spr_label = _status_chip(bar, "SPR  …", TempleTheme.AMBER)
	_spr_label.tooltip_text = "Shockwave projector, fetched on demand."
	_nav_btn = Button.new()
	_nav_btn.focus_mode = Control.FOCUS_NONE
	_nav_btn.custom_minimum_size = Vector2(126, 0)
	_nav_btn.add_theme_font_size_override("font_size", TempleTheme.SIZE_SMALL)
	_nav_btn.pressed.connect(_toggle_page_host)
	bar.add_child(_nav_btn)
	_refresh_nav_chip()
	_flash_btn = Button.new()
	_flash_btn.focus_mode = Control.FOCUS_NONE
	_flash_btn.custom_minimum_size = Vector2(122, 0)
	_flash_btn.add_theme_font_size_override("font_size", TempleTheme.SIZE_SMALL)
	_flash_btn.pressed.connect(_toggle_flash_first)
	bar.add_child(_flash_btn)
	_paint_flash_chip()

	_safe_btn = Button.new()
	_safe_btn.focus_mode = Control.FOCUS_NONE
	_safe_btn.custom_minimum_size = Vector2(104, 0)
	_safe_btn.add_theme_font_size_override("font_size", TempleTheme.SIZE_SMALL)
	_safe_btn.pressed.connect(_open_safe_menu)
	bar.add_child(_safe_btn)
	_safe_menu = PopupMenu.new()
	_safe_menu.hide_on_checkable_item_selection = false
	_safe_menu.id_pressed.connect(_on_safe_menu)
	_safe_btn.add_child(_safe_menu)
	_paint_safe_chip()

	_time_btn = Button.new()
	_time_btn.focus_mode = Control.FOCUS_NONE
	_time_btn.custom_minimum_size = Vector2(108, 0)
	_time_btn.add_theme_font_size_override("font_size", TempleTheme.SIZE_SMALL)
	_time_btn.pressed.connect(_toggle_authentic)
	bar.add_child(_time_btn)
	_paint_time_chip()

	_chain = OptionButton.new()
	_chain.add_item("MON", 0)
	_chain.add_item("SOL", 1)
	_chain.add_item("RH", 2)
	_chain.select(_chain_index(chain))
	_chain.item_selected.connect(_on_chain_selected)
	_chain.custom_minimum_size = Vector2(84, 0)
	_chain.fit_to_longest_item = false
	_chain.clip_text = true
	_chain.tooltip_text = "Inscribe and play on this chain."
	_cap_option_popup(_chain, 100)
	bar.add_child(_chain)
	bar.add_child(TempleTheme.button("REFRESH", _on_refresh))
	return bar


func _paint_time_chip() -> void:
	if _time_btn == null:
		return
	var colour := TempleTheme.GREEN if _authentic else TempleTheme.AMBER
	_time_btn.text = "TIME  ERA" if _authentic else "TIME  NOW"
	_time_btn.tooltip_text = (
		"Throttle toward era hardware so titles don't race. Click for full modern speed."
		if _authentic
		else "Full modern speed. Click to throttle toward era hardware."
	)
	_time_btn.add_theme_color_override("font_color", colour)
	_time_btn.add_theme_color_override("font_hover_color", TempleTheme.BLACK)
	_time_btn.add_theme_color_override("font_pressed_color", TempleTheme.BLACK)
	_time_btn.add_theme_stylebox_override("normal", TempleTheme.chip_box(colour))
	_time_btn.add_theme_stylebox_override("hover", TempleTheme.chip_box(TempleTheme.WHITE))
	_time_btn.add_theme_stylebox_override("pressed", TempleTheme.chip_box(TempleTheme.YELLOW))


## Flashpoint's default for a Flash entry is the projector its applicationPath
## names; Ruffle is its secondary player. Match that, but let it be flipped.
func _paint_flash_chip() -> void:
	if _flash_btn == null:
		return
	var installed := flash != null and flash.has_runtime()
	var colour := TempleTheme.CYAN
	if _flash_first:
		colour = TempleTheme.GREEN if installed else TempleTheme.AMBER
	_flash_btn.text = "FLASH  PLAYER" if _flash_first else "FLASH  RUFFLE"
	_flash_btn.tooltip_text = (
		"Flashpoint's own Flash projector, the way Flashpoint runs it. Click for Ruffle."
		if _flash_first
		else "Ruffle, the open reimplementation. Click for Flashpoint's Flash projector."
	)
	_flash_btn.add_theme_color_override("font_color", colour)
	_flash_btn.add_theme_color_override("font_hover_color", TempleTheme.BLACK)
	_flash_btn.add_theme_color_override("font_pressed_color", TempleTheme.BLACK)
	_flash_btn.add_theme_stylebox_override("normal", TempleTheme.chip_box(colour))
	_flash_btn.add_theme_stylebox_override("hover", TempleTheme.chip_box(TempleTheme.WHITE))
	_flash_btn.add_theme_stylebox_override("pressed", TempleTheme.chip_box(TempleTheme.YELLOW))


## Flashpoint's tag filters. SHOW EXTREME is the master switch it ships off;
## the groups below it are the same seven the launcher lists.
func _paint_safe_chip() -> void:
	if _safe_btn == null:
		return
	var on := tag_filter.is_filtering()
	var colour := TempleTheme.GREEN if on else TempleTheme.MUTED
	_safe_btn.text = "SAFE  ON" if on else "SAFE  OFF"
	var names := tag_filter.active_names()
	_safe_btn.tooltip_text = (
		"Hiding: %s.\nFlashpoint's own tag filters. Tags are crowd-curated, so this is a filter, not a guarantee." % ", ".join(names)
		if on
		else "Nothing is hidden. Click to choose Flashpoint's tag filters."
	)
	_safe_btn.add_theme_color_override("font_color", colour)
	_safe_btn.add_theme_color_override("font_hover_color", TempleTheme.BLACK)
	_safe_btn.add_theme_color_override("font_pressed_color", TempleTheme.BLACK)
	_safe_btn.add_theme_stylebox_override("normal", TempleTheme.chip_box(colour))
	_safe_btn.add_theme_stylebox_override("hover", TempleTheme.chip_box(TempleTheme.WHITE))
	_safe_btn.add_theme_stylebox_override("pressed", TempleTheme.chip_box(TempleTheme.YELLOW))


func _open_safe_menu() -> void:
	if _safe_menu == null:
		return
	_safe_menu.clear()
	_safe_menu.add_check_item("Show extreme entries", 0)
	_safe_menu.set_item_checked(0, tag_filter.show_extreme)
	_safe_menu.set_item_tooltip(
		0, "Flashpoint ships this off. Off hides every group marked extreme."
	)
	_safe_menu.add_separator("Also hide")
	var i := 0
	for entry: Variant in tag_filter.groups:
		if not entry is Dictionary:
			continue
		var g: Dictionary = entry
		var name := str(g.get("name", ""))
		var id := 100 + i
		i += 1
		var label := name
		if bool(g.get("extreme", false)):
			## Already hidden while SHOW EXTREME is off, but still switchable so
			## the choice survives turning SHOW EXTREME on.
			label += "  ·  extreme" if tag_filter.show_extreme else "  ·  extreme (hidden)"
		_safe_menu.add_check_item(label, id)
		var idx := _safe_menu.get_item_index(id)
		_safe_menu.set_item_checked(idx, bool(g.get("enabled", false)))
		var why := str(g.get("description", ""))
		if not why.is_empty():
			_safe_menu.set_item_tooltip(idx, why)
	var at := _safe_btn.get_screen_position() + Vector2(0, _safe_btn.size.y)
	_safe_menu.popup(Rect2i(Vector2i(at), Vector2i(320, 0)))


func _on_safe_menu(id: int) -> void:
	if id == 0:
		tag_filter.set_show_extreme(not tag_filter.show_extreme)
	else:
		var i := id - 100
		if i < 0 or i >= tag_filter.groups.size():
			return
		var g: Dictionary = tag_filter.groups[i]
		tag_filter.set_enabled(str(g.get("name", "")), not bool(g.get("enabled", false)))
	_paint_safe_chip()
	_save_config()
	_open_safe_menu()
	var names := tag_filter.active_names()
	_log("Hiding %s." % (", ".join(names) if names.size() > 0 else "nothing"))
	_reapply_filter()


## Take the live tag lists from Flashpoint's configuration component. The
## built-in copy already works, so a failure here is a log line, not an error.
func _refresh_tag_filters() -> void:
	if not await tag_filter.ensure():
		_log("Tag filters: using the built-in lists (%s)" % tag_filter.last_error)
		return
	_paint_safe_chip()
	_log("Tag filters refreshed from Flashpoint (%d groups)." % tag_filter.groups.size())


## The archive pane lists filtered rows, so a change has to repaint it.
func _reapply_filter() -> void:
	if _archive == null:
		return
	_on_search()


func _toggle_flash_first() -> void:
	_flash_first = not _flash_first
	_paint_flash_chip()
	_save_config()
	_log("Flash entries play in %s." % ("Flash Player" if _flash_first else "Ruffle"))


func _toggle_authentic() -> void:
	_authentic = not _authentic
	_paint_time_chip()
	_save_config()
	_log("Time %s." % ("era" if _authentic else "modern"))


func _throttle_mhz(meta: Dictionary) -> int:
	return Unzip.era_mhz(
		meta, str(meta.get("launch", meta.get("launchCommand", ""))), _authentic
	)


func _prepare_throttle(meta: Dictionary) -> String:
	if _throttle_mhz(meta) <= 0:
		return ""
	if packs.oldcpu_exe().is_empty():
		_set_job("Fetching era-speed helper…")
		await packs.ensure_oldcpu(_on_progress, _recover_download)
	return packs.oldcpu_exe()


func _status_chip(bar: Control, text: String, colour: Color) -> Label:
	var label := TempleTheme.cell(text, colour, TempleTheme.SIZE_SMALL)
	label.size_flags_horizontal = Control.SIZE_SHRINK_END
	label.custom_minimum_size = Vector2(108, 0)
	bar.add_child(TempleTheme.wrap_chip(label, colour))
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
	box.add_child(TempleTheme.rule(TempleTheme.YELLOW))

	var search_row := HBoxContainer.new()
	search_row.add_theme_constant_override("separation", 8)
	box.add_child(search_row)
	_search = LineEdit.new()
	_search.placeholder_text = "search  ·  title:  dev:  tag:"
	_search.tooltip_text = "Bowman   or   title:Alien  tag:Arcade  dev:\"Tom Fulp\""
	_search.size_flags_horizontal = SIZE_EXPAND_FILL
	_search.text_submitted.connect(func(_t: String) -> void: _on_search())
	search_row.add_child(_search)
	_library = OptionButton.new()
	_library.add_item("GAMES", 0)
	_library.add_item("ANIMS", 1)
	_library.select(0)
	_library.custom_minimum_size = Vector2(88, 0)
	_library.fit_to_longest_item = false
	_library.clip_text = true
	_library.tooltip_text = "Games or animations."
	_library.item_selected.connect(func(_i: int) -> void: _on_search())
	_cap_option_popup(_library, 120)
	search_row.add_child(_library)
	_search_btn = TempleTheme.primary_button("SEARCH", _on_search)
	search_row.add_child(_search_btn)
	_view_btn = TempleTheme.button("LIST", _toggle_view)
	_view_btn.tooltip_text = "Switch between poster grid and a text list."
	search_row.add_child(_view_btn)

	var filters := VBoxContainer.new()
	filters.add_theme_constant_override("separation", 4)
	box.add_child(filters)
	_playlist = _facet_option(0)
	## All Games, then the operator's own collection, then the curated ones.
	for spec: Variant in Flashpoint.PLAYLISTS:
		var rec: Dictionary = spec
		var id := str(rec.get("id", ""))
		_playlist.add_item(str(rec.get("title", id if not id.is_empty() else "?")))
		_playlist.set_item_metadata(_playlist.item_count - 1, id)
		if id == "all":
			_playlist.add_item(FAVORITES_TITLE)
			_playlist.set_item_metadata(_playlist.item_count - 1, FAVORITES_ID)
	_playlist.select(0)
	_playlist.item_selected.connect(_on_playlist_selected)
	filters.add_child(_playlist)
	var facets := GridContainer.new()
	facets.columns = 2
	facets.add_theme_constant_override("h_separation", 6)
	facets.add_theme_constant_override("v_separation", 4)
	facets.size_flags_horizontal = SIZE_EXPAND_FILL
	filters.add_child(facets)
	_filter_dev = _make_facet("Developer", "dev")
	_filter_pub = _make_facet("Publisher", "pub")
	_filter_series = _make_facet("Series", "series")
	_filter_tag = _make_facet("Tags", "tag")
	facets.add_child(_filter_dev)
	facets.add_child(_filter_pub)
	facets.add_child(_filter_series)
	facets.add_child(_filter_tag)

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

	var body := HBoxContainer.new()
	body.size_flags_horizontal = SIZE_EXPAND_FILL
	body.size_flags_vertical = SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 4)
	box.add_child(body)

	_letter_bar = VBoxContainer.new()
	_letter_bar.add_theme_constant_override("separation", 0)
	_letter_bar.custom_minimum_size = Vector2(26, 0)
	body.add_child(_letter_bar)
	_fill_letter_bar()
	body.add_child(TempleTheme.rule(TempleTheme.DARK_GREY, true))

	var stack := Control.new()
	stack.size_flags_horizontal = SIZE_EXPAND_FILL
	stack.size_flags_vertical = SIZE_EXPAND_FILL
	stack.clip_contents = true
	body.add_child(stack)

	_archive = _make_list()
	_archive.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_archive.item_selected.connect(_on_archive_selected)
	_archive.item_activated.connect(func(_i: int) -> void: _on_play())
	stack.add_child(_archive)
	_apply_archive_view()

	_archive_empty = _empty_label("Games, anims, a playlist, A–Z, or a search.")
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
	_inscribed_header.add_theme_color_override("font_color", TempleTheme.CYAN)
	box.add_child(_inscribed_header)
	box.add_child(TempleTheme.rule(TempleTheme.CYAN))

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
	_cabinet_cached_btn = TempleTheme.button("CACHE", _on_cabinet_cached)
	_cabinet_cached_btn.tooltip_text = "Show only titles with a local Play cache."
	cab_row.add_child(_cabinet_cached_btn)

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

	var body := HBoxContainer.new()
	body.size_flags_horizontal = SIZE_EXPAND_FILL
	body.size_flags_vertical = SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 4)
	box.add_child(body)

	_cabinet_letters = VBoxContainer.new()
	_cabinet_letters.add_theme_constant_override("separation", 0)
	_cabinet_letters.custom_minimum_size = Vector2(26, 0)
	body.add_child(_cabinet_letters)
	_fill_cabinet_letters()
	body.add_child(TempleTheme.rule(TempleTheme.DARK_GREY, true))

	var stack := Control.new()
	stack.size_flags_horizontal = SIZE_EXPAND_FILL
	stack.size_flags_vertical = SIZE_EXPAND_FILL
	stack.clip_contents = true
	body.add_child(stack)

	_inscribed_list = _make_list()
	_inscribed_list.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_inscribed_list.item_selected.connect(_on_inscribed_selected)
	_inscribed_list.item_activated.connect(func(_i: int) -> void: _on_play())
	_inscribed_list.item_clicked.connect(_on_inscribed_clicked)
	stack.add_child(_inscribed_list)

	_inscribed_empty = _empty_label("Nothing inscribed\non this chain yet.")
	stack.add_child(_inscribed_empty)
	return panel


func _build_stage() -> Control:
	var panel := TempleTheme.panel()
	panel.size_flags_stretch_ratio = 1.6
	var inner := _padded()
	panel.add_child(inner)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	inner.add_child(box)

	box.add_child(TempleTheme.header("STAGE"))
	box.add_child(TempleTheme.rule(TempleTheme.YELLOW))

	var crt := TempleTheme.screen()
	crt.size_flags_stretch_ratio = 1.7
	crt.custom_minimum_size = Vector2(0, 220)
	box.add_child(crt)

	var shot_wrap := Control.new()
	shot_wrap.size_flags_horizontal = SIZE_EXPAND_FILL
	shot_wrap.size_flags_vertical = SIZE_EXPAND_FILL
	crt.add_child(shot_wrap)

	var frame := ColorRect.new()
	frame.color = Color("080808")
	frame.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	shot_wrap.add_child(frame)

	_shot = TextureRect.new()
	_shot.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_shot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	shot_wrap.add_child(_shot)

	var scan := TextureRect.new()
	scan.texture = TempleTheme.scan_texture()
	scan.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scan.stretch_mode = TextureRect.STRETCH_TILE
	scan.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	scan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shot_wrap.add_child(scan)

	_shot_empty = TempleTheme.line("NO CARTRIDGE SELECTED", TempleTheme.MUTED, TempleTheme.SIZE_SMALL)
	_shot_empty.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_shot_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	shot_wrap.add_child(_shot_empty)

	_shot_marquee_bg = ColorRect.new()
	_shot_marquee_bg.color = Color(0, 0, 0, 0.82)
	_shot_marquee_bg.set_anchors_and_offsets_preset(PRESET_BOTTOM_WIDE)
	_shot_marquee_bg.offset_top = -26
	_shot_marquee_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shot_marquee_bg.visible = false
	shot_wrap.add_child(_shot_marquee_bg)
	_shot_marquee = TempleTheme.cell("", TempleTheme.YELLOW, TempleTheme.SIZE_SMALL)
	_shot_marquee.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shot_marquee.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_shot_marquee.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_shot_marquee_bg.add_child(_shot_marquee)

	_detail_chip = TempleTheme.cell("", TempleTheme.CYAN, TempleTheme.SIZE_SMALL)
	box.add_child(_detail_chip)

	_detail_title = TempleTheme.line("", TempleTheme.YELLOW, TempleTheme.SIZE_DISPLAY)
	_detail_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_detail_title.clip_text = true
	_detail_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(_detail_title)

	_meta_box = HFlowContainer.new()
	_meta_box.add_theme_constant_override("h_separation", 6)
	_meta_box.add_theme_constant_override("v_separation", 4)
	box.add_child(_meta_box)

	_detail_body = RichTextLabel.new()
	_detail_body.fit_content = false
	_detail_body.scroll_following = false
	_detail_body.bbcode_enabled = false
	_detail_body.size_flags_vertical = SIZE_EXPAND_FILL
	_detail_body.size_flags_stretch_ratio = 0.45
	_detail_body.custom_minimum_size = Vector2(0, 56)
	box.add_child(_detail_body)

	_tag_box = HFlowContainer.new()
	_tag_box.add_theme_constant_override("h_separation", 6)
	_tag_box.add_theme_constant_override("v_separation", 4)
	box.add_child(_tag_box)

	var cost_row := HBoxContainer.new()
	cost_row.add_theme_constant_override("separation", 8)
	box.add_child(cost_row)
	_detail_cost = TempleTheme.line("", TempleTheme.AMBER, TempleTheme.SIZE_SMALL)
	_detail_cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_detail_cost.size_flags_horizontal = SIZE_EXPAND_FILL
	cost_row.add_child(_detail_cost)
	_drop_btn = TempleTheme.quiet_button("DROP CACHE", _on_drop_cache)
	_drop_btn.tooltip_text = "Delete this title's extracted Play cache. The chain copy stays."
	_drop_btn.visible = false
	cost_row.add_child(_drop_btn)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	box.add_child(actions)
	_inscribe_btn = TempleTheme.primary_button("INSCRIBE", _on_inscribe)
	_play_btn = TempleTheme.button("PLAY", _on_play)
	_fav_btn = TempleTheme.button("FAVOURITE", _on_toggle_favorite)
	_inscribe_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	_play_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	_fav_btn.custom_minimum_size = Vector2(132, 0)
	actions.add_child(_inscribe_btn)
	actions.add_child(_play_btn)
	actions.add_child(_fav_btn)
	_paint_fav_btn()
	return panel


func _build_footer() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	box.add_child(TempleTheme.rule(TempleTheme.DARK_GREY))

	var job_row := HBoxContainer.new()
	job_row.add_theme_constant_override("separation", 10)
	box.add_child(job_row)
	_progress = ProgressBar.new()
	_progress.min_value = 0
	_progress.max_value = 100
	_progress.value = 0
	_progress.show_percentage = false
	_progress.custom_minimum_size = Vector2(0, 12)
	_progress.size_flags_horizontal = SIZE_EXPAND_FILL
	_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	job_row.add_child(_progress)
	_job = TempleTheme.cell("Ready.", TempleTheme.MUTED, TempleTheme.SIZE_SMALL)
	_job.custom_minimum_size = Vector2(240, 0)
	job_row.add_child(_job)
	_log_btn = TempleTheme.button("LOG  +", _toggle_log)
	_log_btn.tooltip_text = "Show or hide the console."
	job_row.add_child(_log_btn)

	_guidance = TempleTheme.line(
		INSCRIBE_GUIDE,
		TempleTheme.AMBER,
		TempleTheme.SIZE_SMALL
	)
	_guidance.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(_guidance)

	_console = RichTextLabel.new()
	_console.fit_content = false
	_console.scroll_following = true
	_console.bbcode_enabled = false
	_console.custom_minimum_size = Vector2(0, 88)
	_console.size_flags_vertical = Control.SIZE_SHRINK_END
	_console.visible = false
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
	list.fixed_icon_size = Vector2i(80, 80)
	list.same_column_width = true
	list.auto_width = false
	list.auto_height = false
	list.clip_contents = true
	list.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return list


func _facet_option(width: int) -> OptionButton:
	var btn := OptionButton.new()
	if width > 0:
		btn.custom_minimum_size = Vector2(width, 0)
	btn.size_flags_horizontal = SIZE_EXPAND_FILL
	btn.fit_to_longest_item = false
	btn.clip_text = true
	_cap_option_popup(btn, 280)
	return btn


func _cap_option_popup(btn: OptionButton, max_width: int) -> void:
	var pop := btn.get_popup()
	pop.max_size = Vector2i(max_width, 360)
	pop.hide_on_item_selection = true


func _apply_archive_view() -> void:
	_apply_list_view(_archive)
	_apply_list_view(_inscribed_list)
	if _view_btn:
		_view_btn.text = "LIST" if _view_grid else "GRID"


func _apply_list_view(list: ItemList) -> void:
	if list == null:
		return
	if _view_grid:
		list.icon_mode = ItemList.ICON_MODE_TOP
		list.fixed_icon_size = Vector2i(80, 80)
		list.max_columns = 0
		list.fixed_column_width = 108
		list.max_text_lines = 2
	else:
		list.icon_mode = ItemList.ICON_MODE_LEFT
		list.fixed_icon_size = Vector2i(40, 40)
		list.max_columns = 1
		list.fixed_column_width = 0
		list.max_text_lines = 1


func _toggle_view() -> void:
	_view_grid = not _view_grid
	_apply_archive_view()
	_save_config()
	for i in _archive.item_count:
		var rec: Variant = _archive.get_item_metadata(i)
		if rec is Dictionary:
			_archive.set_item_text(i, _archive_label(rec))
	if _inscribed_list == null:
		return
	for i in _inscribed_list.item_count:
		var rec: Variant = _inscribed_list.get_item_metadata(i)
		if rec is Dictionary:
			_inscribed_list.set_item_text(i, _cabinet_label(rec))


func _archive_label(rec: Dictionary) -> String:
	## A star in front of the title, so a favourite is obvious while browsing
	## the whole archive and not just inside the collection.
	var star := "★ " if favorites.has(rec) else ""
	if _view_grid:
		return star + str(rec.get("title", "?"))
	return star + _list_line(rec)


func _placeholder_icon() -> Texture2D:
	if _placeholder_tex != null:
		return _placeholder_tex
	var img := Image.create(80, 80, false, Image.FORMAT_RGBA8)
	img.fill(Color("080808"))
	var edge := TempleTheme.YELLOW
	var notch := TempleTheme.DARK_GREY
	for x in 80:
		img.set_pixel(x, 0, edge)
		img.set_pixel(x, 79, edge)
		img.set_pixel(x, 18, notch)
	for y in 80:
		img.set_pixel(0, y, edge)
		img.set_pixel(79, y, edge)
	for x in range(28, 52):
		img.set_pixel(x, 70, edge)
		img.set_pixel(x, 71, edge)
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
	## A new collection opens whole: the search and facets were aimed at the
	## list we just left, and carrying them over hides most of this one.
	_clear_filters()
	_on_search()


func _select_playlist(id: String) -> void:
	var next := id.strip_edges()
	if next.is_empty():
		next = "all"
	_playlist_id = next
	if _playlist == null:
		return
	_facet_guard = true
	for i in _playlist.item_count:
		if str(_playlist.get_item_metadata(i)) == next:
			_playlist.select(i)
			break
	_facet_guard = false


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
	for name in _facet_names(raw):
		into[name] = true


func _facet_names(raw: Variant) -> PackedStringArray:
	var out: PackedStringArray = []
	if raw is Array:
		for item: Variant in raw:
			for name in _facet_names(item):
				out.append(name)
		return out
	var text := str(raw).strip_edges()
	if text.is_empty() or text == "[]":
		return out
	for chunk in text.replace(";", ",").split(","):
		var name := chunk.strip_edges()
		if not name.is_empty():
			out.append(name)
	return out


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
	var label := TempleTheme.line(text, TempleTheme.MUTED, TempleTheme.SIZE_SMALL)
	label.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _connect_host() -> void:
	if await iq.discover(APP_NAME):
		TempleTheme.paint_chip(_host_label, "HOST  OK", TempleTheme.GREEN)
	else:
		_on_host_missing(iq.last_error)


func _on_host_missing(reason: String) -> void:
	TempleTheme.paint_chip(_host_label, "HOST  OFF", TempleTheme.BRIGHT_RED)
	kindled = false
	_update_root_chip()
	_log(reason)


func _ensure_ruffle() -> void:
	TempleTheme.paint_chip(_ruffle_label, "RUFFLE  …", TempleTheme.AMBER)
	_set_job("Fetching Ruffle…")
	var ok := await ruffle.ensure(_recover_download)
	if ok:
		TempleTheme.paint_chip(_ruffle_label, "RUFFLE  %s" % ruffle.tag, TempleTheme.GREEN)
		_set_job("Ready.")
	else:
		TempleTheme.paint_chip(_ruffle_label, "RUFFLE  OFF", TempleTheme.BRIGHT_RED)
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
		TempleTheme.paint_chip(_root_label, "ROOT  —", TempleTheme.MUTED)
		return
	if kindled:
		TempleTheme.paint_chip(_root_label, "ROOT  %s" % chain.to_upper(), TempleTheme.GREEN)
	else:
		TempleTheme.paint_chip(_root_label, "ROOT  WAIT", TempleTheme.AMBER)


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
	if flashpoint == null:
		return
	_search_ticket += 1
	var ticket := _search_ticket
	_set_busy(true)
	var q := _composed_query()
	if _playlist_id != "all":
		await _load_playlist(ticket)
		return
	var limit := 0
	var library := _library_filter()
	if q.is_empty() and _browse_letter.is_empty():
		if not flashpoint.has_catalog(library):
			_set_searching(true, "Loading %s…" % _library_all_title())
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
	_log(_search_log_line(q if not q.is_empty() else _library_all_title()))
	var found: Array = await flashpoint.search(q, library, limit, "", false, Flashpoint.LIST_FIELDS)
	if ticket != _search_ticket:
		return
	_show_search_hits(found)


func _warmup_catalog() -> void:
	_warm_lib = _library_filter()
	_warm_done = false
	_warm_rows = []
	if flashpoint.has_catalog(_warm_lib):
		_set_job("Opening catalog…")
		_warm_rows = await flashpoint.load_catalog_async(_warm_lib)
		_warm_done = true
		if _still_all_games(_warm_lib) and _archive_hits.is_empty() and not _warm_rows.is_empty():
			_show_search_hits(_warm_rows, true)
		if not flashpoint.catalog_is_fresh(_warm_lib):
			_refresh_catalog_background(_warm_lib)
		return
	_set_searching(true, "Loading %s…" % _library_all_title())
	var first: Array = await flashpoint.search("", _warm_lib, PAGE_SIZE, "", false, Flashpoint.LIST_FIELDS)
	_warm_rows = first
	_warm_done = true
	if _still_all_games(_warm_lib) and not first.is_empty():
		_show_search_hits(first)
	_set_job("%d titles on this page. Fetching the full catalog…" % first.size())
	var rest: Array = await flashpoint.search("", _warm_lib, 0, "", false, Flashpoint.LIST_FIELDS)
	if rest.size() > first.size():
		await flashpoint.save_catalog_async(_warm_lib, rest)
		_warm_rows = rest
		if _still_all_games(_warm_lib):
			_show_search_hits(rest, true)


func _refresh_catalog_background(library: String) -> void:
	_set_job("%d titles. Checking for updates…" % _warm_rows.size())
	var fresh: Array = await flashpoint.search("", library, 0, "", false, Flashpoint.LIST_FIELDS)
	if fresh.size() <= 1000:
		return
	await flashpoint.save_catalog_async(library, fresh)
	_warm_rows = fresh
	if _still_all_games(library):
		var keep := _archive_page
		var row := _archive_row()
		_show_search_hits(fresh, true)
		_archive_page = keep
		_archive_keep_row = row
		_paint_archive_page()


## Favourites are already on disk, so the collection opens without the network
## and without the catalog — the point of keeping the row when it was marked.
func _load_favorites(ticket: int) -> void:
	_set_searching(true, "Loading  favourites")
	var rows := favorites.rows_merged(_warm_rows if _still_all_games(_library_filter()) else [])
	if ticket != _search_ticket:
		return
	_set_searching(false)
	if rows.is_empty():
		_archive_keep_row = -1
		_set_busy(false)
		_archive.clear()
		_archive_hits = []
		_archive_header.text = "ARCHIVE  ·  %s" % FAVORITES_TITLE
		_archive_empty.visible = true
		if _page_row:
			_page_row.visible = false
		var why := "No favourites yet. Pick a title and press FAVOURITE."
		_set_job(why)
		_log(why)
		return
	_show_search_hits(rows, true)


func _load_playlist(ticket: int) -> void:
	if _playlist_id == FAVORITES_ID:
		await _load_favorites(ticket)
		return
	var title := _playlist_title()
	_set_searching(true, "Loading  %s" % title)
	_log("Playlist %s…" % title)
	_set_job("Opening %s…" % title)
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
	var hits: Array = await _playlist_from_catalog(ids, ticket)
	if ticket != _search_ticket:
		return
	var missing: PackedStringArray = Flashpoint.missing_ids(hits, ids)
	if not missing.is_empty():
		_set_job("%s  %d / %d" % [title, hits.size(), ids.size()])
		var fetched: Array = await flashpoint.search_ids(missing, func(have: int, total: int) -> void:
			if ticket == _search_ticket:
				_set_job("%s  %d / %d" % [title, hits.size() + have, ids.size()])
		)
		if ticket != _search_ticket:
			return
		if not fetched.is_empty():
			hits = Flashpoint.rows_for_ids(hits + fetched, ids)
	if ticket != _search_ticket:
		return
	_show_search_hits(hits)


func _playlist_from_catalog(ids: PackedStringArray, ticket: int) -> Array:
	if not _warm_done and not _warm_lib.is_empty():
		while not _warm_done:
			if ticket != _search_ticket:
				return []
			await get_tree().process_frame
	var hits := Flashpoint.rows_for_ids(_warm_rows, ids)
	if hits.size() >= ids.size():
		return hits
	var tried := {}
	if not _warm_lib.is_empty() and _warm_rows.size() > PAGE_SIZE:
		tried[_warm_lib] = true
	for lib in ["arcade", "theatre"]:
		if tried.has(lib):
			continue
		if not flashpoint.has_catalog(lib):
			continue
		var extra: Array = await flashpoint.load_catalog_async(lib)
		tried[lib] = true
		if extra.is_empty():
			continue
		var more := Flashpoint.rows_for_ids(extra, ids)
		if more.is_empty():
			continue
		hits = Flashpoint.rows_for_ids(hits + more, ids)
		if hits.size() >= ids.size():
			return hits
	return hits


func _load_all_games(ticket: int, library: String) -> void:
	if library == _warm_lib:
		while not _warm_done:
			if ticket != _search_ticket:
				return
			await get_tree().process_frame
		if not _warm_rows.is_empty():
			_show_search_hits(_warm_rows, true)
			return
	_log("%s — local index first, same idea as Flashpoint’s on-disk database." % _library_all_title())
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
	if _still_all_games(library):
		_show_search_hits(rest, true)


func _still_all_games(library: String) -> bool:
	return (
		_playlist_id == "all"
		and _composed_query().is_empty()
		and _browse_letter.is_empty()
		and _library_filter() == library
	)


func _show_search_hits(hits: Array, already_sorted: bool = false) -> void:
	_set_searching(false)
	_set_busy(false)
	var before := hits.size()
	hits = tag_filter.apply(hits)
	var hidden := before - hits.size()
	hits = _filter_browse(hits)
	if not already_sorted and hits.size() <= 8000:
		Flashpoint.sort_titles(hits)
	_archive_hits = hits
	_archive_page = 0
	if hits.is_empty():
		_archive_keep_row = -1
		var why := flashpoint.last_error if not flashpoint.last_error.is_empty() else "Nothing matched."
		if hidden > 0:
			why = "All %d matches are hidden by tag filters." % hidden
		_archive.clear()
		_archive_header.text = "ARCHIVE"
		_archive_empty.visible = true
		if _page_row:
			_page_row.visible = false
		_set_job(why)
		_log(why)
		return
	_paint_archive_page()
	var line := "%d titles." % hits.size()
	if hidden > 0:
		line += "  %d hidden by tag filters." % hidden
	_set_job(line)
	_log(line)
	_harvest_facets(hits)


func _paint_archive_page() -> void:
	## Consumed here so a stale request cannot leak into the next repaint.
	var keep := _archive_keep_row
	_archive_keep_row = -1
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
		head += "  ·  %s" % _library_all_title().to_upper()
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
		## Landing on the row we were already on: a repaint the operator did not
		## ask for — marking a favourite, a catalog refresh — should not throw
		## them back to the top of the list.
		var row := 0 if keep < 0 else clampi(keep, 0, _archive.item_count - 1)
		_archive.select(row)
		_archive.ensure_current_is_visible()
		_on_archive_selected(row)


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
	_set_marquee(_detail_title.text)
	_detail_chip.text = "INSCRIBED" if inscribed else "AVAILABLE"
	_detail_chip.add_theme_color_override(
		"font_color", TempleTheme.CYAN if inscribed else TempleTheme.GREEN
	)
	_fill_credits(rec)
	_detail_body.text = _description(rec)
	_fill_tags(rec)
	_preview_bytes = -1
	if inscribed:
		_detail_cost.text = "Already on this chain. Play it.\n%s" % _cache_cost_line(_selected_table)
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
	_set_marquee(title)
	_detail_chip.text = "ON CHAIN  ·  %s" % chain.to_upper()
	_detail_chip.add_theme_color_override("font_color", TempleTheme.CYAN)
	var uuid := str(meta.get("uuid", ""))
	_fill_credits(meta)
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
				"On-chain GameZIP %s. %s"
				% [Flashpoint.format_bytes(n), _cache_cost_line(table)]
			)
		else:
			_detail_cost.text = _cache_cost_line(table)
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
	_set_marquee("")
	_detail_chip.text = ""
	_fill_credits({}, "The stage shows art, credits, and the action for whatever you pick.")
	_detail_body.text = ""
	_detail_cost.text = ""
	_preview_bytes = -1
	_clear_tags()
	_shot.texture = null
	_shot_empty.text = "NO CARTRIDGE SELECTED"
	_shot_empty.visible = true
	_refresh_detail_actions()


func _set_marquee(text: String) -> void:
	if _shot_marquee == null:
		return
	_shot_marquee.text = text
	if _shot_marquee_bg:
		_shot_marquee_bg.visible = not text.is_empty()


func _fill_credits(rec: Dictionary, empty_msg: String = "") -> void:
	_clear_credits()
	if _meta_box == null:
		return
	if rec.is_empty() and not empty_msg.is_empty():
		var hint := TempleTheme.line(empty_msg, TempleTheme.GREY, TempleTheme.SIZE_SMALL)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_meta_box.add_child(hint)
		return
	var plat := Flashpoint.platform_label(rec)
	if plat != "Unknown":
		_meta_add_label(plat)
	_meta_add_facet("developer", "dev", "Developer", rec)
	_meta_add_facet("publisher", "pub", "Publisher", rec)
	_meta_add_facet("series", "series", "Series", rec)
	var date := str(rec.get("releaseDate", "")).strip_edges()
	if not date.is_empty():
		_meta_add_label(date)


func _meta_add_sep() -> void:
	if _meta_box.get_child_count() == 0:
		return
	var sep := TempleTheme.line("·", TempleTheme.DARK_GREY, TempleTheme.SIZE_SMALL)
	sep.autowrap_mode = TextServer.AUTOWRAP_OFF
	sep.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	sep.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_meta_box.add_child(sep)


func _meta_add_label(text: String) -> void:
	_meta_add_sep()
	var label := TempleTheme.line(text, TempleTheme.GREY, TempleTheme.SIZE_SMALL)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_meta_box.add_child(label)


func _meta_add_facet(field: String, kind: String, title: String, rec: Dictionary) -> void:
	for name in _facet_names(rec.get(field, "")):
		_meta_add_sep()
		var b := TempleTheme.tag_button(name, _search_facet.bind(kind, name))
		b.tooltip_text = "%s  ·  search archive" % title
		_meta_box.add_child(b)


func _clear_credits() -> void:
	_clear_box(_meta_box)


func _description(rec: Dictionary) -> String:
	var text := str(rec.get("originalDescription", rec.get("notes", ""))).strip_edges()
	if text.is_empty():
		return "No description in the archive record."
	return text


func _library_filter() -> String:
	if _library != null and _library.selected == 1:
		return "theatre"
	return "arcade"


func _library_all_title() -> String:
	return "All Anims" if _library_filter() == "theatre" else "All Games"


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
		var b := TempleTheme.index_button(letter, TempleTheme.YELLOW)
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
			b.add_theme_stylebox_override(
				"normal", TempleTheme._box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 1, 0, 0)
			)
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
		return "Browsing %s…" % _library_all_title()
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
		if n >= 8:
			break
		var label := str(t).strip_edges()
		if label.is_empty():
			continue
		_tag_box.add_child(TempleTheme.tag_button(label, _search_facet.bind("tag", label)))
		n += 1


func _clear_tags() -> void:
	_clear_box(_tag_box)


func _clear_box(box: Container) -> void:
	if box == null:
		return
	for child in box.get_children():
		box.remove_child(child)
		child.free()


## Every narrowing control at once. A filter belongs to the list it was typed
## against, so opening a different collection — or jumping to a facet — starts
## from the whole thing instead of inheriting the last search.
func _clear_filters() -> void:
	_sel_dev = ""
	_sel_pub = ""
	_sel_series = ""
	_sel_tag = ""
	if _filter_dev:
		_filter_dev.set_value("")
	if _filter_pub:
		_filter_pub.set_value("")
	if _filter_series:
		_filter_series.set_value("")
	if _filter_tag:
		_filter_tag.set_value("")
	if _search:
		_search.text = ""
	if not _browse_letter.is_empty():
		_browse_letter = ""
		_paint_letters()


func _search_facet(kind: String, value: String) -> void:
	var v := value.strip_edges()
	_clear_filters()
	_select_playlist("all")
	match kind:
		"dev":
			_sel_dev = v
			if _filter_dev:
				_filter_dev.set_value(v)
		"pub":
			_sel_pub = v
			if _filter_pub:
				_filter_pub.set_value(v)
		"series":
			_sel_series = v
			if _filter_series:
				_filter_series.set_value(v)
		"tag":
			_sel_tag = v
			if _filter_tag:
				_filter_tag.set_value(v)
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
	_guidance.text = "%s %s" % [INSCRIBE_GUIDE, Costs.quote_inscribe(chain, n)]


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
	_paint_fav_btn()
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
	if FlashpointHost.needs_flashpoint(_selected_entry):
		_play_btn.tooltip_text = "Fetches the plugin runtime, then plays from this cartridge."
	else:
		_play_btn.tooltip_text = ""
	var cached := not _selected_table.is_empty() and Cartridge.has_play_cache(_selected_table)
	if _drop_btn:
		_drop_btn.visible = cached
		_drop_btn.disabled = _busy or not cached
		_drop_btn.tooltip_text = "Delete this title's extracted Play cache. The chain copy stays."


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
		_guidance.text = "%s %s" % [INSCRIBE_GUIDE, quote]
		_log("%s — %s" % [Flashpoint.format_bytes(_preview_bytes), quote])
		if not await _confirm(
			(
				"%s\n\nGameZIP %s\n%s\n\nInscribe “%s” on %s?"
				% [
					INSCRIBE_GUIDE,
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
		_guidance.text = "%s %s" % [INSCRIBE_GUIDE, quote]
		_log(quote)
		if not await _confirm(
			(
				"%s\n\n%s\n\nInscribe “%s” on %s?"
				% [INSCRIBE_GUIDE, quote, str(entry.get("title", uuid)), chain.to_upper()]
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


func _on_drop_cache() -> void:
	if _busy:
		return
	var table := _selected_table.strip_edges()
	if table.is_empty() or not Cartridge.has_play_cache(table):
		_log("No local Play cache for this title.")
		return
	var title := str(_selected_entry.get("title", table)).strip_edges()
	if title.is_empty():
		title = table
	if not await _confirm(
		(
			"Delete the local Play cache for “%s”?\n\nThe chain still holds the GameZIP. Play will fetch it again."
			% title
		),
		"DROP CACHE"
	):
		_set_job("Drop cache cancelled.")
		return
	var n := Cartridge.drop_play_cache(table)
	shelf.forget(table)
	_log("Dropped Play cache for %s (%s)." % [table, Flashpoint.format_bytes(n)])
	_set_job("Dropped Play cache (%s)." % Flashpoint.format_bytes(n))
	if _selected_kind == "inscribed":
		_fill_detail_from_inscribed(_selected_table, _selected_entry)
	elif _selected_kind == "archive":
		_fill_detail_from_archive(_selected_entry)
	else:
		_refresh_detail_actions()
	_paint_cabinet()


func _trial_play(entry: Dictionary) -> void:
	if not flashpoint.playable_here(entry):
		_log("That title is not a GameZIP we can download.")
		return
	var uuid := str(entry.get("id", "")).strip_edges()
	if uuid.is_empty():
		_log("Entry has no id.")
		return
	_set_busy(true)
	_last_progress = -1
	if ruffle.exe_path.is_empty() and not FlashpointHost.needs_shockwave(entry):
		await ruffle.ensure(_recover_download)
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
		await ruffle.ensure(_recover_download)
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
		TempleTheme.paint_chip(
			_spr_label,
			"SPR  %s" % (spr.tag if not spr.tag.is_empty() else "OK"),
			TempleTheme.GREEN
		)
	else:
		TempleTheme.paint_chip(_spr_label, "SPR  —", TempleTheme.AMBER)
	_paint_flash_chip()
	_refresh_nav_chip()


## Flashpoint opens pages in its own Navigator; ours can instead hand them to
## the installed browser, which is newer but is not what the archive expects.
func _refresh_nav_chip() -> void:
	if _nav_btn == null:
		return
	var installed := packs != null and packs.has_navigator()
	var colour := TempleTheme.CYAN
	if _page_in_navigator:
		colour = TempleTheme.GREEN if installed else TempleTheme.AMBER
	_nav_btn.text = "NAV  FLASHPOINT" if _page_in_navigator else "NAV  BROWSER"
	_nav_btn.tooltip_text = (
		"Pages open in Flashpoint Navigator, the way Flashpoint opens them. Fetched on first use (58 MB). Click to use this machine's browser."
		if _page_in_navigator
		else "Pages open in the installed browser. Newer engine, but not the one the archive was curated against. Click for Flashpoint Navigator."
	)
	_nav_btn.add_theme_color_override("font_color", colour)
	_nav_btn.add_theme_color_override("font_hover_color", TempleTheme.BLACK)
	_nav_btn.add_theme_color_override("font_pressed_color", TempleTheme.BLACK)
	_nav_btn.add_theme_stylebox_override("normal", TempleTheme.chip_box(colour))
	_nav_btn.add_theme_stylebox_override("hover", TempleTheme.chip_box(TempleTheme.WHITE))
	_nav_btn.add_theme_stylebox_override("pressed", TempleTheme.chip_box(TempleTheme.YELLOW))


func _toggle_page_host() -> void:
	_page_in_navigator = not _page_in_navigator
	_refresh_nav_chip()
	_save_config()
	_log(
		"Pages open in %s."
		% ("Flashpoint Navigator" if _page_in_navigator else "the installed browser")
	)


func _launch_via_flashpoint(entry: Dictionary, trial: bool) -> bool:
	var uuid := str(entry.get("id", entry.get("uuid", ""))).strip_edges()
	if uuid.is_empty():
		return false
	if fp_host.clifp().is_empty():
		fp_host.autodetect()
	if fp_host.clifp().is_empty():
		if not await _pick_flashpoint_root():
			_set_job("Needs a Flashpoint folder.")
			_log("Pick the Flashpoint folder to play this.")
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


func _pick_flashpoint_root() -> bool:
	var state := {"done": false, "ok": false, "path": ""}
	var err := DisplayServer.file_dialog_show(
		"Flashpoint folder",
		OS.get_environment("USERPROFILE"),
		"",
		false,
		DisplayServer.FILE_DIALOG_MODE_OPEN_DIR,
		PackedStringArray(),
		func(status: bool, paths: PackedStringArray, _filter: int) -> void:
			state.ok = status
			if status and paths.size() > 0:
				state.path = str(paths[0])
			state.done = true
	)
	if err != OK:
		return false
	while not bool(state.done):
		await get_tree().process_frame
	var path := str(state.path).strip_edges()
	if not bool(state.ok) or path.is_empty():
		return false
	if not fp_host.set_root(path):
		_log(fp_host.last_error)
		return false
	_save_config()
	return true


func _launch_via_browser(
	dest: String,
	meta: Dictionary,
	trial: bool,
	file: String,
	inject_ruffle: bool
) -> void:
	await _launch_via_local_html(dest, meta, trial, file, inject_ruffle)


func _http_movie(launch: String, file: String, dest: String = "") -> String:
	if not dest.is_empty():
		var resolved := Unzip.resolved_movie(dest, launch)
		if not resolved.is_empty():
			return resolved
	var movie := Unzip.movie_url(launch)
	if movie.begins_with("https://") or movie.begins_with("ftp://"):
		return "http://" + movie.substr(movie.find("://") + 3)
	if movie.begins_with("http://"):
		return movie
	var rel := Unzip.path_from_launch(launch)
	if rel.is_empty() and not file.is_empty():
		rel = file.get_file()
	return "http://" + rel if not rel.is_empty() else ""


func _serve_root(dest: String) -> String:
	var dest_abs := ProjectSettings.globalize_path(dest)
	if DirAccess.dir_exists_absolute(dest_abs.path_join("content")):
		return dest_abs.path_join("content")
	return dest_abs


func _launch_via_local_html(
	dest: String,
	meta: Dictionary,
	trial: bool,
	file: String,
	inject_ruffle: bool
) -> void:
	var launch := str(meta.get("launch", meta.get("launchCommand", "")))
	var original := Unzip.resolved_movie(dest, launch)
	if original.is_empty():
		original = Unzip.movie_url(launch)
		if original.begins_with("https://"):
			original = "http://" + original.substr(8)
	var use_proxy := original.begins_with("http://")
	var web := ruffle.web_dir() if inject_ruffle and ruffle.has_web() else ""
	var port := httpd.serve(_serve_root(dest), 18765, Flashpoint.LEGACY_HTDOCS, web, not use_proxy)
	if port < 0:
		_set_busy(false)
		_set_job("Could not start local HTTP.")
		_log("Could not start local HTTP.")
		return
	await get_tree().process_frame
	await get_tree().process_frame
	var tag := "Trial" if trial else "Play"
	if use_proxy:
		var pid := httpd.open_proxied(original)
		if pid != -1:
			_set_busy(false)
			_set_job("%s locally (%s)%s." % [tag, Flashpoint.platform_label(meta), " — not inscribed" if trial else ""])
			_log("%s origin %s proxy %d" % [tag, original, port])
			return
		port = httpd.serve(_serve_root(dest), 18765, Flashpoint.LEGACY_HTDOCS, web, true)
		if port < 0:
			_set_busy(false)
			_set_job("Could not start local HTTP.")
			return
	var rel := Unzip.resolved_rel(dest, launch)
	if rel.is_empty():
		rel = Unzip.path_from_launch(launch)
	if rel.is_empty() and not file.is_empty():
		rel = _rel_under(_serve_root(dest), file)
		if rel.is_empty():
			rel = file.get_file()
	var url := httpd.url_for(rel)
	OS.shell_open(url)
	_set_busy(false)
	_set_job("%s locally (%s)%s." % [tag, Flashpoint.platform_label(meta), " — not inscribed" if trial else ""])
	_log("%s local %s" % [tag, url])


func _launch_via_navigator(
	dest: String,
	meta: Dictionary,
	trial: bool,
	file: String,
	_inject_ruffle: bool,
	_plugin: bool
) -> void:
	var ok := await packs.ensure_for(
		meta,
		_on_progress,
		func(label: String) -> void: _set_job(label),
		_recover_download
	)
	_refresh_nav_chip()
	if not ok:
		_log(packs.last_error)
		_set_busy(false)
		## A page still renders without the pack — our own server, plus Ruffle
		## for any Flash in it. Only a real plugin needs a Flashpoint install.
		if FlashpointHost.page_entry(meta):
			await _launch_via_local_html(dest, meta, trial, file, true)
			return
		await _launch_via_flashpoint(meta, trial)
		return
	var launch := str(meta.get("launch", meta.get("launchCommand", "")))
	## Navigator ships pointed at Flashpoint's proxy port, so bind that one.
	## ShiVa is the exception: its SecurePlayer rewrites archived URLs onto the
	## plugin port instead, and asks for them there.
	var prefer := (
		LocalHttp.PLUGIN_PORT if Packs.wants_plugin_port(meta) else LocalHttp.SPR_PORT
	)
	var port := httpd.serve(_serve_root(dest), prefer, Flashpoint.LEGACY_HTDOCS)
	if port < 0:
		_set_busy(false)
		_set_job("Could not start local HTTP.")
		return
	## Navigator's own fetches for archived absolute URLs come back to us.
	if not packs.configure_proxy(port):
		_log(packs.last_error)
	var rel := Unzip.resolved_rel(dest, launch)
	if rel.is_empty():
		rel = Unzip.path_from_launch(launch)
	var original := Unzip.resolved_movie(dest, launch)
	var local_movie := (
		httpd.url_for(rel, "localhost")
		if not rel.is_empty()
		else _http_movie(launch, "", dest)
	)
	if local_movie.is_empty() and original.is_empty():
		_set_busy(false)
		_set_job("No launch URL.")
		return
	var oc := await _prepare_throttle(meta)
	var pid := packs.play_app(meta, local_movie, original, _throttle_mhz(meta) if not oc.is_empty() else 0)
	if pid != -1:
		await _await_player_window()
	_set_busy(false)
	var tag := "Trial" if trial else "Play"
	if pid == -1:
		_set_job(packs.last_error)
		_log("Play failed: %s" % packs.last_error)
	else:
		_set_job("%s (%s)%s." % [tag, Flashpoint.platform_label(meta), " — not inscribed" if trial else ""])
		_log("%s pid %d — %s" % [tag, pid, local_movie if not local_movie.is_empty() else original])


## Flashpoint's own path for a Flash entry: the projector its applicationPath
## names, pointed at our loopback server the way FlashpointProxy expects.
## Returns false when the runtime is not there, so Play falls back to Ruffle.
func _launch_via_flash(dest: String, meta: Dictionary, trial: bool) -> bool:
	var launch := str(meta.get("launch", meta.get("launchCommand", "")))
	var movie := Flash.movie_for(dest, launch)
	if movie.is_empty():
		return false
	if not flash.has_runtime():
		_set_job("Fetching Flash player…")
	var ok := await flash.ensure(_on_progress, _recover_download)
	_paint_flash_chip()
	if not ok:
		_log(flash.last_error)
		return false
	var port := httpd.serve(_serve_root(dest), LocalHttp.SPR_PORT, Flashpoint.LEGACY_HTDOCS)
	if port < 0:
		_log("Could not start local HTTP for Flash.")
		return false
	if not flash.configure_proxy(port):
		_log(flash.last_error)
		return false
	var oc := await _prepare_throttle(meta)
	var pid := flash.play(meta, movie, _throttle_mhz(meta) if not oc.is_empty() else 0, oc)
	if pid == -1:
		_log("Flash failed: %s" % flash.last_error)
		return false
	await _await_player_window()
	_set_busy(false)
	var tag := "Trial" if trial else "Play"
	_set_job("%s in Flash Player%s." % [tag, " — not inscribed" if trial else ""])
	_log(
		"%s Flash %s pid %d proxy %d — %s"
		% [tag, Flash.projector_name(meta), pid, port, movie]
	)
	return true


func _launch_via_ruffle(dest: String, meta: Dictionary, trial: bool, file: String) -> void:
	var launch := str(meta.get("launch", meta.get("launchCommand", "")))
	var dest_abs := ProjectSettings.globalize_path(dest)
	var serve_root := dest_abs
	if DirAccess.dir_exists_absolute(dest_abs.path_join("content")):
		serve_root = dest_abs.path_join("content")
	var port := httpd.serve(serve_root, 18765, Flashpoint.LEGACY_HTDOCS)
	if port < 0:
		_set_busy(false)
		_set_job("Could not start local HTTP.")
		_log("Could not start local HTTP for Ruffle.")
		return
	var movie := Unzip.resolved_movie(dest, launch)
	if movie.is_empty() or (not movie.to_lower().contains(".swf") and file.to_lower().ends_with(".swf")):
		var rel_swf := Unzip.resolved_rel(dest, launch)
		if rel_swf.is_empty():
			rel_swf = _rel_under(serve_root, file)
		if rel_swf.is_empty():
			var oc0 := await _prepare_throttle(meta)
			var pid := ruffle.play(file, "", "", "", _throttle_mhz(meta) if not oc0.is_empty() else 0, oc0)
			if pid != -1:
				await _await_player_window()
			_set_busy(false)
			_finish_ruffle(pid, trial, file)
			return
		movie = "http://" + rel_swf
	if movie.begins_with("https://") or movie.begins_with("ftp://"):
		movie = "http://" + movie.substr(movie.find("://") + 3)
	elif not movie.begins_with("http://"):
		var rel := Unzip.resolved_rel(dest, launch)
		if rel.is_empty():
			rel = Unzip.path_from_launch(launch)
		if rel.is_empty():
			var oc := await _prepare_throttle(meta)
			var pid := ruffle.play(file, "", "", "", _throttle_mhz(meta) if not oc.is_empty() else 0, oc)
			if pid != -1:
				await _await_player_window()
			_set_busy(false)
			_finish_ruffle(pid, trial, file)
			return
		movie = "http://" + rel
	var proxy := "http://127.0.0.1:%d" % port
	var oc := await _prepare_throttle(meta)
	var pid := ruffle.play(
		movie, "", proxy, movie, _throttle_mhz(meta) if not oc.is_empty() else 0, oc
	)
	if pid != -1:
		await _await_player_window()
	_set_busy(false)
	_finish_ruffle(pid, trial, movie)


func _rel_under(root: String, path: String) -> String:
	var a := ProjectSettings.globalize_path(root).replace("\\", "/").rstrip("/")
	var b := ProjectSettings.globalize_path(path).replace("\\", "/")
	if b.begins_with(a + "/"):
		return b.substr(a.length() + 1)
	return ""


func _finish_ruffle(pid: int, trial: bool, movie: String) -> void:
	var tag := "Trial" if trial else "Play"
	if pid == -1:
		_set_job(ruffle.last_error)
		_log("Play failed: %s" % ruffle.last_error)
	else:
		_set_job("%s in Ruffle%s." % [tag, " — not inscribed" if trial else ""])
		_log("%s Ruffle pid %d — %s" % [tag, pid, movie.get_file() if not movie.begins_with("http") else movie])


func _launch_via_spr(dest: String, meta: Dictionary, trial: bool) -> void:
	_set_job("Fetching Shockwave projector…")
	TempleTheme.paint_chip(_spr_label, "SPR  …", TempleTheme.AMBER)
	var ok := await spr.ensure(_on_progress, _recover_download)
	_refresh_spr_chip()
	if not ok:
		_log(spr.last_error)
		if fp_host.clifp().is_empty():
			fp_host.autodetect()
		if not fp_host.clifp().is_empty():
			_set_busy(false)
			await _launch_via_flashpoint(meta, trial)
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
	var pj := Spr.projector_for(meta)
	if not spr.configure_proxy(port, pj):
		_set_busy(false)
		_set_job(spr.last_error)
		_log(spr.last_error)
		return
	var movie := Unzip.resolved_movie(dest, launch)
	if movie.begins_with("https://"):
		movie = "http://" + movie.substr(8)
	elif not movie.begins_with("http://") and not movie.begins_with("ftp://"):
		var rel := Unzip.resolved_rel(dest, launch)
		if rel.is_empty():
			rel = Unzip.path_from_launch(launch)
		if rel.is_empty():
			_set_busy(false)
			_set_job("No launch URL for SPR.")
			return
		movie = "http://" + rel
	var extra := Unzip.extra_args(launch)
	var oc := await _prepare_throttle(meta)
	var pid := spr.play(movie, extra, pj, _throttle_mhz(meta) if not oc.is_empty() else 0, oc)
	if pid != -1:
		await _await_player_window()
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
	var file := Unzip.file_for_launch(dest, launch)
	var swf := Unzip.swf_for_launch(dest, launch)
	if FlashpointHost.needs_flashpoint(meta):
		## Flashpoint's answer is always Navigator. For a plain page the operator
		## may prefer a modern engine; anything with a plugin in it has no
		## alternative, so the toggle does not apply.
		if _page_in_navigator or not FlashpointHost.page_entry(meta):
			await _launch_via_navigator(dest, meta, trial, file, false, true)
			return
		await _launch_via_local_html(dest, meta, trial, file, true)
		return
	if file.is_empty() and swf.is_empty():
		_set_busy(false)
		_set_job("No launch file in that cartridge.")
		_log("No launch file in that cartridge.")
		return
	var html_launch := (
		Flashpoint.uses_browser(meta)
		or (not file.is_empty() and file.get_extension().to_lower() in ["html", "htm"])
		or launch.to_lower().find(".html") >= 0
		or launch.to_lower().find(".htm") >= 0
	)
	## Flashpoint's default. The projector only takes a movie, so an entry whose
	## launch is a page still goes through the browser path below.
	if _flash_first and not html_launch and not swf.is_empty() and Flash.projector_entry(meta):
		if await _launch_via_flash(dest, meta, trial):
			return
		_log("Flash player unavailable — falling back to Ruffle.")
	if html_launch:
		var flash_html := str(meta.get("platform", "")).to_lower().find("flash") >= 0
		if flash_html:
			if ruffle.exe_path.is_empty() or not ruffle.has_web():
				await ruffle.ensure(_recover_download)
			if ruffle.has_web():
				await _launch_via_local_html(dest, meta, trial, file, true)
				return
			if not swf.is_empty():
				await _launch_via_ruffle(dest, meta, trial, swf)
				return
		await _launch_via_local_html(dest, meta, trial, file, false)
		return
	if Flashpoint.uses_ruffle(meta) or not swf.is_empty() or (not file.is_empty() and file.to_lower().ends_with(".swf")):
		await _launch_via_ruffle(dest, meta, trial, swf if not swf.is_empty() else file)
		return
	_set_busy(false)
	OS.shell_open(file)
	var tag := "Trial" if trial else "Play"
	_set_job("%s via system open (%s)." % [tag, Flashpoint.platform_label(meta)])
	_log("%s opened %s" % [tag, file])


## Favouriting is free and local: no download, no chain write, no confirmation.
func _on_toggle_favorite() -> void:
	var entry := _favorite_subject()
	if entry.is_empty():
		_log("Pick a title to favourite.")
		return
	var now := favorites.toggle(entry)
	_paint_fav_btn()
	var title := str(entry.get("title", "this title"))
	_set_job("%s %s favourites." % [title, "added to" if now else "removed from"])
	_log("%s %s favourites (%d held)." % [title, "★" if now else "removed from", favorites.size()])
	## Show the marker without disturbing the browse. Inside the collection the
	## row has to go, so the list is rebuilt — but we come back to the same place
	## in it rather than to the top.
	if _playlist_id == FAVORITES_ID:
		_archive_keep_row = _archive_row()
		_on_search()
	else:
		_repaint_archive_row(Favorites.uuid_of(entry))


## The row the archive list is sitting on, or -1 if it is sitting on none.
func _archive_row() -> int:
	if _archive == null:
		return -1
	var picked := _archive.get_selected_items()
	return -1 if picked.is_empty() else picked[0]


## Relabel one row in place. Starring a title changes nothing about the list it
## is in, so there is no reason to rebuild the page and lose where we were.
func _repaint_archive_row(uuid: String) -> void:
	if _archive == null or uuid.is_empty():
		return
	for i in _archive.item_count:
		var rec: Variant = _archive.get_item_metadata(i)
		if rec is Dictionary and Favorites.uuid_of(rec) == uuid:
			_archive.set_item_text(i, _archive_label(rec))
			return


## The archive row if one is selected, else the inscribed cartridge on stage.
func _favorite_subject() -> Dictionary:
	if _selected_entry.is_empty():
		return {}
	var entry := _selected_entry.duplicate()
	if Favorites.uuid_of(entry).is_empty():
		return {}
	return entry


func _paint_fav_btn() -> void:
	if _fav_btn == null:
		return
	var entry := _favorite_subject()
	var on := not entry.is_empty() and favorites.has(entry)
	_fav_btn.disabled = entry.is_empty()
	_fav_btn.text = "★ FAVOURITE" if on else "FAVOURITE"
	_fav_btn.tooltip_text = (
		"In your favourites. Click to remove."
		if on
		else "Keep a local bookmark to this title. Costs nothing and writes nothing to the chain."
	)
	_fav_btn.add_theme_color_override(
		"font_color", TempleTheme.YELLOW if on else TempleTheme.GREY
	)


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


func _cabinet_label(rec: Dictionary) -> String:
	var title := str(rec.get("title", rec.get("table", "?")))
	if _view_grid:
		return title
	var plat := Flashpoint.platform_label(rec.get("meta", {}))
	return title if plat == "Unknown" else "%s  ·  %s" % [title, plat]


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
		if _cabinet_cached and not Cartridge.has_play_cache(str(rec.get("table", ""))):
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
		var idx := _inscribed_list.add_item(_cabinet_label(rec), placeholder)
		_inscribed_list.set_item_metadata(idx, rec)
		var cached := Cartridge.has_play_cache(str(rec.get("table", "")))
		_inscribed_list.set_item_custom_fg_color(idx, TempleTheme.GREEN if cached else TempleTheme.CYAN)
		_inscribed_list.set_item_tooltip(
			idx,
			"Local Play cache. Right-click to drop it."
			if cached
			else "Not cached locally. Play fetches from the chain."
		)
	var head := "ON CHAIN  ·  %d" % total
	if not _cabinet_plat.is_empty():
		head += "  ·  %s" % _cabinet_plat
	if _cabinet_cached:
		head += "  ·  CACHED"
	if total > CABINET_PAGE:
		head += "  ·  %d–%d" % [start + 1, stop]
	_inscribed_header.text = head
	if _inscribed_empty:
		_inscribed_empty.visible = total == 0
		if total == 0 and _cabinet_cached:
			_inscribed_empty.text = "No local Play cache."
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
		var b := TempleTheme.index_button(letter, TempleTheme.CYAN)
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
			b.add_theme_stylebox_override(
				"normal", TempleTheme._box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 1, 0, 0)
			)
			b.add_theme_color_override("font_color", TempleTheme.CYAN)


func _on_cabinet_platform() -> void:
	_cabinet_plat = _facet_value(_cabinet_platform)
	_cabinet_page = 0
	_paint_cabinet()


func _on_cabinet_cached() -> void:
	_cabinet_cached = not _cabinet_cached
	if _cabinet_cached_btn:
		_cabinet_cached_btn.text = "CACHED" if _cabinet_cached else "CACHE"
		if _cabinet_cached:
			_cabinet_cached_btn.add_theme_color_override("font_color", TempleTheme.GREEN)
		else:
			_cabinet_cached_btn.remove_theme_color_override("font_color")
	_cabinet_page = 0
	_paint_cabinet()


func _on_inscribed_clicked(index: int, at_position: Vector2, mouse_button: int) -> void:
	if mouse_button != MOUSE_BUTTON_RIGHT:
		return
	if index < 0 or _inscribed_list == null:
		return
	_inscribed_list.select(index)
	_on_inscribed_selected(index)
	var rec: Variant = _inscribed_list.get_item_metadata(index)
	if not rec is Dictionary:
		return
	var table := str((rec as Dictionary).get("table", ""))
	var cached := Cartridge.has_play_cache(table)
	var menu := PopupMenu.new()
	menu.add_item("PLAY", 0)
	menu.add_item("DROP CACHE", 1)
	menu.set_item_disabled(1, not cached)
	menu.id_pressed.connect(func(id: int) -> void:
		if id == 0:
			_on_play()
		elif id == 1:
			_on_drop_cache()
		menu.queue_free()
	)
	menu.close_requested.connect(menu.queue_free)
	add_child(menu)
	menu.position = Vector2i(_inscribed_list.get_screen_position() + at_position)
	menu.popup()


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
	var pct := int(value)
	if pct == _last_progress:
		return
	_last_progress = pct
	if _job_base.is_empty():
		_job.text = "%d%%" % pct
	else:
		_job.text = "%s  %d%%" % [_job_base, pct]


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
	set_process(on or _player_waiting)


func _process(dt: float) -> void:
	if _player_waiting:
		_search_spin += dt * 3.2
		if _player_veil:
			_player_veil.color.a = 0.62 + 0.18 * sin(_search_spin)
		if _player_wait_label:
			_player_wait_label.modulate.a = 0.7 + 0.3 * abs(sin(_search_spin * 1.4))
		return
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
	_job_base = text
	_last_progress = -1
	_job.text = text
	if not _busy and not _searching:
		_progress.value = 0


func _cache_cost_line(table: String) -> String:
	if table.is_empty() or not Cartridge.has_play_cache(table):
		return "No local Play cache. Play fetches the zip from the chain."
	var n := Cartridge.tree_bytes(Cartridge.cache_dir(table))
	return "Local Play cache %s. Drop it to free disk; Play will fetch again." % Flashpoint.format_bytes(n)


func _confirm(body: String, heading: String = "NO UNPUBLISH") -> bool:
	var veil := ColorRect.new()
	veil.color = Color(0, 0, 0, 0.84)
	veil.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	veil.z_index = 80
	add_child(veil)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.add_child(centre)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(540, 0)
	panel.add_theme_stylebox_override("panel", TempleTheme.dialog_box())
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	centre.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	box.add_child(TempleTheme.title(heading, TempleTheme.AMBER))
	var body_label := TempleTheme.line(body, TempleTheme.GREY, TempleTheme.SIZE_BODY)
	body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	body_label.custom_minimum_size = Vector2(500, 0)
	box.add_child(body_label)
	box.add_child(TempleTheme.rule(TempleTheme.AMBER))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(row)

	var state := {"done": false, "ok": false}
	var finish := func(ok: bool) -> void:
		if bool(state.done):
			return
		state.ok = ok
		state.done = true
	var cancel := TempleTheme.button("CANCEL", finish.bind(false))
	var escape := Shortcut.new()
	var escape_key := InputEventKey.new()
	escape_key.keycode = KEY_ESCAPE
	escape.events.append(escape_key)
	cancel.shortcut = escape
	row.add_child(cancel)
	var proceed := TempleTheme.primary_button("PROCEED", finish.bind(true))
	row.add_child(proceed)

	veil.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			finish.call(false)
	)

	proceed.grab_focus()
	while not state.done:
		await get_tree().process_frame
	veil.queue_free()
	return bool(state.ok)


func _toggle_log() -> void:
	_log_open = not _log_open
	if _console:
		_console.visible = _log_open
	if _log_btn:
		_log_btn.text = "LOG  −" if _log_open else "LOG  +"


func _show_player_wait(on: bool, message: String = "LOADING PLAYER…") -> void:
	_player_waiting = on
	_search_spin = 0.0
	if _player_veil:
		_player_veil.visible = on
	if _player_wait_label and on:
		_player_wait_label.text = message.to_upper()
	if on:
		_set_job(message)
		set_process(true)
	elif not _searching:
		set_process(false)


func _await_player_window() -> void:
	_show_player_wait(true)
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 12000:
		if Spr.player_ready():
			break
		await get_tree().process_frame
	_show_player_wait(false)


func _recover_download(label: String, archive: String) -> bool:
	var choice := await _missing_runtime_prompt(label)
	var kind := str(choice.get("kind", ""))
	if kind == "file":
		var src := str(choice.get("path", "")).strip_edges()
		if src.is_empty() or not FileAccess.file_exists(src):
			return false
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(archive).get_base_dir())
		var bytes := FileAccess.get_file_as_bytes(src)
		var out := FileAccess.open(archive, FileAccess.WRITE)
		if out == null:
			return false
		out.store_buffer(bytes)
		out.close()
		_log("Using local file for %s." % label)
		return FileAccess.file_exists(archive)
	if kind == "signature":
		var sig := str(choice.get("signature", "")).strip_edges()
		if sig.is_empty():
			return false
		if not iq.is_available():
			_set_job("No host to read that signature.")
			return false
		var bytes := PackedByteArray()
		for c in _chain_order():
			_set_job("Reading %s on %s…" % [label, c.to_upper()])
			var doc: Variant = await iq.read_code_in(sig, c, _on_progress)
			bytes = _bytes_from_inscription(doc)
			if bytes.size() > 32:
				break
		if bytes.size() <= 32:
			_set_job("That signature had no file on MON, SOL, or RH.")
			return false
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(archive).get_base_dir())
		var out := FileAccess.open(archive, FileAccess.WRITE)
		if out == null:
			return false
		out.store_buffer(bytes)
		out.close()
		_log("Using chain signature for %s." % label)
		return true
	return false


func _chain_order() -> PackedStringArray:
	var out := PackedStringArray([chain])
	for c in ["mon", "sol", "rh"]:
		if c != chain:
			out.append(c)
	return out


func _bytes_from_inscription(result: Variant) -> PackedByteArray:
	if result is PackedByteArray:
		return result
	if result is Dictionary:
		var raw: Variant = (result as Dictionary).get("data", (result as Dictionary).get("bytes", null))
		if raw is PackedByteArray:
			return raw
		if raw is String:
			var decoded := Marshalls.base64_to_raw(str(raw))
			if decoded.size() > 32:
				return decoded
			return str(raw).to_utf8_buffer()
	if result is String:
		var decoded2 := Marshalls.base64_to_raw(str(result))
		if decoded2.size() > 32:
			return decoded2
	return PackedByteArray()


func _missing_runtime_prompt(label: String) -> Dictionary:
	var veil := ColorRect.new()
	veil.color = Color(0, 0, 0, 0.84)
	veil.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	veil.z_index = 80
	add_child(veil)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.add_child(centre)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	panel.add_theme_stylebox_override("panel", TempleTheme.dialog_box())
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	centre.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	box.add_child(TempleTheme.title(MISSING_RUNTIME, TempleTheme.AMBER))
	var body := TempleTheme.line(
		"Could not fetch %s. Choose the zip on disk, or a signature on MON, SOL, or RH." % label,
		TempleTheme.GREY,
		TempleTheme.SIZE_BODY
	)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	body.custom_minimum_size = Vector2(520, 0)
	box.add_child(body)
	var sig := LineEdit.new()
	sig.placeholder_text = "signature"
	sig.custom_minimum_size = Vector2(0, 28)
	box.add_child(sig)
	box.add_child(TempleTheme.rule(TempleTheme.AMBER))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(row)
	var state := {"done": false, "kind": "", "path": "", "signature": ""}
	var finish := func(kind: String) -> void:
		if bool(state.done):
			return
		state.kind = kind
		state.signature = sig.text.strip_edges()
		state.done = true
	row.add_child(TempleTheme.button("CANCEL", finish.bind("")))
	row.add_child(TempleTheme.button("FILE", finish.bind("file")))
	row.add_child(TempleTheme.primary_button("SIGNATURE", finish.bind("signature")))
	sig.grab_focus()
	while not bool(state.done):
		await get_tree().process_frame
	var kind := str(state.kind)
	veil.queue_free()
	if kind == "file":
		var picked := await _pick_runtime_zip()
		if picked.is_empty():
			return {}
		state.path = picked
	if kind.is_empty():
		return {}
	return {"kind": kind, "path": str(state.path), "signature": str(state.signature)}


func _pick_runtime_zip() -> String:
	var state := {"done": false, "ok": false, "path": ""}
	var err := DisplayServer.file_dialog_show(
		"Runtime zip",
		OS.get_environment("USERPROFILE"),
		"",
		false,
		DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,
		PackedStringArray(["*.zip"]),
		func(status: bool, paths: PackedStringArray, _filter: int) -> void:
			state.ok = status
			if status and paths.size() > 0:
				state.path = str(paths[0])
			state.done = true
	)
	if err != OK:
		return ""
	while not bool(state.done):
		await get_tree().process_frame
	if not bool(state.ok):
		return ""
	return str(state.path).strip_edges()


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
		if (parsed as Dictionary).has("authentic"):
			_authentic = bool((parsed as Dictionary).get("authentic", true))
		if (parsed as Dictionary).has("flash_first"):
			_flash_first = bool((parsed as Dictionary).get("flash_first", true))
		if (parsed as Dictionary).has("page_in_navigator"):
			_page_in_navigator = bool((parsed as Dictionary).get("page_in_navigator", true))
		if (parsed as Dictionary).has("tag_filter"):
			tag_filter.from_config((parsed as Dictionary).get("tag_filter", null))
	if fp_host.root.is_empty():
		fp_host.autodetect()


func _save_config() -> void:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(
		JSON.stringify({
			"chain": chain,
			"flashpoint_root": fp_host.root,
			"view_grid": _view_grid,
			"authentic": _authentic,
			"flash_first": _flash_first,
			"page_in_navigator": _page_in_navigator,
			"tag_filter": tag_filter.to_config(),
		})
	)
	file.close()
