extends Node
## Grenades and their effects: the user holding one, grenades mid-flight, then
## a frag explosion, a smoke cloud and a molotov fire.
## Run: godot --path . res://tests/grenade_shot.tscn -- --test --out=<dir>
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
	m._zoom = 2.2
	var me: Unit = m.user_unit
	var c: Vector2 = m.arena.site_center("A")
	me.global_position = c
	var bots: Array = []
	for u: Unit in m.units:
		if u == me: continue
		u.set_physics_process(false)
		u.set_process(false)
		u.global_position = c + Vector2(3000, 3000)
		bots.append(u)
	me.grenades = {"frag": 1}
	me.held_grenade = "frag"
	await get_tree().create_timer(2.0).timeout
	var kinds := ["flash", "smoke", "frag", "molotov"]
	for i in kinds.size():
		var b: Unit = bots[i]
		b.global_position = c + Vector2(-220, -120 + i * 80)
		b.grenades = {kinds[i]: 1}
		m.utility.throw(b, kinds[i], c + Vector2(260, -160 + i * 110))
	await get_tree().create_timer(0.35).timeout
	get_viewport().get_texture().get_image().save_png(out + "/gren_flight.png")
	await get_tree().create_timer(1.35).timeout
	get_viewport().get_texture().get_image().save_png(out + "/gren_fx_a.png")
	await get_tree().create_timer(2.0).timeout
	get_viewport().get_texture().get_image().save_png(out + "/gren_fx_b.png")
	print("grenade shots done")
	get_tree().quit()
