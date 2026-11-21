extends Node
## Gun art in a match: buy menu (silhouettes + hovered picture), then players
## holding different guns, guns on the floor, the HUD picture and kill feed.
## Run: godot --path . res://tests/gun_art_shot.tscn -- --test --out=<dir>
func _ready() -> void:
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
	get_window().size = Vector2i(1600, 900)
	Game.prepare_quick_match("Dustline")
	Game.pending_match.mode = "test"
	var m: Node = load(Game.MATCH_SCENE).instantiate()
	add_child(m)
	await _wait(2.0)
	m.hud._show_buy_detail("w:%d" % WeaponData.LONGBOW)
	await _wait(0.3)
	get_viewport().get_texture().get_image().save_png(out + "/guns_buy.png")
	while m.phase != m.Phase.LIVE:
		await get_tree().process_frame
	m.buy_menu_open = false
	m._zoom = 2.6
	var me: Unit = m.user_unit
	me.give_primary(WeaponData.KODIAK)
	var c: Vector2 = m.arena.site_center("A")
	me.global_position = c
	var guns := [WeaponData.LONGBOW, WeaponData.HAMMER, WeaponData.SWARM, WeaponData.MAGNUM, WeaponData.BREACHER, WeaponData.GUARDIAN]
	var i := 0
	for u: Unit in m.units:
		if u == me: continue
		u.set_physics_process(false)
		u.set_process(false)
		if i < guns.size():
			if guns[i] == WeaponData.MAGNUM: u.give_pistol(guns[i])
			else: u.give_primary(guns[i])
			u.global_position = c + Vector2(-150 + (i % 3) * 120, -40 + (i / 3) * 110)
			u.aim_dir = Vector2.RIGHT.rotated(i * 1.1)
			u.queue_redraw()
		else:
			u.global_position = c + Vector2(2000, 2000)
		i += 1
	var drops := [WeaponData.PK9, WeaponData.TALON, WeaponData.KESTREL, WeaponData.TEMPEST, WeaponData.OVERWATCH]
	for j in drops.size():
		m.drop_gun(WeaponData.by_id(drops[j]), c + Vector2(-120 + j * 60, 150))
	m.hud.add_kill(m.units[1], m.units[2])
	m.hud.add_kill(me, m.units[3])
	await _wait(1.5)
	get_viewport().get_texture().get_image().save_png(out + "/guns_match.png")
	for u: Unit in m.units:
		if u.global_position.distance_to(c) < 400: print(u.data.player_name, " ", u.weapon.weapon_name, " muzzle ", GunArt.muzzle_point(u.weapon, u.aim_dir, u.side).length(), " scoped ", u.scope_t, " pos ", u.global_position - c)
	print("zoom ", m._zoom, " cam zoom ", get_viewport().get_camera_2d().zoom)
	print("gun art shots done; has kodiak art: ", GunArt.has(WeaponData.KODIAK))
	get_tree().quit()
func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout
