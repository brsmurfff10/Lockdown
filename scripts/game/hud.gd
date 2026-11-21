class_name Hud
extends CanvasLayer
## Match HUD in the Lockdown design system: score bar, timer, vitals, ammo,
## kill feed, round banner, plant/defuse bar, buy menu, scoreboard.

signal buy_pressed(item: String)
signal sell_pressed(item: String)
signal buy_close
signal replay_cmd(cmd: String, value: float)
signal results_cmd(cmd: String)

const SIDE_NAMES := ["T", "CT"]
const SIDE_COLORS := [Color("e8a052"), Color("5b9df5")]
const BOARD_COLS := [["Player", 0, "l"], ["RTG", 44, "c"], ["K", 34, "c"], ["D", 34, "c"], ["ADR", 44, "c"], ["Money", 74, "r"]]

var _root: Control
# Score bar.
var _name_a: Label
var _name_b: Label
var _side_a: PanelContainer
var _side_b: PanelContainer
var _score_a: Label
var _score_b: Label
var _box_a: PanelContainer
var _box_b: PanelContainer
var _timer: Label
var _alive: RichTextLabel
# Banner.
var _banner_band: PanelContainer
var _banner: Label
var _sub_banner: Label
# Vitals / ammo.
var _money: Label
var _hp: Label
var _hp_bar: ProgressBar
var _armor: Label
var _extras: Label
var _weapon: Label
var _weapon_pic: TextureRect ## Rendered picture of the gun in hand.
var _buy_pic: TextureRect ## Colour picture of the hovered gun in the buy menu.
var _buy_side := 0 ## Side of whoever has the buy menu open (molotov vs incendiary picture).
var _ammo: Label
var _vitals_panel: PanelContainer
var _ammo_panel: PanelContainer
# Misc.
var _feed: VBoxContainer
var _action_box: PanelContainer
var _action_label: Label
var _action_bar: ProgressBar
var _hint: Label
var _spectate_panel: PanelContainer
var _spectate: Label
# Buy menu.
var _buy_panel: PanelContainer
var _buy_title: Label
# Scoreboard.
var _scoreboard: PanelContainer
var _board_box: VBoxContainer
var _board_timer := 0.0
# Player dots under the score bar, damage vignette.
var _roster_view: Control
var _roster_rows: Array = [[], []]
var _vignette: TextureRect
var _blind_rect: ColorRect
var _flash := 0.0 ## Damage flash, 0-1, fades fast.
var _low := 0.0 ## Low-health intensity, 0 at 50 HP -> 1 at 0 HP.
var _clock := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # Replays pause the match; their controls live here.
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UI.make_theme()
	add_child(_root)
	_build_vignette()
	_build_scorebar()
	_blind_rect = ColorRect.new()
	_blind_rect.color = Color(1, 1, 1, 0)
	_blind_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blind_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_roster_view()
	_build_banner()
	_build_vitals()
	_build_ammo()
	_build_feed()
	_build_action()
	_build_hint()
	_build_spectate()
	_build_buy_menu()
	_build_radio()
	_build_scoreboard()
	_build_replay_bar()


## The radar (top left): you, teammates, and enemies as your team calls them.
var minimap: Minimap


func setup_minimap(m) -> void:
	minimap = Minimap.new()
	_anchor(minimap, 0, 0, 0, 0)
	minimap.position = Vector2(20, 96)
	_root.add_child(minimap)
	minimap.setup(m)
	if _blind_rect.get_parent() != null:
		_root.move_child(_blind_rect, -1) # The flash still covers everything.


# =============================================================================
# Building
# =============================================================================

func _glass(alpha: float = 0.82, radius: int = 10, border: Color = UI.BORDER) -> StyleBoxFlat:
	return UI._box(Color(UI.PANEL, alpha), radius, Color(border, 0.8), 1, 14, 8)


func _anchor(c: Control, l: float, t: float, r: float, b: float) -> void:
	c.anchor_left = l
	c.anchor_top = t
	c.anchor_right = r
	c.anchor_bottom = b


func _quiet(c: Control) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for ch in c.get_children():
		if ch is Control:
			_quiet(ch)


func _build_scorebar() -> void:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", _glass(0.88, 12))
	_anchor(bar, 0.5, 0, 0.5, 0)
	bar.offset_left = -330
	bar.offset_right = 330
	bar.offset_top = 10
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_root.add_child(bar)
	var row := UI.hbox(10)
	bar.add_child(row)

	_name_a = UI.label("", 17, UI.TEXT, 700)
	_name_a.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_name_a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_a.clip_text = true
	row.add_child(_name_a)
	_side_a = UI.pill("T", SIDE_COLORS[0])
	row.add_child(_side_a)
	_box_a = PanelContainer.new()
	_score_a = UI.label("0", 26, UI.TEXT, 700)
	_score_a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_a.custom_minimum_size = Vector2(40, 0)
	_box_a.add_child(_score_a)
	row.add_child(_box_a)

	var mid := UI.vbox(0)
	mid.custom_minimum_size = Vector2(96, 0)
	_timer = UI.label("", 22, UI.TEXT, 700)
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(_timer)
	_alive = RichTextLabel.new()
	_alive.bbcode_enabled = true
	_alive.fit_content = true
	_alive.scroll_active = false
	_alive.add_theme_font_override("normal_font", UI.font(600))
	_alive.add_theme_font_size_override("normal_font_size", 12)
	mid.add_child(_alive)
	_round_info = UI.label("", 10, UI.TEXT_FAINT, 600)
	_round_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(_round_info)
	row.add_child(mid)

	_box_b = PanelContainer.new()
	_score_b = UI.label("0", 26, UI.TEXT, 700)
	_score_b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_b.custom_minimum_size = Vector2(40, 0)
	_box_b.add_child(_score_b)
	row.add_child(_box_b)
	_side_b = UI.pill("CT", SIDE_COLORS[1])
	row.add_child(_side_b)
	_name_b = UI.label("", 17, UI.TEXT, 700)
	_name_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_b.clip_text = true
	row.add_child(_name_b)
	_quiet(bar)


## Red edges: a flash when you take damage, and a constant pulse below 50 HP
## that gets stronger as you approach 0.
func _build_vignette() -> void:
	var g := Gradient.new()
	g.set_offset(0, 0.0)
	g.set_color(0, Color(0.85, 0.0, 0.0, 0.0))
	g.set_offset(1, 1.0)
	g.set_color(1, Color(0.85, 0.0, 0.0, 1.0))
	g.add_point(0.55, Color(0.85, 0.0, 0.0, 0.0))
	g.add_point(0.8, Color(0.85, 0.0, 0.0, 0.35))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.05, 0.5)
	tex.width = 256
	tex.height = 256
	_vignette = TextureRect.new()
	_vignette.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_vignette.texture = tex
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.modulate.a = 0.0
	_root.add_child(_vignette)


