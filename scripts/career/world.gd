class_name World
extends RefCounted
## The persistent esports world shared by both careers.
##
## 64 teams in 4 leagues (Premier, Pro, Challenger, Academy). Each season:
##   weeks 1-15   league play: single round-robin, one match a week
##   weeks 16-18  league playoffs: top 8, quarter/semi/final, prize money
##   week 24      season end: top 2 promoted, bottom 2 relegated, contracts
##                expire, players age/retire, new prospects arrive
## Optional cups (Open / Challenger / Major) run alongside, with league-based
## eligibility. Transfer windows: weeks 1-4 and 13-15 (free agents any time).
##
## mode "manager": you run one org (money, transfers, training, lineup).
## mode "player":  you are one player (`user_player`) on an AI-run team.

const LEAGUES := [
	{"name": "Premier League", "short": "PRE", "quality": [90.0, 97.0], "prize": 2000000, "sponsor": 70000, "budget": 4000000, "points": 3.0},
	{"name": "Pro League", "short": "PRO", "quality": [74.0, 88.0], "prize": 600000, "sponsor": 25000, "budget": 1500000, "points": 1.6},
	{"name": "Challenger League", "short": "CHL", "quality": [57.0, 72.0], "prize": 150000, "sponsor": 9000, "budget": 500000, "points": 0.8},
	{"name": "Academy League", "short": "ACA", "quality": [40.0, 55.0], "prize": 40000, "sponsor": 3000, "budget": 150000, "points": 0.4},
]
const TEAMS_PER_LEAGUE := 16
const LEAGUE_WEEKS := 15
const PLAYOFF_START := 16
const PLAYOFF_SIZE := 8
const PROMOTE := 2
const SEASON_WEEKS := 24
const WINDOWS := [[1, 4], [13, 15]]
const ROSTER_SIZE := 7
const MIN_ROSTER := 5
const MAX_ROSTER := 7
const FREE_AGENT_COUNT := 150
const CUP_SIZE := 16
const ROUNDS_TO_WIN := 6
const MAX_ROUNDS := 10

const TIERS := {
	"Open": {"fee": 5000, "pool": 60000, "min_rep": 0.0, "mult": 1.0, "max_league": 3},
	"Challenger": {"fee": 25000, "pool": 400000, "min_rep": 35.0, "mult": 2.5, "max_league": 2},
	"Major": {"fee": 100000, "pool": 2500000, "min_rep": 60.0, "mult": 6.0, "max_league": 1},
}
## [name, tier, start week]. 16-team single elimination over 4 weeks.
const CALENDAR := [
	["Open Cup", "Open", 3], ["Challenger Cup", "Challenger", 7], ["Open Cup II", "Open", 10],
	["Spring Major", "Major", 11], ["Challenger Finals", "Challenger", 19], ["World Major", "Major", 20],
]
const PRIZE_SHARE := {1: 0.40, 2: 0.20, 3: 0.10, 5: 0.05, 9: 0.0}
const PLACE_POINTS := {1: 100, 2: 60, 3: 35, 5: 15, 9: 5}
const PLAYOFF_SHARE := {1: 0.45, 2: 0.25, 3: 0.10, 5: 0.025}

const TEAM_ADJ := ["Iron", "Red", "Black", "Silver", "Neon", "Crimson", "Northern", "Golden", "Night", "Storm",
	"Static", "Hollow", "Rogue", "Frozen", "Wild", "Lucky", "Savage", "Electric", "Phantom", "Royal",
	"Atomic", "Shadow", "Steel", "Cobalt", "Scarlet", "Emerald", "Solar", "Lunar", "Rapid", "Ghost"]
const TEAM_NOUN := ["Owls", "Vipers", "Legion", "Syndicate", "Kings", "Wolves", "Raptors", "Saints", "Collective",
	"Gaming", "Esports", "Hornets", "Foxes", "Titans", "Bandits", "Knights", "Rebels", "Sharks", "Ravens",
	"Dynasty", "Outlaws", "Pirates", "Monarchs", "Squad", "Cartel", "Spartans", "Cobras", "Union", "Crew", "Five"]
const FIXED_NAMES := [
	"Ironclad", "Voltage", "Nightjar", "Granite", "Sunforge", "Tidebreak", "Wildfire", "Frostbite",
	"Black Lotus", "Red Comet", "Hollow Point", "Northwind", "Sable Kings", "Copperline", "Grey Wolves", "Static Shock",
]

## Sponsorship slots and the share of a club's commercial value each one carries.
const SPONSOR_SLOTS := {"Main": 0.45, "Apparel": 0.25, "Partner": 0.2}
const SPONSOR_BRANDS := ["Hyperion Energy", "Vortex Peripherals", "Nimbus Bank", "Kairo Motors", "Pulse Drinks",
	"Arclight PC", "Stratus Air", "Omen Apparel", "Bolt Telecom", "Zenith Watches", "Granite Insurance",
	"Lumen Eyewear", "Rift Chairs", "Fizz Cola", "NorthPeak Outdoors", "Quanta Cloud", "Ember Noodles",
	"Halcyon Hotels", "Paragon Audio", "Tessera Chips", "Monolith Displays", "Cascade Water", "Orbit VPN"]
## Lenders. loan: borrow now, repay principal + rate in equal weekly payments.
## stake: cash now, the investor takes `share` of all income for `weeks`.
const LENDERS := [
	{"name": "Citadel Bank", "kind": "loan", "rate": 0.08, "weeks": 30, "limit": 0.5, "min_rep": 35.0,
		"desc": "Cheapest money around, but only for established clubs."},
	{"name": "Players' Credit Union", "kind": "loan", "rate": 0.14, "weeks": 20, "limit": 0.3, "min_rep": 12.0,
		"desc": "Fair terms for smaller orgs. Modest limits."},
	{"name": "Ventura Capital", "kind": "stake", "share": 0.15, "weeks": 48, "limit": 0.9, "min_rep": 20.0,
		"desc": "No repayments: they take 15% of all income for two seasons."},
	{"name": "Apex Equity", "kind": "stake", "share": 0.3, "weeks": 72, "limit": 2.0, "min_rep": 45.0,
		"desc": "Huge cheque for 30% of all income for three seasons."},
	{"name": "QuickCash Lending", "kind": "loan", "rate": 0.35, "weeks": 10, "limit": 0.25, "min_rep": 0.0,
		"desc": "Anyone qualifies. The interest is brutal."},
]
const ILLNESSES := ["the flu", "food poisoning", "a fever", "a migraine", "a stomach bug"]
const INJURIES := ["a wrist strain", "a back spasm", "an RSI flare-up", "eye strain", "a sprained hand"]
const SLUMP_REASONS := ["lost confidence", "a nagging wrist strain", "personal issues", "burnout from streaming",
	"a new mouse that isn't working out", "visa stress", "a breakup", "sleep problems", "a rift with a teammate"]
const HOT_REASONS := ["a new training routine", "a confidence boost", "a fresh setup", "a great bootcamp",
	"the crowd behind them", "a point to prove"]

const TRAINING_FOCUS := {
	"Balanced": ["aim", "flick", "preaim", "recoil", "reaction", "movement", "positioning", "decision", "utility"],
	"Aim": ["aim", "flick", "recoil"],
	"Game Sense": ["preaim", "positioning", "decision"],
	"Reflexes": ["reaction", "movement", "flick"],
	"Utility": ["utility", "decision"],
}
const TRAINING_INTENSITY := {
	"Rest": {"cost": 0, "mult": 0.0},
	"Light": {"cost": 1000, "mult": 0.5},
	"Normal": {"cost": 3000, "mult": 1.0},
	"Intense": {"cost": 8000, "mult": 1.6},
}
## My Player training.
const PM_INTENSITY := {
	"Light": {"mult": 0.5, "sd": 0.25, "injury": 0.0, "desc": "Small, safe gains and a morale lift."},
	"Normal": {"mult": 1.0, "sd": 0.4, "injury": 0.01, "desc": "The usual. A bad session can set you back."},
	"Hard": {"mult": 1.7, "sd": 0.7, "injury": 0.07, "desc": "Big gains, bigger swings, 7% injury risk."},
}
const SPECIALTIES := {
	"Entry Fragger": ["reaction", "movement", "flick"],
	"AWP Specialist": ["aim", "flick", "positioning"],
	"Spray Master": ["recoil", "aim", "preaim"],
	"Anchor": ["positioning", "utility", "preaim"],
	"Clutch Player": ["decision", "reaction", "positioning"],
	"Strategist": ["decision", "utility", "positioning"],
}
const SPECIALTY_MATCHES := 15
const RESPEC_COST := 5000
const PERKS := {
	"first_blood": {"name": "First Blood", "need": "Play 10 matches", "desc": "+1.5 Reaction, +1 Movement."},
	"grinder": {"name": "Grinder", "need": "Play 40 matches", "desc": "Training gains +20%."},
	"headhunter": {"name": "Headhunter", "need": "400 career kills", "desc": "+1.5 Aim, +1.5 Flick."},
	"iron": {"name": "Iron Body", "need": "Play 80 matches", "desc": "Half the chance of illness and injury."},
	"silverware": {"name": "Silverware", "need": "Win a trophy", "desc": "Morale never drops below 40."},
	"big_game": {"name": "Big Game Player", "need": "Average 1.15+ over a season (10+ matches)", "desc": "+2.5 to every stat in cup and playoff matches."},
	"showman": {"name": "Showman", "need": "5 Player of the Match awards", "desc": "Fame gains +30%."},
	"fan_fav": {"name": "Fan Favourite", "need": "25k followers", "desc": "Endorsements pay 25% more."},
	"veteran": {"name": "Veteran Mind", "need": "Play 200 matches", "desc": "+2 Decision, +2 Positioning; aging hits half as hard."},
}
const PERSONAL_BRANDS := ["Kinetic Mice", "Apex Chairs", "Volt Energy", "Nightowl Headsets", "Glide Mousepads",
	"Ripple Streaming", "Ironclad Keyboards", "Zest Gummies", "Orbit Monitors"]
const SETUP_COSTS := [6000, 20000, 60000]
const COACH_COST := 2500
const RETIRE_AGE := 32
const FORCED_RETIRE := 38

var rng := RandomNumberGenerator.new()
var mode := "manager"
var teams: Array[TeamData] = []
var free_agents: Array[PlayerData] = []
var user_team_idx := 0
var user_player: PlayerData = null ## Player mode only.
var money: int = 250000
var season := 1
var week := 1
var schedules: Array = [] ## [league] -> Array[week] of Array of [a, b]
var week_matches: Array = [] ## This week's league fixtures (Dictionaries).
var tournaments: Array = [] ## Cups and league playoffs (bracket dictionaries).
var news: Array[String] = []
var ledger: Array = []
var training := {"focus": "Balanced", "intensity": "Normal"}
var facility := 1
var last_training := {}
var offers_made := {}
var used_names := {}
var next_uid := 1
# Finances.
var sponsors: Array = [] ## Active deals: {brand, slot, weekly, per_win, goal, goal_bonus, weeks}
var sponsor_offers: Array = [] ## Same + {bonus (signing), expires}
var loans: Array = [] ## {lender, kind, principal, weekly, weeks_left, weeks, share}
var debt_weeks := 0
# Clubs bidding for your players: {id, team, player (uid), cash, swap (uid or 0), expires}
var incoming: Array = []
var next_offer_id := 1
var wire: Array = [] ## World news for the ticker: {text, kind}
## Manager mailbox: {id, kind, title, body, uid, options: [[label, action]], data, done, result, s, w, read}
var inbox: Array = []
var next_msg_id := 1
var former_players := {} ## uid -> true: players who left your club (news when they sign elsewhere).
# Player mode.
var offers: Array = [] ## [{team, note, wage, years}]
var trained_this_week := false
var last_report: Dictionary = {}
var wallet: int = 0 ## Your own money: wages, endorsements, bonuses.
var fame: int = 200 ## Followers.
var coach_trust: float = 55.0 ## 0-100: how much the coach rates you (lineup, contract talks).
var endorsements: Array = [] ## Personal deals: {brand, weekly, weeks}
var awards: Array = [] ## {s, name, detail}
var trophies: Array = [] ## Medals: {s, name, place, team} (place 0 = promotion)
var timeline: Array = [] ## One line per season and club: {s, team, league, m, k, d, r_sum, pos, titles}
var goals: Array = [] ## This season: {kind, text, target, reward, status}
var perks: Array = [] ## Unlocked perk ids (see PERKS).
var specialty := ""
var rivals := {} ## Opposing stars you've faced: uid -> {name, team, w, l}
var potm := 0 ## Player of the match awards.
var peak_rating := 0
var transfer_request := false
var setup_level := 0
var coach_booked := false
var trash_target := -1 ## Team you trash-talked: they're fired up next time.
var free_agency := false ## Contract ran out: pick a club before the season can go on.
var renewal_done := false ## This contract's renewal talks are settled.
var allstar: Dictionary = {} ## {season, a: [uid], b: [uid], done, score}
var retired := false
var legacy: Dictionary = {}

# --- Batch 9: difficulty, club operations, My Player extras, history ---------
const DIFFICULTIES := {
	"Casual": {"desc": "Fewer injuries, richer sponsors, a patient board, rivals less aggressive, players happier to join, sloppier bots.",
		"injury": 0.5, "income": 1.25, "ai": 0.7, "board": 1.6, "edge": 2.0, "refuse": 0.5, "bots": 1.3},
	"Normal": {"desc": "The intended balance.", "injury": 1.0, "income": 1.0, "ai": 1.0, "board": 1.0, "edge": 0.0, "refuse": 1.0, "bots": 0.85},
	"Hardcore": {"desc": "More injuries, tighter money, a ruthless board, predatory rivals, choosier players, sharper bots, tougher matches.",
		"injury": 1.5, "income": 0.8, "ai": 1.4, "board": 0.6, "edge": -1.5, "refuse": 1.6, "bots": 0.5},
}
const STAFF_ROLES := {
	"Head Coach": {"base": 900, "desc": "Training +8% per star; academy prospects grow faster."},
	"Analyst": {"base": 800, "desc": "+0.4 to every starter's stats per star on match day."},
	"Physio": {"base": 700, "desc": "-12% illness and injury per star; faster recovery at 3+ stars."},
	"Scout": {"base": 600, "desc": "Scouts 1 + stars players a week; tighter estimates on everyone else."},
}
const STAFF_FIRST := ["Anders", "Mia", "Tomas", "Lena", "Viktor", "Sofia", "Marco", "Hana", "Pieter", "Ines", "Kai", "Nadia", "Oskar", "Zoe"]
const STAFF_LAST := ["Holm", "Novak", "Reyes", "Lindqvist", "Okafor", "Brandt", "Kowal", "Moreau", "Sato", "Vance", "Petrov", "Duarte"]
const FACILITIES := {
	"Training Center": {"max": 5, "cost": 60000, "upkeep": 400, "needs": "", "desc": "+15% training gains per level."},
	"Gaming House": {"max": 3, "cost": 80000, "upkeep": 700, "needs": "", "desc": "Players live together: morale up every week."},
	"Medical Room": {"max": 3, "cost": 70000, "upkeep": 500, "needs": "", "desc": "-10% illness and injury per level."},
	"Bootcamp": {"max": 3, "cost": 120000, "upkeep": 1000, "needs": "Gaming House", "desc": "Form drifts up each week; +4 chemistry per level."},
	"Analyst Room": {"max": 3, "cost": 90000, "upkeep": 600, "needs": "Training Center:2", "desc": "+0.25 match-day stats per level; sharper scouting."},
	"Youth Academy": {"max": 3, "cost": 100000, "upkeep": 900, "needs": "Training Center:2", "desc": "Opens the academy: 3 + level prospects, better intakes."},
}
## Shop items (homes, cars, extras, pets, style, skins, staff): see Lifestyle.SHOP.
const STREAM := {
	"Off": {"income": 0.0, "fans": 0.0, "fatigue": -8.0, "desc": "Rest. Fatigue recovers."},
	"Casual": {"income": 0.02, "fans": 0.006, "fatigue": 2.0, "desc": "A few streams a week. Some money, some fans."},
	"Heavy": {"income": 0.05, "fans": 0.015, "fatigue": 9.0, "desc": "Streaming every night. Big money and fans, but fatigue hurts your form."},
}
const TRAITS := {
	"entry_king": {"name": "Entry King", "need": "0.85+ kills per round over 20 matches", "stats": ["reaction", "movement"]},
	"survivor": {"name": "Survivor", "need": "Die in under 55% of rounds over 20 matches", "stats": ["positioning", "decision"]},
	"damage": {"name": "Damage Dealer", "need": "90+ ADR over 20 matches", "stats": ["aim", "recoil"]},
	"awp_god": {"name": "AWP God", "need": "1.20+ rating over 20 matches as an AWPer", "stats": ["aim", "flick"]},
	"consistent": {"name": "Mr. Consistent", "need": "20 straight matches without dropping under 0.80", "stats": ["decision", "preaim"]},
	"big_stage": {"name": "Big Stage", "need": "5 cup or playoff matches at 1.25+", "stats": ["reaction", "preaim"]},
	"clutch": {"name": "Clutch Minister", "need": "10 highlight moments (3k+, clutches, aces)", "stats": ["decision", "reaction"]},
}

var difficulty := "Normal"
var staff := {} ## role -> {role, name, stars, wage}
var staff_market: Array = []
var facilities := {} ## Facility name -> level (Training Center lives in `facility`).
var academy: Array[PlayerData] = []
var scouted := {} ## uid -> true
var scout_queue: Array = []
var board := {} ## {kind, target, text, confidence}
var job_offers: Array = [] ## {team, note, forced}
var sacked := false
var assets: Array = []
var stream_level := "Off"
var fatigue := 0.0
var relations := {} ## teammate uid -> -100..100
var traits: Array = []
var highlights := 0
var caps := 0
var reviews: Array = []
var review_pending := false
var _review: Dictionary = {}
var hall_of_fame: Array = []
var champions: Array = [] ## {s, name, team}
var records := {} ## title -> {value, holder, team, s, w}
var season_transfers: Array = []
# --- Batch 10 ---
const AGENTS := {
	"none": {"name": "No agent", "cut": 0.0, "wage": 0.0, "push": 0.0, "offers": 0.0, "reach": 0, "fee": 0,
		"desc": "You negotiate yourself."},
	"local": {"name": "Local agent", "cut": 0.05, "wage": 0.05, "push": 0.08, "offers": 0.15, "reach": 0, "fee": 2000,
		"desc": "Takes 5% of your wage. +5% wage offers, a bit more interest from clubs."},
	"pro": {"name": "Pro agency", "cut": 0.08, "wage": 0.12, "push": 0.15, "offers": 0.3, "reach": 3, "fee": 10000,
		"desc": "Takes 8%. +12% wage offers, better at pushing for more, clubs slightly above your level call."},
	"super": {"name": "Super agent", "cut": 0.12, "wage": 0.2, "push": 0.25, "offers": 0.5, "reach": 6, "fee": 40000, "fame": 20000,
		"desc": "Takes 12%. +20% wage offers, the best negotiator, opens doors at bigger clubs. Needs 20k followers."},
}
const MERCH_COSTS := [40000, 120000, 350000]
var club_fans := 0 ## Your club's fan base (manager): grows with results, drives merch.
var merch_level := 0
var press_pledge: Dictionary = {} ## You promised a win: {team, s, w}.
var rattled_team := -1 ## Mind games worked: they play worse in your next meeting.
var derby_record := [0, 0] ## Your derby wins / losses.
var affiliate_idx := -1 ## Your second roster (a lower-league club), or -1.
var agent := "none" ## My Player agent (see AGENTS).
var feed: Array = [] ## My Player social feed: {s, w, who, text, kind, likes, re}
# --- Social (0.19) ---
var social: Social = null ## Posts, DMs, friends/rivals, discipline, comebacks (see soc()).
var lifestyle: Lifestyle = null ## Shop, your home, investments, parties (see life()).
var teamless := false ## My Player: released mid-season, no club (the player is in no roster).
var forced_bench_until := 0 ## Disciplinary bench: the coach won't pick you until this stamp.


# =============================================================================
# Creation
# =============================================================================

## pack: start with a real team pack (RealTeams: "real" or "og"); "" = fictional clubs.
func new_world(p_mode: String = "manager", pack: String = "") -> void:
	rng.randomize()
	mode = p_mode
	teams.clear()
	free_agents.clear()
	used_names.clear()
	var team_names := _team_names(LEAGUES.size() * TEAMS_PER_LEAGUE)
	for l in LEAGUES.size():
		var q: Array = LEAGUES[l].quality
		for k in TEAMS_PER_LEAGUE:
			var t := TeamData.new()
			var n: String = team_names[l * TEAMS_PER_LEAGUE + k]
			t.team_name = n
			t.short_name = _tag(n)
			t.color = Color.from_hsv(fmod((l * TEAMS_PER_LEAGUE + k) * 0.61803, 1.0), 0.55, 0.92)
			t.league = l
			var quality := rng.randf_range(q[0], q[1])
			var non_awp := ["Entry", "Rifler", "Rifler", "Support", "Lurker"]
			for i in ROSTER_SIZE:
				var role: String = "AWPer" if i == 0 else String(non_awp[rng.randi() % non_awp.size()])
				t.roster.append(_new_player(quality, role))
			t.sort_roster()
			t.reputation = clampf((t.rating() - 35.0) * 1.5, 5.0, 95.0)
			t.money = int(LEAGUES[l].budget * rng.randf_range(0.7, 1.3))
			t.sponsor_name = SPONSOR_BRANDS[rng.randi() % SPONSOR_BRANDS.size()]
			t.last_rating = t.rating_exact()
			teams.append(t)
	for i in FREE_AGENT_COUNT:
		free_agents.append(_new_player(rng.randf_range(38.0, 75.0), ""))
	if pack != "":
		RealTeams.apply_new(self, pack)
	season = 1
	week = 1
	news.clear()
	ledger.clear()
	set_difficulty(difficulty)
	_make_schedules()
	_make_calendar()
	_seed_titles()


