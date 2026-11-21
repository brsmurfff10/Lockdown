extends Node
## Scenario tests for bot behaviour. Run with:
##   godot --headless --path . --fixed-fps 60 res://tests/behavior_runner.tscn -- --test


func _ready() -> void:
	Game.autoplay = true
	if "--only-new" in OS.get_cmdline_user_args():
		await _scenario_hearing()
		await _scenario_ghost_clearing()
		get_tree().quit()
		return
	await _scenario_corner_symmetry()
	await _scenario_memory(100.0)
	await _scenario_memory(20.0)
	await _scenario_attacker_chases_weak()
	await _scenario_plant_clicks()
	await _scenario_team_retake(2)
	await _scenario_team_retake(3)
	await _scenario_shot_from_behind()
	await _scenario_holders_peek()
	await _scenario_hearing()
	await _scenario_ghost_clearing()
	await _scenario_trade()
	await _scenario_stress()
	var bs := BotController.stats
	print("METRICS: aim at believed spot %d vs true position %d, refrags %d, flash-peeks %d, dry peeks %d, whiffs %d, panic sprays %d" % [
		bs.aim_belief, bs.aim_true, bs.refrags, bs.flash_waits, bs.dry_peeks, bs.whiffs, bs.panic_sprays])
	get_tree().quit()


func _new_match() -> Node:
	Game.prepare_quick_match()
	Game.pending_match.mode = "test"
	var m: Node = load(Game.MATCH_SCENE).instantiate()
	add_child(m)
	while not m.is_live():
		await get_tree().physics_frame
	return m


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _side(m: Node, side: int) -> Array:
	return m.units.filter(func(u: Unit) -> bool: return u.side == side and u.alive)


## A CT sees a T, the T ducks out of sight: the CT should remember, pick a plan
## (hold / jiggle / swing / push / fallback) and keep aim on the spot. A badly
## hurt CT should fall back rather than peek.
func _scenario_memory(ct_hp: float) -> void:
	var plans := {}
	var aimed := 0
	var trials := 6
	for trial in trials:
		var m := await _new_match()
		await _frames(20)
		var ct: Unit = _side(m, 1)[0]
		var t: Unit = _side(m, 0)[0]
		for u in m.units:
			if u != ct and u != t:
				u.global_position = Vector2(-5000, -5000) # Out of the way.
		for c in t.get_children():
			if c is BotController:
				c.set_physics_process(false)
		t.set_physics_process(false)
		# Put them in mid with clear sight, T in front of CT's aim.
		ct.global_position = m.arena.pt(Vector2i(38, 16))
		ct.aim_dir = Vector2.LEFT
		ct.health = ct_hp
		t.global_position = m.arena.pt(Vector2i(28, 16))
		await _frames(12)
		var seen_spot := t.global_position
		# T steps out of sight (behind the catwalk wall).
		t.global_position = m.arena.pt(Vector2i(27, 12))
		await _frames(18)
		var ctrl: BotController = null
		for c in ct.get_children():
			if c is BotController:
				ctrl = c
		var p := ctrl.plan if ctrl.plan != "" else "(none)"
		plans[p] = plans.get(p, 0) + 1
		if ct.aim_dir.dot((seen_spot - ct.global_position).normalized()) > 0.9:
			aimed += 1
		m.queue_free()
		await _frames(2)
	var ok := aimed >= trials - 1 and not plans.has("(none)")
	if ct_hp < 30.0:
		ok = ok and plans.get("fallback", 0) >= trials - 1
	print("[memory hp=%d] plans %s, aim kept on last-seen spot %d/%d  %s" % [ct_hp, plans, aimed, trials, "PASS" if ok else "FAIL"])


