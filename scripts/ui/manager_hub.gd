extends Control
## Career Mode (manager) hub: top status bar, sidebar navigation, page content.

const PAGES := ["Overview", "Inbox", "Roster", "Transfers", "Club", "League", "Tournaments", "Rankings", "Stats", "Finances", "History"]

var w: World
var _page := "Overview"
var _content: VBoxContainer
var _nav_holder: VBoxContainer
var _topbar: HBoxContainer
var _toast: Label
var _portal_filter := "All"
var _portal_view := "Free agents"
var _league_view := -1
var _ticker: NewsTicker
var _hist_tab := "Season review"
var _stats_state := {"tab": "Leaders", "league": -1, "query": ""}
var _hist_review := -1


func _ready() -> void:
	w = Game.world
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
	_topbar = UI.hbox(16)
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
		Game.save_world()
		Game.goto(Game.MENU_SCENE), 190, "GhostButton"))

	_content = UI.vbox(12)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_content)
	_ticker = NewsTicker.new()
	root.add_child(_ticker)
	_show(_page)
	if w.review_pending:
		HistoryView.ceremony_popup(self, w, func() -> void: HistoryView.review_popup(self, w))


## Sidebar click. League always opens on your own league.
func _nav(page: String) -> void:
	if page == "League":
		_league_view = -1
	if page == "Transfers" and _portal_view == "Offers" and w.incoming.is_empty():
		_portal_view = "Free agents"
	_show(page)


func _show(page: String) -> void:
	_page = page
	for c in _nav_holder.get_children():
		c.queue_free()
	_nav_holder.add_child(UI.nav(PAGES, page, _nav, {"Inbox": w.unread_count(), "Transfers": w.incoming.size()}))
	_build_topbar()
	if _ticker != null:
		_ticker.set_world(w)
	for c in _content.get_children():
		c.queue_free()
	match page:
		"Overview": _overview()
		"Inbox": _inbox()
		"Roster": _roster()
		"Transfers": _transfers()
		"League": _league()
		"Tournaments": _tournaments()
		"Rankings": _rankings()
		"Finances": _finances()
		"Club": _club()
		"Stats":
			_page_title("Stats", "Season leaders and every player in the world")
			StatsView.build(_content, w, _stats_state, func(st: Dictionary) -> void:
				_stats_state = st
				_refresh(), _view_player)
		"History": _history()


func _refresh(msg: String = "") -> void:
	Game.save_world_soon()
	_show(_page)
	if msg != "":
		_toast.text = msg
		_toast.tooltip_text = msg


func _act(err: String, ok_msg: String) -> void:
	_refresh(err if err != "" else ok_msg)
	_toast.add_theme_color_override("font_color", UI.BAD if err != "" else UI.GOOD)


func _build_topbar() -> void:
	for c in _topbar.get_children():
		c.queue_free()
	var ut := w.user_team()
	_topbar.add_child(UI.team_badge_for(ut, 40))
	var name_box := UI.vbox(0)
	name_box.add_child(UI.label(ut.team_name, 24, UI.TEXT, 700))
	name_box.add_child(UI.label("%s  -  Season %d  -  Week %d / %d" % [w.league_name(ut), w.season, w.week, World.SEASON_WEEKS], 13, UI.TEXT_DIM))
	_topbar.add_child(name_box)
	_topbar.add_child(UI.spacer())
	_topbar.add_child(UI.stat_chip("Balance", UI.money_text(w.money), UI.GOOD if w.money >= 0 else UI.BAD))
	_topbar.add_child(UI.stat_chip("League", "#%d" % (w.standings(ut.league).find(ut) + 1)))
	_topbar.add_child(UI.stat_chip("World", "#%d" % w.world_rank(ut)))
	_topbar.add_child(UI.stat_chip("Rep", str(int(ut.reputation))))
	if not w.board.is_empty():
		var bc := float(w.board.confidence)
		_topbar.add_child(UI.stat_chip("Board", "SACKED" if w.sacked else str(int(bc)), UI.BAD if w.sacked or bc < 30.0 else (UI.WARN if bc < 50.0 else UI.GOOD)))
	_topbar.add_child(UI.stat_chip("Team", str(ut.rating()), UI.rating_color(ut.rating())))
	var right := UI.vbox(4)
	right.add_child(UI.pill(w.window_text().replace("Transfer window ", "Window ").replace("(until week ", "(to wk ").replace("(opens week ", "(opens wk "), UI.GOOD if w.window_open() else UI.TEXT_DIM))
	_toast = UI.label("", 13, UI.WARN, 600)
	# Fixed width, wraps to 2 lines: a long message must never widen the top bar.
	_toast.custom_minimum_size = Vector2(260, 34)
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.clip_text = true
	_toast.mouse_filter = Control.MOUSE_FILTER_PASS
	right.add_child(_toast)
	_topbar.add_child(right)


func _page_title(title: String, sub: String = "") -> void:
	var h := UI.hbox(14)
	h.add_child(UI.heading(title, 26))
	if sub != "":
		var s := UI.label(sub, 14, UI.TEXT_DIM)
		s.size_flags_vertical = Control.SIZE_SHRINK_END
		h.add_child(s)
	_content.add_child(h)


# =============================================================================
# Overview
# =============================================================================

func _overview() -> void:
	_page_title("Overview", _week_text())
	if w.sacked:
		_banner("You've been sacked. %d clubs have offered you a job: pick one to carry on." % w.job_offers.size(), UI.BAD, "Job offers", func() -> void: _show("Club"))
	elif not w.job_offers.is_empty():
		_banner("%d club%s want you as their manager." % [w.job_offers.size(), "s" if w.job_offers.size() > 1 else ""], UI.WARN, "See offers", func() -> void: _show("Club"))
	var cols := UI.hbox(14)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(cols)
	var left := UI.vbox(14)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)

	var mt := w.user_match_this_week()
	var ui := w.team_index(w.user_team())
	if not mt.is_empty():
		var opp: TeamData = w.teams[mt.b if mt.a == ui else mt.a]
		var c := UI.card(left, "Match this week  -  " + String(mt.label) + ("  -  DERBY" if w.is_derby(mt) else ""), false, UI.BAD if w.is_derby(mt) else UI.ACCENT)
		var vs := UI.hbox(18)
		vs.alignment = BoxContainer.ALIGNMENT_CENTER
		vs.add_child(_side_block(w.user_team(), true))
		var mid := UI.vbox(2)
		mid.add_child(UI.label("VS", 30, UI.TEXT_FAINT, 700))
		mid.add_child(UI.pill(String(mt.get("map", "?")), UI.TEXT_DIM))
		vs.add_child(mid)
		vs.add_child(_side_block(opp, false))
		c.add_child(vs)
		var row := UI.hbox(10)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		var fit := w.can_field_team()
		var watch := UI.button("Watch Match", func() -> void:
			if not w.can_field_team():
				_act("You need %d fit players to play." % World.MIN_ROSTER, "")
				return
			Game.prepare_manager_match()
			Game.goto(Game.MATCH_SCENE), 200, "PrimaryButton")
		var sim := UI.button("Simulate", func() -> void:
			if not w.can_field_team():
				_act("You need %d fit players to play." % World.MIN_ROSTER, "")
				return
			var res := w.sim_user_match()
			_refresh()
			if not res.is_empty():
				var holder: Array = [] # Lambdas capture by value: hold the overlay in an array.
				holder.append(UI.results_overlay(self, res, func() -> void: (holder[0] as Node).queue_free())), 160)
		watch.disabled = not fit
		sim.disabled = not fit
		row.add_child(watch)
		row.add_child(sim)
		var fee := w.forfeit_fee(mt)
		row.add_child(UI.button("Forfeit" + (("  " + UI.money_text(fee)) if fee > 0 else "  (free)"), func() -> void:
			_confirm("Forfeit this match?", "You lose %d-0%s. Reputation and morale take a small hit." % [World.ROUNDS_TO_WIN,
				(" and pay a %s league fine" % UI.money_text(fee)) if fee > 0 else " (cups don't fine forfeits)"], "Forfeit", func() -> void:
					_act(w.forfeit_user_match(), "Match forfeited.")), 160, "GhostButton"))
		c.add_child(row)
		if not fit:
			var warn := UI.label("Only %d fit players. Sign a free agent (allowed now, even outside windows) or forfeit." % w.user_team().available_count(), 13, UI.BAD, 600)
			warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			c.add_child(warn)
		var hint := UI.label("Watching: - / = speed up to 8x, click to follow players, Esc simulates the rest.", 12, UI.TEXT_FAINT)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		c.add_child(hint)
	else:
		var c := UI.card(left, "This week", false, UI.ACCENT)
		c.add_child(UI.label("No matches left this week.", 16))
		c.add_child(UI.button("Advance Week", func() -> void:
			var r := w.advance_week()
			_refresh({"": "", "sacked": "You've been sacked: pick a new job (Club page)."}.get(r, "You have a match to play first.")), 240, "PrimaryButton"))

	var row2 := UI.hbox(14)
	left.add_child(row2)
	var b := UI.card(row2, "Weekly budget", false, UI.GOOD)
	b.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var net := w.weekly_net()
	var inc := w.weekly_income()
	var lines: Array = [["Sponsors", w.sponsor_income(), UI.GOOD], ["League + merch", w.league_revenue() + w.merch_income(), UI.GOOD]]
	if w.stake_share() > 0.0:
		lines.append(["Investor share", -int(inc * w.stake_share()), UI.BAD])
	lines.append_array([["Salaries", -w.payroll(), UI.BAD], ["Training", -w.training_cost(), UI.BAD]])
	if w.loan_payments() > 0:
		lines.append(["Loan payments", -w.loan_payments(), UI.BAD])
	for line in lines:
		var r := UI.hbox(8)
		r.add_child(UI.label(line[0], 14, UI.TEXT_DIM))
		r.add_child(UI.spacer())
		r.add_child(UI.label(UI.money_text(line[1]), 14, line[2], 600))
		b.add_child(r)
	b.add_child(UI.divider())
	var nr := UI.hbox(8)
	nr.add_child(UI.label("Net / week", 15, UI.TEXT, 600))
	nr.add_child(UI.spacer())
	nr.add_child(UI.label(UI.money_text(net), 17, UI.GOOD if net >= 0 else UI.BAD, 700))
	b.add_child(nr)

	var lt := UI.card(row2, w.league_name(w.user_team()), false, UI.ACCENT2)
	lt.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var table := w.standings(w.user_team().league)
	var pos := table.find(w.user_team())
	var shown := {}
	for i in [0, 1, 2, pos - 1, pos, pos + 1]:
		if i >= 0 and i < table.size() and not shown.has(i):
			shown[i] = true
	var keys := shown.keys()
	keys.sort()
	for i in keys:
		var t: TeamData = table[i]
		var r := UI.hbox(8)
		r.add_child(UI.label("%d" % (i + 1), 14, UI.TEXT_FAINT, 600))
		var tl := UI.team_link(t, _view_team.bind(t), 13, t == w.user_team())
		tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(tl)
		r.add_child(UI.label("%d-%d" % [t.wins, t.losses], 14, UI.TEXT, 600))
		lt.add_child(r)

	var right := UI.vbox(14)
	right.custom_minimum_size = Vector2(420, 0)
	cols.add_child(right)
	_inbox_card(right)
	var news := UI.card(right, "News", true, UI.TEXT_DIM)
	var list := UI.vbox(6)
	for i in range(w.news.size() - 1, maxi(-1, w.news.size() - 60), -1):
		list.add_child(_news_line(w.news[i]))
	news.add_child(UI.scroll(list))