## Flashbanged: white screen, fading out over the last ~1.2s.
## Standing in a smoke: the screen clouds over in grey except a small circle
## around you (depth 0..1, `at` = your position on screen).
var _smoke_fog: TextureRect = null


func set_smoke(depth: float, at: Vector2) -> void:
	if _smoke_fog == null:
		var g := Gradient.new()
		var grey := Color(0.56, 0.58, 0.61)
		g.set_offset(0, 0.0)
		g.set_color(0, Color(grey, 0.0))
		g.set_offset(1, 1.0)
		g.set_color(1, Color(grey, 0.97))
		g.add_point(0.03, Color(grey, 0.06))
		g.add_point(0.075, Color(grey, 0.88))
		g.add_point(0.14, Color(grey, 0.97))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 512
		tex.height = 512
		_smoke_fog = TextureRect.new()
		_smoke_fog.texture = tex
		_smoke_fog.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_smoke_fog.stretch_mode = TextureRect.STRETCH_SCALE
		_smoke_fog.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_smoke_fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(_smoke_fog)
		_root.move_child(_smoke_fog, 1) # Over the world, under the HUD panels.
	_smoke_fog.visible = depth > 0.01
	if not _smoke_fog.visible:
		return
	var vp := get_viewport().get_visible_rect().size
	var side := maxf(vp.x, vp.y) * 3.0 # Hole radius ~0.075 * side / 2: about 3 cells around you.
	_smoke_fog.size = Vector2(side, side)
	_smoke_fog.position = at - _smoke_fog.size * 0.5
	_smoke_fog.modulate.a = ease(depth, 0.6)


func set_blind(seconds: float) -> void:
	if _blind_rect.get_parent() == null:
		_root.add_child(_blind_rect) # Last, so it covers the whole HUD.
	_blind_rect.color.a = clampf(seconds / 1.2, 0.0, 1.0) * 0.97


func flash_damage(amount: float) -> void:
	_flash = minf(1.0, _flash + 0.35 + amount / 60.0)


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.01)
	_clock += real
	_flash = maxf(0.0, _flash - real * 1.8)
	var pulse := 0.0
	if _low > 0.0:
		pulse = _low * (0.42 + 0.14 * sin(_clock * (3.0 + 4.0 * _low)))
	_vignette.modulate.a = 0.0 if _replay_panel != null and _replay_panel.visible else clampf(maxf(pulse, 0.0) + _flash * 0.75, 0.0, 0.92)
	if _radio != null:
		_fade_radio(real)


func _build_roster_view() -> void:
	_roster_view = Control.new()
	_anchor(_roster_view, 0.5, 0, 0.5, 0)
	_roster_view.offset_left = -600
	_roster_view.offset_right = 600
	_roster_view.offset_top = 10
	_roster_view.offset_bottom = 80
	_roster_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_roster_view.draw.connect(_draw_roster)
	_root.add_child(_roster_view)


## rows[team_index] = [{name, alive, hp, side, user, bomb, watched}]
func set_roster(rows: Array) -> void:
	_roster_rows = rows
	_roster_view.queue_redraw()


const TILE := 34.0 ## Player square size.
const TILE_GAP := 6.0
const BAR_HALF := 336.0 ## Half the score bar width plus a margin.


## CS-style player squares either side of the score bar: side colour when
## alive with an HP strip along the bottom, dark and crossed out when dead.
func _draw_roster() -> void:
	var font := UI.font(600)
	var cx := _roster_view.size.x / 2.0
	for t in 2:
		var row: Array = _roster_rows[t]
		var n := row.size()
		for i in n:
			var r: Dictionary = row[i]
			var x := cx - BAR_HALF - (n - i) * (TILE + TILE_GAP) if t == 0 else cx + BAR_HALF + TILE_GAP + i * (TILE + TILE_GAP)
			var rect := Rect2(x, 4, TILE, TILE)
			var col: Color = SIDE_COLORS[int(r.side)]
			if r.alive:
				_roster_view.draw_rect(rect, Color(col, 0.85))
				if bool(r.get("hp_known", true)): # Enemy health is hidden while you play.
					var hp := clampf(float(r.hp) / Unit.MAX_HEALTH, 0.0, 1.0)
					var hc := UI.GOOD if hp > 0.5 else (UI.WARN if hp > 0.25 else UI.BAD)
					_roster_view.draw_rect(Rect2(x, rect.end.y - 5, TILE, 5), Color(0, 0, 0, 0.6))
					_roster_view.draw_rect(Rect2(x, rect.end.y - 5, TILE * hp, 5), hc)
				if r.bomb:
					_roster_view.draw_rect(Rect2(rect.end.x - 9, rect.position.y + 2, 7, 7), Color(0.9, 0.12, 0.12))
			else:
				_roster_view.draw_rect(rect, Color(0.12, 0.13, 0.16, 0.85))
				_roster_view.draw_line(rect.position + Vector2(8, 8), rect.end - Vector2(8, 8), Color(1, 1, 1, 0.3), 2.0)
				_roster_view.draw_line(Vector2(rect.end.x - 8, rect.position.y + 8), Vector2(rect.position.x + 8, rect.end.y - 8), Color(1, 1, 1, 0.3), 2.0)
			var outline := Color(0, 0, 0, 0.7)
			if r.user:
				outline = Color(1.0, 0.95, 0.4)
			elif r.watched:
				outline = Color(1, 1, 1, 0.9)
			_roster_view.draw_rect(rect, outline, false, 2.0 if (r.user or r.watched) else 1.0)
			var name := String(r.name)
			var size := 10
			var maxw := TILE + TILE_GAP - 2
			while name.length() > 2 and font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > maxw:
				name = name.substr(0, name.length() - 1)
			var tw := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			var tx := x + TILE / 2.0 - tw / 2.0
			var tc := Color(1, 1, 1, 0.9) if r.alive else Color(1, 1, 1, 0.35)
			_roster_view.draw_string(font, Vector2(tx + 1, 54), name, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.8))
			_roster_view.draw_string(font, Vector2(tx, 53), name, HORIZONTAL_ALIGNMENT_LEFT, -1, size, tc)


