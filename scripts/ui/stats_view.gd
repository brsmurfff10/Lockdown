class_name StatsView
extends RefCounted
## Stats hub shared by both careers: league leaders this season and a search
## across every player in the world.

const LEADER_COLS := [["#", 26, "c"], ["Player", 0, "l"], ["Club", 130, "l"], ["Value", 64, "c"]]
const SEARCH_COLS := [["Player", 0, "l"], ["Club", 150, "l"], ["League", 60, "c"], ["Role", 64, "l"], ["Age", 34, "c"], ["RTG", 44, "c"],
	["M", 34, "c"], ["Avg", 46, "c"], ["K/D", 46, "c"], ["Nation", 84, "l"]]
const BOARDS := [
	["Season rating", "rating"], ["Kills", "kills"], ["K/D", "kd"], ["Matches", "matches"],
	["Highest rated", "rtg"], ["Best young players (21 and under)", "young"],
]


## state: {tab, league (-1 = all), query}. on_change(state) rebuilds; on_player(p) opens a card.
static func build(parent: Control, w: World, state: Dictionary, on_change: Callable, on_player: Callable) -> void:
	var bar := UI.hbox(8)
	for t: String in ["Leaders", "Search"]:
		var tn := t
		bar.add_child(UI.small_button(t, func() -> void:
			state.tab = tn
			on_change.call(state), 120, "PrimaryButton" if String(state.tab) == t else ""))
	bar.add_child(UI.gap(4))
	var lg := OptionButton.new()
	lg.add_item("All leagues")
	for l in World.LEAGUES.size():
		lg.add_item(World.LEAGUES[l].name)
	lg.select(int(state.league) + 1)
	lg.focus_mode = Control.FOCUS_NONE
	lg.item_selected.connect(func(i: int) -> void:
		state.league = i - 1
		on_change.call(state))
	bar.add_child(lg)
	parent.add_child(bar)
	var pool := _pool(w, int(state.league), String(state.tab) == "Search")
	if String(state.tab) == "Search":
		_search(parent, w, pool, state, on_change, on_player)
	else:
		_leaders(parent, w, pool, on_player)


static func _pool(w: World, league: int, with_free: bool) -> Array:
	var out: Array = []
	for t in w.teams:
		if league >= 0 and t.league != league:
			continue
		out.append_array(t.roster)
	if with_free and league < 0:
		out.append_array(w.free_agents)
	return out


static func _value(p: PlayerData, key: String) -> float:
	match key:
		"rating":
			return p.season_avg_rating() if int(p.season_stats.get("m", 0)) >= 5 else -1.0
		"kills":
			return float(p.season_stats.get("k", 0))
		"kd":
			return p.season_kd() if int(p.season_stats.get("m", 0)) >= 5 else -1.0
		"matches":
			return float(p.season_stats.get("m", 0))
		"young":
			return p.rating_exact() if p.age <= 21 else -1.0
	return p.rating_exact()


static func _fmt(key: String, v: float) -> String:
	return "%.2f" % v if key in ["rating", "kd"] else str(int(round(v)))


static func _leaders(parent: Control, w: World, pool: Array, on_player: Callable) -> void:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	for b: Array in BOARDS:
		var key: String = b[1]
		var ranked: Array = pool.filter(func(p: PlayerData) -> bool: return _value(p, key) > (0.0 if key in ["kills", "matches"] else -0.5))
		ranked.sort_custom(func(a: PlayerData, c: PlayerData) -> bool: return _value(a, key) > _value(c, key))
		var pc := PanelContainer.new()
		pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := UI.vbox(2)
		pc.add_child(v)
		v.add_child(UI.caption(String(b[0]), UI.WARN))
		v.add_child(UI.table_header(LEADER_COLS))
		for i in mini(8, ranked.size()):
			var p: PlayerData = ranked[i]
			var o := w.owner_of(p)
			var nb := UI.link_button(p.player_name, on_player.bind(p), 13, UI.ACCENT2 if p.is_user else UI.TEXT)
			v.add_child(UI.table_row([UI.label(str(i + 1), 12, UI.TEXT_FAINT, 600), nb,
				UI._clip(UI.label(o.team_name if o != null else "Free agent", 12, UI.TEXT_DIM)),
				UI.label(_fmt(key, _value(p, key)), 13, UI.GOOD, 700)], LEADER_COLS, i, p.is_user))
		if ranked.is_empty():
			v.add_child(UI.label("Not enough matches yet.", 12, UI.TEXT_FAINT))
		grid.add_child(pc)
	parent.add_child(UI.scroll(grid))


static func _search(parent: Control, w: World, pool: Array, state: Dictionary, on_change: Callable, on_player: Callable) -> void:
	var row := UI.hbox(8)
	var q := LineEdit.new()
	q.placeholder_text = "Search players by name, club or nation..."
	q.text = String(state.get("query", ""))
	q.custom_minimum_size = Vector2(420, 36)
	q.text_submitted.connect(func(t: String) -> void:
		state.query = t
		on_change.call(state))
	row.add_child(q)
	row.add_child(UI.small_button("Search", func() -> void:
		state.query = q.text
		on_change.call(state), 100, "PrimaryButton"))
	parent.add_child(row)
	var needle := String(state.get("query", "")).strip_edges().to_lower()
	var hits: Array = []
	for p: PlayerData in pool:
		var o := w.owner_of(p)
		var hay := (p.player_name + " " + (o.team_name if o != null else "free agent") + " " + p.nation).to_lower()
		if needle == "" or hay.contains(needle):
			hits.append(p)
	hits.sort_custom(func(a: PlayerData, b: PlayerData) -> bool: return a.rating_exact() > b.rating_exact())
	var card := UI.card(parent, "%d player%s%s" % [hits.size(), "" if hits.size() == 1 else "s", " (top 150 shown)" if hits.size() > 150 else ""], true)
	card.add_child(UI.table_header(SEARCH_COLS))
	var list := UI.vbox(2)
	for i in mini(150, hits.size()):
		var p: PlayerData = hits[i]
		var o := w.owner_of(p)
		var m := int(p.season_stats.get("m", 0))
		list.add_child(UI.table_row([UI.link_button(p.player_name, on_player.bind(p), 14, UI.ACCENT2 if p.is_user else UI.TEXT),
			UI._clip(UI.label(o.team_name if o != null else "Free agent", 12, UI.TEXT_DIM)),
			UI.label(World.LEAGUES[o.league].short if o != null else "-", 12, UI.TEXT_DIM), UI.label(p.role, 12, UI.TEXT_DIM),
			UI.label(str(p.age), 13), UI.rating_chip(int(round(w.est_rating(p)))), UI.label(str(m), 13),
			UI.label("%.2f" % p.season_avg_rating() if m > 0 else "-", 13), UI.label("%.2f" % p.season_kd() if m > 0 else "-", 13),
			UI._clip(UI.label(p.nation, 12, UI.TEXT_DIM))], SEARCH_COLS, i, p.is_user))
	card.add_child(UI.scroll(list))
