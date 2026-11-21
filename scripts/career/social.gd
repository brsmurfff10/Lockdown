class_name Social
extends RefCounted
## My Player's social life and club standing: your own posts on the feed, DMs
## and the team group chat, friends and rivals, discipline (warnings, the
## bench, getting cut) and the ways back (showmatches, trials, your agent,
## stand-in calls). Owned by World (World.soc()); saved inside the world save.
## Text comes from ChatText; every effect is decided here.

const POSTS_PER_WEEK := 3
const POST_MULT := [1.0, 0.6, 0.35] ## Gains from the 1st, 2nd and 3rd post of a week.
const DM_EFFECTS := 2 ## Messages per thread per week that still move relations.
const TEAM_EFFECTS := 3
const THREAD_CAP := 40
const MAX_THREADS := 30
const FRIEND_AT := 0.35
const RIVAL_AT := -0.35
const TONES := {"hype": "Hype team", "callout": "Call out rival", "flame": "Flame teammate", "coach": "Blame coach",
	"haters": "Fire back at haters", "apology": "Apologise", "neutral": "Neutral"}
const TONE_BASE := {"hype": 0.0, "callout": 0.3, "flame": 0.35, "coach": 0.3, "haters": 0.2, "apology": 0.0, "neutral": 0.0}

## The owning World, held weakly (World keeps us: a strong ref both ways would
## never be freed, leaking a whole career every time one is loaded).
var _wref: WeakRef
var w: World:
	get:
		return _wref.get_ref() as World if _wref != null else null
var threads := {} ## key ("team", "coach", "p:<uid>") -> thread (see _new_thread)
var seq := 1 ## Ordering for threads (last activity).
var posts_stamp := 0
var posts_used := 0
var toxicity := 0.0 ## 0-100: how toxic you've been lately (decays weekly).
var strikes := 0 ## Discipline: 0 clean, 1 warned, 2 benched (next: released).
var hate_count := 0 ## Times you've used a slur (posts or messages that got out).
var _trickle := -1.0 ## While handling your post: seconds after it that the next reply lands (-1 = not trickling).
var heat := 0.0 ## Discipline pressure; builds from reasons each week, decays.
var heat_notes: Array = [] ## Reasons that built heat since the last check.
var strike_stamp := 0
var clean_weeks := 0
var weeks_together := {} ## uid -> weeks as your teammate
var ex_mates := {} ## uid -> club you shared
var team_beef := {} ## team index -> weeks left of a club rivalry
var interest := {} ## uid -> 0..1: players you've courted (want to join your club)
var club_interest := {} ## team index -> 0..1: clubs you've asked to join
var comeback := 0.0 ## 0-100: clubs' interest in you while you're without a club
var weeks_teamless := 0
var showmatch_stamp := 0
var last_show := {} ## {kind, score, r}
var trial := {} ## {team, until}: an accepted trial
var standin := {} ## {team, until, start}: a short-term stand-in deal
var known_mates := {} ## uids seen at your club (to spot new signings)
var last_flamed := 0 ## uid of the last player you went after (apologies land on them)
var apology_stamp := 0
var promise_stamp := 0
var lineup_ask_stamp := 0
var last_ctx := {} ## Your last match: {opp, opp_idx, res, score, r}
var feed_recent: Array = [] ## Recently used feed templates.
var llm_on := false ## Set by the hub from Settings (transient).
var llm_jobs: Array = [] ## Transient: {msg, system, user} for the local LLM.
var _post_text := "" ## Transient: the post being answered (LLM context).


func _init(world: World) -> void:
	_wref = weakref(world)
	talk = ClubTalk.new(self)


var talk: ClubTalk ## Where conversations lead: coach decisions, other clubs, attitudes (see ClubTalk).
var live := false ## Transient: a hub is open (unprompted messages get delivery times).
var _unprompted := false ## Transient: inside ClubTalk.deliver().


# =============================================================================
# Friends and rivals
# =============================================================================

## -1..1: negative = rival, positive = friend. Built from World.relations plus
## head-to-head rivalries (World.rivals).
func strength(p: PlayerData) -> float:
	if p == null or w.user_player == null or p.is_user or p.uid == w.user_player.uid:
		return 0.0
	var v := w.relation(p.uid) / 100.0
	if w.rivals.has(p.uid):
		var e: Dictionary = w.rivals[p.uid]
		var met := int(e.get("w", 0)) + int(e.get("l", 0))
		if met >= 2:
			var r := minf(0.12 + 0.05 * float(met - 2), 0.4)
			if _is_mate(p):
				r *= 0.5
			v -= r
	var top := w.top_rival()
	if not top.is_empty() and int(top.uid) == p.uid:
		v -= 0.15
	return clampf(v, -1.0, 1.0)


func kind(p: PlayerData) -> String:
	var s := strength(p)
	if s >= FRIEND_AT:
		return "friend"
	if s <= RIVAL_AT:
		return "rival"
	return ""


func team_rivalry(t: TeamData) -> bool:
	if t == null or w.teams.is_empty():
		return false
	var idx := w.team_index(t)
	if idx < 0:
		return false
	var ut := w.user_team()
	if t == ut and not w.teamless:
		return false
	if idx == w.trash_target or int(team_beef.get(idx, 0)) > 0:
		return true
	if not w.teamless and w.derby_rival(ut) == t:
		return true
	var top := w.top_rival()
	if not top.is_empty():
		var rp := w.find_player(int(top.uid))
		if rp != null and t.roster.has(rp):
			return true
	return false


func _is_mate(p: PlayerData) -> bool:
	return not w.teamless and w.user_player != null and w.user_team().roster.has(p)


func mates() -> Array:
	if w.teamless or w.user_player == null:
		return []
	return w.user_team().roster.filter(func(s: PlayerData) -> bool: return not s.is_user)


func friends() -> Array:
	var out: Array = []
	for uid: int in w.relations:
		var p := w.find_player(uid)
		if p != null and kind(p) == "friend":
			out.append(p)
	return out


## Teammates first, then friends, rivals and ex-teammates: who you know.
func contacts() -> Array:
	var out: Array = mates()
	for uid: int in w.relations:
		var p := w.find_player(uid)
		if p != null and not out.has(p) and absf(strength(p)) >= 0.15:
			out.append(p)
	for uid in w.rivals:
		var rp := w.find_player(int(uid))
		if rp != null and not out.has(rp):
			out.append(rp)
	return out


func relation_label(p: PlayerData) -> String:
	var k := kind(p)
	if k == "friend":
		return "Friend"
	if k == "rival":
		return "Rival"
	return World.relation_text(w.relation(p.uid))


## In-game leader of a club: a Leader persona, else the best decision-maker.
func igl_of(t: TeamData) -> PlayerData:
	var best: PlayerData = null
	for p in t.starters(5):
		if p.is_user:
			continue
		if PlayerData.persona_of(p) == "Leader":
			return p
		if best == null or p.stat("decision") > best.stat("decision"):
			best = p
	return best


func coach_name(t: TeamData) -> String:
	if t == null:
		return "Coach"
	var h := absi(hash(t.team_name + "/coach"))
	return "%s %s" % [World.STAFF_FIRST[h % World.STAFF_FIRST.size()], World.STAFF_LAST[(h / 7) % World.STAFF_LAST.size()]]


# =============================================================================
# Weekly
# =============================================================================

func weekly() -> void:
	var me := w.user_player
	if me == null or w.retired:
		return
	talk.week_trained = talk.week_trained or w.trained_this_week
	toxicity = maxf(0.0, toxicity * 0.88 - 1.0)
	for k in team_beef.keys():
		team_beef[k] = int(team_beef[k]) - 1
		if int(team_beef[k]) <= 0:
			team_beef.erase(k)
	_relations_week()
	if w.teamless:
		_comeback_week()
	else:
		weeks_teamless = 0
		_standin_week()
		if not w.teamless:
			_newcomers_week()
			_budget_week()
			_discipline_week()
			_interest_week()
	_bot_openers()


func _relations_week() -> void:
	var cur := mates()
	var streak := 0 if w.teamless else w.user_team().streak
	for p: PlayerData in cur:
		weeks_together[p.uid] = int(weeks_together.get(p.uid, 0)) + 1
		var v := w.relation(p.uid)
		if v < 40.0:
			w._relate(p.uid, 1.5 + (0.5 if streak > 0 else 0.0))
		ex_mates.erase(p.uid)
	for uid: int in w.relations.keys():
		var p := w.find_player(uid)
		if p != null and cur.has(p):
			continue
		var v := w.relation(uid)
		var keep := 0.99 if v < -20.0 else 0.97
		w.relations[uid] = v * keep
		if absf(float(w.relations[uid])) < 1.0:
			w.relations.erase(uid)


## Newcomers at your club: a better player at your role is a threat.
func _newcomers_week() -> void:
	var me := w.user_player
	var ut := w.user_team()
	var first := known_mates.is_empty()
	for p in ut.roster:
		if p.is_user or known_mates.has(p.uid):
			continue
		known_mates[p.uid] = true
		if first:
			continue
		if p.role == me.role and p.rating_exact() > me.rating_exact() + 3.0:
			w._trust(-3.0)
			_heat(0.6, "the club signed %s, a better %s" % [p.player_name, p.role])
			w._msg("info", "%s have signed %s" % [ut.team_name, p.player_name],
				"%s (RTG %d) is a %s, like you, and rated higher. Your place in the five is under threat: form and the coach's trust decide who starts." % [p.player_name, p.rating(), p.role],
				[["OK", "ok"]], p.uid)
	for uid: int in known_mates.keys():
		var q := w.find_player(uid)
		if q == null or not ut.roster.has(q):
			known_mates.erase(uid)


## A club in the red looks at its wage bill (you included).
func _budget_week() -> void:
	var me := w.user_player
	var ut := w.user_team()
	if ut.money > -20000 or w._has_open_kind("budget") or w.rng.randf() > 0.3:
		return
	var wages: Array = ut.roster.map(func(p: PlayerData) -> int: return p.salary)
	wages.sort()
	var median: int = wages[wages.size() / 2] if not wages.is_empty() else 0
	if me.salary < int(median * 1.1):
		return
	w._msg("budget", "Budget cuts at %s" % ut.team_name,
		"The club is $%s in the red and wants to cut your wage by 20%% (to $%s/wk). If you refuse, they may let you go." % [World._fmt(-ut.money), World._fmt(int(me.salary * 0.8 / 50.0) * 50)],
		[["Take the pay cut", "pm_sx_cut_ok"], ["Refuse", "pm_sx_cut_no"]], me.uid)


func _heat(d: float, why: String) -> void:
	heat += d
	if why != "" and not heat_notes.has(why):
		heat_notes.append(why)


## Warnings first, then the bench, then release.
func _discipline_week() -> void:
	var me := w.user_player
	var ut := w.user_team()
	var reasons: Array = heat_notes.duplicate()
	heat_notes.clear()
	var pressure := 0.0
	var recent: Array = []
	for i in range(me.match_log.size() - 1, -1, -1):
		var e: Dictionary = me.match_log[i]
		if int(e.s) != w.season or recent.size() >= 4:
			break
		recent.append(float(e.r))
	if recent.size() >= 4 and w.coach_trust < 50.0:
		var avg := 0.0
		for r: float in recent:
			avg += r
		avg /= recent.size()
		if avg < 0.8:
			pressure += (0.8 - avg) * 4.0 * (0.6 if me.age <= 20 else 1.0)
			reasons.append("your form (%.2f over your last %d matches)" % [avg, recent.size()])
	if toxicity > 40.0:
		pressure += 0.8 + (toxicity - 40.0) / 40.0
		reasons.append("your behaviour online")
	if w.coach_trust < 25.0:
		pressure += 1.0
		reasons.append("your relationship with the coach")
	if me.morale < 25.0:
		pressure += 0.6
		reasons.append("your attitude (you look miserable)")
	if me.bench_weeks >= 6 and w.coach_trust < 35.0:
		pressure += 1.0
		reasons.append("you're not making the team (%d weeks on the bench)" % me.bench_weeks)
	if w.transfer_request and w.coach_trust < 45.0:
		pressure += 0.5
		reasons.append("you've asked to leave")
	heat = heat * 0.7 + pressure
	# Key players get more rope.
	var by_rating := ut.roster.duplicate()
	by_rating.sort_custom(func(a: PlayerData, b: PlayerData) -> bool: return a.rating_exact() > b.rating_exact())
	var rope := 1.5 if by_rating.find(me) in [0, 1] else 0.0
	if pressure <= 0.01 and heat < 1.0:
		clean_weeks += 1
		if clean_weeks >= 6 and strikes > 0:
			strikes -= 1
			clean_weeks = 0
			w._news("Your slate is a little cleaner: the club has eased off (warnings %d)." % strikes)
		return
	clean_weeks = 0
	if w.stamp() - strike_stamp < 2:
		return
	var why := _reasons_text(reasons)
	if strikes == 0 and heat >= 2.5 + rope:
		strikes = 1
		strike_stamp = w.stamp()
		w._trust(-2.0)
		w._msg("warning", "Warning from %s" % ut.team_name,
			"The coach has had enough of %s. \"This is your warning. Sort it out or you'll lose your place.\"" % why,
			[["Promise to improve", "pm_sx_warn_ok"], ["Ask what you can fix", "pm_sx_warn_talk"], ["Tell them where to go", "pm_sx_warn_push"]], me.uid)
		w._news("WARNING: %s have warned you about %s." % [ut.team_name, why])
	elif strikes == 1 and heat >= 3.5 + rope:
		strikes = 2
		strike_stamp = w.stamp()
		w.forced_bench_until = w.stamp() + 2
		talk.followups.append({"due": w.stamp() + 1, "kind": "mate_checkin"})
		w._apply_coach()
		w._msg("bench", "Dropped: disciplinary", "%s have dropped you for the next two weeks because of %s. One more strike and you're out." % [ut.team_name, why],
			[["Accept it", "pm_sx_bench_ok"], ["Go public about it", "pm_sx_bench_public"], ["Request a transfer", "pm_request"]], me.uid)
		w._news("DROPPED: %s bench you over %s." % [ut.team_name, why])
		w._toxic("benched")
	elif strikes >= 2 and heat >= 4.2 + rope and w.forced_bench_until < w.stamp() and w.stamp() - strike_stamp >= 3:
		release_user(why)