func _build_banner() -> void:
	_banner_band = PanelContainer.new()
	var sb := UI._box(Color(UI.BG, 0.72), 0, Color(0, 0, 0, 0), 0, 0, 14)
	sb.border_color = Color(UI.ACCENT, 0.6)
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	_banner_band.add_theme_stylebox_override("panel", sb)
	_anchor(_banner_band, 0, 0.26, 1, 0.26)
	_root.add_child(_banner_band)
	var v := UI.vbox(2)
	_banner_band.add_child(v)
	_banner = UI.label("", 40, UI.TEXT, 700)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_banner)
	_sub_banner = UI.label("", 17, UI.TEXT_DIM, 500)
	_sub_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_sub_banner)
	_banner_band.visible = false
	_quiet(_banner_band)


func _build_vitals() -> void:
	_vitals_panel = PanelContainer.new()
	_vitals_panel.add_theme_stylebox_override("panel", _glass())
	_anchor(_vitals_panel, 0, 1, 0, 1)
	_vitals_panel.offset_left = 16
	_vitals_panel.offset_top = -104
	_vitals_panel.offset_right = 290
	_vitals_panel.offset_bottom = -16
	_vitals_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_root.add_child(_vitals_panel)
	var v := UI.vbox(4)
	_vitals_panel.add_child(v)
	_money = UI.label("$0", 18, UI.GOOD, 700)
	v.add_child(_money)
	var row := UI.hbox(10)
	v.add_child(row)
	_hp = UI.label("100", 32, UI.TEXT, 700)
	_hp.custom_minimum_size = Vector2(64, 0)
	row.add_child(_hp)
	var bars := UI.vbox(4)
	bars.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bars.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hp_bar = ProgressBar.new()
	_hp_bar.max_value = Unit.MAX_HEALTH
	_hp_bar.show_percentage = false
	_hp_bar.custom_minimum_size = Vector2(0, 8)
	_hp_bar.add_theme_stylebox_override("fill", UI._box(UI.GOOD, 3, Color(0, 0, 0, 0), 0, 0, 0))
	bars.add_child(_hp_bar)
	var info := UI.hbox(8)
	_armor = UI.label("", 13, UI.ACCENT2, 600)
	info.add_child(_armor)
	_extras = UI.label("", 13, UI.WARN, 600)
	info.add_child(_extras)
	bars.add_child(info)
	row.add_child(bars)
	_quiet(_vitals_panel)


func _build_ammo() -> void:
	_ammo_panel = PanelContainer.new()
	_ammo_panel.add_theme_stylebox_override("panel", _glass())
	_anchor(_ammo_panel, 1, 1, 1, 1)
	_ammo_panel.offset_left = -300
	_ammo_panel.offset_right = -16
	_ammo_panel.offset_top = -92
	_ammo_panel.offset_bottom = -16
	_ammo_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_ammo_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_root.add_child(_ammo_panel)
	var v := UI.vbox(0)
	_ammo_panel.add_child(v)
	_weapon = UI.caption("Pistol", UI.TEXT_DIM)
	_weapon.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(_weapon)
	_ammo = UI.label("12 / 12", 30, UI.TEXT, 700)
	_ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ammo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ar := UI.hbox(10)
	_weapon_pic = _gun_pic(Vector2(110, 38))
	ar.add_child(_weapon_pic)
	ar.add_child(_ammo)
	v.add_child(ar)
	_quiet(_ammo_panel)


func _gun_pic(size: Vector2) -> TextureRect:
	var t := TextureRect.new()
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = size
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return t


func _build_feed() -> void:
	_feed = UI.vbox(4)
	_anchor(_feed, 1, 0, 1, 0)
	_feed.offset_left = -420
	_feed.offset_right = -16
	_feed.offset_top = 84
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_feed)


func _build_action() -> void:
	_action_box = PanelContainer.new()
	_action_box.add_theme_stylebox_override("panel", _glass(0.85))
	_anchor(_action_box, 0.5, 0.7, 0.5, 0.7)
	_action_box.offset_left = -180
	_action_box.offset_right = 180
	_action_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_root.add_child(_action_box)
	var v := UI.vbox(6)
	_action_box.add_child(v)
	_action_label = UI.label("", 16, UI.TEXT, 700)
	_action_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_action_label)
	_action_bar = ProgressBar.new()
	_action_bar.custom_minimum_size = Vector2(320, 10)
	_action_bar.show_percentage = false
	_action_bar.max_value = 1.0
	v.add_child(_action_bar)
	_action_box.visible = false
	_quiet(_action_box)


func _build_hint() -> void:
	_hint = UI.label("Shift/RMB look   R reload   1/2/Q weapons   4 grenades   E plant/defuse   F pick up   G drop   Y ask for bomb   B buy   Tab scores", 11, Color(UI.TEXT_DIM, 0.7))
	_anchor(_hint, 0, 1, 1, 1)
	_hint.offset_top = -26
	_hint.offset_bottom = -6
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_hint)


func _build_spectate() -> void:
	_spectate_panel = PanelContainer.new()
	_spectate_panel.add_theme_stylebox_override("panel", _glass(0.82))
	_anchor(_spectate_panel, 0, 1, 0, 1)
	_spectate_panel.offset_left = 16
	_spectate_panel.offset_bottom = -16
	_spectate_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_root.add_child(_spectate_panel)
	_spectate = UI.label("", 13, UI.TEXT)
	_spectate_panel.add_child(_spectate)
	_spectate_panel.visible = false
	_quiet(_spectate_panel)


## CS-style buy menu: six category columns (1 Pistols .. 6 Grenades). Number
## keys: category, then item. Mouse: click buys, right-click sells back
## something you bought this buy phase. Shows price, owned, can't afford and
## side-restricted items; your money on top.
const BUY_CATS := [
	["Pistols", ["w:100", "w:101", "w:102", "w:103", "w:104", "w:105"]],
	["SMGs", ["w:110", "w:111", "w:112", "w:113"]],
	["Rifles", ["w:140", "w:141", "w:142", "w:143", "w:144", "w:145", "w:150", "w:151"]],
	["Heavy", ["w:120", "w:121", "w:130"]],
	["Gear", ["armor", "helmet", "kit"]],
	["Grenades", ["flash", "smoke", "frag", "molotov"]],
]
const BUY_COL_W := 194.0
const BUY_ROW_H := 34.0

var _buy_cat := -1 ## Number-key navigation: selected column, -1 = choosing a column.
var _buy_heads: Array[PanelContainer] = []
var _buy_items := {} ## key -> {button, num, name, status}
var _buy_detail: Label
var _buy_hint: Label
var _buy_unit: Unit
var _buy_match ## Match (for prices / restrictions / refunds).


