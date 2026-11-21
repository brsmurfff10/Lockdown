extends Node
## Bomb planted on A, a CT starts defusing out of the Ts' sight. Do the Ts
## (sitting on post-plant spots without a view of the bomb) go and stop it?
## A trial counts when a T gets eyes on the defuser or hits him within 7 s.
##   godot --headless --path . --fixed-fps 60 res://tests/defuse_push.tscn -- --test [--trials=6] [--ab=old_ai3]

func _ready() -> void:
	Game.autoplay = true
	var trials := 6
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--trials="):
			trials = int(a.substr(9))
	var stopped := 0
	var closed := 0
	for i in trials:
		var r: Array = await _trial()
		stopped += int(r[0])
		closed += int(r[1])
	print("DEFUSE PUSH: Ts contested the defuse in %d/%d trials, moved in on it in %d/%d" % [stopped, trials, closed, trials])
	var ok := Game.ab_flag("old_ai3") or stopped * 3 >= trials * 2
	print("defuse_push: %d failure(s)" % (0 if ok else 1))
	get_tree().quit(0 if ok else 1)


func _ctrl(u: Unit) -> BotController:
	for c in u.get_children():
		if c is BotController:
			return c
	return null


func _trial() -> Array:
	Game.prepare_quick_match("Dustline")
	Game.pending_match.mode = "test"
	var m: Node = load(Game.MATCH_SCENE).instantiate()
	add_child(m)
	while not m.is_live():
		await get_tree().physics_frame
	for f in 10:
		await get_tree().physics_frame
	var a: Arena = m.arena
	var cts: Array = m.units.filter(func(u: Unit) -> bool: return u.side == 1)
	var ts: Array = m.units.filter(func(u: Unit) -> bool: return u.side == 0)
	var ct: Unit = cts[0]
	var team_t: Array = ts.slice(0, 2)
	for u: Unit in m.units:
		if u != ct and not team_t.has(u):
			u.global_position = Vector2(-5000, -5000)
			u.set_physics_process(false)
			var c := _ctrl(u)
			if c != null:
				c.set_physics_process(false)
	var cc := _ctrl(ct)
	cc.set_physics_process(false)
	var bomb := a.site_center("A")
	m.bomb_state = m.Bomb.PLANTED
	m.bomb_pos = bomb
	m.bomb_timer = 30.0
	m.bomb_site = "A"
	var tac = m.tactics
	tac.t_site = "A"
	tac.t_phase = "postplant"
	# Ts on spots 450-800 px away with no view of the bomb.
	var spots: Array = []
	for y in a.H:
		for x in a.W:
			var c := Vector2i(x, y)
			if a.is_solid(c):
				continue
			var p := a.cell_center(c)
			var d := p.distance_to(bomb)
			if d > 450.0 and d < 800.0 and not m.has_line_of_sight(p, bomb) and a.find_path(p, bomb).size() > 1:
				spots.append(p)
	spots.shuffle()
	for i in team_t.size():
		var t: Unit = team_t[i]
		t.global_position = spots[i * 7 % spots.size()]
		tac.t_cover[t] = [t.global_position, bomb]
		tac.orders.erase(t)
	ct.global_position = bomb
	m.request_action(ct)
	var start_d: Array = team_t.map(func(t: Unit) -> float: return a.find_path(t.global_position, bomb).size())
	var contested := 0
	var hp0 := ct.health
	for f in 60 * 7:
		await get_tree().physics_frame
		for t: Unit in team_t:
			if t.alive and m.can_see(t, ct):
				contested = 1
		if ct.health < hp0 or ct.action != Unit.Action.DEFUSE:
			contested = 1
		if contested == 1:
			break
	var moved := 0
	for i in team_t.size():
		var t: Unit = team_t[i]
		if a.find_path(t.global_position, bomb).size() < int(start_d[i]) - 3:
			moved = 1
	m.queue_free()
	await get_tree().process_frame
	return [contested, moved]