static func _reasons_text(reasons: Array) -> String:
	if reasons.is_empty():
		return "your attitude"
	var uniq: Array = []
	for r: String in reasons:
		if not uniq.has(r):
			uniq.append(r)
	if uniq.size() == 1:
		return uniq[0]
	return ", ".join(uniq.slice(0, uniq.size() - 1)) + " and " + String(uniq[uniq.size() - 1])


## Mid-season release: you leave the club and become a free agent with no team.
func release_user(why: String, bad_terms: bool = true) -> void:
	var me := w.user_player
	if me == null or w.teamless or w.retired:
		return
	var t := w.user_team()
	var idx := w.team_index(t)
	var severance := me.salary * (2 if me.contract_until > w.season or w.week < 20 else 1)
	w.wallet += severance
	on_club_change(t, null, bad_terms)
	t.roster.erase(me)
	w._refill_roster(t)
	t.sort_roster()
	w.teamless = true
	w.user_team_idx = idx
	me.salary = 0
	me.bench_weeks = 0
	me.promise_until = 0
	w.forced_bench_until = 0
	w.transfer_request = false
	w.offers.clear()
	w.renewal_done = false
	w.coach_trust = 50.0
	strikes = 0
	heat = 0.0
	heat_notes.clear()
	standin = {}
	if bad_terms:
		team_beef[idx] = 16
		talk.left_bad[idx] = true
	comeback = clampf(25.0 + (me.rating_exact() - t.rating_exact()) * 1.5 + minf(15.0, float(w.fame) / 4000.0) - toxicity * 0.4, 5.0, 70.0)
	weeks_teamless = 0
	for g in w.goals:
		if String(g.status) == "open" and String(g.kind) in ["promotion", "playoffs", "survive", "top", "trophy"]:
			g.status = "failed"
	for m in w.inbox:
		if not bool(m.done) and String(m.kind) in ["bench", "contract", "sold", "role", "teammate", "dressing", "warning", "budget", "media"]:
			m.done = true
			m.result = "You've left the club."
	w._news("RELEASED: %s have let you go%s. You're a free agent with no club." % [t.team_name, (" (%s)" % why) if why != "" else ""])
	w._wire("%s release %s" % [t.team_name, me.player_name], "bad")
	w._post(World.OUTLET_HANDLES.pick_random(), "%s and %s part ways mid-season." % [t.team_name, me.player_name], "press", 2.0)
	var sl := _slots(null)
	sl.oldteam = t.team_name
	_feed_lines("released_fan", 1, sl, "fan")
	_feed_lines("released_toxic", 1, sl, "toxic")
	w._msg("released", "%s have released you" % t.team_name,
		"Because of %s, %s have terminated your contract (severance $%s). You're a free agent with no club. Ways back: play showmatches (Career) to impress scouts, accept trials, let your agent shop you around (lower leagues first), and answer stand-in calls. Your recent behaviour decides who calls." % [why if why != "" else "a decision by the club", t.team_name, World._fmt(severance)],
		[["OK", "ok"]], me.uid)
	for f: PlayerData in friends():
		if w.rng.randf() < 0.5:
			_opener(f, "released")
			break


## You left `from` (for `dest`, or for no club). Ex-teammates remember how it ended.
func on_club_change(from: TeamData, dest: TeamData, bad_terms: bool = false) -> void:
	if from != null:
		for p in from.roster:
			if p.is_user:
				continue
			ex_mates[p.uid] = from.team_name
			if w.relation(p.uid) <= -20.0 or (bad_terms and w.relation(p.uid) < 10.0):
				w._relate(p.uid, -10.0)
	threads.erase("team")
	threads.erase("coach")
	known_mates.clear()
	if dest != null:
		for p in dest.roster:
			if not p.is_user:
				known_mates[p.uid] = true
				ex_mates.erase(p.uid)
				interest.erase(p.uid)


# =============================================================================
# Without a club: showmatches, trials, your agent, stand-in calls
# =============================================================================

func _comeback_week() -> void:
	var me := w.user_player
	weeks_teamless += 1
	var base := 15.0 + clampf((me.rating_exact() - 50.0) * 0.6, -10.0, 25.0) + minf(15.0, float(w.fame) / 4000.0)
	comeback += (base - comeback) * 0.08
	comeback = clampf(comeback - toxicity * 0.05, 0.0, 100.0)
	me.morale = clampf(me.morale + (62.0 - me.morale) * 0.04 - 0.5, 0.0, 100.0)
	if not me.available():
		return
	var mult := clampf(1.0 - toxicity / 140.0, 0.15, 1.0)
	var ag := w.agent_info()
	var chance := (0.16 + comeback / 260.0 + float(ag.offers) * 0.25) * mult
	if w.agent == "none":
		chance *= 0.6
	if w.offers.size() < 3 and w.rng.randf() < chance:
		var t := _shop_club(0)
		if t != null:
			var wage := int(w.offer_wage(t) * 0.85 / 50.0) * 50
			var who := "Your agent" if w.agent != "none" else "You"
			var note := "%s got %s (%s) interested." % [who, t.team_name, World.LEAGUES[t.league].short]
			w.offers.append({"team": w.team_index(t), "note": note, "wage": wage, "years": w.rng.randi_range(1, 2)})
			w._news("OFFER: %s want to sign you (Career)." % t.team_name)
	if trial.is_empty() and not w._has_open_kind("trial") and w.rng.randf() < (0.12 + comeback / 300.0) * mult:
		var tt := _shop_club(1)
		if tt != null:
			w._msg("trial", "Trial invite: %s" % tt.team_name,
				"%s (%s, RTG %d) invite you for a trial week. Play their practice match (Career page): a good performance earns a contract offer." % [tt.team_name, World.LEAGUES[tt.league].name, tt.rating()],
				[["Accept the trial", "pm_sx_trial_go"], ["Decline", "pm_sx_trial_no"]], me.uid, {"team": w.team_index(tt)})
	if not w._has_open_kind("standin") and standin.is_empty() and w.rng.randf() < 0.3 * mult:
		var lowest := World.LEAGUES.size() - 1
		var top := clampi(_reach() - 1, 0, lowest)
		var cands: Array = []
		for i in w.teams.size():
			var t: TeamData = w.teams[i]
			if t.league < top or int(team_beef.get(i, 0)) > 0:
				continue
			for p in t.roster.slice(0, 5):
				if not p.available() and p.out_weeks >= 1:
					cands.append([i, p])
					break
		if not cands.is_empty():
			var pick: Array = cands[w.rng.randi() % cands.size()]
			var st: TeamData = w.teams[int(pick[0])]
			var hurt: PlayerData = pick[1]
			var weeks := clampi(hurt.out_weeks + 1, 2, 4)
			w._msg("standin", "%s need a stand-in" % st.team_name,
				"%s is out with %s. %s (%s) want you in as a stand-in for %d weeks on a short deal. Impress and it could become permanent." % [hurt.player_name, hurt.ailment, st.team_name, World.LEAGUES[st.league].short, weeks],
				[["Accept", "pm_sx_standin_go"], ["Decline", "pm_sx_standin_no"]], me.uid, {"team": int(pick[0]), "weeks": weeks})


## Highest league that would take you now (index; lower = better).
func _reach() -> int:
	var lowest := World.LEAGUES.size() - 1
	var ag := w.agent_info()
	return clampi(lowest - int(comeback / 28.0) - (1 if int(ag.reach) >= 6 else 0), 0, lowest)


## A club for your agent to pitch you to: lower leagues first, better ones as
## interest grows. up: tiers above your current reach (trials aim higher).
func _shop_club(up: int) -> TeamData:
	var me := w.user_player
	var lowest := World.LEAGUES.size() - 1
	var top := clampi(_reach() - up, 0, lowest)
	var cap := me.rating_exact() + 6.0 + float(w.agent_info().reach) + comeback / 10.0
	var pool: Array = []
	var weights: Array = []
	for i in w.teams.size():
		var t: TeamData = w.teams[i]
		if t.league < top or int(team_beef.get(i, 0)) > 0 or t.rating_exact() > cap or String(talk.attitude(i).label) == "won't sign":
			continue
		if w.offers.any(func(o: Dictionary) -> bool: return int(o.team) == i):
			continue
		pool.append(t)
		var wt := (0.4 if String(talk.attitude(i).label) == "wary" else 1.0) * (1.0 + float(t.league - top) * (1.5 if comeback < 40.0 else 0.5) + float(club_interest.get(i, 0.0)) * 4.0)
		weights.append(wt)
	if pool.is_empty():
		return null
	var total := 0.0
	for x: float in weights:
		total += x
	var roll := w.rng.randf() * total
	for k in pool.size():
		roll -= float(weights[k])
		if roll <= 0.0:
			return pool[k]
	return pool[pool.size() - 1]


func _standin_week() -> void:
	if standin.is_empty():
		return
	var me := w.user_player
	var t: TeamData = w.teams[int(standin.team)]
	if not t.roster.has(me):
		standin = {}
		return
	if w.stamp() < int(standin.until):
		return
	var start := int(standin.start)
	var sum := 0.0
	var n := 0
	for e in me.match_log:
		if int(e.s) * 100 + int(e.w) >= start:
			sum += float(e.r)
			n += 1
	var avg := sum / n if n > 0 else 0.0
	standin = {}
	if (n > 0 and avg >= 1.0) or w.coach_trust >= 62.0:
		me.contract_until = w.season + (1 if w.week > 12 else 0)
		me.salary = maxi(me.salary, int(w.offer_wage(t) * 0.95 / 50.0) * 50)
		w._news("STAND-IN: %s keep you on a proper contract (to the end of season %d)." % [t.team_name, me.contract_until])
		w._msg("contract", "%s want to keep you" % t.team_name, "Your stand-in spell went well (%s). They've signed you to the end of season %d at $%s/wk." % [("%.2f average" % avg) if n > 0 else "the coach liked what he saw", me.contract_until, World._fmt(me.salary)], [["Great", "ok"]], me.uid)
	else:
		release_user("the stand-in spell is over", false)


func can_showmatch() -> String:
	var me := w.user_player
	if me == null or w.retired:
		return "Career over"
	if not me.available():
		return "You're injured"
	if showmatch_stamp == w.stamp():
		return "One showmatch a week"
	if not w.teamless and w.user_starting():
		return "You're in the starting five: showmatches are for when you're out of the team"
	return ""


func trial_team() -> TeamData:
	if trial.is_empty():
		return null
	if w.stamp() > int(trial.until):
		trial = {}
		return null
	return w.teams[int(trial.team)]


## Throwaway copies for an exhibition (doesn't count): kind "pug" or "trial".
func showmatch_teams(kind_: String) -> Array:
	var me := w.user_player
	var level := me.rating_exact()
	var used := {}
	var mine := TeamData.new()
	var opp := TeamData.new()
	var you := _copy(me)
	you.match_mod = me.form * 0.6
	mine.roster.append(you)
	used[me.uid] = true
	var tt: TeamData = trial_team() if kind_ == "trial" else null
	if tt != null:
		for p in tt.starters(5):
			if mine.roster.size() >= 5:
				break
			if not p.is_user:
				mine.roster.append(_copy(p))
				used[p.uid] = true
		var others: Array = w.league_teams(tt.league).filter(func(t: TeamData) -> bool: return t != tt)
		var ot: TeamData = others[w.rng.randi() % others.size()]
		for p in ot.starters(5):
			opp.roster.append(_copy(p))
		mine.team_name = "%s (trial)" % tt.team_name
		mine.short_name = tt.short_name
		mine.color = tt.color
		opp.team_name = ot.team_name
		opp.short_name = ot.short_name
		opp.color = ot.color
	else:
		var pool: Array = w.free_agents.duplicate()
		for t in w.teams:
			if absf(t.rating_exact() - level) < 12.0:
				pool.append_array(t.roster)
		pool = pool.filter(func(p: PlayerData) -> bool: return not p.is_user and absf(p.rating_exact() - level) < 10.0)
		pool.shuffle()
		for p: PlayerData in pool:
			if used.has(p.uid):
				continue
			used[p.uid] = true
			if mine.roster.size() < 5:
				mine.roster.append(_copy(p))
			elif opp.roster.size() < 5:
				opp.roster.append(_copy(p))
			else:
				break
		mine.team_name = "Team %s" % me.player_name
		mine.short_name = "PUG"
		mine.color = Color("38d0ff")
		var cap: String = opp.roster[0].player_name if not opp.roster.is_empty() else "Mix"
		opp.team_name = "Team %s" % cap
		opp.short_name = "MIX"
		opp.color = Color("ff7f2e")
	while mine.roster.size() < 5:
		mine.roster.append(w._new_player(level, ""))
	while opp.roster.size() < 5:
		opp.roster.append(w._new_player(level, ""))
	mine.sort_roster()
	opp.sort_roster()
	return [mine, opp]


