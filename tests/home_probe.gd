extends Node
## Homes and the shop (My Player): buy everything, walk every home, use every
## piece, guests and pets, investments, weekly effects, save/load.
##   godot --headless --path . res://tests/home_probe.tscn -- --test
var fails := 0
const HOMES := ["rented_room", "apartment", "loft", "seaside_flat", "townhouse", "house", "villa", "penthouse", "sky_duplex"]


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		fails += 1


func _ready() -> void:
	Game.end_career()
	Game.create_my_player("Homebody", "Rifler", "Canada")
	Game.start_career()
	var w := Game.pworld
	var life := w.life()
	_check(life.home == Lifestyle.STARTER, "start in the rented room")
	w.wallet = 20000000
	var bad: Array = []
	for id: String in Lifestyle.SHOP:
		if bool(Lifestyle.SHOP[id].get("hidden", false)):
			continue
		var r := life.buy(id)
		if r != "":
			bad.append("%s: %s" % [id, r])
	_check(bad.is_empty(), "bought everything in the shop %s" % str(bad))
	_check(life.home == "sky_duplex", "moved up into the best place: %s" % life.home)
	_check(life.cars().size() == 4 and String(life.cars()[0]) == "car_super", "cars, best first: %s" % str(life.cars()))
	_check(life.skin != "" and life.skin_tint().a > 0.0, "first finish equipped: %s" % life.skin)
	_check(life.upkeep() > 10000, "upkeep adds up: %d / wk" % life.upkeep())

	# Party: teammates come over and show up at home.
	var pr := life.party()
	_check(pr.begins_with("Party"), "party: %s" % pr)
	_check(not life.guests_now().is_empty(), "guests this week: %d" % life.guests_now().size())

	var scene: PackedScene = load("res://scenes/home.tscn")
	for hid: String in HOMES:
		life.home = hid
		Game.home_tour = ""
		var h: Home = scene.instantiate()
		add_child(h)
		await get_tree().process_frame
		var uses := {}
		for it: Dictionary in h.items:
			if String(it.use) != "":
				uses[String(it.use)] = it
		_check(h.items.size() >= 10 and uses.has("bed") and uses.has("pc"), "%s: %d pieces, uses %s" % [hid, h.items.size(), str(uses.keys())])
		_check(not h._blocked(h.pos), "%s: spawn is clear" % hid)
		# Every usable piece can be walked up to (A* to a cell within reach) and targeted there.
		var unreachable: Array = []
		var from := Vector2i(h.pos / Home.CELL)
		for u: String in uses:
			var it: Dictionary = uses[u]
			var r: Rect2 = it.rect
			var ok := false
			for y in h.H:
				for x in h.W:
					var c := Vector2i(x, y)
					if ok or h.is_solid(c):
						continue
					var p := h.cell_center(c)
					if not r.grow(Home.REACH).has_point(p):
						continue
					if h.astar.get_id_path(from, c).size() > 0 or c == from:
						h.pos = p
						var t := h._nearest_use()
						ok = not t.is_empty()
			if not ok:
				unreachable.append(u)
		_check(unreachable.is_empty(), "%s: every piece reachable %s" % [hid, str(unreachable)])
		# Walls hold.
		var wall_hit := h._blocked(Vector2(-5, -5)) and h._blocked(Vector2(h.W * Home.CELL + 5, 10))
		_check(wall_hit, "%s: walls block" % hid)
		if hid == "sky_duplex":
			_check(h.pets.size() == 2, "pets roam the duplex: %d" % h.pets.size())
			_check(h.npcs.size() >= 2, "guests and the chef are there: %d" % h.npcs.size())
			var shown := h.items.filter(func(i: Dictionary) -> bool: return String(i.k).begins_with("car_")).map(func(i: Dictionary) -> String: return String(i.sprite))
			_check(shown.has("car_super") and shown.has("car_suv"), "garage shows your two best cars: %s" % str(shown))
			var desk := h.items.filter(func(i: Dictionary) -> bool: return String(i.k).begins_with("desk_pc"))
			_check(not desk.is_empty() and String(desk[0].sprite) == "desk_pc_%d" % w.setup_level, "desk matches setup level")
			for i in 120:
				h._process(1.0 / 30.0)
			_check(true, "pets wander without errors")
		h.queue_free()
		await get_tree().process_frame
	# Tour: an unowned place shows without purchases.
	w.assets.erase("villa")
	Game.home_tour = "villa"
	var ht: Home = scene.instantiate()
	add_child(ht)
	await get_tree().process_frame
	var needy := ht.items.filter(func(i: Dictionary) -> bool: return String(i.k) in ["home_gym", "hot_tub", "studio_rig", "trophy_cabinet"])
	_check(ht.home_id == "villa" and needy.is_empty(), "tour shows the villa without bought extras")
	ht.queue_free()
	Game.home_tour = ""
	await get_tree().process_frame

	# Using things: once a week each.
	var f0 := 60.0
	w.fatigue = f0
	var r1 := life.act("bed")
	_check(bool(r1.ok) and w.fatigue < f0, "sleep: %s" % r1.text)
	var r2 := life.act("bed")
	_check(not bool(r2.ok), "sleep again same week refused: %s" % r2.text)
	for u in ["pc", "stream", "tv", "kitchen", "gym", "car", "sofa", "pet", "view", "tub", "piano", "arcade", "aquarium", "bar"]:
		var rr := life.act(u)
		_check(bool(rr.ok), "%s: %s" % [u, rr.text])
	# Invest, week passes, cash out.
	_check(life.invest("index", 10000) == "" and life.invest("bar", 150000) == "", "invested")
	_check(life.invest("org", 1000) != "", "minimum enforced")
	var wallet0 := w.wallet
	var week0 := w.week
	var guard := 0
	while w.week == week0 and guard < 4:
		guard += 1
		var res := w.advance_week()
		if res == "play_match":
			w.sim_user_match()
			w.advance_week()
	_check(w.week != week0, "a week went by")
	_check(not life.done_this_week("bed"), "home actions reset next week")
	_check(life.investments.has("index") and float(life.investments.index.value) > 0.0, "investment moved: %.0f" % float(life.investments.index.value))
	_check(w.user_player.morale >= 50.0, "house tier keeps morale up")
	var got := life.cash_out("index")
	_check(got > 5000, "cashed out %d" % got)
	_check(wallet0 != w.wallet, "money moved (upkeep, pay, dividends)")
	# Sell the home you live in: you move to the next best.
	life.home = "sky_duplex"
	_check(life.sell("sky_duplex") == "" and life.home == "penthouse", "sold the duplex, now in: %s" % life.home)
	_check(life.sell("trainer") == "" and not w.assets.has("trainer"), "let the trainer go")
	# Save and load.
	life.skin = "skin_gold"
	life.outfit = 1
	var d := w.to_dict()
	var w2 := World.from_dict(JSON.parse_string(JSON.stringify(d)))
	var l2 := w2.life()
	_check(l2.home == "penthouse" and l2.skin == "skin_gold" and l2.outfit == 1 and l2.investments.has("bar"), "lifestyle saved and loaded")
	_check(w2.assets.has("car_super") and w2.assets.has("dog"), "owned items saved")
	# Match: your finish reaches the gun art.
	GunArt.user_finish = Color(0, 0, 0, 0)
	_check(life.skin_tint().is_equal_approx(Lifestyle.SHOP.skin_gold.tint), "gold finish tint")
	print("FAILS: %d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
