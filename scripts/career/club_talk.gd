class_name ClubTalk
extends RefCounted
## Where My Player conversations lead: the coach weighing your case for a
## start, teammates going to the coach, asking to leave, other clubs' coaches
## following up (offers, pre-agreements, trials or a polite no), how every club
## sees you (gates real offers), and trash talk in DMs carrying into matches.
## Owned by Social (Social.talk); saved inside the social block.

const STYLES := ["players", "disciplinarian", "tactician"]
const STYLE_TEXT := {"players": "Players' coach", "disciplinarian": "Disciplinarian", "tactician": "Tactician"}
## How each coach weighs a case: performance, trust, tone of the ask, training.
const WEIGHTS := {
	"players": {"perf": 0.9, "trust": 0.8, "tone": 1.0, "train": 0.5, "demand": 1.0},
	"disciplinarian": {"perf": 0.9, "trust": 1.0, "tone": 1.3, "train": 1.0, "demand": 1.6},
	"tactician": {"perf": 1.5, "trust": 0.5, "tone": 0.5, "train": 0.6, "demand": 1.0},
}
const POLITE := ["please", "could", "would", "can i", "could i", "i think", "i feel", "i believe", "deserve", "earned", "because",
	"since", "ive been", "training", "trained", "practice", "practising", "practicing", "form", "rating", "stats", "numbers",
	"chance", "ready", "prove", "show you", "thanks", "thank you", "respect", "consider", "opportunity", "shot"]
const DEMAND := ["demand", "right now", "have to", "you must", "must start", "or else", "or i", "or ill", "should be starting",
	"ridiculous", "unacceptable", "joke", "disgrace", "pathetic", "i want to start now", "i deserve to start", "why the fuck", "wtf"]

## COACH_LINES[style][stance]. Slots: {me} {rival} {mr} {rr} {coach} {team}.
const COACH_LINES := {
	"players": {
		"start": ["You've made your case, {me}. You're starting this week. Go enjoy it.", "Fair enough. {rival} sits this one out, you're in. Don't let the boys down.",
			"I hear you. You start the next match. Show everyone what you just showed me."],
		"conditional": ["Not yet, but I like the attitude. Keep this up this week and you're in next week.", "Close. Give me another good week and the spot is yours.",
			"I'm not dropping {rival} on a message, but keep working like this and you'll start next week."],
		"earn": ["I get it, but {rival} is doing the job right now ({rr} vs your {mr}). Keep going.", "Your time will come. Right now the numbers say {rival}.",
			"Keep your head up and keep training. I see you."],
		"annoyed": ["Don't talk to me like that. That's not how this works.", "I'm on your side, but demands won't get you anywhere.", "Watch the tone, {me}."],
	},
	"disciplinarian": {
		"start": ["You asked properly and you've put the work in. You start this week. Don't make me regret it.", "Earned. You're in, {rival} is out. Same standards from you all week.",
			"Good. That's how a professional asks. You start the next match."],
		"conditional": ["Do the work this week, every session, and we'll talk about starting next week.", "Show me a full week of discipline first. Then you're in.",
			"One week. Perfect attendance, no noise. Then the spot is yours."],
		"earn": ["The lineup isn't a negotiation. {rival} is ahead of you on merit.", "Train harder than {rival} and the decision makes itself.",
			"Not this week. Earn it in practice, not in my messages."],
		"annoyed": ["Nobody demands a place in my team. That just cost you.", "You do not speak to me like that. Noted.", "Demands? You've just moved further down my list."],
	},
	"tactician": {
		"start": ["The numbers back you: {mr} over your last games against {rival}'s {rr}. You start.", "You're right, the data agrees. You're in this week.",
			"Your recent games make the case for you. Starting this week."],
		"conditional": ["You're close: {mr} against {rival}'s {rr}. One more good week and the numbers make it obvious.", "Keep those ratings up this week and you start next week.",
			"Nearly. Beat {rr} in your next match and you're in."],
		"earn": ["{rival} is at {rr} over the last games, you're at {mr}. Close that gap.", "The data says {rival}. Change the data.",
			"Look at the numbers: {rr} vs {mr}. That's my answer."],
		"annoyed": ["Emotion isn't an argument. Bring numbers next time.", "That's not a case, that's a tantrum. No.", "Shouting doesn't change your rating."],
	},
}
const COACH_ALREADY := ["You're already in the starting five. Keep it that way.", "You're starting. Focus on the game."]
const COACH_NO := ["Not while you're serving a disciplinary. You know why.", "After your behaviour? Not a chance right now."]
const COACH_PUSHY := ["You asked me already. Asking again doesn't help your case.", "Enough. The more you push, the less I want to listen."]
const COACH_KEPT := ["You kept it up. You're starting this week.", "Good week. As promised, you're in.", "You did what I asked. Starting this week."]
const COACH_NOT_KEPT := ["Not enough this week. Keep going.", "I didn't see enough this week. You stay out for now."]
const LEAVE_LINES := {
	"refuse": ["You're under contract and you're important here. You're going nowhere.", "No. You're one of our best and your deal runs until season {until}.",
		"Request denied. We built this team around you."],
	"list": ["If that's what you want, we'll put you on the transfer list. Clubs will be told.", "Fine. You're transfer-listed. Let's see who comes in for you.",
		"Understood. We'll listen to offers for you."],
	"terminate": ["Fine by us. We're terminating your contract. Good luck.", "You want out? You're out. The club will release you today.",
		"Honestly? We were thinking the same. Your contract is terminated."],
	"again": ["You've had your answer.", "We've already dealt with this."],
	"listed": ["You're already on the list. Be patient."],
}
## Other clubs' coaches. Slots: {me} {team} {via} {reason} {signed} {wage}.
const EXT_LINES := {
	"offer": ["{via} told me about you. We'd like to sign you: ${wage}/wk. It's in your offers.", "Hi {me}, coach of {team} here. We've made you an offer, check your Career page.",
		"I've watched your games and {via} vouched for you. There's a contract waiting for you."],
	"pre": ["{via} mentioned you. We can't sign anyone until the window opens, but we'll agree terms now: ${wage}/wk, and the offer arrives when it opens.",
		"We want you at {team}. The window's shut, so consider this a pre-agreement. The offer comes the day it opens."],
	"trial": ["{via} says you're worth a look. Come in for a trial week and show us.", "We're not sure yet, but we'll give you a trial. Check your inbox."],
	"no_level": ["Thanks for your interest, but you're not at our level yet. Keep improving.", "Honestly, our starters are a step above you right now. Maybe next season."],
	"no_toxic": ["We've seen what you post. We can't bring that into our dressing room.", "Your reputation online is a problem for our sponsors. Sorry."],
	"no_signed": ["Bad timing: we've just signed {signed} for your role.", "We just brought in {signed}. No room right now, sorry."],
	"no_wont": ["After {reason}? No.", "Not interested, {me}. {reason} isn't something we forget.", "Don't waste your time. {reason}."],
	"reply": ["The offer stands. Check your Career page.", "We'll be in touch.", "Our decision is made, {me}.", "Talk to your agent, then decide."],
}
const MATE_START := ["coach says you're starting this week, let's go", "heard coach is putting you in. about time", "you're in the five this week apparently. don't waste it",
	"coach just told us you're starting. big week"]
