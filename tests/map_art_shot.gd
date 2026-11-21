extends Node
## Screenshots a quick match on a map with rendered art (player view and the
## spectator overview). Run: godot --path . res://tests/map_art_shot.tscn -- --test --out=<dir> [--map=Dustline]
func _ready() -> void:
	var out := ""
	var map := "Dustline"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		if a.begins_with("--map="): map = a.substr(6)
	get_window().size = Vector2i(1600, 900)
	Game.prepare_quick_match(map)
	Game.pending_match.mode = "test"
	var m: Node = load(Game.MATCH_SCENE).instantiate()
	add_child(m)
	m.buy_menu_open = false
	await _wait(float(OS.get_environment("SHOT_WAIT")) if OS.get_environment("SHOT_WAIT") != "" else 14.0)
	get_viewport().get_texture().get_image().save_png("%s/art_%s_player.png" % [out, map.to_lower()])
	print("art texture: ", m.arena.art_texture != null)
	get_tree().quit()
func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout
