extends Node
## Grenades (flash / smoke / frag / molotov), bots fleeing the bomb, and a bot
## planting where it picked the bomb up. Run:
##   godot --path . res://tests/grenade_probe.tscn -- --test --windowed --out=<dir>

var out := "user://grenades"
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
	await _physics(5)
	m.buy_menu_open = false
	var me: Unit = m.user_unit
	# Buying.
	var lo: Dictionary = m.loadouts[me.data]
	lo.money = 5000
	for k in ["flash", "flash", "flash", "smoke", "frag", "molotov"]:
		m._purchase(me, k)
	_check("buy: 2 flashes max + smoke + frag (4 total cap)", int(me.grenades.get("flash", 0)) == 2 and Utility.total(me.grenades) == 4)
	var bots_with := 0
	for u: Unit in m.units:
		if u != me and not u.grenades.is_empty():
			bots_with += 1
	print("    bots holding grenades in round 1: %d" % bots_with)
	await _physics(60 * 11) # live

	# Freeze everyone else: move bots to known spots for clean checks.
	var enemy: Unit = _first(func(u: Unit) -> bool: return u.side != me.side and u.alive)
	var open := _open_lane(500.0)
	me.global_position = open[0]
	enemy.global_position = open[1]
	for u: Unit in m.units:
		if u != me and u != enemy and u.alive:
			u.global_position = m.arena.spawn_points(u.side)[0]
	enemy.aim_dir = (me.global_position - enemy.global_position).normalized()
	# Freeze the target so it can't walk out of the test.
	enemy.set_physics_process(false)
	for ch in enemy.get_children():
		ch.set_physics_process(false)
	await _physics(2)

	# Flash: enemy facing us gets blinded and can't see us.
	me.grenades["flash"] = 1
	m.utility.throw(me, "flash", enemy.global_position.lerp(me.global_position, 0.3))
	enemy.aim_dir = (me.global_position - enemy.global_position).normalized()
	await _physics(int(60 * 1.45))
	_check("flash blinds the enemy looking at it (%.1fs)" % enemy.flash_t, enemy.flash_t > 1.0)
	_check("blinded enemy can't see you", not m.sees(enemy, me))
	await _wait(3)
	_shot("flash")
	enemy.flash_t = 0.0

	# Smoke between us blocks sight.
	me.grenades["smoke"] = 1
	var mid: Vector2 = me.global_position.lerp(enemy.global_position, 0.5)
	m.utility.throw(me, "smoke", mid)
	await _physics(int(60 * 2.4))
	_check("smoke blocks line of sight", not m.has_line_of_sight(me.global_position, enemy.global_position))
	await _wait(3)
	_shot("smoke")
	m.utility.smokes.clear()

	# Frag damages.
	enemy.health = 100.0
	enemy.armor = 0.0
	me.grenades["frag"] = 1
	m.utility.throw(me, "frag", enemy.global_position)
	await _physics(int(60 * 1.7))
	_check("frag hurts (enemy hp %.0f)" % enemy.health, enemy.health < 70.0 or not enemy.alive)

	# Molotov: burns.
	if enemy.alive:
		enemy.health = 100.0
		me.grenades["molotov"] = 1
		m.utility.throw(me, "molotov", enemy.global_position)
		await _physics(int(60 * 1.2))
		print("    fires=%d smokes=%d enemy alive=%s dist to fire=%s" % [m.utility.fires.size(), m.utility.smokes.size(), enemy.alive, str(enemy.global_position.distance_to(m.utility.fires[0].pos)) if not m.utility.fires.is_empty() else "-"])
		_check("molotov makes fire", m.utility.fires.size() >= 1)
		await _physics(30)
		await _wait(2)
		_shot("molotov")
		_check("fire hurts / pushes out (hp %.0f, in fire %s)" % [enemy.health, m.utility.in_fire(enemy.global_position)], enemy.health < 100.0)

	# Bomb escape: a T bot next to a bomb about to blow, no defuse going: it should run.
	m.utility.clear()
	var tb: Unit = _first(func(u: Unit) -> bool: return u.side == m.T and u.alive and u != me and u != enemy)
	if tb != null:
		var site_pos: Vector2 = m.arena.site_center("A")
		tb.global_position = m.arena.cell_center(m.arena.nearest_open(m.arena.world_to_cell(site_pos)))
		if tb.has_bomb:
			tb.has_bomb = false
		m.bomb_carrier = null
		m.bomb_state = m.Bomb.PLANTED
		m.bomb_pos = tb.global_position
		m.bomb_site = "A"
		m.bomb_timer = 7.0
		m.tactics.on_planted("A", m.bomb_pos)
		for u: Unit in m.units:
			if u.side == m.CT and u.alive:
				u.global_position = m.arena.pt("ct_spawn")
		var max_d := 0.0
		for i in int(60 * 6.8):
			await get_tree().physics_frame
			if not tb.alive:
				break
			max_d = maxf(max_d, tb.global_position.distance_to(m.bomb_pos))
		var bc: BotController = null
		for ch in tb.get_children():
			if ch is BotController:
				bc = ch
		print("    tb alive=%s thought='%s' plan='%s' target=%s esc=%s phase=%s order=%s" % [tb.alive, m.tactics.thought.get(tb, ""), bc.plan, bc._target, m.tactics._escaping.has(tb), m.tactics.t_phase, m.tactics.orders.get(tb, {}).get("points", [])])
		_check("T runs out of the blast before it blows (got %.0f / %.0f px)" % [max_d, m.BOMB_RADIUS], max_d > m.BOMB_RADIUS)
	print("GRENADES: %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])

	# Fresh match: bomb dropped on a site, a T bot picks it up and plants right there.
	m.queue_free()
	await _wait(3)
	Game.prepare_quick_match("Dustline")
	Game.pending_match.mode = "test"
	Game.autoplay = true
	m = load(Game.MATCH_SCENE).instantiate()
	add_child(m)
	await _physics(60 * 11)
	var c: Unit = m.bomb_carrier
	var site_c: Vector2 = m.arena.site_center("B")
	c.has_bomb = false
	m.bomb_carrier = null
	m.bomb_state = m.Bomb.DROPPED
	m.bomb_pos = m.arena.cell_center(m.arena.nearest_open(m.arena.world_to_cell(site_c)))
	var fetcher: Unit = _first(func(u: Unit) -> bool: return u.side == m.T and u.alive)
	fetcher.global_position = m.bomb_pos + Vector2(60, 0) if m.has_wall_los(m.bomb_pos, m.bomb_pos + Vector2(60, 0)) else m.bomb_pos
	for u: Unit in m.units:
		if u.side == m.CT and u.alive:
			u.global_position = m.arena.pt("ct_spawn")
			u.health = 1.0
	var picked_at := -1.0
	var max_away := 0.0
	for i in 60 * 12:
		await get_tree().physics_frame
		if picked_at < 0.0 and m.bomb_state == m.Bomb.CARRIED:
			picked_at = m.round_clock
		if picked_at >= 0.0 and m.bomb_carrier != null:
			max_away = maxf(max_away, m.bomb_carrier.global_position.distance_to(m.bomb_pos))
		if m.bomb_state == m.Bomb.PLANTED:
			break
		if picked_at >= 0.0 and m.bomb_carrier != null and i % 60 == 0:
			var cb: BotController = null
			for ch in m.bomb_carrier.get_children():
				if ch is BotController:
					cb = ch
			print("    t=%.0f carrier '%s' plan='%s' target=%s away=%.0f act=%s" % [m.round_clock, m.tactics.thought.get(m.bomb_carrier, ""), cb.plan if cb else "-", cb._target if cb else null, m.bomb_carrier.global_position.distance_to(m.bomb_pos), m.tactics.orders.get(m.bomb_carrier, {}).get("action", "")])
	_check("picked up on site and planted there (wandered %.0f px)" % max_away, m.bomb_state == m.Bomb.PLANTED and max_away < 300.0)
	print("FINAL: %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit()


func _first(pred: Callable) -> Unit:
	for u: Unit in m.units:
		if pred.call(u):
			return u
	return null


## Two open points `dist` apart with a clear line between them.
func _open_lane(dist: float) -> Array:
	var a: Arena = m.arena
	for y in range(4, a.H - 4, 2):
		for x in range(4, a.W - 4, 2):
			var p := a.cell_center(Vector2i(x, y))
			var q := p + Vector2(dist, 0)
			if not a.is_solid(Vector2i(x, y)) and not a.is_solid(a.world_to_cell(q)) and m.has_wall_los(p, q) \
					and m.has_wall_los(p + Vector2(0, 30), q + Vector2(0, 30)) and m.has_wall_los(p - Vector2(0, 30), q - Vector2(0, 30)):
				return [p, q]
	return [Vector2(300, 300), Vector2(800, 300)]


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
