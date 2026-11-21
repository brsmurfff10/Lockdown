class_name TeamData
extends Resource

@export var team_name: String = ""
@export var short_name: String = ""
@export var color: Color = Color.WHITE
@export var roster: Array[PlayerData] = []
@export var wins: int = 0
@export var losses: int = 0
@export var round_diff: int = 0
@export var reputation: float = 20.0 ## 0-100: sponsors, invites, who wants to join.
@export var points: int = 0 ## World ranking points (tournament placements).
@export var is_user_team: bool = false
@export var titles: int = 0
@export var league: int = 0 ## Index into World.LEAGUES (0 = top division).
@export var money: int = 0 ## Club budget (AI clubs; the user's org uses World.money).
@export var manual_lineup: bool = false ## Manager picks the starting five; don't auto-sort.
@export var last_rating: float = 0.0 ## Starting-five rating last week (news ticker change).
@export var streak: int = 0 ## +N wins in a row / -N losses in a row.
@export var sponsor_name: String = "" ## AI clubs' headline sponsor (flavour).
## My Player: the coach picks on merit, the user included (set by World).
@export var logo: String = "box" ## Badge style: box, round, outline, solid, split.
@export var color2: Color = Color(0, 0, 0, 0) ## Secondary colour (transparent = derived from the main one).
var coach_pick := false
var user_bonus := 0.0


## The first `count` available players in lineup order. Sick/injured players
## are skipped; if that leaves too few, they're used anyway (AI clubs field
## whoever they have). The manager is stopped earlier: see available_count().
func starters(count: int = 5) -> Array[PlayerData]:
	var out: Array[PlayerData] = []
	for p in roster:
		if out.size() >= count:
			break
		if p.available():
			out.append(p)
	for p in roster:
		if out.size() >= count:
			break
		if not out.has(p):
			out.append(p)
	return out


func available_count() -> int:
	var n := 0
	for p in roster:
		if p.available():
			n += 1
	return n


## Rating with current form: what the simulator plays with.
func form_rating() -> float:
	var s := starters(5)
	if s.is_empty():
		return 0.0
	var total := 0.0
	for p in s:
		total += p.rating_exact() + p.form * 0.6
	return total / s.size()


func rating_exact() -> float:
	var s := starters(5)
	if s.is_empty():
		return 0.0
	var total := 0.0
	for p in s:
		total += p.rating_exact()
	return total / s.size()


func rating() -> int:
	var s := starters(5)
	if s.is_empty():
		return 0
	var total := 0.0
	for p in s:
		total += p.rating_exact()
	return int(round(total / s.size()))


## Coach's view of a player: rating, form, and (for you) trust and promises.
func lineup_score(p: PlayerData) -> float:
	return p.rating_exact() + p.form * 0.6 + (user_bonus if p.is_user else 0.0)


## Best players start. In My Player the coach decides (see lineup_score).
func sort_roster() -> void:
	if manual_lineup:
		return
	if coach_pick:
		roster.sort_custom(func(a: PlayerData, b: PlayerData) -> bool: return lineup_score(a) > lineup_score(b))
		return
	roster.sort_custom(func(a: PlayerData, b: PlayerData) -> bool:
		if a.is_user != b.is_user:
			return a.is_user
		return a.rating_exact() > b.rating_exact())


func has_user() -> bool:
	for p in roster:
		if p.is_user:
			return true
	return false


func to_dict() -> Dictionary:
	var players := []
	for p in roster:
		players.append(p.to_dict())
	return {
		"name": team_name, "short": short_name, "color": color.to_html(false),
		"roster": players, "wins": wins, "losses": losses, "round_diff": round_diff,
		"reputation": reputation, "points": points, "is_user_team": is_user_team, "titles": titles,
		"league": league, "money": money, "manual_lineup": manual_lineup,
		"last_rating": last_rating, "streak": streak, "sponsor": sponsor_name,
		"logo": logo, "color2": color2.to_html(true),
	}


static func from_dict(d: Dictionary) -> TeamData:
	var t := TeamData.new()
	t.team_name = d.get("name", "")
	t.short_name = d.get("short", "")
	t.color = Color.html(d.get("color", "ffffff"))
	t.logo = String(d.get("logo", "box"))
	t.color2 = Color.html(d.get("color2", "00000000"))
	for pd in d.get("roster", []):
		t.roster.append(PlayerData.from_dict(pd))
	t.wins = int(d.get("wins", 0))
	t.losses = int(d.get("losses", 0))
	t.round_diff = int(d.get("round_diff", 0))
	t.reputation = float(d.get("reputation", 20.0))
	t.points = int(d.get("points", 0))
	t.is_user_team = bool(d.get("is_user_team", false))
	t.titles = int(d.get("titles", 0))
	t.league = int(d.get("league", 0))
	t.money = int(d.get("money", 0))
	t.manual_lineup = bool(d.get("manual_lineup", false))
	t.last_rating = float(d.get("last_rating", 0.0))
	t.streak = int(d.get("streak", 0))
	t.sponsor_name = String(d.get("sponsor", ""))
	return t
