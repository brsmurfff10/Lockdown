extends Control
## My Player career hub: top status bar, sidebar pages, news ticker.

const PAGES := ["Overview", "Inbox", "Messages", "Feed", "Home", "Shop", "Profile", "Training", "Career", "Team", "League", "Tournaments", "Stats", "History"]

var w: World
var _page := "Overview"
var _shop_state := {} ## Shop page: {cat}.
var _content: VBoxContainer
var _nav_holder: VBoxContainer
var _topbar: HBoxContainer
var _toast: Label
var _ticker: NewsTicker
var _league_view := -1
var _train_pick: OptionButton
var _intensity := "Normal"
var _hist_tab := "Season review"
var _stats_state := {"tab": "Leaders", "league": -1, "query": ""}
var _hist_review := -1
var _social := {"tone": "neutral", "draft": "", "thread": "", "dm_draft": ""} ## Feed + Messages page state.
var _llm: LlmClient = null ## Optional local LLM (Settings > Local AI chat).


func _ready() -> void:
	w = Game.pworld
	if w == null:
		Game.goto(Game.MENU_SCENE)
		return
	UI.setup_screen(self)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, 14)
	add_child(margin)
	var root := UI.vbox(12)
	margin.add_child(root)
	var bar := PanelContainer.new()
	root.add_child(bar)
	_topbar = UI.hbox(14)
	bar.add_child(_topbar)
	var body := UI.hbox(14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	var side := UI.vbox(8)
	side.custom_minimum_size = Vector2(200, 0)
	body.add_child(side)
	_nav_holder = UI.vbox(0)
	side.add_child(_nav_holder)
	side.add_child(UI.spacer(false))
	side.add_child(UI.button("Main Menu", func() -> void:
		Game.save_player_career()
		Game.goto(Game.MENU_SCENE), 190, "GhostButton"))
	_content = UI.vbox(12)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_content)
	_ticker = NewsTicker.new()
	root.add_child(_ticker)
	_clear_pending()
	if Game.hub_page != "":
		_page = Game.hub_page if PAGES.has(Game.hub_page) else _page
		Game.hub_page = ""
	w.soc().llm_on = LlmClient.enabled()
	w.soc().live = true
	LlmClient.warm(self)
	var ft := Timer.new()
	ft.wait_time = 1.0
	ft.autostart = true
	ft.timeout.connect(_feed_tick)
	add_child(ft)
	_show(_page)
	if w.review_pending:
		HistoryView.ceremony_popup(self, w, func() -> void: HistoryView.review_popup(self, w))


func _nav(page: String) -> void:
	if page == "League":
		_league_view = -1
	_show(page)


func _show(page: String) -> void:
	_page = page
	_run_llm() # Lines queued by the week's events (bots messaging you first).
	for c in _nav_holder.get_children():
		c.queue_free()
	var nav := UI.nav(PAGES, page, _nav, {"Inbox": w.unread_count(), "Career": w.offers.size(), "Messages": w.soc().unread_total()})
	for b in nav.get_children():
		(b as Control).custom_minimum_size.y = 31 # 14 pages: keep the sidebar inside 720px.
	_nav_holder.add_child(nav)
	_build_topbar()
	_ticker.set_world(w)
	for c in _content.get_children():
		c.queue_free()
	match page:
		"Overview": _overview()
		"Inbox": _inbox()
		"Profile": _profile()
		"Training": _training()
		"Career": _career()
		"Team": _team()
		"League": _league()
		"Tournaments": _tournaments()
		"Home":
			_page_title("Home", "Your place: walk around it, have people over, move house")
			ShopView.home_page(_content, w, _act)
		"Shop":
			_page_title("Shop", "Property, cars, home extras, pets, style, weapon finishes, staff and investments")
			ShopView.shop_page(_content, w, _shop_state, _act, func() -> void: _show(_page))
		"Feed":
			_page_title("Feed", "%s followers  -  what people are saying about you" % World.fame_text(w.fame))
			SocialView.feed(_content, w, _social, _social_cb())
		"Messages":
			_page_title("Messages", "DMs with anyone, your team's group chat and the coach")
			SocialView.messages(_content, w, _social, _social_cb())
		"Stats":
			_page_title("Stats", "Season leaders and every player in the world")
			StatsView.build(_content, w, _stats_state, func(st: Dictionary) -> void:
				_stats_state = st
				_refresh(), _view_player)
		"History":
			_page_title("History", "Season reviews, champions, records and the Hall of Fame")
			HistoryView.build(_content, w, _hist_tab, _hist_review, _set_hist_tab, _set_hist_review)


func _refresh(msg: String = "", bad: bool = false) -> void:
	Game.save_player_career_soon()
	if msg == "" and not _pending_toast.is_empty():
		msg = String(_pending_toast[0])
		bad = bool(_pending_toast[1])
	_pending_toast = []
	_show(_page)
	if msg != "":
		_toast.text = msg
		_toast.tooltip_text = msg
		_toast.add_theme_color_override("font_color", UI.BAD if bad else UI.GOOD)


func _act(err: String, ok_msg: String) -> void:
	_refresh(err if err != "" else ok_msg, err != "")


func _build_topbar() -> void:
	for c in _topbar.get_children():
		c.queue_free()
	var p := w.user_player
	var ut := w.user_team()
	_topbar.add_child(UI.rating_badge(p.rating(), 34))
	var who := UI.vbox(0)
	who.add_child(UI.label(p.player_name, 24, UI.TEXT, 700))
	if p.title != "":
		who.add_child(UI.label(p.title, 13, UI.WARN, 600))
	who.add_child(UI.label("%s%s  -  age %d  -  Season %d, week %d / %d" % [p.role, (" (%s)" % w.specialty) if w.specialty != "" else "", p.age, w.season, w.week, World.SEASON_WEEKS], 13, UI.TEXT_DIM))
	_topbar.add_child(who)
	_topbar.add_child(UI.spacer())
	if w.teamless:
		_topbar.add_child(UI.pill("Free agent: no club", UI.WARN, 13))
	else:
		_topbar.add_child(UI.team_label(ut, 17, true))
	_topbar.add_child(UI.stat_chip("Wallet", UI.money_text(w.wallet), UI.GOOD))
	_topbar.add_child(UI.stat_chip("Followers", World.fame_text(w.fame), UI.ACCENT2))
	_topbar.add_child(UI.stat_chip("Coach trust", str(int(w.coach_trust)), _trust_color(w.coach_trust)))
	_topbar.add_child(UI.stat_chip("Form", p.form_text(), p.form_color()))
	var right := UI.vbox(4)
	right.add_child(UI.pill(w.window_text().replace("Transfer window ", "Window ").replace("(until week ", "(to wk ").replace("(opens week ", "(opens wk "), UI.GOOD if w.window_open() else UI.TEXT_DIM))
	_toast = UI.label("", 13, UI.GOOD, 600)
	# Fixed width, wraps to 2 lines: a long message must never widen the top bar.
	_toast.custom_minimum_size = Vector2(260, 34)
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.clip_text = true
	_toast.mouse_filter = Control.MOUSE_FILTER_PASS
	right.add_child(_toast)
	_topbar.add_child(right)


func _set_hist_tab(t: String) -> void:
	_hist_tab = t
	_refresh()


func _set_hist_review(i: int) -> void:
	_hist_review = i
	_refresh()


func _trust_color(v: float) -> Color:
	return UI.GOOD if v >= 65.0 else (UI.TEXT if v >= 40.0 else (UI.WARN if v >= 25.0 else UI.BAD))


func _page_title(title: String, sub: String = "") -> void:
	var h := UI.hbox(14)
	h.add_child(UI.heading(title, 26))
	if sub != "":
		var s := UI.label(sub, 14, UI.TEXT_DIM)
		s.size_flags_vertical = Control.SIZE_SHRINK_END
		h.add_child(s)
	_content.add_child(h)


func _wrap(text: String, size: int = 13, color: Color = UI.TEXT_DIM) -> Label:
	var l := UI.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _line(parent: Control, a: String, b: String, color: Color = UI.TEXT) -> void:
	var r := UI.hbox(8)
	r.add_child(UI.label(a, 14, UI.TEXT_DIM))
	r.add_child(UI.spacer())
	r.add_child(UI.label(b, 14, color, 600))
	parent.add_child(r)


func _banner(parent: Control, text: String, color: Color, btn: String = "", cb: Callable = Callable()) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI._edge_box(Color(color, 0.08), color, SIDE_LEFT, 3, Color(0, 0, 0, 0), 14, 8))
	var h := UI.hbox(10)
	p.add_child(h)
	var l := _wrap(text, 14, color)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	if btn != "":
		h.add_child(UI.small_button(btn, cb, 130, "PrimaryButton"))
	parent.add_child(p)


func _confirm(title: String, body: String, ok_text: String, cb: Callable) -> void:
	var m := UI.modal(self, 480, UI.WARN)
	var overlay: Control = m[0]
	var box: VBoxContainer = m[1]
	box.add_child(UI.heading(title, 20))
	box.add_child(_wrap(body, 14))
	var row := UI.hbox(10)
	row.add_child(UI.button("Cancel", func() -> void: overlay.queue_free(), 140, "GhostButton"))
	row.add_child(UI.spacer())
	row.add_child(UI.button(ok_text, func() -> void:
		overlay.queue_free()
		cb.call(), 160, "PrimaryButton"))
	box.add_child(row)


