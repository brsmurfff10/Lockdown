class_name PlayerData
extends Resource
## A player in the league. Eight attributes (20-100) average into the
## player's rating. Attributes drive in-match behaviour for bots and the
## mechanical side (spread, recoil, movement) for the human player too.

const STAT_KEYS := ["aim", "flick", "preaim", "recoil", "reaction", "movement", "positioning", "decision", "utility"]
const STAT_NAMES := {
	"aim": "Aim",
	"flick": "Flick Speed",
	"preaim": "Preaim",
	"recoil": "Recoil Control",
	"reaction": "Reaction Time",
	"movement": "Movement",
	"positioning": "Positioning",
	"decision": "Decision Making",
	"utility": "Utility",
}
const STAT_HELP := {
	"aim": "First-shot accuracy.",
	"flick": "Time to target: how fast your crosshair swings onto an enemy, and how soon a shot after a flick is accurate.",
	"preaim": "Crosshair placement: aiming where enemies will appear, so there's less to flick. Holding an angle steadies your first shot.",
	"recoil": "How much your spray blooms while holding fire.",
	"reaction": "How fast you notice enemies, shake off getting shot (aim punch), and track targets.",
	"movement": "Run speed and accuracy while moving.",
	"positioning": "Field of view, holding angles, patience and peeking discipline.",
	"decision": "Rotations, retakes, buys and mid-round calls. For you: how well you read your team's calls on the radar.",
	"utility": "Grenades: how often bots buy and use them, and how accurately they land (yours too).",
}
## Short table-header names -> stat key.
const STAT_SHORT := {"Aim": "aim", "Flk": "flick", "Pre": "preaim", "Rcl": "recoil", "Rct": "reaction",
	"Mov": "movement", "Pos": "positioning", "Dec": "decision", "Utl": "utility"}
const ROLES := ["Entry", "Rifler", "AWPer", "Support", "Lurker"]
const ROLE_BIAS := {
	"Entry": {"reaction": 6, "movement": 6, "aim": 3, "flick": 4, "positioning": -4, "utility": -4},
	"Rifler": {"aim": 4, "recoil": 6, "preaim": 3, "utility": -3},
	"AWPer": {"aim": 7, "flick": 6, "reaction": 4, "positioning": 3, "recoil": -6, "movement": -4},
	"Support": {"utility": 8, "decision": 4, "positioning": 3, "aim": -4, "flick": -3, "reaction": -3},
	"Lurker": {"positioning": 7, "decision": 4, "preaim": 3, "movement": -2, "utility": -3},
}
const MIN_STAT := 20.0
const NATIONS := ["Sweden", "Denmark", "France", "Brazil", "USA", "Poland", "Ukraine", "Finland", "Germany", "Canada", "Australia", "Korea"]
## Base nations plus every nation in the real-teams pack.
static func all_nations() -> Array:
	var out: Array = NATIONS.duplicate()
	for n in RealTeams.nations():
		if not out.has(n):
			out.append(n)
	return out


## Difficulty: scales how often players turn your club down (set by World).
static var refuse_mult := 1.0
const MAX_STAT := 100.0

const HANDLES := [
	"Viper", "Nox", "Quill", "Brick", "Halo", "Rook", "Jinx", "Talon", "Mako", "Cinder",
	"Vex", "Bolt", "Kestrel", "Drift", "Onyx", "Pike", "Rune", "Sable", "Tusk", "Wraith",
	"Echo", "Flint", "Gage", "Hex", "Ion", "Jolt", "Knox", "Lynx", "Moss", "Nero",
	"Orbit", "Pyre", "Quake", "Rift", "Shade", "Torque", "Umbra", "Volt", "Wisp", "Zed",
	"Ash", "Blitz", "Crux", "Dusk", "Ember", "Frost", "Grit", "Husk", "Ivy", "Jett",
	"Kilo", "Lumen", "Mirage", "Nimbus", "Oxide", "Prism", "Razor", "Spectre", "Tempo", "Vandal",
]

