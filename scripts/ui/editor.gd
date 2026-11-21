extends Control
## Team and player editor: names, tags, colours and logo styles for any team in
## either career, plus player names and nations.

const PALETTE := ["d94d40", "f2b333", "ff7f2e", "4ade80", "33bfb3", "38d0ff", "408cf2", "8c59d9", "c084fc", "f472b6",
	"eef1f6", "8c998c", "545d70", "1f2937", "7c2d12", "065f46"]

var _career := "world" ## "world" (manager) or "player".
var _team: TeamData
var _query := ""
var _list: VBoxContainer
var _editor: VBoxContainer
var _toast: Label
var _draft := {} ## name, tag, color, color2, logo


func _ready() -> void:
	UI.setup_screen(self)
	if Game.world == null and Game.pworld != null:
		_career = "player"
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	var root := UI.vbox(14)
	margin.add_child(root)
	var head := UI.hbox(10)
	head.add_child(UI.heading("Editor", 32))
	for c in [["world", "Career Mode"], ["player", "My Player"]]:
		var key: String = c[0]
		var exists := (Game.world if key == "world" else Game.pworld) != null
		var b := UI.small_button(c[1], func() -> void:
			_career = key
			_team = null
			_rebuild(), 140, "PrimaryButton" if key == _career else "GhostButton")
		b.disabled = not exists
		head.add_child(b)
	head.add_child(UI.spacer())
	_toast = UI.label("", 14, UI.GOOD, 600)
	head.add_child(_toast)
	head.add_child(UI.button("Back", func() -> void: Game.goto(Game.MENU_SCENE), 140, "GhostButton"))
	root.add_child(head)
	var w := _world()
	if w == null:
		root.add_child(UI.label("Start a career first: the editor changes teams and players in your saved careers.", 16, UI.TEXT_DIM))
		return
	if not RealTeams.in_menus().is_empty():
		var rr := UI.hbox(10)
		var note := UI.label("Team packs rename the clubs and players in this save to real teams (stats, contracts and history stay).", 13, UI.TEXT_DIM)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rr.add_child(note)
		for pk: String in RealTeams.in_menus():
			var b := UI.button("Apply " + RealTeams.label(pk), _confirm_real.bind(pk), 200, "PrimaryButton")
			b.tooltip_text = RealTeams.source(pk)
			rr.add_child(b)
		root.add_child(rr)
	var cols := UI.hbox(16)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)
	var left := UI.card(cols, "Teams", true, UI.ACCENT)
	left.get_parent().custom_minimum_size = Vector2(320, 0)
	var q := LineEdit.new()
	q.placeholder_text = "Search teams..."
	q.text = _query
	q.text_changed.connect(func(t: String) -> void:
		_query = t
		_fill_list())
	left.add_child(q)
	_list = UI.vbox(2)
	left.add_child(UI.scroll(_list))
	_editor = UI.vbox(12)
	_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(UI.scroll(_editor))
	if _team == null:
		_team = w.user_team()
	_fill_list()
	_build_editor()


func _confirm_real(pack: String) -> void:
	var dlg := ConfirmationDialog.new()
	var n := mini(RealTeams.teams(pack).size(), 64)
	dlg.dialog_text = "Apply %s (%s) to your %s save?\nThe %d strongest clubs and their players are renamed.\n%s\nA backup of the current save is kept (Settings > Saves & logs)." % [
		RealTeams.label(pack), RealTeams.source(pack), "Career Mode" if _career == "world" else "My Player", n,
		"Your club keeps its name." if _career == "world" else "Your own player keeps their name."]
	dlg.confirmed.connect(func() -> void:
		var w := _world()
		Game.call("_backup", Game.MANAGER_PATH if _career == "world" else Game.PLAYER_CAREER_PATH, -w.stamp())
		var n2 := RealTeams.apply_existing(w, pack)
		_save()
		_team = null
		_rebuild()
		_say("Renamed %d clubs." % n2))
	add_child(dlg)
	dlg.popup_centered()


func _world() -> World:
	return Game.world if _career == "world" else Game.pworld


func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	_ready()


func _say(msg: String, ok: bool = true) -> void:
	_toast.text = msg
	_toast.add_theme_color_override("font_color", UI.GOOD if ok else UI.BAD)


func _save() -> void:
	if _career == "world":
		Game.save_world()
	else:
		Game.save_player_career()


func _fill_list() -> void:
	for c in _list.get_children():
		c.queue_free()
	var w := _world()
	var needle := _query.strip_edges().to_lower()
	for l in World.LEAGUES.size():
		var shown := false
		for t in w.league_teams(l):
			if needle != "" and not t.team_name.to_lower().contains(needle) and not t.short_name.to_lower().contains(needle):
				continue
			if not shown:
				_list.add_child(UI.caption(World.LEAGUES[l].name, UI.TEXT_DIM))
				shown = true
			var row := UI.hbox(8)
			row.add_child(UI.team_badge_for(t, 20))
			var tt := t
			var b := UI.link_button(t.team_name, func() -> void:
				_team = tt
				_draft = {}
				_build_editor(), 14, UI.ACCENT2 if t == _team else UI.TEXT, 600 if t == _team else 400)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(b)
			_list.add_child(row)


