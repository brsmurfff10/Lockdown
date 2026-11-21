extends Node
## Planted-bomb sprite: plants the bomb next to the user and screenshots it
## (LED on and off), zoomed in.
## Run: godot --path . res://tests/bomb_shot.tscn -- --test --out=<dir>
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
	while m.phase != m.Phase.LIVE:
		await get_tree().process_frame
	m.buy_menu_open = false
	m._zoom = 3.0
	for u: Unit in m.units:
		if u == m.user_unit: continue
		u.set_physics_process(false)
		u.set_process(false)
	var me: Unit = m.user_unit
	me.global_position = m.arena.site_center("A") - Vector2(40, 0)
	await _wait(1.5)
	if m.bomb_carrier != null:
		m.bomb_carrier.has_bomb = false
		m.bomb_carrier = null
	m.bomb_state = m.Bomb.PLANTED
	m.bomb_pos = me.global_position + Vector2(40, 0)
	m.bomb_timer = m.BOMB_TIMER
	m.bomb_site = m.arena.site_at(m.bomb_pos)
	m.tactics.on_planted(m.bomb_site, m.bomb_pos)
	var shots := 0
	for i in 8:
		await _wait(0.25)
		get_viewport().get_texture().get_image().save_png(out + "/bomb_%d.png" % i)
		print(i, " state ", m.bomb_state, " beep ", m._beep_phase, " cam ", get_viewport().get_camera_2d().get_screen_center_position(), " me ", me.global_position)
		shots += 1
	print("bomb shots: ", shots, " me ", me.global_position, " alive ", me.alive, " vis ", me.visible, " bomb ", m.bomb_pos, " bv ", m.bomb_view.visible, " z ", m.bomb_view.z_index, " cam ", get_viewport().get_camera_2d().get_screen_center_position() if get_viewport().get_camera_2d() else Vector2.ZERO)
	get_tree().quit()
func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout
