class_name UI
extends RefCounted
## Lockdown design system: palette, fonts, theme and reusable components.
## Every menu screen is built from these so the whole game looks consistent.

# --- Palette ---------------------------------------------------------------
const BG := Color("07090d")
const BG2 := Color("0d1118")
const PANEL := Color("11151d")
const PANEL_HI := Color("181e29")
const PANEL_LO := Color("0b0e14")
const BORDER := Color("242b38")
const TEXT := Color("eef1f6")
const TEXT_DIM := Color("8b94a7")
const TEXT_FAINT := Color("545d70")
const ACCENT := Color("ff7f2e") ## Orange: primary actions, headings.
const ACCENT2 := Color("38d0ff") ## Cyan: highlights, your team.
const GOOD := Color("4ade80")
const BAD := Color("f87171")
const WARN := Color("fbbf24")
const RADIUS := 4 ## Max corner radius: sharp, tactical look.

static var _fonts := {}


# --- Fonts -------------------------------------------------------------------

static func font(weight: int = 400) -> Font:
	if _fonts.has(weight):
		return _fonts[weight]
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial"])
	f.font_weight = weight
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.hinting = TextServer.HINTING_NORMAL
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	f.generate_mipmaps = false
	_fonts[weight] = f
	return f


static var _spaced := {}


## Letter-spaced variant for captions and headings.
static func font_spaced(weight: int, spacing: int = 1) -> Font:
	var key := weight * 100 + spacing
	if _spaced.has(key):
		return _spaced[key]
	var f := FontVariation.new()
	f.base_font = font(weight)
	f.spacing_glyph = spacing
	_spaced[key] = f
	return f


# --- Theme -------------------------------------------------------------------

static func _box(bg: Color, radius: int = 6, border: Color = Color(0, 0, 0, 0), border_w: int = 0, mx: int = 14, my: int = 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(mini(radius, RADIUS))
	if border_w > 0:
		sb.border_color = border
		sb.set_border_width_all(border_w)
	sb.content_margin_left = mx
	sb.content_margin_right = mx
	sb.content_margin_top = my
	sb.content_margin_bottom = my
	sb.anti_aliasing = radius > 0
	sb.anti_aliasing_size = 0.5
	return sb


## Box with one thicker coloured edge (accent bars on buttons and nav).
static func _edge_box(bg: Color, edge: Color, side: int, width: int, _unused: Color = Color(0, 0, 0, 0), mx: int = 14, my: int = 8) -> StyleBoxFlat:
	var sb := _box(bg, 3, Color(0, 0, 0, 0), 0, mx, my)
	sb.border_color = edge
	if side == SIDE_LEFT:
		sb.border_width_left = width
	else:
		sb.border_width_bottom = width
	return sb


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font(400)
	t.default_font_size = 15
	t.set_color("font_color", "Label", TEXT)

	# Buttons (secondary by default): flat, 1px border, accent edge on hover.
	t.set_font("font", "Button", font(600))
	t.set_font_size("font_size", "Button", 15)
	t.set_stylebox("normal", "Button", _box(PANEL_HI, 3, BORDER, 1))
	var hover := _box(PANEL_HI.lightened(0.06), 3, Color(TEXT, 0.22), 1)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", _box(PANEL_LO, 3, ACCENT2, 1))
	t.set_stylebox("hover_pressed", "Button", _box(PANEL_LO, 3, ACCENT2, 1))
	t.set_stylebox("disabled", "Button", _box(Color(PANEL_HI, 0.45), 3, Color(BORDER, 0.5), 1))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", ACCENT2.lightened(0.4))
	t.set_color("font_hover_pressed_color", "Button", ACCENT2.lightened(0.4))
	t.set_color("font_disabled_color", "Button", TEXT_FAINT)

	_variation(t, "PrimaryButton", ACCENT, ACCENT.lightened(0.14), ACCENT.darkened(0.18), Color("140a02"))
	_variation(t, "DangerButton", Color("5a1f22"), Color("6e2428"), Color("451719"), Color("ffd5d5"))
	t.add_type("GhostButton")
	t.set_type_variation("GhostButton", "Button")
	t.set_stylebox("normal", "GhostButton", _box(Color(0, 0, 0, 0), 3))
	t.set_stylebox("hover", "GhostButton", _box(Color(1, 1, 1, 0.05), 3))
	t.set_stylebox("pressed", "GhostButton", _box(Color(1, 1, 1, 0.08), 3))
	t.set_stylebox("disabled", "GhostButton", _box(Color(0, 0, 0, 0), 3))
	t.set_color("font_color", "GhostButton", TEXT_DIM)
	t.set_color("font_hover_color", "GhostButton", TEXT)
	# Sidebar navigation item: accent bar on the left when selected.
	t.add_type("NavButton")
	t.set_type_variation("NavButton", "Button")
	t.set_stylebox("normal", "NavButton", _edge_box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), SIDE_LEFT, 3, Color(0, 0, 0, 0), 16, 10))
	t.set_stylebox("hover", "NavButton", _edge_box(Color(1, 1, 1, 0.045), Color(TEXT, 0.25), SIDE_LEFT, 3, Color(0, 0, 0, 0), 16, 10))
	t.set_stylebox("pressed", "NavButton", _edge_box(Color(ACCENT, 0.13), ACCENT, SIDE_LEFT, 3, Color(0, 0, 0, 0), 16, 10))
	t.set_stylebox("disabled", "NavButton", _edge_box(Color(ACCENT, 0.13), ACCENT, SIDE_LEFT, 3, Color(0, 0, 0, 0), 16, 10))
	t.set_color("font_color", "NavButton", TEXT_DIM)
	t.set_color("font_hover_color", "NavButton", TEXT)
	t.set_color("font_disabled_color", "NavButton", Color.WHITE)
	t.set_constant("h_separation", "NavButton", 10)

	# Panels / cards: flat, hairline border, soft drop shadow.
	var card := _box(PANEL, RADIUS, BORDER, 1, 18, 16)
	card.shadow_color = Color(0, 0, 0, 0.35)
	card.shadow_size = 10
	card.shadow_offset = Vector2(0, 3)
	t.set_stylebox("panel", "PanelContainer", card)
	t.add_type("FlatPanel")
	t.set_type_variation("FlatPanel", "PanelContainer")
	t.set_stylebox("panel", "FlatPanel", _box(Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0, 0, 0))

	# Inputs.
	t.set_stylebox("normal", "LineEdit", _box(PANEL_LO, 3, BORDER, 1, 12, 8))
	t.set_stylebox("focus", "LineEdit", _box(PANEL_LO, 3, ACCENT2.darkened(0.15), 1, 12, 8))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_FAINT)
	t.set_color("caret_color", "LineEdit", ACCENT2)
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		t.set_stylebox(st, "OptionButton", t.get_stylebox(st if st != "focus" else "normal", "Button"))
	t.set_font("font", "OptionButton", font(500))
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		t.set_stylebox(st, "MenuButton", t.get_stylebox(st if st != "focus" else "normal", "Button"))
	t.set_font("font", "MenuButton", font(600))
	t.set_color("font_color", "MenuButton", TEXT)
	t.set_color("font_hover_color", "MenuButton", Color.WHITE)
	var pop := _box(PANEL_HI, 3, BORDER.lightened(0.1), 1, 4, 4)
	pop.shadow_color = Color(0, 0, 0, 0.5)
	pop.shadow_size = 12
	t.set_stylebox("panel", "PopupMenu", pop)
	t.set_stylebox("hover", "PopupMenu", _edge_box(Color(ACCENT2, 0.14), ACCENT2, SIDE_LEFT, 2, Color(0, 0, 0, 0), 8, 4))
	t.set_color("font_color", "PopupMenu", TEXT_DIM)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_font("font", "PopupMenu", font(500))
	t.set_constant("v_separation", "PopupMenu", 8)
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		t.set_stylebox(st, "CheckBox", StyleBoxEmpty.new())
	t.set_icon("unchecked", "CheckBox", _check_icon(false))
	t.set_icon("checked", "CheckBox", _check_icon(true))
	t.set_constant("h_separation", "CheckBox", 10)
	t.set_color("font_color", "CheckBox", TEXT_DIM)
	t.set_color("font_hover_color", "CheckBox", Color.WHITE)
	t.set_color("font_pressed_color", "CheckBox", TEXT)
	t.set_color("font_hover_pressed_color", "CheckBox", Color.WHITE)

	# Sliders / bars / scrollbars.
	t.set_stylebox("slider", "HSlider", _box(PANEL_HI, 2, BORDER, 1, 0, 2))
	t.set_stylebox("grabber_area", "HSlider", _box(ACCENT2.darkened(0.15), 2, Color(0, 0, 0, 0), 0, 0, 2))
	t.set_stylebox("grabber_area_highlight", "HSlider", _box(ACCENT2, 2, Color(0, 0, 0, 0), 0, 0, 2))
	t.set_icon("grabber", "HSlider", _grabber_icon(false))
	t.set_icon("grabber_highlight", "HSlider", _grabber_icon(true))
	t.set_stylebox("background", "ProgressBar", _box(Color(1, 1, 1, 0.06), 2, Color(0, 0, 0, 0), 0, 0, 0))
	t.set_stylebox("fill", "ProgressBar", _box(ACCENT, 2, Color(0, 0, 0, 0), 0, 0, 0))
	var sb_track := _box(Color(0, 0, 0, 0), 2, Color(0, 0, 0, 0), 0, 3, 3)
	var sb_grab := _box(BORDER.lightened(0.12), 2, Color(0, 0, 0, 0), 0, 3, 3)
	var sb_grab_hi := _box(TEXT_FAINT.lightened(0.1), 2, Color(0, 0, 0, 0), 0, 3, 3)
	for sbt in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", sbt, sb_track)
		t.set_stylebox("grabber", sbt, sb_grab)
		t.set_stylebox("grabber_highlight", sbt, sb_grab_hi)
		t.set_stylebox("grabber_pressed", sbt, sb_grab_hi)
	var tip := _box(Color("1c2230"), 3, BORDER.lightened(0.15), 1, 10, 7)
	tip.shadow_color = Color(0, 0, 0, 0.45)
	tip.shadow_size = 8
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font_size("font_size", "TooltipLabel", 14)
	# Dialogs.
	t.set_stylebox("panel", "AcceptDialog", _box(PANEL, RADIUS, BORDER, 1, 16, 14))
	return t


