class_name Lifestyle
extends RefCounted
## My Player lifestyle: the shop (homes, cars, home extras, pets, style, weapon
## skins, personal staff), the home you live in and walk around (scenes/home),
## what you do there, investments and experiences (house parties, vacations).
## Owned shop items live in World.assets (ids, as before); the rest is here,
## saved under "life".

const STARTER := "rented_room"
const TIER_RANK := {"rental": 0, "apartment": 1, "house": 2, "penthouse": 3}

## Everything you can buy. cat: home / car / extra / pet / style / skin / staff.
## Homes: tier (effects), comfort (how much a night's sleep restores).
## Cars: sprite (props kind shown in your garage). Skins: tint (gun colour).
## Staff: cost is the signing fee, upkeep the weekly wage; let go any time.
const SHOP := {
	"rented_room": {"name": "Rented room", "cat": "home", "cost": 0, "upkeep": 0, "resell": false, "tier": "rental", "comfort": 6, "hidden": true,
		"desc": "A box room with a mattress on the floor. It's a start."},
	"apartment": {"name": "City apartment", "cat": "home", "cost": 25000, "upkeep": 300, "resell": true, "tier": "apartment", "comfort": 10,
		"desc": "One bedroom, open-plan living. Morale +1 a week."},
	"loft": {"name": "Industrial loft", "cat": "home", "cost": 45000, "upkeep": 450, "resell": true, "tier": "apartment", "comfort": 11,
		"desc": "Brick, concrete and room for an arcade cabinet. Morale +1 a week."},
	"seaside_flat": {"name": "Seaside flat", "cat": "home", "cost": 70000, "upkeep": 550, "resell": true, "tier": "apartment", "comfort": 12,
		"desc": "A balcony over the water and a telescope. Morale +1 a week."},
	"townhouse": {"name": "City townhouse", "cat": "home", "cost": 180000, "upkeep": 650, "resell": true, "tier": "house", "comfort": 13,
		"desc": "Long, narrow and full of character, with a back garden. Morale never drops below 50."},
	"house": {"name": "Family house", "cat": "home", "cost": 250000, "upkeep": 800, "resell": true, "tier": "house", "comfort": 14,
		"desc": "Garage, garden and a pool. Morale never drops below 50."},
	"villa": {"name": "Modern villa", "cat": "home", "cost": 600000, "upkeep": 1600, "resell": true, "tier": "house", "comfort": 16, "fame": 20000,
		"desc": "Two-car garage, pool, room for a gym. +20k followers; morale never drops below 50."},
	"penthouse": {"name": "Skyline penthouse", "cat": "home", "cost": 1000000, "upkeep": 3000, "resell": true, "tier": "penthouse", "comfort": 17, "fame": 50000,
		"desc": "Glass walls and a terrace over the city. +50k followers, morale +1.5 a week."},
	"sky_duplex": {"name": "Sky duplex", "cat": "home", "cost": 2500000, "upkeep": 6000, "resell": true, "tier": "penthouse", "comfort": 19, "fame": 120000,
		"desc": "Car lift, rooftop pool, the lot. +120k followers, morale +1.5 a week."},

	"car_hatchback": {"name": "Hatchback", "cat": "car", "cost": 18000, "upkeep": 80, "resell": true, "sprite": "car_hatchback", "fame": 500,
		"desc": "Gets you to practice. +500 followers."},
	"car": {"name": "Sports car", "cat": "car", "cost": 60000, "upkeep": 200, "resell": true, "sprite": "car_sports", "fame": 3000,
		"desc": "Loud and red. +3k followers."},
	"car_suv": {"name": "Electric SUV", "cat": "car", "cost": 90000, "upkeep": 150, "resell": true, "sprite": "car_suv", "fame": 2000,
		"desc": "Quiet, roomy, glass roof. +2k followers."},
	"car_super": {"name": "Supercar", "cat": "car", "cost": 300000, "upkeep": 900, "resell": true, "sprite": "car_super", "fame": 25000,
		"desc": "Turns every head in the car park. +25k followers."},

	"studio": {"name": "Streaming studio", "cat": "extra", "cost": 40000, "upkeep": 150, "resell": true,
		"desc": "Streaming pays 50% more. Lights and a camera next to your desk."},
	"chef": {"name": "Personal chef", "cat": "extra", "cost": 5000, "upkeep": 600, "resell": false,
		"desc": "Form +0.3 a week; fatigue recovers faster; better meals at home."},
	"trophy_case": {"name": "Trophy cabinet", "cat": "extra", "cost": 8000, "upkeep": 0, "resell": false,
		"desc": "Your cups, medals and titles on show at home."},
	"home_gym": {"name": "Home gym", "cat": "extra", "cost": 30000, "upkeep": 150, "resell": true,
		"desc": "Fatigue -2 a week; a weekly workout at home. Needs a house or bigger to show."},
	"hot_tub": {"name": "Hot tub", "cat": "extra", "cost": 35000, "upkeep": 250, "resell": true,
		"desc": "Fatigue -3 a week; soak once a week for more. Needs outdoor space to show."},
	"arcade": {"name": "Arcade cabinet", "cat": "extra", "cost": 12000, "upkeep": 20, "resell": true,
		"desc": "Morale +0.5 a week; a few rounds sharpens your reactions."},
	"aquarium": {"name": "Aquarium", "cat": "extra", "cost": 15000, "upkeep": 60, "resell": true,
		"desc": "Morale +0.5 a week. Strangely calming."},
	"piano": {"name": "Grand piano", "cat": "extra", "cost": 40000, "upkeep": 40, "resell": true,
		"desc": "Play to unwind once a week. Needs a big room to show."},

	"dog": {"name": "Dog", "cat": "pet", "cost": 2500, "upkeep": 80, "resell": false,
		"desc": "A golden retriever who's always pleased to see you. Morale +1 a week."},
	"cat": {"name": "Cat", "cat": "pet", "cost": 1500, "upkeep": 50, "resell": false,
		"desc": "Ginger, aloof, occasionally affectionate. Morale +0.7 a week."},

	"watch": {"name": "Luxury watch", "cat": "style", "cost": 15000, "upkeep": 0, "resell": true, "fame": 2000,
		"desc": "Wrist candy for the post-match interview. +2k followers."},
	"chain": {"name": "Gold chain", "cat": "style", "cost": 40000, "upkeep": 0, "resell": true, "fame": 5000,
		"desc": "Heavy. +5k followers."},
	"designer": {"name": "Designer wardrobe", "cat": "style", "cost": 25000, "upkeep": 150, "resell": false, "fame": 1000,
		"desc": "Brands like a sharp dresser: endorsements pay 10% more. +1k followers."},
	"foundation": {"name": "Charity foundation", "cat": "style", "cost": 100000, "upkeep": 0, "resell": false, "fame": 15000,
		"desc": "+15k followers, +10 coach trust."},

	"skin_crimson": {"name": "Crimson weapon finish", "cat": "skin", "cost": 6000, "upkeep": 0, "resell": false, "tint": Color(1.35, 0.55, 0.5),
		"desc": "A deep red finish on every gun you hold. Equip it in your wardrobe."},
	"skin_arctic": {"name": "Arctic weapon finish", "cat": "skin", "cost": 6000, "upkeep": 0, "resell": false, "tint": Color(0.8, 1.0, 1.35),
		"desc": "Ice-white and pale blue."},
	"skin_jungle": {"name": "Jungle weapon finish", "cat": "skin", "cost": 8000, "upkeep": 0, "resell": false, "tint": Color(0.75, 1.1, 0.6),
		"desc": "Olive and moss green."},
	"skin_neon": {"name": "Neon weapon finish", "cat": "skin", "cost": 18000, "upkeep": 0, "resell": false, "tint": Color(1.25, 0.6, 1.55),
		"desc": "Purple and pink. Loud."},
	"skin_gold": {"name": "Gold weapon finish", "cat": "skin", "cost": 100000, "upkeep": 0, "resell": false, "tint": Color(1.75, 1.3, 0.45), "fame": 10000,
		"desc": "Solid gold, apparently. +10k followers."},

	"trainer": {"name": "Personal trainer", "cat": "staff", "cost": 2000, "upkeep": 1200, "resell": false,
		"desc": "Training gains +15%."},
	"psych": {"name": "Sports psychologist", "cat": "staff", "cost": 2000, "upkeep": 900, "resell": false,
		"desc": "Morale never drops below 40, and +0.5 a week."},
	"physio_p": {"name": "Personal physio", "cat": "staff", "cost": 2000, "upkeep": 1000, "resell": false,
		"desc": "25% fewer illnesses and injuries; fatigue -2 a week."},
}