## Things waiting on you: bids for your players, sponsor offers, debt, unhappy players.
func _inbox_card(parent: Control) -> void:
	var items: Array = [] # [text, color, button text, callable]
	for m in w.inbox:
		if not bool(m.done):
			items.append([String(m.title), _msg_color(String(m.kind)), "Open", func() -> void: _show("Inbox")])
	items.reverse()
	if not w.incoming.is_empty():
		items.append(["%d bid%s for your players" % [w.incoming.size(), "s" if w.incoming.size() > 1 else ""], UI.ACCENT2, "Review", func() -> void:
			_portal_view = "Offers"
			_show("Transfers")])
	if not w.sponsor_offers.is_empty():
		items.append(["%d sponsorship offer%s waiting" % [w.sponsor_offers.size(), "s" if w.sponsor_offers.size() > 1 else ""], UI.GOOD, "Finances", func() -> void: _show("Finances")])
	for slot in World.SPONSOR_SLOTS:
		if w.sponsor_in_slot(slot).is_empty():
			items.append(["No %s sponsor: money left on the table" % String(slot).to_lower(), UI.WARN, "Finances", func() -> void: _show("Finances")])
			break
	if w.money < 0:
		items.append(["In debt for %d week%s: creditors force sales from week 3" % [w.debt_weeks, "s" if w.debt_weeks != 1 else ""], UI.BAD, "Loans", func() -> void: _show("Finances")])
	for p in w.user_team().roster:
		if p.morale < 30.0:
			items.append(["%s is unhappy (%s)" % [p.player_name, p.morale_text().to_lower()], UI.WARN, "Card", func() -> void: _view_player(p)])
		elif p.form <= -4.5:
			items.append(["%s is in a slump" % p.player_name, UI.WARN, "Card", func() -> void: _view_player(p)])
	if items.is_empty():
		return
	var c := UI.card(parent, "Inbox", false, UI.ACCENT2)
	for it in items.slice(0, 4):
		var r := UI.hbox(8)
		var dot := ColorRect.new()
		dot.color = it[1]
		dot.custom_minimum_size = Vector2(3, 18)
		r.add_child(dot)
		var il := UI.label(String(it[0]), 13, UI.TEXT)
		il.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		il.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(il)
		r.add_child(UI.small_button(String(it[2]), it[3], 90, "GhostButton"))
		c.add_child(r)


func _side_block(t: TeamData, mine: bool) -> VBoxContainer:
	var v := UI.vbox(4)
	v.custom_minimum_size = Vector2(220, 0)
	var badge := UI.team_badge_for(t, 52)
	badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(badge)
	var n := UI.label(t.team_name, 18, UI.ACCENT2 if mine else UI.TEXT, 700)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(n)
	var s := UI.label("RTG %d  -  %d-%d" % [t.rating(), t.wins, t.losses], 13, UI.TEXT_DIM)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	return v


