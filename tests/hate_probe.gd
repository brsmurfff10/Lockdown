extends Node
## Slurs in posts and messages are hate speech (not "hype"), and replies to
## your posts land over time instead of instantly.
##   godot --headless --path . res://tests/hate_probe.tscn -- --test
var fails := 0


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		fails += 1


func _ready() -> void:
	# Detection: spellings and leetspeak; no false alarms on normal words.
	for t in ["faggot", "you f4ggot", "FAGGOT!!", "faaaggot", "fag", "retard team", "n1gga"]:
		_check(ChatText.slur_count(t) > 0, "slur detected: %s" % ChatText.censor(t))
	for t in ["great game boys", "flag the bomb", "fragging", "nigeria vs canada", "homework", "retarget the crosshair", "spicy round"]:
		_check(ChatText.slur_count(t) == 0, "no false alarm: %s" % t)
	_check(not ChatText.censor("you faggot").contains("faggot"), "censored in the feed: %s" % ChatText.censor("you faggot"))

	Game.end_career()
	Game.create_my_player("Testee", "Rifler", "Canada")
	Game.start_career()
	var w := Game.pworld
	var s := w.soc()
	var me := w.user_player
	w.fame = 20000
	w.endorsements.append({"brand": "Test Energy", "weekly": 900})
	var fame0 := w.fame
	w.wallet = 50000
	var wallet0 := w.wallet
	var n0 := w.feed.size()
	var res := s.post("faggot", "hype")
	_check(bool(res.ok), "post handled: %s" % res.msg)
	_check(w.fame < fame0 * 0.85, "followers lost (%d -> %d)" % [fame0, w.fame])
	_check(w.endorsements.is_empty(), "sponsor dropped")
	_check(w.wallet < wallet0, "club fine (%d -> %d)" % [wallet0, w.wallet])
	_check(w.forced_bench_until > w.stamp(), "suspended")
	var positive := false
	var any_fan := false
	for i in range(n0, w.feed.size()):
		var f: Dictionary = w.feed[i]
		if String(f.kind) == "me":
			_check(not String(f.text).contains("faggot"), "your post shows censored: %s" % f.text)
		elif String(f.kind) == "fan":
			any_fan = true
			for good in ["love", "legend", "goat", "let's go", "lets go", "w post", "based"]:
				if String(f.text).to_lower().contains(good):
					positive = true
	_check(any_fan and not positive, "fans condemn it, nobody cheers")
	var later := 0
	var now := Time.get_unix_time_from_system()
	for i in range(n0, w.feed.size()):
		if float(w.feed[i].get("at", 0.0)) > now + 1.0:
			later += 1
	_check(later >= 3, "replies land over time (%d scheduled later)" % later)
	_check(not SocialView.landed(w, w.feed[w.feed.size() - 1]), "the last reply isn't shown yet")
	_check(SocialView.likes_now(w.feed[n0]) < int(w.feed[n0].likes) or int(w.feed[n0].likes) == 0, "likes climb from zero")
	# A normal post trickles too.
	var n1 := w.feed.size()
	s.post_cap_reset() if s.has_method("post_cap_reset") else null
	s.posts_used = 0
	s.post("gg boys, proud of this team", "hype")
	var sched := 0
	for i in range(n1, w.feed.size()):
		if float(w.feed[i].get("at", 0.0)) > Time.get_unix_time_from_system() + 1.0:
			sched += 1
	_check(sched >= 1, "a normal post's replies trickle in (%d later)" % sched)
	# No tone buttons: the post is read from its words.
	var mate0: PlayerData = null
	for p: PlayerData in w.user_team().roster:
		if not p.is_user:
			mate0 = p
	var rival_t: TeamData = null
	for t: TeamData in w.teams:
		if t != w.user_team() and t.league == w.user_team().league:
			rival_t = t
	for case in [["proud of the boys, what a week", "hype"], ["%s is clueless, worst player in the league" % mate0.player_name, "flame"],
			["%s we're coming for you, see you on the server" % rival_t.team_name, "callout"], ["the coach has no idea what he's doing", "coach"],
			["sorry to everyone for last week, my bad", "apology"], ["to all the haters in my comments: keep crying", "haters"],
			["nice weather today", "neutral"]]:
		var a := ChatText.analyze(case[0])
		var got := s._infer_tone(a, s._post_target(case[0], a))
		_check(got == case[1], "read '%s' as %s (expected %s)" % [case[0], got, case[1]])
	# A DM with a slur: they go off on you (no block, no leak).
	var mate: PlayerData = null
	for p: PlayerData in w.user_team().roster:
		if not p.is_user:
			mate = p
	var key := "p:%d" % mate.uid
	var r2 := s.send(key, "shut up you f4ggot")
	_check(String(r2.get("intent", "")) == "hate", "DM read as hate speech: %s" % r2.msg)
	var th := s.thread(key)
	var said: Array = th.msgs.filter(func(m: Dictionary) -> bool: return not bool(m.me)).map(func(m: Dictionary) -> String: return String(m.text))
	print("   they said: %s" % " / ".join(said))
	_check(said.size() >= 2, "they cuss you out back (%d lines)" % said.size())
	_check(" ".join(said).to_lower().find("block") < 0 and " ".join(said).to_lower().find("screenshot") < 0, "no block / screenshot talk")
	var r3 := s.send(key, "hey")
	_check(bool(r3.ok), "not blocked, you can keep messaging: %s" % r3.msg)
	_check(w.relation_strength(mate) < -0.5, "relationship wrecked (%.2f)" % w.relation_strength(mate))
	print("hate_probe: %d failure(s)" % fails)
	Game.end_career()
	get_tree().quit()