const CATS := ["home", "car", "extra", "pet", "style", "skin", "staff"]
const CAT_NAMES := {"home": "Property", "car": "Cars", "extra": "Home extras", "pet": "Pets", "style": "Style & image",
	"skin": "Weapon finishes", "staff": "Personal staff"}

## Money you can put somewhere. Each week the value moves by drift +- vol
## (normal), and some pay a weekly share of their value.
const INVEST := {
	"index": {"name": "Index fund", "min": 10000, "drift": 0.0016, "vol": 0.015, "yield": 0.0, "desc": "Slow and steady. Rarely loses much."},
	"crypto": {"name": "Crypto", "min": 5000, "drift": 0.002, "vol": 0.13, "yield": 0.0, "desc": "Wild swings: it can double or halve in a month."},
	"bar": {"name": "Esports bar stake", "min": 150000, "drift": 0.0, "vol": 0.03, "yield": 0.004, "desc": "Pays a weekly share, more when you're famous."},
	"drink": {"name": "Energy drink brand", "min": 300000, "drift": 0.0012, "vol": 0.05, "yield": 0.0025, "desc": "Your face on the can. Grows with your fame."},
	"org": {"name": "Esports org stake", "min": 750000, "drift": 0.001, "vol": 0.04, "yield": 0.002, "desc": "A slice of an organisation. Steady payouts."},
}

