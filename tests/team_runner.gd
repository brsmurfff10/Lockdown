extends Node
## Team-play scenario tests. Run:
##   godot --headless --path . --fixed-fps 60 res://tests/team_runner.tscn -- --test


func _ready() -> void:
	Game.autoplay = true
	await _reload_cover()
	await _bomb_spotted_call()
	await _entry_spacing()
	await _outnumbered_fallback()
	await _dropped_bomb_watch()
	await _t_recover_bomb()
	await _ct_close_in_on_bomb()
	get_tree().quit()


func _new_match() -> Node:
	Game.prepare_quick_match()
	Game.pending_match.mode = "test"
	var m: Node = load(Game.MATCH_SCENE).instantiate()
	add_child(m)
	while not m.is_live():
		await get_tree().physics_frame
	return m


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _side(m: Node, side: int) -> Array:
	return m.units.filter(func(u: Unit) -> bool: return u.side == side and u.alive)


func _ctrl(u: Unit) -> BotController:
	for c in u.get_children():
		if c is BotController:
			return c
	return null


func _park_others(m: Node, keep: Array) -> void:
	for u in m.units:
		if not keep.has(u):
			u.global_position = Vector2(-5000, -5000)
			u.set_physics_process(false)
			var c := _ctrl(u)
			if c != null:
				c.set_physics_process(false)


func _result(name: String, ok: bool, detail: String) -> void:
	print("[%s] %s  %s" % [name, detail, "PASS" if ok else "FAIL"])


func _reload_cover() -> void:
	var m := await _new_match()
	var cts := _side(m, 1)
	var a: Unit = cts[0]
	var b: Unit = cts[1]
	var t: Unit = _side(m, 0)[0]
	_park_others(m, [a, b])
	a.global_position = m.arena.pt(Vector2i(40, 16))
	b.global_position = m.arena.pt(Vector2i(41, 17))
	# Team knows a T is in mid.
	m.tactics.seen_by[1][t] = {"pos": m.arena.pt(Vector2i(25, 17)), "time": m.round_clock}
	t.global_position = Vector2(-4000, -4000)
	await _frames(5)
	a.weapon.ammo = 3
	a.start_reload()
	await _frames(3)
	_result("reload cover", _ctrl(b).plan == "cover", "teammate plan while A reloads: '%s'" % _ctrl(b).plan)
	m.queue_free()
	await _frames(2)


func _bomb_spotted_call() -> void:
	var m := await _new_match()
	var carrier: Unit = m.bomb_carrier
	var ct: Unit = _side(m, 1)[0]
	carrier.global_position = m.arena.pt(Vector2i(28, 28)) # Tunnels -> threatens B.
	m.tactics.on_spotted(ct, carrier)
	_result("bomb spotted", m.tactics.ct_call_site == "B" and m.tactics.ct_call_strength >= 3,
		"call site %s strength %d" % [m.tactics.ct_call_site, m.tactics.ct_call_strength])
	m.queue_free()
	await _frames(2)


func _entry_spacing() -> void:
	var m := await _new_match()
	var tac: Tactics = m.tactics
	# Force an A execute with two players on Long.
	var ts := _side(m, 0)
	var bots := ts.filter(func(u: Unit) -> bool: return not u.data.is_user)
	var lead: Unit = bots[0]
	var follower: Unit = bots[1]
	for u in ts:
		tac.t_route[u] = "B.main"
		u.has_bomb = false
	tac.t_route[lead] = "A.main"
	tac.t_route[follower] = "A.main"
	tac.t_lurker = null
	lead.data.role = "Entry"
	follower.data.role = "Support"
	tac.t_site = "A"
	tac.t_phase = "execute"
	tac.orders.clear()
	lead.global_position = m.arena.pt(Vector2i(29, 4))
	follower.global_position = m.arena.pt(Vector2i(28, 5))
	tac.orders[follower] = tac._t_order(follower)
	var waits_before: bool = tac.should_wait(follower)
	print("   lead chosen: %s (expected %s)" % [tac.orders[follower].get("follow").data.player_name if tac.orders[follower].get("follow") != null else "none", lead.data.player_name])
	lead.global_position = m.arena.pt(Vector2i(40, 8)) # Lead is through.
	var waits_after: bool = tac.should_wait(follower)
	_result("entry spacing", waits_before and not waits_after, "follower waits at entrance=%s, after lead is in=%s" % [waits_before, waits_after])
	m.queue_free()
	await _frames(2)