func _show_results(res: Dictionary) -> void:
	if res.is_empty():
		return
	var holder: Array = [] # Lambdas capture by value: hold the overlay in an array.
	holder.append(UI.results_overlay(self, res, func() -> void: (holder[0] as Node).queue_free()))


# =============================================================================
# Overview
# =============================================================================

func _overview() -> void:
	_page_title("Overview", "Season %d  -  week %d of %d" % [w.season, w.week, World.SEASON_WEEKS])
	var p := w.user_player
	if w.retired:
		_banner(_content, "You've retired. Your legacy: %s." % String(w.legacy.get("tier", "?")), UI.WARN, "View legacy", func() -> void: _show("Profile"))
	elif w.free_agency:
		_banner(_content, "You're a free agent. %d clubs have made offers: pick one to start the season." % w.offers.size(), UI.WARN, "See offers", func() -> void: _show("Career"))
	elif w.teamless:
		_banner(_content, "You've been released and have no club. Play showmatches, take trials and stand-in calls, and let your agent find you a way back.", UI.WARN, "Ways back", func() -> void: _show("Career"))
	elif w.forced_bench_until >= w.stamp():
		_banner(_content, "You've been dropped for disciplinary reasons until week %d. One more strike and the club lets you go." % (w.forced_bench_until % 100), UI.BAD)
	elif not p.available():
		_banner(_content, "You're out with %s for %d more week%s. You can't play or train." % [p.ailment, p.out_weeks, "s" if p.out_weeks > 1 else ""], UI.BAD)
	elif p.contract_until <= w.season and w.week >= 12 and not w.renewal_done:
		_banner(_content, "Your contract ends this season. Check your inbox for the club's offer.", UI.WARN, "Inbox", func() -> void: _show("Inbox"))
	var cols := UI.hbox(14)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(cols)
	var left := UI.vbox(14)
	cols.add_child(UI.scroll(left))
	if w.allstar_pending():
		_allstar_card(left)
	if w.teamless or w.soc().trial_team() != null or (not w.user_starting() and p.available() and not w.retired):
		_comeback_card(left)
	_match_card(left)
	_last_match_card(left)
	_status_card(left)
	var right := UI.vbox(14)
	right.custom_minimum_size = Vector2(340, 0)
	cols.add_child(right)
	_inbox_preview(right)
	_goals_card(right)
	var news := UI.card(right, "News", true, UI.TEXT_DIM)
	var list := UI.vbox(5)
	for i in range(w.news.size() - 1, maxi(-1, w.news.size() - 50), -1):
		list.add_child(_wrap(w.news[i], 12))
	news.add_child(UI.scroll(list))


func _match_card(parent: Control) -> void:
	var ut := w.user_team()
	var ui := w.team_index(ut)
	var mt := w.user_match_this_week()
	if mt.is_empty() or w.retired:
		var c := UI.card(parent, "This week", false, UI.ACCENT)
		c.add_child(UI.label("Career over." if w.retired else ("You have no club, so no matches. Showmatches and offers are on the Career page." if w.teamless else "No matches left this week."), 16))
		if not w.retired:
			c.add_child(UI.button("Advance Week", func() -> void:
				var r := w.advance_week()
				var msgs := {"free_agency": "Pick a club first (Career page).", "play_match": "You have a match to play first.", "retired": "You've retired."}
				_refresh(String(msgs.get(r, "")), r != ""), 240, "PrimaryButton"))
		return
	var opp: TeamData = w.teams[mt.b if mt.a == ui else mt.a]
	var c := UI.card(parent, "Match  -  " + String(mt.label), false, UI.ACCENT)
	var vs := UI.hbox(16)
	vs.alignment = BoxContainer.ALIGNMENT_CENTER
	vs.add_child(_side_block(ut, true))
	var mid := UI.vbox(2)
	mid.add_child(UI.label("VS", 28, UI.TEXT_FAINT, 700))
	mid.add_child(UI.pill(String(mt.get("map", "?")), UI.TEXT_DIM))
	vs.add_child(mid)
	vs.add_child(_side_block(opp, false))
	c.add_child(vs)
	var rv := w.top_rival()
	if not rv.is_empty():
		var rp := w.find_player(int(rv.uid))
		if rp != null and opp.roster.has(rp):
			var rl := UI.label("Rivalry: %s plays for them (you lead %d-%d)" % [rp.player_name, int(rv.w), int(rv.l)] if int(rv.w) >= int(rv.l) else "Rivalry: %s plays for them (they lead %d-%d)" % [rp.player_name, int(rv.l), int(rv.w)], 13, UI.WARN, 600)
			rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			c.add_child(rl)
	var block := w.user_play_block()
	var btns := UI.hbox(10)
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	if block == "":
		btns.add_child(UI.button("Play Match", func() -> void:
			Game.prepare_player_match()
			Game.goto(Game.MATCH_SCENE), 200, "PrimaryButton"))
	elif not w.free_agency:
		btns.add_child(UI.button("Watch from the bench", func() -> void:
			Game.prepare_player_match()
			Game.goto(Game.MATCH_SCENE), 230, "PrimaryButton"))
	var sim := UI.button("Simulate", func() -> void:
		var res := w.sim_user_match()
		_refresh()
		_show_results(res), 150)
	sim.disabled = w.free_agency
	btns.add_child(sim)
	c.add_child(btns)
	if block != "":
		var bl := UI.label(block + ("." if w.free_agency else ". The team plays without you."), 13, UI.WARN, 600)
		bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		c.add_child(bl)


func _allstar_card(parent: Control) -> void:
	var c := UI.card(parent, "All-Star Showcase", false, UI.WARN)
	var sides := w.allstar_teams()
	var h := UI.hbox(20)
	for t: TeamData in sides:
		var v := UI.vbox(2)
		v.add_child(UI.label(t.team_name, 16, t.color, 700))
		v.add_child(UI.label(", ".join(t.roster.map(func(pl: PlayerData) -> String: return pl.player_name)), 12, UI.TEXT_DIM))
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(v)
	c.add_child(h)
	var row := UI.hbox(10)
	row.add_child(_wrap("You've been picked with the best players in the world. An exhibition: it doesn't count for stats, but it's great for your fame.", 13))
	row.get_child(0).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(UI.small_button("Play", func() -> void:
		if Game.prepare_allstar():
			Game.goto(Game.MATCH_SCENE), 90, "PrimaryButton"))
	row.add_child(UI.small_button("Simulate", func() -> void:
		var res := w.sim_allstar()
		_refresh()
		_show_results(res), 100))
	c.add_child(row)


func _last_match_card(parent: Control) -> void:
	if w.last_report.is_empty():
		return
	var r: Dictionary = w.last_report
	var s: Array = r.score
	var result := "WIN" if s[0] > s[1] else ("DRAW" if s[0] == s[1] else "LOSS")
	var col := UI.GOOD if result == "WIN" else (UI.BAD if result == "LOSS" else UI.WARN)
	var rc := UI.card(parent, "Last match", false, col)
	var h := UI.hbox(14)
	h.add_child(UI.label("%s  %d-%d" % [result, s[0], s[1]], 22, col, 700))
	h.add_child(UI.label("vs " + String(r.opponent), 16, UI.TEXT_DIM))
	h.add_child(UI.spacer())
	if bool(r.get("potm", false)):
		h.add_child(UI.pill("Player of the match", UI.WARN))
	rc.add_child(h)
	if not bool(r.get("played", true)):
		rc.add_child(UI.label("You didn't play.", 14, UI.TEXT_DIM))
		return
	var total := 0.0
	for k in r.changes:
		total += float(r.changes[k])
	var chips := UI.hbox(26)
	chips.add_child(UI.stat_chip("Rating", "%.2f" % float(r.rating), UI.GOOD if float(r.rating) >= 1.0 else UI.WARN))
	chips.add_child(UI.stat_chip("K / D", "%d / %d" % [int(r.kills), int(r.deaths)]))
	chips.add_child(UI.stat_chip("Stats", "%+.1f" % total, UI.GOOD if total >= 0 else UI.BAD))
	rc.add_child(chips)