const PARTY_COST := 6000
const VACATION_COST := 15000

var _wref: WeakRef
var w: World:
	get:
		return _wref.get_ref() as World if _wref != null else null

var home := STARTER ## The home you live in (a home id in SHOP).
var used := {} ## Home action -> week stamp it was last done (most are once a week).
var investments := {} ## id -> {value: float, paid: int}
var skin := "" ## Equipped weapon finish (shop id) or "".
var outfit := 0 ## Casual look at home.
var guests: Array = [] ## uids of people at your place this week.
var guests_week := -1
var last_vacation := -100 ## Absolute week of your last vacation.


func _init(world: World) -> void:
	_wref = weakref(world)


func stamp() -> int:
	return w.season * 100 + w.week


func abs_week() -> int:
	return w.season * World.SEASON_WEEKS + w.week


func owns(id: String) -> bool:
	return id == STARTER or w.assets.has(id)


static func info(id: String) -> Dictionary:
	return SHOP.get(id, {})


func tier_of(id: String) -> String:
	return String(info(id).get("tier", ""))


func owns_tier(t: String) -> bool:
	for id in w.assets:
		if tier_of(String(id)) == t:
			return true
	return false


func homes_owned() -> Array:
	var out: Array = [STARTER]
	for id in SHOP:
		if String(SHOP[id].cat) == "home" and w.assets.has(id):
			out.append(id)
	return out


func comfort() -> int:
	return int(info(home).get("comfort", 6))


## Cars you own, best first (the garage fills slot 0, 1, ...).
func cars() -> Array:
	var out: Array = []
	for id in SHOP:
		if String(SHOP[id].cat) == "car" and w.assets.has(id):
			out.append(id)
	out.sort_custom(func(a: String, b: String) -> bool: return int(SHOP[a].cost) > int(SHOP[b].cost))
	return out


func pets() -> Array:
	var out: Array = []
	for id in ["dog", "cat"]:
		if w.assets.has(id):
			out.append(id)
	return out


func skin_tint() -> Color:
	if skin == "" or not w.assets.has(skin):
		return Color(0, 0, 0, 0)
	return info(skin).get("tint", Color(0, 0, 0, 0))


# --- Shop ----------------------------------------------------------------------

