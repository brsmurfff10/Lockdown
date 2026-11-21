class_name BotController
extends Node
## Individual bot. Tactics (the team brain) hands out orders: waypoints, where
## to look, whether to hold, plant or defuse. The bot plays like a person:
##
## VISION — same rules as the player (Match.sees): a cone in front (width from
##   Positioning), close awareness, peripheral movement, walls block it all.
##   Spotting takes time (Reaction Time, distance, whether we were aimed there).
##
## MEMORY + DECISIONS — when an enemy disappears (or is heard / called out
##   nearby, or shoots us from out of view) the bot remembers where, how hurt
##   they were, and how sure it is. Then it decides like a human would:
##     hold     – work out the way they'd come at us and where they'd appear
##                on it; take a spot nearby that sees that point at a good
##                range for the gun, hidden from where they are now, off the
##                obvious line, with cover a step away; crosshair on the edge
##                they appear from. Wait about as long as they'd take to get
##                there; reload in cover, not on the angle.
##     jiggle   – quick shoulder peek for info, back into cover
##     swing    – wide peek pre-aimed at the spot, to take the fight
##     push     – chase a weak/fleeing enemy to the spot
##     fallback – break line of sight, reload / heal up, then re-hold
##   The choice weighs health vs. theirs, numbers nearby, ammo, weapon, role
##   aggression, time pressure, and whether we're defending a position.
##   Low Decision Making = noisier, worse choices.
##
## FIGHTING — counter-strafes heavy weapons, controls spray, ducks back into
##   cover when hurt/reloading, AWPers un-peek after shots, pistol when dry.
##
## IMPERFECT INFORMATION — bots only act on what they saw (fading ghosts),
##   heard (rough markers, Tactics.hear) or were told. They pre-aim and clear
##   those spots, not the enemy's real position.
##
## STRESS — low HP, being outnumbered / last alive, flashes, a losing streak and
##   teammates dying raise `stress` (0-1): wider aim error, panic sprays,
##   hurried re-peeks. Composure, Decision Making and morale resist it.
##
## HUMAN MISTAKES — dry peeks, badly timed reloads, whiffed flicks, overpeeking
##   after a kill, losing track of the bomb timer. Rarer for better players;
##   everything scales with `mistake_mult` (difficulty).

const ARRIVE_DIST := 20.0
const WAYPOINT_DIST := 40.0
const TRAIL_INTERVAL := 0.3
const TRAIL_SIZE := 14
const MEMORY_TTL := 8.0 ## Seconds until a contact is forgotten.
const WALK_FRAC := 0.6 ## Quiet walking speed (running = audible above Unit.RUN_FRAC).
const BAD_RELOAD_RATE := 0.05 ## Per second, before skill scaling: reloading on a live angle (a human mistake).
const INTEL_REACT_RADIUS := 700.0 ## Heard/called-out enemies closer than this get a plan.

var unit: Unit

var _target: Unit = null
var _reaction_left := 0.0
var _strafe := 0.0
var _strafe_timer := 0.0
var _counter_strafe := true
var _holding := false
var _clock := 0.0

# Order following.
var _order_id := ""
var _points: Array[Vector2] = []
var _point_idx := 0
var _path := PackedVector2Array()
var _path_idx := 0
var _repath_timer := 0.0

# Holding an ordered position.
var _hold_for := ""
var _cover_spot := Vector2.INF
var _peek_spot := Vector2.INF
var _holds_open := false
var _peek_timer := 0.0
var _peeking := false

# Contact memory.
var _mem_pos := Vector2.INF
var _mem_time := -100.0
var _mem_hp := 100.0
var _mem_conf := 0.0 ## 1 = just saw them, lower = heard / stale / peeked and found nothing.
var _mem_enemy: Unit = null

# Current contact plan.
var plan := "" ## "", hold, jiggle, swing, push, fallback (public for tests/debug)
var _plan_timer := 0.0
var _plan_spot := Vector2.INF
var _plan_home := Vector2.ZERO
var _plan_stage := 0
var _intel_cooldown := 0.0
var _plan_total := 0.0 ## Time spent in contact plans since we last made progress on orders.
var _hp_fallback_at := -100.0 ## Last time we fell back for low health.

# Reactions.
var _alert_pos := Vector2.ZERO
var _alert_timer := 0.0
var _evade_timer := 0.0
var _evade_from := Vector2.ZERO
var _duck_timer := 0.0
var _trail: Array[Vector2] = []
var _trail_timer := 0.0

# Aim imperfection (radians): flick error that settles, plus hand jitter.
var _aim_err := 0.0
var _perceive_left := 0.0 ## Seen, but the hand hasn't started moving yet.
var _burst := 0 ## Shots fired since we last ducked.
var _burst_len := 4
var _stuck_t := 0.0
var _gun_goal := Vector2.INF ## A better gun on the floor we're walking to.
var _gun_t := 0.0
var _gun_scan := 0.0
var _gun_skip: Array[Vector2] = [] ## Guns we gave up on (unreachable / took too long).
var _yield_t := 0.0
var _trade_at := -100.0 ## A teammate died near us at this time...
var _trade_pos := Vector2.INF ## ...to an enemy here. ## Time spent letting a teammate through a choke (capped, then we go).
var _unstick_timer := 0.0
var _unstick_dir := Vector2.ZERO
var _jitter := 0.0
var _jitter_target := 0.0
var _jitter_timer := 0.0
var pers: BotPersonality ## Stable habits (aggression, patience, peek style).
var _spotted_at := -100.0 ## Last time an enemy had eyes on us (they know this angle).
var _quiet := false ## Walking (silent) this frame.
var _plan_wait := 0.0 ## Generic per-stage timer for multi-step plans.

## Difficulty knob: scales every deliberate mistake and how much stress bots
## feel. 1.0 = normal, 0 = machine-like, 2 = very human. Set from career difficulty.
static var mistake_mult := 1.0
## Dev stats (behaviour metrics).
static var stats := {"aim_belief": 0, "aim_true": 0, "prefires": 0, "ghost_clears": 0, "whiffs": 0,
	"panic_sprays": 0, "overpeeks": 0, "flash_waits": 0, "dry_peeks": 0, "bad_reloads": 0, "refrags": 0,
	"bomb_blind": 0, "heard_reacts": 0, "fake_defuses": 0, "holds": 0, "hold_moves": 0, "hold_kills": 0,
	"hold_deaths": 0, "hold_cover_reloads": 0, "hold_extends": 0, "flash_dodges": 0, "pistol_swaps": 0}

var stress := 0.0 ## 0 calm .. 1 panicking (public: debug overlay / tests).
var _stress_spike := 0.0
var _momentum_until := -100.0 ## Overconfident after a kill until this clock.
var bomb_blind := false ## Lost track of the bomb timer this round (thinks there's more time).
var _panic := false ## This fight: spraying instead of controlling.
var _prefire_left := 0
var _glance_pt := Vector2.INF
var _glance_t := 0.0
var _glanced := {} ## Vector2 -> clock last glanced (corner clearing order).
var _edge_key := Vector2.INF
var _edge_pt := Vector2.INF
var _pending_plan := ""
var _no_flash_once := false
var _metric_t := 0.0
var _fake_defuse_t := 0.0 ## Tapping the defuse to bait a peek.
var _fake_defuse_done := false
var _hold_aim := Vector2.INF ## Hold plan: where the contact would appear, on their way to us.
var _hold_route := PackedVector2Array() ## Their likely route to us, sampled, nearest to them first.
var _hold_idx := -1 ## Index on _hold_route of the point we see first from our spot.
var _hold_reload := false ## Stepped back into cover to reload, then back on the angle.
var _hold_t := -100.0 ## Last clock a hold plan was running (kill / death stats).


func _ready() -> void:
	unit.damaged.connect(_on_damaged)
	pers = BotPersonality.for_player(unit.data)
	_holds_open = unit.data.role == "AWPer" or pers.peek_style == "hold" or randf() < unit.data._t("positioning") * 0.2
	_peek_timer = randf_range(1.0, 3.0)


var _death_counted := false
var _fight_from_hold := false ## The current fight started while holding a contact (stats).
var _flash_seen := {} ## Flash ids already reacted to.
var _flash_dodge_t := 0.0 ## Turned away from a flash about to pop.
var _flash_from := Vector2.ZERO


func _physics_process(delta: float) -> void:
	if not unit.alive and not _death_counted:
		_death_counted = true
		if _fight_from_hold or _clock - _hold_t < 0.5:
			stats.hold_deaths += 1
	if not unit.alive or not unit.match_node.can_fight():
		unit.move_input = Vector2.ZERO
		return
	_clock += delta
	_intel_cooldown -= delta
	_record_trail(delta)
	_update_stress(delta)

	var seen := _find_target()
	if seen != _target:
		_fight_from_hold = seen != null and (_clock - _hold_t < 0.3 or (_target != null and _fight_from_hold))
		if seen != null:
			_acquire(seen)
		elif _target != null and is_instance_valid(_target) and _target.alive:
			# Last seen here: we aim at this spot and have to find them again.
			_remember(_target.global_position, _target.health, 1.0, _target)
			_spotted_at = _clock
			_decide()
		_target = seen
	if _target != null:
		_mem_pos = _target.global_position
		_mem_hp = _target.health
		_mem_time = _clock
		_mem_conf = 1.0
		_mem_enemy = _target
	elif unit.match_node.enemies_of(unit.side).is_empty():
		plan = ""
		_evade_timer = 0.0
	else:
		# Out of sight: the ghost fades.
		_mem_conf *= exp(-delta / 7.0)
		_belief_metric(delta)

	# Fake defuse: tap it (they hear it and peek), let go, hold the angle.
	if _fake_defuse_t > 0.0 and unit.action == Unit.Action.DEFUSE:
		_fake_defuse_t -= delta
		if _fake_defuse_t <= 0.0:
			unit.cancel_action()
			var threat: Vector2 = unit.match_node.tactics.intel_near(unit.side, unit.global_position, 900.0)
			if threat != Vector2.INF:
				_remember(threat, 100.0, 0.7, null)
				_set_plan("hold", randf_range(1.0, 1.6))
			return
	# Mid-plant/defuse: keep going unless it's early and someone is on us.
	if unit.action != Unit.Action.NONE:
		if _target != null and unit.action_timer > 1.0:
			unit.cancel_action()
		else:
			return

	if unit.match_node.tactics.is_escaping(unit):
		# Bomb about to blow: run, don't stop to fight.
		plan = ""
		_follow_order(delta)
		if _target != null:
			_aim_at(_target.global_position, 1.0, delta)
	elif _target != null:
		_combat(delta)
	elif _evade_timer > 0.0:
		_evade(delta)
		if _evade_timer <= 0.0:
			_decide()
	elif plan != "":
		_run_plan(delta)
	elif not _fetch_gun(delta):
		_follow_order(delta)
	_watch_flashes(delta)
	if _flash_dodge_t > 0.0:
		# Turn away until it pops (overrides whatever we were looking at).
		_turn_toward((unit.global_position - _flash_from).normalized(), delta, 1.6)
	_quiet = _want_quiet()
	_finalize_move(delta)


