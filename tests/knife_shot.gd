extends Node
## Screenshots: the knife (drawn, mid-swipe, a backstab), the minimap, and a
## smoke with a frag hole and a bullet lane through it.
##   godot --path . res://tests/knife_shot.tscn -- --test --out=<dir>

var m: Node
var out := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	get_window().size = Vector2i(1600, 900)
	Game.prepare_quick_match("Dustline")
	Game.pending_match.mode = "test"
	m = load(Game.MATCH_SCENE).instantiate()
	add_child(m)
	m.buy_menu_open = false
	while not m.is_live():
		await get_tree().physics_frame
	m.buy_menu_open = false
	var me: Unit = m.user_unit
	var foe: Unit = null
	for u: Unit in m.units:
		if u.side != me.side and foe == null:
			foe = u
		elif u != me:
			u.global_position = Vector2(-5000, -5000)
			u.set_physics_process(false)
			for c in u.get_children():
				c.set_physics_process(false)
	for c in me.get_children():
		c.set_physics_process(false) # Scripted, not the mouse.
	for c in foe.get_children():
		c.set_physics_process(false)
	foe.move_input = Vector2.ZERO
	foe.set_physics_process(false)
	me.move_input = Vector2.ZERO
	var spot: Vector2 = m.arena.pt(Vector2i(50, 32))
	me.global_position = spot
	me.aim_dir = Vector2.RIGHT
	foe.global_position = spot + Vector2(120, -60)
	foe.aim_dir = Vector2.RIGHT # Facing away: backstab.
	me.select_knife()
	await _frames(20)
	_shot("knife_drawing")
	await _wait(1.0)
	_shot("knife_idle")
	foe.global_position = spot + Vector2(34, 0)
	me.try_fire()
	await _frames(6)
	_shot("knife_swipe")
	await _frames(20)
	print("backstab killed: ", not foe.alive)
	_shot("knife_after")
	# Smoke between us and a spot down the street, then a frag hole, then a spray lane.
	me.select_primary()
	if me.primary == null:
		me.give_primary(WeaponData.RAPTOR)
	var target := spot + Vector2(260, 0)
	m.utility.smokes.append({"pos": target, "age": 2.0, "holes": []})
	await _wait(1.1)
	_shot("smoke_full")
	me.global_position = target + Vector2(-20, 10) # Step inside the cloud.
	await _frames(25)
	_shot("smoke_inside")
	me.global_position = spot
	await _frames(25)
	m.utility.smokes[0].holes.append({"pos": target + Vector2(-30, 40), "r": Utility.SMOKE_RADIUS * 0.85, "t": Utility.FRAG_HOLE_T})
	await _frames(4)
	_shot("smoke_frag_hole")
	m.utility.smokes[0].holes.clear()
	me.aim_dir = Vector2.RIGHT
	for i in 18:
		me.fire_cooldown = 0.0
		me.bloom = 0.0
		me.weapon.ammo = 30
		me.try_fire()
		await _frames(3)
	_shot("smoke_bullet_lane")
	print("lane open: ", not m.utility.blocks(spot, spot + Vector2(520, 0)))
	get_tree().quit()


func _shot(name: String) -> void:
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout
