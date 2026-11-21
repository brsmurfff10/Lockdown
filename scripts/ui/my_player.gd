extends Control
## My Player: create your character, or view their profile and start/continue
## the My Player career.

const ROLE_DESC := {
	"Entry": "First through the door. Fast reactions and movement.",
	"Rifler": "Consistent gunfighter. Strong aim and spray control.",
	"AWPer": "The sniper. Elite aim and flicks, weaker spray and movement.",
	"Support": "Utility and teamplay. Smart decisions, softer aim.",
	"Lurker": "Plays alone, flanks. Great positioning and game sense.",
}

var _name_edit: LineEdit
var _role := "Rifler"
var _preview: VBoxContainer
var _role_buttons := {}


func _ready() -> void:
	UI.setup_screen(self)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + s, 64)
	for s in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, 40)
	add_child(margin)
	var root := UI.vbox(18)
	margin.add_child(root)
	if Game.my_player == null:
		_build_create(root)
	else:
		_build_view(root)


# --- Create ------------------------------------------------------------------

var _nation_pick: OptionButton
var _difficulty := "Normal"


func _build_create(root: VBoxContainer) -> void:
	root.add_child(UI.heading("Create your player", 34))
	var cols := UI.hbox(18)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)

	var left := UI.card(cols, "Identity", true, UI.ACCENT)
	left.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(UI.caption("Handle"))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "e.g. Phantom"
	_name_edit.max_length = 14
	_name_edit.custom_minimum_size = Vector2(0, 44)
	_name_edit.add_theme_font_size_override("font_size", 18)
	left.add_child(_name_edit)
	left.add_child(UI.gap(6))
	left.add_child(UI.caption("Nation"))
	_nation_pick = OptionButton.new()
	_nation_pick.add_item("Random")
	for n: String in PlayerData.all_nations():
		_nation_pick.add_item(n)
	_nation_pick.tooltip_text = "Who you'd play for at the World Cup."
	left.add_child(_nation_pick)
	left.add_child(UI.gap(6))
	left.add_child(UI.caption("Role"))
	for r: String in PlayerData.ROLES:
		var b := Button.new()
		b.toggle_mode = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 56)
		b.text = "%s\n%s" % [r, ROLE_DESC[r]]
		b.add_theme_font_size_override("font_size", 14)
		var role := r
		b.pressed.connect(func() -> void: _pick_role(role))
		left.add_child(b)
		_role_buttons[r] = b

	var right := UI.card(cols, "Starting attributes  -  age 18 rookie", true, UI.ACCENT2)
	right.get_parent().custom_minimum_size = Vector2(520, 0)
	_preview = UI.vbox(8)
	right.add_child(_preview)
	_pick_role(_role)

	var buttons := UI.hbox(12)
	root.add_child(buttons)
	buttons.add_child(UI.button("Back", func() -> void: Game.goto(Game.MENU_SCENE), 160, "GhostButton"))
	buttons.add_child(UI.spacer())
	buttons.add_child(UI.button("Create Player", _on_create, 260, "PrimaryButton"))


func _pick_role(role: String) -> void:
	_role = role
	for r in _role_buttons:
		(_role_buttons[r] as Button).button_pressed = r == role
	for c in _preview.get_children():
		c.queue_free()
	var bias: Dictionary = PlayerData.ROLE_BIAS[role]
	var total := 0.0
	var head := UI.hbox(14)
	_preview.add_child(head)
	for k: String in PlayerData.STAT_KEYS:
		var v := 48.0 + float(bias.get(k, 0))
		total += v
		_preview.add_child(UI.stat_row(k, v))
	var rating := int(round(total / PlayerData.STAT_KEYS.size()))
	head.add_child(UI.rating_badge(rating, 40))
	var info := UI.vbox(2)
	info.add_child(UI.label(role, 22, UI.TEXT, 700))
	info.add_child(UI.label(ROLE_DESC[role], 13, UI.TEXT_DIM))
	head.add_child(info)


func _on_create() -> void:
	var n := _name_edit.text.strip_edges()
	if n == "":
		_name_edit.placeholder_text = "Enter a handle first!"
		_name_edit.grab_focus()
		return
	Game.create_my_player(n, _role, "" if _nation_pick.selected <= 0 else String(PlayerData.all_nations()[_nation_pick.selected - 1]))
	get_tree().reload_current_scene()


# --- View --------------------------------------------------------------------

