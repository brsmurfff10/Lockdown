extends Node
## My Player career systems: contract and wallet, coach lineup and bench,
## inbox (media, endorsements, contract talks, bids), transfer requests, free
## agency, goals, perks, awards, All-Stars, rivals, save/load, retirement,
## and (with --out=<dir>) screenshots of every hub page.
## Run:  godot --path . res://tests/my_player_probe.tscn -- --test [--windowed] [--out=<dir>]

var fails := 0


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		fails += 1


func _open(w: World, kind: String) -> Dictionary:
	for m in w.inbox:
		if not bool(m.done) and String(m.kind) == kind:
			return m
	return {}


func _opt(m: Dictionary, action: String) -> int:
	for i in (m.options as Array).size():
		if String(m.options[i][1]) == action:
			return i
	return -1


func _ready() -> void:
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	if "--windowed" in OS.get_cmdline_user_args():
		get_window().size = Vector2i(1600, 900)
	Game.end_career()
	Game.create_my_player("Probe", "Rifler")
	Game.start_career()
	var w := Game.pworld
	var p := w.user_player

	# --- Start.
	_check(p.salary > 0 and p.contract_until == w.season + 1, "rookie contract: $%d/wk to S%d" % [p.salary, p.contract_until])
	_check(w.goals.size() == 4, "4 season goals: %s" % ", ".join(w.goals.map(func(g: Dictionary) -> String: return String(g.text))))
	_check(w.timeline.size() == 1 and w.user_team().coach_pick, "timeline started, coach picks the lineup")
	_check(w.user_starting(), "rookie promise: you start the first weeks")

	# --- A season and a half, answering the inbox with the first option.
	var w0 := w.wallet
	var fa_seen := false
	for i in 40:
		for m in w.inbox:
			if not bool(m.done) and String(m.options[0][1]) != "pm_retire":
				w.resolve_msg(m, 0)
		var r := w.advance_week()
		if r == "free_agency":
			fa_seen = true
			w.accept_offer(0)
			r = w.advance_week()
		if r == "play_match":
			w.sim_user_match()
			w.advance_week()
	_check(w.wallet > w0, "wallet grew to %s" % UI.money_text(w.wallet))
	_check(w.season == 2 and w.timeline.size() >= 2, "season 2 reached, timeline has %d lines" % w.timeline.size())
	_check(not w.rivals.is_empty(), "rivals tracked (%d)" % w.rivals.size())
	_check(w.goals.size() >= 3 and w.goals.all(func(g: Dictionary) -> bool: return String(g.status) == "open" or String(g.status) == "done"), "new goals for season 2")
	print("  fame %s, trust %d, potm %d, awards %d, trophies %d, free agency seen %s" % [World.fame_text(w.fame), int(w.coach_trust), w.potm, w.awards.size(), w.trophies.size(), fa_seen])

	# --- Training intensity, injury blocks training.
	p.out_weeks = 0
	p.ailment = ""
	w.trained_this_week = false
	w.train_user("aim", "Light")
	_check(w.trained_this_week and String(w.last_training.get("intensity", "")) == "Light", "light session recorded")
	w.trained_this_week = false
	p.out_weeks = 1
	p.ailment = "the flu"
	_check(w.train_user("aim", "Hard") == 0.0 and not w.trained_this_week, "can't train while ill")
	_check(w.user_play_block().contains("flu"), "can't play while ill: %s" % w.user_play_block())
	p.out_weeks = 0
	p.ailment = ""

	# --- Coach drops you; react.
	p.promise_until = 0
	w.coach_trust = 0.0
	p.form = -8.0
	var saved := p.stats.duplicate()
	for k: String in PlayerData.STAT_KEYS:
		p.set_stat(k, 30.0)
	for pl in w.user_team().roster:
		pl.out_weeks = 0
	w._apply_coach()
	_check(not w.user_starting() and w.user_play_block().contains("bench"), "low trust + slump: benched")
	p.bench_weeks = 0
	w._coach_week()
	var bm := _open(w, "bench")
	_check(not bm.is_empty(), "bench message from the coach")
	if not bm.is_empty():
		w.resolve_msg(bm, _opt(bm, "pm_bench_ok"))
		_check(w.coach_trust >= 2.0, "accepting it earns trust (%d)" % int(w.coach_trust))
	if not w.user_match_this_week().is_empty():
		Game.prepare_player_match()
		_check(Game.pending_match.mode == "bench", "benched: the match is watched from the bench")
		Game.pending_match = {}
	w.coach_trust = 60.0
	p.form = 0.0
	p.stats = saved
	p.promise_until = w.stamp() + 2
	w._apply_coach()
	if not w.user_starting():
		var ut1 := w.user_team()
		for pl in ut1.roster:
			print("    %s score %.1f rtg %.1f form %.1f avail %s" % [pl.player_name, ut1.lineup_score(pl), pl.rating_exact(), pl.form, pl.available()])
		print("    bonus ", ut1.user_bonus, " pick ", ut1.coach_pick)
	_check(w.user_starting(), "promise puts you back in")

	# --- Media: trash talk.
	var mm := {}
	for i in 300:
		w._dressing_room()
		mm = _open(w, "media")
		if not mm.is_empty():
			break
	_check(not mm.is_empty(), "interview request arrives")
	if not mm.is_empty():
		var f0 := w.fame
		w.resolve_msg(mm, _opt(mm, "pm_trash"))
		_check(w.fame > f0 and w.trash_target >= 0, "trash talk: fame %d -> %d, %s fired up" % [f0, w.fame, w.teams[w.trash_target].team_name])

	# --- Endorsements.
	w.fame = 6000
	w.endorsements.clear()
	var em := {}
	for i in 300:
		w._endorsement_offers()
		em = _open(w, "endorse")
		if not em.is_empty():
			break
	_check(not em.is_empty(), "endorsement offer at 6k followers")
	if not em.is_empty():
		var n0 := w.endorsements.size()
		w.resolve_msg(em, _opt(em, "pm_endorse"))
		_check(w.endorsements.size() == n0 + 1 and w.endorsement_income() > 0, "signed: %s/wk" % UI.money_text(w.endorsement_income()))

	# --- Transfer request (low trust, not a key player: accepted), offers, move.
	w.week = 2
	w.transfer_request = false
	w.coach_trust = 0.0
	var saved2 := p.stats.duplicate()
	var res := ""
	for i in 20:
		w.transfer_request = false
		w.coach_trust = 0.0
		res = w.request_transfer()
		if w.transfer_request:
			break
	_check(w.transfer_request, "transfer request accepted: %s" % res)
	w.offers.clear()
	for i in 40:
		w._transfer_interest()
		if w.offers.size() >= 2:
			break
	_check(w.offers.size() >= 1 and int(w.offers[0].wage) > 0, "offers arrive after the request (%d)" % w.offers.size())
	if not w.offers.is_empty():
		var dest: TeamData = w.teams[int(w.offers[0].team)]
		var tl0 := w.timeline.size()
		_check(w.accept_offer(0) == "" and w.user_team() == dest, "moved to %s" % dest.team_name)
		_check(w.timeline.size() == tl0 + 1 and not w.transfer_request and int(w.coach_trust) == 55, "new timeline line, request cleared, fresh trust")

	p.stats = saved2
	# --- Club accepts a bid; you refuse.
	w.week = 2
	var sm := {}
	for m in w.inbox:
		if String(m.kind) == "sold":
			m.done = true
	for i in 400:
		w._transfer_interest()
		sm = _open(w, "sold")
		if not sm.is_empty() and _opt(sm, "pm_sold_stay") >= 0:
			break
		if not sm.is_empty():
			sm.done = true
			sm = {}
	_check(not sm.is_empty(), "club accepts a bid for you (inbox)")
	if not sm.is_empty():
		var t0 := w.coach_trust
		var team0 := w.user_team()
		w.resolve_msg(sm, _opt(sm, "pm_sold_stay"))
		_check(w.coach_trust < t0 and w.user_team() == team0, "refused the move: trust %d -> %d" % [int(t0), int(w.coach_trust)])

	# --- Contract talks in the final season.
	p.contract_until = w.season
	w.renewal_done = false
	w.coach_trust = 70.0
	w.week = 12
	w._contract_talks()
	var cm := _open(w, "contract")
	_check(not cm.is_empty() and _opt(cm, "pm_renew_more") >= 0, "renewal offer at week 12")
	if not cm.is_empty():
		w.resolve_msg(cm, _opt(cm, "pm_renew_more"))
		print("  agent: ", cm.result)
		var cm2 := _open(w, "contract")
		if not cm2.is_empty():
			w.resolve_msg(cm2, _opt(cm2, "pm_renew"))
			_check(p.contract_until > w.season and w.renewal_done, "signed the extension to S%d at $%d" % [p.contract_until, p.salary])
		else:
			_check(w.renewal_done, "club walked away: free agency later")

	# --- Free agency.
	w._start_free_agency(w.user_team())
	_check(w.free_agency and w.offers.size() >= 3, "free agency: %d offers" % w.offers.size())
	_check(w.advance_week() == "free_agency", "can't advance until you pick a club")
	while w.offers.size() > 1:
		w.decline_offer(0)
	_check(w.decline_offer(0) != "", "can't decline your last offer")
	_check(w.accept_offer(0) == "" and not w.free_agency, "joined %s as a free agent" % w.user_team().team_name)

	# --- Goals and perks.
	p.season_stats["k"] = 999
	for g in w.goals:
		g.status = "open"
	var wb := w.wallet
	w._check_goals(false)
	_check(w.goals.any(func(g: Dictionary) -> bool: return String(g.kind) == "kills" and String(g.status) == "done") and w.wallet > wb, "kills goal completed with a bonus")
	p.matches_played = maxi(p.matches_played, 45)
	var re0 := p.stat("reaction")
	w._check_perks()
	_check(w.perks.has("first_blood") and w.perks.has("grinder"), "perks unlocked: %s" % ", ".join(w.perks))

	# --- Awards and the All-Star Showcase.
	p.season_stats = {"m": 20, "k": 300, "d": 100, "r_sum": 20 * 2.6}
	var a0 := w.awards.size()
	w._season_awards()
	_check(w.awards.size() > a0 and w.awards.any(func(a: Dictionary) -> bool: return String(a.name).ends_with("MVP")), "season awards: %s" % ", ".join(w.awards.slice(a0).map(func(a: Dictionary) -> String: return String(a.name))))
	_check(not w.allstar.is_empty() and (w.allstar.a as Array).has(p.uid), "picked as an All-Star")
	w.allstar.season = w.season
	w.week = 2
	w.trophies.append({"s": w.season, "name": "Open Cup S%d" % w.season, "place": 1, "team": w.user_team().team_name})
	w.trophies.append({"s": w.season - 1, "name": "Promotion to the Challenger League", "place": 0, "team": w.user_team().team_name})
	_check(w.allstar_pending(), "All-Star match pending this week")

	# --- Save / load.
	Game.save_player_career()
	Game.load_player_career()
	var w2 := Game.pworld
	_check(w2.wallet == w.wallet and w2.awards.size() == w.awards.size() and w2.perks == w.perks and w2.timeline.size() == w.timeline.size(), "career state survives save/load")
	_check(w2.rivals.keys().all(func(k: Variant) -> bool: return k is int) and w2.user_team().coach_pick, "rival ids and coach lineup restored")
	w = w2
	p = w.user_player

	if out != "":
		var hub: Node = load(Game.CAREER_SCENE).instantiate()
		add_child(hub)
		await _shot(out + "/mp_overview.png")
		for pg in ["Inbox", "Profile", "Training", "Career", "Team", "League", "Tournaments"]:
			hub._show(pg)
			await _shot(out + "/mp_%s.png" % pg.to_lower())
		hub._show("Overview")
		var res2 := w.sim_allstar()
		hub._refresh()
		hub._show_results(res2)
		await _shot(out + "/mp_allstar.png")
		_close_all(hub)
		hub.queue_free()
	else:
		w.sim_allstar()
	_check(bool(w.allstar.done), "All-Star match played")

	# --- Retirement.
	p.age = 31
	_check(w.can_retire(), "can retire at 31")
	w.retire()
	_check(w.retired and String(w.legacy.get("tier", "")) != "", "retired: %s (score %d)" % [w.legacy.get("tier", "?"), int(w.legacy.get("score", 0))])
	_check(w.advance_week() == "retired", "the season stops after retirement")
	if out != "":
		var hub2: Node = load(Game.CAREER_SCENE).instantiate()
		add_child(hub2)
		hub2._show("Profile")
		await _shot(out + "/mp_legacy.png")
		hub2.queue_free()
	Game.end_career()
	print("my_player_probe: %d failure(s)" % fails)
	get_tree().quit()


func _close_all(hub: Node) -> void:
	for c in hub.get_children():
		if c is ColorRect:
			c.queue_free()


func _shot(path: String) -> void:
	for f in 8:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)