## Personal space + unsticking: steer around nearby teammates, and if we've
## been pushing into something without moving, sidestep and re-path.
func _finalize_move(delta: float) -> void:
	var mv := unit.move_input
	if mv != Vector2.ZERO:
		var push := Vector2.ZERO
		for u: Unit in unit.match_node.units:
			if u == unit or not u.alive or u.side != unit.side:
				continue
			var d := unit.global_position - u.global_position
			var l := d.length()
			if l > 0.1 and l < 34.0:
				push += d / l * (34.0 - l) / 34.0
		if push != Vector2.ZERO:
			mv = (mv + push * 0.9).limit_length(1.0)
		# Someone right in front going the same way: let them through first
		# (lower instance id has priority, so two bots never wait on each other).
		if _yield_t < 1.2:
			for u: Unit in unit.match_node.units:
				if u == unit or not u.alive or u.side != unit.side:
					continue
				var rel := u.global_position - unit.global_position
				if rel.length() < 44.0 and rel.normalized().dot(mv.normalized()) > 0.6 \
						and u.get_instance_id() < unit.get_instance_id():
					mv *= 0.15
					_yield_t += delta
					break
		if unit.velocity.length() < unit.top_speed() * 0.2:
			_stuck_t += delta
		else:
			_stuck_t = 0.0
			_yield_t = maxf(0.0, _yield_t - delta * 0.5)
		if _stuck_t > 0.5:
			_stuck_t = 0.0
			_unstick_timer = 0.45
			_unstick_dir = mv.orthogonal() * (1.0 if randf() < 0.5 else -1.0)
			_repath_timer = 0.0
	else:
		_stuck_t = 0.0
	if _unstick_timer > 0.0:
		_unstick_timer -= delta
		mv = (_unstick_dir + mv * 0.3).normalized()
	if _quiet:
		mv = mv.limit_length(WALK_FRAC) # Below running speed: no footsteps.
	# Fire on the ground: get out of it, and wait at the edge instead of walking in.
	for f in unit.match_node.utility.fires:
		var to: Vector2 = unit.global_position - f.pos
		var d := to.length()
		var out := to / d if d > 0.1 else Vector2.RIGHT
		if d < Utility.FIRE_RADIUS + 4.0:
			mv = out
		elif d < Utility.FIRE_RADIUS + 28.0:
			var inward := mv.dot(-out)
			if inward > 0.0:
				mv += out * inward
	unit.move_input = mv


## Human-like crosshair movement: a speed-limited swing (Flick Speed) that
## brakes as it lands. `scale` < 1 for casual looking around.
func _turn_toward(dir: Vector2, delta: float, scale: float = 1.0) -> void:
	if dir == Vector2.ZERO:
		return
	var cur := unit.aim_dir.angle()
	var diff := wrapf(dir.angle() - cur, -PI, PI)
	var max_step := deg_to_rad(unit.data.flick_speed_deg()) * scale * delta
	var braked := absf(diff) * unit.data.flick_settle() * delta
	var step := minf(max_step, maxf(braked, deg_to_rad(25.0) * delta))
	unit.aim_dir = Vector2.from_angle(cur + signf(diff) * minf(step, absf(diff)))

# =============================================================================
# Perception
# =============================================================================

func _find_target() -> Unit:
	var best: Unit = null
	var best_d := INF
	for e: Unit in unit.match_node.enemies_of(unit.side):
		var d := unit.global_position.distance_to(e.global_position)
		if d >= best_d:
			continue
		# Keep tracking someone we're already fighting while they're visible at all
		# (but never from off the human player's screen).
		var ok: bool = unit.match_node.sees(unit, e) or (e == _target and unit.match_node.can_see(unit, e) and unit.match_node.on_users_screen(unit, e))
		if ok:
			best = e
			best_d = d
	return best


func _acquire(enemy: Unit) -> void:
	var fresh := _target == null
	var to_e := enemy.global_position - unit.global_position
	var d := to_e.length()
	var desired := to_e / maxf(d, 0.001)
	var spot := unit.data.reaction_time()
	spot *= lerpf(0.8, 1.4, clampf(d / 1400.0, 0.0, 1.0))
	# Did we actually know someone was there? Checking a corner on a hunch is
	# not the same as holding the spot we heard them in.
	var expected: bool = unit.match_node.tactics.knows_near(unit.side, enemy.global_position, 160.0)
	var pre_aimed := unit.aim_dir.dot(desired) > 0.95
	# Standing still watching an angle = ready for someone to appear there.
	# Walking around checking corners on a hunch is not.
	var anticipating := _holding or (plan == "hold" and unit.velocity.length() < 40.0)
	if pre_aimed:
		# Holder's advantage: crosshair parked on the angle, waiting.
		spot *= (0.68 if anticipating else 0.85) if (expected or anticipating) else 0.97
	elif anticipating:
		spot *= 0.88 # Holding nearby, just not exactly on it.
	elif unit.aim_dir.dot(desired) < unit.data.fov_dot():
		spot *= 1.8 # Only caught it in peripheral vision.
	if fresh and not expected and not anticipating and not Game.ab_flag("no_surprise"):
		spot += randf_range(0.14, 0.3) # Surprise: nobody told us they were here.
	_reaction_left = spot * (1.0 if fresh else 0.5)
	_perceive_left = _reaction_left * 0.6 # Brain first, then hand.
	_burst = 0
	_burst_len = _pick_burst()
	if fresh and anticipating and not Game.ab_flag("old_hold"):
		# They walked into our angle: stand and shoot, don't dance.
		_strafe = 0.0
		_strafe_timer = randf_range(0.5, 0.9)
	# The first flick never lands perfectly; good crosshair placement means less error.
	var flick := deg_to_rad(unit.data.flick_error_deg()) * randf_range(0.5, 1.0)
	flick *= 1.0 - 0.5 * unit.data.preaim_factor() / 0.85
	if pre_aimed:
		flick *= 0.5 if expected else 0.75
	if not fresh:
		flick *= 0.6
	flick *= 1.0 + stress * 0.9
	if randf() < _mistake_p(0.06):
		flick *= 3.0 # Whiffed the flick.
		stats.whiffs += 1
	_aim_err = flick * (1.0 if randf() < 0.5 else -1.0)
	_reaction_left *= 1.0 + stress * 0.2
	_panic = stress > 0.45 and randf() < (stress - 0.35) * mistake_mult
	if _panic:
		stats.panic_sprays += 1
	unit.match_node.report_enemy(unit, enemy)
	_peeking = false
	plan = ""


func _record_trail(delta: float) -> void:
	_trail_timer -= delta
	if _trail_timer <= 0.0:
		_trail_timer = TRAIL_INTERVAL
		_trail.append(unit.global_position)
		if _trail.size() > TRAIL_SIZE:
			_trail.pop_front()


# =============================================================================
# Memory and decisions
# =============================================================================

func _remember(pos: Vector2, hp: float, conf: float, enemy: Unit) -> void:
	_mem_pos = pos
	_mem_hp = hp
	_mem_time = _clock
	_mem_conf = conf
	_mem_enemy = enemy


func _mem_age() -> float:
	return _clock - _mem_time


## How favourable is taking this fight right now? >0 = take it, <0 = play safe.
func _advantage() -> float:
	var m = unit.match_node
	var adv := (unit.health - _mem_hp) / 60.0
	# Numbers: teammates near me vs. enemies we know about near the contact.
	var allies := 0
	for u: Unit in m.units:
		if u.alive and u.side == unit.side and u != unit and u.global_position.distance_to(unit.global_position) < 600.0:
			allies += 1
	var enemies: int = maxi(1, m.tactics.known_enemies_near(unit.side, _mem_pos, 500.0))
	adv += 0.45 * (allies - (enemies - 1))
	# Gear.
	var ammo_frac := float(unit.weapon.ammo) / unit.weapon.mag_size
	if ammo_frac < 0.3:
		adv -= 0.8
	var contact_d := _mem_pos.distance_to(unit.global_position)
	match unit.weapon.cat:
		WeaponData.SNIPER:
			adv -= 0.5 # AWPers let fights come to them.
		WeaponData.PISTOL:
			if unit.primary == null:
				adv -= 0.3
		WeaponData.SHOTGUN:
			# Shotguns want it close: wait for them around a corner, don't swing long.
			adv += 0.5 if contact_d < 260.0 else (-0.9 if contact_d > 420.0 else 0.0)
		WeaponData.SMG:
			# Run-and-gun up close, poor at range.
			adv += 0.35 if contact_d < 380.0 else (-0.4 if contact_d > 750.0 else 0.0)
	# Personality: hotheads take fights, passive players let them come.
	adv += (pers.aggression - 0.5) * 1.5
	var tac: Tactics = m.tactics
	if tac.enemy_eco[unit.side]:
		adv += 0.4 # They've only got pistols: take the fights.
	if tac.side_style[unit.side] == "aggressive":
		adv += 0.2
	elif tac.side_style[unit.side] == "default":
		adv -= 0.1
	# Situation: defenders let attackers come; the side on the clock must act.
	var planted: bool = m.bomb_state == m.Bomb.PLANTED
	var defending := (unit.side == Tactics.CT and not planted) or (unit.side == Tactics.T and planted)
	if defending:
		adv -= 0.5
	if unit.side == Tactics.T and not planted and m.round_time_left < 35.0:
		adv += 0.8
	if unit.side == Tactics.CT and planted:
		adv += 0.6 + (0.6 if bomb_time_seen() < 20.0 else 0.0)
	# Stale info is less worth chasing.
	adv -= _mem_age() * 0.1
	# Trade: a teammate just died to this enemy nearby. Swing them now, while
	# they're reloading / repositioning (good players trade fast).
	if _clock - _trade_at < 2.5 and _mem_pos.distance_to(_trade_pos) < 160.0:
		adv += lerpf(0.5, 1.1, unit.data._t("decision"))
		if unit.side == Tactics.T and not planted:
			adv += 0.3 # Attackers must trade or the execute falls apart.
	# Saving the gun: only fight if it comes to us.
	if m.tactics.is_saving(unit):
		adv -= 2.5
	# Poor decision makers misjudge.
	adv += randf_range(-1.0, 1.0) * (1.0 - unit.data._t("decision")) * 0.9
	return adv


func _decide() -> void:
	if _mem_pos == Vector2.INF or _mem_age() > MEMORY_TTL or _mem_conf < 0.25:
		plan = ""
		return
	_plan_home = unit.global_position
	_plan_stage = 0
	var m = unit.match_node
	var low_ammo := unit.reloading or unit.weapon.ammo < unit.weapon.mag_size * 0.25
	var hurt := unit.health < 30.0 and _clock - _hp_fallback_at > 12.0
	if low_ammo or hurt:
		if hurt:
			_hp_fallback_at = _clock # Once; after that, play on carefully.
		_set_plan("fallback", randf_range(1.0, 1.8))
		return
	if Game.ab_flag("old_decide"):
		var adv0 := _advantage()
		if adv0 > 0.6:
			_set_plan("push" if _mem_hp < 35.0 else "swing", 6.0 if _mem_hp < 35.0 else 2.5)
		elif adv0 > -0.4:
			_set_plan("jiggle", 2.0)
		else:
			_set_plan("hold", lerpf(1.5, 4.0, unit.data._t("positioning")))
		return
	var s := _score_options()
	# Poor decision makers misjudge; everyone has a bit of randomness.
	var noise := (0.15 + (1.0 - unit.data._t("decision")) * 0.6) * (1.0 + stress)
	var best := "hold"
	var best_v := -INF
	for k: String in s:
		var v: float = s[k] + randf_range(-noise, noise)
		if v > best_v:
			best_v = v
			best = k
	var dur := {"hold": lerpf(1.5, 4.5, pers.patience), "jiggle": 2.0, "swing": 2.5, "bait": 3.5,
		"push": 6.0, "reposition": 6.0, "flank": 14.0, "spam": randf_range(1.2, 2.2)}
	_set_plan(best, float(dur[best]) * (1.0 - 0.35 * stress)) # Stressed: hurried.