## Slider handle: a small square with a dark outline (drawn in code).
static func _grabber_icon(hot: bool) -> ImageTexture:
	var n := 14
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var fill := Color.WHITE if hot else Color("dfe5ee")
	for y in range(1, n - 1):
		for x in range(1, n - 1):
			var edge := x == 1 or y == 1 or x == n - 2 or y == n - 2
			img.set_pixel(x, y, Color(BG, 0.9) if edge else fill)
	return ImageTexture.create_from_image(img)


## Checkbox icons drawn in code: outlined box / filled cyan box with a tick.
static func _check_icon(on: bool) -> ImageTexture:
	var n := 18
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var edge := ACCENT2 if on else TEXT_FAINT
	for y in n:
		for x in n:
			var border := x < 2 or y < 2 or x >= n - 2 or y >= n - 2
			var corner := (x < 1 or x >= n - 1) and (y < 1 or y >= n - 1)
			if corner:
				continue
			if border:
				img.set_pixel(x, y, edge)
			elif on:
				img.set_pixel(x, y, Color(ACCENT2, 0.85))
	if on:
		# Tick.
		for i in 4:
			for t in 2:
				img.set_pixel(4 + i, 8 + i + t, BG)
		for i in 7:
			for t in 2:
				img.set_pixel(7 + i, 11 - i + t, BG)
	return ImageTexture.create_from_image(img)


static func _variation(t: Theme, name: String, bg: Color, hover: Color, pressed: Color, fg: Color) -> void:
	t.add_type(name)
	t.set_type_variation(name, "Button")
	t.set_stylebox("normal", name, _edge_box(bg, bg.darkened(0.3), SIDE_BOTTOM, 2))
	t.set_stylebox("hover", name, _edge_box(hover, hover.darkened(0.3), SIDE_BOTTOM, 2))
	t.set_stylebox("pressed", name, _box(pressed, 3))
	t.set_stylebox("hover_pressed", name, _box(pressed, 3))
	t.set_stylebox("disabled", name, _box(Color(bg.darkened(0.55), 0.6), 3))
	t.set_color("font_color", name, fg)
	t.set_color("font_hover_color", name, fg)
	t.set_color("font_pressed_color", name, fg)
	t.set_color("font_hover_pressed_color", name, fg)
	t.set_color("font_disabled_color", name, Color(TEXT_FAINT, 0.9))


# --- Screen setup ------------------------------------------------------------

## Makes `screen` fill the window, applies the theme and adds the backdrop.
static func setup_screen(screen: Control) -> void:
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.theme = make_theme()
	var bg := Backdrop.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(bg)


## Gradient + hairline tactical grid + soft edge vignette.
class Backdrop extends Control:
	func _draw() -> void:
		var s := size
		var top := UI.BG2
		var bottom := UI.BG
		draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0), s, Vector2(0, s.y)]),
			PackedColorArray([top, top, bottom, bottom]))
		# Width -1 = one physical pixel at any UI scale (never blurry).
		var step := 40.0
		var grid := Color(1, 1, 1, 0.024)
		var x := step
		while x < s.x:
			draw_line(Vector2(x, 0), Vector2(x, s.y), grid, -1.0)
			x += step
		var y := step
		while y < s.y:
			draw_line(Vector2(0, y), Vector2(s.x, y), grid, -1.0)
			y += step
		# Faint warm light from the top-left corner.
		var glow := Color(UI.ACCENT, 0.05)
		var clear := Color(UI.ACCENT, 0.0)
		draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(s.x * 0.55, 0), Vector2(0, s.y * 0.7)]),
			PackedColorArray([glow, clear, clear]))
		# Dark edges.
		var edge := Color(0, 0, 0, 0.45)
		var none := Color(0, 0, 0, 0)
		var e := 140.0
		draw_polygon(PackedVector2Array([Vector2(0, s.y - e), Vector2(s.x, s.y - e), s, Vector2(0, s.y)]),
			PackedColorArray([none, none, edge, edge]))
		draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(e, 0), Vector2(e, s.y), Vector2(0, s.y)]),
			PackedColorArray([Color(0, 0, 0, 0.25), none, none, Color(0, 0, 0, 0.25)]))
		draw_polygon(PackedVector2Array([Vector2(s.x - e, 0), Vector2(s.x, 0), s, Vector2(s.x - e, s.y)]),
			PackedColorArray([none, Color(0, 0, 0, 0.25), Color(0, 0, 0, 0.25), none]))

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()