func _team_names(count: int) -> Array:
	var out: Array = FIXED_NAMES.duplicate()
	var taken := {}
	for n in out:
		taken[n] = true
	while out.size() < count:
		var n: String = "%s %s" % [TEAM_ADJ[rng.randi() % TEAM_ADJ.size()], TEAM_NOUN[rng.randi() % TEAM_NOUN.size()]]
		if not taken.has(n):
			taken[n] = true
			out.append(n)
	# Shuffle so fixed names aren't all in the top league.
	for i in range(out.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = out[i]
		out[i] = out[j]
		out[j] = tmp
	return out


func _tag(n: String) -> String:
	var parts := n.split(" ")
	if parts.size() >= 2:
		return (parts[0].substr(0, 2) + parts[1].substr(0, 1)).to_upper()
	return n.substr(0, 3).to_upper()


func _new_player(quality: float, role: String) -> PlayerData:
	var p := PlayerData.generate(rng, quality, used_names, role)
	p.salary = PlayerData.salary_for_rating(p.rating_exact())
	p.contract_until = season + rng.randi_range(0, 2)
	p.form = rng.randfn(0.0, 1.5)
	p.morale = rng.randf_range(55.0, 80.0)
	_assign_uid(p)
	return p


func _assign_uid(p: PlayerData) -> void:
	if p.uid <= 0:
		p.uid = next_uid
		next_uid += 1
	else:
		next_uid = maxi(next_uid, p.uid + 1)
	if p.nation == "":
		p.nation = PlayerData.NATIONS[absi(hash(p.uid * 7919)) % PlayerData.NATIONS.size()]


func find_player(uid: int) -> PlayerData:
	if user_player != null and user_player.uid == uid and uid > 0:
		return user_player
	for t in teams:
		for p in t.roster:
			if p.uid == uid:
				return p
	for p in free_agents:
		if p.uid == uid:
			return p
	return null


## Manager: take over a team, rename it, set the budget by league.
func take_over(team_idx: int, org_name: String, tag: String, color: Color) -> void:
	user_team_idx = team_idx
	var t := teams[team_idx]
	t.is_user_team = true
	t.manual_lineup = true
	if org_name.strip_edges() != "" and org_name.strip_edges() != t.team_name:
		t.team_name = org_name.strip_edges()
		if t.logo.begins_with("img:"):
			t.logo = "box"
			t.color2 = Color(0, 0, 0, 0)
	if tag.strip_edges() != "":
		t.short_name = tag.strip_edges().to_upper().substr(0, 4)
	t.color = color
	money = int(LEAGUES[t.league].budget * 0.4) + 150000
	_news("Investors back %s in the %s with $%s." % [t.team_name, LEAGUES[t.league].name, _fmt(money)])
	_ledger("Investor capital", money)
	# A modest headline sponsor to start; better offers come with results.
	var first := _make_sponsor_offer("Main", "Steady")
	first.weekly = int(first.weekly * 0.8)
	_sign_sponsor(first)
	for slot in ["Apparel", "Partner"]:
		sponsor_offers.append(_make_sponsor_offer(slot))
	_refresh_staff_market()
	_make_board_objective()
	board.confidence = 60.0
	club_fans = int(t.reputation * 400.0) + 500
	_begin_week()


## Player mode: put `p` on a weak Academy team.
func place_user_player(p: PlayerData) -> void:
	user_player = p
	p.is_user = true
	p.contract_until = season + 1
	p.uid = 0 # Fresh id in this world (inbox, rivals and All-Star picks refer to it).
	_assign_uid(p)
	var candidates: Array = []
	for i in teams.size():
		if teams[i].league == LEAGUES.size() - 1:
			candidates.append(i)
	candidates.sort_custom(func(a: int, b: int) -> bool: return teams[a].rating() < teams[b].rating())
	var idx: int = candidates[rng.randi() % 4]
	var t := teams[idx]
	var cut: PlayerData = t.roster.pop_back()
	free_agents.append(cut)
	t.roster.append(p)
	t.sort_roster()
	user_team_idx = idx
	p.salary = int(PlayerData.salary_for_rating(p.rating_exact()) * 0.8 / 50.0) * 50
	p.promise_until = stamp() + 6 # Rookie deal: guaranteed starts for the first weeks.
	peak_rating = p.rating()
	_news("You signed your first pro contract with %s (%s), $%s/wk." % [t.team_name, LEAGUES[t.league].name, _fmt(p.salary)])
	_apply_coach()
	_make_goals()
	_tl()
	_begin_week()


func user_team() -> TeamData:
	if mode == "player" and user_player != null:
		for i in teams.size():
			if teams[i].roster.has(user_player):
				user_team_idx = i
				return teams[i]
	return teams[user_team_idx]


func league_teams(l: int) -> Array[TeamData]:
	var out: Array[TeamData] = []
	for t in teams:
		if t.league == l:
			out.append(t)
	return out


func league_name(t: TeamData) -> String:
	return LEAGUES[t.league].name


# =============================================================================
# Schedules
# =============================================================================

## Single round-robin per league (circle method). Uses global team indices.
func _make_schedules() -> void:
	schedules.clear()
	for l in LEAGUES.size():
		var idx: Array = []
		for i in teams.size():
			if teams[i].league == l:
				idx.append(i)
		idx.shuffle()
		var n := idx.size()
		var weeks: Array = []
		for d in n - 1:
			var pairs: Array = []
			for i in n / 2:
				var a: int = idx[i]
				var b: int = idx[n - 1 - i]
				pairs.append([a, b] if d % 2 == 0 else [b, a])
			weeks.append(pairs)
			var last: int = idx.pop_back()
			idx.insert(1, last)
		schedules.append(weeks)


func _make_calendar() -> void:
	tournaments.clear()
	for c in CALENDAR:
		tournaments.append(_new_bracket("%s S%d" % [c[0], season], "cup", c[1], c[2], CUP_SIZE, -1))


func _new_bracket(b_name: String, kind: String, tier: String, start: int, size: int, league: int) -> Dictionary:
	return {
		"name": b_name, "kind": kind, "tier": tier, "start_week": start, "size": size, "league": league,
		"teams": [], "rounds": [], "round": 0, "status": "upcoming", "user_enrolled": false, "placements": {},
	}


# =============================================================================
# Week loop
# =============================================================================

func _begin_week() -> void:
	offers_made.clear()
	trained_this_week = false
	week_matches.clear()
	if week <= LEAGUE_WEEKS:
		for l in schedules.size():
			if week - 1 < schedules[l].size():
				for pair in schedules[l][week - 1]:
					week_matches.append(_match(pair[0], pair[1], "league", LEAGUES[l].name))
	if week == PLAYOFF_START:
		_start_playoffs()
	if mode == "player":
		_auto_enroll_user_team()
	elif not teams.is_empty() and user_team().is_user_team:
		_press_conference()
	for t in tournaments:
		if t.status == "upcoming" and int(t.start_week) == week:
			_start_cup(t)
	if mode == "player" and user_player != null and social != null:
		social.talk.deliver() # Coaches and teammates getting back to you.


func _match(a: int, b: int, kind: String, label: String) -> Dictionary:
	return {"a": a, "b": b, "sa": 0, "sb": 0, "winner": -1, "map": Maps.random_name(rng), "kind": kind, "label": label}


## All of this week's matches: league fixtures + bracket rounds due this week.
func all_week_matches() -> Array:
	var out: Array = week_matches.duplicate()
	for t in tournaments:
		if t.status == "running" and week - int(t.start_week) == int(t.round):
			out.append_array(t.rounds[t.round])
	return out


## Your next unplayed match this week, or {}.
func user_match_this_week() -> Dictionary:
	if mode == "player" and teamless:
		return {}
	var ui := team_index(user_team())
	for mt in all_week_matches():
		if mt.winner == -1 and (mt.a == ui or mt.b == ui):
			return mt
	return {}


## Returns "" when the week advanced, or "play_match" if you have a match pending.
func advance_week() -> String:
	if mode == "player" and retired:
		return "retired"
	if mode == "player" and free_agency:
		return "free_agency"
	if mode == "manager" and sacked:
		return "sacked"
	if not user_match_this_week().is_empty():
		return "play_match"
	for t in teams:
		t.last_rating = t.rating_exact() # The wire shows each team's change over the week.
		if _ai_controls(t) and t.roster.size() < MIN_ROSTER + 1:
			_refill_roster(t) # Short clubs (e.g. one a sacked manager left) sign free agents straight away.
	for mt in all_week_matches():
		if mt.winner == -1:
			_sim_match(mt)
	_apply_league_results()
	_wire_results()
	_advance_brackets()
	if mode == "manager":
		_run_training()
		_weekly_finances()
		_sponsor_market()
		_expire_incoming()
		_academy_week()
		_scout_week()
		_release_clauses()
		_board_week()
		_fans_week()
		if affiliate_income() > 0:
			_earn(affiliate_income(), "Affiliate (%s)" % affiliate().team_name, false)
		if week % 6 == 0:
			_refresh_staff_market()
		if money >= 1000000:
			_achieve("millionaire")
	else:
		_player_mode_week()
	_ai_finances()
	_ai_transfers()
	_weekly_form()
	if mode == "manager":
		_ai_bids_for_user()
		_player_messages()
	else:
		_apply_coach()
		_coach_week()
	week += 1
	if week > SEASON_WEEKS:
		_end_season()
	_begin_week()
	return ""


func window_open() -> bool:
	for w in WINDOWS:
		if week >= w[0] and week <= w[1]:
			return true
	return false


func window_text() -> String:
	if window_open():
		for w in WINDOWS:
			if week >= w[0] and week <= w[1]:
				return "Transfer window OPEN (until week %d)" % w[1]
	for w in WINDOWS:
		if week < w[0]:
			return "Transfer window closed (opens week %d)" % w[0]
	return "Transfer window closed (opens next season)"


# =============================================================================
# Matches
# =============================================================================

func team_index(t: TeamData) -> int:
	return teams.find(t)


func _win_prob(a: int, b: int) -> float:
	return 1.0 / (1.0 + exp(-(_match_strength(teams[a]) - _match_strength(teams[b])) / 14.0)) # Per round.


## Starting five's rating with form and today's mood (see roll_match_day).
func _match_strength(t: TeamData) -> float:
	var s := t.starters(5)
	if s.is_empty():
		return 0.0
	var total := 0.0
	for p in s:
		total += p.rating_exact() + p.match_mod
	var edge := diff("edge") if teams.find(t) == user_team_idx else 0.0
	return total / s.size() + edge


## Everyone has good and bad days. Sets each starter's match_mod (form + mood)
## for the next match; returns the players having a notably bad/great day.
func roll_match_day(t: TeamData) -> Dictionary:
	var out := {"bad": [], "great": []}
	var chem := chem_bonus(t)
	for p in t.roster:
		if p.is_user:
			p.match_mod = p.form * 0.6 + chem # You bring your own good and bad days.
			continue
		var day := rng.randfn(0.0, 1.3)
		var roll := rng.randf()
		if roll < 0.07:
			day = -rng.randf_range(4.0, 7.0)
			out.bad.append(p)
		elif roll < 0.12:
			day = rng.randf_range(3.5, 5.5)
			out.great.append(p)
		p.match_mod = p.form * 0.6 + day + chem
	return out


func sim_score(a: int, b: int) -> Array:
	var p := _win_prob(a, b)
	var s := [0, 0]
	var rounds := 0
	while s[0] < ROUNDS_TO_WIN and s[1] < ROUNDS_TO_WIN and rounds < MAX_ROUNDS:
		s[0 if rng.randf() < p else 1] += 1
		rounds += 1
	# Overtime: blocks of 4, first to 3 in the block; repeat if tied again.
	while s[0] == s[1]:
		var o := [0, 0]
		while o[0] < 3 and o[1] < 3 and o[0] + o[1] < 4:
			o[0 if rng.randf() < p else 1] += 1
			rounds += 1
		if o[0] == o[1]:
			s[0] += o[0]
			s[1] += o[1]
			continue
		s[0] += o[0]
		s[1] += o[1]
	return [s[0], s[1], rounds]


func _sim_match(mt: Dictionary) -> void:
	roll_match_day(teams[mt.a])
	roll_match_day(teams[mt.b])
	var r := sim_score(mt.a, mt.b)
	_sim_growth(teams[mt.a], teams[mt.b], r[0], r[1], r[2], String(mt.label))
	_sim_growth(teams[mt.b], teams[mt.a], r[1], r[0], r[2], String(mt.label))
	_set_result(mt, r[0], r[1])


func _set_result(mt: Dictionary, sa: int, sb: int) -> void:
	mt.sa = sa
	mt.sb = sb
	if sa == sb and mt.kind != "league":
		# Brackets need a winner: overtime.
		if rng.randf() < _win_prob(mt.a, mt.b):
			mt.sa += 1
		else:
			mt.sb += 1
	if mt.sa == mt.sb:
		mt.winner = -2 # League draw.
	else:
		mt.winner = mt.a if mt.sa > mt.sb else mt.b
	for side in [[mt.a, mt.sa > mt.sb], [mt.b, mt.sb > mt.sa]]:
		var tm: TeamData = teams[side[0]]
		if mt.sa == mt.sb:
			tm.streak = 0
		elif side[1]:
			tm.streak = maxi(1, tm.streak + 1)
			_record("Longest win streak", tm.streak, tm.team_name, LEAGUES[tm.league].short)
			if tm.streak >= 10 and side[0] == team_index(user_team()) and not teamless:
				_achieve("streak10")
		else:
			tm.streak = mini(-1, tm.streak - 1)
	_derby_result(mt)
	# Sponsors paying per win.
	if mode == "manager" and mt.winner == team_index(user_team()):
		for d in sponsors:
			if int(d.per_win) > 0:
				_earn(int(d.per_win), "Win bonus: %s" % d.brand)


func _sim_growth(team: TeamData, opp: TeamData, my_score: int, opp_score: int, rounds: int, label: String) -> void:
	var won := my_score > opp_score
	var avg := team.rating()
	for p in team.starters(5):
		if p.is_user:
			continue # The user player's development comes from their own matches.
		var r := clampf(rng.randfn(1.0 + (p.rating_exact() + p.match_mod - avg) / 40.0 + (0.08 if won else -0.08), 0.25), 0.3, 2.0)
		var kills := int(round(r * 0.68 * rounds))
		var deaths := int(round(rounds * clampf(0.72 - (r - 1.0) * 0.4, 0.15, 1.0)))
		p.matches_played += 1
		p.career_kills += kills
		p.career_deaths += deaths
		p.push_match_rating(r)
		Progression.apply_match(p, r, float(kills) / maxi(1, rounds), 0, rng)
		_log_match(p, opp, my_score, opp_score, kills, deaths, int(75.0 * r + rng.randf_range(-8.0, 8.0)), r, label)


func _log_match(p: PlayerData, opp: TeamData, my_score: int, opp_score: int, k: int, d: int, adr: int, r: float, label: String) -> void:
	_record("Most kills in a match", k, p.player_name, "vs %s, %s" % [opp.team_name if opp != null else "?", label])
	_record("Best match rating", snappedf(r, 0.01), p.player_name, "vs %s, %s" % [opp.team_name if opp != null else "?", label])
	p.log_match({"s": season, "w": week, "opp": opp.team_name if opp != null else "?", "label": label,
		"res": "W" if my_score > opp_score else ("L" if my_score < opp_score else "D"),
		"score": "%d-%d" % [my_score, opp_score], "k": k, "d": d, "adr": adr, "r": snappedf(r, 0.01),
		"mod": snappedf(p.match_mod, 0.1)})


## Your match result (watched/played in the match scene, or simulated).
func record_user_match(score: Array, rounds: int, player_stats: Dictionary, others: Dictionary = {}) -> void:
	var mt := user_match_this_week()
	if mt.is_empty():
		return
	var ui := team_index(user_team())
	var user_is_a: bool = mt.a == ui
	var report := {"opponent": teams[mt.b if user_is_a else mt.a].team_name, "label": mt.label, "score": [score[0], score[1]],
		"changes": {}, "rating": 1.0, "kills": 0, "deaths": 0, "player_changes": {}}
	var mine := teams[ui]
	var opp_team: TeamData = teams[mt.b if user_is_a else mt.a]
	for p: PlayerData in player_stats:
		var s: Dictionary = player_stats[p]
		var r := Progression.match_rating(s.kills, s.deaths, rounds, s.objectives, s.damage)
		var on_mine := mine.roster.has(p)
		_log_match(p, opp_team if on_mine else mine, score[0] if on_mine else score[1], score[1] if on_mine else score[0],
			int(s.kills), int(s.deaths), int(float(s.damage) / maxi(1, rounds)), r, String(mt.label))
		p.matches_played += 1
		p.career_kills += s.kills
		p.career_deaths += s.deaths
		p.push_match_rating(r)
		var ch := Progression.apply_match(p, r, float(s.kills) / maxi(1, rounds), s.objectives, rng)
		var total := 0.0
		for k in ch:
			total += float(ch[k])
		report.player_changes[p.player_name] = total
		if p.is_user:
			report.changes = ch
			report.rating = r
			report.kills = s.kills
			report.deaths = s.deaths
	_set_result(mt, score[0] if user_is_a else score[1], score[1] if user_is_a else score[0])
	var won: bool = mt.winner == ui
	var draw: bool = mt.winner == -2
	_news("%s %d-%d vs %s (%s)." % ["DRAW" if draw else ("WIN" if won else "LOSS"), score[0], score[1], report.opponent, mt.label])
	last_report = report
	if mode == "manager":
		_appearance_fees(player_stats.keys().filter(func(x: PlayerData) -> bool: return mine.roster.has(x)))
		trash_target = -1
		rattled_team = -1
	if won:
		_achieve("first_win")
		if maxi(score[0], score[1]) > ROUNDS_TO_WIN:
			_achieve("ot_win")
	if mode == "player":
		var ratings := {}
		for src: Dictionary in [player_stats, others]:
			for p: PlayerData in src:
				var st: Dictionary = src[p]
				ratings[p] = Progression.match_rating(st.kills, st.deaths, rounds, st.objectives, st.damage)
		_after_user_match(ratings, mine, opp_team, won)


## Five fit players needed to play (sick/injured don't count).
func can_field_team() -> bool:
	return user_team().available_count() >= MIN_ROSTER


## League forfeits are fined (scaled by league); cups charge nothing.
func forfeit_fee(mt: Dictionary) -> int:
	if mt.is_empty() or mt.kind != "league":
		return 0
	return int(LEAGUES[user_team().league].prize * 0.05 / 500.0) * 500


func forfeit_user_match() -> String:
	var mt := user_match_this_week()
	if mt.is_empty():
		return "No match to forfeit"
	var fee := forfeit_fee(mt)
	var ui := team_index(user_team())
	var user_is_a: bool = mt.a == ui
	var opp: TeamData = teams[mt.b if user_is_a else mt.a]
	if fee > 0:
		money -= fee
		_ledger("Forfeit fine: %s" % mt.label, -fee)
	_set_result(mt, 0 if user_is_a else ROUNDS_TO_WIN, ROUNDS_TO_WIN if user_is_a else 0)
	var ut := user_team()
	ut.reputation = maxf(0.0, ut.reputation - (1.5 if mt.kind == "league" else 0.5))
	for p in ut.roster:
		p.morale = maxf(0.0, p.morale - 3.0)
	_news("FORFEIT: you forfeited vs %s (%s)%s." % [opp.team_name, mt.label, (", fined $" + _fmt(fee)) if fee > 0 else ""])
	_wire("%s forfeit against %s" % [ut.team_name, opp.team_name], "bad")
	return ""


## Simulates your match with a full box score. Returns the results-screen data
## (see UI.results_overlay), or {} if there's no match this week.
func sim_user_match() -> Dictionary:
	var mt := user_match_this_week()
	if mt.is_empty() or (mode == "manager" and not can_field_team()):
		return {}
	prepare_match_day()
	var r := sim_score(mt.a, mt.b)
	var ui := team_index(user_team())
	var user_is_a: bool = mt.a == ui
	var mine: TeamData = teams[ui]
	var opp: TeamData = teams[mt.b if user_is_a else mt.a]
	var my_score: int = r[0] if user_is_a else r[1]
	var opp_score: int = r[1] if user_is_a else r[0]
	# Round-by-round kills, weighted by player quality (same model as Esc-sim in matches).
	var order: Array = []
	for i in my_score:
		order.append(0)
	for i in opp_score:
		order.append(1)
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = order[i]
		order[i] = order[j]
		order[j] = tmp
	var lineups := [mine.starters(5), opp.starters(5)]
	var box := sim_box_score(lineups, order)
	# Your side goes through the normal match recording (progression + report);
	# everyone else develops from their simulated line.
	var recorded := {}
	for p: PlayerData in lineups[0]:
		if mode == "manager" or p.is_user:
			recorded[p] = box[p]
	for t in 2:
		for p: PlayerData in lineups[t]:
			if not recorded.has(p) and not p.is_user:
				_box_growth(p, box[p], r[2])
				_log_match(p, mine if t == 1 else opp, opp_score if t == 1 else my_score, my_score if t == 1 else opp_score,
					int(box[p].kills), int(box[p].deaths), int(float(box[p].damage) / maxi(1, r[2])),
					Progression.match_rating(box[p].kills, box[p].deaths, r[2], box[p].objectives, box[p].damage), String(mt.label))
	var others := {}
	for t in 2:
		for p: PlayerData in lineups[t]:
			if not recorded.has(p):
				others[p] = box[p]
	record_user_match([my_score, opp_score], r[2], recorded, others)
	var changes: Dictionary = last_report.get("player_changes", {})
	var rows := [[], []]
	var mvp := ""
	var best := -1.0
	for t in 2:
		for p: PlayerData in lineups[t]:
			var s: Dictionary = box[p]
			var mr := Progression.match_rating(s.kills, s.deaths, r[2], s.objectives, s.damage)
			if mr > best:
				best = mr
				mvp = p.player_name
			rows[t].append({"name": p.player_name, "rating": p.rating(), "kills": s.kills, "deaths": s.deaths,
				"adr": int(s.damage / maxi(1, r[2])), "match_rating": mr, "is_user": p.is_user,
				"change": changes.get(p.player_name, null)})
		rows[t].sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.match_rating > b.match_rating)
	return {"teams": [mine, opp], "score": [my_score, opp_score], "rows": rows, "mvp": mvp,
		"label": "Simulated  -  " + String(mt.label), "perspective": true, "map": String(mt.get("map", ""))}


## Kills/deaths/damage for simulated rounds. order: winning lineup index per round.
## Winners usually trade 4-5 kills, losers 0-3; better players get more of them.
func sim_box_score(lineups: Array, order: Array) -> Dictionary:
	var box := {}
	for t in 2:
		for p: PlayerData in lineups[t]:
			box[p] = {"kills": 0, "deaths": 0, "damage": 0.0, "objectives": 0}
	for winner: int in order:
		var counts := [0, 0]
		counts[winner] = 5 if rng.randf() < 0.6 else 4
		counts[1 - winner] = rng.randi_range(0, 3)
		for t in 2:
			var victims: Array = (lineups[1 - t] as Array).duplicate()
			for i in mini(counts[t], victims.size()):
				var killer := _weighted_player(lineups[t])
				if killer == null:
					break
				var victim: PlayerData = victims.pop_at(rng.randi() % victims.size())
				box[killer].kills += 1
				box[killer].damage += 100.0 + rng.randf_range(0.0, 40.0)
				box[victim].deaths += 1
		for t in 2:
			for p: PlayerData in lineups[t]:
				box[p].damage += rng.randf_range(0.0, 30.0)
		if rng.randf() < 0.45:
			var planter := _weighted_player(lineups[0 if rng.randf() < 0.5 else 1])
			if planter != null:
				box[planter].objectives += 1
	return box


func _weighted_player(players: Array) -> PlayerData:
	if players.is_empty():
		return null
	var total := 0.0
	for p: PlayerData in players:
		total += pow(maxf(10.0, p.rating_exact() + p.match_mod), 2.0)
	var x := rng.randf() * total
	for p: PlayerData in players:
		x -= pow(maxf(10.0, p.rating_exact() + p.match_mod), 2.0)
		if x <= 0.0:
			return p
	return players[0]


func _box_growth(p: PlayerData, s: Dictionary, rounds: int) -> void:
	var r := Progression.match_rating(s.kills, s.deaths, rounds, s.objectives, s.damage)
	p.matches_played += 1
	p.career_kills += s.kills
	p.career_deaths += s.deaths
	p.push_match_rating(r)
	Progression.apply_match(p, r, float(s.kills) / maxi(1, rounds), s.objectives, rng)


func _apply_league_results() -> void:
	for mt in week_matches:
		var a: TeamData = teams[mt.a]
		var b: TeamData = teams[mt.b]
		a.round_diff += mt.sa - mt.sb
		b.round_diff += mt.sb - mt.sa
		if mt.winner == mt.a:
			a.wins += 1
			b.losses += 1
		elif mt.winner == mt.b:
			b.wins += 1
			a.losses += 1


## League table order: wins, then round difference.
func standings(l: int) -> Array[TeamData]:
	var out := league_teams(l)
	out.sort_custom(func(a: TeamData, b: TeamData) -> bool:
		if a.wins != b.wins:
			return a.wins > b.wins
		return a.round_diff > b.round_diff)
	return out


# =============================================================================
# Brackets (cups + league playoffs)
# =============================================================================

func tier_info(t: Dictionary) -> Dictionary:
	return TIERS.get(t.tier, TIERS.Open)


func can_enroll(t: Dictionary) -> String:
	if mode != "manager":
		return "Your team decides"
	if t.kind != "cup":
		return "League playoffs"
	if t.status != "upcoming":
		return "Already started"
	if t.user_enrolled:
		return "Enrolled"
	if week >= int(t.start_week):
		return "Registration closed"
	if week < int(t.start_week) - 3:
		return "Registration opens week %d" % (int(t.start_week) - 3)
	var s0 := int(t.start_week)
	for o in tournaments:
		if o != t and o.kind == "cup" and o.user_enrolled and o.status != "done":
			var s1 := int(o.start_week)
			if s0 <= s1 + 3 and s1 <= s0 + 3:
				return "Clashes with %s" % o.name
	var info := tier_info(t)
	var ut := user_team()
	if ut.league > int(info.max_league) and ut.reputation < float(info.min_rep) + 15.0:
		return "%s league or higher (or rep %d)" % [LEAGUES[int(info.max_league)].name.split(" ")[0], int(info.min_rep) + 15]
	if ut.reputation < float(info.min_rep):
		return "Needs reputation %d" % int(info.min_rep)
	if money < int(info.fee):
		return "Can't afford entry"
	if ut.roster.size() < MIN_ROSTER:
		return "Need %d players" % MIN_ROSTER
	return ""


func enroll(t: Dictionary) -> bool:
	if can_enroll(t) != "":
		return false
	var fee: int = tier_info(t).fee
	money -= fee
	t.user_enrolled = true
	_ledger("Entry fee: %s" % t.name, -fee)
	_news("You registered for %s." % t.name)
	return true


## Player mode: the AI-run club decides which cups to enter (and you go along).
func _auto_enroll_user_team() -> void:
	if teamless:
		return
	var ut := user_team()
	for t in tournaments:
		if t.kind == "cup" and t.status == "upcoming" and int(t.start_week) == week + 1 and not t.user_enrolled:
			var info := tier_info(t)
			if ut.league <= int(info.max_league) and ut.reputation >= float(info.min_rep) and rng.randf() < 0.75:
				t.user_enrolled = true
				_news("%s entered %s." % [ut.team_name, t.name])


func _eligible_for(t: Dictionary, i: int) -> bool:
	var info := tier_info(t)
	var tm := teams[i]
	return tm.roster.size() >= MIN_ROSTER and (tm.league <= int(info.max_league) or tm.reputation >= float(info.min_rep) + 15.0) \
		and tm.reputation >= float(info.min_rep) * 0.8


func _start_cup(t: Dictionary) -> void:
	var field: Array = []
	var ui := team_index(user_team())
	if t.user_enrolled:
		field.append(ui)
	var candidates: Array = []
	for i in teams.size():
		if i != ui and _eligible_for(t, i):
			candidates.append(i)
	candidates.sort_custom(func(a: int, b: int) -> bool: return _seed_score(a) > _seed_score(b))
	if t.tier == "Open":
		candidates.shuffle()
	for i in candidates:
		if field.size() >= CUP_SIZE:
			break
		field.append(i)
	for i in teams.size():
		if field.size() >= CUP_SIZE:
			break
		if not field.has(i) and i != ui:
			field.append(i)
	_seed_bracket(t, field)
	_news("%s begins (%d teams): %s are top seed." % [t.name, field.size(), teams[t.teams[0]].team_name])


func _start_playoffs() -> void:
	for l in LEAGUES.size():
		_table_titles(l, standings(l), season)
		var b := _new_bracket("%s Playoffs S%d" % [LEAGUES[l].name, season], "playoff", "Open", PLAYOFF_START, PLAYOFF_SIZE, l)
		var field: Array = []
		for tm in standings(l).slice(0, PLAYOFF_SIZE):
			field.append(team_index(tm))
		if field.has(team_index(user_team())):
			b.user_enrolled = true
			if mode == "manager":
				_sponsor_goal("playoffs")
		_seed_bracket(b, field, false)
		tournaments.append(b)
	_news("League playoffs begin: the top %d of every league fight for the title." % PLAYOFF_SIZE)


static func stage_name(size: int, round_i: int) -> String:
	match size >> (round_i + 1):
		1: return "Final"
		2: return "Semi-final"
		4: return "Quarter-final"
		8: return "Round of 16"
	return "Round %d" % (round_i + 1)


func _seed_bracket(t: Dictionary, field: Array, resort: bool = true) -> void:
	if resort:
		field.sort_custom(func(a: int, b: int) -> bool: return _seed_score(a) > _seed_score(b))
	var size: int = field.size()
	var first: Array = []
	for k in size / 2:
		first.append(_match(field[k], field[size - 1 - k], t.kind, "%s - %s" % [t.name, stage_name(size, 0)]))
	t.teams = field
	t.rounds = [first]
	t.round = 0
	t.status = "running"


func _seed_score(i: int) -> float:
	return teams[i].points + teams[i].rating() * 5.0 - teams[i].league * 40.0


func _advance_brackets() -> void:
	for t in tournaments:
		if t.status != "running" or week - int(t.start_week) != int(t.round):
			continue
		var size: int = t.size
		var place := (size >> int(t.round)) / 2 + 1
		for mt in t.rounds[t.round]:
			t.placements[mt.b if mt.winner == mt.a else mt.a] = place
		var winners: Array = []
		for mt in t.rounds[t.round]:
			winners.append(mt.winner)
		if winners.size() == 1:
			t.placements[winners[0]] = 1
			t.status = "done"
			_finish_bracket(t)
		else:
			var next: Array = []
			for k in range(0, winners.size(), 2):
				next.append(_match(winners[k], winners[k + 1], t.kind, "%s - %s" % [t.name, stage_name(size, int(t.round) + 1)]))
			t.rounds.append(next)
			t.round = int(t.round) + 1


func _finish_bracket(t: Dictionary) -> void:
	var champ_idx := _team_with_place(t, 1)
	var champ: TeamData = teams[champ_idx]
	champ.titles += 1
	for p in champ.starters(5):
		p.titles += 1
	var ui := -1 if teamless else team_index(user_team())
	for idx in t.placements:
		var place: int = t.placements[idx]
		var team: TeamData = teams[idx]
		var pts := 0
		var prize := 0
		if t.kind == "cup":
			var info := tier_info(t)
			pts = int(PLACE_POINTS[place] * float(info.mult))
			prize = int(float(info.pool) * PRIZE_SHARE[place])
			team.reputation = clampf(team.reputation + _rep_gain(place) * sqrt(float(info.mult)), 0.0, 100.0)
		else:
			var lg: Dictionary = LEAGUES[int(t.league)]
			pts = int(PLACE_POINTS[place] * float(lg.points))
			prize = int(float(lg.prize) * PLAYOFF_SHARE.get(place, 0.0))
			team.reputation = clampf(team.reputation + _rep_gain(place) * float(lg.points) * 0.6, 0.0, 100.0)
		team.points += pts
		if place == 1:
			var trank := (90 - int(t.league) * 15) if t.kind != "cup" else clampi(int(45.0 + 15.0 * float(tier_info(t).mult)), 45, 88)
			_honour_team(team, "%s Champion" % _plain_event(String(t.name)), trank)
		elif place == 2:
			_honour_team(team, "%s Finalist" % _plain_event(String(t.name)), 25)
		elif place == 3:
			_honour_team(team, "%s Semi Finalist" % _plain_event(String(t.name)), 20)
		elif place == 5:
			_honour_team(team, "%s Quarter Finalist" % _plain_event(String(t.name)), 10)
		if idx == ui and mode == "manager":
			if prize > 0:
				_earn(prize, "Prize: %s (%s)" % [t.name, _place_name(place)])
			if place == 1:
				_sponsor_goal("trophy")
		elif prize > 0:
			team.money += prize
		if idx == ui and mode == "player" and place <= 2 and user_player != null:
			trophies.append({"s": season, "name": String(t.name), "place": place, "team": team.team_name})
			if place == 1:
				_tl().titles = int(_tl().titles) + 1
				_gain_fame(int(2500 * _lmult(team)))
				_news("TROPHY: you won %s with %s!" % [t.name, team.team_name])
				_check_perks()
		if idx == ui:
			_news("Your team finished %s at %s: +%d ranking points%s." % [_place_name(place), t.name, pts,
				(", $" + _fmt(prize) + " prize") if prize > 0 and mode == "manager" else ""])
	champions.append({"s": season, "name": base_cup_name(String(t.name)), "team": champ.team_name})
	if champ_idx == ui:
		_achieve("silverware")
		if mode == "manager":
			_fans(int(club_fans * 0.15))
		if String(t.tier) == "Major":
			_achieve("major")
		if difficulty == "Hardcore":
			_achieve("hardcore")
	_news("%s WIN %s!" % [champ.team_name.to_upper(), t.name])
	_wire("%s WIN %s" % [champ.team_name.to_upper(), String(t.name).to_upper()], "good")


func _team_with_place(t: Dictionary, place: int) -> int:
	for idx in t.placements:
		if t.placements[idx] == place:
			return idx
	return -1


func _rep_gain(place: int) -> float:
	match place:
		1: return 8.0
		2: return 5.0
		3: return 3.0
		5: return 1.0
	return -0.5


static func _place_name(place: int) -> String:
	match place:
		1: return "1st"
		2: return "2nd"
		3: return "3rd-4th"
		5: return "5th-8th"
	return "9th-16th"


# =============================================================================
# Manager: finances, training, lineup, contracts, transfers
# =============================================================================

## Weekly money from signed sponsorship deals.
func sponsor_income() -> int:
	var total := 0
	for d in sponsors:
		total += int(d.weekly)
	return int(total * diff("income"))


## League share (broadcast/prize fund distribution) + merchandise.
func league_revenue() -> int:
	return int((LEAGUES[user_team().league].sponsor * 0.25 + 1000) * diff("income"))


func merch_income() -> int:
	if mode == "manager" and club_fans > 0:
		return int(club_fans * 0.12 * (1.0 + 0.5 * merch_level) * diff("income"))
	return int(user_team().reputation * 60.0 * diff("income"))


func loan_payments() -> int:
	var total := 0
	for l in loans:
		if l.kind == "loan":
			total += int(l.weekly)
	return total


## Gross weekly income before investor shares.
func weekly_income() -> int:
	return sponsor_income() + league_revenue() + merch_income()


func stake_share() -> float:
	var share := 0.0
	for l in loans:
		if l.kind == "stake":
			share += float(l.share)
	return minf(share, 0.6)


## Expected weekly net (income - investor share - wages - training - loans).
func weekly_net() -> int:
	var inc := weekly_income()
	return inc - int(inc * stake_share()) - payroll() - training_cost() - loan_payments()


## Credit income: investors with a stake take their cut.
func _earn(amount: int, text: String, share: bool = true) -> void:
	money += amount
	_ledger(text, amount)
	if share:
		_stake_cut(amount)


func _stake_cut(amount: int) -> void:
	for l in loans:
		if l.kind == "stake" and amount > 0:
			var cut := int(amount * float(l.share))
			if cut > 0:
				money -= cut
				_ledger("%s share (%d%%)" % [l.lender, int(float(l.share) * 100.0)], -cut)


func payroll() -> int:
	var total := staff_wages() if mode == "manager" else 0
	for p in user_team().roster:
		total += p.loan_fee if p.loan_kind == "in" else p.salary
	return total


func _weekly_finances() -> void:
	if sponsor_income() > 0:
		_earn(sponsor_income(), "Sponsors", false)
	_earn(league_revenue(), "League revenue share", false)
	if merch_income() > 0:
		_earn(merch_income(), "Merchandise", false)
	_stake_cut(weekly_income()) # One investor line for the week's income.
	var pay := payroll()
	money -= pay
	_ledger("Salaries and staff", -pay)
	var upkeep := facility_upkeep()
	if upkeep > 0:
		money -= upkeep
		_ledger("Facility upkeep", -upkeep)
	for l in loans.duplicate():
		l.weeks_left = int(l.weeks_left) - 1
		if l.kind == "loan":
			money -= int(l.weekly)
			_ledger("Loan repayment: %s" % l.lender, -int(l.weekly))
		if int(l.weeks_left) <= 0:
			loans.erase(l)
			_news("%s with %s has ended." % ["Loan" if l.kind == "loan" else "Investor stake", l.lender])
	_debt_check()


## Running out of money has consequences: reputation, then creditors step in.
func _debt_check() -> void:
	if money >= 0:
		debt_weeks = 0
		return
	debt_weeks += 1
	var ut := user_team()
	ut.reputation = maxf(0.0, ut.reputation - 0.8)
	for p in ut.roster:
		p.morale = maxf(0.0, p.morale - 3.0) # Late wages.
	if debt_weeks == 1:
		_news("WARNING: you're $%s in debt. Wages are late and players are unhappy. Take a loan or sell." % _fmt(-money))
	elif debt_weeks == 2:
		_news("WARNING: second week in debt ($%s). Creditors will force a sale next week." % _fmt(-money))
	elif debt_weeks >= 3:
		var sold := _forced_sale()
		if money < 0 and debt_weeks >= 4:
			var amount := int(-money * 1.1 / 1000.0 + 1) * 1000
			var lender: Dictionary = LENDERS[LENDERS.size() - 1]
			_add_loan(lender, amount)
			_news("WARNING: administrators forced a $%s %s loan on you to cover the debt." % [_fmt(amount), lender.name])
		elif sold == "":
			_news("WARNING: still $%s in debt and nobody to sell. Reputation is suffering." % _fmt(-money))


## Creditors sell the most valuable player (cut-price, any time of year).
func _forced_sale() -> String:
	var ut := user_team()
	if ut.roster.size() <= MIN_ROSTER:
		return ""
	var best: PlayerData = null
	for p in ut.roster:
		if best == null or p.market_value() > best.market_value():
			best = p
	var price := int(best.market_value() * 0.6 / 1000.0) * 1000
	var buyer: TeamData = null
	for t in teams:
		if t != ut and t.money >= price and (buyer == null or t.money > buyer.money):
			buyer = t
	if buyer == null:
		return ""
	_move_player(best, ut, buyer)
	buyer.money -= price
	_trim_roster(buyer, best)
	money += price
	_ledger("Forced sale: %s to %s" % [best.player_name, buyer.team_name], price)
	_news("WARNING: creditors sold %s to %s for $%s (60%% of value)." % [best.player_name, buyer.team_name, _fmt(price)])
	_wire("FIRE SALE: debt-ridden %s forced to sell %s to %s." % [ut.team_name, best.player_name, buyer.team_name], "bad")
	return best.player_name


