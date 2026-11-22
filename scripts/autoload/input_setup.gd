class_name InputSetup
extends RefCounted
## Registers input actions in code so project.godot stays readable.


static func ensure() -> void:
	_key("move_up", KEY_W)
	_key("move_up", KEY_UP)
	_key("move_down", KEY_S)
	_key("move_down", KEY_DOWN)
	_key("move_left", KEY_A)
	_key("move_left", KEY_LEFT)
	_key("move_right", KEY_D)
	_key("move_right", KEY_RIGHT)
	_key("reload", KEY_R)
	_key("scoreboard", KEY_TAB)
	_key("weapon_1", KEY_1)
	_key("weapon_2", KEY_2)
	_key("weapon_3", KEY_3)
	_key("swap_weapon", KEY_Q)
	_key("grenade", KEY_4)
	_key("use", KEY_E)
	_key("buy_menu", KEY_B)
	_key("pickup", KEY_F)
	_key("drop", KEY_G)
	_key("request_bomb", KEY_Y)
	_key("freecam", KEY_SPACE)
	_key("confirm", KEY_ENTER)
	_key("confirm", KEY_KP_ENTER)
	_key("quit", KEY_ESCAPE)
	_key("toggle_fullscreen", KEY_F11)
	_mouse("shoot", MOUSE_BUTTON_LEFT)
	_key("walk", KEY_SHIFT) # Hold: half speed, silent footsteps.
	_key("speed_up", KEY_EQUAL)
	_key("speed_up", KEY_KP_ADD)
	_key("slow_down", KEY_MINUS)
	_key("slow_down", KEY_KP_SUBTRACT)
	_mouse("free_look", MOUSE_BUTTON_RIGHT)


static func _key(action: StringName, keycode: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	_add(action, ev)


static func _mouse(action: StringName, button: MouseButton) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	_add(action, ev)


static func _add(action: StringName, ev: InputEvent) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	if not InputMap.action_has_event(action, ev):
		InputMap.action_add_event(action, ev)