const MATE_CHECKIN := ["you good after the bench thing?", "heard about the suspension. keep your head down and you'll be back", "that disciplinary is rough. we need you back"]
const VIA_LINES := ["told our coach about you. he's going to message you", "our coach wants to talk to you", "mentioned you to the coach. check your messages"]
const JOIN_WONT := ["after what you said about us? no chance", "our coach won't even hear your name, sorry", "lol no. nobody at {team} wants you after that"]

var _sref: WeakRef
var s: Social:
	get:
		return _sref.get_ref() as Social if _sref != null else null
var w: World:
	get:
		return s.w if s != null else null

var start_until := 0 ## The coach starts you up to this stamp.
var start_granted := 0
var conditional := {} ## {made, need, rival}
var week_trained := false ## Training in the week a conditional promise covers.
var complaints := 0 ## Teammates' complaints to the coach (recent).
var complaint_stamp := 0
var coach_insults := 0
var insult_stamp := 0
var leave_stamp := 0
var club_events := {} ## team index -> [{d, why, until}] (until: absolute week)
var left_bad := {} ## team index -> true: clubs you left on bad terms
var followups: Array = [] ## {due, kind, ...}: messages that come later
var pre_agreements: Array = [] ## {team, wage, years}
var trash := {} ## uid -> {team, mod, leaked, until}


func _init(social: Social) -> void:
	_sref = weakref(social)


static func coach_style(t: TeamData) -> String:
	if t == null:
		return "players"
	return STYLES[absi(hash(t.team_name + "/coachstyle")) % STYLES.size()]


func _now() -> int:
	return w._weeks_at(w.stamp())


func _coach_who(t: TeamData) -> String:
	return "Coach %s" % s.coach_name(t)


func _say(th: Dictionary, bank: Array, slots: Dictionary, who: String) -> Dictionary:
	return s._bot_say(th, null, ChatText.line(bank, "pro", slots, w.rng, th.recent), "coach", "", who)


