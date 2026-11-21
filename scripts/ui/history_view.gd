class_name HistoryView
extends RefCounted
## World history pages shared by both career hubs: season reviews, champions,
## records and the Hall of Fame. Plus the end-of-season review popup.

const TABS := ["Season review", "Champions", "Records", "Hall of Fame"]
const HOF_COLS := [["#", 30, "c"], ["Player", 0, "l"], ["Nation", 90, "l"], ["Last club", 150, "l"], ["Retired", 60, "c"], ["Titles", 50, "c"],
	["Matches", 64, "c"], ["K/D", 50, "c"], ["Peak", 50, "c"], ["Score", 56, "c"]]
const REC_COLS := [["Record", 220, "l"], ["Value", 90, "c"], ["Holder", 0, "l"], ["Details", 300, "l"], ["When", 70, "c"]]


## tab: current tab; review_idx: which season review (-1 = latest).
static func build(parent: Control, w: World, tab: String, review_idx: int, on_tab: Callable, on_review: Callable) -> void:
	var bar := UI.hbox(8)
	for t: String in TABS:
		var tn := t
		bar.add_child(UI.small_button(t, func() -> void: on_tab.call(tn), 150, "PrimaryButton" if t == tab else ""))
	parent.add_child(bar)
	match tab:
		"Season review":
			_reviews(parent, w, review_idx, on_review)
		"Champions":
			_champions(parent, w)
		"Records":
			_records(parent, w)
		"Hall of Fame":
			_hall(parent, w)


static func _reviews(parent: Control, w: World, idx: int, on_review: Callable) -> void:
	if w.reviews.is_empty():
		var c := UI.card(parent, "Season review", true)
		c.add_child(UI.label("The first review is written when season %d ends." % w.season, 14, UI.TEXT_DIM))
		return
	var i := w.reviews.size() - 1 if idx < 0 or idx >= w.reviews.size() else idx
	var pick := UI.hbox(8)
	pick.add_child(UI.label("Season:", 13, UI.TEXT_DIM))
	for k in w.reviews.size():
		var kk := k
		pick.add_child(UI.small_button("S%d" % int(w.reviews[k].s), func() -> void: on_review.call(kk), 56, "PrimaryButton" if k == i else "GhostButton"))
	parent.add_child(pick)
	var body := UI.vbox(12)
	review_body(body, w.reviews[i])
	parent.add_child(UI.scroll(body))


## The review's content (used on the History page and in the popup).
static func review_body(box: VBoxContainer, r: Dictionary) -> void:
	var you: Dictionary = r.get("you", {})
	if not you.is_empty():
		var c := UI.card(box, "Your season", false, UI.ACCENT2)
		var chips := HFlowContainer.new()
		chips.add_theme_constant_override("h_separation", 26)
		chips.add_child(UI.stat_chip("Club", String(you.get("team", "-")), UI.ACCENT2))
		chips.add_child(UI.stat_chip("League finish", "#%d" % int(you.get("pos", 0))))
		chips.add_child(UI.stat_chip("Record", String(you.get("record", "-"))))
		if you.has("money"):
			chips.add_child(UI.stat_chip("Balance", UI.money_text(int(you.money)), UI.GOOD if int(you.money) >= 0 else UI.BAD))
		if you.has("avg"):
			chips.add_child(UI.stat_chip("Matches", str(int(you.m))))
			chips.add_child(UI.stat_chip("Avg rating", "%.2f" % float(you.avg), UI.GOOD if float(you.avg) >= 1.0 else UI.WARN))
			chips.add_child(UI.stat_chip("K/D", "%.2f" % float(you.kd)))
			chips.add_child(UI.stat_chip("Followers", World.fame_text(int(you.fame)), UI.ACCENT2))
		c.add_child(chips)
		if String(you.get("board", "")) != "":
			c.add_child(UI.label("Board: " + String(you.board), 13, UI.TEXT_DIM))
	var row := UI.hbox(12)
	box.add_child(row)
	var lc := UI.card(row, "Leagues", false, UI.ACCENT)
	lc.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for lg: Dictionary in r.get("leagues", []):
		var h := UI.hbox(8)
		h.add_child(UI.label(String(lg.name), 14, UI.TEXT, 700))
		h.add_child(UI.spacer())
		h.add_child(UI.label("Top: %s (%s)" % [lg.top, lg.record], 13, UI.TEXT_DIM))
		lc.add_child(h)
		var bits: Array = []
		if String(lg.playoffs) != "":
			bits.append("Playoff champions: %s" % lg.playoffs)
		if not (lg.up as Array).is_empty():
			bits.append("Up: %s" % ", ".join(lg.up))
		if not (lg.down as Array).is_empty():
			bits.append("Down: %s" % ", ".join(lg.down))
		var l := UI.label("   ".join(bits), 12, UI.TEXT_FAINT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lc.add_child(l)
	var side := UI.vbox(12)
	side.custom_minimum_size = Vector2(420, 0)
	row.add_child(side)
	var cc := UI.card(side, "Cups", false, UI.WARN)
	for cup: Dictionary in r.get("cups", []):
		var h := UI.hbox(8)
		h.add_child(UI.label(String(cup.name), 13, UI.TEXT))
		h.add_child(UI.spacer())
		h.add_child(UI.label(String(cup.team), 13, UI.WARN, 600))
		cc.add_child(h)
	var wc: Dictionary = r.get("world_cup", {})
	if not wc.is_empty():
		var h := UI.hbox(8)
		h.add_child(UI.label("World Cup", 13, UI.TEXT, 700))
		h.add_child(UI.spacer())
		h.add_child(UI.label(String(wc.winner), 13, UI.WARN, 700))
		cc.add_child(h)
		if String(wc.get("you", "")) != "":
			cc.add_child(UI.label("You: %s" % wc.you, 12, UI.TEXT_DIM))
	var ac := UI.card(side, "Awards", false, UI.GOOD)
	for a in r.get("awards", []):
		ac.add_child(UI.label(String(a), 13, UI.TEXT))
	if (r.get("awards", []) as Array).is_empty():
		ac.add_child(UI.label("-", 13, UI.TEXT_FAINT))
	var tc := UI.card(side, "Biggest transfers", false, UI.ACCENT2)
	for t: Dictionary in r.get("transfers", []):
		var h := UI.hbox(8)
		var n := UI.label("%s: %s to %s" % [t.player, t.from, t.to], 12, UI.TEXT)
		n.clip_text = true
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(n)
		h.add_child(UI.label(UI.money_text(int(t.fee)), 12, UI.GOOD, 600))
		tc.add_child(h)
	if (r.get("transfers", []) as Array).is_empty():
		tc.add_child(UI.label("-", 13, UI.TEXT_FAINT))


static func _champions(parent: Control, w: World) -> void:
	var by := {}
	for c: Dictionary in w.champions:
		var n := String(c.name)
		if not by.has(n):
			by[n] = []
		(by[n] as Array).append(c)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 12)
	flow.add_theme_constant_override("v_separation", 12)
	var names: Array = by.keys()
	names.sort()
	for n: String in names:
		var p := PanelContainer.new()
		p.custom_minimum_size = Vector2(300, 0)
		var v := UI.vbox(4)
		p.add_child(v)
		v.add_child(UI.label(n, 15, UI.WARN, 700))
		var list: Array = by[n]
		var counts := {}
		for i in range(list.size() - 1, -1, -1):
			var c: Dictionary = list[i]
			counts[c.team] = int(counts.get(c.team, 0)) + 1
			var h := UI.hbox(8)
			h.add_child(UI.label("S%d" % int(c.s), 12, UI.TEXT_FAINT, 600))
			h.add_child(UI.label(String(c.team), 13, UI.TEXT))
			v.add_child(h)
		var best := ""
		for t in counts:
			if best == "" or int(counts[t]) > int(counts[best]):
				best = t
		if int(counts.get(best, 0)) > 1:
			v.add_child(UI.label("Most wins: %s (%d)" % [best, int(counts[best])], 11, UI.TEXT_DIM))
		flow.add_child(p)
	if names.is_empty():
		parent.add_child(UI.label("No trophies handed out yet.", 14, UI.TEXT_DIM))
	parent.add_child(UI.scroll(flow))