func _news_line(text: String) -> Control:
	var h := UI.hbox(8)
	var color := UI.TEXT_DIM
	for kv in [["WIN", UI.GOOD], ["LOSS", UI.BAD], ["PROMOTED", UI.GOOD], ["RELEGATED", UI.BAD], ["TRANSFER", UI.ACCENT2], ["OFFER", UI.ACCENT2],
			["SPONSOR", UI.GOOD], ["FINANCE", UI.ACCENT2], ["signed", UI.ACCENT2], ["WARNING", UI.WARN], ["MATCHDAY", UI.WARN], ["on fire", UI.GOOD]]:
		if kv[0] in text:
			color = kv[1]
			break
	var dot := ColorRect.new()
	dot.color = color
	dot.custom_minimum_size = Vector2(3, 0)
	h.add_child(dot)
	var l := UI.label(text, 13, UI.TEXT if color != UI.TEXT_DIM else UI.TEXT_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	return h


func _week_text() -> String:
	if w.week <= World.LEAGUE_WEEKS:
		return "League play: week %d of %d  -  playoffs from week %d" % [w.week, World.LEAGUE_WEEKS, World.PLAYOFF_START]
	if w.week < World.PLAYOFF_START + 3:
		return "League playoffs"
	return "Off-season cups until week %d" % World.SEASON_WEEKS


# =============================================================================
# Roster
# =============================================================================

const ROSTER_COLS := [["", 50, "l"], ["Player", 0, "l"], ["Age", 28, "c"], ["RTG", 40, "c"], ["Form", 62, "c"], ["Mor", 34, "c"],
	["Aim", 26, "c"], ["Flk", 26, "c"], ["Pre", 26, "c"], ["Rcl", 26, "c"], ["Rct", 26, "c"], ["Mov", 26, "c"], ["Pos", 26, "c"], ["Dec", 26, "c"], ["Utl", 26, "c"],
	["Wage", 56, "r"], ["Value", 60, "r"], ["Deal", 44, "c"], ["", 84, "r"]]


func _roster() -> void:
	_page_title("Roster", "Top 5 start  -  %d / %d players" % [w.user_team().roster.size(), World.MAX_ROSTER])
	var tc := UI.card(_content, "Training plan", false, UI.ACCENT2)
	var tp := HFlowContainer.new() # Wraps at narrow widths (fullscreen).
	tp.add_theme_constant_override("h_separation", 12)
	tp.add_theme_constant_override("v_separation", 6)
	tc.add_child(tp)
	tp.add_child(UI.label("Focus", 14, UI.TEXT_DIM))
	var focus := OptionButton.new()
	var fkeys := World.TRAINING_FOCUS.keys()
	for k in fkeys:
		focus.add_item(k)
	focus.select(fkeys.find(w.training.focus))
	focus.item_selected.connect(func(i: int) -> void:
		w.training.focus = fkeys[i]
		Game.save_world())
	tp.add_child(focus)
	tp.add_child(UI.label("Intensity", 14, UI.TEXT_DIM))
	var inten := OptionButton.new()
	var ikeys := World.TRAINING_INTENSITY.keys()
	for k in ikeys:
		inten.add_item("%s  (%s/wk)" % [k, UI.money_text(World.TRAINING_INTENSITY[k].cost)])
	inten.select(ikeys.find(w.training.intensity))
	inten.item_selected.connect(func(i: int) -> void:
		w.training.intensity = ikeys[i]
		_refresh())
	tp.add_child(inten)
	tp.add_child(UI.spacer())
	tp.add_child(UI.pill("Chemistry %d" % int(w.chemistry(w.user_team())), UI.GOOD if w.chemistry(w.user_team()) >= 55.0 else UI.WARN))
	tp.add_child(UI.pill("Training Center L%d" % w.facility, UI.ACCENT2))
	var up_cost := w.facility_upgrade_cost()
	if up_cost > 0:
		tp.add_child(UI.small_button("Upgrade  " + UI.money_text(up_cost), func() -> void:
			_act("" if w.upgrade_facility() else "Not enough money for the upgrade.", "Facility upgraded."), 160))

	var ut := w.user_team()
	var expiring: Array = []
	var out: Array = []
	for p in ut.roster:
		if p.contract_until <= w.season:
			expiring.append(p.player_name)
		if not p.available():
			out.append("%s (%s, %d wk)" % [p.player_name, p.ailment, p.out_weeks])
	if not expiring.is_empty() or not out.is_empty():
		var alerts := UI.vbox(4)
		if not expiring.is_empty():
			var h := UI.hbox(8)
			h.add_child(UI.pill("Contracts", UI.BAD))
			h.add_child(UI.label("Expiring at season end: %s. Extend from Manage, or they leave as free agents." % ", ".join(expiring), 13, UI.TEXT))
			alerts.add_child(h)
		if not out.is_empty():
			var h2 := UI.hbox(8)
			h2.add_child(UI.pill("Unavailable", UI.WARN))
			h2.add_child(UI.label(", ".join(out) + ". Skipped in the lineup.", 13, UI.TEXT))
			alerts.add_child(h2)
		_content.add_child(alerts)
	var card := UI.card(_content, "", true)
	card.add_child(UI.table_header(ROSTER_COLS))
	var list := UI.vbox(2)
	for i in ut.roster.size():
		var p: PlayerData = ut.roster[i]
		var row := UI.table_row(_roster_cells(p, i), ROSTER_COLS, i)
		_make_draggable(row, p, i)
		list.add_child(row)
		if i == 4 and ut.roster.size() > 5:
			var sep := UI.hbox(8)
			sep.add_child(UI.caption("   Bench", UI.TEXT_FAINT))
			list.add_child(sep)
	card.add_child(UI.scroll(list))
	card.add_child(UI.label("Drag rows to reorder (top 5 start). Click a name for history and stats. Form: streaks/slumps. Mor: morale. '!' deals expire this season.", 12, UI.TEXT_FAINT))


## Drag a roster row onto another to move that player there.
func _make_draggable(row: Control, p: PlayerData, i: int) -> void:
	row.mouse_default_cursor_shape = Control.CURSOR_DRAG
	row.set_drag_forwarding(func(_at: Vector2) -> Variant:
		var prev := PanelContainer.new()
		prev.add_theme_stylebox_override("panel", UI._box(Color(UI.ACCENT2, 0.25), 4, UI.ACCENT2, 1, 12, 6))
		prev.add_child(UI.label(p.player_name, 15, UI.TEXT, 700))
		row.set_drag_preview(prev)
		return {"roster_uid": p.uid},
	func(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and (data as Dictionary).has("roster_uid"),
	func(_at: Vector2, data: Variant) -> void:
		var dp := w.find_player(int(data.roster_uid))
		if dp != null and dp != p:
			w.move_to_index(dp, i)
			_refresh("%s moved to #%d%s." % [dp.player_name, i + 1, "" if i < 5 else " (bench)"]))


func _roster_cells(p: PlayerData, i: int) -> Array:
	var pp := p
	var arrows := UI.hbox(2)
	arrows.add_child(UI.small_button("^", func() -> void:
		w.move_in_lineup(pp, -1)
		_refresh(), 25, "GhostButton"))
	arrows.add_child(UI.small_button("v", func() -> void:
		w.move_in_lineup(pp, 1)
		_refresh(), 25, "GhostButton"))
	var name_box := UI.vbox(0)
	var dt: float = float(w.last_training.get(p.player_name, 0.0))
	var nb := UI.link_button(p.player_name, _view_player.bind(pp), 15, UI.TEXT if i < 5 else UI.TEXT_DIM)
	nb.tooltip_text = "Player card: match history, stats, rename"
	nb.clip_text = false
	var top := HFlowContainer.new() # Tags wrap under the name instead of widening the table.
	top.add_theme_constant_override("h_separation", 6)
	top.add_theme_constant_override("v_separation", 2)
	top.add_child(nb)
	if not p.available():
		var op := UI.pill("Out %dw" % p.out_weeks, UI.BAD, 10)
		op.tooltip_text = "%s: out for %d week(s)" % [p.ailment, p.out_weeks]
		top.add_child(op)
	if p.listed:
		top.add_child(UI.pill("Listed", UI.ACCENT2, 10))
	if p.contract_until <= w.season:
		top.add_child(UI.pill("Expiring", UI.WARN, 10))
	if p.promise_until >= w.stamp():
		top.add_child(UI.pill("Promised", UI.GOOD, 10))
	var pe := PlayerData.persona_of(p)
	if pe != "":
		var pp2 := UI.pill(pe, Color("c084fc"), 10)
		pp2.tooltip_text = String(PlayerData.PERSONA_TEXT[pe])
		top.add_child(pp2)
	if p.loan_kind == "in":
		top.add_child(UI.pill("On loan", UI.ACCENT2, 10))
	name_box.add_child(top)
	name_box.add_child(UI.label("%s  -  %s%s" % [p.role, _potential(p), ("   training %+.1f" % dt) if absf(dt) >= 0.05 else ""], 11, UI.TEXT_FAINT))
	var mc := UI.GOOD if p.morale >= 60.0 else (UI.WARN if p.morale >= 35.0 else UI.BAD)
	var mor := UI.label(str(int(p.morale)), 13, mc, 600)
	mor.tooltip_text = "Morale: " + p.morale_text()
	mor.mouse_filter = Control.MOUSE_FILTER_PASS
	var cells: Array = [arrows, name_box, UI.label(str(p.age), 14, UI.TEXT_DIM), UI.rating_chip(p.rating()),
		UI.pill(p.form_text(), p.form_color(), 10), mor]
	for k: String in PlayerData.STAT_KEYS:
		cells.append(UI.label(str(int(round(p.stat(k)))), 13, UI.rating_color(p.stat(k)), 600))
	cells.append(UI.label(UI.money_text(p.salary), 13, UI.TEXT_DIM))
	cells.append(UI.label(UI.money_text(p.market_value()), 13, UI.TEXT_DIM))
	var expiring := p.contract_until <= w.season
	cells.append(UI.pill("S%d%s" % [p.contract_until, "!" if expiring else ""], UI.BAD if expiring else UI.TEXT_DIM, 11))
	var menu := MenuButton.new()
	menu.text = "Manage"
	menu.flat = false
	menu.add_theme_font_size_override("font_size", 13)
	menu.custom_minimum_size = Vector2(80, 30)
	var pop := menu.get_popup()
	pop.add_item("Extend contract  (%s)" % UI.money_text(w.extension_cost(p)), 0)
	pop.add_item("Remove from transfer list" if p.listed else "Transfer-list (clubs bid over the coming weeks)", 1)
	pop.add_item("Release  (%s severance)" % UI.money_text(p.salary * 2), 2)
	pop.add_separator()
	pop.add_item("Player card", 4)
	if p.loan_kind != "in":
		pop.add_item("Loan out until season end (they play, you don't pay)", 5)
	if w.affiliate() != null:
		pop.add_item("Send down to %s" % w.affiliate().team_name, 6)
	pop.add_item("Rename", 3)
	pop.id_pressed.connect(_manage_player.bind(pp))
	cells.append(menu)
	return cells


func _manage_player(id: int, p: PlayerData) -> void:
	if id == 0:
		_contract_dialog(p, "extend")
	elif id == 1:
		w.set_listed(p, not p.listed)
		_refresh("%s %s the transfer list." % [p.player_name, "is on" if p.listed else "is off"])
	elif id == 2:
		_act(w.release_player(p), "Released %s." % p.player_name)
	elif id == 3:
		_rename_player(p)
	elif id == 5:
		_act(w.loan_out(p), "%s is out on loan." % p.player_name)
	elif id == 6:
		_act(w.send_down(p), "%s sent down to %s." % [p.player_name, w.affiliate().team_name if w.affiliate() != null else "the affiliate"])
	else:
		_view_player(p)


func _rename_player(p: PlayerData) -> void:
	UI.text_prompt(self, "Rename player", [["Name", p.player_name, 18]], func(vals: Array) -> String:
		var err := w.rename_player(p, String(vals[0]))
		if err == "":
			_refresh("Renamed to %s." % p.player_name)
		return err)


func _rename_team(t: TeamData) -> void:
	UI.text_prompt(self, "Rename team", [["Name", t.team_name, 24], ["Tag (up to 4 letters)", t.short_name, 4]], func(vals: Array) -> String:
		var err := w.rename_team(t, String(vals[0]), String(vals[1]))
		if err == "":
			_close_modals()
			_refresh("Renamed to %s." % t.team_name)
		return err)


## Close every popup layer (team popups, player cards).
func _close_modals() -> void:
	for c in get_children():
		if c.has_meta("modal"):
			c.queue_free()


func _view_player(p: PlayerData) -> void:
	var m := UI.player_card(self, w, p)
	var overlay: Control = m[0]
	overlay.set_meta("modal", true)
	var box: VBoxContainer = m[1]
	var row := UI.hbox(10)
	row.add_child(UI.button("Close", func() -> void: overlay.queue_free(), 140, "GhostButton"))
	row.add_child(UI.spacer())
	if w.user_team().roster.has(p):
		row.add_child(UI.button("Rename", func() -> void: _rename_player(p), 150))
	elif w.owner_of(p) != null or w.free_agents.has(p):
		row.add_child(UI.button("Scout / bid", func() -> void:
			_close_modals()
			_scout(p), 170, "PrimaryButton"))
	box.add_child(row)


func _view_team(t: TeamData) -> void:
	var m := UI.team_popup(self, w, t, null, _view_player)
	var overlay: Control = m[0]
	overlay.set_meta("modal", true)
	var box: VBoxContainer = m[1]
	var row := UI.hbox(10)
	row.add_child(UI.button("Close", func() -> void: overlay.queue_free(), 140, "GhostButton"))
	row.add_child(UI.spacer())
	row.add_child(UI.button("Rename team", func() -> void: _rename_team(t), 170))
	box.add_child(row)


func _potential(p: PlayerData) -> String:
	var gap := p.potential - p.rating()
	if gap >= 20:
		return "Elite"
	if gap >= 12:
		return "High"
	if gap >= 6:
		return "Good"
	if gap >= 2:
		return "Some"
	return "Peaked"


# =============================================================================
# Transfers
# =============================================================================

const PORTAL_COLS := [["Player", 0, "l", "name"], ["Role", 60, "l", "role"], ["Club", 118, "l", "club"], ["Age", 30, "c", "age"], ["RTG", 42, "c", "rating"], ["Pot.", 44, "l", "potential"],
	["Aim", 26, "c", "aim"], ["Flk", 26, "c", "flick"], ["Pre", 26, "c", "preaim"], ["Rcl", 26, "c", "recoil"], ["Rct", 26, "c", "reaction"], ["Mov", 26, "c", "movement"], ["Pos", 26, "c", "positioning"], ["Dec", 26, "c", "decision"], ["Utl", 26, "c", "utility"],
	["Wage", 56, "r", "wage"], ["Price", 68, "r", "price"], ["", 58, "r", ""]]
const MIN_RTG_OPTIONS := [0, 45, 55, 65, 75, 85, 90]
const MAX_PRICE_OPTIONS := [0, 25000, 50000, 100000, 250000, 500000, 1000000, 2500000]
const MAX_AGE_OPTIONS := [0, 20, 23, 26, 29]

var _sort_key := "rating"
var _sort_asc := false
var _f_min_rtg := 0
var _f_max_price := 0
var _f_max_age := 0
var _f_affordable := false
var _overlay: Control


func _price_of(p: PlayerData) -> int:
	return w.signing_fee(p) if w.owner_of(p) == null else w.buyout_price(p)


func _sort_value(p: PlayerData, key: String) -> Variant:
	match key:
		"name":
			return p.player_name.to_lower()
		"role":
			return p.role
		"club":
			var o := w.owner_of(p)
			return "" if o == null else o.team_name.to_lower()
		"age":
			return float(p.age)
		"rating":
			return w.est_rating(p)
		"potential":
			return float(p.potential - p.rating()) if w.known(p) else -1.0
		"wage":
			return float(PlayerData.salary_for_rating(p.rating_exact()))
		"price":
			return float(_price_of(p))
	return w.est_stat(p, key)


func _on_sort(key: String) -> void:
	if key == _sort_key:
		_sort_asc = not _sort_asc
	else:
		_sort_key = key
		# Text / age / money read naturally ascending; skills best-first.
		_sort_asc = key in ["name", "role", "club", "age", "wage", "price"]
	_refresh()


func _option(items: Array, labels: Array, current: Variant, on_pick: Callable) -> OptionButton:
	var o := OptionButton.new()
	for l in labels:
		o.add_item(String(l))
	o.select(maxi(0, items.find(current)))
	o.add_theme_font_size_override("font_size", 13)
	o.focus_mode = Control.FOCUS_NONE
	o.item_selected.connect(func(i: int) -> void: on_pick.call(items[i]))
	return o


func _transfers() -> void:
	_page_title("Transfers", "%s  -  roster %d / %d  -  balance %s" % [w.window_text(), w.user_team().roster.size(), World.MAX_ROSTER, UI.money_text(w.money)])
	var bar := UI.hbox(8)
	_content.add_child(bar)
	for view in ["Free agents", "Other clubs", "Offers"]:
		var v: String = view
		var txt := v if v != "Offers" or w.incoming.is_empty() else "Offers (%d)" % w.incoming.size()
		bar.add_child(UI.small_button(txt, func() -> void:
			_portal_view = v
			_refresh(), 112, "PrimaryButton" if _portal_view == v else ""))
	if _portal_view == "Offers":
		_offers_view()
		return
	bar.add_child(UI.gap(4))
	var roles: Array = ["All"] + PlayerData.ROLES
	bar.add_child(_option(roles, ["Role: All"] + PlayerData.ROLES, _portal_filter, func(v: Variant) -> void:
		_portal_filter = v
		_refresh()))
	var rtg_labels: Array = []
	for x: int in MIN_RTG_OPTIONS:
		rtg_labels.append("Min RTG: any" if x == 0 else "RTG %d+" % x)
	bar.add_child(_option(MIN_RTG_OPTIONS, rtg_labels, _f_min_rtg, func(v: Variant) -> void:
		_f_min_rtg = v
		_refresh()))
	var price_labels: Array = []
	for x: int in MAX_PRICE_OPTIONS:
		price_labels.append("Max price: any" if x == 0 else "Under " + UI.money_text(x))
	bar.add_child(_option(MAX_PRICE_OPTIONS, price_labels, _f_max_price, func(v: Variant) -> void:
		_f_max_price = v
		_refresh()))
	var age_labels: Array = []
	for x: int in MAX_AGE_OPTIONS:
		age_labels.append("Max age: any" if x == 0 else "Age %d or under" % x)
	bar.add_child(_option(MAX_AGE_OPTIONS, age_labels, _f_max_age, func(v: Variant) -> void:
		_f_max_age = v
		_refresh()))
	var aff := CheckBox.new()
	aff.text = "Affordable"
	aff.button_pressed = _f_affordable
	aff.focus_mode = Control.FOCUS_NONE
	aff.add_theme_font_size_override("font_size", 13)
	aff.toggled.connect(func(on: bool) -> void:
		_f_affordable = on
		_refresh())
	bar.add_child(aff)

	var players: Array[PlayerData] = []
	if _portal_view == "Free agents":
		players = w.free_agents.duplicate()
	else:
		players = w.market_players()
	var filtered: Array[PlayerData] = []
	for p in players:
		if _portal_filter != "All" and p.role != _portal_filter:
			continue
		if _f_min_rtg > 0 and p.rating() < _f_min_rtg:
			continue
		if _f_max_age > 0 and p.age > _f_max_age:
			continue
		var price := _price_of(p)
		if _f_max_price > 0 and price > _f_max_price:
			continue
		if _f_affordable and price > w.money:
			continue
		filtered.append(p)
	var key := _sort_key
	var asc := _sort_asc
	filtered.sort_custom(func(a: PlayerData, b: PlayerData) -> bool:
		var va: Variant = _sort_value(a, key)
		var vb: Variant = _sort_value(b, key)
		if va == vb:
			return a.rating_exact() > b.rating_exact()
		return va < vb if asc else va > vb)

	if not w.can_sign_now():
		var warn := UI.hbox(8)
		warn.add_child(UI.pill("Window closed", UI.BAD))
		warn.add_child(UI.label("No signings or bids until the window opens (%s). Browse and scout in the meantime." % w.window_text().split("(")[-1].trim_suffix(")"), 13, UI.TEXT_DIM))
		_content.add_child(warn)
	var card := UI.card(_content, "", true)
	card.add_child(UI.sort_header(PORTAL_COLS, _sort_key, _sort_asc, _on_sort))
	var list := UI.vbox(2)
	var shown := 0
	for p in filtered:
		if shown >= 120:
			break
		list.add_child(UI.table_row(_portal_cells(p), PORTAL_COLS, shown))
		shown += 1
	if filtered.is_empty():
		list.add_child(UI.label("No players match these filters.", 14, UI.TEXT_DIM))
	card.add_child(UI.scroll(list))
	card.add_child(UI.label("%d players match%s. Click a header to sort, a player to scout and compare. Signings and bids only in transfer windows; clubs may refuse." % [filtered.size(), " (top 120 shown)" if filtered.size() > 120 else ""], 12, UI.TEXT_FAINT))


func _portal_cells(p: PlayerData) -> Array:
	var owner := w.owner_of(p)
	var pp := p
	var name_btn := Button.new()
	name_btn.flat = true
	name_btn.focus_mode = Control.FOCUS_NONE
	name_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_btn.text = p.player_name
	name_btn.clip_text = true
	name_btn.add_theme_font_override("font", UI.font(600))
	name_btn.add_theme_font_size_override("font_size", 14)
	name_btn.add_theme_color_override("font_color", UI.TEXT)
	name_btn.add_theme_color_override("font_hover_color", UI.ACCENT2)
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus"]:
		name_btn.add_theme_stylebox_override(st, empty)
	name_btn.tooltip_text = "Scout %s" % p.player_name
	name_btn.pressed.connect(func() -> void: _scout(pp))
	var club: Control = UI.label("Free agent", 12, UI.TEXT_FAINT)
	if owner != null:
		club = UI.hbox(5)
		club.add_child(UI.team_badge_for(owner, 18))
		var cl := UI.label(World.LEAGUES[owner.league].short + "  " + owner.short_name, 12, UI.TEXT_DIM)
		cl.tooltip_text = owner.team_name
		cl.mouse_filter = Control.MOUSE_FILTER_PASS
		club.add_child(cl)
	var price := _price_of(p)
	var kn := w.known(p)
	if not kn:
		name_btn.text = p.player_name + "  ?"
		name_btn.tooltip_text = "Not scouted: ratings are estimates (+/- %d). Click to scout." % int(w.scout_width() * 0.5)
	var rc := UI.rating_chip(int(round(w.est_rating(p))))
	if not kn:
		rc.modulate = Color(1, 1, 1, 0.55)
	var cells: Array = [name_btn, UI.label(p.role, 12, UI.TEXT_DIM), club, UI.label(str(p.age), 13, UI.TEXT_DIM), rc,
		UI.label(_potential(p) if kn else "?", 12, UI.TEXT_DIM)]
	for k: String in PlayerData.STAT_KEYS:
		var ev := w.est_stat(p, k)
		cells.append(UI.label(str(int(round(ev))), 13, UI.rating_color(ev) if kn else Color(UI.rating_color(ev), 0.5), 600))
	cells.append(UI.label(UI.money_text(PlayerData.salary_for_rating(p.rating_exact())), 12, UI.TEXT_DIM))
	cells.append(UI.label(UI.money_text(price), 13, UI.TEXT if price <= w.money else UI.BAD, 600))
	var refuse := p.refuses(w.user_team())
	if refuse != "":
		var np := UI.small_button("No", func() -> void: _act(refuse + ".", ""), 58, "GhostButton")
		np.tooltip_text = refuse + "."
		np.add_theme_color_override("font_color", UI.BAD)
		cells.append(np)
		return cells
	var buy := UI.small_button("Sign" if owner == null else "Bid", func() -> void: _buy(pp), 58, "PrimaryButton")
	if not w.can_sign_now():
		buy.disabled = true
		buy.tooltip_text = w.window_text()
	cells.append(buy)
	return cells


const OFFER_COLS := [["Your player", 0, "l"], ["RTG", 40, "c"], ["Value", 70, "r"], ["Bidder", 170, "l"], ["Cash", 80, "r"],
	["Swap player", 150, "l"], ["Expires", 56, "c"], ["", 250, "r"]]


## Bids from other clubs for your players: accept, counter (+25%) or decline.
func _counter(o: Dictionary, t: TeamData) -> void:
	var r := w.counter_incoming(o)
	if r == "accepted":
		_act("", "%s agreed to %s. Accept to complete." % [t.team_name, UI.money_text(int(o.cash))])
	elif r == "walked":
		_act("%s walked away." % t.team_name, "")
	elif r == "held":
		_act("", "%s won't go higher; the original offer stands." % t.team_name)
	else:
		_act(r, "")


func _offers_view() -> void:
	var card := UI.card(_content, "Bids for your players", true, UI.ACCENT2)
	card.add_child(UI.table_header(OFFER_COLS))
	var list := UI.vbox(2)
	var i := 0
	for o: Dictionary in w.incoming.duplicate():
		var p := w.find_player(int(o.player))
		var t: TeamData = w.teams[int(o.team)]
		if p == null:
			continue
		var sw: PlayerData = w.find_player(int(o.swap)) if int(o.swap) != 0 else null
		var oo := o
		var sw_cell: Control = UI.label("-", 13, UI.TEXT_FAINT)
		if sw != null:
			sw_cell = UI.link_button("%s (%d %s)" % [sw.player_name, sw.rating(), sw.role], _view_player.bind(sw), 13)
		var btns := UI.hbox(4)
		btns.add_child(UI.small_button("Accept", func() -> void:
			_act(w.accept_incoming(oo), "Deal done: %s leaves." % p.player_name), 70, "PrimaryButton"))
		var counter := UI.small_button("Counter +25%", _counter.bind(oo, t), 104)
		counter.disabled = bool(o.get("countered", false))
		btns.add_child(counter)
		btns.add_child(UI.small_button("Decline", func() -> void:
			w.decline_incoming(oo)
			_refresh("Declined."), 66, "GhostButton"))
		var valid := w.offer_valid(o)
		if valid != "":
			(btns.get_child(0) as Button).disabled = true
			(btns.get_child(0) as Button).tooltip_text = valid
		list.add_child(UI.table_row([UI.link_button(p.player_name, _view_player.bind(p), 14), UI.rating_chip(p.rating()),
			UI.label(UI.money_text(p.market_value()), 13, UI.TEXT_DIM), UI.team_link(t, _view_team.bind(t), 13),
			UI.label(UI.money_text(int(o.cash)), 14, UI.GOOD, 700), sw_cell,
			UI.label("%d wk" % int(o.expires), 13, UI.TEXT_DIM), btns], OFFER_COLS, i))
		i += 1
	if i == 0:
		list.add_child(UI.label("No bids right now. Clubs bid during transfer windows, more for players in form or unhappy ones.", 14, UI.TEXT_DIM))
	card.add_child(UI.scroll(list))
	card.add_child(UI.label("Accepting moves the player (name, stats and history go with them). A swap player joins you on a new deal. Countering is a gamble: they may walk.", 12, UI.TEXT_FAINT))


func _buy(p: PlayerData) -> void:
	if w.owner_of(p) == null:
		_contract_dialog(p, "sign")
	else:
		_bid_dialog(p)


## Build a bid: cash (a share of the asking price) plus any of your players.
func _bid_dialog(p: PlayerData) -> void:
	var owner := w.owner_of(p)
	var ask := w.buyout_price(p)
	var m := UI.modal(self, 640)
	var overlay: Control = m[0]
	overlay.set_meta("modal", true)
	var box: VBoxContainer = m[1]
	var head := UI.hbox(12)
	head.add_child(UI.rating_badge(p.rating(), 40))
	var info := UI.vbox(2)
	info.add_child(UI.label("Bid for %s" % p.player_name, 22, UI.TEXT, 700))
	info.add_child(UI.label("%s  -  %s  -  asking %s" % [p.role, owner.team_name, UI.money_text(ask)], 13, UI.TEXT_DIM))
	head.add_child(info)
	box.add_child(head)
	box.add_child(UI.divider())
	box.add_child(UI.caption("Cash"))
	var shares := [0.0, 0.5, 0.7, 0.85, 1.0, 1.15, 1.3]
	var cash_vals: Array = []
	var cash_labels: Array = []
	for f: float in shares:
		var v := int(round(ask * f / 1000.0)) * 1000
		cash_vals.append(v)
		cash_labels.append("%s  (%d%% of asking)" % [UI.money_text(v), int(f * 100)])
	var state := {"cash": cash_vals[4], "swaps": []}
	var verdict := UI.label("", 14, UI.TEXT, 600)
	var update := func() -> void:
		var total: int = state.cash
		for sw: PlayerData in state.swaps:
			total += w.swap_value(sw, owner)
		var ratio := float(total) / maxf(1.0, float(ask))
		var txt := "Insulting" if ratio < 0.6 else ("Unlikely" if ratio < 0.9 else ("Fair" if ratio < 1.1 else "Strong"))
		verdict.text = "Package worth %s to them (%d%% of asking): %s" % [UI.money_text(total), int(ratio * 100), txt]
		verdict.add_theme_color_override("font_color", UI.BAD if ratio < 0.9 else (UI.TEXT if ratio < 1.1 else UI.GOOD))
	box.add_child(_option(cash_vals, cash_labels, state.cash, func(v: Variant) -> void:
		state.cash = int(v)
		update.call()))
	box.add_child(UI.caption("Add your players (optional)"))
	for q in w.user_team().roster:
		var cb := CheckBox.new()
		var qq := q
		var no := q.refuses(owner)
		cb.text = "%s  (%s, RTG %d)  -  worth ~%s to them%s" % [q.player_name, q.role, q.rating(), UI.money_text(w.swap_value(q, owner)), "  -  refuses to go" if no != "" else ""]
		cb.disabled = no != ""
		cb.tooltip_text = no
		cb.add_theme_font_size_override("font_size", 13)
		cb.focus_mode = Control.FOCUS_NONE
		cb.toggled.connect(func(on: bool) -> void:
			if on:
				state.swaps.append(qq)
			else:
				state.swaps.erase(qq)
			update.call())
		box.add_child(cb)
	box.add_child(verdict)
	update.call()
	var row := UI.hbox(10)
	row.add_child(UI.button("Cancel", func() -> void: overlay.queue_free(), 140, "GhostButton"))
	row.add_child(UI.spacer())
	row.add_child(UI.button("Submit bid", func() -> void:
		var swaps: Array = state.swaps.duplicate()
		var err := w.make_offer(p, int(state.cash), swaps)
		overlay.queue_free()
		_act(err, "Deal done: %s joins you." % p.player_name), 200, "PrimaryButton"))
	box.add_child(row)


func _confirm(title: String, body: String, ok_text: String, cb: Callable) -> void:
	var m := UI.modal(self, 480, UI.WARN)
	var overlay: Control = m[0]
	var box: VBoxContainer = m[1]
	box.add_child(UI.heading(title, 20))
	var l := UI.label(body, 14, UI.TEXT_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(l)
	var row := UI.hbox(10)
	row.add_child(UI.button("Cancel", func() -> void: overlay.queue_free(), 140, "GhostButton"))
	row.add_child(UI.spacer())
	row.add_child(UI.button(ok_text, func() -> void:
		overlay.queue_free()
		cb.call(), 160, "PrimaryButton"))
	box.add_child(row)


# =============================================================================
# Inbox
# =============================================================================

func _msg_color(kind: String) -> Color:
	match kind:
		"wants_out", "complaint": return UI.BAD
		"wage", "contract": return UI.WARN
		"sponsor": return UI.GOOD
		"suggestion": return UI.ACCENT2
	return UI.TEXT_DIM


func _inbox() -> void:
	_page_title("Inbox", "%d waiting on you" % w.unread_count())
	var list := UI.vbox(10)
	var shown := 0
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
		top.add_child(UI.pill(String(m.kind).replace("_", " "), col, 10))
		top.add_child(UI.spacer())
		top.add_child(UI.label("S%d W%d" % [int(m.s), int(m.w)], 12, UI.TEXT_FAINT))
		v.add_child(top)
		var body := UI.label(String(m.body), 13, UI.TEXT_DIM)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(body)
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
					var action := String(opt[1])
					var err := w.resolve_msg(mm, kk)
					_act(err, String(mm.result))
					if err == "" and action == "scout":
						var sp := w.find_player(int(mm.uid))
						if sp != null:
							_scout(sp), 0, "PrimaryButton" if k == 0 else "GhostButton"))
			var pl := w.find_player(int(m.uid)) if int(m.uid) != 0 else null
			if pl != null:
				row.add_child(UI.spacer())
				row.add_child(UI.small_button("Player card", func() -> void: _view_player(pl), 110, "GhostButton"))
			v.add_child(row)
		list.add_child(p)
		shown += 1
	if shown == 0:
		list.add_child(UI.label("Nothing here yet. Players, staff and sponsors will get in touch.", 14, UI.TEXT_DIM))
	_content.add_child(UI.scroll(list))


func _weakest_starter() -> PlayerData:
	var worst: PlayerData = null
	for s: PlayerData in w.user_team().starters():
		if worst == null or s.rating_exact() < worst.rating_exact():
			worst = s
	return worst


## Scouting card: full attributes, compared with your weakest starter.
func _scout(p: PlayerData) -> void:
	_close_scout()
	_overlay = ColorRect.new()
	(_overlay as ColorRect).color = Color(UI.BG, 0.75)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UI._box(UI.PANEL, 14, UI.ACCENT2, 1, 22, 18))
	panel.custom_minimum_size = Vector2(760, 0)
	center.add_child(panel)
	var box := UI.vbox(10)
	panel.add_child(box)
	var cmp := _weakest_starter()
	var owner := w.owner_of(p)
	var price := _price_of(p)

	var kn := w.known(p)
	var head := UI.hbox(14)
	head.add_child(UI.rating_badge(int(round(w.est_rating(p))), 44))
	var info := UI.vbox(4)
	info.add_child(UI.label(p.player_name, 28, UI.TEXT, 700))
	var pills := UI.hbox(6)
	pills.add_child(UI.pill(p.role, UI.ACCENT2))
	pills.add_child(UI.pill("Age %d" % p.age, UI.TEXT_DIM))
	pills.add_child(UI.pill("Potential: " + (_potential(p) if kn else "?"), UI.WARN))
	if not kn:
		pills.add_child(UI.pill("Estimates  +/- %d" % int(w.scout_width() * 0.5), UI.BAD))
	pills.add_child(UI.pill(owner.team_name if owner != null else "Free agent", UI.TEXT_DIM))
	info.add_child(pills)
	head.add_child(info)
	head.add_child(UI.spacer())
	var money := UI.vbox(2)
	money.add_child(UI.stat_chip("Price", UI.money_text(price), UI.GOOD if price <= w.money else UI.BAD))
	money.add_child(UI.label("Wage %s / wk" % UI.money_text(PlayerData.salary_for_rating(p.rating_exact())), 12, UI.TEXT_DIM))
	head.add_child(money)
	box.add_child(head)
	box.add_child(UI.divider())

	var cap := UI.hbox(10)
	cap.add_child(UI.caption("Attributes", UI.TEXT))
	cap.add_child(UI.spacer())
	if cmp != null:
		cap.add_child(UI.label("vs your weakest starter  %s (%d)" % [cmp.player_name, cmp.rating()], 13, UI.TEXT_DIM))
	box.add_child(cap)
	var total_diff := 0.0
	for k: String in PlayerData.STAT_KEYS:
		var row := UI.hbox(10)
		var v := w.est_stat(p, k)
		var sr := UI.stat_row(k, v)
		if not kn:
			var rg := w.stat_range(p, k)
			sr.add_child(UI.label("%d-%d" % [rg[0], rg[1]], 12, UI.TEXT_FAINT))
		sr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(sr)
		if cmp != null:
			var d := v - cmp.stat(k)
			total_diff += d
			var cv := UI.label("%d" % int(round(cmp.stat(k))), 13, UI.TEXT_FAINT)
			cv.custom_minimum_size = Vector2(28, 0)
			cv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			row.add_child(cv)
			var dl := UI.label("%+d" % int(round(d)), 14, UI.GOOD if d >= 1 else (UI.BAD if d <= -1 else UI.TEXT_DIM), 700)
			dl.custom_minimum_size = Vector2(40, 0)
			dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			row.add_child(dl)
		box.add_child(row)
	if cmp != null:
		var verdict := "Clear upgrade" if total_diff >= 18 else ("Slight upgrade" if total_diff >= 4 else ("Similar level" if total_diff > -4 else "Downgrade"))
		var vc := UI.GOOD if total_diff >= 4 else (UI.TEXT_DIM if total_diff > -4 else UI.BAD)
		var vrow := UI.hbox(8)
		vrow.add_child(UI.pill(verdict, vc))
		vrow.add_child(UI.label("Attribute total %+d vs %s" % [int(round(total_diff)), cmp.player_name], 13, UI.TEXT_DIM))
		box.add_child(vrow)
	box.add_child(UI.divider())
	var btns := UI.hbox(10)
	btns.add_child(UI.button("Close", _close_scout, 140, "GhostButton"))
	if not kn:
		var queued := w.scout_queue.has(p.uid)
		var sb := UI.button("Scouting..." if queued else "Send scout", func() -> void:
			_close_scout()
			_act(w.queue_scout(p), "%s added to the scouting list (%d a week)." % [p.player_name, 1 + w.staff_stars("Scout")]), 160, "PrimaryButton")
		sb.disabled = queued
		btns.add_child(sb)
	btns.add_child(UI.spacer())
	btns.add_child(UI.button("Full card", func() -> void:
		_close_scout()
		_view_player(p), 140, "GhostButton"))
	if owner != null and p.loan_from == "":
		var ln := UI.button("Loan in  %s/wk" % UI.money_text(w.loan_in_fee(p)), func() -> void:
			_close_scout()
			_act(w.loan_in(p), "%s joins on loan until the end of the season." % p.player_name), 190, "GhostButton")
		ln.disabled = not w.window_open()
		ln.tooltip_text = "Borrow them until the season ends: you pay 60% of their wage. Clubs rarely loan out starters."
		btns.add_child(ln)
	var buy := UI.button(("Sign  " if owner == null else "Bid  ") + UI.money_text(price), func() -> void:
		_close_scout()
		_buy(p), 220, "PrimaryButton")
	if not w.can_sign_now():
		buy.disabled = true
		buy.tooltip_text = w.window_text()
	btns.add_child(buy)
	box.add_child(btns)