func buy(id: String) -> String:
	if not SHOP.has(id) or bool(info(id).get("hidden", false)):
		return "Not for sale"
	if w.assets.has(id):
		return "Already yours"
	var a := info(id)
	if w.wallet < int(a.cost):
		return "Need $%s" % World._fmt(int(a.cost))
	w.wallet -= int(a.cost)
	w.assets.append(id)
	if int(a.get("fame", 0)) > 0:
		w._gain_fame(int(a.fame))
	match id:
		"foundation":
			w._trust(10.0)
	var cat := String(a.cat)
	if cat == "home" and TIER_RANK[tier_of(id)] >= TIER_RANK.get(tier_of(home), 0):
		home = id # Moving up: you move straight in.
	if cat == "skin" and skin == "":
		skin = id
	if cat == "staff":
		w._news("STAFF: you hired a %s." % String(a.name).to_lower())
		return ""
	w._news("LIFESTYLE: you bought %s." % _a_name(String(a.name)))
	var me := w.user_player.player_name
	var line := ""
	match cat:
		"home":
			line = "%s just moved into a %s. Living the dream" % [me, String(a.name).to_lower()]
		"car":
			line = "Spotted %s in a new %s outside the gaming house" % [me, String(a.name).to_lower()]
		"pet":
			line = "%s got a %s!! need pics" % [me, id]
		"skin":
			line = "%s rocking the %s now" % [me, String(a.name).to_lower()]
		_:
			line = "%s just got a %s. Must be nice" % [me, String(a.name).to_lower()]
	w._post(w._fan_handle(), line, "fan", 1.3 if int(a.cost) >= 50000 else 0.9)
	return ""


static func _a_name(n: String) -> String:
	var l := n.to_lower()
	return ("an " if "aeiou".contains(l.substr(0, 1)) else "a ") + l


## Sell it back (60%), or let staff go (nothing back).
func sell(id: String) -> String:
	if not w.assets.has(id):
		return "You don't own that"
	var a := info(id)
	var staff := String(a.cat) == "staff"
	if not staff and not bool(a.resell):
		return "Can't sell that"
	w.assets.erase(id)
	if not staff:
		w.wallet += int(int(a.cost) * 0.6)
	if id == home:
		home = _best_home()
	if id == skin:
		skin = ""
	if staff:
		w._news("STAFF: you let your %s go." % String(a.name).to_lower())
	return ""


func _best_home() -> String:
	var best := STARTER
	for id in homes_owned():
		if int(info(id).cost) > int(info(best).cost):
			best = id
	return best


func move_in(id: String) -> String:
	if not owns(id) or String(info(id).get("cat", "")) != "home":
		return "You don't own that place"
	home = id
	return ""


func upkeep() -> int:
	var n := 0
	for id in w.assets:
		n += int(info(String(id)).get("upkeep", 0))
	return n


# --- Weekly --------------------------------------------------------------------

## After pay, from World._lifestyle_week: what your homes, staff, pets and
## extras do for you, and your investments moving.
func weekly() -> void:
	var p := w.user_player
	if owns_tier("apartment"):
		p.morale = minf(100.0, p.morale + 1.0)
	if owns_tier("house"):
		p.morale = maxf(p.morale, 50.0)
	if owns_tier("penthouse"):
		p.morale = minf(100.0, p.morale + 1.5)
	if owns("chef"):
		w.fatigue -= 3.0
		p.form += 0.3
	var mood := 0.0
	mood += 1.0 if owns("dog") else 0.0
	mood += 0.7 if owns("cat") else 0.0
	mood += 0.5 if owns("arcade") else 0.0
	mood += 0.5 if owns("aquarium") else 0.0
	if owns("psych"):
		mood += 0.5
	p.morale = minf(100.0, p.morale + mood)
	if owns("psych"):
		p.morale = maxf(p.morale, 40.0)
	if owns("home_gym"):
		w.fatigue -= 2.0
	if owns("hot_tub"):
		w.fatigue -= 3.0
	if owns("physio_p"):
		w.fatigue -= 2.0
	_invest_week()


func _invest_week() -> void:
	for id in investments.keys():
		var v: Dictionary = investments[id]
		var d: Dictionary = INVEST[id]
		var change := w.rng.randfn(float(d.drift), float(d.vol))
		v.value = maxf(0.0, float(v.value) * (1.0 + clampf(change, -0.6, 1.0)))
		var y := float(d.yield)
		if id == "bar" or id == "drink":
			y *= 1.0 + clampf(float(w.fame) / 500000.0, 0.0, 1.5)
		var div := int(float(v.value) * y)
		if div > 0:
			w.wallet += div
		if change < -0.25:
			w._news("MARKETS: your %s just lost %d%% in a week." % [String(d.name).to_lower(), int(-change * 100.0)])
		elif change > 0.3:
			w._news("MARKETS: your %s jumped %d%% this week." % [String(d.name).to_lower(), int(change * 100.0)])


