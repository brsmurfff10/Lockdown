extends Node
## Screenshots of an OG Teams My Player world. Run: godot --path . res://tests/og_shot.tscn -- --test --out=<dir>
func _ready() -> void:
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	get_window().size = Vector2i(1280, 720)
	Game.end_career()
	Game.create_my_player("OGcheck", "AWPer", "Sweden")
	Game.start_career("Normal", "og")
	var ph: Node = load(Game.CAREER_SCENE).instantiate()
	add_child(ph)
	for c in ph.get_children():
		if c is ColorRect:
			c.queue_free()
	ph._show("League")
	await _f()
	for b in _all(ph):
		if b is Button and (b as Button).text == "Premier League":
			b.emit_signal("pressed")
	await _f()
	get_viewport().get_texture().get_image().save_png(out + "/og_league.png")
	ph._view_team(Game.pworld.league_teams(0)[0])
	await _f()
	get_viewport().get_texture().get_image().save_png(out + "/og_team.png")
	ph.queue_free()
	var mp: Node = load(Game.MY_PLAYER_SCENE).instantiate()
	add_child(mp)
	await _f()
	get_viewport().get_texture().get_image().save_png(out + "/og_myplayer.png")
	Game.end_career()
	get_tree().quit()
func _all(n: Node) -> Array:
	var r: Array = [n]
	for c in n.get_children():
		r.append_array(_all(c))
	return r
func _f() -> void:
	for i in 8:
		await get_tree().process_frame