# --- Text --------------------------------------------------------------------

static func label(text: String, size: int = 15, color: Color = TEXT, weight: int = 400) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if weight != 400:
		l.add_theme_font_override("font", font(weight))
	return l


static func heading(text: String, size: int = 30, color: Color = TEXT) -> Label:
	var l := label(text.to_upper(), size, color, 700)
	l.add_theme_font_override("font", font_spaced(700, 2 if size >= 24 else 1))
	return l


static func caption(text: String, color: Color = TEXT_DIM) -> Label:
	var l := label(text.to_upper(), 12, color, 600)
	l.add_theme_font_override("font", font_spaced(600, 1))
	return l


# --- Buttons -----------------------------------------------------------------

static func button(text: String, cb: Callable, min_width: int = 220, kind: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, 42)
	if kind != "":
		b.theme_type_variation = kind
	b.pressed.connect(cb)
	return b


static func small_button(text: String, cb: Callable, min_width: int = 80, kind: String = "") -> Button:
	var b := button(text, cb, min_width, kind)
	b.custom_minimum_size.y = 30
	b.add_theme_font_size_override("font_size", 13)
	return b


## Big title-screen entry: bold title, dim subtitle, accent edge and a chevron.
## Slides right a touch on hover. `primary` keeps the accent edge lit.
static func menu_item(title: String, subtitle: String, cb: Callable, primary: bool = false) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(420, 64 if subtitle != "" else 48)
	b.focus_mode = Control.FOCUS_NONE
	var edge := ACCENT if primary else Color(TEXT, 0.12)
	b.add_theme_stylebox_override("normal", _edge_box(Color(ACCENT, 0.08) if primary else Color(1, 1, 1, 0.025), edge, SIDE_LEFT, 3))
	b.add_theme_stylebox_override("hover", _edge_box(Color(ACCENT, 0.16) if primary else Color(1, 1, 1, 0.06), ACCENT, SIDE_LEFT, 3))
	b.add_theme_stylebox_override("pressed", _edge_box(Color(ACCENT, 0.24), ACCENT, SIDE_LEFT, 3))
	b.add_theme_stylebox_override("hover_pressed", _edge_box(Color(ACCENT, 0.24), ACCENT, SIDE_LEFT, 3))
	if primary:
		b.set_meta("ui_sound", "confirm")
	var row := hbox(12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 22
	row.offset_right = -18
	b.add_child(row)
	var texts := vbox(1)
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(texts)
	var t := label(title.to_upper(), 20, TEXT, 700)
	t.add_theme_font_override("font", font_spaced(700, 1))
	texts.add_child(t)
	if subtitle != "":
		texts.add_child(label(subtitle, 13, TEXT_DIM, 500))
	var chev := label("›", 26, Color(TEXT, 0.25), 400)
	chev.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chev.size_flags_vertical = Control.SIZE_FILL
	row.add_child(chev)
	for c in [t, chev]:
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.mouse_entered.connect(func() -> void:
		t.add_theme_color_override("font_color", Color.WHITE)
		chev.add_theme_color_override("font_color", ACCENT)
		b.create_tween().tween_property(row, "offset_left", 30.0, 0.09))
	b.mouse_exited.connect(func() -> void:
		t.add_theme_color_override("font_color", TEXT)
		chev.add_theme_color_override("font_color", Color(TEXT, 0.25))
		b.create_tween().tween_property(row, "offset_left", 22.0, 0.12))
	b.pressed.connect(cb)
	return b


# --- Layout ------------------------------------------------------------------

static func panel() -> PanelContainer:
	return PanelContainer.new()


static func vbox(sep: int = 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep: int = 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func spacer(expand_h: bool = true) -> Control:
	var c := Control.new()
	if expand_h:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


static func gap(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


## A card with an optional titled header. Returns the content container.
static func card(parent: Control, title: String = "", expand_v: bool = false, accent: Color = ACCENT) -> VBoxContainer:
	var p := PanelContainer.new()
	if expand_v:
		p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(p)
	var v := vbox(8)
	p.add_child(v)
	if title != "":
		var head := hbox(8)
		var bar := ColorRect.new()
		bar.color = accent
		bar.custom_minimum_size = Vector2(2, 12)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(bar)
		head.add_child(caption(title, Color(TEXT, 0.92)))
		v.add_child(head)
	return v


static func scroll(child: Control) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(child)
	# Keep a table header (the previous sibling) aligned with rows when the
	# scrollbar appears and narrows them.
	var bar := s.get_v_scroll_bar()
	var sync := func() -> void:
		var par := s.get_parent()
		if par == null or s.get_index() == 0:
			return
		var head := par.get_child(s.get_index() - 1)
		if head.has_meta("table_header"):
			var pad: Control = head.get_node("ScrollPad")
			var sep := (head as HBoxContainer).get_theme_constant("separation")
			pad.visible = bar.visible
			pad.custom_minimum_size.x = maxf(0.0, maxf(bar.size.x, bar.get_combined_minimum_size().x) + 6.0 - sep) # Rows: 6px panel margin.
	bar.visibility_changed.connect(sync)
	bar.resized.connect(sync)
	s.ready.connect(sync)
	return s


static func center_in(screen: Control, content: Control) -> CenterContainer:
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(c)
	c.add_child(content)
	return c


static func divider() -> ColorRect:
	var r := ColorRect.new()
	r.color = BORDER
	r.custom_minimum_size = Vector2(0, 1)
	return r


# --- Badges, chips, pills ----------------------------------------------------

static func rating_color(v: float) -> Color:
	if v >= 90.0:
		return Color("c084fc") # Elite (violet).
	if v >= 80.0:
		return ACCENT2
	if v >= 70.0:
		return GOOD
	if v >= 58.0:
		return WARN
	if v >= 45.0:
		return ACCENT
	return BAD


## Rounded chip with a rating number in its tier colour.
static func rating_chip(value: int, size: int = 14, min_w: int = 38) -> PanelContainer:
	var c := rating_color(value)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(Color(c, 0.14), 2, Color(c, 0.5), 1, 6, 2))
	p.custom_minimum_size = Vector2(min_w, 0)
	var l := label(str(value), size, c, 700)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return p


## Big rating badge (profile cards).
static func rating_badge(value: int, size: int = 54) -> PanelContainer:
	var c := rating_color(value)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _edge_box(Color(c, 0.12), c, SIDE_BOTTOM, 3, Color(0, 0, 0, 0), 14, 4))
	var v := vbox(-4)
	p.add_child(v)
	var n := label(str(value), size, c, 700)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(n)
	var cap := caption("rating", Color(c, 0.8))
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(cap)
	return p


## Team badge: tag on the team colour.
static func team_badge(tag: String, color: Color, size: int = 30) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(color.darkened(0.55), int(size * 0.22), color, 2, 4, 2))
	p.custom_minimum_size = Vector2(size * 1.55, size)
	var l := label(tag.to_upper(), int(size * 0.42), color.lightened(0.35), 700)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return p