func _close_scout() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null


# =============================================================================
# League
# =============================================================================

const LEAGUE_COLS := [["#", 30, "c"], ["Team", 0, "l"], ["W", 40, "c"], ["L", 40, "c"], ["RD", 50, "c"], ["RTG", 48, "c"],
	["Rep", 44, "c"], ["Budget", 110, "r"], ["", 110, "c"]]


func _league() -> void:
	if _league_view < 0:
		_league_view = w.user_team().league
	var lg: Dictionary = World.LEAGUES[_league_view]
	_page_title("League", "Prize pool %s  -  top %d make the playoffs" % [UI.money_text(lg.prize), World.PLAYOFF_SIZE])
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
			UI.rating_chip(t.rating()), UI.label(str(int(t.reputation)), 14, UI.TEXT_DIM),
			UI.label(UI.money_text(w.money if mine else t.money), 13, UI.TEXT_DIM), zone], LEAGUE_COLS, i, mine))
	card.add_child(UI.scroll(list))
	card.add_child(UI.label("Click a team for its squad and season stats.", 12, UI.TEXT_FAINT))


# =============================================================================
# Tournaments
# =============================================================================

func _tournaments() -> void:
	_page_title("Tournaments", "Cups are optional; league playoffs are automatic for the top %d." % World.PLAYOFF_SIZE)
	var list := UI.vbox(12)
	for t in w.tournaments:
		list.add_child(_tournament_card(t))
	_content.add_child(UI.scroll(list))