@export var player_name: String = ""
@export var age: int = 20
@export var role: String = "Rifler"
@export var stats: Dictionary = {} ## String -> float
@export var potential: int = 70 ## Hidden rating ceiling growth slows toward.
@export var is_user: bool = false

@export var matches_played: int = 0
@export var career_kills: int = 0
@export var career_deaths: int = 0
@export var recent_ratings: Array[float] = [] ## Last few match ratings.

# Manager-career economics.
@export var salary: int = 0 ## Weekly wage.
@export var titles: int = 0 ## Tournaments won.
@export var contract_until: int = 1 ## Last season of the current contract.

# Career mode: identity, form and history.
@export var uid: int = 0 ## Stable id (names can be changed).
@export var form: float = 0.0 ## -8..+8 stat points: hot streak or slump. Moves week to week.
@export var morale: float = 70.0 ## 0-100. Benching, losing and wage disputes lower it.
@export var match_log: Array = [] ## Recent matches: {s, w, opp, res, score, k, d, adr, r, label}.
@export var season_stats: Dictionary = {} ## This season: {m, k, d, r_sum}.
@export var listed: bool = false ## On the transfer list: clubs bid over the following weeks.
@export var out_weeks: int = 0 ## Sick / injured: weeks until available again.
@export var ailment: String = ""
@export var bench_weeks: int = 0 ## Consecutive weeks out of the starting five.
@export var promise_until: int = 0 ## Promised a starting spot until this week stamp (season*100+week).
@export var msg_cooldown: int = 0 ## No new complaints before this week stamp.
@export var nation: String = ""
@export var joined: int = 0 ## Week stamp they joined their club (0 = long-standing). Drives chemistry.
@export var release_clause: int = 0 ## Any club paying this takes the player (your contracts only).
@export var loyalty_bonus: int = 0 ## Paid if they see the contract out with you.
@export var appearance_fee: int = 0 ## Paid per match played, on top of a lower wage.
@export var peak: int = 0 ## Best rating reached (Hall of Fame).
@export var loan_from: String = "" ## "" = not on loan; "user" = loaned out by you; else the parent club's name.
@export var loan_kind: String = "" ## "squad" / "academy" (loaned out by you) or "in" (loaned to you).
@export var loan_team: int = -1 ## Parent club's team index (loans in).
@export var loan_fee: int = 0 ## Weekly fee you pay instead of the wage (loans in).


const PERSONAS := ["Leader", "Mentor", "Troublemaker", "Professional", "Showman"]
const PERSONA_TEXT := {
	"Leader": "Lifts the starting five: morale and chemistry.",
	"Mentor": "Teammates aged 21 and under develop faster.",
	"Troublemaker": "Talented, but starts dressing-room fights.",
	"Professional": "Never slumps; steady form.",
	"Showman": "Crowd favourite: more fans and merch, streakier form.",
}


## About a third of players have a personality, fixed from their id.
static func persona_of(p: PlayerData) -> String:
	if p == null or p.is_user:
		return ""
	var h := absi(hash("%d/persona" % p.uid)) % 100
	return PERSONAS[h % PERSONAS.size()] if h < 35 else ""


func available() -> bool:
	return out_weeks <= 0


## Some players simply won't join certain clubs. Deterministic per player+club,
## likelier when the club is far below the player's level. "" = open to it.
func refuses(t: TeamData, mult: float = 1.0) -> String:
	if t == null:
		return ""
	var gap := clampf((rating_exact() - t.rating_exact()) / 60.0, 0.0, 0.25)
	var h := float(absi(hash("%d/%s" % [uid, t.team_name])) % 1000) / 1000.0
	if h >= (0.05 + gap) * refuse_mult * mult:
		return ""
	var reasons := ["wants a bigger stage than %s" % t.team_name, "has a long-running feud with %s" % t.team_name,
		"doesn't fancy %s's project" % t.team_name, "won't play for %s, full stop" % t.team_name,
		"is holding out for a bigger club", "doesn't want to relocate to %s" % t.team_name]
	return "%s %s" % [player_name, reasons[absi(hash(t.team_name + str(uid))) % reasons.size()]]
