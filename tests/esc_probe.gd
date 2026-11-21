extends Node
## Repro: press Esc (sim rest) during a watched manager match.


func _ready() -> void:
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	get_window().size = Vector2i(1600, 900)
	var w := Game.new_manager_world()
	Game.start_manager_career(w, w.team_index(w.league_teams(3)[0]), "Esc Test", "ESC", Color.CYAN)
	Game.prepare_manager_match()
	var m: Node = load(Game.MATCH_SCENE).instantiate()
	add_child(m)
	for i in 60 * 13:
		await get_tree().physics_frame
	print("before: phase=%d live=%s score=%s" % [m.phase, m.is_live(), m.score])
	Input.action_press("quit")
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_release("quit")
	for i in 30:
		await get_tree().process_frame
	print("after: phase=%d (MATCH_OVER=%d) score=%s banner='%s' visible=%s" % [m.phase, m.Phase.MATCH_OVER, m.score, m.hud._banner.text, m.hud._banner_band.visible])
	if out != "":
		get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