func _status_card(parent: Control) -> void:
	var p := w.user_player
	var c := UI.card(parent, "You", false, UI.ACCENT2)
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 24)
	chips.add_theme_constant_override("v_separation", 6)
	chips.add_child(UI.stat_chip("Lineup", "Starting" if w.user_starting() else ("Out" if not p.available() else "Bench"), UI.GOOD if w.user_starting() else UI.WARN))
	chips.add_child(UI.stat_chip("Form", p.form_text(), p.form_color()))
	chips.add_child(UI.stat_chip("Morale", p.morale_text(), UI.GOOD if p.morale >= 60 else (UI.WARN if p.morale >= 30 else UI.BAD)))
	chips.add_child(UI.stat_chip("Coach trust", "%d / 100" % int(w.coach_trust), _trust_color(w.coach_trust)))
	chips.add_child(UI.stat_chip("Season", "%.2f avg" % p.season_avg_rating() if int(p.season_stats.get("m", 0)) > 0 else "-"))
	chips.add_child(UI.stat_chip("Contract", "to S%d" % p.contract_until, UI.WARN if p.contract_until <= w.season else UI.TEXT))
	chips.add_child(UI.stat_chip("Fatigue", "%d" % int(w.fatigue), UI.GOOD if w.fatigue < 40 else (UI.WARN if w.fatigue < 70 else UI.BAD)))
	c.add_child(chips)
	if p.promise_until >= w.stamp():
		c.add_child(UI.label("The coach has promised you a start until week %d." % (p.promise_until % 100), 12, UI.GOOD))
	c.add_child(UI.label("The coach picks the five on rating, form and trust. Play well, train, and handle the media to stay in.", 12, UI.TEXT_FAINT))


func _inbox_preview(parent: Control) -> void:
	var c := UI.card(parent, "Inbox", false, UI.ACCENT2)
	var open: Array = w.inbox.filter(func(m: Dictionary) -> bool: return not bool(m.done))
	if open.is_empty():
		c.add_child(UI.label("Nothing waiting on you.", 13, UI.TEXT_DIM))
		return
	for i in range(open.size() - 1, maxi(-1, open.size() - 4), -1):
		var m: Dictionary = open[i]
		var r := UI.hbox(8)
		r.add_child(UI.pill(String(m.kind), _msg_color(String(m.kind)), 10))
		var l := UI.label(String(m.title), 13, UI.TEXT)
		l.clip_text = true
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(l)
		c.add_child(r)
	c.add_child(UI.small_button("Open inbox (%d)" % open.size(), func() -> void: _show("Inbox"), 150, "PrimaryButton"))


func _goals_card(parent: Control) -> void:
	var c := UI.card(parent, "Season goals", false, UI.GOOD)
	for g in w.goals:
		var st := String(g.status)
		var r := UI.hbox(8)
		var mark := "+" if st == "done" else ("x" if st == "failed" else "-")
		r.add_child(UI.label(mark, 14, UI.GOOD if st == "done" else (UI.BAD if st == "failed" else UI.TEXT_FAINT), 700))
		var l := UI.label(String(g.text), 13, UI.TEXT if st == "open" else UI.TEXT_DIM)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		r.add_child(l)
		r.add_child(UI.label("Done" if st == "done" else ("Missed" if st == "failed" else w.goal_progress(g)), 12, UI.GOOD if st == "done" else UI.TEXT_DIM, 600))
		c.add_child(r)
	c.add_child(UI.label("Hitting goals pays a bonus and builds trust and fame.", 11, UI.TEXT_FAINT))


func _side_block(t: TeamData, mine: bool) -> VBoxContainer:
	var v := UI.vbox(4)
	v.custom_minimum_size = Vector2(190, 0)
	var badge := UI.team_badge_for(t, 46)
	badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(badge)
	var n := UI.link_button(t.team_name, _view_team.bind(t), 17, UI.ACCENT2 if mine else UI.TEXT, 700)
	n.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	n.clip_text = false
	v.add_child(n)
	var s := UI.label("RTG %d  -  %d-%d" % [t.rating(), t.wins, t.losses], 13, UI.TEXT_DIM)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	return v


# =============================================================================
# Inbox
# =============================================================================

func _msg_color(kind: String) -> Color:
	match kind:
		"bench", "sold", "injury", "released", "warning": return UI.BAD
		"budget": return UI.WARN
		"trial", "standin": return UI.GOOD
		"contract", "role", "retire": return UI.WARN
		"endorse", "award", "perk": return UI.GOOD
		"media", "teammate": return UI.ACCENT2
	return UI.TEXT_DIM


func _inbox() -> void:
	_page_title("Inbox", "%d waiting on you" % w.unread_count())
	var list := UI.vbox(10)
	for i in range(w.inbox.size() - 1, -1, -1):
		var m: Dictionary = w.inbox[i]
		var col := _msg_color(String(m.kind))
		var done := bool(m.done)
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", UI._edge_box(UI.PANEL if not done else UI.PANEL_LO, col if not done else Color(col, 0.35), SIDE_LEFT, 3, Color(0, 0, 0, 0), 16, 10))
		var v := UI.vbox(6)
		p.add_child(v)
		var top := UI.hbox(10)
		var tl := UI.label(String(m.title), 16, UI.TEXT if not done else UI.TEXT_DIM, 700)
		tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(tl)
		top.add_child(UI.pill(String(m.kind), col, 10))
		top.add_child(UI.spacer())
		top.add_child(UI.label("S%d W%d" % [int(m.s), int(m.w)], 12, UI.TEXT_FAINT))
		v.add_child(top)
		v.add_child(_wrap(String(m.body)))
		if done:
			var rl := UI.label("> " + String(m.result), 13, UI.TEXT_FAINT, 600)
			rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v.add_child(rl)
		else:
			var row := HFlowContainer.new() # Wraps: long answers never widen the page.
			row.add_theme_constant_override("h_separation", 8)
			row.add_theme_constant_override("v_separation", 6)
			var mm := m
			for k in (m.options as Array).size():
				var opt: Array = m.options[k]
				var kk := k
				row.add_child(UI.small_button(String(opt[0]), func() -> void:
					var err := w.resolve_msg(mm, kk)
					_act(err, String(mm.result)), 0, "PrimaryButton" if k == 0 else "GhostButton"))
			v.add_child(row)
		list.add_child(p)
	if w.inbox.is_empty():
		list.add_child(UI.label("Nothing yet. Your coach, teammates, reporters and sponsors will get in touch.", 14, UI.TEXT_DIM))
	_content.add_child(UI.scroll(list))


# =============================================================================
# Profile: trophies, awards, timeline, perks, rivals, legacy
# =============================================================================

const TIMELINE_COLS := [["Season", 60, "l"], ["Club", 0, "l"], ["League", 70, "c"], ["M", 36, "c"], ["K/D", 50, "c"], ["Avg", 50, "c"], ["Pos", 44, "c"], ["Titles", 50, "c"]]
const RIVAL_COLS := [["Player", 0, "l"], ["Club", 150, "l"], ["Met", 40, "c"], ["W-L", 60, "c"]]