func _copy(p: PlayerData) -> PlayerData:
	var cp := PlayerData.from_dict(p.to_dict())
	cp.is_user = p.is_user
	cp.match_mod = 0.0
	return cp


## Simulated showmatch: your line depends on your stats and form.
func sim_showmatch(kind_: String) -> Dictionary:
	var sides := showmatch_teams(kind_)
	var a: TeamData = sides[0]
	var b: TeamData = sides[1]
	var pa := 1.0 / (1.0 + exp(-((a.rating_exact() + w.user_player.form * 0.12) - b.rating_exact()) / 14.0))
	var s := [0, 0]
	var order: Array = []
	while s[0] < World.ROUNDS_TO_WIN and s[1] < World.ROUNDS_TO_WIN and order.size() < World.MAX_ROUNDS:
		var wn := 0 if w.rng.randf() < pa else 1
		s[wn] += 1
		order.append(wn)
	var lineups := [a.starters(5), b.starters(5)]
	var box := w.sim_box_score(lineups, order)
	var rows := [[], []]
	var mvp := ""
	var best := -1.0
	var mine := 1.0
	for t in 2:
		for pl: PlayerData in lineups[t]:
			var st: Dictionary = box[pl]
			var mr := Progression.match_rating(st.kills, st.deaths, order.size(), st.objectives, st.damage)
			if mr > best:
				best = mr
				mvp = pl.player_name
			if pl.is_user:
				mine = mr
			rows[t].append({"name": pl.player_name, "rating": pl.rating(), "kills": st.kills, "deaths": st.deaths,
				"adr": int(st.damage / maxi(1, order.size())), "match_rating": mr, "is_user": pl.is_user, "change": null})
		rows[t].sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.match_rating > y.match_rating)
	finish_showmatch(s, mine, kind_)
	var label := "Trial match (simulated)" if kind_ == "trial" else "Showmatch (simulated)"
	return {"teams": [a, b], "score": s, "rows": rows, "mvp": mvp, "label": label, "perspective": true, "map": ""}


## After a showmatch or trial match (played or simulated). Returns a summary.
func finish_showmatch(score: Array, r: float, kind_: String) -> String:
	var me := w.user_player
	showmatch_stamp = w.stamp()
	var won: bool = int(score[0]) > int(score[1])
	var gain := (r - 0.9) * 30.0 * (1.0 - toxicity / 200.0) + (4.0 if won else 0.0)
	var out := ""
	if w.teamless:
		comeback = clampf(comeback + gain, 0.0, 100.0)
		out = "Scouts noticed: club interest %d/100." % int(comeback)
	else:
		w._trust(clampf((r - 1.0) * 6.0, -3.0, 4.0))
		me.form = clampf(me.form + (r - 1.0) * 1.5, -8.0, 8.0)
		out = "The coach was watching (trust %d)." % int(w.coach_trust)
	w._gain_fame(int(maxf(0.0, (r - 0.8) * 300.0)))
	last_show = {"kind": kind_, "score": [int(score[0]), int(score[1])], "r": snappedf(r, 0.01), "s": w.season, "w": w.week}
	w._news("%s: %s %d-%d (you: %.2f rating). %s" % ["TRIAL" if kind_ == "trial" else "SHOWMATCH", "won" if won else "lost", int(score[0]), int(score[1]), r, out])
	if r >= 1.25:
		w._post("@PugWatch", "%s drops a %.2f rating in a %s. Someone sign them." % [me.player_name, r, "trial match" if kind_ == "trial" else "showmatch"], "press", 1.2)
	if kind_ == "trial":
		var tt := trial_team()
		trial = {}
		if tt != null:
			var need := clampf(1.0 + (tt.rating_exact() - me.rating_exact()) / 60.0, 0.85, 1.25) + toxicity / 250.0
			if r >= need or (won and r >= need - 0.1):
				var idx := w.team_index(tt)
				w.offers = w.offers.filter(func(o: Dictionary) -> bool: return int(o.team) != idx)
				w.offers.append({"team": idx, "note": "Trial passed (%.2f): %s want you." % [r, tt.team_name], "wage": int(w.offer_wage(tt) * 0.9 / 50.0) * 50, "years": w.rng.randi_range(1, 2)})
				club_interest[idx] = 1.0
				out = "Trial passed! %s have made you an offer (Career)." % tt.team_name
				w._news("TRIAL PASSED: %s offer you a contract." % tt.team_name)
			else:
				out = "%s passed on you (needed about %.2f)." % [tt.team_name, need]
				w._news("TRIAL: %s won't offer you a deal." % tt.team_name)
	last_show["note"] = out
	return out


# =============================================================================
# Courting players and clubs
# =============================================================================

func _interest_week() -> void:
	var ut := w.user_team()
	for uid: int in interest.keys():
		var p := w.find_player(uid)
		var v := float(interest[uid]) * 0.9
		interest[uid] = v
		if p == null or v < 0.08 or ut.roster.has(p):
			interest.erase(uid)
			continue
		if p.refuses(ut) != "":
			continue
		if w.free_agents.has(p):
			if v >= 0.4 and w.rng.randf() < v * 0.3 and ut.money > w.signing_fee(p) / 2 and p.salary <= w.wage_budget(ut) * 1.2:
				w.free_agents.erase(p)
				p.contract_until = w.season + 1
				p.joined = w.stamp()
				ut.roster.append(p)
				w._trim_roster(ut, p)
				known_mates[p.uid] = true
				interest.erase(uid)
				w._relate(p.uid, 10.0)
				w._news("SIGNING: %s join %s after your messages." % [p.player_name, ut.team_name])
				w._wire("%s sign free agent %s" % [ut.team_name, p.player_name], "deal")
				_opener(p, "joined")
		elif w.window_open() and v >= 0.6 and w.rng.randf() < v * 0.12:
			var from := w.owner_of(p)
			if from == null or from == ut:
				continue
			var price := int(p.market_value() * 0.85)
			if ut.money >= price and from.roster.size() > World.MIN_ROSTER and ut.league <= from.league + 1:
				from.roster.erase(p)
				ut.roster.append(p)
				p.joined = w.stamp()
				ut.money -= price
				from.money += price
				w._note_transfer(p, from, ut, price)
				w._trim_roster(ut, p)
				w._refill_roster(from)
				known_mates[p.uid] = true
				interest.erase(uid)
				w._relate(p.uid, 10.0)
				w._news("TRANSFER: %s pushed for a move and joined %s from %s ($%s)." % [p.player_name, ut.team_name, from.team_name, World._fmt(price)])
				w._wire("%s force a move to %s" % [p.player_name, ut.team_name], "deal")
				_opener(p, "joined")
			else:
				interest[uid] = v * 0.5
				w._wire("%s (%s) linked with a move to %s" % [p.player_name, from.short_name, ut.team_name], "info")
	for k: int in club_interest.keys():
		club_interest[k] = float(club_interest[k]) * 0.92
		if float(club_interest[k]) < 0.05:
			club_interest.erase(k)


## Extra pull from clubs you've asked to join (used by World._transfer_interest).
func club_pull(idx: int) -> float:
	return float(club_interest.get(idx, 0.0))


# =============================================================================
# After your matches
# =============================================================================

func after_match(r: float, won: bool, opp: TeamData, label: String) -> void:
	var sc: Array = w.last_report.get("score", [0, 0])
	last_ctx = {"opp": opp.team_name, "opp_idx": w.team_index(opp), "res": "win" if won else "loss",
		"score": "%d-%d" % [int(sc[0]), int(sc[1])], "r": snappedf(r, 0.01), "s": w.season, "w": w.week}
	if label.contains("Final"):
		team_beef[w.team_index(opp)] = maxi(int(team_beef.get(w.team_index(opp), 0)), 12)
	var cur := mates()
	for p: PlayerData in cur:
		if won:
			w._relate(p.uid, 0.5)
	# Friends and mentors message you after big games.
	if r >= 1.4 or r <= 0.6:
		var fr: Array = cur.filter(func(p: PlayerData) -> bool: return w.relation(p.uid) >= 15.0 or ChatText.voice(p) == "mentor")
		if not fr.is_empty() and w.rng.randf() < 0.55:
			_opener(fr[w.rng.randi() % fr.size()], "big_game" if r >= 1.4 else "bad_game")
	# The group chat after the match.
	if not cur.is_empty() and w.rng.randf() < 0.5:
		var th := thread("team")
		var who: PlayerData = cur[w.rng.randi() % cur.size()]
		var ln: Array = ChatText.line(ChatText.OPEN["after_win" if won else "after_loss"], ChatText.voice(who), _slots(who), w.rng, th.recent)
		_bot_say(th, who, ln, "after_win" if won else "after_loss", "")
	# Rivals.
	for p in opp.roster:
		if kind(p) == "rival" and w.rng.randf() < 0.4:
			_opener(p, "rival_respect" if won and r >= 1.15 else ("rival_taunt" if not won else "rival_respect"))
			break


func _bot_openers() -> void:
	var me := w.user_player
	var sent := 0
	if not w.teamless and not w.user_starting() and me.available() and w.rng.randf() < 0.35:
		var fr: Array = mates().filter(func(p: PlayerData) -> bool: return w.relation(p.uid) >= 15.0)
		if not fr.is_empty():
			_opener(fr[w.rng.randi() % fr.size()], "benched")
			sent += 1
	if sent == 0 and w.rng.randf() < 0.1:
		var ex: Array = []
		for uid: int in ex_mates:
			var p := w.find_player(uid)
			if p != null and absf(w.relation(uid)) >= 20.0:
				ex.append(p)
		if not ex.is_empty():
			var p: PlayerData = ex[w.rng.randi() % ex.size()]
			_opener(p, "ex_hello" if w.relation(p.uid) > 0.0 else ("ex_beef" if w.teamless else "rival_taunt"))
			sent += 1
	if sent == 0 and not interest.is_empty() and w.rng.randf() < 0.2:
		var uid: int = interest.keys()[w.rng.randi() % interest.size()]
		var cp := w.find_player(uid)
		if cp != null and float(interest[uid]) >= 0.3:
			_opener(cp, "courted")


func _opener(p: PlayerData, situation: String) -> void:
	if p == null or not ChatText.OPEN.has(situation):
		return
	var th := thread("p:%d" % p.uid)
	var ln: Array = ChatText.line(ChatText.OPEN[situation], ChatText.voice(p), _slots(p), w.rng, th.recent)
	_bot_say(th, p, ln, situation, "")


# =============================================================================
# Threads
# =============================================================================

func _new_thread(key: String, uid: int, title: String) -> Dictionary:
	return {"key": key, "uid": uid, "title": title, "msgs": [], "unread": 0, "last": 0, "eff_stamp": 0, "eff_n": 0,
		"sent_stamp": 0, "sent_n": 0, "recent": [], "team": ""}


## The thread for a key, created on demand ("team" follows your current club).
func thread(key: String) -> Dictionary:
	var th: Dictionary = threads.get(key, {})
	if key == "team":
		var tn := "" if w.teamless else w.user_team().team_name
		if th.is_empty() or String(th.get("team", "")) != tn:
			th = _new_thread("team", 0, "Team chat")
			th.team = tn
			threads[key] = th
	elif key == "coach":
		if th.is_empty():
			th = _new_thread("coach", 0, "Coach")
			threads[key] = th
	elif key.begins_with("xc:"):
		if th.is_empty():
			var ti := int(key.substr(3))
			th = _new_thread(key, 0, "Coach (%s)" % w.teams[ti].short_name)
			threads[key] = th
			_trim_threads()
	elif th.is_empty():
		var uid := int(key.substr(2)) if key.begins_with("p:") else 0
		var p := w.find_player(uid)
		th = _new_thread(key, uid, p.player_name if p != null else "Unknown")
		threads[key] = th
		_trim_threads()
	return th


func open_thread(p: PlayerData) -> String:
	if p == null:
		return ""
	var key := "p:%d" % p.uid
	thread(key)
	return key


func thread_title(th: Dictionary) -> String:
	var key := String(th.key)
	if key == "team":
		return "Team chat" + ("" if w.teamless else "  (%s)" % w.user_team().short_name)
	if key == "coach":
		return "Coach %s" % coach_name(null if w.teamless else w.user_team())
	if key.begins_with("xc:"):
		var ct: TeamData = w.teams[int(key.substr(3))]
		return "Coach %s (%s)" % [coach_name(ct), ct.short_name]
	var p := w.find_player(int(th.uid))
	return p.player_name if p != null else String(th.title)