func invest(id: String, amount: int) -> String:
	if not INVEST.has(id):
		return "Unknown investment"
	if amount < int(INVEST[id].min) and not investments.has(id):
		return "The minimum is $%s" % World._fmt(int(INVEST[id].min))
	if w.wallet < amount:
		return "Need $%s" % World._fmt(amount)
	w.wallet -= amount
	var v: Dictionary = investments.get(id, {"value": 0.0, "paid": 0})
	v.value = float(v.value) + amount
	v.paid = int(v.paid) + amount
	investments[id] = v
	return ""


func cash_out(id: String) -> int:
	if not investments.has(id):
		return 0
	var got := int(float(investments[id].value))
	w.wallet += got
	investments.erase(id)
	w._news("MARKETS: you cashed out of your %s for $%s." % [String(INVEST[id].name).to_lower(), World._fmt(got)])
	return got


func invested_value() -> int:
	var n := 0.0
	for id in investments:
		n += float(investments[id].value)
	return int(n)


func weekly_dividends() -> int:
	var n := 0
	for id in investments:
		var y := float(INVEST[id].yield)
		if id == "bar" or id == "drink":
			y *= 1.0 + clampf(float(w.fame) / 500000.0, 0.0, 1.5)
		n += int(float(investments[id].value) * y)
	return n


# --- At home -------------------------------------------------------------------

func done_this_week(key: String) -> bool:
	return int(used.get(key, -1)) == stamp()


func _mark(key: String) -> void:
	used[key] = stamp()


## People over at your place this week (from a party or an invite).
func guests_now() -> Array[PlayerData]:
	var out: Array[PlayerData] = []
	if guests_week != stamp():
		return out
	var t := w.user_team()
	if t == null:
		return out
	for p: PlayerData in t.roster:
		if guests.has(p.uid) and not p.is_user:
			out.append(p)
	return out


## Teammates who'd come round: friends first.
func invitable() -> Array[PlayerData]:
	var out: Array[PlayerData] = []
	var t := w.user_team()
	if t == null or w.teamless:
		return out
	for p: PlayerData in t.roster:
		if not p.is_user and w.relation(p.uid) > -20.0:
			out.append(p)
	out.sort_custom(func(a: PlayerData, b: PlayerData) -> bool: return w.relation(a.uid) > w.relation(b.uid))
	return out


