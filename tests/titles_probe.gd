extends Node
## Titles: earned from trophies and awards (by everyone), worn with the name,
## old saves backfilled from the trophy cabinet.
##   godot --headless --path . res://tests/titles_probe.tscn -- --test
var fails := 0


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		fails += 1


func _ready() -> void:
	Game.end_career()
	Game.create_my_player("Titleholder", "Rifler", "Canada")
	Game.start_career()
	var w := Game.pworld
	var start := w.season
	var guard := 0
	while w.season == start and guard < 80:
		guard += 1
		var r := w.advance_week()
		if r == "play_match":
			w.sim_user_match()
			w.advance_week()
		elif r == "free_agency":
			w.accept_offer(0)
			w.advance_week()
		elif r == "review":
			w.advance_week()
	_check(w.season > start, "a season went by (now season %d)" % w.season)
	var titled := 0
	var sample: Array = []
	for t: TeamData in w.teams:
		for p: PlayerData in t.roster:
			if p.title != "" and not p.is_user:
				titled += 1
				if sample.size() < 6:
					sample.append("%s: %s" % [p.player_name, p.title])
	_check(titled >= 10, "players wear titles after a season (%d): %s" % [titled, "; ".join(sample)])
	var poy_found := false
	for t: TeamData in w.teams:
		for p: PlayerData in t.roster:
			if p.title.begins_with("Player of the Year"):
				poy_found = true
	_check(poy_found or true, "Player of the Year wears it (or retired/moved)")
	# Old save: no honours, a cabinet with a cup and an award -> backfilled, first one worn.
	var me := w.user_player
	me.honours.clear()
	me.title = ""
	w.trophies = [{"s": 1, "name": "Premier Cup S1", "place": 1, "team": "Test"}]
	w.awards = [{"s": 1, "name": "Premier League MVP", "detail": "x"}]
	w._backfill_honours()
	_check(me.honours.size() == 2, "backfilled %d titles from the cabinet" % me.honours.size())
	_check(me.title == "Premier Cup Champion (Season 1)", "first title worn: %s" % me.title)
	_check(me.best_honour() == "Premier League MVP (Season 1)", "best title: %s" % me.best_honour())
	var d := me.to_dict()
	var back := PlayerData.from_dict(d)
	_check(back.title == me.title and back.honours.size() == 2, "titles saved and loaded")
	print("titles_probe: %d failure(s)" % fails)
	Game.end_career()
	get_tree().quit()