func _trim_threads() -> void:
	var dms: Array = threads.keys().filter(func(k: String) -> bool: return k.begins_with("p:") or k.begins_with("xc:"))
	if dms.size() <= MAX_THREADS:
		return
	dms.sort_custom(func(a: String, b: String) -> bool: return int(threads[a].last) < int(threads[b].last))
	for k: String in dms.slice(0, dms.size() - MAX_THREADS):
		threads.erase(k)


## Thread keys for the Messages page: team chat and coach first, then DMs by activity.
func thread_keys() -> Array:
	var out: Array = []
	if not w.teamless:
		thread("team")
		thread("coach")
		out.append("team")
		out.append("coach")
	var dms: Array = threads.keys().filter(func(k: String) -> bool: return k.begins_with("p:") or k.begins_with("xc:"))
	dms.sort_custom(func(a: String, b: String) -> bool: return int(threads[a].last) > int(threads[b].last))
	out.append_array(dms)
	return out


func unread_total() -> int:
	var n := 0
	for k: String in threads:
		if (k == "team" or k == "coach") and w.teamless:
			continue
		n += int(threads[k].unread)
	return n


func mark_read(key: String) -> void:
	if threads.has(key):
		threads[key].unread = 0


func _tick() -> int:
	seq += 1
	return seq


func _push(th: Dictionary, m: Dictionary) -> void:
	(th.msgs as Array).append(m)
	while (th.msgs as Array).size() > THREAD_CAP:
		(th.msgs as Array).pop_front()
	th.last = _tick()


## A bot line into a thread. ln: [text, template]. Queues the LLM rewrite.
func _bot_say(th: Dictionary, p: PlayerData, ln: Array, intent: String, stance: String, who_override: String = "") -> Dictionary:
	var text: String = ln[0]
	if text == "":
		return {}
	var who := who_override if who_override != "" else (p.player_name if p != null else "?")
	var m := {"me": false, "who": who, "uid": p.uid if p != null else 0, "text": text, "s": w.season, "w": w.week}
	if who_override != "":
		m["coach"] = true
	if _replying:
		# Nobody answers in the same instant: time to read it, then to type.
		var v := ChatText.voice(p) if p != null else "pro"
		var read := w.rng.randf_range(1.2, 4.0) * (2.5 if who_override != "" else 1.0) * (1.6 if v == "shy" else 1.0)
		var typing := float(text.length()) / w.rng.randf_range(5.0, 9.0)
		if w.rng.randf() < 0.12:
			read += w.rng.randf_range(4.0, 12.0) # Busy for a bit.
		var start := maxf(float(th.get("next_at", 0.0)), Time.get_unix_time_from_system())
		m["at"] = start + read + clampf(typing, 1.0, 9.0)
		m["type_from"] = start + read
		th["next_at"] = float(m.at) + w.rng.randf_range(0.5, 2.0)
	elif _unprompted and live:
		# Messages that come to you while you're looking: they arrive a little later.
		var at := Time.get_unix_time_from_system() + w.rng.randf_range(3.0, 14.0)
		m["at"] = at
		m["type_from"] = at - clampf(float(text.length()) / 7.0, 1.0, 6.0)
	_push(th, m)
	(th.recent as Array).append(String(ln[1]))
	while (th.recent as Array).size() > 8:
		(th.recent as Array).pop_front()
	th.unread = int(th.unread) + 1
	if llm_on:
		m["pending"] = true
		llm_jobs.append({"msg": m, "th": th, "system": ChatText.llm_system(_llm_ctx(p, stance if stance != "" else intent, who_override != "")),
			"user": _llm_user(th, intent), "fallback": text, "intent": intent})
		_cap_jobs()
	return m


var _replying := false ## Inside send(): bot replies get read/typing delays.


## A message counts as said once its delivery time has come (or the week moved on).
static func landed(m: Dictionary, season: int, week: int) -> bool:
	if not m.has("at"):
		return true
	if int(m.get("s", 0)) != season or int(m.get("w", 0)) != week:
		return true
	return Time.get_unix_time_from_system() >= float(m.at)


## Someone in this thread is typing right now (name), or "".
func typing_in(th: Dictionary) -> String:
	var now := Time.get_unix_time_from_system()
	for m: Dictionary in th.msgs:
		if bool(m.me) or landed(m, w.season, w.week) and not bool(m.get("pending", false)):
			continue
		if bool(m.get("pending", false)) or now >= float(m.get("type_from", 0.0)):
			return String(m.who)
	return ""


## The conversation so far as chat turns for the local model: your lines are
## "user", this speaker's are "assistant", anyone else in a group chat is
## quoted by name. Only what had been said before `upto`.
func llm_history(th: Dictionary, upto: Dictionary) -> Array:
	var out: Array = []
	var msgs: Array = th.msgs
	var idx := msgs.find(upto)
	if idx < 0:
		idx = msgs.size()
	var from := maxi(0, idx - 14)
	for i in range(from, idx):
		var m: Dictionary = msgs[i]
		if bool(m.me):
			out.append({"role": "user", "content": String(m.text)})
		elif String(m.who) == String(upto.who):
			out.append({"role": "assistant", "content": String(m.text)})
		else:
			out.append({"role": "user", "content": "%s: %s" % [String(m.who), String(m.text)]})
	# The model expects the turn it answers to be the user's.
	while not out.is_empty() and String(out[out.size() - 1].role) == "assistant":
		out.pop_back()
	if out.is_empty():
		out.append({"role": "user", "content": "..."})
	return out


## Nobody is collecting the jobs (no hub open): keep the template lines.
func _cap_jobs() -> void:
	while llm_jobs.size() > 12:
		var old: Dictionary = llm_jobs.pop_front()
		(old.msg as Dictionary).erase("pending")


func _llm_user(th: Dictionary, intent: String) -> String:
	var msgs: Array = th.msgs
	for i in range(msgs.size() - 1, -1, -1):
		if bool(msgs[i].me):
			return String(msgs[i].text)
	return "(Write a short message to %s first. Topic: %s.)" % [w.user_player.player_name, intent.replace("_", " ")]


func _llm_ctx(p: PlayerData, stance: String, is_coach: bool) -> Dictionary:
	var me := w.user_player
	var ctx := {"me": me.player_name, "stance": stance, "events": _events_text()}
	if is_coach or p == null:
		var ut := w.user_team()
		ctx.merge({"coach": true, "name": coach_name(ut), "team": ut.team_name, "voice": "pro",
			"mood": "demanding" if w.coach_trust < 40.0 else "supportive", "relation": "trusts them %d/100" % int(w.coach_trust)})
		return ctx
	var t := w.owner_of(p)
	var mood := "upbeat" if p.morale >= 70.0 else ("okay" if p.morale >= 45.0 else "frustrated")
	if p.form >= 2.0:
		mood += ", in great form"
	elif p.form <= -2.0:
		mood += ", in poor form"
	var rel := relation_label(p).to_lower()
	if _is_mate(p):
		rel += ", teammates"
	elif ex_mates.has(p.uid):
		rel += ", ex-teammates at %s" % ex_mates[p.uid]
	ctx.merge({"name": p.player_name, "age": p.age, "role": p.role, "team": t.team_name if t != null else "(free agent)",
		"voice": ChatText.voice(p), "mood": mood, "relation": rel})
	return ctx


func _events_text() -> String:
	var me := w.user_player
	var parts: Array = []
	if not last_ctx.is_empty():
		parts.append("%s's last match: %s %s vs %s, rated %.2f" % [me.player_name, String(last_ctx.res), String(last_ctx.score), String(last_ctx.opp), float(last_ctx.r)])
	if w.teamless:
		parts.append("%s was released and has no club" % me.player_name)
	elif not w.user_starting():
		parts.append("%s is on the bench at %s" % [me.player_name, w.user_team().team_name])
	else:
		parts.append("%s plays for %s (%s)" % [me.player_name, w.user_team().team_name, World.LEAGUES[w.user_team().league].name])
	if toxicity > 40.0:
		parts.append("%s has been toxic online lately" % me.player_name)
	return "; ".join(parts)


## Hands queued LLM jobs to the caller (the hub runs them).
func take_llm_jobs() -> Array:
	var out := llm_jobs
	llm_jobs = []
	return out


func _slots(p: PlayerData) -> Dictionary:
	var me := w.user_player
	var ut := w.user_team()
	var t: TeamData = w.owner_of(p) if p != null else null
	var cur := mates()
	var others: Array = cur.filter(func(q: PlayerData) -> bool: return q != p)
	var igl: PlayerData = igl_of(ut) if not w.teamless else null
	var top := w.top_rival()
	var streak := ut.streak if not w.teamless else 0
	return {
		"me": me.player_name, "name": p.player_name if p != null else "", "team": t.team_name if t != null else "my team",
		"myteam": "no club" if w.teamless else ut.team_name, "opp": String(last_ctx.get("opp", "them")),
		"score": String(last_ctx.get("score", "that score")), "rating": "%.2f" % float(last_ctx.get("r", 1.0)),
		"res": String(last_ctx.get("res", "game")), "mate": (others[w.rng.randi() % others.size()] as PlayerData).player_name if not others.is_empty() else "the boys",
		"igl": igl.player_name if igl != null else "the IGL", "coach": coach_name(ut), "rival": String(top.get("name", "them")),
		"map": Maps.LIST[w.rng.randi() % Maps.LIST.size()], "site": ["A", "B"][w.rng.randi() % 2], "nade": ["smoke", "molly", "flash"][w.rng.randi() % 3],
		"role": p.role if p != null else "", "myrole": me.role, "myform": me.form_text().to_lower(),
		"oldteam": String(ex_mates.get(p.uid, "your old club")) if p != null else "your old club",
		"streak": ("%d straight losses" % -streak) if streak <= -2 else "that run", "target": "", "other": "",
	}


func _effect_ok(th: Dictionary, limit: int) -> bool:
	if int(th.eff_stamp) != w.stamp():
		th.eff_stamp = w.stamp()
		th.eff_n = 0
	if int(th.eff_n) >= limit:
		return false
	th.eff_n = int(th.eff_n) + 1
	return true


# =============================================================================
# Sending messages
# =============================================================================

## You type in a thread. Bots reply (effects decided here). Returns
## {ok, msg} where msg is a short effect summary or an error.
func send(key: String, text: String) -> Dictionary:
	var me := w.user_player
	text = text.strip_edges().substr(0, 240)
	if text.length() < 1:
		return {"ok": false, "msg": "Type a message first"}
	if me == null or w.retired:
		return {"ok": false, "msg": "Your career is over"}
	if (key == "team" or key == "coach") and w.teamless:
		return {"ok": false, "msg": "You don't have a club right now"}
	var p: PlayerData = null
	if key.begins_with("p:"):
		p = w.find_player(int(key.substr(2)))
		if p == null:
			return {"ok": false, "msg": "They've left the scene (retired)"}
	var th := thread(key)
	if int(th.get("blocked_until", 0)) > w.stamp():
		return {"ok": false, "msg": "%s has blocked you." % String(th.title)}
	var a0 := ChatText.analyze(text)
	if int(a0.slur) > 0:
		_push(th, {"me": true, "who": me.player_name, "uid": me.uid, "text": ChatText.censor(text), "s": w.season, "w": w.week})
		return {"ok": true, "msg": _hate_dm(th, key, p), "intent": "hate"}
	_push(th, {"me": true, "who": me.player_name, "uid": me.uid, "text": text, "s": w.season, "w": w.week})
	if int(th.sent_stamp) != w.stamp():
		th.sent_stamp = w.stamp()
		th.sent_n = 0
	th.sent_n = int(th.sent_n) + 1
	var a := ChatText.analyze(text)
	var intent := ChatText.dm_intent(a)
	var res := ""
	_replying = true
	th["next_at"] = Time.get_unix_time_from_system()
	if key == "team":
		res = _group_reply(th, text, a, intent)
	elif key == "coach":
		res = _coach_reply(th, text, a, intent)
	elif key.begins_with("xc:"):
		res = talk.ext_reply(th, int(key.substr(3)), a, intent)
	else:
		res = _dm_reply(th, p, text, a, intent)
	_replying = false
	th.unread = 0
	return {"ok": true, "msg": res, "intent": intent}