## Do something at home. Returns {ok, text}. Most things count once a week.
func act(action: String) -> Dictionary:
	var p := w.user_player
	if p == null:
		return {"ok": false, "text": ""}
	var weekly_only := action not in ["trophies", "wardrobe"]
	if weekly_only and done_this_week(action):
		return {"ok": false, "text": AGAIN.get(action, "You've done that this week.")}
	var t := ""
	match action:
		"bed":
			var c := comfort()
			w.fatigue = maxf(0.0, w.fatigue - c)
			p.morale = minf(100.0, p.morale + c / 6.0)
			t = "You sleep in properly for once. Fatigue -%d." % c
		"pc":
			var keys := ["aim", "reaction", "recoil", "preaim", "flick"]
			var key: String = keys[w.rng.randi() % keys.size()]
			var d := Progression.train(p, key, w.rng, 0.3 * (1.0 + 0.12 * w.setup_level), 0.15)
			w.fatigue = minf(100.0, w.fatigue + 2.0)
			t = "An hour on an aim map. %s %+.2f." % [PlayerData.STAT_NAMES.get(key, key), d]
		"stream":
			var pay := int(maxf(300.0, float(w.fame) * 0.012) * (1.5 if owns("studio") else 1.0))
			var fans := int(30 + w.fame * 0.004)
			w.wallet += pay
			w._gain_fame(fans)
			w.fatigue = minf(100.0, w.fatigue + 4.0)
			t = "You go live for a few hours: $%s in subs and donations, +%s followers." % [World._fmt(pay), World.fame_text(fans)]
		"tv":
			var d2 := Progression.train(p, "decision" if w.rng.randf() < 0.5 else "positioning", w.rng, 0.25, 0.1)
			w.fatigue = maxf(0.0, w.fatigue - 2.0)
			t = "You put on some pro demos and take notes. Game sense %+.2f, fatigue -2." % d2
		"kitchen":
			var chef := owns("chef")
			p.form += 0.4 if chef else 0.2
			if chef:
				w.fatigue = maxf(0.0, w.fatigue - 2.0)
			t = "Your chef plates up something ridiculous. Form +0.4." if chef else "You cook a proper meal for once. Form +0.2."
		"gym":
			var d3 := Progression.train(p, "movement", w.rng, 0.35, 0.15)
			w.fatigue = minf(100.0, w.fatigue + 3.0)
			t = "Leg day. Movement %+.2f, fatigue +3." % d3
		"car":
			var cs := cars()
			if cs.is_empty():
				return {"ok": false, "text": "You don't have a car yet."}
			p.morale = minf(100.0, p.morale + 3.0)
			var top: Dictionary = info(String(cs[0]))
			t = "You take the %s out for a spin. Morale +3." % String(top.name).to_lower()
			if int(top.cost) >= 60000:
				var f := int(200 + int(top.cost) / 400)
				w._gain_fame(f)
				w._post(w._fan_handle(), "Just saw %s's %s on the highway!!" % [p.player_name, String(top.name).to_lower()], "fan", 1.0)
				t += " Someone filmed it: +%s followers." % World.fame_text(f)
		"sofa":
			var gs := guests_now()
			if gs.is_empty():
				p.morale = minf(100.0, p.morale + 1.0)
				w.fatigue = maxf(0.0, w.fatigue - 1.0)
				t = "You put your feet up for a while. Morale +1."
			else:
				for g: PlayerData in gs:
					w._relate(g.uid, 4.0)
				p.morale = minf(100.0, p.morale + 2.0)
				t = "You hang out with %s. You get on a bit better (relationship +4)." % _names(gs)
		"pet":
			var ps := pets()
			if ps.is_empty():
				return {"ok": false, "text": ""}
			p.morale = minf(100.0, p.morale + 2.0)
			t = "Your %s is delighted. Morale +2." % ("dog" if ps.has("dog") else "cat")
		"view":
			p.morale = minf(100.0, p.morale + 1.0)
			t = "You look out over everything for a while. Morale +1."
		"tub":
			w.fatigue = maxf(0.0, w.fatigue - 4.0)
			t = "Twenty minutes in the hot tub. Fatigue -4."
		"piano":
			p.morale = minf(100.0, p.morale + 2.0)
			t = "You plink out something that's nearly a song. Morale +2."
		"arcade":
			var d4 := Progression.train(p, "reaction", w.rng, 0.15, 0.08)
			p.morale = minf(100.0, p.morale + 1.0)
			t = "A few rounds on the arcade machine. Reaction %+.2f, morale +1." % d4
		"aquarium":
			p.morale = minf(100.0, p.morale + 1.0)
			t = "The fish don't care about your rating. Morale +1."
		"bar":
			var gs2 := guests_now()
			if gs2.is_empty():
				p.morale = minf(100.0, p.morale + 1.0)
				t = "You pour yourself one. Just the one. Morale +1."
			else:
				for g: PlayerData in gs2:
					w._relate(g.uid, 2.0)
				t = "Drinks for %s. Relationship +2." % _names(gs2)
		_:
			return {"ok": false, "text": ""}
	p.form = clampf(p.form, -8.0, 8.0)
	w.fatigue = clampf(w.fatigue, 0.0, 100.0)
	if weekly_only:
		_mark(action)
	Game.save_player_career_soon()
	return {"ok": true, "text": t}


const AGAIN := {
	"bed": "You're not tired enough to sleep again yet (once a week).",
	"pc": "Your aim session is done for the week.",
	"stream": "You've already streamed from home this week.",
	"tv": "You've watched enough demos this week.",
	"kitchen": "You've already cooked a big meal this week.",
	"gym": "Your muscles are still sore. Next week.",
	"car": "You've had your drive this week.",
	"sofa": "You've lounged enough for one week.",
	"pet": "It's asleep. Let it be.",
	"tub": "You've had your soak this week.",
}


func _names(ps: Array[PlayerData]) -> String:
	var n: Array = ps.map(func(q: PlayerData) -> String: return q.player_name)
	if n.size() == 1:
		return String(n[0])
	return "%s and %s" % [", ".join(n.slice(0, n.size() - 1)), String(n[n.size() - 1])]


## Ask one teammate over this week.
func invite(uid: int) -> String:
	if guests_week == stamp() and not guests.is_empty():
		return "You've already got people over this week"
	var t := w.user_team()
	var who: PlayerData = null
	if t != null:
		for q: PlayerData in t.roster:
			if q.uid == uid:
				who = q
	if who == null:
		return "They're not around"
	var r := w.relation(uid)
	if r < -20.0 or w.rng.randf() < 0.25 - r / 200.0:
		w._relate(uid, -1.0)
		return "%s says they're busy." % who.player_name
	guests = [uid]
	guests_week = stamp()
	w._relate(uid, 3.0)
	return ""