func _profile() -> void:
	var p := w.user_player
	var h := UI.hbox(14)
	h.add_child(UI.heading("Profile", 26))
	h.add_child(UI.spacer())
	h.add_child(UI.small_button("Player card & match history", func() -> void: _view_player(p), 230))
	if w.can_retire():
		h.add_child(UI.small_button("Retire", func() -> void:
			_confirm("Retire now?", "Your career ends here and your legacy is written. This can't be undone.", "Retire", func() -> void:
				w.retire()
				_refresh("You've retired.")), 100, "GhostButton"))
	_content.add_child(h)
	var page := UI.vbox(14)
	if w.retired:
		_legacy_card(page)
	var chips_card := UI.card(page, "Career", false, UI.ACCENT2)
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 26)
	var r_sum := 0.0
	var m := 0
	for e in w.timeline:
		r_sum += float(e.r_sum)
		m += int(e.m)
	for ch in [["Matches", str(p.matches_played), UI.TEXT], ["K / D", "%.2f" % p.career_kd(), UI.TEXT],
			["Avg rating", "%.2f" % (r_sum / m) if m > 0 else "-", UI.TEXT], ["Trophies", str(w.trophy_count(1)), UI.WARN],
			["Runner-up", str(w.trophy_count(2)), UI.TEXT_DIM], ["Awards", str(w.awards.size()), UI.GOOD],
			["Player of match", str(w.potm), UI.ACCENT2], ["Peak RTG", str(w.peak_rating), UI.rating_color(w.peak_rating)],
			["Followers", World.fame_text(w.fame), UI.ACCENT2], ["Clubs", str(_club_count()), UI.TEXT],
			["Nation", p.nation, UI.TEXT], ["Caps", str(w.caps), UI.TEXT], ["Highlights", str(w.highlights), UI.ACCENT2]]:
		chips.add_child(UI.stat_chip(ch[0], ch[1], ch[2]))
	chips_card.add_child(chips)

	var row := UI.hbox(14)
	page.add_child(row)
	var cab := UI.card(row, "Trophy cabinet", false, UI.WARN)
	cab.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	for t in w.trophies:
		flow.add_child(_trophy_tile(t))
	if w.trophies.is_empty():
		cab.add_child(UI.label("No silverware yet. Cups, playoffs and promotions end up here.", 13, UI.TEXT_DIM))
	cab.add_child(flow)
	var aw := UI.card(row, "Awards", false, UI.GOOD)
	aw.get_parent().custom_minimum_size = Vector2(380, 0)
	if w.awards.is_empty():
		aw.add_child(UI.label("None yet: MVPs, Rookie of the Year, Team of the Season, All-Star picks.", 13, UI.TEXT_DIM))
	for i in range(w.awards.size() - 1, -1, -1):
		var a: Dictionary = w.awards[i]
		var ar := UI.hbox(8)
		ar.add_child(UI.label("Season %d" % int(a.s), 12, UI.TEXT_FAINT, 600))
		var v := UI.vbox(0)
		v.add_child(UI.label(String(a.name), 14, UI.TEXT, 600))
		v.add_child(UI.label(String(a.detail), 12, UI.TEXT_DIM))
		ar.add_child(v)
		aw.add_child(ar)

	var tc := UI.card(page, "Titles (wear one: it shows with your name, here and on the scoreboard)", false, UI.WARN)
	if p.honours.is_empty():
		tc.add_child(UI.label("Win a trophy or an award to earn a title.", 13, UI.TEXT_DIM))
	else:
		var tflow0 := HFlowContainer.new()
		tflow0.add_theme_constant_override("h_separation", 8)
		tflow0.add_theme_constant_override("v_separation", 8)
		var sorted: Array = p.honours.duplicate()
		sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.rank) > int(b.rank) or (int(a.rank) == int(b.rank) and int(a.s) > int(b.s)))
		for hon: Dictionary in sorted:
			var lbl := PlayerData.honour_label(hon)
			var on := p.title == lbl
			tflow0.add_child(UI.small_button(("Wearing: " if on else "") + lbl, func() -> void:
				p.title = "" if on else lbl
				Game.save_player_career_soon()
				_build_topbar()
				_show(_page), 0, "PrimaryButton" if on else "GhostButton"))
		tc.add_child(tflow0)

	var tl := UI.card(page, "Career timeline", false, UI.ACCENT)
	tl.add_child(UI.table_header(TIMELINE_COLS))
	for i in w.timeline.size():
		var e: Dictionary = w.timeline[i]
		var em := int(e.m)
		var current := i == w.timeline.size() - 1 and not w.retired
		tl.add_child(UI.table_row([UI.label("S%d" % int(e.s), 14, UI.TEXT_DIM, 600), UI.label(String(e.team) + ("  (now)" if current else ""), 14, UI.ACCENT2 if current else UI.TEXT, 600),
			UI.label(World.LEAGUES[int(e.league)].short, 13, UI.TEXT_DIM), UI.label(str(em), 14),
			UI.label("%.2f" % (float(e.k) / maxf(1.0, float(e.d))) if em > 0 else "-", 14),
			UI.label("%.2f" % (float(e.r_sum) / em) if em > 0 else "-", 14, UI.GOOD if em > 0 and float(e.r_sum) / em >= 1.0 else UI.TEXT),
			UI.label("#%d" % int(e.pos) if int(e.pos) > 0 else "-", 14, UI.TEXT_DIM), UI.label(str(int(e.titles)), 14, UI.WARN if int(e.titles) > 0 else UI.TEXT_FAINT)], TIMELINE_COLS, i, current))

	var row2 := UI.hbox(14)
	page.add_child(row2)
	var trc := UI.card(page, "Signature traits (earned by how you play)", false, UI.WARN)
	var tflow := HFlowContainer.new()
	tflow.add_theme_constant_override("h_separation", 8)
	tflow.add_theme_constant_override("v_separation", 8)
	for id: String in World.TRAITS:
		var info: Dictionary = World.TRAITS[id]
		var has := w.traits.has(id)
		var tp := PanelContainer.new()
		tp.custom_minimum_size = Vector2(230, 0)
		tp.add_theme_stylebox_override("panel", UI._box(Color(UI.WARN, 0.1) if has else UI.PANEL_LO, 4, UI.WARN if has else UI.BORDER, 1, 10, 6))
		var tv := UI.vbox(1)
		tv.add_child(UI.label(String(info.name), 13, UI.WARN if has else UI.TEXT_DIM, 700))
		tv.add_child(_wrap(String(info.need), 11, UI.TEXT_DIM if has else UI.TEXT_FAINT))
		tp.add_child(tv)
		tflow.add_child(tp)
	trc.add_child(tflow)
	page.move_child(trc.get_parent(), page.get_child_count() - 2)
	var pk := UI.card(row2, "Perks", false, UI.ACCENT2)
	pk.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for id: String in World.PERKS:
		grid.add_child(_perk_tile(id))
	pk.add_child(grid)
	var rv := UI.card(row2, "Rivalries", false, UI.WARN)
	rv.get_parent().custom_minimum_size = Vector2(420, 0)
	var keys: Array = w.rivals.keys()
	keys.sort_custom(func(a: int, b: int) -> bool: return int(w.rivals[a].w) + int(w.rivals[a].l) > int(w.rivals[b].w) + int(w.rivals[b].l))
	if keys.is_empty():
		rv.add_child(UI.label("The best opponent in each of your matches is tracked here, head to head.", 13, UI.TEXT_DIM))
	else:
		rv.add_child(UI.table_header(RIVAL_COLS))
	for i in mini(8, keys.size()):
		var e: Dictionary = w.rivals[keys[i]]
		var met := int(e.w) + int(e.l)
		rv.add_child(UI.table_row([UI.label(String(e.name), 14, UI.WARN if met >= 3 else UI.TEXT, 600), UI.label(String(e.team), 13, UI.TEXT_DIM),
			UI.label(str(met), 14), UI.label("%d-%d" % [int(e.w), int(e.l)], 14, UI.GOOD if int(e.w) > int(e.l) else (UI.BAD if int(e.l) > int(e.w) else UI.TEXT))], RIVAL_COLS, i))
	var fr: Array = w.soc().friends()
	rv.add_child(UI.divider())
	var fl := _wrap("Friends: " + (", ".join(fr.map(func(x: PlayerData) -> String: return x.player_name)) if not fr.is_empty() else "none yet. Time as teammates, friendly DMs and supportive posts build friendships."), 12, UI.GOOD if not fr.is_empty() else UI.TEXT_FAINT)
	rv.add_child(fl)
	_content.add_child(UI.scroll(page))


func _club_count() -> int:
	var clubs := {}
	for e in w.timeline:
		clubs[String(e.team)] = true
	return clubs.size()


func _trophy_tile(t: Dictionary) -> Control:
	var place := int(t.place)
	var col: Color = UI.WARN if place == 1 else (Color("c0c7d4") if place == 2 else UI.GOOD)
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(170, 0)
	p.add_theme_stylebox_override("panel", UI._box(Color(col, 0.1), 4, col, 1, 10, 6))
	var v := UI.vbox(1)
	v.add_child(UI.caption("Winner" if place == 1 else ("Runner-up" if place == 2 else "Promoted"), col))
	var n := UI.label(String(t.name), 13, UI.TEXT, 700)
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(n)
	v.add_child(UI.label("Season %d  -  %s" % [int(t.s), t.team], 11, UI.TEXT_DIM))
	p.add_child(v)
	return p


func _perk_tile(id: String) -> Control:
	var info: Dictionary = World.PERKS[id]
	var has := w.perks.has(id)
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_theme_stylebox_override("panel", UI._box(Color(UI.ACCENT2, 0.1) if has else UI.PANEL_LO, 4, UI.ACCENT2 if has else UI.BORDER, 1, 10, 6))
	var v := UI.vbox(1)
	v.add_child(UI.label(String(info.name), 13, UI.ACCENT2 if has else UI.TEXT_DIM, 700))
	var d := _wrap(String(info.desc) if has else "Locked: " + String(info.need), 11, UI.TEXT_DIM if has else UI.TEXT_FAINT)
	v.add_child(d)
	p.add_child(v)
	p.tooltip_text = "%s\n%s\nUnlock: %s" % [info.name, info.desc, info.need]
	return p


func _legacy_card(parent: Control) -> void:
	var lg: Dictionary = w.legacy
	var c := UI.card(parent, "Legacy", false, UI.WARN)
	var h := UI.hbox(20)
	var v := UI.vbox(0)
	v.add_child(UI.label(String(lg.get("tier", "?")), 30, UI.WARN, 700))
	v.add_child(UI.label("Retired at %d after %d season%s  -  legacy score %d" % [int(lg.get("age", 0)), int(lg.get("seasons", 0)), "s" if int(lg.get("seasons", 0)) != 1 else "", int(lg.get("score", 0))], 14, UI.TEXT_DIM))
	h.add_child(v)
	h.add_child(UI.spacer())
	var club := w.user_team().team_name
	h.add_child(UI.button("Coach %s" % club, func() -> void:
		var go := func() -> void:
			Game.save_player_career()
			Game.coach_from_player()
			Game.goto(Game.MANAGER_SCENE)
		if Game.world != null:
			_confirm("Replace your manager career?", "Coaching %s starts a new manager career and replaces the one you have saved." % club, "Coach them", go)
		else:
			go.call(), 230, "PrimaryButton"))
	h.add_child(UI.button("New manager career", func() -> void:
		Game.save_player_career()
		Game.goto(Game.MANAGER_SETUP_SCENE), 200, "GhostButton"))
	c.add_child(h)
	c.add_child(UI.label("Hall of Famer 1400+  -  Legend 900+  -  Respected Pro 550+  -  Journeyman 350+", 12, UI.TEXT_FAINT))


# =============================================================================
# Training
# =============================================================================