## How appealing each way of playing this contact is, for this bot, right now.
func _score_options() -> Dictionary:
	var m = unit.match_node
	var adv := _advantage()
	var planted: bool = m.bomb_state == m.Bomb.PLANTED
	var defending := (unit.side == Tactics.CT and not planted) or (unit.side == Tactics.T and planted)
	var on_clock: bool = (unit.side == Tactics.T and not planted and m.round_time_left < 35.0) \
			or (unit.side == Tactics.CT and planted)
	var executing: bool = unit.side == Tactics.T and not planted and m.tactics.t_phase == "execute"
	var dist := _mem_pos.distance_to(unit.global_position)
	var awp := unit.weapon.cat == WeaponData.SNIPER
	var buddy := _teammate_near(320.0)
	var seen_me := _clock - _spotted_at < 3.0 # They know this angle.
	var s := {}
	s["hold"] = 0.3 + pers.patience * 0.9 - adv * 0.45 + (0.9 if defending else 0.0) + (0.6 if awp else 0.0) \
			- (0.9 if on_clock else 0.0) + (0.4 if pers.peek_style == "hold" else 0.0) - (0.5 if seen_me else 0.0)
	s["jiggle"] = 0.45 + (0.45 if pers.peek_style == "jiggle" else 0.0) + (0.35 if _mem_conf < 0.7 else 0.0) \
			- maxf(adv, 0.0) * 0.2 - (0.3 if awp else 0.0)
	s["swing"] = 0.1 + adv * 0.85 + pers.aggression * 0.6 + (0.45 if pers.peek_style == "wide" else 0.0) \
			+ (0.4 if on_clock else 0.0) - (0.6 if awp else 0.0) - (0.3 if seen_me else 0.0) - (0.4 if defending else 0.0)
	s["bait"] = -0.1 + (0.75 if pers.peek_style == "shoulder" else 0.0) + (0.4 if buddy else 0.0) \
			+ pers.discipline * 0.3 - (0.5 if awp else 0.0)
	s["push"] = -0.55 + adv * 0.8 + pers.aggression * 0.7 + (0.9 if _mem_hp < 35.0 else 0.0) \
			+ (0.5 if on_clock else 0.0) - pers.patience * 0.3 + (0.3 if _mem_age() > 2.0 and unit.data.role == "Entry" else 0.0)
	if executing and dist > 550.0:
		s["push"] -= 1.5 # Attackers mid-execute don't chase contacts across the map.
	# Off-angle: they just saw us here, so be somewhere else when they re-peek.
	s["reposition"] = -0.25 + pers.patience * 0.5 + pers.discipline * 0.3 + (0.8 if seen_me else 0.0) \
			- (0.6 if on_clock else 0.0) - (0.7 if defending and not seen_me else 0.0)
	# Flank: patient lurkers go around instead of re-peeking the same door.
	s["flank"] = -0.7 + pers.patience * 0.7 + pers.aggression * 0.3 + (0.6 if unit.data.role == "Lurker" else 0.0) \
			+ (0.4 if not _teammate_near(500.0) else -0.3) - (1.0 if on_clock else 0.0) - (0.8 if executing else 0.0)
	if dist < 300.0 or dist > 1300.0 or awp:
		s["flank"] -= 1.2
	if unit.side == Tactics.CT and not planted and m.tactics.ct_state.get(unit, "hold") == "hold":
		s["flank"] -= 1.0 # Anchors don't leave the site to go hunting.
	if m.tactics.is_saving(unit):
		s["hold"] += 2.0
		s["reposition"] += 1.0
	# Trade window: a teammate just died to this enemy nearby: swing NOW.
	if _clock - _trade_at < 2.5 and _mem_pos.distance_to(_trade_pos) < 160.0:
		s["swing"] += 0.6 + pers.discipline * 0.6
	# Their AWP is on that angle: bait it with jiggles / shoulders, don't wide swing.
	if _mem_is_awp():
		s["bait"] += 0.7
		s["jiggle"] += 0.4
		s["swing"] -= 0.6
		s["push"] -= 0.4
	if pers.has("jiggler"):
		s["jiggle"] += 0.4
	# Overconfident after a kill: re-peek the same fight.
	if _clock < _momentum_until:
		s["swing"] += 0.8
		s["push"] += 0.4
		s["reposition"] -= 0.6
		s["hold"] -= 0.3
	# Stressed: hurried, bad re-peeks.
	s["swing"] += stress * randf() * 0.7
	# Post-plant "play for picks": the Ts hunt instead of sitting on the bomb.
	if unit.side == Tactics.T and planted and m.tactics.t_post_mode == "picks":
		s["hold"] -= 0.6
		s["swing"] += 0.4
		s["push"] += 0.2
	# They're behind a smoke we have a straight line through: spray it (bullets
	# go through and punch holes in it), especially when they're pushing out of it.
	if m.utility != null and not m.utility.smokes.is_empty() and unit.weapon.automatic and not awp 			and unit.weapon.ammo > unit.weapon.mag_size * 0.4 and _mem_age() < 4.0 and dist < 900.0 			and m.has_wall_los(unit.global_position, _mem_pos) and m.utility.blocks(unit.global_position, _mem_pos):
		s["spam"] = 0.35 + pers.aggression * 0.5 + (0.5 if _mem_age() < 1.5 else 0.0) + (0.35 if dist < 500.0 else 0.0) 				- (1.5 if m.tactics.is_saving(unit) else 0.0)
		s["swing"] -= 0.5 # Peeking into a smoke is pointless.
		s["jiggle"] -= 0.4
	# Habit: takes an early peek most rounds.
	if pers.has("early_peek") and m.round_clock < 25.0:
		s["swing"] += 0.5
		s["push"] += 0.2
		s["hold"] -= 0.3
	return s


## T side, bomb not down, clock nearly out: no time for anything but the site.
func _late_t() -> bool:
	var m = unit.match_node
	return unit.side == Tactics.T and m.bomb_state != m.Bomb.PLANTED and m.round_time_left < 30.0 * m.arena.tempo \
			and not m.tactics.is_saving(unit)


func _teammate_near(r: float) -> bool:
	for u: Unit in unit.match_node.units:
		if u != unit and u.alive and u.side == unit.side and u.global_position.distance_to(unit.global_position) < r:
			return true
	return false


## Can this bot be asked to cover someone right now?
func can_cover() -> bool:
	return unit.alive and _target == null and plan == "" and unit.action == Unit.Action.NONE and not unit.reloading


## Step up and hold `threat` while a teammate reloads.
func cover(threat: Vector2, duration: float) -> void:
	_remember(threat, 100.0, 0.8, null)
	plan = "cover"
	_plan_timer = duration
	_plan_spot = _find_peek_point(threat, 3)
	if _plan_spot == Vector2.INF:
		_plan_spot = unit.global_position


static var plan_counts := {} ## Dev stats: how often each plan gets picked.


func _set_plan(p: String, duration: float) -> void:
	plan_counts[p] = int(plan_counts.get(p, 0)) + 1
	plan = p
	_plan_timer = duration
	_plan_spot = Vector2.INF
	_plan_stage = 0
	match p:
		"swing", "jiggle", "bait":
			var radius := 2
			if p == "swing":
				radius = 4 if pers.peek_style == "wide" else 3
			_plan_spot = _find_peek_point(_mem_pos, radius)
			if _plan_spot == Vector2.INF:
				# No angle on it from here.
				if p == "swing":
					plan = "push"
					_plan_timer = 6.0
				else:
					plan = "hold"
					_plan_timer = 2.0
		"reposition":
			_plan_spot = _find_reposition()
			if _plan_spot == Vector2.INF:
				plan = "hold"
				_plan_timer = 2.0
		"flank":
			_plan_spot = _find_flank_point()
			if _plan_spot == Vector2.INF:
				_set_plan("reposition", 6.0)
	if plan == "hold" and not Game.ab_flag("old_hold"):
		_plan_hold()
	if plan == "swing":
		# Prefire where we expect them (aggressive players, the "prefire" habit).
		_prefire_left = 0
		var pc := 0.1 + 0.3 * pers.aggression + (0.4 if pers.has("prefire") else 0.0)
		if unit.weapon.automatic and _mem_conf > 0.5 and _mem_age() < 3.0 and randf() < pc:
			_prefire_left = randi_range(2, 4)
	if plan in ["swing", "push"] and not _no_flash_once and _mem_conf > 0.45 and _mem_age() < 4.0:
		if _try_peek_flash():
			_pending_plan = plan
			plan = "flashwait"
			_plan_timer = 1.15 # The flash pops (1.3s fuse) as we swing.
	_no_flash_once = false


