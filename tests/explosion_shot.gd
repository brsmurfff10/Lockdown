extends Node
## Explosion VFX: a frag-sized and a bomb-sized blast beside the user,
## captured early (fireball), mid (fire in smoke) and late (smoke + scorch).
## Run: godot --path . res://tests/explosion_shot.tscn -- --test --out=<dir>
func _ready() -> void:
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
	get_window().size = Vector2i(1600, 900)
	Game.prepare_quick_match("Dustline")
	Game.pending_match.mode = "test"
	var m: Node = load(Game.MATCH_SCENE).instantiate()
	add_child(m)
	while m.phase != m.Phase.LIVE:
		await get_tree().process_frame
	m.buy_menu_open = false
	m._zoom = 1.6
	var me: Unit = m.user_unit
	var c: Vector2 = m.arena.site_center("A")
	me.global_position = c
	for u: Unit in m.units:
		if u != me:
			u.set_physics_process(false)
			u.set_process(false)
	await get_tree().create_timer(2.0).timeout
	m.vfx.explode(c + Vector2(-170, 120), 110.0)
	m.vfx.explode(c + Vector2(220, 140), 190.0, true)
	for pair in [[0.12, "early"], [0.45, "mid"], [1.4, "late"]]:
		await get_tree().create_timer(pair[0] - (0.0 if pair[1] == "early" else 0.0)).timeout
		get_viewport().get_texture().get_image().save_png(out + "/expl_%s.png" % pair[1])
	print("explosion shots done")
	get_tree().quit()
