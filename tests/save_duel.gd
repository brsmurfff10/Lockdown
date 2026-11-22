extends Node
## Bomb about to blow: a T running from it (escaping) and a CT saving end up in
## the same corner, the T facing the CT. Does anyone shoot? Before the fix
## escaping bots only aimed. Reports trials where shots landed within 4 s.
##   godot --headless --path . --fixed-fps 60 res://tests/save_duel.tscn -- --test [--trials=8] [--ab=old_escape]

func _ready() -> void:
	Game.autoplay = true
	var trials := 8
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--trials="):
			trials = int(a.substr(9))
	var fought := 0
	for i in trials:
		fought += await _trial()
	print("SAVE DUEL: shots landed in %d/%d trials" % [fought, trials])
	print("save_duel: %d failure(s)" % (0 if fought * 2 >= trials or Game.ab_flag("old_escape") else 1))
	get_tree().quit()


func _ctrl(u: Unit) -> BotController:
	for c in u.get_children():
		if c is BotController:
			return c
	return null


func _trial() -> int:
	Game.prepare_quick_match("Dustline")
	Game.pending_match.mode = "test"
	var m: Node = load(Game.MATCH_SCENE).instantiate()
	add_child(m)
	while not m.is_live():
		await get_tree().physics_frame
	for f in 10:
		await get_tree().physics_frame
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
	var a: Arena = m.arena
	var spot := a.pt("ct_spawn")
	ct.global_position = spot
	t.global_position = spot + Vector2(170, 0)
	t.global_position = a.cell_center(a.nearest_open(a.world_to_cell(t.global_position)))
	ct.aim_dir = Vector2.LEFT
	t.aim_dir = (ct.global_position - t.global_position).normalized()
	# Planted far away, not much time left.
	m.bomb_state = m.Bomb.PLANTED
	m.bomb_pos = a.spawn_points(0)[0]
	m.bomb_timer = 12.0
	m.bomb_site = "A"
	var tac = m.tactics
	tac._escaping[t] = tac._order([t.global_position], m.bomb_pos, "", false)
	tac.saving[ct] = true
	tac.ct_state[ct] = "save"
	tac.orders[ct] = tac._order([ct.global_position], m.bomb_pos, "", true)
	var hit := 0
	for f in 60 * 4:
		await get_tree().physics_frame
		if ct.health < 100.0 or t.health < 100.0:
			hit = 1
			break
	m.queue_free()
	await get_tree().process_frame
	return hit