func _run_plan(delta: float) -> void:
	_plan_timer -= delta
	# Attackers on the clock can't sit in plans forever: after a while, get
	# back to the hit and ignore stale noise for a few seconds.
	_plan_total += delta
	var m = unit.match_node
	var attacking: bool = unit.side == Tactics.T and m.bomb_state != m.Bomb.PLANTED and m.tactics.t_phase == "execute"
	var limit := 5.0 if attacking else lerpf(7.0, 15.0, pers.patience)
	if plan == "flank":
		limit += 10.0
	# Urgent jobs (picking up the bomb, the clock running out on the Ts) cut
	# side-fights short.
	var act: String = m.objective_for(unit).get("action", "")
	var urgent: bool = act == "fetch" or _late_t()
	if urgent:
		limit = minf(limit, 2.5)
	var stale: bool = _mem_age() > 2.0 or urgent or _plan_total > limit * 1.8
	if _plan_total > limit and stale and plan in ["hold", "jiggle", "fallback", "push", "swing", "bait", "reposition", "flank"] and not unit.reloading:
		# Nothing's come of it: drop the contact, get back to the team plan and
		# don't re-react to the same stale noise for a while.
		plan = ""
		_plan_total = 0.0
		_intel_cooldown = 6.0
		_mem_conf = 0.0
		return
	# Crosshair stays where we last saw / heard them: if they've moved, we
	# have to find them and flick, like anyone else.
	if plan == "flank" and unit.global_position.distance_to(_mem_pos) > 520.0 and unit.velocity.length() > 10.0:
		_aim_at(unit.global_position + unit.velocity, 9.0, delta) # Walking the long way round.
	elif plan == "hold" and _hold_aim != Vector2.INF:
		# On the edge they'd come round, not on the wall in front of where they were.
		_aim_at(_edge_aim(unit.global_position, _hold_aim) if _hold_idx > 0 else _hold_aim, 9.0, delta)
	else:
		_aim_at(_mem_pos, 9.0, delta)
	match plan:
		"hold" when not Game.ab_flag("old_hold"):
			_run_hold(delta)
		"hold":
			if unit.reloading:
				_retreat_from(_mem_pos)
			elif not m.has_line_of_sight(unit.global_position, _mem_pos) and not fully_hidden(unit.global_position, _mem_pos):
				# Half in, half out (a shoulder showing but we can't see them):
				# commit to cover instead of standing there.
				var c := _cover_from(_mem_pos)
				if c != Vector2.INF:
					_move_to(c, 2.5)
				else:
					unit.move_input = Vector2.ZERO
			else:
				unit.move_input = Vector2.ZERO
				if unit.weapon.ammo < unit.weapon.mag_size * 0.5:
					unit.start_reload()
				elif not unit.reloading and unit.weapon.ammo < unit.weapon.mag_size * 0.85 \
						and randf() < _mistake_p(BAD_RELOAD_RATE) * delta:
					unit.start_reload() # Reloading right on a live angle.
					stats.bad_reloads += 1
			if _plan_timer <= 0.0:
				_mem_time -= 1.5 # Holding without contact makes the info feel older.
				_mem_conf *= 0.6
				_decide()
		"fallback":
			_retreat_from(_mem_pos)
			# Reload once out of their sight (or straight away if nearly dry).
			if not unit.reloading and unit.weapon.ammo < unit.weapon.mag_size 					and (fully_hidden(unit.global_position, _mem_pos) or unit.weapon.ammo < unit.weapon.mag_size * 0.15):
				unit.start_reload()
			if _plan_timer <= 0.0 and not unit.reloading:
				_set_plan("hold", randf_range(1.5, 3.0))
		"jiggle":
			# Stage 0: step out. Stage 1: step back. Then rethink.
			if _plan_stage == 0:
				if _move_to(_plan_spot, 6.0):
					_plan_stage = 1
					_plan_timer = randf_range(0.15, 0.35) # Brief look.
			elif _plan_stage == 1:
				unit.move_input = Vector2.ZERO
				if _plan_timer <= 0.0:
					_plan_stage = 2
			else:
				if _move_to(_plan_home, 6.0):
					_mem_conf *= 0.5 # Peeked, saw nothing: they've probably moved.
					_mem_time -= 1.0
					_decide()
		"flashwait":
			# Hidden, crosshair on the spot, waiting for the flash to pop.
			unit.move_input = Vector2.ZERO
			if _plan_timer <= 0.0:
				_no_flash_once = true
				_set_plan(_pending_plan if _pending_plan != "" else "swing", 2.5)
		"swing":
			if _plan_stage == 0:
				if _move_to(_plan_spot, 6.0) or _plan_timer <= 0.0:
					_plan_stage = 1
					_plan_timer = randf_range(0.4, 0.8)
			else:
				unit.move_input = Vector2.ZERO
				if _prefire_left > 0 and unit.aim_dir.dot((_mem_pos - unit.global_position).normalized()) > 0.97 \
						and m.has_line_of_sight(unit.global_position, _mem_pos):
					if unit.try_fire():
						_prefire_left -= 1
						if _prefire_left == 0:
							stats.prefires += 1
				if _plan_timer <= 0.0:
					_mem_conf *= 0.45
					_decide()
		"bait":
			# Shoulder-peek to draw a shot, duck back, then swing for real.
			match _plan_stage:
				0:
					_move_to(_plan_spot, 6.0)
					_plan_wait += delta
					if _plan_wait > randf_range(0.12, 0.2):
						_plan_wait = 0.0
						_plan_stage = 1
				1:
					if _move_to(_plan_home, 6.0):
						_plan_stage = 2
						_plan_wait = randf_range(0.25, 0.6)
				_:
					unit.move_input = Vector2.ZERO
					_plan_wait -= delta
					if _plan_wait <= 0.0:
						_plan_wait = 0.0
						_set_plan("swing", 2.5)
		"reposition":
			# Off-angle: quietly move somewhere they won't pre-aim, then hold it.
			if _plan_stage == 0:
				_walk_path_to(_plan_spot, delta)
				if unit.global_position.distance_to(_plan_spot) < 14.0 or _plan_timer <= 0.0:
					_plan_stage = 1
					_plan_timer = lerpf(1.5, 3.5, pers.patience)
			else:
				unit.move_input = Vector2.ZERO
				if _plan_timer <= 0.0:
					_mem_time -= 1.0
					_decide()
		"flank":
			if _plan_stage == 0:
				_walk_path_to(_plan_spot, delta)
				if unit.global_position.distance_to(_plan_spot) < 18.0:
					_plan_stage = 1
					_plan_timer = randf_range(0.8, 1.8) # Settle, then hit them from the side.
				elif _plan_timer <= 0.0:
					plan = ""
			else:
				unit.move_input = Vector2.ZERO
				if _plan_timer <= 0.0:
					_set_plan("swing", 2.5)
		"cover":
			_move_to(_plan_spot, 6.0)
			if _plan_timer <= 0.0:
				plan = ""
		"spam":
			# Controlled bursts into the cloud, sweeping a little around the spot.
			unit.move_input = Vector2.ZERO
			var sweep := _mem_pos + Vector2.from_angle(_clock * 2.3).orthogonal() * sin(_clock * 3.1) * 30.0
			_aim_at(sweep, 9.0, delta)
			var to_s := (sweep - unit.global_position).normalized()
			if unit.aim_dir.dot(to_s) > 0.985 and unit.bloom < lerpf(7.0, 3.5, unit.data._t("recoil")):
				unit.try_fire()
			if _plan_timer <= 0.0 or unit.weapon.ammo < unit.weapon.mag_size * 0.25 or not m.utility.blocks(unit.global_position, _mem_pos):
				_mem_conf *= 0.7
				_decide()
		"push":
			_walk_path_to(_mem_pos, delta)
			if unit.global_position.distance_to(_mem_pos) < 40.0 or _plan_timer <= 0.0:
				_mem_conf = 0.0 # Cleared the spot.
				plan = ""
		_:
			plan = ""


## A nearby spot we can step to in a straight line that has eyes on `target`.
func _find_peek_point(target: Vector2, radius: int) -> Vector2:
	var m = unit.match_node
	var a: Arena = m.arena
	var center := a.world_to_cell(unit.global_position)
	var best := Vector2.INF
	var best_d := INF
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var c := center + Vector2i(dx, dy)
			if a.is_solid(c):
				continue
			var p := a.cell_center(c)
			var d := p.distance_to(unit.global_position)
			if d >= best_d or not m.has_line_of_sight(unit.global_position, p):
				continue
			if m.has_line_of_sight(p, target):
				best = p
				best_d = d
	return best


## A different spot nearby that still sees the contact but from a new angle
## (so a re-peek on our old position finds nobody there).
func _find_reposition() -> Vector2:
	var m = unit.match_node
	var a: Arena = m.arena
	var center := a.world_to_cell(unit.global_position)
	var old_dir := (unit.global_position - _mem_pos).normalized()
	var best := Vector2.INF
	var best_score := 0.0
	# Defenders shuffle along their position; they don't wander off it.
	var planted: bool = m.bomb_state == m.Bomb.PLANTED
	var defending := (unit.side == Tactics.CT and not planted) or (unit.side == Tactics.T and planted)
	var max_d := 210.0 if defending else 330.0
	for dy in range(-6, 7):
		for dx in range(-6, 7):
			var c := center + Vector2i(dx, dy)
			if a.is_solid(c):
				continue
			var p := a.cell_center(c)
			var d := p.distance_to(unit.global_position)
			if d < 110.0 or d > max_d:
				continue
			var new_dir := (p - _mem_pos).normalized()
			var turn := absf(old_dir.angle_to(new_dir))
			if turn < deg_to_rad(12.0):
				continue
			var score := turn - d / 1200.0 + randf() * 0.15
			if score <= best_score or not m.has_line_of_sight(p, _mem_pos):
				continue
			best = p
			best_score = score
	if best != Vector2.INF:
		var path := a.find_path(unit.global_position, best)
		if path.size() < 2 or _path_len(path) > best.distance_to(unit.global_position) * 2.5 + 80.0:
			return Vector2.INF
	return best


## A spot beside the contact, reached by a different way in than the one
## we're looking down (so we hit them from the side).
func _find_flank_point() -> Vector2:
	var m = unit.match_node
	var a: Arena = m.arena
	var mine := (unit.global_position - _mem_pos).normalized()
	var direct := unit.global_position.distance_to(_mem_pos)
	var best := Vector2.INF
	var best_turn := deg_to_rad(70.0)
	for k in 12:
		var dir := Vector2.from_angle(k * TAU / 12.0)
		var c := a.nearest_open(a.world_to_cell(_mem_pos + dir * 260.0))
		var p := a.cell_center(c)
		var turn := absf(mine.angle_to((p - _mem_pos).normalized()))
		if turn <= best_turn or not m.has_line_of_sight(p, _mem_pos):
			continue
		var path := a.find_path(unit.global_position, p)
		if path.size() < 2 or _path_len(path) > direct * 2.2 + 500.0:
			continue
		# The way there must not just walk through them.
		var through := false
		for q in path:
			if q.distance_to(_mem_pos) < 200.0:
				through = true
				break
		if through:
			continue
		best = p
		best_turn = turn
	return best


# =============================================================================
# Holding a contact
# =============================================================================

const ROUTE_STEP := 28.0 ## Spacing of the samples along an enemy's likely route.


## The way an enemy at `from` would walk to `to`: the A* path, sampled every
## ROUTE_STEP px, nearest to them first, cut after ~900 px.
func _approach_route(from: Vector2, to: Vector2) -> PackedVector2Array:
	var path: PackedVector2Array = unit.match_node.arena.find_path(from, to)
	var out := PackedVector2Array([from])
	var walked := 0.0
	for i in range(1, path.size()):
		var a := path[i - 1]
		var b := path[i]
		var seg := a.distance_to(b)
		var n := maxi(1, ceili(seg / ROUTE_STEP))
		for k in range(1, n + 1):
			out.append(a.lerp(b, float(k) / n))
		walked += seg
		if walked > 900.0:
			break
	return out


## First point of `route` (from the enemy's end) that `p` can see, or -1.
func _first_visible(p: Vector2, route: PackedVector2Array) -> int:
	var m = unit.match_node
	# Coarse pass every other sample, then step back one to find the edge.
	var i := 0
	while i < route.size():
		if m.has_line_of_sight(p, route[i]):
			if i > 0 and m.has_line_of_sight(p, route[i - 1]):
				return i - 1
			return i
		i += 2
	if route.size() % 2 == 0 and m.has_line_of_sight(p, route[route.size() - 1]):
		return route.size() - 1
	return -1


## Comfortable distance (px) to the point an enemy appears, by weapon:
## rifles and AWPs back off for reaction time, shotguns sit tight on the corner.
func _hold_range() -> Vector2:
	match unit.weapon.cat:
		WeaponData.SNIPER:
			return Vector2(380.0, 950.0)
		WeaponData.SHOTGUN:
			return Vector2(60.0, 220.0)
		WeaponData.SMG, WeaponData.PISTOL:
			return Vector2(130.0, 420.0)
	return Vector2(200.0, 620.0)


## A cell one step from `p` fully hidden from `threat` (to reload / fall back into).
func _cover_step(p: Vector2, threat: Vector2) -> Vector2:
	var m = unit.match_node
	var a: Arena = m.arena
	var c0 := a.world_to_cell(p)
	var best := Vector2.INF
	var best_d := INF
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var c := c0 + Vector2i(dx, dy)
			if (dx == 0 and dy == 0) or a.is_solid(c):
				continue
			var q := a.cell_center(c)
			var d := q.distance_to(p)
			if d < best_d and m.has_line_of_sight(p, q) and fully_hidden(q, threat):
				best = q
				best_d = d
	return best