# --- Sponsorship ---------------------------------------------------------------

## A club's commercial value per week: what all its deals together are worth.
func commercial_value() -> float:
	var lg: Dictionary = LEAGUES[user_team().league]
	var rank_bonus := clampf((40.0 - world_rank(user_team())) / 40.0, 0.0, 1.0) * 0.4
	return (lg.sponsor + 1500.0 + user_team().reputation * 300.0) * (1.0 + rank_bonus)


## style: Steady (all weekly), Performance (per-win), Signing (cash up front), Goal (bonus for a target).
func _make_sponsor_offer(slot: String, style: String = "") -> Dictionary:
	if style == "":
		style = ["Steady", "Performance", "Signing", "Goal"][rng.randi() % 4]
	var base := commercial_value() * float(SPONSOR_SLOTS[slot]) * rng.randf_range(0.8, 1.2)
	var taken := {}
	for d in sponsors:
		taken[d.brand] = true
	for d in sponsor_offers:
		taken[d.brand] = true
	var brand: String = SPONSOR_BRANDS[rng.randi() % SPONSOR_BRANDS.size()]
	for i in 10:
		if not taken.has(brand):
			break
		brand = SPONSOR_BRANDS[rng.randi() % SPONSOR_BRANDS.size()]
	var o := {"brand": brand, "slot": slot, "style": style, "weekly": int(base), "per_win": 0, "bonus": 0,
		"goal": "", "goal_bonus": 0, "weeks": rng.randi_range(3, 8) * 4, "expires": rng.randi_range(2, 4)}
	match style:
		"Performance":
			o.weekly = int(base * 0.55)
			o.per_win = int(base * 1.6)
		"Signing":
			o.weekly = int(base * 0.7)
			o.bonus = int(base * 10.0)
		"Goal":
			o.weekly = int(base * 0.75)
			o.goal = "playoffs" if rng.randf() < 0.6 else "trophy"
			o.goal_bonus = int(base * (14.0 if o.goal == "playoffs" else 22.0))
	for k in ["weekly", "per_win", "bonus", "goal_bonus"]:
		o[k] = int(round(float(o[k]) / 100.0)) * 100
	return o


func _sign_sponsor(o: Dictionary) -> void:
	var d := o.duplicate()
	d.erase("expires")
	sponsors.append(d)
	if int(o.bonus) > 0:
		_earn(int(o.bonus), "Signing bonus: %s" % o.brand)


func sponsor_in_slot(slot: String) -> Dictionary:
	for d in sponsors:
		if d.slot == slot:
			return d
	return {}


func accept_sponsor(i: int) -> String:
	if i < 0 or i >= sponsor_offers.size():
		return "Offer gone"
	var o: Dictionary = sponsor_offers[i]
	var cur := sponsor_in_slot(String(o.slot))
	if not cur.is_empty():
		return "%s slot is taken by %s (end that deal first)" % [o.slot, cur.brand]
	sponsor_offers.remove_at(i)
	_sign_sponsor(o)
	_news("SPONSOR: %s are your new %s sponsor (%s/wk for %d weeks)." % [o.brand, String(o.slot).to_lower(), UI_money(int(o.weekly)), int(o.weeks)])
	_wire("%s sign %s as %s sponsor." % [user_team().team_name, o.brand, String(o.slot).to_lower()], "deal")
	return ""


## Declining: they may come back with a better offer (once), or pull out.
func decline_sponsor(i: int) -> String:
	if i < 0 or i >= sponsor_offers.size():
		return ""
	var o: Dictionary = sponsor_offers[i]
	var roll := rng.randf()
	if not bool(o.get("countered", false)) and roll < 0.4:
		var bump := rng.randf_range(1.12, 1.3)
		for k in ["weekly", "per_win", "bonus", "goal_bonus"]:
			o[k] = int(round(float(o[k]) * bump / 100.0)) * 100
		o.countered = true
		o.expires = 2
		_news("SPONSOR: %s came back with an improved offer (%s/wk)." % [o.brand, UI_money(int(o.weekly))])
		return "%s came back with a better offer: %s/wk." % [o.brand, UI_money(int(o.weekly))]
	sponsor_offers.remove_at(i)
	if roll < 0.75:
		_news("SPONSOR: %s pulled out of talks." % o.brand)
		return "%s pulled out." % o.brand
	return "Declined %s." % o.brand


## Ending a deal early costs 4 weeks of its fee.
func termination_fee(d: Dictionary) -> int:
	return int(d.weekly) * 4


func end_sponsor(d: Dictionary) -> String:
	var fee := termination_fee(d)
	if money < fee:
		return "Can't afford the $%s exit fee" % _fmt(fee)
	money -= fee
	sponsors.erase(d)
	_ledger("Ended %s deal early" % d.brand, -fee)
	_news("You ended the %s sponsorship early." % d.brand)
	return ""


func _sponsor_goal(goal: String) -> void:
	for d in sponsors:
		if String(d.goal) == goal and int(d.goal_bonus) > 0:
			_earn(int(d.goal_bonus), "Goal bonus: %s (%s)" % [d.brand, goal])
			_news("SPONSOR: %s paid a $%s bonus for %s." % [d.brand, _fmt(int(d.goal_bonus)),
				"reaching the playoffs" if goal == "playoffs" else "winning a trophy"])
			d.goal_bonus = 0


## Weekly: deals tick down, offers expire, new offers arrive (more for winners).
func _sponsor_market() -> void:
	for d in sponsors.duplicate():
		d.weeks = int(d.weeks) - 1
		if int(d.weeks) == 4 and not bool(d.get("ext_offered", false)):
			d.ext_offered = true
			var nw := int(round(commercial_value() * float(SPONSOR_SLOTS[d.slot]) * rng.randf_range(0.9, 1.25) / 100.0)) * 100
			var wk := rng.randi_range(6, 10) * 4
			_msg("sponsor", "%s want to extend" % d.brand,
				"Your %s deal with %s ends in 4 weeks. They offer %s more weeks at %s/wk (now %s/wk)." % [String(d.slot).to_lower(), d.brand, wk, UI_money(nw), UI_money(int(d.weekly))],
				[["Extend (%s/wk, %d wks)" % [UI_money(nw), wk], "sponsor_extend"], ["Let it run out", "sponsor_no"]], 0,
				{"brand": d.brand, "weekly": nw, "weeks": wk})
		if int(d.weeks) <= 0:
			sponsors.erase(d)
			_news("SPONSOR: your %s deal with %s has ended. Find a new %s sponsor." % [String(d.slot).to_lower(), d.brand, String(d.slot).to_lower()])
	for o in sponsor_offers.duplicate():
		o.expires = int(o.expires) - 1
		if int(o.expires) <= 0:
			sponsor_offers.erase(o)
	var chance := 0.35 + clampf(user_team().streak * 0.08, -0.15, 0.3)
	if sponsor_offers.size() < 4 and rng.randf() < chance:
		var slots := SPONSOR_SLOTS.keys()
		# Mostly for empty slots, sometimes a rival bid for a filled one.
		var open: Array = slots.filter(func(sl: String) -> bool: return sponsor_in_slot(sl).is_empty())
		var slot: String = open[rng.randi() % open.size()] if not open.is_empty() and rng.randf() < 0.75 else slots[rng.randi() % slots.size()]
		var o := _make_sponsor_offer(slot)
		sponsor_offers.append(o)
		_news("SPONSOR: %s offer a %s deal (%s/wk). See Finances." % [o.brand, slot.to_lower(), UI_money(int(o.weekly))])


static func UI_money(n: int) -> String:
	return ("-$" if n < 0 else "$") + _fmt(absi(n))


# --- Loans and investors ---------------------------------------------------------

## What a lender will offer you right now: "" if eligible, else the reason.
func lender_block(l: Dictionary) -> String:
	for x in loans:
		if x.lender == l.name:
			return "Already have a deal with them"
	if user_team().reputation < float(l.min_rep):
		return "Needs reputation %d" % int(l.min_rep)
	if l.kind == "stake" and stake_share() + float(l.share) > 0.6:
		return "Investors already own too much"
	return ""


func lender_limit(l: Dictionary) -> int:
	var lg: Dictionary = LEAGUES[user_team().league]
	var credit := 1.0 if debt_weeks == 0 else 0.6
	return int(lg.budget * float(l.limit) * credit / 5000.0) * 5000


func loan_terms(l: Dictionary, amount: int) -> Dictionary:
	if l.kind == "stake":
		return {"weekly": 0, "total": 0, "text": "%d%% of all income for %d weeks" % [int(float(l.share) * 100.0), int(l.weeks)]}
	var total := int(amount * (1.0 + float(l.rate)))
	var weekly := int(ceil(float(total) / float(l.weeks)))
	return {"weekly": weekly, "total": total, "text": "%s/wk for %d weeks (repay %s)" % [UI_money(weekly), int(l.weeks), UI_money(total)]}


func take_loan(li: int, amount: int) -> String:
	var l: Dictionary = LENDERS[li]
	var why := lender_block(l)
	if why != "":
		return why
	if amount <= 0 or amount > lender_limit(l):
		return "They won't lend that much"
	_add_loan(l, amount)
	_news("FINANCE: %s %s $%s." % [l.name, "lent you" if l.kind == "loan" else "invested", _fmt(amount)])
	_wire("%s raise $%s from %s." % [user_team().team_name, _fmt(amount), l.name], "deal")
	return ""


func _add_loan(l: Dictionary, amount: int) -> void:
	var terms := loan_terms(l, amount)
	loans.append({"lender": l.name, "kind": l.kind, "principal": amount, "weekly": terms.weekly,
		"weeks": int(l.weeks), "weeks_left": int(l.weeks), "share": float(l.get("share", 0.0)), "rate": float(l.get("rate", 0.0))})
	money += amount
	_ledger("%s from %s" % ["Loan" if l.kind == "loan" else "Investment", l.name], amount)


## Pay off a loan early: the remaining principal (no further interest) + 3%.
## Buying out an investor costs 1.5x what they put in, scaled by time left.
func payoff_cost(x: Dictionary) -> int:
	var left := float(x.weeks_left) / float(x.weeks)
	if x.kind == "loan":
		return int(float(x.principal) * left * 1.03)
	return int(float(x.principal) * 1.5 * left)


func repay_loan(x: Dictionary) -> String:
	var cost := payoff_cost(x)
	if money < cost:
		return "Need $%s to pay it off" % _fmt(cost)
	money -= cost
	loans.erase(x)
	_ledger("Paid off %s" % x.lender, -cost)
	_news("FINANCE: you paid off %s." % x.lender)
	return ""


func training_cost() -> int:
	return int(TRAINING_INTENSITY[training.intensity].cost)


func facility_upgrade_cost() -> int:
	return 60000 * facility if facility < 5 else -1


func upgrade_facility() -> bool:
	var cost := facility_upgrade_cost()
	if cost < 0 or money < cost:
		return false
	money -= cost
	facility += 1
	_ledger("Training facility level %d" % facility, -cost)
	_news("Training facility upgraded to level %d." % facility)
	return true


func _run_training() -> void:
	last_training.clear()
	var it: Dictionary = TRAINING_INTENSITY[training.intensity]
	var mult: float = it.mult * (1.0 + 0.15 * (facility - 1)) * (1.0 + 0.08 * staff_stars("Head Coach"))
	if it.cost > 0:
		money -= int(it.cost)
		_ledger("Training (%s, %s)" % [training.focus, training.intensity], -int(it.cost))
	if mult <= 0.0:
		return
	var keys: Array = TRAINING_FOCUS[training.focus]
	var spread := 3.0 / keys.size()
	for p in user_team().roster:
		var before := p.rating_exact()
		var age_f := maxf(0.15, Progression.age_factor(p.age) + 0.3)
		var room := maxf(0.1, clampf((p.potential - p.rating_exact()) / 8.0, 0.0, 1.0))
		for k: String in keys:
			p.set_stat(k, p.stat(k) + rng.randfn(0.18, 0.12) * mult * age_f * room * spread)
		last_training[p.player_name] = p.rating_exact() - before


## Move a player up/down the lineup (top 5 start).
func move_in_lineup(p: PlayerData, delta: int) -> void:
	var r := user_team().roster
	var i := r.find(p)
	var j := clampi(i + delta, 0, r.size() - 1)
	if i < 0 or i == j:
		return
	r[i] = r[j]
	r[j] = p


func extension_cost(p: PlayerData) -> int:
	return PlayerData.salary_for_rating(p.rating_exact()) * 4


## Extend a contract by one season (signing bonus = 4 weeks of the new wage).
func extend_contract(p: PlayerData, terms: Dictionary = {}) -> String:
	if p.contract_until >= season + 3:
		return "Already signed long-term"
	var cost := extension_cost(p)
	if money < cost:
		return "Can't afford the $%s bonus" % _fmt(cost)
	money -= cost
	_pay_loyalty(p)
	p.contract_until += 1
	_apply_terms(p, terms)
	_ledger("Extended %s to S%d" % [p.player_name, p.contract_until], -cost)
	return ""


func buyout_price(p: PlayerData) -> int:
	var owner := owner_of(p)
	var mult := 1.3
	if owner != null and owner.starters(5).has(p):
		mult = 1.6
	# Players in the last year of their deal are cheaper.
	if p.contract_until <= season:
		mult *= 0.7
	return int(round(p.market_value() * mult / 1000.0)) * 1000


func signing_fee(p: PlayerData) -> int:
	return int(round(p.market_value() * 0.25 / 500.0)) * 500


func owner_of(p: PlayerData) -> TeamData:
	for t in teams:
		if t.roster.has(p):
			return t
	return null


## Free agents sign in windows only, unless you can't field a team.
func can_sign_now() -> bool:
	return window_open() or user_team().available_count() < MIN_ROSTER


func sign_free_agent(p: PlayerData, terms: Dictionary = {}) -> String:
	if not can_sign_now():
		return window_text()
	if user_team().roster.size() >= MAX_ROSTER:
		return "Roster full (%d)" % MAX_ROSTER
	var why := p.refuses(user_team(), 0.5 if int(terms.get("loyalty", 0)) > 0 else 1.0)
	if why != "":
		return why
	var fee := signing_fee(p)
	if money < fee:
		return "Can't afford the $%s signing fee" % _fmt(fee)
	money -= fee
	free_agents.erase(p)
	_apply_terms(p, terms)
	p.contract_until = season + 1
	p.morale = clampf(p.morale + 15.0, 0.0, 100.0)
	p.joined = stamp()
	user_team().roster.append(p)
	_ledger("Signed %s" % p.player_name, -fee)
	_news("You signed free agent %s (%s, %d) through season %d." % [p.player_name, p.role, p.rating(), p.contract_until])
	return ""


## Value a club puts on a player offered to it in a deal.
func swap_value(sw: PlayerData, to: TeamData) -> int:
	var weakest: PlayerData = null
	if not to.roster.is_empty():
		weakest = to.starters(5)[to.starters(5).size() - 1]
	var useful := weakest == null or sw.rating_exact() >= weakest.rating_exact() - 3.0
	return int(sw.market_value() * (0.9 if useful else 0.45))


## Bid for another club's player: cash (default: their asking price) plus any
## of your players. Clubs weigh the total against the asking price.
func make_offer(p: PlayerData, cash: int = -1, swaps: Array = []) -> String:
	if not window_open():
		return window_text()
	var owner := owner_of(p)
	var ut := user_team()
	if owner == null or owner == ut:
		return "Not available"
	var why := p.refuses(ut)
	if why != "":
		return why
	if ut.roster.size() + 1 - swaps.size() > MAX_ROSTER:
		return "Roster full (%d)" % MAX_ROSTER
	if ut.roster.size() + 1 - swaps.size() < MIN_ROSTER:
		return "You'd have fewer than %d players" % MIN_ROSTER
	for sw: PlayerData in swaps:
		var sr := sw.refuses(owner)
		if sr != "":
			return sr
	if offers_made.has(p.uid):
		return "Already bid this week"
	var price := buyout_price(p)
	if cash < 0:
		cash = price
	if money < cash:
		return "Can't afford $%s" % _fmt(cash)
	var value := cash
	for sw: PlayerData in swaps:
		value += swap_value(sw, owner)
	var ratio := float(value) / maxf(1.0, float(price))
	offers_made[p.uid] = week
	if ratio < 0.6:
		_news("%s laughed off your bid for %s." % [owner.team_name, p.player_name])
		return "%s found the bid insulting" % owner.team_name
	var chance := 0.75 - maxf(0.0, owner.reputation - user_team().reputation) / 150.0 + (ratio - 1.0) * 1.2
	if owner.starters(5).has(p):
		chance -= 0.2
	if owner.league < user_team().league:
		chance -= 0.15 * (user_team().league - owner.league)
	if owner.money < 0:
		chance += 0.3 # Broke clubs sell.
	var what := UI_money(cash)
	for sw: PlayerData in swaps:
		what += " + " + sw.player_name
	if rng.randf() > clampf(chance, 0.05, 0.95):
		_news("%s rejected your bid for %s (%s)." % [owner.team_name, p.player_name, what])
		return "%s rejected the bid" % owner.team_name
	money -= cash
	owner.money += cash
	_move_player(p, owner, ut)
	for sw: PlayerData in swaps:
		_move_player(sw, ut, owner)
		former_players[sw.uid] = true
	_trim_roster(owner)
	_refill_roster(owner)
	_wire("TRANSFER: %s sign %s from %s (%s)." % [ut.team_name, p.player_name, owner.team_name, what], "deal")
	if cash > 0:
		_ledger("Bought %s from %s" % [p.player_name, owner.team_name], -cash)
		_note_transfer(p, owner, ut, cash)
	_news("You signed %s from %s for %s." % [p.player_name, owner.team_name, what])
	return ""


## Transfer list: clubs bid over the coming weeks (in windows).
func set_listed(p: PlayerData, on: bool) -> void:
	if p.listed == on:
		return
	p.listed = on
	if on:
		p.morale = clampf(p.morale + (12.0 if p.morale < 40.0 else -8.0), 0.0, 100.0)
		_news("You transfer-listed %s.%s" % [p.player_name, "" if window_open() else " Bids come in when the window opens."])
	else:
		p.morale = clampf(p.morale + (-10.0 if p.morale < 40.0 else 4.0), 0.0, 100.0)
		_news("You took %s off the transfer list." % p.player_name)


## Drag-and-drop lineup ordering.
func move_to_index(p: PlayerData, idx: int) -> void:
	var r := user_team().roster
	var i := r.find(p)
	if i < 0:
		return
	r.remove_at(i)
	r.insert(clampi(idx, 0, r.size()), p)


func sell_player(p: PlayerData) -> String:
	if not window_open():
		return window_text()
	if user_team().roster.size() <= MIN_ROSTER:
		return "Need at least %d players" % MIN_ROSTER
	var buyer: TeamData = null
	var best := -INF
	var price := int(round(p.market_value() * 0.85 / 1000.0)) * 1000
	for t in teams:
		if t == user_team() or t.money < price:
			continue
		var weakest: PlayerData = t.starters(5)[t.starters(5).size() - 1]
		var interest := p.rating_exact() - weakest.rating_exact() + rng.randf_range(-3, 3)
		if interest > best:
			best = interest
			buyer = t
	if buyer == null:
		return "No club can afford $%s right now" % _fmt(price)
	user_team().roster.erase(p)
	buyer.roster.append(p)
	p.joined = stamp()
	buyer.money -= price
	_trim_roster(buyer, p)
	money += price
	_note_transfer(p, user_team(), buyer, price)
	_ledger("Sold %s to %s" % [p.player_name, buyer.team_name], price)
	_news("You sold %s to %s for $%s." % [p.player_name, buyer.team_name, _fmt(price)])
	return ""


## Moves a player between clubs. The player object (name, stats, history)
## travels with them.
func _move_player(p: PlayerData, from: TeamData, to: TeamData) -> void:
	from.roster.erase(p)
	to.roster.append(p)
	p.joined = stamp()
	p.salary = PlayerData.salary_for_rating(p.rating_exact())
	p.contract_until = maxi(p.contract_until, season + 1)
	p.morale = clampf(p.morale + 10.0, 0.0, 100.0)
	p.listed = false
	p.promise_until = 0
	p.bench_weeks = 0
	if from == user_team() and mode == "manager":
		former_players[p.uid] = true
	for o in incoming.duplicate():
		if int(o.player) == p.uid or int(o.swap) == p.uid:
			incoming.erase(o)
	from.sort_roster()
	to.sort_roster()


# --- Clubs bidding for your players ------------------------------------------------

## In windows, AI clubs bid for your players: cash, or one of theirs plus cash.
func _ai_bids_for_user() -> void:
	if not window_open():
		return
	var ut := user_team()
	var order := ut.roster.duplicate()
	order.sort_custom(func(a: PlayerData, b: PlayerData) -> bool: return a.listed and not b.listed) # Listed players first.
	for p: PlayerData in order:
		if incoming.size() >= 6:
			break
		if p.loan_from != "":
			continue
		var unhappy := p.morale < 40.0
		var chance := 0.07 + (0.12 if unhappy else 0.0) + clampf(p.avg_recent_rating() - 1.0, 0.0, 0.4) * 0.3
		if p.listed:
			chance = 0.3 + clampf(p.avg_recent_rating() - 1.0, 0.0, 0.4) * 0.4
		if rng.randf() > chance * diff("ai"):
			continue
		if incoming.any(func(o: Dictionary) -> bool: return int(o.player) == p.uid):
			continue
		var bidders: Array = []
		for i in teams.size():
			var t := teams[i]
			if t == ut or t.league > ut.league + 1 or t.roster.size() < MIN_ROSTER:
				continue
			var weakest := t.starters(5)[t.starters(5).size() - 1]
			if p.rating_exact() > weakest.rating_exact() - (6.0 if p.listed else 2.0) and p.refuses(t) == "":
				bidders.append(i)
		if bidders.is_empty():
			continue
		var ti: int = bidders[rng.randi() % bidders.size()]
		var t := teams[ti]
		var value := float(p.market_value()) * rng.randf_range(0.8, 1.35) * (1.15 if p.contract_until > season else 0.85)
		if p.listed:
			value *= 0.85 # Everyone knows you're selling.
		var swap: PlayerData = null
		if rng.randf() < 0.35 or t.money < value:
			# Offer a player back (one they rate lower), topped up with cash.
			var cands: Array = t.roster.filter(func(x: PlayerData) -> bool: return not x.is_user and x.market_value() < value and x.refuses(ut) == "")
			if not cands.is_empty():
				swap = cands[rng.randi() % cands.size()]
				value = maxf(0.0, value - swap.market_value() * 0.9)
		var cash := int(round(value / 1000.0)) * 1000
		if t.money < cash:
			continue
		if swap == null and cash <= 0:
			continue
		incoming.append({"id": next_offer_id, "team": ti, "player": p.uid, "cash": cash, "swap": swap.uid if swap != null else 0,
			"expires": rng.randi_range(1, 3), "countered": false})
		next_offer_id += 1
		_news("OFFER: %s bid %s%s for %s. See Transfers > Offers." % [t.team_name, UI_money(cash),
			(" + " + swap.player_name) if swap != null else "", p.player_name])


func _expire_incoming() -> void:
	for o in incoming.duplicate():
		o.expires = int(o.expires) - 1
		if int(o.expires) <= 0 or not window_open():
			incoming.erase(o)


func offer_valid(o: Dictionary) -> String:
	if not window_open():
		return "Window closed"
	var p := find_player(int(o.player))
	var t: TeamData = teams[int(o.team)]
	if p == null or not user_team().roster.has(p):
		return "Player gone"
	if int(o.swap) != 0:
		var sw := find_player(int(o.swap))
		if sw == null or not t.roster.has(sw):
			return "Their player is gone"
	elif user_team().roster.size() <= MIN_ROSTER:
		return "You'd drop below %d players" % MIN_ROSTER
	if t.money < int(o.cash):
		return "They can't afford it any more"
	return ""


func accept_incoming(o: Dictionary) -> String:
	var why := offer_valid(o)
	if why != "":
		incoming.erase(o)
		return why
	var p := find_player(int(o.player))
	var t: TeamData = teams[int(o.team)]
	var ut := user_team()
	var sw: PlayerData = find_player(int(o.swap)) if int(o.swap) != 0 else null
	_move_player(p, ut, t)
	if sw != null:
		_move_player(sw, t, ut)
	t.money -= int(o.cash)
	if int(o.cash) > 0:
		money += int(o.cash)
		_ledger("Sold %s to %s" % [p.player_name, t.team_name], int(o.cash))
		_note_transfer(p, ut, t, int(o.cash))
	_trim_roster(t, p)
	incoming.erase(o)
	var what := UI_money(int(o.cash)) + ((" + " + sw.player_name) if sw != null else "")
	_news("TRANSFER: %s joins %s for %s." % [p.player_name, t.team_name, what])
	_wire("TRANSFER: %s sign %s from %s (%s)." % [t.team_name, p.player_name, ut.team_name, what], "deal")
	return ""


func decline_incoming(o: Dictionary) -> void:
	incoming.erase(o)


## Ask for 25% more cash. They may agree, walk away, or hold their offer.
func counter_incoming(o: Dictionary) -> String:
	if bool(o.get("countered", false)):
		return "They won't negotiate again"
	var t: TeamData = teams[int(o.team)]
	var p := find_player(int(o.player))
	o.countered = true
	var ask := int(round(maxf(float(o.cash) * 1.25, float(o.cash) + 10000.0) / 1000.0)) * 1000
	var chance := 0.45 + (0.15 if p != null and p.avg_recent_rating() > 1.1 else 0.0)
	var roll := rng.randf()
	if roll < chance and t.money >= ask:
		o.cash = ask
		return "accepted"
	if roll > 0.75:
		incoming.erase(o)
		_news("%s walked away from talks for %s." % [t.team_name, p.player_name if p != null else "your player"])
		return "walked"
	return "held"


# --- Renaming ------------------------------------------------------------------

func rename_player(p: PlayerData, new_name: String) -> String:
	var n := new_name.strip_edges()
	if n == "" or n.length() > 18:
		return "Name must be 1-18 characters"
	if n == p.player_name:
		return ""
	if used_names.has(n):
		return "Another player is already called %s" % n
	var old := p.player_name
	used_names.erase(old)
	used_names[n] = true
	if last_training.has(old):
		last_training[n] = last_training[old]
		last_training.erase(old)
	p.player_name = n
	_news("%s will now play as %s." % [old, n])
	return ""


func rename_team(t: TeamData, new_name: String, tag: String) -> String:
	var n := new_name.strip_edges()
	if n == "" or n.length() > 24:
		return "Name must be 1-24 characters"
	for o in teams:
		if o != t and o.team_name.to_lower() == n.to_lower():
			return "%s already exists" % n
	var old := t.team_name
	t.team_name = n
	var tg := tag.strip_edges().to_upper()
	t.short_name = tg.substr(0, 4) if tg != "" else _tag(n)
	if old != n:
		_news("%s rebrand as %s." % [old, n])
	return ""


func release_player(p: PlayerData) -> String:
	if user_team().roster.size() <= MIN_ROSTER:
		return "Need at least %d players" % MIN_ROSTER
	user_team().roster.erase(p)
	free_agents.append(p)
	var severance := p.salary * 2
	money -= severance
	_ledger("Released %s (severance)" % p.player_name, -severance)
	_news("You released %s." % p.player_name)
	return ""


# =============================================================================
# AI clubs
# =============================================================================

func _ai_finances() -> void:
	for t in teams:
		if t.is_user_team and mode == "manager":
			continue
		var lg: Dictionary = LEAGUES[t.league]
		var pay := 0
		for p in t.roster:
			pay += p.salary
		t.money += int(lg.sponsor + t.reputation * 200.0) - pay
		# Broke: release the most expensive player (never the user).
		if t.money < -50000 and t.roster.size() > MIN_ROSTER + 1:
			var priciest: PlayerData = null
			for p in t.roster:
				if (priciest == null or p.salary > priciest.salary) and not p.is_user:
					priciest = p
			if priciest != null:
				t.roster.erase(priciest)
				free_agents.append(priciest)
				t.money += priciest.salary * 4
				_wire("%s, short of money, release %s." % [t.team_name, priciest.player_name], "bad")


## The most a club will pay one player per week: a slice of its income.
func wage_budget(t: TeamData) -> int:
	var lg: Dictionary = LEAGUES[t.league]
	return int((lg.sponsor + t.reputation * 200.0) / 4.0)


func _refill_roster(t: TeamData) -> void:
	while t.roster.size() < MIN_ROSTER + 1 and not free_agents.is_empty():
		# Best free agents the club can afford.
		var cap := wage_budget(t)
		var affordable := free_agents.filter(func(p: PlayerData) -> bool: return PlayerData.salary_for_rating(p.rating_exact()) <= cap)
		if affordable.is_empty():
			affordable = free_agents.duplicate()
			affordable.sort_custom(func(a: PlayerData, b: PlayerData) -> bool: return a.rating_exact() < b.rating_exact())
		else:
			affordable.sort_custom(func(a: PlayerData, b: PlayerData) -> bool: return a.rating_exact() > b.rating_exact())
		var pick: PlayerData = affordable[rng.randi() % mini(6, affordable.size())]
		free_agents.erase(pick)
		pick.contract_until = season + 1
		pick.joined = stamp()
		t.roster.append(pick)
		_note_signing(t, pick)
	t.sort_roster()


## News when a free agent lands somewhere (and always when it's one of yours).
func _note_signing(t: TeamData, p: PlayerData, wire_it: bool = true) -> void:
	if former_players.has(p.uid) and mode == "manager":
		_news("TRANSFER: your former player %s has joined %s." % [p.player_name, t.team_name])
		former_players.erase(p.uid)
	if wire_it and (p.rating() >= 70 or t.league <= 1):
		_wire("%s pick up %s on a free (RTG %d)." % [t.team_name, p.player_name, p.rating()], "deal")


## Over the limit: release the weakest, never the user or `keep` (a player
## they've just bought).
func _trim_roster(t: TeamData, keep: PlayerData = null) -> void:
	t.sort_roster()
	while t.roster.size() > MAX_ROSTER:
		var i := t.roster.size() - 1
		while i > 0 and (t.roster[i].is_user or t.roster[i] == keep or t.roster[i].loan_from != ""):
			i -= 1
		free_agents.append(t.roster.pop_at(i))


func _ai_controls(t: TeamData) -> bool:
	return not (t.is_user_team and mode == "manager")