func _training() -> void:
	var p := w.user_player
	_page_title("Training", "One session a week. Specialise after %d matches." % World.SPECIALTY_MATCHES)
	var cols := UI.hbox(14)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(cols)
	var at := UI.card(cols, "Attributes", true, UI.ACCENT2)
	at.get_parent().custom_minimum_size = Vector2(420, 0)
	var changes: Dictionary = w.last_report.get("changes", {})
	for k: String in PlayerData.STAT_KEYS:
		var row := UI.stat_row(k, p.stat(k), float(changes.get(k, 0.0)))
		if w.specialty != "" and (World.SPECIALTIES[w.specialty] as Array).has(k):
			row.add_child(UI.pill("Spec", UI.ACCENT2, 10))
		at.add_child(row)
	at.add_child(UI.label("Rating %d  -  K/D %.2f  -  %d matches" % [p.rating(), p.career_kd(), p.matches_played], 13, UI.TEXT_DIM))

	var right := UI.vbox(14)
	cols.add_child(UI.scroll(right))
	var tc := UI.card(right, "This week's session", false, UI.ACCENT)
	if w.trained_this_week:
		var lt: Dictionary = w.last_training
		var txt := "Done this week."
		if lt.has("key"):
			txt = "Done: %s (%s) %+.1f.  %s" % [PlayerData.STAT_NAMES[lt.key], lt.intensity, float(lt.delta), String(lt.get("note", ""))]
		tc.add_child(UI.label(txt, 14, UI.TEXT_DIM))
	elif not p.available():
		tc.add_child(UI.label("You're injured or ill: no training until you're fit.", 14, UI.BAD))
	else:
		var row := UI.hbox(8)
		_train_pick = OptionButton.new()
		_train_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for k: String in PlayerData.STAT_KEYS:
			_train_pick.add_item(PlayerData.STAT_NAMES[k] + ("  (specialty)" if w.specialty != "" and (World.SPECIALTIES[w.specialty] as Array).has(k) else ""))
		row.add_child(_train_pick)
		tc.add_child(row)
		var ir := UI.hbox(8)
		for it: String in World.PM_INTENSITY:
			var itn := it
			ir.add_child(UI.small_button(it, func() -> void:
				_intensity = itn
				_refresh(), 90, "PrimaryButton" if it == _intensity else "GhostButton"))
		var idl := _wrap(String(World.PM_INTENSITY[_intensity].desc), 12, UI.TEXT_DIM)
		idl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ir.add_child(idl)
		tc.add_child(ir)
		tc.add_child(UI.button("Train", func() -> void:
			var key: String = PlayerData.STAT_KEYS[_train_pick.selected]
			var d := Game.train(key, _intensity)
			var note := String(w.last_training.get("note", ""))
			_refresh("Training %s: %+.1f%s" % [PlayerData.STAT_NAMES[key], d, ("  " + note) if note != "" else ("  (bad session)" if d < 0 else "")], d < 0 or note != ""), 180, "PrimaryButton"))
	var bonus: Array = []
	if w.setup_level > 0:
		bonus.append("Setup L%d +%d%%" % [w.setup_level, w.setup_level * 12])
	if w.perks.has("grinder"):
		bonus.append("Grinder +20%")
	if w.specialty != "":
		bonus.append("Specialty stats +35%")
	if w.coach_booked:
		bonus.append("Personal coach booked: +50%, steadier")
	tc.add_child(UI.label("Bonuses: " + (", ".join(bonus) if not bonus.is_empty() else "none yet"), 12, UI.TEXT_FAINT))

	var sc := UI.card(right, "Specialty", false, UI.ACCENT2)
	if p.matches_played < World.SPECIALTY_MATCHES:
		sc.add_child(UI.label("Unlocks after %d matches (%d so far). Specialty stats train 35%% faster." % [World.SPECIALTY_MATCHES, p.matches_played], 13, UI.TEXT_DIM))
	else:
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		for s: String in World.SPECIALTIES:
			var sn := s
			var stats := ", ".join((World.SPECIALTIES[s] as Array).map(func(k: String) -> String: return PlayerData.STAT_NAMES[k]))
			var b := UI.small_button(s, func() -> void:
				var cost := World.RESPEC_COST if w.specialty != "" else 0
				if cost > 0:
					_confirm("Switch to %s?" % sn, "Changing specialty costs %s from your wallet." % UI.money_text(cost), "Switch", func() -> void: _act(w.choose_specialty(sn), "You're now a %s." % sn))
				else:
					_act(w.choose_specialty(sn), "You're now a %s." % sn), 0, "PrimaryButton" if s == w.specialty else "GhostButton")
			b.tooltip_text = stats
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(b)
		sc.add_child(grid)
		sc.add_child(UI.label(("Current: %s. Switching costs %s." % [w.specialty, UI.money_text(World.RESPEC_COST)]) if w.specialty != "" else "Pick one (free). Hover for the stats it boosts.", 12, UI.TEXT_FAINT))

	var stc := UI.card(right, "Streaming", false, UI.ACCENT2)
	var sr := UI.hbox(8)
	for lv: String in World.STREAM:
		var lvn := lv
		sr.add_child(UI.small_button(lv, func() -> void:
			w.set_stream(lvn)
			_refresh("Streaming: %s." % lvn), 90, "PrimaryButton" if lv == w.stream_level else "GhostButton"))
	var sdl := _wrap(String(World.STREAM[w.stream_level].desc), 12, UI.TEXT_DIM)
	sdl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sr.add_child(sdl)
	stc.add_child(sr)
	var fr := UI.hbox(20)
	fr.add_child(UI.stat_chip("Stream income", UI.money_text(w.stream_income()) + " / wk", UI.GOOD))
	fr.add_child(UI.stat_chip("Fatigue", "%d / 100" % int(w.fatigue), UI.GOOD if w.fatigue < 40 else (UI.WARN if w.fatigue < 70 else UI.BAD)))
	stc.add_child(fr)
	stc.add_child(UI.label("Fatigue over 40 drags your form down and raises injury risk. Hard training adds to it; resting clears it.", 11, UI.TEXT_FAINT))
	var shop := UI.card(right, "Invest in yourself", false, UI.GOOD)
	var r1 := UI.hbox(8)
	r1.add_child(UI.label("Gaming setup  L%d / %d" % [w.setup_level, World.SETUP_COSTS.size()], 14))
	r1.add_child(UI.label("+12% training per level", 12, UI.TEXT_FAINT))
	r1.add_child(UI.spacer())
	var up := UI.small_button("Maxed" if w.setup_level >= World.SETUP_COSTS.size() else "Upgrade  " + UI.money_text(w.setup_cost()), func() -> void: _act(w.buy_setup(), "Setup upgraded."), 170, "PrimaryButton")
	up.disabled = w.setup_level >= World.SETUP_COSTS.size()
	r1.add_child(up)
	shop.add_child(r1)
	var r2 := UI.hbox(8)
	r2.add_child(UI.label("Personal coach", 14))
	r2.add_child(UI.label("next session +50% and steadier", 12, UI.TEXT_FAINT))
	r2.add_child(UI.spacer())
	var cb := UI.small_button("Booked" if w.coach_booked else "Book  " + UI.money_text(w.coach_cost()), func() -> void: _act(w.book_coach(), "Coach booked for your next session."), 170, "PrimaryButton")
	cb.disabled = w.coach_booked
	r2.add_child(cb)
	shop.add_child(r2)
	shop.add_child(UI.label("Wallet: %s" % UI.money_text(w.wallet), 12, UI.TEXT_DIM))


# =============================================================================
# Career: contract, money, transfers
# =============================================================================