const LOGO_STYLES := ["box", "round", "outline", "solid", "split"]


static func team_badge_for(t: TeamData, size: int = 30) -> PanelContainer:
	if t.logo.begins_with("img:"):
		var b := logo_badge(t.logo.substr(4), t.color, size)
		if b != null:
			return b
		return team_badge(t.short_name, t.color, size)
	if t.logo == "box" and t.color2.a == 0.0:
		return team_badge(t.short_name, t.color, size)
	return team_badge_styled(t.short_name, t.color, t.color2, t.logo, size)


## Team pack for new careers: "real", "og" or "" (fictional). Real teams by default.
static func team_pack() -> String:
	var p := String(Game.settings.get("team_pack", "real" if bool(Game.settings.get("real_teams", true)) else ""))
	if RealTeams.HIDDEN.has(p):
		p = "real"
	return p if RealTeams.available(p) else ""


## One checkbox per installed pack (Real teams / OG Teams); ticking one unticks
## the other, none ticked = fictional clubs. Null when no pack is installed.
static func team_pack_toggles(on_change: Callable) -> HBoxContainer:
	var packs := RealTeams.in_menus()
	if packs.is_empty():
		return null
	var row := hbox(10)
	var boxes: Array = []
	for pk: String in packs:
		var c := CheckBox.new()
		c.text = RealTeams.label(pk)
		c.button_pressed = team_pack() == pk
		c.focus_mode = Control.FOCUS_NONE
		var n := RealTeams.teams(pk).size()
		c.tooltip_text = "Start with the %s from the %s%s, with their players and logos." % [
			"top %d teams" % mini(n, 64), RealTeams.source(pk), "" if n >= 64 else " (generated clubs fill the rest of the 64)"]
		boxes.append(c)
		row.add_child(c)
		c.toggled.connect(func(on: bool) -> void:
			Game.settings["team_pack"] = pk if on else ""
			Game.save_settings()
			for o: CheckBox in boxes:
				if o != c:
					o.set_pressed_no_signal(false)
			on_change.call())
	return row


## A real team's logo image on a plate (null if the image is missing).
static func logo_badge(slug: String, color: Color, size: int = 30) -> PanelContainer:
	var tex := RealTeams.logo_texture(slug)
	if tex == null:
		return null
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(RealTeams.logo_bg(slug), int(size * 0.22), color, 2 if size >= 24 else 1, 3, 2))
	p.custom_minimum_size = Vector2(size * 1.55, size)
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(r)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return p


## Custom team logos (editor): shape and a second colour.
static func team_badge_styled(tag: String, color: Color, color2: Color, style: String, size: int = 30) -> PanelContainer:
	var c2 := color2 if color2.a > 0.0 else color.darkened(0.55)
	var bg := c2
	var border := color
	var fg := color.lightened(0.35)
	var radius := int(size * 0.22)
	var bw := 2
	match style:
		"round":
			radius = size
		"outline":
			bg = Color(0, 0, 0, 0)
			bw = 3
		"solid":
			bg = color
			border = c2
			fg = c2 if color2.a > 0.0 else color.darkened(0.7)
		"split":
			bg = c2
			border = color
			bw = 4
			fg = color
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(bg, radius, border, bw, 4, 2))
	p.custom_minimum_size = Vector2(size * 1.55, size)
	var l := label(tag.to_upper(), int(size * 0.42), fg, 700)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return p


## Team name with its badge.
static func team_label(t: TeamData, size: int = 15, highlight: bool = false) -> HBoxContainer:
	var h := hbox(8)
	h.add_child(team_badge_for(t, size + 9))
	h.add_child(label(t.team_name, size, ACCENT2 if highlight else TEXT, 600 if highlight else 500))
	return h


## Small rounded tag.
static func pill(text: String, color: Color, size: int = 12) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(Color(color, 0.12), 2, Color(color, 0.38), 1, 8, 2))
	var l := label(text.to_upper(), size, color, 600)
	l.add_theme_font_override("font", font_spaced(600, 1))
	p.add_child(l)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return p


## Caption-over-value stat (top bars, summaries).
static func stat_chip(cap: String, value: String, color: Color = TEXT) -> VBoxContainer:
	var v := vbox(0)
	v.add_child(caption(cap))
	v.add_child(label(value, 20, color, 700))
	return v


static func money_text(n: int) -> String:
	return ("-$" if n < 0 else "$") + World._fmt(absi(n))


# --- Attribute rows ----------------------------------------------------------

static func stat_row(key: String, value: float, delta: float = 0.0) -> HBoxContainer:
	var row := hbox(10)
	var name_l := label(PlayerData.STAT_NAMES[key], 14, TEXT_DIM, 500)
	name_l.custom_minimum_size = Vector2(130, 0)
	name_l.tooltip_text = PlayerData.stat_tooltip(key)
	name_l.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(name_l)
	var bar := ProgressBar.new()
	bar.min_value = PlayerData.MIN_STAT
	bar.max_value = PlayerData.MAX_STAT
	bar.value = value
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(150, 6)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_theme_stylebox_override("fill", _box(rating_color(value), 3, Color(0, 0, 0, 0), 0, 0, 0))
	row.add_child(bar)
	var val := label("%d" % int(round(value)), 15, rating_color(value), 700)
	val.custom_minimum_size = Vector2(28, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val)
	var d := label("%+.1f" % delta if absf(delta) >= 0.05 else "", 12, GOOD if delta > 0 else BAD, 600)
	d.custom_minimum_size = Vector2(34, 0)
	row.add_child(d)
	return row


# --- Tables ------------------------------------------------------------------

## cols: [[title, width, align]] with align "l", "r" or "c". width 0 = expand.
static func table_header(cols: Array) -> HBoxContainer:
	var h := hbox(6)
	var pad := Control.new() # + separation = the rows' 6px panel margin.
	h.add_child(pad)
	for c in cols:
		var l := caption(String(c[0]), TEXT_FAINT)
		_size_cell(l, c)
		_header_tip(l, String(c[0]))
		h.add_child(l)
	_scroll_pad(h)
	return h


## Trailing spacer that UI.scroll widens to the scrollbar's width.
static func _scroll_pad(h: HBoxContainer) -> void:
	var pad := Control.new()
	pad.name = "ScrollPad"
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.visible = false
	h.add_child(pad)
	h.set_meta("table_header", true)


static func _header_tip(ctrl: Control, title: String) -> void:
	var tip := PlayerData.column_tooltip(title)
	if tip != "":
		ctrl.tooltip_text = tip
		ctrl.mouse_filter = Control.MOUSE_FILTER_STOP
		if ctrl is Label:
			(ctrl as Label).add_theme_color_override("font_color", TEXT_DIM)


