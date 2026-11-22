extends Node
## One bot duel, traced frame by frame: when the bot sees the dummy, when its
## reaction finishes, when the crosshair is on, when it fires and hits.
##   godot --headless --path . --fixed-fps 60 res://tests/aim_trace.tscn -- --test [--rating=80] [--strafe]


func _ready() -> void:
	Game.autoplay = true
	var rating := 80
	var strafe := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rating="):
			rating = int(a.substr(9))
		if a == "--strafe":
			strafe = true
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
	var bot: BotController = null
	for c in shooter.get_children():
		if c is BotController:
			bot = c
	for k: String in PlayerData.STAT_KEYS:
		shooter.data.set_stat(k, rating)
	shooter.give_primary(WeaponData.RAPTOR)
	shooter.draw_t = 0.0
	var lane: Array = load("res://tests/aim_duel.gd").new()._open_lane(m, shooter, dummy)
	shooter.global_position = lane[0]
	dummy.global_position = lane[1]
	var to_d: Vector2 = (lane[1] - lane[0]).normalized()
	shooter.aim_dir = to_d.rotated(1.0)
	dummy.health = 100000.0
	var t := 0.0
	var hits := [0]
	dummy.damaged.connect(func(_s: Unit, _a: float) -> void: hits[0] += 1)
	m.sfx.play_log.clear()
	var seen_at := -1.0
	var shots_seen := 0
	var dir := 1.0
	var sw := 0.0
	for i in 60 * 3:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		if strafe:
			sw -= 1.0 / 60.0
			if sw <= 0.0:
				sw = randf_range(0.35, 0.7)
				dir = -dir
			dummy.move_input = to_d.orthogonal() * dir
		else:
			dummy.move_input = Vector2.ZERO
		if seen_at < 0.0 and bot._target != null:
			seen_at = t
			print("%.2f  target acquired  reaction=%.2f perceive=%.2f aim_err=%.1fdeg" % [t, bot._reaction_left, bot._perceive_left, rad_to_deg(bot._aim_err)])
		var shots: int = m.sfx.play_log.filter(func(s: String) -> bool: return s.ends_with("rifle_shot")).size()
		var to_dummy := (dummy.global_position - shooter.global_position).normalized()
		var off := rad_to_deg(absf(shooter.aim_dir.angle_to(to_dummy)))
		if shots != shots_seen:
			print("%.2f  sees=%s cansee=%s off=%.1fdeg react=%.2f perc=%.2f err=%.1f vel=%.0f spread=%.1f shots=%d hits=%d tgt=%s plan=%s hid=%s me=%s dm=%s aim=%.0f" % [t, str(m.sees(shooter, dummy)), str(m.can_see(shooter, dummy)), off, bot._reaction_left, bot._perceive_left,
				rad_to_deg(bot._aim_err), shooter.velocity.length(), shooter.current_spread(), shots, hits[0], str(bot._target != null), bot.plan, str(bot._hidden), str(shooter.global_position.round()), str(dummy.global_position.round()), rad_to_deg(shooter.aim_dir.angle())])
		shots_seen = shots
	get_tree().quit()
