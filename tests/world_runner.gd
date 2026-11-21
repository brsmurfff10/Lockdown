extends Node
## Headless manager-career simulation over two seasons: leagues, playoffs,
## promotion/relegation, contracts, windows, AI finances, save/load. Run:
##   godot --headless --path . res://tests/world_runner.tscn -- --test


func _ready() -> void:
	var w := World.new()
	w.new_world("manager")
	var bottom := w.league_teams(3)
	w.take_over(w.team_index(bottom[0]), "Test Org", "TST", Color.CYAN)
	var ut := w.user_team()
	print("Start: %s in %s (rating %d), $%s, %d teams, %d free agents" % [ut.team_name, w.league_name(ut), ut.rating(), World._fmt(w.money), w.teams.size(), w.free_agents.size()])
	var names := {}
	var total := 0
	for t in w.teams:
		for p in t.roster:
			names[p.player_name] = true
			total += 1
	for p in w.free_agents:
		names[p.player_name] = true
		total += 1
	print("Players: %d, unique names: %d. Leagues: %s" % [total, names.size(), range(4).map(func(l: int) -> String: return "%s avg %d" % [World.LEAGUES[l].short, _avg(w, l)])])
	print("Week 1 window: %s | bid: %s" % [w.window_text(), w.make_offer(w.market_players()[60])])
	var leagues_at_start := {}
	for t in w.teams:
		leagues_at_start[t.team_name] = t.league
	var user_matches := 0
	var draws := 0
	for wk in 48:
		for t in w.tournaments:
			if w.can_enroll(t) == "":
				w.enroll(t)
		if w.week == 6 and w.season == 1:
			print("Week 6 window: %s | sell: %s" % [w.window_text(), w.sell_player(w.user_team().roster[w.user_team().roster.size() - 1])])
		var res := w.advance_week()
		while res != "":
			if res == "sacked":
				print("Sacked at S%d W%d: taking %s" % [w.season, w.week, w.teams[int(w.job_offers[0].team)].team_name])
				w.accept_job(0)
			elif w.sim_user_match().is_empty():
				w.forfeit_user_match() # Not enough fit players.
			else:
				user_matches += 1
			res = w.advance_week()
		if wk == 20:
			var json := JSON.stringify(w.to_dict())
			w = World.from_dict(JSON.parse_string(json))
			print("Save/load at week %d: %d KB, %d league fixtures this week, %d brackets" % [w.week, json.length() / 1024, w.week_matches.size(), w.tournaments.size()])
	ut = w.user_team()
	var moved := 0
	for t in w.teams:
		if t.league != leagues_at_start.get(t.team_name, t.league):
			moved += 1
	print("After 2 seasons: S%d W%d, $%s, %s, world #%d, user matches %d, teams that changed league: %d" % [w.season, w.week, World._fmt(w.money), w.league_name(ut), w.world_rank(ut), user_matches, moved])
	print("Leagues now: %s" % [range(4).map(func(l: int) -> String: return "%s avg %d" % [World.LEAGUES[l].short, _avg(w, l)])])
	var broke := w.teams.filter(func(t: TeamData) -> bool: return t.money < 0).size()
	print("AI clubs in debt: %d / %d" % [broke, w.teams.size()])
	var kinds := {}
	for n in w.news:
		for key in ["PROMOTED", "RELEGATED", "TRANSFER", "signed free agent", "Contract expired", "retires", "WIN", "Playoffs"]:
			if key in n:
				kinds[key] = kinds.get(key, 0) + 1
	print("News mix (last 150): ", kinds)
	get_tree().quit()


func _avg(w: World, l: int) -> int:
	var s := 0
	var lt := w.league_teams(l)
	for t in lt:
		s += t.rating()
	return s / maxi(1, lt.size())
