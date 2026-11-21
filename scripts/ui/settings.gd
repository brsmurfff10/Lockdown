extends Control
## Settings screen. Currently: crosshair editor with live preview.

var _preview: Crosshair
var _values := {} ## key -> current value (written to Game.settings.crosshair)
var _controls := {} ## key -> Control, for reset


func _ready() -> void:
	UI.setup_screen(self)
	_values = Crosshair.settings()
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 64)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	add_child(margin)
	var root := UI.vbox(18)
	margin.add_child(root)
	root.add_child(UI.heading("Settings", 34))

	var cols := UI.hbox(18)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)

	var box := UI.card(cols, "Crosshair", true, UI.ACCENT)
	box.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider(box, "length", "Line length", 0, 20, 1)
	_slider(box, "thickness", "Thickness", 1, 6, 1)
	_slider(box, "gap", "Center gap", 0, 14, 1)
	_slider(box, "dot_size", "Dot size", 1, 8, 1)
	_slider(box, "alpha", "Opacity", 0.2, 1.0, 0.05)
	var checks := GridContainer.new()
	checks.columns = 2
	checks.add_theme_constant_override("h_separation", 30)
	box.add_child(checks)
	_check(checks, "lines", "Show lines")
	_check(checks, "t_style", "T-style (no top line)")
	_check(checks, "dot", "Center dot")
	_check(checks, "outline", "Outline")
	_check(checks, "dynamic", "Dynamic (widens with spread)")
	_color(box)

	var right := UI.vbox(18)
	right.custom_minimum_size = Vector2(380, 0)
	var rs := UI.scroll(right) # More cards than fit at 720px: the column scrolls.
	rs.size_flags_horizontal = Control.SIZE_FILL
	rs.custom_minimum_size = Vector2(404, 0)
	cols.add_child(rs)
	var pbox := UI.card(right, "Preview", false, UI.ACCENT2)
	var stage := ColorRect.new()
	stage.color = Color(0.17, 0.18, 0.20)
	stage.custom_minimum_size = Vector2(340, 260)
	pbox.add_child(stage)
	_preview = Crosshair.new()
	stage.add_child(_preview)
	_preview.preview_center = Vector2(170, 95)
	var light := ColorRect.new() # A bright strip to check visibility on light floors.
	light.color = Color(0.75, 0.77, 0.8)
	light.position = Vector2(0, 175)
	light.size = Vector2(340, 85)
	stage.add_child(light)
	stage.move_child(light, 0)
	var second := Crosshair.new()
	stage.add_child(second)
	second.preview_center = Vector2(170, 217)

	var audio := UI.card(right, "Audio", false, UI.GOOD)
	for pair in [["master", "Master"], ["sfx", "Effects"], ["weapons", "Weapons"], ["ui", "Interface"]]:
		var key: String = pair[0]
		var row := UI.hbox(10)
		var l := UI.label(pair[1], 14, UI.TEXT_DIM, 500)
		l.custom_minimum_size = Vector2(80, 0)
		row.add_child(l)
		var s := HSlider.new()
		s.min_value = 0
		s.max_value = 100
		s.step = 1
		s.value = Game.volume(key)
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var v := UI.label("%d%%" % int(s.value), 13, UI.TEXT_DIM)
		v.custom_minimum_size = Vector2(44, 0)
		s.value_changed.connect(func(val: float) -> void:
			v.text = "%d%%" % int(val)
			Game.set_volume(key, val))
		row.add_child(s)
		row.add_child(v)
		audio.add_child(row)

	var disp := UI.card(right, "Display", false, UI.TEXT_DIM)
	var fs := CheckBox.new()
	fs.text = "Fullscreen  (F11)"
	fs.button_pressed = bool(Game.settings.get("fullscreen", true))
	fs.toggled.connect(func(on: bool) -> void: Game.set_fullscreen(on))
	disp.add_child(fs)
	var bl := CheckBox.new()
	bl.text = "Blood  (hit mist, spatter, pools)"
	bl.button_pressed = bool(Game.settings.get("blood", true))
	bl.toggled.connect(func(on: bool) -> void:
		Game.settings["blood"] = on
		Game.save_settings())
	disp.add_child(bl)

	_ai_card(right)

	var saves := UI.card(right, "Saves & logs", false, UI.WARN)
	var sl := UI.label("Careers save automatically. A backup is kept each in-game week (last %d per career)." % Game.BACKUPS, 12, UI.TEXT_DIM)
	sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	saves.add_child(sl)
	var sr := UI.hbox(8)
	sr.add_child(UI.button("Restore a backup", _show_backups, 0))
	sr.add_child(UI.button("Error log", _show_log, 0))
	for b in sr.get_children():
		(b as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	saves.add_child(sr)

	var buttons := UI.hbox(12)
	root.add_child(buttons)
	buttons.add_child(UI.button("Back", func() -> void:
		_save()
		Game.goto(Game.MENU_SCENE), 160, "GhostButton"))
	buttons.add_child(UI.spacer())
	buttons.add_child(UI.button("Reset crosshair", _reset, 200))


## Optional local LLM (Ollama) for My Player chat lines. Off by default.
func _ai_card(parent: Control) -> void:
	var ai := UI.card(parent, "Local AI chat (Ollama)", false, UI.ACCENT2)
	var on := CheckBox.new()
	on.text = "Local AI chat (Ollama)"
	on.button_pressed = LlmClient.enabled()
	on.toggled.connect(func(v: bool) -> void:
		Game.settings["llm_on"] = v
		Game.save_settings())
	ai.add_child(on)
	for f in [["URL", "llm_url", LlmClient.url()], ["Model", "llm_model", LlmClient.model()]]:
		var row := UI.hbox(10)
		var l := UI.label(String(f[0]), 14, UI.TEXT_DIM, 500)
		l.custom_minimum_size = Vector2(60, 0)
		row.add_child(l)
		var le := LineEdit.new()
		le.text = String(f[2])
		le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var key: String = f[1]
		le.text_changed.connect(func(t: String) -> void:
			Game.settings[key] = t.strip_edges()
			Game.save_settings())
		row.add_child(le)
		ai.add_child(row)
	var note := UI.label("Optional: needs Ollama running on this PC with the model pulled (e.g. ollama pull %s). The game decides what every message does; the model only words the replies of players, the coach and people on your feed. If it's off or doesn't answer within 6 seconds, the built-in lines are used." % LlmClient.DEFAULT_MODEL, 12, UI.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ai.add_child(note)
	var tr := UI.hbox(10)
	var status := UI.label("", 12, UI.TEXT_DIM)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tr.add_child(UI.small_button("Test connection", func() -> void:
		status.text = "Asking %s... (the first answer loads the model and can take up to a minute)" % LlmClient.model()
		status.add_theme_color_override("font_color", UI.TEXT_DIM)
		var client := LlmClient.new()
		client.timeout = 150.0
		add_child(client)
		client.chat("You are a test. Reply with one short friendly sentence.", "ping", func(t: String) -> void:
			if is_instance_valid(status):
				status.text = ("Connected: " + t) if t != "" else "No answer. Is Ollama running at that URL with that model?"
				status.add_theme_color_override("font_color", UI.GOOD if t != "" else UI.BAD)
			client.queue_free()), 150, "GhostButton"))
	tr.add_child(status)
	ai.add_child(tr)


func _slider(parent: Control, key: String, label: String, lo: float, hi: float, step: float) -> void:
	var row := UI.hbox(10)
	var l := UI.label(label, 14, UI.TEXT_DIM, 500)
	l.custom_minimum_size = Vector2(150, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(_values[key])
	s.custom_minimum_size = Vector2(180, 20)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(s)
	var v := UI.label(_fmt(s.value, step), 15, UI.TEXT_DIM)
	v.custom_minimum_size = Vector2(40, 0)
	row.add_child(v)
	s.value_changed.connect(func(val: float) -> void:
		_values[key] = val
		v.text = _fmt(val, step)
		_save())
	parent.add_child(row)
	_controls[key] = s


func _check(parent: Control, key: String, label: String) -> void:
	var c := CheckBox.new()
	c.text = label
	c.button_pressed = bool(_values[key])
	c.toggled.connect(func(on: bool) -> void:
		_values[key] = on
		_save())
	parent.add_child(c)
	_controls[key] = c


func _color(parent: Control) -> void:
	var row := UI.hbox(10)
	var l := UI.label("Color", 15)
	l.custom_minimum_size = Vector2(200, 0)
	row.add_child(l)
	var picker := ColorPickerButton.new()
	picker.color = Color.html(String(_values.color))
	picker.edit_alpha = false
	picker.custom_minimum_size = Vector2(80, 28)
	picker.color_changed.connect(func(col: Color) -> void:
		_values.color = col.to_html(false)
		_save())
	row.add_child(picker)
	# Quick presets.
	for hex in ["5cff7a", "ffffff", "00e5ff", "ffe14d", "ff4d4d", "ff66ff"]:
		var b := Button.new()
		b.custom_minimum_size = Vector2(24, 24)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color.html(hex)
		sb.set_corner_radius_all(4)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", sb)
		var h: String = hex
		b.pressed.connect(func() -> void:
			_values.color = h
			picker.color = Color.html(h)
			_save())
		row.add_child(b)
	parent.add_child(row)
	_controls["color"] = picker


func _fmt(v: float, step: float) -> String:
	return "%.2f" % v if step < 1.0 else "%d" % int(v)


func _save() -> void:
	Game.settings["crosshair"] = _values.duplicate()
	Game.save_settings()


func _reset() -> void:
	_values = Crosshair.DEFAULTS.duplicate()
	_save()
	get_tree().reload_current_scene()



func _show_backups() -> void:
	var m := UI.modal(self, 720, UI.WARN)
	var overlay: Control = m[0]
	var box: VBoxContainer = m[1]
	box.add_child(UI.heading("Restore a backup", 22))
	var note := UI.label("Restoring replaces that career's current save with the backup. Newest first.", 13, UI.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)
	for kind in [["world", "Career Mode (manager)"], ["player", "My Player"]]:
		box.add_child(UI.caption(kind[1], UI.TEXT))
		var list := Game.list_backups(kind[0])
		if list.is_empty():
			box.add_child(UI.label("No backups yet.", 13, UI.TEXT_FAINT))
		for b: Dictionary in list:
			var row := UI.hbox(10)
			row.add_child(UI.label("Season %d, week %d" % [int(b.season), int(b.week)], 14, UI.TEXT, 600))
			row.add_child(UI.label(String(b.team), 13, UI.ACCENT2))
			row.add_child(UI.spacer())
			row.add_child(UI.label(String(b.modified), 12, UI.TEXT_FAINT))
			var k: String = kind[0]
			var idx := int(b.index)
			row.add_child(UI.small_button("Restore", func() -> void:
				var ok := Game.restore_backup(k, idx)
				overlay.queue_free()
				_toast_msg("Backup restored." if ok else "Couldn't restore that backup.", ok), 100, "PrimaryButton"))
			box.add_child(row)
	var close := UI.hbox(10)
	close.add_child(UI.spacer())
	close.add_child(UI.button("Close", func() -> void: overlay.queue_free(), 140, "GhostButton"))
	box.add_child(close)


func _show_log() -> void:
	var m := UI.modal(self, 1000, UI.BAD)
	var overlay: Control = m[0]
	var box: VBoxContainer = m[1]
	var head := UI.hbox(10)
	head.add_child(UI.heading("Error log", 22))
	head.add_child(UI.spacer())
	var only := CheckBox.new()
	only.text = "Errors and warnings only"
	only.button_pressed = true
	head.add_child(only)
	box.add_child(head)
	var text := TextEdit.new()
	text.editable = false
	text.custom_minimum_size = Vector2(0, 460)
	text.add_theme_font_size_override("font_size", 12)
	text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	box.add_child(text)
	var count := UI.label("", 12, UI.TEXT_DIM)
	var fill := func() -> void:
		var lines := Game.read_log().split("\n")
		var shown: Array = []
		var errors := 0
		var i := 0
		while i < lines.size():
			var l := lines[i]
			var bad := l.contains("ERROR") or l.contains("WARNING")
			if bad:
				errors += 1
			if not only.button_pressed or bad:
				shown.append(l)
				# Keep the "at:" location line that follows an error.
				if bad and i + 1 < lines.size() and lines[i + 1].strip_edges().begins_with("at:"):
					shown.append(lines[i + 1])
					i += 1
			i += 1
		text.text = "\n".join(shown) if not shown.is_empty() else "No errors logged this session."
		count.text = "%d error/warning line(s) this session. Older logs are in the logs folder." % errors
	only.toggled.connect(func(_on: bool) -> void: fill.call())
	fill.call()
	var row := UI.hbox(10)
	row.add_child(count)
	row.add_child(UI.spacer())
	row.add_child(UI.button("Copy", func() -> void: DisplayServer.clipboard_set(text.text), 110, "GhostButton"))
	row.add_child(UI.button("Open logs folder", func() -> void: OS.shell_open(ProjectSettings.globalize_path("user://logs")), 180, "GhostButton"))
	row.add_child(UI.button("Close", func() -> void: overlay.queue_free(), 120, "PrimaryButton"))
	box.add_child(row)


var _toast_label: Label


func _toast_msg(msg: String, good: bool) -> void:
	if _toast_label == null or not is_instance_valid(_toast_label):
		_toast_label = UI.label("", 14, UI.GOOD, 600)
		_toast_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_toast_label.position = Vector2(get_viewport_rect().size.x - 420, 24)
		add_child(_toast_label)
	_toast_label.text = msg
	_toast_label.add_theme_color_override("font_color", UI.GOOD if good else UI.BAD)