## Transient: form + today's mood, applied to gameplay curves only (not the
## rating). Set before each career match.
var match_mod: float = 0.0
var honours: Array = [] ## Titles earned: {t: text, s: season, rank: prestige}. See add_honour.
var title: String = "" ## Title worn with the name (profile, scoreboard); "" = none.


func _init() -> void:
	for k: String in STAT_KEYS:
		stats[k] = 50.0


func stat(key: String) -> float:
	return float(stats.get(key, 50.0))


func set_stat(key: String, value: float) -> void:
	stats[key] = clampf(value, MIN_STAT, MAX_STAT)


func rating_exact() -> float:
	var total := 0.0
	for k: String in STAT_KEYS:
		total += stat(k)
	return total / STAT_KEYS.size()


func rating() -> int:
	return int(round(rating_exact()))


func avg_recent_rating() -> float:
	if recent_ratings.is_empty():
		return 1.0
	var total := 0.0
	for r in recent_ratings:
		total += r
	return total / recent_ratings.size()


func push_match_rating(r: float) -> void:
	recent_ratings.append(r)
	while recent_ratings.size() > 5:
		recent_ratings.pop_front()


# --- Gameplay mappings ------------------------------------------------------

func _t(key: String) -> float:
	return clampf((stat(key) + match_mod - MIN_STAT) / (MAX_STAT - MIN_STAT), 0.0, 1.0)


## Skill curves: piecewise-linear through [stat, value] anchors. Steep below
## ~60 so weak players are genuinely weak, flattening out at the top.
func _curve(key: String, pts: Array) -> float:
	var x := stat(key) + match_mod
	if x <= pts[0][0]:
		return pts[0][1]
	for i in range(1, pts.size()):
		if x <= pts[i][0]:
			var a: Array = pts[i - 1]
			var b: Array = pts[i]
			return lerpf(a[1], b[1], (x - a[0]) / (b[0] - a[0]))
	return pts[-1][1]


func move_speed() -> float:
	return lerpf(155.0, 201.0, _t("movement")) # Original 165-215, -40%, then +25%, then +25%.


## Multiplier on a weapon's moving inaccuracy. Good movement = cleaner counter-strafes.
func moving_penalty_mult() -> float:
	return _curve("movement", [[20, 1.6], [40, 1.4], [60, 1.1], [80, 0.85], [100, 0.7]])


## First-shot spread. Your own player uses a gentler curve (your mouse does the aiming).
func spread_degrees() -> float:
	if is_user:
		return lerpf(7.0, 0.8, _t("aim"))
	return _curve("aim", [[20, 14.0], [40, 10.0], [60, 4.0], [80, 2.0], [95, 1.5], [100, 1.3]])


func recoil_mult() -> float:
	if is_user:
		return lerpf(1.7, 0.45, _t("recoil"))
	return _curve("recoil", [[20, 2.4], [40, 2.0], [60, 1.2], [80, 0.75], [100, 0.55]])


func reaction_time() -> float:
	if Game.ab_flag("old_ai2"):
		return _curve("reaction", [[20, 1.6], [40, 1.25], [60, 0.85], [80, 0.6], [95, 0.5], [100, 0.46]])
	return _curve("reaction", [[20, 1.3], [40, 1.0], [60, 0.7], [80, 0.5], [95, 0.42], [100, 0.39]])


## Max crosshair swing speed (degrees/second). Humans flick ~300-900 deg/s.
func flick_speed_deg() -> float:
	return _curve("flick", [[20, 170.0], [40, 230.0], [60, 420.0], [80, 650.0], [100, 800.0]])


## How hard the swing brakes as it lands on target (higher = snappier settle).
func flick_settle() -> float:
	return _curve("flick", [[20, 4.0], [40, 5.0], [60, 8.0], [80, 11.0], [100, 14.0]])


# --- Bot aim model (human-like imperfection) ---