## A healthy T sees a nearly dead CT duck away: it should take the fight.
func _scenario_attacker_chases_weak() -> void:
	var plans := {}
	var trials := 6
	for trial in trials:
		var m := await _new_match()
		await _frames(20)
		# Not the AWPer: they're passive by design (and the test save's My Player may be one).
		var ts: Array = _side(m, 0).filter(func(u: Unit) -> bool: return u.data.role != "AWPer" and not u.data.is_user)
		var t: Unit = ts[0] if not ts.is_empty() else _side(m, 0)[0]
		var ct: Unit = _side(m, 1)[0]
		for u in m.units:
			if u != ct and u != t:
				u.global_position = Vector2(-5000, -5000)
		for c in ct.get_children():
			if c is BotController:
				c.set_physics_process(false)
		ct.set_physics_process(false)
		ct.health = 20.0
		t.global_position = m.arena.pt(Vector2i(28, 16))
		t.aim_dir = Vector2.RIGHT
		ct.global_position = m.arena.pt(Vector2i(38, 16))
		await _frames(12)
		ct.global_position = m.arena.pt(Vector2i(34, 13)) # Into short A, out of sight.
		await _frames(18)
		var ctrl: BotController = null
		for c in t.get_children():
			if c is BotController:
				ctrl = c
		var p := ctrl.plan if ctrl.plan != "" else "(none)"
		plans[p] = plans.get(p, 0) + 1
		m.queue_free()
		await _frames(2)
	var aggressive: int = plans.get("push", 0) + plans.get("swing", 0) + plans.get("flashwait", 0)
	print("[attacker vs weak CT] plans %s  %s" % [plans, "PASS" if aggressive >= trials - 2 else "FAIL"])


## Random positions near walls: visibility must be mutual, and if you can see
## someone your shot must be able to reach them.
func _scenario_corner_symmetry() -> void:
	var m := await _new_match()
	var a: Unit = _side(m, 0)[0]
	var b: Unit = _side(m, 1)[0]
	for u in m.units:
		for c in u.get_children():
			if c is BotController:
				c.set_physics_process(false)
		u.set_physics_process(false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var arena: Arena = m.arena
	var tested := 0
	var asym := 0
	var unshootable := 0
	while tested < 400:
		var ca := Vector2i(rng.randi_range(1, arena.W - 2), rng.randi_range(1, arena.H - 2))
		var cb := ca + Vector2i(rng.randi_range(-8, 8), rng.randi_range(-8, 8))
		if arena.is_solid(ca) or arena.is_solid(cb) or ca == cb:
			continue
		# Random offset inside the cell so bodies sit near wall edges.
		a.global_position = arena.cell_center(ca) + Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3))
		b.global_position = arena.cell_center(cb) + Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3))
		var ab: Array = m.sight_line(a, b)
		var ba: Array = m.sight_line(b, a)
		if ab.is_empty() != ba.is_empty():
			asym += 1
		for pair in [[a, b, ab], [b, a, ba]]:
			var line: Array = pair[2]
			if line.is_empty():
				continue
			var shooter: Unit = pair[0]
			var target: Unit = pair[1]
			var dir: Vector2 = (line[1] - line[0]).normalized()
			var origin: Vector2 = m._shot_origin(shooter, dir)
			var reach: float = origin.distance_to(target.global_position) - Unit.RADIUS
			if m._wall_distance(origin, dir, 3000.0) < reach:
				unshootable += 1
		tested += 1
	print("[corner symmetry] %d pairs: %d asymmetric, %d visible-but-unshootable  %s" % [tested, asym, unshootable, "PASS" if asym == 0 and unshootable <= 4 else "FAIL"])
	m.queue_free()
	await _frames(2)


## Plant clicks: one immediately, then every 0.5s; none after cancelling.
func _scenario_plant_clicks() -> void:
	var m := await _new_match()
	var carrier: Unit = m.bomb_carrier
	# Freeze every bot so nothing interrupts.
	for u in m.units:
		for c in u.get_children():
			if c is BotController:
				c.set_physics_process(false)
		u.move_input = Vector2.ZERO
	carrier.global_position = m.arena.pt(Vector2i(39, 7))
	var count := func() -> int: return m.sfx.play_log.count("lockdown_bomb_plant_click")
	m.sfx.play_log.clear()
	m.request_action(carrier)
	await _frames(int(60 * 2.1))
	carrier.cancel_action()
	var at_cancel: int = count.call()
	await _frames(60)
	var after: int = count.call()
	print("[plant clicks] cancelled at 2.1s: %d clicks, %d after cancel  %s" % [at_cancel, after - at_cancel, "PASS" if at_cancel == 5 and after == at_cancel else "FAIL"])
	m.sfx.play_log.clear()
	m.request_action(carrier)
	await _frames(60 * 5)
	var full: int = count.call()
	var planted: bool = m.bomb_state == m.Bomb.PLANTED
	print("[plant clicks] full plant: %d clicks, planted=%s  %s" % [full, planted, "PASS" if full == 8 and planted else "FAIL"])
	m.queue_free()
	await _frames(2)