func _tournament_card(t: Dictionary) -> Control:
	var p := PanelContainer.new()
	var box := UI.vbox(8)
	p.add_child(box)
	var head := UI.hbox(10)
	box.add_child(head)
	head.add_child(UI.label(String(t.name), 19, UI.TEXT, 700))
	var ui := w.team_index(w.user_team())
	if t.kind == "cup":
		var info := w.tier_info(t)
		head.add_child(UI.pill(String(t.tier), {"Open": UI.TEXT_DIM, "Challenger": UI.ACCENT2, "Major": Color("c084fc")}[t.tier]))
		head.add_child(UI.pill("Weeks %d-%d" % [t.start_week, int(t.start_week) + 3], UI.TEXT_DIM))
		head.add_child(UI.pill("Prize %s" % UI.money_text(info.pool), UI.GOOD))
		head.add_child(UI.pill("Entry %s" % UI.money_text(info.fee), UI.TEXT_DIM))
	else:
		head.add_child(UI.pill("Playoffs", UI.ACCENT))
		head.add_child(UI.pill("Weeks %d-%d" % [t.start_week, int(t.start_week) + 2], UI.TEXT_DIM))
	head.add_child(UI.spacer())
	match t.status:
		"upcoming":
			var reason := w.can_enroll(t)
			if t.user_enrolled:
				head.add_child(UI.pill("Registered", UI.GOOD))
			elif reason == "":
				var tt: Dictionary = t
				head.add_child(UI.small_button("Enroll  " + UI.money_text(w.tier_info(t).fee), func() -> void:
					w.enroll(tt)
					_act("", "Registered for %s." % tt.name), 170, "PrimaryButton"))
			else:
				head.add_child(UI.label(reason, 13, UI.TEXT_FAINT))
		"running", "done":
			if t.status == "done":
				var champ: TeamData = w.teams[w._team_with_place(t, 1)]
				head.add_child(UI.label("Champion", 12, UI.TEXT_DIM))
				head.add_child(UI.team_link(champ, _view_team.bind(champ), 14, champ == w.user_team()))
			if t.placements.has(ui):
				head.add_child(UI.pill("You: " + World._place_name(t.placements[ui]), UI.WARN))
			elif t.teams.has(ui):
				head.add_child(UI.pill("You're still in", UI.GOOD))
			box.add_child(_bracket(t))
			if t.status == "running":
				box.add_child(_watch_row(t))
	return p


func _bracket(t: Dictionary) -> Control:
	return UI.bracket(w, t, _view_team)


# =============================================================================
# Rankings
# =============================================================================

const RANK_COLS := [["#", 34, "c"], ["Team", 0, "l"], ["League", 70, "c"], ["Points", 70, "r"], ["RTG", 48, "c"],
	["Rep", 44, "c"], ["Titles", 54, "c"], ["Best player", 190, "l"]]


func _rankings() -> void:
	_page_title("World rankings", "Points from cups and playoffs; half carry over each season.")
	var card := UI.card(_content, "", true)
	card.add_child(UI.table_header(RANK_COLS))
	var list := UI.vbox(2)
	var pos := 1
	for t in w.rankings():
		var best: PlayerData = null
		for p in t.roster:
			if best == null or p.rating_exact() > best.rating_exact():
				best = p
		var mine := t == w.user_team()
		var best_cell: Control = UI.label("-", 13, UI.TEXT_DIM)
		if best != null:
			best_cell = UI.link_button("%s (%d)" % [best.player_name, best.rating()], _view_player.bind(best), 13, UI.TEXT_DIM, 500)
		list.add_child(UI.table_row([UI.label(str(pos), 14, UI.TEXT_DIM, 600), UI.team_link(t, _view_team.bind(t), 14, mine),
			UI.pill(World.LEAGUES[t.league].short, UI.TEXT_DIM, 11), UI.label(str(t.points), 14, UI.TEXT, 600),
			UI.rating_chip(t.rating()), UI.label(str(int(t.reputation)), 14, UI.TEXT_DIM), UI.label(str(t.titles), 14, UI.WARN if t.titles > 0 else UI.TEXT_FAINT),
			best_cell], RANK_COLS, pos - 1, mine))
		pos += 1
	card.add_child(UI.scroll(list))


# =============================================================================
# Finances
# =============================================================================

const LEDGER_COLS := [["When", 70, "l"], ["Item", 0, "l"], ["Amount", 110, "r"]]
var _loan_pick := {} ## lender index -> chosen amount


func _finances() -> void:
	_page_title("Finances", "Week %d  -  %s" % [w.week, "in debt for %d week(s)" % w.debt_weeks if w.money < 0 else "solvent"])
	var chips := UI.hbox(14)
	_content.add_child(chips)
	var net := w.weekly_net()
	var debt := 0
	for l in w.loans:
		if l.kind == "loan":
			debt += int(l.weekly) * int(l.weeks_left)
	for c in [["Balance", UI.money_text(w.money), UI.GOOD if w.money >= 0 else UI.BAD], ["Income / wk", UI.money_text(w.weekly_income()), UI.GOOD],
			["Costs / wk", UI.money_text(-(w.payroll() + w.training_cost() + w.loan_payments() + int(w.weekly_income() * w.stake_share()))), UI.BAD],
			["Net / wk", UI.money_text(net), UI.GOOD if net >= 0 else UI.BAD], ["Owed on loans", UI.money_text(debt), UI.WARN if debt > 0 else UI.TEXT_DIM]]:
		var card := UI.card(chips, "")
		card.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_child(UI.stat_chip(c[0], c[1], c[2]))
	var cols := UI.hbox(14)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(cols)
	var left := UI.vbox(12)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ls := UI.scroll(left)
	ls.size_flags_stretch_ratio = 1.5
	cols.add_child(ls)
	_sponsor_section(left)
	_loan_section(left)
	for l in left.find_children("*", "Label", true, false):
		if (l as Label).text.length() > 40:
			(l as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			(l as Label).size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var lc := UI.card(cols, "Transactions", true, UI.TEXT_DIM)
	lc.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lc.add_child(UI.table_header(LEDGER_COLS))
	var list := UI.vbox(2)
	var n := 0
	for i in range(w.ledger.size() - 1, -1, -1):
		var e: Dictionary = w.ledger[i]
		var amt := int(e.amount)
		list.add_child(UI.table_row([UI.label("S%d W%d" % [int(e.season), int(e.week)], 12, UI.TEXT_FAINT), UI.label(String(e.text), 13),
			UI.label(UI.money_text(amt), 13, UI.GOOD if amt >= 0 else UI.BAD, 600)], LEDGER_COLS, n))
		n += 1
	lc.add_child(UI.scroll(list))


func _deal_terms(d: Dictionary) -> String:
	var parts: Array = ["%s/wk" % UI.money_text(int(d.weekly))]
	if int(d.get("per_win", 0)) > 0:
		parts.append("+%s per win" % UI.money_text(int(d.per_win)))
	if int(d.get("bonus", 0)) > 0:
		parts.append("%s signing bonus" % UI.money_text(int(d.bonus)))
	if String(d.get("goal", "")) != "" and int(d.get("goal_bonus", 0)) > 0:
		parts.append("%s if you %s" % [UI.money_text(int(d.goal_bonus)), "reach the playoffs" if d.goal == "playoffs" else "win a trophy"])
	return "  -  ".join(parts)


func _sponsor_section(parent: Control) -> void:
	var c := UI.card(parent, "Sponsorship", false, UI.GOOD)
	var slots := UI.hbox(10)
	c.add_child(slots)
	for slot in World.SPONSOR_SLOTS:
		var d := w.sponsor_in_slot(slot)
		var p := PanelContainer.new()
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p.add_theme_stylebox_override("panel", UI._box(UI.PANEL_HI, 4, Color(UI.GOOD, 0.35) if not d.is_empty() else UI.BORDER, 1, 10, 8))
		var v := UI.vbox(3)
		p.add_child(v)
		v.add_child(UI.caption("%s sponsor" % slot, UI.TEXT_FAINT))
		if d.is_empty():
			v.add_child(UI.label("Empty", 16, UI.WARN, 700))
			v.add_child(UI.label("Accept an offer below to fill it.", 12, UI.TEXT_FAINT))
		else:
			v.add_child(UI.label(String(d.brand), 16, UI.TEXT, 700))
			var tl := UI.label(_deal_terms(d), 12, UI.TEXT_DIM)
			tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v.add_child(tl)
			var r := UI.hbox(6)
			r.add_child(UI.label("%d weeks left" % int(d.weeks), 12, UI.TEXT_FAINT))
			r.add_child(UI.spacer())
			var dd := d
			var end := UI.small_button("End (%s)" % UI.money_text(w.termination_fee(d)), func() -> void:
				_act(w.end_sponsor(dd), "Ended the %s deal." % dd.brand), 110, "GhostButton")
			r.add_child(end)
			v.add_child(r)
		slots.add_child(p)
	c.add_child(UI.caption("Offers", UI.TEXT))
	if w.sponsor_offers.is_empty():
		c.add_child(UI.label("No offers right now. New ones arrive most weeks; winning streaks bring more.", 13, UI.TEXT_DIM))
	for i in w.sponsor_offers.size():
		var o: Dictionary = w.sponsor_offers[i]
		var r := UI.hbox(10)
		var info := UI.vbox(0)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var top := UI.hbox(8)
		top.add_child(UI.label(String(o.brand), 15, UI.TEXT, 700))
		top.add_child(UI.pill(String(o.slot), UI.ACCENT2, 10))
		top.add_child(UI.pill(String(o.style), UI.TEXT_DIM, 10))
		info.add_child(top)
		info.add_child(UI.label("%s  -  %d weeks  -  offer expires in %d wk" % [_deal_terms(o), int(o.weeks), int(o.expires)], 12, UI.TEXT_DIM))
		r.add_child(info)
		var idx := i
		var acc := UI.small_button("Accept", func() -> void:
			_act(w.accept_sponsor(idx), "Signed with %s." % o.brand), 80, "PrimaryButton")
		if not w.sponsor_in_slot(String(o.slot)).is_empty():
			acc.disabled = true
			acc.tooltip_text = "%s slot is taken: end that deal first." % o.slot
		r.add_child(acc)
		r.add_child(UI.small_button("Decline", func() -> void:
			_refresh(w.decline_sponsor(idx)), 76, "GhostButton"))
		if bool(o.get("countered", false)):
			top.add_child(UI.pill("Improved", UI.GOOD, 10))
		c.add_child(r)


func _loan_section(parent: Control) -> void:
	var c := UI.card(parent, "Loans and investors", false, UI.ACCENT2)
	if not w.loans.is_empty():
		c.add_child(UI.caption("Active", UI.TEXT))
		for x: Dictionary in w.loans:
			var r := UI.hbox(10)
			var txt := ""
			if x.kind == "loan":
				txt = "%s: %s/wk, %d of %d weeks left (borrowed %s)" % [x.lender, UI.money_text(int(x.weekly)), int(x.weeks_left), int(x.weeks), UI.money_text(int(x.principal))]
			else:
				txt = "%s: %d%% of income, %d weeks left (invested %s)" % [x.lender, int(float(x.share) * 100.0), int(x.weeks_left), UI.money_text(int(x.principal))]
			var l := UI.label(txt, 13, UI.TEXT)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			r.add_child(l)
			var xx := x
			r.add_child(UI.small_button(("Pay off " if x.kind == "loan" else "Buy out ") + UI.money_text(w.payoff_cost(x)), func() -> void:
				_act(w.repay_loan(xx), "Done: %s is settled." % xx.lender), 150, "GhostButton"))
			c.add_child(r)
		c.add_child(UI.divider())
	c.add_child(UI.caption("Lenders", UI.TEXT))
	for li in World.LENDERS.size():
		var l: Dictionary = World.LENDERS[li]
		var block := w.lender_block(l)
		var limit := w.lender_limit(l)
		var amounts: Array = []
		for f in [0.25, 0.5, 1.0]:
			var a := int(limit * f / 5000.0) * 5000
			if a > 0 and not amounts.has(a):
				amounts.append(a)
		var pick: int = int(_loan_pick.get(li, amounts[amounts.size() / 2] if not amounts.is_empty() else 0))
		if not amounts.has(pick) and not amounts.is_empty():
			pick = amounts[0]
		var r := UI.hbox(10)
		var info := UI.vbox(0)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var top := UI.hbox(8)
		top.add_child(UI.label(String(l.name), 15, UI.TEXT if block == "" else UI.TEXT_DIM, 700))
		top.add_child(UI.pill("Loan %d%%" % int(float(l.rate) * 100.0) if l.kind == "loan" else "Equity", UI.ACCENT2 if l.kind == "loan" else UI.WARN, 10))
		info.add_child(top)
		info.add_child(UI.label(String(l.desc), 12, UI.TEXT_DIM))
		if block == "" and pick > 0:
			info.add_child(UI.label(w.loan_terms(l, pick).text, 12, UI.TEXT_FAINT))
		r.add_child(info)
		if block != "":
			r.add_child(UI.label(block, 12, UI.TEXT_FAINT))
		elif not amounts.is_empty():
			var labels: Array = []
			for a: int in amounts:
				labels.append(UI.money_text(a))
			var lii := li
			r.add_child(_option(amounts, labels, pick, func(v: Variant) -> void:
				_loan_pick[lii] = int(v)
				_refresh()))
			var amt := pick
			r.add_child(UI.small_button("Take", func() -> void:
				_act(w.take_loan(lii, amt), "%s: %s received." % [l.name, UI.money_text(amt)]), 70, "PrimaryButton"))
		c.add_child(r)
	c.add_child(UI.label("Loans are repaid weekly whatever happens. Equity investors take their share of every sponsor payment, prize and win bonus. In debt, wages go unpaid: morale and reputation drop, and from week 3 creditors sell your best player.", 12, UI.TEXT_FAINT))


func _banner(text: String, color: Color, btn: String = "", cb: Callable = Callable()) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI._edge_box(Color(color, 0.08), color, SIDE_LEFT, 3, Color(0, 0, 0, 0), 14, 8))
	var h := UI.hbox(10)
	p.add_child(h)
	var l := UI.label(text, 14, color, 600)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	if btn != "":
		h.add_child(UI.small_button(btn, cb, 130, "PrimaryButton"))
	_content.add_child(p)