func _career() -> void:
	var p := w.user_player
	var ut := w.user_team()
	_page_title("Career", "Your contract, money and moves")
	var page := UI.vbox(14)
	_content.add_child(UI.scroll(page))
	if w.free_agency:
		_banner(page, "Free agent: accept one of the offers below to join a club. Moves are allowed now.", UI.WARN)
	if w.teamless or soc_needs_card():
		_comeback_card(page)
	var cols := UI.hbox(14)
	page.add_child(cols)
	var cc := UI.card(cols, "Contract", false, UI.ACCENT)
	cc.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_line(cc, "Club", "Free agent" if w.free_agency or w.teamless else ut.team_name, UI.WARN if w.teamless else UI.ACCENT2)
	_line(cc, "Wage", UI.money_text(p.salary) + " / wk")
	if not w.teamless:
		_line(cc, "Runs until", "End of season %d%s" % [p.contract_until, "  (final season)" if p.contract_until <= w.season else ""], UI.WARN if p.contract_until <= w.season else UI.TEXT)
	var talks := "Not yet (week 12 of your final season)"
	if p.contract_until > w.season:
		talks = "Settled"
	elif w.renewal_done:
		talks = "Over: free agency at season end"
	elif w.week >= 12:
		talks = "Offer in your inbox"
	if not w.teamless:
		_line(cc, "Renewal talks", talks)
	_line(cc, "Coach trust", "%d / 100" % int(w.coach_trust), _trust_color(w.coach_trust))
	var soc := w.soc()
	var standing: String = ["Good", "Warned", "Final warning"][mini(soc.strikes, 2)]
	_line(cc, "Club standing", standing if not w.teamless else "-", UI.GOOD if soc.strikes == 0 else (UI.WARN if soc.strikes == 1 else UI.BAD))
	_line(cc, "Online reputation", "Clean" if soc.toxicity < 20.0 else ("Edgy" if soc.toxicity < 45.0 else "Toxic"), UI.GOOD if soc.toxicity < 20.0 else (UI.WARN if soc.toxicity < 45.0 else UI.BAD))
	cc.add_child(_wrap("Trust rises with good games, goals and loyalty; it drives your lineup spot and contract offers. Bad form, toxic posts, fights with the coach and sulking earn warnings, then the bench, then release.", 12, UI.TEXT_FAINT))
	var mc := UI.card(cols, "Money", false, UI.GOOD)
	mc.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_line(mc, "Wallet", UI.money_text(w.wallet), UI.GOOD)
	_line(mc, "Wage", UI.money_text(p.salary) + " / wk")
	_line(mc, "Endorsements", UI.money_text(w.endorsement_income()) + " / wk")
	_line(mc, "Streaming", UI.money_text(w.stream_income()) + " / wk")
	_line(mc, "Lifestyle upkeep", UI.money_text(-w.lifestyle_upkeep()) + " / wk", UI.BAD if w.lifestyle_upkeep() > 0 else UI.TEXT)
	mc.add_child(UI.divider())
	if w.agent_cut() > 0:
		_line(mc, "Agent cut", UI.money_text(-w.agent_cut()) + " / wk", UI.BAD)
	var net := w.weekly_pay() + w.stream_income() - w.lifestyle_upkeep() - w.agent_cut()
	_line(mc, "Net", UI.money_text(net) + " / wk", UI.GOOD if net >= 0 else UI.BAD)
	mc.add_child(UI.caption("Personal deals"))
	if w.endorsements.is_empty():
		mc.add_child(_wrap("None yet. Brands come knocking from 1.5k followers.", 13, UI.TEXT_DIM))
	for d in w.endorsements:
		_line(mc, String(d.brand), "%s / wk  -  %d wk left" % [UI.money_text(int(d.weekly)), int(d.weeks)])

	_clubs_card(page)
	var agc := UI.card(page, "Agent", false, UI.ACCENT2)
	var cur := w.agent_info()
	var ah := UI.hbox(10)
	ah.add_child(UI.label(String(cur.name), 16, UI.ACCENT2, 700))
	var ad := _wrap(String(cur.desc), 12, UI.TEXT_DIM)
	ad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ah.add_child(ad)
	if w.agent_cut() > 0:
		ah.add_child(UI.label("Cut %s / wk" % UI.money_text(w.agent_cut()), 13, UI.WARN, 600))
	agc.add_child(ah)
	var agrid := HFlowContainer.new()
	agrid.add_theme_constant_override("h_separation", 8)
	agrid.add_theme_constant_override("v_separation", 8)
	for id: String in World.AGENTS:
		if id == "none" or id == w.agent:
			continue
		var a: Dictionary = World.AGENTS[id]
		var idd := id
		var b := UI.small_button("Hire %s  %s" % [a.name, UI.money_text(int(a.fee))], func() -> void: _act(w.hire_agent(idd), "%s now represents you." % String(World.AGENTS[idd].name)), 0, "GhostButton")
		b.tooltip_text = String(a.desc)
		agrid.add_child(b)
	if w.agent != "none":
		agrid.add_child(UI.small_button("Release agent", func() -> void:
			w.agent = "none"
			_refresh("You're negotiating for yourself again."), 0, "GhostButton"))
	agc.add_child(agrid)
	var lc := UI.card(page, "Lifestyle", false, UI.WARN)
	var lr := UI.hbox(10)
	var ll := _wrap("Homes, cars, pets, staff, weapon finishes and investments are in the Shop. Upkeep: %s / wk." % UI.money_text(w.lifestyle_upkeep()), 13, UI.TEXT_DIM)
	ll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lr.add_child(ll)
	lr.add_child(UI.small_button("Open the Shop", func() -> void: _show("Shop"), 150, "PrimaryButton"))
	lr.add_child(UI.small_button("Go home", func() -> void: ShopView.go_home(), 110, "GhostButton"))
	lc.add_child(lr)
	var tc := UI.card(page, "Transfers", false, UI.ACCENT2)
	var head := UI.hbox(10)
	if w.free_agency:
		head.add_child(UI.label("Choose your next club.", 14, UI.WARN, 600))
	elif w.teamless:
		head.add_child(UI.label("No club: you can accept any offer below straight away.", 14, UI.WARN, 600))
	elif w.transfer_request:
		head.add_child(UI.pill("Transfer requested", UI.WARN))
		var hl := _wrap("Clubs know you want out. Offers can only be accepted in a window.", 13, UI.TEXT_DIM)
		hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(hl)
		head.add_child(UI.spacer())
		head.add_child(UI.small_button("Withdraw request", func() -> void:
			w.cancel_transfer_request()
			_refresh("Request withdrawn."), 170, "GhostButton"))
	else:
		var hl2 := _wrap("Strong form gets you noticed. Or ask to leave; the club may say no.", 13, UI.TEXT_DIM)
		hl2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(hl2)
		head.add_child(UI.spacer())
		head.add_child(UI.small_button("Request a transfer", func() -> void:
			_confirm("Request a transfer?", "The club may refuse, especially if you're one of their best. Either way the coach's trust drops a little.", "Request", func() -> void:
				var res := w.request_transfer()
				_refresh(res, not w.transfer_request)), 180, "PrimaryButton"))
	tc.add_child(head)
	if w.offers.is_empty():
		tc.add_child(UI.label("No offers right now.", 14, UI.TEXT_DIM))
	for i in w.offers.size():
		var o: Dictionary = w.offers[i]
		var t: TeamData = w.teams[int(o.team)]
		var row := UI.hbox(10)
		var tl := UI.team_link(t, _view_team.bind(t), 15, t == ut)
		tl.custom_minimum_size.x = 200
		row.add_child(tl)
		row.add_child(UI.pill(World.LEAGUES[t.league].short, UI.TEXT_DIM, 11))
		row.add_child(UI.rating_chip(t.rating(), 12))
		var nl := UI.label(String(o.note), 12, UI.TEXT_FAINT)
		nl.clip_text = true
		nl.tooltip_text = String(o.note)
		nl.mouse_filter = Control.MOUSE_FILTER_PASS
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nl)
		var wage := int(o.wage)
		row.add_child(UI.label("%s / wk" % UI.money_text(wage), 14, UI.GOOD if wage > p.salary else UI.TEXT, 600))
		row.add_child(UI.label("%d season%s" % [int(o.years), "s" if int(o.years) > 1 else ""], 13, UI.TEXT_DIM))
		var idx := i
		row.add_child(UI.small_button("Details", func() -> void: _view_offer(idx), 90, "GhostButton"))
		row.add_child(UI.small_button("Accept", func() -> void:
			var err := w.accept_offer(idx)
			_act(err, "Welcome to %s!" % w.user_team().team_name), 90, "PrimaryButton"))
		row.add_child(UI.small_button("Decline", func() -> void: _act(w.decline_offer(idx), "Offer declined."), 90, "GhostButton"))
		tc.add_child(row)


# =============================================================================
# Team, league, tournaments
# =============================================================================

func _team() -> void:
	var ut := w.user_team()
	if w.teamless:
		_page_title("Team", "You don't have a club")
		_banner(_content, "You were released by %s. Find a way back on the Career page: showmatches, trials, stand-in calls and your agent." % ut.team_name, UI.WARN, "Ways back", func() -> void: _show("Career"))
		return
	_page_title(ut.team_name, "%s  -  #%d  -  coach trust in you: %d" % [w.league_name(ut), w.standings(ut.league).find(ut) + 1, int(w.coach_trust)])
	var page := UI.vbox(14)
	_content.add_child(UI.scroll(page))
	var c := UI.card(page, "Squad (top five start)", false, UI.ACCENT2)
	c.add_child(UI.squad_table(ut.roster, w.user_player, 5, _view_player))
	var dr := UI.card(page, "Dressing room: friends give you both a match-day lift, rivals in your own squad the opposite", false, UI.ACCENT2)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	for mate in ut.roster:
		if mate.is_user:
			continue
		var v := w.relation(mate.uid)
		var col := UI.GOOD if v >= 20 else (UI.BAD if v <= -20 else UI.TEXT_DIM)
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", UI._box(UI.PANEL_LO, 4, Color(col, 0.6), 1, 10, 4))
		var h := UI.hbox(8)
		var nb := UI.link_button(mate.player_name, _view_player.bind(mate), 14)
		nb.clip_text = false
		h.add_child(nb)
		h.add_child(UI.label("%s %+d" % [World.relation_text(v), int(v)], 12, col, 600))
		pc.add_child(h)
		flow.add_child(pc)
	dr.add_child(flow)
	var s := UI.card(page, "Season stats", false, UI.TEXT_DIM)
	s.add_child(UI.team_stats_table(ut.roster, w.user_player, _view_player))


