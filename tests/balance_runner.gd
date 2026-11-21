extends Node
## Bot-only matches to check T/CT round balance. Run with:
##   godot --headless --path . --fixed-fps 60 res://tests/balance_runner.tscn -- --test [--matches=N] [--equal]
const MATCHES := 2


func _ready() -> void:
	Game.autoplay = true
	var probe := Arena.new()
	add_child(probe)
	print("ARENA CHECK: ", probe.validate())
	probe.queue_free()
	var tally := {"T": 0, "CT": 0}
	var reasons := {}
	var buys := {}
	var n_matches := MATCHES
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--matches="):
			n_matches = int(a.substr(10))
	for i in n_matches:
		Game.prepare_quick_match()
		Game.pending_match.mode = "test"
		if "--equal" in OS.get_cmdline_user_args():
			# Identical 60-rated teams: isolates T-side vs CT-side balance.
			for team: TeamData in Game.pending_match.teams:
				for p in team.roster:
					for k: String in PlayerData.STAT_KEYS:
						p.set_stat(k, 60.0)
		var m: Node = load(Game.MATCH_SCENE).instantiate()
		add_child(m)
		var last_round := -1
		while m.phase != m.Phase.MATCH_OVER:
			await get_tree().physics_frame
			if m.round_num != last_round and m.phase == m.Phase.LIVE:
				last_round = m.round_num
				for u: Unit in m.units:
					var key: String = u.primary.weapon_name if u.primary != null else u.pistol.weapon_name
					buys[key] = int(buys.get(key, 0)) + 1
		print("  ratings %s %d vs %s %d" % [m.teams[0].team_name, m.teams[0].rating(), m.teams[1].team_name, m.teams[1].rating()])
		for t in 2:
			var k := 0
			for p: PlayerData in m.starters[t]:
				k += m.stats[p].kills
			print("    team %d kills %d" % [t, k])
		for r: Dictionary in m.round_log:
			print("    %-22s %-3s %-15s t=%3.0fs plant@%3.0f alive T/CT=%s" % [r.strategy, ["T", "CT"][r.winner_side], r.reason, r.clock, r.plant_clock, r.alive])
			tally["T" if r.winner_side == 0 else "CT"] += 1
			reasons[r.reason] = reasons.get(r.reason, 0) + 1
		m.queue_free()
		await get_tree().process_frame
	print("GUNS CARRIED (per player-round): ", buys)
	var bs := BotController.stats
	print("AI METRICS: trades %d/%d deaths (%.0f%%), fakes bitten %d/%d, aim at believed spot %d vs true position %d, heard-reacts %d, flash-peeks %d, dry peeks %d, refrags %d, whiffs %d, panic sprays %d, overpeeks %d, bad reloads %d, lost bomb timer %d" % [
		Tactics.traded_count, Tactics.deaths_count, 100.0 * Tactics.traded_count / maxi(1, Tactics.deaths_count),
		Tactics.fake_bitten, Tactics.fake_rounds, bs.aim_belief, bs.aim_true, bs.heard_reacts, bs.flash_waits, bs.dry_peeks,
		bs.refrags, bs.whiffs, bs.panic_sprays, bs.overpeeks, bs.bad_reloads, bs.bomb_blind])
	var total := maxi(1, int(tally.T) + int(tally.CT))
	print("BALANCE: ", tally, "  T win %.0f%%" % (100.0 * tally.T / total), "  reasons: ", reasons)
	get_tree().quit()
