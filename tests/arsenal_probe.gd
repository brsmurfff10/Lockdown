extends Node
## New gameplay features: the arsenal + buy menu (prices, side locks, pistol slot,
## sell-back), overtime, round recording, replays, kill-cam and highlights.
## Run:  godot --path . res://tests/arsenal_probe.tscn -- --test --windowed --out=<dir>

var out := "user://arsenal"
var m: Node
var fails := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = Vector2i(1600, 900)

	# --- 1. Weapon table ---
	var ok_table := true
	for wid: int in WeaponData.ALL:
		var w := WeaponData.by_id(wid)
		if w.weapon_name == "" or w.price <= 0 or w.ammo != w.mag_size:
			ok_table = false
	_check("every weapon has a name, price and full mag", ok_table)
	_check("21 guns", WeaponData.ALL.size() == 21)
	_check("SMGs pay more per kill than rifles, the big sniper least",
		WeaponData.reward_of(WeaponData.HORNET) > WeaponData.reward_of(WeaponData.RAPTOR)
		and WeaponData.reward_of(WeaponData.LONGBOW) < WeaponData.reward_of(WeaponData.RAPTOR)
		and WeaponData.reward_of(WeaponData.BREACHER) > WeaponData.reward_of(WeaponData.HORNET))

	# --- 2. Buying ---
	Game.prepare_quick_match("Dustline")
	Game.pending_match.mode = "test"
	m = load(Game.MATCH_SCENE).instantiate()
	add_child(m)
	await _wait(5)
	var me: Unit = m.user_unit
	var lo: Dictionary = m.loadouts[me.data]
	lo.money = 16000
	var mine_rifle := WeaponData.pick(me.side, WeaponData.RAPTOR, WeaponData.GUARDIAN)
	var their_rifle := WeaponData.pick(me.side, WeaponData.GUARDIAN, WeaponData.RAPTOR)
	_check("starter pistol matches your side", me.pistol.id == WeaponData.starter(me.side))
	_check("can't buy the other side's rifle", not m._purchase(me, m.weapon_item(their_rifle)))
	_check("buy your side's rifle", m._purchase(me, m.weapon_item(mine_rifle)) and me.primary.id == mine_rifle)
	_check("money taken", int(lo.money) == 16000 - WeaponData.price_of(mine_rifle))
	_check("can't buy what you own", not m._purchase(me, m.weapon_item(mine_rifle)))
	_check("pistol slot: buy the Magnum", m._purchase(me, m.weapon_item(WeaponData.MAGNUM)) and me.pistol.id == WeaponData.MAGNUM and me.primary.id == mine_rifle)
	_check("sell the Magnum back: starter returns, full refund", m._sell(me, m.weapon_item(WeaponData.MAGNUM))
		and me.pistol.id == WeaponData.starter(me.side) and int(lo.money) == 16000 - WeaponData.price_of(mine_rifle))
	_check("kevlar + helmet", m._purchase(me, "helmet") and me.armor == 100.0 and me.helmet)
	_check("helmet over kevlar is cheaper", m.item_price(me, "helmet") == m.HELMET_UPGRADE)
	m._purchase(me, m.weapon_item(WeaponData.LONGBOW))
	_check("sniper replaces the rifle", me.primary.id == WeaponData.LONGBOW)
	_check("selling the sniper gives the rifle back", m._sell(me, m.weapon_item(WeaponData.LONGBOW)) and me.primary.id == mine_rifle)
	_check("kit is CT only", (m.item_block(me, "kit") == "CT ONLY") == (me.side == m.T))
	m._purchase(me, "flash")
	m._purchase(me, "flash")
	_check("sell one flash back", m._sell(me, "flash") and int(me.grenades.get("flash", 0)) == 1)
	# Bots bought something on the pistol round.
	var bot_gear := 0
	for u: Unit in m.units:
		if u != me and (u.armor > 0.0 or u.pistol.id != WeaponData.starter(u.side) or u.has_kit or not u.grenades.is_empty()):
			bot_gear += 1
	_check("bots buy on the pistol round", bot_gear >= 5)
	# Buy menu with the rifles column selected via number keys.
	m.buy_menu_open = true
	m.hud.reset_buy_nav()
	_press(KEY_3)
	await _wait(4)
	_check("number key 3 selects the rifles column", m.hud._buy_cat == 2)
	_shot("buy_menu")
	_press(KEY_0)
	await _wait(2)
	_check("0 goes back to the categories", m.hud._buy_cat == -1)
	_press(KEY_1)
	var money_before := int(lo.money)
	_press(KEY_6) # Pistols column item 6 = Magnum.
	await _wait(2)
	_check("1 then 6 buys the Magnum", me.pistol.id == WeaponData.MAGNUM and int(lo.money) == money_before - 700)
	_press(KEY_ESCAPE)
	await _wait(3)
	_check("Esc closes the buy menu (and doesn't leave)", not m.buy_menu_open and is_instance_valid(m) and m.is_inside_tree())

	# --- 3. Bot full buys (simulate a rich team) ---
	var plans := []
	for p: PlayerData in m.loadouts:
		m.loadouts[p].money = 9000
	m.round_num = 3
	plans = [m.team_buy_plan(0), m.team_buy_plan(1)]
	_check("rich teams full buy", plans == ["full", "full"])
	for p: PlayerData in m.loadouts:
		m.loadouts[p].money = 1200
		m.loadouts[p].primary = -1
	_check("broke teams eco", m.team_buy_plan(0) == "eco")
	m.round_num = 1

	# --- 4. Overtime ---
	_check("6-4 decided", m.match_decided([6, 4]))
	_check("5-5 not decided (overtime)", not m.match_decided([5, 5]))
	_check("OT: 8-6 decided, 7-7 not", m.match_decided([8, 6]) and not m.match_decided([7, 7]))
	_check("second OT: 10-8 decided, 9-8 not", m.match_decided([10, 8]) and not m.match_decided([9, 8]))
	await _physics(60 * 11) # Into the live round.
	m.score.assign([5, 4])
	m.round_num = 10
	var sides_before: Array = m.sides.duplicate()
	m._end_round(1 if m.score[1] == 4 else 0, "Test")
	_check("5-5 after round 10 sends us to overtime", m._ot_pending == 1 and not m._match_over_pending)
	m._after_post_round()
	await _wait(5)
	_check("overtime pause shows OVERTIME", m.hud._banner.text.begins_with("OVERTIME"))
	_check("OT start money $10,000", int(m.loadouts[me.data].money) == m.OT_MONEY)
	_check("sides stay for the first OT half", m.sides == sides_before)
	_shot("overtime_banner")
	while m.phase == m.Phase.HALFTIME:
		await get_tree().physics_frame
	await _wait(3)
	_check("round 11 is overtime 1", m.round_num == 11 and m.is_overtime() and m.hud._banner.text.begins_with("OVERTIME 1"))
	m.buy_menu_open = false
	await _wait(3)
	_shot("overtime_round")

	# --- 5. Recording + replay ---
	Engine.time_scale = 4.0
	var guard := 0
	while m.replay.rounds.size() < 2 and guard < 60 * 60 * 3 and m.phase != m.Phase.MATCH_OVER:
		await get_tree().physics_frame
		guard += 1
	Engine.time_scale = 1.0
	_check("rounds get recorded", m.replay.rounds.size() >= 2)
	var rd: Dictionary = m.replay.rounds[-1]
	_check("timeline sampled at ~20 Hz", rd.frames.size() > 20 and float(rd.end) > 1.0 and rd.frames.size() / maxf(float(rd.end), 1.0) > 12.0)
	var shots := 0
	var kills := 0
	for ev: Dictionary in rd.events:
		if ev.k == "shot":
			shots += 1
		elif ev.k == "kill":
			kills += 1
	_check("shots and kills recorded", shots > 0 and kills > 0)
	while m.phase != m.Phase.BUY:
		await get_tree().physics_frame
	m.replay.play_round(m.replay.rounds.size() - 1)
	await _wait(3)
	_check("replay opens and pauses the match", m.replay.active and get_tree().paused)
	m.replay.command("seek_frac", 0.5)
	m.replay.command("faster")
	await _wait(20)
	_check("replay seeks + speeds up", m.replay.speed == 2.0 and m.replay.t > float(rd.end) * 0.4)
	_shot("replay_round")
	m.replay.command("overview")
	await _wait(25)
	_shot("replay_overview")
	m.replay.close()
	await _wait(3)
	_check("replay closes and unpauses", not m.replay.active and not get_tree().paused)

	# --- 6. Kill-cam (forced: a bot "kills" you) ---
	while m.phase != m.Phase.LIVE:
		await get_tree().physics_frame
	await _physics(60 * 6)
	me = m.user_unit # Units are respawned every round.
	var killer: Unit = null
	for u: Unit in m.units:
		if u.side != me.side and u.alive:
			killer = u
			break
	if me.alive and killer != null:
		m.killcam_enabled = true
		me.take_damage(500.0, killer)
		await _wait(4)
		_check("kill-cam starts when you die", m.replay.active and m.replay.kind == "killcam" and m.replay.follow == m.replay._idx[killer])
		await _wait(30)
		_shot("killcam")
		_press(KEY_SPACE)
		await _wait(4)
		_check("Space skips the kill-cam", not m.replay.active and not get_tree().paused)
		m.killcam_enabled = false
	else:
		_check("kill-cam (skipped: you were already dead)", true)

	# --- 7. Highlights: give someone a 3k in a recorded round ---
	var rd0: Dictionary = m.replay.rounds[0]
	var hero := 0
	var tt := 5.0
	for v in range(5, 8):
		rd0.events.append({"k": "kill", "t": tt, "i": hero, "v": v % rd0.units.size(), "w": "Test", "tk": false, "post": false})
		tt += 2.0
	rd0.events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.t) < float(b.t))
	m.replay._clutch = [{}, {}]
	rd0.moments = m.replay._compute_moments(rd0)
	var counts: Dictionary = m.highlight_counts()
	var hero_pd: PlayerData = rd0.units[hero].pd
	_check("a 3k counts as a highlight", int(counts.get(hero_pd, 0)) >= 1)
	_check("every starter has a highlights entry", counts.size() == 10)

	# --- 8. Sim the rest: never a draw; results carry highlights ---
	m._sim_rest_of_match()
	await _wait(5)
	_check("match ends with a winner", m.phase == m.Phase.MATCH_OVER and m.score[0] != m.score[1])
	_check("overtime rounds counted", m.rounds_played() > 10)
	var res: Dictionary = m.match_result()
	_check("result has highlights {PlayerData: int}", res.has("highlights") and (res.highlights as Dictionary).size() == 10)
	await _wait(10)
	_shot("results_overtime")
	_check("highlight reel plays", m.replay.play_highlights(null))
	await _wait(30)
	_shot("highlights")
	m.replay.close()
	await _wait(3)
	print("ARSENAL: %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit()


func _press(key: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	ev.keycode = key
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := ev.duplicate()
	up.pressed = false
	Input.parse_input_event(up)


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