## Clickable header: cols are [title, width, align, sort_key]; sort_key "" = not sortable.
static func sort_header(cols: Array, sort_key: String, ascending: bool, on_sort: Callable) -> HBoxContainer:
	var h := hbox(6)
	var pad := Control.new() # + separation = the rows' 6px panel margin.
	h.add_child(pad)
	for c in cols:
		var key: String = c[3] if c.size() > 3 else ""
		if key == "":
			var l := caption(String(c[0]), TEXT_FAINT)
			_size_cell(l, c)
			_header_tip(l, String(c[0]))
			h.add_child(l)
			continue
		# A label (not a button) so its text lines up exactly with the cells below.
		var on := key == sort_key
		var l2 := caption(String(c[0]) + ((" ▲" if ascending else " ▼") if on else ""), ACCENT if on else TEXT_FAINT)
		_size_cell(l2, c)
		var tip := PlayerData.column_tooltip(String(c[0]))
		l2.tooltip_text = ("Click to sort.

" + tip) if tip != "" else "Sort by " + String(c[0])
		l2.mouse_filter = Control.MOUSE_FILTER_STOP
		l2.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var base := ACCENT if on else TEXT_FAINT
		l2.mouse_entered.connect(func() -> void: l2.add_theme_color_override("font_color", TEXT))
		l2.mouse_exited.connect(func() -> void: l2.add_theme_color_override("font_color", base))
		l2.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				if Game.ui_sounds != null:
					Game.ui_sounds.play("click")
				on_sort.call(key))
		h.add_child(l2)
	_scroll_pad(h)
	return h


## cells: Strings or Controls, one per column. Alternating backgrounds.
static func table_row(cells: Array, cols: Array, index: int, highlight: bool = false) -> PanelContainer:
	var p := PanelContainer.new()
	var bg := Color(ACCENT2, 0.10) if highlight else (Color(1, 1, 1, 0.025) if index % 2 == 0 else Color(0, 0, 0, 0))
	var sb := _edge_box(bg, ACCENT2, SIDE_LEFT, 2, Color(0, 0, 0, 0), 6, 4) if highlight else _box(bg, 2, Color(0, 0, 0, 0), 0, 6, 4)
	p.add_theme_stylebox_override("panel", sb)
	var h := hbox(6)
	p.add_child(h)
	for i in cells.size():
		var cell = cells[i]
		var c: Array = cols[i] if i < cols.size() else ["", 0, "l"]
		var ctrl: Control
		if cell is Control:
			ctrl = cell
		else:
			ctrl = label(String(cell), 14, TEXT)
		_size_cell(ctrl, c)
		h.add_child(ctrl)
	return p


static func _size_cell(ctrl: Control, c: Array) -> void:
	var w: int = c[1]
	if w > 0:
		ctrl.custom_minimum_size.x = w
	else:
		ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if ctrl is Label:
		var l := ctrl as Label
		l.clip_text = true
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if c[2] == "r" else (HORIZONTAL_ALIGNMENT_CENTER if c[2] == "c" else HORIZONTAL_ALIGNMENT_LEFT)
	elif c[2] != "l":
		ctrl.size_flags_horizontal = Control.SIZE_SHRINK_END if c[2] == "r" else Control.SIZE_SHRINK_CENTER


# --- Match results ---------------------------------------------------------------

const RESULT_COLS := [["Player", 0, "l"], ["RTG", 44, "c"], ["K", 34, "c"], ["D", 34, "c"], ["ADR", 44, "c"], ["Rating", 60, "c"], ["Stats", 64, "c"]]


## Full-screen results: VICTORY/DEFEAT, score, MVP and both teams' box scores.
## data: {teams, score, rows[2] of {name, rating, kills, deaths, adr, match_rating, is_user, change},
##        mvp, label, perspective, map}
static func results_overlay(parent: Control, data: Dictionary, on_continue: Callable) -> Control:
	var overlay := ColorRect.new()
	overlay.color = Color(BG, 0.86)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(overlay)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(Color(PANEL, 0.97), 14, Color(BORDER, 0.8), 1, 14, 8))
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -470
	panel.offset_right = 470
	panel.offset_top = -330
	panel.offset_bottom = 330
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	overlay.add_child(panel)
	var box := vbox(8)
	panel.add_child(box)

	var teams: Array = data.teams
	var score: Array = data.score
	var a: TeamData = teams[0]
	var b: TeamData = teams[1]
	var title := "DRAW"
	var title_col := WARN
	if score[0] != score[1]:
		var w := 0 if score[0] > score[1] else 1
		if data.perspective:
			title = "VICTORY" if w == 0 else "DEFEAT"
			title_col = GOOD if w == 0 else BAD
		else:
			title = "%s WIN" % (teams[w] as TeamData).team_name.to_upper()
			title_col = ACCENT

	var head := hbox(14)
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	var tl := label(title, 40, title_col, 700)
	head.add_child(tl)
	box.add_child(head)
	var sub := "%s%s" % [String(data.map), ("  -  " + String(data.label)) if String(data.label) != "" else ""]
	var sl := label(sub, 14, TEXT_DIM)
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sl)

	var sc := hbox(18)
	sc.alignment = BoxContainer.ALIGNMENT_CENTER
	sc.add_child(team_badge_for(a, 40))
	sc.add_child(label(a.team_name, 22, TEXT, 700))
	sc.add_child(label("%d  :  %d" % [score[0], score[1]], 38, TEXT, 700))
	sc.add_child(label(b.team_name, 22, TEXT, 700))
	sc.add_child(team_badge_for(b, 40))
	box.add_child(sc)
	var mvp := hbox(8)
	mvp.alignment = BoxContainer.ALIGNMENT_CENTER
	mvp.add_child(pill("MVP", WARN))
	mvp.add_child(label(String(data.mvp), 16, WARN, 700))
	box.add_child(mvp)

	var rows: Array = data.rows
	for t in 2:
		var team: TeamData = teams[t]
		var th := hbox(10)
		th.add_child(team_badge_for(team, 22))
		th.add_child(label(team.team_name, 16, TEXT, 700))
		box.add_child(th)
		box.add_child(table_header(RESULT_COLS))
		var i := 0
		for r: Dictionary in rows[t]:
			var mine: bool = r.is_user
			var mr: float = r.match_rating
			var ch_cell: Control
			if r.change == null:
				ch_cell = label("-", 13, TEXT_FAINT)
			else:
				var c := float(r.change)
				ch_cell = label("%+.1f" % c, 14, GOOD if c > 0.05 else (BAD if c < -0.05 else TEXT_DIM), 700)
			var name_l := label(("★ " if String(r.name) == String(data.mvp) else "") + String(r.name), 15, ACCENT2 if mine else TEXT, 600)
			box.add_child(table_row([name_l, rating_chip(int(r.rating), 13),
				label(str(r.kills), 15, TEXT, 700), label(str(r.deaths), 15, TEXT_DIM),
				label(str(r.adr), 14, TEXT_DIM),
				label("%.2f" % mr, 15, GOOD if mr >= 1.1 else (BAD if mr < 0.85 else TEXT), 700),
				ch_cell], RESULT_COLS, i, mine))
			i += 1
	box.add_child(spacer())
	var foot := hbox(10)
	foot.add_child(label("Stats = total attribute change from this match.", 12, TEXT_FAINT))
	foot.add_child(spacer())
	foot.add_child(button("Continue", on_continue, 200, "PrimaryButton"))
	box.add_child(foot)
	return overlay


# --- Squad table / modal ------------------------------------------------------

