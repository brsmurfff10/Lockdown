extends Node
## Checks interface sounds fire for hover / click / confirm / back / toggle. Run:
##   godot --path . res://tests/ui_sound_probe.tscn -- --test --windowed

var fails := 0


func _ready() -> void:
	var s: UiSounds = Game.ui_sounds
	var root := Control.new()
	UI.setup_screen(root)
	add_child(root)
	var box := UI.vbox()
	root.add_child(box)
	var plain := UI.button("Train", func() -> void: pass)
	var primary := UI.button("Advance Week", func() -> void: pass, 200, "PrimaryButton")
	var back := UI.button("Back", func() -> void: pass, 200, "GhostButton")
	var check := CheckBox.new()
	var item := UI.menu_item("Quick Match", "sub", func() -> void: pass)
	for c in [plain, primary, back, check, item]:
		box.add_child(c)
	await get_tree().process_frame
	_check("click", s._kind(plain) == "click")
	_check("confirm", s._kind(primary) == "confirm")
	_check("back", s._kind(back) == "back")
	_check("toggle", s._kind(check) == "toggle")
	plain.pressed.emit()
	await get_tree().process_frame
	var busy := 0
	for p: AudioStreamPlayer in s._players:
		if p.playing:
			busy += 1
	_check("a sound is playing after a click (%d)" % busy, busy >= 1)
	_check("UI bus exists", AudioServer.get_bus_index("UI") >= 0)
	print("UI SOUNDS: %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit()


func _check(what: String, ok: bool) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		fails += 1
