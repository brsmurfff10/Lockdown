extends Node
## Plays full bot rounds and measures the team AI:
##   godot --headless --path . --fixed-fps 60 res://tests/ai_probe.tscn -- --test --map=Dustline [--rounds=8]

var m: Node
var stats := {"rounds": 0, "plants": 0, "clear_at_plant": [], "postplant_exposed": 0, "postplant_checks": 0,
	"saves_t": 0, "saves_ct": 0, "kept_guns": 0, "rotations": 0, "rot_gather": 0, "info": 0,
	"postround_kills": 0, "stuck_secs": 0.0, "retake_clear_wait": 0}
var _stuck := {}
var _was_saving := {}
var _rot_seen := {}
var _info_seen := false
var _gather_seen := {}
var _postplant_sampled := false


func _ready() -> void:
	Game.autoplay = true
	var rounds := 8
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rounds="):
			rounds = int(a.substr(9))
	Game.prepare_quick_match(Game._default_map())
	Game.pending_match.mode = "test"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mismatch="):
			var r := a.substr(11).split(",")
			for ti in 2:
				for p in Game.pending_match.teams[ti].roster:
					for k: String in PlayerData.STAT_KEYS:
						p.set_stat(k, float(r[ti]))
	if "--equal" in OS.get_cmdline_user_args():
		for team: TeamData in Game.pending_match.teams:
			for p in team.roster:
				for k: String in PlayerData.STAT_KEYS:
					p.set_stat(k, 60.0)
	m = load(Game.MATCH_SCENE).instantiate()
	add_child(m)

	var last_round := 0
	var post_kills_before := 0
	while m.round_num <= rounds and m.phase != m.Phase.MATCH_OVER:
		await get_tree().physics_frame
		if m.round_num != last_round:
			last_round = m.round_num
			_rot_seen.clear()
			_was_saving.clear()
			_info_seen = false
			_gather_seen.clear()
			_postplant_sampled = false
		_sample(1.0 / 60.0)
		if "--trace" in OS.get_cmdline_user_args() and m.phase == m.Phase.LIVE and int(m.round_clock * 60.0) % 600 == 0:
			var line := "  R%d t=%3.0f left=%3.0f bomb=%d |" % [m.round_num, m.round_clock, m.round_time_left, m.bomb_state]
			for u: Unit in m.units:
				if u.alive:
					var bc: BotController = null
					for c in u.get_children():
						if c is BotController:
							bc = c
					line += " %s%s[%s|%s|%s]" % ["T" if u.side == 0 else "C", u.data.player_name.substr(0, 4), m.arena.threat_at(u.global_position), m.tactics.debug_label(u), bc.plan if bc else ""]
			print(line)
		if m.phase == m.Phase.POST_ROUND and m.phase_timer < 0.25 and m.phase_timer > 0.2:
			# About to end: who kept their guns?
			for u: Unit in m.units:
				if u.alive and u.primary != null and m.tactics.is_saving(u):
					stats.kept_guns += 1
	stats.rounds = m.round_log.size()
	stats.postround_kills = m.postround_kills
	var avg_clear := 0.0
	for c in stats.clear_at_plant:
		avg_clear += c
	avg_clear /= maxf(1.0, stats.clear_at_plant.size())
	print("[ai] map=%s rounds=%d score %d-%d (team ratings %d vs %d)" % [m.arena.map_name, stats.rounds, m.score[0], m.score[1], m.teams[0].rating(), m.teams[1].rating()])
	var kills := [0, 0]
	for p: PlayerData in m.stats:
		for ti in 2:
			if m.starters[ti].has(p):
				kills[ti] += m.stats[p].kills
	print("[ai] kills %d vs %d" % [kills[0], kills[1]])
	for r: Dictionary in m.round_log:
		print("   %s" % r)
	print("[ai] plants %d, angles cleared at plant %.0f%%, post-plant Ts exposed to CT approach %d/%d" % [stats.plants, avg_clear * 100.0, stats.postplant_exposed, stats.postplant_checks])
	print("[ai] T saves %d, CT saves %d, savers kept guns %d" % [stats.saves_t, stats.saves_ct, stats.kept_guns])
	print("[ai] CT rotations %d (gathered first %d), info plays %d" % [stats.rotations, stats.rot_gather, stats.info])
	print("[ai] post-round kills %d, total stuck time %.1fs" % [stats.postround_kills, stats.stuck_secs])
	print("[ai] grenades thrown %s" % str(m.utility.thrown))
	print("[ai] contact plans %s" % str(BotController.plan_counts))
	var bs := BotController.stats
	print("[ai] bot habits: flash dodges %d, pistol swaps %d, bad reloads %d, cover reloads %d, smoke sprays %d" % [bs.flash_dodges, bs.pistol_swaps, bs.bad_reloads, bs.hold_cover_reloads, int(BotController.plan_counts.get("spam", 0))])
	print("[ai] strats %s" % str(m.tactics.hist))
	get_tree().quit()


func _sample(dt: float) -> void:
	var t = m.tactics
	for u: Unit in m.units:
		if not u.alive:
			continue
		# Stuck: trying to move but not moving, outside fights.
		var trying := u.move_input.length() > 0.3
		if trying and u.velocity.length() < 15.0:
			_stuck[u] = _stuck.get(u, 0.0) + dt
			if _stuck[u] > 1.5:
				stats.stuck_secs += dt
		else:
			_stuck[u] = 0.0
		if t.is_saving(u) and not _was_saving.has(u):
			_was_saving[u] = true
			if m.phase == m.Phase.LIVE:
				if u.side == 0:
					stats.saves_t += 1
				else:
					stats.saves_ct += 1
		var st: String = t.ct_state.get(u, "")
		if st == "rotate" and not _rot_seen.has(u):
			_rot_seen[u] = true
			stats.rotations += 1
		if st == "info" and not _info_seen:
			_info_seen = true
			stats.info += 1
	for site in t.ct_rot_go:
		if t.ct_rot_go[site] and not _gather_seen.has(site):
			_gather_seen[site] = true
			stats.rot_gather += 1
	if m.bomb_state == m.Bomb.PLANTED and not _postplant_sampled and m.bomb_timer < m.BOMB_TIMER - 8.0:
		_postplant_sampled = true
		stats.plants += 1
		var angles: Array = m.arena.site_angles.get(m.bomb_site, [])
		var done := 0
		for a in angles:
			if t.cleared[0].has(a):
				done += 1
		stats.clear_at_plant.append(float(done) / maxf(1.0, angles.size()))
		var approaches: Array = []
		for s: String in m.arena.site_info[m.bomb_site].retake:
			approaches.append(m.arena.pt(s))
		for u: Unit in m.units:
			if u.alive and u.side == 0:
				stats.postplant_checks += 1
				for p: Vector2 in approaches:
					if m.has_line_of_sight(p, u.global_position):
						stats.postplant_exposed += 1
						break
