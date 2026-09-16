## Type-to-filter picker. Stores the full name list; the popup only draws
## matches (capped), so tens of thousands of developers do not freeze OptionButton.

class_name FacetPick
extends Control

signal picked(value: String)

const SHOW := 120

var all_label: String = "All"
var names: PackedStringArray = PackedStringArray()
var value: String = ""

var _btn: Button
var _pop: PopupPanel
var _filter: LineEdit
var _list: ItemList
var _hint: Label


func _ready() -> void:
	custom_minimum_size = Vector2(150, 0)
	size_flags_horizontal = SIZE_EXPAND_FILL
	_btn = Button.new()
	_btn.text = all_label
	_btn.clip_text = true
	_btn.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_btn.pressed.connect(_open)
	add_child(_btn)

	_pop = PopupPanel.new()
	_pop.unresizable = true
	add_child(_pop)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_pop.add_child(box)

	_filter = LineEdit.new()
	_filter.placeholder_text = "type to search…"
	_filter.text_changed.connect(func(_t: String) -> void: _rebuild())
	_filter.text_submitted.connect(func(_t: String) -> void: _pick_first())
	box.add_child(_filter)

	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", TempleTheme.SIZE_SMALL)
	_hint.add_theme_color_override("font_color", TempleTheme.MUTED)
	box.add_child(_hint)

	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(260, 220)
	_list.auto_height = false
	_list.item_activated.connect(func(i: int) -> void: _choose(i))
	_list.item_selected.connect(func(i: int) -> void: pass)
	_list.gui_input.connect(_on_list_input)
	box.add_child(_list)


func set_names(next: PackedStringArray) -> void:
	names = next
	_refresh_button()


func set_value(next: String) -> void:
	value = next.strip_edges()
	_refresh_button()


func _refresh_button() -> void:
	if _btn == null:
		return
	if value.is_empty():
		_btn.text = all_label
		_btn.add_theme_color_override("font_color", TempleTheme.YELLOW)
	else:
		_btn.text = value
		_btn.add_theme_color_override("font_color", TempleTheme.CYAN)


func _open() -> void:
	_filter.text = ""
	_rebuild()
	var g := get_global_rect()
	_pop.size = Vector2i(280, 300)
	_pop.position = Vector2i(int(g.position.x), int(g.position.y + g.size.y))
	_pop.popup()
	_filter.grab_focus()


func _rebuild() -> void:
	_list.clear()
	_list.add_item(all_label)
	_list.set_item_metadata(0, "")
	var needle := _filter.text.strip_edges().to_lower()
	var shown := 0
	var hits := 0
	for name in names:
		if not needle.is_empty() and name.to_lower().find(needle) < 0:
			continue
		hits += 1
		if shown >= SHOW:
			continue
		_list.add_item(name)
		_list.set_item_metadata(_list.item_count - 1, name)
		shown += 1
	if needle.is_empty():
		_hint.text = "%d names  ·  type to jump" % names.size()
	elif hits > shown:
		_hint.text = "showing %d of %d matches" % [shown, hits]
	else:
		_hint.text = "%d match%s" % [hits, "" if hits == 1 else "es"]


func _on_list_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse: InputEventMouseButton = event
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			var i := _list.get_item_at_position(mouse.position, true)
			if i >= 0:
				_choose(i)


func _pick_first() -> void:
	if _list.item_count <= 1:
		_choose(0)
		return
	_choose(1)


func _choose(index: int) -> void:
	if index < 0 or index >= _list.item_count:
		return
	var next := str(_list.get_item_metadata(index))
	value = next
	_refresh_button()
	_pop.hide()
	picked.emit(value)
