class_name ShopView
extends RefCounted
## My Player hub pages: Home (your place, properties, guests) and Shop
## (everything in Lifestyle.SHOP by category, plus investments).
## `done` is the hub's _act(err, ok_msg): it saves and rebuilds the page.

## Sprite that shows a shop item (assets/homes/props/<kind>.png).
const THUMB := {"studio": "studio_rig", "chef": "kitchen_line", "trophy_case": "trophy_cabinet", "home_gym": "home_gym", "hot_tub": "hot_tub",
	"arcade": "arcade", "aquarium": "aquarium", "piano": "piano", "dog": "dog", "cat": "cat", "car_hatchback": "car_hatchback",
	"car": "car_sports", "car_suv": "car_suv", "car_super": "car_super"}


static func _thumb(id: String, h: int) -> Control:
	var path := ""
	var info := Lifestyle.info(id)
	if String(info.get("cat", "")) == "home":
		path = "res://assets/homes/%s.png" % id
	elif THUMB.has(id):
		path = "res://assets/homes/props/%s.png" % String(THUMB[id])
	if path == "" or not ResourceLoader.exists(path):
		if String(info.get("cat", "")) == "skin":
			var sw := ColorRect.new()
			var tint: Color = info.get("tint", Color.WHITE)
			sw.color = Color(0.32 * tint.r, 0.32 * tint.g, 0.32 * tint.b).clamp()
			sw.custom_minimum_size = Vector2(h, h)
			return sw
		return null
	var tr := TextureRect.new()
	tr.texture = load(path)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = Vector2(h * 1.6, h) if String(info.get("cat", "")) == "home" else Vector2(h, h)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


static func _wrap(text: String, size: int = 12, color: Color = UI.TEXT_DIM) -> Label:
	var l := UI.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 60
	return l


static func go_home(tour: String = "") -> void:
	Game.home_tour = tour
	Game.save_player_career_soon()
	Game.goto(Game.HOME_SCENE)


# --- Home ----------------------------------------------------------------------

