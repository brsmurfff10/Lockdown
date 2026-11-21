extends Node
## Where My Player conversations lead: the coach weighing a case for a start
## (lineup actually changes), demands backfiring, conditional promises,
## teammates going to the coach until discipline bites (bench, release),
## asking to leave (transfer list -> offers, termination, refusal), other
## clubs' coaches following up (offer, pre-agreement, refusal), club attitudes
## gating offers, and DM trash talk changing match_mod.
## Run:  godot --headless --path . res://tests/outcomes_probe.tscn -- --test

var fails := 0


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		fails += 1


func _fresh(name_: String) -> World:
	Game.end_career()
	Game.create_my_player(name_, "Rifler", "Canada")
	Game.start_career()
	return Game.pworld


func _week(w: World) -> void:
	var r := w.advance_week()
	if r == "play_match":
		w.sim_user_match()
		w.advance_week()
	elif r == "free_agency":
		w.accept_offer(0)
		w.advance_week()


func _has_msg(w: World, needle: String) -> bool:
	return w.inbox.any(func(m: Dictionary) -> bool: return String(m.title).contains(needle))


func _bot_texts(th: Dictionary) -> String:
	var out: Array = []
	for m in th.msgs:
		if not bool(m.me):
			out.append(String(m.text))
	return " | ".join(out)


## Puts you just outside the five: rating a little below the rival starter.
func _bench(w: World) -> PlayerData:
	var me := w.user_player
	me.promise_until = 0
	w.forced_bench_until = 0
	w.soc().talk.start_until = 0
	var low := INF
	for p in w.user_team().roster:
		if not p.is_user:
			p.out_weeks = 0
	for p in w.user_team().starters(5):
		if not p.is_user:
			low = minf(low, p.rating_exact())
	for k: String in PlayerData.STAT_KEYS:
		me.set_stat(k, low - 5.0)
	me.form = 0.0
	w._apply_coach()
	return w.soc().talk.rival_starter()


func _log(p: PlayerData, r: float, n: int, w: World) -> void:
	for i in n:
		p.log_match({"s": w.season, "w": w.week, "opp": "X", "label": "League", "res": "W", "score": "6-3", "k": 15, "d": 10, "adr": 80, "r": r, "mod": 0.0})


