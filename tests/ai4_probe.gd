extends Node
## Bot rounds measuring the 0.19 "more human" AI: trades, crossfire assists,
## listening stops, lurker feints, glances at their favourite angles and into
## buildings, room utility, delayed / missed calls, drops, ninja defuses,
## clutch rounds and tilt.
##   godot --headless --audio-driver Dummy --path . --fixed-fps 60 res://tests/ai4_probe.tscn -- --test [--rounds=12] [--map=Dustline] [--ab=old_ai4]
var fails := 0


func _ready() -> void:
	Game.autoplay = true
	var rounds := 12
	var map_name := "Dustline"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rounds="):
			rounds = int(a.substr(9))
		if a.begins_with("--map="):
			map_name = a.substr(6)
	Game.prepare_quick_match(map_name)
	Game.pending_match.mode = "test"
	var m: Node = load(Game.MATCH_SCENE).instantiate()
	add_child(m)
	for k in BotController.stats:
		BotController.stats[k] = 0
	Tactics.deaths_count = 0
	Tactics.traded_count = 0
	Tactics.calls_missed = 0
	Tactics.calls_made = 0
	Tactics.room_util = 0
	m.drops = 0
	var ninja_rounds := 0
	var ninja_seen := -1
	var clutch := {} # round -> side in a 1vX (X >= 2)
	var last_round := 0
	var window_holds := 0
	for s: String in m.arena.site_info:
		for h: Array in m.arena.site_info[s].ct_holds:
			if m.arena.building_at(m.arena.cell_center(h[0])) != "":
				window_holds += 1
	while m.round_num <= rounds and m.phase != m.Phase.MATCH_OVER:
		await get_tree().physics_frame
		if m.round_num != last_round:
			last_round = m.round_num
		if not m.can_fight():
			continue
		if m.tactics.ninja and ninja_seen != m.round_num:
			ninja_seen = m.round_num
			ninja_rounds += 1
		var alive: Array[int] = m.alive_counts()
		for side in 2:
			if alive[side] == 1 and alive[1 - side] >= 2 and not clutch.has(m.round_num):
				clutch[m.round_num] = side
	var clutch_won := 0
	for i in m.round_log.size():
		var rn: int = i + 1
		if clutch.has(rn) and int(m.round_log[i].get("winner_side", -1)) == int(clutch[rn]):
			clutch_won += 1
	var st: Dictionary = BotController.stats
	var tilt_max := 0.0
	for pd in m.tactics.tilt:
		tilt_max = maxf(tilt_max, float(m.tactics.tilt[pd]))
	var trade_pct := 100.0 * Tactics.traded_count / maxf(1.0, Tactics.deaths_count)
	print("[ai4] %s rounds=%d  trades %d/%d (%.0f%%)  refrags %d  assists %d  listens %d  feints %d  hot-angle glances %d  room glances %d" % [
		map_name, m.round_log.size(), Tactics.traded_count, Tactics.deaths_count, trade_pct, st.refrags, st.assists, st.listens, st.feints, st.hot_glances, st.room_glances])
	print("[ai4] calls made %d missed %d  room utility %d  drops %d  ninja-defuse rounds %d  clutch rounds %d won %d  window holds %d  max tilt %.1f" % [
		Tactics.calls_made, Tactics.calls_missed, Tactics.room_util, m.drops, ninja_rounds, clutch.size(), clutch_won, window_holds, tilt_max])
	if not Game.ab_flag("old_ai4"):
		_check(st.assists > 0, "teammates swing into each other's fights")
		_check(st.listens > 0, "bots stop to listen near contacts")
		_check(Tactics.calls_made > 0, "first calls go out (delayed)")
	print("ai4_probe: %d failure(s)" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		fails += 1