## How far off the first flick lands when an enemy appears (degrees).
func flick_error_deg() -> float:
	return _curve("aim", [[20, 32.0], [40, 25.0], [60, 10.0], [80, 5.0], [95, 3.9], [100, 3.6]])


## How fast that flick error is corrected (per second, exponential).
func settle_rate() -> float:
	return _curve("aim", [[20, 1.0], [40, 1.4], [60, 3.5], [80, 5.5], [100, 6.6]])


## Constant hand wobble while aiming (degrees, std-dev).
func aim_jitter_deg() -> float:
	return _curve("aim", [[20, 4.5], [40, 3.6], [60, 1.8], [80, 1.0], [100, 0.75]])


## Bots aim where you were this many seconds ago, so strafing makes them miss.
func tracking_lag() -> float:
	return _curve("reaction", [[20, 0.5], [40, 0.42], [60, 0.3], [80, 0.21], [100, 0.16]])


func preaim_factor() -> float:
	return lerpf(0.0, 0.85, _t("preaim"))


func sight_range() -> float:
	return lerpf(1100.0, 1500.0, _t("positioning"))


func fov_dot() -> float:
	return lerpf(0.45, 0.05, _t("positioning"))


func hold_chance() -> float:
	return lerpf(0.25, 0.65, _t("positioning"))


func rotate_delay() -> float:
	return _curve("decision", [[20, 12.0], [40, 9.0], [60, 4.5], [80, 2.5], [100, 1.5]])


# --- Your own player (mouse and keyboard) ----------------------------------
# The stats a bot uses to aim and think also shape how your hands behave.
# All of these are no-ops with --ab=old_skills.

## Flick: extra spread (degrees) for firing mid-swing, at a full-speed flick.
func user_swing_spread() -> float:
	return lerpf(9.0, 1.5, _t("flick"))


## Flick: how fast that swing wobble settles (per second).
func user_swing_recover() -> float:
	return lerpf(5.0, 16.0, _t("flick"))


## Flick: scope-in time multiplier.
func user_scope_mult() -> float:
	return lerpf(1.3, 0.75, _t("flick"))


## Preaim: first-shot spread multiplier once your crosshair has been still on an angle.
func user_steady_mult() -> float:
	return lerpf(1.0, 0.55, _t("preaim"))


## Reaction: aim punch (degrees of spread) from a 30-damage hit.
func user_flinch_deg() -> float:
	return lerpf(7.0, 1.5, _t("reaction"))


## Reaction: how fast the aim punch wears off (per second).
func user_flinch_recover() -> float:
	return lerpf(2.5, 9.0, _t("reaction"))


## Reaction: how fast an enemy fades in when they come into view (per second).
func user_reveal_rate() -> float:
	return lerpf(4.0, 16.0, _t("reaction"))


## Utility: how far off your grenade lands at full throw range (px).
func user_throw_scatter() -> float:
	return lerpf(80.0, 6.0, _t("utility"))


## Decision: seconds your team's calls stay on your radar.
func user_call_time() -> float:
	return lerpf(4.0, 9.0, _t("decision"))


## Decision: how often a called enemy's radar marker refreshes (seconds).
func user_call_every() -> float:
	return lerpf(2.2, 0.9, _t("decision"))


func preferred_primary() -> int:
	return WeaponData.SNIPER if role == "AWPer" else WeaponData.RIFLE


# --- Explanations (hover tooltips) -------------------------------------------

const _TIP_LEVELS := [40, 60, 80, 95]


