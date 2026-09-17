## The look: sixteen colours on black, one monospaced face, hard edges.
##
## TempleOS ran at 640x480 in 16 colours because Terry decided that was what
## God had specified, and the constraint gives the app its whole character.
## Nothing here is anti-aliased into a modern gradient; the fire is yellow, the
## warnings are red, and the rest is grey.
##
## Built in code rather than a .tres so the palette lives next to the reasoning.

class_name TempleTheme
extends RefCounted

# The VGA sixteen, or the ones worth having.
const BLACK := Color("000000")
const DARK_GREY := Color("555555")
const GREY := Color("AAAAAA")
## For disabled controls. Dark grey reads as unavailable but at 2.8:1 is also
## unreadable, and a control you cannot read is one you cannot reason about.
const MUTED := Color("808080")
const WHITE := Color("FFFFFF")
const RED := Color("AA0000")
const BRIGHT_RED := Color("FF5555")
const BROWN := Color("AA5500")
const YELLOW := Color("FFFF55")
## Warnings need to be read, and #AA5500 on black is 4:1 — under the threshold
## for body text. This is the same hue carried up to a legible brightness.
const AMBER := Color("FFAA55")
const CYAN := Color("55FFFF")
const GREEN := Color("55FF55")
const MAGENTA := Color("FF55FF")
const BLUE := Color("5555FF")
const PANEL := Color("0A0A0A")

const FONT_PATH := "res://Assets/IBMPlexMono-Light.ttf"

const SIZE_BODY := 16
const SIZE_SMALL := 13
const SIZE_TITLE := 28
const SIZE_DISPLAY := 22


static func build() -> Theme:
	var theme := Theme.new()

	var font: Font = null
	if ResourceLoader.exists(FONT_PATH):
		font = load(FONT_PATH)

	theme.default_font_size = SIZE_BODY
	if font != null:
		theme.default_font = font

	_style_labels(theme)
	_style_buttons(theme)
	_style_inputs(theme)
	_style_panels(theme)
	_style_lists(theme)
	_style_bars(theme)
	_style_scroll(theme)
	_style_tips(theme)
	_style_windows(theme)

	return theme


static func _style_labels(theme: Theme) -> void:
	# Default text is the light grey, not the dark one. Dark grey is reserved
	# for genuinely decorative things — rules, gutters, dead chrome.
	theme.set_color("font_color", "Label", GREY)
	theme.set_color("default_color", "RichTextLabel", GREY)
	# The console is the only place long text lands, so give it room to breathe.
	theme.set_constant("line_separation", "RichTextLabel", 2)


static func _style_buttons(theme: Theme) -> void:
	# Idle buttons are outlines; hovering fills them, which is how text-mode
	# UIs have always signalled focus.
	theme.set_stylebox("normal", "Button", _outline(YELLOW, BLACK))
	theme.set_stylebox("hover", "Button", _solid(YELLOW))
	theme.set_stylebox("pressed", "Button", _solid(WHITE))
	theme.set_stylebox("focus", "Button", _outline(WHITE, Color(0, 0, 0, 0)))
	theme.set_stylebox("disabled", "Button", _outline(DARK_GREY, BLACK))

	theme.set_color("font_color", "Button", YELLOW)
	theme.set_color("font_hover_color", "Button", BLACK)
	theme.set_color("font_pressed_color", "Button", BLACK)
	theme.set_color("font_focus_color", "Button", YELLOW)
	theme.set_color("font_disabled_color", "Button", DARK_GREY)

	# CheckBox derives from Button, and Godot's theme lookup falls back to the
	# base type — so every state has to be stated here or a checkbox picks up
	# the button's solid yellow fill and renders its label invisibly on top.
	var quiet := _outline(Color(0, 0, 0, 0), Color(0, 0, 0, 0))
	theme.set_stylebox("normal", "CheckBox", quiet)
	theme.set_stylebox("hover", "CheckBox", _outline(Color(0, 0, 0, 0), Color("141414")))
	theme.set_stylebox("pressed", "CheckBox", _outline(Color(0, 0, 0, 0), Color("141414")))
	theme.set_stylebox("hover_pressed", "CheckBox", _outline(Color(0, 0, 0, 0), Color("141414")))
	theme.set_stylebox("focus", "CheckBox", _outline(DARK_GREY, Color(0, 0, 0, 0)))
	theme.set_stylebox("disabled", "CheckBox", quiet)

	theme.set_color("font_color", "CheckBox", GREY)
	theme.set_color("font_hover_color", "CheckBox", YELLOW)
	theme.set_color("font_pressed_color", "CheckBox", YELLOW)
	theme.set_color("font_hover_pressed_color", "CheckBox", YELLOW)
	theme.set_color("font_focus_color", "CheckBox", WHITE)
	theme.set_color("font_disabled_color", "CheckBox", MUTED)

	# The box itself is an icon, and its colour is a theme item separate from
	# the label's. Left at the default it drew near-black on black, so an
	# unticked box was invisible and the only way to read the state was to tick
	# it. Unticked is deliberately the brightest: an option you cannot see is
	# an option you cannot knowingly decline.
	theme.set_color("icon_normal_color", "CheckBox", WHITE)
	theme.set_color("icon_hover_color", "CheckBox", YELLOW)
	theme.set_color("icon_pressed_color", "CheckBox", YELLOW)
	theme.set_color("icon_hover_pressed_color", "CheckBox", YELLOW)
	theme.set_color("icon_focus_color", "CheckBox", WHITE)
	theme.set_color("icon_disabled_color", "CheckBox", MUTED)