# =============================================================================
# 1. The coach weighs your case for starting
# =============================================================================

## The player keeping you out: the starter in your role, else the weakest starter.
func rival_starter() -> PlayerData:
	var me := w.user_player
	var ut := w.user_team()
	var best: PlayerData = null
	var weakest: PlayerData = null
	for p in ut.starters(5):
		if p.is_user:
			continue
		if p.role == me.role and (best == null or p.rating_exact() < best.rating_exact()):
			best = p
		if weakest == null or ut.lineup_score(p) < ut.lineup_score(weakest):
			weakest = p
	return best if best != null else weakest


static func recent_avg(p: PlayerData, n: int = 5) -> float:
	var sum := 0.0
	var k := 0
	for i in range(p.match_log.size() - 1, -1, -1):
		if k >= n:
			break
		sum += float(p.match_log[i].r)
		k += 1
	return sum / k if k > 0 else p.avg_recent_rating()


## Tone of the ask: + polite/argued, - demanding/insulting.
static func ask_tone(a: Dictionary) -> float:
	var n: String = a.n
	var polite := mini(3, ChatText.count_kw(n, POLITE))
	var demand := ChatText.count_kw(n, DEMAND)
	var t := 0.25 * polite - 0.5 * demand - 0.35 * int(a.profanity) - 1.0 * int(a.insult) - (0.4 if float(a.caps) > 0.6 else 0.0)
	return clampf(t, -2.0, 1.0)


## The coach's view of your case: score and the numbers behind it.
func lineup_case(a: Dictionary) -> Dictionary:
	var me := w.user_player
	var style := coach_style(w.user_team())
	var wt: Dictionary = WEIGHTS[style]
	var riv := rival_starter()
	var mr := recent_avg(me)
	var rr := recent_avg(riv) if riv != null else 1.0
	var perf := (mr - rr) * 2.5 + (me.form - (riv.form if riv != null else 0.0)) / 4.0 + (me.rating_exact() - (riv.rating_exact() if riv != null else me.rating_exact())) / 6.0
	var train := 0.0
	if w.trained_this_week:
		train = 0.5 if String(w.last_training.get("intensity", "")) == "Hard" else 0.3
	var trust := (w.coach_trust - 50.0) / 25.0
	var tone := ask_tone(a)
	var tone_w := float(wt.tone) * (float(wt.demand) if tone < 0.0 else 1.0)
	var score := float(wt.perf) * perf + float(wt.trust) * trust + tone_w * tone + float(wt.train) * train
	return {"score": score, "rival": riv, "mr": mr, "rr": rr, "tone": tone, "style": style}


func _case_slots(c: Dictionary) -> Dictionary:
	var riv: PlayerData = c.rival
	return {"me": w.user_player.player_name, "rival": riv.player_name if riv != null else "the starter", "mr": "%.2f" % float(c.mr),
		"rr": "%.2f" % float(c.rr), "coach": s.coach_name(w.user_team()), "team": w.user_team().team_name}


## You ask the coach for a start. insult: the ask came with an insult (the
## flame consequences are applied by the caller). Returns the outcome line.
func ask_to_start(th: Dictionary, a: Dictionary, insult: bool) -> String:
	var me := w.user_player
	var ut := w.user_team()
	var who := _coach_who(ut)
	var c := lineup_case(a)
	var style: String = c.style
	var slots := _case_slots(c)
	var lines: Dictionary = COACH_LINES[style]
	if w.user_starting() and start_until < w.stamp():
		_say(th, COACH_ALREADY, slots, who)
		return "You're already starting."
	if w.forced_bench_until >= w.stamp() or s.strikes >= 2:
		_say(th, COACH_NO, slots, who)
		return "No chance while you're on a disciplinary."
	if s.lineup_ask_stamp == w.stamp():
		w._trust(-2.0)
		_say(th, COACH_PUSHY, slots, who)
		return "Coach trust -2: you're being pushy."
	s.lineup_ask_stamp = w.stamp()
	var score: float = c.score
	if insult or float(c.tone) <= -0.5:
		var hit := 4.0 + (3.0 if style == "disciplinarian" else 0.0) + (4.0 if insult else 0.0)
		w._trust(-hit)
		s._heat(0.4 if not insult else 0.0, "demanding a place from the coach")
		_say(th, lines.annoyed, slots, who)
		return "The coach didn't like that. Trust -%d." % int(hit)
	if score >= 1.0 and w.stamp() - start_granted >= 3:
		grant_start(w.stamp() + 1)
		_say(th, lines.start, slots, who)
		_mate_mention()
		return "The coach will start you%s." % ("" if w.user_starting() else " (lineup updates for the match)")
	if score >= 0.3:
		conditional = {"made": w.stamp(), "need": maxf(0.95, float(c.rr)), "rival": (c.rival as PlayerData).uid if c.rival != null else 0}
		_say(th, lines.conditional, slots, who)
		w._trust(1.0)
		return "Keep it up this week and you start next week."
	_say(th, lines.earn, slots, who)
	return "Not yet: %s is ahead on merit (%.2f vs your %.2f)." % [slots.rival, float(c.rr), float(c.mr)]


