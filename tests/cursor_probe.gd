extends Node
## Dev probe: human-controlled match, check cursor/crosshair state after buy phase.


func _ready() -> void:
	Game.autoplay = false
	Game.prepare_quick_match()
	Game.pending_match.mode = "test"
	var m: Node = load(Game.MATCH_SCENE).instantiate()
	add_child(m)
	for i in 60 * 3:
		await get_tree().physics_frame
	print("BUY phase: mouse_mode=%d crosshair.visible=%s buy_menu_open=%s" % [Input.mouse_mode, m.crosshair.visible, m.buy_menu_open])
	for i in 60 * 9:
		await get_tree().physics_frame
	print("LIVE phase=%d: mouse_mode=%d crosshair.visible=%s user_alive=%s buy_menu_open=%s" % [m.phase, Input.mouse_mode, m.crosshair.visible, m.user_unit.alive, m.buy_menu_open])
	get_tree().quit()
