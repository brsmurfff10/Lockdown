extends Node
## Screenshot: the TAB scoreboard with titles.   godot --path . res://tests/titles_shot.tscn -- --test --out=<dir>
func _ready() -> void:
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	get_window().size = Vector2i(1600, 900)
	Game.prepare_quick_match("Dustline")
	Game.pending_match.mode = "test"
	var i := 0
	for t: TeamData in Game.pending_match.teams:
		for p: PlayerData in t.roster:
			if p.is_user:
				p.title = "Premier League MVP (Season 2)"
			elif i % 3 == 0:
				p.add_honour(["Premier Cup Champion", "Challenger Cup Finalist", "Player of the Year"][i % 3 if i % 2 == 0 else 1], 1, 50)
			i += 1
	var m: Node = load(Game.MATCH_SCENE).instantiate()
	add_child(m)
	m.buy_menu_open = false
	await get_tree().create_timer(1.0).timeout
	Input.action_press("scoreboard")
	await get_tree().create_timer(0.3).timeout
	get_viewport().get_texture().get_image().save_png(out + "/titles_scoreboard.png")
	get_tree().quit()
