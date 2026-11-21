extends Node
## Bomb planted, the CTs can't make the defuse: do they hide properly (well
## outside the blast, out of sight of the Ts) instead of stopping just past
## the edge?   godot --headless --path . --fixed-fps 60 res://tests/save_hide.tscn -- --test [--map=Dustline]

func _ready() -> void:
	Game.autoplay = true
	var map := "Dustline"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map="):
			map = a.substr(6)
	var ok := 0
	var total := 0
	var margins: Array = []
	var seen := 0
	for trial in 4:
		Game.prepare_quick_match(map)
		Game.pending_match.mode = "test"
		var m: Node = load(Game.MATCH_SCENE).instantiate()
		add_child(m)
		while not m.is_live():
			await get_tree().physics_frame
		await _frames(10)
		var site: String = "A" if trial % 2 == 0 else "B"
		var bomb: Vector2 = m.arena.site_center(site)
		var cts: Array = m.units.filter(func(u: Unit) -> bool: return u.side == 1)
		var ts: Array = m.units.filter(func(u: Unit) -> bool: return u.side == 0)
		# Ts sit on the bomb; CTs start around it with no time to defuse.
		for i in ts.size():
			ts[i].global_position = m.arena.cell_center(m.arena.nearest_open(m.arena.world_to_cell(bomb + Vector2.from_angle(i * 1.3) * 90.0)))
		for i in cts.size():
			cts[i].global_position = m.arena.cell_center(m.arena.nearest_open(m.arena.world_to_cell(bomb + Vector2.from_angle(i * 1.25 + 0.4) * 300.0)))
			cts[i].has_kit = false
		for u in ts:
			for c in u.get_children():
				c.set_physics_process(false) # Ts hold still: this is about the CTs.
			u.set_physics_process(false)
		m.bomb_state = m.Bomb.PLANTED
		m.bomb_pos = bomb
		m.bomb_timer = 9.0
		m.tactics.on_planted(site, bomb)
		for u in ts:
			m.tactics._note(1, u, u.global_position, 30.0, "seen")
		var guard := 0
		while m.bomb_state == m.Bomb.PLANTED and m.bomb_timer > 0.15 and guard < 60 * 15:
			guard += 1
			await get_tree().physics_frame
		for u: Unit in cts:
			if not u.alive:
				continue
			total += 1
			var d := u.global_position.distance_to(bomb)
			margins.append(int(d - m.BOMB_RADIUS))
			if d < m.BOMB_RADIUS:
				var bc: BotController = null
				for ch in u.get_children():
					if ch is BotController:
						bc = ch
				print("  inside: thought=%s escaping=%s saving=%s action=%d plan=%s blind=%s" % [m.tactics.thought.get(u, ""), m.tactics.is_escaping(u), m.tactics.is_saving(u), u.action, bc.plan if bc else "-", bc.bomb_blind if bc else false])
			var hidden := true
			for t: Unit in ts:
				if m.has_wall_los(t.global_position, u.global_position):
					hidden = false
			if hidden:
				seen += 0
			else:
				seen += 1
			if d > m.BOMB_RADIUS + 60.0 and hidden:
				ok += 1
		m.queue_free()
		await _frames(3)
	print("[save hide] %d/%d CTs clear of the blast and out of the Ts' sight (visible %d), margins past the radius %s  %s" % [
		ok, total, seen, margins, "PASS" if total > 0 and ok >= total * 0.75 else "FAIL"])
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