func _build_buy_menu() -> void:
	_buy_panel = PanelContainer.new()
	_buy_panel.add_theme_stylebox_override("panel", _glass(0.95, 12, UI.ACCENT))
	_anchor(_buy_panel, 0.5, 0, 0.5, 0)
	var w := BUY_COL_W * BUY_CATS.size() + 8.0 * (BUY_CATS.size() - 1) + 30.0
	_buy_panel.offset_left = -w / 2.0
	_buy_panel.offset_right = w / 2.0
	_buy_panel.offset_top = 76
	_buy_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_buy_panel.visible = false
	_root.add_child(_buy_panel)
	var box := UI.vbox(8)
	_buy_panel.add_child(box)
	var head := UI.hbox(12)
	head.add_child(UI.label("BUY MENU", 20, UI.TEXT, 700))
	_buy_hint = UI.label("", 12, UI.TEXT_DIM)
	_buy_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_buy_hint)
	head.add_child(UI.spacer())
	_buy_title = UI.label("$0", 26, UI.GOOD, 700)
	head.add_child(_buy_title)
	box.add_child(head)
	var cols := UI.hbox(8)
	box.add_child(cols)
	for ci in BUY_CATS.size():
		var col := UI.vbox(4)
		col.custom_minimum_size = Vector2(BUY_COL_W, 0)
		cols.add_child(col)
		var hp := PanelContainer.new()
		var hl := UI.label("%d   %s" % [ci + 1, String(BUY_CATS[ci][0]).to_upper()], 14, UI.TEXT, 700)
		hp.add_child(hl)
		col.add_child(hp)
		_buy_heads.append(hp)
		var items: Array = BUY_CATS[ci][1]
		for ii in items.size():
			var key: String = items[ii]
			var b := Button.new()
			b.custom_minimum_size = Vector2(BUY_COL_W, BUY_ROW_H)
			b.focus_mode = Control.FOCUS_NONE
			b.set_meta("ui_sound", "none") # The match plays buy / can't-afford.
			b.pressed.connect(func() -> void: buy_pressed.emit(key))
			b.gui_input.connect(func(ev: InputEvent) -> void:
				if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
					sell_pressed.emit(key))
			b.mouse_entered.connect(func() -> void: _show_buy_detail(key))
			var row := UI.hbox(4)
			row.set_anchors_preset(Control.PRESET_FULL_RECT)
			row.offset_left = 8
			row.offset_right = -8
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var num := UI.label(str(ii + 1), 12, UI.TEXT_FAINT, 700)
			num.custom_minimum_size = Vector2(12, 0)
			num.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var pic := _gun_pic(Vector2(22, 12))
			pic.modulate = Color(1, 1, 1, 0.7)
			if key.begins_with("w:"):
				pic.texture = GunArt.picture(int(key.substr(2)), true)
			elif key in Utility.KINDS:
				pic.texture = GunArt.grenade_picture(key, 0, true)
			pic.visible = pic.texture != null
			var nm := UI.label("", 12 if pic.visible else 13, UI.TEXT, 600)
			nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			nm.clip_text = true
			var st := UI.label("", 12, UI.GOOD, 700)
			st.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			st.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			row.add_child(num)
			row.add_child(pic)
			row.add_child(nm)
			row.add_child(st)
			for c in row.get_children():
				(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(row)
			col.add_child(b)
			_buy_items[key] = {"button": b, "num": num, "name": nm, "status": st, "pic": pic}
	_buy_detail = UI.label("", 12, UI.TEXT_DIM)
	_buy_detail.custom_minimum_size = Vector2(0, 18)
	_buy_detail.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_buy_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var drow := UI.hbox(12)
	_buy_pic = _gun_pic(Vector2(150, 48))
	drow.add_child(_buy_pic)
	drow.add_child(_buy_detail)
	box.add_child(drow)


func reset_buy_nav() -> void:
	_buy_cat = -1


func _item_name(key: String, side: int) -> String:
	if key.begins_with("w:"):
		return WeaponData.name_of(int(key.substr(2)))
	match key:
		"armor":
			return "Kevlar Vest"
		"helmet":
			return "Vest + Helmet"
		"kit":
			return "Defuse Kit"
	return Utility.display_name(key, side)


func _show_buy_detail(key: String) -> void:
	if _buy_detail == null:
		return
	if _buy_pic != null:
		if key.begins_with("w:"):
			_buy_pic.texture = GunArt.picture(int(key.substr(2)))
		elif key in Utility.KINDS:
			_buy_pic.texture = GunArt.grenade_picture(key, _buy_side)
		else:
			_buy_pic.texture = null
	if key.begins_with("w:"):
		var w := WeaponData.by_id(int(key.substr(2)))
		var side_txt := "" if w.side == WeaponData.ANY else ("   %s ONLY" % SIDE_NAMES[w.side])
		_buy_detail.text = "%s:   %s%s" % [w.weapon_name, w.stat_line(), side_txt]
		return
	match key:
		"armor":
			_buy_detail.text = "Kevlar Vest:   armour absorbs 35% of body damage (less vs armour-piercing guns)"
		"helmet":
			_buy_detail.text = "Kevlar + Helmet:   armour absorbs 42% instead of 35%   ($350 if you already wear full kevlar)"
		"kit":
			_buy_detail.text = "Defuse Kit:   defuse in 5s instead of 10s   CT ONLY"
		"flash":
			_buy_detail.text = "Flashbang:   blinds by distance and facing (your team gets 30%)   max 2"
		"smoke":
			_buy_detail.text = "Smoke:   blocks sight for 16s, puts out fire"
		"frag":
			_buy_detail.text = "Frag Grenade:   up to 98 damage in a blast, needs line of sight"
		"molotov":
			_buy_detail.text = "Molotov / Incendiary:   7s of fire on the ground"


## Number keys while the menu is open: category, then item. 0 / Backspace goes
## back a level; Esc closes.
func _input(event: InputEvent) -> void:
	if _buy_panel == null or not _buy_panel.visible or not (event is InputEventKey):
		return
	var ek := event as InputEventKey
	if not ek.pressed or ek.echo:
		return
	var code := ek.physical_keycode
	var n := -1
	if code >= KEY_1 and code <= KEY_9:
		n = code - KEY_1 + 1
	elif code >= KEY_KP_1 and code <= KEY_KP_9:
		n = code - KEY_KP_1 + 1
	if n > 0:
		if _buy_cat < 0:
			if n <= BUY_CATS.size():
				_buy_cat = n - 1
		else:
			var items: Array = BUY_CATS[_buy_cat][1]
			if n <= items.size():
				buy_pressed.emit(String(items[n - 1]))
				_show_buy_detail(String(items[n - 1]))
				_buy_cat = -1
		get_viewport().set_input_as_handled()
	elif code == KEY_0 or code == KEY_KP_0 or code == KEY_BACKSPACE:
		_buy_cat = -1
		get_viewport().set_input_as_handled()
	elif code == KEY_ESCAPE:
		_buy_cat = -1
		buy_close.emit()
		get_viewport().set_input_as_handled()


func show_buy_menu(visible_now: bool, u: Unit, money: int, match_node = null) -> void:
	_buy_side = u.side if u != null else 0
	_buy_panel.visible = visible_now and u != null and match_node != null
	_banner_band.modulate.a = 0.0 if _buy_panel.visible else 1.0 # The round banner would show through.
	if not _buy_panel.visible:
		return
	_buy_title.text = UI.money_text(money)
	_buy_hint.text = ("Press 1-6 for a category, then the item number" if _buy_cat < 0
		else "%s: press the item number   (0 = back)" % String(BUY_CATS[_buy_cat][0])) \
		+ "   |   Right-click: sell back   |   B / Esc: close"
	var refunds: Dictionary = match_node.refundable(u)
	for ci in BUY_CATS.size():
		var active := ci == _buy_cat
		_buy_heads[ci].add_theme_stylebox_override("panel", UI._box(Color(UI.ACCENT, 0.28) if active else Color(UI.BG, 0.5), 6,
			Color(UI.ACCENT, 0.9) if active else Color(UI.BORDER, 0.6), 1, 8, 4))
		for key: String in BUY_CATS[ci][1]:
			var it: Dictionary = _buy_items[key]
			var b: Button = it.button
			var price: int = match_node.item_price(u, key)
			var block: String = match_node.item_block(u, key)
			var nm: Label = it.name
			var st: Label = it.status
			var label := _item_name(key, u.side)
			if key == "molotov": # Molotov bottle for T, incendiary canister for CT.
				(it.pic as TextureRect).texture = GunArt.grenade_picture(key, u.side, true)
			if key in Utility.KINDS:
				var have := int(u.grenades.get(key, 0))
				if have > 0:
					label += "  x%d" % have
			nm.text = label
			(it.num as Label).add_theme_color_override("font_color", UI.ACCENT if active else UI.TEXT_FAINT)
			var restricted := block.ends_with("ONLY")
			var col := UI.TEXT
			if restricted:
				st.text = block
				st.add_theme_color_override("font_color", UI.TEXT_FAINT)
				col = UI.TEXT_FAINT
			elif block == "OWNED" or block == "FULL":
				st.text = ("SELL $%d" % price) if refunds.has(key) and block == "OWNED" else block
				st.add_theme_color_override("font_color", UI.ACCENT2)
			elif price > money:
				st.text = UI.money_text(price)
				st.add_theme_color_override("font_color", UI.BAD)
				col = UI.TEXT_DIM
			else:
				st.text = UI.money_text(price)
				st.add_theme_color_override("font_color", UI.GOOD)
			if refunds.has(key) and block != "OWNED":
				st.text += " · sell" # Bought this round (grenades): right-click sells one back.
			nm.add_theme_color_override("font_color", col)
			b.modulate.a = 0.45 if restricted else 1.0
			var owned := block == "OWNED"
			var border := UI.ACCENT2 if owned else (UI.ACCENT if active else UI.BORDER)
			var bg := Color(UI.ACCENT2, 0.16) if owned else Color(UI.PANEL, 0.9)
			b.add_theme_stylebox_override("normal", UI._box(bg, 6, Color(border, 0.8), 1, 8, 4))
			b.add_theme_stylebox_override("hover", UI._box(bg.lightened(0.12), 6, Color(UI.ACCENT, 1.0), 1, 8, 4))
			b.add_theme_stylebox_override("pressed", UI._box(bg.darkened(0.1), 6, Color(UI.ACCENT, 1.0), 1, 8, 4))
	if _radio != null:
		# Keep the round call readable below the menu.
		_radio.offset_left = 18
		_radio.offset_right = 460


var _radio: VBoxContainer
const RADIO_LINES := 5
const RADIO_TIME := 7.0


## Team radio: bot callouts stacked above the health panel, fading out.
func _build_radio() -> void:
	_radio = UI.vbox(2)
	_anchor(_radio, 0, 1, 0, 1)
	_radio.offset_left = 18
	_radio.offset_right = 460
	_radio.offset_top = -122
	_radio.offset_bottom = -122
	_radio.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_radio.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_radio)