func _ai_transfers() -> void:
	# Free-agent signings (any time). Best first, ratings computed once.
	var fr := {}
	for fa in free_agents:
		fr[fa] = fa.rating_exact()
	free_agents.sort_custom(func(a: PlayerData, b: PlayerData) -> bool: return fr[a] > fr[b])
	for i in 5:
		if rng.randf() > 0.35:
			continue
		var t: TeamData = teams[rng.randi() % teams.size()]
		if not _ai_controls(t) or t.money < 0 or t.roster.is_empty():
			continue
		var weakest: PlayerData = t.roster[t.roster.size() - 1]
		var wage_cap := wage_budget(t)
		for fa in free_agents.slice(0, 40):
			if fa.rating_exact() > weakest.rating_exact() + 2.0 and t.money > signing_fee(fa) 					and PlayerData.salary_for_rating(fa.rating_exact()) <= wage_cap:
				free_agents.erase(fa)
				t.money -= signing_fee(fa)
				fa.contract_until = season + 1
				fa.joined = stamp()
				t.roster.append(fa)
				_trim_roster(t, fa)
				_wire("%s sign free agent %s (RTG %d)." % [t.team_name, fa.player_name, fa.rating()], "deal")
				_note_signing(t, fa, false)
				break
	# Club-to-club transfers (windows only). Richer, higher clubs poach from lower ones.
	if window_open():
		for i in 2:
			if rng.randf() > 0.3:
				continue
			var buyer: TeamData = teams[rng.randi() % teams.size()]
			var seller: TeamData = teams[rng.randi() % teams.size()]
			if buyer == seller or not _ai_controls(buyer) or not _ai_controls(seller) or seller.roster.size() <= MIN_ROSTER:
				continue
			if buyer.league > seller.league:
				continue
			var p: PlayerData = seller.roster[rng.randi() % seller.roster.size()]
			if p.is_user or p.loan_from != "":
				continue # Bids for you go through your own inbox (see _transfer_interest).
			var price := int(p.market_value() * 1.2)
			if buyer.money < price:
				continue
			var buyer_weakest: PlayerData = buyer.roster[buyer.roster.size() - 1]
			if p.rating_exact() <= buyer_weakest.rating_exact():
				continue
			seller.roster.erase(p)
			buyer.roster.append(p)
			p.joined = stamp()
			buyer.money -= price
			seller.money += price
			_note_transfer(p, seller, buyer, price)
			_trim_roster(buyer, p)
			_refill_roster(seller)
			var who := "YOU" if p.is_user else p.player_name
			if p.is_user:
				_news("TRANSFER: %s buy %s from %s ($%s)." % [buyer.team_name, who, seller.team_name, _fmt(price)])
			_wire("TRANSFER: %s buy %s from %s for $%s." % [buyer.team_name, p.player_name, seller.team_name, _fmt(price)], "deal")


# =============================================================================
# Player mode: your career as a player
# =============================================================================

func _lmult(t: TeamData) -> float:
	return 1.0 + float(LEAGUES.size() - 1 - t.league) * 0.9


func _gain_fame(n: int) -> void:
	if n > 0 and perks.has("showman"):
		n = int(n * 1.3)
	fame = maxi(0, fame + n)


static func fame_text(n: int) -> String:
	if n >= 1000000:
		return "%.1fM" % (n / 1000000.0)
	if n >= 1000:
		return "%.1fk" % (n / 1000.0)
	return str(n)


func _trust(d: float) -> void:
	coach_trust = clampf(coach_trust + d, 0.0, 100.0)


func _has_open_kind(kind: String) -> bool:
	for m in inbox:
		if not bool(m.done) and String(m.kind) == kind:
			return true
	return false


## How much the coach's pick favours you: trust, plus any promise of a start.
func lineup_bonus() -> float:
	var b := (coach_trust - 50.0) / 8.0 + 1.5
	if user_player != null and user_player.promise_until >= stamp():
		b += 8.0
	if forced_bench_until >= stamp():
		b -= 40.0
	elif mode == "player" and social != null:
		b += social.talk.start_bonus()
	return b


## Player mode: the coach picks the five on merit (rating, form, trust in you).
func _apply_coach() -> void:
	for t in teams:
		t.coach_pick = mode == "player" and user_player != null and t.roster.has(user_player)
		t.user_bonus = lineup_bonus() if t.coach_pick else 0.0
		if t.coach_pick:
			t.sort_roster()


func user_starting() -> bool:
	return user_player != null and user_team().starters(5).has(user_player)


## Why you can't play this week's match yourself ("" = you can).
func user_play_block() -> String:
	if user_player == null:
		return "No player"
	if retired:
		return "You've retired"
	if free_agency:
		return "Pick a club first (Career)"
	if teamless:
		return "You're a free agent with no club"
	if not user_player.available():
		return "You're out with %s (%d wk)" % [user_player.ailment, user_player.out_weeks]
	if not user_starting():
		return "You're on the bench this week"
	return ""


func endorsement_income() -> int:
	var n := 0
	for d in endorsements:
		n += int(d.weekly)
	return int(n * 1.1) if assets.has("designer") else n


func weekly_pay() -> int:
	return (user_player.salary if user_player != null else 0) + endorsement_income()


## This season's line on the career timeline (one per season and club).
func _tl() -> Dictionary:
	var ut := user_team()
	if timeline.is_empty() or int(timeline[-1].s) != season or String(timeline[-1].team) != ut.team_name:
		timeline.append({"s": season, "team": ut.team_name, "league": ut.league, "m": 0, "k": 0, "d": 0, "r_sum": 0.0, "pos": 0, "titles": 0})
	return timeline[-1]


func trophy_count(place: int = 1) -> int:
	var n := 0
	for t in trophies:
		if int(t.place) == place:
			n += 1
	return n


## Your fiercest head-to-head: the opposing star you've met most (3+ times).
func top_rival() -> Dictionary:
	var best := {}
	for uid in rivals:
		var e: Dictionary = rivals[uid]
		var n := int(e.w) + int(e.l)
		if n >= 3 and (best.is_empty() or n > int(best.w) + int(best.l) or (n == int(best.w) + int(best.l) and int(e.l) > int(best.l))):
			best = e.duplicate()
			best["uid"] = int(uid)
	return best


func _note_rival(opp_best: PlayerData, opp_r: float, my_r: float, opp: TeamData) -> void:
	if opp_best == null:
		return
	var e: Dictionary = rivals.get(opp_best.uid, {"name": opp_best.player_name, "team": opp.team_name, "w": 0, "l": 0})
	e.name = opp_best.player_name
	e.team = opp.team_name
	if my_r >= opp_r:
		e.w = int(e.w) + 1
	else:
		e.l = int(e.l) + 1
	rivals[opp_best.uid] = e
	if int(e.w) + int(e.l) == 10:
		_achieve("nemesis")
	if int(e.w) + int(e.l) == 3:
		_news("RIVALRY: you and %s (%s) keep going head to head (%d-%d)." % [e.name, e.team, int(e.w), int(e.l)])
		_wire("A rivalry is brewing: %s vs %s" % [user_player.player_name, e.name], "info")


## After each of your matches (player mode): fame, trust, timeline, player of
## the match and rivals. ratings: PlayerData -> match rating for everyone known.
func _after_user_match(ratings: Dictionary, mine: TeamData, opp: TeamData, won: bool) -> void:
	var me := user_player
	if not ratings.has(me):
		last_report["played"] = false
		return
	last_report["played"] = true
	var r: float = ratings[me]
	var tl := _tl()
	tl.m = int(tl.m) + 1
	tl.k = int(tl.k) + int(last_report.get("kills", 0))
	tl.d = int(tl.d) + int(last_report.get("deaths", 0))
	tl.r_sum = float(tl.r_sum) + r
	_trust((r - 1.0) * 4.0)
	_gain_fame(int(((r - 0.9) * 150.0 + (40.0 if won else 0.0)) * _lmult(mine)))
	var best := -1.0
	var top: PlayerData = null
	var opp_best: PlayerData = null
	var opp_r := -1.0
	for p: PlayerData in ratings:
		if float(ratings[p]) > best:
			best = ratings[p]
			top = p
		if opp.roster.has(p) and float(ratings[p]) > opp_r:
			opp_r = ratings[p]
			opp_best = p
	if top == me:
		potm += 1
		last_report["potm"] = true
		_gain_fame(int(120 * _lmult(mine)))
		_news("PLAYER OF THE MATCH: you (%.2f rating)." % r)
	_note_rival(opp_best, opp_r, r, opp)
	_feed_match(r, won, opp, top == me)
	if me.matches_played % 5 == 0:
		_check_traits()
	if trash_target == team_index(opp):
		trash_target = -1
	soc().after_match(r, won, opp, String(last_report.get("label", "")))
	peak_rating = maxi(peak_rating, me.rating())
	_check_perks()


## One My Player training session a week on one stat. Intensity trades safety
## for size; your setup, specialty, perks and a booked coach all help.
func train_user(key: String, intensity: String = "Normal") -> float:
	if trained_this_week or user_player == null or retired or not user_player.available():
		return 0.0
	trained_this_week = true
	var it: Dictionary = PM_INTENSITY.get(intensity, PM_INTENSITY.Normal)
	var mult := float(it.mult) * (1.0 + 0.12 * setup_level)
	if perks.has("grinder"):
		mult *= 1.2
	if specialty != "" and (SPECIALTIES[specialty] as Array).has(key):
		mult *= 1.35
	var sd := float(it.sd)
	if coach_booked:
		mult *= 1.5
		sd *= 0.6
		coach_booked = false
	if assets.has("trainer"):
		mult *= 1.15
	var before := user_player.stat(key)
	var d := Progression.train(user_player, key, rng, mult, sd)
	# A session always moves the stat visibly (no "+0.0"), unless it's maxed out.
	if absf(d) < 0.1:
		user_player.set_stat(key, before + (0.1 if d >= 0.0 else -0.1))
		d = user_player.stat(key) - before
	var note := ""
	if before >= PlayerData.MAX_STAT - 0.05:
		note = "Already maxed out."
	elif user_player.potential - user_player.rating_exact() < 1.5:
		note = "Close to your potential: gains are small now."
	if intensity == "Light":
		user_player.morale = minf(100.0, user_player.morale + 3.0)
	if rng.randf() < float(it.injury) * (0.5 if perks.has("iron") else 1.0):
		user_player.out_weeks = rng.randi_range(1, 2)
		user_player.ailment = "a training injury"
		note = "Injured! Out %d week%s." % [user_player.out_weeks, "s" if user_player.out_weeks > 1 else ""]
		_news("INJURY: you hurt yourself in a hard session and will miss %d week%s." % [user_player.out_weeks, "s" if user_player.out_weeks > 1 else ""])
	_news("Training (%s): %s %+.1f%s" % [intensity, PlayerData.STAT_NAMES[key], d, "  (bad session)" if d < 0.0 else ""])
	last_training = {"key": key, "delta": d, "intensity": intensity, "note": note}
	return d


func choose_specialty(s: String) -> String:
	if not SPECIALTIES.has(s):
		return "Unknown specialty"
	if user_player.matches_played < SPECIALTY_MATCHES:
		return "Play %d matches first" % SPECIALTY_MATCHES
	if specialty == s:
		return "Already your specialty"
	if specialty != "":
		if wallet < RESPEC_COST:
			return "Changing specialty costs $%s" % _fmt(RESPEC_COST)
		wallet -= RESPEC_COST
	specialty = s
	_news("You now specialise as: %s." % s)
	return ""


func setup_cost() -> int:
	return SETUP_COSTS[setup_level] if setup_level < SETUP_COSTS.size() else 0


func buy_setup() -> String:
	if setup_level >= SETUP_COSTS.size():
		return "Your setup is maxed out"
	var c := setup_cost()
	if wallet < c:
		return "Need $%s" % _fmt(c)
	wallet -= c
	setup_level += 1
	return ""


func coach_cost() -> int:
	return int(COACH_COST * (1.0 + 0.5 * float(LEAGUES.size() - 1 - user_team().league)))


func book_coach() -> String:
	if coach_booked:
		return "Already booked for your next session"
	if wallet < coach_cost():
		return "Need $%s" % _fmt(coach_cost())
	wallet -= coach_cost()
	coach_booked = true
	return ""


## Weekly, after the week's matches: pay, health, form, the market, contract
## talks, endorsements, media and the dressing room.
func _player_mode_week() -> void:
	if user_player == null or retired:
		return
	var p := user_player
	wallet += weekly_pay() - agent_cut()
	for d in endorsements.duplicate():
		d.weeks = int(d.weeks) - 1
		if int(d.weeks) <= 0:
			endorsements.erase(d)
			_news("ENDORSEMENT: your %s deal has ended." % d.brand)
	_user_health()
	_user_form()
	_lifestyle_week()
	if not teamless:
		_relationship_events()
		_transfer_interest()
		_contract_talks()
	_endorsement_offers()
	if not teamless:
		_dressing_room()
	soc().weekly()
	_check_goals(false)
	_check_perks()
	peak_rating = maxi(peak_rating, p.rating())
	if wallet >= 1000000:
		_achieve("millionaire")


func _user_health() -> void:
	var p := user_player
	if p.out_weeks > 0:
		p.out_weeks -= 1
		if p.out_weeks == 0:
			p.ailment = ""
			_news("You're fit again.")
		return
	var k := (0.5 if perks.has("iron") else 1.0) * diff("injury") * (1.0 + fatigue / 100.0) * (0.75 if assets.has("physio_p") else 1.0)
	var roll := rng.randf()
	if roll < 0.010 * k:
		p.out_weeks = 1
		p.ailment = ILLNESSES[rng.randi() % ILLNESSES.size()]
	elif roll < 0.015 * k:
		p.out_weeks = rng.randi_range(1, 3)
		p.ailment = INJURIES[rng.randi() % INJURIES.size()]
	else:
		return
	_news("WARNING: you're out for %d week%s with %s." % [p.out_weeks, "s" if p.out_weeks > 1 else "", p.ailment])
	_post(_fan_handle(), "Get well soon %s" % p.player_name, "fan", 0.8)
	if rng.randf() < 0.6:
		_toxic("injury")
	_msg("injury", "You're unavailable: %s" % p.ailment,
		"The physio rules you out for %d week%s. You can't train or play until you're fit; the team plays without you." % [p.out_weeks, "s" if p.out_weeks > 1 else ""],
		[["OK", "ok"]], p.uid)


## Your form follows your own results; morale follows playing time and results.
func _user_form() -> void:
	var p := user_player
	p.form *= 0.75
	if not p.match_log.is_empty():
		var last: Dictionary = p.match_log[p.match_log.size() - 1]
		if int(last.s) == season and int(last.w) == week:
			p.form += (float(last.r) - 1.0) * 2.5
	p.form = clampf(p.form + (p.morale - 60.0) / 80.0 + rng.randfn(0.0, 0.5), -8.0, 8.0)
	var starting := user_starting()
	var streak_mod := 0.0 if teamless else clampf(user_team().streak * 0.6, -2.0, 2.0)
	p.morale += (0.8 if starting else (-0.8 if teamless else -2.5)) + streak_mod + (62.0 - p.morale) * 0.04
	p.morale = clampf(p.morale, 40.0 if perks.has("silverware") else 0.0, 100.0)
	coach_trust += (50.0 - coach_trust) * 0.03


## After the lineup is picked: tell you when you're dropped, and let you react.
func _coach_week() -> void:
	var p := user_player
	if p == null or retired or teamless or not p.available():
		if p != null:
			p.bench_weeks = 0
		return
	if user_starting():
		if p.bench_weeks >= 2:
			_news("You're back in the starting five.")
		p.bench_weeks = 0
		return
	p.bench_weeks += 1
	if p.bench_weeks == 1:
		_toxic("benched")
	if p.bench_weeks == 1 and not _has_open_kind("bench"):
		var ahead := ""
		for s in user_team().starters(5):
			ahead = s.player_name
		_msg("bench", "Coach: you're on the bench", "%s's coach has gone with %s ahead of you this week. Your form (%s) and how much the coach trusts you (%d/100) decide the lineup." % [user_team().team_name, ahead, p.form_text().to_lower(), int(coach_trust)],
			[["Accept it", "pm_bench_ok"], ["Demand to start", "pm_demand"], ["Request a transfer", "pm_request"]], p.uid)
	elif p.bench_weeks == 4:
		p.morale = maxf(0.0, p.morale - 5.0)
		_news("Four weeks on the bench. It's getting to you.")


## Wage a club offers you: your rating, their level, your form.
func offer_wage(t: TeamData) -> int:
	var p := user_player
	var f := 1.0 + float(LEAGUES.size() - 1 - t.league) * 0.15 + clampf(p.avg_recent_rating() - 1.0, -0.2, 0.3)
	var w := PlayerData.salary_for_rating(p.rating_exact()) * f * (1.0 + float(agent_info().wage))
	if t != user_team():
		w = maxf(w, p.salary * 1.05)
	return int(round(w / 50.0)) * 50


## force: skip the club's attitude check (a coach who already said yes).
func _add_offer(idx: int, note: String, force: bool = false) -> void:
	if offers.any(func(o: Dictionary) -> bool: return int(o.team) == idx):
		return
	if not force and mode == "player" and not soc().talk.allows_offer(idx):
		return
	var t := teams[idx]
	offers.append({"team": idx, "note": note, "wage": offer_wage(t), "years": rng.randi_range(1, 3)})
	_news("Transfer offer from %s!" % t.team_name)


## Interest from other clubs, clubs selling you, and being shipped out.
func _transfer_interest() -> void:
	var p := user_player
	var ut := user_team()
	var form := p.avg_recent_rating()
	var chance := clampf((form - 1.0) * 0.6, 0.0, 0.4) if form > 1.05 else 0.0
	if transfer_request:
		chance = maxf(chance, 0.35)
	chance *= 1.0 + float(agent_info().offers)
	if offers.size() < 4 and rng.randf() < chance:
		var pool: Array = []
		for i in teams.size():
			var t := teams[i]
			if t == ut:
				continue
			# Clubs at most a league up, and not far above your level.
			var reach := t.league >= ut.league - 1 and t.rating_exact() <= p.rating_exact() + 12.0 + float(agent_info().reach)
			var better := t.league < ut.league or (t.league == ut.league and t.rating() > ut.rating())
			var sideways := transfer_request and t.league <= ut.league + 1 # You asked: any club up to a league lower.
			if reach and (better or sideways):
				pool.append(i)
		if not pool.is_empty():
			var idx: int = pool[rng.randi() % pool.size()]
			_add_offer(idx, ("%s heard you want out." % teams[idx].team_name) if transfer_request else "%s (%s) like your form (%.2f)." % [teams[idx].team_name, LEAGUES[teams[idx].league].name, form])
	# Clubs you've asked to join (DMs with their players) may come calling.
	for ci: int in soc().club_interest:
		if ci != team_index(ut) and offers.size() < 4 and rng.randf() < soc().club_pull(ci) * 0.12 and teams[ci].rating_exact() <= p.rating_exact() + 14.0:
			_add_offer(ci, "%s heard you'd like to join." % teams[ci].team_name)
	# Your club accepts a bid for you without asking. You can still say no.
	if window_open() and not transfer_request and rng.randf() < 0.04 and not _has_open_kind("sold"):
		var buyers: Array = []
		for i in teams.size():
			var bt := teams[i]
			if bt != ut and bt.league <= ut.league and bt.league >= ut.league - 1 and bt.rating_exact() <= p.rating_exact() + 10.0 and bt.money > p.market_value():
				buyers.append(i)
		if not buyers.is_empty():
			var bi: int = buyers[rng.randi() % buyers.size()]
			var b := teams[bi]
			var fee := int(p.market_value() * rng.randf_range(1.0, 1.4) / 1000.0) * 1000
			_msg("sold", "%s have accepted a bid for you" % ut.team_name,
				"%s (%s) bid $%s and your club said yes without asking you. They'd pay you $%s/wk on a 2-season deal (now $%s/wk). You can refuse, but the coach won't like it." % [b.team_name, LEAGUES[b.league].name, _fmt(fee), _fmt(offer_wage(b)), _fmt(p.salary)],
				[["Accept the move", "pm_sold_go"], ["Refuse to go", "pm_sold_stay"]], p.uid, {"team": bi, "wage": offer_wage(b)})
	# Poor form as the weakest starter can get you shipped out (no say).
	var weakest := true
	for s in ut.starters(5):
		if not s.is_user and s.rating_exact() < p.rating_exact():
			weakest = false
	if weakest and form < 0.85 and coach_trust < 35.0 and window_open() and rng.randf() < 0.2:
		var others: Array = []
		for i in teams.size():
			if teams[i] != ut and teams[i].league >= ut.league:
				others.append(i)
		var dest: TeamData = teams[others[rng.randi() % others.size()]]
		_join_club(dest, offer_wage(dest), 1)
		_news("TRADED: %s sent you to %s." % [ut.team_name, dest.team_name])
		_msg("sold", "You've been traded to %s" % dest.team_name, "%s lost faith and shipped you out. Fresh start: the coach at %s doesn't know you yet." % [ut.team_name, dest.team_name], [["OK", "ok"]], p.uid)


## Moves you to a club on new terms (contract years from now).
func _join_club(dest: TeamData, wage: int, years: int) -> void:
	_move_user_to(dest)
	user_player.salary = wage
	user_player.contract_until = season + years - (1 if week <= 2 else 0)
	user_player.promise_until = 0
	user_player.bench_weeks = 0
	offers.clear()
	transfer_request = false
	free_agency = false
	renewal_done = false
	coach_trust = 55.0
	forced_bench_until = 0
	soc().strikes = 0
	soc().heat = 0.0
	soc().trial = {}
	_apply_coach()
	_tl()
	_post("@%s" % dest.short_name, "Welcome to %s, %s!" % [dest.team_name, user_player.player_name], "club", 1.5)
	_toxic("new_club", dest.team_name)


func request_transfer() -> String:
	if transfer_request:
		return "You're already on the market"
	var ut := user_team()
	var by_rating := ut.starters(5)
	by_rating.sort_custom(func(a: PlayerData, b: PlayerData) -> bool: return a.rating_exact() > b.rating_exact())
	var key := by_rating.find(user_player) in [0, 1]
	var chance := 0.75 - (0.45 if key else 0.0) - (coach_trust - 50.0) / 200.0
	_trust(-4.0)
	if rng.randf() < chance:
		transfer_request = true
		_news("TRANSFER REQUEST: %s agree to let you go. Clubs are being told you're available." % ut.team_name)
		_wire("%s want out of %s" % [user_player.player_name, ut.team_name], "deal")
		_post(OUTLET_HANDLES.pick_random(), "BREAKING: %s has asked to leave %s." % [user_player.player_name, ut.team_name], "press", 2.0)
		_toxic("transfer", "", 2.0)
		_toxic("transfer", "", 1.4)
		return "Request accepted: you're on the market. Offers will come in over the next weeks."
	user_player.morale = maxf(0.0, user_player.morale - 6.0)
	_news("%s turned down your transfer request." % ut.team_name)
	return "%s rejected your request: %s" % [ut.team_name, "you're too important to them." if key else "they want you to fight for your place."]


func cancel_transfer_request() -> void:
	transfer_request = false
	_trust(2.0)
	_news("You withdrew your transfer request.")


func accept_offer(i: int) -> String:
	if i < 0 or i >= offers.size():
		return "Offer gone"
	if not window_open() and not free_agency and not teamless:
		return window_text() + ": the move can only happen in a window"
	var o: Dictionary = offers[i]
	var dest: TeamData = teams[int(o.team)]
	var from := user_team()
	if free_agency and dest != from:
		_achieve("free_agent")
	_join_club(dest, int(o.wage), int(o.years))
	if dest == from:
		_news("You re-signed with %s ($%s/wk)." % [dest.team_name, _fmt(int(o.wage))])
	else:
		_news("You signed with %s (from %s), $%s/wk." % [dest.team_name, from.team_name, _fmt(int(o.wage))])
		_wire("%s joins %s" % [user_player.player_name, dest.team_name], "deal")
	return ""


func decline_offer(i: int) -> String:
	if free_agency and offers.size() <= 1:
		return "You need a club: this is your last offer"
	offers.remove_at(i)
	return ""


func _move_user_to(dest: TeamData) -> void:
	if teamless:
		# No club to swap with: just join (their weakest goes if the roster is full).
		soc().on_club_change(null, dest)
		teamless = false
		dest.roster.append(user_player)
		user_player.joined = stamp()
		for mate in dest.roster:
			if not mate.is_user and not relations.has(mate.uid):
				relations[mate.uid] = 0.0
		_trim_roster(dest, user_player)
		dest.sort_roster()
		return
	var from := user_team()
	if from == dest:
		return
	soc().on_club_change(from, dest)
	var starters := dest.starters(5)
	var swap: PlayerData = starters[starters.size() - 1]
	for p in starters:
		if p.rating_exact() < swap.rating_exact():
			swap = p
	dest.roster.erase(swap)
	from.roster.erase(user_player)
	dest.roster.append(user_player)
	from.roster.append(swap)
	user_player.joined = stamp()
	swap.joined = stamp()
	for mate in dest.roster:
		if not mate.is_user and not relations.has(mate.uid):
			relations[mate.uid] = 0.0
	dest.sort_roster()
	from.sort_roster()


## Final season of your deal: the club makes an offer (or lets you go).
func _contract_talks() -> void:
	var p := user_player
	if renewal_done or free_agency or p.contract_until > season or week != 12:
		return
	var ut := user_team()
	if coach_trust < 35.0 and p.rating_exact() < ut.rating_exact() - 2.0:
		renewal_done = true
		_msg("contract", "%s won't renew your contract" % ut.team_name,
			"Your deal ends after this season and the club has decided to move on. You'll be a free agent: clubs will make offers when the season ends.", [["OK", "ok"]], p.uid)
		return
	var wage := int(round(maxf(p.salary, PlayerData.salary_for_rating(p.rating_exact()) * (0.85 + coach_trust / 250.0 + clampf(p.avg_recent_rating() - 1.0, -0.15, 0.25)) * (1.0 + float(agent_info().wage))) / 50.0)) * 50
	var years := rng.randi_range(1, 3)
	_msg("contract", "Contract offer from %s" % ut.team_name,
		"Your deal ends after this season. %s offer %d more season%s at $%s/wk (now $%s/wk). Your agent can push for more, but clubs sometimes walk away." % [ut.team_name, years, "s" if years > 1 else "", _fmt(wage), _fmt(p.salary)],
		[["Sign it", "pm_renew"], ["Ask for more", "pm_renew_more"], ["Reject: test free agency", "pm_renew_no"]], p.uid, {"wage": wage, "years": years})


## Contract over: offers from clubs around your level (maybe your old club too).
func _start_free_agency(from: TeamData) -> void:
	free_agency = true
	offers.clear()
	for m in inbox:
		if not bool(m.done) and String(m.kind) == "contract":
			m.done = true
			m.result = "Expired."
	var p := user_player
	var pool: Array = []
	for i in teams.size():
		if teams[i] != from:
			pool.append(i)
	pool.sort_custom(func(a: int, b: int) -> bool:
		return absf(teams[a].rating_exact() - p.rating_exact() - 2.0) < absf(teams[b].rating_exact() - p.rating_exact() - 2.0))
	var picks: Array = pool.slice(0, 10)
	picks.shuffle()
	for idx in picks.slice(0, 3):
		_add_offer(idx, "%s want you on a free." % teams[idx].team_name)
	if coach_trust >= 40.0 and rng.randf() < 0.6:
		_add_offer(team_index(from), "%s would take you back." % from.team_name)
	for idx in picks:
		if not offers.is_empty():
			break
		_add_offer(idx, "%s are the only club willing to take a chance on you." % teams[idx].team_name, true)
	_news("FREE AGENT: your contract with %s is up. Choose your next club (Career)." % from.team_name)
	_msg("contract", "You're a free agent", "Your contract with %s has run out. %d clubs have made offers: pick one on the Career page before the season can start." % [from.team_name, offers.size()], [["OK", "ok"]], p.uid)


func _endorsement_offers() -> void:
	var slots := 1 + mini(2, fame / 20000)
	if fame < 1500 or endorsements.size() >= slots or _has_open_kind("endorse") or rng.randf() > 0.12:
		return
	var taken := endorsements.map(func(d: Dictionary) -> String: return String(d.brand))
	var brands := PERSONAL_BRANDS.filter(func(b: String) -> bool: return not taken.has(b))
	var brand: String = brands[rng.randi() % brands.size()]
	var weekly := int(round((80.0 + fame * 0.03) * (1.25 if perks.has("fan_fav") else 1.0) / 10.0)) * 10
	var weeks := rng.randi_range(12, 30)
	_msg("endorse", "%s want you as an ambassador" % brand,
		"A personal deal, separate from the club: $%s/wk for %d weeks, plus $%s up front. Your %s followers are the draw." % [_fmt(weekly), weeks, _fmt(weekly * 3), fame_text(fame)],
		[["Sign", "pm_endorse"], ["Decline", "ok"]], user_player.uid, {"brand": brand, "weekly": weekly, "weeks": weeks})


const OUTLETS := ["FragFeed", "The Clutch Podcast", "Headshot Weekly", "ESN Live", "Roundup Radio", "PeekTV"]


## Reporters, the coach and teammates.
func _dressing_room() -> void:
	var p := user_player
	var ut := user_team()
	var big := false
	var opp_idx := -1
	if not p.match_log.is_empty():
		var last: Dictionary = p.match_log[p.match_log.size() - 1]
		if int(last.s) == season and int(last.w) == week:
			big = float(last.r) >= 1.4 or float(last.r) <= 0.6
			for i in teams.size():
				if teams[i].team_name == String(last.opp):
					opp_idx = i
	if opp_idx < 0:
		var others: Array = league_teams(ut.league).filter(func(t: TeamData) -> bool: return t != ut)
		opp_idx = team_index(others[rng.randi() % others.size()])
	if not _has_open_kind("media") and rng.randf() < (0.45 if big else 0.08):
		var outlet: String = OUTLETS[rng.randi() % OUTLETS.size()]
		var q := "How do you explain that performance?" if big and p.avg_recent_rating() < 1.0 else "What's driving your form right now?"
		if not big:
			q = "Where do %s stand this season?" % ut.team_name
		_msg("media", "Interview request: %s" % outlet, "\"%s\" How you answer shapes your fame, the coach's trust and the dressing room." % q,
			[["Stay humble", "pm_humble"], ["Back yourself", "pm_confident"], ["Trash talk %s" % teams[opp_idx].team_name, "pm_trash"]], p.uid, {"team": opp_idx})
	if week > 3 and week <= LEAGUE_WEEKS and not _has_open_kind("role") and rng.randf() < 0.03:
		var have := ut.starters(5).map(func(s: PlayerData) -> String: return s.role)
		var options: Array = PlayerData.ROLES.filter(func(r: String) -> bool: return r != p.role and not have.has(r))
		if options.is_empty():
			options = PlayerData.ROLES.filter(func(r: String) -> bool: return r != p.role)
		var role: String = options[rng.randi() % options.size()]
		_msg("role", "Coach wants you to play %s" % role, "The lineup needs a %s and the coach thinks you can do it. Accepting earns trust; refusing costs some." % role,
			[["Accept the role", "pm_role"], ["Refuse", "pm_role_no"]], p.uid, {"role": role})
	if not _has_open_kind("teammate") and rng.randf() < 0.06:
		var mates: Array = ut.roster.filter(func(s: PlayerData) -> bool: return not s.is_user)
		if not mates.is_empty():
			var mate: PlayerData = mates[rng.randi() % mates.size()]
			_msg("teammate", "%s: \"Extra practice tonight?\"" % mate.player_name, "%s wants to grind duo drills with you. It uses this week's training session (if you still have it), but you both improve and it builds team spirit." % mate.player_name,
				[["Sure", "pm_duo"], ["Not tonight", "pm_duo_no"]], mate.uid)