## Chooses where to hold a contact from and where to aim (sets _plan_spot,
## _hold_aim) and stretches the plan to roughly when they could arrive.
func _plan_hold() -> void:
	var m = unit.match_node
	var a: Arena = m.arena
	var me := unit.global_position
	stats.holds += 1
	_hold_reload = false
	_hold_route = _approach_route(_mem_pos, me)
	var planted: bool = m.bomb_state == m.Bomb.PLANTED
	var defending := (unit.side == Tactics.CT and not planted) or (unit.side == Tactics.T and planted)
	var radius := 4 if defending else 5
	# On the bomb (fake defuse, guarding it): stay on it, just aim right.
	if planted and me.distance_to(m.bomb_pos) < 80.0:
		radius = 0
	if m.tactics.is_saving(unit):
		radius = 2
	var rng_ok := _hold_range()
	var seen_me := _clock - _spotted_at < 3.0
	var mates: Array[Unit] = []
	for u: Unit in m.units:
		if u != unit and u.alive and u.side == unit.side and u.global_position.distance_to(me) < 700.0:
			mates.append(u)
	var center := a.world_to_cell(me)
	var cands: Array = [] # [score, spot, route index]
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var c := center + Vector2i(dx, dy)
			if a.is_solid(c):
				continue
			var p := a.cell_center(c) if (dx != 0 or dy != 0) else me
			var d_me := p.distance_to(me)
			if d_me > radius * 32.0 + 8.0:
				continue
			# Further out, every other cell is plenty (keeps the search cheap).
			if maxi(absi(dx), absi(dy)) > 2 and (dx + dy) % 2 != 0:
				continue
			# Somewhere we can step to in a straight line, and not inside a smoke (blind there).
			if d_me > 24.0 and not m.has_line_of_sight(me, p):
				continue
			if m.utility != null and m.utility.in_smoke(p, 10.0):
				continue
			var i := _first_visible(p, _hold_route)
			if i < 0:
				continue # Can't see any of the way they'd come.
			var app := _hold_route[i]
			var d_app := p.distance_to(app)
			var s := 0.0
			# Range for the gun.
			if d_app < rng_ok.x:
				s -= (rng_ok.x - d_app) / 90.0
			elif d_app > rng_ok.y:
				s -= (d_app - rng_ok.y) / 220.0
			# Hidden from where they are now: they can't pre-aim or wide-swing onto
			# us, they have to walk into our crosshair. A straight standoff with a
			# spot they may be holding themselves is worse.
			if i > 0 and fully_hidden(p, _mem_pos):
				s += 0.7
			elif i == 0:
				s -= 0.35
			# Off-angle: they'll come round pre-aimed at where they last saw us, so
			# be outside that cone (seen from where they appear) and not straight
			# down the line they walk in.
			if d_app > 1.0:
				var cone := absf((me - app).angle_to(p - app))
				s += clampf((cone - deg_to_rad(6.0)) / deg_to_rad(16.0), 0.0, 1.0) * (0.6 + 0.5 * pers.discipline)
				var nxt := _hold_route[mini(i + 1, _hold_route.size() - 1)]
				var prv := _hold_route[maxi(i - 1, 0)]
				var walk_dir := (nxt - prv).normalized()
				if walk_dir != Vector2.ZERO:
					var off := absf(walk_dir.angle_to((p - app) / d_app))
					var side_on := 1.0 - absf(off - deg_to_rad(115.0)) / deg_to_rad(115.0)
					s += clampf(side_on, 0.0, 1.0) * 0.2
			# They just saw us here: they'll pre-aim it.
			if seen_me and p.distance_to(me) < 48.0:
				s -= 0.8
			# Walking over must not cross their view.
			if d_me > 24.0 and m.has_line_of_sight(_mem_pos, me.lerp(p, 0.5)) and not m.has_line_of_sight(_mem_pos, me):
				s -= 0.9
			# Teammates: not on top of each other; a crossfire on the same entry is good.
			for u in mates:
				if u.global_position.distance_to(p) < 34.0:
					s -= 2.0
				var bc: BotController = null
				for ch in u.get_children():
					if ch is BotController:
						bc = ch
				if bc != null and bc.plan == "hold" and bc._hold_aim != Vector2.INF and bc._hold_aim.distance_to(app) < 140.0:
					var ang := absf((u.global_position - app).angle_to(p - app))
					s += 0.45 if ang > deg_to_rad(35.0) else -0.6
			# Don't wander off: defenders keep to their post.
			s -= d_me / (200.0 if defending else 320.0)
			s += randf() * 0.12 * (1.0 + (1.0 - unit.data._t("positioning")) * 2.0)
			cands.append([s, p, i])
	if cands.is_empty():
		# Nothing on this side sees their way in: hold from here on the last spot.
		_plan_spot = me
		_hold_aim = _mem_pos
		_hold_idx = 0
		return
	cands.sort_custom(func(x: Array, y: Array) -> bool: return x[0] > y[0])
	# Cover a step away (to reload / fall back into) is checked for the best few only.
	var best: Array = cands[0]
	var best_s := -INF
	for k in mini(5, cands.size()):
		var cd: Array = cands[k]
		var sc: float = cd[0]
		if _cover_step(cd[1], _hold_route[cd[2]]) != Vector2.INF:
			sc += 0.5
		if sc > best_s:
			best_s = sc
			best = cd
	_plan_spot = best[1]
	_hold_idx = best[2]
	_hold_aim = _hold_route[_hold_idx]
	if _plan_spot.distance_to(me) > 24.0:
		stats.hold_moves += 1
	_plan_stage = 0 if _plan_spot.distance_to(me) > 6.0 else 1
	# Wait about as long as they'd take to walk into view, plus patience.
	var arrive := float(_hold_idx) * ROUTE_STEP / maxf(unit.top_speed(), 1.0)
	_plan_timer = clampf(_plan_timer + arrive * lerpf(0.6, 1.1, pers.patience), 1.5, 10.0)


## Runs the hold plan: get to the spot, stand still on the angle, reload in cover.
func _run_hold(delta: float) -> void:
	var m = unit.match_node
	_hold_t = _clock
	var app := _hold_aim if _hold_aim != Vector2.INF else _mem_pos
	var mag := float(unit.weapon.mag_size)
	var arrive_left := float(_hold_idx) * ROUTE_STEP / maxf(unit.top_speed(), 1.0) - _mem_age()
	var imminent := _mem_conf > 0.4 and arrive_left < 1.5
	if _hold_reload:
		# Stepped back to reload: out of sight of the angle until it's done.
		var c := _cover_step(_plan_spot, app)
		if c != Vector2.INF:
			_move_to(c, 3.0)
		else:
			_retreat_from(app)
		if not unit.reloading:
			if unit.weapon.ammo < unit.weapon.mag_size:
				unit.start_reload()
			else:
				_hold_reload = false
				_plan_stage = 0 # Back on the angle.
	elif _plan_stage == 0:
		if _move_to(_plan_spot, 5.0):
			_plan_stage = 1
	else:
		unit.move_input = Vector2.ZERO
		var low := unit.weapon.ammo < mag * 0.5
		if unit.reloading or (low and not imminent) or unit.weapon.ammo < mag * 0.2:
			# Don't reload on a live angle: a step back into cover first.
			if not unit.reloading:
				unit.start_reload()
			if _cover_step(_plan_spot, app) != Vector2.INF:
				_hold_reload = true
				stats.hold_cover_reloads += 1
		elif not unit.reloading and unit.weapon.ammo < mag * 0.7 and randf() < _mistake_p(BAD_RELOAD_RATE) * delta:
			unit.start_reload() # Reloading right on a live angle.
			stats.bad_reloads += 1
	if _plan_timer <= 0.0 and not unit.reloading:
		_mem_time -= 1.5 # Holding without contact makes the info feel older.
		_mem_conf *= 0.6
		_decide()


## Heard them again while holding: if it's the same way in, keep the spot
## (aim follows, wait longer) instead of re-deciding everything.
func _hold_update(pos: Vector2, conf: float) -> bool:
	if plan != "hold" or Game.ab_flag("old_hold") or _plan_spot == Vector2.INF:
		return false
	var route := _approach_route(pos, _plan_spot)
	var i := _first_visible(_plan_spot, route)
	if i < 0 or (i > 0 and route[i].distance_to(_hold_aim) > 120.0):
		return false
	_remember(pos, 100.0, maxf(conf, _mem_conf), null)
	_hold_route = route
	_hold_idx = i
	_hold_aim = route[i]
	var arrive := float(i) * ROUTE_STEP / maxf(unit.top_speed(), 1.0)
	_plan_timer = clampf(maxf(_plan_timer, arrive + lerpf(1.0, 2.5, pers.patience)), 0.0, 10.0)
	stats.hold_extends += 1
	return true


func _path_len(path: PackedVector2Array) -> float:
	var d := 0.0
	for i in range(1, path.size()):
		d += path[i - 1].distance_to(path[i])
	return d


## Walk instead of run (no footsteps) when sneaking makes sense for this bot.
func _want_quiet() -> bool:
	if Game.ab_flag("no_quiet"):
		return false
	if _target != null or unit.reloading and _target != null:
		return false
	var m = unit.match_node
	var t: Tactics = m.tactics
	if t.is_escaping(unit) or t.is_saving(unit) or t.hunting:
		return false
	var planted: bool = m.bomb_state == m.Bomb.PLANTED
	# On the clock: no time to sneak.
	if unit.side == Tactics.T and not planted and m.round_time_left < 30.0 * m.arena.tempo:
		return false
	if unit.side == Tactics.CT and planted and bomb_time_seen() < 22.0:
		return false
	if plan in ["reposition", "flank", "bait", "jiggle"]:
		return pers.discipline > 0.3
	if plan in ["swing", "push", "fallback"]:
		return false
	if pers.has("silent") and not (unit.side == Tactics.T and t.t_phase == "execute" and not planted):
		return true # Habit: walks almost everywhere.
	if unit.side == Tactics.T and t.t_route.get(unit, "") == "lurk":
		return true
	if unit.side == Tactics.T and t.t_phase == "execute" and not planted:
		return false # The hit is fast and loud.
	# Close to where we think they are: sneak (disciplined / patient players).
	if t.intel_near(unit.side, unit.global_position, 650.0) != Vector2.INF:
		return pers.discipline + pers.patience * 0.5 > 0.62
	# Ts creeping up to their staging point.
	if unit.side == Tactics.T and t.t_phase == "approach":
		var r: String = t.t_route.get(unit, "")
		if r != "" and m.arena.routes.has(r):
			return unit.global_position.distance_to(m.arena.pt(m.arena.routes[r].stage)) < 380.0 and pers.patience > 0.4
	return false


func _move_to(p: Vector2, tolerance: float) -> bool:
	var to := p - unit.global_position
	if to.length() <= tolerance:
		unit.move_input = Vector2.ZERO
		return true
	unit.move_input = to.normalized()
	return false


func _walk_path_to(goal: Vector2, delta: float) -> void:
	_repath_timer -= delta
	if _repath_timer <= 0.0:
		_repath_timer = 1.0
		_path = unit.match_node.arena.find_path(unit.global_position, goal)
		_path_idx = 1
	if _path_idx < _path.size():
		var wp := _path[_path_idx]
		if unit.global_position.distance_to(wp) < 10.0:
			_path_idx += 1
		unit.move_input = (wp - unit.global_position).normalized()
	else:
		unit.move_input = (goal - unit.global_position).normalized()