func grant_start(until: int) -> void:
	start_until = until
	start_granted = w.stamp()
	w._apply_coach()
	w._news("LINEUP: the coach will start you%s." % (" this week" if until <= w.stamp() else ""))


func start_bonus() -> float:
	return 40.0 if start_until >= w.stamp() else 0.0


## A teammate passes the news on in the team chat.
func _mate_mention() -> void:
	var cur := s.mates()
	if cur.is_empty():
		return
	var m: PlayerData = cur[w.rng.randi() % cur.size()]
	var th := s.thread("team")
	s._bot_say(th, m, ChatText.line(MATE_START, ChatText.voice(m), s._slots(m), w.rng, th.recent), "smalltalk", "warm")


# =============================================================================
# 2. Escalations: teammates go to the coach; asking to leave
# =============================================================================

## You flamed in the team chat. Teammates may report you to the coach.
func on_team_flame(target: PlayerData, harsh: float) -> String:
	if w.stamp() - complaint_stamp > 4:
		complaints = 0
	complaints += 1
	var chance := 0.35 + 0.25 * float(complaints - 1) + (0.2 if target != null else 0.0) + harsh * 0.2
	if w.rng.randf() >= chance:
		return ""
	complaint_stamp = w.stamp()
	var cur := s.mates()
	if cur.is_empty():
		return ""
	var reporter: PlayerData = target if target != null else cur[w.rng.randi() % cur.size()]
	var hit := 5.0 + 3.0 * complaints
	w._trust(-hit)
	s._heat(1.0 + 0.4 * complaints, "teammates complained about you to the coach")
	s.toxicity = minf(100.0, s.toxicity + 5.0)
	var ut := w.user_team()
	w._msg("complaint", "%s went to the coach about you" % reporter.player_name,
		"%s told %s about your messages in the team chat. The coach's trust in you dropped (-%d) and it's on your record. Keep it up and it ends in a disciplinary or worse." % [reporter.player_name, _coach_who(ut), int(hit)],
		[["OK", "ok"]], reporter.uid)
	w._news("DRESSING ROOM: %s complained to the coach about you." % reporter.player_name)
	var cth := s.thread("coach")
	s._bot_say(cth, null, ["%s came to see me about the team chat. Sort yourself out, %s." % [reporter.player_name, w.user_player.player_name], ""], "coach", "furious", _coach_who(ut))
	_escalate("teammates complaining about you")
	return "%s went to the coach about you (trust -%d)." % [reporter.player_name, int(hit)]


## You insulted the coach. Repeat offences end in a disciplinary or release.
func on_coach_insult() -> String:
	if w.stamp() - insult_stamp > 4:
		coach_insults = 0
	coach_insults += 1
	insult_stamp = w.stamp()
	if coach_insults >= 2:
		return _escalate("insulting the coach")
	return ""


## Straight to the discipline path: warning -> disciplinary bench -> release.
func _escalate(why: String) -> String:
	var me := w.user_player
	var ut := w.user_team()
	if w.teamless:
		return ""
	if s.strikes == 0:
		s.strikes = 1
		s.strike_stamp = w.stamp()
		w._msg("warning", "Warning from %s" % ut.team_name, "The coach has had enough of %s. \"This is your warning. One more and you lose your place.\"" % why,
			[["Promise to improve", "pm_sx_warn_ok"], ["Tell them where to go", "pm_sx_warn_push"]], me.uid)
		w._news("WARNING: %s have warned you about %s." % [ut.team_name, why])
		return "Formal warning."
	if s.strikes == 1 or w.forced_bench_until >= w.stamp():
		if s.strikes == 1:
			s.strikes = 2
			s.strike_stamp = w.stamp()
			w.forced_bench_until = w.stamp() + 2
			w._apply_coach()
			w._msg("bench", "Dropped: disciplinary", "%s have dropped you for two weeks over %s. One more and you're out." % [ut.team_name, why],
				[["Accept it", "pm_sx_bench_ok"], ["Go public about it", "pm_sx_bench_public"], ["Request a transfer", "pm_request"]], me.uid)
			w._news("DROPPED: %s bench you over %s." % [ut.team_name, why])
			followups.append({"due": w.stamp() + 1, "kind": "mate_checkin"})
			return "Dropped for two weeks."
		return ""
	note_club(w.team_index(ut), -35.0, "you were kicked out", 40)
	left_bad[w.team_index(ut)] = true
	s.release_user(why)
	return "Released."