## Season goals: set at the start of each season, rewarded when hit.
func _make_goals() -> void:
	goals.clear()
	if user_player == null:
		return
	var p := user_player
	var ut := user_team()
	var tr := clampf(snappedf(maxf(p.avg_recent_rating(), 0.9) + 0.05, 0.05), 0.95, 1.3)
	goals.append({"kind": "rating", "text": "Average a %.2f+ rating (8+ matches)" % tr, "target": tr, "reward": 5, "status": "open"})
	var kt := int(round((50.0 + p.rating_exact() * 0.4) / 5.0)) * 5
	goals.append({"kind": "kills", "text": "Get %d kills this season" % kt, "target": kt, "reward": 3, "status": "open"})
	goals.append({"kind": "matches", "text": "Play 12 matches this season", "target": 12, "reward": 3, "status": "open"})
	if teamless:
		goals[goals.size() - 1] = {"kind": "matches", "text": "Find a club and play 12 matches", "target": 12, "reward": 5, "status": "open"}
		return
	var lg := league_teams(ut.league)
	lg.sort_custom(func(a: TeamData, b: TeamData) -> bool: return a.rating_exact() > b.rating_exact())
	var rank := lg.find(ut) + 1
	if rank <= 3:
		if ut.league > 0:
			goals.append({"kind": "promotion", "text": "Win promotion (top %d)" % PROMOTE, "target": PROMOTE, "reward": 8, "status": "open"})
		else:
			goals.append({"kind": "trophy", "text": "Win a trophy", "target": 1, "reward": 8, "status": "open"})
	elif rank <= 9:
		goals.append({"kind": "playoffs", "text": "Make the playoffs (top %d)" % PLAYOFF_SIZE, "target": PLAYOFF_SIZE, "reward": 6, "status": "open"})
	elif ut.league < LEAGUES.size() - 1:
		goals.append({"kind": "survive", "text": "Avoid relegation", "target": TEAMS_PER_LEAGUE - PROMOTE, "reward": 6, "status": "open"})
	else:
		goals.append({"kind": "top", "text": "Finish in the top 12", "target": 12, "reward": 4, "status": "open"})


func goal_progress(g: Dictionary) -> String:
	var p := user_player
	var ut := user_team()
	var pos := standings(ut.league).find(ut) + 1
	match String(g.kind):
		"rating":
			return "%.2f over %d" % [p.season_avg_rating(), int(p.season_stats.get("m", 0))]
		"kills":
			return "%d / %d" % [int(p.season_stats.get("k", 0)), int(g.target)]
		"matches":
			return "%d / %d" % [int(p.season_stats.get("m", 0)), int(g.target)]
		"trophy":
			return "%d won" % trophies.filter(func(t: Dictionary) -> bool: return int(t.s) == season and int(t.place) == 1).size()
	return "#%d now" % pos


func _check_goals(final: bool) -> void:
	if user_player == null:
		return
	var p := user_player
	var ut := user_team()
	var pos := standings(ut.league).find(ut) + 1
	var m := int(p.season_stats.get("m", 0))
	var won_now := trophies.any(func(t: Dictionary) -> bool: return int(t.s) == season and int(t.place) == 1)
	for g in goals:
		if String(g.status) != "open":
			continue
		var done := false
		match String(g.kind):
			"rating": done = final and m >= 8 and p.season_avg_rating() >= float(g.target)
			"kills": done = int(p.season_stats.get("k", 0)) >= int(g.target)
			"matches": done = m >= int(g.target)
			"trophy": done = won_now
			"promotion", "playoffs", "top": done = (final or week > LEAGUE_WEEKS) and pos <= int(g.target)
			"survive": done = final and pos <= int(g.target)
		if done:
			g.status = "done"
			var bonus := maxi(1000, p.salary * 4)
			wallet += bonus
			_trust(float(g.reward))
			_gain_fame(int(300 * _lmult(ut)))
			_news("GOAL COMPLETE: %s (+$%s bonus)." % [g.text, _fmt(bonus)])
		elif final:
			g.status = "failed"
			_trust(-2.0)


## "Premier Cup S3" -> "Premier Cup" (the season goes in the title's own label).
static func _plain_event(n: String) -> String:
	var rx := RegEx.new()
	rx.compile(" S\\d+$")
	return rx.sub(n, "").strip_edges()


const ORDINALS := ["#1", "#2", "#3", "#4", "#5"]


## League table titles: the top 5 teams after the regular season, whole roster.
func _table_titles(l: int, table: Array, s: int) -> void:
	for i in mini(5, table.size()):
		_honour_team(table[i], "%s in the %s" % [ORDINALS[i], LEAGUES[l].name], s, 60 - l * 12 - i * 6)


## Player leaderboard titles for one league's qualified players (already sorted
## by season rating): top 5 rated, plus the season's best K/D and most kills.
func _leader_titles(pool: Array, l: int, s: int) -> void:
	var lname: String = LEAGUES[l].name
	for i in mini(5, pool.size()):
		(pool[i] as PlayerData).add_honour("#%d Rated in the %s" % [i + 1, lname], s, 70 - l * 12 - i * 6)
	var kd: PlayerData = pool[0]
	var kills: PlayerData = pool[0]
	for p: PlayerData in pool:
		if p.season_kd() > kd.season_kd():
			kd = p
		if int(p.season_stats.get("k", 0)) > int(kills.season_stats.get("k", 0)):
			kills = p
	kd.add_honour("Top K/D in the %s" % lname, s, 55 - l * 10)
	kills.add_honour("Most Kills in the %s" % lname, s, 50 - l * 10)


## New world: last season's honours (Season 0) so the scene already has
## title holders. Results follow team and player strength, with some luck.
func _seed_titles() -> void:
	for l in LEAGUES.size():
		var lt := league_teams(l)
		if lt.is_empty():
			continue
		var luck := {}
		for t: TeamData in lt:
			luck[t] = t.rating() + rng.randfn(0.0, 2.5)
		lt.sort_custom(func(a: TeamData, b: TeamData) -> bool: return float(luck[a]) > float(luck[b]))
		_table_titles(l, lt, 0)
		var top := lt.slice(0, mini(PLAYOFF_SIZE, lt.size()))
		for t: TeamData in top:
			luck[t] = float(luck[t]) + rng.randfn(0.0, 2.0)
		top.sort_custom(func(a: TeamData, b: TeamData) -> bool: return float(luck[a]) > float(luck[b]))
		var ev := "%s Playoffs" % LEAGUES[l].name
		var names := ["%s Champion" % ev, "%s Finalist" % ev, "%s Semi Finalist" % ev, "%s Semi Finalist" % ev]
		var ranks := [90 - l * 15, 25, 20, 20]
		for i in mini(top.size(), 8):
			if i < 4:
				_honour_team(top[i], names[i], 0, ranks[i])
			else:
				_honour_team(top[i], "%s Quarter Finalist" % ev, 0, 10)
		var pool: Array = []
		var score := {}
		for t: TeamData in lt:
			for p: PlayerData in t.starters(5):
				pool.append(p)
				score[p] = p.rating_exact() + rng.randfn(0.0, 3.0)
				var m := rng.randi_range(14, 22)
				var k := int(m * 18 * clampf(0.75 + (float(score[p]) - 60.0) / 60.0, 0.5, 1.4) * rng.randf_range(0.85, 1.15))
				p.season_stats = {"m": m, "k": k, "d": int(m * 17 * rng.randf_range(0.85, 1.15)), "r_sum": 0.0}
		pool.sort_custom(func(a: PlayerData, b: PlayerData) -> bool: return float(score[a]) > float(score[b]))
		if not pool.is_empty():
			_leader_titles(pool, l, 0)
		for p: PlayerData in pool:
			p.season_stats = {}


## Everyone on the team gets the title.
func _honour_team(team: TeamData, text: String, s: int, rank: int = -1) -> void:
	if rank < 0: # Short form (team, text, rank): this season.
		rank = s
		s = season
	for p: PlayerData in team.roster:
		p.add_honour(text, s, rank)


## Old saves: build your titles from the trophy cabinet and awards.
func _backfill_honours() -> void:
	var p := user_player
	if p == null or not p.honours.is_empty():
		return
	for t: Dictionary in trophies:
		var place := int(t.place)
		var n := _plain_event(String(t.name))
		if place == 1:
			p.add_honour(n if n.begins_with("World Cup") else "%s Champion" % n, int(t.s), 95 if n.begins_with("World Cup") else 70)
		elif place == 2:
			p.add_honour("%s Finalist" % n, int(t.s), 25)


func _check_perks() -> void:
	var p := user_player
	if p == null:
		return
	var conds := {"first_blood": p.matches_played >= 10, "grinder": p.matches_played >= 40, "headhunter": p.career_kills >= 400,
		"iron": p.matches_played >= 80, "silverware": trophy_count(1) >= 1, "showman": potm >= 5, "fan_fav": fame >= 25000,
		"veteran": p.matches_played >= 200}
	for id: String in conds:
		if conds[id] and not perks.has(id):
			_unlock_perk(id)


func _unlock_perk(id: String) -> void:
	perks.append(id)
	var p := user_player
	match id:
		"first_blood":
			p.set_stat("reaction", p.stat("reaction") + 1.5)
			p.set_stat("movement", p.stat("movement") + 1.0)
		"headhunter":
			p.set_stat("aim", p.stat("aim") + 1.5)
			p.set_stat("flick", p.stat("flick") + 1.5)
		"veteran":
			p.set_stat("decision", p.stat("decision") + 2.0)
			p.set_stat("positioning", p.stat("positioning") + 2.0)
	var info: Dictionary = PERKS[id]
	_news("PERK UNLOCKED: %s (%s)" % [info.name, info.desc])
	_msg("perk", "Perk unlocked: %s" % info.name, "%s  %s" % [info.need + ".", info.desc], [["Nice", "ok"]], p.uid)


func _award(a_name: String, detail: String, fame_amt: int) -> void:
	awards.append({"s": season, "name": a_name, "detail": detail})
	_gain_fame(fame_amt)
	_post(OUTLET_HANDLES.pick_random(), "%s wins %s: %s." % [user_player.player_name if user_player != null else "?", a_name, detail], "press", 2.0)
	_post(_fan_handle(), "Deserved. %s is the real deal" % (user_player.player_name if user_player != null else "?"), "fan", 1.2)
	_trust(3.0)
	_news("AWARD: %s (%s)." % [a_name, detail])
	_msg("award", "Award: %s" % a_name, "Season %d: %s. Added to your trophy cabinet (Profile)." % [season, detail], [["Nice", "ok"]], user_player.uid if user_player != null else 0)


## End of season, before anything resets: league MVPs, rookies, team of the
## season, player of the year, and the All-Star selection.
func _season_awards() -> void:
	var world_pool: Array = []
	for l in LEAGUES.size():
		var pool: Array = []
		for t in league_teams(l):
			for p in t.roster:
				if int(p.season_stats.get("m", 0)) >= 8:
					pool.append(p)
		if pool.is_empty():
			continue
		pool.sort_custom(func(a: PlayerData, b: PlayerData) -> bool: return a.season_avg_rating() > b.season_avg_rating())
		var lname: String = LEAGUES[l].name
		var mvp: PlayerData = pool[0]
		_leader_titles(pool, l, season)
		_wire("%s MVP: %s (%.2f)" % [lname, mvp.player_name, mvp.season_avg_rating()], "good")
		if not _review.is_empty():
			(_review.awards as Array).append("%s MVP: %s (%.2f)" % [lname, mvp.player_name, mvp.season_avg_rating()])
			_ceremony("%s MVP" % lname, mvp, "%.2f average rating over %d matches" % [mvp.season_avg_rating(), int(mvp.season_stats.get("m", 0))])
		var mine := mode == "player" and user_player != null
		if mine and mvp == user_player:
			_award("%s MVP" % lname, "%.2f average rating" % mvp.season_avg_rating(), int(3000 * (1.0 + (LEAGUES.size() - 1 - l) * 0.9)))
			_achieve("mvp")
		var rookies := pool.filter(func(p: PlayerData) -> bool: return p.age <= 20)
		if not rookies.is_empty():
			var rk: PlayerData = rookies[0]
			_wire("%s Rookie of the Year: %s" % [lname, rk.player_name], "good")
			if not _review.is_empty():
				(_review.awards as Array).append("%s Rookie of the Year: %s" % [lname, rk.player_name])
				_ceremony("%s Rookie of the Year" % lname, rk, "%.2f average at age %d" % [rk.season_avg_rating(), rk.age])
			if mine and rk == user_player:
				_award("%s Rookie of the Year" % lname, "%.2f at age %d" % [rk.season_avg_rating(), rk.age], 1500)
		for i in mini(5, pool.size()):
			if mine and pool[i] == user_player:
				_award("%s Team of the Season" % lname, "#%d rated player in the league" % (i + 1), 800)
		for p in pool:
			world_pool.append([p, p.season_avg_rating() * (1.0 - l * 0.07)])
	if world_pool.is_empty():
		return
	world_pool.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	var poy: PlayerData = world_pool[0][0]
	_wire("PLAYER OF THE YEAR: %s" % poy.player_name, "good")
	if not _review.is_empty():
		(_review.awards as Array).insert(0, "Player of the Year: %s" % poy.player_name)
		_ceremony("Player of the Year", poy, "The best player in the world this season (%.2f)" % poy.season_avg_rating())
	_news("Player of the Year: %s." % poy.player_name)
	if mode != "player" or user_player == null:
		return
	if poy == user_player:
		_award("Player of the Year", "best player in the world in season %d" % season, 8000)
		_achieve("poy")
	# All-Stars: the top 10, snake-drafted into two teams (you on team A).
	var picks: Array = []
	for e in world_pool.slice(0, 10):
		picks.append(e[0])
	if not picks.has(user_player):
		return
	var a: Array = []
	var b: Array = []
	for i in picks.size():
		(a if i % 4 in [0, 3] else b).append((picks[i] as PlayerData).uid)
	if not a.has(user_player.uid):
		var tmp := a
		a = b
		b = tmp
	allstar = {"season": season + 1, "a": a, "b": b, "done": false}
	_award("All-Star", "picked for the season %d All-Star Showcase" % (season + 1), 2000)
	_achieve("allstar")


## The All-Star sides as throwaway copies (the exhibition doesn't count).
func allstar_teams() -> Array:
	var out: Array = []
	for side in ["a", "b"]:
		var t := TeamData.new()
		var cap: PlayerData = null
		for uid in allstar.get(side, []):
			var src := find_player(int(uid))
			if src == null:
				continue
			var cp := PlayerData.from_dict(src.to_dict())
			cp.is_user = src.is_user
			cp.match_mod = 0.0
			t.roster.append(cp)
			if cap == null:
				cap = cp
		while t.roster.size() < 5:
			t.roster.append(_new_player(80.0, ""))
		t.team_name = "Team %s" % (cap.player_name if cap != null else "Stars")
		t.short_name = "ASA" if side == "a" else "ASB"
		t.color = Color("38d0ff") if side == "a" else Color("ff7f2e")
		t.sort_roster()
		out.append(t)
	return out


func allstar_pending() -> bool:
	return not allstar.is_empty() and int(allstar.season) == season and not bool(allstar.done) and week <= 3 and not retired


## score: [your side, theirs]; ratings: player name -> match rating.
func finish_allstar(score: Array, my_rating: float, mvp_is_me: bool) -> void:
	allstar.done = true
	allstar.score = score
	var won: bool = score[0] > score[1]
	_gain_fame(2500 if won else 1200)
	_news("ALL-STAR SHOWCASE: your side %s %d-%d (you: %.2f rating)." % ["won" if won else "lost", score[0], score[1], my_rating])
	if mvp_is_me:
		_award("All-Star MVP", "best player in the season %d showcase" % season, 2500)


func sim_allstar() -> Dictionary:
	var sides := allstar_teams()
	var a: TeamData = sides[0]
	var b: TeamData = sides[1]
	var p := 1.0 / (1.0 + exp(-(a.rating_exact() - b.rating_exact()) / 14.0))
	var s := [0, 0]
	var order: Array = []
	while s[0] < ROUNDS_TO_WIN and s[1] < ROUNDS_TO_WIN and order.size() < MAX_ROUNDS:
		var wn := 0 if rng.randf() < p else 1
		s[wn] += 1
		order.append(wn)
	var lineups := [a.starters(5), b.starters(5)]
	var box := sim_box_score(lineups, order)
	var rows := [[], []]
	var mvp := ""
	var best := -1.0
	var mine := 1.0
	for t in 2:
		for pl: PlayerData in lineups[t]:
			var st: Dictionary = box[pl]
			var mr := Progression.match_rating(st.kills, st.deaths, order.size(), st.objectives, st.damage)
			if mr > best:
				best = mr
				mvp = pl.player_name
			if pl.is_user:
				mine = mr
			rows[t].append({"name": pl.player_name, "rating": pl.rating(), "kills": st.kills, "deaths": st.deaths,
				"adr": int(st.damage / maxi(1, order.size())), "match_rating": mr, "is_user": pl.is_user, "change": null})
		rows[t].sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.match_rating > y.match_rating)
	finish_allstar(s, mine, mvp == user_player.player_name)
	return {"teams": [a, b], "score": s, "rows": rows, "mvp": mvp, "label": "All-Star Showcase (simulated)", "perspective": true, "map": ""}


## End of season (after aging): decline from 30, retirement talk from 32.
func _user_aging() -> void:
	var p := user_player
	if p == null or retired:
		return
	if p.age >= 30:
		var k := float(p.age - 29) * 0.45 * (0.5 if perks.has("veteran") else 1.0)
		for key: String in PlayerData.STAT_KEYS:
			p.set_stat(key, p.stat(key) - rng.randf_range(0.2, 1.0) * k)
		_news("Age is catching up with you (%d): your attributes slipped over the off-season." % p.age)
	if p.age >= FORCED_RETIRE:
		retire()
	elif p.age >= RETIRE_AGE:
		_msg("retire", "Thinking about retirement?", "You're %d. You can keep going, or hang up the mouse and see your legacy (Profile). At %d you'll have to stop." % [p.age, FORCED_RETIRE],
			[["Keep playing", "ok"], ["Retire now", "pm_retire"]], p.uid)


func can_retire() -> bool:
	return user_player != null and user_player.age >= 30 and not retired


func legacy_score() -> int:
	var p := user_player
	return int(trophy_count(1) * 120 + trophy_count(2) * 40 + awards.size() * 60 + potm * 8 + p.matches_played + peak_rating * 4 + fame / 1000)


static func legacy_tier(score: int) -> String:
	if score >= 1400:
		return "Hall of Famer"
	if score >= 900:
		return "Legend"
	if score >= 550:
		return "Respected Pro"
	if score >= 350:
		return "Journeyman"
	return "Cult Hero"


func retire() -> void:
	if retired or user_player == null:
		return
	var p := user_player
	retired = true
	var clubs := {}
	var seasons := {}
	for e in timeline:
		clubs[String(e.team)] = true
		seasons[int(e.s)] = true
	var score := legacy_score()
	legacy = {"age": p.age, "seasons": seasons.size(),
		"matches": p.matches_played, "kd": snappedf(p.career_kd(), 0.01), "titles": trophy_count(1), "awards": awards.size(),
		"potm": potm, "peak": peak_rating, "fame": fame, "clubs": clubs.size(), "score": score, "tier": legacy_tier(score), "s": season}
	_news("RETIRED: you hang up the mouse at %d. Legacy: %s." % [p.age, legacy.tier])
	_post(OUTLET_HANDLES.pick_random(), "End of an era: %s retires. %d trophies, %d awards." % [p.player_name, trophy_count(1), awards.size()], "press", 3.0)
	_post(_fan_handle(), "Thank you %s. Legend." % p.player_name, "fan", 3.0)
	_toxic("retire", "", 1.5)
	user_player.titles = trophy_count(1)
	_consider_hall(p, user_team().team_name)
	if String(legacy.tier) == "Hall of Famer":
		_achieve("hof")
	_wire("%s RETIRES: %d trophies, %d awards" % [p.player_name.to_upper(), trophy_count(1), awards.size()], "info")


## My Player inbox actions. Returns the outcome line shown under the message.
func _resolve_pm(m: Dictionary, action: String, other: PlayerData) -> String:
	if action.begins_with("pm_sx_"):
		return soc().resolve_pm(m, action, other)
	var me := user_player
	var data: Dictionary = m.get("data", {})
	var ut := user_team()
	match action:
		"pm_bench_ok":
			_trust(2.0)
			return "You keep your head down and work. Trust +2."
		"pm_demand":
			var gap := _weakest_starter_rating() - me.rating_exact()
			var chance := 0.3 + (coach_trust - 50.0) / 60.0 - maxf(gap, 0.0) * 0.08
			if rng.randf() < chance:
				me.promise_until = stamp() + 3
				_apply_coach()
				return "The coach agrees: you start the next three weeks. Don't waste it."
			_trust(-8.0)
			me.morale = maxf(0.0, me.morale - 6.0)
			return "The coach didn't take it well. Trust -8."
		"pm_request":
			return request_transfer()
		"pm_sold_go":
			var dest: TeamData = teams[int(data.team)]
			if dest == ut:
				return "You're already there."
			var from_name := ut.team_name
			_join_club(dest, int(data.wage), 2)
			_news("TRANSFER: %s sold you to %s." % [from_name, dest.team_name])
			_wire("%s sell %s to %s" % [from_name, me.player_name, dest.team_name], "deal")
			return "You joined %s." % dest.team_name
		"pm_sold_stay":
			_trust(-12.0)
			me.morale = maxf(0.0, me.morale - 8.0)
			return "You refused the move. The deal is off, and the coach is not happy (trust -12)."
		"pm_renew":
			me.salary = int(data.wage)
			me.contract_until = season + int(data.years)
			renewal_done = true
			_news("CONTRACT: you extended with %s to season %d at $%s/wk." % [ut.team_name, me.contract_until, _fmt(me.salary)])
			return "Signed: $%s/wk until the end of season %d." % [_fmt(me.salary), me.contract_until]
		"pm_renew_more":
			var chance := 0.35 + (coach_trust - 50.0) / 100.0 + clampf((me.avg_recent_rating() - 1.0) * 0.8, -0.2, 0.3) + float(agent_info().push)
			var roll := rng.randf()
			if roll < chance:
				var better := int(round(int(data.wage) * rng.randf_range(1.12, 1.3) / 50.0)) * 50
				_msg("contract", "Improved offer from %s" % ut.team_name,
					"Your agent pushed and the club moved: %d season%s at $%s/wk. This is their final offer." % [int(data.years), "s" if int(data.years) > 1 else "", _fmt(better)],
					[["Sign it", "pm_renew"], ["Reject: test free agency", "pm_renew_no"]], me.uid, {"wage": better, "years": int(data.years)})
				return "Your agent got an improved offer: see the new message."
			if roll < chance + 0.35:
				_msg("contract", "%s won't budge" % ut.team_name,
					"The club is sticking to %d season%s at $%s/wk. Take it or leave it." % [int(data.years), "s" if int(data.years) > 1 else "", _fmt(int(data.wage))],
					[["Sign it", "pm_renew"], ["Reject: test free agency", "pm_renew_no"]], me.uid, data.duplicate())
				return "No movement. The original offer stands (new message)."
			renewal_done = true
			_trust(-5.0)
			_news("CONTRACT: %s walked away from talks. You'll be a free agent at season end." % ut.team_name)
			return "The club walked away. You'll be a free agent at the end of the season."
		"pm_renew_no":
			renewal_done = true
			_news("CONTRACT: you turned down %s. You'll test free agency at season end." % ut.team_name)
			return "You'll be a free agent when the season ends."
		"pm_endorse":
			endorsements.append({"brand": String(data.brand), "weekly": int(data.weekly), "weeks": int(data.weeks)})
			wallet += int(data.weekly) * 3
			_news("ENDORSEMENT: you signed with %s ($%s/wk)." % [data.brand, _fmt(int(data.weekly))])
			_post("@%s" % String(data.brand).replace(" ", ""), "Proud to welcome %s to the team." % me.player_name, "brand", 1.2)
			return "Signed with %s. $%s up front." % [data.brand, _fmt(int(data.weekly) * 3)]
		"pm_humble":
			_trust(3.0)
			_gain_fame(int(150 * _lmult(ut)))
			return "Respectful and on message. The coach liked it (trust +3)."
		"pm_confident":
			_gain_fame(int(400 * _lmult(ut)))
			me.morale = minf(100.0, me.morale + 4.0)
			return "Confident, quotable, good for the brand. Fame up, morale up."
		"pm_trash":
			_gain_fame(int(1000 * _lmult(ut)))
			trash_target = int(data.get("team", -1))
			if trash_target >= 0:
				soc().team_beef[trash_target] = maxi(int(soc().team_beef.get(trash_target, 0)), 8)
				var star: PlayerData = teams[trash_target].starters(1)[0] if not teams[trash_target].roster.is_empty() else null
				if star != null:
					_relate(star.uid, -10.0)
				_post(_fan_handle(), "%s really said that about %s?? Popcorn ready" % [me.player_name, teams[trash_target].team_name], "fan", 2.5)
				_post("@%s" % teams[trash_target].short_name, "We'll see you on the server, %s." % me.player_name, "rival", 1.5)
				_toxic("trash_reply", teams[trash_target].team_name, 2.0)
				_toxic("trash_reply", teams[trash_target].team_name, 1.5)
			if rng.randf() < 0.4:
				_trust(-8.0)
				me.morale = maxf(0.0, me.morale - 4.0)
				return "It went viral, and the coach is furious (trust -8). They'll be fired up next time you meet."
			return "It went viral. Your fans loved it; they'll be fired up next time you meet."
		"pm_role":
			me.role = String(data.role)
			_trust(6.0)
			return "You're now a %s. The coach appreciates it (trust +6)." % me.role
		"pm_role_no":
			_trust(-5.0)
			return "You stick with %s. Trust -5." % me.role
		"pm_duo":
			var amt := 0.5 if not trained_this_week else 0.2
			trained_this_week = true
			var keys: Array = PlayerData.STAT_KEYS.duplicate()
			keys.shuffle()
			for k: String in keys.slice(0, 2):
				me.set_stat(k, me.stat(k) + amt)
				if other != null:
					other.set_stat(k, other.stat(k) + amt)
			if other != null:
				other.morale = minf(100.0, other.morale + 5.0)
				_relate(other.uid, 15.0)
			return "Good session: +%.1f %s and %s for you both." % [amt, PlayerData.STAT_NAMES[keys[0]], PlayerData.STAT_NAMES[keys[1]]]
		"pm_duo_no":
			if other != null:
				other.morale = maxf(0.0, other.morale - 4.0)
				_relate(other.uid, -8.0)
			return "Maybe next time."
		"pm_rel_dinner":
			if other != null:
				_relate(other.uid, 12.0)
				for mate in ut.roster:
					if not mate.is_user and mate != other:
						_relate(mate.uid, 4.0)
			return "Good night out. The squad gets on better with you."
		"pm_rel_skip":
			if other != null:
				_relate(other.uid, -3.0)
			return "You stayed in."
		"pm_rel_sorry":
			if other != null:
				_relate(other.uid, 8.0)
			_trust(1.0)
			return "Cleared the air."
		"pm_rel_fight":
			if other != null:
				_relate(other.uid, -18.0)
			me.morale = minf(100.0, me.morale + 3.0)
			return "You gave as good as you got. %s won't forget it." % (other.player_name if other != null else "They")
		"pm_rel_share":
			if other != null:
				_relate(other.uid, 12.0)
			_gain_fame(-300)
			return "You tagged %s in your next stream. Relations improved." % (other.player_name if other != null else "them")
		"pm_rel_ignore":
			if other != null:
				_relate(other.uid, -10.0)
			return "The frost continues."
		"pm_retire":
			retire()
			return "You've retired. See your legacy on the Profile page."
	return "Noted."


# =============================================================================
# Difficulty presets
# =============================================================================

func diff(key: String) -> float:
	return float((DIFFICULTIES.get(difficulty, DIFFICULTIES.Normal) as Dictionary)[key])


func set_difficulty(d: String) -> void:
	difficulty = d if DIFFICULTIES.has(d) else "Normal"
	PlayerData.refuse_mult = diff("refuse")


# =============================================================================
# Achievements (kept across saves by Game)
# =============================================================================

func _achieve(id: String) -> void:
	if Game.unlock_achievement(id):
		_news("ACHIEVEMENT UNLOCKED: %s" % String(Game.ACHIEVEMENTS[id].name))


# =============================================================================
# Staff
# =============================================================================

func staff_stars(role: String) -> int:
	return int((staff.get(role, {}) as Dictionary).get("stars", 0))


func staff_wages() -> int:
	var n := 0
	for r in staff:
		n += int(staff[r].wage)
	return n


func _new_staff(role: String, stars: int) -> Dictionary:
	var first: String = STAFF_FIRST[rng.randi() % STAFF_FIRST.size()]
	var last: String = STAFF_LAST[rng.randi() % STAFF_LAST.size()]
	var base: int = STAFF_ROLES[role].base
	return {"role": role, "name": "%s %s" % [first, last], "stars": stars, "wage": int(round(base * pow(stars, 1.6) / 50.0)) * 50}


func _refresh_staff_market() -> void:
	staff_market.clear()
	var ut := user_team()
	var top := clampi(5 - ut.league + (1 if ut.reputation > 50.0 else 0), 2, 5)
	var roles: Array = STAFF_ROLES.keys()
	for i in 6:
		var role: String = roles[i % roles.size()] if i < roles.size() else roles[rng.randi() % roles.size()]
		staff_market.append(_new_staff(role, rng.randi_range(1, top)))


func hire_staff(i: int) -> String:
	if i < 0 or i >= staff_market.size():
		return "Gone"
	var c: Dictionary = staff_market[i]
	var fee := int(c.wage) * 4
	if money < fee:
		return "Need $%s (4 weeks' wages up front)" % _fmt(fee)
	var role := String(c.role)
	if staff.has(role):
		var old: Dictionary = staff[role]
		money -= int(old.wage) * 4
		_ledger("Severance: %s (%s)" % [old.name, role], -int(old.wage) * 4)
	money -= fee
	_ledger("Hired %s (%s)" % [c.name, role], -fee)
	staff[role] = c
	staff_market.remove_at(i)
	_news("STAFF: %s joins as %s (%d stars)." % [c.name, role, int(c.stars)])
	var full := STAFF_ROLES.keys().all(func(r: String) -> bool: return staff_stars(r) >= 4)
	if full:
		_achieve("dream_team")
	return ""


