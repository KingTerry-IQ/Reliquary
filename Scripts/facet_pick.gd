## Type-to-filter picker. Stores the full name list; the popup only draws
## matches (capped), so tens of thousands of developers do not freeze OptionButton.
##
## This is a container on purpose: a bare Control with a full-rect button reports
## zero height, and a flow row then stacks every picker on the same pixels.

class_name FacetPick
extends HBoxContainer

signal picked(value: String)

const SHOW := 120
const POP_H := 320
const ROW_H := 28

var all_label: String = "All"
var names: PackedStringArray = PackedStringArray()
var value: String = ""

var _btn: Button
var _pop: PopupPanel
var _filter: LineEdit
var _list: ItemList
var _hint: Label


func _init() -> void:
	size_flags_horizontal = SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0, ROW_H)
	add_theme_constant_override("separation", 0)


func _ready() -> void:
	_btn = Button.new()
	_btn.text = "%s  ▾" % all_label
	_btn.clip_text = true
	_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	_btn.size_flags_vertical = SIZE_EXPAND_FILL
	_btn.custom_minimum_size = Vector2(0, ROW_H)
	_btn.pressed.connect(_open)
	add_child(_btn)

	_pop = PopupPanel.new()
	_pop.unresizable = true
	_pop.add_theme_stylebox_override("panel", TempleTheme._outline(TempleTheme.YELLOW, TempleTheme.BLACK))
	add_child(_pop)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.size_flags_horizontal = SIZE_EXPAND_FILL
	box.size_flags_vertical = SIZE_EXPAND_FILL
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 8)
	pad.add_theme_constant_override("margin_right", 8)
	pad.add_theme_constant_override("margin_top", 8)
	pad.add_theme_constant_override("margin_bottom", 8)
	pad.size_flags_horizontal = SIZE_EXPAND_FILL
	pad.size_flags_vertical = SIZE_EXPAND_FILL
	_pop.add_child(pad)
	pad.add_child(box)

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
	_list.size_flags_horizontal = SIZE_EXPAND_FILL
	_list.size_flags_vertical = SIZE_EXPAND_FILL
	_list.custom_minimum_size = Vector2(0, 180)
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
		_btn.text = "%s  ▾" % all_label
		_btn.add_theme_color_override("font_color", TempleTheme.YELLOW)
	else:
		_btn.text = "%s  ▾" % value
		_btn.add_theme_color_override("font_color", TempleTheme.CYAN)


func _open() -> void:
	_filter.text = ""
	_rebuild()
	var g := get_global_rect()
	var vp := get_viewport().get_visible_rect()
	var w := maxi(int(g.size.x), 220)
	w = mini(w, maxi(220, int(vp.size.x) - 24))
	var h := POP_H
	var x := g.position.x
	var y := g.position.y + g.size.y
	if x + float(w) > vp.position.x + vp.size.x:
		x = vp.position.x + vp.size.x - float(w)
	if x < vp.position.x:
		x = vp.position.x
	if y + float(h) > vp.position.y + vp.size.y:
		y = g.position.y - float(h)
		if y < vp.position.y:
			y = vp.position.y + vp.size.y - float(h)
	_pop.popup(Rect2i(Vector2i(int(x), int(y)), Vector2i(w, h)))
	_filter.grab_focus()


func _rebuild() -> void:
	_list.clear()
	_list.add_item(all_label)
	_list.set_item_metadata(0, "")
	if value.is_empty():
		_list.set_item_custom_fg_color(0, TempleTheme.YELLOW)
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
		var idx := _list.item_count - 1
		_list.set_item_metadata(idx, name)
		if name == value:
			_list.set_item_custom_fg_color(idx, TempleTheme.CYAN)
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
