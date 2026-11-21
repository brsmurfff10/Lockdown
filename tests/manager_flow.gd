extends Node
## Manager career flow: new career -> enroll -> advance -> watch match (in the
## real match scene) -> sim the rest -> result recorded -> hub tabs render.
## Run:  godot --path . res://tests/manager_flow.tscn -- --test --windowed --out=<dir>


func _ready() -> void:
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var nw := Game.new_manager_world()
	Game.start_manager_career(nw, Game.new_manager_world().teams.size() - 1, "Flow Org", "FLO", Color.CYAN)
	var w := Game.world
	var guard := 0
	while w.user_match_this_week().is_empty() and guard < 10:
		w.advance_week()
		guard += 1
	print("Week %d, user match ready: %s" % [w.week, not w.user_match_this_week().is_empty()])
	# Watch it in the real match scene, then skip ahead like pressing Esc.
	var ok := Game.prepare_manager_match()
	var m: Node = load(Game.MATCH_SCENE).instantiate()
	add_child(m)
	while not m.is_live():
		await get_tree().physics_frame
	for i in 60 * 6:
		await get_tree().physics_frame
	if out != "":
		get_viewport().get_texture().get_image().save_png(out + "/manager_match.png")
	var before := w.user_match_this_week()
	m._sim_rest_of_match()
	var kills := 0
	for p in m.stats:
		kills += m.stats[p].kills
	print("Match (%s): %d-%d, %d kills tracked, mode=%s" % [ok, m.score[0], m.score[1], kills, m.mode])
	# The match records its own result when it ends (results screen shows the changes).
	var rep: Dictionary = w.last_report
	print("Result recorded: %s (report %s, %d player changes)" % [w.user_match_this_week().is_empty() and not before.is_empty(), rep.get("score", []), rep.get("player_changes", {}).size()])
	print("Recorded once: %s" % m._recorded) # _leave_match skips recording when set.
	m.queue_free()
	Engine.time_scale = 1.0
	await get_tree().process_frame
	print("Advance after match: '%s' -> week %d" % [w.advance_week(), w.week])
	for n in w.news.slice(w.news.size() - 4):
		print("  ", n)
	# Hub tabs.
	var hub: Node = load(Game.MANAGER_SCENE).instantiate()
	add_child(hub)
	for page in hub.PAGES:
		hub._show(page)
		for f in 6:
			await get_tree().process_frame
		if out != "":
			get_viewport().get_texture().get_image().save_png("%s/hub_%s.png" % [out, page.to_lower()])
	print("Hub rendered %d pages" % hub.PAGES.size())
	get_tree().quit()