func fire_staff(role: String) -> String:
	if not staff.has(role):
		return "Nobody in that role"
	var old: Dictionary = staff[role]
	var fee := int(old.wage) * 4
	money -= fee
	_ledger("Severance: %s (%s)" % [old.name, role], -fee)
	staff.erase(role)
	_news("STAFF: %s (%s) has left the club." % [old.name, role])
	return ""


# =============================================================================
# Facilities
# =============================================================================

func fac(name: String) -> int:
	if name == "Training Center":
		return facility
	return int(facilities.get(name, 0))


func fac_cost(name: String) -> int:
	var lv := fac(name)
	var info: Dictionary = FACILITIES[name]
	if lv >= int(info.max):
		return -1
	return int(info.cost) * (lv + 1)


func fac_block(name: String) -> String:
	var need := String(FACILITIES[name].needs)
	if need == "":
		return ""
	var parts := need.split(":")
	var lv := int(parts[1]) if parts.size() > 1 else 1
	if fac(parts[0]) < lv:
		return "Needs %s L%d" % [parts[0], lv]
	return ""


func upgrade_fac(name: String) -> String:
	var cost := fac_cost(name)
	if cost < 0:
		return "Already at the top level"
	var b := fac_block(name)
	if b != "":
		return b
	if money < cost:
		return "Need $%s" % _fmt(cost)
	money -= cost
	if name == "Training Center":
		facility += 1
	else:
		facilities[name] = fac(name) + 1
	_ledger("%s level %d" % [name, fac(name)], -cost)
	_news("FACILITIES: %s upgraded to level %d." % [name, fac(name)])
	if name == "Youth Academy" and fac(name) == 1:
		_academy_intake()
	if FACILITIES.keys().all(func(f: String) -> bool: return fac(f) >= 3):
		_achieve("campus")
	return ""


func facility_upkeep() -> int:
	var n := 0
	for f: String in FACILITIES:
		n += int(FACILITIES[f].upkeep) * (fac(f) - (1 if f == "Training Center" else 0))
	return maxi(0, n)


# =============================================================================
# Youth academy
# =============================================================================

func academy_capacity() -> int:
	var lv := fac("Youth Academy")
	return 0 if lv == 0 else 3 + lv


func _academy_intake() -> void:
	var lv := fac("Youth Academy")
	if lv == 0:
		return
	var n := mini(1 + lv, academy_capacity() - academy.size())
	for i in n:
		var pr := _new_player(rng.randf_range(30.0, 38.0) + lv * 3.0, "")
		pr.age = rng.randi_range(16, 17)
		pr.potential = clampi(pr.rating() + rng.randi_range(22, 38 + lv * 6), 50, 99)
		pr.salary = 0
		academy.append(pr)
		_news("ACADEMY: %s (%s, %d) joins the academy. Potential looks %s." % [pr.player_name, pr.role, pr.age, UI_pot(pr)])


static func UI_pot(p: PlayerData) -> String:
	var room := p.potential - p.rating()
	return "elite" if room >= 35 else ("very good" if room >= 25 else ("good" if room >= 15 else "limited"))


func _academy_week() -> void:
	var k := 1.0 + 0.1 * staff_stars("Head Coach") + 0.15 * fac("Youth Academy")
	for pr in academy:
		var room := clampf((pr.potential - pr.rating_exact()) / 8.0, 0.0, 1.0)
		for key: String in PlayerData.STAT_KEYS:
			pr.set_stat(key, pr.stat(key) + rng.randfn(0.14, 0.08) * k * maxf(room, 0.1))


func promote_academy(pr: PlayerData) -> String:
	if not academy.has(pr):
		return "Not in the academy"
	var ut := user_team()
	if ut.roster.size() >= MAX_ROSTER:
		return "Roster full (%d)" % MAX_ROSTER
	academy.erase(pr)
	pr.salary = int(PlayerData.salary_for_rating(pr.rating_exact()) * 0.7 / 50.0) * 50
	pr.contract_until = season + 2
	pr.joined = stamp()
	pr.morale = 85.0
	ut.roster.append(pr)
	_news("ACADEMY: %s is promoted to the first team." % pr.player_name)
	_achieve("homegrown")
	return ""


func release_academy(pr: PlayerData) -> void:
	academy.erase(pr)
	free_agents.append(pr)
	pr.salary = PlayerData.salary_for_rating(pr.rating_exact())


func sell_academy(pr: PlayerData) -> String:
	var buyers: Array = teams.filter(func(t: TeamData) -> bool: return t != user_team() and t.money > pr.market_value() + 20000) # They make room (see _trim_roster).
	if buyers.is_empty():
		return "No club can afford them right now"
	var b: TeamData = buyers[rng.randi() % buyers.size()]
	var fee := pr.market_value()
	academy.erase(pr)
	b.money -= fee
	b.roster.append(pr)
	pr.joined = stamp()
	pr.salary = PlayerData.salary_for_rating(pr.rating_exact())
	pr.contract_until = season + 2
	_trim_roster(b, pr)
	_earn(fee, "Academy sale: %s to %s" % [pr.player_name, b.team_name])
	_note_transfer(pr, null, b, fee)
	return ""


func _academy_season() -> void:
	for pr in academy.duplicate():
		pr.age += 1
		if pr.age >= 20:
			release_academy(pr)
			_news("ACADEMY: %s aged out of the academy and left as a free agent." % pr.player_name)
	_academy_intake()


# =============================================================================
# Scouting fog: other clubs' players are estimates until scouted
# =============================================================================

func known(p: PlayerData) -> bool:
	if mode != "manager" or p == null:
		return true
	return scouted.has(p.uid) or user_team().roster.has(p) or academy.has(p) or former_players.has(p.uid)


func scout_width() -> float:
	return maxf(2.0, 14.0 - 2.0 * staff_stars("Scout") - 1.5 * fac("Analyst Room"))


func _noise(p: PlayerData, key: String) -> float:
	return float(absi(hash("%d:%s" % [p.uid, key])) % 1000) / 1000.0 * 2.0 - 1.0


func est_stat(p: PlayerData, key: String) -> float:
	if known(p):
		return p.stat(key)
	return clampf(p.stat(key) + _noise(p, key) * scout_width() * 0.5, PlayerData.MIN_STAT, PlayerData.MAX_STAT)


func est_rating(p: PlayerData) -> float:
	if known(p):
		return p.rating_exact()
	var t := 0.0
	for k: String in PlayerData.STAT_KEYS:
		t += est_stat(p, k)
	return t / PlayerData.STAT_KEYS.size()


func stat_range(p: PlayerData, key: String) -> Array:
	var c := est_stat(p, key)
	var h := scout_width() * 0.5
	return [int(clampf(c - h, 20, 100)), int(clampf(c + h, 20, 100))]


func queue_scout(p: PlayerData) -> String:
	if known(p):
		return "Already scouted"
	if scout_queue.has(p.uid):
		return "Already on the scouting list"
	scout_queue.append(p.uid)
	return ""


func _scout_week() -> void:
	var n := 1 + staff_stars("Scout")
	while n > 0 and not scout_queue.is_empty():
		var uid: int = scout_queue.pop_front()
		var p := find_player(uid)
		if p == null:
			for fa in free_agents:
				if fa.uid == uid:
					p = fa
		if p != null:
			scouted[uid] = true
			_news("SCOUT REPORT: %s is a %d-rated %s (potential %s)." % [p.player_name, p.rating(), p.role, UI_pot(p)])
		n -= 1


# =============================================================================
# Board, job security and job offers
# =============================================================================

func _make_board_objective() -> void:
	var ut := user_team()
	var lg := league_teams(ut.league)
	lg.sort_custom(func(a: TeamData, b: TeamData) -> bool: return a.rating_exact() > b.rating_exact())
	var rank := lg.find(ut) + 1
	var obj := {}
	if rank <= 3 and ut.league > 0:
		obj = {"kind": "pos", "target": PROMOTE, "text": "Win promotion (top %d)" % PROMOTE}
	elif rank <= 3:
		obj = {"kind": "pos", "target": 3, "text": "Finish in the top 3"}
	elif rank <= 9:
		obj = {"kind": "pos", "target": PLAYOFF_SIZE, "text": "Make the playoffs (top %d)" % PLAYOFF_SIZE}
	elif ut.league < LEAGUES.size() - 1:
		obj = {"kind": "pos", "target": TEAMS_PER_LEAGUE - PROMOTE, "text": "Avoid relegation"}
	else:
		obj = {"kind": "pos", "target": 12, "text": "Finish in the top 12"}
	obj["confidence"] = float(board.get("confidence", 60.0)) * 0.5 + 30.0
	board = obj


func board_status() -> String:
	var ut := user_team()
	var pos := standings(ut.league).find(ut) + 1
	return "On track (#%d)" % pos if pos <= int(board.get("target", 16)) else "Behind (#%d)" % pos


func _board_week() -> void:
	if board.is_empty() or sacked:
		return
	var ut := user_team()
	var c := float(board.confidence)
	var patience := diff("board")
	for mt in all_week_matches():
		if mt.winner == -1 or (mt.a != user_team_idx and mt.b != user_team_idx):
			continue
		if mt.winner == user_team_idx:
			c += 1.5
		elif mt.winner >= 0:
			c -= 2.0 / patience
	if money < 0:
		c -= 2.0 / patience
	var pos := standings(ut.league).find(ut) + 1
	if week >= 8 and week <= LEAGUE_WEEKS and pos > int(board.target) + 3:
		c -= 0.8 / patience
	board.confidence = clampf(c, 0.0, 100.0)
	if board.confidence <= 10.0 and week >= 6:
		_sack("The board has lost faith after a run of poor results.")


func _board_season_end() -> void:
	if board.is_empty() or sacked:
		return
	var ut := user_team()
	var pos := standings(ut.league).find(ut) + 1
	var met := pos <= int(board.target)
	board.confidence = clampf(float(board.confidence) + (25.0 if met else -30.0 / diff("board")), 0.0, 100.0)
	_news("BOARD: objective \"%s\" %s (finished #%d). Confidence %d." % [board.text, "met" if met else "missed", pos, int(board.confidence)])
	if board.confidence <= 15.0:
		_sack("You missed the board's objective: %s." % board.text)
		return
	# Doing well: bigger clubs come calling.
	if board.confidence >= 70.0 and pos <= 4:
		var pool: Array = []
		for i in teams.size():
			var t := teams[i]
			if t != ut and (t.league < ut.league or (t.league == ut.league and t.reputation > ut.reputation + 5.0)) and t.league >= ut.league - 1:
				pool.append(i)
		pool.shuffle()
		for idx in pool.slice(0, 2):
			job_offers.append({"team": idx, "note": "%s (%s) want you as their manager." % [teams[idx].team_name, LEAGUES[teams[idx].league].name], "forced": false})
		if not job_offers.is_empty():
			_msg("board", "Job offers", "Your work at %s has been noticed: %d club%s want to talk. See Club > Board. Leaving means a new squad, budget and board; your staff come with you." % [ut.team_name, job_offers.size(), "s" if job_offers.size() > 1 else ""])


func _sack(why: String) -> void:
	sacked = true
	var ut := user_team()
	_news("SACKED: %s %s" % [ut.team_name, why])
	_wire("%s sack their manager" % ut.team_name, "bad")
	_achieve("sacked")
	job_offers.clear()
	var pool: Array = []
	for i in teams.size():
		var t := teams[i]
		if t != ut and t.league >= ut.league and t.rating_exact() <= ut.rating_exact() + 3.0:
			pool.append(i)
	pool.shuffle()
	for idx in pool.slice(0, 3):
		job_offers.append({"team": idx, "note": "%s (%s) will give you a chance." % [teams[idx].team_name, LEAGUES[teams[idx].league].name], "forced": true})
	_msg("board", "You've been sacked", "%s Pick one of %d job offers (Club > Board) to carry on." % [why, job_offers.size()])


func accept_job(i: int) -> String:
	if i < 0 or i >= job_offers.size():
		return "Offer gone"
	var o: Dictionary = job_offers[i]
	var dest: TeamData = teams[int(o.team)]
	var from := user_team()
	var bigger := dest.league < from.league
	_switch_club(int(o.team))
	if bigger and not bool(o.forced):
		_achieve("upward")
	return ""


func decline_job(i: int) -> String:
	if sacked and job_offers.size() <= 1:
		return "You need a job: this is your last offer"
	job_offers.remove_at(i)
	return ""


## You take over another club: its squad, budget and board. Staff follow you;
## the old club keeps its sponsors, loans, academy and facilities.
func _switch_club(idx: int) -> void:
	var old := user_team()
	old.is_user_team = false
	old.manual_lineup = false
	old.money = maxi(money, int(LEAGUES[old.league].budget * 0.3))
	_refill_roster(old)
	for pr in academy:
		free_agents.append(pr)
	academy.clear()
	sponsors.clear()
	sponsor_offers.clear()
	loans.clear()
	debt_weeks = 0
	incoming.clear()
	scout_queue.clear()
	user_team_idx = idx
	var t := teams[idx]
	t.is_user_team = true
	t.manual_lineup = true
	money = maxi(t.money, int(LEAGUES[t.league].budget * 0.3))
	facility = clampi(4 - t.league, 1, 5)
	facilities = {"Gaming House": clampi(3 - t.league, 0, 3), "Medical Room": clampi(2 - t.league, 0, 3)}
	var first := _make_sponsor_offer("Main", "Steady")
	_sign_sponsor(first)
	for slot in ["Apparel", "Partner"]:
		sponsor_offers.append(_make_sponsor_offer(slot))
	sacked = false
	job_offers.clear()
	affiliate_idx = -1
	club_fans = int(t.reputation * 400.0) + 500
	merch_level = 0
	board = {}
	_make_board_objective()
	board.confidence = 60.0
	_refresh_staff_market()
	_news("NEW JOB: you are the new manager of %s (%s), leaving %s." % [t.team_name, LEAGUES[t.league].name, old.team_name])
	_wire("%s appoint a new manager (from %s)" % [t.team_name, old.team_name], "deal")


# =============================================================================
# Contract clauses
# =============================================================================

## Terms for a deal. release: 0 (none) or a multiple of market value.
func contract_terms(p: PlayerData, release: float, loyalty: bool, appearance: bool) -> Dictionary:
	var base := float(PlayerData.salary_for_rating(p.rating_exact()))
	var wage := base
	if release > 0.0:
		wage *= {2.0: 0.95, 1.5: 0.9, 1.2: 0.85}.get(release, 1.0)
	if loyalty:
		wage *= 0.95
	var fee := 0
	if appearance:
		wage *= 0.75
		fee = int(round(base * 0.4 / 50.0)) * 50
	return {"wage": int(round(wage / 50.0)) * 50, "release": int(p.market_value() * release) if release > 0.0 else 0,
		"loyalty": int(base * 10) if loyalty else 0, "appearance": fee}


func _apply_terms(p: PlayerData, terms: Dictionary) -> void:
	if terms.is_empty():
		p.salary = PlayerData.salary_for_rating(p.rating_exact())
		p.release_clause = 0
		p.loyalty_bonus = 0
		p.appearance_fee = 0
		return
	p.salary = int(terms.wage)
	p.release_clause = int(terms.release)
	p.loyalty_bonus = int(terms.loyalty)
	p.appearance_fee = int(terms.appearance)
	if p.loyalty_bonus > 0:
		p.morale = minf(100.0, p.morale + 10.0)


func _pay_loyalty(p: PlayerData) -> void:
	if p.loyalty_bonus <= 0:
		return
	money -= p.loyalty_bonus
	_ledger("Loyalty bonus: %s" % p.player_name, -p.loyalty_bonus)
	_news("%s collects a $%s loyalty bonus." % [p.player_name, _fmt(p.loyalty_bonus)])
	p.loyalty_bonus = 0


## AI clubs paying release clauses on your players (windows only).
func _release_clauses() -> void:
	if not window_open():
		return
	var ut := user_team()
	for p in ut.roster.duplicate():
		if p.release_clause <= 0 or rng.randf() > 0.12 * diff("ai"):
			continue
		var buyers: Array = teams.filter(func(t: TeamData) -> bool:
			return t != ut and t.league <= ut.league and t.money >= p.release_clause and t.roster.size() > 0 and p.rating_exact() > t.roster[t.roster.size() - 1].rating_exact())
		if buyers.is_empty():
			continue
		var b: TeamData = buyers[rng.randi() % buyers.size()]
		var fee: int = p.release_clause
		b.money -= fee
		p.release_clause = 0
		p.loyalty_bonus = 0
		p.appearance_fee = 0
		_move_player(p, ut, b)
		_trim_roster(b, p)
		_earn(fee, "Release clause: %s to %s" % [p.player_name, b.team_name])
		_note_transfer(p, ut, b, fee)
		_news("RELEASE CLAUSE: %s paid $%s and %s is gone." % [b.team_name, _fmt(fee), p.player_name])
		_msg("info", "%s triggered %s's release clause" % [b.team_name, p.player_name], "%s paid the full $%s clause, so the player leaves whether you like it or not." % [b.team_name, _fmt(fee)])
		_achieve("fine_print")


func _appearance_fees(players: Array) -> void:
	var total := 0
	for p: PlayerData in players:
		total += p.appearance_fee
	if total > 0:
		money -= total
		_ledger("Appearance fees", -total)


# =============================================================================
# Team chemistry: time together in the lineup
# =============================================================================

func _weeks_at(st: int) -> int:
	return (st / 100) * SEASON_WEEKS + st % 100


func chemistry(t: TeamData) -> float:
	var s := t.starters(5)
	if s.is_empty():
		return 50.0
	var now := _weeks_at(stamp())
	var total := 0.0
	for p in s:
		var wks := 60 if p.joined <= 0 else now - _weeks_at(p.joined)
		total += clampf(float(wks) / 30.0, 0.0, 1.0)
	var c := total / s.size() * 90.0 + 10.0
	for p in s:
		if PlayerData.persona_of(p) == "Leader":
			c += 5.0
	if t.is_user_team and mode == "manager":
		c += fac("Bootcamp") * 4.0
	return clampf(c, 0.0, 100.0)


func chem_bonus(t: TeamData) -> float:
	return (chemistry(t) - 55.0) / 22.5


# =============================================================================
# My Player: lifestyle, streaming, relationships, traits
# =============================================================================

func buy_asset(id: String) -> String:
	return life().buy(id)


func sell_asset(id: String) -> String:
	return life().sell(id)


func lifestyle_upkeep() -> int:
	return life().upkeep()


## My Player lifestyle (created on demand; saved under "life").
func life() -> Lifestyle:
	if lifestyle == null:
		lifestyle = Lifestyle.new(self)
	return lifestyle


func stream_income() -> int:
	var s: Dictionary = STREAM[stream_level]
	return int(fame * float(s.income) * (1.5 if assets.has("studio") else 1.0))


func set_stream(level: String) -> void:
	if STREAM.has(level):
		stream_level = level


func _lifestyle_week() -> void:
	var p := user_player
	wallet += stream_income() - lifestyle_upkeep()
	var s: Dictionary = STREAM[stream_level]
	_gain_fame(int(fame * float(s.fans)) + (40 if stream_level != "Off" else 0))
	fatigue += float(s.fatigue)
	if String(last_training.get("intensity", "")) == "Hard" and trained_this_week:
		fatigue += 8.0
	life().weekly() # Homes, chef, pets, extras, staff, investments.
	fatigue = clampf(fatigue, 0.0, 100.0)
	if fatigue > 40.0:
		p.form -= (fatigue - 40.0) / 30.0
	if fatigue >= 80.0 and not _has_open_kind("fatigue"):
		_msg("fatigue", "You're running on empty", "Fatigue %d/100: your form is suffering and you're more injury-prone. Stream less, train lighter, or hire a chef." % int(fatigue), [["OK", "ok"]], p.uid)
	p.form = clampf(p.form, -8.0, 8.0)


func relation(uid: int) -> float:
	return float(relations.get(uid, 0.0))


## My Player social systems (created on demand; saved under "social").
func soc() -> Social:
	if social == null:
		social = Social.new(self)
	return social


## "friend", "rival" or "": how a player feels about you (My Player). Used by
## match chat. Manager mode: always "".
func relation_to_user(p: PlayerData) -> String:
	if mode != "player" or user_player == null or p == null:
		return ""
	return soc().kind(p)


## -1..1: negative = rival, positive = friend (My Player; 0 in manager mode).
func relation_strength(p: PlayerData) -> float:
	if mode != "player" or user_player == null or p == null:
		return 0.0
	return soc().strength(p)


## True if your club treats this team as a rival: trash talk, a recent final,
## the derby, or your top rival's club.
func team_rivalry(t: TeamData) -> bool:
	if t == null or teams.is_empty():
		return false
	if mode != "player":
		return t != user_team() and (team_index(t) == trash_target or derby_rival(user_team()) == t)
	if user_player == null:
		return false
	return soc().team_rivalry(t)


func _relate(uid: int, d: float) -> void:
	relations[uid] = clampf(relation(uid) + d, -100.0, 100.0)


static func relation_text(v: float) -> String:
	if v >= 50.0:
		return "Close friend"
	if v >= 20.0:
		return "Friendly"
	if v > -20.0:
		return "Neutral"
	if v > -50.0:
		return "Tense"
	return "Rival"


## Teammate events: dinners, blame after losses, jealousy over your fame.
func _relationship_events() -> void:
	var ut := user_team()
	var mates: Array = ut.roster.filter(func(s: PlayerData) -> bool: return not s.is_user)
	if mates.is_empty() or _has_open_kind("dressing"):
		return
	var mate: PlayerData = mates[rng.randi() % mates.size()]
	var roll := rng.randf()
	if roll < 0.05:
		_msg("dressing", "%s invites you to a team dinner" % mate.player_name, "A few of the squad are going out. Good for the dressing room.",
			[["Go", "pm_rel_dinner"], ["Skip it", "pm_rel_skip"]], mate.uid)
	elif roll < 0.09 and ut.streak <= -2:
		_msg("dressing", "%s blames you for the losing run" % mate.player_name, "In the team chat, %s says your positioning is costing rounds." % mate.player_name,
			[["Apologise", "pm_rel_sorry"], ["Fire back", "pm_rel_fight"]], mate.uid)
	elif roll < 0.12 and fame > 8000:
		_msg("dressing", "%s seems jealous of your fame" % mate.player_name, "Your follower count keeps climbing and %s has gone quiet around you." % mate.player_name,
			[["Share the spotlight", "pm_rel_share"], ["Ignore it", "pm_rel_ignore"]], mate.uid)


## Match-day bonus from how you get on with today's teammates.
func _relationship_mods() -> void:
	var ut := user_team()
	var total := 0.0
	for s in ut.starters(5):
		if s.is_user:
			continue
		var r := relation(s.uid)
		total += r
		s.match_mod += r / 100.0
	user_player.match_mod += clampf(total / 250.0, -1.5, 1.5)


func _check_traits() -> void:
	var p := user_player
	var logs: Array = p.match_log.slice(maxi(0, p.match_log.size() - 20))
	if logs.size() < 20:
		if highlights >= 10 and not traits.has("clutch"):
			_unlock_trait("clutch")
		return
	var k := 0.0
	var d := 0.0
	var rounds := 0.0
	var adr := 0.0
	var r := 0.0
	var low := false
	var big: Array = []
	for e in logs:
		var sc := String(e.score).split("-")
		rounds += float(int(sc[0]) + int(sc[1]))
		k += float(e.k)
		d += float(e.d)
		adr += float(e.adr)
		r += float(e.r)
		if float(e.r) < 0.8:
			low = true
	for e in p.match_log:
		var lbl := String(e.get("label", ""))
		if (lbl.contains("Cup") or lbl.contains("Playoffs") or lbl.contains("Major")) and float(e.r) >= 1.25:
			big.append(e)
	var conds := {"entry_king": k / rounds >= 0.85, "survivor": d / rounds < 0.55, "damage": adr / logs.size() >= 90.0,
		"awp_god": p.role == "AWPer" and r / logs.size() >= 1.2, "consistent": not low, "big_stage": big.size() >= 5, "clutch": highlights >= 10}
	for id: String in conds:
		if conds[id] and not traits.has(id):
			_unlock_trait(id)


func _unlock_trait(id: String) -> void:
	traits.append(id)
	var info: Dictionary = TRAITS[id]
	for key: String in info.stats:
		user_player.set_stat(key, user_player.stat(key) + 1.5)
	_gain_fame(1500)
	_news("SIGNATURE TRAIT: %s (%s)." % [info.name, info.need])
	_msg("perk", "Signature trait: %s" % info.name, "%s. +1.5 to %s." % [info.need, ", ".join((info.stats as Array).map(func(s: String) -> String: return PlayerData.STAT_NAMES[s]))], [["Nice", "ok"]], user_player.uid)


func note_highlights(h: Dictionary) -> void:
	if user_player == null:
		return
	for p in h:
		if p == user_player or (p is PlayerData and (p as PlayerData).is_user):
			highlights += int(h[p])
	if mode == "player":
		if highlights >= 10:
			_achieve("highlight_reel")
		_check_traits()


# =============================================================================
# World Cup (every second season, between seasons)
# =============================================================================

func _national_squad(nation: String) -> Array:
	var pool: Array = []
	for t in teams:
		for p in t.roster:
			if p.nation == nation:
				pool.append(p)
	pool.sort_custom(func(a: PlayerData, b: PlayerData) -> bool: return a.rating_exact() + a.form * 0.6 > b.rating_exact() + b.form * 0.6)
	return pool.slice(0, 5)


func _world_cup() -> Dictionary:
	var sides: Array = []
	for n: String in PlayerData.all_nations():
		var sq := _national_squad(n)
		if sq.size() < 5:
			continue
		var st := 0.0
		for p in sq:
			st += p.rating_exact() + p.form * 0.6
		sides.append({"nation": n, "squad": sq, "str": st / sq.size()})
	sides.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.str > b.str)
	sides = sides.slice(0, 8)
	if sides.size() < 8:
		return {}
	var order := [0, 7, 3, 4, 1, 6, 2, 5]
	var alive: Array = order.map(func(i: int) -> Dictionary: return sides[i])
	var rounds := ["Quarter-final", "Semi-final", "Final"]
	var games: Array = []
	var me := user_player
	var my_nation := me.nation if me != null and mode == "player" else ""
	var picked := false
	for sd in sides:
		if me != null and (sd.squad as Array).has(me):
			picked = true
	var my_place := ""
	for ri in 3:
		var next: Array = []
		for k in range(0, alive.size(), 2):
			var a: Dictionary = alive[k]
			var b: Dictionary = alive[k + 1]
			var pa := 1.0 / (1.0 + exp(-(float(a.str) - float(b.str)) / 14.0))
			var s := [0, 0]
			while s[0] < ROUNDS_TO_WIN and s[1] < ROUNDS_TO_WIN:
				s[0 if rng.randf() < pa else 1] += 1
			var win: Dictionary = a if s[0] > s[1] else b
			var lose: Dictionary = b if s[0] > s[1] else a
			games.append("%s: %s %d-%d %s" % [rounds[ri], a.nation, s[0], s[1], b.nation])
			next.append(win)
			if picked and lose.nation == my_nation:
				my_place = rounds[ri]
			if picked and (a.nation == my_nation or b.nation == my_nation):
				caps += 1
				_gain_fame(2000)
		alive = next
	var champ: Dictionary = alive[0]
	var summary := {"s": season, "winner": champ.nation, "log": games, "you": my_place if my_place != "" else ("Champion" if picked and champ.nation == my_nation else ("Not picked" if my_nation != "" else ""))}
	champions.append({"s": season, "name": "World Cup", "team": champ.nation})
	_wire("%s WIN THE WORLD CUP" % String(champ.nation).to_upper(), "good")
	_news("WORLD CUP: %s are world champions. %s" % [champ.nation, games[games.size() - 1]])
	if mode == "player" and me != null:
		if picked:
			if champ.nation == my_nation:
				trophies.append({"s": season, "name": "World Cup (%s)" % my_nation, "place": 1, "team": my_nation})
				me.add_honour("World Cup Champion", season, 95)
				_award("World Cup winner", "won the World Cup with %s" % my_nation, 20000)
				_achieve("world_champ")
			else:
				_news("WORLD CUP: %s went out in the %s." % [my_nation, my_place.to_lower()])
			_msg("award", "World Cup: %s" % ("champions!" if champ.nation == my_nation else "out in the " + my_place.to_lower()), "You represented %s. %s" % [my_nation, "\n".join(games)], [["OK", "ok"]], me.uid)
		else:
			_news("WORLD CUP: you weren't picked for %s's squad." % my_nation)
	return summary


# =============================================================================
# History: records, champions, Hall of Fame, season reviews
# =============================================================================

func _record(key: String, value: float, holder: String, team: String) -> void:
	var cur: Dictionary = records.get(key, {})
	if cur.is_empty() or value > float(cur.value):
		records[key] = {"value": value, "holder": holder, "team": team, "s": season, "w": week}


func _note_transfer(p: PlayerData, from: TeamData, to: TeamData, fee: int) -> void:
	season_transfers.append({"fee": fee, "player": p.player_name, "from": from.team_name if from != null else "Free agent", "to": to.team_name})
	while season_transfers.size() > 120:
		season_transfers.pop_front()
	_record("Biggest transfer fee", fee, p.player_name, "%s to %s" % [from.team_name if from != null else "free", to.team_name])


static func base_cup_name(n: String) -> String:
	var i := n.rfind(" S")
	if i > 0 and n.substr(i + 2).is_valid_int():
		return n.substr(0, i)
	return n


func _hall_score(p: PlayerData) -> int:
	return p.titles * 40 + p.matches_played / 4 + maxi(0, p.peak - 70) * 6 + p.career_kills / 60


func _consider_hall(p: PlayerData, team: String) -> void:
	var sc := _hall_score(p)
	if sc < 150 and not p.is_user:
		return
	hall_of_fame.append({"name": p.player_name, "age": p.age, "titles": p.titles, "matches": p.matches_played, "kills": p.career_kills,
		"kd": snappedf(p.career_kd(), 0.01), "peak": p.peak, "team": team, "s": season, "score": sc, "user": p.is_user, "nation": p.nation})
	hall_of_fame.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.score) > int(b.score))
	while hall_of_fame.size() > 100:
		hall_of_fame.pop_back()
	if sc >= 150:
		_wire("HALL OF FAME: %s (%d titles, peak %d)" % [p.player_name, p.titles, p.peak], "good")


func _season_records() -> void:
	for t in teams:
		_record("Most titles (club)", t.titles, t.team_name, LEAGUES[t.league].short)
		for p in t.roster:
			_record("Most career kills", p.career_kills, p.player_name, t.team_name)
			_record("Most trophies (player)", p.titles, p.player_name, t.team_name)
			_record("Highest peak rating", p.peak, p.player_name, t.team_name)