func _dm_reply(th: Dictionary, p: PlayerData, _text: String, a: Dictionary, intent: String) -> String:
	var me := w.user_player
	var ut := w.user_team()
	var rel := strength(p)
	var mate := _is_mate(p)
	var fa := w.free_agents.has(p)
	var v := ChatText.voice(p)
	var mood := (p.morale - 55.0) / 45.0 + rel * 0.8
	var harsh := clampf(float(a.harsh) + 0.25, 0.0, 1.0)
	var slots := _slots(p)
	var stance := "neutral"
	var bank: Array = []
	var res := ""
	if int(th.sent_n) > 6:
		var ln0: Array = ChatText.line(ChatText.DM.spam.annoyed, v, slots, w.rng, th.recent)
		_bot_say(th, p, ln0, "spam", "annoyed")
		w._relate(p.uid, -1.0)
		return "%s is getting annoyed by all the messages." % p.player_name
	var eff := _effect_ok(th, DM_EFFECTS)
	match intent:
		"flame":
			if rel < -0.2 or v == "toxic":
				stance = "hostile" if not mate else "angry"
			elif mate:
				stance = "hurt" if v in ["shy", "pro", "mentor", "igl"] else "angry"
			else:
				stance = "laugh" if w.rng.randf() < 0.5 else "angry"
			if eff:
				w._relate(p.uid, -(12.0 + 25.0 * harsh))
				toxicity = minf(100.0, toxicity + 5.0 + 8.0 * harsh)
				last_flamed = p.uid
				if mate:
					p.morale = maxf(0.0, p.morale - (4.0 + 6.0 * harsh))
					_heat(0.4 * harsh, "flaming teammates")
				res = "%s won't forget that." % p.player_name
				if not mate and not fa:
					var tr := talk.note_trash_dm(p, harsh)
					if tr != "":
						res = tr
		"apology":
			var target := last_flamed == p.uid
			if rel > -0.5 and (v != "toxic" or w.rng.randf() < 0.55):
				stance = "accept"
			elif rel > -0.75:
				stance = "wary"
			else:
				stance = "reject"
			if eff and stance != "reject":
				w._relate(p.uid, (12.0 if target else 5.0) * (1.0 if stance == "accept" else 0.5))
				if target:
					last_flamed = 0
				res = "Things are better with %s." % p.player_name
		"praise":
			stance = "warm" if rel > -0.3 else ("hostile" if rel < -0.5 else "humble")
			if stance == "warm" and p.form < -2.0:
				stance = "humble"
			if eff:
				w._relate(p.uid, 4.0 if rel > -0.5 else 1.0)
				if mate:
					p.morale = minf(100.0, p.morale + 2.0)
		"banter":
			stance = "laugh" if mood > -0.2 else ("meh" if mood > -0.6 else "annoyed")
			if mate and ut.streak <= -2 and w.rng.randf() < 0.5:
				stance = "annoyed"
			if eff:
				w._relate(p.uid, 2.0 if stance == "laugh" else (-1.0 if stance == "annoyed" else 0.5))
		"strategy":
			if not mate:
				stance = "spy"
			elif v == "igl":
				stance = "agree" if w.rng.randf() < 0.4 else "suggest"
			else:
				stance = "agree" if mood > -0.3 else "dismiss"
			if eff and mate:
				w._relate(p.uid, 2.0 if stance != "dismiss" else -1.0)
		"form":
			stance = "good" if p.form >= 1.5 else ("bad" if p.form <= -1.5 or p.morale < 35.0 else "meh")
			if eff:
				w._relate(p.uid, 1.5)
		"practice":
			if mate:
				stance = "yes" if rel > -0.25 and w.rng.randf() < 0.75 else ("later" if rel > -0.4 else "no")
			else:
				stance = "yes" if rel > 0.15 else ("later" if rel > -0.3 else "no")
			if eff and stance == "yes":
				w._relate(p.uid, 6.0 if mate else 4.0)
				if mate and not w.trained_this_week and me.available():
					w.trained_this_week = true
					var k: String = PlayerData.STAT_KEYS[w.rng.randi() % PlayerData.STAT_KEYS.size()]
					me.set_stat(k, me.stat(k) + 0.4)
					p.set_stat(k, p.stat(k) + 0.4)
					res = "Duo session with %s: +0.4 %s for you both (this week's training)." % [p.player_name, PlayerData.STAT_NAMES[k]]
				elif mate:
					res = "You'll practise together (no stat gain: you've already trained this week)."
		"sign":
			if mate:
				stance = "already"
			elif w.teamless:
				stance = "noclub"
			else:
				var owner := w.owner_of(p)
				var refuses := p.refuses(ut) != ""
				if refuses or rel < -0.3:
					stance = "no"
				elif fa or (owner != null and owner.league > ut.league) or p.morale < 45.0 or rel > 0.3 or p.bench_weeks >= 2:
					stance = "interested"
				else:
					stance = "maybe"
				if eff and stance != "no":
					var add := (0.28 if stance == "interested" else 0.12) * (1.0 + rel * 0.5)
					interest[p.uid] = minf(1.0, float(interest.get(p.uid, 0.0)) + add)
					w._relate(p.uid, 2.0)
					res = "%s is %s a move to %s." % [p.player_name, "seriously considering" if stance == "interested" else "thinking about", ut.team_name]
				elif stance == "no" and refuses:
					res = p.refuses(ut) + "."
		"join":
			var owner2 := w.owner_of(p)
			if fa:
				stance = "fa"
			elif mate:
				stance = "already"
			else:
				var oi := w.team_index(owner2)
				var att := talk.attitude(oi)
				if String(att.label) == "won't sign":
					var wl: Array = ChatText.line(ClubTalk.JOIN_WONT, v, slots, w.rng, th.recent)
					_bot_say(th, p, wl, intent, "no")
					return "%s won't consider you (%s)." % [owner2.team_name, String((att.reasons as Array)[0]) if not (att.reasons as Array).is_empty() else "reputation"]
				if rel < -0.3 or int(team_beef.get(oi, 0)) > 0:
					stance = "no"
				elif rel > 0.2 or absf(owner2.rating_exact() - me.rating_exact()) < 8.0:
					stance = "positive"
				else:
					stance = "neutral"
				if eff and stance != "no":
					club_interest[oi] = minf(1.0, float(club_interest.get(oi, 0.0)) + (0.25 if stance == "positive" else 0.1) * (1.0 + maxf(rel, 0.0)))
					res = "%s will mention you to the %s coach: expect to hear from them next week." % [p.player_name, owner2.team_name]
					talk.queue_ext_coach(oi, p)
					if w.teamless:
						comeback = minf(100.0, comeback + (4.0 if stance == "positive" else 1.5))
		"contract":
			stance = "deflect"
		"lineup":
			stance = "askcoach"
		"greeting", "smalltalk":
			stance = "warm" if rel >= 0.2 or (mood > 0.3 and rel > -0.2) else ("neutral" if rel > -0.25 else ("cold" if rel > -0.55 else "hostile"))
			if eff:
				w._relate(p.uid, 1.0 if rel > -0.4 else 0.0)
	var cat: Dictionary = ChatText.DM.get(intent, ChatText.DM.smalltalk)
	bank = cat.get(stance, [])
	if bank.is_empty():
		bank = ChatText.DM.smalltalk.get(stance, ChatText.DM.smalltalk.neutral)
	var ln: Array = ChatText.line(bank, v, slots, w.rng, th.recent)
	_bot_say(th, p, ln, intent, stance)
	# Chatty voices sometimes add a second line.
	if v in ["showman", "chill", "toxic"] and stance in ["warm", "laugh", "interested", "yes"] and w.rng.randf() < 0.2:
		var extra: Array = ChatText.line(ChatText.DM.smalltalk.warm, v, slots, w.rng, th.recent)
		_bot_say(th, p, extra, intent, stance)
	return res


func _coach_reply(th: Dictionary, text: String, a: Dictionary, intent: String) -> String:
	var me := w.user_player
	var ut := w.user_team()
	var slots := _slots(null)
	var stance := "neutral"
	var cat := "smalltalk"
	var res := ""
	var eff := _effect_ok(th, DM_EFFECTS)
	var harsh := clampf(float(a.harsh) + 0.25, 0.0, 1.0)
	var asks_start := ChatText.count_kw(String(a.n), ChatText.INTENT_KW.lineup) > 0
	if intent == "lineup" or (intent == "flame" and asks_start):
		var insult := intent == "flame"
		var extra := ""
		if insult and eff:
			w._trust(-(10.0 + 20.0 * harsh))
			_heat(1.0 + harsh, "insulting the coach")
			toxicity = minf(100.0, toxicity + 6.0)
			extra = talk.on_coach_insult()
		var out := talk.ask_to_start(th, a, insult)
		return out + ((" " + extra) if extra != "" else "")
	if intent == "leave":
		return talk.ask_to_leave(th)
	match intent:
		"apology":
			cat = "apology"
			if (strikes > 0 or heat > 0.5 or w.coach_trust < 45.0) and w.stamp() - apology_stamp >= 3:
				stance = "accept"
				apology_stamp = w.stamp()
				w._trust(4.0)
				heat = maxf(0.0, heat - 0.6)
				res = "Coach trust +4."
			else:
				stance = "nothing" if strikes == 0 else "accept"
		"flame":
			cat = "flame"
			stance = "furious"
			if eff:
				w._trust(-(10.0 + 20.0 * harsh))
				_heat(1.0 + harsh, "insulting the coach")
				toxicity = minf(100.0, toxicity + 6.0)
				res = "Coach trust -%d. That's going on your record." % int(10.0 + 20.0 * harsh)
				var esc := talk.on_coach_insult()
				if esc != "":
					res += " " + esc
		"praise":
			cat = "praise"
			stance = "thanks"
			if eff:
				w._trust(1.0)
		"strategy":
			cat = "strategy"
			stance = "likes" if me.stat("decision") >= 55.0 or w.rng.randf() < 0.3 else "igl"
			if eff:
				w._trust(2.0 if stance == "likes" else 0.5)
				res = "The coach noted your idea." if stance == "likes" else ""
		"contract":
			cat = "contract"
			if me.contract_until <= w.season and w.week < 12:
				stance = "later"
			elif w.coach_trust >= 70.0:
				stance = "longterm"
			else:
				stance = "focus"
		"form":
			cat = "form"
			stance = "good" if me.form >= 0.5 else "bad"
		"practice":
			cat = "practice"
			stance = "yes"
			if eff:
				w._trust(1.0)
		"join":
			cat = "join"
			stance = "under"
			if eff:
				w._trust(-3.0)
				res = "Coach trust -3: he didn't like that."
		"sign":
			cat = "sign"
			stance = "noted"
			var named := ChatText.find_players(text, w.free_agents + w.market_players().slice(0, 200))
			if not named.is_empty() and eff:
				var q: PlayerData = named[0]
				interest[q.uid] = minf(1.0, float(interest.get(q.uid, 0.0)) + 0.1)
				res = "The coach will look at %s." % q.player_name
	var bank: Array = (ChatText.COACH.get(cat, ChatText.COACH.smalltalk) as Dictionary).get(stance, ChatText.COACH.smalltalk.neutral)
	var ln: Array = ChatText.line(bank, "pro", slots, w.rng, th.recent)
	_bot_say(th, null, ln, intent, stance, "Coach %s" % coach_name(ut))
	return res


## Team group chat: one to three teammates answer, sometimes each other.
func _group_reply(th: Dictionary, text: String, a: Dictionary, intent: String) -> String:
	var cur := mates()
	if cur.is_empty():
		return ""
	var named := ChatText.find_players(text, cur)
	var target: PlayerData = named[0] if not named.is_empty() else null
	var igl := igl_of(w.user_team())
	var harsh := clampf(float(a.harsh) + 0.25, 0.0, 1.0)
	var eff := _effect_ok(th, TEAM_EFFECTS)
	var res := ""
	# Effects on the squad.
	if eff:
		match intent:
			"praise":
				for p: PlayerData in cur:
					w._relate(p.uid, 2.0 + (4.0 if p == target else 0.0))
					p.morale = minf(100.0, p.morale + 2.0)
				res = "Team morale up."
			"flame":
				if target != null:
					w._relate(target.uid, -(15.0 + 25.0 * harsh))
					target.morale = maxf(0.0, target.morale - (4.0 + 6.0 * harsh))
					last_flamed = target.uid
				for p: PlayerData in cur:
					if p != target:
						w._relate(p.uid, -(3.0 + 5.0 * harsh) * (1.0 if target != null else 1.6))
						p.morale = maxf(0.0, p.morale - (1.0 if target != null else 3.0))
				w._trust(-(2.0 + 4.0 * harsh))
				toxicity = minf(100.0, toxicity + 6.0 + 8.0 * harsh)
				_heat(0.5 * harsh + 0.3, "flaming teammates")
				res = "The squad is rattled. Coach trust down."
				var rep := talk.on_team_flame(target, harsh)
				if rep != "":
					res += " " + rep
			"strategy":
				if igl != null:
					w._relate(igl.uid, 2.0 if ChatText.voice(igl) != "toxic" else -1.0)
				w._trust(1.0)
				res = "The coach liked the initiative."
			"banter":
				var good := w.user_team().streak >= 0
				for p: PlayerData in cur:
					w._relate(p.uid, 1.5 if good else -0.5)
			"apology":
				for p: PlayerData in cur:
					w._relate(p.uid, 3.0 + (8.0 if p.uid == last_flamed else 0.0))
				if last_flamed != 0 and cur.any(func(p: PlayerData) -> bool: return p.uid == last_flamed):
					last_flamed = 0
				res = "The squad appreciates it."
			"practice":
				for p: PlayerData in cur:
					w._relate(p.uid, 2.0)
					p.morale = minf(100.0, p.morale + 1.0)
			_:
				for p: PlayerData in cur:
					w._relate(p.uid, 0.5)
	# Who answers.
	var first: PlayerData = target
	if first == null and intent == "strategy" and igl != null:
		first = igl
	if first == null:
		var chatty: Array = cur.duplicate()
		var score := {}
		for q: PlayerData in chatty:
			score[q] = _chattiness(q)
		chatty.sort_custom(func(x: PlayerData, y: PlayerData) -> bool: return float(score[x]) > float(score[y]))
		first = chatty[w.rng.randi() % mini(3, chatty.size())]
	var responders: Array = [first]
	var rest: Array = cur.filter(func(p: PlayerData) -> bool: return p != first)
	rest.shuffle()
	if not rest.is_empty() and w.rng.randf() < 0.55:
		responders.append(rest[0])
	if rest.size() > 1 and w.rng.randf() < 0.25:
		responders.append(rest[1])
	for i in responders.size():
		var p: PlayerData = responders[i]
		var slots := _slots(p)
		slots.target = target.player_name if target != null else "the team"
		var v := ChatText.voice(p)
		if i > 0 and w.rng.randf() < 0.45:
			# Cross-talk: reacting to the teammate before them (or defending the target).
			var prev: PlayerData = responders[i - 1]
			slots.other = prev.player_name
			var ck := "agree"
			if intent == "flame" and target != null and p != target:
				ck = "defend" if w.relation(target.uid) > -30.0 and strength(p) > -0.5 else "pile"
			elif intent == "flame":
				ck = "calm"
			elif v == "toxic" or v == "chill":
				ck = "tease"
			var cl: Array = ChatText.line(ChatText.CROSS[ck], v, slots, w.rng, th.recent)
			_bot_say(th, p, cl, intent, ck)
			continue
		var rel := strength(p)
		var stance := _group_stance(p, intent, rel, p == target)
		var cat: Dictionary = ChatText.DM.get(intent, ChatText.DM.smalltalk)
		var bank: Array = cat.get(stance, ChatText.DM.smalltalk.get(stance, ChatText.DM.smalltalk.neutral))
		var ln: Array = ChatText.line(bank, v, slots, w.rng, th.recent)
		_bot_say(th, p, ln, intent, stance)
	return res