const LEAGUE_COLS := [["#", 30, "c"], ["Team", 0, "l"], ["W", 40, "c"], ["L", 40, "c"], ["RD", 50, "c"], ["RTG", 48, "c"], ["", 110, "c"]]


func _league() -> void:
	if _league_view < 0:
		_league_view = w.user_team().league
	_page_title("League", "Top %d make the playoffs  -  top %d go up, bottom %d go down" % [World.PLAYOFF_SIZE, World.PROMOTE, World.PROMOTE])
	var bar := UI.hbox(8)
	_content.add_child(bar)
	for l in World.LEAGUES.size():
		var li := l
		bar.add_child(UI.small_button(World.LEAGUES[l].name, func() -> void:
			_league_view = li
			_refresh(), 170, "PrimaryButton" if l == _league_view else ""))
	var card := UI.card(_content, "", true)
	card.add_child(UI.table_header(LEAGUE_COLS))
	var list := UI.vbox(2)
	var table := w.standings(_league_view)
	for i in table.size():
		var t: TeamData = table[i]
		var zone: Control = UI.label("", 12)
		if _league_view > 0 and i < World.PROMOTE:
			zone = UI.pill("Promotion", UI.GOOD, 11)
		elif _league_view < World.LEAGUES.size() - 1 and i >= table.size() - World.PROMOTE:
			zone = UI.pill("Relegation", UI.BAD, 11)
		elif i < World.PLAYOFF_SIZE:
			zone = UI.pill("Playoffs", UI.ACCENT2, 11)
		var mine := t == w.user_team()
		list.add_child(UI.table_row([UI.label(str(i + 1), 14, UI.TEXT_DIM, 600), UI.team_link(t, _view_team.bind(t), 14, mine),
			UI.label(str(t.wins), 14, UI.TEXT, 600), UI.label(str(t.losses), 14, UI.TEXT_DIM),
			UI.label("%+d" % t.round_diff, 14, UI.GOOD if t.round_diff > 0 else (UI.BAD if t.round_diff < 0 else UI.TEXT_DIM)),
			UI.rating_chip(t.rating()), zone], LEAGUE_COLS, i, mine))
	card.add_child(UI.scroll(list))
	card.add_child(UI.label("Click a team for its squad and season stats.", 12, UI.TEXT_FAINT))


func _tournaments() -> void:
	_page_title("Tournaments", "Your club picks the cups; league playoffs are automatic for the top %d." % World.PLAYOFF_SIZE)
	var list := UI.vbox(12)
	var ui := w.team_index(w.user_team())
	for t in w.tournaments:
		var p := PanelContainer.new()
		var box := UI.vbox(8)
		p.add_child(box)
		var head := UI.hbox(10)
		box.add_child(head)
		head.add_child(UI.label(String(t.name), 19, UI.TEXT, 700))
		if t.kind == "cup":
			head.add_child(UI.pill(String(t.tier), {"Open": UI.TEXT_DIM, "Challenger": UI.ACCENT2, "Major": Color("c084fc")}[t.tier]))
			head.add_child(UI.pill("Weeks %d-%d" % [t.start_week, int(t.start_week) + 3], UI.TEXT_DIM))
		else:
			head.add_child(UI.pill("Playoffs", UI.ACCENT))
			head.add_child(UI.pill("Weeks %d-%d" % [t.start_week, int(t.start_week) + 2], UI.TEXT_DIM))
		head.add_child(UI.spacer())
		if t.status == "upcoming":
			head.add_child(UI.pill("Your club is entered" if t.user_enrolled else "Not entered", UI.GOOD if t.user_enrolled else UI.TEXT_FAINT))
		else:
			if t.status == "done":
				var champ: TeamData = w.teams[w._team_with_place(t, 1)]
				head.add_child(UI.label("Champion", 12, UI.TEXT_DIM))
				head.add_child(UI.team_link(champ, _view_team.bind(champ), 14, champ == w.user_team()))
			if t.placements.has(ui):
				head.add_child(UI.pill("You: " + World._place_name(t.placements[ui]), UI.WARN))
			elif t.teams.has(ui):
				head.add_child(UI.pill("You're still in", UI.GOOD))
			box.add_child(UI.bracket(w, t, _view_team))
			if t.status == "running":
				box.add_child(_watch_row(t))
		list.add_child(p)
	_content.add_child(UI.scroll(list))


# =============================================================================
# Popups
# =============================================================================

func _view_player(p: PlayerData) -> void:
	var m := UI.player_card(self, w, p)
	var overlay: Control = m[0]
	overlay.set_meta("modal", true)
	var row := UI.hbox(10)
	row.add_child(UI.button("Close", func() -> void: overlay.queue_free(), 140, "GhostButton"))
	row.add_child(UI.spacer())
	if not p.is_user and not w.retired:
		row.add_child(UI.button("Message", func() -> void:
			_social.thread = w.soc().open_thread(p)
			_close_modals()
			overlay.queue_free()
			_show("Messages"), 150, "PrimaryButton"))
	row.add_child(UI.button("Rename", func() -> void: _rename_player(p), 150))
	(m[1] as VBoxContainer).add_child(row)


func _view_team(t: TeamData) -> void:
	var m := UI.team_popup(self, w, t, w.user_player, _view_player)
	var overlay: Control = m[0]
	overlay.set_meta("modal", true)
	var row := UI.hbox(10)
	row.add_child(UI.button("Close", func() -> void: overlay.queue_free(), 140, "GhostButton"))
	row.add_child(UI.spacer())
	row.add_child(UI.button("Rename team", func() -> void: _rename_team(t), 170))
	(m[1] as VBoxContainer).add_child(row)


## Any player or team in the world (your own included). Stats and history stay.
func _rename_player(p: PlayerData) -> void:
	UI.text_prompt(self, "Rename player", [["Name", p.player_name, 18]], func(vals: Array) -> String:
		var err := w.rename_player(p, String(vals[0]))
		if err == "":
			_close_modals()
			_refresh("Renamed to %s." % p.player_name)
		return err)


func _rename_team(t: TeamData) -> void:
	UI.text_prompt(self, "Rename team", [["Name", t.team_name, 24], ["Tag (up to 4 letters)", t.short_name, 4]], func(vals: Array) -> String:
		var err := w.rename_team(t, String(vals[0]), String(vals[1]))
		if err == "":
			_close_modals()
			_refresh("Renamed to %s." % t.team_name)
		return err)


func _close_modals() -> void:
	for c in get_children():
		if c.has_meta("modal"):
			c.queue_free()


## Offer details: the club, where you'd fit in their lineup, the terms.
func _view_offer(idx: int) -> void:
	var o: Dictionary = w.offers[idx]
	var t: TeamData = w.teams[int(o.team)]
	var m := UI.team_popup(self, w, t, null, _view_player)
	var overlay: Control = m[0]
	var box: VBoxContainer = m[1]
	var me := w.user_player
	var better := 0
	for pl: PlayerData in t.roster:
		if pl.rating_exact() > me.rating_exact() and not pl.is_user:
			better += 1
	var row := UI.hbox(10)
	row.add_child(UI.pill("Likely starter" if better < 5 else "Bench risk", UI.GOOD if better < 5 else UI.WARN))
	row.add_child(UI.label(("You'd be #%d of their squad by rating." % (better + 1)), 14, UI.TEXT_DIM))
	row.add_child(UI.spacer())
	row.add_child(UI.label("%s / wk for %d season%s" % [UI.money_text(int(o.wage)), int(o.years), "s" if int(o.years) > 1 else ""], 15, UI.GOOD, 700))
	box.add_child(row)
	box.add_child(UI.label(String(o.get("note", "")), 13, UI.TEXT_FAINT))
	box.add_child(UI.divider())
	var btns := UI.hbox(10)
	btns.add_child(UI.button("Close", func() -> void: overlay.queue_free(), 140, "GhostButton"))
	btns.add_child(UI.spacer())
	btns.add_child(UI.button("Decline", func() -> void:
		overlay.queue_free()
		_act(w.decline_offer(idx), "Offer declined."), 140, "GhostButton"))
	btns.add_child(UI.button("Accept offer", func() -> void:
		overlay.queue_free()
		var err := w.accept_offer(idx)
		_act(err, "Welcome to %s!" % w.user_team().team_name), 200, "PrimaryButton"))
	box.add_child(btns)



# =============================================================================
# Feed and live viewing
# =============================================================================

const FEED_COLORS := {"fan": Color("8b94a7"), "press": Color("fbbf24"), "rival": Color("f87171"), "teammate": Color("4ade80"),
	"club": Color("38d0ff"), "brand": Color("c084fc"), "toxic": Color("ef4444")}


func _social_cb() -> Dictionary:
	return {"refresh": func() -> void: _refresh(), "toast": func(msg: String, bad: bool) -> void: _toast_msg(msg, bad),
		"llm": _run_llm, "player": _view_player, "screen": self}


func _toast_msg(msg: String, bad: bool) -> void:
	_pending_toast = [msg, bad]


var _pending_toast: Array = []


## Rewrites queued chat lines with the local LLM (optional). The game effects
## are already applied; on failure the template line simply stays.
func _run_llm() -> void:
	var jobs := w.soc().take_llm_jobs()
	if jobs.is_empty():
		return
	if _llm == null:
		_llm = LlmClient.new()
		add_child(_llm)
	_llm_queue.append_array(jobs)
	_llm_next()