## Built at the end of each season, before anything resets.
func _start_review() -> void:
	var leagues: Array = []
	for l in LEAGUES.size():
		var table := standings(l)
		var po := ""
		for t in tournaments:
			if t.kind == "playoff" and int(t.league) == l and t.status == "done":
				po = teams[_team_with_place(t, 1)].team_name
		leagues.append({"name": LEAGUES[l].name, "top": table[0].team_name, "record": "%d-%d" % [table[0].wins, table[0].losses], "playoffs": po, "up": [], "down": []})
	var cups: Array = []
	for t in tournaments:
		if t.kind == "cup" and t.status == "done":
			cups.append({"name": String(t.name), "team": teams[_team_with_place(t, 1)].team_name})
	var tr := season_transfers.duplicate()
	tr.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.fee) > int(b.fee))
	var ut := user_team()
	var you := {}
	if mode == "manager":
		you = {"team": ut.team_name, "pos": standings(ut.league).find(ut) + 1, "record": "%d-%d" % [ut.wins, ut.losses], "money": money,
			"board": "%s: %s" % [board.get("text", "-"), board_status()] if not board.is_empty() else ""}
	elif user_player != null:
		var p := user_player
		you = {"team": ut.team_name, "pos": standings(ut.league).find(ut) + 1, "record": "%d-%d" % [ut.wins, ut.losses],
			"m": int(p.season_stats.get("m", 0)), "avg": snappedf(p.season_avg_rating(), 0.01), "kd": snappedf(p.season_kd(), 0.01), "fame": fame}
	_review = {"s": season, "leagues": leagues, "cups": cups, "awards": [], "transfers": tr.slice(0, 6), "you": you, "world_cup": {}}


## One award for the end-of-season ceremony.
func _ceremony(title: String, p: PlayerData, detail: String) -> void:
	if _review.is_empty():
		return
	if not _review.has("ceremony"):
		_review["ceremony"] = []
	var t := owner_of(p)
	(_review.ceremony as Array).append({"title": title, "name": p.player_name, "team": t.team_name if t != null else "", "detail": detail, "you": p.is_user})


func _finish_review() -> void:
	if _review.is_empty():
		return
	reviews.append(_review)
	while reviews.size() > 12:
		reviews.pop_front()
	review_pending = true
	_review = {}
	season_transfers.clear()


# =============================================================================
# Manager: personalities, press conferences, derbies, fans & merch, loans,
# the affiliate (second roster)
# =============================================================================

## Weekly effects of player personalities on every club.
func _persona_week(t: TeamData, starting: Array) -> void:
	var leaders := 0
	for s: PlayerData in starting:
		if PlayerData.persona_of(s) == "Leader":
			leaders += 1
	var mentors := 0
	var trouble: Array = []
	for p in t.roster:
		var pe := PlayerData.persona_of(p)
		if pe == "Mentor":
			mentors += 1
		elif pe == "Troublemaker":
			trouble.append(p)
	if leaders > 0:
		for s: PlayerData in starting:
			s.morale = minf(100.0, s.morale + 0.5 * leaders)
	if mentors > 0:
		for p in t.roster:
			if p.age <= 21 and PlayerData.persona_of(p) != "Mentor":
				var k: String = PlayerData.STAT_KEYS[rng.randi() % PlayerData.STAT_KEYS.size()]
				p.set_stat(k, p.stat(k) + 0.08 * mentors)
	for tp: PlayerData in trouble:
		if rng.randf() > 0.04:
			continue
		var others: Array = t.roster.filter(func(x: PlayerData) -> bool: return x != tp and not x.is_user)
		if others.is_empty():
			continue
		var victim: PlayerData = others[rng.randi() % others.size()]
		for o: PlayerData in others:
			o.morale = maxf(0.0, o.morale - 2.0)
		if t == user_team() and mode == "manager" and not _has_open_kind("trouble"):
			_msg("trouble", "%s fell out with %s" % [tp.player_name, victim.player_name],
				"A shouting match after practice. The squad is rattled (morale down). %s is a known troublemaker." % tp.player_name,
				[["Fine them", "mg_fine"], ["Back them", "mg_back"], ["Transfer-list them", "list"]], tp.uid)
		elif t.league <= 1:
			_wire("Bust-up at %s: %s and %s" % [t.team_name, tp.player_name, victim.player_name], "bad")


func _resolve_mgr(m: Dictionary, action: String, p: PlayerData) -> String:
	var data: Dictionary = m.get("data", {})
	var ut := user_team()
	match action:
		"mg_fine":
			if p != null:
				p.morale = maxf(0.0, p.morale - 12.0)
				for o in ut.roster:
					if o != p:
						o.morale = minf(100.0, o.morale + 3.0)
			return "Fined. The rest of the squad appreciates it."
		"mg_back":
			if p != null:
				p.morale = minf(100.0, p.morale + 8.0)
				for o in ut.roster:
					if o != p:
						o.morale = maxf(0.0, o.morale - 3.0)
			return "You backed them. Some of the squad think it's favouritism."
		"mg_calm":
			board.confidence = clampf(float(board.get("confidence", 50.0)) + 2.0, 0.0, 100.0)
			for o in ut.roster:
				o.morale = minf(100.0, o.morale + 2.0)
			return "Measured and professional. The board likes it."
		"mg_promise":
			for o in ut.roster:
				o.morale = minf(100.0, o.morale + 5.0)
			press_pledge = {"team": int(data.team), "s": season, "w": week}
			return "You promised a win. The squad is fired up. Now deliver."
		"mg_mind":
			if rng.randf() < 0.6:
				rattled_team = int(data.team)
				return "It got under their skin: they look rattled."
			trash_target = int(data.team)
			return "It backfired: they're fired up now."
	return "Noted."


## Before notable matches: cups, derbies, top-of-the-table clashes.
func _press_conference() -> void:
	for m in inbox:
		if not bool(m.done) and String(m.kind) == "press" and (int(m.s) != season or int(m.w) != week):
			m.done = true
			m.result = "You skipped it."
	var mt := user_match_this_week()
	if mt.is_empty() or _has_open_kind("press"):
		return
	var ui := team_index(user_team())
	var oi: int = mt.b if mt.a == ui else mt.a
	var opp := teams[oi]
	var table := standings(user_team().league)
	var big: bool = mt.kind != "league" or is_derby(mt) or table.find(opp) < 3 or (week >= LEAGUE_WEEKS - 2 and table.find(user_team()) < 4)
	if not big:
		return
	var why := "the derby" if is_derby(mt) else (String(mt.label) if mt.kind != "league" else "a top-of-the-table clash")
	_msg("press", "Press conference: %s vs %s" % [user_team().team_name, opp.team_name],
		"Reporters want your view before %s. Stay calm (the board likes it), promise a win (the squad loves it, the board will hold you to it), or play mind games (60%% they're rattled, 40%% it fires them up)." % why,
		[["Stay calm", "mg_calm"], ["Promise a win", "mg_promise"], ["Mind games", "mg_mind"]], 0, {"team": oi})


## Local rivals: within a league, clubs pair up by their place in the world list.
func derby_rival(t: TeamData) -> TeamData:
	if t == null:
		return null
	var lg := league_teams(t.league)
	lg.sort_custom(func(a: TeamData, b: TeamData) -> bool: return teams.find(a) < teams.find(b))
	var i := lg.find(t)
	var j := i + 1 if i % 2 == 0 else i - 1
	return lg[j] if j >= 0 and j < lg.size() else null


func is_derby(mt: Dictionary) -> bool:
	if mt.is_empty() or mt.kind != "league":
		return false
	return derby_rival(teams[int(mt.a)]) == teams[int(mt.b)]


func _derby_result(mt: Dictionary) -> void:
	if not is_derby(mt) or mt.winner < 0:
		return
	var w_t: TeamData = teams[mt.winner]
	var l_t: TeamData = teams[mt.b if mt.winner == mt.a else mt.a]
	w_t.reputation = clampf(w_t.reputation + 2.0, 0.0, 100.0)
	l_t.reputation = clampf(l_t.reputation - 1.0, 0.0, 100.0)
	_wire("DERBY: %s beat local rivals %s %d-%d" % [w_t.team_name, l_t.team_name, maxi(mt.sa, mt.sb), mini(mt.sa, mt.sb)], "good")
	var ut := user_team()
	if w_t == ut or l_t == ut:
		var won := w_t == ut
		derby_record[0 if won else 1] = int(derby_record[0 if won else 1]) + 1
		_news("DERBY %s: %s %d-%d %s." % ["WIN" if won else "LOSS", w_t.team_name, maxi(mt.sa, mt.sb), mini(mt.sa, mt.sb), l_t.team_name])
		if mode == "manager":
			if not board.is_empty():
				board.confidence = clampf(float(board.confidence) + (3.0 if won else -3.0), 0.0, 100.0)
			_fans(int(club_fans * (0.03 if won else -0.015)))
			if won:
				_achieve("derby")


# --- Fans and merchandise (your club) ---

func _fans(d: int) -> void:
	club_fans = maxi(100, club_fans + d)


func merch_cost() -> int:
	return MERCH_COSTS[merch_level] if merch_level < MERCH_COSTS.size() else -1


func upgrade_merch() -> String:
	var c := merch_cost()
	if c < 0:
		return "Merch range maxed out"
	if money < c:
		return "Need $%s" % _fmt(c)
	money -= c
	merch_level += 1
	_ledger("Merch range level %d" % merch_level, -c)
	return ""


func _fans_week() -> void:
	var ut := user_team()
	var showmen := ut.roster.filter(func(p: PlayerData) -> bool: return PlayerData.persona_of(p) == "Showman").size()
	_fans(int(club_fans * 0.004 * showmen) + int(ut.reputation * 2.0))
	for mt in all_week_matches():
		if mt.winner < 0 or (mt.a != user_team_idx and mt.b != user_team_idx):
			continue
		if mt.winner == user_team_idx:
			_fans(int(club_fans * 0.01) + 40)
		else:
			_fans(-int(club_fans * 0.005))
		if not press_pledge.is_empty() and int(press_pledge.s) == season and int(press_pledge.w) == week:
			var won: bool = mt.winner == user_team_idx
			if not board.is_empty():
				board.confidence = clampf(float(board.confidence) + (5.0 if won else -6.0), 0.0, 100.0)
			_news("PRESS: you promised a win and %s." % ("delivered" if won else "didn't deliver. The board noticed"))
			press_pledge = {}


# --- Loans ---

## Loan a squad or academy player to a lower club until the season ends:
## they play every week (and develop); their new club pays the wage.
func loan_out(p: PlayerData) -> String:
	if not window_open():
		return window_text()
	var from_academy := academy.has(p)
	var ut := user_team()
	if not from_academy and not ut.roster.has(p):
		return "Not your player"
	if p.loan_from != "":
		return "Already on loan"
	var pool: Array = teams.filter(func(t: TeamData) -> bool:
		return t != ut and _ai_controls(t) and t.league >= ut.league and t.rating_exact() <= p.rating_exact() + 6.0 and teams.find(t) != affiliate_idx)
	if pool.is_empty():
		return "No club wants them on loan right now"
	pool.sort_custom(func(a: TeamData, b: TeamData) -> bool: return absf(a.rating_exact() - p.rating_exact()) < absf(b.rating_exact() - p.rating_exact()))
	var dest: TeamData = pool[rng.randi() % mini(4, pool.size())]
	if from_academy:
		academy.erase(p)
	else:
		ut.roster.erase(p)
	p.loan_from = "user"
	p.loan_kind = "academy" if from_academy else "squad"
	p.joined = stamp()
	dest.roster.append(p)
	dest.sort_roster()
	_trim_roster(dest, p)
	_news("LOAN: %s joins %s on loan until the end of the season." % [p.player_name, dest.team_name])
	return ""


func loan_in_fee(p: PlayerData) -> int:
	return int(round(p.salary * 0.6 / 50.0)) * 50


## Borrow another club's player until the season ends, paying part of the wage.
func loan_in(p: PlayerData) -> String:
	if not window_open():
		return window_text()
	var owner := owner_of(p)
	var ut := user_team()
	if owner == null or owner == ut:
		return "Can't loan that player"
	if p.loan_from != "":
		return "Already on loan"
	if ut.roster.size() >= MAX_ROSTER:
		return "Roster full (%d)" % MAX_ROSTER
	if owner.roster.size() <= MIN_ROSTER + 1:
		return "%s can't spare players" % owner.team_name
	var why := p.refuses(ut)
	if why != "":
		return why
	if owner.starters(5).has(p) and rng.randf() < 0.7:
		return "%s won't loan out a starter" % owner.team_name
	owner.roster.erase(p)
	p.loan_from = owner.team_name
	p.loan_kind = "in"
	p.loan_team = teams.find(owner)
	p.loan_fee = loan_in_fee(p)
	p.joined = stamp()
	ut.roster.append(p)
	_refill_roster(owner)
	_news("LOAN: %s arrives from %s on loan ($%s/wk) until the end of the season." % [p.player_name, owner.team_name, _fmt(p.loan_fee)])
	return ""


## Season end: everyone on loan goes home.
func _return_loans() -> void:
	for t in teams:
		for p in t.roster.duplicate():
			if p.loan_from == "":
				continue
			t.roster.erase(p)
			if p.loan_from == "user":
				if p.loan_kind == "academy" and p.age < 20 and academy.size() < maxi(1, academy_capacity()):
					academy.append(p)
				else:
					user_team().roster.append(p)
				_news("LOAN: %s is back from %s (%d matches this season)." % [p.player_name, t.team_name, int(p.season_stats.get("m", 0))])
			else:
				var home: TeamData = teams[p.loan_team] if p.loan_team >= 0 and p.loan_team < teams.size() else null
				if home != null:
					home.roster.append(p)
					_trim_roster(home, p)
				else:
					free_agents.append(p)
			p.loan_from = ""
			p.loan_kind = ""
			p.loan_team = -1
			p.loan_fee = 0
			p.joined = stamp()
			t.sort_roster()


# --- Affiliate: a lower-league club you own as a second roster ---

func affiliate() -> TeamData:
	return teams[affiliate_idx] if affiliate_idx >= 0 and affiliate_idx < teams.size() else null


func affiliate_cost(t: TeamData) -> int:
	return int(LEAGUES[t.league].budget * 0.5 / 1000.0) * 1000


func affiliate_candidates() -> Array:
	var ut := user_team()
	var out: Array = teams.filter(func(t: TeamData) -> bool: return t.league > ut.league and t != ut)
	out.sort_custom(func(a: TeamData, b: TeamData) -> bool: return a.rating_exact() > b.rating_exact())
	return out.slice(0, 6)


func buy_affiliate(t: TeamData) -> String:
	if affiliate_idx >= 0:
		return "You already have an affiliate"
	if t.league <= user_team().league:
		return "The affiliate must play in a lower league"
	var c := affiliate_cost(t)
	if money < c:
		return "Need $%s" % _fmt(c)
	money -= c
	affiliate_idx = teams.find(t)
	_ledger("Bought affiliate %s" % t.team_name, -c)
	_news("AFFILIATE: %s (%s) is now your second roster. Send players down to play; call them back up any time." % [t.team_name, LEAGUES[t.league].name])
	_achieve("affiliate")
	return ""


func send_down(p: PlayerData) -> String:
	var aff := affiliate()
	var ut := user_team()
	if aff == null:
		return "No affiliate"
	if not ut.roster.has(p):
		return "Not on your roster"
	if p.loan_from != "":
		return "On loan"
	ut.roster.erase(p)
	aff.roster.append(p)
	p.joined = stamp()
	aff.sort_roster()
	_trim_roster(aff, p)
	return ""


func call_up(p: PlayerData) -> String:
	var aff := affiliate()
	var ut := user_team()
	if aff == null or not aff.roster.has(p):
		return "Not at the affiliate"
	if ut.roster.size() >= MAX_ROSTER:
		return "Roster full (%d)" % MAX_ROSTER
	if aff.roster.size() <= MIN_ROSTER:
		return "%s need at least %d players" % [aff.team_name, MIN_ROSTER]
	aff.roster.erase(p)
	p.joined = stamp()
	p.salary = PlayerData.salary_for_rating(p.rating_exact())
	p.contract_until = maxi(p.contract_until, season + 1)
	ut.roster.append(p)
	_refill_roster(aff)
	return ""


func affiliate_income() -> int:
	var aff := affiliate()
	return int(LEAGUES[aff.league].sponsor * 0.15) if aff != null else 0


func _affiliate_check() -> void:
	var aff := affiliate()
	if aff != null and aff.league <= user_team().league:
		_news("AFFILIATE: %s climbed to your league and became independent." % aff.team_name)
		affiliate_idx = -1


# =============================================================================
# My Player: agents and the social feed
# =============================================================================

func agent_info() -> Dictionary:
	return AGENTS.get(agent, AGENTS.none)


func hire_agent(id: String) -> String:
	if not AGENTS.has(id):
		return "Unknown agent"
	if id == agent:
		return "Already your agent"
	var a: Dictionary = AGENTS[id]
	if fame < int(a.get("fame", 0)):
		return "%s only take clients with %s+ followers" % [a.name, fame_text(int(a.fame))]
	if wallet < int(a.fee):
		return "Need $%s" % _fmt(int(a.fee))
	wallet -= int(a.fee)
	agent = id
	_post("@%s" % String(a.name).replace(" ", ""), "Delighted to welcome %s to our client list." % user_player.player_name, "press", 0.6)
	return ""


func agent_cut() -> int:
	return int(user_player.salary * float(agent_info().cut)) if user_player != null else 0


## Toxic fans and haters. Vulgar on purpose (no slurs). {me} = you, {team} = your club, {opp} = the other club.
const TOXIC := {
	"bad_game": [
		"{me} is fucking dogshit. Uninstall the game, you absolute bot",
		"Who the fuck keeps giving {me} a contract? Pure trash",
		"{me} played like they're on a fucking trackpad with their elbow",
		"My nan frags harder than {me}. Bench this clown",
		"{me} couldn't hit a barn from inside the fucking barn",
		"Refund my ticket. {me} is a walking free kill for {opp}",
		"Imagine getting paid to be this shit. {me}, seriously?",
		"{me} is a fraud. Send them back to the low ranks where they belong",
		"{me} whiffed more shots tonight than I've had hot dinners. Fucking embarrassing",
		"Holy shit {me}, did you play with your monitor off?",
		"{me} is the reason {team} lose. Sell the useless prick",
		"Every round {me} dies first like a fucking lemming. Clown shit",
	],
	"loss": [
		"{team} choked AGAIN. What a fucking surprise",
		"Another L. {team} are a joke and {me} is the punchline",
		"{team} getting bent over by {opp}. Pathetic",
		"I'm done supporting this shit show. {team} are a disgrace",
		"Lost to {opp}? Lmao, {team} are fucking finished",
	],
	"hater": [
		"{me} popped off against bots, means fuck all",
		"Overrated as shit. {me} disappears the second it matters",
		"Stat-padding piece of shit. Wake me up when {me} shows up in a final",
	],
	"trash_reply": [
		"Big words from a fucking nobody. {me} is getting bodied",
		"Talk is cheap, {me}. Your aim's even cheaper",
		"Shut the fuck up and hit your shots, {me}",
		"{me} talking shit like they've ever won anything lmao",
		"Screenshot this: {opp} are going to wipe the floor with {me}'s mouthy ass",
	],
	"transfer": [
		"{me} you fucking snake. Hope you rot on the bench at your next club",
		"Fuck {me}. Never liked that rat anyway",
		"Loyalty means nothing to {me}. Pack your shit and go",
	],
	"benched": [
		"Finally someone benched that useless fuck {me}",
		"{me} on the bench where the dead weight belongs. About bloody time",
	],
	"injury": [
		"{me} injured? Can't tell the difference from how they normally play lmao",
		"Good. {team} might actually win something without {me}",
	],
	"new_club": [
		"{me} to {team}? Enjoy your new overpriced bench warmer lmao",
		"{team} paid money for {me}?? Somebody's getting fucking sacked",
	],
	"retire": [
		"Good riddance {me}, overrated as shit",
	],
}


const FAN_HANDLES := ["fragfanatic", "clutchqueen", "ecoking", "nadegod", "onetapper", "rotatefaster", "aimlabsenjoyer",
	"bombsiteB", "smokecriminal", "ggwp_dad", "headclicker", "flickandpray", "saveround", "peekerspal", "lurkmode"]
const OUTLET_HANDLES := ["@FragFeed", "@ESNLive", "@HeadshotWeekly", "@RoundupRadio", "@TheClutchPod"]


## A post from a toxic fan or hater (kind "toxic").
func _toxic(key: String, opp: String = "", mult: float = 1.0) -> void:
	if mode != "player" or user_player == null:
		return
	var line: String = (TOXIC[key] as Array).pick_random()
	line = line.replace("{me}", user_player.player_name).replace("{team}", user_team().team_name).replace("{opp}", opp if opp != "" else "anyone")
	_post(_fan_handle(), line, "toxic", mult)


func _fan_handle() -> String:
	return "@%s%d" % [FAN_HANDLES[rng.randi() % FAN_HANDLES.size()], rng.randi_range(1, 999)]


func _post(who: String, text: String, kind: String = "fan", mult: float = 1.0) -> void:
	if mode != "player":
		return
	var likes := int((fame * 0.02 + 5.0) * mult * rng.randf_range(0.5, 1.6))
	feed.append({"s": season, "w": week, "who": who, "text": text, "kind": kind, "likes": likes})
	while feed.size() > 90:
		feed.pop_front()


func _feed_match(r: float, won: bool, opp: TeamData, potm_now: bool) -> void:
	var me := user_player.player_name
	var fan := ""
	if r >= 1.4:
		fan = ["%s is HIM. %.2f rating, are you kidding" % [me, r], "Someone give %s a raise immediately" % me, "That was a highlight reel from %s" % me].pick_random()
	elif r >= 1.1:
		fan = ["Solid from %s again vs %s" % [me, opp.team_name], "%s quietly carrying" % me].pick_random()
	elif r >= 0.85:
		fan = ["Average game from %s, happens" % me, "%s needs to step up a bit" % me].pick_random()
	else:
		fan = ["Bench %s honestly" % me, "What was %s doing out there" % me, "%s had a shocker vs %s" % [me, opp.team_name]].pick_random()
	_post(_fan_handle(), fan, "fan", 1.0 if r >= 0.85 else 0.6)
	if r < 0.85:
		_toxic("bad_game", opp.team_name, 1.4)
		if r < 0.65 or rng.randf() < 0.5:
			_toxic("bad_game", opp.team_name, 1.1)
	if not won and rng.randf() < 0.6:
		_toxic("loss", opp.team_name)
	elif r >= 1.3 and rng.randf() < 0.3:
		_toxic("hater", opp.team_name, 0.7)
	if potm_now or r >= 1.35:
		_post(OUTLET_HANDLES.pick_random(), "%s puts up a %.2f as %s %s %s." % [me, r, user_team().team_name, "beat" if won else "fall to", opp.team_name], "press", 1.4)
	var rv := top_rival()
	if not rv.is_empty():
		var rp := find_player(int(rv.uid))
		if rp != null and opp.roster.has(rp) and rng.randf() < 0.6:
			_post("@%s" % rp.player_name, "gg %s. %s" % [me, "Next time." if won else "Not your day."], "rival", 1.2)
	if won and rng.randf() < 0.35:
		var mates: Array = user_team().roster.filter(func(p: PlayerData) -> bool: return not p.is_user and relation(p.uid) >= 20.0)
		if not mates.is_empty():
			var mate: PlayerData = mates.pick_random()
			_post("@%s" % mate.player_name, "Good dub. Duo with %s hits different" % me, "teammate", 0.8)


# =============================================================================
# Live viewing: watch any AI match this week instead of simulating it
# =============================================================================

func find_week_match(a: int, b: int) -> Dictionary:
	for mt in all_week_matches():
		if int(mt.a) == a and int(mt.b) == b and int(mt.winner) == -1:
			return mt
	return {}


## Result of a watched AI match: same bookkeeping as a simulated one.
func record_watched_match(a: int, b: int, score: Array, rounds: int, stats: Dictionary) -> void:
	var mt := find_week_match(a, b)
	if mt.is_empty():
		return
	for p: PlayerData in stats:
		var s: Dictionary = stats[p]
		var on_a: bool = teams[a].roster.has(p)
		_box_growth(p, s, rounds)
		_log_match(p, teams[b] if on_a else teams[a], score[0] if on_a else score[1], score[1] if on_a else score[0],
			int(s.kills), int(s.deaths), int(float(s.damage) / maxi(1, rounds)),
			Progression.match_rating(s.kills, s.deaths, rounds, s.objectives, s.damage), String(mt.label))
	_set_result(mt, int(score[0]), int(score[1]))
	_news("WATCHED: %s %d-%d %s (%s)." % [teams[a].team_name, int(score[0]), int(score[1]), teams[b].team_name, mt.label])


# =============================================================================
# Form, morale and the news wire
# =============================================================================

## Before your match: everyone's mood for the day. Notes off days on your team.
func prepare_match_day() -> void:
	var mt := user_match_this_week()
	if mt.is_empty():
		return
	var ui := team_index(user_team())
	var days := roll_match_day(teams[ui])
	var opp_idx: int = mt.b if mt.a == ui else mt.a
	roll_match_day(teams[opp_idx])
	if mode == "manager":
		var boost := 0.4 * staff_stars("Analyst") + 0.25 * fac("Analyst Room")
		if boost > 0.0:
			for sp in teams[ui].roster:
				sp.match_mod += boost
	if mode == "manager":
		if opp_idx == trash_target:
			for op in teams[opp_idx].roster:
				op.match_mod += 2.0
			_news("%s are fired up after your mind games." % teams[opp_idx].team_name)
		if opp_idx == rattled_team:
			for op in teams[opp_idx].roster:
				op.match_mod -= 1.5
			_news("%s look rattled." % teams[opp_idx].team_name)
	if mode == "player" and user_player != null:
		_relationship_mods()
		if perks.has("big_game") and mt.kind != "league":
			user_player.match_mod += 2.5
		if opp_idx == trash_target:
			for op in teams[opp_idx].roster:
				op.match_mod += 2.0
			_news("%s are fired up after your trash talk." % teams[opp_idx].team_name)
		soc().talk.apply_match_mods(teams[opp_idx])
		var rv := top_rival()
		if not rv.is_empty():
			var rp := find_player(int(rv.uid))
			if rp != null and teams[opp_idx].roster.has(rp):
				_news("RIVALRY: you vs %s again, meeting #%d (%d-%d)." % [rp.player_name, int(rv.w) + int(rv.l) + 1, int(rv.w), int(rv.l)])
	if mode == "manager":
		for p: PlayerData in days.bad:
			_news("MATCHDAY: %s is having an off day." % p.player_name)
		for p: PlayerData in days.great:
			_news("MATCHDAY: %s looks sharp in warm-ups." % p.player_name)


## Weekly: form drifts (results, morale, randomness, the odd slump or hot
## streak); morale follows playing time and results.
func _weekly_form() -> void:
	var ut := user_team()
	for t in teams:
		var starting := t.starters(5)
		var notable := t.league <= 1 or t == ut
		for p in t.roster:
			if p.is_user:
				continue
			_health_week(p, t, notable)
			p.form *= 0.8
			if not p.match_log.is_empty():
				var last: Dictionary = p.match_log[p.match_log.size() - 1]
				if int(last.s) == season and int(last.w) == week:
					p.form += (float(last.r) - 1.0) * 2.2
			p.form += (p.morale - 60.0) / 60.0 + rng.randfn(0.0, 0.8)
			var roll := rng.randf()
			if roll < 0.012 and PlayerData.persona_of(p) != "Professional":
				p.form -= rng.randf_range(4.0, 7.0)
				var why: String = SLUMP_REASONS[rng.randi() % SLUMP_REASONS.size()]
				if t == ut and mode == "manager":
					_news("WARNING: %s is in a slump (%s)." % [p.player_name, why])
				elif notable:
					_wire("%s (%s) in a slump: %s." % [p.player_name, t.short_name, why], "bad")
			elif roll < 0.024:
				p.form += rng.randf_range(4.0, 6.0)
				var why2: String = HOT_REASONS[rng.randi() % HOT_REASONS.size()]
				if t == ut and mode == "manager":
					_news("%s is on fire after %s." % [p.player_name, why2])
				elif notable:
					_wire("%s (%s) on fire after %s." % [p.player_name, t.short_name, why2], "good")
			p.form = clampf(p.form, -8.0, 8.0)
			var benched := not starting.has(p) and p.available()
			if t == ut:
				p.bench_weeks = p.bench_weeks + 1 if benched else 0
				if benched and p.promise_until >= stamp():
					p.promise_until = 0
					p.morale -= 25.0
					if mode == "manager":
						_msg("complaint", "%s: \"You promised.\"" % p.player_name,
							"%s was promised a starting spot and is on the bench again. Trust is broken." % p.player_name,
							[["Put them on the transfer list", "list"], ["Apologise", "ok"]], p.uid)
			p.morale += (-2.5 if benched else 0.6) + clampf(t.streak * 0.6, -2.0, 2.0) + (62.0 - p.morale) * 0.04
			if t.is_user_team and mode == "manager":
				p.morale += 0.6 * fac("Gaming House")
				p.form += 0.25 * fac("Bootcamp")
			p.morale = clampf(p.morale, 0.0, 100.0)
			if t == ut and mode == "manager" and p.morale < 25.0 and rng.randf() < 0.25:
				_news("WARNING: %s is unhappy (%s) and wants to leave." % [p.player_name, "benched" if benched else "results"])
		_persona_week(t, starting)


func stamp() -> int:
	return season * 100 + week


## Weekly health: recover, or fall ill / get hurt (rarely).
func _health_week(p: PlayerData, t: TeamData, notable: bool) -> void:
	var mine := t == user_team() and mode == "manager"
	if p.out_weeks > 0:
		if mine and p.out_weeks > 1 and staff_stars("Physio") >= 3 and rng.randf() < 0.3:
			p.out_weeks -= 1
		p.out_weeks -= 1
		if p.out_weeks == 0:
			p.ailment = ""
			if mine:
				_news("%s is fit again." % p.player_name)
		return
	var hk := diff("injury") if t.is_user_team or t.roster.has(user_player) else 1.0
	if mine:
		hk *= (1.0 - 0.12 * staff_stars("Physio")) * (1.0 - 0.1 * fac("Medical Room"))
	var roll := rng.randf()
	if roll < 0.012 * hk:
		p.out_weeks = 1
		p.ailment = ILLNESSES[rng.randi() % ILLNESSES.size()]
	elif roll < 0.018 * hk:
		p.out_weeks = rng.randi_range(2, 4)
		p.ailment = INJURIES[rng.randi() % INJURIES.size()]
	else:
		return
	if mine:
		_news("WARNING: %s is out for %d week%s with %s." % [p.player_name, p.out_weeks, "s" if p.out_weeks > 1 else "", p.ailment])
		_msg("info", "%s is unavailable" % p.player_name,
			"%s has %s and will miss %d week%s. They're skipped in the lineup; with fewer than 5 fit players you'll have to sign someone (allowed outside windows) or forfeit." % [p.player_name, p.ailment, p.out_weeks, "s" if p.out_weeks > 1 else ""],
			[["OK", "ok"]], p.uid)
	elif notable:
		_wire("%s (%s) out %d wk with %s." % [p.player_name, t.short_name, p.out_weeks, p.ailment], "bad")