static func home_page(content: Control, w: World, done: Callable) -> void:
	var life := w.life()
	var page := UI.vbox(14)
	content.add_child(UI.scroll(page))
	var cur := Lifestyle.info(life.home)
	var top := UI.card(page, "Where you live", false, UI.WARN)
	var row := UI.hbox(16)
	top.add_child(row)
	var th := _thumb(life.home, 190)
	if th != null:
		row.add_child(th)
	var v := UI.vbox(6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	v.add_child(UI.label(String(cur.name), 24, UI.TEXT, 700))
	v.add_child(_wrap(String(cur.desc), 13))
	v.add_child(UI.label("Comfort %d: a night in your own bed clears %d fatigue (once a week)." % [life.comfort(), life.comfort()], 12, UI.TEXT_FAINT))
	var gs := life.guests_now()
	if not gs.is_empty():
		v.add_child(UI.label("Over at yours this week: " + ", ".join(gs.map(func(q: PlayerData) -> String: return q.player_name)), 12, UI.GOOD))
	var bits: Array = []
	for id in life.pets():
		bits.append("your " + String(id))
	for id in life.cars():
		bits.append(String(Lifestyle.info(String(id)).name).to_lower())
	if not bits.is_empty():
		v.add_child(UI.label("Waiting at home: " + ", ".join(bits), 12, UI.TEXT_DIM))
	var acts := UI.hbox(8)
	acts.add_child(UI.button("Go home", func() -> void: go_home(), 180, "PrimaryButton"))
	acts.add_child(UI.small_button("Throw a party  " + UI.money_text(Lifestyle.PARTY_COST), func() -> void:
		var r := life.party()
		done.call("" if r.begins_with("Party") else r, r), 0, "GhostButton"))
	var vb := UI.small_button(("Vacation  " + UI.money_text(Lifestyle.VACATION_COST)) if life.vacation_ready() else "Vacation: too soon", func() -> void:
		var r := life.vacation()
		done.call("" if r.begins_with("A week") else r, r), 0, "GhostButton")
	vb.disabled = not life.vacation_ready()
	acts.add_child(vb)
	v.add_child(acts)
	v.add_child(UI.label("At home: sleep, cook, practise on your PC, stream, work out, have friends over, pet the dog...", 11, UI.TEXT_FAINT))

	var pc := UI.card(page, "Your properties", false, UI.ACCENT2)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	for id: String in life.homes_owned():
		var a := Lifestyle.info(id)
		var card := PanelContainer.new()
		var here := id == life.home
		card.add_theme_stylebox_override("panel", UI._box(Color(UI.WARN, 0.08) if here else UI.PANEL_LO, 4, UI.WARN if here else UI.BORDER, 1, 10, 8))
		card.custom_minimum_size = Vector2(250, 0)
		var cv := UI.vbox(4)
		var t2 := _thumb(id, 90)
		if t2 != null:
			cv.add_child(t2)
		cv.add_child(UI.label(String(a.name), 14, UI.TEXT, 700))
		var idd := id
		var br := UI.hbox(6)
		if here:
			br.add_child(UI.label("You live here", 12, UI.WARN, 600))
		else:
			br.add_child(UI.small_button("Move in", func() -> void: done.call(life.move_in(idd), "You moved into your %s." % String(Lifestyle.info(idd).name).to_lower()), 90, "PrimaryButton"))
		if id != Lifestyle.STARTER:
			br.add_child(UI.small_button("Sell  " + UI.money_text(int(int(a.cost) * 0.6)), func() -> void: done.call(life.sell(idd), "Sold."), 0, "GhostButton"))
		cv.add_child(br)
		card.add_child(cv)
		flow.add_child(card)
	pc.add_child(flow)
	pc.add_child(UI.label("Buy more in the Shop (Property). You can tour any place before you buy it.", 11, UI.TEXT_FAINT))


# --- Shop ----------------------------------------------------------------------

static func shop_page(content: Control, w: World, state: Dictionary, done: Callable, rebuild: Callable) -> void:
	var life := w.life()
	var cat := String(state.get("cat", "home"))
	var tabs := UI.hbox(6)
	for c: String in Lifestyle.CATS + ["invest"]:
		var cc := c
		tabs.add_child(UI.small_button(String(Lifestyle.CAT_NAMES.get(c, "Investments")), func() -> void:
			state["cat"] = cc
			rebuild.call(), 0, "PrimaryButton" if c == cat else "GhostButton"))
	content.add_child(tabs)
	var sum := UI.hbox(20)
	sum.add_child(UI.stat_chip("Wallet", UI.money_text(w.wallet), UI.GOOD))
	sum.add_child(UI.stat_chip("Upkeep", UI.money_text(life.upkeep()) + " / wk", UI.BAD if life.upkeep() > 0 else UI.TEXT))
	if not life.investments.is_empty():
		sum.add_child(UI.stat_chip("Invested", UI.money_text(life.invested_value()), UI.ACCENT2))
		sum.add_child(UI.stat_chip("Dividends", UI.money_text(life.weekly_dividends()) + " / wk", UI.GOOD))
	content.add_child(sum)
	var page := UI.vbox(12)
	content.add_child(UI.scroll(page))
	if cat == "invest":
		_invest(page, w, done)
		return
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	page.add_child(flow)
	for id: String in Lifestyle.SHOP:
		var a: Dictionary = Lifestyle.SHOP[id]
		if String(a.cat) != cat or bool(a.get("hidden", false)):
			continue
		flow.add_child(_item_card(w, id, a, done))
	var note := {"home": "Moving up a tier moves you straight in. Upkeep is weekly. Sell back for 60%.",
		"extra": "Extras show up in your home if it has space for them (gym, piano and hot tub need a house or bigger).",
		"skin": "Equip a finish in your wardrobe at home. It colours every gun you hold in matches.",
		"staff": "Staff charge a signing fee, then a weekly wage. Let them go any time.",
		"car": "Cars park in your garage (houses, the villa and the duplex's car lift)."}
	if note.has(cat):
		page.add_child(UI.label(String(note[cat]), 11, UI.TEXT_FAINT))


static func _item_card(w: World, id: String, a: Dictionary, done: Callable) -> Control:
	var life := w.life()
	var own := w.assets.has(id)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(300 if String(a.cat) == "home" else 260, 0)
	card.add_theme_stylebox_override("panel", UI._box(Color(UI.WARN, 0.07) if own else UI.PANEL_LO, 4, UI.WARN if own else UI.BORDER, 1, 10, 8))
	var v := UI.vbox(4)
	card.add_child(v)
	var th := _thumb(id, 120 if String(a.cat) == "home" else 72)
	if th != null:
		v.add_child(th)
	var tr := UI.hbox(6)
	tr.add_child(UI.label(String(a.name), 14, UI.TEXT, 700))
	tr.add_child(UI.spacer())
	tr.add_child(UI.label(UI.money_text(int(a.cost)), 13, UI.TEXT_FAINT if own else UI.GOOD, 600))
	v.add_child(tr)
	var up := int(a.get("upkeep", 0))
	v.add_child(_wrap(String(a.desc) + ("  Upkeep %s/wk." % UI.money_text(up) if up > 0 else "")))
	var br := UI.hbox(6)
	var cat := String(a.cat)
	if own:
		if cat == "home":
			br.add_child(UI.label("You live here" if life.home == id else "Owned", 12, UI.WARN, 600))
			if life.home != id:
				br.add_child(UI.small_button("Move in", func() -> void: done.call(life.move_in(id), "Moved in."), 80, "PrimaryButton"))
		elif cat == "skin":
			var on := life.skin == id
			br.add_child(UI.small_button("Equipped" if on else "Equip", func() -> void:
				life.skin = "" if on else id
				done.call("", "Finish removed." if on else "Equipped. Your guns will wear it in matches."), 90, "PrimaryButton" if on else "GhostButton"))
		elif cat == "staff":
			br.add_child(UI.label("Hired", 12, UI.WARN, 600))
			br.add_child(UI.small_button("Let go", func() -> void: done.call(life.sell(id), "You let them go."), 80, "GhostButton"))
		else:
			br.add_child(UI.label("Owned", 12, UI.WARN, 600))
		if bool(a.resell):
			br.add_child(UI.small_button("Sell (60%)", func() -> void: done.call(life.sell(id), "Sold."), 90, "GhostButton"))
	else:
		var b := UI.small_button("Hire" if cat == "staff" else "Buy", func() -> void: done.call(life.buy(id), "%s is yours." % String(a.name)), 80, "PrimaryButton")
		b.disabled = w.wallet < int(a.cost)
		br.add_child(b)
	if cat == "home":
		br.add_child(UI.small_button("Tour" if not own else "Visit", func() -> void: _visit(w, id), 70, "GhostButton"))
	v.add_child(br)
	return card


## Tour a place (yours or not); your own current home opens normally.
static func _visit(w: World, id: String) -> void:
	go_home("" if w.life().home == id else id)


static func _invest(page: Control, w: World, done: Callable) -> void:
	var life := w.life()
	page.add_child(_wrap("Put money to work. Values move every week; some pay a weekly share. You can lose money.", 13))
	for id: String in Lifestyle.INVEST:
		var d: Dictionary = Lifestyle.INVEST[id]
		var card := UI.card(page, String(d.name), false, UI.ACCENT2)
		card.add_child(_wrap(String(d.desc)))
		var r := UI.hbox(10)
		var mine: Dictionary = life.investments.get(id, {})
		if not mine.is_empty():
			var val := int(float(mine.value))
			var pl := val - int(mine.paid)
			r.add_child(UI.stat_chip("Value", UI.money_text(val), UI.TEXT))
			r.add_child(UI.stat_chip("Profit", ("+" if pl >= 0 else "") + UI.money_text(pl), UI.GOOD if pl >= 0 else UI.BAD))
		r.add_child(UI.spacer())
		var mn := int(d.min)
		for mult in [1, 2, 5]:
			var amt := mn * int(mult)
			var idd := id
			var b := UI.small_button("Invest " + UI.money_text(amt), func() -> void: done.call(life.invest(idd, amt), "Invested %s." % UI.money_text(amt)), 0, "PrimaryButton" if mult == 1 else "GhostButton")
			b.disabled = w.wallet < amt
			r.add_child(b)
		if not mine.is_empty():
			var idc := id
			r.add_child(UI.small_button("Cash out", func() -> void:
				var got := life.cash_out(idc)
				done.call("", "Cashed out %s." % UI.money_text(got)), 0, "GhostButton"))
		card.add_child(r)