const SQUAD_COLS := [["Player", 0, "l"], ["Role", 62, "l"], ["Age", 30, "c"], ["RTG", 42, "c"], ["Pot.", 50, "l"],
	["Aim", 28, "c"], ["Flk", 28, "c"], ["Pre", 28, "c"], ["Rcl", 28, "c"], ["Rct", 28, "c"], ["Mov", 28, "c"], ["Pos", 28, "c"], ["Dec", 28, "c"], ["Utl", 28, "c"]]


static func potential_text(p: PlayerData) -> String:
	var gap := p.potential - p.rating()
	if gap >= 20:
		return "Elite"
	if gap >= 12:
		return "High"
	if gap >= 6:
		return "Good"
	if gap >= 2:
		return "Some"
	return "Peaked"


## Flat text button (looks like a label, highlights on hover).
static func link_button(text: String, cb: Callable, size: int = 14, color: Color = TEXT, weight: int = 600) -> Button:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text = text
	b.clip_text = true
	b.add_theme_font_override("font", font(weight))
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", color)
	b.add_theme_color_override("font_hover_color", ACCENT2)
	b.add_theme_color_override("font_pressed_color", ACCENT2)
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		b.add_theme_stylebox_override(st, empty)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(cb)
	return b


## Team badge + name that opens something (usually the team popup) when clicked.
static func team_link(t: TeamData, cb: Callable, size: int = 14, highlight: bool = false) -> HBoxContainer:
	var h := hbox(8)
	h.add_child(team_badge_for(t, size + 9))
	var b := link_button(t.team_name, cb, size, ACCENT2 if highlight else TEXT, 600 if highlight else 500)
	b.tooltip_text = "View %s" % t.team_name
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(b)
	return h


## A team's players with every attribute. First `starters` rows are the lineup.
## on_player(p): makes names clickable (player card).
static func squad_table(players: Array, highlight: PlayerData = null, starters: int = 5, on_player: Callable = Callable()) -> VBoxContainer:
	var v := vbox(2)
	v.add_child(table_header(SQUAD_COLS))
	for i in players.size():
		var p: PlayerData = players[i]
		if i == starters and players.size() > starters:
			v.add_child(caption("   Bench", TEXT_FAINT))
		var mine := p == highlight
		var nm := p.player_name + ("  (you)" if mine else "")
		var ncol := ACCENT2 if mine else (TEXT if i < starters else TEXT_DIM)
		var name_cell: Control = label(nm, 14, ncol, 600)
		if on_player.is_valid():
			var pp := p
			name_cell = link_button(nm, func() -> void: on_player.call(pp), 14, ncol)
		var cells: Array = [name_cell,
			label(p.role, 12, TEXT_FAINT), label(str(p.age), 13, TEXT_DIM), rating_chip(p.rating(), 13), label(potential_text(p), 12, TEXT_DIM)]
		for k: String in PlayerData.STAT_KEYS:
			cells.append(label(str(int(round(p.stat(k)))), 13, rating_color(p.stat(k)), 600))
		v.add_child(table_row(cells, SQUAD_COLS, i, mine))
	return v


## Centered popup over `parent`. Returns [overlay, content_vbox]; free the overlay to close.
## Clicking the dimmed backdrop closes it too.
static func modal(parent: Control, width: int = 880, accent: Color = ACCENT2) -> Array:
	var overlay := ColorRect.new()
	overlay.color = Color(BG, 0.78)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(PANEL, 14, accent, 1, 22, 18))
	panel.custom_minimum_size = Vector2(width, 0)
	center.add_child(panel)
	var box := vbox(10)
	panel.add_child(box)
	overlay.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT \
				and not panel.get_global_rect().has_point(ev.global_position):
			overlay.queue_free())
	return [overlay, box]


const TEAM_STATS_COLS := [["Player", 0, "l"], ["Role", 62, "l"], ["Form", 70, "l"], ["M", 32, "c"], ["K", 40, "c"], ["D", 40, "c"],
	["K/D", 44, "c"], ["Avg", 46, "c"], ["Last 5", 150, "l"], ["Career K/D", 76, "c"], ["Titles", 46, "c"]]


## Season numbers for a squad: form, matches, K/D, average rating, recent results.
static func team_stats_table(players: Array, highlight: PlayerData = null, on_player: Callable = Callable()) -> VBoxContainer:
	var v := vbox(2)
	v.add_child(table_header(TEAM_STATS_COLS))
	for i in players.size():
		var p: PlayerData = players[i]
		var mine := p == highlight
		var name_cell: Control = label(p.player_name, 14, ACCENT2 if mine else TEXT, 600)
		if on_player.is_valid():
			var pp := p
			name_cell = link_button(p.player_name, func() -> void: on_player.call(pp), 14, ACCENT2 if mine else TEXT)
		var ss := p.season_stats
		var m := int(ss.get("m", 0))
		var avg := p.season_avg_rating()
		var last := hbox(3)
		for e: Dictionary in p.match_log.slice(maxi(0, p.match_log.size() - 5)):
			var r := float(e.get("r", 1.0))
			last.add_child(label("%.2f" % r, 11, GOOD if r >= 1.1 else (BAD if r < 0.85 else TEXT_DIM), 600))
		v.add_child(table_row([name_cell, label(p.role, 12, TEXT_FAINT), pill(p.form_text(), p.form_color(), 10),
			label(str(m), 13, TEXT_DIM), label(str(int(ss.get("k", 0))), 13, TEXT), label(str(int(ss.get("d", 0))), 13, TEXT_DIM),
			label("%.2f" % p.season_kd() if m > 0 else "-", 13, TEXT, 600),
			label("%.2f" % avg if m > 0 else "-", 13, GOOD if avg >= 1.1 else (BAD if avg < 0.85 and m > 0 else TEXT), 700),
			last, label("%.2f" % p.career_kd(), 13, TEXT_DIM), label(str(p.titles), 13, WARN if p.titles > 0 else TEXT_FAINT)],
			TEAM_STATS_COLS, i, mine))
	return v