## What a stat does, how it's used, and what it works out to at a few levels.
## Numbers are computed from the real curves, so they stay correct if tuned.
static func stat_tooltip(key: String) -> String:
	var lines: Array[String] = ["%s  (%s)" % [STAT_NAMES[key], key.substr(0, 3).to_upper()], String(STAT_HELP[key]), ""]
	var rows: Array = [] # [label, Callable(PlayerData) -> String]
	match key:
		"aim":
			rows = [["Bot first-shot spread", func(p: PlayerData) -> String: return "%.1f°" % p.spread_degrees()],
				["First flick lands off by", func(p: PlayerData) -> String: return "%.0f°" % p.flick_error_deg()],
				["Hand wobble", func(p: PlayerData) -> String: return "%.1f°" % p.aim_jitter_deg()]]
			lines.append("Bots: how close shots land and how fast a bad flick is corrected.")
			lines.append("You: your first-shot spread is %.1f° at 40 and %.1f° at 95." % [_tip_player(key, 40, true).spread_degrees(), _tip_player(key, 95, true).spread_degrees()])
		"flick":
			rows = [["Max crosshair swing", func(p: PlayerData) -> String: return "%.0f°/s" % p.flick_speed_deg()],
				["Settle (snap) rate", func(p: PlayerData) -> String: return "%.0f" % p.flick_settle()]]
			lines.append("Bots: how fast they swing onto you.")
			lines.append("You: firing mid-flick adds up to %.1f° spread at 40, %.1f° at 95; it settles %.0fx faster at 95." % [_tip_player(key, 40, true).user_swing_spread(), _tip_player(key, 95, true).user_swing_spread(), _tip_player(key, 95, true).user_swing_recover() / _tip_player(key, 40, true).user_swing_recover()])
			lines.append("You: scoping in takes %.2fs at 40, %.2fs at 95." % [0.3 * _tip_player(key, 40, true).user_scope_mult(), 0.3 * _tip_player(key, 95, true).user_scope_mult()])
		"preaim":
			rows = [["Crosshair pre-placed", func(p: PlayerData) -> String: return "%.0f%%" % (p.preaim_factor() * 100.0)]]
			lines.append("Bots: how much of the angle to an enemy is already covered when they appear.")
			lines.append("You: holding still on an angle tightens your first shot to x%.2f at 40, x%.2f at 95." % [_tip_player(key, 40, true).user_steady_mult(), _tip_player(key, 95, true).user_steady_mult()])
		"recoil":
			rows = [["Bot spray bloom", func(p: PlayerData) -> String: return "x%.2f" % p.recoil_mult()]]
			lines.append("Multiplies how much each shot in a spray widens the cone.")
			lines.append("You: x%.2f at 40, x%.2f at 95." % [_tip_player(key, 40, true).recoil_mult(), _tip_player(key, 95, true).recoil_mult()])
		"reaction":
			rows = [["Time to react", func(p: PlayerData) -> String: return "%.2fs" % p.reaction_time()],
				["Tracking lag", func(p: PlayerData) -> String: return "%.2fs" % p.tracking_lag()]]
			lines.append("Bots aim where you were 'lag' seconds ago, so strafing beats slow reactions.")
			lines.append("You: a 30-damage hit punches your aim %.1f° at 40, %.1f° at 95 (wears off %.0fx faster), and enemies pop into view faster." % [_tip_player(key, 40, true).user_flinch_deg(), _tip_player(key, 95, true).user_flinch_deg(), _tip_player(key, 95, true).user_flinch_recover() / _tip_player(key, 40, true).user_flinch_recover()])
		"movement":
			rows = [["Run speed", func(p: PlayerData) -> String: return "%.0f px/s" % p.move_speed()],
				["Run-and-gun penalty", func(p: PlayerData) -> String: return "x%.2f" % p.moving_penalty_mult()],
				["Bot counter-strafes", func(p: PlayerData) -> String: return "%.0f%%" % (lerpf(30.0, 95.0, p._t("movement")))]]
			lines.append("Applies to you as well as bots.")
		"positioning":
			rows = [["Sight range", func(p: PlayerData) -> String: return "%.0f px" % p.sight_range()],
				["Field of view", func(p: PlayerData) -> String: return "%.0f°" % (rad_to_deg(acos(p.fov_dot())) * 2.0)],
				["Bot holds instead of pushing", func(p: PlayerData) -> String: return "%.0f%%" % (p.hold_chance() * 100.0)]]
			lines.append("Vision cone applies to you too.")
		"decision":
			rows = [["Rotation delay", func(p: PlayerData) -> String: return "%.1fs" % p.rotate_delay()],
				["Makes the right save/retake call", func(p: PlayerData) -> String: return "%.0f%%" % ((0.3 + 0.6 * p._t("decision")) * 100.0)]]
			lines.append("Bots: rotations, retakes, saves, forced buys and peeking discipline.")
			lines.append("You: team calls stay on your radar %.0fs at 40, %.0fs at 95, and update more often." % [_tip_player(key, 40, true).user_call_time(), _tip_player(key, 95, true).user_call_time()])
		"utility":
			rows = [["Throw lands within", func(p: PlayerData) -> String: return "%.0f px" % lerpf(110.0, 12.0, p._t("utility"))],
				["Uses a good chance", func(p: PlayerData) -> String: return "%.0f%%" % ((0.25 + 0.6 * p._t("utility")) * 100.0)],
				["Buys each grenade", func(p: PlayerData) -> String: return "%.0f%%" % ((0.3 + 0.65 * p._t("utility")) * 100.0)]]
			lines.append("Bots: smokes and mollies on CT holds, entry flashes, retake flashes,")
			lines.append("mollies on the defuser and on a push.")
			lines.append("You: a full-range throw lands within %.0f px at 40, %.0f px at 95." % [_tip_player(key, 40, true).user_throw_scatter(), _tip_player(key, 95, true).user_throw_scatter()])
	if not rows.is_empty():
		lines.append("")
		var head := "At stat:"
		for lv in _TIP_LEVELS:
			head += "   %d" % lv
		lines.append(head)
		for r in rows:
			var line := "  %s:" % r[0]
			for lv in _TIP_LEVELS:
				line += "   " + (r[1] as Callable).call(_tip_player(key, lv, false))
			lines.append(line)
	lines.append("")
	lines.append("Rating (RTG) = average of all nine attributes.")
	lines.append("Training and good match ratings raise it; from age 30 it slowly drops.")
	return "