## "Release me / I want to leave / transfer me" to the coach.
func ask_to_leave(th: Dictionary) -> String:
	var me := w.user_player
	var ut := w.user_team()
	var who := _coach_who(ut)
	var slots := {"me": me.player_name, "until": str(me.contract_until), "team": ut.team_name}
	if w.transfer_request:
		_say(th, LEAVE_LINES.listed, slots, who)
		return "You're already transfer-listed."
	if w.stamp() - leave_stamp < 3 and leave_stamp > 0:
		_say(th, LEAVE_LINES.again, slots, who)
		return "The club has already answered."
	leave_stamp = w.stamp()
	var by := ut.roster.duplicate()
	by.sort_custom(func(x: PlayerData, y: PlayerData) -> bool: return x.rating_exact() > y.rating_exact())
	var key := by.find(me) in [0, 1] and me.contract_until > w.season
	if key and w.coach_trust >= 35.0:
		w._trust(-3.0)
		_say(th, LEAVE_LINES.refuse, slots, who)
		w._msg("info", "%s refuse to let you go" % ut.team_name, "You asked to leave. The club says you're too important and your contract runs until season %d." % me.contract_until, [["OK", "ok"]], me.uid)
		w._news("TRANSFER: %s refuse your request to leave." % ut.team_name)
		return "Refused: you're a key player with a long contract."
	if w.coach_trust < 35.0:
		_say(th, LEAVE_LINES.terminate, slots, who)
		note_club(w.team_index(ut), -15.0, "you walked out", 30)
		s.release_user("you asked to leave", false)
		return "%s terminated your contract. You're a free agent." % ut.team_name
	w.transfer_request = true
	w._trust(-4.0)
	_say(th, LEAVE_LINES.list, slots, who)
	w._msg("info", "You've been transfer-listed", "%s have agreed to sell you. Clubs are being told; offers should arrive over the next weeks (accept them on the Career page, in a window)." % ut.team_name, [["OK", "ok"]], me.uid)
	w._news("TRANSFER LIST: %s put you up for sale at your request." % ut.team_name)
	w._wire("%s transfer-list %s" % [ut.team_name, me.player_name], "deal")
	followups.append({"due": w.stamp() + 1, "kind": "listed"})
	followups.append({"due": w.stamp() + 2, "kind": "listed"})
	return "You're transfer-listed: expect offers in the next weeks."


func _listed_offer() -> void:
	if w.teamless or not w.transfer_request:
		return
	var me := w.user_player
	var ut := w.user_team()
	var pool: Array = []
	for i in w.teams.size():
		var t: TeamData = w.teams[i]
		if t == ut or String(attitude(i).label) == "won't sign":
			continue
		if w.offers.any(func(o: Dictionary) -> bool: return int(o.team) == i):
			continue
		pool.append(i)
	if pool.is_empty():
		return
	# The clubs closest to your level come in for you.
	pool.sort_custom(func(x: int, y: int) -> bool: return absf(w.teams[x].rating_exact() - me.rating_exact()) < absf(w.teams[y].rating_exact() - me.rating_exact()))
	var idx: int = pool[w.rng.randi() % mini(8, pool.size())]
	w._add_offer(idx, "%s saw you on the transfer list." % w.teams[idx].team_name, true)


# =============================================================================
# 3. Other clubs: a player mentions you to their coach
# =============================================================================

func queue_ext_coach(idx: int, via: PlayerData) -> void:
	for f: Dictionary in followups:
		if String(f.kind) == "ext_coach" and int(f.team) == idx:
			return
	followups.append({"due": w.stamp() + 1, "kind": "ext_coach", "team": idx, "via": via.uid if via != null else 0})


func ext_key(idx: int) -> String:
	return "xc:%d" % idx


