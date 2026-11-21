extends Node
## Exercises the in-match features: bomb request, weapon drops/pickups (you and
## bots), spectating teammates after death, freecam, HUD dots, vignette, ammo ring.
## Run:  godot --path . res://tests/feature_probe.tscn -- --test --windowed --out=<dir>

var out := "user://features"
var m: Node
var fails := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = Vector2i(1600, 900)
	Game.prepare_quick_match("Dustline")
	Game.pending_match.mode = "test"
	m = load(Game.MATCH_SCENE).instantiate()
	add_child(m)
	await _wait(5)
	# Make sure we're T so we can ask for the bomb.
	var tries := 0
	while m.user_unit.side != m.T and tries < 3:
		m.sides.assign([m.sides[1], m.sides[0]])
		m.round_num -= 1
		m._start_round()
		await _wait(3)
		tries += 1
	var me: Unit = m.user_unit
	m.buy_menu_open = false

	# --- 1. Request the bomb in buy phase ---
	var carrier: Unit = m.bomb_carrier
	_check("someone else carries the bomb", carrier != null and carrier != me)
	m.request_bomb(me)
	await _physics(3)
	_check("bomb is yours after asking", me.has_bomb and m.bomb_carrier == me)
	await _wait(2)
	_shot("buy_bomb_request")

	# --- 2. Guns drop on death; you pick one up with F ---
	await _physics(60 * 11) # into the live round
	var victim: Unit = null
	for u: Unit in m.units:
		if u.side != me.side and u.alive:
			victim = u
			break
	victim.give_primary(WeaponData.RAPTOR)
	victim.take_damage(500.0, me)
	await _physics(2)
	_check("dead player's rifle is on the floor", m.dropped_guns.size() >= 1)
	var gpos: Vector2 = m.dropped_guns[0].pos
	me.global_position = m.arena.cell_center(m.arena.nearest_open(m.arena.world_to_cell(gpos)))
	await _physics(2)
	var had_primary: bool = me.primary != null
	var n_before: int = m.dropped_guns.size()
	_check("F picks it up", m.pickup_gun(me) and me.primary != null and me.primary.id == WeaponData.RAPTOR)
	_check("your old primary (if any) dropped", m.dropped_guns.size() == n_before - 1 + (1 if had_primary else 0))
	m.drop_item(me) # holds the bomb -> drops the bomb first
	_check("G drops the bomb first", not me.has_bomb and m.bomb_state == m.Bomb.DROPPED)
	me.select_primary()
	m.drop_item(me)
	_check("G then drops the held gun", me.primary == null and me.weapon == me.pistol)
	_check("bomb unreserved after you drop it", m.bomb_reserved_for == null)

	# --- 3. Bots grab a better gun nearby ---
	var bot: Unit = null
	for u: Unit in m.units:
		if u.side == me.side and u.alive and u != me:
			bot = u
			break
	bot.primary = null
	bot.weapon = bot.pistol
	m.drop_gun(WeaponData.by_id(WeaponData.RAPTOR), bot.global_position + Vector2(40, 0) if m.has_line_of_sight(bot.global_position, bot.global_position + Vector2(40, 0)) else bot.global_position)
	var got := false
	for i in 60 * 4:
		await get_tree().physics_frame
		# Any bot may take it (in a pistol round every nearby teammate wants it).
		for u: Unit in m.units:
			if u != me and u.alive and u.primary != null and u.primary.id == WeaponData.RAPTOR and u.side == me.side:
				got = true
		if got:
			break
	if not got:
		var bc: BotController = null
		for c in bot.get_children():
			if c is BotController:
				bc = c
		print("    bot alive=%s plan='%s' target=%s gun_goal=%s dist=%.0f guns=%d phase=%d" % [bot.alive, bc.plan, bc._target, bc._gun_goal,
			bot.global_position.distance_to(m.dropped_guns[0].pos) if not m.dropped_guns.is_empty() else -1.0, m.dropped_guns.size(), m.phase])
	_check("bot picked up the rifle", got)

	# --- 4. HUD: low HP vignette, ammo bar, teammate intents, player dots ---
	me.health = 22.0
	me.select_pistol()
	me.weapon.ammo = 4
	m.camera.zoom = Vector2(1.0, 1.0)
	await _wait(20)
	_shot("hud_low_hp")
	me.start_reload()
	await _wait(25)
	_shot("hud_reload")

	# --- 5. Die: watch teammates only, cycle, freecam ---
	var was_alive := me.alive # Enemies may have finished us off during the HUD shots.
	me.take_damage(500.0, victim)
	await _wait(2)
	_check("watching after death", m._watching_others())
	if was_alive:
		_check("first lingers on your body", m._camera_target() == me)
	for i in 110:
		await get_tree().process_frame
	await get_tree().create_timer(1.7).timeout
	var t1: Unit = m._camera_target()
	_check("then follows a live teammate", t1 != null and t1.alive and t1.side == me.side and t1 != me)
	m._spec_next(1)
	var t2: Unit = m._camera_target()
	var alive_mates := 0
	for u: Unit in m.units:
		if u.alive and u.side == me.side:
			alive_mates += 1
	_check("click cycles to another teammate", t2 != null and t2.side == me.side and (t2 != t1 or alive_mates == 1))
	await _wait(20)
	_shot("dead_spectate")
	# Kill the one we're watching: should move on by itself.
	t2.take_damage(500.0, victim)
	await get_tree().create_timer(1.8).timeout
	await _wait(3)
	var t3: Unit = m._camera_target()
	_check("moves on when the watched teammate dies", t3 == null or (t3.alive and t3.side == me.side) or alive_mates <= 1)
	m._freecam = true
	m._freecam_pos = m.camera.position + Vector2(300, 0)
	await _wait(15)
	_check("freecam moves the camera", m.camera.position.distance_to(m._freecam_pos) < 2.0)
	_shot("freecam")
	print("FEATURES: %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit()


func _check(what: String, ok: bool) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		fails += 1


func _shot(name: String) -> void:
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])


func _physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
