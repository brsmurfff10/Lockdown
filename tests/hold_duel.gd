extends Node
## Holding a contact, measured: a CT sees a T, the T ducks out of sight, the CT
## is made to hold (plan "hold"); after a pause the T swings back on the CT's
## last-seen spot (plan "push"). Both are equal-stat rifle bots. Reports how
## often the holder wins, whether its crosshair was already on the T when it
## appeared, and how many reloaded on the angle.
##   godot --headless --path . --fixed-fps 60 res://tests/hold_duel.tscn -- --test [--trials=12] [--ab=old_hold]

const SETUPS := [
	# map, CT cell, T seen cell, T hides at
	["Cage", Vector2i(38, 16), Vector2i(28, 16), Vector2i(27, 12)],
	["Dustline", Vector2i(38, 24), Vector2i(38, 13), Vector2i(32, 8)],
	["Harbor", Vector2i(52, 33), Vector2i(42, 40), Vector2i(38, 48)],
]


func _ready() -> void:
	Game.autoplay = true
	var trials := 12
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--trials="):
			trials = int(a.substr(9))
	var tot := {"n": 0, "win": 0, "pre": 0, "moved": 0, "draw": 0, "first": 0, "dealt": 0, "taken": 0}
	for s in SETUPS:
		var r := {"n": 0, "win": 0, "pre": 0, "moved": 0, "draw": 0, "first": 0, "dealt": 0, "taken": 0}
		for i in trials:
			var res := await _trial(s[0], s[1], s[2], s[3])
			for k in res:
				r[k] += res[k]
				tot[k] += res[k]
		print("[hold %s] holder won %d/%d (even %d), hit first %d, damage dealt %d vs taken %d, pre-aimed %d, moved %d" % [
			s[0], r.win, r.n, r.draw, r.first, r.dealt, r.taken, r.pre, r.moved])
	var bs := BotController.stats
	print("HOLD: won %d/%d (%.0f%%), lost %d, hit first %d, damage %d dealt vs %d taken, pre-aimed %d (%.0f%%), moved %d, cover reloads %d, bad reloads %d" % [
		tot.win, tot.n, 100.0 * tot.win / maxi(1, tot.n), tot.n - tot.win - tot.draw, tot.first, tot.dealt, tot.taken,
		tot.pre, 100.0 * tot.pre / maxi(1, tot.n), tot.moved, bs.hold_cover_reloads, bs.bad_reloads])
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _ctrl(u: Unit) -> BotController:
	for c in u.get_children():
		if c is BotController:
			return c
	return null


func _trial(map: String, ct_cell: Vector2i, seen_cell: Vector2i, hide_cell: Vector2i) -> Dictionary:
	Game.prepare_quick_match(map)
	Game.pending_match.mode = "test"
	var m: Node = load(Game.MATCH_SCENE).instantiate()
	add_child(m)
	while not m.is_live():
		await get_tree().physics_frame
	await _frames(10)
	var ct: Unit = null
	var t: Unit = null
	for u: Unit in m.units:
		if u.side == 1 and ct == null:
			ct = u
		elif u.side == 0 and t == null:
			t = u
	for u: Unit in m.units:
		if u != ct and u != t:
			u.global_position = Vector2(-5000, -5000)
			u.set_physics_process(false)
			var c := _ctrl(u)
			if c != null:
				c.set_physics_process(false)
	for u in [ct, t]:
		for k: String in PlayerData.STAT_KEYS:
			u.data.set_stat(k, 60.0)
		u.health = 100.0
	ct.give_primary(WeaponData.GUARDIAN)
	t.give_primary(WeaponData.RAPTOR)
	var tc := _ctrl(t)
	var cc := _ctrl(ct)
	tc.set_physics_process(false)
	t.set_physics_process(false)
	var a: Arena = m.arena
	var ct_start := a.pt(ct_cell)
	ct.global_position = ct_start
	t.global_position = a.pt(seen_cell)
	ct.aim_dir = (t.global_position - ct.global_position).normalized()
	await _frames(14)
	var seen_at := t.global_position
	t.global_position = a.pt(hide_cell)
	await _frames(4)
	cc._target = null
	cc._remember(seen_at, 100.0, 1.0, t)
	cc._set_plan("hold", 4.0)
	await _frames(randi_range(70, 130))
	var moved := 1 if ct.global_position.distance_to(ct_start) > 40.0 else 0
	var dbg := "--debug" in OS.get_cmdline_user_args()
	if dbg:
		print("  spot %s -> aim %s (route idx %d, dist %d) start %s" % [a.world_to_cell(cc._plan_spot), a.world_to_cell(cc._hold_aim) if cc._hold_aim != Vector2.INF else Vector2i(-1, -1), cc._hold_idx, int(cc._plan_spot.distance_to(cc._hold_aim)) if cc._hold_aim != Vector2.INF else -1, ct_cell])
	t.set_physics_process(true)
	tc.set_physics_process(true)
	tc._remember(ct_start, 100.0, 1.0, ct)
	tc._set_plan("push", 8.0)
	var pre := 0
	var first := true
	var res := {"n": 1, "win": 0, "pre": 0, "moved": moved, "draw": 0, "first": 0, "dealt": 0, "taken": 0}
	var first_hit := -1
	for f in 60 * 9:
		await get_tree().physics_frame
		if first_hit < 0:
			if t.health < 100.0:
				first_hit = 1
			elif ct.health < 100.0:
				first_hit = 0
			if first_hit >= 0 and dbg:
				print("  f%d first hit by %s" % [f, "CT" if first_hit == 1 else "T"])
		if dbg and tc._target == ct and not tc.has_meta("s"):
			tc.set_meta("s", 1)
			print("  f%d T spots CT (dist %d)" % [f, int(t.global_position.distance_to(ct.global_position))])
		if first and cc._target == t:
			if dbg:
				print("  f%d CT spots T at %s (dist %d) aim err %.0f deg" % [f, a.world_to_cell(t.global_position), int(t.global_position.distance_to(ct.global_position)), rad_to_deg(ct.aim_dir.angle_to(t.global_position - ct.global_position))])
			first = false
			var to := (t.global_position - ct.global_position).normalized()
			if ct.aim_dir.dot(to) > cos(deg_to_rad(10.0)):
				pre = 1
		if "--debug2" in OS.get_cmdline_user_args() and f % 60 == 0:
			print("  f%d ct %s hp%d plan=%s tgt=%s | t %s hp%d plan=%s tgt=%s ammo %d/%d" % [f, a.world_to_cell(ct.global_position), ct.health, cc.plan, cc._target != null, a.world_to_cell(t.global_position), t.health, tc.plan, tc._target != null, ct.weapon.ammo, t.weapon.ammo])
		if not t.alive or not ct.alive:
			break
	res.pre = pre
	res.first = 1 if first_hit == 1 else 0
	res.dealt = int(100.0 - maxf(t.health, 0.0)) if t.alive else 100
	res.taken = int(100.0 - maxf(ct.health, 0.0)) if ct.alive else 100
	# Won = killed them, or came out clearly ahead on damage.
	if (not t.alive and ct.alive) or (t.alive and ct.alive and res.dealt - res.taken >= 25):
		res.win = 1
	elif t.alive and ct.alive and absi(res.dealt - res.taken) < 25:
		res.draw = 1
	m.queue_free()
	await _frames(2)
	return res
