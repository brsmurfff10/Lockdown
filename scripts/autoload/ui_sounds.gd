class_name UiSounds
extends Node
## Interface sounds for every button, checkbox, dropdown and slider in the game.
## Hooks controls as they enter the tree, so screens don't wire anything up.
## A control can opt out or pick its sound with set_meta("ui_sound", name):
## "none", "click", "confirm", "back", "tab", "toggle".

const STREAMS := {
	"hover": preload("res://audio/ui_hover.wav"),
	"click": preload("res://audio/ui_click.wav"),
	"confirm": preload("res://audio/ui_confirm.wav"),
	"back": preload("res://audio/ui_back.wav"),
	"tab": preload("res://audio/ui_tab.wav"),
	"toggle": preload("res://audio/ui_toggle.wav"),
	"tick": preload("res://audio/ui_tick.wav"),
	"error": preload("res://audio/ui_error.wav"),
	"buy": preload("res://audio/ui_buy.wav"),
}
const VOLUME_DB := {"hover": -14.0, "tick": -12.0, "click": -6.0, "toggle": -6.0, "tab": -6.0, "back": -6.0, "confirm": -5.0, "error": -6.0, "buy": -4.0}
const BACK_WORDS := ["back", "main menu", "cancel", "close", "decline", "quit", "resume"]
const MIN_GAP := {"hover": 0.035, "tick": 0.045} ## Seconds between repeats.

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _last := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 6:
		var p := AudioStreamPlayer.new()
		p.bus = "UI"
		add_child(p)
		_players.append(p)
	get_tree().node_added.connect(_on_node_added)


func play(name: String) -> void:
	if not STREAMS.has(name):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last.get(name, -10.0)) < float(MIN_GAP.get(name, 0.02)):
		return
	_last[name] = now
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = STREAMS[name]
	p.volume_db = VOLUME_DB.get(name, -6.0)
	p.pitch_scale = randf_range(0.97, 1.03) if name in ["hover", "click", "tick"] else 1.0
	p.play()


func _on_node_added(n: Node) -> void:
	if n is BaseButton:
		var b := n as BaseButton
		b.mouse_entered.connect(_on_hover.bind(b))
		b.pressed.connect(_on_pressed.bind(b))
		b.gui_input.connect(_on_button_input.bind(b))
		if b is CheckBox or b is CheckButton:
			# Code-drawn tick icons: keep them smooth when the UI is scaled.
			b.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		if b is OptionButton:
			(b as OptionButton).item_selected.connect(func(_i: int) -> void: play("click"))
	elif n is Slider:
		var s := n as Slider
		s.value_changed.connect(func(_v: float) -> void:
			if s.has_focus() or s.get_global_rect().has_point(s.get_global_mouse_position()):
				play("tick"))
		s.mouse_entered.connect(func() -> void: play("hover"))
	elif n is PopupMenu:
		(n as PopupMenu).id_focused.connect(func(_i: int) -> void: play("hover"))


func _kind(b: BaseButton) -> String:
	if b.has_meta("ui_sound"):
		return String(b.get_meta("ui_sound"))
	if b is CheckBox or b is CheckButton:
		return "toggle"
	if b is OptionButton or b is MenuButton:
		return "click"
	var variation := String(b.theme_type_variation)
	if variation == "NavButton":
		return "tab"
	if b is Button:
		var text := (b as Button).text.strip_edges().to_lower()
		for w in BACK_WORDS:
			if text.begins_with(w):
				return "back"
	if variation == "PrimaryButton":
		return "confirm"
	return "click"


func _on_hover(b: BaseButton) -> void:
	if b.disabled or _kind(b) == "none" and not b.has_meta("ui_hover"):
		return
	play("hover")


func _on_pressed(b: BaseButton) -> void:
	var k := _kind(b)
	if k != "none":
		play(k)


## Clicking a disabled button: a short "can't do that" buzz.
func _on_button_input(event: InputEvent, b: BaseButton) -> void:
	if b.disabled and String(b.theme_type_variation) != "NavButton" and event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		play("error")
