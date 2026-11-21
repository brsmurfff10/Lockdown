extends Node
## Your skills in your hands: a human-driven unit at stat 20 vs 95.
## Flick (spread right after a swing), preaim (steady first shot), reaction
## (aim punch after a hit), utility (grenade scatter), flick (scope time).
##   godot --headless --path . --fixed-fps 60 res://tests/hands_probe.tscn -- --test
var fails := 0


func _ready() -> void:
	Game.autoplay = true
	Game.prepare_quick_match("Dustline")
	Game.pending_match.mode = "test"
	var m: Node = load(Game.MATCH_SCENE).instantiate()
	add_child(m)
	while not m.is_live():
		await get_tree().physics_frame
	var u: Unit = m.units[0]
	for c in u.get_children():
		if c is BotController:
			c.set_physics_process(false)
	for o: Unit in m.units:
		if o != u:
			o.global_position = Vector2(-5000, -5000)
			o.set_physics_process(false)
			for c in o.get_children():
				if c is BotController:
					c.set_physics_process(false)
	u.human = true
	u.give_primary(WeaponData.KODIAK)
	u.draw_t = 0.0
	var res := {}
	for lv in [20, 95]:
		for k in PlayerData.STAT_KEYS:
			u.data.set_stat(k, lv)
		u.velocity = Vector2.ZERO
		u.move_input = Vector2.ZERO
		u.bloom = 0.0
		u.flinch = 0.0
		# Steady on an angle.
		u._swing = 0.0
		u._last_aim = u.aim_dir
		for f in 40:
			await get_tree().physics_frame
		var steady := u.current_spread()
		# Flick 90 degrees in 6 frames, measure right after and 0.15 s later.
		for f in 6:
			u.aim_dir = u.aim_dir.rotated(deg_to_rad(15.0))
			await get_tree().physics_frame
		var flick0 := u.current_spread()
		for f in 9:
			await get_tree().physics_frame
		var flick15 := u.current_spread()
		# Aim punch: a 30-damage hit, measure at once and 0.3 s later.
		for f in 40:
			await get_tree().physics_frame
		var base := u.current_spread()
		u.health = 100.0
		u.armor = 0.0
		u.take_damage(30.0, null)
		var punch0 := u.current_spread() - base
		for f in 18:
			await get_tree().physics_frame
		var punch30 := u.current_spread() - base
		u.health = 100.0
		# Grenade scatter: 20 smokes at 600 px.
		var miss := 0.0
		for i in 20:
			u.draw_t = 0.0
			u.grenades = {"smoke": 1}
			var target := u.global_position + Vector2(600, 0)
			m.utility.throw(u, "smoke", target)
			var p: Dictionary = m.utility.projectiles[-1]
			var fuse: float = m.utility.FUSE["smoke"]
			var land: Vector2 = p.pos + (p.vel as Vector2) / m.utility.DRAG * (1.0 - exp(-m.utility.DRAG * fuse))
			miss += land.distance_to(target)
			m.utility.projectiles.pop_back()
		res[lv] = {"steady": steady, "flick0": flick0, "flick15": flick15, "punch0": punch0, "punch30": punch30, "miss": miss / 20.0}
		print("stat %d: steady %.2f°  right after a flick %.2f° (0.15s later %.2f°)  aim punch %.2f° (0.3s later %.2f°)  smoke lands %.0f px off" % [
			lv, steady, flick0, flick15, punch0, punch30, miss / 20.0])
	if not Game.ab_flag("old_skills"):
		_check(res[95].steady < res[20].steady, "preaim/aim: steadier first shot at 95")
		_check(res[20].flick0 - res[20].steady > 3.0, "flicking costs accuracy at 20")
		_check(res[95].flick15 - res[95].steady < res[20].flick15 - res[20].steady, "flick: settles faster at 95")
		_check(res[20].punch30 > res[95].punch30 * 2.0, "reaction: aim punch wears off faster at 95")
		_check(res[20].miss > res[95].miss + 25.0, "utility: throws land closer at 95 (throws start a body-width out, so ~15 px is the floor)")
	print("hands_probe: %d failure(s)" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		fails += 1
