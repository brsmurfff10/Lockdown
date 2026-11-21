class_name Tactics
extends RefCounted
## Team brains for both sides. Produces an order per bot:
##   {id, points: Array[Vector2] (waypoints, last = destination), look: Vector2,
##    action: "" | "plant" | "defuse", hold: bool}
## Bots follow orders; this class decides strategy from shared team intel.
##
## T side: picks a strategy each round (execute / rush / split / default+call),
## moves players along real routes to staging points, executes together,
## sets cover for the planter, then plays post-plant.
## CT side: picks a setup, holds angles, shares sightings, rotates when a
## mob is spotted (keeping an anchor), sometimes flanks, and retakes together.

const T := 0
const CT := 1
const INTEL_TTL := 5.0 ## Seconds a sighting stays "fresh".
const STAGE_RADIUS := 56.0

const T_STRATS := [
	# Route names are generic; every map defines A/B .main, .alt, .short and lurk.
	{"name": "Execute A", "site": "A", "routes": ["A.main", "A.main", "A.alt", "A.short", "A.short"], "weight": 3},
	{"name": "Execute B", "site": "B", "routes": ["B.main", "B.main", "B.alt", "B.short", "B.short"], "weight": 3},
	{"name": "Rush A", "site": "A", "routes": ["A.main", "A.main", "A.main", "A.alt", "A.alt"], "rush": true, "weight": 1},
	{"name": "Rush B", "site": "B", "routes": ["B.main", "B.main", "B.main", "B.main", "B.alt"], "rush": true, "weight": 1},
	{"name": "Split A", "site": "A", "routes": ["A.main", "A.main", "A.short", "A.short", "lurk"], "weight": 2},
	{"name": "Split B", "site": "B", "routes": ["B.main", "B.main", "B.short", "B.short", "lurk"], "weight": 2},
	{"name": "Default", "site": "", "routes": ["A.main", "lurk", "B.main", "A.short", "B.short"], "default": true, "weight": 3},
	# Fakes: go loud at one site (utility, noise), pull the rotation, then hit the other.
	{"name": "Fake A, hit B", "site": "B", "fake": "A", "routes": ["A.main", "A.main", "A.short", "A.alt", "lurk"], "weight": 2},
	{"name": "Fake B, hit A", "site": "A", "fake": "B", "routes": ["B.main", "B.main", "B.short", "B.alt", "lurk"], "weight": 2},
]
const CT_SETUPS := [
	{"name": "Standard", "slots": [["A", 0], ["A", 1], ["mid", 0], ["B", 0], ["B", 1]], "weight": 5},
	{"name": "Stack A", "slots": [["A", 0], ["A", 1], ["A", 2], ["mid", 0], ["B", 0]], "weight": 2},
	{"name": "Stack B", "slots": [["B", 0], ["B", 1], ["B", 2], ["mid", 0], ["A", 0]], "weight": 2},
	# Push out early for picks (mid + one entrance), then fall back to the sites.
	{"name": "Aggressive", "slots": [["A", 0], ["A", 1], ["mid", 0], ["B", 0], ["B", 1]], "aggro": 2, "weight": 1},
]

## Team playstyles: every team has one, stable from its name (no saved data).
const TEAM_STYLES := ["aggressive", "default", "utility", "awp"]
const STYLE_TEXT := {"aggressive": "Aggressive (rushes, early pushes)", "default": "Slow default (info, late calls)",
	"utility": "Utility-heavy (smokes, flashes, mollies)", "awp": "AWP-centric (snipers, long angles)"}


## A team's playstyle from its name: "aggressive", "default", "utility" or
## "awp". Deterministic, so the same team plays the same way every match.
## Safe to call from UI code.
static func team_style(team_name: String) -> String:
	return TEAM_STYLES[absi(hash(team_name + "/style")) % TEAM_STYLES.size()]


static func team_style_text(style: String) -> String:
	return STYLE_TEXT.get(style, style)


var m ## Match.
var side_style := ["default", "default"] ## Per side this round (from the team on it).
var enemy_eco := [false, false] ## Per side: our read that the enemy is on an eco / weak buy.
var t_post_mode := "time" ## Post-plant: "time" (hide, crossfire) or "picks" (hunt before they group).
var _igl_t := 0.0
var _igl_done := {} ## Calls already made this round.
var _t_deaths_at := {} ## region -> T deaths there this round (for "two down mid").
var arena: Arena
var rng: RandomNumberGenerator
var orders := {} ## Unit -> order Dictionary.
var _tick := 0.0
var _seq := 0 ## Makes order ids unique.

# --- Intel ---
var seen_by := [{}, {}] ## [side] -> {enemy Unit: {pos, time}}

# --- T state ---
var t_strat: Dictionary = {}
var t_site := "A"
var t_phase := "approach" ## approach | execute | postplant
var t_route := {} ## Unit -> route name
var t_deadline := 30.0
var t_called := false
var t_contact_time := -100.0
var t_plant_spot := Vector2.ZERO
var t_cover := {} ## Unit -> [pos, look]
var t_lurker: Unit = null
var _late_push := false
var _t_switched := false ## Already rotated off a stacked site this round.
var _ct_fell_back := {} ## site -> true once an outnumbered anchor has fallen back.
var ct_watch: Unit = null ## CT holding an angle on a dropped bomb.

# --- CT state ---
var ct_setup: Dictionary = {}
var ct_home := {} ## Unit -> {site, pos, look}
var ct_state := {} ## Unit -> "hold" | "aggro" | "rotate" | "flank" | "retake" | "save"
var ct_rotate_at := {} ## Unit -> round_clock when they start moving
var ct_rotate_dest := {} ## Unit -> [pos, look]
var ct_call_site := ""
var ct_call_strength := 0
var ct_retake_stage := {} ## Unit -> stage point name
var ct_retake_go := false
var t_execute_at := -1.0
var _util_cd := {} ## Unit -> round clock when it may throw again.
var _smoked: Array[Vector2] = [] ## Where smokes went this round (no doubling up).
var _escaping := {} ## Unit -> escape order once running from the bomb (overrides everything).
var ct_defuser: Unit = null ## Sticky: keeps the job until dead.
var ct_info: Unit = null ## CT making an info play this round.
var ct_info_until := 0.0
var _ct_info_done := false
var ct_rot_stage := {} ## Rotating CT -> stage point (Vector2) they gather at.
var ct_rot_go := {} ## site -> true once the rotators go in together.
var _ct_rot_first := {} ## site -> clock the first rotator arrived at the stage.

# --- Shared knowledge ---
var cleared := [{}, {}] ## [side] -> {angle Vector2: clock it was last seen empty}
var t_assigned := {} ## T -> angle (Vector2) they're clearing on the way in.
var t_on_site_at := -1.0 ## When the first T stepped onto the site.
var post_spots: Array[Vector2] = [] ## Post-plant crossfire spots (computed at plant).
var saving := {} ## Unit -> true: playing for the next round (avoid fights, keep the gun).
var thought := {} ## Unit -> short text of what the team brain wants (spectate overlay).
var hunting := false ## Post-round: winners hunt, losers run.

# --- Match memory (per attacking team; survives between rounds) ---
var hist := {} ## team index -> {hits: {A, B}, ct_seen: {A, B}, strat: {name: [won, lost]}}
var _round_ct_seen := {"A": {}, "B": {}} ## CTs the Ts saw near each site early this round.
var _fake_to := "" ## Real site while a fake is running.
var _t_reason := "" ## Why the T caller picked this strat (radio).
var _ct_reason := ""
var _radio_t := [-100.0, -100.0] ## Per side: last radio message time.
var _radio_last := [{}, {}] ## Per side: text -> time (no repeats).
var _pers_cache := {} ## PlayerData -> BotPersonality
# Dropped bomb.
var t_fetcher: Unit = null ## T going for a dropped bomb.
var t_escort: Unit = null ## T covering the fetcher.
var _drop_called := false
var ct_bomb_known := false ## CTs know where the dropped bomb lies.
var ct_contest := {} ## CT -> true: closing in on a dropped bomb.
var _ct_drop_called := false
# Moving as a group.
var _wait_start := {} ## T -> clock they started waiting at an entrance.
var _wait_seen := {} ## T -> last clock they were told to wait.
var _wait_block := {} ## T -> no more waiting until this clock (don't stand forever).
var _lurk_joined := false
var _retake_first := -1.0 ## Clock the first CT reached a retake stage.
var trade_partner := {} ## Unit -> teammate who refrags for them (entry + trader pairs).
var _last_kill := {} ## killer Unit -> [clock, victim side] (for trade stats).
static var deaths_count := 0 ## Dev stats: deaths...
static var traded_count := 0 ## ...that were traded within 3s.


func _init(p_match, p_arena: Arena, p_rng: RandomNumberGenerator) -> void:
	m = p_match
	arena = p_arena
	rng = p_rng


func strategy_label() -> String:
	return "%s / %s" % [t_strat.get("name", "?"), ct_setup.get("name", "?")]


# =============================================================================
# Round setup
# =============================================================================

func setup_round() -> void:
	_round_ct_seen = {"A": {}, "B": {}}
	_fake_to = ""
	orders.clear()
	seen_by = [{}, {}]
	cleared = [{}, {}]
	t_assigned.clear()
	t_on_site_at = -1.0
	post_spots.clear()
	t_fetcher = null
	t_escort = null
	_drop_called = false
	ct_bomb_known = false
	ct_contest.clear()
	_ct_drop_called = false
	_wait_start.clear()
	_wait_seen.clear()
	_wait_block.clear()
	_lurk_joined = false
	_retake_first = -1.0
	saving.clear()
	thought.clear()
	hunting = false
	site_evidence = {"A": [], "B": []}
	_shot_heard.clear()
	_fake_counted = false
	trade_partner.clear()
	_igl_done.clear()
	_t_deaths_at.clear()
	igl_call = ["", ""]
	t_post_mode = "time"
	for side in [T, CT]:
		side_style[side] = team_style(m.teams[m.team_of_side(side)].team_name)
		enemy_eco[side] = _read_enemy_eco(side)
	_setup_t()
	_setup_ct()
	if side_style[T] == "default":
		t_deadline += 6.0 * arena.tempo
	elif side_style[T] == "aggressive":
		t_deadline = maxf(12.0, t_deadline - 4.0 * arena.tempo)
	_fake_site = t_site if t_strat.has("fake") else ""
	if _fake_site != "":
		fake_rounds += 1
	_round_calls()


func _pick(options: Array) -> Dictionary:
	var total := 0
	for o: Dictionary in options:
		total += int(o.weight)
	var roll := rng.randi_range(1, total)
	for o: Dictionary in options:
		roll -= int(o.weight)
		if roll <= 0:
			return o
	return options[0]


func _side_units(side: int) -> Array[Unit]:
	var out: Array[Unit] = []
	for u: Unit in m.units:
		if u.side == side:
			out.append(u)
	return out


func _setup_t() -> void:
	t_strat = _pick_t_strat()
	var no_guns := 0
	for u in _side_units(T):
		if u.primary == null:
			no_guns += 1
	if not m.is_pistol_round() and no_guns >= 3:
		# Eco: pistols only win by sticking together and hitting fast.
		t_strat = T_STRATS[2 + rng.randi() % 2]
		_t_reason = "eco"
	elif m.is_pistol_round() and (t_strat.get("default", false) or t_strat.has("fake")):
		t_strat = T_STRATS[rng.randi() % 2] # Pistol rounds: straightforward execute.
		_t_reason = ""
	t_site = t_strat.site if t_strat.site != "" else ("A" if rng.randf() < 0.5 else "B")
	if t_strat.has("fake"):
		_fake_to = t_strat.site
		t_site = t_strat.fake
	t_phase = "execute" if t_strat.get("rush", false) else "approach"
	t_deadline = rng.randf_range(22.0, 38.0) * arena.tempo
	t_called = not t_strat.get("default", false)
	t_contact_time = -100.0
	t_route.clear()
	t_lurker = null
	_late_push = false
	_t_switched = false

	# Slot assignment: Lurker role takes the lurk slot, Entry/AWPer take lead slots.
	var ts := _side_units(T)
	ts.sort_custom(func(a: Unit, b: Unit) -> bool: return _t_slot_pref(a) < _t_slot_pref(b))
	var routes: Array = t_strat.routes.duplicate()
	var lurk_idx := routes.find("lurk")
	if lurk_idx >= 0:
		routes.remove_at(lurk_idx)
		var lurker: Unit = null
		for u in ts:
			if u.data.role == "Lurker" and not u.has_bomb:
				lurker = u
		if lurker == null:
			var best_p := -1.0
			for u in ts:
				if not u.has_bomb and pers(u).patience > best_p:
					best_p = pers(u).patience
					lurker = u
		if lurker != null:
			t_route[lurker] = "lurk"
			t_lurker = lurker
	routes = _limit_mid(routes, t_route.has(t_lurker) if t_lurker != null else false)
	routes.shuffle()
	var i := 0
	for u in ts:
		if t_route.has(u):
			continue
		t_route[u] = routes[i % routes.size()]
		i += 1
	_assign_t_site_spots()


