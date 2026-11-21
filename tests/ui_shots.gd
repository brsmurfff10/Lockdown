extends Node
## Renders menu screens to PNGs for design review. Run:
##   godot --path . res://tests/ui_shots.tscn -- --test --windowed --out=<dir> [--only=a,b]


func _ready() -> void:
	var out := "user://ui"
	var only: PackedStringArray = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		if a.begins_with("--only="):
			only = a.substr(7).split(",")
	DirAccess.make_dir_recursive_absolute(out)
	if "--windowed" in OS.get_cmdline_user_args():
		get_window().size = Vector2i(1600, 900)
	if Game.my_player == null:
		Game.create_my_player("Phantom", "Rifler")
	if not Game.career_active:
		Game.start_career()
		for i in 3:
			if Game.pworld.advance_week() == "play_match":
				Game.pworld.sim_user_match()
				Game.pworld.advance_week()
	if Game.world == null:
		var w := Game.new_manager_world()
		Game.start_manager_career(w, w.league_teams(3)[0].get_instance_id() * 0 + w.team_index(w.league_teams(3)[0]), "Midnight Esports", "MID", Color.html("4dd2ff"))
		for i in 2:
			if Game.world.advance_week() == "play_match":
				Game.world.sim_user_match()
				Game.world.advance_week()
	var screens := ["main_menu", "my_player", "player_hub", "manager_setup", "settings"]
	for s in screens:
		if not only.is_empty() and not only.has(s):
			continue
		var n: Node = load("res://scenes/%s.tscn" % s).instantiate()
		add_child(n)
		await _wait(12)
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, s])
		n.queue_free()
		await _wait(2)
	if only.is_empty() or only.has("extras"):
		# Org setup with a squad dropdown open.
		var setup: Node = load("res://scenes/manager_setup.tscn").instantiate()
		add_child(setup)
		await _wait(10)
		_press(setup, "Squad")
		await _wait(8)
		get_viewport().get_texture().get_image().save_png("%s/setup_squad.png" % out)
		setup.queue_free()
		await _wait(2)
		# My Player: an offer, viewed.
		var w: World = Game.pworld
		var other := w.league_teams(maxi(0, w.user_team().league - 1))[0]
		w.offers = [{"team": w.team_index(other), "note": "%s want you after your form (1.12)." % other.team_name, "wage": 1800, "years": 2}]
		var ph: Node = load(Game.CAREER_SCENE).instantiate()
		add_child(ph)
		await _wait(10)
		ph._view_team(w.standings(w.user_team().league)[0])
		await _wait(8)
		get_viewport().get_texture().get_image().save_png("%s/player_league_team.png" % out)
		for c in ph.get_children():
			if c is ColorRect:
				c.queue_free()
		await _wait(2)
		ph._view_offer(0)
		await _wait(8)
		get_viewport().get_texture().get_image().save_png("%s/player_offer.png" % out)
		ph.queue_free()
		await _wait(2)
		# Manager: Simulate -> results screen.
		var mh: Node = load(Game.MANAGER_SCENE).instantiate()
		add_child(mh)
		await _wait(10)
		if Game.world.user_match_this_week().is_empty():
			Game.world.advance_week()
			mh._refresh()
			await _wait(6)
		_press(mh, "Simulate")
		await _wait(10)
		get_viewport().get_texture().get_image().save_png("%s/sim_results.png" % out)
		mh.queue_free()
		await _wait(2)
	if only.is_empty() or only.has("manager_hub"):
		var hub: Node = load(Game.MANAGER_SCENE).instantiate()
		add_child(hub)
		await _wait(12)
		for page in hub.PAGES:
			hub._show(page)
			await _wait(8)
			get_viewport().get_texture().get_image().save_png("%s/hub_%s.png" % [out, page.to_lower()])
		# Transfers extras: other clubs sorted by aim, and the scouting card.
		hub._page = "Transfers"
		hub._portal_view = "Other clubs"
		hub._f_min_rtg = 55
		hub._on_sort("aim")
		await _wait(8)
		get_viewport().get_texture().get_image().save_png("%s/hub_transfers_sorted.png" % out)
		hub._scout(hub.w.market_players()[3])
		await _wait(8)
		get_viewport().get_texture().get_image().save_png("%s/hub_scout.png" % out)
	get_tree().quit()


func _press(root: Node, prefix: String) -> bool:
	for c in root.find_children("*", "Button", true, false):
		if (c as Button).text.begins_with(prefix):
			(c as Button).pressed.emit()
			return true
	print("  no button '%s'" % prefix)
	return false


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