".join(lines)


static func _tip_player(key: String, value: float, user: bool) -> PlayerData:
	var p := PlayerData.new()
	p.set_stat(key, value)
	p.is_user = user
	return p


## Tooltips for the non-stat columns used in player tables.
static func column_tooltip(title: String) -> String:
	if STAT_SHORT.has(title):
		return stat_tooltip(STAT_SHORT[title])
	match title:
		"RTG":
			return "Rating: the average of the nine attributes (20-100).
Premier League teams average 90+, Academy 40-55."
		"Pot.":
			return "Potential: how much room the player has left to grow.
Young players grow fastest; growth stops near their ceiling.
Elite 20+, High 12+, Good 6+, Some 2+ points of headroom."
		"Age":
			return "Players 19 and under improve fastest; growth slows through the mid-20s
and players start declining from 30."
		"Wage":
			return "Weekly salary (rises steeply with rating)."
		"Value":
			return "Market value: wage-based, plus a premium for youth and potential."
		"Deal":
			return "Contract runs through this season. '!' = expires at season end."
	return ""


# --- Titles ------------------------------------------------------------------

## Titles that exist: "<event> Champion", "<event> Finalist" (lost the final),
## "<event> Semi Finalist", "<event> Quarter Finalist", the league table
## ("#1".."#5 in the <league>"), the rating leaderboard ("#1".."#5 Rated in
## the <league>") and season stat leaders ("Top K/D" / "Most Kills in the <league>").
const TITLE_PREFIXES := ["#1", "#2", "#3", "#4", "#5", "#1 Rated", "#2 Rated", "#3 Rated", "#4 Rated", "#5 Rated", "Top K/D", "Most Kills"]


static func allowed_honour(t: String) -> bool:
	if t.ends_with(" Champion") or t.ends_with(" Finalist"):
		return true
	for pre: String in TITLE_PREFIXES:
		if t.begins_with(pre + " in the "):
			return true
	return false


