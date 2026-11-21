extends Control
## New Career setup: name your org, pick colours, choose a league and the team
## you take over (its roster becomes yours; the name/tag/colour are replaced).

const COLORS := ["4dd2ff", "ff5c5c", "5cff7a", "ffd24d", "c77dff", "ff8c42", "f2f2f2", "33c4b0"]
const COLS := [["Team", 0, "l"], ["RTG", 48, "c"], ["Rep", 44, "c"], ["Best player", 220, "l"], ["Avg age", 64, "c"], ["", 96, "c"], ["", 130, "r"]]

var _world: World
var _name_edit: LineEdit
var _tag_edit: LineEdit
var _color := Color.html("4dd2ff")
## New careers always start in the lowest league (Academy).
const STARTING_LEAGUE := 3
var _league := STARTING_LEAGUE
var _list: VBoxContainer
var _swatches: Array[Button] = []
var _league_bar: HBoxContainer
var _capital: Label
var _badge_holder: HBoxContainer


var _difficulty := "Normal"


func _ready() -> void:
	UI.setup_screen(self)
	_world = Game.new_manager_world(UI.team_pack())
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + s, 48)
	for s in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, 32)
	add_child(margin)
	var root := UI.vbox(14)
	margin.add_child(root)

	var head := UI.hbox(14)
	root.add_child(head)
	head.add_child(UI.heading("Found your organization", 32))
	head.add_child(UI.spacer())
	head.add_child(UI.label("Difficulty", 14, UI.TEXT_DIM))
	head.add_child(_difficulty_picker(_difficulty, func(d: String) -> void: _difficulty = d))
	var real := UI.team_pack_toggles(func() -> void:
		_world = Game.new_manager_world(UI.team_pack())
		_fill_list())
	if real != null:
		head.add_child(real)
	head.add_child(UI.button("New world", func() -> void:
		_world = Game.new_manager_world(UI.team_pack())
		_fill_list(), 140))
	head.add_child(UI.button("Back", func() -> void: Game.goto(Game.MENU_SCENE), 120, "GhostButton"))

	var form := UI.card(root, "Identity", false, UI.ACCENT)
	var row := UI.hbox(14)
	form.add_child(row)
	_badge_holder = UI.hbox(0)
	row.add_child(_badge_holder)
	var name_col := UI.vbox(4)
	name_col.add_child(UI.caption("Org name"))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "e.g. Midnight Esports"
	_name_edit.max_length = 22
	_name_edit.custom_minimum_size = Vector2(280, 40)
	_name_edit.text_changed.connect(func(_t: String) -> void: _refresh_badge())
	name_col.add_child(_name_edit)
	row.add_child(name_col)
	var tag_col := UI.vbox(4)
	tag_col.add_child(UI.caption("Tag"))
	_tag_edit = LineEdit.new()
	_tag_edit.placeholder_text = "MID"
	_tag_edit.max_length = 4
	_tag_edit.custom_minimum_size = Vector2(90, 40)
	_tag_edit.text_changed.connect(func(_t: String) -> void: _refresh_badge())
	tag_col.add_child(_tag_edit)
	row.add_child(tag_col)
	var col_col := UI.vbox(4)
	col_col.add_child(UI.caption("Colour"))
	var sw := UI.hbox(6)
	for hex in COLORS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(34, 34)
		var h: String = hex
		b.pressed.connect(func() -> void:
			_color = Color.html(h)
			_refresh_swatches()
			_refresh_badge())
		sw.add_child(b)
		_swatches.append(b)
	col_col.add_child(sw)
	row.add_child(col_col)
	row.add_child(UI.spacer())
	var cap_col := UI.vbox(0)
	_capital = UI.label("", 22, UI.GOOD, 700)
	cap_col.add_child(UI.caption("Investor capital"))
	cap_col.add_child(_capital)
	row.add_child(cap_col)
	_refresh_swatches()
	_refresh_badge()

	_league_bar = UI.hbox(8)
	root.add_child(_league_bar)

	var lc := UI.card(root, "Choose the team you take over", true, UI.ACCENT2)
	lc.add_child(UI.table_header(COLS))
	_list = UI.vbox(2)
	lc.add_child(UI.scroll(_list))
	_fill_list()


