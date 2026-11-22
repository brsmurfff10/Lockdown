extends Node
## Saving: where does a CT go to keep their gun when the round is lost?
## Bomb planted on A, a T seen in mid. Measures the chosen spot (walls around
## it, ways in, distance to the sites / bomb / enemy, seen from them) and
## whether the bot ends up there facing the way in.
##   godot --headless --path . --fixed-fps 60 res://tests/save_spot.tscn -- --test [--trials=8] [--ab=old_save]

func _ready() -> void:
	Game.autoplay = true
	var trials := 8
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--trials="):
			trials = int(a.substr(9))
	var tot := {"walls": 0.0, "ways": 0.0, "clear": 0, "seen": 0, "arrived": 0, "facing": 0}
	for i in trials:
		var r: Dictionary = await _trial(i)
		for k in tot:
			tot[k] += r[k]
	var n := float(trials)
	print("SAVE SPOT: walls around %.1f/8, ways in %.1f, clear of sites/bomb/enemy %d/%d, in their sight %d/%d, got there %d/%d, facing the way in %d/%d" % [
		tot.walls / n, tot.ways / n, tot.clear, trials, tot.seen, trials, tot.arrived, trials, tot.facing, trials])
	var ok: bool = Game.ab_flag("old_save") or (tot.walls / n >= 4.0 and tot.ways / n <= 3.0 and tot.clear >= trials - 1 and tot.seen <= 1)
	print("save_spot: %d failure(s)" % (0 if ok else 1))
	get_tree().quit(0 if ok else 1)


func _ctrl(u: Unit) -> BotController:
	for c in u.get_children():
		if c is BotController:
			return c
	return null


func _trial(i: int) -> Dictionary:
	Game.prepare_quick_match(["Dustline", "Harbor", "Foundry", "Cage"][i % 4])
	Game.pending_match.mode = "test"
	var m: Node = load(Game.MATCH_SCENE).instantiate()
	add_child(m)
	while not m.is_live():
		await get_tree().physics_frame
	for f in 10:
		await get_tree().physics_frame
	var a: Arena = m.arena
	var ct: Unit = m.units.filter(func(u: Unit) -> bool: return u.side == 1)[0]
	var t: Unit = m.units.filter(func(u: Unit) -> bool: return u.side == 0)[0]
	for u: Unit in m.units:
		if u != ct:
			u.global_position = Vector2(-5000, -5000)
			u.set_physics_process(false)
			var c := _ctrl(u)
			if c != null:
				c.set_physics_process(false)
	ct.global_position = a.pt("mid_hold")
	m.bomb_state = m.Bomb.PLANTED
	m.bomb_pos = a.site_center("A")
	m.bomb_timer = 40.0
	m.bomb_site = "A"
	var tac = m.tactics
	var enemy_pos := a.pt("mid_center")
	tac.seen_by[1][t] = {"pos": enemy_pos, "time": m.round_clock, "called": m.round_clock, "kind": "seen", "unc": 0.0}
	t.global_position = Vector2(-5000, -5000)
	tac._start_save(ct)
	var spot: Vector2 = tac._save_spot[ct]
	var c0 := a.world_to_cell(spot)
	var walls := 0
	for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		if a.is_solid(c0 + dv):
			walls += 1
	var ways: int = tac._open_rays(c0, 8)[0]
	var clear: bool = spot.distance_to(a.site_center("A")) > 500.0 and spot.distance_to(a.site_center("B")) > 500.0 \
		and spot.distance_to(m.bomb_pos) > m.BOMB_RADIUS + 100.0 and spot.distance_to(enemy_pos) > 450.0
	var seen: bool = m.has_wall_los(enemy_pos, spot) or m.has_wall_los(m.bomb_pos, spot)
	var arrived := 0
	var facing := 0
	for f in 60 * 10:
		await get_tree().physics_frame
		if ct.global_position.distance_to(spot) < 30.0:
			arrived = 1
			break
	if arrived == 1:
		for f in 60:
			await get_tree().physics_frame
		var look: Vector2 = tac._save_look.get(ct, Vector2.INF)
		if look != Vector2.INF and ct.aim_dir.dot((look - ct.global_position).normalized()) > 0.85:
			facing = 1
	m.queue_free()
	await get_tree().process_frame
	return {"walls": walls, "ways": ways, "clear": 1 if clear else 0, "seen": 1 if seen else 0, "arrived": arrived, "facing": facing}