func _chattiness(p: PlayerData) -> float:
	var v := ChatText.voice(p)
	return {"showman": 3.0, "toxic": 2.5, "chill": 2.0, "igl": 1.8, "mentor": 1.2, "pro": 1.0, "shy": 0.4}.get(v, 1.0) + w.rng.randf()


func _group_stance(p: PlayerData, intent: String, rel: float, targeted: bool) -> String:
	var v := ChatText.voice(p)
	var mood := (p.morale - 55.0) / 45.0 + rel * 0.8
	match intent:
		"flame":
			if targeted:
				return "hurt" if v in ["shy", "pro", "mentor"] else "angry"
			return "laugh" if v == "toxic" else "hurt"
		"apology":
			return "accept" if rel > -0.5 else "wary"
		"praise":
			return "warm" if rel > -0.4 else "humble"
		"banter":
			return "laugh" if mood > -0.3 and w.user_team().streak >= -1 else "annoyed"
		"strategy":
			if v == "igl":
				return "suggest" if w.rng.randf() < 0.6 else "agree"
			return "agree" if mood > -0.3 else "dismiss"
		"form":
			return "good" if p.form >= 1.5 else ("bad" if p.form <= -1.5 else "meh")
		"practice":
			return "yes" if rel > -0.3 else "later"
		"sign", "join", "contract":
			return "deflect"
		"lineup":
			return "askcoach"
	return "warm" if rel >= 0.2 or mood > 0.3 else ("neutral" if rel > -0.4 else "cold")


# =============================================================================
# Posting to the feed
# =============================================================================

func posts_left() -> int:
	if posts_stamp != w.stamp():
		return POSTS_PER_WEEK
	return maxi(0, POSTS_PER_WEEK - posts_used)


## Reads the post, settles the real tone and target, applies the fallout and
## generates replies. Returns {ok, msg, tone}.
func post(text: String, tone: String) -> Dictionary:
	_trickle = 0.0
	var res := _post_inner(text, tone)
	_trickle = -1.0
	return res


## Your post shows right away (its likes climb for a couple of minutes); the
## replies to it land over the next minute or so instead of all at once.
func _stamp_mine() -> void:
	if w.feed.is_empty():
		return
	var f: Dictionary = w.feed[w.feed.size() - 1]
	if String(f.kind) == "me":
		f["t0"] = Time.get_unix_time_from_system()


func _post_inner(text: String, tone: String) -> Dictionary:
	var me := w.user_player
	text = text.strip_edges().substr(0, 220)
	if me == null or w.retired:
		return {"ok": false, "msg": "Your career is over"}
	if text.length() < 3:
		return {"ok": false, "msg": "Write something first"}
	if not TONES.has(tone):
		tone = "neutral"
	if posts_stamp != w.stamp():
		posts_stamp = w.stamp()
		posts_used = 0
	if posts_used >= POSTS_PER_WEEK:
		return {"ok": false, "msg": "You've posted %d times this week. Put the phone down until next week." % POSTS_PER_WEEK}
	_post_text = text
	var a := ChatText.analyze(text)
	if int(a.slur) > 0:
		posts_used += 1
		return _hate_post(text)
	var tg := _post_target(text, a)
	if tone == "auto":
		tone = _infer_tone(a, tg)
	var rt := _resolve_tone(tone, a, tg)
	if String(rt.note) == "":
		rt.note = _read_as(String(rt.tone), tg)
	var final: String = rt.tone
	posts_used += 1
	var mult: float = POST_MULT[mini(posts_used - 1, POST_MULT.size() - 1)]
	var harsh := clampf(float(TONE_BASE.get(final, 0.0)) + float(a.harsh), 0.0, 1.0)
	if int(a.insult) == 0 and int(a.profanity) == 0:
		harsh *= 0.7
	var lm := w._lmult(w.user_team()) if not w.teamless else 1.0
	var parts: Array = []
	if String(rt.note) != "":
		parts.append(String(rt.note))
	var tp: PlayerData = tg.player
	var tt: TeamData = tg.team
	var ut := w.user_team()
	var slots := _slots(tp)
	slots.target = tp.player_name if tp != null else (tt.team_name if tt != null else "them")
	var fame0 := w.fame
	var trust0 := w.coach_trust
	match final:
		"hype":
			var cynic := not w.teamless and ut.streak <= -3
			w._gain_fame(int((60.0 + w.fame * 0.004) * mult * lm * (0.5 if cynic else 1.0)))
			for p: PlayerData in mates():
				w._relate(p.uid, 2.0 * mult + (6.0 * mult if p == tp else 0.0))
				p.morale = minf(100.0, p.morale + 2.0 * mult)
			w._trust(1.0 * mult)
			toxicity = maxf(0.0, toxicity - 3.0)
			w._post("@" + me.player_name, text, "me", 1.2)
			_feed_lines("hype_cynic" if cynic else "hype_fan", 2 + (1 if w.fame > 8000 else 0), slots, "fan")
			if not mates().is_empty() and w.rng.randf() < 0.7:
				var m: PlayerData = mates()[w.rng.randi() % mates().size()]
				_feed_reply("@" + m.player_name, ChatText.line(ChatText.FEED.hype_mate, ChatText.voice(m), _slots(m), w.rng, feed_recent), "teammate", 0.8)
			parts.append("The squad loved it.")
		"callout":
			if tt == null and tp != null:
				tt = w.owner_of(tp)
			var tidx := w.team_index(tt) if tt != null else -1
			w._gain_fame(int((250.0 + w.fame * 0.01) * (0.5 + harsh) * mult * lm))
			if tidx >= 0 and (tt != ut or w.teamless):
				w.trash_target = tidx
				team_beef[tidx] = maxi(int(team_beef.get(tidx, 0)), 10)
				talk.note_club(tidx, -25.0, "you trash-talked them", 20)
				for q in tt.roster:
					w._relate(q.uid, -5.0)
				parts.append("%s will be fired up next time you meet." % tt.team_name)
			if tp != null:
				w._relate(tp.uid, -(15.0 + 25.0 * harsh))
				last_flamed = tp.uid
			toxicity = minf(100.0, toxicity + 15.0 * harsh)
			if harsh > 0.6:
				_heat(0.4 * harsh, "trash talk online")
			if harsh > 0.5 and w.rng.randf() < harsh * 0.6 and not w.teamless:
				w._trust(-(3.0 + 6.0 * harsh))
			w._post("@" + me.player_name, text, "me", 1.0 + harsh * 2.0)
			_feed_lines("callout_fan", 2, slots, "fan")
			_feed_lines("callout_toxic", 1 + (1 if harsh > 0.5 else 0), slots, "toxic")
			if tp != null:
				_target_reply(tp, ChatText.FEED.callout_target, "rival", "callout", slots)
			if tt != null:
				_feed_reply("@" + tt.short_name, ChatText.line(ChatText.FEED.callout_club, "pro", slots, w.rng, feed_recent), "rival", 1.5)
			_sponsor_risk(harsh, int(a.profanity), parts)
		"flame":
			var cur := mates()
			var named := tp != null and cur.has(tp)
			if named:
				w._relate(tp.uid, -(15.0 + 35.0 * harsh))
				tp.morale = maxf(0.0, tp.morale - (5.0 + 10.0 * harsh))
				last_flamed = tp.uid
			for p: PlayerData in cur:
				if p != tp:
					w._relate(p.uid, -(4.0 + 8.0 * harsh) * (1.0 if named else 1.3))
					p.morale = maxf(0.0, p.morale - (2.0 + 4.0 * harsh))
			w._trust(-(4.0 + 10.0 * harsh))
			toxicity = minf(100.0, toxicity + 20.0 + 30.0 * harsh)
			_heat(0.8 + 1.2 * harsh, "flaming teammates in public")
			w._gain_fame(int((150.0 + w.fame * 0.006) * harsh * mult))
			if harsh >= 0.35 and not w.teamless:
				var fine := mini(w.wallet, int(maxf(500.0, me.salary * (1.0 + harsh * 2.0)) / 50.0) * 50)
				if fine > 0:
					w.wallet -= fine
					parts.append("%s fined you $%s." % [ut.team_name, World._fmt(fine)])
			slots.target = tp.player_name if named else "the team"
			w._post("@" + me.player_name, text, "me", 1.5 + harsh * 2.0)
			if named:
				_target_reply(tp, ChatText.FEED.flame_target, "teammate", "flame", slots)
			_feed_lines("flame_fan", 2, slots, "fan")
			_feed_lines("flame_toxic", 1, slots, "toxic")
			if harsh > 0.4 and not w.teamless:
				_feed_reply("@" + ut.short_name, ChatText.line(ChatText.FEED.flame_club, "pro", slots, w.rng, feed_recent), "club", 1.5)
			_feed_reply(World.OUTLET_HANDLES.pick_random(), ChatText.line(ChatText.FEED.flame_press, "pro", slots, w.rng, feed_recent), "press", 1.8)
			parts.append("The dressing room is furious.")
			_sponsor_risk(harsh + 0.1, int(a.profanity), parts)
		"coach":
			w._trust(-(8.0 + 18.0 * harsh))
			toxicity = minf(100.0, toxicity + 10.0 + 20.0 * harsh)
			_heat(0.6 + harsh, "criticising the coach in public")
			w._gain_fame(int((120.0 + w.fame * 0.005) * mult))
			if harsh >= 0.5 and not w.teamless:
				var fine2 := mini(w.wallet, int(me.salary * (0.5 + harsh) / 50.0) * 50)
				if fine2 > 0:
					w.wallet -= fine2
					parts.append("Fined $%s." % World._fmt(fine2))
			w._post("@" + me.player_name, text, "me", 1.4 + harsh)
			_feed_lines("coach_fan", 2, slots, "fan")
			if not w.teamless:
				_feed_reply("@" + ut.short_name, ChatText.line(ChatText.FEED.coach_club, "pro", slots, w.rng, feed_recent), "club", 1.4)
			_feed_reply(World.OUTLET_HANDLES.pick_random(), ChatText.line(ChatText.FEED.coach_press, "pro", slots, w.rng, feed_recent), "press", 1.6)
			_sponsor_risk(harsh, int(a.profanity), parts)
		"haters":
			if harsh < 0.35:
				w._gain_fame(int((120.0 + w.fame * 0.006) * mult * lm))
				toxicity = minf(100.0, toxicity + 2.0)
				w._post("@" + me.player_name, text, "me", 1.3)
				_feed_lines("haters_witty", 1, slots, "fan")
				_feed_lines("haters_fan", 1, slots, "fan")
				_feed_lines("haters_toxic", 1, slots, "toxic")
				parts.append("Composed and funny: it landed.")
			else:
				w._gain_fame(int((80.0 + w.fame * 0.004) * mult * lm))
				toxicity = minf(100.0, toxicity + 5.0 + 12.0 * harsh)
				w._post("@" + me.player_name, text, "me", 1.0 + harsh)
				_feed_lines("haters_fan", 1, slots, "fan")
				_feed_lines("haters_toxic", 2, slots, "toxic")
				w._toxic("hater", "", 1.2)
				parts.append("The haters smell blood.")
				if int(a.profanity) > 0:
					_sponsor_risk(harsh, int(a.profanity), parts)
			me.morale = minf(100.0, me.morale + 3.0)
		"apology":
			var meant := toxicity > 15.0 or strikes > 0 or last_flamed != 0 or heat > 0.5
			var fresh := w.stamp() - apology_stamp >= 3
			var e := (1.0 if fresh else 0.3) * (0.3 if int(a.insult) > 0 else 1.0)
			w._post("@" + me.player_name, text, "me", 1.0)
			if meant:
				apology_stamp = w.stamp()
				toxicity = maxf(0.0, toxicity - 25.0 * e)
				heat = maxf(0.0, heat - 0.8 * e)
				if strikes > 0:
					w._trust(3.0 * e)
				if last_flamed != 0:
					var lp := w.find_player(last_flamed)
					w._relate(last_flamed, 12.0 * e)
					if lp != null:
						slots.target = lp.player_name
						if e >= 1.0:
							_target_reply(lp, ChatText.FEED.apology_target, "teammate" if _is_mate(lp) else "rival", "apology", slots)
					last_flamed = 0
				_feed_lines("apology_fan", 2, slots, "fan")
				_feed_lines("apology_cynic", 1, slots, "toxic")
				parts.append("Most people respect it." if e >= 1.0 else "Another apology? People are tired of them.")
			else:
				_feed_lines("apology_none", 2, slots, "fan")
				parts.append("Nobody's sure what you're apologising for.")
		_:
			w._gain_fame(int((30.0 + w.fame * 0.002) * mult * lm))
			w._post("@" + me.player_name, text, "me", 1.0)
			if tp != null and int(a.praise) > 0:
				w._relate(tp.uid, 4.0 * mult)
				_feed_lines("neutral_praise", 1, slots, "fan")
				if w.rng.randf() < 0.6:
					_target_reply(tp, ChatText.DM.praise.warm, "teammate" if _is_mate(tp) else "fan", "praise", slots)
			_feed_lines("neutral_fan", 1 + (1 if w.fame > 5000 else 0), slots, "fan")
	var df := w.fame - fame0
	if df != 0:
		parts.append("%s%s followers." % ["+" if df > 0 else "", World.fame_text(df) if df > 0 else "-" + World.fame_text(-df)])
	var dt := int(round(w.coach_trust - trust0))
	if dt != 0:
		parts.append("Coach trust %+d." % dt)
	return {"ok": true, "msg": " ".join(parts), "tone": final}