func add_radio(speaker: String, color: Color, text: String) -> void:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("normal_font", UI.font(500))
	l.add_theme_font_override("bold_font", UI.font(700))
	l.add_theme_font_size_override("normal_font_size", 13)
	l.add_theme_font_size_override("bold_font_size", 13)
	l.add_theme_color_override("default_color", Color(UI.TEXT, 0.95))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.text = "[b][color=#%s]%s[/color][/b]  %s" % [color.lightened(0.15).to_html(false), speaker, text.replace("[", "(")]
	l.set_meta("t", RADIO_TIME)
	_radio.add_child(l)
	while _radio.get_child_count() > RADIO_LINES:
		var old := _radio.get_child(0)
		_radio.remove_child(old)
		old.queue_free()
	if Game.ui_sounds != null:
		Game.ui_sounds.play("tick")


## All-chat line from a bot (shown to everyone, in the radio stack, grey tag).
func add_chat(speaker: String, color: Color, text: String) -> void:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("normal_font", UI.font(500))
	l.add_theme_font_override("bold_font", UI.font(700))
	l.add_theme_font_size_override("normal_font_size", 13)
	l.add_theme_font_size_override("bold_font_size", 13)
	l.add_theme_color_override("default_color", Color(1, 1, 1, 0.95))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.text = "[color=#9aa3b5][ALL][/color] [b][color=#%s]%s[/color][/b]: %s" % [color.lightened(0.15).to_html(false), speaker, text.replace("[", "(")]
	l.set_meta("t", RADIO_TIME)
	l.set_meta("chat", true)
	_radio.add_child(l)
	while _radio.get_child_count() > RADIO_LINES:
		var old := _radio.get_child(0)
		_radio.remove_child(old)
		old.queue_free()


func _fade_radio(real: float) -> void:
	for c in _radio.get_children():
		var t: float = float(c.get_meta("t", 0.0)) - real
		c.set_meta("t", t)
		(c as CanvasItem).modulate.a = clampf(t, 0.0, 1.0)
		if t <= 0.0:
			c.queue_free()


