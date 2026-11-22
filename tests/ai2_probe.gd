extends Node
## Bot rounds measuring the 0.19 AI work: grenades thrown with no enemies left
## (should be none), rifle shots fired while running (counter-strafing),
## jiggle peeks (several shoulder peeks each) and prefires on last-seen spots.
##   godot --headless --path . --fixed-fps 60 res://tests/ai2_probe.tscn -- --test [--rounds=8] [--ab=old_ai2]
var fails := 0


func _ready() -> void:
	Game.autoplay = true
	var rounds := 8
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rounds="):
			rounds = int(a.substr(9))
	Game.prepare_quick_match(Game._default_map())
	Game.pending_match.mode = "test"
	var m: Node = load(Game.MATCH_SCENE).instantiate()
	add_child(m)
	BotController.stats.prefires = 0
	var nades_alone := 0
	var nade_counts := {}
	var shots_far := 0
	var shots_running := 0
	var ammo := {}
	var jiggle_peeks := 0
	var jiggles := 0
	var last_stage := {}
	var last_round := 0
	var exec_samples := 0
	var stacked := 0
	var retake_util := 0
	var awp_homes := {} ## PlayerData -> Array of home positions per round
	var awp_logged := -1
	while m.round_num <= rounds and m.phase != m.Phase.MATCH_OVER:
		await get_tree().physics_frame
		if m.round_num != last_round:
			last_round = m.round_num
			nade_counts.clear()
			ammo.clear()
		if not m.can_fight():
			continue
		var tac = m.tactics
		# Execute spacing: Ts walking in together, how many pairs are stacked (< 80 px)?
		if tac.t_phase == "execute" and m.bomb_state != m.Bomb.PLANTED:
			var movers: Array = m.units.filter(func(u: Unit) -> bool: return u.alive and u.side == 0 and u.velocity.length() > 40.0)
			if movers.size() >= 2:
				exec_samples += 1
				for i in movers.size():
					for j in range(i + 1, movers.size()):
						if (movers[i] as Unit).global_position.distance_to((movers[j] as Unit).global_position) < 80.0:
							stacked += 1
		if awp_logged != m.round_num and m.round_clock > 3.0:
			awp_logged = m.round_num
			for u: Unit in m.units:
				if u.side == 1 and u.data.role == "AWPer" and tac.ct_home.has(u):
					if not awp_homes.has(u.data):
						awp_homes[u.data] = []
					(awp_homes[u.data] as Array).append(tac.ct_home[u].pos)
		for u: Unit in m.units:
			if not u.alive:
				continue
			var n := 0
			for k in u.grenades:
				n += int(u.grenades[k])
			if nade_counts.has(u) and n < int(nade_counts[u]) and m.enemies_of(u.side).is_empty():
				nades_alone += 1
			if nade_counts.has(u) and n < int(nade_counts[u]) and String(tac.thought.get(u, "")).begins_with("retake:"):
				retake_util += 1
			nade_counts[u] = n
			# Shots: ammo went down this frame.
			var a := u.weapon.ammo
			if ammo.has(u) and a < int(ammo[u]) and u.weapon.cat in [WeaponData.RIFLE, WeaponData.PISTOL]:
				var bc: BotController = null
				for c in u.get_children():
					if c is BotController:
						bc = c
				if bc != null and bc._target != null and is_instance_valid(bc._target) \
						and u.global_position.distance_to(bc._target.global_position) > 250.0:
					shots_far += 1
					if u.movement_penalty_frac() > 0.5:
						shots_running += 1
			ammo[u] = a
			for c in u.get_children():
				if c is BotController:
					var b := c as BotController
					var key := "%d" % u.get_instance_id()
					var st := "%s/%d" % [b.plan, b._plan_stage]
					if b.plan == "jiggle" and st != String(last_stage.get(key, "")):
						if b._plan_stage == 0:
							jiggle_peeks += 1
							if not String(last_stage.get(key, "")).begins_with("jiggle"):
								jiggles += 1
					last_stage[key] = st
	var run_pct := 100.0 * shots_running / maxf(1.0, shots_far)
	var spots := 0
	var rounds_awp := 0
	for pd in awp_homes:
		var hs: Array = awp_homes[pd]
		rounds_awp += hs.size()
		var distinct: Array = []
		for h: Vector2 in hs:
			if not distinct.any(func(q: Vector2) -> bool: return q.distance_to(h) < 100.0):
				distinct.append(h)
		spots += distinct.size()
	print("[ai2] execute spacing: %.2f stacked pairs per sample (%d samples)  retake utility on known Ts: %d  AWP CT homes: %d distinct over %d rounds" % [float(stacked) / maxf(1.0, exec_samples), exec_samples, retake_util, spots, rounds_awp])
	print("[ai2] rounds=%d nades_with_no_enemies=%d  rifle/pistol shots at range=%d, while running=%d (%.0f%%)  jiggles=%d peeks=%d (%.1f per jiggle)  prefires=%d" % [
		m.round_log.size(), nades_alone, shots_far, shots_running, run_pct, jiggles, jiggle_peeks, float(jiggle_peeks) / maxf(1.0, jiggles), BotController.stats.prefires])
	if not Game.ab_flag("old_ai2"):
		_check(nades_alone == 0, "no grenades once the other side is dead (%d)" % nades_alone)
		_check(run_pct < 35.0, "rifles and pistols mostly stop to shoot at range (%.0f%% running)" % run_pct)
		_check(jiggles == 0 or float(jiggle_peeks) / jiggles > 1.5, "jiggle peeks are several shoulder peeks (%.1f)" % (float(jiggle_peeks) / maxf(1.0, jiggles)))
	print("AI2: %d failed" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		fails += 1