static func _records(parent: Control, w: World) -> void:
	var c := UI.card(parent, "World records", true, UI.ACCENT)
	c.add_child(UI.table_header(REC_COLS))
	var list := UI.vbox(2)
	var keys: Array = w.records.keys()
	keys.sort()
	for i in keys.size():
		var r: Dictionary = w.records[keys[i]]
		var v := float(r.value)
		var vt := UI.money_text(int(v)) if String(keys[i]).contains("fee") else ("%.2f" % v if v != floor(v) else str(int(v)))
		list.add_child(UI.table_row([UI.label(String(keys[i]), 14, UI.TEXT, 600), UI.label(vt, 14, UI.WARN, 700), UI.label(String(r.holder), 14, UI.ACCENT2, 600),
			UI.label(String(r.team), 12, UI.TEXT_DIM), UI.label("S%d" % int(r.s), 12, UI.TEXT_FAINT)], REC_COLS, i))
	if keys.is_empty():
		list.add_child(UI.label("Records are set as matches are played.", 14, UI.TEXT_DIM))
	c.add_child(UI.scroll(list))


static func _hall(parent: Control, w: World) -> void:
	var c := UI.card(parent, "Hall of Fame", true, UI.WARN)
	c.add_child(UI.label("Retired greats, ranked by titles, longevity, peak and kills.", 12, UI.TEXT_FAINT))
	c.add_child(UI.table_header(HOF_COLS))
	var list := UI.vbox(2)
	for i in w.hall_of_fame.size():
		var h: Dictionary = w.hall_of_fame[i]
		var mine := bool(h.get("user", false))
		list.add_child(UI.table_row([UI.label(str(i + 1), 14, UI.TEXT_DIM, 600), UI.label(String(h.name) + ("  (you)" if mine else ""), 14, UI.ACCENT2 if mine else UI.TEXT, 600),
			UI.label(String(h.get("nation", "")), 12, UI.TEXT_DIM), UI.label(String(h.team), 12, UI.TEXT_DIM), UI.label("S%d" % int(h.s), 12, UI.TEXT_FAINT),
			UI.label(str(int(h.titles)), 14, UI.WARN if int(h.titles) > 0 else UI.TEXT_FAINT), UI.label(str(int(h.matches)), 13),
			UI.label("%.2f" % float(h.kd), 13), UI.rating_chip(int(h.peak)), UI.label(str(int(h.score)), 13, UI.GOOD, 600)], HOF_COLS, i, mine))
	if w.hall_of_fame.is_empty():
		list.add_child(UI.label("Nobody has been inducted yet: great players are added when they retire.", 14, UI.TEXT_DIM))
	c.add_child(UI.scroll(list))


## Popup shown the first time a hub opens after a season ends.
static func review_popup(parent: Control, w: World) -> void:
	if w.reviews.is_empty():
		return
	var r: Dictionary = w.reviews[w.reviews.size() - 1]
	var m := UI.modal(parent, 1100, UI.WARN)
	var overlay: Control = m[0]
	var box: VBoxContainer = m[1]
	box.add_child(UI.heading("Season %d in review" % int(r.s), 26))
	var body := UI.vbox(12)
	review_body(body, r)
	var sc := UI.scroll(body)
	sc.custom_minimum_size = Vector2(0, 560)
	box.add_child(sc)
	var row := UI.hbox(10)
	row.add_child(UI.label("Past reviews, champions, records and the Hall of Fame are on the History page.", 12, UI.TEXT_FAINT))
	row.add_child(UI.spacer())
	row.add_child(UI.button("Continue", func() -> void:
		w.review_pending = false
		overlay.queue_free(), 160, "PrimaryButton"))
	box.add_child(row)