## Popup describing a team: league, standing, record, squad attributes and
## season stats (tabs). on_player(p) makes names open the player card.
static func team_popup(parent: Control, w: World, t: TeamData, highlight: PlayerData = null, on_player: Callable = Callable()) -> Array:
	var m := modal(parent, 980)
	var box: VBoxContainer = m[1]
	var head := hbox(14)
	head.add_child(team_badge_for(t, 52))
	var info := vbox(4)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(label(t.team_name, 28, TEXT, 700))
	var pills := HFlowContainer.new()
	pills.add_theme_constant_override("h_separation", 6)
	pills.add_theme_constant_override("v_separation", 4)
	var table := w.standings(t.league)
	pills.add_child(pill(w.league_name(t), ACCENT2))
	pills.add_child(pill("#%d of %d" % [table.find(t) + 1, table.size()], TEXT_DIM))
	pills.add_child(pill("%d-%d" % [t.wins, t.losses], TEXT_DIM))
	pills.add_child(pill("World #%d" % w.world_rank(t), TEXT_DIM))
	var style := Tactics.team_style(t.team_name)
	var sp := pill("Style: " + Tactics.team_style_text(style), WARN)
	sp.tooltip_text = "How this team plays in matches: strat choices, aggression, utility and AWP use."
	pills.add_child(sp)
	info.add_child(pills)
	head.add_child(info)
	head.add_child(stat_chip("Team RTG", str(t.rating()), rating_color(t.rating())))
	head.add_child(stat_chip("Reputation", str(int(t.reputation))))
	head.add_child(stat_chip("Titles", str(t.titles), WARN if t.titles > 0 else TEXT))
	box.add_child(head)
	var facts := hbox(16)
	var rd := "%+d" % t.round_diff
	var streak := ("W%d" % t.streak) if t.streak > 0 else (("L%d" % -t.streak) if t.streak < 0 else "-")
	for f in [["Round diff", rd], ["Streak", streak], ["Ranking pts", str(t.points)], ["Sponsor", t.sponsor_name if t.sponsor_name != "" else "-"]]:
		var fh := hbox(6)
		fh.add_child(caption(f[0], TEXT_FAINT))
		fh.add_child(label(f[1], 13, TEXT_DIM, 600))
		facts.add_child(fh)
	box.add_child(facts)
	box.add_child(divider())
	var tabs := hbox(6)
	box.add_child(tabs)
	var holder := vbox(0)
	box.add_child(holder)
	var show_tab := func(which: String) -> void:
		for c in holder.get_children():
			c.queue_free()
		holder.add_child(squad_table(t.roster, highlight, 5, on_player) if which == "Squad" else team_stats_table(t.roster, highlight, on_player))
		for b: Button in tabs.get_children():
			b.theme_type_variation = "PrimaryButton" if b.text == which else ""
	for name in ["Squad", "Season stats"]:
		var nm: String = name
		tabs.add_child(small_button(nm, func() -> void: show_tab.call(nm), 120))
	show_tab.call("Squad")
	if on_player.is_valid():
		box.add_child(label("Click a player for their card and match history.", 12, TEXT_FAINT))
	return m


const HISTORY_COLS := [["When", 62, "l"], ["Event", 0, "l"], ["Opponent", 150, "l"], ["Res", 64, "c"], ["K", 32, "c"], ["D", 32, "c"],
	["ADR", 40, "c"], ["Rating", 54, "c"], ["Day", 44, "c"]]