func _ext_coach(idx: int, via_uid: int) -> void:
	var me := w.user_player
	var t: TeamData = w.teams[idx]
	if not w.teamless and t == w.user_team():
		return
	var via := w.find_player(via_uid)
	var th := s.thread(ext_key(idx))
	var who := "%s (%s)" % [_coach_who(t), t.short_name]
	var att := attitude(idx)
	var slots := {"me": me.player_name, "team": t.team_name, "via": via.player_name if via != null else "One of my players",
		"reason": String(att.reasons[0]) if not (att.reasons as Array).is_empty() else "your reputation", "signed": "someone", "wage": World._fmt(w.offer_wage(t))}
	var weakest := INF
	for p in t.starters(5):
		weakest = minf(weakest, p.rating_exact())
	var signed: PlayerData = null
	for p in t.roster:
		if not p.is_user and p.joined >= w.stamp() - 2 and p.role == me.role:
			signed = p
	if signed != null:
		slots.signed = signed.player_name
	var outcome := "offer"
	if String(att.label) == "won't sign":
		outcome = "no_wont"
	elif s.toxicity > 55.0 or s.hate_count > 0:
		outcome = "no_toxic"
	elif me.rating_exact() < weakest - 5.0:
		outcome = "trial" if w.teamless else "no_level"
	elif signed != null:
		outcome = "no_signed"
	elif not (w.window_open() or w.teamless or w.free_agency):
		outcome = "pre"
	if via != null and outcome in ["offer", "pre", "trial"]:
		var vth := s.thread("p:%d" % via.uid)
		s._bot_say(vth, via, ChatText.line(VIA_LINES, ChatText.voice(via), s._slots(via), w.rng, vth.recent), "smalltalk", "warm")
	s._bot_say(th, null, ChatText.line(EXT_LINES[outcome], "pro", slots, w.rng, th.recent), "coach", outcome, who)
	match outcome:
		"offer":
			w._add_offer(idx, "Coach of %s (via %s)." % [t.team_name, String(slots.via)], true)
			w._msg("info", "%s have made you an offer" % t.team_name, "After %s mentioned you, %s's coach got in touch with a contract offer (Career page)." % [slots.via, t.team_name], [["OK", "ok"]], me.uid)
		"pre":
			pre_agreements = pre_agreements.filter(func(x: Dictionary) -> bool: return int(x.team) != idx)
			pre_agreements.append({"team": idx, "wage": w.offer_wage(t), "years": w.rng.randi_range(1, 3)})
			w._msg("info", "Pre-agreement with %s" % t.team_name, "%s want you but the transfer window is closed. Their offer arrives when it opens (%s)." % [t.team_name, w.window_text()], [["OK", "ok"]], me.uid)
			w._news("PRE-AGREEMENT: %s will offer you a deal when the window opens." % t.team_name)
		"trial":
			w._msg("trial", "Trial invite: %s" % t.team_name, "%s's coach invites you for a trial week. Play their practice match (Career page): a good performance earns a contract offer." % t.team_name,
				[["Accept the trial", "pm_sx_trial_go"], ["Decline", "pm_sx_trial_no"]], me.uid, {"team": idx})
		_:
			w._news("%s turned you down." % t.team_name)


## You message another club's coach.
func ext_reply(th: Dictionary, idx: int, a: Dictionary, intent: String) -> String:
	var t: TeamData = w.teams[idx]
	var who := "%s (%s)" % [_coach_who(t), t.short_name]
	if intent == "flame" or int(a.insult) > 0:
		note_club(idx, -20.0, "you insulted their coach", 20)
		s.toxicity = minf(100.0, s.toxicity + 6.0)
		s._bot_say(th, null, ["Good luck finding a club with that attitude.", ""], "coach", "furious", who)
		return "%s won't forget that." % t.team_name
	var slots := {"me": w.user_player.player_name, "team": t.team_name}
	s._bot_say(th, null, ChatText.line(EXT_LINES.reply, "pro", slots, w.rng, th.recent), "coach", "neutral", who)
	return ""


# =============================================================================
# 4. How clubs see you
# =============================================================================

func note_club(idx: int, d: float, why: String, weeks: int) -> void:
	if idx < 0:
		return
	var arr: Array = club_events.get(idx, [])
	arr.append({"d": d, "why": why, "until": _now() + weeks})
	while arr.size() > 8:
		arr.pop_front()
	club_events[idx] = arr


