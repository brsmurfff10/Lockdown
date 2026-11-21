extends Node
## Long My Player run: a whole career, answering the inbox at random, until
## forced retirement. Prints one line per season.
## Run:  godot --headless --path . res://tests/my_player_seasons.tscn -- --test


func _ready() -> void:
	Game.end_career()
	Game.create_my_player("Lifer", "AWPer")
	Game.start_career()
	var w := Game.pworld
	var p := w.user_player
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var last_season := w.season
	var guard := 0
	while not w.retired and guard < 30 * World.SEASON_WEEKS:
		guard += 1
		for m in w.inbox:
			if not bool(m.done):
				w.resolve_msg(m, rng.randi() % (m.options as Array).size())
		if not w.trained_this_week and p.available():
			w.train_user(PlayerData.STAT_KEYS[rng.randi() % PlayerData.STAT_KEYS.size()], ["Light", "Normal", "Hard"][rng.randi() % 3])
		if w.wallet > w.setup_cost() * 2 and w.setup_cost() > 0:
			w.buy_setup()
		if w.allstar_pending():
			w.sim_allstar()
		if w.offers.size() > 0 and (w.free_agency or (w.window_open() and rng.randf() < 0.3)):
			w.accept_offer(0)
		var r := w.advance_week()
		if r == "play_match":
			w.sim_user_match()
			r = w.advance_week()
		if w.season != last_season:
			last_season = w.season
			var tl: Dictionary = w.timeline[w.timeline.size() - 1] if not w.timeline.is_empty() else {}
			print("S%d  age %d  RTG %d  %s (%s)  $%d/wk  wallet %s  fans %s  trust %d  trophies %d  awards %d  perks %d" % [w.season, p.age, p.rating(),
				w.user_team().team_name, World.LEAGUES[w.user_team().league].short, p.salary, UI.money_text(w.wallet), World.fame_text(w.fame),
				int(w.coach_trust), w.trophy_count(1), w.awards.size(), w.perks.size()])
	print("Retired: %s  age %d  legacy %s (%d)  clubs in timeline %d  rivals %d" % [w.retired, p.age, w.legacy.get("tier", "?"), int(w.legacy.get("score", 0)), w.timeline.size(), w.rivals.size()])
	Game.end_career()
	get_tree().quit()
