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
	# A new world already has last season's title holders.
	var seeded := 0
	var seed_kinds := {}
	for t: TeamData in w.teams:
		for p: PlayerData in t.roster:
			if p.title != "" and not p.is_user:
				seeded += 1
			for h: Dictionary in p.honours:
				seed_kinds[String(h.t).get_slice(" in the ", 0) if String(h.t).contains(" in the ") else String(h.t).get_slice(" ", String(h.t).get_slice_count(" ") - 1)] = true
	_check(seeded > 40 and w.user_player.honours.is_empty(), "new world: %d players wear last season's titles, you have none" % seeded)
	_check(seed_kinds.has("Champion") and seed_kinds.has("Finalist") and seed_kinds.has("#1") and seed_kinds.has("#1 Rated") and seed_kinds.has("Top K/D") and seed_kinds.has("Most Kills"),
		"seeded kinds: %s" % str(seed_kinds.keys()))
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
	var bad: Array = []
	var kinds := {}
	for t: TeamData in w.teams:
		for p: PlayerData in t.roster:
			for h: Dictionary in p.honours:
				var tx := String(h.t)
				if not PlayerData.allowed_honour(tx):
					bad.append(tx)
				if int(h.s) < start:
					continue
				for k in [" Champion", " Finalist", "Semi Finalist", "Quarter Finalist", "#1 in the", "#5 in the", "#1 Rated", "Top K/D", "Most Kills"]:
					if tx.contains(k) and not (k == " Finalist" and (tx.contains("Semi") or tx.contains("Quarter"))):
						kinds[k] = true
	_check(bad.is_empty(), "only allowed titles exist %s" % str(bad.slice(0, 5)))
	_check(kinds.size() == 9, "every title kind was handed out this season: %s" % str(kinds.keys()))
	# Old saves: retired titles (MVP, Promoted...) are dropped on load; a worn one is swapped for the best left.
	var old := PlayerData.from_dict({"name": "Oldie", "honours": [{"t": "Premier League MVP", "s": 1, "rank": 80}, {"t": "Premier Cup Champion", "s": 1, "rank": 60}, {"t": "2nd in the Premier League", "s": 1, "rank": 64}], "title": "Premier League MVP (Season 1)"})
	_check(old.honours.size() == 2 and old.title == "#2 in the Premier League (Season 1)", "old save cleaned: %s" % old.title)
	var worn := PlayerData.from_dict({"name": "Oldie2", "honours": [{"t": "1st in the Premier League", "s": 2, "rank": 60}], "title": "1st in the Premier League (Season 2)"})
	_check(worn.title == "#1 in the Premier League (Season 2)", "old worn league title renamed: %s" % worn.title)
	# Old save: no honours, a cabinet with a cup and an award -> backfilled, first one worn.
	var me := w.user_player
	me.honours.clear()
	me.title = ""
	w.trophies = [{"s": 1, "name": "Premier Cup S1", "place": 2, "team": "Test"}, {"s": 2, "name": "Premier League Playoffs S2", "place": 1, "team": "Test"}]
	w.awards = [{"s": 1, "name": "Premier League MVP", "detail": "x"}]
	w._backfill_honours()
	_check(me.honours.size() == 2, "backfilled %d titles from the cabinet" % me.honours.size())
	_check(me.title == "Premier Cup Finalist (Season 1)", "first title worn: %s" % me.title)
	_check(me.best_honour() == "Premier League Playoffs Champion (Season 2)", "best title: %s" % me.best_honour())
	var d := me.to_dict()
	var back := PlayerData.from_dict(d)
	_check(back.title == me.title and back.honours.size() == 2, "titles saved and loaded")
	print("titles_probe: %d failure(s)" % fails)
	Game.end_career()
	get_tree().quit()