## Bomb planted, no Ts alive, several CTs: they must not get stuck sharing the defuse.
func _scenario_team_retake(n: int) -> void:
	var m := await _new_match()
	await _frames(30)
	var cts := _side(m, 1)
	for u in cts.slice(n):
		u.take_damage(999, null)
	var carrier: Unit = m.bomb_carrier
	carrier.global_position = m.arena.pt(Vector2i(41, 10)) # Tucked next to a box.
	m.bomb_state = m.Bomb.PLANTED
	m.bomb_pos = carrier.global_position
	m.bomb_site = "A"
	m.bomb_timer = m.BOMB_TIMER
	m.plant_clock = m.round_clock
	m.planted_this_round = true
	carrier.has_bomb = false
	m.tactics.on_planted("A", m.bomb_pos)
	for u in _side(m, 0):
		u.take_damage(999, null)
	var t0: float = m.round_clock
	for i in 60 * 44:
		await get_tree().physics_frame
		if not m.is_live():
			break
	var result: String = m.round_log[-1].reason if not m.round_log.is_empty() else "none"
	print("[team retake x%d] %s after %.1fs  %s" % [n, result, m.round_clock - t0, "PASS" if result == "Bomb defused" else "FAIL"])
	m.queue_free()
	await _frames(2)


## Bomb planted, every T dead, one CT left far away: it must go defuse.
func _scenario_last_ct_retakes() -> void:
	var m := await _new_match()
	await _frames(30)
	var cts := _side(m, 1)
	var a_pos: Vector2 = m.arena.pt(Vector2i(39, 7))
	cts.sort_custom(func(x: Unit, y: Unit) -> bool: return x.global_position.distance_to(a_pos) > y.global_position.distance_to(a_pos))
	var last: Unit = cts[0]
	for u in cts.slice(1):
		u.take_damage(999, null)
	# Plant at A by hand.
	var carrier: Unit = m.bomb_carrier
	carrier.global_position = m.arena.pt(Vector2i(39, 7))
	m.bomb_state = m.Bomb.PLANTED
	m.bomb_pos = carrier.global_position
	m.bomb_site = "A"
	m.bomb_timer = m.BOMB_TIMER
	m.plant_clock = m.round_clock
	m.planted_this_round = true
	carrier.has_bomb = false
	m.tactics.on_planted("A", m.bomb_pos)
	for u in _side(m, 0):
		u.take_damage(999, null)
	var start_d := last.global_position.distance_to(m.bomb_pos)
	for i in 60 * 44:
		await get_tree().physics_frame
		if not m.is_live():
			break
	var result: String = m.round_log[-1].reason if not m.round_log.is_empty() else "none"
	print("[last CT retake] start dist %.0f -> result: %s  %s" % [start_d, result, "PASS" if result == "Bomb defused" else "FAIL"])
	m.queue_free()
	await _frames(2)


## A CT gets shot by a T standing behind it: it should turn and fight or move.
func _scenario_shot_from_behind() -> void:
	var passes := 0
	for trial in 3:
		var m := await _new_match()
		await _frames(30)
		var ct: Unit = _side(m, 1)[0]
		var t: Unit = _side(m, 0)[0]
		# Put the T 300px behind the CT in a spot with line of sight.
		var behind := ct.global_position - ct.aim_dir * 300.0
		var cell: Vector2i = m.arena.nearest_open(m.arena.world_to_cell(behind))
		t.global_position = m.arena.cell_center(cell)
		var start := ct.global_position
		ct.take_damage(20, t)
		await _frames(int(60 * 1.5))
		var ctrl: BotController = null
		for c in ct.get_children():
			if c is BotController:
				ctrl = c
		var faced := ct.aim_dir.dot((t.global_position - ct.global_position).normalized()) > 0.7
		var moved := ct.global_position.distance_to(start) > 20.0
		var engaged := ctrl != null and ctrl._target == t
		var ok := (faced or engaged or moved) and ct.alive or not t.alive
		print("[shot from behind %d] faced=%s engaged=%s moved=%s t_alive=%s  %s" % [trial, faced, engaged, moved, t.alive, "PASS" if ok else "FAIL"])
		if ok:
			passes += 1
		m.queue_free()
		await _frames(2)


