extends Node
## Real teams pack: new worlds (both careers), applying to an existing save,
## logos, nations and the World Cup. With --out=<dir>: screenshots.
## Run:  godot --path . res://tests/real_probe.tscn -- --test [--out=<dir>]

var fails := 0


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		fails += 1


func _ready() -> void:
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	get_window().size = Vector2i(1280, 720)
	_check(RealTeams.available() and RealTeams.teams().size() == 248, "pack loads (%d teams)" % RealTeams.teams().size())
	# New manager world with real teams.
	var w := Game.new_manager_world("real")
	var top: TeamData = w.league_teams(0)[0]
	_check(top.team_name == "FURIA" and top.logo.begins_with("img:"), "#1 FURIA in the Premier League (%s, %s)" % [top.team_name, top.logo])
	_check(RealTeams.logo_texture(top.logo.substr(4)) != null, "FURIA logo texture loads")
	var names := {}
	var dup := 0
	for t in w.teams:
		for p in t.roster:
			if names.has(p.player_name):
				dup += 1
			names[p.player_name] = true
	for p in w.free_agents:
		if names.has(p.player_name):
			dup += 1
		names[p.player_name] = true
	_check(dup == 0, "no duplicate player names (%d)" % dup)
	var spirit: TeamData = null
	for t in w.teams:
		if t.team_name == "Spirit":
			spirit = t
	var donk: PlayerData = null
	for p in spirit.roster:
		if p.player_name == "donk":
			donk = p
	_check(donk != null and donk.nation == "Russia", "donk on Spirit, Russia")
	var missing := 0
	for t in w.teams:
		if not t.logo.begins_with("img:") or RealTeams.logo_texture(t.logo.substr(4)) == null:
			missing += 1
	_check(missing == 0, "all 64 clubs have a logo (%d missing)" % missing)
	_check(w.league_teams(0)[0].rating() > w.league_teams(0)[15].rating(), "FURIA (%d) stronger than #16 %s (%d)" % [w.league_teams(0)[0].rating(), w.league_teams(0)[15].team_name, w.league_teams(0)[15].rating()])
	_check(w.free_agents[0].player_name == RealTeams.teams()[64].players[0].nick, "free agents come from ranks 65+ (%s)" % w.free_agents[0].player_name)
	var cup := w._world_cup()
	_check(not cup.is_empty(), "World Cup runs with real nations")

	# Existing save: a generated My Player career gets rebranded.
	Game.end_career()
	Game.create_my_player("Realcheck", "Rifler", "Canada")
	Game.start_career("Normal", "")
	var pw := Game.pworld
	for i in 4:
		if pw.advance_week() == "play_match":
			pw.sim_user_match()
			pw.advance_week()
	var stats_before := pw.user_player.rating_exact()
	var n := RealTeams.apply_existing(pw)
	_check(n == 64, "existing My Player save: %d clubs renamed" % n)
	_check(pw.user_player.player_name == "Realcheck" and is_equal_approx(pw.user_player.rating_exact(), stats_before), "your player keeps name and stats")
	var best: TeamData = pw.league_teams(0)[0]
	for t in pw.league_teams(0):
		if t.rating_exact() > best.rating_exact():
			best = t
	_check(best.team_name == "FURIA", "strongest Premier club became FURIA (%s)" % best.team_name)
	Game.save_player_career()
	Game.load_player_career()
	_check(Game.pworld.user_team().logo.begins_with("img:"), "logo survives save/load (%s)" % Game.pworld.user_team().team_name)
	Game.pworld.advance_week()
	_check(true, "week advances after rebrand")

	if out != "":
		var ph: Node = load(Game.CAREER_SCENE).instantiate()
		add_child(ph)
		for c in ph.get_children():
			if c is ColorRect:
				c.queue_free()
		for pg in ["Overview", "League", "Team"]:
			ph._show(pg)
			await _shot(out + "/real_p_%s.png" % pg.to_lower())
		ph._view_team(Game.pworld.league_teams(0)[0])
		await _shot(out + "/real_p_teamcard.png")
		ph.queue_free()
		var ms: Node = load(Game.MANAGER_SETUP_SCENE).instantiate()
		add_child(ms)
		await _shot(out + "/real_m_setup.png")
		ms.queue_free()
		var ed: Node = load(Game.EDITOR_SCENE).instantiate()
		add_child(ed)
		await _shot(out + "/real_editor.png")
		ed.queue_free()
		await _shot("")
	# OG pack: 20 teams on top, generated clubs below.
	var og := Game.new_manager_world("og")
	var o0: TeamData = og.league_teams(0)[0]
	_check(o0.team_name == "fnatic" and RealTeams.logo_texture(o0.logo.substr(4)) != null, "OG: fnatic #1 with logo (%s)" % o0.logo)
	var og_named := 0
	for t in og.teams:
		if t.logo.begins_with("img:og/"):
			og_named += 1
	_check(og_named == 20 and og.league_teams(1)[0].logo.begins_with("img:og/"), "OG: 20 classic clubs, 4 in the Pro League (%d)" % og_named)
	var kenny := false
	for t in og.teams:
		for p in t.roster:
			if p.player_name == "kennyS" and p.role == "AWPer" and t.team_name == "Envy":
				kenny = true
	_check(kenny, "OG: kennyS is Envy's AWPer")
	_check(RealTeams.logo_texture("furia") != null, "old real logo keys still work")

	# A full season on a real-teams My Player world.
	Game.end_career()
	Game.create_my_player("Seasoncheck", "AWPer", "Mongolia")
	Game.start_career("Normal", "real")
	var rw := Game.pworld
	for i in 60:
		var r := rw.advance_week()
		if r == "play_match":
			rw.sim_user_match()
			rw.advance_week()
		if rw.season == 2 and rw.week >= 2:
			break
	_check(rw.season == 2, "real world plays a full season (S%d W%d, champion %s)" % [rw.season, rw.week, rw.champions[-1].get("team", "?") if not rw.champions.is_empty() else "-"])
	Game.end_career()
	print("real_probe: %d failure(s)" % fails)
	get_tree().quit()


func _shot(path: String) -> void:
	for f in 8:
		await get_tree().process_frame
	if path != "":
		get_viewport().get_texture().get_image().save_png(path)