## Every map's short and alt routes (and the lurk) start through mid, so a
## strat used as written sends most of the team through it every round:
## predictable, and mid is where the CTs keep a player. Cap how many go that
## way this round (varies: no-mid rounds, the usual one or two, the odd
## mid-control round), lower it when mid has been costing us players, and
## put the rest on the site's main route.
func _limit_mid(routes: Array, lurker_taken: bool) -> Array:
	var h := _hist()
	var roll := rng.randf()
	var cap := 1 if roll < 0.45 else (2 if roll < 0.8 else (0 if roll < 0.92 else 3))
	var iq := _side_iq(T)
	var burned := float(h.get("mid_deaths", 0.0))
	if burned >= 1.5 and rng.randf() < 0.4 + 0.5 * iq:
		cap = maxi(0, cap - (2 if burned >= 3.0 else 1))
	if float(h.get("mid_used", 0.0)) >= 2.5 and rng.randf() < 0.5 * iq:
		cap = maxi(0, cap - 1) # We've been in mid every round: they'll be waiting.
	var used := 1 if lurker_taken else 0
	var site := String(t_strat.get("site", ""))
	var out: Array = []
	for r: String in routes:
		var via: Array = arena.routes.get(r, {}).get("via", [])
		if via.has("mid_entry"):
			if used < cap:
				used += 1
				out.append(r)
				continue
			var s2 := r.left(1) if r.length() > 1 and r[1] == "." else (site if site != "" else ("A" if rng.randf() < 0.5 else "B"))
			out.append(s2 + ".main")
		else:
			out.append(r)
	h["mid_used"] = float(h.get("mid_used", 0.0)) * 0.6 + float(used)
	return out


func _t_slot_pref(u: Unit) -> int:
	match u.data.role:
		"Entry":
			return 0
		"AWPer":
			return 1
		"Rifler":
			return 2
		"Support":
			return 3
	return 4


func _assign_t_site_spots() -> void:
	var info: Dictionary = arena.site_info[t_site]
	t_plant_spot = arena.pt(info.plant[rng.randi() % info.plant.size()])
	var covers: Array = info.t_cover.duplicate()
	covers.shuffle()
	t_cover.clear()
	var i := 0
	for u in _side_units(T):
		if u == t_lurker:
			continue
		var c: Array = covers[i % covers.size()]
		t_cover[u] = [arena.pt(c[0]), arena.pt(c[1])]
		i += 1


func _setup_ct() -> void:
	ct_setup = _pick_ct_setup()
	ct_home.clear()
	ct_state.clear()
	ct_rotate_at.clear()
	ct_rotate_dest.clear()
	ct_retake_stage.clear()
	t_execute_at = -1.0
	_util_cd.clear()
	_smoked.clear()
	_escaping.clear()
	_save_spot.clear()
	ct_defuser = null
	ct_info = null
	_ct_info_done = false
	ct_rot_stage.clear()
	ct_rot_go.clear()
	_ct_rot_first.clear()
	_ct_fell_back.clear()
	ct_watch = null
	ct_call_site = ""
	ct_call_strength = 0
	ct_retake_go = false
	var cts := _side_units(CT)
	cts.shuffle()
	# AWPers like mid / the long angle.
	cts.sort_custom(func(a: Unit, b: Unit) -> bool: return a.data.role == "AWPer" and b.data.role != "AWPer")
	var slots: Array = ct_setup.slots.duplicate()
	var mid_slot := -1
	for s in slots.size():
		if slots[s][0] == "mid":
			mid_slot = s
	if mid_slot >= 0 and not cts.is_empty() and cts[0].data.role == "AWPer":
		var tmp = slots[0]
		slots[0] = slots[mid_slot]
		slots[mid_slot] = tmp
	var aggro_mid := false
	for i in cts.size():
		if slots[i % slots.size()][0] == "mid":
			aggro_mid = rng.randf() < 0.1 + 0.5 * pers(cts[i]).aggression # Hotheads play mid aggressive.
	if int(ct_setup.get("aggro", 0)) > 0:
		aggro_mid = true
	for i in cts.size():
		var u := cts[i]
		var slot: Array = slots[i % slots.size()]
		var site: String = slot[0]
		var home := {}
		if site == "mid":
			var p := arena.jittered("mid_hold", rng, 1)
			home = {"site": "mid", "pos": p, "look": arena.pt("mid_center")}
		else:
			var holds: Array = arena.site_info[site].ct_holds
			var h: Array = holds[int(slot[1]) % holds.size()]
			home = {"site": site, "pos": arena.pt(h[0]), "look": arena.pt(h[1])}
		ct_home[u] = home
		ct_state[u] = "aggro" if site == "mid" and aggro_mid else "hold"
	# Habit: an AWPer with a favourite angle goes back to it every round.
	for u in cts:
		var home: Dictionary = ct_home[u]
		if pers(u).has("awp_angle") and home.site in ["A", "B"]:
			var holds: Array = arena.site_info[home.site].ct_holds
			var h: Array = holds[absi(hash(u.data.player_name)) % holds.size()]
			ct_home[u] = {"site": home.site, "pos": arena.pt(h[0]), "look": arena.pt(h[1])}
	# Aggressive setup: the most aggressive site player also pushes out for info.
	if int(ct_setup.get("aggro", 0)) >= 2:
		var pick: Unit = null
		for u in cts:
			if ct_state[u] == "hold" and u.weapon.cat != WeaponData.SNIPER and (pick == null or pers(u).aggression > pers(pick).aggression):
				pick = u
		if pick != null and ct_home[pick].site in ["A", "B"]:
			var route: Dictionary = arena.routes[arena.site_info[ct_home[pick].site].main_route]
			ct_info = pick
			ct_info_until = 18.0 * arena.tempo
			_ct_info_done = true
			ct_state[pick] = "info"
			ct_rotate_dest[pick] = [arena.pt(route.entry), arena.pt(route.stage)]


# =============================================================================
# Events
# =============================================================================

## Record intel on `enemy` for `side`. Callouts and sounds are rough and only
## refresh every ~1.2s (or when the enemy has clearly moved), so bots that
## didn't see the enemy themselves don't get a live position to aim at.
## Entry: {pos, time, called, kind ("seen" / "heard" / "call"), unc (px of
## uncertainty), bomb / awp (only when someone actually saw it), cleared}.
## Once nobody sees them any more a sighting is a fading "ghost" (belief_conf).
func _note(side: int, enemy: Unit, pos: Vector2, jitter: float, kind: String = "call") -> void:
	var prev: Dictionary = seen_by[side].get(enemy, {})
	var now: float = m.round_clock
	var saw := kind == "seen"
	if Game.ab_flag("no_note"):
		seen_by[side][enemy] = {"pos": pos, "time": now, "called": now, "kind": kind, "unc": 0.0}
		return
	if not prev.is_empty() and now - float(prev.get("called", -100.0)) < 1.2 and Vector2(prev.pos).distance_to(pos) < 180.0:
		prev["time"] = now # Still there, roughly.
		prev["cleared"] = false
		if saw:
			prev["kind"] = "seen"
			prev["bomb"] = enemy.has_bomb
			prev["awp"] = enemy.weapon.is_sniper()
		return
	var j := Vector2.from_angle(rng.randf() * TAU) * jitter * sqrt(rng.randf())
	var e := {"pos": pos + j, "time": now, "called": now, "kind": kind, "unc": jitter, "cleared": false,
		"bomb": bool(prev.get("bomb", false)) and not saw, "awp": bool(prev.get("awp", false))}
	if saw:
		e.bomb = enemy.has_bomb
		e.awp = enemy.weapon.is_sniper()
	seen_by[side][enemy] = e


## Sounds (footsteps, shots, reloads, plant / defuse): the nearest enemy in
## earshot hears it and the team gets a rough marker. Uncertainty grows with
## distance and shrinks with the listener's Positioning + Decision Making.
const SOUND_RANGE := {"steps": 230.0, "shot": 1300.0, "suppressed": 700.0, "reload": 380.0, "plant": 800.0, "defuse": 800.0, "knife": 300.0}
static var heard_count := 0 ## Dev stats.


func hear(src: Unit, kind: String) -> void:
	var radius: float = SOUND_RANGE.get(kind, 500.0)
	var best: Unit = null
	var best_d := radius
	for u: Unit in m.units:
		if u.alive and u.side != src.side:
			var d := u.global_position.distance_to(src.global_position)
			if d < best_d:
				best_d = d
				best = u
	if best == null:
		return
	var skill := (best.data._t("positioning") + best.data._t("decision")) * 0.5
	var unc := lerpf(30.0, 150.0, best_d / radius) * lerpf(1.35, 0.65, skill)
	var prev: Dictionary = seen_by[best.side].get(src, {})
	if not prev.is_empty() and String(prev.get("kind", "")) == "seen" and m.round_clock - float(prev.time) < 0.5:
		return # They're looking at him anyway.
	_note(best.side, src, src.global_position, unc, "heard")
	heard_count += 1
	if kind in ["plant", "defuse"] or kind == "shot":
		_note_evidence(arena.threat_at(src.global_position), 1.0 if kind == "shot" else 2.0)
	for c in best.get_children():
		if c is BotController:
			(c as BotController).on_heard(Vector2(seen_by[best.side][src].pos), kind)


## How sure `side` still is about an entry: fades with age (sightings slower
## than sounds), and a spot someone looked at and found empty is worth little.
func belief_conf(entry: Dictionary) -> float:
	var age: float = m.round_clock - float(entry.time)
	var tau := 4.0 if String(entry.get("kind", "")) == "seen" else 2.5
	var c := exp(-age / tau)
	if entry.get("cleared", false):
		c *= 0.15
	return c


## Every marker `side` believes in (debug overlay / tests).
func beliefs(side: int) -> Array:
	var out: Array = []
	for e in seen_by[side]:
		var s: Dictionary = seen_by[side][e]
		var age: float = m.round_clock - float(s.time)
		if age > INTEL_TTL * 1.5:
			continue
		var kind := String(s.get("kind", "call"))
		if kind == "seen" and age > 0.4:
			kind = "ghost"
		out.append({"pos": s.pos, "unc": float(s.get("unc", 40.0)), "kind": kind, "conf": belief_conf(s), "age": age,
			"cleared": bool(s.get("cleared", false))})
	return out


## A heard / called-out spot a teammate is looking straight at with nobody
## there: cleared. Ghosts of real sightings are only cleared up close (they
## just stepped out of view, the spot itself was always visible).
func _clear_markers() -> void:
	var now: float = m.round_clock
	for side in [T, CT]:
		for e in seen_by[side]:
			var s: Dictionary = seen_by[side][e]
			if s.get("cleared", false) or now - float(s.time) < 0.8:
				continue
			var p: Vector2 = s.pos
			var ghost := String(s.get("kind", "")) == "seen"
			for u in _alive(side):
				var to := p - u.global_position
				var d := to.length()
				if d > (160.0 if ghost else 750.0) or (d > 60.0 and u.aim_dir.dot(to / d) < 0.8):
					continue
				if not m.has_line_of_sight(u.global_position, p):
					continue
				if is_instance_valid(e) and e.alive and m.can_see(u, e):
					continue
				s["cleared"] = true
				break


## Fake reads: utility and noise near a site count as evidence the Ts are
## going there, on top of actual sightings. Gullible (low decision) teams
## weigh it heavily, so fakes pull their rotations.
var site_evidence := {"A": [], "B": []} ## site -> [[clock, weight]]
static var fake_rounds := 0 ## Dev stats: rounds with a fake...
static var fake_bitten := 0 ## ...where the CTs called the fake site.
var _fake_site := ""
var _fake_counted := false


func _note_evidence(site: String, w: float) -> void:
	if site != "A" and site != "B":
		return
	(site_evidence[site] as Array).append([m.round_clock, w])


func on_utility(kind: String, pos: Vector2, thrower_side: int) -> void:
	if thrower_side == T and kind in ["smoke", "molotov", "flash"]:
		_note_evidence(arena.threat_at(pos), 1.5 if kind == "smoke" else 1.0)


## Recent evidence for a site (last 12s, fading).
func evidence(site: String) -> float:
	var total := 0.0
	for ev: Array in site_evidence.get(site, []):
		var age: float = m.round_clock - float(ev[0])
		if age < 12.0:
			total += float(ev[1]) * (1.0 - age / 12.0)
	return total


func on_spotted(spotter: Unit, enemy: Unit) -> void:
	var prev: Dictionary = seen_by[spotter.side].get(enemy, {})
	var fresh_contact: bool = prev.is_empty() or m.round_clock - float(prev.time) > 6.0
	_note(spotter.side, enemy, enemy.global_position, 40.0, "seen")
	if spotter.side == T and enemy.side == CT and m.round_clock < 30.0 * arena.tempo:
		var near := arena.threat_at(enemy.global_position)
		if near in ["A", "B"]:
			_round_ct_seen[near][enemy] = true
	if fresh_contact and not _human(spotter) and m.is_live():
		var where := _where(enemy.global_position)
		var n := known_enemies_near(spotter.side, enemy.global_position, 500.0)
		if enemy.has_bomb:
			_say(spotter, "Bomb carrier %s!" % where)
		elif n >= 2:
			_say(spotter, "%d %s!" % [n, where])
		else:
			_say(spotter, "One %s." % where)
	if spotter.side == T:
		t_contact_time = m.round_clock
	elif enemy.has_bomb and m.bomb_state == m.Bomb.CARRIED:
		# "Bomb spotted!" — that's where the hit is going: full rotate.
		var site := arena.threat_at(enemy.global_position)
		if (site == "A" or site == "B") and (site != ct_call_site or ct_call_strength < 3):
			_ct_call(site, 3)


