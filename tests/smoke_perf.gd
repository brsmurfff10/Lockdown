extends Node
## Cost of sight checks and drawing through a smoke that's been sprayed.
##   godot --path . res://tests/smoke_perf.tscn -- --test
func _ready() -> void:
	Game.prepare_quick_match("Dustline")
	Game.pending_match.mode = "test"
	var m: Node = load(Game.MATCH_SCENE).instantiate()
	add_child(m)
	while not m.is_live():
		await get_tree().physics_frame
	var c: Vector2 = m.arena.pt(Vector2i(60, 32))
	m.utility.smokes.append({"pos": c, "age": 2.0, "holes": []})
	var from := c - Vector2(400, 0)
	for i in 120: # A long spray (4 mags) through the middle, a little spread.
		m.utility.on_bullet(from, c + Vector2(400, randf_range(-60, 60)))
	m.utility.on_bullet(from, c + Vector2(400, 0))
	m.utility.smokes[0].holes.append({"pos": c + Vector2(-20, 50), "r": Utility.SMOKE_RADIUS * 0.85, "t": 30.0})
	await get_tree().physics_frame
	await get_tree().physics_frame
	var holes_n := (m.utility.smokes[0].holes as Array).size()
	var t0 := Time.get_ticks_usec()
	var n := 3000
	var blocked := 0
	for i in n:
		if m.utility.blocks(from + Vector2(0, randf_range(-80, 80)), c + Vector2(400, randf_range(-80, 80))):
			blocked += 1
	var per := float(Time.get_ticks_usec() - t0) / n
	var frames := 0
	var t1 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 3000:
		for k in 3: # Keep spraying while we measure.
			m.utility.on_bullet(from, c + Vector2(400, randf_range(-60, 60)))
		await get_tree().process_frame
		frames += 1
	print("holes %d, blocks() %.1f us per check (%d/%d blocked), %d fps rendering" % [holes_n, per, blocked, n, frames / 3])
	get_tree().quit()
