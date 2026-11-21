extends Node
## Renders the in-match HUD (buy phase, live, scoreboard). Run:
##   godot --path . res://tests/hud_shots.tscn -- --test --windowed --out=<dir>


func _ready() -> void:
	var out := "user://hud"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	if "--windowed" in OS.get_cmdline_user_args():
		get_window().size = Vector2i(1600, 900)
	if "--spectate" in OS.get_cmdline_user_args():
		Game.prepare_spectate_match()
		Game.pending_match.map = "Dustline"
		var sm: Node = load(Game.MATCH_SCENE).instantiate()
		add_child(sm)
		for i in 60 * 34:
			await get_tree().physics_frame
		sm.camera.zoom = Vector2(1.1, 1.1)
		await _wait(10)
		get_viewport().get_texture().get_image().save_png(out + "/spectate.png")
		get_tree().quit()
		return
	Game.prepare_quick_match("Dustline")
	Game.pending_match.mode = "test"
	var m: Node = load(Game.MATCH_SCENE).instantiate()
	add_child(m)
	await _wait(40)
	get_viewport().get_texture().get_image().save_png(out + "/hud_buy.png")
	m.buy_menu_open = false
	Game.autoplay = true
	for i in 60 * 22:
		await get_tree().physics_frame
	get_viewport().get_texture().get_image().save_png(out + "/hud_live.png")
	Input.action_press("scoreboard")
	await _wait(30)
	get_viewport().get_texture().get_image().save_png(out + "/hud_board.png")
	Input.action_release("scoreboard")
	get_tree().quit()


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