func on_planted(site: String, pos: Vector2) -> void:
	for u: Unit in m.units:
		for c in u.get_children():
			if c is BotController:
				(c as BotController).on_bomb_planted()
	t_site = site
	t_phase = "postplant"
	_say_caller(T, "Planted %s. Play the crossfire, don't peek." % site, true)
	_say_caller(CT, "Bomb's down %s. Group up for the retake." % site, true)
	_assign_t_site_spots()
	# Post-plant: hide from where the CTs will come from, but watch the bomb.
	var approaches: Array[Vector2] = []
	for st: String in arena.site_info[site].retake:
		approaches.append(arena.pt(st))
	approaches.append(arena.pt("ct_mid"))
	post_spots = arena.post_plant_spots(pos, approaches, 5)
	var free := post_spots.duplicate()
	var ts := _alive(T)
	ts.sort_custom(func(a: Unit, b: Unit) -> bool: return a.global_position.distance_to(pos) < b.global_position.distance_to(pos))
	for u in ts:
		if u == t_lurker or free.is_empty():
			continue
		var best: Vector2 = free[0]
		for s: Vector2 in free:
			if u.global_position.distance_to(s) < u.global_position.distance_to(best):
				best = s
		free.erase(best)
		t_cover[u] = [best, pos]
	# CTs: everyone retakes, split between the CT-side and mid-side stages.
	var info: Dictionary = arena.site_info[site]
	ct_retake_go = false
	_retake_first = -1.0
	var stages: Array = info.retake.duplicate()
	stages.append(arena.routes[info.main_route].stage) # From behind, for flankers.
	for u in _side_units(CT):
		if not u.alive:
			continue
		var best: String = stages[0]
		for st: String in stages:
			if u.global_position.distance_to(arena.pt(st)) < u.global_position.distance_to(arena.pt(best)):
				best = st
		ct_retake_stage[u] = best
		ct_state[u] = "retake"
	_rebuild_all()


## Gunfire is loud: the nearest enemy in earshot hears roughly where it came from.
var _shot_heard := {} ## shooter -> clock (one marker per ~0.4s of fire).


func on_gunfire(shooter: Unit) -> void:
	if m.round_clock - float(_shot_heard.get(shooter, -100.0)) < 0.4:
		return
	_shot_heard[shooter] = m.round_clock
	hear(shooter, "suppressed" if shooter.weapon.id == WeaponData.SENTRY else "shot")


## Running footsteps carry a short distance; walking/standing is silent. You
## only hear roughly where they are, not the exact spot.
func _listen_for_footsteps() -> void:
	for u: Unit in m.units:
		if not u.alive or u.velocity.length() < u.top_speed() * 0.7:
			continue
		hear(u, "steps")
		if u.side == T:
			_note_evidence(arena.threat_at(u.global_position), 0.25)


func on_death(victim: Unit, killer: Unit) -> void:
	if m.is_live() and killer != null and killer.side != victim.side:
		deaths_count += 1
		_last_kill[killer] = m.round_clock
		# Was the victim himself a fresh killer? Then this was a trade.
		if m.round_clock - float(_last_kill.get(victim, -100.0)) < 3.0:
			traded_count += 1
	if m.is_live() and killer != null and victim.side == T and killer.side == CT:
		var region := arena.threat_at(victim.global_position)
		_t_deaths_at[region] = int(_t_deaths_at.get(region, 0)) + 1
		if region == "mid" and m.round_clock < 45.0 * arena.tempo:
			var hm := _hist()
			hm["mid_deaths"] = float(hm.get("mid_deaths", 0.0)) + 1.0 # Mid is getting us killed.
		if m.round_clock < 20.0 * arena.tempo:
			var h := _hist()
			h.early = float(h.early) + 1.0 # Their CTs pick us off early.
	if m.is_live() and killer != null:
		var partner: Unit = trade_partner.get(victim, null)
		if partner != null and is_instance_valid(partner) and partner.alive:
			for c in partner.get_children():
				if c is BotController:
					(c as BotController).on_partner_died(killer.global_position)
	if killer != null and not _human(victim) and m.is_live():
		var hp := int(ceil(killer.health))
		_say(victim, "Dead. They're %s, %s." % [_where(killer.global_position), "one shot" if hp <= 25 else "%d hp" % hp], true)
	if killer != null and is_instance_valid(killer) and killer.alive and not _human(killer) and m.is_live() and rng.randf() < 0.5:
		var left := _alive(victim.side).size()
		_say(killer, "Got one. %d left." % left if left > 0 else "Got the last one!")
	if killer != null:
		_note(victim.side, killer, killer.global_position, 50.0, "call")
		# "They killed me on A!" — a dead anchor is a call for help.
		if victim.side == CT and m.bomb_state != m.Bomb.PLANTED:
			var site := arena.threat_at(killer.global_position)
			if (site == "A" or site == "B") and (site != ct_call_site or ct_call_strength < 2):
				_ct_call(site, maxi(2, _threat_count(CT, site)))
	if victim.side == T:
		t_contact_time = m.round_clock
		if killer != null and killer.side == CT and m.bomb_state == m.Bomb.DROPPED \
				and m.bomb_pos.distance_to(victim.global_position) < 8.0:
			ct_bomb_known = true # We killed the carrier: we know where it is.
	if killer != null and is_instance_valid(killer) and killer.alive and not killer.data.is_user:
		if rng.randf() < 0.4 + 0.5 * killer.data._t("decision"):
			_reposition(killer)


var igl_call := ["", ""] ## Per side: the in-game leader's latest call (debug overlay).


func igl_call_text(side: int) -> String:
	var c: String = igl_call[side]
	if c == "":
		return (t_strat.get("name", "?") if side == T else ct_setup.get("name", "?"))
	return c


## Entry + trader pairs: during a T execute the player following a route lead
## refrags for him; otherwise everyone's trader is the nearest teammate within
## trade distance. Lone players (nobody close) don't get traded.
func _pair_traders() -> void:
	trade_partner.clear()
	for side in [T, CT]:
		var us := _alive(side)
		for u in us:
			if side == T and t_phase == "execute":
				var lead = orders.get(u, {}).get("follow", null)
				if lead != null and lead != u and is_instance_valid(lead) and lead.alive and not trade_partner.has(lead) 						and u.global_position.distance_to(lead.global_position) < 600.0:
					trade_partner[lead] = u
		for u in us:
			if trade_partner.has(u):
				continue
			var best: Unit = null
			var best_d := 450.0
			for v in us:
				if v == u:
					continue
				var d := u.global_position.distance_to(v.global_position)
				if d < best_d:
					best_d = d
					best = v
			if best != null:
				trade_partner[u] = best


## After getting a kill, smart players move: the enemy now knows that angle.
func _reposition(u: Unit) -> void:
	if u.side == CT and m.bomb_state != m.Bomb.PLANTED and ct_state.get(u, "") in ["hold", "rotate"]:
		var home: Dictionary = ct_home.get(u, {})
		var site: String = home.get("site", "mid")
		if site == "mid":
			ct_home[u] = {"site": "mid", "pos": arena.jittered("mid_hold", rng, 2), "look": arena.pt("mid_center")}
		else:
			var holds: Array = arena.site_info[site].ct_holds
			var options: Array = holds.filter(func(h: Array) -> bool: return arena.pt(h[0]).distance_to(home.pos) > 40.0)
			if options.is_empty():
				return
			var h: Array = options[rng.randi() % options.size()]
			ct_home[u] = {"site": site, "pos": arena.pt(h[0]), "look": arena.pt(h[1])}
		ct_state[u] = "hold"
		orders.erase(u)
	elif u.side == T and t_phase == "postplant" and u != t_lurker and post_spots.size() > 1:
		var cur: Array = t_cover.get(u, [u.global_position, m.bomb_pos])
		var options := post_spots.filter(func(s: Vector2) -> bool: return s.distance_to(cur[0]) > 60.0)
		if options.is_empty():
			return
		t_cover[u] = [options[rng.randi() % options.size()], m.bomb_pos]
		orders.erase(u)


## A teammate is reloading with an enemy nearby: the closest free teammate
## steps up and holds the angle for them.
func request_cover(reloader: Unit) -> void:
	var threat := intel_near(reloader.side, reloader.global_position, 900.0)
	if threat == Vector2.INF:
		return
	var best: BotController = null
	var best_d := 450.0
	for u: Unit in m.units:
		if not u.alive or u.side != reloader.side or u == reloader or u.reloading:
			continue
		var d := u.global_position.distance_to(reloader.global_position)
		if d >= best_d:
			continue
		for c in u.get_children():
			if c is BotController and (c as BotController).can_cover():
				best = c
				best_d = d
	if best != null:
		best.cover(threat, reloader.weapon.reload_time + 0.5)


## Entry spacing: during an execute, followers stay a trade-distance behind
## the player leading their route until that player is through the entrance.
func should_wait(u: Unit) -> bool:
	var now: float = m.round_clock
	if not _should_wait_raw(u):
		if now - float(_wait_seen.get(u, -100.0)) > 0.5:
			_wait_start.erase(u)
		return false
	if now < float(_wait_block.get(u, -1.0)):
		return false
	_wait_seen[u] = now
	if not _wait_start.has(u):
		_wait_start[u] = now
	elif now - float(_wait_start[u]) > 4.0:
		# Waited long enough: go, and don't stop again for a while.
		_wait_block[u] = now + 8.0
		_wait_start.erase(u)
		return false
	return true


func _should_wait_raw(u: Unit) -> bool:
	if u.side != T or t_phase != "execute" or _late_push:
		return false
	var o: Dictionary = orders.get(u, {})
	var lead = o.get("follow", null)
	if lead == u or lead == null:
		return _lead_waits(u, o)
	if not is_instance_valid(lead) or not lead.alive:
		return false
	var entry: Vector2 = o.get("entry", Vector2.INF)
	if entry == Vector2.INF:
		return false
	var site_c := arena.site_center(t_site)
	if lead.global_position.distance_to(site_c) < entry.distance_to(site_c) - 20.0:
		return false # Lead is through: go.
	var my_d := u.global_position.distance_to(entry)
	var lead_d: float = lead.global_position.distance_to(entry)
	# Only near the entrance, and only if we're actually behind the lead —
	# never stand in front of them (that blocks them in narrow corridors).
	if my_d > 500.0 or my_d <= lead_d:
		return false
	return my_d < lead_d + 110.0


func _route_lead(route_name: String) -> Unit:
	var best: Unit = null
	for u in _alive(T):
		if t_route.get(u, "") != route_name or u == t_lurker:
			continue
		if best == null or _lead_score(u) < _lead_score(best):
			best = u
	return best


func _lead_score(u: Unit) -> int:
	return _t_slot_pref(u) + (10 if u.has_bomb else 0) + (5 if u.data.is_user else 0)


## Freshest known enemy position near `pos` for `side`, or Vector2.INF.
## How many distinct enemies `side` knows about (fresh intel) near `pos`.
func known_enemies_near(side: int, pos: Vector2, radius: float) -> int:
	var n := 0
	var known: Dictionary = seen_by[side]
	for e in known:
		if not is_instance_valid(e) or not e.alive:
			continue
		var s: Dictionary = known[e]
		if m.round_clock - float(s.time) <= INTEL_TTL and pos.distance_to(s.pos) < radius and not s.get("cleared", false):
			n += 1
	return n


## True if `side` has fresh intel (sighting, sound, callout) within `radius` of `pos`.
func knows_near(side: int, pos: Vector2, radius: float) -> bool:
	var known: Dictionary = seen_by[side]
	for e in known:
		var s: Dictionary = known[e]
		if m.round_clock - float(s.time) <= INTEL_TTL and pos.distance_to(s.pos) < radius and not s.get("cleared", false):
			return true
	return false


func intel_near(side: int, pos: Vector2, radius: float) -> Vector2:
	var best := Vector2.INF
	var best_d := radius
	var known: Dictionary = seen_by[side]
	for e in known:
		if not is_instance_valid(e) or not e.alive:
			continue
		var s: Dictionary = known[e]
		if m.round_clock - float(s.time) > INTEL_TTL or s.get("cleared", false):
			continue
		var d := pos.distance_to(s.pos)
		if d < best_d:
			best_d = d
			best = s.pos
	return best


func _threat_count(side_seeing: int, site: String) -> int:
	var n := 0
	var known: Dictionary = seen_by[side_seeing]
	for e in known:
		if not is_instance_valid(e) or not e.alive:
			continue
		var s: Dictionary = known[e]
		if m.round_clock - float(s.time) > INTEL_TTL:
			continue
		if arena.threat_at(s.pos) == site and not s.get("cleared", false):
			n += 1
			if s.get("bomb", false):
				n += 1 # Someone saw the bomb: a strong tell.
	return n


# =============================================================================
# Update
# =============================================================================