static func _style_inputs(theme: Theme) -> void:
	theme.set_stylebox("normal", "LineEdit", _outline(DARK_GREY, BLACK))
	theme.set_stylebox("focus", "LineEdit", _outline(YELLOW, BLACK))
	theme.set_color("font_color", "LineEdit", WHITE)
	theme.set_color("font_placeholder_color", "LineEdit", DARK_GREY)
	theme.set_color("caret_color", "LineEdit", YELLOW)
	theme.set_color("selection_color", "LineEdit", RED)

	theme.set_stylebox("normal", "TextEdit", _outline(DARK_GREY, BLACK))
	theme.set_stylebox("focus", "TextEdit", _outline(YELLOW, BLACK))
	# A box showing something that must not be edited is still a box on black.
	# Left to the default, read_only drew a pale grey slab — which is where the
	# opened word lands, so the one thing worth reading was the one thing not
	# drawn in the app's colours.
	theme.set_stylebox("read_only", "TextEdit", _outline(DARK_GREY, BLACK))
	theme.set_color("font_color", "TextEdit", WHITE)
	theme.set_color("font_readonly_color", "TextEdit", WHITE)
	theme.set_color("caret_color", "TextEdit", YELLOW)

	theme.set_stylebox("normal", "SpinBox", _outline(DARK_GREY, BLACK))

	theme.set_stylebox("normal", "OptionButton", _outline(DARK_GREY, BLACK))
	theme.set_stylebox("hover", "OptionButton", _outline(YELLOW, BLACK))
	theme.set_stylebox("pressed", "OptionButton", _solid(YELLOW))
	theme.set_stylebox("focus", "OptionButton", _outline(YELLOW, BLACK))
	theme.set_color("font_color", "OptionButton", YELLOW)
	theme.set_color("font_hover_color", "OptionButton", YELLOW)
	theme.set_color("font_pressed_color", "OptionButton", BLACK)
	theme.set_color("font_focus_color", "OptionButton", WHITE)


static func _style_panels(theme: Theme) -> void:
	theme.set_stylebox("panel", "Panel", _outline(BROWN, PANEL))
	theme.set_stylebox("panel", "PanelContainer", _outline(BROWN, PANEL))
	theme.set_stylebox("panel", "PopupMenu", _outline(YELLOW, BLACK))
	theme.set_color("font_color", "PopupMenu", GREY)
	theme.set_color("font_hover_color", "PopupMenu", BLACK)
	theme.set_color("font_accelerator_color", "PopupMenu", MUTED)
	theme.set_stylebox("hover", "PopupMenu", _solid(YELLOW))


static func _style_lists(theme: Theme) -> void:
	theme.set_stylebox("panel", "ItemList", _outline(DARK_GREY, BLACK))
	theme.set_stylebox("hovered", "ItemList", _solid(Color("141414")))
	theme.set_stylebox("selected", "ItemList", _outline(YELLOW, Color("1A1400")))
	theme.set_stylebox("cursor", "ItemList", _outline(YELLOW, Color(0, 0, 0, 0)))
	theme.set_color("font_color", "ItemList", GREY)
	theme.set_color("font_hovered_color", "ItemList", WHITE)
	theme.set_color("font_selected_color", "ItemList", YELLOW)
	theme.set_constant("v_separation", "ItemList", 4)
	theme.set_constant("icon_margin", "ItemList", 8)
	theme.set_constant("line_separation", "ItemList", 2)


