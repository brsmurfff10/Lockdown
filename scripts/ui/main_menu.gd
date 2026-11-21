extends Control
## Title screen: menu on the left, live summaries of your careers on the right.

var _menu: VBoxContainer
var _side: VBoxContainer


func _ready() -> void:
	UI.setup_screen(self)
	if _ready_spectate_shortcut():
		return
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + s, 72)
	for s in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, 56)
	add_child(margin)
	var cols := UI.hbox(56)
	margin.add_child(cols)

	var left := UI.vbox(10)
	left.custom_minimum_size = Vector2(420, 0)
	cols.add_child(left)
	var title := UI.hbox(6)
	for part in [["LOCK", UI.TEXT], ["DOWN", UI.ACCENT]]:
		var l := UI.label(part[0], 84, part[1], 700)
		l.add_theme_font_override("font", UI.font_spaced(700, 6))
		title.add_child(l)
	left.add_child(title)
	var tag := UI.hbox(12)
	var line := ColorRect.new()
	line.color = UI.ACCENT
	line.custom_minimum_size = Vector2(44, 3)
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tag.add_child(line)
	tag.add_child(UI.caption("Tactical 5v5   /   Career   /   Manager", UI.TEXT_DIM))
	left.add_child(tag)
	left.add_child(UI.gap(36))
	_menu = UI.vbox(8)
	left.add_child(_menu)
	left.add_child(UI.spacer(false))
	left.add_child(UI.label("v%s     F11  fullscreen     Esc  back" % PatchNotes.VERSION, 12, UI.TEXT_FAINT))

	_side = UI.vbox(16)
	_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(_side)
	_build_side()
	_show_main()


func _ready_spectate_shortcut() -> bool:
	# Launch straight into a bot match with `-- --spectate`.
	if "--spectate" in OS.get_cmdline_user_args() and not Game.has_meta("spectate_launched"):
		Game.set_meta("spectate_launched", true)
		Game.prepare_spectate_match()
		Game.goto(Game.MATCH_SCENE)
		return true
	return false


func _clear() -> void:
	for c in _menu.get_children():
		c.queue_free()


func _menu_title(text: String) -> void:
	_menu.add_child(UI.caption(text, UI.TEXT_DIM))


func _btn(text: String, cb: Callable, kind: String = "", sub: String = "") -> void:
	if kind == "GhostButton":
		# Quiet secondary actions (Back, Quit): plain text row.
		var g := UI.button(text, cb, 420, kind)
		g.alignment = HORIZONTAL_ALIGNMENT_LEFT
		g.custom_minimum_size.y = 40
		g.add_theme_font_size_override("font_size", 15)
		g.focus_mode = Control.FOCUS_NONE
		_menu.add_child(g)
		return
	_menu.add_child(UI.menu_item(text, sub, cb, kind == "PrimaryButton"))


func _show_main() -> void:
	_clear()
	_btn("Career Mode", _show_career, "PrimaryButton", "Run an esports organization")
	_btn("My Player", func() -> void: Game.goto(Game.MY_PLAYER_SCENE), "", "Play your way up as one player")
	_btn("Quick Match", _show_maps, "", "Jump into a 5v5 on any map")
	_btn("Watch Bot Match", func() -> void:
		Game.prepare_spectate_match()
		Game.goto(Game.MATCH_SCENE), "", "Spectate two AI teams")
	# Achievements and patch notes share one row of smaller buttons.
	var extra := UI.hbox(8)
	var ach := UI.button("Achievements  %d/%d" % [Game.achievements.size(), Game.ACHIEVEMENTS.size()], _show_achievements, 130)
	var unseen := String(Game.settings.get("notes_seen", "")) != PatchNotes.VERSION
	var pn := UI.button(("Patch Notes  NEW" if unseen else "Patch Notes  v%s" % PatchNotes.VERSION), _show_patch_notes, 130, "PrimaryButton" if unseen else "")
	var ed := UI.button("Editor", func() -> void: Game.goto(Game.EDITOR_SCENE), 130)
	ed.tooltip_text = "Edit team names, colours and logos, and player names and nations"
	for b: Button in [ach, pn, ed]:
		b.custom_minimum_size.y = 44
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 14)
		b.focus_mode = Control.FOCUS_NONE
		extra.add_child(b)
	_menu.add_child(extra)
	_btn("Settings", func() -> void: Game.goto(Game.SETTINGS_SCENE), "", "Crosshair, audio, display")
	_btn("Quit", func() -> void: get_tree().quit(), "GhostButton")


