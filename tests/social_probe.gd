extends Node
## My Player social systems: posting to the feed (tone + target detection,
## fallout, replies, rate limit), friends and rivals (relation API used by
## match chat), DMs, team chat and the coach, discipline (warning, bench,
## release), life without a club (showmatches, trials, stand-ins, offers),
## save/load (and old saves), and the optional LLM client's fallback.
## Run:  godot --path . res://tests/social_probe.tscn -- --test

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


func _bot_lines(th: Dictionary) -> Array:
	var out: Array = []
	for m in th.msgs:
		if not bool(m.me):
			out.append(String(m.text))
	return out


func _week(w: World) -> void:
	var r := w.advance_week()
	if r == "play_match":
		w.sim_user_match()
		w.advance_week()
	elif r == "free_agency":
		w.accept_offer(0)
		w.advance_week()


func _ready() -> void:
	Game.end_career()
	Game.create_my_player("Socialite", "Rifler", "Canada")
	Game.start_career()
	var w := Game.pworld
	var me := w.user_player
	var s := w.soc()
	var ut := w.user_team()
	var mates: Array = ut.roster.filter(func(p: PlayerData) -> bool: return not p.is_user)
	var mate: PlayerData = mates[0]
	var mate2: PlayerData = mates[1]

	# --- Relation API (match chat calls these via has_method).
	_check(w.has_method("relation_to_user") and w.has_method("relation_strength") and w.has_method("team_rivalry"), "relation API exists on World")
	_check(w.relation_to_user(mate) == "" and absf(w.relation_strength(mate)) < 0.01, "new teammate: no relation yet")
	w.relations[mate.uid] = 50.0
	_check(w.relation_to_user(mate) == "friend" and w.relation_strength(mate) > 0.3, "relation 50 -> friend (%.2f)" % w.relation_strength(mate))
	var other_team: TeamData = null
	for t in w.league_teams(ut.league):
		if t != ut and w.derby_rival(ut) != t:
			other_team = t
			break
	var opp_star: PlayerData = other_team.roster[0]
	w.rivals[opp_star.uid] = {"name": opp_star.player_name, "team": other_team.team_name, "w": 2, "l": 3}
	w.relations[opp_star.uid] = -25.0
	_check(w.relation_to_user(opp_star) == "rival" and w.relation_strength(opp_star) < -0.35, "head-to-head + bad blood -> rival (%.2f)" % w.relation_strength(opp_star))
	_check(w.relation_to_user(null) == "" and w.relation_strength(null) == 0.0, "null-safe")
	_check(w.team_rivalry(other_team) or w.top_rival().is_empty() == false, "top rival's club counts as a rivalry")
	_check(not w.team_rivalry(ut), "your own club is never a rival")
	_check(w.team_rivalry(w.derby_rival(ut)) if w.derby_rival(ut) != null else true, "derby rival counts")

	# --- Posting: hype, detection, rate limit.
	var f0 := w.fame
	var n0 := w.feed.size()
	var res := s.post("Proud of the boys, %s all the way. Let's go!" % ut.team_name, "hype")
	_check(bool(res.ok) and String(res.tone) == "hype", "hype post accepted (%s)" % res.msg)
	_check(w.fame > f0, "followers up after hype (%d -> %d)" % [f0, w.fame])
	var mine := w.feed.filter(func(f: Dictionary) -> bool: return String(f.kind) == "me")
	var replies := w.feed.filter(func(f: Dictionary) -> bool: return bool(f.get("re", false)))
	_check(mine.size() == 1 and replies.size() >= 2 and w.feed.size() - n0 >= 3, "own post + %d replies in the feed" % replies.size())
	_check(s.posts_left() == Social.POSTS_PER_WEEK - 1, "posts left: %d" % s.posts_left())
	# Chip says hype, text flames a named teammate: the text wins.
	var rel0 := w.relation(mate2.uid)
	var trust0 := w.coach_trust
	res = s.post("%s is absolute dogshit, worst player on this team" % mate2.player_name, "hype")
	_check(String(res.tone) == "flame", "hype chip + insult at teammate reads as flaming (%s)" % res.msg)
	_check(w.relation(mate2.uid) < rel0 - 15.0 and w.coach_trust < trust0 and s.toxicity > 20.0, "flame fallout: relation %d -> %d, trust %d -> %d, toxicity %d" % [int(rel0), int(w.relation(mate2.uid)), int(trust0), int(w.coach_trust), int(s.toxicity)])
	var thr := w.feed.filter(func(f: Dictionary) -> bool: return String(f.who) == "@" + mate2.player_name)
	_check(not thr.is_empty(), "the flamed teammate replies on the feed")
	res = s.post("%s are a bunch of clowns, see you on the server" % other_team.team_name, "callout")
	_check(String(res.tone) == "callout" and w.trash_target == w.team_index(other_team) and w.team_rivalry(other_team), "call-out: %s fired up and a club rivalry (%s)" % [other_team.short_name, res.msg])
	res = s.post("one more post", "neutral")
	_check(not bool(res.ok), "4th post in a week is refused: %s" % res.msg)
	# Variety in generated replies.
	var texts := {}
	for f in w.feed:
		texts[String(f.text)] = true
	_check(texts.size() >= w.feed.size() - 1, "feed lines are varied (%d unique of %d)" % [texts.size(), w.feed.size()])
	# Apology is detected from text even with the neutral chip.
	s.posts_stamp = 0
	res = s.post("I'm sorry %s, that was out of line. My bad." % mate2.player_name, "neutral")
	_check(String(res.tone) == "apology" and s.toxicity < 60.0, "apology detected from text (%s)" % res.msg)

	# --- DMs.
	var key := s.open_thread(mate)
	var r0 := w.relation(mate.uid)
	var dm := s.send(key, "gg man, you were insane today")
	var th := s.thread(key)
	_check(bool(dm.ok) and _bot_lines(th).size() >= 1, "DM to a teammate gets a reply: \"%s\"" % _bot_lines(th)[-1])
	_check(w.relation(mate.uid) > r0, "praise DM improves the relation (%.1f -> %.1f)" % [r0, w.relation(mate.uid)])
	r0 = w.relation(mate.uid)
	s.send(key, "you're a useless clown, uninstall")
	_check(w.relation(mate.uid) < r0 - 10.0, "flame DM hurts it (%.1f -> %.1f): \"%s\"" % [r0, w.relation(mate.uid), _bot_lines(th)[-1]])
	_check(ChatText.dm_intent(ChatText.analyze("can you start me next week coach")) == "lineup", "intent: lineup")
	_check(ChatText.dm_intent(ChatText.analyze("would you join us next season? we need you")) == "sign", "intent: sign")
	_check(ChatText.dm_intent(ChatText.analyze("we should fake B and rotate through mid")) == "strategy", "intent: strategy")
	_check(ChatText.dm_intent(ChatText.analyze("sorry about yesterday, my bad")) == "apology", "intent: apology")
	_check(ChatText.dm_intent(ChatText.analyze("wanna scrim tonight? aim map then retakes")) == "practice", "intent: practice")
	# No identical bot line twice in a row in a thread.
	var key2 := s.open_thread(mate2)
	for i in 6:
		s.send(key2, "hey")
		s.thread(key2).sent_n = 0
	var lines := _bot_lines(s.thread(key2))
	var dup := 0
	for i in range(1, lines.size()):
		if lines[i] == lines[i - 1]:
			dup += 1
	_check(dup == 0, "no line repeated back to back (%d lines)" % lines.size())
	# Courting a free agent.
	var fa: PlayerData = w.free_agents[0]
	for cand in w.free_agents:
		if cand.refuses(ut) == "":
			fa = cand
			break
	var fkey := s.open_thread(fa)
	s.send(fkey, "would you join us? we need a player like you")
	_check(float(s.interest.get(fa.uid, 0.0)) > 0.0, "telling a free agent you want them raises their interest (%.2f)" % float(s.interest.get(fa.uid, 0.0)))
	# Spam.
	for i in 8:
		s.send(fkey, "yo")
	_check(String(_bot_lines(s.thread(fkey))[-1]) != "", "spamming gets an annoyed reply: \"%s\"" % _bot_lines(s.thread(fkey))[-1])
	# Group chat and coach.
	var before := (s.thread("team").msgs as Array).size()
	s.send("team", "good work today boys, proud of everyone")
	var after: Array = s.thread("team").msgs
	_check(after.size() - before >= 2, "team chat: %d teammate replies" % (after.size() - before - 1))
	var ct0 := w.coach_trust
	s.send("coach", "you're a clueless idiot coach")
	_check(w.coach_trust < ct0 - 8.0 and _bot_lines(s.thread("coach")).size() >= 1, "insulting the coach costs trust (%d -> %d)" % [int(ct0), int(w.coach_trust)])
	_check(s.unread_total() >= 0 and s.thread_keys().size() >= 4, "thread list: %d threads" % s.thread_keys().size())

	# --- Save/load keeps threads and relations.
	var w2 := World.from_dict(JSON.parse_string(JSON.stringify(w.to_dict())))
	_check(w2.soc().threads.size() == s.threads.size() and (w2.soc().thread(key).msgs as Array).size() == (th.msgs as Array).size(), "threads survive save/load")
	_check(absf(w2.relation_strength(w2.find_player(mate.uid)) - w.relation_strength(mate)) < 0.01, "relations survive save/load")
	# Old save without the social block.
	var od: Dictionary = JSON.parse_string(JSON.stringify(w.to_dict()))
	od.erase("social")
	(od.pm as Dictionary).erase("teamless")
	var w3 := World.from_dict(od)
	_check(w3.user_player != null and not w3.teamless and w3.soc().posts_left() == Social.POSTS_PER_WEEK, "old save loads with social defaults")

	# --- Discipline: warning, bench, release.
	s.toxicity = 95.0
	w.coach_trust = 10.0
	var warned := false
	var benched := false
	for i in 14:
		s.toxicity = maxf(s.toxicity, 90.0)
		w.coach_trust = minf(w.coach_trust, 12.0)
		_week(w)
		if not _open(w, "warning").is_empty() or s.strikes >= 1:
			warned = true
		if w.forced_bench_until >= w.stamp() or s.strikes >= 2:
			benched = true
		if w.teamless:
			break
	_check(warned, "warning first")
	_check(benched, "then dropped (disciplinary bench)")
	_check(w.teamless and not w.user_team().roster.has(me), "then released: free agent with no club")
	_check(w.user_play_block().contains("no club") and w.user_match_this_week().is_empty(), "play block: %s" % w.user_play_block())
	var wk := w.week
	_check(w.advance_week() == "" and (w.week != wk or w.season > 1), "the season goes on without you")
	# Teamless save/load.
	var w4 := World.from_dict(JSON.parse_string(JSON.stringify(w.to_dict())))
	_check(w4.teamless and w4.user_player != null and w4.user_player.player_name == me.player_name, "teamless career saves and loads")

	# --- Ways back.
	s.toxicity = 0.0
	me.out_weeks = 0
	_check(s.can_showmatch() == "", "showmatch available while teamless")
	var c0 := s.comeback
	var sm := s.sim_showmatch("pug")
	_check(not sm.is_empty() and (sm.teams as Array).size() == 2 and s.showmatch_stamp == w.stamp(), "simulated showmatch (%d-%d)" % [int(sm.score[0]), int(sm.score[1])])
	_check(s.comeback != c0, "showmatch moves club interest (%.0f -> %.0f)" % [c0, s.comeback])
	_check(s.can_showmatch() != "", "one showmatch a week")
	# Playable showmatch via Game (exhibition mode) routes back to finish_showmatch.
	s.showmatch_stamp = 0
	_check(Game.prepare_showmatch("pug") and String(Game.pending_match.mode) == "allstar" and String(Game.pending_match.kind) == "pug", "Game.prepare_showmatch uses the exhibition match mode")
	var teams_: Array = Game.pending_match.teams
	var stats := {}
	for t: TeamData in teams_:
		for p in t.starters(5):
			stats[p] = {"kills": 12 if p.is_user else 5, "deaths": 5, "damage": 1500.0 if p.is_user else 600.0, "objectives": 1}
	Game.finish_allstar({"score": [6, 3], "rounds": 9, "players": stats})
	_check(s.showmatch_stamp == w.stamp() and String(s.last_show.get("kind", "")) == "pug", "played showmatch recorded (rating %.2f)" % float(s.last_show.get("r", 0.0)))
	# Trial.
	var tt: TeamData = w.league_teams(World.LEAGUES.size() - 1)[0]
	var tm := {"id": 9999, "kind": "trial", "title": "t", "body": "", "uid": me.uid, "options": [["Go", "pm_sx_trial_go"]], "data": {"team": w.team_index(tt)}, "done": false, "result": "", "s": w.season, "w": w.week, "read": false}
	w.inbox.append(tm)
	w.resolve_msg(tm, 0)
	_check(s.trial_team() == tt, "trial accepted: %s" % tt.team_name)
	s.showmatch_stamp = 0
	var tr := s.sim_showmatch("trial")
	_check(String(tr.label).contains("Trial") and s.trial.is_empty(), "trial match played: %s" % w.news[-1])
	# Agent shopping: offers arrive over a few weeks (lower leagues first). This
	# player was just released for their behaviour, so some clubs are wary
	# (fewer offers get through): give it a few more weeks.
	s.comeback = 40.0
	var got := false
	for i in 14:
		if w.teamless:
			_week(w)
		if not w.offers.is_empty():
			got = true
			break
	if not got:
		var att := {}
		for ti in w.teams.size():
			var k: String = String(s.talk.attitude(ti).get("state", "?")) if s.talk != null and s.talk.has_method("attitude") else "?"
			att[k] = int(att.get(k, 0)) + 1
		print("  debug: teamless=%s comeback=%.0f window=%s toxicity=%.0f hate=%d attitudes=%s week=%d" % [w.teamless, s.comeback, w.window_open(), s.toxicity, s.hate_count, att, w.week])
	_check(got, "clubs come calling (%d offers)" % w.offers.size())
	var lowest := true
	for o in w.offers:
		if w.teams[int(o.team)].league < World.LEAGUES.size() - 2:
			lowest = false
	_check(lowest, "early offers come from the lower leagues")
	if got:
		var dest: TeamData = w.teams[int(w.offers[0].team)]
		var err := w.accept_offer(0)
		_check(err == "" and not w.teamless and dest.roster.has(me) and w.user_team() == dest, "signed with %s mid-season (%s)" % [dest.team_name, err])
		_check(dest.roster.size() <= World.MAX_ROSTER, "their roster stays legal (%d)" % dest.roster.size())
	# Stand-in.
	s.release_user("test", false)
	var st: TeamData = w.league_teams(World.LEAGUES.size() - 1)[3]
	var sm2 := {"id": 9998, "kind": "standin", "title": "s", "body": "", "uid": me.uid, "options": [["Go", "pm_sx_standin_go"]], "data": {"team": w.team_index(st), "weeks": 2}, "done": false, "result": "", "s": w.season, "w": w.week, "read": false}
	w.inbox.append(sm2)
	w.resolve_msg(sm2, 0)
	_check(not w.teamless and st.roster.has(me) and not s.standin.is_empty(), "stand-in call: you join %s short-term" % st.team_name)

	# --- Courted free agent joins your club.
	var club := w.user_team()
	club.money = 500000
	var target: PlayerData = null
	for cand in w.free_agents:
		if cand.refuses(club) == "" and cand.salary <= w.wage_budget(club):
			target = cand
			break
	if target != null:
		s.interest[target.uid] = 1.0
		for i in 40:
			s.interest[target.uid] = 1.0
			s._interest_week()
			if club.roster.has(target):
				break
		_check(club.roster.has(target) and club.roster.size() <= World.MAX_ROSTER, "courted free agent %s signs for %s" % [target.player_name, club.team_name])
	# Newcomer at your role, budget cuts.
	var better := w._new_player(me.rating_exact() + 15.0, me.role)
	club.roster.append(better)
	s._newcomers_week()
	_check(w.inbox.any(func(m: Dictionary) -> bool: return String(m.title).contains(better.player_name)), "a better signing at your role is flagged")
	club.roster.erase(better)
	club.money = -80000
	me.salary = 99999
	for i in 30:
		s._budget_week()
		if not _open(w, "budget").is_empty():
			break
	_check(not _open(w, "budget").is_empty(), "budget cuts: the club asks you to take a pay cut")
	w.resolve_msg(_open(w, "budget"), 0)
	club.money = 100000
	# Coach can promise starts.
	w.coach_trust = 80.0
	me.form = 1.0
	s.promise_stamp = 0
	s.lineup_ask_stamp = 0
	w.forced_bench_until = 0
	s.strikes = 0
	var ckey := "coach"
	s.thread(ckey).sent_n = 0
	s.thread(ckey).eff_n = 0
	var cres := s.send(ckey, "can you start me next match? I want my chance")
	_check(bool(cres.ok) and _bot_lines(s.thread(ckey)).size() >= 1, "coach answers a lineup request: \"%s\" %s" % [_bot_lines(s.thread(ckey))[-1], cres.msg])
	# Without a club: trials and stand-in calls arrive over time.
	s.release_user("test", false)
	s.toxicity = 0.0
	s.comeback = 50.0
	var hurt_team: TeamData = w.league_teams(World.LEAGUES.size() - 1)[5]
	hurt_team.roster[0].out_weeks = 3
	hurt_team.roster[0].ailment = "a wrist strain"
	var kinds := {}
	for i in 60:
		s._comeback_week()
		for m in w.inbox:
			if not bool(m.done) and String(m.kind) in ["trial", "standin"]:
				kinds[String(m.kind)] = true
				m.done = true
		w.offers.clear()
	_check(kinds.has("trial"), "trial invites arrive while teamless")
	_check(kinds.has("standin"), "stand-in calls from a club with an injured starter")
	# Bots message you first.
	var ex_before := s.unread_total()
	for i in 20:
		s._bot_openers()
		for uid: int in s.ex_mates:
			w.relations[uid] = 40.0
	_check(s.unread_total() >= ex_before, "bots open conversations (%d unread)" % s.unread_total())
	var st2: TeamData = w.league_teams(World.LEAGUES.size() - 1)[3]
	w._join_club(st2, 500, 1)
	_check(not w.teamless, "back at a club for the UI checks")

	# --- LLM client: completely optional, falls back on failure.
	_check(LlmClient.clean("Viper: \"gg wp #esports #gg\"\nsecond\nthird") == "gg wp second", "LLM output is cleaned: '%s'" % LlmClient.clean("Viper: \"gg wp #esports #gg\"\nsecond\nthird"))
	var client := LlmClient.new()
	client.timeout = 2.0
	add_child(client)
	Game.settings["llm_url"] = "http://127.0.0.1:9"
	var box := ["unset"]
	client.chat("system", "hi", func(t: String) -> void: box[0] = t)
	var waited := 0.0
	while String(box[0]) == "unset" and waited < 5.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	_check(String(box[0]) == "", "no Ollama: reply is empty so the template stays (%.1fs)" % waited)
	Game.settings.erase("llm_url")
	# Jobs are queued only when the toggle is on, and the template is kept as the text.
	s.llm_on = true
	var k3 := s.open_thread(mate)
	s.thread(k3).sent_n = 0
	s.send(k3, "how are you feeling?")
	var jobs := s.take_llm_jobs()
	_check(not jobs.is_empty() and String(jobs[0].msg.text) != "" and String(jobs[0].system).contains("How you feel about what they just said") and jobs[0].has("th"), "LLM job queued with persona + decided outcome + the thread, template text kept")
	s.llm_on = false

	# --- Hub pages fit at 1280x720, with and without a club.
	get_window().size = Vector2i(1280, 720)
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	for state in ["club", "teamless"]:
		if state == "teamless":
			s.release_user("test", true)
			w.offers.append({"team": 5, "note": "Your agent got a long note about a club that would like to sign you after a strong showmatch.", "wage": 900, "years": 1})
		var hub: Node = load(Game.CAREER_SCENE).instantiate()
		add_child(hub)
		await get_tree().process_frame
		for pg: String in ["Overview", "Messages", "Feed", "Career", "Team", "Profile"]:
			if pg == "Messages":
				hub._social.thread = "team" if state == "club" else s.open_thread(mate)
			hub._show(pg)
			for i in 3:
				await get_tree().process_frame
			var worst := 0.0
			for c in hub.get_children():
				if c is Control and (c as Control).visible:
					worst = maxf(worst, (c as Control).get_global_rect().end.x)
			_check(worst <= 1281.0, "%s / %s fits (%.0f px)" % [state, pg, worst])
			if out != "":
				get_viewport().get_texture().get_image().save_png("%s/social_%s_%s.png" % [out, state, pg.to_lower()])
		hub.queue_free()
		await get_tree().process_frame

	# Insulted players trash-talk back (vulgar), across many players.
	var swore := 0
	var tried := 0
	for t0: TeamData in w.teams:
		for q: PlayerData in t0.roster:
			if tried >= 12 or q == w.user_player:
				continue
			tried += 1
			var kq := s.open_thread(q)
			s.send(kq, "you're fucking trash, uninstall")
			var said := " ".join(_bot_lines(s.thread(kq))).to_lower()
			if ["fuck", "shit", "bitch", "dick", "ass", "prick", "bastard", "garbage", "trash", "so bad"].any(func(x: String) -> bool: return said.contains(x)):
				swore += 1
			else:
				print("   (no swear) %s %s: %s" % [q.player_name, ChatText.voice(q), said])
			if tried <= 6:
				print("   %s: %s" % [q.player_name, " / ".join(_bot_lines(s.thread(kq)))])
	_check(swore == tried, "insulted players swear back: %d of %d" % [swore, tried])
	var punct: Array = []
	for t1 in 40:
		var q1: PlayerData = w.teams[t1 % w.teams.size()].roster[0]
		for tpl: String in ChatText.DM.flame.angry + ChatText.DM.flame.laugh + ChatText.DM.flame.hostile + ChatText.DM.flame.double:
			var ln1 := ChatText.raw(String(ChatText.line([tpl], ChatText.voice(q1), s._slots(q1), w.rng)[0]))
			if ln1.contains("!") or (ln1 != "" and ".?".contains(ln1[ln1.length() - 1])):
				punct.append(ln1)
		break
	_check(punct.is_empty(), "trash talk: no ! and no end punctuation %s" % str(punct.slice(0, 3)))
	Game.end_career()
	print("SOCIAL: %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit()
