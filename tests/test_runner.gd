extends Node
## Headless smoke test of the My Player career. Run with:
##   godot --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test
## Creates a player, starts a career in the 64-team world, trains, sims a
## season+, round-trips the save, then plays one bot-controlled match.


func _ready() -> void:
	Game.end_career()
	Game.create_my_player("Tester", "Rifler")
	Game.start_career()
	var w := Game.pworld
	var p := Game.my_player
	print("Start: %s rating %d on %s (%s)" % [p.player_name, p.rating(), w.user_team().team_name, w.league_name(w.user_team())])
	var gains := []
	for i in 6:
		w.trained_this_week = false
		gains.append("%+.2f" % Game.train("aim"))
	print("6 training sessions (aim): ", gains)
	for i in 30:
		var r := w.advance_week()
		if r == "free_agency":
			print("Free agency: %d offers" % w.offers.size())
			w.accept_offer(0)
			r = w.advance_week()
		if r == "play_match":
			if w.sim_user_match().is_empty():
				w.forfeit_user_match()
			w.advance_week()
	print("After ~30 weeks: season %d week %d, rating %.1f, age %d, team %s (%s)" % [w.season, w.week, p.rating_exact(), p.age, w.user_team().team_name, w.league_name(w.user_team())])
	for n in w.news.slice(maxi(0, w.news.size() - 10)):
		print("  NEWS: ", n)
	Game.save_player_career()
	Game.load_my_player()
	Game.load_player_career()
	print("Reloaded: active=%s team=%s rating=%.1f same object=%s" % [Game.career_active, Game.pworld.user_team().team_name, Game.my_player.rating_exact(), Game.my_player == Game.pworld.user_player])
	# Find a week with a match and play it.
	var guard := 0
	while Game.pworld.user_match_this_week().is_empty() and guard < 30:
		Game.pworld.advance_week()
		guard += 1
	Game.autoplay = true
	print("Playing match: ", Game.prepare_player_match())
	Game.goto(Game.MATCH_SCENE)