func _outnumbered_fallback() -> void:
	# Falling back is a decision roll (~85-90% for a 95 Decision Making player): 3 trials.
	var fell := 0
	for trial in 3:
		var m := await _new_match()
		var tac: Tactics = m.tactics
		var cts := _side(m, 1)
		var anchor: Unit = null
		for u in cts:
			if tac.ct_home[u].site == "B":
				anchor = u
		for u in cts:
			if u != anchor and tac.ct_home[u].site == "B":
				tac.ct_home[u] = {"site": "A", "pos": m.arena.pt(Vector2i(45, 4)), "look": m.arena.pt("a_long_entry")}
		for k: String in PlayerData.STAT_KEYS:
			anchor.data.set_stat(k, 95)
		tac.ct_state[anchor] = "hold" # (Aggressive setups can send the anchor out for info.)
		var ts := _side(m, 0)
		for i in 3:
			tac.seen_by[1][ts[i]] = {"pos": m.arena.pt(Vector2i(20 + i, 28)), "time": m.round_clock}
		tac._tick = 0.0
		await _frames(3)
		if tac.ct_state.get(anchor, "") == "fallback":
			fell += 1
		m.queue_free()
		await _frames(2)
	_result("outnumbered fallback", fell >= 2, "lone B anchor fell back in %d/3 trials" % fell)


func _dropped_bomb_watch() -> void:
	var m := await _new_match()
	var carrier: Unit = m.bomb_carrier
	var ct: Unit = _side(m, 1)[0]
	_park_others(m, [ct, carrier])
	ct.global_position = m.arena.pt(Vector2i(38, 16))
	carrier.global_position = m.arena.pt(Vector2i(28, 16))
	carrier.take_damage(999, null) # Drops the bomb in mid, in view of the CT.
	m.tactics._tick = 0.0
	await _frames(3)
	# Alone, the CT that saw it closes in on it (contest) rather than just watching.
	var plays: bool = m.tactics.ct_watch == ct or m.tactics.ct_contest.has(ct)
	_result("dropped bomb watch", plays, "watcher: %s, contesting: %s" % [m.tactics.ct_watch.data.player_name if m.tactics.ct_watch != null else "none", m.tactics.ct_contest.has(ct)])
	m.queue_free()
	await _frames(2)


func _t_recover_bomb() -> void:
	var m := await _new_match()
	var carrier: Unit = m.bomb_carrier
	var ts := _side(m, 0).filter(func(u: Unit) -> bool: return u != carrier and not u.data.is_user)
	var mate: Unit = ts[0]
	_park_others(m, [carrier, mate])
	carrier.global_position = m.arena.pt("mid_center")
	mate.global_position = m.arena.pt("mid_entry")
	carrier.take_damage(999, null)
	m.tactics._tick = 0.0
	var got := false
	for i in 60 * 12:
		await get_tree().physics_frame
		if m.bomb_state == m.Bomb.CARRIED and m.bomb_carrier == mate:
			got = true
			break
	_result("T recovers dropped bomb", got, "teammate picked it up: %s (fetcher %s)" % [got, m.tactics.t_fetcher.data.player_name if m.tactics.t_fetcher != null else "none"])
	m.queue_free()
	await _frames(2)


func _ct_close_in_on_bomb() -> void:
	var m := await _new_match()
	var carrier: Unit = m.bomb_carrier
	var cts := _side(m, 1).filter(func(u: Unit) -> bool: return not u.data.is_user)
	var a: Unit = cts[0]
	_park_others(m, [carrier, a])
	carrier.global_position = m.arena.pt("mid_center")
	a.global_position = m.arena.pt("mid_hold")
	var d0: float = a.global_position.distance_to(carrier.global_position)
	carrier.take_damage(999, a) # The CT got the carrier: they know where the bomb is.
	m.tactics._tick = 0.0
	var closed := false
	for i in 60 * 10:
		await get_tree().physics_frame
		if m.tactics.ct_state.get(a, "") == "contest" and a.global_position.distance_to(m.bomb_pos) < minf(260.0, d0 - 60.0):
			closed = true
			break
	_result("CT closes in on dropped bomb", closed, "state=%s dist %.0f -> %.0f" % [m.tactics.ct_state.get(a, ""), d0, a.global_position.distance_to(m.bomb_pos)])
	m.queue_free()
	await _frames(2)