# =============================================================================
# Club: board, staff, facilities, academy
# =============================================================================

const ACADEMY_COLS := [["Prospect", 0, "l"], ["Role", 62, "l"], ["Age", 34, "c"], ["RTG", 42, "c"], ["Pot.", 60, "l"], ["", 260, "r"]]


func _club() -> void:
	_page_title("Club", "Board, staff, facilities and academy")
	var page := UI.vbox(14)
	# Board
	var bc := UI.card(page, "Board", false, UI.WARN)
	if w.sacked:
		bc.add_child(UI.label("You've been sacked. Pick a club to continue your career.", 15, UI.BAD, 700))
	elif not w.board.is_empty():
		var h := UI.hbox(24)
		h.add_child(UI.stat_chip("Objective", String(w.board.text)))
		h.add_child(UI.stat_chip("Status", w.board_status(), UI.GOOD if w.board_status().begins_with("On") else UI.WARN))
		var conf := float(w.board.confidence)
		h.add_child(UI.stat_chip("Confidence", "%d / 100" % int(conf), UI.GOOD if conf >= 50 else (UI.WARN if conf >= 25 else UI.BAD)))
		h.add_child(UI.stat_chip("Difficulty", w.difficulty))
		bc.add_child(h)
		bc.add_child(UI.label("Wins and meeting the objective raise confidence; losses, debt and missing it lower it. Below 10 you're sacked.", 12, UI.TEXT_FAINT))
	for i in w.job_offers.size():
		var o: Dictionary = w.job_offers[i]
		var t: TeamData = w.teams[int(o.team)]
		var row := UI.hbox(10)
		var tl := UI.team_link(t, _view_team.bind(t), 15)
		tl.custom_minimum_size.x = 210
		row.add_child(tl)
		row.add_child(UI.pill(World.LEAGUES[t.league].short, UI.TEXT_DIM, 11))
		row.add_child(UI.rating_chip(t.rating(), 12))
		row.add_child(UI.label("Budget %s" % UI.money_text(t.money), 13, UI.TEXT_DIM))
		var nl := UI.label(String(o.note), 12, UI.TEXT_FAINT)
		nl.clip_text = true
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nl)
		var idx := i
		row.add_child(UI.small_button("Take the job", func() -> void:
			_confirm("Move to %s?" % t.team_name, "You leave %s: its squad, sponsors, loans, academy and facilities stay behind. Your staff come with you." % w.user_team().team_name, "Take the job", func() -> void:
				_act(w.accept_job(idx), "Welcome to %s!" % t.team_name)), 140, "PrimaryButton"))
		if not w.sacked or w.job_offers.size() > 1:
			row.add_child(UI.small_button("Decline", func() -> void: _act(w.decline_job(idx), "Declined."), 90, "GhostButton"))
		bc.add_child(row)

	var row2 := UI.hbox(14)
	page.add_child(row2)
	# Staff
	var sc := UI.card(row2, "Staff", false, UI.ACCENT2)
	sc.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for role: String in World.STAFF_ROLES:
		var h := UI.hbox(8)
		var v := UI.vbox(0)
		v.add_child(UI.label(role, 14, UI.TEXT, 700))
		var sd := UI.label(String(World.STAFF_ROLES[role].desc), 11, UI.TEXT_FAINT)
		sd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(sd)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(v)
		if w.staff.has(role):
			var st: Dictionary = w.staff[role]
			h.add_child(UI.label(String(st.name), 13, UI.ACCENT2, 600))
			h.add_child(UI.label(_stars(int(st.stars)), 14, UI.WARN))
			h.add_child(UI.label("%s/wk" % UI.money_text(int(st.wage)), 12, UI.TEXT_DIM))
			var rr := role
			h.add_child(UI.small_button("Fire", func() -> void:
				_confirm("Fire %s?" % st.name, "Severance is 4 weeks' wages (%s)." % UI.money_text(int(st.wage) * 4), "Fire", func() -> void: _act(w.fire_staff(rr), "Staff member let go.")), 60, "GhostButton"))
		else:
			h.add_child(UI.label("Vacant", 13, UI.TEXT_FAINT))
		sc.add_child(h)
	sc.add_child(UI.divider())
	sc.add_child(UI.caption("Available"))
	for i in w.staff_market.size():
		var c: Dictionary = w.staff_market[i]
		var h := UI.hbox(8)
		h.add_child(UI.label(String(c.role), 13, UI.TEXT_DIM))
		h.add_child(UI.label(String(c.name), 13, UI.TEXT, 600))
		h.add_child(UI.label(_stars(int(c.stars)), 14, UI.WARN))
		h.add_child(UI.spacer())
		h.add_child(UI.label("%s/wk" % UI.money_text(int(c.wage)), 12, UI.TEXT_DIM))
		var ci := i
		h.add_child(UI.small_button("Hire", func() -> void: _act(w.hire_staff(ci), "Hired %s." % c.name), 70, "PrimaryButton"))
		sc.add_child(h)
	sc.add_child(UI.label("Hiring costs 4 weeks' wages up front. The market refreshes every 6 weeks.", 11, UI.TEXT_FAINT))
	# Facilities
	var fc := UI.card(row2, "Facilities", false, UI.GOOD)
	fc.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for f: String in World.FACILITIES:
		var info: Dictionary = World.FACILITIES[f]
		var lv := w.fac(f)
		var h := UI.hbox(8)
		var v := UI.vbox(0)
		var top := UI.hbox(6)
		top.add_child(UI.label(f, 14, UI.TEXT if lv > 0 else UI.TEXT_DIM, 700))
		top.add_child(UI.label("L%d / %d" % [lv, int(info.max)], 12, UI.ACCENT2 if lv > 0 else UI.TEXT_FAINT, 600))
		v.add_child(top)
		var fd := UI.label(String(info.desc), 11, UI.TEXT_FAINT)
		fd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(fd)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(v)
		var block := w.fac_block(f)
		var cost := w.fac_cost(f)
		if cost < 0:
			h.add_child(UI.pill("Max", UI.GOOD))
		elif block != "":
			h.add_child(UI.label(block, 12, UI.WARN))
		else:
			var ff := f
			h.add_child(UI.small_button("Upgrade  " + UI.money_text(cost), func() -> void: _act(w.upgrade_fac(ff), "%s upgraded." % ff), 160, "PrimaryButton"))
		fc.add_child(h)
	fc.add_child(UI.label("Upkeep: %s / wk" % UI.money_text(w.facility_upkeep()), 12, UI.TEXT_DIM))
	# Academy
	var ac := UI.card(page, "Youth academy", false, UI.ACCENT)
	if w.fac("Youth Academy") == 0:
		ac.add_child(UI.label("Build the Youth Academy facility (needs Training Center L2) to bring in prospects aged 16-17.", 13, UI.TEXT_DIM))
	else:
		ac.add_child(UI.label("%d / %d prospects. New intake every season; they grow each week and leave at 20 unless promoted." % [w.academy.size(), w.academy_capacity()], 12, UI.TEXT_FAINT))
		ac.add_child(UI.table_header(ACADEMY_COLS))
		for i in w.academy.size():
			var pr: PlayerData = w.academy[i]
			var btns := UI.hbox(6)
			var pp := pr
			btns.add_child(UI.small_button("Promote", func() -> void: _act(w.promote_academy(pp), "%s promoted to the first team." % pp.player_name), 80, "PrimaryButton"))
			btns.add_child(UI.small_button("Loan", func() -> void: _act(w.loan_out(pp), "%s is out on loan." % pp.player_name), 60, "GhostButton"))
			btns.add_child(UI.small_button("Sell " + UI.money_text(pr.market_value()), func() -> void: _act(w.sell_academy(pp), "Sold %s." % pp.player_name), 100, "GhostButton"))
			btns.add_child(UI.small_button("Release", func() -> void:
				w.release_academy(pp)
				_refresh("Released %s." % pp.player_name), 70, "GhostButton"))
			ac.add_child(UI.table_row([UI.link_button(pr.player_name, _view_player.bind(pr), 14), UI.label(pr.role, 12, UI.TEXT_DIM), UI.label(str(pr.age), 13),
				UI.rating_chip(pr.rating()), UI.label(World.UI_pot(pr), 12, UI.WARN), btns], ACADEMY_COLS, i))
	_club_extras(page)
	_content.add_child(UI.scroll(page))


