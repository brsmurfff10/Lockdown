extends Node
## Slides a target out from behind a wall corner and reports how much of its
## body is past the corner line when it first becomes visible/shootable.


func _ready() -> void:
	Game.autoplay = true
	Game.prepare_quick_match("Cage")
	Game.pending_match.mode = "test"
	var m: Node = load(Game.MATCH_SCENE).instantiate()
	add_child(m)
	while not m.is_live():
		await get_tree().physics_frame
	var viewer: Unit = m.units.filter(func(u: Unit) -> bool: return u.side == 0)[0]
	var target: Unit = m.units.filter(func(u: Unit) -> bool: return u.side == 1)[0]
	for u in m.units:
		u.set_physics_process(false)
		for c in u.get_children():
			if c is BotController:
				c.set_physics_process(false)
	# Mid box occupies cells x20-21, y15-16 on Cage: its bottom edge is y = 17*32 = 544.
	# Viewer looks along row y16 from the left; target sits behind the box on the right
	# and slides down past the bottom edge.
	viewer.global_position = Vector2(12.5 * 32, 544.0 - 14.0)
	var edge_y := 544.0
	var first := INF
	for step in 60:
		var cy := edge_y - 24.0 + step * 0.5
		target.global_position = Vector2(26.5 * 32, cy)
		if m.can_see(viewer, target):
			first = cy
			break
	# Corner line from viewer through the box corner (704, 544): how far is the target's
	# body past that line at the moment it first shows?
	var corner := Vector2(704, 544)
	var dir := (corner - viewer.global_position).normalized()
	var normal := dir.orthogonal()
	if normal.y < 0:
		normal = -normal
	var center_past: float = (Vector2(26.5 * 32, first) - corner).dot(normal)
	var exposed := center_past + Unit.RADIUS
	print("[corner] target first visible with %.1f px of its %.0f px body past the corner (%.0f%%)" % [exposed, Unit.RADIUS * 2, 100.0 * exposed / (Unit.RADIUS * 2)])
	get_tree().quit()