func _build_scoreboard() -> void:
	_scoreboard = PanelContainer.new()
	_scoreboard.add_theme_stylebox_override("panel", _glass(0.95, 12))
	_anchor(_scoreboard, 0.5, 0.5, 0.5, 0.5)
	_scoreboard.offset_left = -400
	_scoreboard.offset_right = 400
	_scoreboard.offset_top = -250
	_scoreboard.offset_bottom = 250
	_scoreboard.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_scoreboard.grow_vertical = Control.GROW_DIRECTION_BOTH
	_scoreboard.visible = false
	_scoreboard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_scoreboard)
	_board_box = UI.vbox(6)
	_scoreboard.add_child(_board_box)


# =============================================================================
# Updates (API used by Match)
# =============================================================================

func _side_box(box: PanelContainer, side: int) -> void:
	box.add_theme_stylebox_override("panel", UI._box(Color(SIDE_COLORS[side], 0.22), 7, SIDE_COLORS[side], 1, 6, 0))


func _set_pill(p: PanelContainer, text: String, color: Color) -> void:
	p.add_theme_stylebox_override("panel", UI._box(Color(color, 0.15), 10, Color(color, 0.5), 1, 9, 2))
	var l: Label = p.get_child(0)
	l.text = text
	l.add_theme_color_override("font_color", color)


func set_score(teams: Array[TeamData], score: Array[int], sides: Array[int]) -> void:
	_name_a.text = teams[0].team_name.to_upper()
	_name_b.text = teams[1].team_name.to_upper()
	_set_pill(_side_a, SIDE_NAMES[sides[0]], SIDE_COLORS[sides[0]])
	_set_pill(_side_b, SIDE_NAMES[sides[1]], SIDE_COLORS[sides[1]])
	_score_a.text = str(score[0])
	_score_b.text = str(score[1])
	_side_box(_box_a, sides[0])
	_side_box(_box_b, sides[1])


func set_timer(text: String, color: Color = Color.WHITE) -> void:
	_timer.text = text
	_timer.add_theme_color_override("font_color", color)


func set_alive(t_alive: int, ct_alive: int) -> void:
	_alive.text = "[center][color=#%s]%s[/color]  [color=#%s]%s[/color][/center]" % [
		SIDE_COLORS[0].to_html(false), _pips(t_alive), SIDE_COLORS[1].to_html(false), _pips(ct_alive)]


func _pips(n: int) -> String:
	return "%d alive" % n


func set_spectate_info(text: String) -> void:
	if _spectate.text == text and _spectate_panel.visible == (text != ""):
		return
	_spectate.text = text
	var watching := text != ""
	_spectate_panel.visible = watching
	_hint.visible = not watching
	_vitals_panel.visible = not watching # Nothing of ours to show while watching.
	if watching:
		_ammo_panel.visible = false


func set_banner(text: String, sub: String = "") -> void:
	_banner.text = text
	_sub_banner.text = sub
	_sub_banner.visible = sub != ""
	_banner_band.visible = text != ""


func set_vitals(u: Unit, money: int) -> void:
	_money.text = UI.money_text(money)
	_low = clampf((50.0 - u.health) / 50.0, 0.0, 1.0) if u != null and u.alive else 0.0
	if u == null or not u.alive:
		_hp.text = "-"
		_hp_bar.value = 0
		_armor.text = "DEAD  -  spectating"
		_extras.text = ""
		_ammo_panel.visible = false
		return
	_ammo_panel.visible = not _spectate_panel.visible
	_hp.text = str(ceili(u.health))
	_hp_bar.value = u.health
	var hp_col := UI.GOOD if u.health > 50 else (UI.WARN if u.health > 25 else UI.BAD)
	_hp.add_theme_color_override("font_color", hp_col)
	_hp_bar.add_theme_stylebox_override("fill", UI._box(hp_col, 3, Color(0, 0, 0, 0), 0, 0, 0))
	_armor.text = "ARMOR %d" % ceili(u.armor) if u.armor > 0.0 else "NO ARMOR"
	_armor.add_theme_color_override("font_color", UI.ACCENT2 if u.armor > 0.0 else UI.TEXT_FAINT)
	var ex := []
	if u.has_kit:
		ex.append("KIT")
	if u.has_bomb:
		ex.append("BOMB")
	for k: String in Utility.KINDS:
		var n := int(u.grenades.get(k, 0))
		if n > 0:
			ex.append(Utility.SHORT[k] + ("x%d" % n if n > 1 else ""))
	_extras.text = "   ".join(ex)
	_weapon.text = u.weapon.weapon_name.to_upper()
	_weapon_pic.texture = GunArt.picture(u.weapon.id) if u.held_grenade == "" else GunArt.grenade_picture(u.held_grenade, u.side)
	if u.knife_out and u.held_grenade == "":
		_weapon_pic.texture = GunArt.knife_picture()
		_weapon.text = "KNIFE   BACKSTAB KILLS"
	elif u.weapon.scope:
		_weapon.text += "   SCOPED" if u.is_scoped() else "   RMB: SCOPE"
	if u.is_drawing():
		_ammo.text = "DRAWING"
		_ammo.add_theme_color_override("font_color", UI.TEXT_FAINT)
	elif u.knife_out and u.held_grenade == "":
		_ammo.text = "-"
		_ammo.add_theme_color_override("font_color", UI.TEXT)
	elif u.held_grenade != "":
		_weapon.text = "CLICK TO THROW   4: NEXT"
		_ammo.text = Utility.display_name(u.held_grenade, u.side).to_upper()
		_ammo.add_theme_color_override("font_color", Utility.COLORS[u.held_grenade])
	elif u.reloading:
		_ammo.text = "RELOADING"
		_ammo.add_theme_color_override("font_color", UI.WARN)
	else:
		_ammo.text = "%d / %d" % [u.weapon.ammo, u.weapon.mag_size]
		_ammo.add_theme_color_override("font_color", UI.BAD if u.weapon.ammo <= u.weapon.mag_size / 5 else UI.TEXT)


func set_action(text: String, progress: float) -> void:
	_action_box.visible = text != ""
	_action_label.text = text
	_action_bar.value = progress
	_action_bar.visible = progress > 0.0


func buy_menu_visible() -> bool:
	return _buy_panel.visible


func _feed_pill(bbcode: String, border: Color) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI._box(Color(UI.BG, 0.78), 6, Color(border, 0.5), 1, 10, 3))
	p.size_flags_horizontal = Control.SIZE_SHRINK_END
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.autowrap_mode = TextServer.AUTOWRAP_OFF
	r.scroll_active = false
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_theme_font_override("normal_font", UI.font(600))
	r.add_theme_font_size_override("normal_font_size", 14)
	r.text = bbcode
	p.add_child(r)
	_feed.add_child(p)
	get_tree().create_timer(5.0).timeout.connect(p.queue_free)


