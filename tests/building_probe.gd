extends Node
## Walk-through buildings: open windows block walking but not sight, and bots use
## the buildings in real rounds on every map (time inside, kills inside, T win rate).
##   godot --headless --path . --fixed-fps 60 res://tests/building_probe.tscn -- --test [--rounds=6] [--map=Dustline]
var fails := 0


func _ready() -> void:
	Game.autoplay = true
	var rounds := 6
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rounds="):
			rounds = int(a.substr(9))
		if a.begins_with("--map="):
			only = a.substr(6)
	for map_name: String in Maps.LIST:
		if only != "" and map_name != only:
			continue
		await _map(map_name, rounds)
	print("building_probe: %d failure(s)" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func _map(map_name: String, rounds: int) -> void:
	Game.prepare_quick_match(map_name)
	Game.pending_match.mode = "test"
	var m: Node = load(Game.MATCH_SCENE).instantiate()
	add_child(m)
	while not m.is_live():
		await get_tree().physics_frame
	var a: Arena = m.arena
	# Glass: find a window cell with floor on both sides.
	var checked := false
	for b: Dictionary in a.buildings:
		for r: Rect2i in b.get("windows", []):
			var c := r.position
			for dv: Vector2i in [Vector2i(0, 1), Vector2i(1, 0)]:
				if checked or a.is_solid(c - dv) or a.is_solid(c + dv):
					continue
				checked = true
				var p0 := a.cell_center(c - dv)
				var p1 := a.cell_center(c + dv)
				_check(m.has_wall_los(p0, p1), "%s: you can see through the %s window" % [map_name, b.name])
				var u: Unit = m.units[0]
				for cc in u.get_children():
					if cc is BotController:
						cc.set_physics_process(false)
				u.global_position = p0
				u.velocity = Vector2.ZERO
				for f in 60:
					u.move_input = (p1 - p0).normalized()
					await get_tree().physics_frame
				u.move_input = Vector2.ZERO
				var crossed: bool = (u.global_position - a.cell_center(c)).dot(p1 - p0) > 0.0
				_check(not crossed, "%s: you can't walk through the window" % map_name)
				for cc in u.get_children():
					if cc is BotController:
						cc.set_physics_process(true)
	m.queue_free()
	await get_tree().process_frame
	# Real rounds.
	Game.prepare_quick_match(map_name)
	Game.pending_match.mode = "test"
	m = load(Game.MATCH_SCENE).instantiate()
	add_child(m)
	a = m.arena
	var inside := {} # building -> unit-seconds
	var stuck := 0
	var still := {}
	var tally := [0, 0] # kills at buildings, kills
	for u: Unit in m.units:
		u.died.connect(func(victim: Unit, killer: Unit) -> void:
			tally[1] += 1
			if a.building_at(victim.global_position) != "" or (killer != null and is_instance_valid(killer) and a.building_at(killer.global_position) != ""):
				tally[0] += 1)
	var dt := 1.0 / 60.0
	while m.round_num <= rounds and m.phase != m.Phase.MATCH_OVER:
		await get_tree().physics_frame
		if not m.can_fight():
			still.clear()
			continue
		for u: Unit in m.units:
			if not u.alive:
				continue
			var bn := a.building_at(u.global_position)
			if bn != "":
				inside[bn] = float(inside.get(bn, 0.0)) + dt
			# Stuck: wants to move but hasn't for 4 s.
			if u.move_input.length() > 0.5 and u.velocity.length() < 5.0:
				still[u] = float(still.get(u, 0.0)) + dt
				if float(still[u]) > 4.0:
					stuck += 1
					still[u] = -1000.0
			else:
				still[u] = 0.0
	var tw := 0
	for r: Dictionary in m.round_log:
		if int(r.get("winner_side", -1)) == 0:
			tw += 1
	var line := ""
	for bn in inside:
		line += "%s %.0fs  " % [bn, inside[bn]]
	print("[%s] %d rounds, T won %d  | time in buildings: %s| kills in/at buildings %d/%d  stuck bots %d" % [map_name, m.round_log.size(), tw, line, tally[0], tally[1], stuck])
	_check(inside.size() >= 1, "%s: bots go through the buildings" % map_name)
	_check(stuck <= 2, "%s: bots don't get stuck (%d)" % [map_name, stuck])
	m.queue_free()
	await get_tree().process_frame


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		fails += 1
