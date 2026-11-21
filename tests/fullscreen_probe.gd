extends Node
## Dev probe: window mode + visible world size after launch.


func _ready() -> void:
	for i in 30:
		await get_tree().process_frame
	print("window mode=%d (3=fullscreen)  window size=%s  screen=%s" % [DisplayServer.window_get_mode(), DisplayServer.window_get_size(), DisplayServer.screen_get_size()])
	Game.prepare_quick_match("Dustline")
	Game.pending_match.mode = "test"
	var m: Node = load(Game.MATCH_SCENE).instantiate()
	add_child(m)
	for i in 60:
		await get_tree().process_frame
	var vp := get_viewport().get_visible_rect().size
	print("visible world area: %.0f x %.0f px at zoom %.2f" % [vp.x / m.camera.zoom.x, vp.y / m.camera.zoom.y, m.camera.zoom.x])
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			get_viewport().get_texture().get_image().save_png(a.substr(6))
	get_tree().quit()