var _llm_queue: Array = []


## One reply at a time, so a group chat's second speaker sees what the first one said.
func _llm_next() -> void:
	if _llm_queue.is_empty() or _llm.busy > 0:
		return
	var j: Dictionary = _llm_queue.pop_front()
	var msg: Dictionary = j.msg
	var hist: Array = w.soc().llm_history(j.th, msg) if j.has("th") else []
	_llm.chat(String(j.system), String(j.user), func(t: String) -> void:
		if t != "":
			msg.text = t
			msg.llm = true
		msg.erase("pending")
		Game.save_player_career_soon()
		if is_inside_tree():
			if _page == "Feed" and _llm_queue.is_empty():
				_show(_page)
			_llm_next(), 60, hist)


var _feed_shown := -1 ## Feed entries visible at the last build (new replies landing trigger a rebuild).


var _msgs_shown := -1 ## Messages visible (and typing state) at the last build of the Messages page.


func _msgs_state() -> int:
	var s := w.soc()
	var n := 0
	for th: Dictionary in s.threads.values():
		for m: Dictionary in th.msgs:
			if Social.landed(m, w.season, w.week) and not bool(m.get("pending", false)):
				n += 1
		if s.typing_in(th) != "":
			n += 100000
	return n


func _feed_tick() -> void:
	if _page == "Messages":
		var st := _msgs_state()
		if _msgs_shown >= 0 and st != _msgs_shown:
			_show(_page)
		_msgs_shown = st
		return
	_msgs_shown = -1
	if _page != "Feed":
		_feed_shown = -1
		return
	if _feed_shown < 0:
		_feed_shown = SocialView.visible_count(w)
		return
	if SocialView.tick(w, self, _feed_shown):
		var f := get_viewport().gui_get_focus_owner()
		if f is LineEdit:
			return # Don't rebuild under someone typing; catch up after.
		_feed_shown = SocialView.visible_count(w)
		_show(_page)


## A hub that closed mid-request leaves "typing..." flags behind: clear them.
func _clear_pending() -> void:
	for th: Dictionary in w.soc().threads.values():
		for m: Dictionary in th.msgs:
			m.erase("pending")
	for f: Dictionary in w.feed:
		f.erase("pending")


func soc_needs_card() -> bool:
	return w.soc().trial_team() != null or (not w.retired and not w.user_starting() and w.user_player.available())


## Showmatches, trials and (without a club) how close you are to a way back.
func _comeback_card(parent: Control) -> void:
	var s := w.soc()
	var c := UI.card(parent, "Ways back" if w.teamless else "Showmatch", false, UI.WARN)
	if w.teamless:
		var chips := HFlowContainer.new()
		chips.add_theme_constant_override("h_separation", 24)
		chips.add_child(UI.stat_chip("Club interest", "%d / 100" % int(s.comeback), UI.GOOD if s.comeback >= 50.0 else (UI.WARN if s.comeback >= 25.0 else UI.BAD)))
		chips.add_child(UI.stat_chip("Without a club", "%d wk" % s.weeks_teamless))
		chips.add_child(UI.stat_chip("Agent", String(w.agent_info().name), UI.ACCENT2))
		chips.add_child(UI.stat_chip("Offers", str(w.offers.size()), UI.GOOD if not w.offers.is_empty() else UI.TEXT_DIM))
		chips.add_child(UI.stat_chip("Reputation", "Clean" if s.toxicity < 20.0 else ("Edgy" if s.toxicity < 45.0 else "Toxic"), UI.GOOD if s.toxicity < 20.0 else UI.BAD))
		c.add_child(chips)
		c.add_child(_wrap("Your agent pitches you every week: lower leagues first, better clubs as interest grows. Trial invites and stand-in calls (teams with an injured player) arrive in your inbox. Toxic behaviour scares clubs off; an agent widens the net.", 12, UI.TEXT_DIM))
	var tt := s.trial_team()
	if tt != null:
		var tr := UI.hbox(10)
		var tl := _wrap("Trial at %s: play their practice match. A good showing earns a contract offer." % tt.team_name, 13, UI.TEXT)
		tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tr.add_child(tl)
		var block := s.can_showmatch()
		var pb := UI.small_button("Play trial match", func() -> void:
			if Game.prepare_showmatch("trial"):
				Game.goto(Game.MATCH_SCENE), 150, "PrimaryButton")
		pb.disabled = block != ""
		tr.add_child(pb)
		var sb := UI.small_button("Simulate trial", func() -> void:
			var res := s.sim_showmatch("trial")
			_refresh(String(s.last_show.get("note", "")))
			_show_results(res), 130)
		sb.disabled = block != ""
		tr.add_child(sb)
		c.add_child(tr)
	var row := UI.hbox(10)
	var why := s.can_showmatch()
	var txt := "Showmatch (PUG): an exhibition with players around your level. It doesn't count, but scouts and coaches watch: play well to raise interest." if w.teamless \
		else "Showmatch (PUG): out of the five? Play an exhibition this week. Doesn't count for stats; a good game catches the coach's eye."
	var dl := _wrap(txt if why == "" else "%s  (%s)" % [txt, why], 13, UI.TEXT_DIM)
	dl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(dl)
	var play := UI.small_button("Play showmatch", func() -> void:
		if Game.prepare_showmatch("pug"):
			Game.goto(Game.MATCH_SCENE), 150, "PrimaryButton")
	play.disabled = why != ""
	row.add_child(play)
	var sim := UI.small_button("Simulate showmatch", func() -> void:
		var res := s.sim_showmatch("pug")
		_refresh(String(s.last_show.get("note", "")))
		_show_results(res), 160)
	sim.disabled = why != ""
	row.add_child(sim)
	c.add_child(row)
	if not s.last_show.is_empty():
		var ls: Dictionary = s.last_show
		var sc: Array = ls.get("score", [0, 0])
		c.add_child(UI.label("Last %s (S%d W%d): %s %d-%d, %.2f rating" % ["trial" if String(ls.kind) == "trial" else "showmatch", int(ls.get("s", 0)), int(ls.get("w", 0)),
			"won" if int(sc[0]) > int(sc[1]) else "lost", int(sc[0]), int(sc[1]), float(ls.get("r", 0.0))], 12, UI.TEXT_FAINT))


func _watch_row(t: Dictionary) -> Control:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_child(UI.label("Watch live:", 13, UI.TEXT_DIM))
	var ui := w.team_index(w.user_team())
	var n := 0
	if int(t.round) < (t.rounds as Array).size() and w.week - int(t.start_week) == int(t.round):
		for mt: Dictionary in t.rounds[t.round]:
			if int(mt.winner) != -1 or int(mt.a) == ui or int(mt.b) == ui:
				continue
			var a := int(mt.a)
			var b := int(mt.b)
			row.add_child(UI.small_button("%s vs %s" % [w.teams[a].short_name, w.teams[b].short_name], func() -> void:
				if Game.prepare_watch_match(w, a, b, Game.CAREER_SCENE):
					Game.goto(Game.MATCH_SCENE), 0, "GhostButton"))
			n += 1
	if n == 0:
		row.add_child(UI.label("nothing left to watch this week", 12, UI.TEXT_FAINT))
	return row


func _exit_tree() -> void:
	if w != null:
		w.soc().live = false


## How every club sees you: interest, wariness, refusals, and why. It gates real offers.
func _clubs_card(parent: Control) -> void:
	var talk := w.soc().talk
	var c := UI.card(parent, "How clubs see you", false, UI.ACCENT2)
	var list := talk.attitudes(10)
	if list.is_empty():
		c.add_child(_wrap("No club has a strong opinion of you yet. Trash talk, toxic posts and how you leave clubs make them wary; friends at a club and showing interest help. Clubs that won't sign you never make offers.", 12, UI.TEXT_DIM))
		return
	for at: Dictionary in list:
		var t: TeamData = at.team
		var lab := String(at.label)
		var col := UI.GOOD if lab == "interested" else (UI.TEXT_DIM if lab == "neutral" else (UI.WARN if lab == "wary" else UI.BAD))
		var row := UI.hbox(10)
		var tl := UI.team_link(t, _view_team.bind(t), 14, false)
		tl.custom_minimum_size.x = 200
		row.add_child(tl)
		row.add_child(UI.pill(World.LEAGUES[t.league].short, UI.TEXT_DIM, 10))
		var pl := UI.pill(lab, col, 10)
		pl.custom_minimum_size.x = 96
		row.add_child(pl)
		var reasons: Array = at.reasons
		var rl := UI.label(", ".join(reasons.slice(0, 3)) if not reasons.is_empty() else "-", 12, UI.TEXT_FAINT)
		rl.clip_text = true
		rl.tooltip_text = ", ".join(reasons)
		rl.mouse_filter = Control.MOUSE_FILTER_PASS
		rl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(rl)
		c.add_child(row)
	c.add_child(UI.label("Clubs that won't sign you never make offers; wary ones rarely do.", 11, UI.TEXT_FAINT))