func _aim_at(p: Vector2, _speed: float, delta: float) -> void:
	var look := p - unit.global_position
	if look.length() > 1.0:
		_turn_toward(look.normalized(), delta, 0.7)


# =============================================================================
# Combat
# =============================================================================

func _combat(delta: float) -> void:
	unit.match_node.report_enemy(unit, _target)
	_manage_weapon_in_fight()

	var to_t := _target.global_position - unit.global_position
	var dist := to_t.length()
	var desired := to_t / maxf(dist, 0.001)
	# Aim at the exposed part of them, but where they were a moment ago (tracking lag).
	var lagged := _target.global_position - _target.velocity * unit.data.tracking_lag()
	var origin := unit.global_position
	var aim_point := lagged
	var line: Array = unit.match_node.sight_line(unit, _target)
	if not line.is_empty():
		origin = line[0]
		aim_point = lagged + (line[1] - _target.global_position)
	if aim_point.distance_to(origin) > 1.0:
		desired = (aim_point - origin).normalized()
	# Human error: the flick settles over time; the hand always wobbles a bit.
	_aim_err *= exp(-unit.data.settle_rate() * delta)
	_jitter_timer -= delta
	if _jitter_timer <= 0.0:
		_jitter_timer = 0.12
		_jitter_target = randfn(0.0, deg_to_rad(unit.data.aim_jitter_deg()) * (1.0 + stress * 0.8))
	_jitter = lerpf(_jitter, _jitter_target, clampf(10.0 * delta, 0.0, 1.0))
	var intended := desired.rotated(_aim_err + _jitter)
	_perceive_left -= delta
	if _perceive_left <= 0.0:
		_turn_toward(intended, delta)

	_duck_timer -= delta
	if unit.reloading or _duck_timer > 0.0:
		_retreat_from(_target.global_position)
		return

	_reaction_left -= delta
	var on_target := unit.aim_dir.dot(intended) > 0.99
	var ready := _reaction_left <= 0.0 and on_target
	var heavy := unit.weapon.moving_inaccuracy >= 8.0
	# Scoped guns: stop and scope in before the shot (no unscoped no-scopes).
	var stopping := ready and heavy and (_counter_strafe or unit.weapon.scope)
	var scoped_ok := not unit.weapon.scope or unit.scope_t > 0.9
	if ready and scoped_ok and not (stopping and unit.is_moving()):
		var reset_bloom := lerpf(9.0, 3.0, unit.data._t("recoil"))
		if _panic:
			reset_bloom = 99.0 # Panic: hold the trigger down.
		if unit.bloom < reset_bloom or not unit.weapon.automatic:
			if unit.try_fire():
				_burst += 1
				if unit.weapon.cat == WeaponData.SNIPER:
					_duck_timer = randf_range(0.5, 0.9) # Peek, shoot, un-peek.
				elif _burst >= _burst_len and _target.health > 25.0 and not _panic \
						and randf() < lerpf(0.2, 0.85, unit.data._t("positioning")) \
						and _cover_from(_target.global_position) != Vector2.INF:
					# Don't stand in the open trading: duck, then decide how to re-peek.
					_duck_timer = randf_range(0.35, 0.7)
					_burst = 0
					_burst_len = _pick_burst()
				elif _burst >= _burst_len and not unit.weapon.scope:
					# No cover: shift sideways between bursts instead of standing still.
					_burst = 0
					_burst_len = _pick_burst()
					_strafe = -_strafe if _strafe != 0.0 else (1.0 if randf() < 0.5 else -1.0)
					_strafe_timer = randf_range(0.25, 0.45)

	_strafe_timer -= delta
	if _strafe_timer <= 0.0:
		_strafe_timer = randf_range(0.3, 0.9)
		if randf() < unit.data.hold_chance() or unit.weapon.scope or (_holding and _holds_open):
			_strafe = 0.0
		else:
			_strafe = 1.0 if randf() < 0.5 else -1.0
		_counter_strafe = randf() < lerpf(0.3, 0.95, unit.data._t("movement"))
	var perp := Vector2(-desired.y, desired.x) * _strafe
	var radial := 0.0
	var ideal := unit.weapon.ideal_range
	if dist > ideal * 1.3 and not _holding:
		radial = 0.8
	elif dist < ideal * 0.5:
		radial = -0.5
	if stopping:
		unit.move_input = Vector2.ZERO
	else:
		unit.move_input = (perp * 0.8 + desired * radial).limit_length(1.0)
	_repath_timer = 0.0


## Mid-fight: switch to the pistol when that's quicker than reloading with
## someone on us (DRAW_TIME vs. the reload left), don't swap back mid-duel,
## AWPers pull the pistol when rushed up close, knife only as a last resort.
func _manage_weapon_in_fight() -> void:
	if unit.is_drawing():
		return
	var dist := unit.global_position.distance_to(_target.global_position) if _target != null else INF
	var close := dist < 420.0
	var reload_left := unit.reload_timer if unit.reloading else unit.weapon.reload_time
	if unit.knife_out:
		if dist > 70.0 and (unit.pistol.ammo > 0 or (unit.primary != null and unit.primary.ammo > 0)):
			if unit.primary != null and unit.primary.ammo > 0:
				unit.select_primary()
			else:
				unit.select_pistol()
		return
	if unit.weapon == unit.primary:
		var dry := unit.weapon.ammo == 0
		var low := unit.weapon.ammo <= maxi(2, int(unit.weapon.mag_size * 0.12))
		var rushed := unit.weapon.scope and dist < 260.0 and unit.weapon.ammo < unit.weapon.mag_size
		var swap_wins := reload_left > Unit.DRAW_TIME + 0.6
		if _pistol_ready() and swap_wins and (dry or rushed or (unit.reloading and close) or (low and close and _target.health > 40.0)):
			unit.select_pistol()
			stats.pistol_swaps += 1
			return
	elif unit.weapon == unit.pistol and unit.pistol.ammo == 0 and unit.primary != null and unit.primary.ammo > 0 and not close:
		unit.select_primary()
		return
	if unit.weapon.ammo == 0:
		if unit.pistol.ammo == 0 and (unit.primary == null or unit.primary.ammo == 0) and dist < 90.0:
			unit.select_knife() # Nothing left and they're on top of us.
		else:
			unit.start_reload()


func _pistol_ready() -> bool:
	return unit.pistol != null and unit.pistol.ammo > 0 and unit.weapon != unit.pistol


## The enemy we'd be exposed to while reloading: something we know about
## (seen, heard or called) close enough to matter, or INF if it's quiet.
func reload_threat() -> Vector2:
	var m = unit.match_node
	if _target != null:
		return _target.global_position
	if _mem_pos != Vector2.INF and _mem_age() < 5.0 and _mem_conf > 0.3 and _mem_pos.distance_to(unit.global_position) < 1100.0:
		return _mem_pos
	return m.tactics.intel_near(unit.side, unit.global_position, 900.0)


## Back off into our cover spot or along our recent trail, out of the threat's sight.
func _retreat_from(threat: Vector2) -> void:
	var m = unit.match_node
	var cover := _cover_from(threat)
	if cover != Vector2.INF:
		_move_to(cover, 4.0)
		return
	if _cover_spot != Vector2.INF and unit.global_position.distance_to(_cover_spot) < 120.0 \
			and not m.has_line_of_sight(threat, _cover_spot):
		_move_to(_cover_spot, 6.0)
		return
	for i in range(_trail.size() - 1, -1, -1):
		var p := _trail[i]
		if p.distance_to(unit.global_position) < 24.0:
			continue
		if not m.has_line_of_sight(threat, p):
			unit.move_input = (p - unit.global_position).normalized()
			return
	var away := (unit.global_position - threat).normalized()
	unit.move_input = (away + away.orthogonal() * (1.0 if randf() < 0.5 else -1.0)).normalized()


func _pick_burst() -> int:
	match unit.weapon.cat:
		WeaponData.SMG:
			return randi_range(4, 8)
		WeaponData.HEAVY:
			return randi_range(8, 16) # Machine guns spray.
		WeaponData.PISTOL:
			return randi_range(2, 3)
		WeaponData.SHOTGUN:
			return 1
		WeaponData.SNIPER:
			return 1
	return randi_range(3, 6)


## Nearest spot within 2 cells (one straight step away) the threat can't see.
var _cover_cache_pos := Vector2.INF
var _cover_cache_threat := Vector2.INF
var _cover_cache := Vector2.INF


func _cover_from(threat: Vector2) -> Vector2:
	if _cover_cache_pos.distance_to(unit.global_position) < 8.0 and _cover_cache_threat.distance_to(threat) < 24.0:
		return _cover_cache
	var m = unit.match_node
	var a: Arena = m.arena
	var center := a.world_to_cell(unit.global_position)
	var best := Vector2.INF
	var best_d := INF
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var c := center + Vector2i(dx, dy)
			if a.is_solid(c):
				continue
			var p := a.cell_center(c)
			var d := p.distance_to(unit.global_position)
			if d >= best_d or not m.has_line_of_sight(unit.global_position, p):
				continue
			if fully_hidden(p, threat):
				best = p
				best_d = d
	_cover_cache_pos = unit.global_position
	_cover_cache_threat = threat
	_cover_cache = best
	return best


## No part of the body at `p` (not even a shoulder) is visible from `threat`.
func fully_hidden(p: Vector2, threat: Vector2) -> bool:
	var m = unit.match_node
	var perp := (p - threat).normalized().orthogonal() * (Unit.RADIUS + 2.0)
	for o in [Vector2.ZERO, perp, -perp]:
		if m.has_line_of_sight(threat, p + o):
			return false
	return true


func _evade(delta: float) -> void:
	_evade_timer -= delta
	_turn_toward((_evade_from - unit.global_position).normalized(), delta)
	_retreat_from(_evade_from)


# =============================================================================
# Orders
# =============================================================================

func _gun_value(w: WeaponData) -> float:
	if w == null or w.is_pistol():
		return 0.0
	if w.cat == WeaponData.SNIPER:
		return w.tier + (1.5 if unit.data.role == "AWPer" else -0.6)
	return w.tier


## Grab a clearly better gun lying nearby (a dead player's rifle, say) when
## nothing is going on. Returns true while walking to it.
func _fetch_gun(delta: float) -> bool:
	var m = unit.match_node
	if m.dropped_guns.is_empty() or Game.ab_flag("no_guns"):
		_gun_goal = Vector2.INF
		_gun_skip.clear()
		return false
	if _gun_goal == Vector2.INF:
		_gun_scan -= delta
		if _gun_scan > 0.0:
			return false
		_gun_scan = 0.6
		var act: String = m.objective_for(unit).get("action", "")
		if act == "plant" or act == "defuse" or act == "fetch" or unit.has_bomb:
			return false
		var mine := _gun_value(unit.primary)
		var best_d := 280.0
		for g: Dictionary in m.dropped_guns:
			var d: float = unit.global_position.distance_to(g.pos)
			if d < best_d and _gun_value(g.w) > mine + 0.5 and not _gun_skip.has(g.pos) 					and m.has_line_of_sight(unit.global_position, g.pos):
				best_d = d
				_gun_goal = g.pos
		if _gun_goal == Vector2.INF:
			return false
		_gun_t = 4.0
	_gun_t -= delta
	var still := false
	for g: Dictionary in m.dropped_guns:
		if (g.pos as Vector2).distance_to(_gun_goal) < 1.0:
			still = true
			break
	if not still or _gun_t <= 0.0:
		if still:
			_gun_skip.append(_gun_goal)
		_gun_goal = Vector2.INF
		return false
	if unit.global_position.distance_to(_gun_goal) < 28.0:
		m.pickup_gun(unit)
		_gun_goal = Vector2.INF
		_order_id = "" # Re-read orders from where we are now.
		return false
	_walk_path_to(_gun_goal, delta)
	_look_around(delta, unit.move_input, Vector2.ZERO)
	return true