## {score, label, reasons}. label: interested / neutral / wary / won't sign.
func attitude(idx: int) -> Dictionary:
	var t: TeamData = w.teams[idx]
	var score := 0.0
	var reasons: Array = []
	var why := {}
	for e: Dictionary in club_events.get(idx, []):
		if int(e.until) < _now():
			continue
		score += float(e.d)
		why[String(e.why)] = float(why.get(String(e.why), 0.0)) + float(e.d)
	for k: String in why:
		reasons.append(k)
	if int(s.team_beef.get(idx, 0)) > 0:
		score -= 20.0
		reasons.append("bad blood between you")
	if left_bad.has(idx):
		score -= 35.0
		reasons.append("you left on bad terms")
	if s.hate_count > 0:
		score -= minf(90.0, 40.0 * s.hate_count)
		reasons.append("hate speech")
	if s.toxicity > 30.0:
		score -= (s.toxicity - 30.0) * 0.7
		reasons.append("toxic reputation")
	for p in t.roster:
		if p.is_user:
			continue
		var st := s.strength(p)
		if st >= Social.FRIEND_AT:
			score += 12.0
			reasons.append("friend of %s" % p.player_name)
		elif st <= Social.RIVAL_AT:
			score -= 8.0
			reasons.append("%s can't stand you" % p.player_name)
	var ci := float(s.club_interest.get(idx, 0.0))
	if ci >= 0.1:
		score += ci * 30.0
		reasons.append("you've shown interest")
	var label := "neutral"
	if score >= 20.0:
		label = "interested"
	elif score <= -45.0:
		label = "won't sign"
	elif score <= -15.0:
		label = "wary"
	# Negative reasons first.
	reasons.sort_custom(func(x: String, y: String) -> bool: return _reason_sign(x) < _reason_sign(y))
	return {"score": score, "label": label, "reasons": reasons, "team": t}


static func _reason_sign(r: String) -> int:
	return 1 if r.begins_with("friend of") or r == "you've shown interest" else 0


## Real offers are gated: never from "won't sign", fewer from "wary".
func allows_offer(idx: int) -> bool:
	var lab := String(attitude(idx).label)
	if lab == "won't sign":
		return false
	if lab == "wary":
		return w.rng.randf() < 0.4
	return true


## Clubs with an opinion of you, strongest first (for the Career page).
func attitudes(limit: int = 12) -> Array:
	var out: Array = []
	var ut := w.user_team()
	for i in w.teams.size():
		if not w.teamless and w.teams[i] == ut:
			continue
		var at := attitude(i)
		if absf(float(at.score)) >= 1.0:
			out.append(at)
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return absf(float(x.score)) > absf(float(y.score)))
	return out.slice(0, limit)


# =============================================================================
# 5. Trash talk in DMs carries into the match
# =============================================================================

## You flamed a player at another club in DMs.
func note_trash_dm(p: PlayerData, _harsh: float) -> String:
	var t := w.owner_of(p)
	if t == null or (not w.teamless and t == w.user_team()):
		return ""
	var idx := w.team_index(t)
	var v := ChatText.voice(p)
	var mod := 2.0
	var how := "fired up"
	if v == "shy" or (v == "chill" and w.rng.randf() < 0.5):
		mod = -2.0
		how = "rattled"
	var leaked := false # DMs stay private (no screenshots).
	trash[p.uid] = {"team": idx, "mod": mod, "leaked": leaked, "until": _now() + 4}
	note_club(idx, -6.0, "you trash-talked %s" % p.player_name, 16)
	if leaked:
		note_club(idx, -20.0, "you trash-talked their players", 16)
		w._post(World.OUTLET_HANDLES.pick_random(), "Screenshots: %s trash-talking %s (%s) in DMs." % [w.user_player.player_name, p.player_name, t.short_name], "press", 1.6)
		w._news("LEAKED: your DMs to %s are out. %s are fired up." % [p.player_name, t.team_name])
		return "%s leaked your messages: all of %s are fired up and the club thinks less of you." % [p.player_name, t.team_name]
	return "%s looks %s for your next meeting." % [p.player_name, how]


## Before your match: trash-talked opponents get fired up or tilted.
func apply_match_mods(opp: TeamData) -> void:
	var idx := w.team_index(opp)
	var team_up := false
	for uid: int in trash.keys():
		var e: Dictionary = trash[uid]
		if int(e.until) < _now():
			trash.erase(uid)
			continue
		if int(e.team) != idx:
			continue
		var p := w.find_player(uid)
		if p != null and opp.roster.has(p):
			p.match_mod += float(e.mod)
			w._news("MATCHDAY: %s %s after your messages." % [p.player_name, "is fired up" if float(e.mod) > 0.0 else "looks rattled"])
		if bool(e.leaked):
			team_up = true
		trash.erase(uid)
	if team_up:
		for q in opp.roster:
			q.match_mod += 1.0
		w._news("MATCHDAY: %s are fired up after your leaked DMs." % opp.team_name)


# =============================================================================
# Follow-ups (start of each week)
# =============================================================================

