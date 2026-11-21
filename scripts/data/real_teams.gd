class_name RealTeams
extends RefCounted
## Real-world team packs from HLTV world-ranking snapshots: "real" (current
## teams) and "og" (the 2015 classics). New careers can start with a pack, and
## the Editor can apply one to an existing save (renames clubs, players,
## nations, colours and logos; stats are kept).
## Data: res://data/<pack>/teams.json, logos in res://data/<pack>/logos/.
## The packs are local only: delete a data/<pack> folder to remove it.
## Team logo keys: "img:<slug>" (real pack) or "img:<pack>/<slug>".

const PACKS := {"real": "Real teams", "og": "OG Teams"}
## Packs kept in the game but hidden from the menus (setup checkboxes, Editor).
const HIDDEN := ["og"]
const LIGHT_BG := Color("d8dee9")
const DARK_BG := Color("161b26")
const TAGS := {"Natus Vincere": "NAVI", "Ninjas in Pyjamas": "NIP", "The MongolZ": "MGLZ", "100 Thieves": "100T",
	"Eternal Fire": "EF", "GamerLegion": "GL", "Iberian Soul": "IBS", "Black Phoenix": "BPX", "Inner Circle": "IC",
	"Lynn Vision": "LVG", "Nuclear TigeRES": "NTR", "BASEMENT BOYS": "BB", "Chinggis Warriors": "CW", "PARIVISION": "PARI",
	"BETBOOM": "BB", "Vitality": "VIT", "Falcons": "FLC", "Aurora": "AUR", "Spirit": "TS", "Liquid": "TL",
	"HEROIC": "HER", "Astralis": "AST", "Legacy": "LGC", "Wildcard": "WC", "Luminosity": "LG", "FlyQuest": "FLY",
	"Imperial": "IMP", "Nemiga": "NEM", "BC.Game": "BCG", "JiJieHao": "JJH", "SINNERS": "SIN", "TYLOO": "TYL"}
const FILL_ROLES := ["Rifler", "Entry", "Lurker", "Rifler", "Support"]

static var _data: Dictionary = {} ## pack -> parsed teams.json
static var _by_slug: Dictionary = {} ## pack -> {slug: record}
static var _tex: Dictionary = {}


static func _dir(pack: String) -> String:
	return "res://data/%s/" % pack


static func teams(pack: String = "real") -> Array:
	if not _data.has(pack):
		_data[pack] = {}
		_by_slug[pack] = {}
		var path := _dir(pack) + "teams.json"
		if FileAccess.file_exists(path):
			var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if typeof(j) == TYPE_DICTIONARY:
				_data[pack] = j
				for t: Dictionary in (j as Dictionary).get("teams", []):
					_by_slug[pack][String(t.slug)] = t
	return (_data[pack] as Dictionary).get("teams", [])


static func available(pack: String = "real") -> bool:
	return PACKS.has(pack) and not teams(pack).is_empty()


## Installed packs, in menu order.
static func installed() -> Array:
	return PACKS.keys().filter(func(p: String) -> bool: return available(p))


## Installed packs the player can pick (installed minus HIDDEN).
static func in_menus() -> Array:
	return installed().filter(func(p: String) -> bool: return not HIDDEN.has(p))


static func label(pack: String) -> String:
	return String(PACKS.get(pack, pack))


static func source(pack: String = "real") -> String:
	teams(pack)
	return String((_data[pack] as Dictionary).get("source", "HLTV ranking"))


## Every nation in the installed packs (for the nation pickers and the World Cup).
static func nations() -> Array:
	var out: Array = []
	for pack: String in installed():
		for t: Dictionary in teams(pack):
			for p: Dictionary in t.players:
				if not out.has(String(p.nation)):
					out.append(String(p.nation))
	out.sort()
	return out


## "og/fnatic" -> ["og", "fnatic"]; a bare slug is the real pack.
static func _split(key: String) -> Array:
	var i := key.find("/")
	return ["real", key] if i < 0 else [key.substr(0, i), key.substr(i + 1)]