# =============================================================================
# Mailbox: complaints, requests, suggestions, sponsor and contract matters
# =============================================================================

func _msg(kind: String, title: String, body: String, options: Array = [["OK", "ok"]], uid: int = 0, data: Dictionary = {}) -> void:
	inbox.append({"id": next_msg_id, "kind": kind, "title": title, "body": body, "uid": uid, "options": options,
		"data": data, "done": false, "result": "", "s": season, "w": week, "read": false})
	next_msg_id += 1
	while inbox.size() > 60:
		inbox.pop_front()


func unread_count() -> int:
	var n := 0
	for m in inbox:
		if not bool(m.done):
			n += 1
	return n


func _has_open_msg(uid: int, kind: String) -> bool:
	for m in inbox:
		if not bool(m.done) and int(m.uid) == uid and String(m.kind) == kind:
			return true
	return false


func _weakest_starter_rating() -> float:
	var lo := INF
	for s in user_team().starters(5):
		lo = minf(lo, s.rating_exact())
	return lo if lo < INF else 0.0


## Players speak up: benched, unhappy, underpaid. Plus staff suggestions and
## contract reminders.
func _player_messages() -> void:
	var ut := user_team()
	var now := stamp()
	var weakest := _weakest_starter_rating()
	for p in ut.roster:
		if now < p.msg_cooldown or p.is_user:
			continue
		if p.morale < 25.0 and not p.listed:
			p.msg_cooldown = now + 5
			_msg("wants_out", "%s wants to leave" % p.player_name,
				"%s (morale %d) has asked to leave. \"I'm not happy here. Let me go, or give me a reason to stay.\"" % [p.player_name, int(p.morale)],
				[["Transfer-list them", "list"], ["Offer a raise (+30%%: %s/wk)" % UI_money(_raise(p)), "raise"], ["Refuse", "refuse"]], p.uid)
		elif p.bench_weeks >= 3 and p.available() and p.rating_exact() >= weakest - 3.0:
			p.msg_cooldown = now + 5
			_msg("complaint", "%s wants to play" % p.player_name,
				"%s has been on the bench for %d weeks. \"I'm as good as the guys starting. Give me a chance.\"" % [p.player_name, p.bench_weeks],
				[["Promise a starting spot", "promise"], ["Tell them to earn it", "earn"], ["Transfer-list them", "list"]], p.uid)
		elif p.avg_recent_rating() > 1.15 and p.salary < PlayerData.salary_for_rating(p.rating_exact()) * 0.95 and rng.randf() < 0.3:
			p.msg_cooldown = now + 8
			var ask := int(round(PlayerData.salary_for_rating(p.rating_exact()) * 1.1 / 50.0)) * 50
			_msg("wage", "%s asks for a raise" % p.player_name,
				"%s is playing great (avg %.2f) and wants %s/wk (now %s/wk)." % [p.player_name, p.avg_recent_rating(), UI_money(ask), UI_money(p.salary)],
				[["Agree (%s/wk)" % UI_money(ask), "wage_yes"], ["Refuse", "wage_no"]], p.uid, {"ask": ask})
	if week in [12, 18, 22]:
		for p in ut.roster:
			if p.contract_until <= season and not _has_open_msg(p.uid, "contract"):
				_msg("contract", "%s's contract is expiring" % p.player_name,
					"%s's deal ends this season (week %d of %d). Extend now or they leave as a free agent." % [p.player_name, week, SEASON_WEEKS],
					[["Extend (%s bonus)" % UI_money(extension_cost(p)), "extend"], ["Let them go", "ok"]], p.uid)
	if rng.randf() < 0.12:
		_suggestion()


func _raise(p: PlayerData) -> int:
	return int(round(p.salary * 1.3 / 50.0)) * 50


func _suggestion() -> void:
	var ut := user_team()
	var kinds := ["bootcamp", "fans", "scout"]
	if training.intensity == "Intense":
		kinds.append("rest")
	var k: String = kinds[rng.randi() % kinds.size()]
	var cap: String = ut.starters(1)[0].player_name if not ut.roster.is_empty() else "Your captain"
	match k:
		"bootcamp":
			var cost := int(LEAGUES[ut.league].sponsor * 2.0 / 500.0) * 500 + 2000
			_msg("suggestion", "%s suggests a bootcamp" % cap,
				"\"A week together at a bootcamp would sort our comms out.\" Morale +8 and a bit of form for everyone.",
				[["Book it (%s)" % UI_money(cost), "bootcamp"], ["Not now", "ok"]], 0, {"cost": cost})
		"fans":
			var cost2 := int(LEAGUES[ut.league].sponsor / 500.0) * 500 + 1000
			_msg("suggestion", "Fan meet-up proposal", "Your social team wants to run a fan meet-up. Reputation +2.",
				[["Run it (%s)" % UI_money(cost2), "fans"], ["Skip", "ok"]], 0, {"cost": cost2})
		"scout":
			var best: PlayerData = null
			for fa in free_agents:
				if fa.rating_exact() > _weakest_starter_rating() and fa.refuses(ut) == "" and (best == null or fa.rating_exact() > best.rating_exact()):
					best = fa
			if best != null:
				_msg("suggestion", "%s recommends %s" % [cap, best.player_name],
					"\"I played with %s, they'd fit in.\" Free agent, %s, RTG %d, age %d." % [best.player_name, best.role, best.rating(), best.age],
					[["Scout them", "scout"], ["Ignore", "ok"]], best.uid)
		"rest":
			_msg("suggestion", "The squad is tired", "\"Intense training every week is wearing us down.\"",
				[["Drop to Normal training", "rest"], ["Push on", "push"]])


## Act on a message. Returns "" or an error (message stays open on error).
func resolve_msg(m: Dictionary, idx: int) -> String:
	if bool(m.done):
		return ""
	var action: String = m.options[idx][1]
	var p := find_player(int(m.uid)) if int(m.uid) != 0 else null
	var mine := p != null and user_team().roster.has(p)
	var res := ""
	if action.begins_with("pm_"):
		m.done = true
		m.read = true
		m.result = _resolve_pm(m, action, p)
		return ""
	if action.begins_with("mg_"):
		m.done = true
		m.read = true
		m.result = _resolve_mgr(m, action, p)
		return ""
	match action:
		"ok", "sponsor_no":
			res = "Noted."
		"list":
			if not mine:
				return "They're no longer at the club"
			set_listed(p, true)
			res = "%s is on the transfer list." % p.player_name
		"raise":
			if not mine:
				return "They're no longer at the club"
			p.salary = _raise(p)
			p.morale = minf(100.0, p.morale + 25.0)
			res = "%s accepts %s/wk and calms down." % [p.player_name, UI_money(p.salary)]
		"refuse":
			if mine:
				p.morale = maxf(0.0, p.morale - 10.0)
				p.form = maxf(-8.0, p.form - 1.5)
				if rng.randf() < 0.3:
					user_team().reputation = maxf(0.0, user_team().reputation - 1.0)
					_wire("%s goes public with transfer request at %s" % [p.player_name, user_team().team_name], "bad")
					res = "%s went to the press. Reputation -1." % p.player_name
				else:
					res = "%s sulks but stays." % p.player_name
		"promise":
			if mine:
				p.promise_until = stamp() + 6
				p.morale = minf(100.0, p.morale + 15.0)
				p.bench_weeks = 0
				res = "%s is happy. Start them in the next 6 weeks or they'll take it badly." % p.player_name
		"earn":
			if mine:
				if rng.randf() < 0.35:
					p.form = minf(8.0, p.form + 2.0)
					res = "%s takes it as motivation (form up)." % p.player_name
				else:
					p.morale = maxf(0.0, p.morale - 8.0)
					res = "%s isn't impressed (morale down)." % p.player_name
		"wage_yes":
			if mine:
				p.salary = int(m.data.ask)
				p.morale = minf(100.0, p.morale + 15.0)
				res = "%s signs the new terms." % p.player_name
		"wage_no":
			if mine:
				p.morale = maxf(0.0, p.morale - 12.0)
				res = "%s is disappointed." % p.player_name
		"extend":
			if not mine:
				return "They're no longer at the club"
			var err := extend_contract(p)
			if err != "":
				return err
			res = "%s extended through season %d." % [p.player_name, p.contract_until]
		"bootcamp", "fans":
			var cost := int(m.data.cost)
			if money < cost:
				return "Can't afford it"
			money -= cost
			_ledger("Bootcamp" if action == "bootcamp" else "Fan meet-up", -cost)
			if action == "bootcamp":
				for q in user_team().roster:
					q.morale = minf(100.0, q.morale + 8.0)
					q.form = minf(8.0, q.form + 1.0)
				res = "Bootcamp booked: the squad is buzzing."
			else:
				user_team().reputation = minf(100.0, user_team().reputation + 2.0)
				res = "Great turnout. Reputation +2."
		"scout":
			res = "Opened the scouting report."
		"rest":
			training.intensity = "Normal"
			for q in user_team().roster:
				q.morale = minf(100.0, q.morale + 4.0)
			res = "Training set to Normal."
		"push":
			for q in user_team().roster:
				q.morale = maxf(0.0, q.morale - 4.0)
			res = "The squad grumbles."
		"sponsor_extend":
			var found := false
			for d in sponsors:
				if d.brand == m.data.brand:
					d.weeks = int(d.weeks) + int(m.data.weeks)
					d.weekly = int(m.data.weekly)
					d.ext_offered = false
					found = true
			if not found:
				return "That deal has already ended"
			res = "Extended with %s." % m.data.brand
			_news("SPONSOR: %s extended for %d weeks." % [m.data.brand, int(m.data.weeks)])
	m.done = true
	m.read = true
	m.result = res
	return ""


## League results worth a headline: upsets, streaks, the top of the tables.
func _wire_results() -> void:
	for mt in week_matches:
		if mt.winner < 0:
			continue
		var w_t: TeamData = teams[mt.winner]
		var l_t: TeamData = teams[mt.b if mt.winner == mt.a else mt.a]
		var ws: int = maxi(mt.sa, mt.sb)
		var ls: int = mini(mt.sa, mt.sb)
		if w_t.rating() <= l_t.rating() - 5:
			_wire("UPSET: %s stun %s %d-%d (%s)" % [w_t.team_name, l_t.team_name, ws, ls, LEAGUES[w_t.league].short], "good")
		elif w_t.league == 0 and rng.randf() < 0.35:
			_wire("%s %d-%d %s" % [w_t.team_name.to_upper(), ws, ls, l_t.team_name.to_upper()], "info")
		if w_t.streak == 5 or w_t.streak == 8:
			_wire("%s on a %d-match win streak" % [w_t.team_name, w_t.streak], "good")
		if l_t.streak == -5:
			_wire("Crisis at %s: five straight losses" % l_t.team_name, "bad")
	if rng.randf() < 0.3:
		var t: TeamData = teams[rng.randi() % teams.size()]
		if t != user_team():
			var b: String = SPONSOR_BRANDS[rng.randi() % SPONSOR_BRANDS.size()]
			t.sponsor_name = b
			_wire("%s sign %s as headline sponsor" % [t.team_name, b], "deal")


func _wire(text: String, kind: String = "info") -> void:
	wire.append({"text": text, "kind": kind, "s": season, "w": week})
	while wire.size() > 80:
		wire.pop_front()


# =============================================================================
# Season rollover
# =============================================================================

func _end_season() -> void:
	_news("=== Season %d is over. %s finish #1 in the world. ===" % [season, rankings()[0].team_name])
	_start_review()
	_season_awards()
	_season_records()
	if season % 2 == 0:
		_review.world_cup = _world_cup()
	if mode == "manager":
		_board_season_end()
	if mode == "player" and user_player != null and not retired:
		_check_goals(true)
		var ut0 := user_team()
		if not teamless:
			_tl().pos = standings(ut0.league).find(ut0) + 1
		if not perks.has("big_game") and int(user_player.season_stats.get("m", 0)) >= 10 and user_player.season_avg_rating() >= 1.15:
			_unlock_perk("big_game")
	_promotion_relegation()
	season += 1
	week = 1
	var everyone: Array[PlayerData] = []
	for t in teams:
		everyone.append_array(t.roster)
	everyone.append_array(free_agents)
	if teamless and user_player != null:
		everyone.append(user_player)
		user_player.season_stats = {}
	for p in everyone:
		Progression.age_up(p)
		if p.is_user:
			continue
		var f := Progression.age_factor(p.age)
		for k: String in PlayerData.STAT_KEYS:
			p.set_stat(k, p.stat(k) + f * rng.randf_range(0.0, 0.8))
	if mode == "player":
		_user_aging()
	if mode == "manager":
		_return_loans()
	_expire_contracts()
	for t in teams:
		for p in t.roster.duplicate():
			if p.is_user:
				continue
			if p.age >= 35 or (p.age >= 32 and rng.randf() < 0.3):
				t.roster.erase(p)
				_consider_hall(p, t.team_name)
				if t == user_team():
					_news("%s (%s) retires at %d." % [p.player_name, t.team_name, p.age])
				else:
					_wire("%s (%s) retires at %d." % [p.player_name, t.team_name, p.age], "info")
		if _ai_controls(t):
			_refill_roster(t)
	for p in free_agents.duplicate():
		if p.age >= 33:
			free_agents.erase(p)
	for p in free_agents:
		p.season_stats = {}
		if p.match_log.size() > 10:
			p.match_log = p.match_log.slice(p.match_log.size() - 10)
	for i in 40:
		var prospect := _new_player(rng.randf_range(38.0, 58.0), "")
		prospect.age = rng.randi_range(17, 19)
		prospect.potential = clampi(prospect.rating() + rng.randi_range(10, 35), 40, 99)
		free_agents.append(prospect)
	for t in teams:
		t.points = int(t.points * 0.5)
		t.wins = 0
		t.losses = 0
		t.round_diff = 0
		t.streak = 0
		t.sort_roster()
		for p in t.roster:
			p.season_stats = {}
			p.morale = lerpf(p.morale, 65.0, 0.4)
			if t != user_team() and p.match_log.size() > 10:
				p.match_log = p.match_log.slice(p.match_log.size() - 10) # Keeps saves small; your squad keeps 30.
	_make_schedules()
	_make_calendar()
	if mode == "manager":
		_affiliate_check()
		_academy_season()
		_refresh_staff_market()
		if not sacked:
			_make_board_objective()
		if user_team().league == 0:
			_achieve("top_flight")
	_finish_review()
	if mode == "player":
		if user_team().league == 0:
			_achieve("top_flight")
		if not free_agency:
			offers.clear()
		transfer_request = false
		_make_goals()
		_apply_coach()
		if not retired and teamless:
			_news("Season %d begins. You are %d and still without a club." % [season, user_player.age])
		elif not retired:
			_news("Season %d begins. You are %d, playing for %s in the %s." % [season, user_player.age, user_team().team_name, league_name(user_team())])
	elif user_team().roster.size() < MIN_ROSTER:
		_news("Your roster is short: sign players before the season starts.")


func _promotion_relegation() -> void:
	# League prize money for the regular-season top 4 (before teams move).
	for l in LEAGUES.size():
		var table := standings(l)
		var shares := [0.3, 0.15, 0.08, 0.05]
		for k in 4:
			var prize := int(float(LEAGUES[l].prize) * shares[k])
			var t: TeamData = table[k]
			if t.is_user_team and mode == "manager":
				_earn(prize, "League finish #%d (%s)" % [k + 1, LEAGUES[l].name])
			else:
				t.money += prize
	var moves: Array = []
	for l in range(LEAGUES.size() - 1):
		var upper := standings(l)
		var lower := standings(l + 1)
		moves.append([upper.slice(upper.size() - PROMOTE), lower.slice(0, PROMOTE), l])
	for mv in moves:
		var l: int = mv[2]
		for t: TeamData in mv[0]:
			t.league = l + 1
			_news("RELEGATED: %s drop to the %s." % [t.team_name, LEAGUES[l + 1].name])
			if not _review.is_empty():
				(_review.leagues[l].down as Array).append(t.team_name)
		for t: TeamData in mv[1]:
			t.league = l
			t.reputation = clampf(t.reputation + 5.0, 0.0, 100.0)
			_news("PROMOTED: %s rise to the %s!" % [t.team_name, LEAGUES[l].name])
			if not _review.is_empty():
				(_review.leagues[l + 1].up as Array).append(t.team_name)
			if t == user_team() and not teamless:
				_achieve("promoted")
				if mode == "manager":
					_fans(int(club_fans * 0.2))
			if mode == "player" and user_player != null and t.roster.has(user_player) and not retired:
				trophies.append({"s": season, "name": "Promotion to the %s" % LEAGUES[l].name, "place": 0, "team": t.team_name})
				_gain_fame(int(800 * _lmult(t)))


## Contracts that ran out: AI clubs re-sign players they still want; yours
## leave unless you extended them; the user player is re-signed automatically.
func _expire_contracts() -> void:
	for t in teams:
		for p in t.roster.duplicate():
			if p.contract_until >= season or p.loan_from != "":
				continue
			if p.is_user:
				if not retired:
					_start_free_agency(t)
				continue
			if t.is_user_team and mode == "manager":
				_pay_loyalty(p)
				p.release_clause = 0
				p.appearance_fee = 0
				t.roster.erase(p)
				free_agents.append(p)
				p.listed = false
				former_players[p.uid] = true
				_news("Contract expired: %s left %s and is now a free agent (Transfers > Free agents)." % [p.player_name, t.team_name])
				_msg("info", "%s has left" % p.player_name,
					"%s's contract ran out and they've joined the free-agent pool. You can re-sign them from Transfers in a window, if they'll have you." % p.player_name)
			elif rng.randf() < 0.7 and t.money > 0:
				p.contract_until = season + rng.randi_range(1, 2)
				p.salary = PlayerData.salary_for_rating(p.rating_exact())
			else:
				t.roster.erase(p)
				free_agents.append(p)
				if p.rating() >= 70 or t.league <= 1:
					_wire("%s leave %s as a free agent." % [p.player_name, t.team_name], "info")


# =============================================================================
# Queries + bookkeeping
# =============================================================================

func rankings() -> Array[TeamData]:
	var out: Array[TeamData] = teams.duplicate()
	var rt := {}
	for t in teams:
		rt[t] = t.rating_exact() # Once per team, not once per comparison.
	out.sort_custom(func(a: TeamData, b: TeamData) -> bool:
		if a.points != b.points:
			return a.points > b.points
		if a.league != b.league:
			return a.league < b.league
		return rt[a] > rt[b])
	return out


func world_rank(t: TeamData) -> int:
	return rankings().find(t) + 1


func market_players() -> Array[PlayerData]:
	var out: Array[PlayerData] = []
	for t in teams:
		if t != user_team():
			out.append_array(t.roster)
	out.sort_custom(func(a: PlayerData, b: PlayerData) -> bool: return a.rating_exact() > b.rating_exact())
	return out


func _news(s: String) -> void:
	news.append("[S%d W%d] %s" % [season, week, s])
	while news.size() > 150:
		news.pop_front()


func _ledger(text: String, amount: int) -> void:
	ledger.append({"season": season, "week": week, "text": text, "amount": amount})
	while ledger.size() > 250:
		ledger.pop_front()


static func _fmt(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


# =============================================================================
# Persistence
# =============================================================================

func to_dict() -> Dictionary:
	var td := []
	for t in teams:
		td.append(t.to_dict())
	var fa := []
	for p in free_agents:
		fa.append(p.to_dict())
	return {
		"mode": mode, "teams": td, "free_agents": fa, "user_team_idx": user_team_idx, "money": money,
		"season": season, "week": week, "schedules": schedules, "week_matches": week_matches.duplicate(true),
		"tournaments": tournaments.duplicate(true), "news": Array(news), "ledger": ledger.duplicate(true),
		"training": training.duplicate(), "facility": facility, "last_training": last_training.duplicate(),
		"used_names": used_names.keys(), "offers": offers.duplicate(true), "trained": trained_this_week,
		"report": last_report.duplicate(true), "next_uid": next_uid,
		"sponsors": sponsors.duplicate(true), "sponsor_offers": sponsor_offers.duplicate(true), "loans": loans.duplicate(true),
		"debt_weeks": debt_weeks, "incoming": incoming.duplicate(true), "next_offer_id": next_offer_id, "wire": wire.duplicate(true),
		"inbox": inbox.duplicate(true), "next_msg_id": next_msg_id, "former": former_players.keys(),
		"pm": {"wallet": wallet, "fame": fame, "trust": coach_trust, "endorsements": endorsements.duplicate(true),
			"awards": awards.duplicate(true), "trophies": trophies.duplicate(true), "timeline": timeline.duplicate(true),
			"goals": goals.duplicate(true), "perks": perks.duplicate(), "specialty": specialty, "rivals": rivals.duplicate(true),
			"potm": potm, "peak": peak_rating, "request": transfer_request, "setup": setup_level, "coach": coach_booked,
			"trash": trash_target, "fa": free_agency, "renewal": renewal_done, "allstar": allstar.duplicate(true),
			"retired": retired, "legacy": legacy.duplicate(true), "assets": assets.duplicate(), "stream": stream_level,
			"fatigue": fatigue, "relations": relations.duplicate(), "traits": traits.duplicate(), "highlights": highlights, "caps": caps,
			"teamless": teamless, "fbench": forced_bench_until, "user": user_player.to_dict() if teamless and user_player != null else {}},
		"social": social.to_dict() if social != null else {},
		"life": lifestyle.to_dict() if lifestyle != null else {},
		"difficulty": difficulty, "staff": staff.duplicate(true), "staff_market": staff_market.duplicate(true),
		"facilities": facilities.duplicate(), "academy": academy.map(func(p: PlayerData) -> Dictionary: return p.to_dict()),
		"scouted": scouted.keys(), "scout_queue": scout_queue.duplicate(), "board": board.duplicate(true),
		"job_offers": job_offers.duplicate(true), "sacked": sacked, "reviews": reviews.duplicate(true), "review_pending": review_pending,
		"hall": hall_of_fame.duplicate(true), "champions": champions.duplicate(true), "records": records.duplicate(true),
		"season_transfers": season_transfers.duplicate(true),
		"b10": {"fans": club_fans, "merch": merch_level, "pledge": press_pledge.duplicate(), "rattled": rattled_team, "derby": derby_record.duplicate(),
			"affiliate": affiliate_idx, "agent": agent, "feed": feed.duplicate(true), "trash": trash_target},
	}


static func from_dict(d: Dictionary) -> World:
	var w := World.new()
	w.rng.randomize()
	w.mode = String(d.get("mode", "manager"))
	for td in d.get("teams", []):
		w.teams.append(TeamData.from_dict(td))
	for pd in d.get("free_agents", []):
		w.free_agents.append(PlayerData.from_dict(pd))
	w.user_team_idx = int(d.get("user_team_idx", 0))
	w.money = int(d.get("money", 0))
	w.season = int(d.get("season", 1))
	w.week = int(d.get("week", 1))
	w.schedules = []
	for lg in d.get("schedules", []):
		var weeks := []
		for wk in lg:
			var pairs := []
			for pr in wk:
				pairs.append([int(pr[0]), int(pr[1])])
			weeks.append(pairs)
		w.schedules.append(weeks)
	w.week_matches = []
	for mt in d.get("week_matches", []):
		w.week_matches.append(_fix_match(mt))
	for t in d.get("tournaments", []):
		w.tournaments.append(_fix_bracket(t))
	for n in d.get("news", []):
		w.news.append(String(n))
	w.ledger = d.get("ledger", [])
	w.training = d.get("training", {"focus": "Balanced", "intensity": "Normal"})
	w.facility = int(d.get("facility", 1))
	w.last_training = d.get("last_training", {})
	for n in d.get("used_names", []):
		w.used_names[String(n)] = true
	for o in d.get("offers", []):
		w.offers.append({"team": int(o.team), "note": String(o.note), "wage": int(o.get("wage", 0)), "years": int(o.get("years", 1))})
	w.trained_this_week = bool(d.get("trained", false))
	w.last_report = d.get("report", {})
	w.next_uid = int(d.get("next_uid", 1))
	for t in w.teams:
		for p in t.roster:
			w._assign_uid(p)
	for p in w.free_agents:
		w._assign_uid(p)
	w.sponsors = d.get("sponsors", [])
	w.sponsor_offers = d.get("sponsor_offers", [])
	w.loans = d.get("loans", [])
	w.debt_weeks = int(d.get("debt_weeks", 0))
	w.incoming = d.get("incoming", [])
	w.next_offer_id = int(d.get("next_offer_id", 1))
	w.wire = d.get("wire", [])
	w.inbox = d.get("inbox", [])
	w.next_msg_id = int(d.get("next_msg_id", 1))
	for u in d.get("former", []):
		w.former_players[int(u)] = true
	w.set_difficulty(String(d.get("difficulty", "Normal")))
	w.staff = d.get("staff", {})
	w.staff_market = d.get("staff_market", [])
	w.facilities = d.get("facilities", {})
	for pd in d.get("academy", []):
		var ap := PlayerData.from_dict(pd)
		w._assign_uid(ap)
		w.academy.append(ap)
	for u in d.get("scouted", []):
		w.scouted[int(u)] = true
	for u in d.get("scout_queue", []):
		w.scout_queue.append(int(u))
	w.board = d.get("board", {})
	w.job_offers = d.get("job_offers", [])
	w.sacked = bool(d.get("sacked", false))
	w.reviews = d.get("reviews", [])
	w.review_pending = bool(d.get("review_pending", false))
	w.hall_of_fame = d.get("hall", [])
	w.champions = d.get("champions", [])
	w.records = d.get("records", {})
	w.season_transfers = d.get("season_transfers", [])
	var b10: Dictionary = d.get("b10", {})
	w.club_fans = int(b10.get("fans", 0))
	w.merch_level = int(b10.get("merch", 0))
	w.press_pledge = b10.get("pledge", {})
	w.rattled_team = int(b10.get("rattled", -1))
	var dr: Array = b10.get("derby", [0, 0])
	w.derby_record = [int(dr[0]), int(dr[1])]
	w.affiliate_idx = int(b10.get("affiliate", -1))
	w.agent = String(b10.get("agent", "none"))
	w.feed = b10.get("feed", [])
	if w.mode == "manager" and w.club_fans == 0 and not w.teams.is_empty():
		w.club_fans = int(w.teams[w.user_team_idx].reputation * 400.0) + 500
	if w.mode == "manager":
		w.trash_target = int(b10.get("trash", -1))
	if w.mode == "manager" and w.board.is_empty():
		w._make_board_objective()
		w.board.confidence = 60.0
	if w.mode == "manager" and w.staff_market.is_empty():
		w._refresh_staff_market()
	if w.mode == "manager" and w.sponsors.is_empty() and not d.has("sponsors"):
		# Older save: give the club its old income as a headline deal.
		var first := w._make_sponsor_offer("Main", "Steady")
		w.sponsors.append(first)
	if w.mode == "player":
		for t in w.teams:
			for p in t.roster:
				if p.is_user:
					w.user_player = p
		var pm: Dictionary = d.get("pm", {})
		w.teamless = bool(pm.get("teamless", false))
		w.forced_bench_until = int(pm.get("fbench", 0))
		var ud: Dictionary = pm.get("user", {})
		if w.user_player == null and not ud.is_empty():
			w.user_player = PlayerData.from_dict(ud)
			w.user_player.is_user = true
			w._assign_uid(w.user_player)
			w.teamless = true
		elif w.user_player != null:
			w.teamless = false
		w.social = Social.from_dict(w, d.get("social", {}))
		w.lifestyle = Lifestyle.from_dict(w, d.get("life", {}))
		w.wallet = int(pm.get("wallet", 0))
		w.fame = int(pm.get("fame", 200))
		w.coach_trust = float(pm.get("trust", 55.0))
		w.endorsements = pm.get("endorsements", [])
		w.awards = pm.get("awards", [])
		w.trophies = pm.get("trophies", [])
		w.timeline = pm.get("timeline", [])
		w.goals = pm.get("goals", [])
		for k in pm.get("perks", []):
			w.perks.append(String(k))
		w.specialty = String(pm.get("specialty", ""))
		var rv: Dictionary = pm.get("rivals", {})
		for k in rv:
			w.rivals[int(k)] = rv[k]
		w.potm = int(pm.get("potm", 0))
		w.peak_rating = int(pm.get("peak", 0))
		w.transfer_request = bool(pm.get("request", false))
		w.setup_level = int(pm.get("setup", 0))
		w.coach_booked = bool(pm.get("coach", false))
		w.trash_target = int(pm.get("trash", -1))
		w.free_agency = bool(pm.get("fa", false))
		w.renewal_done = bool(pm.get("renewal", false))
		w.allstar = pm.get("allstar", {})
		w.retired = bool(pm.get("retired", false))
		w.legacy = pm.get("legacy", {})
		for k in pm.get("assets", []):
			w.assets.append(String(k))
		w.stream_level = String(pm.get("stream", "Off"))
		w.fatigue = float(pm.get("fatigue", 0.0))
		var rl: Dictionary = pm.get("relations", {})
		for k in rl:
			w.relations[int(k)] = float(rl[k])
		for k in pm.get("traits", []):
			w.traits.append(String(k))
		w.highlights = int(pm.get("highlights", 0))
		w.caps = int(pm.get("caps", 0))
		if w.user_player != null:
			if w.goals.is_empty():
				w._make_goals()
			w._apply_coach()
	w._backfill_honours()
	return w


static func _fix_match(mt: Dictionary) -> Dictionary:
	return {"a": int(mt.a), "b": int(mt.b), "sa": int(mt.sa), "sb": int(mt.sb), "winner": int(mt.winner),
		"map": String(mt.get("map", "Dustline")), "kind": String(mt.get("kind", "league")), "label": String(mt.get("label", ""))}


## JSON turns ints into floats and int dict keys into strings: put them back.
static func _fix_bracket(t: Dictionary) -> Dictionary:
	var out := t.duplicate(true)
	out.start_week = int(t.start_week)
	out.round = int(t.round)
	out.size = int(t.get("size", CUP_SIZE))
	out.league = int(t.get("league", -1))
	var tms := []
	for i in t.teams:
		tms.append(int(i))
	out.teams = tms
	var rounds := []
	for r in t.rounds:
		var ms := []
		for mt in r:
			ms.append(_fix_match(mt))
		rounds.append(ms)
	out.rounds = rounds
	var pl := {}
	for k in t.placements:
		pl[int(k)] = int(t.placements[k])
	out.placements = pl
	return out