func _refresh_swatches() -> void:
	for i in _swatches.size():
		var c := Color.html(COLORS[i])
		var on := c.is_equal_approx(_color)
		var sb := UI._box(c, 7, Color.WHITE if on else Color(0, 0, 0, 0), 3 if on else 0)
		for st in ["normal", "hover", "pressed"]:
			_swatches[i].add_theme_stylebox_override(st, sb)


func _refresh_badge() -> void:
	for c in _badge_holder.get_children():
		c.queue_free()
	var tag := _tag_edit.text.strip_edges() if _tag_edit != null and _tag_edit.text.strip_edges() != "" else "NEW"
	_badge_holder.add_child(UI.team_badge(tag, _color, 50))


func _fill_list() -> void:
	for c in _league_bar.get_children():
		c.queue_free()
	_league_bar.add_child(UI.caption("Start in", UI.TEXT_DIM))
	for l in World.LEAGUES.size():
		var lg: Dictionary = World.LEAGUES[l]
		var li := l
		var b := UI.small_button("%s  %d-%d" % [String(lg.name).replace(" League", ""), int(lg.quality[0]), int(lg.quality[1])], func() -> void:
			_league = li
			_fill_list(), 150, "PrimaryButton" if l == _league else "")
		if l != STARTING_LEAGUE:
			b.disabled = true
			b.text += "  (locked)"
			b.tooltip_text = "New orgs start in the %s. Earn promotion to get here." % World.LEAGUES[STARTING_LEAGUE].name
		_league_bar.add_child(b)
	_league_bar.add_child(UI.spacer())
	_league_bar.add_child(UI.label("Every org starts at the bottom.
Win promotion to climb.", 12, UI.TEXT_FAINT))
	_capital.text = UI.money_text(int(World.LEAGUES[_league].budget * 0.4) + 150000)

	for c in _list.get_children():
		c.queue_free()
	var lt := _world.league_teams(_league)
	lt.sort_custom(func(a: TeamData, b: TeamData) -> bool: return a.rating() > b.rating())
	var i := 0
	for t in lt:
		var best: PlayerData = t.roster[0]
		var age_sum := 0
		for p in t.roster:
			age_sum += p.age
			if p.rating_exact() > best.rating_exact():
				best = p
		var idx := _world.team_index(t)
		var take := UI.small_button("Take over", func() -> void:
			_world.set_difficulty(_difficulty)
			Game.start_manager_career(_world, idx, _name_edit.text, _tag_edit.text, _color)
			Game.goto(Game.MANAGER_SCENE), 120, "PrimaryButton")
		# Squad dropdown: every player and attribute, hidden until opened.
		var squad := MarginContainer.new()
		squad.add_theme_constant_override("margin_left", 28)
		squad.add_theme_constant_override("margin_bottom", 10)
		squad.add_child(UI.squad_table(t.roster))
		squad.visible = false
		var toggle := UI.small_button("Squad  \u25be", func() -> void: pass, 92, "GhostButton")
		toggle.pressed.connect(func() -> void:
			squad.visible = not squad.visible
			toggle.text = "Squad  \u25b4" if squad.visible else "Squad  \u25be")
		_list.add_child(UI.table_row([UI.team_label(t, 15), UI.rating_chip(t.rating()), UI.label(str(int(t.reputation)), 14, UI.TEXT_DIM),
			UI.label("%s  (%d, %s)" % [best.player_name, best.rating(), best.role], 13, UI.TEXT_DIM),
			UI.label("%.1f" % (float(age_sum) / t.roster.size()), 14, UI.TEXT_DIM), toggle, take], COLS, i))
		_list.add_child(squad)
		i += 1


## Difficulty preset picker (Casual / Normal / Hardcore) with its description as a tooltip.
func _difficulty_picker(current: String, on_pick: Callable) -> OptionButton:
	var o := OptionButton.new()
	var keys: Array = World.DIFFICULTIES.keys()
	for k: String in keys:
		o.add_item(k)
	o.select(maxi(0, keys.find(current)))
	o.tooltip_text = String(World.DIFFICULTIES[current].desc)
	o.item_selected.connect(func(i: int) -> void:
		o.tooltip_text = String(World.DIFFICULTIES[keys[i]].desc)
		on_pick.call(String(keys[i])))
	return o
