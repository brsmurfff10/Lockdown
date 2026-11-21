extends Node
## Manager career systems: windows, renames, sponsors, loans/investors, debt,
## bids for your players, form/morale, match history, save/load, and (with
## --out=<dir>) screenshots of the hub pages and popups.
## Run:  godot --path . res://tests/career_probe.tscn -- --test [--windowed] [--out=<dir>]

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
	var nw := Game.new_manager_world()
	Game.start_manager_career(nw, nw.team_index(nw.league_teams(2)[3]), "Probe Org", "PRB", Color.CYAN)
	var w := Game.world
	var ut := w.user_team()

	# --- Starting sponsor + offers.
	_check(w.sponsors.size() == 1 and w.sponsor_in_slot("Main").size() > 0, "starts with a headline sponsor (%s)" % w.sponsors[0].brand)
	_check(w.sponsor_offers.size() >= 2, "starts with %d sponsor offers" % w.sponsor_offers.size())
	var inc0 := w.sponsor_income()
	var err := w.accept_sponsor(0)
	_check(err == "" and w.sponsor_income() > inc0, "accepting an offer adds income (%s -> %s)" % [inc0, w.sponsor_income()])

	# --- Renames.
	var p0: PlayerData = ut.roster[0]
	var uid := p0.uid
	_check(w.rename_player(p0, "Renamed") == "" and p0.player_name == "Renamed", "rename player")
	_check(w.rename_player(ut.roster[1], "Renamed") != "", "duplicate player name rejected")
	var other: TeamData = w.teams[0] if w.teams[0] != ut else w.teams[1]
	_check(w.rename_team(other, "Banana Republic", "BAN") == "" and other.short_name == "BAN", "rename another team")

	# --- Window closed blocks signings.
	while w.window_open():
		w.week += 1
	var fa: PlayerData = w.free_agents[0]
	if ut.roster.size() >= World.MAX_ROSTER:
		w.release_player(ut.roster[ut.roster.size() - 1])
	_check(w.sign_free_agent(fa) != "" and not ut.roster.has(fa), "free agent signing blocked outside the window (%s)" % w.window_text())
	w.week = 1

	# --- Loans.
	var m0 := w.money
	var bank_i := World.LENDERS.size() - 1 # QuickCash: anyone qualifies.
	var amt := w.lender_limit(World.LENDERS[bank_i])
	_check(w.take_loan(bank_i, amt) == "" and w.money == m0 + amt, "QuickCash loan of %s" % UI.money_text(amt))
	_check(w.take_loan(bank_i, amt) != "", "second loan from the same lender refused")
	var stake_i := 2
	ut.reputation = maxf(ut.reputation, 25.0)
	var s_amt := w.lender_limit(World.LENDERS[stake_i]) / 2
	_check(w.take_loan(stake_i, s_amt) == "" and w.stake_share() > 0.1, "investor stake (%d%% of income)" % int(w.stake_share() * 100))
	var before := w.money
	w._earn(10000, "Test income")
	_check(w.money - before == 10000 - int(10000 * 0.15), "investor takes their share of income (%d)" % (w.money - before))
	var loan: Dictionary = w.loans[0]
	var pay := w.payoff_cost(loan)
	_check(w.repay_loan(loan) == "" and w.loans.size() == 1, "loan paid off early for %s" % UI.money_text(pay))

	# --- Debt consequences.
	var roster_before := ut.roster.size()
	w.money = -400000
	var rep0 := ut.reputation
	for i in 3:
		w._debt_check()
	_check(ut.reputation < rep0, "debt costs reputation")
	_check(ut.roster.size() < roster_before or roster_before <= World.MIN_ROSTER, "creditors forced a sale in week 3 of debt")
	w._debt_check()
	_check(w.loans.any(func(x: Dictionary) -> bool: return x.lender == "QuickCash Lending") or w.money >= 0, "administrators forced an emergency loan")
	w.money = 500000
	w.debt_weeks = 0
	while ut.roster.size() < World.MAX_ROSTER and not w.free_agents.is_empty():
		var f: PlayerData = w.free_agents.pop_back()
		ut.roster.append(f)

	# --- Bids for your players.
	var tries := 0
	while w.incoming.is_empty() and tries < 60:
		w._ai_bids_for_user()
		tries += 1
	_check(not w.incoming.is_empty(), "AI clubs bid for your players (%d after %d tries)" % [w.incoming.size(), tries])
	var swaps := 0
	for o in w.incoming:
		if int(o.swap) != 0:
			swaps += 1
	print("  bids: %d (%d with a player in the deal)" % [w.incoming.size(), swaps])
	if not w.incoming.is_empty():
		var o: Dictionary = w.incoming[0]
		var target := w.find_player(int(o.player))
		var buyer: TeamData = w.teams[int(o.team)]
		var log_n := target.match_log.size()
		var nm := target.player_name
		var cash0 := w.money
		var e2 := w.accept_incoming(o)
		_check(e2 == "" and buyer.roster.has(target) and not ut.roster.has(target) and w.money == cash0 + int(o.cash),
			"accepting a bid moves the player and pays %s (%s; got %d, buyer has: %s, sacked %s)" % [UI.money_text(int(o.cash)), e2, w.money - cash0, buyer.roster.has(target), w.sacked])
		_check(target.player_name == nm and target.match_log.size() == log_n, "traded player keeps name and history")
	if not w.incoming.is_empty():
		var results := {}
		for o in w.incoming.duplicate():
			var r := w.counter_incoming(o)
			results[r] = int(results.get(r, 0)) + 1
		print("  counters: %s" % results)

	# --- A season of weeks: form, morale, history, wire, sponsors.
	for i in 14:
		if not w.user_match_this_week().is_empty():
			if w.sim_user_match().is_empty():
				w.forfeit_user_match()
		w.advance_week()
	var p := w.find_player(uid)
	_check(p != null and p.match_log.size() > 0, "match history logged for %s (%d matches)" % [p.player_name if p else "?", p.match_log.size() if p else 0])
	var any_ai_log := false
	for pl in other.roster:
		if pl.match_log.size() > 0:
			any_ai_log = true
	_check(any_ai_log, "AI teams' players have match history")
	var forms: Array = []
	var slumps := 0
	for t in w.teams:
		for pl in t.roster:
			forms.append(pl.form)
			if pl.form <= -4.5:
				slumps += 1
	forms.sort()
	print("  form spread: min %.1f  median %.1f  max %.1f, %d in a slump" % [forms[0], forms[forms.size() / 2], forms[-1], slumps])
	_check(forms[-1] - forms[0] > 4.0, "form varies between players")
	_check(w.wire.size() >= 10, "news wire has %d headlines" % w.wire.size())
	for e in w.wire.slice(maxi(0, w.wire.size() - 6)):
		print("   wire: %s" % e.text)
	print("  sponsors: %d active, %d offers; money %s; net/wk %s" % [w.sponsors.size(), w.sponsor_offers.size(), UI.money_text(w.money), UI.money_text(w.weekly_net())])

	# --- Batch 2: listing, sponsors counter, inbox, illness, forfeit, brackets, bids, refusals.
	w.week = 2
	ut = w.user_team()
	var lp: PlayerData = ut.roster[ut.roster.size() - 1]
	w.set_listed(lp, true)
	w.incoming.clear()
	var listed_bids := 0
	for i in 20:
		w._ai_bids_for_user()
		listed_bids = w.incoming.filter(func(o: Dictionary) -> bool: return int(o.player) == lp.uid).size()
		if listed_bids > 0:
			break
	_check(listed_bids > 0, "listed player attracts bids over a few weeks")
	var outcomes := {}
	for i in 30:
		w.sponsor_offers.append(w._make_sponsor_offer("Partner"))
		var r := w.decline_sponsor(w.sponsor_offers.size() - 1)
		var k := "counter" if "better offer" in r else ("pulled" if "pulled out" in r else "declined")
		outcomes[k] = int(outcomes.get(k, 0)) + 1
	print("  sponsor declines: %s" % outcomes)
	_check(outcomes.get("counter", 0) > 0 and outcomes.get("pulled", 0) > 0, "declined sponsors sometimes counter, sometimes pull out")
	w.sponsor_offers.clear()
	# Complaint -> action.
	var bp: PlayerData = ut.roster[ut.roster.size() - 2]
	bp.bench_weeks = 5
	bp.msg_cooldown = 0
	bp.morale = 50.0
	w._player_messages()
	var msg: Dictionary = {}
	for m in w.inbox:
		if int(m.uid) == bp.uid and not m.done:
			msg = m
	_check(not msg.is_empty(), "benched player complains (%s)" % msg.get("title", "-"))
	if not msg.is_empty():
		var mor := bp.morale
		_check(w.resolve_msg(msg, 0) == "" and bp.morale > mor and bp.promise_until > 0, "promise a starting spot: %s" % msg.result)
	var wp: PlayerData = ut.roster[0]
	wp.morale = 10.0
	wp.msg_cooldown = 0
	w._player_messages()
	var wm: Dictionary = {}
	for m in w.inbox:
		if int(m.uid) == wp.uid and m.kind == "wants_out" and not m.done:
			wm = m
	_check(not wm.is_empty(), "unhappy player asks to leave")
	if not wm.is_empty():
		var sal := wp.salary
		_check(w.resolve_msg(wm, 1) == "" and wp.salary > sal and wp.morale > 30.0, "offer a raise: %s" % wm.result)
	# Illness and forfeits.
	for q in ut.roster:
		q.out_weeks = 0
	for i in ut.roster.size() - 4:
		ut.roster[i].out_weeks = 2
		ut.roster[i].ailment = "the flu"
	_check(not w.can_field_team() and w.can_sign_now(), "fewer than 5 fit players: can't play, can sign outside a window")
	var guard := 0
	while w.user_match_this_week().is_empty() and guard < 10:
		w.advance_week()
		guard += 1
	for i in ut.roster.size() - 4:
		ut.roster[i].out_weeks = 2
	var mt := w.user_match_this_week()
	if not mt.is_empty():
		_check(w.sim_user_match().is_empty(), "simulate refused with too few fit players (no crash)")
		var fee := w.forfeit_fee(mt)
		var m1 := w.money
		_check(w.forfeit_user_match() == "" and w.user_match_this_week() != mt and w.money == m1 - fee, "forfeit costs %s (%s)" % [UI.money_text(fee), mt.label])
	for q in ut.roster:
		q.out_weeks = 0
	# Registration rules (fresh calendar).
	w._make_calendar()
	w.week = 1
	var oc2: Dictionary = {}
	var maj: Dictionary = {}
	for t in w.tournaments:
		if String(t.name).begins_with("Open Cup II"):
			oc2 = t
		if String(t.name).begins_with("Spring Major"):
			maj = t
	_check(w.can_enroll(oc2).begins_with("Registration opens"), "late cups can't be registered in week 1 (%s)" % w.can_enroll(oc2))
	w.week = 8
	ut.reputation = 90.0
	w.money = 900000
	if w.can_enroll(oc2) == "":
		w.enroll(oc2)
	_check(w.can_enroll(maj).begins_with("Clashes"), "overlapping cups clash (%s)" % w.can_enroll(maj))
	_check(World.stage_name(8, 0) == "Quarter-final" and World.stage_name(16, 3) == "Final", "playoff stage names")
	# Bids with players + refusals.
	w.week = 2
	w.offers_made.clear()
	var target2: PlayerData = null
	for t in w.teams:
		if t != ut and t.league >= ut.league:
			for q in t.roster:
				if q.refuses(ut) == "" and target2 == null:
					target2 = q
	var swap: PlayerData = ut.roster[ut.roster.size() - 1]
	var r2 := w.make_offer(target2, 0, [swap])
	print("  player-swap bid: '%s'" % r2)
	_check(r2 == "" or "rejected" in r2 or "insulting" in r2 or "refuse" in r2 or "wants" in r2 or "feud" in r2, "bid with a player in it is evaluated")
	var refusers := 0
	var total2 := 0
	for q in w.market_players():
		total2 += 1
		if q.refuses(ut) != "":
			refusers += 1
	print("  %d / %d players refuse to join you" % [refusers, total2])
	_check(refusers > 0 and refusers < total2 / 2, "some (not most) players refuse your club")
	var first_uid := ut.roster[0].uid
	w.move_to_index(ut.roster[0], 3)
	_check(ut.roster[3].uid == first_uid, "drag-and-drop reorder")

	# --- Save / load keeps everything.
	var d := w.to_dict()
	var w2 := World.from_dict(JSON.parse_string(JSON.stringify(d)))
	var p2 := w2.find_player(uid)
	_check(p2 != null and p2.player_name == p.player_name and p2.match_log.size() == p.match_log.size(), "save/load keeps uid, name and history")
	_check(w2.sponsors.size() == w.sponsors.size() and w2.loans.size() == w.loans.size(), "save/load keeps sponsors and loans")
	_check(w2.teams[w.team_index(other)].team_name == "Banana Republic", "save/load keeps team rename")

	# --- Screens.
	if out != "":
		w.week = 2 # Window open, for the offers view.
		var tries2 := 0
		while w.incoming.size() < 3 and tries2 < 60:
			w._ai_bids_for_user()
			tries2 += 1
		var hub: Node = load(Game.MANAGER_SCENE).instantiate()
		add_child(hub)
		for page in hub.PAGES:
			hub._show(page)
			await _shot(out + "/c_%s.png" % page.to_lower())
		hub._portal_view = "Offers"
		hub._show("Transfers")
		await _shot(out + "/c_offers.png")
		hub._show("Roster")
		hub._view_player(ut.roster[0])
		await _shot(out + "/c_player_card.png")
		hub._close_modals()
		hub._show("League")
		hub._view_team(w.standings(ut.league)[0])
		await _shot(out + "/c_team_popup.png")
		var popup: Node = hub.get_child(hub.get_child_count() - 1)
		for b in popup.find_children("*", "Button", true, false):
			if (b as Button).text == "Season stats":
				(b as Button).pressed.emit()
		await _shot(out + "/c_team_stats.png")
		hub._close_modals()
		hub._rename_team(other)
		await _shot(out + "/c_rename.png")
		_close_all(hub)
		hub._show("Inbox")
		await _shot(out + "/c_inbox.png")
		hub._show("Transfers")
		hub._portal_view = "Other clubs"
		hub._bid_dialog(w.market_players()[5])
		await _shot(out + "/c_bid.png")
		_close_all(hub)
		w._make_calendar()
		for t in w.tournaments:
			t.user_enrolled = false
		w.week = 3
		w._begin_week()
		for k in 3:
			if not w.user_match_this_week().is_empty() and w.sim_user_match().is_empty():
				w.forfeit_user_match()
			w.advance_week()
		hub._show("Tournaments")
		await _shot(out + "/c_bracket.png")
	print("career_probe: %d failure(s)" % fails)
	get_tree().quit()


func _close_all(hub: Node) -> void:
	for c in hub.get_children():
		if c is ColorRect:
			c.queue_free()


func _shot(path: String) -> void:
	for f in 8:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)