func _follow_order(delta: float) -> void:
	# Heard or called-out enemy close by: think about it instead of walking on.
	if _intel_cooldown <= 0.0:
		_intel_cooldown = 0.5
		var intel: Vector2 = unit.match_node.tactics.intel_near(unit.side, unit.global_position, INTEL_REACT_RADIUS)
		var saving: bool = unit.match_node.tactics.is_saving(unit)
		var busy: bool = _late_t() or unit.match_node.objective_for(unit).get("action", "") == "fetch"
		if intel != Vector2.INF and (intel.distance_to(_mem_pos) > 64.0 or _mem_age() > 3.0) \
				and (not saving or intel.distance_to(unit.global_position) < 350.0) \
				and (not busy or intel.distance_to(unit.global_position) < 320.0):
			_remember(intel, 100.0, 0.6, null)
			_decide()
			if plan != "":
				return

	_plan_total = maxf(0.0, _plan_total - delta * 0.5) # Following orders = making progress.
	var order: Dictionary = unit.match_node.objective_for(unit)
	if order.id != _order_id:
		_order_id = order.id
		_points = order.points
		_point_idx = 0
		_repath_timer = 0.0
		_peeking = false
	if _points.is_empty():
		unit.move_input = Vector2.ZERO
		return

	while _point_idx < _points.size() - 1 and unit.global_position.distance_to(_points[_point_idx]) < WAYPOINT_DIST:
		_point_idx += 1
		_repath_timer = 0.0
	var goal := _points[_point_idx]
	var final_leg := _point_idx == _points.size() - 1
	var action: String = order.get("action", "")
	var arrive := 34.0 if action == "defuse" else ARRIVE_DIST
	var at_goal := final_leg and unit.global_position.distance_to(goal) < arrive
	var hold := bool(order.get("hold", false))
	var look_pt: Vector2 = order.get("look", Vector2.ZERO)
	var aim_pt: Vector2 = order.get("aim", Vector2.INF)
	if Game.ab_flag("no_preaim"):
		aim_pt = Vector2.INF
	if aim_pt != Vector2.INF and aim_pt.distance_to(unit.global_position) < 1000.0:
		look_pt = aim_pt # Clearing: crosshair on the angle we're responsible for.
	else:
		aim_pt = Vector2.INF
	_holding = hold and final_leg and unit.global_position.distance_to(goal) < 90.0

	if at_goal and (action == "plant" or action == "defuse"):
		unit.move_input = Vector2.ZERO
		if action == "defuse" and not _fake_defuse_done:
			_fake_defuse_done = true
			var m2 = unit.match_node
			var need: float = m2.DEFUSE_TIME_KIT if unit.has_kit else m2.DEFUSE_TIME
			var ts_near: bool = m2.tactics.known_enemies_near(unit.side, unit.global_position, 900.0) > 0
			if ts_near and bomb_time_seen() > need + 5.0 and randf() < 0.25 + 0.4 * pers.discipline * unit.data._t("decision"):
				_fake_defuse_t = randf_range(0.4, 0.7)
				stats.fake_defuses += 1
		unit.match_node.request_action(unit)
		return

	var low := unit.weapon.ammo < unit.weapon.mag_size * 0.5
	if not unit.reloading and low and not unit.knife_out and _clock - _mem_time > 2.5:
		var threat := reload_threat()
		if threat == Vector2.INF or fully_hidden(unit.global_position, threat):
			unit.start_reload()
		elif unit.weapon.ammo < unit.weapon.mag_size * 0.2 and _pistol_ready() and unit.weapon == unit.primary:
			unit.select_pistol() # Nearly dry somewhere exposed: pistol up, reload later.

	if _holding and look_pt != Vector2.ZERO:
		_do_hold(delta, goal, look_pt)
	else:
		_walk_to(delta, goal, at_goal, action, aim_pt)

	if (unit.weapon == unit.pistol or unit.knife_out) and unit.primary != null and not unit.reloading 			and (reload_threat() == Vector2.INF or unit.primary.ammo > unit.primary.mag_size * 0.3):
		unit.select_primary()
	elif unit.knife_out and unit.primary == null:
		unit.select_pistol()


func _walk_to(delta: float, goal: Vector2, at_goal: bool, action: String, aim_pt: Vector2 = Vector2.INF) -> void:
	_repath_timer -= delta
	if _repath_timer <= 0.0:
		_repath_timer = 1.5
		_path = unit.match_node.arena.find_path(unit.global_position, goal)
		_path_idx = 1
	var move := Vector2.ZERO
	if not at_goal:
		if _path_idx < _path.size():
			var wp := _path[_path_idx]
			if unit.global_position.distance_to(wp) < 10.0:
				_path_idx += 1
			move = (wp - unit.global_position).normalized()
		else:
			move = (goal - unit.global_position).normalized()
	if unit.reloading and action == "" and _clock - _mem_time < 6.0:
		move = Vector2.ZERO
	# Stay a trade-distance behind the teammate leading our route in.
	if move != Vector2.ZERO and unit.match_node.tactics.should_wait(unit):
		move = Vector2.ZERO
	unit.move_input = move
	if aim_pt != Vector2.INF:
		# Pre-aiming: walk slower and keep the crosshair on the corner.
		unit.move_input = move * 0.75
		_look_around(delta, move, aim_pt, 0.8)
	else:
		_look_around(delta, move, Vector2.ZERO)


## Holding an ordered position: sit in cover beside the angle and jiggle-peek
## it, or hold it open (AWPers / patient players).
func _do_hold(delta: float, goal: Vector2, look_pt: Vector2) -> void:
	if _hold_for != _order_id:
		_hold_for = _order_id
		_build_hold_spots(goal, look_pt)
	var spot := goal
	if not _holds_open and _cover_spot != Vector2.INF and _peek_spot != Vector2.INF:
		_peek_timer -= delta
		if _peek_timer <= 0.0:
			_peeking = not _peeking
			if _peeking:
				_peek_timer = randf_range(0.2, 0.55) # Quick shoulder peek: take info, get back.
			else:
				var intel: Vector2 = unit.match_node.tactics.intel_near(unit.side, look_pt, 700.0)
				# Nothing known: peek often to find them. Known contact: good players
				# peek less and make them come; impatient ones keep peeking.
				var eager := 1.0
				if intel != Vector2.INF:
					eager = lerpf(0.8, 1.6, unit.data._t("decision"))
				if unit.data.role == "Entry":
					eager *= 0.65
				elif unit.data.role == "Support":
					eager *= 0.9
				_peek_timer = randf_range(0.8, 2.6) * eager
				if Game.ab_flag("old_peek"):
					_peek_timer = randf_range(1.5, 4.5) * eager
		spot = _peek_spot if _peeking else _cover_spot
	elif _holds_open and _peek_spot != Vector2.INF:
		spot = _peek_spot
	for u: Unit in unit.match_node.units:
		if u != unit and u.alive and u.side == unit.side and u.global_position.distance_to(spot) < 28.0 \
				and u.get_instance_id() < unit.get_instance_id():
			# Someone's already there: take the spot next to it.
			var side := (look_pt - spot).normalized().orthogonal()
			var alt := spot + side * 34.0
			if unit.match_node.arena.is_solid(unit.match_node.arena.world_to_cell(alt)):
				alt = spot - side * 34.0
			spot = alt
			break
	# Tight tolerance in cover so a shoulder doesn't hang out past the wall.
	_move_to(spot, 6.0 if _peeking or spot != _cover_spot else 2.5)
	_look_around(delta, Vector2.ZERO, look_pt)


## Cover = nearby spot hidden from the angle we watch AND from as many enemy
## approach points as possible. Peek = nearby spot that sees the angle while
## exposed to as little else as possible.
func _build_hold_spots(goal: Vector2, look_pt: Vector2) -> void:
	var m = unit.match_node
	var a: Arena = m.arena
	_cover_spot = Vector2.INF
	_peek_spot = Vector2.INF
	# Where enemies could see this position from (excluding our own side's areas).
	var own_area := "ct" if unit.side == Tactics.CT else "t"
	var threats: Array[Vector2] = [look_pt]
	for k: String in a.points:
		var p := a.pt(k)
		var d := p.distance_to(goal)
		if d < 64.0 or d > 1100.0 or a.threat_at(p) == own_area:
			continue
		if m.has_line_of_sight(p, goal):
			threats.append(p)
	var center := a.world_to_cell(goal)
	var best_cover := INF
	var best_peek := INF
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var c := center + Vector2i(dx, dy)
			if a.is_solid(c):
				continue
			var p := a.cell_center(c)
			if not m.has_line_of_sight(goal, p):
				continue
			var exposure := 0
			for t in threats.slice(1):
				if m.has_line_of_sight(p, t):
					exposure += 1
			var score := exposure * 100.0 + p.distance_to(goal)
			if m.has_line_of_sight(p, look_pt):
				if score < best_peek:
					best_peek = score
					_peek_spot = p
			elif fully_hidden(p, look_pt):
				if score < best_cover:
					best_cover = score
					_cover_spot = p
			elif score + 1000.0 < best_cover:
				best_cover = score + 1000.0 # Last resort: a shoulder may show.
				_cover_spot = p


func _look_around(delta: float, move: Vector2, look_pt: Vector2, turn_scale: float = 0.45) -> void:
	var look := move
	if look_pt != Vector2.ZERO:
		# Crosshair placement: on the edge of the angle, where they'd appear.
		look = (_edge_aim(unit.global_position, look_pt) - unit.global_position).normalized()
	elif move != Vector2.ZERO:
		var g := _corner_glance(delta, move)
		if g != Vector2.INF:
			look = (g - unit.global_position).normalized()
	var intel: Vector2 = unit.match_node.tactics.intel_near(unit.side, unit.global_position, 1100.0)
	if intel != Vector2.INF:
		look = (intel - unit.global_position).normalized()
	if _alert_timer > 0.0:
		_alert_timer -= delta
		look = (_alert_pos - unit.global_position).normalized()
	if look != Vector2.ZERO:
		_turn_toward(look.normalized(), delta, turn_scale) # Casual: not a flick.


# =============================================================================
# Reactions
# =============================================================================

func _on_damaged(source: Unit, amount: float) -> void:
	_stress_spike = minf(0.6, _stress_spike + amount / 150.0)
	if source == null or not is_instance_valid(source):
		return
	_spotted_at = _clock
	if _target == null:
		# Shot from out of view: you know roughly where it came from, not the spot.
		var guess := source.global_position + _rand_circle(lerpf(140.0, 50.0, unit.data._t("positioning")))
		unit.match_node.tactics._note(unit.side, source, guess, 60.0, "call")
		_remember(guess, 100.0, 0.9, source)
		_evade_from = guess
		_evade_timer = lerpf(0.9, 0.4, unit.data._t("reaction"))
		plan = ""
	else:
		unit.match_node.report_enemy(unit, source)
		if unit.health < 45.0 and randf() < unit.data._t("decision"):
			_duck_timer = randf_range(0.5, 1.0)