func update(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.25
	_listen_for_footsteps()
	_clear_markers()
	_pair_traders()
	if hunting:
		_update_post_round()
		return
	_update_cleared()
	_update_t()
	_update_ct()
	_igl_t -= 0.25
	if _igl_t <= 0.0:
		_igl_t = 2.0
		_igl_think()
	_update_saves()
	_update_bomb_escape()
	_update_utility()


func _update_t() -> void:
	var ts := _alive(T)
	if ts.is_empty():
		return
	if t_phase == "approach":
		# Default: spread for info, then call the site the CTs look weakest on.
		if not t_called and (m.round_clock >= t_deadline - 10.0 or m.round_clock - t_contact_time < 1.0 and m.round_clock > 12.0 * arena.tempo):
			_t_call_site()
		var ready := true
		for u in ts:
			if t_route.get(u, "") == "lurk":
				continue
			var stage: String = arena.routes[t_route[u]].stage
			if u.global_position.distance_to(arena.pt(stage)) > STAGE_RADIUS * 1.6:
				ready = false
		var contact_now: bool = m.round_clock - t_contact_time < 1.5 and m.round_clock > 8.0
		if _fake_to != "" and (ready or contact_now or m.round_clock >= t_deadline - 4.0):
			_run_fake()
			return
		if t_called and not _t_switched and m.round_time_left > 45.0 * arena.tempo and _threat_count(T, t_site) >= 3:
			_t_switched = true
			var old := t_site
			_switch_site()
			_say_caller(T, "They're stacked %s. Rotate %s." % [old, t_site], true)
			return
		var contact: bool = m.round_clock - t_contact_time < 1.5 and m.round_clock > 8.0
		var have_bomb: bool = m.bomb_state != m.Bomb.DROPPED or m.round_time_left < 35.0 * arena.tempo
		if have_bomb and t_called and (ready or contact or m.round_clock >= t_deadline or m.round_time_left < 30.0 * arena.tempo):
			t_phase = "execute"
			t_execute_at = m.round_clock
			_rebuild_side(T)
			_say_caller(T, "Execute %s now, go go go!" % t_site, true)
	elif t_phase == "execute" and m.round_time_left < 25.0 * arena.tempo and not _late_push:
		# Time pressure: everyone commits to the site, no more holding outside.
		_late_push = true
		_rebuild_side(T)
	if t_phase == "execute" and not _lurk_joined and t_lurker != null and t_lurker.alive and _lurker_joins():
		_lurk_joined = true
		var info: Dictionary = arena.site_info[t_site]
		t_route[t_lurker] = info.short_route
		orders.erase(t_lurker)
		_say(t_lurker, "Coming in behind you, %s." % t_site)
	if t_phase == "execute":
		_assign_clearing(ts)
		if t_on_site_at < 0.0:
			for u in ts:
				if arena.site_at(u.global_position) == t_site:
					t_on_site_at = m.round_clock
					break
		var carrier: Unit = m.bomb_carrier
		if carrier != null and carrier.alive and orders.has(carrier) and orders[carrier].action != "plant" and _site_clear():
			orders.erase(carrier)
	for u in ts:
		if not orders.has(u):
			orders[u] = _t_order(u)
	_update_dropped_bomb_t(ts)
	# Just picked up: back to the plan (the on-site check below may override).
	if m.bomb_state == m.Bomb.CARRIED:
		for u in ts:
			if orders.get(u, {}).get("action", "") in ["fetch", "escort"]:
				orders[u] = _t_order(u)
	# Carrier already standing on a site (e.g. picked a dropped bomb up there):
	# never walk the route back out. Plant if nobody's on us, else hold here.
	var bc: Unit = m.bomb_carrier
	if bc != null and bc.alive and not _human(bc) and m.bomb_state == m.Bomb.CARRIED and not saving.has(bc) \
			and arena.site_at(bc.global_position) != "" and orders.get(bc, {}).get("action", "") != "plant":
		var o: Dictionary = orders.get(bc, {})
		var going_off_site: bool = o.is_empty() or arena.site_at(o.points[-1]) == ""
		if not going_off_site:
			pass # Normal execute: the plant spot is on this site; let the clearing logic decide.
		elif _fresh_enemies_near(T, bc.global_position, 450.0, 1.5) == 0:
			orders[bc] = _order([bc.global_position], Vector2.ZERO, "plant")
			thought[bc] = "planting where I picked it up"
		elif going_off_site:
			var threat := intel_near(T, bc.global_position, 900.0)
			orders[bc] = _order([bc.global_position], threat if threat != Vector2.INF else arena.site_center(arena.site_at(bc.global_position)), "", true)
			thought[bc] = "bomb on site: holding, plant when it's quiet"
	if m.bomb_state == m.Bomb.CARRIED:
		if m.bomb_carrier != null and orders.get(m.bomb_carrier, {}).get("action", "") != "plant" and t_phase == "execute" \
				and arena.site_at(m.bomb_carrier.global_position) == "":
			orders[m.bomb_carrier] = _t_order(m.bomb_carrier)


## Fake: throw what we have at the fake site, then everyone rotates to the real one.
func _run_fake() -> void:
	var fake := t_site
	var thrown := 0
	for u in _alive(T):
		if thrown >= 2 or _human(u) or u.grenades.is_empty():
			continue
		for k: String in ["smoke", "flash", "molotov"]:
			if not _has(u, k):
				continue
			var spots: Array = arena.site_angles.get(fake, [])
			spots = spots + [arena.site_center(fake)]
			for sp: Vector2 in spots:
				if _can_throw(u, sp, k) and m.utility.throw(u, k, sp):
					thrown += 1
					_util_cd[u] = m.round_clock + 3.0
					thought[u] = "fake: utility on %s" % fake
					break
			break
	_fake_to = ""
	_t_switched = true
	_switch_site()
	_say_caller(T, "That's the fake, rotate %s! Fast!" % t_site, true)


## They're stacked on our site: rotate to the other one via the closest routes.
func _switch_site() -> void:
	t_site = "B" if t_site == "A" else "A"
	var info: Dictionary = arena.site_info[t_site]
	for u in _alive(T):
		if t_route.get(u, "") == "lurk":
			continue
		var main: String = info.main_route
		var short: String = info.short_route
		var dm := u.global_position.distance_to(arena.pt(arena.routes[main].stage))
		var ds := u.global_position.distance_to(arena.pt(arena.routes[short].stage))
		t_route[u] = main if dm <= ds else short
	t_deadline = m.round_clock + 15.0 * arena.tempo
	_assign_t_site_spots()
	_rebuild_side(T)


func _t_call_site() -> void:
	t_called = true
	var a := _threat_count(T, "A")
	var b := _threat_count(T, "B")
	# Count CTs seen on each site; go where fewer were spotted.
	t_site = "A" if a < b else ("B" if b < a else ("A" if rng.randf() < 0.5 else "B"))
	_say_caller(T, "Looks light on %s. We go %s." % [t_site, t_site] if a != b else "Nothing yet. Let's hit %s." % t_site, true)
	var info: Dictionary = arena.site_info[t_site]
	for u in _alive(T):
		if t_route.get(u, "") == "lurk":
			continue
		var main: String = info.main_route
		var short: String = info.short_route
		var dm := u.global_position.distance_to(arena.pt(arena.routes[main].stage))
		var ds := u.global_position.distance_to(arena.pt(arena.routes[short].stage))
		t_route[u] = main if dm <= ds else short
	t_deadline = m.round_clock + 12.0 * arena.tempo
	_assign_t_site_spots()
	_rebuild_side(T)


func _t_order(u: Unit) -> Dictionary:
	if saving.has(u):
		return _save_order(u)
	if hunting:
		return _hunt_order(u)
	var route_name: String = t_route.get(u, "A.main")
	var route: Dictionary = arena.routes[route_name]
	var pts: Array[Vector2] = []
	match t_phase:
		"postplant":
			if u == t_lurker:
				# Lurker cuts off the rotation from behind.
				return _order([arena.jittered("ct_mid", rng, 1)], arena.pt(arena.site_info[t_site].retake[0]), "", true)
			var c: Array = t_cover.get(u, [m.bomb_pos, arena.pt("ct_spawn")])
			thought[u] = "post-plant: crossfire on bomb"
			return _order([c[0]], c[1], "", true)
		"execute":
			if route_name == "lurk" and not _late_push and not _lurk_joined:
				return _order([arena.jittered("mid_center", rng, 1)], arena.pt("mid_hold"), "", true)
			for p in route.via:
				pts.append(arena.jittered(p, rng, 1))
			pts.append(arena.jittered(route.stage, rng, 1))
			var entry := arena.pt(route.entry) if route.site == t_site else arena.pt(arena.routes[arena.site_info[t_site].main_route].entry)
			pts.append(entry)
			var o: Dictionary
			if u.has_bomb:
				if _site_clear():
					pts.append(t_plant_spot)
					o = _order(pts, Vector2.ZERO, "plant")
					thought[u] = "planting"
				else:
					# Go in with the team; sit on the plant spot until it's clear.
					pts.append(t_plant_spot)
					o = _order(pts, arena.site_center(t_site), "", true)
					thought[u] = "bomb: on site, waiting for clear"
			else:
				var c: Array = t_cover.get(u, [arena.site_center(t_site), arena.pt("ct_spawn")])
				pts.append(c[0])
				o = _order(pts, c[1], "", true)
				thought[u] = "execute %s via %s" % [t_site, route_name]
			o["points"] = _trim_behind(u, o.points)
			o["entry"] = entry
			o["follow"] = _route_lead(route_name)
			o["aim"] = t_assigned.get(u, Vector2.INF)
			return o
	# Approach: walk the route to the staging point and hold the entrance.
	thought[u] = "approach %s, hold %s" % [route_name, route.stage]
	for p in route.via:
		pts.append(arena.jittered(p, rng, 1))
	pts.append(arena.jittered(route.stage, rng, 1))
	var look := arena.pt(route.entry) if route.entry != "" else arena.pt("mid_hold")
	var ao := _order(pts, look, "", true)
	ao["points"] = _trim_behind(u, ao.points)
	return ao


## Drop route waypoints that are already behind us (e.g. we picked the bomb
## up on site: don't walk back out along the route before planting).
## Uses walking distance to the final point, so walls are respected.
func _trim_behind(u: Unit, pts: Array[Vector2]) -> Array[Vector2]:
	if pts.size() < 2:
		return pts
	var goal: Vector2 = pts[-1]
	var mine := _walk_dist(u.global_position, goal)
	var out: Array[Vector2] = pts.duplicate()
	while out.size() > 1 and _walk_dist(out[0], goal) > mine + 48.0:
		out.pop_front()
	return out


func _walk_dist(a: Vector2, b: Vector2) -> float:
	var path := arena.find_path(a, b)
	if path.size() < 2:
		return a.distance_to(b)
	var d := 0.0
	for i in range(1, path.size()):
		d += path[i - 1].distance_to(path[i])
	return d


func _update_ct() -> void:
	var cts := _alive(CT)
	if cts.is_empty():
		return
	if m.bomb_state == m.Bomb.PLANTED:
		_update_retake(cts)
	else:
		# Aggressive mid player falls back after the opening seconds.
		for u in cts:
			if ct_state.get(u, "") == "aggro" and m.round_clock > 12.0 * arena.tempo:
				ct_state[u] = "hold"
				orders.erase(u)
		# Rotation calls from shared intel, plus the "read": utility and noise on
		# a site count as evidence, heavily for gullible teams (fakes work on them).
		var gull := lerpf(0.7, 0.1, _side_iq(CT)) * BotController.mistake_mult
		for site in ["A", "B"]:
			var c := _threat_count(CT, site)
			var score := float(c) + gull * evidence(site) * 0.3
			var ci := int(floor(score))
			if ci >= 2 and (site != ct_call_site or ci > ct_call_strength):
				_ct_call(site, mini(ci, 3) if c < 2 else ci)
			if c >= 3 and not _ct_fell_back.has(site):
				_maybe_fall_back(site, cts)
		_watch_dropped_bomb(cts)
		_maybe_info_play(cts)
		_update_rotation_gather(cts)
		for u in cts:
			if ct_state.get(u, "") in ["rotate", "flank"] and m.round_clock >= float(ct_rotate_at.get(u, 0.0)) and orders.get(u, {}).get("id", "").begins_with("ct_home"):
				orders.erase(u)
	for u in cts:
		if not orders.has(u):
			orders[u] = _ct_order(u)


## Alone against 3+ on a site: don't throw your life away, fall back to the
## retake position and wait for the rotation (good decision makers do this).
func _maybe_fall_back(site: String, cts: Array[Unit]) -> void:
	var on_site: Array[Unit] = []
	for u in cts:
		if ct_home[u].site == site and ct_state.get(u, "") == "hold":
			on_site.append(u)
	if on_site.size() != 1:
		return
	var u := on_site[0]
	if rng.randf() > 0.3 + 0.6 * u.data._t("decision"):
		_ct_fell_back[site] = true # Decided to hold anyway.
		return
	_ct_fell_back[site] = true
	ct_state[u] = "fallback"
	_say(u, "Too many on %s, I'm falling back. Retake with me." % site, true)
	orders[u] = _order([arena.jittered(arena.site_info[site].retake[0], rng, 1)], arena.site_center(site), "", true)


## Dropped bomb: a CT with eyes on it holds an angle so the Ts can't just walk
## over; once the CTs know where it is, the closest one or two close in on it.
func _watch_dropped_bomb(cts: Array[Unit]) -> void:
	if m.bomb_state != m.Bomb.DROPPED:
		if ct_watch != null:
			orders.erase(ct_watch)
			ct_watch = null
		for u in ct_contest:
			if is_instance_valid(u) and u.alive and ct_state.get(u, "") == "contest":
				ct_state[u] = "hold"
				orders.erase(u)
		ct_contest.clear()
		ct_bomb_known = false
		_ct_drop_called = false
		return
	for u in cts:
		if u.global_position.distance_to(m.bomb_pos) < 1100.0 and m.has_line_of_sight(u.global_position, m.bomb_pos):
			ct_bomb_known = true
			break
	if ct_watch == null or not is_instance_valid(ct_watch) or not ct_watch.alive:
		ct_watch = null
		var best: Unit = null
		var best_d := 1100.0
		for u in cts:
			var d := u.global_position.distance_to(m.bomb_pos)
			if d < best_d and m.has_line_of_sight(u.global_position, m.bomb_pos) and not ct_contest.has(u) and not _human(u):
				best = u
				best_d = d
		if best != null:
			ct_watch = best
			orders[best] = _order([best.global_position], m.bomb_pos, "", true)
	if not ct_bomb_known or Game.ab_flag("no_contest"):
		return
	for u in ct_contest.keys():
		if not is_instance_valid(u) or not u.alive or ct_state.get(u, "") != "contest":
			ct_contest.erase(u)
	var want := 1
	if m.round_time_left < 40.0 * arena.tempo or _alive(T).size() <= cts.size():
		want = 2
	while ct_contest.size() < want:
		var pick: Unit = null
		var pick_d := 1500.0
		for u in cts:
			if ct_contest.has(u) or saving.has(u) or _human(u):
				continue
			if not ct_state.get(u, "hold") in ["hold", "aggro", "info"]:
				continue
			var d := u.global_position.distance_to(m.bomb_pos)
			if d < pick_d:
				pick_d = d
				pick = u
		if pick == null:
			break
		if pick == ct_watch:
			ct_watch = null # Closing in beats watching from afar; someone else takes the angle.
		ct_contest[pick] = true
		ct_state[pick] = "contest"
		orders.erase(pick)
		if not _ct_drop_called:
			_ct_drop_called = true
			_say(pick, "Bomb's down %s. I'm closing in, play around it." % _where(m.bomb_pos), true)
	# Late in the round: whoever's contesting goes and sits on it.
	if m.round_time_left < 25.0 * arena.tempo:
		for u in ct_contest:
			if not orders.get(u, {}).get("camp", false) and _fresh_enemies_near(CT, m.bomb_pos, 600.0, 3.0) == 0:
				orders.erase(u)


func _ct_call(site: String, strength: int) -> void:
	ct_call_site = site
	ct_call_strength = strength
	if _fake_site != "" and site == _fake_site and strength >= 3 and not _fake_counted:
		_fake_counted = true
		fake_bitten += 1
	if strength >= 3:
		_say_caller(CT, "They're hitting %s! Rotate, rotate!" % site, true)
	else:
		_say_caller(CT, "%d pushing %s. Mid, help out." % [strength, site])
	var cts := _alive(CT)
	var other := "B" if site == "A" else "A"
	# Keep one anchor on the other site.
	var anchor: Unit = null
	for u in cts:
		if ct_home[u].site == other:
			anchor = u
			break
	var flank_used := false
	var hold_i := 0
	for u in cts:
		var home_site: String = ct_home[u].site
		if home_site == site or u == anchor:
			continue
		if strength < 3 and home_site != "mid":
			continue # Small push: only mid helps.
		var st: String = ct_state.get(u, "hold")
		if st == "rotate" or st == "flank" or st == "contest":
			continue
		# Early, late or on time: poor decision makers are all over the place.
		var dec := u.data._t("decision")
		var react := lerpf(2.8, 0.6, dec) * rng.randf_range(lerpf(0.45, 0.8, dec), lerpf(1.6, 1.2, dec))
		ct_rotate_at[u] = m.round_clock + react
		if strength >= 3 and not flank_used and cts.size() >= 3 and (u.data.role in ["Lurker", "Entry"] or rng.randf() < 0.3):
			ct_state[u] = "flank"
			flank_used = true
		else:
			ct_state[u] = "rotate"
			var holds: Array = arena.site_info[site].ct_holds
			var h: Array = holds[hold_i % holds.size()]
			hold_i += 1
			ct_rotate_dest[u] = [arena.pt(h[0]), arena.pt(h[1])]
			# Gather at the nearest retake stage so rotators arrive together.
			var best_st: Vector2 = arena.pt(arena.site_info[site].retake[0])
			for rst: String in arena.site_info[site].retake:
				if u.global_position.distance_to(arena.pt(rst)) < u.global_position.distance_to(best_st):
					best_st = arena.pt(rst)
			ct_rot_stage[u] = best_st
		orders.erase(u)


func _update_retake(cts: Array[Unit]) -> void:
	var defuse_need: float = m.DEFUSE_TIME
	for u in cts:
		if u.has_kit:
			defuse_need = m.DEFUSE_TIME_KIT
	var ts_alive := _alive(T).size()
	# Save if it's hopeless.
	if cts.size() == 1 and ts_alive >= 3 and m.bomb_timer < defuse_need + 8.0:
		var u := cts[0]
		if ct_state.get(u, "") != "save" and rng.randf() < u.data._t("decision") * 0.7:
			ct_state[u] = "save"
			orders[u] = _order([arena.pt("ct_spawn")], arena.pt("ct_mid"), "", true)
		if ct_state.get(u, "") == "save":
			return
	for u in cts:
		if ct_state.get(u, "") != "retake" and ct_state.get(u, "") != "save":
			ct_state[u] = "retake"
			if not ct_retake_stage.has(u):
				ct_retake_stage[u] = arena.site_info[m.bomb_site].retake[0]
			orders.erase(u)
	if not ct_retake_go:
		var staged := 0
		for u in cts:
			var st: String = ct_retake_stage.get(u, "")
			var near_bomb := u.global_position.distance_to(m.bomb_pos) < u.global_position.distance_to(arena.pt(st)) if st != "" else true
			if near_bomb or u.global_position.distance_to(arena.pt(st)) < STAGE_RADIUS * 1.5:
				staged += 1
		# Retake together: wait for (nearly) everyone, but not forever.
		var need := cts.size() if cts.size() <= 3 else cts.size() - 1
		if staged > 0 and _retake_first < 0.0:
			_retake_first = m.round_clock
		var waited: float = m.round_clock - _retake_first if _retake_first >= 0.0 else 0.0
		if waited > 5.0:
			need = ceili(cts.size() / 2.0)
		if staged >= need or m.bomb_timer < defuse_need + 18.0 or ts_alive == 0:
			ct_retake_go = true
			_say_caller(CT, "Go now, retake %s together!" % m.bomb_site, true)
			for u in cts:
				if ct_state.get(u, "") == "retake":
					orders.erase(u)


func _ct_order(u: Unit) -> Dictionary:
	if saving.has(u):
		return _save_order(u)
	if hunting:
		return _hunt_order(u)
	var home: Dictionary = ct_home.get(u, {"site": "mid", "pos": arena.pt("mid_hold"), "look": arena.pt("mid_center")})
	match ct_state.get(u, "hold"):
		"aggro":
			thought[u] = "aggressive mid for an early pick"
			return _order([arena.jittered("mid_center", rng, 1)], arena.pt("mid_entry"), "", true)
		"info":
			var spot: Vector2 = ct_rotate_dest.get(u, [home.pos, home.look])[0]
			var look: Vector2 = ct_rotate_dest.get(u, [home.pos, home.look])[1]
			thought[u] = "info play: peeking for the hit"
			return _order([spot], look, "", true)
		"rotate":
			if m.round_clock < float(ct_rotate_at.get(u, 0.0)):
				thought[u] = "heard the call, about to rotate"
				return _home_order(home)
			var d: Array = ct_rotate_dest[u]
			var site_r := ct_call_site if ct_call_site != "" else String(home.site)
			if ct_rot_stage.has(u) and not ct_rot_go.get(site_r, false):
				thought[u] = "rotating %s: gathering" % site_r
				return _order([ct_rot_stage[u]], arena.site_center(site_r) if site_r in ["A", "B"] else d[1], "", true)
			thought[u] = "rotating %s: going in" % site_r
			return _order([d[0]], d[1], "", true)
		"flank":
			if m.round_clock < float(ct_rotate_at.get(u, 0.0)):
				return _home_order(home)
			var site := ct_call_site if ct_call_site != "" else "A"
			var pts: Array[Vector2] = []
			for p in arena.site_info[site].flank:
				pts.append(arena.jittered(p, rng, 1))
			return _order(pts, arena.site_center(site), "", true)
		"retake":
			var stage: String = ct_retake_stage.get(u, "ct_spawn")
			if not ct_retake_go:
				thought[u] = "retake: waiting for team at %s" % stage
				return _order([arena.jittered(stage, rng, 1)], m.bomb_pos, "", true)
			if u == _defuser():
				if _retake_clear():
					thought[u] = "defusing"
					return _order(_via_stage(u, stage, m.bomb_pos), Vector2.ZERO, "defuse")
				thought[u] = "retake: clear first, then defuse"
				var near: Vector2 = m.bomb_pos.lerp(arena.pt(stage), 0.45)
				var ho := _order([arena.cell_center(arena.nearest_open(arena.world_to_cell(near)))], m.bomb_pos, "", true)
				ho["aim"] = _next_post_spot(u)
				return ho
			var c := arena.world_to_cell(m.bomb_pos) + Vector2i(rng.randi_range(-3, 3), rng.randi_range(-3, 3))
			var spot := arena.cell_center(arena.nearest_open(c))
			var o := _order(_via_stage(u, stage, spot), m.bomb_pos, "", false)
			o["aim"] = _next_post_spot(u)
			thought[u] = "retake: clearing post-plant spots"
			return o
		"save":
			thought[u] = "saving the gun"
			return _order([arena.pt("ct_spawn")], arena.pt("ct_mid"), "", true)
		"contest":
			return _contest_order(u)
		"fallback":
			thought[u] = "outnumbered: falling back to retake"
			var st := ct_call_site if ct_call_site != "" else String(home.site)
			if st == "mid":
				st = "A"
			return _order([arena.jittered(arena.site_info[st].retake[0], rng, 1)], arena.site_center(st), "", true)
	return _home_order(home)


## The CT on defuse duty. Sticks with one player until they die, so the role
## doesn't ping-pong between two CTs standing near the bomb.
func _defuser() -> Unit:
	if ct_defuser == null or not is_instance_valid(ct_defuser) or not ct_defuser.alive:
		ct_defuser = m._closest(CT, m.bomb_pos)
	return ct_defuser


## Route through the staging point only if we haven't passed it yet, and never
## when no Ts are left (just go).
func _via_stage(u: Unit, stage: String, dest: Vector2) -> Array:
	var sp := arena.pt(stage)
	var ts_alive := _alive(T).size()
	if ts_alive == 0 or u.global_position.distance_to(dest) <= sp.distance_to(dest) + 64.0:
		return [dest]
	return [sp, dest]


## Short "what is this bot doing" text for spectate mode.
func debug_label(u: Unit) -> String:
	var s: String = thought.get(u, "")
	if s == "":
		if u.side == T:
			s = "%s %s" % [t_route.get(u, "?"), t_phase]
		else:
			s = "%s %s" % [ct_state.get(u, "hold"), ct_home.get(u, {}).get("site", "")]
	if saving.has(u):
		s = "SAVING: " + s
	if u.has_bomb:
		s += " [BOMB]"
	return s


## Controlled by a person (not the dev-test autoplay bot standing in for you).
func _human(u: Unit) -> bool:
	return u.data.is_user and not Game.autoplay


func is_escaping(u: Unit) -> bool:
	return _escaping.has(u) and not hunting


func is_saving(u: Unit) -> bool:
	return saving.has(u)


# =============================================================================
# Shared knowledge: clearing angles
# =============================================================================

## An angle counts as cleared when a teammate has had eyes on it (in their
## view cone, line of sight, close enough) and nobody was there.
func _update_cleared() -> void:
	for side in [T, CT]:
		var angles := _angles_for(side)
		if angles.is_empty():
			continue
		for a: Vector2 in angles:
			if cleared[side].has(a):
				continue
			for u in _alive(side):
				var to := a - u.global_position
				var d := to.length()
				if d > 1000.0 or (d > 90.0 and u.aim_dir.dot(to / d) < u.data.fov_dot()):
					continue
				if m.has_line_of_sight(u.global_position, a):
					var enemy_there := false
					for e: Unit in m.enemies_of(side):
						if e.global_position.distance_to(a) < 110.0 and m.can_see(u, e):
							enemy_there = true # Only what they can actually see.
					if not enemy_there:
						cleared[side][a] = m.round_clock
					break


func _angles_for(side: int) -> Array:
	if side == T and t_phase == "execute":
		return arena.site_angles.get(t_site, [])
	if side == CT and m.bomb_state == m.Bomb.PLANTED:
		return post_spots
	return []


## Each T walking in pre-aims one uncleared angle; when it's cleared, the next.
func _assign_clearing(ts: Array[Unit]) -> void:
	var angles: Array = arena.site_angles.get(t_site, [])
	if angles.is_empty():
		return
	var site_c := arena.site_center(t_site)
	var taken := {}
	for u in ts:
		var a = t_assigned.get(u, null)
		if a != null and not cleared[T].has(a):
			taken[a] = true
	for u in ts:
		if u == t_lurker and not _late_push:
			continue
		if u.global_position.distance_to(site_c) > 1300.0:
			continue
		var cur = t_assigned.get(u, null)
		if cur != null and not cleared[T].has(cur):
			continue
		var best = null
		var best_d := INF
		for a: Vector2 in angles:
			if cleared[T].has(a) or taken.has(a):
				continue
			var d := u.global_position.distance_to(a)
			if d < best_d:
				best_d = d
				best = a
		if best == null:
			t_assigned.erase(u)
		else:
			t_assigned[u] = best
			taken[best] = true
		if orders.has(u):
			orders[u]["aim"] = t_assigned.get(u, Vector2.INF)


func _site_clear() -> bool:
	var angles: Array = arena.site_angles.get(t_site, [])
	var done := 0
	for a in angles:
		if cleared[T].has(a):
			done += 1
	var frac := 1.0 if angles.is_empty() else float(done) / angles.size()
	var known_on_site := _fresh_enemies_near(T, arena.site_center(t_site), 650.0, 2.5)
	if frac >= 0.6 and known_on_site == 0:
		return true
	# Two of us on site and quiet for a moment: good enough.
	var on_site := 0
	for u in _alive(T):
		if arena.site_at(u.global_position) == t_site:
			on_site += 1
	if on_site >= 2 and known_on_site == 0 and m.round_clock - t_contact_time > 2.5:
		return true
	# Can't clear forever: time, numbers, or we've been on site a while.
	var need := 12.0 * arena.tempo
	if m.round_time_left < need + 8.0 or _alive(T).size() <= 2:
		return true
	return t_on_site_at >= 0.0 and m.round_clock - t_on_site_at > 5.0 and known_on_site == 0


func _fresh_enemies_near(side: int, pos: Vector2, radius: float, max_age: float) -> int:
	var n := 0
	for e in seen_by[side]:
		if is_instance_valid(e) and e.alive and m.round_clock - float(seen_by[side][e].time) <= max_age 				and pos.distance_to(seen_by[side][e].pos) < radius:
			n += 1
	return n


func _retake_clear() -> bool:
	var defuse_need: float = m.DEFUSE_TIME_KIT if _defuser() != null and _defuser().has_kit else m.DEFUSE_TIME
	if m.bomb_timer < defuse_need + 4.0 or _alive(T).is_empty():
		return true
	if known_enemies_near(CT, m.bomb_pos, 800.0) > 0:
		return false
	var done := 0
	for a in post_spots:
		if cleared[CT].has(a):
			done += 1
	return post_spots.is_empty() or float(done) / post_spots.size() >= 0.6


func _next_post_spot(u: Unit) -> Vector2:
	var best := Vector2.INF
	for a: Vector2 in post_spots:
		if cleared[CT].has(a):
			continue
		if best == Vector2.INF or u.global_position.distance_to(a) < u.global_position.distance_to(best):
			best = a
	return best


# =============================================================================
# CT: info plays and rotations that arrive together
# =============================================================================

## Quiet round: one CT steps up to look for the hit instead of everyone waiting.
func _maybe_info_play(cts: Array[Unit]) -> void:
	if ct_info != null:
		if not ct_info.alive or m.round_clock > ct_info_until or m.round_clock - t_contact_time < 0.5 or ct_call_site != "":
			if ct_info.alive and ct_state.get(ct_info, "") == "info":
				ct_state[ct_info] = "hold"
				orders.erase(ct_info)
			ct_info = null
		return
	if Game.ab_flag("no_info"):
		return
	if _ct_info_done or m.round_clock < 13.0 * arena.tempo or m.round_clock > 40.0 * arena.tempo:
		return
	# Only when nobody has seen or heard anything recently.
	for e in seen_by[CT]:
		if m.round_clock - float(seen_by[CT][e].time) < 8.0:
			return
	_ct_info_done = true
	var best: Unit = null
	var best_score := -INF
	for u in cts:
		if ct_state.get(u, "") != "hold" or u.weapon.cat == WeaponData.SNIPER:
			continue
		var sc := rng.randf() + (1.0 if u.data.role in ["Entry", "Lurker"] else 0.0) + u.data._t("decision")
		if sc > best_score:
			best_score = sc
			best = u
	if best == null or rng.randf() > 0.35 + 0.5 * best.data._t("decision"):
		return
	var site: String = ct_home[best].site
	var spot := arena.pt("mid_entry")
	var look := arena.pt("mid_center")
	if site in ["A", "B"]:
		var route: Dictionary = arena.routes[arena.site_info[site].main_route]
		spot = arena.pt(route.entry)
		look = arena.pt(route.stage)
	ct_info = best
	_say(best, "Quiet round. I'll take a look %s." % ("mid" if site == "mid" else "out " + site))
	ct_info_until = m.round_clock + rng.randf_range(6.0, 10.0)
	ct_state[best] = "info"
	ct_rotate_dest[best] = [spot, look]
	orders.erase(best)


func _update_rotation_gather(cts: Array[Unit]) -> void:
	var site := ct_call_site
	if site == "" or ct_rot_go.get(site, false):
		return
	var rotators: Array[Unit] = []
	var staged := 0
	for u in cts:
		if ct_state.get(u, "") == "rotate" and ct_rot_stage.has(u) and m.round_clock >= float(ct_rotate_at.get(u, 0.0)):
			rotators.append(u)
			if u.global_position.distance_to(ct_rot_stage[u]) < STAGE_RADIUS * 2.0:
				staged += 1
	if rotators.is_empty():
		return
	if staged > 0 and not _ct_rot_first.has(site):
		_ct_rot_first[site] = m.round_clock
	# Anchors in trouble (fighting on site) can't wait for a perfect regroup.
	var anchors := 0
	for u in cts:
		if ct_home[u].site == site and ct_state.get(u, "") == "hold":
			anchors += 1
	var waited: float = m.round_clock - float(_ct_rot_first.get(site, m.round_clock))
	if staged >= mini(2, rotators.size()) or waited > 4.0 or anchors == 0:
		ct_rot_go[site] = true
		for u in rotators:
			orders.erase(u)


# =============================================================================
# Saving: play for the next round when this one is lost
# =============================================================================

func _update_saves() -> void:
	var ts := _alive(T)
	var cts := _alive(CT)
	if ts.is_empty() or cts.is_empty():
		return
	if m.bomb_state != m.Bomb.PLANTED:
		_t_save_check(ts, cts)
	else:
		_ct_save_check(cts, ts)


## Ts can't plant in time, or are hopelessly outnumbered late: keep the guns.
func _t_save_check(ts: Array[Unit], cts: Array[Unit]) -> void:
	if saving.has(ts[0]) or m.round_clock < 20.0:
		return
	var from: Vector2 = m.bomb_pos if m.bomb_state == m.Bomb.DROPPED else (m.bomb_carrier.global_position if m.bomb_carrier != null else ts[0].global_position)
	var speed := ts[0].top_speed() * 0.85
	var travel := from.distance_to(t_plant_spot) * 1.25 / speed
	var cant_plant: bool = m.round_time_left < travel + m.PLANT_TIME + 2.0
	var outnumbered: bool = ts.size() <= 2 and cts.size() >= ts.size() + 2 and m.round_time_left < 50.0 * arena.tempo
	if not (cant_plant or outnumbered):
		return
	# Worth saving? Guns are worth more when the team is broke.
	var gear := 0
	var money := 0
	for u in ts:
		if u.primary != null:
			gear += 1
		money += m.money_of(u.data)
	var broke := money / ts.size() < 3500
	if gear == 0 and not broke and not cant_plant:
		return
	var caller := igl(T)
	var smart: float = (caller if caller != null else ts[0]).data._t("decision")
	if rng.randf() > 0.35 + 0.6 * smart:
		return # Poor decision makers keep forcing it.
	_say_caller(T, "Save it, keep the guns for next round.", true)
	for u in ts:
		_start_save(u)


## CTs can't reach and defuse in time (or 1vMany with the clock short): save.
func _ct_save_check(cts: Array[Unit], ts: Array[Unit]) -> void:
	if saving.has(cts[0]):
		return
	var best := INF
	for u in cts:
		var need: float = m.DEFUSE_TIME_KIT if u.has_kit else m.DEFUSE_TIME
		var travel := u.global_position.distance_to(m.bomb_pos) * 1.2 / (u.top_speed() * 0.9)
		best = minf(best, travel + need)
	var hopeless: bool = best > m.bomb_timer - 0.5
	if not hopeless and cts.size() == 1 and ts.size() >= 3 and m.bomb_timer < best + 10.0:
		hopeless = true
	if not hopeless and cts.size() * 2 <= ts.size() and m.bomb_timer < best + 12.0:
		hopeless = true # 2v4 into a set-up crossfire with the clock low.
	if not hopeless:
		return
	if rng.randf() > 0.4 + 0.55 * cts[0].data._t("decision"):
		return
	_say_caller(CT, "Can't make it. Save, save.", true)
	for u in cts:
		_start_save(u)
		ct_state[u] = "save"


var _save_spot := {}


func _start_save(u: Unit) -> void:
	saving[u] = true
	# Hide: tucked in a corner away from the enemies (and clear of a planted
	# bomb), toward home, where a hunting team won't just walk into us.
	if m.bomb_state == m.Bomb.PLANTED:
		_save_spot[u] = _hide_spot(u, m.bomb_pos, m.BOMB_RADIUS + 140.0, maxf(m.bomb_timer - 1.0, 2.0))
	else:
		var threat := intel_near(u.side, u.global_position, 2500.0)
		if threat == Vector2.INF:
			threat = arena.pt("ct_spawn") if u.side == T else arena.spawn_points(T)[0]
		_save_spot[u] = _hide_spot(u, threat, 450.0, 9.0)
	orders[u] = _save_order(u)


## Where to hide: open cells at least `min_r` from `avoid`, reachable in
## `max_time`, scored on being out of sight of every enemy we know about (and
## of `avoid`), tucked into a corner, and toward home.
func _hide_spot(u: Unit, avoid: Vector2, min_r: float, max_time: float) -> Vector2:
	var me := u.global_position
	var speed := u.top_speed() * 0.9
	var home := arena.pt("ct_spawn") if u.side == CT else arena.spawn_points(T)[0]
	var threats: Array[Vector2] = [avoid]
	for e in seen_by[u.side]:
		if is_instance_valid(e) and e.alive:
			threats.append(seen_by[u.side][e].pos)
	var cands: Array = []
	for k in 110:
		var r := rng.randf_range(min_r + 20.0, min_r + 750.0)
		var c := arena.nearest_open(arena.world_to_cell(avoid + Vector2.from_angle(rng.randf() * TAU) * r))
		var p := arena.cell_center(c)
		if p.distance_to(avoid) < min_r or me.distance_to(p) / speed > max_time:
			continue
		var sc := 0.0
		for t in threats:
			if m.has_wall_los(t, p):
				sc -= 3.0
		var walls := 0
		for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
			if arena.is_solid(c + dv):
				walls += 1
		sc += minf(walls, 5) * 0.35 # Corners and nooks.
		sc -= me.distance_to(p) / 700.0
		sc += (me.distance_to(home) - p.distance_to(home)) / 900.0
		sc += rng.randf() * 0.2
		cands.append([sc, p])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	for i in mini(6, cands.size()):
		var p: Vector2 = cands[i][1]
		if _walk_dist(me, p) / speed <= max_time:
			return p
	return _escape_point(u, min_r)


func _save_order(u: Unit) -> Dictionary:
	thought[u] = "saving: round is lost, keep the gun"
	return _order([_save_spot.get(u, u.global_position)], arena.pt("mid_center"), "", true)


# =============================================================================
# Post-round: 5 seconds of exit time
# =============================================================================

func on_round_decided(winner_side: int) -> void:
	_remember_round(winner_side)
	hunting = true
	for u in _alive(1 - winner_side):
		_start_save(u)
		thought[u] = "round lost: run and keep the gun"
	for u in _alive(winner_side):
		saving.erase(u)
		orders[u] = _hunt_order(u)


func _hunt_order(u: Unit) -> Dictionary:
	var target := Vector2.INF
	var best_t := -INF
	for e in seen_by[u.side]:
		if is_instance_valid(e) and e.alive and float(seen_by[u.side][e].time) > best_t:
			best_t = float(seen_by[u.side][e].time)
			target = seen_by[u.side][e].pos
	if target == Vector2.INF:
		target = arena.pt("ct_spawn") if u.side == T else arena.spawn_points(T)[0]
	thought[u] = "round won: hunting savers"
	return _order([target], target, "", false)


func _update_post_round() -> void:
	var winner: int = m.round_winner_side
	if winner < 0:
		return
	for u in _alive(winner):
		var o: Dictionary = orders.get(u, {})
		if o.is_empty() or u.global_position.distance_to(o.points[-1]) < 60.0:
			orders[u] = _hunt_order(u)


# =============================================================================
# Bomb about to blow: get out of the blast
# =============================================================================

## Ts stay to stop the defuse as long as it matters, then run once no CT can
## finish a defuse in time. CTs who can't defuse in time run too.
func _update_bomb_escape() -> void:
	if m.bomb_state != m.Bomb.PLANTED:
		return
	var defusing: bool = m.defuser != null and is_instance_valid(m.defuser) and m.defuser.alive and m.defuser.action == Unit.Action.DEFUSE
	var safe_r: float = m.BOMB_RADIUS + 70.0
	for u: Unit in m.units:
		if not u.alive or _human(u) or _escaping.has(u):
			continue
		var d := u.global_position.distance_to(m.bomb_pos)
		if d > safe_r:
			continue
		if u.side == CT:
			if u == m.defuser and defusing and u.action_timer < m.bomb_timer:
				continue # Will make it: keep defusing.
			var need: float = m.DEFUSE_TIME_KIT if u.has_kit else m.DEFUSE_TIME
			var travel := d / (u.top_speed() * 0.9)
			if travel + need < m.bomb_timer - 0.3:
				continue # Still time to defuse.
		elif defusing and m.defuser.action_timer < m.bomb_timer:
			continue # A defuse that will finish: stay and stop it.
		# A real hiding spot well clear of the blast (not one step past the edge),
		# out of sight of the enemies we know about. Picked once per bot.
		if not _save_spot.has(u) or (_save_spot[u] as Vector2).distance_to(m.bomb_pos) < m.BOMB_RADIUS + 60.0:
			_save_spot[u] = _hide_spot(u, m.bomb_pos, m.BOMB_RADIUS + 140.0, maxf(m.bomb_timer - 1.0, 2.0))
		var spot: Vector2 = _save_spot[u]
		var time_out := _walk_dist(u.global_position, spot) / (u.top_speed() * 0.9) + 1.0
		if _bomb_seen(u) > time_out + 2.5: # Someone who lost track of the timer goes late.
			continue # Not yet: hold the bomb a little longer.
		var o := _order([spot], m.bomb_pos, "", false)
		_escaping[u] = o
		orders[u] = o
		thought[u] = "bomb about to blow: getting clear"


## The bomb timer as `u` believes it (BotController.bomb_blind).
func _bomb_seen(u: Unit) -> float:
	for c in u.get_children():
		if c is BotController:
			return (c as BotController).bomb_time_seen()
	return m.bomb_timer


## Nearest walkable spot outside the blast, preferring the way home.
func _escape_point(u: Unit, safe_r: float) -> Vector2:
	var home := arena.spawn_points(T)[0] if u.side == T else arena.pt("ct_spawn")
	var path := arena.find_path(u.global_position, home)
	for p in path:
		if p.distance_to(m.bomb_pos) > safe_r:
			return p
	var away: Vector2 = (u.global_position - m.bomb_pos).normalized()
	if away == Vector2.ZERO:
		away = Vector2.RIGHT
	return arena.cell_center(arena.nearest_open(arena.world_to_cell(m.bomb_pos + away * (safe_r + 40.0))))


# =============================================================================
# Utility: when and where bots throw grenades
# =============================================================================

func _update_utility() -> void:
	if not m.is_live():
		return
	if Game.ab_flag("no_util"):
		return
	for u: Unit in m.units:
		if not u.alive or _human(u) or u.grenades.is_empty() or _escaping.has(u):
			continue
		if m.round_clock < float(_util_cd.get(u, 2.0)):
			continue
		var skill := u.data._t("utility")
		var plan: Dictionary = _t_util(u) if u.side == T else _ct_util(u)
		if plan.is_empty():
			continue
		# Not every chance gets taken: good utility players use theirs reliably.
		var keen := 0.0
		if side_style[u.side] == "utility":
			keen += 0.2
		if pers(u).has("nade_happy"):
			keen += 0.2
		if rng.randf() > 0.25 + 0.6 * skill + keen:
			_util_cd[u] = m.round_clock + 1.5
			continue
		var target: Vector2 = plan.target
		var err := lerpf(110.0, 12.0, skill)
		var aimed := target + Vector2(rng.randfn(0.0, err), rng.randfn(0.0, err))
		if m.utility.throw(u, plan.kind, aimed):
			_util_cd[u] = m.round_clock + 2.5
			thought[u] = String(plan.why)
			if plan.kind == "smoke":
				_smoked.append(target)


func _has(u: Unit, kind: String) -> bool:
	return int(u.grenades.get(kind, 0)) > 0


## Straight throw path, in range, and (for damage nades) not on our own people.
func _can_throw(u: Unit, target: Vector2, kind: String) -> bool:
	var d := u.global_position.distance_to(target)
	if d > Utility.MAX_THROW * 0.95 or d < 90.0:
		return false
	if not m.has_wall_los(u.global_position, target):
		return false
	var r := 0.0
	if kind == "frag":
		r = Utility.FRAG_RADIUS * 0.6
	elif kind == "molotov":
		r = Utility.FIRE_RADIUS + 40.0
	if r > 0.0:
		if d < r + 30.0:
			return false
		for o: Unit in m.units:
			if o.alive and o.side == u.side and o != u and o.global_position.distance_to(target) < r:
				return false
	return true


func _smoked_near(p: Vector2) -> bool:
	for s in _smoked:
		if s.distance_to(p) < Utility.SMOKE_RADIUS * 1.2:
			return true
	return false


func _t_util(u: Unit) -> Dictionary:
	if t_phase == "execute" and t_site != "" and m.bomb_state != m.Bomb.PLANTED and m.round_clock - t_execute_at < 25.0:
		var entry: Vector2 = orders.get(u, {}).get("entry", arena.site_center(t_site))
		var de := u.global_position.distance_to(entry)
		if de < 700.0 and arena.site_at(u.global_position) != t_site:
			var spots: Array = arena.site_angles.get(t_site, [])
			if _has(u, "smoke"):
				for sp: Vector2 in spots:
					if not _smoked_near(sp) and _can_throw(u, sp, "smoke"):
						return {"kind": "smoke", "target": sp, "why": "smoking off a CT angle"}
			if _has(u, "molotov"):
				for sp: Vector2 in spots:
					if not _smoked_near(sp) and _can_throw(u, sp, "molotov"):
						return {"kind": "molotov", "target": sp, "why": "molly on a corner"}
			if _has(u, "flash") and de < 450.0:
				var fp := entry + (arena.site_center(t_site) - entry).normalized() * 170.0
				if _can_throw(u, fp, "flash"):
					return {"kind": "flash", "target": fp, "why": "flashing the entry"}
	if m.bomb_state == m.Bomb.PLANTED and m.defuser != null and is_instance_valid(m.defuser) and m.defuser.alive \
			and m.defuser.action == Unit.Action.DEFUSE and u.global_position.distance_to(m.bomb_pos) < SOUND_RANGE.defuse:
		for k: String in ["molotov", "frag", "flash"]:
			if _has(u, k) and _can_throw(u, m.bomb_pos, k):
				return {"kind": k, "target": m.bomb_pos, "why": "utility on the defuser"}
	return _frag_known(u)


func _ct_util(u: Unit) -> Dictionary:
	# Ts pushing an entrance: stall it.
	for site: String in ["A", "B"]:
		var info: Dictionary = arena.site_info[site]
		var seen := {}
		for rk: String in ["main_route", "alt_route", "short_route"]:
			var rn: String = info.get(rk, "")
			if rn == "" or not arena.routes.has(rn) or String(arena.routes[rn].entry) == "":
				continue
			var e := arena.pt(arena.routes[rn].entry)
			if seen.has(e):
				continue
			seen[e] = true
			var n := known_enemies_near(CT, e, 450.0)
			if n < 2 or u.global_position.distance_to(e) > 800.0:
				continue
			var tp := intel_near(CT, e, 450.0)
			if tp == Vector2.INF:
				tp = e
			if _has(u, "molotov") and _can_throw(u, tp, "molotov"):
				return {"kind": "molotov", "target": tp, "why": "molly on the push"}
			if _has(u, "smoke") and n >= 3 and not _smoked_near(e) and _can_throw(u, e, "smoke"):
				return {"kind": "smoke", "target": e, "why": "smoking the push to buy time"}
			if _has(u, "frag") and _can_throw(u, tp, "frag"):
				return {"kind": "frag", "target": tp, "why": "nade on the push"}
	# Retake: flash the site before going in.
	if m.bomb_state == m.Bomb.PLANTED and ct_retake_go and _has(u, "flash"):
		var fp: Vector2 = m.bomb_pos
		if _can_throw(u, fp, "flash"):
			return {"kind": "flash", "target": fp, "why": "flashing for the retake"}
	if m.bomb_state == m.Bomb.PLANTED and ct_retake_go and _has(u, "molotov"):
		var sp := _next_post_spot(u)
		if sp != Vector2.INF and _can_throw(u, sp, "molotov"):
			return {"kind": "molotov", "target": sp, "why": "molly on a post-plant spot"}
	return _frag_known(u)


## A known enemy just out of sight (behind cover): frag them.
func _frag_known(u: Unit) -> Dictionary:
	if not _has(u, "frag"):
		return {}
	var known: Dictionary = seen_by[u.side]
	for e in known:
		if not is_instance_valid(e) or not e.alive:
			continue
		var s: Dictionary = known[e]
		if m.round_clock - float(s.time) > 2.0:
			continue
		var p: Vector2 = s.pos
		var d := u.global_position.distance_to(p)
		if d > 220.0 and d < 650.0 and not m.has_line_of_sight(u.global_position, p) and not s.get("cleared", false) and _can_throw(u, p, "frag"):
			return {"kind": "frag", "target": p, "why": "nade on a known enemy"}
	return {}


func _home_order(home: Dictionary) -> Dictionary:
	var pts: Array[Vector2] = [home.pos]
	for u in ct_home:
		if ct_home[u] == home:
			thought[u] = "holding %s" % home.site
	return {"id": "ct_home_%s_%s" % [home.site, home.pos], "points": pts, "look": home.look, "action": "", "hold": true}


# =============================================================================
# Match memory: both sides read the opponent as the half goes on
# =============================================================================

func _hist() -> Dictionary:
	var team: int = m.team_of_side(T) # Memory is about this half's attackers.
	if not hist.has(team):
		hist[team] = {"hits": {"A": 0.0, "B": 0.0}, "ct_seen": {"A": 0.0, "B": 0.0}, "strat": {}, "early": 0.0,
			"rush": 0.0, "last": "", "mid_deaths": 0.0, "mid_used": 0.0}
	return hist[team]


func _remember_round(winner_side: int) -> void:
	var h := _hist()
	h["mid_deaths"] = float(h.get("mid_deaths", 0.0)) * 0.65
	var name: String = t_strat.get("name", "")
	if name != "":
		var rec: Array = h.strat.get(name, [0, 0])
		rec[0 if winner_side == T else 1] += 1
		h.strat[name] = rec
	for k in ["A", "B"]:
		h.hits[k] = float(h.hits[k]) * 0.6
		h.ct_seen[k] = float(h.ct_seen[k]) * 0.6 + (_round_ct_seen[k] as Dictionary).size()
	if t_phase in ["execute", "postplant"] and t_site in ["A", "B"]:
		h.hits[t_site] = float(h.hits[t_site]) + 1.0
	h.early = float(h.early) * 0.6
	h.rush = float(h.rush) * 0.6
	if t_on_site_at >= 0.0 and t_on_site_at < 25.0 * arena.tempo:
		h.rush = float(h.rush) + 1.0
	h.last = name


func _side_iq(side: int) -> float:
	var us := _side_units(side)
	if us.is_empty():
		return 0.5
	var s := 0.0
	for u in us:
		s += u.data._t("decision")
	return s / us.size()


## T strat weights shift with what's worked and where the CTs have been.
func _pick_t_strat() -> Dictionary:
	if Game.ab_flag("no_adapt"):
		_t_reason = ""
		return _pick(T_STRATS.filter(func(x: Dictionary) -> bool: return not x.has("fake")))
	var h := _hist()
	var iq := _side_iq(T)
	var heavy := ""
	var diff := float(h.ct_seen.A) - float(h.ct_seen.B)
	if absf(diff) >= 1.5:
		heavy = "A" if diff > 0 else "B"
	var opts: Array = []
	var why := {}
	var style: String = team_style(m.teams[m.team_of_side(T)].team_name)
	var losing: bool = int(m.loss_streak[m.team_of_side(T)]) >= 2
	for st: Dictionary in T_STRATS:
		var w := float(st.weight)
		var rec: Array = h.strat.get(st.name, [0, 0])
		w *= clampf(1.0 + 0.45 * iq * (rec[0] - rec[1]), 0.3, 2.5)
		var rush: bool = st.get("rush", false)
		var deflt: bool = st.get("default", false)
		match style:
			"aggressive":
				w *= 2.2 if rush else (0.6 if deflt else 1.0)
			"default":
				w *= 2.0 if deflt else (0.5 if rush else (1.3 if st.name.begins_with("Split") else 1.0))
			"utility":
				w *= 1.5 if (st.has("fake") or st.name.begins_with("Execute")) else 1.0
			"awp":
				w *= 1.4 if deflt else 1.0
		# Their CTs keep picking us off early: slow default, no blind rushes.
		if float(h.early) >= 1.2:
			w *= lerpf(1.0, 0.5, iq) if rush else (lerpf(1.0, 1.6, iq) if deflt else 1.0)
			if deflt:
				why[st.name] = "they push early, slow default"
		# Losing streak: switch it up.
		if losing and st.name == String(h.get("last", "")):
			w *= lerpf(0.7, 0.2, iq)
		# They're on an eco: just run them over.
		if enemy_eco[T] and rush:
			w *= 2.5
			why[st.name] = "they're broke, rush them"
		if heavy != "" and st.site != "":
			w *= lerpf(1.0, 0.35, iq) if st.site == heavy else lerpf(1.0, 1.8, iq)
			if st.has("fake") and st.fake == heavy:
				w *= 1.4 # They over-rotate there: fake it.
		var d := st.duplicate()
		d.weight = maxi(1, int(round(w * 10.0)))
		opts.append(d)
		if rec[0] > rec[1]:
			why[st.name] = "it worked last time"
		elif heavy != "" and st.site != "" and st.site != heavy:
			why[st.name] = "they're heavy on %s" % heavy
	var pick := _pick(opts)
	_t_reason = why.get(pick.name, "")
	if _t_reason == "" and losing and pick.name != String(h.get("last", "")):
		_t_reason = "switching it up"
	return pick


## CT setup: stack the site they keep hitting; push out against ecos.
func _pick_ct_setup() -> Dictionary:
	if Game.ab_flag("no_adapt"):
		_ct_reason = ""
		return _pick(CT_SETUPS.filter(func(x: Dictionary) -> bool: return not x.has("aggro")))
	var h := _hist()
	var iq := _side_iq(CT)
	var opts: Array = []
	# What we read of their buy (guns seen), not their bank balance.
	var t_eco: bool = enemy_eco[CT]
	var style: String = team_style(m.teams[m.team_of_side(CT)].team_name)
	var lean := float(h.hits.A) - float(h.hits.B)
	_ct_reason = ""
	for st: Dictionary in CT_SETUPS:
		var w := float(st.weight)
		if st.name == "Stack A" and lean > 0.8:
			w *= 1.0 + lean * 2.0 * iq
		elif st.name == "Stack B" and lean < -0.8:
			w *= 1.0 - lean * 2.0 * iq
		elif st.name == "Aggressive" and t_eco:
			w *= 5.0
		if st.name == "Aggressive":
			if style == "aggressive":
				w *= 2.5
			if float(h.rush) >= 1.2:
				w *= lerpf(1.0, 0.3, iq) # Pushing out into rushes gets you killed.
			if float(h.early) >= 1.2:
				w *= 1.0 + float(h.early) * 0.6 * iq # Our early picks keep working.
		elif st.name == "Standard" and style == "default":
			w *= 1.5
		var d := st.duplicate()
		d.weight = maxi(1, int(round(w * 10.0)))
		opts.append(d)
	var pick := _pick(opts)
	if pick.name == "Stack A" and lean > 0.8:
		_ct_reason = "they keep hitting A"
	elif pick.name == "Stack B" and lean < -0.8:
		_ct_reason = "they keep hitting B"
	elif pick.name == "Aggressive" and t_eco:
		_ct_reason = "they're on an eco"
	return pick


# =============================================================================
# Radio: what the bots tell each other (shown to the player's team)
# =============================================================================

func pers(u: Unit) -> BotPersonality:
	if not _pers_cache.has(u.data):
		_pers_cache[u.data] = BotPersonality.for_player(u.data)
	return _pers_cache[u.data]


## Rough place name for callouts.
func _where(p: Vector2) -> String:
	var site := arena.site_at(p)
	if site != "":
		return "on " + site
	match arena.threat_at(p):
		"A":
			return "near A"
		"B":
			return "near B"
		"mid":
			return "mid"
		"ct":
			return "CT side"
		"t":
			return "T side"
	return "close"


func _say(u: Unit, text: String, important: bool = false) -> void:
	if u == null or not is_instance_valid(u) or _human(u) or not m.has_method("radio"):
		return
	var side := u.side
	var now: float = m.round_clock
	if not important and now - float(_radio_t[side]) < 1.5:
		return
	if now - float(_radio_last[side].get(text, -100.0)) < 8.0:
		return
	_radio_t[side] = now
	_radio_last[side][text] = now
	m.radio(u, text)


## The team's caller (in-game leader: best decision maker alive) says it.
func _say_caller(side: int, text: String, important: bool = false) -> void:
	var best := igl(side)
	if important:
		igl_call[side] = text
	_say(best, text, important)


## In-game leader: the bot with the best Decision Making still alive.
func igl(side: int) -> Unit:
	var best: Unit = null
	for u in _alive(side):
		if not _human(u) and (best == null or u.data._t("decision") > best.data._t("decision")):
			best = u
	return best


## Reading the enemy buy from what they carry (like checking their guns in
## the first fight); poor readers sometimes get it wrong.
func _read_enemy_eco(side: int) -> bool:
	if m.is_pistol_round():
		return false
	var guns := 0
	var n := 0
	for u: Unit in m.units:
		if u.side != side:
			n += 1
			if u.primary != null and u.primary.tier >= 1.5:
				guns += 1
	var eco := n > 0 and guns <= 1
	var reader := igl(side)
	var iq: float = reader.data._t("decision") if reader != null else 0.5
	if rng.randf() < (1.0 - iq) * 0.25 * BotController.mistake_mult:
		eco = not eco # Misread.
	return eco


## The IGL reads the round every couple of seconds and changes the plan.
func _igl_think() -> void:
	if not m.is_live():
		return
	var ts := _alive(T)
	var cts := _alive(CT)
	if ts.is_empty() or cts.is_empty():
		return
	var planted: bool = m.bomb_state == m.Bomb.PLANTED
	if not planted and t_phase == "approach":
		if ts.size() - cts.size() >= 2 and not _igl_done.has("t_up"):
			_igl_done["t_up"] = true
			if not t_called:
				_t_call_site()
			t_deadline = minf(t_deadline, m.round_clock + 2.0)
			_say_caller(T, "We're up %d. Hit %s now, before they regroup." % [ts.size() - cts.size(), t_site], true)
		elif cts.size() - ts.size() >= 2 and m.round_time_left > 45.0 * arena.tempo and not _igl_done.has("t_down"):
			_igl_done["t_down"] = true
			t_deadline = minf(t_deadline + 8.0 * arena.tempo, m.round_clock + m.round_time_left - 35.0 * arena.tempo)
			_say_caller(T, "Down %d. Slow it down, stick together, play for picks." % [cts.size() - ts.size()], true)
	if not planted:
		for region in _t_deaths_at:
			if int(_t_deaths_at[region]) >= 2 and ts.size() <= 3 and not _igl_done.has("ct_two_down"):
				_igl_done["ct_two_down"] = true
				var where := "mid" if region not in ["A", "B"] else String(region)
				var other := "B" if region == "A" else "A"
				_say_caller(CT, "Two down %s, they're light there. One rotate %s." % [where, other], true)
				if ct_call_site == "" or ct_call_strength < 2:
					_ct_call(other, 2)
	elif not _igl_done.has("post_mode"):
		_igl_done["post_mode"] = true
		# Post-plant: up or even -> play time; down with time on the clock -> hunt picks.
		if ts.size() < cts.size() and m.bomb_timer > 25.0:
			t_post_mode = "picks"
			_say_caller(T, "We're down. Play for picks before they group up.", true)
		else:
			t_post_mode = "time"
			_say_caller(T, "Play time. Crossfire, nobody peeks.", true)



func _round_calls() -> void:
	_radio_t = [-100.0, -100.0]
	_radio_last = [{}, {}]
	var strat: String = t_strat.get("name", "")
	var t_line := ""
	if _t_reason == "eco":
		t_line = "Eco. Rush %s together, trade everything." % t_site
	elif t_strat.has("fake"):
		t_line = "Fake %s, make noise, then we hit %s." % [t_strat.fake, t_strat.site]
	elif t_strat.get("default", false):
		t_line = "Default. Spread out, get info, I'll call it."
	elif t_strat.get("rush", false):
		t_line = "Rush %s, full speed." % t_site
	else:
		t_line = "%s." % strat
	if _t_reason != "" and _t_reason != "eco":
		t_line += " (%s)" % _t_reason
	if t_lurker != null and not _human(t_lurker):
		t_line += " %s lurks." % t_lurker.data.player_name
	_say_caller(T, t_line, true)
	var c_line: String = {"Standard": "Standard. Two A, two B, one mid.", "Stack A": "Stack A this round.",
		"Stack B": "Stack B this round.", "Aggressive": "Push out early for picks, then fall back."}.get(ct_setup.get("name", ""), "Standard.")
	if _ct_reason != "":
		c_line += " (%s)" % _ct_reason
	_say_caller(CT, c_line, true)


# =============================================================================
# Helpers
# =============================================================================

# =============================================================================
# Dropped bomb and moving as a group
# =============================================================================

## Bomb on the floor: the nearest T goes for it, the next one covers them,
## and the hit waits until we have it back.
func _update_dropped_bomb_t(ts: Array[Unit]) -> void:
	if m.bomb_state != m.Bomb.DROPPED:
		for u in [t_fetcher, t_escort]:
			if u != null and is_instance_valid(u) and orders.get(u, {}).get("action", "") in ["fetch", "escort"]:
				orders.erase(u)
		t_fetcher = null
		t_escort = null
		_drop_called = false
		return
	if m.bomb_reserved_for != null:
		return
	var cand: Array[Unit] = []
	for u in ts:
		if not _human(u) and not saving.has(u):
			cand.append(u)
	if cand.is_empty():
		return
	if t_fetcher == null or not is_instance_valid(t_fetcher) or not t_fetcher.alive or saving.has(t_fetcher):
		cand.sort_custom(func(a: Unit, b: Unit) -> bool: return a.global_position.distance_to(m.bomb_pos) < b.global_position.distance_to(m.bomb_pos))
		t_fetcher = cand[0]
		if t_escort == t_fetcher:
			t_escort = null
		_drop_called = false
	if orders.get(t_fetcher, {}).get("action", "") != "fetch":
		var fo := _order([m.bomb_pos], Vector2.ZERO, "fetch")
		var threat := intel_near(T, m.bomb_pos, 900.0)
		if threat != Vector2.INF:
			fo["aim"] = threat
		orders[t_fetcher] = fo
		thought[t_fetcher] = "getting the dropped bomb"
	if not _drop_called:
		_drop_called = true
		_say(t_fetcher, "Bomb's down %s, I'll get it. Cover me." % _where(m.bomb_pos), true)
	# Escort: the next closest holds an angle over the pickup.
	if t_escort == null or not is_instance_valid(t_escort) or not t_escort.alive or saving.has(t_escort):
		t_escort = null
		var best_d := 1100.0
		for u in cand:
			if u == t_fetcher or (u == t_lurker and not _lurk_joined):
				continue
			var d := u.global_position.distance_to(m.bomb_pos)
			if d < best_d:
				best_d = d
				t_escort = u
	if t_escort == null:
		return
	var threat := intel_near(T, m.bomb_pos, 1100.0)
	var look: Vector2 = threat
	if look == Vector2.INF:
		look = m.bomb_pos + (m.bomb_pos - arena.pt("ct_spawn")).normalized() * -300.0
	var cur: Dictionary = orders.get(t_escort, {})
	if cur.get("action", "") == "escort" and Vector2(cur.look).distance_to(look) < 250.0:
		return
	var away: Vector2 = t_escort.global_position - m.bomb_pos
	var spot: Vector2 = m.bomb_pos + (away.normalized() * minf(away.length(), 120.0) if away.length() > 1.0 else Vector2.ZERO)
	spot = arena.cell_center(arena.nearest_open(arena.world_to_cell(spot)))
	orders[t_escort] = _order([spot], look, "escort", true)
	thought[t_escort] = "covering the bomb pickup"


## The lurker comes in once the team has the site (or the hit has stalled).
func _lurker_joins() -> bool:
	if t_on_site_at >= 0.0 and m.round_clock - t_on_site_at > 3.0:
		return true
	return t_execute_at >= 0.0 and m.round_clock - t_execute_at > 14.0 * arena.tempo


## The player leading a route in waits at the entrance until someone is close
## enough to trade them (briefly; should_wait caps it).
func _lead_waits(u: Unit, o: Dictionary) -> bool:
	if t_execute_at < 0.0 or m.round_clock - t_execute_at > 8.0 * arena.tempo:
		return false
	var entry: Vector2 = o.get("entry", Vector2.INF)
	if entry == Vector2.INF:
		return false
	var site_c := arena.site_center(t_site)
	if u.global_position.distance_to(entry) > 150.0 or u.global_position.distance_to(site_c) < entry.distance_to(site_c) - 20.0:
		return false
	var coming := false
	for v in _alive(T):
		if v == u or (v == t_lurker and not _lurk_joined):
			continue
		var d := v.global_position.distance_to(u.global_position)
		if d < 380.0:
			return false # Someone's with us: go.
		if v.global_position.distance_to(entry) < 1400.0:
			coming = true
	return coming


## Dropped bomb the CTs know about: the closest one or two close in on it and
## hold it (or sit on it late in the round); the rest keep their positions.
func _contest_order(u: Unit) -> Dictionary:
	var late: bool = m.round_time_left < 25.0 * arena.tempo
	var threat := intel_near(CT, m.bomb_pos, 900.0)
	var t_side: Vector2 = m.bomb_pos + (m.bomb_pos - arena.pt("ct_spawn")).normalized() * 300.0
	if late and _fresh_enemies_near(CT, m.bomb_pos, 600.0, 3.0) == 0:
		thought[u] = "late: sitting on the dropped bomb"
		var o := _order([m.bomb_pos], threat if threat != Vector2.INF else t_side, "", true)
		o["camp"] = true
		return o
	var away: Vector2 = u.global_position - m.bomb_pos
	var spot: Vector2 = m.bomb_pos + away.normalized() * minf(away.length(), 150.0)
	spot = arena.cell_center(arena.nearest_open(arena.world_to_cell(spot)))
	if not m.has_line_of_sight(spot, m.bomb_pos):
		spot = arena.cell_center(arena.nearest_open(arena.world_to_cell(m.bomb_pos.lerp(spot, 0.5))))
	thought[u] = "closing in on the dropped bomb"
	return _order([spot], m.bomb_pos, "", true)


func order_for(u: Unit) -> Dictionary:
	if _escaping.has(u) and not hunting:
		return _escaping[u]
	if not orders.has(u):
		orders[u] = _t_order(u) if u.side == T else _ct_order(u)
	# The defuser role moves to whoever is closest now.
	var o: Dictionary = orders[u]
	if u.side == CT and m.bomb_state == m.Bomb.PLANTED and ct_retake_go and ct_state.get(u, "") == "retake":
		var is_defuser: bool = u == _defuser()
		if is_defuser != (o.action == "defuse"):
			orders[u] = _ct_order(u)
	return orders[u]


func _order(pts: Array, look: Vector2, action: String = "", hold: bool = false) -> Dictionary:
	_seq += 1
	var typed: Array[Vector2] = []
	for p in pts:
		typed.append(p)
	return {"id": "o%d" % _seq, "points": typed, "look": look, "action": action, "hold": hold}


func _alive(side: int) -> Array[Unit]:
	var out: Array[Unit] = []
	for u: Unit in m.units:
		if u.alive and u.side == side:
			out.append(u)
	return out


func _rebuild_side(side: int) -> void:
	for u in _side_units(side):
		orders.erase(u)


func _rebuild_all() -> void:
	orders.clear()