## "#2 Rated in the Premier League (Season 2)"
static func honour_label(h: Dictionary) -> String:
	return "%s (Season %d)" % [String(h.t), int(h.s)]


## A title from a trophy or an award. Bots always wear their best one; you
## get your first one put on automatically and choose after that.
func add_honour(text: String, season_n: int, rank: int) -> void:
	for h: Dictionary in honours:
		if String(h.t) == text and int(h.s) == season_n:
			return
	honours.append({"t": text, "s": season_n, "rank": rank})
	if not is_user:
		title = best_honour()
	elif title == "":
		title = honour_label(honours[honours.size() - 1])


## The most prestigious title (newest first on ties), or "".
func best_honour() -> String:
	if honours.is_empty():
		return ""
	var best: Dictionary = honours[0]
	for h: Dictionary in honours:
		if int(h.rank) > int(best.rank) or (int(h.rank) == int(best.rank) and int(h.s) > int(best.s)):
			best = h
	return honour_label(best)


# --- Form, morale, history ---------------------------------------------------

func form_text() -> String:
	if form >= 4.5:
		return "On fire"
	if form >= 1.8:
		return "Good"
	if form > -1.8:
		return "Steady"
	if form > -4.5:
		return "Poor"
	return "Slump"


func form_color() -> Color:
	if form >= 1.8:
		return Color("4ade80")
	if form > -1.8:
		return Color("8b94a7")
	if form > -4.5:
		return Color("fbbf24")
	return Color("f87171")


func morale_text() -> String:
	if morale >= 80.0:
		return "Delighted"
	if morale >= 60.0:
		return "Content"
	if morale >= 40.0:
		return "Unsettled"
	if morale >= 20.0:
		return "Unhappy"
	return "Wants out"


## One line in the match history (keeps the last 30) + season totals.
func log_match(entry: Dictionary) -> void:
	match_log.append(entry)
	while match_log.size() > 30:
		match_log.pop_front()
	season_stats["m"] = int(season_stats.get("m", 0)) + 1
	season_stats["k"] = int(season_stats.get("k", 0)) + int(entry.get("k", 0))
	season_stats["d"] = int(season_stats.get("d", 0)) + int(entry.get("d", 0))
	season_stats["r_sum"] = float(season_stats.get("r_sum", 0.0)) + float(entry.get("r", 1.0))
	peak = maxi(peak, rating())


func season_avg_rating() -> float:
	var m := int(season_stats.get("m", 0))
	return float(season_stats.get("r_sum", 0.0)) / m if m > 0 else 0.0


func season_kd() -> float:
	return float(season_stats.get("k", 0)) / maxf(1.0, float(season_stats.get("d", 0)))


func career_kd() -> float:
	return float(career_kills) / maxf(1.0, float(career_deaths))


# --- Generation / serialization --------------------------------------------

static func generate(rng: RandomNumberGenerator, quality: float, used_names: Dictionary, p_role: String = "") -> PlayerData:
	var p := PlayerData.new()
	p.player_name = unique_name(rng, used_names)
	p.role = p_role if p_role != "" else String(ROLES[rng.randi() % ROLES.size()])
	p.nation = NATIONS[rng.randi() % NATIONS.size()]
	p.age = rng.randi_range(17, 33)
	var bias: Dictionary = ROLE_BIAS[p.role]
	for k: String in STAT_KEYS:
		p.set_stat(k, rng.randfn(quality, 6.0) + float(bias.get(k, 0)))
	var room := clampi((26 - p.age) * 3, 0, 30)
	p.potential = clampi(p.rating() + rng.randi_range(0, room) + rng.randi_range(0, 4), 30, 100)
	return p


static func unique_name(rng: RandomNumberGenerator, used: Dictionary) -> String:
	return NameGen.handle(rng, used)


## Weekly wage a player of this rating expects.
static func salary_for_rating(r: float) -> int:
	return int(round(300.0 * exp((r - 40.0) / 15.0) / 50.0)) * 50


