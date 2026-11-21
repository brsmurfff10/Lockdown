extends Node
## Bot aim benchmark: a bot (all stats = rating, rifle, standing) shoots a
## dummy 500px away for 6s. Reports hit rate and time to first hit, for a
## standing and a strafing dummy. Run:
##   godot --headless --path . --fixed-fps 60 res://tests/aim_duel.tscn -- --test


func _ready() -> void:
	Game.autoplay = true
	for rating in [40, 60, 80, 95]:
		for strafing in [false, true]:
			var shots := 0
			var hits := 0
			var max_turn := 0.0
			var first_shots: Array[float] = []
			var first_hits: Array[float] = []
			for trial in 8:
				var r: Dictionary = await _duel(rating, strafing)
				shots += r.shots
				hits += r.hits
				max_turn = maxf(max_turn, r.max_turn)
				if r.first_shot >= 0.0:
					first_shots.append(r.first_shot)
				if r.first_hit >= 0.0:
					first_hits.append(r.first_hit)
			var avg_first := 0.0
			for f in first_hits:
				avg_first += f
			avg_first /= maxf(1.0, first_hits.size())
			var avg_shot := 0.0
			for f in first_shots:
				avg_shot += f
			avg_shot /= maxf(1.0, first_shots.size())
			print("[aim] rating %d %-9s hit rate %3d%%  first shot %.2fs  first hit %.2fs  fastest swing %.0f deg/s" % [rating, "strafing" if strafing else "standing", int(100.0 * hits / maxi(1, shots)), avg_shot, avg_first, max_turn * 60.0])
	get_tree().quit()


func _duel(rating: int, strafing: bool) -> Dictionary:
	Game.prepare_quick_match()
	Game.pending_match.mode = "test"
	var m: Node = load(Game.MATCH_SCENE).instantiate()
	add_child(m)
	while not m.is_live():
		await get_tree().physics_frame
	var shooter: Unit = m.units.filter(func(u: Unit) -> bool: return u.side == 1)[0]
	var dummy: Unit = m.units.filter(func(u: Unit) -> bool: return u.side == 0)[0]
	for u in m.units:
		if u != shooter and u != dummy:
			u.global_position = Vector2(-5000, -5000)
			u.set_physics_process(false)
	for c in dummy.get_children():
		if c is BotController:
			c.set_physics_process(false)
	for k: String in PlayerData.STAT_KEYS:
		shooter.data.set_stat(k, rating)
	shooter.give_primary(WeaponData.RAPTOR)
	var lane := _open_lane(m, shooter, dummy)
	shooter.global_position = lane[0]
	dummy.global_position = lane[1]
	var to_d: Vector2 = (lane[1] - lane[0]).normalized()
	shooter.aim_dir = to_d.rotated(1.0) # ~57 degrees off: inside vision, must swing.
	dummy.health = 100000.0
	var hits := [0]
	var first_hit := [-1.0]
	var t := [0.0]
	dummy.damaged.connect(func(_s: Unit, _a: float) -> void:
		hits[0] += 1
		if first_hit[0] < 0.0:
			first_hit[0] = t[0])
	m.sfx.play_log.clear()
	var dir := 1.0
	var switch := 0.0
	var prev_angle := shooter.aim_dir.angle()
	var max_turn := 0.0
	var first_shot := -1.0
	for i in 60 * 6:
		await get_tree().physics_frame
		t[0] += 1.0 / 60.0
		var a := shooter.aim_dir.angle()
		max_turn = maxf(max_turn, rad_to_deg(absf(wrapf(a - prev_angle, -PI, PI))))
		prev_angle = a
		if first_shot < 0.0 and m.sfx.play_log.size() > 0 and m.sfx.play_log.any(func(s: String) -> bool: return s.ends_with("rifle_shot")):
			first_shot = t[0]
		if strafing:
			switch -= 1.0 / 60.0
			if switch <= 0.0:
				switch = randf_range(0.35, 0.7)
				dir = -dir
			# Strafe across the line of fire, never drifting far from the start.
			var perp := to_d.orthogonal()
			if (dummy.global_position - lane[1]).dot(perp) * dir > 70.0:
				dir = -dir
			dummy.move_input = perp * dir
		else:
			dummy.move_input = Vector2.ZERO
	var shots: int = m.sfx.play_log.filter(func(s: String) -> bool: return s.ends_with("rifle_shot")).size()
	m.queue_free()
	await get_tree().process_frame
	return {"shots": shots, "hits": hits[0], "first_hit": first_hit[0], "max_turn": max_turn, "first_shot": first_shot}


## Shooter/dummy spots ~480px apart with clear sight even when the dummy strafes 90px either way.
func _open_lane(m: Node, shooter: Unit, dummy: Unit) -> Array:
	var a: Arena = m.arena
	for y in range(4, a.H - 4):
		for x in range(4, a.W - 20):
			var p1 := a.pt(Vector2i(x, y))
			var p2 := p1 + Vector2(480, 0)
			var ok := true
			for off in [-90.0, -45.0, 0.0, 45.0, 90.0]:
				shooter.global_position = p1
				dummy.global_position = p2 + Vector2(0, off)
				var q := PhysicsRayQueryParameters2D.create(p1, p2 + Vector2(0, off), 1)
				var q2 := PhysicsRayQueryParameters2D.create(p1 + Vector2(0, 30), p2 + Vector2(0, off + 30), 1)
				var q3 := PhysicsRayQueryParameters2D.create(p1 - Vector2(0, 30), p2 + Vector2(0, off - 30), 1)
				var space: PhysicsDirectSpaceState2D = m.get_world_2d().direct_space_state
				if not space.intersect_ray(q).is_empty() or not space.intersect_ray(q2).is_empty() or not space.intersect_ray(q3).is_empty():
					ok = false
					break
			if ok:
				return [p1, p2]
	return [a.pt(Vector2i(38, 16)), a.pt(Vector2i(23, 17))]