## Who the post is about: {player, team, coach, haters}.
func _post_target(text: String, a: Dictionary) -> Dictionary:
	var cands: Array = mates()
	var top := w.top_rival()
	if not top.is_empty():
		var rp := w.find_player(int(top.uid))
		if rp != null:
			cands.append(rp)
	for uid in w.rivals:
		var q := w.find_player(int(uid))
		if q != null and not cands.has(q):
			cands.append(q)
	var opp_idx := int(last_ctx.get("opp_idx", -1))
	if opp_idx >= 0 and opp_idx < w.teams.size():
		cands.append_array(w.teams[opp_idx].roster)
	var players := ChatText.find_players(text, cands)
	if players.is_empty():
		var everyone: Array = []
		for t in w.teams:
			everyone.append_array(t.roster)
		players = ChatText.find_players(text, everyone)
	var teams_hit := ChatText.find_teams(text, w.teams)
	var team: TeamData = null
	for t: TeamData in teams_hit:
		if w.teamless or t != w.user_team():
			team = t
			break
	return {"player": players[0] if not players.is_empty() else null, "team": team,
		"coach": int(a.coach) > 0, "haters": int(a.haters) > 0, "own": int(a.own) > 0 or teams_hit.has(w.user_team())}


## Your chip vs what you actually wrote: the text wins when it's clear.
## No tone buttons: what the post is, read from the words and who it names.
func _infer_tone(a: Dictionary, tg: Dictionary) -> String:
	var tp: PlayerData = tg.player
	var tt: TeamData = tg.team
	var mate := tp != null and _is_mate(tp)
	var rival := (tp != null and not mate) or (tt != null and tt != w.user_team())
	var hostile := int(a.insult) > 0 or (int(a.profanity) > 0 and float(a.harsh) > 0.25)
	var dig := hostile or int(a.negative) > 0
	if int(a.apology) > 0 and not hostile:
		return "apology"
	if bool(tg.coach) and dig:
		return "coach"
	if mate and dig:
		return "flame"
	if rival and (dig or int(a.challenge) > 0):
		return "callout"
	if bool(tg.haters) or (hostile and not rival and not mate):
		return "haters"
	# Hype is about your team: "we", "the boys", a teammate, or a lot of praise.
	if not rival and (bool(tg.own) or (mate and int(a.praise) > 0) or int(a.praise) >= 2):
		return "hype"
	return "neutral"


func _read_as(tone: String, tg: Dictionary) -> String:
	var tp: PlayerData = tg.player
	var tt: TeamData = tg.team
	var who := tp.player_name if tp != null else (tt.team_name if tt != null else "")
	match tone:
		"hype":
			return "Read as hyping up the team."
		"callout":
			return "Read as calling out %s." % (who if who != "" else "a rival")
		"flame":
			return "Read as going after %s in public." % (who if who != "" else "your own team")
		"coach":
			return "Read as criticising the coach."
		"haters":
			return "Read as firing back at the haters."
		"apology":
			return "Read as an apology."
	return ""


func _resolve_tone(chip: String, a: Dictionary, tg: Dictionary) -> Dictionary:
	var tp: PlayerData = tg.player
	var tt: TeamData = tg.team
	var mate := tp != null and _is_mate(tp)
	var rival_target := (tp != null and not mate) or tt != null
	var hostile := int(a.insult) > 0
	var tone := chip
	var note := ""
	if int(a.apology) > 0 and not hostile and chip != "apology":
		tone = "apology"
		note = "It reads as an apology."
	elif chip == "apology" and hostile:
		note = "An apology with insults in it? Nobody buys that."
	elif chip in ["hype", "neutral"] and hostile:
		if mate:
			tone = "flame"
		elif rival_target:
			tone = "callout"
		elif bool(tg.coach):
			tone = "coach"
		elif bool(tg.haters) or chip == "neutral":
			tone = "haters"
		if tone != chip:
			note = "That's not how it reads: it comes across as %s." % String(TONES[tone]).to_lower()
	elif chip == "neutral" and int(a.praise) > 0 and bool(tg.own) and not rival_target:
		tone = "hype"
	elif chip == "callout" and mate:
		tone = "flame"
		note = "%s is your own teammate: that's flaming a teammate." % tp.player_name
	elif chip == "flame" and tp != null and not mate:
		tone = "callout"
		note = "%s isn't your teammate: it reads as a call-out." % tp.player_name
	elif chip == "haters" and hostile and mate:
		tone = "flame"
		note = "Naming %s turns it into flaming a teammate." % tp.player_name
	elif chip in ["callout", "flame", "coach", "haters"] and not hostile and int(a.praise) > int(a.insult) + 1:
		tone = "neutral" if not bool(tg.own) else "hype"
		note = "Too nice to count as a dig."
	if tone == "flame" and w.teamless:
		tone = "haters" if not rival_target else "callout"
		note = "You don't have teammates right now."
	if tone == "coach" and w.teamless:
		tone = "haters"
		note = "You don't have a coach right now."
	return {"tone": tone, "note": note}


func _feed_reply(who: String, ln: Array, kind_: String, mult: float) -> Dictionary:
	var text: String = ln[0]
	if text == "":
		return {}
	if _trickle >= 0.0:
		_stamp_mine()
	w._post(who, text, kind_, mult)
	if _trickle >= 0.0 and not w.feed.is_empty():
		# First replies within seconds, the rest spread over the next minute or two.
		_trickle += w.rng.randf_range(2.5, 6.0) if _trickle < 1.0 else w.rng.randf_range(4.0, 16.0)
		var fr: Dictionary = w.feed[w.feed.size() - 1]
		fr["at"] = Time.get_unix_time_from_system() + _trickle
		fr["t0"] = fr["at"]
	feed_recent.append(String(ln[1]))
	while feed_recent.size() > 30:
		feed_recent.pop_front()
	if w.feed.is_empty():
		return {}
	var f: Dictionary = w.feed[w.feed.size() - 1]
	f["re"] = true
	return f


func _feed_lines(bank_key: String, n: int, slots: Dictionary, kind_: String) -> void:
	var bank: Array = ChatText.FEED.get(bank_key, [])
	for i in n:
		var v: String = ["chill", "toxic", "shy", "showman", "chill"][w.rng.randi() % 5] if kind_ != "toxic" else "toxic"
		_feed_reply(w._fan_handle(), ChatText.line(bank, v, slots, w.rng, feed_recent), kind_, 0.6 if kind_ == "toxic" else 0.9)


## The person you posted about answers (optionally rewritten by the local LLM).
func _target_reply(p: PlayerData, bank: Array, kind_: String, stance: String, slots: Dictionary) -> void:
	var ln: Array = ChatText.line(bank, ChatText.voice(p), slots, w.rng, feed_recent)
	var f := _feed_reply("@" + p.player_name, ln, kind_, 1.4)
	if llm_on and not f.is_empty():
		f["pending"] = true
		var ctx := _llm_ctx(p, {"callout": "hostile", "flame": "hurt", "apology": "accept", "praise": "warm"}.get(stance, stance), false)
		llm_jobs.append({"msg": f, "system": ChatText.llm_system(ctx) + "\nYou are replying publicly on social media to a post about you.",
			"user": _post_text, "fallback": String(f.text)})
		_cap_jobs()


# =============================================================================
# Hate speech: slurs in a post or a message
# =============================================================================

const HATE_FANS := ["This is disgusting. {me} needs to be gone.", "No place for this. Hope {team} do the right thing.",
	"Unfollowed. Absolutely vile from {me}.", "Deleting won't save you {me}, everyone saw it.",
	"Was a fan of {me}. Not anymore.", "Kids look up to these players. Shameful.", "Ban him. Simple as that.",
	"How do you write that and press post?", "{team} stay silent and they're complicit.", "Grim. Really grim.",
	"Every sponsor of {me} should be asked about this.", "Talent means nothing if you're like this."]
const HATE_PRESS := ["{me} under fire after posting a slur on social media. {team} say they are 'aware and investigating'.",
	"The league has opened a disciplinary case against {me} over a hateful post.",
	"Sponsors distance themselves from {me} after a slur in a now-deleted post.",
	"{me}'s post: fans, players and partners react with anger."]
const HATE_MATES := ["That's not who we are. I don't stand with that.", "Disappointed doesn't cover it.",
	"I've spoken to the team. That post doesn't represent any of us.", "Not ok. Not even close."]
const HATE_REPLY := ["what the fuck is wrong with you", "blocked. don't message me again", "screenshotted. good luck",
	"wow. ok. we're done", "you're actually disgusting", "reported."]


func _hate_slots() -> Dictionary:
	var ut := w.user_team()
	return {"me": w.user_player.player_name, "team": ut.team_name if ut != null and not w.teamless else "his club"}


func _fill(t: String, sl: Dictionary) -> String:
	for k in sl:
		t = t.replace("{%s}" % k, String(sl[k]))
	return t


## A slur in a public post: the post is pulled, the internet turns on you,
## every sponsor walks, the club suspends you (or releases you if it's not the
## first time), and nobody wants to sign you for a while.
func _hate_post(text: String) -> Dictionary:
	var me := w.user_player
	var sl := _hate_slots()
	hate_count += 1
	toxicity = 100.0
	var parts: Array = ["Your post was reported and removed."]
	var lost := int(w.fame * (0.18 + 0.07 * mini(hate_count, 4)))
	w.fame = maxi(50, w.fame - lost)
	parts.append("You lost %s followers." % World.fame_text(lost))
	w._post("@" + me.player_name, ChatText.censor(text) + "   [removed]", "me", 0.3)
	var lines := HATE_FANS.duplicate()
	lines.shuffle()
	for i in 4:
		_feed_reply(w._fan_handle(), [_fill(lines[i], sl), ""], "fan", 1.4)
	_feed_reply(World.OUTLET_HANDLES.pick_random(), [_fill(HATE_PRESS[w.rng.randi() % HATE_PRESS.size()], sl), ""], "press", 2.5)
	_hate_consequences(parts, "posting a slur", true)
	w._news("SCANDAL: you posted a slur. %s" % " ".join(parts.slice(1)))
	return {"ok": true, "msg": " ".join(parts)}