func on_teammate_died(killer_pos: Vector2) -> void:
	killer_pos += _rand_circle(50.0) # The callout, not the exact spot.
	_stress_spike = minf(0.6, _stress_spike + 0.25)
	_trade_at = _clock
	_trade_pos = killer_pos
	if _target == null:
		_alert_pos = killer_pos
		_alert_timer = 2.0
		# A trade opportunity or a threat: treat it like a fresh contact.
		_remember(killer_pos, 100.0, 0.8, null)
		if plan in ["", "hold", "reposition", "jiggle", "bait", "cover"]:
			_decide()


# =============================================================================
# Hearing, trades, stress, mistakes, crosshair habits
# =============================================================================

static func _rand_circle(r: float) -> Vector2:
	return Vector2.from_angle(randf() * TAU) * r * sqrt(randf())


## Chance of a deliberate human mistake: rarer for better players, scaled by
## the difficulty knob.
func _mistake_p(base: float) -> float:
	var skill := clampf((unit.data.rating_exact() - 40.0) / 55.0, 0.0, 1.0)
	return base * lerpf(1.6, 0.3, skill) * mistake_mult


func _update_stress(delta: float) -> void:
	var m = unit.match_node
	var target := (1.0 - unit.health / Unit.MAX_HEALTH) * 0.35
	var alive: Array[int] = m.alive_counts()
	var mine: int = alive[unit.side]
	var theirs: int = alive[1 - unit.side]
	if mine == 1 and theirs >= 2:
		target += -0.1 if pers.has("clutch_calm") else 0.15 + 0.08 * theirs
	elif theirs > mine:
		target += 0.08 * (theirs - mine)
	if unit.flash_t > 0.3:
		target += 0.45
	target += 0.05 * int(m.loss_streak[unit.team_index])
	target += _stress_spike
	_stress_spike = maxf(0.0, _stress_spike - delta * 0.2)
	var resist := 0.4 * pers.composure + 0.35 * unit.data._t("decision") + 0.25 * clampf(unit.data.morale / 100.0, 0.0, 1.0)
	target = clampf(target * (1.0 - 0.65 * resist) * mistake_mult, 0.0, 1.0)
	stress = move_toward(stress, target, delta * (0.8 if target > stress else 0.2))


## Heard something (Tactics.hear): look over there; close and not busy, treat
## it as a contact (pre-aim where we heard it, not where they really are).
func on_heard(pos: Vector2, kind: String) -> void:
	if _target != null or not unit.alive:
		return
	_alert_pos = pos
	_alert_timer = 1.0
	var d := unit.global_position.distance_to(pos)
	if d < INTEL_REACT_RADIUS and _hold_update(pos, 0.8 if kind in ["defuse", "plant"] else 0.55):
		return # Same way in as the angle we're holding: stay on it.
	if d < INTEL_REACT_RADIUS and plan in ["", "hold", "reposition"] and not unit.match_node.tactics.is_saving(unit) \
			and (_mem_age() > 2.0 or _mem_pos.distance_to(pos) > 120.0):
		_remember(pos, 100.0, 0.8 if kind in ["defuse", "plant"] else 0.55, null)
		stats.heard_reacts += 1
		_decide()


## A flash about to pop near us: notice it (sight, the bounce, a teammate's
## call for our own side's flashes) and turn away. Faster, smarter players
## react more often; stress makes it worse.
func _watch_flashes(delta: float) -> void:
	_flash_dodge_t -= delta
	var m = unit.match_node
	if m.utility == null:
		return
	for g: Dictionary in m.utility.projectiles:
		if g.kind != "flash" or float(g.t) > 0.9 or _flash_seen.has(g.get("id", 0)):
			continue
		var d := unit.global_position.distance_to(g.pos)
		if d > Utility.FLASH_RANGE:
			continue
		_flash_seen[g.get("id", 0)] = true
		var skill := (unit.data._t("reaction") + unit.data._t("decision")) * 0.5
		var chance := lerpf(0.3, 0.92, skill) * (1.0 - 0.4 * stress)
		if int(g.side) == unit.side:
			chance = maxf(chance, 0.9) # "Flashing!"
		elif not m.has_line_of_sight(g.pos, unit.global_position):
			chance *= 0.55 # Only heard it bounce.
		if randf() < chance:
			_flash_dodge_t = float(g.t) + 0.12
			_flash_from = g.pos
			stats.flash_dodges += 1


## Our trade partner just died: refrag window. Swing the killer now while
## they're still reloading / repositioning.
func on_partner_died(killer_pos: Vector2) -> void:
	if not unit.alive or _target != null or unit.match_node.tactics.is_saving(unit):
		return
	var guess := killer_pos + _rand_circle(40.0)
	if unit.global_position.distance_to(guess) > 900.0 or unit.health < 30.0:
		return
	_trade_at = _clock
	_trade_pos = guess
	_remember(guess, 100.0, 0.85, null)
	stats.refrags += 1
	_no_flash_once = randf() < 0.6 # Usually no time for a flash.
	_set_plan("swing", 2.5)


## Got a kill: aggressive players (and hotheads) get overconfident and re-peek.
func on_got_kill() -> void:
	if _fight_from_hold:
		stats.hold_kills += 1
	var p := (pers.aggression - 0.4) + (0.5 if pers.has("hothead") else 0.0)
	if p > 0.0 and randf() < _mistake_p(0.6) * p:
		_momentum_until = _clock + 4.0
		stats.overpeeks += 1


## Bomb planted: a few players lose track of the timer this round.
func on_bomb_planted() -> void:
	_fake_defuse_done = false
	bomb_blind = randf() < _mistake_p(0.07)
	if bomb_blind:
		stats.bomb_blind += 1


## The bomb timer as this bot believes it.
func bomb_time_seen() -> float:
	return float(unit.match_node.bomb_timer) + (12.0 if bomb_blind else 0.0)


func _mem_is_awp() -> bool:
	if _mem_enemy == null or not is_instance_valid(_mem_enemy):
		return false
	var e: Dictionary = unit.match_node.tactics.seen_by[unit.side].get(_mem_enemy, {})
	return bool(e.get("awp", false))


## Before a swing / push: a flash first if one is handy (ours, or a nearby
## teammate's). Sometimes we just dry-peek (a mistake).
func _try_peek_flash() -> bool:
	var m = unit.match_node
	var t: Tactics = m.tactics
	if _late_t() or randf() < _mistake_p(0.25):
		stats.dry_peeks += 1
		return false
	var to := _mem_pos - unit.global_position
	var d := to.length()
	if d < 160.0 or d > 700.0:
		return false
	var pt := _mem_pos - to / d * 80.0
	if int(unit.grenades.get("flash", 0)) > 0 and t._can_throw(unit, pt, "flash") and m.utility.throw(unit, "flash", pt):
		t._util_cd[unit] = m.round_clock + 2.5
		stats.flash_waits += 1
		return true
	for u: Unit in m.units:
		if u == unit or not u.alive or u.side != unit.side or u.data.is_user and not Game.autoplay:
			continue
		if int(u.grenades.get("flash", 0)) <= 0 or u.global_position.distance_to(unit.global_position) > 400.0:
			continue
		var ok := false
		for c in u.get_children():
			if c is BotController and (c as BotController).can_cover():
				ok = true
		if ok and t._can_throw(u, pt, "flash") and m.utility.throw(u, "flash", pt):
			t._util_cd[u] = m.round_clock + 2.5
			t._say(u, "Flashing it for you.")
			stats.flash_waits += 1
			return true
	return false


## Dev metric: when we believe someone is somewhere (and can't see anyone),
## is the crosshair on the believed spot or on where they really are?
func _belief_metric(delta: float) -> void:
	_metric_t -= delta
	if _metric_t > 0.0 or _mem_conf < 0.3 or _mem_age() > 4.0 or _mem_pos == Vector2.INF:
		return
	_metric_t = 0.5
	var m = unit.match_node
	var best: Unit = null
	var best_d := INF
	for e: Unit in m.enemies_of(unit.side):
		var d := e.global_position.distance_to(_mem_pos)
		if d < best_d:
			best_d = d
			best = e
	if best == null or best_d < 60.0:
		return
	var a_mem := absf(unit.aim_dir.angle_to(_mem_pos - unit.global_position))
	var a_true := absf(unit.aim_dir.angle_to(best.global_position - unit.global_position))
	if a_mem + 0.15 < a_true:
		stats.aim_belief += 1
	elif a_true + 0.15 < a_mem:
		stats.aim_true += 1


## Holding an angle: put the crosshair on its edge (where a peeker appears
## first) instead of the middle of the room. Cached per spot.
func _edge_aim(from: Vector2, look_pt: Vector2) -> Vector2:
	var key := Vector2(roundf(from.x / 24.0), roundf(from.y / 24.0)) * 10000.0 + look_pt.round()
	if key == _edge_key:
		return _edge_pt
	_edge_key = key
	_edge_pt = look_pt
	var m = unit.match_node
	var base := (look_pt - from).angle()
	var L := from.distance_to(look_pt)
	if L < 80.0:
		return look_pt
	var prev := -1.0
	var best := 0.0
	for i in range(-10, 11):
		var ang := base + deg_to_rad(i * 3.0)
		var d: float = m._wall_distance(from, Vector2.from_angle(ang), L * 1.6)
		if prev >= 0.0:
			var jump := absf(d - prev)
			var score := jump - absf(i) * 12.0
			if jump > 90.0 and score > best:
				best = score
				# Just inside the open side of the edge.
				var open_ang := ang if d > prev else base + deg_to_rad((i - 1) * 3.0)
				var nudge := deg_to_rad(1.5) * (1.0 if d > prev else -1.0)
				_edge_pt = from + Vector2.from_angle(open_ang + nudge) * minf(L, 650.0)
		prev = d
	return _edge_pt


## Walking: glance at the corners and doorways along the way, nearest-to-
## the-crosshair first (a natural sweep), then back to where we're going.
func _corner_glance(delta: float, move: Vector2) -> Vector2:
	_glance_t -= delta
	if _glance_t > 0.0:
		return _glance_pt
	if _glance_pt != Vector2.INF:
		_glance_pt = Vector2.INF
		_glance_t = randf_range(0.5, 1.3) # Eyes forward for a bit.
		return Vector2.INF
	var m = unit.match_node
	var a: Arena = m.arena
	var best := Vector2.INF
	var best_turn := INF
	for k: String in a.points:
		var p := a.pt(k)
		var to := p - unit.global_position
		var d := to.length()
		if d < 120.0 or d > 600.0:
			continue
		var off := absf(move.angle_to(to))
		if off < deg_to_rad(25.0) or off > deg_to_rad(150.0):
			continue
		if _clock - float(_glanced.get(p, -100.0)) < 6.0:
			continue
		var turn := absf(unit.aim_dir.angle_to(to))
		if turn < best_turn and m.has_line_of_sight(unit.global_position, p):
			best_turn = turn
			best = p
	if best != Vector2.INF:
		_glanced[best] = _clock
		_glance_pt = best
		_glance_t = randf_range(0.35, 0.7)
	else:
		_glance_t = 0.8
	return _glance_pt