static func _style_bars(theme: Theme) -> void:
	var bg := _outline(DARK_GREY, BLACK)
	bg.content_margin_top = 2
	bg.content_margin_bottom = 2
	theme.set_stylebox("background", "ProgressBar", bg)
	theme.set_stylebox("fill", "ProgressBar", _solid(YELLOW))
	theme.set_color("font_color", "ProgressBar", BLACK)
	theme.set_color("font_outline_color", "ProgressBar", BLACK)


static func _style_scroll(theme: Theme) -> void:
	var track := _box(DARK_GREY, BLACK, 1, 1, 1)
	var grab := _box(YELLOW, YELLOW, 0, 0, 1)
	var grab_hot := _box(WHITE, WHITE, 0, 0, 1)
	for kind in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", kind, track)
		theme.set_stylebox("scroll_focus", kind, track)
		theme.set_stylebox("grabber", kind, grab)
		theme.set_stylebox("grabber_highlight", kind, grab_hot)
		theme.set_stylebox("grabber_pressed", kind, grab_hot)
		theme.set_stylebox("grabber_area", kind, StyleBoxEmpty.new())
		theme.set_stylebox("grabber_area_highlight", kind, StyleBoxEmpty.new())


static func _style_tips(theme: Theme) -> void:
	theme.set_stylebox("panel", "TooltipPanel", _outline(YELLOW, BLACK))
	theme.set_color("font_color", "TooltipLabel", GREY)
	theme.set_font_size("font_size", "TooltipLabel", SIZE_SMALL)


static func _style_windows(theme: Theme) -> void:
	theme.set_stylebox("embedded_border", "Window", _outline(YELLOW, PANEL))
	theme.set_stylebox("embedded_unfocused_border", "Window", _outline(DARK_GREY, PANEL))
	theme.set_color("title_color", "Window", YELLOW)
	theme.set_constant("title_height", "Window", 28)
	theme.set_stylebox("panel", "AcceptDialog", _outline(AMBER, BLACK))


static func _outline(border: Color, fill: Color) -> StyleBoxFlat:
	return _box(border, fill, 8, 4, 1)


static func _solid(fill: Color) -> StyleBoxFlat:
	return _box(fill, fill, 8, 4, 1)


static func _box(border: Color, fill: Color, pad_x: int, pad_y: int, width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.draw_center = fill.a > 0.0
	box.border_color = border
	box.set_border_width_all(width)
	# No corner radius anywhere. Text mode did not round its corners.
	box.content_margin_left = pad_x
	box.content_margin_right = pad_x
	box.content_margin_top = pad_y
	box.content_margin_bottom = pad_y
	return box


static func chip_box(colour: Color) -> StyleBoxFlat:
	return _box(colour, BLACK, 10, 3, 1)


static func screen_box() -> StyleBoxFlat:
	return _box(YELLOW, BLACK, 3, 3, 2)


static func dialog_box() -> StyleBoxFlat:
	return _box(AMBER, BLACK, 18, 14, 1)


## Recolour a chip built by wrap_chip when a status changes.
static func paint_chip(label: Label, text: String, colour: Color) -> void:
	if label == null:
		return
	label.text = text
	label.add_theme_color_override("font_color", colour)
	var parent := label.get_parent()
	if parent is PanelContainer:
		(parent as PanelContainer).add_theme_stylebox_override("panel", chip_box(colour))


static func wrap_chip(label: Label, colour: Color) -> PanelContainer:
	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override("panel", chip_box(colour))
	wrap.size_flags_horizontal = Control.SIZE_SHRINK_END
	wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wrap.add_child(label)
	return wrap


## Jukebox index key: one letter, fills the strip, no fat button padding.
static func index_button(letter: String, accent: Color) -> Button:
	var b := Button.new()
	b.text = letter
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(24, 14)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 12)
	b.add_theme_color_override("font_color", accent)
	b.add_theme_color_override("font_hover_color", BLACK)
	b.add_theme_color_override("font_pressed_color", BLACK)
	b.add_theme_color_override("font_focus_color", accent)
	var quiet := _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 1, 0, 0)
	b.add_theme_stylebox_override("normal", quiet)
	b.add_theme_stylebox_override("hover", _solid(accent))
	b.add_theme_stylebox_override("pressed", _solid(WHITE))
	b.add_theme_stylebox_override("focus", quiet)
	return b


