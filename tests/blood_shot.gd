extends Node
## Blood effects: fires shots into a bot (and kills one) next to a wall, then
## screenshots the mist mid-air and the spatter/pool after.
## Run: godot --path . res://tests/blood_shot.tscn -- --test --out=<dir>
func _ready() -> void:
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
	get_window().size = Vector2i(1600, 900)
	Game.prepare_quick_match("Dustline")
	Game.pending_match.mode = "test"
	var m: Node = load(Game.MATCH_SCENE).instantiate()
	add_child(m)
	await _wait(5.0)
	m.buy_menu_open = false
	m._zoom = 2.4
	# Freeze bots, line up a victim in front of the user near a wall.
	var me: Unit = m.user_unit
	var victims: Array = []
	for u: Unit in m.units:
		if u != me:
			u.set_physics_process(false)
			u.set_process(false)
			if u.side != me.side and victims.size() < 2:
				victims.append(u)
	var arena: Arena = m.arena
	me.global_position = arena.cell_center(Vector2i(48, 32))
	victims[0].global_position = arena.cell_center(Vector2i(51, 31))
	victims[1].global_position = arena.cell_center(Vector2i(51, 33))
	me.set_physics_process(false)
	await _wait(0.6)
	var ex: Array[RID] = [me.get_rid()]
	var w := WeaponData.by_id(WeaponData.KODIAK)
	var dir: Vector2 = (victims[0].global_position - me.global_position).normalized()
	m.bullets.fire(me, me.global_position, dir, w, ex)
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out + "/blood_mist.png")
	for i in 4:
		await _wait(0.12)
		m.bullets.fire(me, me.global_position, dir.rotated(randf_range(-0.02, 0.02)), w, ex)
	var dir2: Vector2 = (victims[1].global_position - me.global_position).normalized()
	for i in 2:
		m.bullets.fire(me, me.global_position, dir2, w, ex)
		await _wait(0.1)
	await _wait(2.5)
	get_viewport().get_texture().get_image().save_png(out + "/blood_after.png")
	print("victim alive: ", victims[0].alive, " decals: ", m.blood._decals.size(), " pools: ", m.blood._pools.size())
	get_tree().quit()
func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout
