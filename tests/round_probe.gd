extends Node
## Logs what each T bot is doing every 5s through a round. Run:
##   godot --headless --path . --fixed-fps 60 res://tests/round_probe.tscn -- --test --map=Dustline


func _ready() -> void:
	Game.autoplay = true
	Game.prepare_quick_match()
	Game.pending_match.mode = "test"
	for team: TeamData in Game.pending_match.teams:
		for p in team.roster:
			for k: String in PlayerData.STAT_KEYS:
				p.set_stat(k, 60.0)
	var m: Node = load(Game.MATCH_SCENE).instantiate()
	add_child(m)
	for rnd in 2:
		while not m.is_live():
			await get_tree().physics_frame
		print("=== round %d  strat %s  site %s" % [m.round_num, m.tactics.t_strat.name, m.tactics.t_site])
		var t := 0.0
		while m.is_live():
			for i in 300:
				await get_tree().physics_frame
				if not m.is_live():
					break
			t += 5.0
			var line := "t=%3.0f phase=%-9s left=%3.0f |" % [m.round_clock, m.tactics.t_phase, m.round_time_left]
			for u: Unit in m.units:
				if u.side != 0 or not u.alive:
					continue
				var c: BotController = null
				for ch in u.get_children():
					if ch is BotController:
						c = ch
				var route: String = m.tactics.t_route.get(u, "?")
				var stage: Vector2 = m.arena.pt(m.arena.routes[route].stage) if m.arena.routes.has(route) else Vector2.ZERO
				line += " [%s d=%d v=%d %s%s%s]" % [route, int(u.global_position.distance_to(stage)), int(u.velocity.length()),
					c.plan if c.plan != "" else "-", " WAIT" if m.tactics.should_wait(u) else "", " TGT" if c._target != null else ""]
			print(line)
		print("  -> ", m.round_log[-1].reason if not m.round_log.is_empty() else "?")
		while not m.is_live() and m.phase != m.Phase.MATCH_OVER:
			await get_tree().physics_frame
	get_tree().quit()