## CTs holding sites should jiggle/peek rather than freeze.
func _scenario_holders_peek() -> void:
	var m := await _new_match()
	# Remove the Ts' threat: freeze Ts in spawn by killing their movement.
	for u in _side(m, 0):
		u.global_position = m.arena.pt(Vector2i(4, 16))
	await _frames(60 * 4) # Let CTs reach their holds.
	var cts := _side(m, 1)
	var travel := {}
	var last := {}
	for u in cts:
		travel[u] = 0.0
		last[u] = u.global_position
	for i in 60 * 10:
		await get_tree().physics_frame
		for u in cts:
			travel[u] += u.global_position.distance_to(last[u])
			last[u] = u.global_position
	var moving := 0
	for u in cts:
		if travel[u] > 40.0:
			moving += 1
		print("   %s (%s) moved %.0fpx while holding" % [u.data.player_name, u.data.role, travel[u]])
	print("[holders peek] %d/%d CTs active while holding  %s" % [moving, cts.size(), "PASS" if moving >= 2 else "FAIL"])
	m.queue_free()
	await _frames(2)


func _ctrl_of(u: Unit) -> BotController:
	for c in u.get_children():
		if c is BotController:
			return c
	return null


func _freeze(u: Unit) -> void:
	var c := _ctrl_of(u)
	if c != null:
		c.set_physics_process(false)
	u.set_physics_process(false)


## An open cell `dist` px from `from` in direction `dir` (or as close as possible).
func _open_near(m: Node, p: Vector2) -> Vector2:
	return m.arena.cell_center(m.arena.nearest_open(m.arena.world_to_cell(p)))


## Hearing: a T runs behind a CT. The CT gets a rough "heard" marker (not the
## exact spot) and turns to check where it heard him.
func _scenario_hearing() -> void:
	var trials := 6
	var rough := 0
	var turned := 0
	var errs := []
	for trial in trials:
		var m := await _new_match()
		await _frames(20)
		var ct: Unit = _side(m, 1)[0]
		var t: Unit = _side(m, 0)[0]
		for u in m.units:
			if u != ct and u != t:
				u.global_position = Vector2(-5000, -5000)
		_freeze(t)
		var behind := _open_near(m, ct.global_position - ct.aim_dir * 320.0)
		t.global_position = behind
		await _frames(2)
		m.tactics.seen_by[1].erase(t)
		m.tactics.hear(t, "steps")
		var e: Dictionary = m.tactics.seen_by[1].get(t, {})
		if not e.is_empty():
			var err := Vector2(e.pos).distance_to(t.global_position)
			errs.append(int(err))
			if String(e.kind) == "heard" and err > 0.5 and err <= float(e.unc) + 1.0:
				rough += 1
			await _frames(45)
			var ctrl := _ctrl_of(ct)
			var to_heard := (Vector2(e.pos) - ct.global_position).normalized()
			# Turned to check the heard spot (or already found him there).
			if ct.aim_dir.dot(to_heard) > 0.85 or (ctrl != null and (ctrl._mem_pos.distance_to(e.pos) < 1.0 or ctrl._target == t)):
				turned += 1
			elif "--verbose-ai" in OS.get_cmdline_user_args():
				print("   hearing miss: unc %.0f err %.0f plan '%s' mem %s heard %s dot %.2f target %s reacts %d" % [e.unc, Vector2(e.pos).distance_to(t.global_position), ctrl.plan, ctrl._mem_pos, e.pos, ct.aim_dir.dot(to_heard), ctrl._target, BotController.stats.heard_reacts])
		m.queue_free()
		await _frames(2)
	var ok := rough >= trials - 1 and turned >= trials - 2
	print("[hearing] rough markers %d/%d (errors %s px), checked the heard spot %d/%d  %s" % [rough, trials, errs, turned, trials, "PASS" if ok else "FAIL"])