func _show_maps() -> void:
	_clear()
	_menu_title("Quick match  -  choose a map")
	for map_name: String in Maps.LIST:
		var d := Maps.get_map(map_name)
		var mn := map_name
		_btn(map_name, func() -> void:
			Game.prepare_quick_match(mn)
			Game.goto(Game.MATCH_SCENE), "", "%d x %d" % [d.size.x, d.size.y])
	_btn("Random map", func() -> void:
		Game.prepare_quick_match(Maps.random_name(Game.rng))
		Game.goto(Game.MATCH_SCENE), "PrimaryButton", "Surprise me")
	_btn("Back", _show_main, "GhostButton")


func _show_career() -> void:
	_clear()
	_menu_title("Career Mode  -  run an esports organization")
	if Game.world != null:
		var w := Game.world
		_btn("Continue", func() -> void: Game.goto(Game.MANAGER_SCENE), "PrimaryButton", "%s  -  season %d, week %d" % [w.user_team().team_name, w.season, w.week])
	_btn("New Career", _confirm_new_career, "", "Found a new organization")
	_btn("Back", _show_main, "GhostButton")


func _confirm_new_career() -> void:
	if Game.world == null:
		_start_new_career()
		return
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = "Start a new Career?\nYour current organization will be lost."
	dlg.confirmed.connect(_start_new_career)
	add_child(dlg)
	dlg.popup_centered()


func _start_new_career() -> void:
	Game.goto(Game.MANAGER_SETUP_SCENE)


# --- Right side: career summaries -------------------------------------------

func _build_side() -> void:
	_side.add_child(UI.gap(96))
	var row := UI.hbox(16)
	_side.add_child(row)

	var c1 := UI.card(row, "Career Mode", false, UI.ACCENT)
	c1.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if Game.world != null:
		var w := Game.world
		var t := w.user_team()
		c1.add_child(UI.team_label(t, 22, true))
		c1.add_child(UI.label("%s  -  Season %d, week %d" % [w.league_name(t), w.season, w.week], 14, UI.TEXT_DIM))
		var chips := UI.hbox(26)
		chips.add_child(UI.stat_chip("Balance", UI.money_text(w.money), UI.GOOD if w.money >= 0 else UI.BAD))
		chips.add_child(UI.stat_chip("World", "#%d" % w.world_rank(t)))
		chips.add_child(UI.stat_chip("Team", str(t.rating()), UI.rating_color(t.rating())))
		c1.add_child(chips)
	else:
		c1.add_child(UI.label("Found an organization in any of 4 leagues,\nsign players, train them and climb from\nthe Academy to the Premier League.", 15, UI.TEXT_DIM))

	var c2 := UI.card(row, "My Player", false, UI.ACCENT2)
	c2.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if Game.my_player != null:
		var p := Game.my_player
		var h := UI.hbox(14)
		h.add_child(UI.rating_badge(p.rating(), 40))
		var info := UI.vbox(2)
		info.add_child(UI.label(p.player_name, 22, UI.TEXT, 700))
		info.add_child(UI.label("%s  -  age %d" % [p.role, p.age], 14, UI.TEXT_DIM))
		if Game.career_active:
			var t := Game.pworld.user_team()
			info.add_child(UI.label("%s  -  %s" % [t.team_name, Game.pworld.league_name(t)], 14, t.color))
		h.add_child(info)
		c2.add_child(h)
	else:
		c2.add_child(UI.label("Create your own player and play\nyour way up from the Academy League.", 15, UI.TEXT_DIM))

	var maps := UI.card(_side, "Maps", false, UI.TEXT_DIM)
	var mrow := UI.hbox(10)
	for m: String in Maps.LIST:
		var d := Maps.get_map(m)
		mrow.add_child(UI.pill("%s  %dx%d" % [m, d.size.x, d.size.y], UI.TEXT_DIM))
	maps.add_child(mrow)