func _club_extras(page: VBoxContainer) -> void:
	var ut := w.user_team()
	var row := UI.hbox(14)
	page.add_child(row)
	# Fans and merch
	var fc := UI.card(row, "Fans & merch", false, UI.GOOD)
	fc.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ch := HFlowContainer.new()
	ch.add_theme_constant_override("h_separation", 22)
	ch.add_child(UI.stat_chip("Fans", World.fame_text(w.club_fans), UI.ACCENT2))
	ch.add_child(UI.stat_chip("Merch / wk", UI.money_text(w.merch_income()), UI.GOOD))
	ch.add_child(UI.stat_chip("Merch range", "L%d / %d" % [w.merch_level, World.MERCH_COSTS.size()]))
	fc.add_child(ch)
	var mc := w.merch_cost()
	var mb := UI.small_button("Maxed" if mc < 0 else "Upgrade merch range  " + UI.money_text(mc), func() -> void: _act(w.upgrade_merch(), "Merch range upgraded."), 260, "PrimaryButton")
	mb.disabled = mc < 0
	fc.add_child(mb)
	var fl := UI.label("Fans grow with wins, trophies, promotions, derbies and Showman players. Each merch level sells 50% more per fan.", 11, UI.TEXT_FAINT)
	fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fc.add_child(fl)
	# Derby
	var dc := UI.card(row, "Local rivals", false, UI.BAD)
	dc.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rv := w.derby_rival(ut)
	if rv == null:
		dc.add_child(UI.label("No local rival in this league.", 13, UI.TEXT_DIM))
	else:
		var tl := UI.team_link(rv, _view_team.bind(rv), 16)
		tl.custom_minimum_size.x = 220
		dc.add_child(tl)
		dc.add_child(UI.label("Your derby record: %d W - %d L" % [int(w.derby_record[0]), int(w.derby_record[1])], 14, UI.TEXT, 600))
		var dl := UI.label("Derbies swing the board's confidence, your fans and both clubs' reputations. Press conferences come before big games.", 11, UI.TEXT_FAINT)
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dc.add_child(dl)
	# Affiliate
	var ac := UI.card(page, "Second roster (affiliate club)", false, UI.ACCENT2)
	var aff := w.affiliate()
	if aff == null:
		var al := UI.label("Own a lower-league club as a feeder: send players down to get games, call them back up any time. Pays a little each week.", 12, UI.TEXT_DIM)
		al.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ac.add_child(al)
		for t: TeamData in w.affiliate_candidates():
			var r := UI.hbox(10)
			var tl2 := UI.team_link(t, _view_team.bind(t), 14)
			tl2.custom_minimum_size.x = 220
			r.add_child(tl2)
			r.add_child(UI.pill(World.LEAGUES[t.league].short, UI.TEXT_DIM, 11))
			r.add_child(UI.rating_chip(t.rating(), 12))
			r.add_child(UI.spacer())
			var tt := t
			r.add_child(UI.small_button("Buy  " + UI.money_text(w.affiliate_cost(t)), func() -> void:
				_confirm("Buy %s?" % tt.team_name, "They become your affiliate for %s." % UI.money_text(w.affiliate_cost(tt)), "Buy", func() -> void:
					_act(w.buy_affiliate(tt), "%s is your affiliate." % tt.team_name)), 170, "PrimaryButton"))
			ac.add_child(r)
	else:
		var head := UI.hbox(10)
		var tl3 := UI.team_link(aff, _view_team.bind(aff), 16)
		tl3.custom_minimum_size.x = 240
		head.add_child(tl3)
		head.add_child(UI.pill(World.LEAGUES[aff.league].name, UI.TEXT_DIM))
		head.add_child(UI.label("Income %s / wk" % UI.money_text(w.affiliate_income()), 13, UI.GOOD))
		ac.add_child(head)
		for p in aff.roster:
			var r := UI.hbox(10)
			r.add_child(UI.rating_chip(p.rating(), 12))
			var nb := UI.link_button(p.player_name, _view_player.bind(p), 14)
			nb.clip_text = false
			r.add_child(nb)
			r.add_child(UI.label("%s, %d" % [p.role, p.age], 12, UI.TEXT_DIM))
			r.add_child(UI.spacer())
			var pp := p
			r.add_child(UI.small_button("Call up", func() -> void: _act(w.call_up(pp), "%s called up." % pp.player_name), 90, "PrimaryButton"))
			ac.add_child(r)
	# Loans
	var lc := UI.card(page, "Loans", false, UI.WARN)
	var any := false
	for t in w.teams:
		for p in t.roster:
			if p.loan_from == "user":
				any = true
				lc.add_child(UI.label("OUT  %s (%s) at %s: %d matches this season" % [p.player_name, p.loan_kind, t.team_name, int(p.season_stats.get("m", 0))], 13, UI.TEXT))
			elif p.loan_kind == "in" and t == ut:
				any = true
				lc.add_child(UI.label("IN  %s from %s: %s / wk" % [p.player_name, p.loan_from, UI.money_text(p.loan_fee)], 13, UI.ACCENT2))
	if not any:
		var ll := UI.label("No loans. Loan players out from the roster menu or the academy; loan players in from their scouting card (Transfers). Everyone returns at season end.", 12, UI.TEXT_DIM)
		ll.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lc.add_child(ll)


## Live viewing: this round's matches you're not in.
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
				if Game.prepare_watch_match(w, a, b, Game.MANAGER_SCENE):
					Game.goto(Game.MATCH_SCENE), 0, "GhostButton"))
			n += 1
	if n == 0:
		row.add_child(UI.label("nothing left to watch this week", 12, UI.TEXT_FAINT))
	return row


func _stars(n: int) -> String:
	return "*".repeat(n) + "-".repeat(maxi(0, 5 - n))


func _history() -> void:
	_page_title("History", "Season reviews, champions, records and the Hall of Fame")
	HistoryView.build(_content, w, _hist_tab, _hist_review, func(t: String) -> void:
		_hist_tab = t
		_refresh(), func(i: int) -> void:
		_hist_review = i
		_refresh())


## Contract terms: optional release clause, loyalty bonus and appearance fees.
func _contract_dialog(p: PlayerData, kind: String) -> void:
	var m := UI.modal(self, 560, UI.ACCENT2)
	var overlay: Control = m[0]
	var box: VBoxContainer = m[1]
	box.add_child(UI.heading(("Sign %s" if kind == "sign" else "Extend %s") % p.player_name, 22))
	box.add_child(UI.label("%s  -  RTG %d  -  age %d" % [p.role, p.rating(), p.age], 13, UI.TEXT_DIM))
	var state := {"release": 0.0, "loyalty": false, "appear": false}
	var summary := UI.label("", 14, UI.TEXT, 600)
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var update := func() -> void:
		var t := w.contract_terms(p, float(state.release), bool(state.loyalty), bool(state.appear))
		var lines: Array = ["Wage: %s / wk" % UI.money_text(int(t.wage))]
		if int(t.release) > 0:
			lines.append("Release clause: %s (any club paying it takes them)" % UI.money_text(int(t.release)))
		if int(t.loyalty) > 0:
			lines.append("Loyalty bonus: %s, paid if they see the deal out" % UI.money_text(int(t.loyalty)))
		if int(t.appearance) > 0:
			lines.append("Appearance fee: %s per match played" % UI.money_text(int(t.appearance)))
		if kind == "sign":
			lines.append("Signing fee: %s" % UI.money_text(w.signing_fee(p)))
		else:
			lines.append("Extension bonus: %s" % UI.money_text(w.extension_cost(p)))
		summary.text = "\n".join(lines)
	var r1 := UI.hbox(8)
	r1.add_child(UI.label("Release clause", 14, UI.TEXT_DIM))
	r1.add_child(UI.spacer())
	var rel := OptionButton.new()
	for t in ["None", "2x value (-5% wage)", "1.5x value (-10% wage)", "1.2x value (-15% wage)"]:
		rel.add_item(t)
	rel.item_selected.connect(func(i: int) -> void:
		state.release = [0.0, 2.0, 1.5, 1.2][i]
		update.call())
	r1.add_child(rel)
	box.add_child(r1)
	var loy := CheckBox.new()
	loy.text = "Loyalty bonus (10 weeks' wage at the end; -5% wage, happier, likelier to sign)"
	loy.toggled.connect(func(on: bool) -> void:
		state.loyalty = on
		update.call())
	box.add_child(loy)
	var app := CheckBox.new()
	app.text = "Appearance fees (-25% wage, 40% of the base wage per match played)"
	app.toggled.connect(func(on: bool) -> void:
		state.appear = on
		update.call())
	box.add_child(app)
	box.add_child(UI.divider())
	box.add_child(summary)
	update.call()
	var row := UI.hbox(10)
	row.add_child(UI.button("Cancel", func() -> void: overlay.queue_free(), 140, "GhostButton"))
	row.add_child(UI.spacer())
	row.add_child(UI.button("Sign" if kind == "sign" else "Extend", func() -> void:
		var t := w.contract_terms(p, float(state.release), bool(state.loyalty), bool(state.appear))
		overlay.queue_free()
		if kind == "sign":
			_act(w.sign_free_agent(p, t), "Signed %s!" % p.player_name)
		else:
			_act(w.extend_contract(p, t), "Extended %s through season %d." % [p.player_name, p.contract_until]), 160, "PrimaryButton"))
	box.add_child(row)