## A heard marker in plain view with nobody there gets cleared; the ghost of a
## real sighting does not get cleared from afar (they just stepped out of view).
func _scenario_ghost_clearing() -> void:
	var trials := 4
	var cleared_ok := 0
	var ghost_kept := 0
	for trial in trials:
		var m := await _new_match()
		await _frames(20)
		var ct: Unit = _side(m, 1)[0]
		var ts: Array = _side(m, 0)
		for u in m.units:
			if u != ct:
				u.global_position = m.arena.spawn_points(u.side)[0] if u.side == 0 else Vector2(-5000, -5000)
		for u in ts:
			_freeze(u)
		# Find an open spot the CT can see, ~300px in front.
		var spot := Vector2.INF
		for k in 16:
			var dir := ct.aim_dir.rotated(deg_to_rad((k - 8) * 6.0))
			var p := _open_near(m, ct.global_position + dir * 300.0)
			if m.has_line_of_sight(ct.global_position, p) and p.distance_to(ct.global_position) > 200.0:
				spot = p
				break
		if spot == Vector2.INF:
			m.queue_free()
			await _frames(2)
			continue
		var now: float = m.round_clock
		m.tactics.seen_by[1][ts[0]] = {"pos": spot, "time": now - 1.0, "called": now - 1.0, "kind": "heard", "unc": 60.0, "cleared": false}
		m.tactics.seen_by[1][ts[1]] = {"pos": spot + Vector2(1, 0), "time": now - 1.0, "called": now - 1.0, "kind": "seen", "unc": 40.0, "cleared": false}
		ct.aim_dir = (spot - ct.global_position).normalized()
		_freeze(ct)
		ct.aim_dir = (spot - ct.global_position).normalized()
		await _frames(40)
		if m.tactics.seen_by[1][ts[0]].get("cleared", false):
			cleared_ok += 1
		if not m.tactics.seen_by[1][ts[1]].get("cleared", false):
			ghost_kept += 1
		m.queue_free()
		await _frames(2)
	var ok := cleared_ok >= trials - 1 and ghost_kept >= trials - 1
	print("[ghost clearing] heard spot in view cleared %d/%d, distant ghost kept %d/%d  %s" % [cleared_ok, trials, ghost_kept, trials, "PASS" if ok else "FAIL"])


## Trades: two CTs together, one dies to an unseen T; his partner swings the
## killer within the refrag window.
func _scenario_trade() -> void:
	var trials := 6
	var swung := 0
	for trial in trials:
		var m := await _new_match()
		await _frames(20)
		var cts: Array = _side(m, 1)
		var a: Unit = cts[0]
		var b: Unit = cts[1]
		var t: Unit = _side(m, 0)[0]
		for u in m.units:
			if u != a and u != b and u != t:
				u.global_position = Vector2(-5000, -5000)
		_freeze(t)
		b.global_position = _open_near(m, a.global_position + a.aim_dir.orthogonal() * 60.0)
		t.global_position = _open_near(m, a.global_position - a.aim_dir * 420.0)
		await _frames(20) # Pairing runs on the tactics tick.
		var partner = m.tactics.trade_partner.get(a, null)
		if partner == null:
			m.queue_free()
			await _frames(2)
			continue
		var pc := _ctrl_of(partner)
		a.take_damage(500.0, t)
		await _frames(3)
		if pc != null and (pc.plan in ["swing", "flashwait", "push"] or pc._target == t):
			swung += 1
		m.queue_free()
		await _frames(2)
	var ok := swung >= trials - 2
	print("[trade] partner swung the killer %d/%d  %s" % [swung, trials, "PASS" if ok else "FAIL"])


## Stress: low HP, flashed, last alive -> stress rises; calm conditions stay
## low; mistake_mult 0 turns it off.
func _scenario_stress() -> void:
	var m := await _new_match()
	await _frames(20)
	var ct: Unit = _side(m, 1)[0]
	var bc := _ctrl_of(ct)
	await _frames(60)
	var calm := bc.stress
	for u in _side(m, 1):
		if u != ct:
			u.take_damage(500.0, null)
	ct.health = 25.0
	ct.blind(3.0)
	await _frames(90)
	var high := bc.stress
	BotController.mistake_mult = 0.0
	await _frames(240)
	var off := bc.stress
	BotController.mistake_mult = 1.0
	var ok := high > calm + 0.2 and off < high * 0.5
	print("[stress] calm %.2f -> last alive, 25hp, flashed %.2f -> mistake_mult 0: %.2f  %s" % [calm, high, off, "PASS" if ok else "FAIL"])
	m.queue_free()
	await _frames(2)