## Player card: attributes, form, morale, contract, career numbers and match
## history. Returns [overlay, box] so callers can add buttons.
static func player_card(parent: Control, w: World, p: PlayerData) -> Array:
	var m := modal(parent, 980)
	var box: VBoxContainer = m[1]
	var owner := w.owner_of(p)
	var head := hbox(14)
	head.add_child(rating_badge(p.rating(), 46))
	var info := vbox(4)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(label(p.player_name, 28, TEXT, 700))
	var pills := HFlowContainer.new() # Wraps: many tags must never widen the card.
	pills.add_theme_constant_override("h_separation", 6)
	pills.add_theme_constant_override("v_separation", 4)
	pills.add_child(pill(p.role, ACCENT2))
	pills.add_child(pill("Age %d" % p.age, TEXT_DIM))
	pills.add_child(pill("Potential: " + potential_text(p), WARN))
	pills.add_child(pill(owner.team_name if owner != null else "Free agent", TEXT_DIM))
	pills.add_child(pill("Form: " + p.form_text(), p.form_color()))
	var mc := GOOD if p.morale >= 60.0 else (WARN if p.morale >= 35.0 else BAD)
	pills.add_child(pill("Morale: " + p.morale_text(), mc))
	for h: String in BotPersonality.habits(p):
		var hp := pill(BotPersonality.habit_text(h), Color("c084fc"))
		hp.tooltip_text = "In-match habit"
		pills.add_child(hp)
	var pe := PlayerData.persona_of(p)
	if pe != "":
		var pp := pill("Personality: " + pe, WARN)
		pp.tooltip_text = String(PlayerData.PERSONA_TEXT[pe])
		pills.add_child(pp)
	if p.loan_from != "":
		pills.add_child(pill("On loan", ACCENT2))
	info.add_child(pills)
	head.add_child(info)
	head.add_child(stat_chip("Wage / wk", money_text(p.salary if owner != null else PlayerData.salary_for_rating(p.rating_exact()))))
	head.add_child(stat_chip("Value", money_text(p.market_value())))
	head.add_child(stat_chip("Contract", ("S%d" % p.contract_until) if owner != null else "-"))
	box.add_child(head)
	box.add_child(divider())

	var cols := hbox(22)
	box.add_child(cols)
	var attrs := vbox(4)
	attrs.custom_minimum_size = Vector2(380, 0)
	attrs.add_child(caption("Attributes", TEXT))
	for k: String in PlayerData.STAT_KEYS:
		attrs.add_child(stat_row(k, p.stat(k)))
	cols.add_child(attrs)
	var right := vbox(8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	right.add_child(caption("Career", TEXT))
	var chips := hbox(18)
	var m_count := int(p.season_stats.get("m", 0))
	for c in [["Matches", str(p.matches_played)], ["Kills", str(p.career_kills)], ["K/D", "%.2f" % p.career_kd()],
			["Last 5 avg", "%.2f" % p.avg_recent_rating()], ["Titles", str(p.titles)]]:
		chips.add_child(stat_chip(c[0], c[1]))
	right.add_child(chips)
	right.add_child(caption("This season", TEXT))
	var chips2 := hbox(18)
	for c in [["Matches", str(m_count)], ["K-D", "%d-%d" % [int(p.season_stats.get("k", 0)), int(p.season_stats.get("d", 0))]],
			["K/D", "%.2f" % p.season_kd() if m_count > 0 else "-"], ["Avg rating", "%.2f" % p.season_avg_rating() if m_count > 0 else "-"]]:
		chips2.add_child(stat_chip(c[0], c[1]))
	right.add_child(chips2)
	var fm := "Form %+.1f: %s. Form moves with results, morale and luck; slumps and hot streaks come and go." % [p.form, p.form_text().to_lower()]
	var fl := label(fm, 12, TEXT_FAINT)
	fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(fl)
	var ml := label("Morale %d: %s. Benched players and losing streaks get unhappy; happy players play into form." % [int(p.morale), p.morale_text().to_lower()], 12, TEXT_FAINT)
	ml.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(ml)

	box.add_child(caption("Match history", TEXT))
	var hist := vbox(2)
	hist.add_child(table_header(HISTORY_COLS))
	var list := vbox(2)
	var n := 0
	for i in range(p.match_log.size() - 1, -1, -1):
		var e: Dictionary = p.match_log[i]
		var r := float(e.get("r", 1.0))
		var res := String(e.get("res", "?"))
		var mod := float(e.get("mod", 0.0))
		list.add_child(table_row([label("S%d W%d" % [int(e.get("s", 0)), int(e.get("w", 0))], 12, TEXT_FAINT),
			_clip(label(String(e.get("label", "")), 12, TEXT_DIM)), _clip(label(String(e.get("opp", "")), 13, TEXT)),
			label("%s %s" % [res, String(e.get("score", ""))], 13, GOOD if res == "W" else (BAD if res == "L" else WARN), 600),
			label(str(int(e.get("k", 0))), 13, TEXT, 600), label(str(int(e.get("d", 0))), 13, TEXT_DIM),
			label(str(int(e.get("adr", 0))), 13, TEXT_DIM),
			label("%.2f" % r, 13, GOOD if r >= 1.1 else (BAD if r < 0.85 else TEXT), 700),
			label("bad" if mod <= -3.0 else ("great" if mod >= 3.0 else ""), 11, BAD if mod <= -3.0 else GOOD, 600)], HISTORY_COLS, n))
		n += 1
	if p.match_log.is_empty():
		list.add_child(label("No matches played yet.", 13, TEXT_DIM))
	var sc := scroll(list)
	sc.custom_minimum_size = Vector2(0, 190)
	hist.add_child(sc)
	box.add_child(hist)
	return m


## Small form dialog: fields = [[label, initial, max_len]]. on_ok(values) returns
## "" to close, or an error to show.
static func text_prompt(parent: Control, title: String, fields: Array, on_ok: Callable) -> void:
	var m := modal(parent, 460)
	var overlay: Control = m[0]
	var box: VBoxContainer = m[1]
	box.add_child(heading(title, 20))
	var edits: Array = []
	for f in fields:
		box.add_child(caption(String(f[0])))
		var le := LineEdit.new()
		le.text = String(f[1])
		le.max_length = int(f[2])
		le.custom_minimum_size = Vector2(0, 36)
		box.add_child(le)
		edits.append(le)
	var err := label("", 13, BAD, 600)
	box.add_child(err)
	var row := hbox(10)
	row.add_child(button("Cancel", func() -> void: overlay.queue_free(), 140, "GhostButton"))
	row.add_child(spacer())
	var submit := func() -> void:
		var vals: Array = []
		for le: LineEdit in edits:
			vals.append(le.text)
		var e: String = on_ok.call(vals)
		if e == "":
			overlay.queue_free()
		else:
			err.text = e
	row.add_child(button("Save", submit, 160, "PrimaryButton"))
	box.add_child(row)
	for le: LineEdit in edits:
		le.text_submitted.connect(func(_t: String) -> void: submit.call())
	if not edits.is_empty():
		(edits[0] as LineEdit).call_deferred("grab_focus")
		(edits[0] as LineEdit).call_deferred("select_all")


## Sidebar navigation: returns the VBox; `current` item shown as selected.
static func nav(items: Array, current: String, on_pick: Callable, badges: Dictionary = {}) -> VBoxContainer:
	var v := vbox(4)
	for it in items:
		var name: String = it
		var b := Button.new()
		b.text = name + (("   %d" % int(badges[name])) if int(badges.get(name, 0)) > 0 else "")
		if int(badges.get(name, 0)) > 0:
			b.add_theme_color_override("font_color", ACCENT2)
		b.theme_type_variation = "NavButton"
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(190, 40)
		b.disabled = name == current
		b.pressed.connect(func() -> void: on_pick.call(name))
		v.add_child(b)
	return v


## Classic bracket: each match sits between the two it came from, joined by lines.
static func bracket(w: World, t: Dictionary, on_team: Callable) -> Control:
	var size: int = t.size
	var rounds := int(round(log(float(size)) / log(2.0)))
	var ui := w.team_index(w.user_team())
	var box_w := 178.0
	var box_h := 40.0
	var gap_x := 30.0
	var slot := 46.0
	var head := 20.0
	var first_n := size / 2
	var holder := Control.new()
	var done: bool = t.status == "done"
	holder.custom_minimum_size = Vector2(rounds * (box_w + gap_x) + (box_w * 0.8 if done else 0.0), head + first_n * slot)
	var lines: Array = []
	for r in rounds:
		var n := first_n >> r
		var x := r * (box_w + gap_x)
		var cap := caption(World.stage_name(size, r) + ("s" if n in [2, 4] else ""), TEXT_FAINT)
		cap.position = Vector2(x, 0)
		holder.add_child(cap)
		var span := slot * float(1 << r)
		for k in n:
			var cy := head + (k + 0.5) * span
			var mt: Dictionary = t.rounds[r][k] if r < t.rounds.size() and k < (t.rounds[r] as Array).size() else {}
			var panel: Control = _bracket_match(w, mt, ui, on_team) if not mt.is_empty() else _bracket_tbd()
			panel.position = Vector2(x, cy - box_h * 0.5)
			panel.custom_minimum_size = Vector2(box_w, box_h)
			holder.add_child(panel)
			if r > 0:
				var half := slot * float(1 << (r - 1))
				var y1 := head + (2 * k + 0.5) * half
				var y2 := head + (2 * k + 1.5) * half
				var mx := x - gap_x * 0.5
				lines.append([Vector2(x - gap_x, y1), Vector2(mx, y1)])
				lines.append([Vector2(x - gap_x, y2), Vector2(mx, y2)])
				lines.append([Vector2(mx, y1), Vector2(mx, y2)])
				lines.append([Vector2(mx, cy), Vector2(x, cy)])
	if done:
		var champ: TeamData = w.teams[w._team_with_place(t, 1)]
		var cx := rounds * (box_w + gap_x)
		var cy2 := head + first_n * slot * 0.5
		var cp := PanelContainer.new()
		cp.add_theme_stylebox_override("panel", _box(Color(WARN, 0.12), 4, WARN, 1, 10, 6))
		var cv := vbox(0)
		cv.add_child(caption("Champion", WARN))
		cv.add_child(link_button(champ.team_name, on_team.bind(champ), 13, TEXT, 700))
		cp.add_child(cv)
		cp.position = Vector2(cx, cy2 - 24)
		cp.custom_minimum_size = Vector2(box_w * 0.8, 48)
		holder.add_child(cp)
		lines.append([Vector2(cx - gap_x, cy2), Vector2(cx, cy2)])
	holder.draw.connect(func() -> void:
		for seg in lines:
			holder.draw_line(seg[0], seg[1], Color(TEXT_FAINT, 0.8), -1))
	return holder


static func _bracket_tbd() -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(PANEL_LO, 5, Color(BORDER, 0.6), 1, 8, 3))
	var l := label("TBD", 12, TEXT_FAINT)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


static func _bracket_match(w: World, mt: Dictionary, ui: int, on_team: Callable) -> Control:
	var p := PanelContainer.new()
	var mine: bool = mt.a == ui or mt.b == ui
	p.add_theme_stylebox_override("panel", _box(PANEL_HI if not mine else Color(ACCENT2, 0.12), 5, BORDER if not mine else ACCENT2, 1, 8, 3))
	var v := vbox(0)
	p.add_child(v)
	for side in [[mt.a, mt.sa], [mt.b, mt.sb]]:
		var t: TeamData = w.teams[side[0]]
		var h := hbox(6)
		var won: bool = mt.winner == side[0]
		h.add_child(label(t.short_name, 12, t.color, 700))
		var n := link_button(t.team_name, on_team.bind(t), 12, TEXT if won or mt.winner == -1 else TEXT_FAINT, 400)
		n.custom_minimum_size = Vector2(96, 0)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		n.add_theme_constant_override("h_separation", 0)
		h.add_child(n)
		h.add_child(label(str(side[1]) if mt.winner != -1 else "", 12, GOOD if won else TEXT_DIM, 700))
		v.add_child(h)
	return p


## Long text in a fixed-width or shared cell: cut it instead of widening the row.
static func _clip(l: Label) -> Label:
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.tooltip_text = l.text
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	return l