func deliver() -> void:
	if w.user_player == null or w.retired:
		return
	s._unprompted = true
	# Conditional promise from last week.
	if not conditional.is_empty() and w.stamp() > int(conditional.made):
		var me := w.user_player
		var ok := week_trained
		for e in me.match_log:
			if int(e.s) * 100 + int(e.w) >= int(conditional.made) and float(e.r) >= float(conditional.need):
				ok = true
		var th := s.thread("coach")
		var who := _coach_who(w.user_team())
		if not w.teamless:
			if ok and w.forced_bench_until < w.stamp():
				grant_start(w.stamp())
				_say(th, COACH_KEPT, {}, who)
				_mate_mention()
			else:
				_say(th, COACH_NOT_KEPT, {}, who)
		conditional = {}
	week_trained = false
	for pa: Dictionary in pre_agreements.duplicate():
		if w.window_open() or w.teamless:
			pre_agreements.erase(pa)
			var idx := int(pa.team)
			w._add_offer(idx, "Pre-agreement: %s, as promised." % w.teams[idx].team_name, true)
			w._msg("info", "%s's offer has arrived" % w.teams[idx].team_name, "The window is open: the pre-agreed offer from %s is on your Career page." % w.teams[idx].team_name, [["OK", "ok"]], w.user_player.uid)
	var due: Array = followups.filter(func(f: Dictionary) -> bool: return int(f.due) <= w.stamp())
	followups = followups.filter(func(f: Dictionary) -> bool: return int(f.due) > w.stamp())
	for f: Dictionary in due:
		match String(f.kind):
			"ext_coach":
				_ext_coach(int(f.team), int(f.get("via", 0)))
			"listed":
				_listed_offer()
			"mate_checkin":
				var fr: Array = s.mates().filter(func(p: PlayerData) -> bool: return w.relation(p.uid) >= 0.0)
				if not fr.is_empty():
					var m: PlayerData = fr[w.rng.randi() % fr.size()]
					var th2 := s.thread("p:%d" % m.uid)
					s._bot_say(th2, m, ChatText.line(MATE_CHECKIN, ChatText.voice(m), s._slots(m), w.rng, th2.recent), "smalltalk", "warm")
	s._unprompted = false


# =============================================================================
# Persistence
# =============================================================================

func to_dict() -> Dictionary:
	return {"start": start_until, "granted": start_granted, "cond": conditional.duplicate(), "trained": week_trained, "complaints": complaints,
		"cstamp": complaint_stamp, "insults": coach_insults, "istamp": insult_stamp, "leave": leave_stamp, "events": club_events.duplicate(true),
		"left_bad": left_bad.keys(), "followups": followups.duplicate(true), "pre": pre_agreements.duplicate(true), "trash": trash.duplicate(true)}


static func from_dict(social: Social, d: Dictionary) -> ClubTalk:
	var t := ClubTalk.new(social)
	t.start_until = int(d.get("start", 0))
	t.start_granted = int(d.get("granted", 0))
	var c: Dictionary = d.get("cond", {})
	if not c.is_empty():
		t.conditional = {"made": int(c.get("made", 0)), "need": float(c.get("need", 1.0)), "rival": int(c.get("rival", 0))}
	t.week_trained = bool(d.get("trained", false))
	t.complaints = int(d.get("complaints", 0))
	t.complaint_stamp = int(d.get("cstamp", 0))
	t.coach_insults = int(d.get("insults", 0))
	t.insult_stamp = int(d.get("istamp", 0))
	t.leave_stamp = int(d.get("leave", 0))
	var ev: Dictionary = d.get("events", {})
	for k in ev:
		var arr: Array = []
		for e: Dictionary in ev[k]:
			arr.append({"d": float(e.get("d", 0.0)), "why": String(e.get("why", "")), "until": int(e.get("until", 0))})
		t.club_events[int(k)] = arr
	for k in d.get("left_bad", []):
		t.left_bad[int(k)] = true
	for f: Dictionary in d.get("followups", []):
		t.followups.append({"due": int(f.get("due", 0)), "kind": String(f.get("kind", "")), "team": int(f.get("team", -1)), "via": int(f.get("via", 0))})
	for pa: Dictionary in d.get("pre", []):
		t.pre_agreements.append({"team": int(pa.get("team", 0)), "wage": int(pa.get("wage", 0)), "years": int(pa.get("years", 1))})
	var tr: Dictionary = d.get("trash", {})
	for k in tr:
		var e2: Dictionary = tr[k]
		t.trash[int(k)] = {"team": int(e2.get("team", -1)), "mod": float(e2.get("mod", 0.0)), "leaked": bool(e2.get("leaked", false)), "until": int(e2.get("until", 0))}
	return t