static func tag_button(text: String, on_pressed: Callable) -> Button:
	var b := button(text, on_pressed)
	b.add_theme_font_size_override("font_size", SIZE_SMALL)
	b.add_theme_stylebox_override("normal", _box(DARK_GREY, BLACK, 6, 2, 1))
	b.add_theme_stylebox_override("hover", _box(CYAN, BLACK, 6, 2, 1))
	b.add_theme_stylebox_override("pressed", _solid(CYAN))
	b.add_theme_color_override("font_color", CYAN)
	b.add_theme_color_override("font_hover_color", CYAN)
	b.add_theme_color_override("font_pressed_color", BLACK)
	return b


static func rule(colour: Color = DARK_GREY, vertical: bool = false) -> ColorRect:
	var line := ColorRect.new()
	line.color = colour
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if vertical:
		line.custom_minimum_size = Vector2(1, 0)
		line.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		line.custom_minimum_size = Vector2(0, 1)
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return line


## Tiled 1-bit scanlines. Honest pixels, no shader.
static func scan_texture() -> Texture2D:
	var img := Image.create(1, 2, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color(0, 0, 0, 0))
	img.set_pixel(0, 1, Color(0, 0, 0, 0.32))
	return ImageTexture.create_from_image(img)


## A heading, in the app's voice: bright, spaced, shouted.
static func title(text: String, colour: Color = YELLOW) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", SIZE_TITLE)
	label.add_theme_color_override("font_color", colour)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


static func line(text: String, colour: Color = GREY, size: int = SIZE_BODY) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


## One row of a table: left-aligned and never wrapped.
##
## line() wraps, which is right for prose and wrong for a padded column layout.
## Squeezed into a narrow container a padded string has no spaces to break on,
## so word-wrap degrades to breaking after single characters and the table
## becomes a column of letters. These clip instead.
static func cell(text: String, colour: Color = GREY, size: int = SIZE_SMALL) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.clip_text = true
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


## The one action the app is recommending: filled rather than outlined, so
## there is never a question of where to look first.
##
## Theme font_focus_color is yellow, which is right on an outlined idle
## button and invisible on this yellow fill. Confirm dialogs grab_focus the
## proceed button, so every focus/pressed colour has to stay black.
static func primary_button(text: String, on_pressed: Callable) -> Button:
	var b := button(text, on_pressed)
	b.add_theme_stylebox_override("normal", _solid(YELLOW))
	b.add_theme_stylebox_override("hover", _solid(WHITE))
	b.add_theme_stylebox_override("pressed", _solid(WHITE))
	b.add_theme_stylebox_override("hover_pressed", _solid(WHITE))
	b.add_theme_stylebox_override("focus", _box(WHITE, YELLOW, 8, 4, 1))
	b.add_theme_color_override("font_color", BLACK)
	b.add_theme_color_override("font_hover_color", BLACK)
	b.add_theme_color_override("font_pressed_color", BLACK)
	b.add_theme_color_override("font_hover_pressed_color", BLACK)
	b.add_theme_color_override("font_focus_color", BLACK)
	return b


## Maintenance, not a destination: small muted outline, skipped in tab order.
static func quiet_button(text: String, on_pressed: Callable) -> Button:
	var b := button(text, on_pressed)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", SIZE_SMALL)
	b.add_theme_stylebox_override("normal", _box(DARK_GREY, BLACK, 6, 2, 1))
	b.add_theme_stylebox_override("hover", _box(MUTED, BLACK, 6, 2, 1))
	b.add_theme_stylebox_override("pressed", _solid(MUTED))
	b.add_theme_stylebox_override("disabled", _box(DARK_GREY, BLACK, 6, 2, 1))
	b.add_theme_color_override("font_color", MUTED)
	b.add_theme_color_override("font_hover_color", WHITE)
	b.add_theme_color_override("font_pressed_color", BLACK)
	b.add_theme_color_override("font_disabled_color", DARK_GREY)
	return b


static func button(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(on_pressed)
	return b


static func header(text: String) -> Label:
	var label := line(text, YELLOW, SIZE_SMALL)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return label


static func panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.clip_contents = true
	return p


static func screen() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", screen_box())
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.clip_contents = true
	return p