## Transfer value: wage-based, young high-potential players are worth more.
func market_value() -> int:
	var base := salary_for_rating(rating_exact()) * 40.0
	var youth := clampf((26 - age) * 0.06, -0.3, 0.5)
	var upside := clampf((potential - rating()) / 40.0, 0.0, 0.6)
	return int(round(base * (1.0 + youth + upside) / 1000.0)) * 1000


func to_dict() -> Dictionary:
	return {
		"name": player_name, "age": age, "role": role, "stats": stats.duplicate(),
		"potential": potential, "is_user": is_user, "matches": matches_played,
		"kills": career_kills, "deaths": career_deaths, "recent": Array(recent_ratings),
		"salary": salary, "titles": titles, "contract_until": contract_until,
		"uid": uid, "form": form, "morale": morale, "log": match_log.duplicate(true), "season": season_stats.duplicate(),
		"listed": listed, "out": out_weeks, "ailment": ailment, "bench": bench_weeks, "promise": promise_until, "cool": msg_cooldown,
		"nation": nation, "joined": joined, "clause": release_clause, "loyalty": loyalty_bonus, "appear": appearance_fee, "peak": peak,
		"loan_from": loan_from, "loan_kind": loan_kind, "loan_team": loan_team, "loan_fee": loan_fee,
		"honours": honours.duplicate(true), "title": title,
	}


static func from_dict(d: Dictionary) -> PlayerData:
	var p := PlayerData.new()
	p.player_name = d.get("name", "")
	p.age = int(d.get("age", 20))
	p.role = d.get("role", "Rifler")
	var s: Dictionary = d.get("stats", {})
	for k: String in STAT_KEYS:
		p.set_stat(k, float(s.get(k, 50.0)))
	p.potential = int(d.get("potential", 70))
	p.is_user = bool(d.get("is_user", false))
	p.matches_played = int(d.get("matches", 0))
	p.career_kills = int(d.get("kills", 0))
	p.career_deaths = int(d.get("deaths", 0))
	for r in d.get("recent", []):
		p.recent_ratings.append(float(r))
	p.salary = int(d.get("salary", 0))
	p.titles = int(d.get("titles", 0))
	p.contract_until = int(d.get("contract_until", 1))
	p.uid = int(d.get("uid", 0))
	p.form = float(d.get("form", 0.0))
	p.morale = float(d.get("morale", 70.0))
	p.match_log = d.get("log", [])
	p.season_stats = d.get("season", {})
	p.listed = bool(d.get("listed", false))
	p.out_weeks = int(d.get("out", 0))
	p.ailment = String(d.get("ailment", ""))
	p.bench_weeks = int(d.get("bench", 0))
	p.promise_until = int(d.get("promise", 0))
	p.msg_cooldown = int(d.get("cool", 0))
	p.nation = String(d.get("nation", ""))
	p.joined = int(d.get("joined", 0))
	p.release_clause = int(d.get("clause", 0))
	p.loyalty_bonus = int(d.get("loyalty", 0))
	p.appearance_fee = int(d.get("appear", 0))
	p.peak = int(d.get("peak", 0))
	p.loan_from = String(d.get("loan_from", ""))
	p.loan_kind = String(d.get("loan_kind", ""))
	p.loan_team = int(d.get("loan_team", -1))
	p.loan_fee = int(d.get("loan_fee", 0))
	var rx := RegEx.new()
	rx.compile("^([1-5])(st|nd|rd|th) in the ") # League places were "1st".."5th" before 0.19.
	for h in d.get("honours", []):
		var ht := rx.sub(String(h.get("t", "")), "#$1 in the ")
		if allowed_honour(ht): # Old saves: retired title kinds are dropped.
			p.honours.append({"t": ht, "s": int(h.get("s", 1)), "rank": int(h.get("rank", 0))})
	p.title = rx.sub(String(d.get("title", "")), "#$1 in the ")
	if p.title != "" and not p.honours.any(func(h: Dictionary) -> bool: return honour_label(h) == p.title):
		p.title = p.best_honour()
	return p
