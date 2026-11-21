extends Node
## Batch-10 systems: personalities, press conferences, derbies, fans/merch,
## loans, the affiliate, agents, the social feed, live watching (recording),
## stats hub, awards ceremony, team logos, save backups and restore, enemy
## health hiding. With --out=<dir>: screenshots of the new screens.
## Run:  godot --path . res://tests/b10_probe.tscn -- --test [--windowed] [--out=<dir>]

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
		get_window().size = Vector2i(1280, 720)
	var nw := Game.new_manager_world()
	Game.start_manager_career(nw, nw.team_index(nw.league_teams(3)[2]), "Batch Ten", "BTN", Color.ORANGE)
	var w := Game.world
	var ut := w.user_team()
	w.money = 5000000

	# --- Personalities.
	var counts := {}
	for t in w.teams:
		for p in t.roster:
			var pe := PlayerData.persona_of(p)
			counts[pe] = int(counts.get(pe, 0)) + 1
	_check(counts.size() == 6 and int(counts.get("", 0)) > 200, "personalities spread: %s" % counts)

	# --- Derbies.
	var rv := w.derby_rival(ut)
	_check(rv != null and w.derby_rival(rv) == ut, "derby rivals pair up (%s)" % (rv.team_name if rv else "-"))

	# --- Fans and merch.
	_check(w.club_fans > 0 and w.merch_income() > 0, "club fans %d, merch %s/wk" % [w.club_fans, UI.money_text(w.merch_income())])
	var m0 := w.merch_income()
	_check(w.upgrade_merch() == "" and w.merch_income() > m0, "merch upgrade raises income")

	# --- Press conference before a big match.
	var pm := {}
	for i in 30:
		for m in w.inbox:
			if String(m.kind) == "press" and not bool(m.done):
				pm = m
		if not pm.is_empty():
			break
		if w.advance_week() == "play_match":
			w.sim_user_match()
	_check(not pm.is_empty(), "press conference message (%s)" % pm.get("title", "none"))
	if not pm.is_empty():
		w.resolve_msg(pm, 1)
		_check(not w.press_pledge.is_empty(), "promised a win: pledge recorded")

	# --- Loans.
	w.week = 2
	var lp: PlayerData = ut.roster[ut.roster.size() - 1]
	_check(w.loan_out(lp) == "" and not ut.roster.has(lp) and lp.loan_from == "user", "loaned out %s" % lp.player_name)
	var target: PlayerData = null
	for t in w.teams:
		if t != ut and t.roster.size() >= 7 and t.league == ut.league and t.roster[t.roster.size() - 1].refuses(ut) == "" and t.roster[t.roster.size() - 1].loan_from == "":
			target = t.roster[t.roster.size() - 1]
			break
	var lin := w.loan_in(target)
	_check(lin == "" and ut.roster.has(target) and target.loan_fee > 0, "loaned in %s (%s)" % [target.player_name, lin])
	var pay0 := w.payroll()
	_check(pay0 > 0, "payroll counts loan fee")
	w._return_loans()
	_check(ut.roster.has(lp) and not ut.roster.has(target) and lp.loan_from == "" and target.loan_from == "", "season end: loans go home")

	# --- Affiliate (must be a lower league: move the test club up one by swapping with a Challenger team).
	if ut.league == World.LEAGUES.size() - 1:
		var up: TeamData = w.league_teams(ut.league - 1)[0]
		up.league = ut.league
		ut.league -= 1
	var cands := w.affiliate_candidates()
	_check(not cands.is_empty() and w.buy_affiliate(cands[0]) == "" and w.affiliate() == cands[0], "bought affiliate %s" % (cands[0].team_name if not cands.is_empty() else "-"))
	var sd: PlayerData = ut.roster[ut.roster.size() - 1]
	_check(w.send_down(sd) == "" and w.affiliate().roster.has(sd), "sent %s down" % sd.player_name)
	_check(w.call_up(sd) == "" and ut.roster.has(sd), "called %s back up" % sd.player_name)
	_check(w.affiliate_income() > 0, "affiliate income %s/wk" % UI.money_text(w.affiliate_income()))

	# --- Live watching records a result.
	w.week = 1
	w._begin_week()
	var mt: Dictionary = {}
	for x in w.all_week_matches():
		if int(x.a) != w.user_team_idx and int(x.b) != w.user_team_idx:
			mt = x
			break
	var a := int(mt.a)
	var b := int(mt.b)
	var stats := {}
	for p in w.teams[a].starters(5) + w.teams[b].starters(5):
		stats[p] = {"kills": 5, "deaths": 4, "damage": 600.0, "objectives": 0}
	w.record_watched_match(a, b, [6, 3], 9, stats)
	_check(int(mt.winner) == a and int(mt.sa) == 6, "watched match recorded 6-3")

	# --- Ceremony data.
	for i in 30:
		var r := w.advance_week()
		if r == "play_match":
			w.sim_user_match()
			w.advance_week()
		if r == "sacked":
			w.accept_job(0)
		if w.week == 1 and w.season == 2:
			break
	_check(not w.reviews.is_empty() and (w.reviews[-1].get("ceremony", []) as Array).size() >= 4, "ceremony awards recorded (%d)" % (w.reviews[-1].get("ceremony", []) as Array).size() if not w.reviews.is_empty() else "ceremony: no review")

	# --- Logos persist.
	ut = w.user_team()
	ut.logo = "split"
	ut.color2 = Color("065f46")
	Game.save_world()
	Game.load_world()
	w = Game.world
	_check(w.user_team().logo == "split" and w.user_team().color2.to_html(false) == "065f46", "team logo and second colour saved")

	# --- Backups: a save in a new week rotates a backup.
	Game.save_world()
	w.week += 1
	Game.save_world()
	var bl := Game.list_backups("world")
	_check(bl.size() >= 1, "backups listed: %d" % bl.size())
	if not bl.is_empty():
		var wk := w.week
		_check(Game.restore_backup("world", 1) and Game.world.week == wk - 1, "restored backup (week %d -> %d)" % [wk, Game.world.week])
	w = Game.world

	if out != "":
		var hub: Node = load(Game.MANAGER_SCENE).instantiate()
		add_child(hub)
		await _shot(out + "/b10_ceremony.png")
		for c in hub.get_children():
			if c is ColorRect:
				c.queue_free()
		w.review_pending = false
		for pg in ["Club", "Stats"]:
			hub._show(pg)
			await _shot(out + "/b10_m_%s.png" % pg.to_lower())
		hub._stats_state = {"tab": "Search", "league": -1, "query": ""}
		hub._show("Stats")
		await _shot(out + "/b10_m_search.png")
		hub.queue_free()
		var ed: Node = load(Game.EDITOR_SCENE).instantiate()
		add_child(ed)
		await _shot(out + "/b10_editor.png")
		ed.queue_free()
		await _shot("")

	# --- My Player: agent and feed.
	Game.end_career()
	Game.create_my_player("Tenner", "Entry", "Korea")
	Game.start_career()
	var pw := Game.pworld
	var me := pw.user_player
	pw.wallet = 200000
	var w0 := pw.offer_wage(pw.teams[0])
	_check(pw.hire_agent("super") != "", "super agent needs followers")
	_check(pw.hire_agent("pro") == "" and pw.offer_wage(pw.teams[0]) > w0 and pw.agent_cut() > 0, "pro agent: offers %s -> %s, cut %s" % [w0, pw.offer_wage(pw.teams[0]), pw.agent_cut()])
	for i in 6:
		var r := pw.advance_week()
		if r == "play_match":
			pw.sim_user_match()
			pw.advance_week()
	_check(pw.feed.size() >= 3, "feed has %d posts" % pw.feed.size())
	if out != "":
		var ph: Node = load(Game.CAREER_SCENE).instantiate()
		add_child(ph)
		for c in ph.get_children():
			if c is ColorRect:
				c.queue_free()
		for pg in ["Feed", "Career"]:
			ph._show(pg)
			await _shot(out + "/b10_p_%s.png" % pg.to_lower())
		ph.queue_free()
		await _shot("")
	Game.end_career()
	print("b10_probe: %d failure(s)" % fails)
	get_tree().quit()


func _shot(path: String) -> void:
	for f in 8:
		await get_tree().process_frame
	if path != "":
		get_viewport().get_texture().get_image().save_png(path)