func add_kill(killer: Unit, victim: Unit) -> void:
	var k := ""
	if killer != null:
		var gun := "[color=#8791a8]%s[/color]" % ("Knife" if killer.knife_out else killer.weapon.weapon_name)
		var ip := GunArt.KNIFE_ICON if killer.knife_out and ResourceLoader.exists(GunArt.KNIFE_ICON) else ("" if killer.knife_out else GunArt.icon_path(killer.weapon.id))
		if ip != "":
			gun = "[img height=15 color=#c8cfdc]%s[/img]" % ip
		k = "[color=#%s]%s[/color]  %s  " % [SIDE_COLORS[killer.side].to_html(false), killer.data.player_name, gun]
	var user_involved := (killer != null and killer.data.is_user) or victim.data.is_user
	_feed_pill("%s[color=#%s]%s[/color]" % [k, SIDE_COLORS[victim.side].to_html(false), victim.data.player_name],
		UI.ACCENT if user_involved else UI.BORDER)


func add_feed_text(text: String) -> void:
	_feed_pill("[color=#fbbf24]%s[/color]" % text, UI.WARN)


func clear_feed() -> void:
	for c in _feed.get_children():
		c.queue_free()


## rows[t] = Array of {name, rating, kills, deaths, adr, money, is_user}
func show_scoreboard(visible_now: bool, teams: Array[TeamData], sides: Array[int], rows: Array) -> void:
	_scoreboard.visible = visible_now
	if not visible_now:
		_board_timer = 0.0
		return
	_board_timer -= get_process_delta_time()
	if _board_timer > 0.0:
		return
	_board_timer = 0.3 # Rebuild a few times a second, not every frame.
	for c in _board_box.get_children():
		c.queue_free()
	for t in 2:
		var team := teams[t]
		var head := UI.hbox(10)
		head.add_child(UI.team_badge_for(team, 24))
		head.add_child(UI.label(team.team_name, 18, UI.TEXT, 700))
		head.add_child(UI.pill(SIDE_NAMES[sides[t]], SIDE_COLORS[sides[t]]))
		head.add_child(UI.spacer())
		head.add_child(UI.label("Team rating %d" % team.rating(), 13, UI.TEXT_DIM))
		_board_box.add_child(head)
		_board_box.add_child(UI.table_header(BOARD_COLS))
		var i := 0
		for r: Dictionary in rows[t]:
			var mine: bool = r.is_user
			var name_cell := UI.hbox(8)
			name_cell.add_child(UI.label(String(r.name), 15, UI.ACCENT2 if mine else UI.TEXT, 600))
			if String(r.get("title", "")) != "":
				var tl := UI.label(String(r.title), 11, UI.WARN, 500)
				tl.clip_text = true
				tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				tl.custom_minimum_size.x = 0
				name_cell.add_child(tl)
			_board_box.add_child(UI.table_row([name_cell, UI.rating_chip(int(r.rating), 13),
				UI.label(str(r.kills), 15, UI.TEXT, 700), UI.label(str(r.deaths), 15, UI.TEXT_DIM),
				UI.label(str(r.adr), 14, UI.TEXT_DIM), UI.label(UI.money_text(int(r.money)), 14, UI.GOOD)], BOARD_COLS, i, mine))
			i += 1
		if t == 0:
			_board_box.add_child(UI.gap(6))
	_quiet(_scoreboard)


# =============================================================================
# Post-match results
# =============================================================================

var _results: Control


## data: see UI.results_overlay.
func show_results(data: Dictionary, on_continue: Callable) -> void:
	if _results != null:
		_results.queue_free()
	_scoreboard.visible = false
	_buy_panel.visible = false
	_results = UI.results_overlay(_root, data, on_continue)


# =============================================================================
# Round info (under the timer), replays, results extras
# =============================================================================

var _round_info: Label


func set_round_info(text: String, overtime: bool) -> void:
	if _round_info == null:
		return
	_round_info.text = text
	_round_info.add_theme_color_override("font_color", UI.WARN if overtime else UI.TEXT_FAINT)


var _replay_panel: PanelContainer
var _replay_tag: PanelContainer
var _replay_tag_label: Label
var _replay_title: Label
var _replay_time: Label
var _replay_slider: HSlider
var _replay_play: Button
var _replay_speed: Button
var _replay_follow: Label
var _replay_feed: RichTextLabel
var _replay_buttons: Array[Button] = []
var _replay_skip: Button
var _replay_help: Label
var _replay_saved := {}
var _slider_lock := false
var _results_bar: BoxContainer


