extends Node
## CT AWPer's home spot over 10 round setups: how many different spots, and
## never the one they died on last round. Also: retake utility goes at known Ts.
##   godot --headless --path . --fixed-fps 60 res://tests/awp_spots.tscn -- --test [--ab=old_ai3]
var fails := 0


func _ready() -> void:
	Game.autoplay = true
	Game.prepare_quick_match("Dustline")
	Game.pending_match.mode = "test"
	var m: Node = load(Game.MATCH_SCENE).instantiate()
	add_child(m)
	while not m.is_live():
		await get_tree().physics_frame
	var tac = m.tactics
	var cts: Array = m.units.filter(func(u: Unit) -> bool: return u.side == 1)
	var awp: Unit = cts[0]
	awp.data.role = "AWPer"
	for u: Unit in cts:
		if u != awp and u.data.role == "AWPer":
			u.data.role = "Rifler"
	var spots: Array = []
	var died_repeat := 0
	var last := Vector2.INF
	for r in 10:
		var died := r % 3 == 1
		if died:
			tac.note_awp_death(awp)
		tac._setup_ct()
		var p: Vector2 = tac.ct_home[awp].pos
		if died and last != Vector2.INF and p.distance_to(last) < 120.0:
			died_repeat += 1
		if not spots.any(func(q: Vector2) -> bool: return q.distance_to(p) < 100.0):
			spots.append(p)
		last = p
	print("AWP SPOTS: %d different spots over 10 rounds, went back to where they died %d time(s)" % [spots.size(), died_repeat])
	if not Game.ab_flag("old_ai3"):
		_check(spots.size() >= 3, "AWPer moves around (%d spots)" % spots.size())
		_check(died_repeat == 0, "never back where they died")
	# Retake utility: a CT with a flash and a known T near the planted bomb.
	m.bomb_state = m.Bomb.PLANTED
	m.bomb_pos = m.arena.site_center("A")
	m.bomb_site = "A"
	var ct: Unit = cts[1]
	var t: Unit = m.units.filter(func(u: Unit) -> bool: return u.side == 0)[0]
	var found := false
	var why := ""
	for y in range(0, m.arena.H, 2):
		for x in range(0, m.arena.W, 2):
			if found:
				break
			var c := Vector2i(x, y)
			if m.arena.is_solid(c):
				continue
			var cp: Vector2 = m.arena.cell_center(c)
			var tp: Vector2 = m.bomb_pos + Vector2(120, 80)
			tp = m.arena.cell_center(m.arena.nearest_open(m.arena.world_to_cell(tp)))
			if cp.distance_to(tp) < 300.0 or cp.distance_to(tp) > 800.0:
				continue
			ct.global_position = cp
			ct.grenades = {"flash": 1, "molotov": 1}
			tac.seen_by[1][t] = {"pos": tp, "time": m.round_clock, "called": m.round_clock, "kind": "seen", "unc": 0.0}
			var plan: Dictionary = tac._retake_util(ct)
			if not plan.is_empty():
				found = true
				why = String(plan.why)
	print("RETAKE UTIL: %s" % (why if found else "none"))
	if not Game.ab_flag("old_ai3"):
		_check(found and why.begins_with("retake:"), "retake utility goes at the known T (%s)" % why)
	print("awp_spots: %d failure(s)" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		fails += 1