## Throw a house party: teammates come over (relationships up), followers up,
## and sometimes it ends up all over the feed.
func party() -> String:
	if w.wallet < PARTY_COST:
		return "A party costs $%s" % World._fmt(PARTY_COST)
	if guests_week == stamp() and guests.size() > 1:
		return "You've already had a party this week"
	var inv := invitable()
	if inv.is_empty():
		return "Nobody to invite"
	w.wallet -= PARTY_COST
	guests = []
	var came: Array[PlayerData] = []
	for q: PlayerData in inv:
		if w.relation(q.uid) > -10.0 or w.rng.randf() < 0.4:
			guests.append(q.uid)
			came.append(q)
			w._relate(q.uid, 6.0)
	guests_week = stamp()
	var size := HOME_PARTY_FAME.get(tier_of(home), 400) as int
	w._gain_fame(size)
	w.user_player.morale = minf(100.0, w.user_player.morale + 5.0)
	var scandal := 0.12 + w.soc().toxicity / 300.0
	if w.rng.randf() < scandal:
		w._trust(-6.0)
		w.soc().toxicity = minf(100.0, w.soc().toxicity + 4.0)
		w._news("SCANDAL: videos from your house party are all over the feed. The coach is not impressed.")
		w._post(w._fan_handle(), "%s's party got WILD last night lmao the neighbours called the police" % w.user_player.player_name, "press", 1.6)
		return "Party! %d came. Then someone posted the videos: coach trust -6." % came.size()
	w._post(w._fan_handle(), "%s threw a party with the whole squad, team chemistry looking good" % w.user_player.player_name, "fan", 1.1)
	return "Party! %d teammates came round (relationships +6, +%s followers)." % [came.size(), World.fame_text(size)]


const HOME_PARTY_FAME := {"rental": 200, "apartment": 600, "house": 1500, "penthouse": 4000}


func vacation_ready() -> bool:
	return abs_week() - last_vacation >= 6


## A week away: fatigue gone, morale up. Mid-season the coach notices.
func vacation() -> String:
	if not vacation_ready():
		return "You were away recently. Wait %d more week(s)." % (6 - (abs_week() - last_vacation))
	if w.wallet < VACATION_COST:
		return "A trip costs $%s" % World._fmt(VACATION_COST)
	w.wallet -= VACATION_COST
	last_vacation = abs_week()
	w.fatigue = 0.0
	var p := w.user_player
	p.morale = minf(100.0, p.morale + 15.0)
	var quiet := w.week <= 2 or w.week >= World.SEASON_WEEKS - 1 or w.teamless
	w._post(w._fan_handle(), "%s posting beach pics, living the life" % p.player_name, "fan", 1.0)
	if quiet:
		return "A week in the sun. Fatigue gone, morale +15."
	w._trust(-5.0)
	p.form -= 0.5
	return "A week in the sun: fatigue gone, morale +15. The coach wasn't thrilled you left mid-season (trust -5, a bit rusty)."


# --- Save ----------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"home": home, "used": used.duplicate(), "inv": investments.duplicate(true), "skin": skin, "outfit": outfit,
		"guests": guests.duplicate(), "gweek": guests_week, "vac": last_vacation}


static func from_dict(world: World, d: Dictionary) -> Lifestyle:
	var l := Lifestyle.new(world)
	l.home = String(d.get("home", STARTER))
	if not SHOP.has(l.home):
		l.home = STARTER
	var u: Dictionary = d.get("used", {})
	for k in u:
		l.used[String(k)] = int(u[k])
	var inv: Dictionary = d.get("inv", {})
	for k in inv:
		if INVEST.has(String(k)):
			l.investments[String(k)] = {"value": float(inv[k].get("value", 0.0)), "paid": int(inv[k].get("paid", 0))}
	l.skin = String(d.get("skin", ""))
	l.outfit = int(d.get("outfit", 0))
	for g in d.get("guests", []):
		l.guests.append(int(g))
	l.guests_week = int(d.get("gweek", -1))
	l.last_vacation = int(d.get("vac", -100))
	return l