## A slur in a DM / the team chat / to the coach: they block you, and it
## gets out (always from the team chat or the coach, often from a DM).
func _hate_dm(th: Dictionary, key: String, p: PlayerData) -> String:
	var me := w.user_player
	toxicity = minf(100.0, toxicity + 45.0)
	th["blocked_until"] = w.stamp() + 10
	var who := String(th.title)
	if p != null:
		w._relate(p.uid, -80.0)
		_push(th, {"me": false, "who": p.player_name, "uid": p.uid, "text": HATE_REPLY[w.rng.randi() % HATE_REPLY.size()], "s": w.season, "w": w.week})
	elif key == "team":
		for q: PlayerData in mates():
			w._relate(q.uid, -40.0)
		var m0: Array = mates()
		if not m0.is_empty():
			var q0: PlayerData = m0[w.rng.randi() % m0.size()]
			_push(th, {"me": false, "who": q0.player_name, "uid": q0.uid, "text": "nah. that's going straight to management.", "s": w.season, "w": w.week})
	else:
		_push(th, {"me": false, "who": who, "uid": 0, "text": "We will be speaking to you about this formally.", "s": w.season, "w": w.week})
	var leaked := p == null or w.rng.randf() < (0.9 if _is_mate(p) else 0.6)
	if not leaked:
		return "%s has blocked you." % who
	hate_count += 1
	var parts: Array = ["%s has blocked you, and it got out." % who]
	var lost := int(w.fame * 0.12)
	w.fame = maxi(50, w.fame - lost)
	parts.append("You lost %s followers." % World.fame_text(lost))
	_feed_reply(World.OUTLET_HANDLES.pick_random(), [_fill("Screenshots show {me} using a slur in private messages.", _hate_slots()), ""], "press", 2.2)
	_hate_consequences(parts, "using a slur in messages", false)
	w._news("SCANDAL: your message with a slur leaked. %s" % " ".join(parts.slice(1)))
	return " ".join(parts)


func _hate_consequences(parts: Array, why: String, public: bool) -> void:
	var me := w.user_player
	# Every personal sponsor walks.
	for d: Dictionary in w.endorsements.duplicate():
		w.endorsements.erase(d)
		w._msg("endorse", "%s have dropped you" % d.brand, "%s have terminated your deal ($%s/wk) with immediate effect over %s." % [d.brand, World._fmt(int(d.weekly)), why], [["OK", "ok"]], me.uid)
		_feed_reply("@" + String(d.brand).replace(" ", ""), ["We have ended our partnership with %s, effective immediately. We do not tolerate hate speech." % me.player_name, ""], "brand", 2.0)
		parts.append("%s dropped you." % d.brand)
	if w.teamless:
		comeback = maxf(0.0, comeback - 50.0)
		parts.append("No club will touch you for now.")
		return
	var ut := w.user_team()
	for q: PlayerData in mates():
		w._relate(q.uid, -30.0)
		q.morale = maxf(0.0, q.morale - 6.0)
	if public and not mates().is_empty():
		var q1: PlayerData = mates()[w.rng.randi() % mates().size()]
		_feed_reply("@" + q1.player_name, [HATE_MATES[w.rng.randi() % HATE_MATES.size()], ""], "teammate", 1.6)
	w._trust(-35.0)
	var fine := mini(w.wallet, int(me.salary * 4 / 50) * 50)
	if fine > 0:
		w.wallet -= fine
		parts.append("%s fined you $%s." % [ut.team_name, World._fmt(fine)])
	_heat(3.0, why)
	if hate_count >= 2 or strikes >= 2:
		_feed_reply("@" + ut.short_name, ["%s has left the club with immediate effect." % me.player_name, ""], "club", 2.5)
		parts.append("%s have terminated your contract." % ut.team_name)
		release_user(why)
		return
	strikes = 2
	strike_stamp = w.stamp()
	w.forced_bench_until = w.stamp() + 4
	w._apply_coach()
	_feed_reply("@" + ut.short_name, ["%s has been suspended while the club deals with this internally." % me.player_name, ""], "club", 2.5)
	w._msg("bench", "Suspended", "%s have suspended you for four weeks and fined you over %s. Any repeat and your contract is terminated." % [ut.team_name, why], [["Accept it", "pm_sx_bench_ok"]], me.uid)
	parts.append("Suspended for 4 weeks; one more and you're out.")


## Brands don't like controversy: a harsh post can cost you a personal deal.
func _sponsor_risk(harsh: float, profanity: int, parts: Array) -> void:
	if w.endorsements.is_empty():
		return
	var p := maxf(0.0, harsh - 0.45) * 0.9 + maxf(0.0, toxicity - 50.0) / 200.0
	if profanity > 0:
		p *= 1.3
	if w.rng.randf() >= p:
		return
	var d: Dictionary = w.endorsements[w.rng.randi() % w.endorsements.size()]
	w.endorsements.erase(d)
	w._msg("endorse", "%s have dropped you" % d.brand, "After your latest post, %s have ended your deal ($%s/wk) with immediate effect. Brands watch what you say." % [d.brand, World._fmt(int(d.weekly))], [["OK", "ok"]], w.user_player.uid)
	_feed_reply("@" + String(d.brand).replace(" ", ""), ["We have ended our partnership with %s, effective immediately." % w.user_player.player_name, ""], "brand", 2.0)
	w._news("SPONSOR: %s dropped you over your post." % d.brand)
	parts.append("%s dropped your deal!" % d.brand)


# =============================================================================
# Inbox actions (pm_sx_*)
# =============================================================================

func resolve_pm(m: Dictionary, action: String, _other: PlayerData) -> String:
	var me := w.user_player
	var data: Dictionary = m.get("data", {})
	match action:
		"pm_sx_warn_ok":
			w._trust(3.0)
			heat = maxf(0.0, heat - 0.5)
			return "You promise to sort it out. Trust +3."
		"pm_sx_warn_talk":
			if w.coach_trust >= 30.0:
				heat = maxf(0.0, heat - 1.0)
				w._trust(1.0)
				return "A constructive chat. The coach eases off a little."
			return "The coach isn't in the mood to talk."
		"pm_sx_warn_push":
			_heat(1.5, "your attitude to the coach")
			w._trust(-8.0)
			toxicity = minf(100.0, toxicity + 5.0)
			me.morale = minf(100.0, me.morale + 2.0)
			return "You told them where to go. Trust -8. You're on thin ice."
		"pm_sx_bench_ok":
			w._trust(2.0)
			heat = maxf(0.0, heat - 0.7)
			return "You take it on the chin. Trust +2."
		"pm_sx_bench_public":
			w._gain_fame(int(500 * (w._lmult(w.user_team()) if not w.teamless else 1.0)))
			_heat(1.5, "going public about the club")
			w._trust(-6.0)
			w._post("@" + me.player_name, "Benched for 'discipline'. Make of that what you will.", "me", 2.0)
			w._post(World.OUTLET_HANDLES.pick_random(), "%s goes public after being dropped by %s." % [me.player_name, w.user_team().team_name], "press", 2.0)
			return "It's everywhere. Fans are split; the club is livid (trust -6)."
		"pm_sx_cut_ok":
			if w.teamless:
				return "You've already left."
			me.salary = int(me.salary * 0.8 / 50.0) * 50
			w._trust(5.0)
			return "Pay cut accepted ($%s/wk). The club appreciates it (trust +5)." % World._fmt(me.salary)
		"pm_sx_cut_no":
			if w.teamless:
				return "You've already left."
			if w.rng.randf() < 0.5:
				release_user("budget cuts", false)
				return "The club let you go to save money. You're a free agent."
			w._trust(-5.0)
			return "They backed down, for now. Trust -5."
		"pm_sx_trial_go":
			if not w.teamless:
				return "You've found a club already."
			trial = {"team": int(data.team), "until": w.stamp() + 1}
			return "Trial accepted: play %s's practice match on the Career page this week or next." % w.teams[int(data.team)].team_name
		"pm_sx_trial_no":
			return "You passed on the trial."
		"pm_sx_standin_go":
			if not w.teamless:
				return "You've found a club already."
			var t: TeamData = w.teams[int(data.team)]
			var weeks := int(data.get("weeks", 2))
			w._join_club(t, int(w.offer_wage(t) * 0.7 / 50.0) * 50, 1)
			me.contract_until = w.season
			me.promise_until = w.stamp() + weeks
			standin = {"team": int(data.team), "until": w.stamp() + weeks, "start": w.stamp()}
			w._apply_coach()
			w._news("STAND-IN: you join %s for %d weeks." % [t.team_name, weeks])
			return "You're in at %s for %d weeks. Impress and it could become permanent." % [t.team_name, weeks]
		"pm_sx_standin_no":
			return "You turned it down."
	return "Noted."


# =============================================================================
# Persistence
# =============================================================================

func to_dict() -> Dictionary:
	var th := {}
	for k: String in threads:
		var t: Dictionary = threads[k].duplicate(true)
		for m in t.msgs:
			(m as Dictionary).erase("pending")
		th[k] = t
	return {"threads": th, "seq": seq, "posts_stamp": posts_stamp, "posts_used": posts_used, "toxicity": toxicity,
		"strikes": strikes, "hate": hate_count, "heat": heat, "heat_notes": heat_notes.duplicate(), "strike_stamp": strike_stamp, "clean": clean_weeks,
		"together": weeks_together.duplicate(), "ex": ex_mates.duplicate(), "beef": team_beef.duplicate(), "interest": interest.duplicate(),
		"club_interest": club_interest.duplicate(), "comeback": comeback, "teamless_wk": weeks_teamless, "show": showmatch_stamp,
		"last_show": last_show.duplicate(true), "trial": trial.duplicate(), "standin": standin.duplicate(), "known": known_mates.keys(),
		"flamed": last_flamed, "apology": apology_stamp, "promise": promise_stamp, "ask": lineup_ask_stamp, "ctx": last_ctx.duplicate(),
		"feed_recent": feed_recent.duplicate(), "talk": talk.to_dict()}


static func _int_keys(d: Dictionary, as_float: bool) -> Dictionary:
	var out := {}
	for k in d:
		out[int(k)] = float(d[k]) if as_float else int(d[k])
	return out


static func from_dict(world: World, d: Dictionary) -> Social:
	var s := Social.new(world)
	var th: Dictionary = d.get("threads", {})
	for k in th:
		var t: Dictionary = th[k]
		var msgs: Array = []
		for m: Dictionary in t.get("msgs", []):
			msgs.append({"me": bool(m.get("me", false)), "who": String(m.get("who", "")), "uid": int(m.get("uid", 0)), "text": String(m.get("text", "")),
				"s": int(m.get("s", 1)), "w": int(m.get("w", 1)), "llm": bool(m.get("llm", false))})
		var rec: Array = []
		for r in t.get("recent", []):
			rec.append(String(r))
		s.threads[String(k)] = {"key": String(k), "uid": int(t.get("uid", 0)), "title": String(t.get("title", "")), "msgs": msgs,
			"unread": int(t.get("unread", 0)), "last": int(t.get("last", 0)), "eff_stamp": int(t.get("eff_stamp", 0)), "eff_n": int(t.get("eff_n", 0)),
			"sent_stamp": int(t.get("sent_stamp", 0)), "sent_n": int(t.get("sent_n", 0)), "recent": rec, "team": String(t.get("team", "")),
			"blocked_until": int(t.get("blocked_until", 0))}
	s.seq = int(d.get("seq", 1))
	s.posts_stamp = int(d.get("posts_stamp", 0))
	s.posts_used = int(d.get("posts_used", 0))
	s.toxicity = float(d.get("toxicity", 0.0))
	s.strikes = int(d.get("strikes", 0))
	s.hate_count = int(d.get("hate", 0))
	s.heat = float(d.get("heat", 0.0))
	for n in d.get("heat_notes", []):
		s.heat_notes.append(String(n))
	s.strike_stamp = int(d.get("strike_stamp", 0))
	s.clean_weeks = int(d.get("clean", 0))
	s.weeks_together = _int_keys(d.get("together", {}), false)
	var ex: Dictionary = d.get("ex", {})
	for k in ex:
		s.ex_mates[int(k)] = String(ex[k])
	s.team_beef = _int_keys(d.get("beef", {}), false)
	s.interest = _int_keys(d.get("interest", {}), true)
	s.club_interest = _int_keys(d.get("club_interest", {}), true)
	s.comeback = float(d.get("comeback", 0.0))
	s.weeks_teamless = int(d.get("teamless_wk", 0))
	s.showmatch_stamp = int(d.get("show", 0))
	s.last_show = d.get("last_show", {})
	var tr: Dictionary = d.get("trial", {})
	if not tr.is_empty():
		s.trial = {"team": int(tr.get("team", 0)), "until": int(tr.get("until", 0))}
	var st: Dictionary = d.get("standin", {})
	if not st.is_empty():
		s.standin = {"team": int(st.get("team", 0)), "until": int(st.get("until", 0)), "start": int(st.get("start", 0))}
	for u in d.get("known", []):
		s.known_mates[int(u)] = true
	s.last_flamed = int(d.get("flamed", 0))
	s.apology_stamp = int(d.get("apology", 0))
	s.promise_stamp = int(d.get("promise", 0))
	s.lineup_ask_stamp = int(d.get("ask", 0))
	s.last_ctx = d.get("ctx", {})
	if s.last_ctx.has("opp_idx"):
		s.last_ctx.opp_idx = int(s.last_ctx.opp_idx)
	for r in d.get("feed_recent", []):
		s.feed_recent.append(String(r))
	s.talk = ClubTalk.from_dict(s, d.get("talk", {}))
	return s
