extends Node
## Movement speeds: base +25%, guns slow you by type, Shift walks at half speed
## silently.
##   godot --headless --path . --fixed-fps 60 res://tests/move_probe.tscn -- --test
var fails := 0


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		fails += 1


func _ready() -> void:
	var want := {WeaponData.PK9 if WeaponData.TABLE.has(WeaponData.PK9) else WeaponData.VIPER: 0.9, WeaponData.HORNET: 0.85,
		WeaponData.KODIAK: 0.8, WeaponData.GUARDIAN: 0.8, WeaponData.LONGBOW: 0.7, WeaponData.PATHFINDER: 0.7, WeaponData.TALON: 0.7}
	for id: int in want:
		var w := WeaponData.by_id(id)
		_check(is_equal_approx(w.move_mult, float(want[id])), "%s moves at %d%%" % [w.weapon_name, int(round(w.move_mult * 100.0))])
	var p := PlayerData.new()
	_check(p.move_speed() >= 155.0, "base speed raised: %.0f" % p.move_speed())
	# Walking in a match: half speed, no footsteps.
	Game.prepare_quick_match("Dustline")
	Game.pending_match.mode = "test"
	var m: Node = load(Game.MATCH_SCENE).instantiate()
	add_child(m)
	while not m.is_live():
		await get_tree().physics_frame
	var u: Unit = null
	for x: Unit in m.units:
		for ch in x.get_children():
			if ch is BotController:
				ch.set_physics_process(false)
		x.move_input = Vector2.ZERO
		if u == null:
			u = x
	u.select_knife()
	for i in 30:
		await get_tree().physics_frame
	var run := 0.0
	for i in 40:
		u.move_input = Vector2.RIGHT
		await get_tree().physics_frame
		run = maxf(run, u.velocity.length())
	for i in 20: # Settle down to walking speed first.
		u.move_input = Vector2.RIGHT * Unit.WALK_MULT
		await get_tree().physics_frame
	m.sfx.play_log.clear()
	var walk := 0.0
	for i in 40:
		u.move_input = Vector2.RIGHT * Unit.WALK_MULT # What PlayerController sends while Shift is held.
		await get_tree().physics_frame
		walk = u.velocity.length()
	var steps: int = m.sfx.play_log.filter(func(s: String) -> bool: return s == "lockdown_footstep").size()
	_check(absf(walk / maxf(run, 1.0) - 0.5) < 0.06, "walking is half speed: %.0f vs %.0f" % [walk, run])
	_check(steps == 0, "walking is silent (%d footsteps)" % steps)
	_check(InputMap.has_action("walk") and not InputMap.action_get_events("free_look").any(func(e: InputEvent) -> bool: return e is InputEventKey), "Shift is walk, free look is right mouse only")
	print("move_probe: %d failure(s)" % fails)
	get_tree().quit()