func _ready() -> void:
	# --- 1. The coach weighs your case.
	var w := _fresh("Outcome")
	var s := w.soc()
	var styles := {}
	for t in w.teams:
		styles[ClubTalk.coach_style(t)] = true
	_check(styles.size() == 3, "coach personalities vary by club (%s)" % ", ".join(styles.keys()))
	var riv := _bench(w)
	_check(not w.user_starting(), "setup: you're on the bench behind %s" % riv.player_name)
	_log(w.user_player, 1.55, 5, w)
	_log(riv, 0.7, 5, w)
	w.coach_trust = 45.0
	w.trained_this_week = true
	s.thread("coach").sent_n = 0
	var r := s.send("coach", "Coach, I've been training hard and my last games were strong. I think I deserve a chance, please consider me.")
	_check(s.talk.start_until >= w.stamp() and w.user_starting(), "a strong, polite case below 60 trust gets you in the five (%s)" % r.msg)
	_check(_bot_texts(s.thread("team")) != "", "a teammate mentions it in the team chat: %s" % _bot_texts(s.thread("team")))
	# Demands backfire.
	riv = _bench(w)
	s.lineup_ask_stamp = 0
	s.talk.start_granted = 0
	var t0 := w.coach_trust
	r = s.send("coach", "START ME NOW. you have to, this is ridiculous")
	_check(w.coach_trust < t0 and not w.user_starting(), "a demand backfires: trust %d -> %d, still benched (%s)" % [int(t0), int(w.coach_trust), r.msg])
	# Weak case: earn it.
	s.lineup_ask_stamp = 0
	s.talk.start_granted = 0
	w.user_player.match_log.clear()
	_log(w.user_player, 0.6, 5, w)
	_log(riv, 1.4, 5, w)
	w.trained_this_week = false
	r = s.send("coach", "can I start next match please?")
	_check(s.talk.start_until < w.stamp() and not w.user_starting(), "a weak case: earn it (%s)" % r.msg)
	# Conditional promise checked next week.
	s.talk.conditional = {"made": w.stamp(), "need": 1.0, "rival": riv.uid}
	_log(w.user_player, 1.3, 1, w)
	_week(w)
	_check(s.talk.start_until >= w.stamp() and s.talk.conditional.is_empty(), "conditional promise kept: you start the next week (%s)" % _bot_texts(s.thread("coach")).right(80))

	# --- 2a. Teammates go to the coach; discipline bites.
	w = _fresh("Hothead")
	s = w.soc()
	var complained := false
	var benched := false
	for i in 14:
		var mates: Array = s.mates()
		if w.teamless or mates.is_empty():
			break
		var tgt: PlayerData = mates[0]
		s.thread("team").sent_n = 0
		s.send("team", "%s you're useless trash, uninstall" % tgt.player_name)
		s.send("team", "this whole team is garbage, worst clowns ever")
		s.thread("coach").sent_n = 0
		s.send("coach", "you're a clueless idiot coach")
		if _has_msg(w, "went to the coach about you"):
			complained = true
		if w.forced_bench_until >= w.stamp():
			benched = true
		_week(w)
		if w.teamless:
			break
	_check(complained, "a teammate went to the coach about you (visible inbox message)")
	_check(benched, "it ends in a disciplinary bench")
	_check(w.teamless, "and then release")

	# --- 2b. Asking to leave.
	w = _fresh("Leaver")
	s = w.soc()
	var me := w.user_player
	var rs: Array = w.user_team().roster.filter(func(p: PlayerData) -> bool: return not p.is_user).map(func(p: PlayerData) -> float: return p.rating_exact())
	rs.sort()
	for k: String in PlayerData.STAT_KEYS:
		me.set_stat(k, float(rs[1]))
	w.coach_trust = 55.0
	r = s.send("coach", "I want to leave, please transfer me")
	_check(w.transfer_request, "asking to leave gets you transfer-listed (%s)" % r.msg)
	var o0 := w.offers.size()
	_week(w)
	_week(w)
	_check(w.offers.size() > o0, "transfer list produces real offers (%d)" % w.offers.size())
	w = _fresh("Walkout")
	s = w.soc()
	for k: String in PlayerData.STAT_KEYS:
		w.user_player.set_stat(k, 30.0)
	w.coach_trust = 20.0
	r = s.send("coach", "release me, I want out")
	_check(w.teamless, "low trust: the club terminates your contract (%s)" % r.msg)
	w = _fresh("Keyman")
	s = w.soc()
	me = w.user_player
	for k: String in PlayerData.STAT_KEYS:
		me.set_stat(k, 95.0)
	me.contract_until = w.season + 2
	w.coach_trust = 60.0
	r = s.send("coach", "let me go, transfer me")
	_check(not w.transfer_request and not w.teamless and _has_msg(w, "refuse"), "key player with a long contract: refused (%s)" % r.msg)

	# --- 3. Other clubs' coaches follow up.
	w = _fresh("Courted")
	s = w.soc()
	me = w.user_player
	var ut := w.user_team()
	var club: TeamData = null
	for t in w.league_teams(ut.league):
		if t != ut and w.derby_rival(ut) != t:
			club = t
			break
	var idx := w.team_index(club)
	for k: String in PlayerData.STAT_KEYS:
		me.set_stat(k, club.rating_exact() + 2.0)
	var via: PlayerData = club.roster[0]
	w.relations[via.uid] = 40.0
	var key := s.open_thread(via)
	r = s.send(key, "hey, can I join your team? put a word in with your coach")
	_check(s.talk.followups.any(func(f: Dictionary) -> bool: return String(f.kind) == "ext_coach" and int(f.team) == idx), "the player will mention you to their coach (%s)" % r.msg)
	_check(w.window_open(), "setup: transfer window open (week %d)" % w.week)
	s.live = true
	_week(w)
	var xth := s.thread(s.talk.ext_key(idx))
	_check(not (xth.msgs as Array).is_empty(), "their coach DMs you: %s: %s" % [s.thread_title(xth), _bot_texts(xth)])
	_check(w.offers.any(func(o: Dictionary) -> bool: return int(o.team) == idx), "a real contract offer from %s" % club.team_name)
	_check(_bot_texts(s.thread(key)).to_lower().contains("coach"), "the player tells you their coach will be in touch: %s" % _bot_texts(s.thread(key)).right(70))
	var last: Dictionary = (xth.msgs as Array)[(xth.msgs as Array).size() - 1]
	_check(last.has("at"), "follow-ups sent while the hub is open get a delivery time")
	s.live = false
	# Pre-agreement outside a window.
	var club2: TeamData = w.league_teams(ut.league)[3] if w.league_teams(ut.league)[3] != ut else w.league_teams(ut.league)[4]
	var idx2 := w.team_index(club2)
	for k: String in PlayerData.STAT_KEYS:
		me.set_stat(k, club2.rating_exact() + 2.0)
	var wk := w.week
	w.week = 7
	s.talk._ext_coach(idx2, club2.roster[0].uid)
	_check(s.talk.pre_agreements.any(func(x: Dictionary) -> bool: return int(x.team) == idx2) and not w.offers.any(func(o: Dictionary) -> bool: return int(o.team) == idx2), "window shut: a pre-agreement instead of an offer")
	w.week = 13
	s.talk.deliver()
	_check(w.offers.any(func(o: Dictionary) -> bool: return int(o.team) == idx2), "the window opens: the pre-agreed offer arrives")
	w.week = wk
	# A club you have beef with shuts you down.
	var club3: TeamData = w.league_teams(ut.league)[5] if w.league_teams(ut.league)[5] != ut else w.league_teams(ut.league)[6]
	var idx3 := w.team_index(club3)
	s.team_beef[idx3] = 10
	s.talk.note_club(idx3, -40.0, "you trash-talked them", 20)
	var k3 := s.open_thread(club3.roster[1])
	r = s.send(k3, "can I join your team? any spots?")
	_check(not s.talk.followups.any(func(f: Dictionary) -> bool: return String(f.kind) == "ext_coach" and int(f.team) == idx3), "beef: shut down, no follow-up (%s / %s)" % [r.msg, _bot_texts(s.thread(k3))])

	# --- 4. Club attitudes gate offers.
	var at := s.talk.attitude(idx3)
	_check(String(at.label) == "won't sign" and (at.reasons as Array).has("you trash-talked them"), "attitude: %s (%s)" % [at.label, ", ".join(at.reasons)])
	w.offers = w.offers.filter(func(o: Dictionary) -> bool: return int(o.team) != idx3)
	for i in 30:
		w._add_offer(idx3, "test")
	_check(not w.offers.any(func(o: Dictionary) -> bool: return int(o.team) == idx3), "a club that won't sign you never makes an offer")
	var club4: TeamData = w.league_teams(ut.league)[7] if w.league_teams(ut.league)[7] != ut else w.league_teams(ut.league)[8]
	var idx4 := w.team_index(club4)
	s.talk.note_club(idx4, -25.0, "you trash-talked their players", 20)
	var allowed := 0
	for i in 200:
		if s.talk.allows_offer(idx4):
			allowed += 1
	_check(String(s.talk.attitude(idx4).label) == "wary" and allowed > 40 and allowed < 130, "wary clubs make fewer offers (%d/200 allowed)" % allowed)
	var club5: TeamData = w.league_teams(ut.league)[9] if w.league_teams(ut.league)[9] != ut else w.league_teams(ut.league)[10]
	w.relations[club5.roster[0].uid] = 60.0
	var at5 := s.talk.attitude(w.team_index(club5))
	_check((at5.reasons as Array).has("friend of %s" % club5.roster[0].player_name) and float(at5.score) > 0.0, "friends help: %s (%s)" % [at5.label, ", ".join(at5.reasons)])
	_check(not s.talk.attitudes(10).is_empty(), "How clubs see you list has %d clubs" % s.talk.attitudes(10).size())

	# --- 5. DM trash talk carries into the match.
	var bold: PlayerData = null
	var shy: PlayerData = null
	for t in w.teams:
		if t == w.user_team():
			continue
		for p in t.roster:
			var v := ChatText.voice(p)
			if bold == null and v == "toxic":
				bold = p
			if shy == null and v == "shy":
				shy = p
	var bkey := s.open_thread(bold)
	s.send(bkey, "you're trash, I'm going to destroy you")
	var e: Dictionary = s.talk.trash.get(bold.uid, {})
	_check(float(e.get("mod", 0.0)) > 0.0, "a toxic player gets fired up (+%.1f)" % float(e.get("mod", 0.0)))
	e.leaked = true
	var bteam := w.owner_of(bold)
	for q in bteam.roster:
		q.match_mod = 0.0
	s.talk.apply_match_mods(bteam)
	var other: PlayerData = bteam.roster[0] if bteam.roster[0] != bold else bteam.roster[1]
	_check(absf(bold.match_mod - 3.0) < 0.01 and absf(other.match_mod - 1.0) < 0.01 and w.news[-1].contains("fired up"), "match_mod applied (%s %.1f, teammate %.1f): %s" % [bold.player_name, bold.match_mod, other.match_mod, w.news[-1]])
	var skey := s.open_thread(shy)
	s.send(skey, "you're a useless bot, uninstall")
	var e2: Dictionary = s.talk.trash.get(shy.uid, {})
	_check(float(e2.get("mod", 0.0)) < 0.0, "a shy player gets tilted (%.1f)" % float(e2.get("mod", 0.0)))

	# --- Save/load keeps it all.
	var w2 := World.from_dict(JSON.parse_string(JSON.stringify(w.to_dict())))
	_check(w2.soc().talk.trash.size() == s.talk.trash.size() and String(w2.soc().talk.attitude(idx3).label) == "won't sign", "outcomes survive save/load")

	Game.end_career()
	print("OUTCOMES: %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit()