func _build_editor() -> void:
	for c in _editor.get_children():
		c.queue_free()
	var t := _team
	if _draft.is_empty():
		_draft = {"name": t.team_name, "tag": t.short_name, "color": t.color, "color2": t.color2, "logo": t.logo}
	var card := UI.card(_editor, "Team", false, UI.ACCENT2)
	var top := UI.hbox(18)
	card.add_child(top)
	var preview := UI.vbox(6)
	for sz in [64, 24]:
		var lb: PanelContainer = UI.logo_badge(String(_draft.logo).substr(4), _draft.color, sz) if String(_draft.logo).begins_with("img:") else null
		preview.add_child(lb if lb != null else UI.team_badge_styled(String(_draft.tag), _draft.color, _draft.color2, String(_draft.logo), sz))
	top.add_child(preview)
	var fields := UI.vbox(6)
	fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(fields)
	fields.add_child(UI.caption("Name"))
	var ne := LineEdit.new()
	ne.text = String(_draft.name)
	ne.max_length = 24
	ne.text_changed.connect(func(v: String) -> void: _draft.name = v)
	fields.add_child(ne)
	fields.add_child(UI.caption("Tag (2-4 letters)"))
	var te := LineEdit.new()
	te.text = String(_draft.tag)
	te.max_length = 4
	te.text_changed.connect(func(v: String) -> void:
		_draft.tag = v.to_upper()
		_build_editor())
	fields.add_child(te)
	card.add_child(UI.caption("Main colour"))
	card.add_child(_swatches("color", false))
	card.add_child(UI.caption("Second colour"))
	card.add_child(_swatches("color2", true))
	card.add_child(UI.caption("Logo style"))
	var ls := UI.hbox(8)
	var styles: Array = UI.LOGO_STYLES.duplicate()
	if t.logo.begins_with("img:"):
		styles.insert(0, t.logo)
	for st: String in styles:
		var stn := st
		var b := UI.small_button("Real logo" if st.begins_with("img:") else st.capitalize(), func() -> void:
			_draft.logo = stn
			_build_editor(), 90, "PrimaryButton" if st == String(_draft.logo) else "GhostButton")
		ls.add_child(b)
	card.add_child(ls)
	var save := UI.hbox(10)
	save.add_child(UI.spacer())
	save.add_child(UI.button("Revert", func() -> void:
		_draft = {}
		_build_editor(), 120, "GhostButton"))
	save.add_child(UI.button("Save team", _save_team, 160, "PrimaryButton"))
	card.add_child(save)
	# Players
	var pc := UI.card(_editor, "Players", false, UI.ACCENT)
	for p in t.roster:
		if p.is_user and _career == "player":
			continue
		var row := UI.hbox(8)
		row.add_child(UI.rating_chip(p.rating(), 12))
		var pn := LineEdit.new()
		pn.text = p.player_name
		pn.max_length = 18
		pn.custom_minimum_size = Vector2(220, 0)
		row.add_child(pn)
		var na := OptionButton.new()
		var nats := PlayerData.all_nations()
		if not nats.has(p.nation):
			nats.append(p.nation)
		for n: String in nats:
			na.add_item(n)
		na.select(maxi(0, nats.find(p.nation)))
		row.add_child(na)
		row.add_child(UI.label(p.role, 12, UI.TEXT_DIM))
		row.add_child(UI.spacer())
		var pp := p
		row.add_child(UI.small_button("Save", func() -> void:
			var err := ""
			if pn.text.strip_edges() != pp.player_name:
				err = _world().rename_player(pp, pn.text)
			if err == "":
				pp.nation = String(nats[na.selected])
				_save()
				_say("Saved %s." % pp.player_name)
			else:
				_say(err, false), 80, "PrimaryButton"))
		pc.add_child(row)
	pc.add_child(UI.label("Names must be unique in the world. Stats can't be edited.", 12, UI.TEXT_FAINT))


func _swatches(key: String, allow_none: bool) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 6)
	f.add_theme_constant_override("v_separation", 6)
	if allow_none:
		var nb := UI.small_button("Auto", func() -> void:
			_draft[key] = Color(0, 0, 0, 0)
			_build_editor(), 60, "PrimaryButton" if (_draft[key] as Color).a == 0.0 else "GhostButton")
		f.add_child(nb)
	for hx: String in PALETTE:
		var col := Color.html(hx)
		var b := Button.new()
		b.custom_minimum_size = Vector2(30, 30)
		b.focus_mode = Control.FOCUS_NONE
		var cur: Color = _draft[key]
		var sel := cur.a > 0.0 and cur.to_html(false) == col.to_html(false)
		for st in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(st, UI._box(col, 4, UI.TEXT if sel else Color(0, 0, 0, 0.5), 3 if sel else 1, 0, 0))
		var cc := col
		b.pressed.connect(func() -> void:
			_draft[key] = cc
			_build_editor())
		f.add_child(b)
	return f


func _save_team() -> void:
	var w := _world()
	var t := _team
	var err := ""
	if String(_draft.name).strip_edges() != t.team_name or String(_draft.tag).strip_edges().to_upper() != t.short_name:
		err = w.rename_team(t, String(_draft.name), String(_draft.tag))
	if err != "":
		_say(err, false)
		return
	t.color = _draft.color
	t.color2 = _draft.color2
	t.logo = String(_draft.logo)
	_save()
	_draft = {}
	_say("Saved %s." % t.team_name)
	_fill_list()
	_build_editor()
