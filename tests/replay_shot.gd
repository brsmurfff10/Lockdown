extends Node
## Replay art: plays part of a live round, closes it into the replay, opens the
## round replay and screenshots it (soldiers, guns and bomb art like live play).
## Run: godot --path . res://tests/replay_shot.tscn -- --test --out=<dir>
func _ready() -> void:
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
	get_window().size = Vector2i(1600, 900)
	Game.prepare_quick_match("Dustline")
	Game.pending_match.mode = "test"
	var m: Node = load(Game.MATCH_SCENE).instantiate()
	add_child(m)
	Engine.time_scale = 3.0
	while m.phase != m.Phase.LIVE:
		await get_tree().process_frame
	m.buy_menu_open = false
	await get_tree().create_timer(30.0).timeout # ~10 s of live play at 3x.
	Engine.time_scale = 1.0
	m.replay.end_round(0, "test")
	m.replay.play_round(m.replay.rounds.size() - 1)
	await get_tree().process_frame
	m.replay._seek(7.0)
	m.replay.paused = true
	await get_tree().create_timer(0.6).timeout
	get_viewport().get_texture().get_image().save_png(out + "/replay.png")
	print("replay shot: active ", m.replay.active, " t ", m.replay.t)
	get_tree().quit()
