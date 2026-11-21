extends Node
## Batch-9 systems: difficulty presets, staff, facilities, academy, scouting
## fog, board / sacking / job moves, contract clauses, chemistry, season
## reviews, records, Hall of Fame, achievements; My Player lifestyle,
## streaming, relationships, traits, the World Cup and coaching after retiring.
## With --out=<dir>: screenshots of the new pages and popups.
## Run:  godot --path . res://tests/club_probe.tscn -- --test [--windowed] [--out=<dir>]

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
	if "--windowed" in OS.get_cmdline_user_args():
		get_window().size = Vector2i(1600, 900)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.ACHIEVEMENTS_PATH))
	Game.achievements = {}

	# --- Difficulty presets.
	var nw := Game.new_manager_world()
	nw.set_difficulty("Hardcore")
	Game.start_manager_career(nw, nw.team_index(nw.league_teams(3)[2]), "Club Probe", "CLP", Color.ORANGE)
	var w := Game.world
	var ut := w.user_team()
	_check(w.difficulty == "Hardcore" and w.diff("injury") > 1.0 and PlayerData.refuse_mult > 1.0, "Hardcore preset applied")
	var inc_hard := w.league_revenue()
	w.set_difficulty("Casual")
	_check(w.league_revenue() > inc_hard, "Casual pays more league revenue (%d > %d)" % [w.league_revenue(), inc_hard])
	w.set_difficulty("Normal")
	_check(not w.board.is_empty() and w.staff_market.size() == 6, "board objective (%s) and a staff market" % w.board.get("text", "?"))

	# --- Staff.
	w.money = 5000000
	var hired := 0
	for role: String in World.STAFF_ROLES:
		for i in w.staff_market.size():
			if String(w.staff_market[i].role) == role:
				if w.hire_staff(i) == "":
					hired += 1
				break
	_check(hired == 4 and w.staff_wages() > 0, "hired all four roles (wages %s/wk)" % UI.money_text(w.staff_wages()))
	_check(w.payroll() > w.staff_wages(), "staff wages are in the payroll")
	_check(w.fire_staff("Analyst") == "" and not w.staff.has("Analyst"), "fire the analyst")

	# --- Facilities tree.
	_check(w.upgrade_fac("Bootcamp") != "", "Bootcamp blocked without a Gaming House")
	_check(w.upgrade_fac("Gaming House") == "" and w.upgrade_fac("Bootcamp") == "", "Gaming House then Bootcamp")
	_check(w.upgrade_fac("Youth Academy") != "", "academy needs Training Center L2")
	w.upgrade_fac("Training Center")
	_check(w.upgrade_fac("Youth Academy") == "" and w.academy.size() >= 2, "academy built: %d prospects" % w.academy.size())
	_check(w.facility_upkeep() > 0, "facility upkeep %s/wk" % UI.money_text(w.facility_upkeep()))

	# --- Academy.
	var pr: PlayerData = w.academy[0]
	var r0 := pr.rating_exact()
	for i in 10:
		w._academy_week()
	_check(pr.rating_exact() > r0, "prospects grow (%.1f -> %.1f)" % [r0, pr.rating_exact()])
	while ut.roster.size() >= World.MAX_ROSTER:
		w.release_player(ut.roster[ut.roster.size() - 1])
	_check(w.promote_academy(pr) == "" and ut.roster.has(pr) and Game.achievements.has("homegrown"), "promote a prospect (achievement)")
	if not w.academy.is_empty():
		var sp: PlayerData = w.academy[0]
		var m0 := w.money
		_check(w.sell_academy(sp) == "" and w.money > m0, "sell a prospect")

	# --- Scouting fog.
	var target: PlayerData = w.market_players()[40]
	_check(not w.known(target), "other clubs' players are unknown")
	var diffs := 0.0
	for k: String in PlayerData.STAT_KEYS:
		diffs += absf(w.est_stat(target, k) - target.stat(k))
	_check(diffs > 0.5, "estimates differ from the truth (total off %.1f)" % diffs)
	_check(w.queue_scout(target) == "" and w.queue_scout(target) != "", "queue a scout (no duplicates)")
	w._scout_week()
	_check(w.known(target) and is_equal_approx(w.est_rating(target), target.rating_exact()), "scouted: exact ratings")

	# --- Contract clauses.
	w.week = 2
	var fa: PlayerData = w.free_agents[3]
	var terms := w.contract_terms(fa, 1.2, true, true)
	_check(int(terms.wage) < PlayerData.salary_for_rating(fa.rating_exact()) and int(terms.release) > 0 and int(terms.appearance) > 0, "clauses lower the wage (%s vs %s)" % [terms.wage, PlayerData.salary_for_rating(fa.rating_exact())])
	while ut.roster.size() >= World.MAX_ROSTER:
		w.release_player(ut.roster[ut.roster.size() - 1])
	var serr := w.sign_free_agent(fa, terms)
	_check(serr == "" and fa.release_clause > 0 and fa.appearance_fee > 0, "signed with clauses %s" % serr)
	fa.release_clause = 1000 # Cheap: someone will pay it.
	var gone := false
	for i in 300:
		w._release_clauses()
		if not ut.roster.has(fa):
			gone = true
			break
	_check(gone and Game.achievements.has("fine_print"), "release clause triggered")
	var e0 := ut.roster[0]
	_check(w.extend_contract(e0, w.contract_terms(e0, 0.0, true, false)) == "" and e0.loyalty_bonus > 0, "extension with a loyalty bonus")

	# --- Chemistry.
	var c0 := w.chemistry(ut)
	for p in ut.roster:
		p.joined = w.stamp()
	_check(w.chemistry(ut) < c0, "new signings lower chemistry (%d -> %d)" % [int(c0), int(w.chemistry(ut))])

	# --- Board: sacking and a new job.
	w.board.confidence = 5.0
	w.week = 8
	w._board_week()
	_check(w.sacked and w.job_offers.size() >= 1, "sacked with %d job offers" % w.job_offers.size())
	_check(w.advance_week() == "sacked", "can't advance while sacked")
	var dest: TeamData = w.teams[int(w.job_offers[0].team)]
	var old := w.user_team()
	_check(w.accept_job(0) == "" and w.user_team() == dest and not old.is_user_team and not w.sacked, "took the job at %s" % dest.team_name)
	_check(w.staff.size() == 3 and w.academy.is_empty() and w.board.confidence == 60.0, "staff followed; academy stayed behind")

	# --- A full season for reviews, records and history.
	w.week = 1
	w._begin_week()
	for i in 26:
		var r := w.advance_week()
		if r == "play_match":
			if w.sim_user_match().is_empty():
				w.forfeit_user_match()
			r = w.advance_week()
		if r == "sacked":
			w.accept_job(0)
	_check(w.reviews.size() >= 1 and w.review_pending, "season review written (S%d)" % (int(w.reviews[0].s) if not w.reviews.is_empty() else -1))
	_check(not w.records.is_empty() and w.records.has("Most kills in a match"), "records: %s" % ", ".join(w.records.keys()))
	_check(w.champions.size() >= 4, "champions recorded (%d)" % w.champions.size())
	print("  hall of fame: %d, last review awards: %s" % [w.hall_of_fame.size(), w.reviews[-1].awards if not w.reviews.is_empty() else []])
	_check(Game.achievements.has("sacked") and Game.achievements.has("dream_team") == false, "achievements: %s" % ", ".join(Game.achievements.keys()))

	# --- Save/load keeps the new state.
	Game.save_world()
	Game.load_world()
	var w2 := Game.world
	_check(w2.staff.size() == w.staff.size() and w2.reviews.size() == w.reviews.size() and w2.records.size() == w.records.size() and w2.difficulty == w.difficulty, "manager state survives save/load")
	w = w2

	if out != "":
		var hub: Node = load(Game.MANAGER_SCENE).instantiate()
		add_child(hub)
		await _shot(out + "/b9_review.png")
		_close_all(hub)
		w.review_pending = false
		hub._show("Club")
		await _shot(out + "/b9_club.png")
		for tab in HistoryView.TABS:
			hub._hist_tab = tab
			hub._show("History")
			await _shot(out + "/b9_hist_%s.png" % tab.replace(" ", "_").to_lower())
		hub._show("Transfers")
		hub._portal_view = "Other clubs"
		hub._show("Transfers")
		await _shot(out + "/b9_fog.png")
		hub._scout(w.market_players()[12])
		await _shot(out + "/b9_scout.png")
		hub._close_scout()
		hub._contract_dialog(w.free_agents[0], "sign")
		await _shot(out + "/b9_contract.png")
		_close_all(hub)
		hub.queue_free()
		await _shot(out + "/_blank.png")

	# --- My Player extras.
	Game.end_career()
	Game.create_my_player("Extras", "AWPer", "Brazil")
	Game.start_career("Casual")
	var pw := Game.pworld
	var me := pw.user_player
	_check(me.nation == "Brazil" and pw.difficulty == "Casual", "nation and difficulty set")
	pw.wallet = 2000000
	_check(pw.buy_asset("house") == "" and pw.buy_asset("chef") == "" and pw.buy_asset("studio") == "" and pw.lifestyle_upkeep() > 0, "bought lifestyle assets")
	_check(pw.sell_asset("chef") != "" and pw.sell_asset("studio") == "", "chef can't be resold; studio can")
	pw.buy_asset("studio")
	pw.fame = 20000
	pw.set_stream("Heavy")
	var wl0 := pw.wallet
	pw._lifestyle_week()
	_check(pw.stream_income() > 0 and pw.fatigue > 0.0, "heavy streaming pays %s/wk, fatigue %d" % [UI.money_text(pw.stream_income()), int(pw.fatigue)])
	pw.fatigue = 90.0
	me.form = 0.0
	pw._lifestyle_week()
	_check(me.form < 0.0, "high fatigue hurts form (%.1f)" % me.form)
	pw.set_stream("Off")
	var mate: PlayerData = pw.user_team().roster.filter(func(x: PlayerData) -> bool: return not x.is_user)[0]
	pw._relate(mate.uid, 60.0)
	_check(World.relation_text(pw.relation(mate.uid)) == "Close friend", "relationships: %s is a close friend" % mate.player_name)
	var dm := {}
	for i in 400:
		pw._relationship_events()
		for m in pw.inbox:
			if not bool(m.done) and String(m.kind) == "dressing":
				dm = m
		if not dm.is_empty():
			break
	_check(not dm.is_empty(), "dressing room event: %s" % dm.get("title", "-"))
	if not dm.is_empty():
		pw.resolve_msg(dm, 0)
		_check(bool(dm.done), "event resolved: %s" % dm.result)
	pw.highlights = 9
	pw.note_highlights({me: 2})
	_check(pw.traits.has("clutch") and Game.achievements.has("highlight_reel"), "Clutch Minister trait from highlights")
	var wc := pw._world_cup()
	_check(not wc.is_empty() and String(wc.winner) != "" and pw.champions.any(func(c: Dictionary) -> bool: return String(c.name) == "World Cup"), "World Cup: %s won (you: %s)" % [wc.get("winner", "?"), wc.get("you", "-")])
	if out != "":
		var ph: Node = load(Game.CAREER_SCENE).instantiate()
		add_child(ph)
		for pg in ["Career", "Training", "Team", "Profile"]:
			ph._show(pg)
			await _shot(out + "/b9_mp_%s.png" % pg.to_lower())
		ph.queue_free()
		await _shot(out + "/_blank.png")
	# Retire and coach.
	me.age = 31
	pw.retire()
	Game.coach_from_player()
	_check(Game.world != null and Game.world.mode == "manager" and not Game.world.user_team().roster.any(func(p: PlayerData) -> bool: return p.is_user), "coaching your old club: %s" % Game.world.user_team().team_name)
	_check(Game.achievements.has("coach"), "From Player to Coach unlocked")
	if out != "":
		var mm: Node = load(Game.MENU_SCENE).instantiate()
		add_child(mm)
		await _shot(out + "/_blank.png")
		mm._show_achievements()
		await _shot(out + "/b9_achievements.png")
		mm.queue_free()
	Game.end_career()
	print("club_probe: %d failure(s)" % fails)
	get_tree().quit()


func _close_all(hub: Node) -> void:
	for c in hub.get_children():
		if c is ColorRect:
			c.queue_free()


func _shot(path: String) -> void:
	for f in 8:
		await get_tree().process_frame
	if not path.ends_with("_blank.png"):
		get_viewport().get_texture().get_image().save_png(path)