## End-of-season awards ceremony: champions and individual awards revealed one
## by one (Player of the Year last), then on_done (the season review).
static func ceremony_popup(parent: Control, w: World, on_done: Callable) -> void:
	if w.reviews.is_empty():
		on_done.call()
		return
	var r: Dictionary = w.reviews[w.reviews.size() - 1]
	var items: Array = []
	for lg: Dictionary in r.get("leagues", []):
		if String(lg.get("playoffs", "")) != "":
			items.append({"title": "%s champions" % lg.name, "name": String(lg.playoffs), "team": "", "detail": "Won the league playoffs", "you": false})
	for c: Dictionary in r.get("cups", []):
		items.append({"title": String(c.name), "name": String(c.team), "team": "", "detail": "Cup winners", "you": false})
	items.append_array(r.get("ceremony", []))
	var wc: Dictionary = r.get("world_cup", {})
	if not wc.is_empty():
		items.append({"title": "World Cup", "name": String(wc.winner), "team": "", "detail": "World champions", "you": String(wc.get("you", "")) == "Champion"})
	if items.is_empty():
		on_done.call()
		return
	var m := UI.modal(parent, 760, UI.WARN)
	var overlay: Control = m[0]
	var box: VBoxContainer = m[1]
	var head := UI.hbox(10)
	head.add_child(UI.heading("Season %d awards" % int(r.s), 24))
	head.add_child(UI.spacer())
	var counter := UI.label("", 13, UI.TEXT_DIM)
	head.add_child(counter)
	box.add_child(head)
	var stage := UI.vbox(6)
	stage.custom_minimum_size = Vector2(0, 230)
	stage.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(stage)
	var row := UI.hbox(10)
	var skip := UI.button("Skip ceremony", func() -> void: pass, 170, "GhostButton")
	var next := UI.button("Next", func() -> void: pass, 170, "PrimaryButton")
	row.add_child(skip)
	row.add_child(UI.spacer())
	row.add_child(next)
	box.add_child(row)
	var idx := [0]
	var finish := func() -> void:
		overlay.queue_free()
		on_done.call()
	var reveal := func() -> void:
		for c in stage.get_children():
			c.queue_free()
		var it: Dictionary = items[idx[0]]
		var mine := bool(it.get("you", false))
		var col := UI.ACCENT2 if mine else UI.WARN
		var t := UI.label(String(it.title).to_upper(), 16, UI.TEXT_DIM, 700)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stage.add_child(t)
		var n := UI.label(String(it.name), 44, col, 700)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stage.add_child(n)
		if String(it.get("team", "")) != "":
			var tl := UI.label(String(it.team), 18, UI.TEXT, 600)
			tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			stage.add_child(tl)
		var d := UI.label(String(it.detail) + ("   (that's you!)" if mine else ""), 14, UI.TEXT_DIM)
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		stage.add_child(d)
		stage.modulate.a = 0.0
		var tw := stage.create_tween()
		tw.tween_property(stage, "modulate:a", 1.0, 0.45).set_trans(Tween.TRANS_SINE)
		counter.text = "%d / %d" % [idx[0] + 1, items.size()]
		next.text = "Finish" if idx[0] == items.size() - 1 else "Next"
		if Game.ui_sounds != null:
			Game.ui_sounds.play("confirm")
	next.pressed.connect(func() -> void:
		if idx[0] >= items.size() - 1:
			finish.call()
		else:
			idx[0] += 1
			reveal.call())
	skip.pressed.connect(func() -> void: finish.call())
	reveal.call()