func _show_achievements() -> void:
	var m := UI.modal(self, 760, UI.WARN)
	var overlay: Control = m[0]
	var box: VBoxContainer = m[1]
	box.add_child(UI.heading("Achievements  %d / %d" % [Game.achievements.size(), Game.ACHIEVEMENTS.size()], 24))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	for id: String in Game.ACHIEVEMENTS:
		var a: Dictionary = Game.ACHIEVEMENTS[id]
		var has := Game.achievements.has(id)
		var p := PanelContainer.new()
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p.add_theme_stylebox_override("panel", UI._box(Color(UI.WARN, 0.1) if has else UI.PANEL_LO, 4, UI.WARN if has else UI.BORDER, 1, 10, 6))
		var v := UI.vbox(1)
		var h := UI.hbox(6)
		h.add_child(UI.label(String(a.name), 14, UI.WARN if has else UI.TEXT_DIM, 700))
		h.add_child(UI.spacer())
		if has:
			h.add_child(UI.label(String(Game.achievements[id]), 11, UI.TEXT_FAINT))
		v.add_child(h)
		v.add_child(UI.label(String(a.desc), 12, UI.TEXT_DIM if has else UI.TEXT_FAINT))
		p.add_child(v)
		grid.add_child(p)
	var sc := UI.scroll(grid)
	sc.custom_minimum_size = Vector2(0, 520)
	box.add_child(sc)
	var row := UI.hbox(10)
	row.add_child(UI.label("Kept across every save, in both careers.", 12, UI.TEXT_FAINT))
	row.add_child(UI.spacer())
	row.add_child(UI.button("Close", func() -> void: overlay.queue_free(), 140, "GhostButton"))
	box.add_child(row)


func _show_patch_notes() -> void:
	Game.settings["notes_seen"] = PatchNotes.VERSION
	Game.save_settings()
	var m := UI.modal(self, 900, UI.ACCENT)
	var overlay: Control = m[0]
	var box: VBoxContainer = m[1]
	var head := UI.hbox(12)
	head.add_child(UI.heading("Patch notes", 26))
	var cur := UI.label("Current version v%s" % PatchNotes.VERSION, 14, UI.TEXT_DIM)
	cur.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(cur)
	box.add_child(head)
	var list := UI.vbox(14)
	for i in PatchNotes.NOTES.size():
		var n: Dictionary = PatchNotes.NOTES[i]
		var latest := i == 0
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", UI._edge_box(UI.PANEL_HI if latest else UI.PANEL, UI.ACCENT if latest else UI.BORDER, SIDE_LEFT, 3, Color(0, 0, 0, 0), 16, 10))
		var v := UI.vbox(4)
		p.add_child(v)
		var h := UI.hbox(10)
		h.add_child(UI.label("v" + String(n.ver), 18, UI.ACCENT if latest else UI.ACCENT2, 700))
		h.add_child(UI.label(String(n.title), 17, UI.TEXT, 700))
		if latest:
			h.add_child(UI.pill("Latest", UI.GOOD))
		h.add_child(UI.spacer())
		h.add_child(UI.label(String(n.date), 12, UI.TEXT_FAINT))
		v.add_child(h)
		for it in n.items:
			var l := UI.label("-  " + String(it), 13, UI.TEXT_DIM)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v.add_child(l)
		list.add_child(p)
	var sc := UI.scroll(list)
	sc.custom_minimum_size = Vector2(0, 600)
	box.add_child(sc)
	var row := UI.hbox(10)
	row.add_child(UI.label("%d updates" % PatchNotes.NOTES.size(), 12, UI.TEXT_FAINT))
	row.add_child(UI.spacer())
	row.add_child(UI.button("Close", func() -> void:
		overlay.queue_free()
		_show_main(), 140, "GhostButton"))
	box.add_child(row)