func _build_view(root: VBoxContainer) -> void:
	var p := Game.my_player
	var top := UI.hbox(18)
	root.add_child(top)
	top.add_child(UI.rating_badge(p.rating(), 56))
	var info := UI.vbox(2)
	info.add_child(UI.label(p.player_name, 38, UI.TEXT, 700))
	var sub := UI.hbox(8)
	sub.add_child(UI.pill(p.role, UI.ACCENT2))
	sub.add_child(UI.pill("Age %d" % p.age, UI.TEXT_DIM))
	sub.add_child(UI.pill("Potential: " + _potential_text(p), UI.WARN))
	info.add_child(sub)
	top.add_child(info)
	top.add_child(UI.spacer())
	if Game.career_active:
		var t := Game.pworld.user_team()
		var tb := UI.vbox(2)
		tb.add_child(UI.team_label(t, 20, true))
		tb.add_child(UI.label(Game.pworld.league_name(t), 13, UI.TEXT_DIM))
		top.add_child(tb)

	var cols := UI.hbox(18)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)
	var attrs := UI.card(cols, "Attributes", true, UI.ACCENT2)
	attrs.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for k: String in PlayerData.STAT_KEYS:
		attrs.add_child(UI.stat_row(k, p.stat(k)))
	attrs.add_child(UI.label("Rating = average of all attributes (20-100). Hover an attribute for details.", 12, UI.TEXT_FAINT))

	var right := UI.vbox(18)
	right.custom_minimum_size = Vector2(440, 0)
	cols.add_child(right)
	var cc := UI.card(right, "Career", false, UI.ACCENT)
	var chips := UI.hbox(28)
	chips.add_child(UI.stat_chip("Matches", str(p.matches_played)))
	chips.add_child(UI.stat_chip("K / D", "%.2f" % (float(p.career_kills) / maxf(1.0, float(p.career_deaths)))))
	chips.add_child(UI.stat_chip("Form", "%.2f" % p.avg_recent_rating(), UI.GOOD if p.avg_recent_rating() >= 1.0 else UI.WARN))
	chips.add_child(UI.stat_chip("Titles", str(p.titles), UI.WARN if p.titles > 0 else UI.TEXT))
	cc.add_child(chips)

	var mc := UI.card(right, "My Player career", false, UI.ACCENT)
	var blurb := UI.label("Play every match yourself in the 64-team world. Training is a gamble and your stats move with how well you play.", 13, UI.TEXT_DIM)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mc.add_child(blurb)
	if Game.career_active:
		mc.add_child(UI.button("Continue career", func() -> void: Game.goto(Game.CAREER_SCENE), 0, "PrimaryButton"))
	var dr := UI.hbox(8)
	dr.add_child(UI.label("Difficulty for a new career", 13, UI.TEXT_DIM))
	dr.add_child(UI.spacer())
	dr.add_child(_difficulty_picker(_difficulty, func(d: String) -> void: _difficulty = d))
	mc.add_child(dr)
	var real := UI.team_pack_toggles(func() -> void: pass)
	if real != null:
		mc.add_child(real)
	mc.add_child(UI.button("New career", _confirm_new_career, 0, "" if Game.career_active else "PrimaryButton"))

	var buttons := UI.hbox(12)
	root.add_child(buttons)
	buttons.add_child(UI.button("Back", func() -> void: Game.goto(Game.MENU_SCENE), 160, "GhostButton"))
	buttons.add_child(UI.spacer())
	buttons.add_child(UI.button("Delete Player", _confirm_delete, 180, "DangerButton"))


func _potential_text(p: PlayerData) -> String:
	var gap := p.potential - p.rating()
	if gap >= 25:
		return "Generational"
	if gap >= 15:
		return "Very high"
	if gap >= 8:
		return "High"
	if gap >= 3:
		return "Moderate"
	return "Near peak"


func _confirm_new_career() -> void:
	if not Game.career_active:
		_start_new_career()
		return
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = "Start a new My Player career?\nYour current one will be lost and your player resets to rookie stats."
	dlg.confirmed.connect(_start_new_career)
	add_child(dlg)
	dlg.popup_centered()


func _start_new_career() -> void:
	Game.start_career(_difficulty, UI.team_pack())
	Game.goto(Game.CAREER_SCENE)


func _confirm_delete() -> void:
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = "Delete your player?\nThis also ends your My Player career."
	dlg.confirmed.connect(func() -> void:
		Game.delete_my_player()
		get_tree().reload_current_scene())
	add_child(dlg)
	dlg.popup_centered()


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