static func _record(key: String) -> Dictionary:
	var ps := _split(key)
	teams(ps[0])
	return (_by_slug.get(ps[0], {}) as Dictionary).get(ps[1], {})


static func logo_texture(key: String) -> Texture2D:
	if _tex.has(key):
		return _tex[key]
	var tex: Texture2D = null
	var t := _record(key)
	if not t.is_empty() and String(t.logo) != "":
		var path := _dir(_split(key)[0]) + "logos/" + String(t.logo)
		if ResourceLoader.exists(path):
			tex = load(path)
	_tex[key] = tex
	return tex


static func logo_bg(key: String) -> Color:
	return LIGHT_BG if bool(_record(key).get("light_bg", false)) else DARK_BG


static func tag_for(n: String) -> String:
	if TAGS.has(n):
		return TAGS[n]
	var words := n.split(" ", false)
	if words.size() == 1:
		return n.to_upper() if n.length() <= 4 else n.substr(0, 3).to_upper()
	var s := ""
	for wd in words:
		s += wd.substr(0, 1)
	return s.to_upper().substr(0, 4)


## Name, tag, colours and logo from a pack record.
static func _brand(t: TeamData, rec: Dictionary, pack: String) -> void:
	t.team_name = String(rec.name).substr(0, 24)
	t.short_name = tag_for(String(rec.name))
	if String(rec.color) != "":
		t.color = Color(String(rec.color))
	t.color2 = Color(String(rec.color2)) if String(rec.get("color2", "")) != "" else Color(0, 0, 0, 0)
	var key := String(rec.slug) if pack == "real" else "%s/%s" % [pack, rec.slug]
	t.logo = ("img:" + key) if String(rec.logo) != "" else "box"


static func _reserve_names(w: World, pack: String) -> void:
	for t: Dictionary in teams(pack):
		for p: Dictionary in t.players:
			w.used_names[String(p.nick)] = true


## A new world: the top 64 fill the four leagues in ranking order with fresh
## rosters (real starters scaled from the ranking, generated subs). The rest
## of the ranking becomes the free-agent pool.
static func apply_new(w: World, pack_id: String = "real") -> void:
	var pack := teams(pack_id)
	if pack.is_empty():
		return
	_reserve_names(w, pack_id)
	var order: Array = []
	for l in World.LEAGUES.size():
		order.append_array(w.league_teams(l))
	for i in mini(order.size(), pack.size()):
		var t: TeamData = order[i]
		var rec: Dictionary = pack[i]
		_brand(t, rec, pack_id)
		var l := t.league
		var q: Array = World.LEAGUES[l].quality
		var k := i % World.TEAMS_PER_LEAGUE
		var quality := float(q[1]) - (float(q[1]) - float(q[0])) * k / float(World.TEAMS_PER_LEAGUE - 1)
		t.roster.clear()
		var reals: Array = rec.players
		var has_awp := false
		for rp: Dictionary in reals:
			has_awp = has_awp or String(rp.role) == "AWPer"
		for j in reals.size():
			var rp: Dictionary = reals[j]
			var role := String(rp.role)
			if role == "":
				role = "AWPer" if not has_awp else String(FILL_ROLES[j % FILL_ROLES.size()])
				has_awp = true
			var p := w._new_player(quality + float(rp.get("star", 0)), role)
			w.used_names.erase(p.player_name)
			p.player_name = String(rp.nick)
			p.nation = String(rp.nation)
			p.age = clampi(p.age, 18, 31)
			p.potential = maxi(p.potential, p.rating())
			t.roster.append(p)
		while t.roster.size() < World.ROSTER_SIZE:
			var role := "AWPer" if not has_awp else String(FILL_ROLES[w.rng.randi() % FILL_ROLES.size()])
			has_awp = true
			t.roster.append(w._new_player(quality - 4.0, role))
		t.sort_roster()
		t.reputation = clampf((t.rating() - 35.0) * 1.5, 5.0, 95.0)
		t.last_rating = t.rating_exact()
	_rename_free_agents(w, pack_id, order.size())