func _build_replay_bar() -> void:
	_replay_tag = PanelContainer.new()
	_replay_tag.add_theme_stylebox_override("panel", UI._box(Color(UI.BAD, 0.85), 6, Color(0, 0, 0, 0), 0, 12, 4))
	_anchor(_replay_tag, 0, 0, 0, 0)
	_replay_tag.offset_left = 16
	_replay_tag.offset_top = 84
	_replay_tag_label = UI.label("REPLAY", 18, Color.WHITE, 700)
	_replay_tag.add_child(_replay_tag_label)
	_replay_tag.visible = false
	_replay_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_replay_tag)

	_replay_feed = RichTextLabel.new()
	_replay_feed.bbcode_enabled = true
	_replay_feed.fit_content = true
	_replay_feed.scroll_active = false
	_replay_feed.autowrap_mode = TextServer.AUTOWRAP_OFF
	_replay_feed.add_theme_font_override("normal_font", UI.font(600))
	_replay_feed.add_theme_font_size_override("normal_font_size", 14)
	_replay_feed.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_replay_feed.add_theme_constant_override("shadow_offset_x", 1)
	_replay_feed.add_theme_constant_override("shadow_offset_y", 1)
	_anchor(_replay_feed, 1, 0, 1, 0)
	_replay_feed.offset_left = -440
	_replay_feed.offset_right = -16
	_replay_feed.offset_top = 84
	_replay_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_replay_feed.visible = false
	_root.add_child(_replay_feed)

	_replay_panel = PanelContainer.new()
	_replay_panel.add_theme_stylebox_override("panel", _glass(0.93, 12, UI.ACCENT))
	_anchor(_replay_panel, 0.5, 1, 0.5, 1)
	_replay_panel.offset_left = -470
	_replay_panel.offset_right = 470
	_replay_panel.offset_top = -132
	_replay_panel.offset_bottom = -16
	_replay_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_replay_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_replay_panel.visible = false
	_root.add_child(_replay_panel)
	var v := UI.vbox(6)
	_replay_panel.add_child(v)
	var top := UI.hbox(10)
	_replay_title = UI.label("", 16, UI.TEXT, 700)
	_replay_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_replay_title.clip_text = true
	top.add_child(_replay_title)
	_replay_follow = UI.label("", 13, UI.ACCENT2, 600)
	top.add_child(_replay_follow)
	_replay_time = UI.label("0:00 / 0:00", 14, UI.TEXT_DIM, 600)
	top.add_child(_replay_time)
	v.add_child(top)
	_replay_slider = HSlider.new()
	_replay_slider.min_value = 0.0
	_replay_slider.max_value = 1.0
	_replay_slider.step = 0.001
	_replay_slider.focus_mode = Control.FOCUS_NONE
	_replay_slider.set_meta("ui_sound", "none")
	_replay_slider.value_changed.connect(func(val: float) -> void:
		if not _slider_lock:
			replay_cmd.emit("seek_frac", val))
	v.add_child(_replay_slider)
	var row := UI.hbox(6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	var defs := [["Prev (P)", "prev"], ["-5s", "seek_back"], ["Pause", "toggle"], ["+5s", "seek_fwd"],
		["Speed 1x", "speed"], ["Next (N)", "next"], ["Overview (F)", "overview"], ["Close (Esc)", "close"]]
	for d: Array in defs:
		var cmd: String = d[1]
		var b := UI.small_button(String(d[0]), _replay_button_cb(cmd), 86)
		b.focus_mode = Control.FOCUS_NONE
		b.set_meta("cmd", cmd)
		row.add_child(b)
		_replay_buttons.append(b)
		if cmd == "toggle":
			_replay_play = b
		elif cmd == "speed":
			_replay_speed = b
	_replay_skip = UI.small_button("Skip (Space)", func() -> void: replay_cmd.emit("close", 0.0), 140)
	_replay_skip.focus_mode = Control.FOCUS_NONE
	row.add_child(_replay_skip)
	_replay_help = UI.label("Click / right-click or Tab: follow next / previous player   Wheel: zoom   - / = : speed   Left / Right: seek", 11, UI.TEXT_FAINT)
	_replay_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_replay_help)


func _replay_button_cb(cmd: String) -> Callable:
	if cmd == "seek_back":
		return func() -> void: replay_cmd.emit("seek", -5.0)
	if cmd == "seek_fwd":
		return func() -> void: replay_cmd.emit("seek", 5.0)
	return func() -> void: replay_cmd.emit(cmd, 0.0)


## Replay on/off: hide the live HUD (restored afterwards).
func set_replay_mode(on: bool, kind: String) -> void:
	var live: Array[Control] = [_vitals_panel, _ammo_panel, _feed, _action_box, _hint, _spectate_panel, _buy_panel,
		_radio, _banner_band, _scoreboard, _blind_rect]
	if _results != null:
		live.append(_results)
	if _results_bar != null:
		live.append(_results_bar)
	if on:
		_replay_saved.clear()
		for c in live:
			if c != null:
				_replay_saved[c] = c.visible
				c.visible = false
		_vignette.modulate.a = 0.0
	else:
		for c in _replay_saved:
			if is_instance_valid(c):
				(c as Control).visible = _replay_saved[c]
		_replay_saved.clear()
	var killcam := kind == "killcam"
	_replay_panel.visible = on
	_replay_tag.visible = on
	_replay_feed.visible = on
	_replay_tag_label.text = "KILL CAM" if killcam else ("HIGHLIGHTS" if kind == "highlights" else "REPLAY")
	for b in _replay_buttons:
		b.visible = not killcam
	_replay_skip.visible = killcam
	_replay_slider.visible = not killcam
	_replay_help.visible = not killcam
	_replay_panel.offset_top = -84 if killcam else -132


func _fmt(sec: float) -> String:
	var s := maxi(0, int(sec))
	return "%d:%02d" % [s / 60, s % 60]


## d: {title, t, len, clock, speed, paused, follow, feed, multi, kind}
func update_replay(d: Dictionary) -> void:
	_replay_title.text = String(d.title)
	_replay_time.text = "%s / %s" % [_fmt(float(d.t)), _fmt(float(d.len))]
	_replay_follow.text = "Following: %s" % String(d.follow)
	_slider_lock = true
	_replay_slider.value = clampf(float(d.t) / maxf(float(d.len), 0.01), 0.0, 1.0)
	_slider_lock = false
	_replay_play.text = "Play" if d.paused else "Pause"
	var sp: float = d.speed
	_replay_speed.text = "Speed %sx" % (str(int(sp)) if sp >= 1.0 else str(sp))
	for b in _replay_buttons:
		var cmd := String(b.get_meta("cmd", ""))
		if cmd == "prev" or cmd == "next":
			b.disabled = not d.multi
	_replay_feed.text = "\n".join(d.feed)


## Results screen: buttons for the round replays and the highlight reel.
func show_results_extras(n_rounds: int, n_highlights: int) -> void:
	if _results_bar != null:
		_results_bar.queue_free()
	# Right of the results panel (it is 940 wide, centred), stacked.
	_results_bar = UI.vbox(8)
	_anchor(_results_bar, 1, 0.5, 1, 0.5)
	_results_bar.offset_left = -160
	_results_bar.offset_right = -8
	_results_bar.offset_top = -60
	_results_bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_root.add_child(_results_bar)
	if n_highlights > 0:
		_results_bar.add_child(UI.small_button("Highlights (%d)" % n_highlights, func() -> void: results_cmd.emit("highlights"), 150, "PrimaryButton"))
	elif n_rounds > 0:
		var none := UI.small_button("No highlights", func() -> void: pass, 150)
		none.disabled = true
		_results_bar.add_child(none)
	if n_rounds > 0:
		_results_bar.add_child(UI.small_button("Round replays", func() -> void: results_cmd.emit("replays"), 150))


var _debug_label: Label


## F3 AI debug overlay text (top left).
func set_debug_text(text: String) -> void:
	if _debug_label == null:
		if text == "":
			return
		_debug_label = UI.label("", 11, Color(1, 1, 0.8), 600)
		_debug_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		_debug_label.add_theme_constant_override("shadow_offset_x", 1)
		_debug_label.add_theme_constant_override("shadow_offset_y", 1)
		_anchor(_debug_label, 0, 0, 0, 0)
		_debug_label.offset_left = 16
		_debug_label.offset_top = 92
		_debug_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(_debug_label)
	_debug_label.text = text
	_debug_label.visible = text != ""
