extends Node
## Dev tool: renders each screen and saves PNGs. Pass an output dir:
##   godot --path . res://tests/screenshot_runner.tscn -- --test --out=C:/some/dir


func _ready() -> void:
	var out := "user://shots"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	if Game.my_player == null:
		Game.create_my_player("Phantom", "Rifler")
	if not Game.career_active:
		Game.start_career()
		Game.train("aim")
		for i in 3:
			if Game.pworld.advance_week() == "play_match":
				Game.pworld.sim_user_match()
				Game.pworld.advance_week()
	if Game.world == null:
		var w := Game.new_manager_world()
		Game.start_manager_career(w, w.teams.size() - 1, "Test Org", "TST", Color(0.3, 0.8, 1.0))
	for s in ["main_menu", "my_player", "player_hub", "manager_setup", "settings"]:
		var n: Node = load("res://scenes/%s.tscn" % s).instantiate()
		add_child(n)
		await _wait(10)
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, s])
		n.queue_free()
		await _wait(2)
	Game.prepare_quick_match()
	Game.pending_match.mode = "test"
	var m: Node = load(Game.MATCH_SCENE).instantiate()
	add_child(m)
	await _wait(60)
	get_viewport().get_texture().get_image().save_png("%s/match_buy.png" % out)
	m.buy_menu_open = false
	# Camera lead check: cursor at the right edge, normal then free look.
	var vp := get_viewport().get_visible_rect().size
	Input.warp_mouse(Vector2(20, vp.y / 2) if m.user_unit.side == 1 else Vector2(vp.x - 20, vp.y / 2))
	await _wait(40)
	get_viewport().get_texture().get_image().save_png("%s/match_lead.png" % out)
	Input.action_press("free_look")
	await _wait(40)
	get_viewport().get_texture().get_image().save_png("%s/match_freelook.png" % out)
	Input.action_release("free_look")
	Game.autoplay = true
	for i in 60 * 30:
		await get_tree().physics_frame
	get_viewport().get_texture().get_image().save_png("%s/match_live.png" % out)
	get_tree().quit()


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