## An existing save: clubs are matched to the ranking by league and strength
## (best Premier club = #1). Names, nations, colours and logos change; stats,
## contracts and history stay. Your manager club and your own player are kept.
## Returns how many clubs were renamed.
static func apply_existing(w: World, pack_id: String = "real") -> int:
	var pack := teams(pack_id)
	if pack.is_empty():
		return 0
	var keep_team: TeamData = w.user_team() if w.mode == "manager" else null
	var order: Array = []
	for l in World.LEAGUES.size():
		var lt: Array = w.league_teams(l).filter(func(t: TeamData) -> bool: return t != keep_team)
		lt.sort_custom(func(a: TeamData, b: TeamData) -> bool: return a.rating_exact() > b.rating_exact())
		order.append_array(lt)
	var real_nicks := {}
	for t: Dictionary in pack:
		for p: Dictionary in t.players:
			real_nicks[String(p.nick)] = true
	var renamed := {} ## PlayerData -> true
	var count := 0
	for i in mini(order.size(), pack.size()):
		var t: TeamData = order[i]
		var rec: Dictionary = pack[i]
		var clash := false
		for o in w.teams:
			if o != t and o.team_name.to_lower() == String(rec.name).to_lower() and o == keep_team:
				clash = true
		if not clash:
			_brand(t, rec, pack_id)
			count += 1
		# Real names onto the club's best players; known AWPers onto its AWPer.
		var pool: Array = t.roster.filter(func(p: PlayerData) -> bool: return not p.is_user and p.loan_from == "")
		pool.sort_custom(func(a: PlayerData, b: PlayerData) -> bool: return a.rating_exact() > b.rating_exact())
		var reals: Array = (rec.players as Array).duplicate()
		reals.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("star", 0)) > int(b.get("star", 0)))
		for rp: Dictionary in reals:
			if pool.is_empty():
				break
			var pick: PlayerData = pool[0]
			if String(rp.role) == "AWPer":
				for p: PlayerData in pool:
					if p.role == "AWPer":
						pick = p
						break
			pool.erase(pick)
			_rename(w, pick, String(rp.nick))
			pick.nation = String(rp.nation)
			renamed[pick] = true
	_rename_free_agents(w, pack_id, order.size(), renamed)
	# Anyone else who happens to share a real player's name gets a new one.
	_reserve_names(w, pack_id)
	var everyone: Array = w.free_agents.duplicate()
	for t in w.teams:
		everyone.append_array(t.roster)
	for p: PlayerData in everyone:
		if not renamed.has(p) and not p.is_user and real_nicks.has(p.player_name):
			_rename(w, p, NameGen.handle(w.rng, w.used_names))
	w._news("The world has been rebranded: %s (%s)." % [label(pack_id), source(pack_id)])
	return count


static func _rename_free_agents(w: World, pack_id: String, start: int, renamed: Dictionary = {}) -> void:
	var pack := teams(pack_id)
	var names: Array = []
	for i in range(start, pack.size()):
		for rp: Dictionary in (pack[i] as Dictionary).players:
			names.append(rp)
	var j := 0
	for p: PlayerData in w.free_agents:
		if j >= names.size():
			break
		if p.is_user:
			continue
		var rp: Dictionary = names[j]
		j += 1
		_rename(w, p, String(rp.nick))
		p.nation = String(rp.nation)
		renamed[p] = true


static func _rename(w: World, p: PlayerData, n: String) -> void:
	var old := p.player_name
	if old == n:
		return
	w.used_names.erase(old)
	w.used_names[n] = true
	if w.last_training.has(old):
		w.last_training[n] = w.last_training[old]
		w.last_training.erase(old)
	p.player_name = n
