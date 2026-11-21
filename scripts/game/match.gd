extends Node2D
## A competitive match: T vs CT, buy phase + economy, bomb plant/defuse,
## halftime side swap after round 5. First to 6 of 10 rounds; 5-5 goes to
## overtime (blocks of 4 rounds, sides swap after 2, first to 3 in the block).
## Team strategy lives in Tactics; this class runs the rules.

const TEAM_SIZE := 5
const ROUNDS_PER_HALF := 5
const ROUNDS_TO_WIN := 6
const MAX_ROUNDS := 10
const BUY_TIME := 10.0
const POST_ROUND_TIME := 5.0 ## Live "exit" time: hunt or run. Survivors keep their guns.
const HALFTIME_TIME := 6.0
const PLANT_TIME := 4.0
const BOMB_TIMER := 45.0
const DEFUSE_TIME := 10.0
const DEFUSE_TIME_KIT := 5.0
const DEFUSE_RANGE := 40.0
const PICKUP_RANGE := 24.0
const BOMB_RADIUS := 630.0
const BOMB_DAMAGE := 220.0

const START_MONEY := 800
const MAX_MONEY := 16000
const WIN_REWARD := 3250
const OBJECTIVE_WIN_REWARD := 3500
const LOSS_BONUS := [1400, 1900, 2400, 2900, 3400]
const PLANT_BONUS := 800
const ARMOR_PRICE := 650
const HELMET_PRICE := 1000 ## Kevlar + helmet (350 if you already wear full kevlar).
const HELMET_UPGRADE := 350
const KIT_PRICE := 400
## Overtime (MR-style): 4-round blocks, sides swap after 2, first to 3 in the
## block wins it; 2-2 plays another block. Everyone restarts each OT half on OT_MONEY.
const OT_ROUNDS := 4
const OT_HALF := 2
const OT_TO_WIN := 3
const OT_MONEY := 10000

const WALL_MASK := 1
const T := 0
const CT := 1
const SIDE_NAMES := ["T", "CT"]
const FOG_COLOR := Color(0.45, 0.46, 0.52)

enum Phase { BUY, LIVE, POST_ROUND, HALFTIME, MATCH_OVER }
enum Bomb { CARRIED, DROPPED, PLANTED, DEFUSED, EXPLODED }

var mode: String = "quick"
var _kind := "" ## Exhibition flavour (allstar mode): "pug" / "trial" show matches, else the All-Star game.
var teams: Array[TeamData] = []
var starters: Array = [[], []] ## PlayerData per team index.
var sides: Array[int] = [T, CT] ## Side for each team index.
var score: Array[int] = [0, 0]
var round_num: int = 0
var loss_streak: Array[int] = [0, 0]
var phase: Phase = Phase.BUY
var phase_timer: float = 0.0
var round_time: float = 115.0 ## From the map (bigger maps get longer rounds).
var round_time_left: float = 115.0
var map_name := ""
var round_clock: float = 0.0
var units: Array[Unit] = []
var user_unit: Unit
var user_player: PlayerData
var loadouts := {} ## PlayerData -> {money, primary, armor, kit}
var stats := {} ## PlayerData -> {kills, deaths, damage, objectives}
var buy_menu_open: bool = false
var _recorded := false ## Result already handed to the career (at match end).
var round_log: Array[Dictionary] = [] ## Per-round summary (used by dev tests).
var _halftime_pending := false
var _match_over_pending := false
var _ot_pending := 0 ## 1 = an overtime block starts next round, 2 = OT halftime.
var _buy_log := {} ## Unit -> [{item, price, prev}] bought this buy phase (sell-back).
var replay: Replay ## Round recorder + replay / kill-cam / highlights player.
var killcam_enabled := true
var sim_highlights := {} ## PlayerData -> highlight moments in simulated rounds.

# Bomb.
var bomb_state: int = Bomb.CARRIED
var bomb_pos: Vector2 = Vector2.ZERO
var bomb_carrier: Unit = null
var bomb_timer: float = 0.0
var bomb_site: String = ""
var defuser: Unit = null
var planted_this_round := false
var plant_clock := 0.0
var _explosion_fx := 0.0

var rng := RandomNumberGenerator.new()
var tactics: Tactics

var arena: Arena
var bullets: BulletLayer
var blood: BloodLayer
var vfx: VfxLayer ## Explosions, smoke clouds, fire (rendered sheets).
var unit_layer: Node2D
var bomb_view: Node2D
var camera: Camera2D
var hud: Hud
var vision_light: PointLight2D
var ally_lights: Array[PointLight2D] = []
var sfx: Sfx
var utility: Utility
var crosshair: Crosshair
var _fog: CanvasModulate
var _spec_unit: Unit = null ## Who the camera follows while watching (spectating, or after you die).
var _spec_dead_t := 0.0 ## How long the followed unit has been dead (we linger, then move on).
var _freecam := false
var _freecam_pos := Vector2.ZERO
const FREECAM_SPEED := 900.0

## Weapons on the floor: {w: WeaponData (keeps its ammo), pos: Vector2}. Cleared each round.
var dropped_guns: Array[Dictionary] = []
var gun_view: Node2D
const GUN_PICKUP_RANGE := 44.0
## A bot dropped the bomb because you asked: only you can pick it up for a few seconds.
var bomb_reserved_for: Unit = null
var bomb_reserve_t := 0.0
var _beep_phase := 0.0
var _side_rids: Array = [[], []]


func _ready() -> void:
	rng.randomize()
	# The UI default is nearest (pixel-sharp text); the zoomed world wants smooth.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if Game.pending_match.is_empty():
		Game.prepare_quick_match()
	var pm: Dictionary = Game.pending_match
	_kind = String(pm.get("kind", ""))
	mode = pm.mode
	# Your weapon finish from the My Player shop (career matches only).
	GunArt.user_finish = Game.pworld.life().skin_tint() if mode in ["career", "bench", "allstar"] and Game.pworld != null and Game.pworld.user_player != null else Color(0, 0, 0, 0)
	teams.assign(pm.teams)
	for t in 2:
		starters[t] = teams[t].starters(TEAM_SIZE)
		for p: PlayerData in starters[t]:
			stats[p] = {"kills": 0, "deaths": 0, "damage": 0.0, "objectives": 0}
			loadouts[p] = _fresh_loadout(START_MONEY)
			if p.is_user:
				user_player = p
	sides.assign([T, CT] if rng.randf() < 0.5 else [CT, T])

	arena = Arena.new()
	map_name = String(pm.get("map", ""))
	if map_name == "":
		map_name = Maps.random_name(rng)
	arena.load_map(Maps.get_map(map_name))
	round_time = arena.round_time
	arena.z_index = -10 # Map at the bottom: blood (-5) and bodies (-1) draw over it.
	add_child(arena)
	blood = BloodLayer.new(self)
	add_child(blood)
	vfx = VfxLayer.new(self)
	add_child(vfx)
	tactics = Tactics.new(self, arena, rng)
	bomb_view = Node2D.new()
	bomb_view.draw.connect(_draw_bomb)
	bomb_view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(bomb_view)
	gun_view = Node2D.new()
	gun_view.draw.connect(_draw_guns)
	gun_view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(gun_view)
	utility = Utility.new(self)
	add_child(utility)
	unit_layer = Node2D.new()
	add_child(unit_layer)
	bullets = BulletLayer.new()
	add_child(bullets)
	sfx = Sfx.new()
	add_child(sfx)
	_build_fog()

	camera = Camera2D.new()
	# No limits at the map edge: you stay in the middle of the screen even
	# against the border, so every corner of the map is as easy to see.
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 12.0
	camera.zoom = Vector2(_zoom, _zoom)
	add_child(camera)
	camera.make_current()

	hud = Hud.new()
	add_child(hud)
	hud.setup_minimap(self)
	var xl := CanvasLayer.new()
	xl.layer = 5
	add_child(xl)
	crosshair = Crosshair.new()
	xl.add_child(crosshair)
	hud.buy_pressed.connect(func(item: String) -> void:
		if user_unit != null and phase == Phase.BUY:
			Game.ui_sounds.play("buy" if _purchase(user_unit, item) else "error"))
	hud.sell_pressed.connect(func(item: String) -> void:
		if user_unit != null and phase == Phase.BUY:
			Game.ui_sounds.play("buy" if _sell(user_unit, item) else "error"))
	hud.buy_close.connect(func() -> void:
		buy_menu_open = false
		_buy_closed_frame = Engine.get_process_frames())
	killcam_enabled = mode != "test"
	replay = Replay.new()
	replay.setup(self)
	add_child(replay)
	_debug_view = Node2D.new()
	_debug_view.z_index = 40
	_debug_view.draw.connect(_draw_ai_debug)
	add_child(_debug_view)
	hud.replay_cmd.connect(replay.command)
	hud.results_cmd.connect(func(cmd: String) -> void:
		if cmd == "highlights":
			replay.play_highlights(_highlight_focus())
		elif cmd == "replays":
			replay.play_round(replay.rounds.size() - 1))
	_start_round()


func _fresh_loadout(money: int) -> Dictionary:
	return {"money": money, "primary": -1, "pistol": -1, "armor": 0.0, "helmet": false, "kit": false, "grenades": {}}


func team_of_side(s: int) -> int:
	return 0 if sides[0] == s else 1


func is_pistol_round() -> bool:
	return round_num == 1 or round_num == ROUNDS_PER_HALF + 1


## 0 in regulation, else which overtime block the current round belongs to.
func ot_block() -> int:
	return ot_block_of(round_num)


static func ot_block_of(round_number: int) -> int:
	if round_number <= MAX_ROUNDS:
		return 0
	return (round_number - MAX_ROUNDS - 1) / OT_ROUNDS + 1


func is_overtime() -> bool:
	return ot_block() > 0


## Has a team won, given the score? Regulation: first to 6 (5-5 is not over).
## Overtime: every block starts level, first to OT_TO_WIN rounds in it wins.
static func match_decided(s: Array) -> bool:
	var played: int = int(s[0]) + int(s[1])
	var hi: int = maxi(int(s[0]), int(s[1]))
	if played <= MAX_ROUNDS:
		return hi >= ROUNDS_TO_WIN
	var block := ot_block_of(played)
	var base := (MAX_ROUNDS + (block - 1) * OT_ROUNDS) / 2
	return hi - base >= OT_TO_WIN


## Rounds a team still needs to win (for buy decisions: match point = 1).
func rounds_needed(team: int) -> int:
	var block := ot_block_of(rounds_played() + 1)
	if block == 0:
		return ROUNDS_TO_WIN - score[team]
	var base := (MAX_ROUNDS + (block - 1) * OT_ROUNDS) / 2
	return OT_TO_WIN - (score[team] - base)


## Last round before sides swap (halftime or OT halftime / block end).
func is_last_round_of_half() -> bool:
	if round_num == ROUNDS_PER_HALF or round_num == MAX_ROUNDS:
		return true
	if round_num > MAX_ROUNDS:
		return (round_num - MAX_ROUNDS) % OT_HALF == 0
	return false


# =============================================================================
# Round flow
# =============================================================================

func _start_round() -> void:
	round_num += 1
	bullets.clear_all()
	blood.clear()
	vfx.clear()
	hud.clear_feed()
	_spawn_units()
	_bots_buy()
	_reset_bomb()
	phase = Phase.BUY
	phase_timer = BUY_TIME
	round_time_left = round_time
	round_clock = 0.0
	round_winner_side = -1
	dropped_guns.clear()
	if gun_view != null:
		gun_view.queue_redraw()
	utility.clear()
	bomb_reserved_for = null
	_freecam = false
	_spec_unit = null
	tactics.setup_round()
	buy_menu_open = user_unit != null and not Game.autoplay
	hud.reset_buy_nav()
	_buy_log.clear()
	hud.set_score(teams, score, sides)
	hud.set_round_info(_round_info_text(), is_overtime())
	if user_unit != null:
		camera.position = user_unit.position
		camera.reset_smoothing()
	var sub := "Pistol round" if is_pistol_round() else "Buy phase"
	if is_overtime():
		var in_block := (round_num - MAX_ROUNDS - 1) % OT_ROUNDS + 1
		sub = "Overtime %d  -  round %d of %d, first to %d" % [ot_block(), in_block, OT_ROUNDS, OT_TO_WIN]
	if user_unit != null:
		sub += "  -  you are %s" % SIDE_NAMES[user_unit.side]
	if replay != null and replay.rounds.size() > 0:
		sub += "   |   V: replay last round"
	var title := "ROUND %d  -  %s" % [round_num, arena.map_name.to_upper()]
	if is_overtime():
		title = "OVERTIME %d  -  ROUND %d" % [ot_block(), round_num]
	hud.set_banner(title, sub)
	if replay != null:
		replay.begin_round()
	_chat_count = 0
	if round_num == 1:
		for i in 2:
			var u: Unit = units[rng.randi() % units.size()]
			chat(u, ["glhf", "gl hf", "gl", "have fun"][rng.randi() % 4])
	_pre_round_chat()


func _round_info_text() -> String:
	if is_overtime():
		return "OVERTIME %d  ·  R%d" % [ot_block(), round_num]
	return "ROUND %d / %d" % [round_num, MAX_ROUNDS]


func _spawn_units() -> void:
	for u in units:
		u.queue_free()
	units.clear()
	user_unit = null
	var rids_t: Array[RID] = []
	var rids_ct: Array[RID] = []
	_side_rids = [rids_t, rids_ct]
	for ti in 2:
		var side := sides[ti]
		var points := arena.spawn_points(side)
		var roster: Array = starters[ti]
		for i in roster.size():
			var pd: PlayerData = roster[i]
			var lo: Dictionary = loadouts[pd]
			var u := Unit.new()
			u.setup(pd, side, ti, self)
			if int(lo.get("pistol", -1)) >= 0:
				u.give_pistol(int(lo.pistol))
			if lo.primary >= 0:
				u.give_primary(lo.primary)
			u.armor = lo.armor
			u.helmet = bool(lo.get("helmet", false)) and u.armor > 0.0
			u.has_kit = lo.kit and side == CT
			u.grenades = (lo.get("grenades", {}) as Dictionary).duplicate()
			u.position = points[i % points.size()]
			u.aim_dir = Vector2.RIGHT if side == T else Vector2.LEFT
			unit_layer.add_child(u)
			u.died.connect(_on_unit_died)
			u.action_finished.connect(_on_action_finished)
			var ctrl = PlayerController.new() if pd.is_user and not Game.autoplay else BotController.new()
			ctrl.unit = u
			u.human = ctrl is PlayerController
			u.add_child(ctrl)
			units.append(u)
			_side_rids[side].append(u.get_rid())
			if pd.is_user:
				user_unit = u
				if not Game.autoplay:
					u.z_index = 11 # You always see yourself, even inside a smoke (smoke is z 10).
				u.damaged.connect(func(_src: Unit, amount: float) -> void: hud.flash_damage(amount))


func _save_loadouts() -> void:
	for u in units:
		var lo: Dictionary = loadouts[u.data]
		if u.alive:
			lo.primary = u.primary.id if u.primary != null else -1
			lo.pistol = u.pistol.id if u.pistol.id != WeaponData.starter(u.side) else -1
			lo.armor = u.armor
			lo.helmet = u.helmet
			lo.kit = u.has_kit
			lo.grenades = u.grenades.duplicate()
		else:
			lo.primary = -1
			lo.pistol = -1
			lo.armor = 0.0
			lo.helmet = false
			lo.kit = false
			lo.grenades = {}


func _end_round(winner: int, reason: String, objective: bool = false) -> void:
	if phase != Phase.LIVE:
		return
	phase = Phase.POST_ROUND
	phase_timer = POST_ROUND_TIME
	buy_menu_open = false
	for u in units:
		u.cancel_action()
	var loser := 1 - winner
	round_winner_side = sides[winner]
	score[winner] += 1
	var alive_now := alive_counts()
	round_log.append({"winner_side": sides[winner], "reason": reason, "planted": planted_this_round,
		"alive": [alive_now[0], alive_now[1]], "plant_clock": plant_clock if planted_this_round else -1.0,
		"strategy": tactics.strategy_label(), "clock": round_clock})

	# Economy.
	_pay_team(winner, OBJECTIVE_WIN_REWARD if objective else WIN_REWARD)
	loss_streak[winner] = 0
	loss_streak[loser] = mini(loss_streak[loser] + 1, LOSS_BONUS.size())
	var bonus: int = LOSS_BONUS[loss_streak[loser] - 1]
	if sides[loser] == T and planted_this_round:
		bonus += PLANT_BONUS
	_pay_team(loser, bonus)

	hud.set_score(teams, score, sides)
	var side_name: String = SIDE_NAMES[sides[winner]]
	hud.set_banner("%s WIN" % (teams[winner].team_name.to_upper()), "%s  -  %s   |   5s: survivors keep their weapons" % [side_name, reason])
	tactics.on_round_decided(sides[winner])
	if replay != null:
		replay.end_round(sides[winner], reason)
	_round_chat(sides[winner])
	print("Round %d: %s (%s) %s  |  %d-%d  [%s]" % [round_num, teams[winner].team_name, side_name, reason, score[0], score[1], tactics.strategy_label()])

	if match_decided(score):
		_match_over_pending = true
	elif round_num == ROUNDS_PER_HALF:
		_halftime_pending = true
	elif round_num >= MAX_ROUNDS and (round_num - MAX_ROUNDS) % OT_ROUNDS == 0:
		_ot_pending = 1 # Tied at the end of regulation / an OT block: (another) overtime.
	elif round_num > MAX_ROUNDS and (round_num - MAX_ROUNDS) % OT_ROUNDS == OT_HALF:
		_ot_pending = 2 # OT halftime: swap sides.


func _pay_team(team: int, amount: int) -> void:
	for p: PlayerData in starters[team]:
		_add_money(p, amount)


func _add_money(p: PlayerData, amount: int) -> void:
	var lo: Dictionary = loadouts[p]
	lo.money = clampi(lo.money + amount, 0, MAX_MONEY)


func _after_post_round() -> void:
	_save_loadouts()
	if _match_over_pending:
		_end_match()
	elif _halftime_pending:
		_halftime_pending = false
		phase = Phase.HALFTIME
		phase_timer = HALFTIME_TIME
		sides.assign([sides[1], sides[0]])
		loss_streak.assign([0, 0])
		for p: PlayerData in loadouts:
			loadouts[p] = _fresh_loadout(START_MONEY)
		hud.set_score(teams, score, sides)
		hud.set_banner("HALFTIME  %d - %d" % [score[0], score[1]], "Switching sides")
	elif _ot_pending > 0:
		var swap := _ot_pending == 2
		_ot_pending = 0
		phase = Phase.HALFTIME
		phase_timer = HALFTIME_TIME
		if swap:
			sides.assign([sides[1], sides[0]])
		loss_streak.assign([0, 0])
		for p: PlayerData in loadouts:
			loadouts[p] = _fresh_loadout(OT_MONEY)
		hud.set_score(teams, score, sides)
		var block := ot_block_of(round_num + 1)
		hud.set_round_info("OVERTIME %d" % block, true)
		if swap:
			hud.set_banner("OVERTIME %d  -  HALFTIME  %d - %d" % [block, score[0], score[1]], "Switching sides   |   $%s each" % _thousands(OT_MONEY))
		else:
			hud.set_banner("OVERTIME%s  %d - %d" % ["" if block == 1 else " %d" % block, score[0], score[1]],
				"Blocks of %d rounds, first to %d   |   $%s each, sides swap after %d" % [OT_ROUNDS, OT_TO_WIN, _thousands(OT_MONEY), OT_HALF])
	else:
		_start_round()


static func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


func _end_match() -> void:
	phase = Phase.MATCH_OVER
	Engine.time_scale = 1.0
	hud.set_banner("")
	hud.set_action("", 0.0)
	hud.set_score(teams, score, sides)
	# Record now (stats/progression), so the results screen shows real changes.
	var changes := {}
	var label := ""
	if mode == "manager" and Game.world != null:
		label = String(Game.world.user_match_this_week().get("label", ""))
		Game.finish_manager_match(match_result())
		changes = Game.world.last_report.get("player_changes", {})
	elif mode in ["career", "bench"] and Game.pworld != null:
		label = String(Game.pworld.user_match_this_week().get("label", ""))
		Game.finish_player_match(match_result())
		changes = Game.pworld.last_report.get("player_changes", {})
	elif mode == "watch":
		label = "Live: %s vs %s" % [teams[0].team_name, teams[1].team_name]
		Game.finish_watch_match(match_result())
	elif mode == "allstar":
		label = {"pug": "Show match", "showmatch": "Show match", "trial": "Trial match"}.get(_kind, "All-Star Showcase")
		Game.finish_allstar(match_result())
	_recorded = true
	var ot := ot_block_of(rounds_played())
	if ot > 0:
		var ot_text := "after overtime" if ot == 1 else "after %d overtimes" % ot
		label = ot_text if label == "" else "%s  -  %s" % [label, ot_text]
	hud.show_results(_results_data(label, changes), _leave_match)
	_gg_chat()
	hud.show_results_extras(replay.rounds.size(), replay.highlight_clips(_highlight_focus()).size())
	print("Match over: %s %d-%d %s%s" % [teams[0].team_name, score[0], score[1], teams[1].team_name, ("  (OT %d)" % ot) if ot > 0 else ""])


## What the career side records: {"score", "rounds", "players", "highlights", "overtimes"}.
## "highlights" = {PlayerData: int} moments per player (3k+ rounds, 1vX clutches
## won with X >= 2, aces), played and simulated rounds alike. Every starter has a key.
func match_result() -> Dictionary:
	return {"score": [score[0], score[1]], "rounds": rounds_played(), "players": stats, "highlights": highlight_counts(),
		"overtimes": ot_block_of(rounds_played())}


func highlight_counts() -> Dictionary:
	var out := {}
	for t in 2:
		for p: PlayerData in starters[t]:
			out[p] = int(sim_highlights.get(p, 0))
	if replay != null:
		var rec := replay.highlight_counts()
		for p in rec:
			out[p] = int(out.get(p, 0)) + int(rec[p])
	return out


## Highlights reel: your own moments when you played, otherwise anyone's.
func _highlight_focus() -> PlayerData:
	if user_player != null and not is_spectating() and mode != "spectate":
		return user_player
	return null


## Everything the results screen needs: per-team rows with match rating, MVP, stat changes.
func _results_data(label: String, changes: Dictionary) -> Dictionary:
	var rounds := maxi(1, rounds_played())
	var rows := [[], []]
	var mvp := ""
	var best := -1.0
	for t in 2:
		for p: PlayerData in starters[t]:
			var s: Dictionary = stats[p]
			var r := Progression.match_rating(s.kills, s.deaths, rounds, s.objectives, s.damage)
			if r > best:
				best = r
				mvp = p.player_name
			rows[t].append({"name": p.player_name, "rating": p.rating(), "kills": s.kills, "deaths": s.deaths,
				"adr": int(s.damage / rounds), "match_rating": r, "is_user": p.is_user,
				"change": changes.get(p.player_name, null)})
		rows[t].sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.match_rating > b.match_rating)
	var focus := 0 # Whose perspective: your team in career/manager/quick.
	return {"teams": teams, "score": score, "sides": sides, "rows": rows, "mvp": mvp, "label": label,
		"focus": focus, "perspective": mode in ["career", "manager", "quick", "bench", "allstar", "watch"], "map": arena.map_name}


func rounds_played() -> int:
	return score[0] + score[1]


func _leave_match() -> void:
	if mode == "test":
		return
	if mode == "manager":
		if not _recorded:
			Game.finish_manager_match(match_result())
		Game.goto(Game.MANAGER_SCENE)
		return
	if mode == "watch":
		if not _recorded:
			Game.finish_watch_match(match_result())
		Game.goto(Game.watch_back_scene())
		return
	if mode == "bench":
		if not _recorded:
			Game.finish_player_match(match_result())
		Game.goto(Game.CAREER_SCENE)
		return
	if mode == "allstar":
		Game.pending_match = {}
		Game.goto(Game.CAREER_SCENE)
		return
	if is_spectating():
		Game.pending_match = {}
		Game.goto(Game.MENU_SCENE)
		return
	if mode == "career":
		if not _recorded:
			Game.finish_player_match(match_result())
		Game.goto(Game.CAREER_SCENE)
	else:
		Game.pending_match = {}
		Game.goto(Game.MENU_SCENE)


# =============================================================================
# Economy / buying
# =============================================================================

func money_of(p: PlayerData) -> int:
	return int(loadouts[p].money) if loadouts.has(p) else 0


## Buy-menu item keys: "w:<weapon id>" for guns, "armor" (kevlar), "helmet"
## (kevlar + helmet), "kit", or a grenade kind.
static func weapon_item(weapon_id: int) -> String:
	return "w:%d" % weapon_id


## Price of `item` for `u` right now (helmet is cheaper over full kevlar).
func item_price(u: Unit, item: String) -> int:
	if item.begins_with("w:"):
		return WeaponData.price_of(int(item.substr(2)))
	match item:
		"armor":
			return ARMOR_PRICE
		"helmet":
			return HELMET_UPGRADE if u.armor >= 100.0 else HELMET_PRICE
		"kit":
			return KIT_PRICE
	if item in Utility.KINDS:
		return Utility.price(item, u.side)
	return 0


## Can't buy it at all (side-restricted / already have it / full)? "" if buyable,
## otherwise a short reason for the menu ("OWNED", "CT ONLY", "FULL").
func item_block(u: Unit, item: String) -> String:
	if item.begins_with("w:"):
		var wid := int(item.substr(2))
		if not WeaponData.allowed(wid, u.side):
			return "%s ONLY" % SIDE_NAMES[WeaponData.side_of(wid)]
		if (u.primary != null and u.primary.id == wid) or u.pistol.id == wid:
			return "OWNED"
		return ""
	match item:
		"armor":
			return "OWNED" if u.armor >= 100.0 else ""
		"helmet":
			return "OWNED" if u.armor >= 100.0 and u.helmet else ""
		"kit":
			if u.side != CT:
				return "CT ONLY"
			return "OWNED" if u.has_kit else ""
	if item in Utility.KINDS:
		if int(u.grenades.get(item, 0)) >= int(Utility.MAX_OF[item]) or Utility.total(u.grenades) >= Utility.MAX_TOTAL:
			return "FULL"
		return ""
	return "?"


func _purchase(u: Unit, item: String) -> bool:
	var lo: Dictionary = loadouts[u.data]
	if item_block(u, item) != "":
		return false
	var price := item_price(u, item)
	if lo.money < price:
		return false
	var rec := {"item": item, "price": price}
	if item.begins_with("w:"):
		var wid := int(item.substr(2))
		if WeaponData.is_secondary(wid):
			rec.prev = u.pistol
			u.give_pistol(wid)
		else:
			rec.prev = u.primary
			u.give_primary(wid)
	else:
		match item:
			"armor":
				rec.prev = [u.armor, u.helmet]
				u.armor = 100.0
			"helmet":
				rec.prev = [u.armor, u.helmet]
				u.armor = 100.0
				u.helmet = true
			"kit":
				u.has_kit = true
			_:
				u.grenades[item] = int(u.grenades.get(item, 0)) + 1
	lo.money -= price
	if not _buy_log.has(u):
		_buy_log[u] = []
	(_buy_log[u] as Array).append(rec)
	return true


## Items `u` bought this buy phase that can still be sold back (full refund).
func refundable(u: Unit) -> Dictionary:
	var out := {}
	if u == null or phase != Phase.BUY:
		return out
	for rec: Dictionary in _buy_log.get(u, []):
		out[rec.item] = true
	return out


## Sell back the most recent purchase of `item` this buy phase (CS-style refund).
func _sell(u: Unit, item: String) -> bool:
	if phase != Phase.BUY or not _buy_log.has(u):
		return false
	var log_: Array = _buy_log[u]
	for i in range(log_.size() - 1, -1, -1):
		var rec: Dictionary = log_[i]
		if rec.item != item:
			continue
		if item.begins_with("w:"):
			var wid := int(item.substr(2))
			if WeaponData.is_secondary(wid):
				if u.pistol.id != wid:
					return false
				var prev: WeaponData = rec.prev
				u.take_pistol(prev if prev != null else WeaponData.by_id(WeaponData.starter(u.side)))
			else:
				if u.primary == null or u.primary.id != wid:
					return false
				var prev: WeaponData = rec.prev
				if prev != null:
					u.take_primary(prev)
				else:
					u.primary = null
					u.weapon = u.pistol
					u.reloading = false
		else:
			match item:
				"armor", "helmet":
					u.armor = float(rec.prev[0])
					u.helmet = bool(rec.prev[1])
				"kit":
					u.has_kit = false
				_:
					if int(u.grenades.get(item, 0)) <= 0:
						return false
					u.grenades[item] = int(u.grenades[item]) - 1
					if u.grenades[item] <= 0:
						u.grenades.erase(item)
		log_.remove_at(i)
		_add_money(u.data, int(rec.price))
		return true
	return false


## Team buy call: "pistol", "eco", "force" or "full".
##  - full: the average player can afford a rifle + armour (guns already owned count),
##  - force: must-win rounds (match point against, last round of a half), or saving
##    wouldn't get us a full buy next round anyway,
##  - eco: otherwise save for next round.
func team_buy_plan(ti: int) -> String:
	if is_pistol_round():
		return "pistol"
	var n := maxi(1, starters[ti].size())
	var total := 0
	var gun_value := 0
	for p: PlayerData in starters[ti]:
		total += money_of(p)
		var pid := int(loadouts[p].primary)
		if pid >= 0:
			gun_value += WeaponData.price_of(pid)
	var avg := total / n
	var eff := (total + gun_value) / n
	if eff >= 4300:
		return "full"
	var must := rounds_needed(1 - ti) <= 1 or is_last_round_of_half()
	if must and avg >= 1400:
		return "force"
	var next_avg: int = avg + int(LOSS_BONUS[mini(loss_streak[ti], LOSS_BONUS.size() - 1)])
	if avg >= 2300 and next_avg < 4300:
		return "force"
	if not Game.ab_flag("old_ai4") and avg >= 1700:
		# They're broke too: SMGs and armour farm pistols (an anti-eco force).
		var their := 0
		for p: PlayerData in starters[1 - ti]:
			their += money_of(p)
		if their / maxi(1, starters[1 - ti].size()) < 1600:
			return "force"
	return "eco"


static var drops := 0 ## Dev stats: guns bought for a teammate.


## Team buy: a rich player buys a gun for a teammate who can't afford one
## (the classic drop), so the team buys together.
func _team_drops(ti: int, plan: String) -> void:
	if Game.ab_flag("old_ai4") or not plan in ["full", "force"]:
		return
	var needy: Array[Unit] = []
	var rich: Array[Unit] = []
	for u in units:
		if u.team_index != ti or (u.data.is_user and not Game.autoplay):
			continue
		if u.primary == null:
			needy.append(u)
		else:
			rich.append(u)
	rich.sort_custom(func(a: Unit, b: Unit) -> bool: return money_of(a.data) > money_of(b.data))
	for n in needy:
		var gun := WeaponData.pick(n.side, WeaponData.RAPTOR, WeaponData.GUARDIAN) if plan == "full" \
				else WeaponData.pick(n.side, WeaponData.KODIAK, WeaponData.LANCER)
		var price := WeaponData.price_of(gun)
		for r in rich:
			if money_of(r.data) >= price + 600:
				loadouts[r.data].money -= price
				n.give_primary(gun)
				drops += 1
				if tactics != null:
					tactics._say(r, "Dropping you a gun, %s." % n.data.name)
				break


func _bots_buy() -> void:
	for ti in 2:
		var plan := team_buy_plan(ti)
		for u in units:
			if u.team_index != ti or (u.data.is_user and not Game.autoplay):
				continue
			_bot_buy(u, plan)
		_team_drops(ti, plan)


## One bot's shopping: role-based (AWPer snipers, Entry close-range guns, Support
## cheaper guns + more utility) and economy-aware (the team's buy plan).
func _bot_buy(u: Unit, plan: String) -> void:
	var role := u.data.role
	var side := u.side
	var money := money_of(u.data)
	if plan == "pistol":
		var roll := rng.randf()
		if (role == "Entry" or roll < 0.5) and money >= ARMOR_PRICE:
			_purchase(u, "armor")
		elif roll < 0.8:
			var up := WeaponData.pick(side, WeaponData.VIPER, WeaponData.FALCON) if rng.randf() < 0.6 else WeaponData.DUSTER
			_purchase(u, weapon_item(up))
		elif side == CT:
			_purchase(u, "kit")
		_bot_buy_utility(u, 0)
		return
	if plan == "eco":
		# Poor decision makers force anyway.
		var forcing := rng.randf() > u.data._t("decision") * 0.8 + 0.2
		if forcing and money >= 1500:
			plan = "force"
		else:
			if u.primary != null:
				# Saved a gun: still top up armour and a nade or two.
				if u.armor < 50.0:
					_purchase(u, "armor")
				_bot_buy_utility(u, 1500)
			elif money >= 1900 and rng.randf() < 0.3:
				_purchase(u, weapon_item(WeaponData.DUSTER)) # Cheap pistol upgrade, still saving.
			return
	var want := _bot_primary_choice(u, plan)
	var have_tier := WeaponData.tier_of(u.primary.id) if u.primary != null else -1.0
	if want >= 0 and WeaponData.tier_of(want) > have_tier + 0.3:
		_purchase(u, weapon_item(want))
	elif u.primary == null and money_of(u.data) < WeaponData.price_of(WeaponData.pick(side, WeaponData.HORNET, WeaponData.KESTREL)) + ARMOR_PRICE:
		# Can't get a gun: at least a better pistol on a force.
		var pist := WeaponData.MAGNUM if money_of(u.data) >= 700 + ARMOR_PRICE and rng.randf() < 0.5 \
				else WeaponData.pick(side, WeaponData.VIPER, WeaponData.FALCON)
		if u.pistol.id == WeaponData.starter(side):
			_purchase(u, weapon_item(pist))
	# Armour: helmet on full buys, kevlar otherwise.
	if plan == "full" and money_of(u.data) >= HELMET_PRICE:
		_purchase(u, "helmet")
	elif u.armor < 50.0:
		_purchase(u, "armor")
	if u.side == CT and money_of(u.data) >= KIT_PRICE + 500 and rng.randf() < 0.6:
		_purchase(u, "kit")
	_bot_buy_utility(u, 0 if u.primary != null else 1000)
	# Rich with everything else: a better pistol too.
	if money_of(u.data) >= 2600 and u.pistol.id == WeaponData.starter(side):
		var pist2 := WeaponData.MAGNUM if role in ["Entry", "AWPer", "Rifler"] and rng.randf() < 0.6 \
				else WeaponData.pick(side, WeaponData.VIPER, WeaponData.FALCON)
		_purchase(u, weapon_item(pist2))


## Which primary a bot wants on this buy (-1 = nothing affordable). Leaves money
## for armour.
func _bot_primary_choice(u: Unit, plan: String) -> int:
	var side := u.side
	var money := money_of(u.data)
	var role := u.data.role
	var budget := money - ARMOR_PRICE
	var rifle := WeaponData.pick(side, WeaponData.RAPTOR, WeaponData.GUARDIAN)
	var cheap_rifle := WeaponData.pick(side, WeaponData.KODIAK, WeaponData.LANCER)
	var scoped := WeaponData.pick(side, WeaponData.TALON, WeaponData.OVERWATCH)
	var smg := WeaponData.pick(side, WeaponData.HORNET, WeaponData.KESTREL)
	var options: Array = []
	var awp_team := Tactics.team_style(teams[u.team_index].team_name) == "awp"
	if plan == "full" and awp_team and role == "Rifler" and u.data._t("aim") > 0.6 and rng.randf() < 0.35:
		role = "AWPer" # AWP-centric teams run a second sniper.
	if plan == "full":
		match role:
			"AWPer":
				options = [WeaponData.LONGBOW, rifle, WeaponData.PATHFINDER, cheap_rifle]
			"Entry":
				options = [rifle, WeaponData.SWARM if rng.randf() < 0.15 else rifle, cheap_rifle, smg]
			"Support":
				# Support keeps money for a full utility belt.
				budget -= 600
				options = [rifle, cheap_rifle, smg]
			_:
				var picky := role == "Rifler" and u.data._t("positioning") > 0.6 and rng.randf() < 0.3
				options = [scoped, rifle, cheap_rifle, smg] if picky else [rifle, cheap_rifle, smg]
	else: # force
		match role:
			"AWPer":
				options = [WeaponData.LONGBOW, WeaponData.PATHFINDER, cheap_rifle, smg] if awp_team else [WeaponData.PATHFINDER, cheap_rifle, smg]
			"Entry":
				options = [WeaponData.BREACHER if rng.randf() < 0.35 else smg, smg, WeaponData.BREACHER]
			"Support":
				options = [WeaponData.BULLDOG if rng.randf() < 0.4 else smg, smg]
			_:
				options = [cheap_rifle if rng.randf() < 0.55 else smg, smg, WeaponData.BULLDOG]
		if rng.randf() < 0.06:
			options.push_front(WeaponData.HAMMER) # The odd heavy-gun force.
		if rng.randf() < 0.08:
			options.push_front(WeaponData.TEMPEST)
	for wid in options:
		if WeaponData.allowed(wid, side) and WeaponData.price_of(wid) <= budget:
			return wid
	return -1


const UTIL_PREFS := {
	"Support": ["smoke", "flash", "molotov", "flash"],
	"Entry": ["flash", "flash", "frag"],
	"Rifler": ["smoke", "flash", "frag", "molotov"],
	"AWPer": ["flash", "smoke"],
	"Lurker": ["flash", "smoke", "molotov"],
}


## Grenades with whatever is left. Better Utility players buy more of them;
## `keep` is money they hold back (e.g. saving toward a gun).
func _bot_buy_utility(u: Unit, keep: int) -> void:
	var ut := u.data._t("utility")
	if Tactics.team_style(teams[u.team_index].team_name) == "utility":
		ut = minf(1.0, ut + 0.3)
	for kind: String in UTIL_PREFS.get(u.data.role, ["flash", "smoke"]):
		if money_of(u.data) - Utility.price(kind, u.side) < keep:
			continue
		if rng.randf() < 0.3 + 0.65 * ut:
			_purchase(u, kind)


# =============================================================================
# Bomb
# =============================================================================

func _reset_bomb() -> void:
	bomb_state = Bomb.CARRIED
	bomb_site = ""
	bomb_timer = 0.0
	defuser = null
	planted_this_round = false
	var ts: Array[Unit] = []
	for u in units:
		if u.side == T:
			ts.append(u)
	if ts.is_empty():
		return
	# Give the bomb to a Support/Rifler bot if possible: not the entry, not the AWPer.
	var candidates := ts.filter(func(u: Unit) -> bool: return u.data.role in ["Support", "Rifler"] and not u.data.is_user)
	if candidates.is_empty():
		candidates = ts
	bomb_carrier = candidates[rng.randi() % candidates.size()]
	bomb_carrier.has_bomb = true


func request_action(u: Unit) -> void:
	if not is_live() or u.action != Unit.Action.NONE:
		return
	if u.side == T:
		if u.has_bomb and bomb_state == Bomb.CARRIED and arena.site_at(u.global_position) != "":
			u.begin_action(Unit.Action.PLANT, PLANT_TIME)
			tactics.hear(u, "plant")
	elif can_defuse(u):
		defuser = u
		u.begin_action(Unit.Action.DEFUSE, DEFUSE_TIME_KIT if u.has_kit else DEFUSE_TIME)
		tactics.hear(u, "defuse")


func can_defuse(u: Unit) -> bool:
	if u.side != CT or bomb_state != Bomb.PLANTED:
		return false
	if u.global_position.distance_to(bomb_pos) > DEFUSE_RANGE:
		return false
	return defuser == null or defuser == u or not defuser.alive or defuser.action != Unit.Action.DEFUSE


func _on_action_finished(u: Unit, action: int) -> void:
	if not is_live() or not u.alive:
		return
	if action == Unit.Action.PLANT and u.has_bomb and bomb_state == Bomb.CARRIED:
		bomb_state = Bomb.PLANTED
		bomb_pos = u.global_position
		bomb_site = arena.site_at(bomb_pos)
		bomb_timer = BOMB_TIMER
		plant_clock = round_clock
		planted_this_round = true
		u.has_bomb = false
		bomb_carrier = null
		_beep_phase = 1.0 # First beep right away.
		stats[u.data].objectives += 1
		hud.add_feed_text("Bomb planted at %s by %s" % [bomb_site, u.data.player_name])
		if replay != null:
			replay.on_text("Bomb planted at %s by %s" % [bomb_site, u.data.player_name])
		tactics.on_planted(bomb_site, bomb_pos)
	elif action == Unit.Action.DEFUSE and bomb_state == Bomb.PLANTED:
		bomb_state = Bomb.DEFUSED
		stats[u.data].objectives += 1
		hud.add_feed_text("Bomb defused by %s" % u.data.player_name)
		if replay != null:
			replay.on_text("Bomb defused by %s" % u.data.player_name)
		_end_round(team_of_side(CT), "Bomb defused", true)


func _explode() -> void:
	bomb_state = Bomb.EXPLODED
	_explosion_fx = 0.8
	vfx.explode(bomb_pos, 285.0, true)
	if replay != null:
		replay.on_text("Bomb detonated")
	_end_round(team_of_side(T), "Bomb detonated", true)
	for u in units:
		if not u.alive:
			continue
		var d := u.global_position.distance_to(bomb_pos)
		if d < BOMB_RADIUS:
			var dealt := u.take_damage(BOMB_DAMAGE * (1.0 - d / BOMB_RADIUS), null)
			blood.hit(u, u.global_position, u.global_position - bomb_pos, dealt, not u.alive)


const BEEP_SLOW_INTERVAL := 2.0 ## Steady slow beep...
const BEEP_SLOW_PHASE := 25.0 ## ...for the first 25s after the plant.
const BEEP_FINAL_INTERVAL := 0.08 ## Near-continuous at detonation.


## Seconds between bomb beeps: steady and slow for the first 25s, then
## speeding up continuously until detonation.
func beep_interval() -> float:
	var ramp_len := BOMB_TIMER - BEEP_SLOW_PHASE # Last 20s.
	if bomb_timer >= ramp_len:
		return BEEP_SLOW_INTERVAL
	var t := 1.0 - bomb_timer / ramp_len # 0 -> 1 over the last 20s.
	return lerpf(BEEP_SLOW_INTERVAL, BEEP_FINAL_INTERVAL, pow(t, 1.3))


const BOMB_SPRITE: Texture2D = preload("res://assets/sprites/c4_planted.png") ## Rendered from art/blender/gun_kit.py (c4).
const BOMB_SPRITE_SIZE := Vector2(30, 22.5)
const BOMB_LED := Vector2(-7.0, 4.7) ## The timer's LED on the sprite, from its centre.


func _draw_bomb() -> void:
	if _explosion_fx > 0.0:
		var k := _explosion_fx / 0.8
		if not VfxLayer.available():
			bomb_view.draw_circle(bomb_pos, BOMB_RADIUS * (1.0 - k * 0.6), Color(1.0, 0.55, 0.2, 0.35 * k))
	match bomb_state:
		Bomb.DROPPED:
			if BOMB_SPRITE:
				bomb_view.draw_texture_rect(BOMB_SPRITE, Rect2(bomb_pos - BOMB_SPRITE_SIZE * 0.4, BOMB_SPRITE_SIZE * 0.8), false)
			else:
				bomb_view.draw_rect(Rect2(bomb_pos - Vector2(6, 5), Vector2(12, 10)), Color(0.8, 0.15, 0.15))
		Bomb.PLANTED, Bomb.DEFUSED:
			if BOMB_SPRITE:
				bomb_view.draw_texture_rect(BOMB_SPRITE, Rect2(bomb_pos - BOMB_SPRITE_SIZE * 0.5, BOMB_SPRITE_SIZE), false)
			else:
				bomb_view.draw_rect(Rect2(bomb_pos - Vector2(7, 6), Vector2(14, 12)), Color(0.7, 0.12, 0.12))
			if bomb_state == Bomb.PLANTED:
				if _beep_phase < 0.35:
					var led := bomb_pos + (BOMB_LED if BOMB_SPRITE else Vector2.ZERO)
					bomb_view.draw_circle(led, 5.0, Color(1, 0.15, 0.1, 0.35))
					bomb_view.draw_circle(led, 2.2, Color(1, 0.35, 0.3))
				bomb_view.draw_arc(bomb_pos, DEFUSE_RANGE, 0, TAU, 32, Color(1, 0.3, 0.3, 0.25), 1.0)


# =============================================================================
# Deaths
# =============================================================================

func _on_unit_died(victim: Unit, killer: Unit) -> void:
	stats[victim.data].deaths += 1
	if victim.side == CT and victim.weapon != null and victim.weapon.cat == WeaponData.SNIPER:
		tactics.note_awp_death(victim)
	if phase == Phase.POST_ROUND:
		postround_kills += 1
	if killer != null and killer.side != victim.side:
		stats[killer.data].kills += 1
		_add_money(killer.data, killer.kill_reward())
		for c in killer.get_children():
			if c is BotController:
				(c as BotController).on_got_kill()
	hud.add_kill(killer, victim)
	if replay != null:
		replay.on_kill(killer, victim)
	if killer != null and killer.side != victim.side and phase == Phase.LIVE:
		_kill_chat(killer, victim)
	var drop_at := victim.global_position + Vector2(randf_range(-10, 10), randf_range(-10, 10))
	if victim.primary != null:
		drop_gun(victim.primary, drop_at)
		victim.primary = null
	elif victim.pistol.id != WeaponData.starter(victim.side):
		drop_gun(victim.pistol, drop_at) # A bought pistol is worth picking up too.
	if victim == user_unit:
		_spec_unit = victim # Linger on your own body for a moment, then follow a teammate.
		_spec_dead_t = 0.0
		if killcam_enabled and killer != null and killer != victim and not Game.autoplay and not is_spectating():
			replay.call_deferred("start_killcam", killer, victim)
	if victim == bomb_reserved_for:
		bomb_reserved_for = null
	if victim.has_bomb:
		victim.has_bomb = false
		bomb_state = Bomb.DROPPED
		bomb_pos = victim.global_position
		bomb_carrier = null
	if victim == defuser:
		defuser = null
	tactics.on_death(victim, killer)
	# Nearby teammates react: look where the shot came from (trade).
	if killer != null:
		for u in units:
			if u.alive and u.side == victim.side and u.global_position.distance_to(victim.global_position) < 700.0:
				for c in u.get_children():
					if c is BotController:
						(c as BotController).on_teammate_died(killer.global_position)
	if phase != Phase.LIVE:
		return
	var alive := alive_counts()
	if alive[CT] == 0:
		_end_round(team_of_side(T), "Elimination")
	elif alive[T] == 0 and bomb_state != Bomb.PLANTED:
		_end_round(team_of_side(CT), "Elimination")


func alive_counts() -> Array[int]:
	var alive: Array[int] = [0, 0]
	for u in units:
		if u.alive:
			alive[u.side] += 1
	return alive


## A knife swipe connected (Unit._slash).
func on_knife_hit(attacker: Unit, victim: Unit, dealt: float) -> void:
	register_damage(attacker, dealt)
	blood.hit(victim, victim.global_position, victim.global_position - attacker.global_position, dealt, not victim.alive,
		not user_sees(victim))
	tactics.hear(attacker, "knife")


## Can the player (or whoever the camera follows) see this unit right now?
## Hits on enemies you can't see (in smoke, behind a wall) show nothing.
func user_sees(u: Unit) -> bool:
	if is_spectating() or Game.autoplay or user_unit == null:
		return true
	var viewer := _camera_target()
	if viewer == null or u.side == viewer.side:
		return true
	return u.modulate.a > 0.35 and (not u.alive or sees(viewer, u))


func register_damage(shooter: Unit, amount: float) -> void:
	if shooter != null and stats.has(shooter.data):
		stats[shooter.data].damage += amount


# =============================================================================
# API used by units and bots
# =============================================================================

func is_live() -> bool:
	return phase == Phase.LIVE


## Units can still move and shoot: the live round plus the 5s after it's decided
## (objectives are locked then; survivors who make it keep their weapons).
func can_fight() -> bool:
	return phase == Phase.LIVE or phase == Phase.POST_ROUND


## Which team index won the round being played out in post-round, or -1.
var round_winner_side := -1
var postround_kills := 0 ## Kills during exit time (dev stats).


## Hitscan: the shot lands instantly; BulletLayer just draws a tracer.
func spawn_bullet(shooter: Unit, _origin: Vector2, dir: Vector2) -> void:
	bullets.fire(shooter, _shot_origin(shooter, dir), dir, shooter.weapon, _side_rids[shooter.side])
	tactics.on_gunfire(shooter)


## BulletLayer: a shot went from `from` to `to` (the replay draws it as a tracer).
func on_shot(shooter: Unit, from: Vector2, to: Vector2) -> void:
	if replay != null and (phase == Phase.LIVE or phase == Phase.POST_ROUND):
		replay.on_shot(shooter, from, to)


func objective_for(u: Unit) -> Dictionary:
	return tactics.order_for(u)


## Bot radio: shown for the player's team (both teams when just spectating).
func radio(speaker: Unit, text: String) -> void:
	if hud == null or speaker == null:
		return
	if user_unit != null and is_instance_valid(user_unit) and not Game.autoplay and speaker.side != user_unit.side:
		return
	hud.add_radio(speaker.data.player_name, Unit.SIDE_COLORS[speaker.side], text)


func report_enemy(spotter: Unit, enemy: Unit) -> void:
	tactics.on_spotted(spotter, enemy)


func on_reload(u: Unit) -> void:
	if is_live():
		tactics.request_cover(u)
		tactics.hear(u, "reload")


func enemies_of(side: int) -> Array[Unit]:
	var out: Array[Unit] = []
	for u in units:
		if u.alive and u.side != side:
			out.append(u)
	return out


## Walls and smoke block sight.
func has_line_of_sight(from: Vector2, to: Vector2) -> bool:
	if utility != null and not utility.smokes.is_empty() and utility.blocks(from, to):
		return false
	return has_wall_los(from, to)


## Walls only (explosions, throws).
func has_wall_los(from: Vector2, to: Vector2) -> bool:
	var q := PhysicsRayQueryParameters2D.create(from, to, WALL_MASK)
	return get_world_2d().direct_space_state.intersect_ray(q).is_empty()


## Symmetric visibility: if any part of A (center or either shoulder) can see
## any part of B, they see each other. Returns [from_point, to_point] or [].
## Used for fog, bot spotting and bot aiming, so if you can see a bot peeking
## a corner, that bot can see (and shoot) you too.
func sight_line(a: Unit, b: Unit) -> Array:
	var pa := a.global_position
	var pb := b.global_position
	var perp := (pb - pa).normalized().orthogonal() * (Unit.RADIUS * Unit.SHOULDER)
	var from_pts := [pa, pa + perp, pa - perp]
	var to_pts := [pb, pb + perp, pb - perp]
	for f: Vector2 in from_pts:
		for t: Vector2 in to_pts:
			if has_line_of_sight(f, t):
				return [f, t]
	return []


func can_see(viewer: Unit, target: Unit) -> bool:
	return not sight_line(viewer, target).is_empty()


## Shots leave from the part of the body with the clearest line along the aim,
## so someone peeking a corner can shoot back from the exposed shoulder.
func _shot_origin(u: Unit, dir: Vector2) -> Vector2:
	var center := u.global_position
	var perp := dir.orthogonal() * (Unit.RADIUS * Unit.SHOULDER)
	var best := center
	var best_d := _wall_distance(center, dir, Unit.BULLET_RANGE)
	for o in [center + perp, center - perp]:
		var d := _wall_distance(o, dir, Unit.BULLET_RANGE)
		if d > best_d + 8.0:
			best_d = d
			best = o
	return best


func _wall_distance(from: Vector2, dir: Vector2, max_d: float) -> float:
	var q := PhysicsRayQueryParameters2D.create(from, from + dir * max_d, WALL_MASK)
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	return max_d if hit.is_empty() else from.distance_to(hit.position)


func _closest(side: int, pos: Vector2) -> Unit:
	var best: Unit = null
	var best_d := INF
	for u in units:
		if u.alive and u.side == side:
			var d := u.global_position.distance_squared_to(pos)
			if d < best_d:
				best_d = d
				best = u
	return best


# =============================================================================
# Fog of war / vision cones: the world is dimmed except where your cone (and
# your teammates' cones) reach past the walls. Enemies you can't notice are hidden.
# =============================================================================

## Everyone (you and the bots) sees with the same rules:
##  - a cone in front of them (width from the Positioning stat),
##  - a small circle of close awareness around their body,
##  - movement glimpsed in peripheral vision,
##  - and walls block all of it.
const NEAR_VISION := 120.0
const CONE_TEX_SIZE := 256
const VIEW_LIGHT_SCALE := 12.0 ## 256px * 12 = 3072px across: covers the free-look view.
const ALLY_LIGHT_SCALE := 7.0

var _cone_cache := {}


func _build_fog() -> void:
	var fog := CanvasModulate.new()
	fog.color = FOG_COLOR if mode != "spectate" else Color.WHITE
	add_child(fog)
	_fog = fog
	vision_light = _make_vision_light(VIEW_LIGHT_SCALE)
	# Teammates share what their cones see (shorter reach so your own view dominates).
	for i in TEAM_SIZE:
		ally_lights.append(_make_vision_light(ALLY_LIGHT_SCALE))


## Can `viewer` notice `target` right now? Same rule for players and bots.
func sees(viewer: Unit, target: Unit) -> bool:
	if viewer.is_blind():
		return false
	var to := target.global_position - viewer.global_position
	var d := to.length()
	if d > viewer.data.sight_range() or d < 0.01:
		return false
	if not on_users_screen(viewer, target):
		return false
	var facing := viewer.aim_dir.dot(to / d)
	var in_view := d < NEAR_VISION or facing > viewer.data.fov_dot() or (target.is_moving() and facing > -0.4)
	return in_view and can_see(viewer, target)


## Fairness: a bot can only spot / shoot the human player from somewhere the
## player can see on their own screen. Bot-vs-bot sight is unaffected.
func on_users_screen(viewer: Unit, target: Unit) -> bool:
	if target != user_unit or Game.autoplay or camera == null or not target.data.is_user:
		return true
	var half := get_viewport().get_visible_rect().size / 2.0 / camera.zoom
	var c := camera.get_screen_center_position()
	var p := viewer.global_position
	var margin := Unit.RADIUS * 0.5 # Half their body poking onto the screen counts.
	return absf(p.x - c.x) < half.x + margin and absf(p.y - c.y) < half.y + margin


func fov_half_degrees(u: Unit) -> float:
	return rad_to_deg(acos(clampf(u.data.fov_dot(), -1.0, 1.0)))


## Light texture: a soft-edged cone pointing +X plus a small circle at the center.
func _cone_texture(half_deg: float, scale: float) -> Texture2D:
	var key := "%d_%d" % [int(round(half_deg)), int(scale)]
	if _cone_cache.has(key):
		return _cone_cache[key]
	var size := CONE_TEX_SIZE
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) / 2.0
	var r_max := size / 2.0
	var near_px := NEAR_VISION / scale
	var half := deg_to_rad(half_deg)
	var soft := deg_to_rad(5.0)
	for y in size:
		for x in size:
			var v := Vector2(x + 0.5, y + 0.5) - c
			var d := v.length()
			var radial := clampf((r_max - d) / (r_max * 0.12), 0.0, 1.0)
			var cone := clampf((half - absf(v.angle())) / soft + 0.5, 0.0, 1.0)
			var near := clampf((near_px - d) / 3.0 + 0.5, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, maxf(cone, near) * radial))
	var tex := ImageTexture.create_from_image(img)
	_cone_cache[key] = tex
	return tex


func _make_vision_light(scale: float) -> PointLight2D:
	var l := PointLight2D.new()
	l.texture_scale = scale
	# MIX blends from the fog colour up to full brightness by the texture's
	# alpha, so overlapping cones never over-brighten (ADD would stack).
	l.color = Color(1, 1, 1, 1)
	l.blend_mode = Light2D.BLEND_MODE_MIX
	l.shadow_enabled = true
	l.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	l.shadow_filter_smooth = 2.0
	l.enabled = false
	add_child(l)
	return l


## Manager mode: skip the rest of the match (rounds decided by team strength).
func _sim_rest_of_match() -> void:
	var p := 1.0 / (1.0 + exp(-(teams[0].rating() - teams[1].rating()) / 14.0))
	if replay != null:
		replay.stop()
	while not match_decided(score):
		var w := 0 if rng.randf() < p else 1
		score[w] += 1
		_sim_round_stats(w)
	round_num = rounds_played()
	Engine.time_scale = 1.0
	_end_match()


## Kills/deaths/damage for a round that was simulated instead of played.
## Winners usually trade 4-5 kills, losers 0-3; better players get more.
func _sim_round_stats(winner: int) -> void:
	var counts := [0, 0]
	counts[winner] = 5 if rng.randf() < 0.6 else 4
	counts[1 - winner] = rng.randi_range(0, 3)
	for t in 2:
		var alive_victims: Array = starters[1 - t].duplicate()
		var round_kills := {}
		for i in mini(counts[t], alive_victims.size()):
			var killer: PlayerData = _weighted_pick(starters[t])
			var victim: PlayerData = alive_victims.pop_at(rng.randi() % alive_victims.size())
			stats[killer].kills += 1
			stats[killer].damage += 100.0 + rng.randf_range(0.0, 40.0)
			stats[victim].deaths += 1
			round_kills[killer] = int(round_kills.get(killer, 0)) + 1
		for k in round_kills:
			if int(round_kills[k]) >= 3:
				sim_highlights[k] = int(sim_highlights.get(k, 0)) + 1
	for t in 2:
		for pl: PlayerData in starters[t]:
			stats[pl].damage += rng.randf_range(0.0, 30.0) # Chip damage.


func _weighted_pick(players: Array) -> PlayerData:
	var total := 0.0
	for pl: PlayerData in players:
		total += pow(pl.rating_exact(), 2.0)
	var x := rng.randf() * total
	for pl: PlayerData in players:
		x -= pow(pl.rating_exact(), 2.0)
		if x <= 0.0:
			return pl
	return players[0]


## Camera isn't on our own live player: a watched match, or we're dead.
func _watching_others() -> bool:
	return is_spectating() or user_unit == null or not user_unit.alive


## Who you may watch: everyone when spectating, only teammates once you're dead.
func _spec_pool() -> Array[Unit]:
	var out: Array[Unit] = []
	for u in units:
		if u.alive and (is_spectating() or user_unit == null or u.side == user_unit.side):
			out.append(u)
	return out


func _nearest_in_pool(pos: Vector2) -> Unit:
	var best: Unit = null
	var best_d := INF
	for u in _spec_pool():
		var d := u.global_position.distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best = u
	return best


## Keep a valid follow target: linger 1.5s on whoever just died, then jump to
## the nearest player we're allowed to watch.
func _update_spectate_target(real_dt: float) -> void:
	if not _watching_others():
		_spec_unit = null
		return
	if _spec_unit == null or not is_instance_valid(_spec_unit) or not units.has(_spec_unit):
		_spec_unit = _nearest_in_pool(camera.position)
		_spec_dead_t = 0.0
	elif not _spec_unit.alive:
		_spec_dead_t += real_dt
		if _spec_dead_t > 1.5:
			var n := _nearest_in_pool(_spec_unit.global_position)
			if n != null:
				_spec_unit = n
				_spec_dead_t = 0.0
	else:
		_spec_dead_t = 0.0


func _spectate_input(real_dt: float) -> void:
	if Input.is_action_just_pressed("shoot"):
		_spec_next(1)
	elif Input.is_action_just_pressed("free_look") and not Input.is_key_pressed(KEY_SHIFT):
		_spec_next(-1)
	if Input.is_action_just_pressed("freecam"):
		_freecam = not _freecam
		_freecam_pos = camera.get_screen_center_position()
	if _freecam:
		var mv := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		var fast := 2.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0
		_freecam_pos += mv * FREECAM_SPEED * fast * real_dt / camera.zoom.x
		_freecam_pos = _freecam_pos.clamp(Vector2.ZERO, arena.size_px())
	if is_spectating():
		if Input.is_action_just_pressed("speed_up"):
			Engine.time_scale = minf(Engine.time_scale * 2.0, 8.0)
			Engine.max_physics_steps_per_frame = 16
		elif Input.is_action_just_pressed("slow_down"):
			Engine.time_scale = maxf(Engine.time_scale / 2.0, 0.5)
	var u := _camera_target()
	var who := "-"
	if _freecam:
		who = "FREE CAMERA"
	elif u != null:
		who = "%s  (%s %s, RTG %d)%s" % [u.data.player_name, SIDE_NAMES[u.side], u.data.role, u.data.rating(), "" if u.alive else "  -  dead"]
	var keys := "Click / Right-click: next / previous %s   Space: free camera (WASD, Shift = fast)   Wheel: zoom" % ("player" if is_spectating() else "teammate")
	if is_spectating():
		hud.set_spectate_info("SPECTATING  %s\nT: %s     CT: %s     Speed %sx\n%s\n-  /  = : speed (up to 8x)   Esc: %s" % [
			who, tactics.t_strat.get("name", "?"), tactics.ct_setup.get("name", "?"), str(Engine.time_scale), keys,
			"sim the rest" if mode in ["manager", "bench", "watch"] else "menu"])
	else:
		hud.set_spectate_info("YOU DIED  -  watching %s\n%s" % [who, keys])


func _spec_next(step: int) -> void:
	var pool := _spec_pool()
	_freecam = false
	if pool.is_empty():
		return
	var i := pool.find(_spec_unit)
	_spec_unit = pool[0 if i < 0 else posmod(i + step, pool.size())]
	_spec_dead_t = 0.0


## HUD player dots: per team index, in lineup order.
func _roster_rows() -> Array:
	var show_bomb := is_spectating() or (user_unit != null and user_unit.side == T)
	var rows := [[], []]
	for u in units:
		rows[u.team_index].append({"name": u.data.player_name, "alive": u.alive, "hp": u.health, "hp_known": shows_health(u), "side": u.side,
			"user": u.data.is_user, "bomb": u.has_bomb and show_bomb, "watched": u == _camera_target() and _watching_others() and not _freecam})
	return rows


# =============================================================================
# Dropped weapons
# =============================================================================

func drop_gun(w: WeaponData, pos: Vector2) -> void:
	var cell := arena.world_to_cell(pos)
	if arena.is_solid(cell):
		pos = arena.cell_center(arena.nearest_open(cell))
	dropped_guns.append({"w": w, "pos": pos})
	gun_view.queue_redraw()


## Index of the closest gun `u` can grab, or -1.
func _gun_near(u: Unit, reach: float = GUN_PICKUP_RANGE) -> int:
	var best := -1
	var best_d := reach
	for i in dropped_guns.size():
		var d: float = u.global_position.distance_to(dropped_guns[i].pos)
		if d < best_d:
			best_d = d
			best = i
	return best


## Pick up the nearest gun; whatever primary you had goes on the floor.
func pickup_gun(u: Unit) -> bool:
	if not u.alive or u.action != Unit.Action.NONE:
		return false
	var i := _gun_near(u)
	if i < 0:
		return false
	var g: Dictionary = dropped_guns[i]
	dropped_guns.remove_at(i)
	var gw: WeaponData = g.w
	if gw.is_pistol():
		drop_gun(u.pistol, u.global_position)
		u.take_pistol(gw)
	else:
		if u.primary != null:
			drop_gun(u.primary, u.global_position)
		u.take_primary(gw)
	sfx.play("rifle_reload", u.global_position, -8.0, 0.1)
	gun_view.queue_redraw()
	return true


## G: drop the bomb if you carry it, otherwise the gun in your hands.
func drop_item(u: Unit) -> void:
	if not u.alive or u.action != Unit.Action.NONE:
		return
	var toss := u.global_position + u.aim_dir * 34.0
	if not has_line_of_sight(u.global_position, toss):
		toss = u.global_position
	if u.has_bomb:
		u.has_bomb = false
		bomb_state = Bomb.DROPPED
		bomb_pos = toss
		bomb_carrier = null
		bomb_reserved_for = null
		hud.add_feed_text("%s dropped the bomb" % u.data.player_name)
	elif u.primary != null and u.weapon == u.primary:
		var w := u.primary
		u.primary = null
		u.weapon = u.pistol
		u.reloading = false
		drop_gun(w, toss)


## Y in buy phase (or live): the bot carrying the bomb drops it at your feet.
func request_bomb(u: Unit) -> void:
	if u == null or not u.alive or u.side != T or u.has_bomb or bomb_state != Bomb.CARRIED:
		return
	if phase != Phase.BUY and phase != Phase.LIVE:
		return
	var c := bomb_carrier
	if c == null or not c.alive or c.data.is_user:
		return
	c.has_bomb = false
	bomb_carrier = null
	bomb_state = Bomb.DROPPED
	var near := c.global_position.distance_to(u.global_position) < 260.0
	# Close (buy phase at spawn): toss it right to you. Far: they drop it where they stand.
	bomb_pos = u.global_position + (c.global_position - u.global_position).normalized() * 12.0 if near else c.global_position
	bomb_reserved_for = u
	bomb_reserve_t = 10.0
	hud.add_feed_text("%s dropped the bomb for %s" % [c.data.player_name, u.data.player_name])


func _bomb_pickups(delta: float) -> void:
	if bomb_reserved_for != null:
		bomb_reserve_t -= delta if phase == Phase.LIVE else 0.0
		if bomb_reserve_t <= 0.0 or not is_instance_valid(bomb_reserved_for) or not bomb_reserved_for.alive:
			bomb_reserved_for = null
	if bomb_state != Bomb.DROPPED:
		return
	for u in units:
		if bomb_reserved_for != null and u != bomb_reserved_for:
			continue
		if u.alive and u.side == T and u.global_position.distance_to(bomb_pos) < PICKUP_RANGE:
			u.has_bomb = true
			bomb_carrier = u
			bomb_state = Bomb.CARRIED
			bomb_reserved_for = null
			break


const GUN_COLORS := {WeaponData.PISTOL: Color(0.85, 0.85, 0.85), WeaponData.SMG: Color(0.75, 0.85, 0.55),
	WeaponData.SHOTGUN: Color(0.9, 0.7, 0.45), WeaponData.RIFLE: Color(0.95, 0.85, 0.4),
	WeaponData.SNIPER: Color(0.6, 0.85, 1.0), WeaponData.HEAVY: Color(0.95, 0.6, 0.5)}


func _draw_guns() -> void:
	var font := ThemeDB.fallback_font
	for g in dropped_guns:
		var w: WeaponData = g.w
		var p: Vector2 = g.pos
		var col: Color = GUN_COLORS.get(w.cat, Color.WHITE)
		var length := 20.0 if w.cat == WeaponData.SNIPER else (16.0 if w.cat in [WeaponData.RIFLE, WeaponData.HEAVY] else (8.0 if w.cat == WeaponData.PISTOL else 12.0))
		var dir := Vector2.RIGHT.rotated(float(hash(p) % 628) / 100.0)
		if not GunArt.draw_floor(gun_view, w, p, dir.angle()):
			gun_view.draw_line(p - dir * length / 2.0, p + dir * length / 2.0, Color(0, 0, 0, 0.8), 6.0)
			gun_view.draw_line(p - dir * length / 2.0, p + dir * length / 2.0, col, 3.0)
		if user_unit != null and user_unit.alive and user_unit.global_position.distance_to(p) < 160.0:
			gun_view.draw_string(font, p + Vector2(-40, -10), w.weapon_name, HORIZONTAL_ALIGNMENT_CENTER, 80, 10, Color(col, 0.9))


func _update_fog(delta: float) -> void:
	var viewer := _camera_target()
	if viewer == null:
		return
	if is_spectating():
		_fog.color = Color.WHITE # Watching bots: no fog, full brightness.
		vision_light.enabled = false
		for l in ally_lights:
			l.enabled = false
		for u in units:
			u.modulate.a = 1.0
		sfx.set_listener(_freecam_pos if _freecam else viewer.global_position)
		return
	if not viewer.alive:
		# Dead and nobody left to watch through: just dim the world.
		var any_ally := false
		for u in units:
			if u.alive and u.side == viewer.side:
				any_ally = true
				break
		if not any_ally:
			vision_light.enabled = false
			for l in ally_lights:
				l.enabled = false
			sfx.set_listener(camera.position)
			return
	_fog.color = FOG_COLOR
	_aim_light(vision_light, viewer, VIEW_LIGHT_SCALE)
	vision_light.enabled = viewer.alive
	sfx.set_listener(_freecam_pos if _freecam and _watching_others() else viewer.global_position)
	# Only your own eyes: teammates' sightings reach you as calls on the minimap.
	for l in ally_lights:
		l.enabled = false
	var match_over := phase == Phase.MATCH_OVER
	for u in units:
		var show := true
		if u.side != viewer.side and not match_over:
			if u.alive:
				show = sees(viewer, u)
			else:
				# Bodies: once you've seen them, or when there's a clear line to them.
				show = u.modulate.a > 0.5 or (viewer.global_position.distance_to(u.global_position) < viewer.data.sight_range() 						and has_line_of_sight(viewer.global_position, u.global_position))
		var fade := 10.0
		if show and viewer.human and u.side != viewer.side and not Game.ab_flag("old_skills"):
			fade = viewer.data.user_reveal_rate() # Reaction: how fast they pop into view.
		u.modulate.a = move_toward(u.modulate.a, 1.0 if show else 0.0, delta * fade)


func _aim_light(l: PointLight2D, u: Unit, scale: float) -> void:
	l.texture = _cone_texture(fov_half_degrees(u), scale)
	l.global_position = u.global_position
	l.rotation = u.aim_dir.angle()
	l.enabled = true


# =============================================================================
# Frame update
# =============================================================================

func _physics_process(delta: float) -> void:
	_explosion_fx = maxf(0.0, _explosion_fx - delta)
	match phase:
		Phase.BUY:
			phase_timer -= delta
			_bomb_pickups(delta)
			if phase_timer <= 0.0:
				phase = Phase.LIVE
				buy_menu_open = false
				hud.set_banner("")
		Phase.LIVE:
			round_clock += delta
			tactics.update(delta)
			if bomb_state == Bomb.PLANTED:
				bomb_timer -= delta
				# Beep in sync with the blinking light: 1/s at plant, ~8/s near the end.
				_beep_phase += delta / beep_interval()
				if _beep_phase >= 1.0:
					_beep_phase -= 1.0
					sfx.play("bomb_beep", bomb_pos, -3.0, 0.0)
				if bomb_timer <= 0.0:
					_explode()
			else:
				round_time_left -= delta
				if round_time_left <= 0.0:
					_end_round(team_of_side(CT), "Time ran out")
			_bomb_pickups(delta)
		Phase.POST_ROUND:
			round_clock += delta
			tactics.update(delta)
			phase_timer -= delta
			if phase_timer <= 0.0:
				_after_post_round()
		Phase.HALFTIME:
			phase_timer -= delta
			if phase_timer <= 0.0:
				_start_round()
	bomb_view.queue_redraw()
	gun_view.queue_redraw() # Always: an emptied list (new round, last pickup) must clear the old drawing.
	if replay != null and (phase == Phase.LIVE or phase == Phase.POST_ROUND):
		replay.sample(round_clock)


func _process(delta: float) -> void:
	_update_fog(delta)
	if phase == Phase.MATCH_OVER and (Input.is_action_just_pressed("confirm") or (Game.autoplay and mode != "test")):
		_leave_match()
		return
	var real_dt := delta / maxf(Engine.time_scale, 0.01)
	_update_spectate_target(real_dt)
	if _watching_others():
		_spectate_input(real_dt)
	else:
		hud.set_spectate_info("")
	hud.set_roster(_roster_rows())
	if _buy_closed_frame >= Engine.get_process_frames() - 1:
		pass # Esc just closed the buy menu: don't also leave / sim.
	elif Input.is_action_just_pressed("quit") and mode in ["manager", "bench", "watch"] and phase != Phase.MATCH_OVER:
		_sim_rest_of_match()
		return
	elif Input.is_action_just_pressed("quit") and (mode == "quick" or is_spectating()):
		_leave_match()
		return
	if Input.is_action_just_pressed("buy_menu") and phase == Phase.BUY and user_unit != null:
		buy_menu_open = not buy_menu_open
		if buy_menu_open:
			hud.reset_buy_nav()
	if Input.is_key_pressed(KEY_V) and not _v_down and (phase == Phase.BUY or phase == Phase.HALFTIME) \
			and replay.rounds.size() > 0 and not replay.active:
		replay.play_round(replay.rounds.size() - 1)
	_v_down = Input.is_key_pressed(KEY_V)
	if Input.is_key_pressed(KEY_F3) and not _f3_down:
		debug_ai = not debug_ai
	_f3_down = Input.is_key_pressed(KEY_F3)
	_debug_view.visible = debug_ai
	if debug_ai:
		_debug_view.queue_redraw()
		hud.set_debug_text(_ai_debug_text())
	else:
		hud.set_debug_text("")

	match phase:
		Phase.BUY:
			hud.set_timer("BUY  %s" % _fmt_time(phase_timer), Color(0.6, 1.0, 0.6))
		Phase.LIVE, Phase.POST_ROUND:
			if bomb_state == Bomb.PLANTED:
				hud.set_timer("BOMB  %s" % _fmt_time(bomb_timer), Color(1.0, 0.35, 0.3))
			else:
				hud.set_timer(_fmt_time(round_time_left))
		_:
			hud.set_timer("")
	var alive := alive_counts()
	hud.set_alive(alive[T], alive[CT])
	hud.set_vitals(user_unit, money_of(user_player) if user_player != null else 0)
	hud.set_blind(user_unit.flash_t if user_unit != null and user_unit.alive and not _watching_others() else 0.0)
	var in_smoke := 0.0
	var smoke_at := Vector2.ZERO
	if user_unit != null and user_unit.alive and not _watching_others() and utility != null and not utility.smokes.is_empty():
		in_smoke = utility.smoke_depth(user_unit.global_position)
		smoke_at = user_unit.get_global_transform_with_canvas().origin
	hud.set_smoke(in_smoke, smoke_at)
	hud.show_buy_menu(buy_menu_open and phase == Phase.BUY, user_unit, money_of(user_player) if user_player != null else 0, self)
	_update_action_hint()
	hud.show_scoreboard(Input.is_action_pressed("scoreboard") and phase != Phase.MATCH_OVER, teams, sides, _scoreboard_rows())

	_update_camera()
	_update_cursor()


## During play the system cursor is hidden and the custom crosshair (Settings)
## is drawn instead. The cursor comes back for the buy menu and match end.
func _update_cursor() -> void:
	var need_cursor := (buy_menu_open and phase == Phase.BUY) or phase == Phase.MATCH_OVER or is_spectating()
	var mode := Input.MOUSE_MODE_VISIBLE if need_cursor else Input.MOUSE_MODE_HIDDEN
	if Input.mouse_mode != mode:
		Input.mouse_mode = mode
		# Belt and braces: some setups (e.g. the editor's embedded game view)
		# ignore MOUSE_MODE_HIDDEN, so also swap in a fully transparent cursor.
		Input.set_custom_mouse_cursor(null if need_cursor else _blank_cursor())
	# Our own crosshair replaces the cursor while you're alive and playing.
	crosshair.unit = user_unit
	crosshair.visible = not need_cursor and user_unit != null and user_unit.alive


var _blank_cursor_tex: ImageTexture
var _v_down := false
var debug_ai := false ## F3: AI debug overlay (beliefs, stress, calls).
var _f3_down := false
var _debug_view: Node2D
var _buy_closed_frame := -10


func _blank_cursor() -> ImageTexture:
	if _blank_cursor_tex == null:
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		_blank_cursor_tex = ImageTexture.create_from_image(img)
	return _blank_cursor_tex


func _exit_tree() -> void:
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.set_custom_mouse_cursor(null)


## Camera leads toward the cursor so you can see where you're aiming.
## Hold right mouse for free look (pushes the view much further out),
## mouse wheel zooms. Spectating follows the teammate without the lead.
const CAMERA_LEAD := 0.0 ## Fraction of the cursor's offset from screen centre (0: you stay centred; hold right mouse to look ahead).
const FREE_LOOK_LEAD := 1.25
const ZOOM_MIN := 0.45 ## Wheel out: see much more of the map.
const ZOOM_MAX := 1.2
var _zoom := 0.75


func _update_camera() -> void:
	camera.zoom = camera.zoom.lerp(Vector2(_zoom, _zoom), 0.15)
	if _freecam and _watching_others():
		camera.position = _freecam_pos
		return
	var followed := _camera_target()
	if followed == null:
		return
	var look_ahead := Vector2.ZERO
	if followed == user_unit and user_unit != null and user_unit.alive and not is_spectating():
		var vp := get_viewport().get_visible_rect().size
		var lead := FREE_LOOK_LEAD if Input.is_action_pressed("free_look") else CAMERA_LEAD
		# Screen-space offset converted to world space at the current zoom.
		look_ahead = (get_viewport().get_mouse_position() - vp / 2.0) * lead / camera.zoom.x
		# Keep yourself on screen with an 80px margin.
		var max_off := (vp / 2.0 - Vector2(80, 80)) / camera.zoom.x
		look_ahead = look_ahead.clamp(-max_off, max_off)
	camera.position = followed.position + look_ahead


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = clampf(_zoom + 0.08, ZOOM_MIN, ZOOM_MAX)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = clampf(_zoom - 0.08, ZOOM_MIN, ZOOM_MAX)


func _update_action_hint() -> void:
	var u := user_unit
	if u != null and u.alive and phase == Phase.BUY and u.side == T and not u.has_bomb and bomb_state == Bomb.CARRIED \
			and bomb_carrier != null and not bomb_carrier.data.is_user:
		hud.set_action("Y: ask %s to drop you the bomb" % bomb_carrier.data.player_name, 0.0)
		return
	if u == null or not u.alive or not can_fight():
		hud.set_action("", 0.0)
		return
	if not is_live():
		var pg := _gun_near(u)
		hud.set_action(("F: pick up %s" % (dropped_guns[pg].w as WeaponData).weapon_name) if pg >= 0 else "", 0.0)
		return
	if u.action == Unit.Action.PLANT:
		hud.set_action("PLANTING...", u.action_progress())
	elif u.action == Unit.Action.DEFUSE:
		hud.set_action("DEFUSING%s..." % (" (kit)" if u.has_kit else ""), u.action_progress())
	elif u.has_bomb and arena.site_at(u.global_position) != "":
		hud.set_action("Hold E to plant", 0.0)
	elif can_defuse(u):
		hud.set_action("Hold E to defuse", 0.0)
	else:
		var g := _gun_near(u)
		if g >= 0:
			var gw: WeaponData = dropped_guns[g].w
			var replaced: WeaponData = u.pistol if gw.is_pistol() else u.primary
			hud.set_action("F: pick up %s%s" % [gw.weapon_name,
				("  (drops your %s)" % replaced.weapon_name) if replaced != null else ""], 0.0)
		else:
			hud.set_action("", 0.0)


func _scoreboard_rows() -> Array:
	var rows := [[], []]
	var rounds := maxi(1, rounds_played())
	for t in 2:
		for p: PlayerData in starters[t]:
			var s: Dictionary = stats[p]
			rows[t].append({
				"name": p.player_name, "title": p.title, "rating": p.rating(), "kills": s.kills, "deaths": s.deaths,
				"adr": int(s.damage / rounds), "money": money_of(p), "is_user": p.is_user,
			})
	return rows


func _fmt_time(seconds: float) -> String:
	var s := maxi(0, ceili(seconds))
	return "%d:%02d" % [s / 60, s % 60]


## While you play, your bot teammates show what they're doing (like spectating).
func shows_intent(u: Unit) -> bool:
	return user_unit != null and u != user_unit and u.side == user_unit.side and phase != Phase.MATCH_OVER


## Health bars: spectators see everyone; a player only sees their own team.
func shows_health(u: Unit) -> bool:
	if is_spectating() or user_unit == null:
		return true
	return u.team_index == user_unit.team_index


func is_spectating() -> bool:
	return mode == "spectate" or mode == "manager" or mode == "bench" or mode == "watch"


func _camera_target() -> Unit:
	if not _watching_others():
		return user_unit
	if _spec_unit != null and is_instance_valid(_spec_unit) and units.has(_spec_unit):
		return _spec_unit
	if is_spectating():
		return units[0] if not units.is_empty() else null
	var my_side := user_unit.side if user_unit != null else T
	for u in units:
		if u.alive and u.side == my_side:
			return u
	for u in units:
		if u.alive:
			return u
	return user_unit


# =============================================================================
# AI debug overlay (F3)
# =============================================================================

const BELIEF_COLORS := {"seen": Color(1.0, 0.3, 0.25), "ghost": Color(1.0, 0.6, 0.2), "heard": Color(1.0, 0.95, 0.3),
	"call": Color(0.5, 0.8, 1.0)}


## Which sides' beliefs to show: both when spectating, else your own.
func _debug_sides() -> Array:
	if is_spectating() or user_unit == null or Game.autoplay:
		return [T, CT]
	return [user_unit.side]


func _draw_ai_debug() -> void:
	var font := ThemeDB.fallback_font
	for side: int in _debug_sides():
		for b: Dictionary in tactics.beliefs(side):
			var col: Color = BELIEF_COLORS.get(b.kind, Color.WHITE)
			var a: float = clampf(float(b.conf), 0.15, 1.0)
			var p: Vector2 = b.pos
			var r: float = maxf(10.0, float(b.unc))
			_debug_view.draw_arc(p, r, 0, TAU, 28, Color(col, 0.85 * a), 2.0)
			_debug_view.draw_circle(p, 4.0, Color(col, a))
			if b.cleared:
				_debug_view.draw_line(p + Vector2(-7, -7), p + Vector2(7, 7), Color(1, 1, 1, 0.7), 2.0)
				_debug_view.draw_line(p + Vector2(-7, 7), p + Vector2(7, -7), Color(1, 1, 1, 0.7), 2.0)
			var tag := "%s %s %.1fs" % [SIDE_NAMES[side], b.kind, b.age]
			_debug_view.draw_string(font, p + Vector2(-60, -r - 4), tag, HORIZONTAL_ALIGNMENT_CENTER, 120, 10, Color(col, 0.9))
	for u in units:
		if not u.alive:
			continue
		var bc: BotController = null
		for c in u.get_children():
			if c is BotController:
				bc = c
		if bc == null or not _debug_sides().has(u.side):
			continue
		var p := u.global_position
		# Stress bar under the unit.
		var bar := Rect2(p + Vector2(-18, Unit.RADIUS + 16), Vector2(36, 4))
		_debug_view.draw_rect(bar, Color(0, 0, 0, 0.7))
		_debug_view.draw_rect(Rect2(bar.position, Vector2(36.0 * bc.stress, 4)), Color(1.0, 0.35, 0.2).lerp(Color(1, 0, 0), bc.stress))
		# What it believes (its own contact memory) and what it's doing.
		if bc._mem_pos != Vector2.INF and bc._mem_conf > 0.2 and bc._mem_age() < BotController.MEMORY_TTL:
			_debug_view.draw_line(p, bc._mem_pos, Color(1, 1, 1, 0.25 * bc._mem_conf), 1.0)
			_debug_view.draw_circle(bc._mem_pos, 3.0, Color(1, 1, 1, 0.6))
		var partner = tactics.trade_partner.get(u, null)
		var line := "stress %.2f  %s" % [bc.stress, bc.plan if bc.plan != "" else "-"]
		if partner != null and is_instance_valid(partner):
			line += "  trade: %s" % partner.data.player_name
		if bc.bomb_blind:
			line += "  (lost bomb timer)"
		_debug_view.draw_string(font, p + Vector2(-110, Unit.RADIUS + 32), line, HORIZONTAL_ALIGNMENT_CENTER, 220, 10, Color(1, 1, 1, 0.9))


func _ai_debug_text() -> String:
	var lines := ["AI DEBUG (F3)   markers: red seen  orange ghost  yellow heard  blue callout  X cleared"]
	for side: int in [T, CT]:
		lines.append("%s call: %s" % [SIDE_NAMES[side], tactics.igl_call_text(side)])
	var bs := BotController.stats
	var trades := "%d/%d" % [Tactics.traded_count, Tactics.deaths_count]
	lines.append("trades %s   fakes bitten %d/%d   aim belief/true %d/%d   flash-peeks %d  dry %d  refrags %d" % [
		trades, Tactics.fake_bitten, Tactics.fake_rounds, int(bs.aim_belief), int(bs.aim_true), int(bs.flash_waits),
		int(bs.dry_peeks), int(bs.refrags)])
	return "
".join(lines)


# =============================================================================
# Chat: light, low-frequency all-chat from bots
# =============================================================================

var _chat_t := -100.0 ## Real time of the last chat line.
var _chat_count := 0 ## Lines this round.


## A bot says something in all-chat (rate-limited; never the human).
func chat(u: Unit, text: String, force: bool = false) -> void:
	if u == null or not is_instance_valid(u) or (u.data.is_user and not Game.autoplay) or hud == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if not force and (now - _chat_t < 1.6 or _chat_count >= 6):
		return
	_chat_t = now
	_chat_count += 1
	hud.add_chat(u.data.player_name, Unit.SIDE_COLORS[u.side], text)


func _pers_of(u: Unit) -> BotPersonality:
	return tactics.pers(u)


# --- Rivals and friends ------------------------------------------------------
# In a My Player career the World knows who you get on with: rivals (and a
# rival team) talk a lot more trash at you, friends on the other side are
# friendlier. Quick matches fall back to each bot's own trash-talk habit.

## -1 (bitter rival) .. 1 (good friend) toward the player; 0 when unknown.
func _rel(u: Unit) -> float:
	if u == null or user_unit == null or u.data.is_user or Game.pworld == null or not mode in ["career", "bench"]:
		return 0.0
	if Game.pworld.has_method("relation_strength"):
		return clampf(float(Game.pworld.relation_strength(u.data)), -1.0, 1.0)
	if Game.pworld.has_method("relation_to_user"):
		var r: String = Game.pworld.relation_to_user(u.data)
		return -0.7 if r == "rival" else (0.7 if r == "friend" else 0.0)
	return 0.0


## The other team is one the player's club has a rivalry with.
func _rival_match() -> bool:
	if user_unit == null or Game.pworld == null or not mode in ["career", "bench"] or not Game.pworld.has_method("team_rivalry"):
		return false
	return bool(Game.pworld.team_rivalry(teams[1 - user_unit.team_index]))


func _you() -> String:
	return user_unit.data.player_name if user_unit != null else "you"


func _say_line(u: Unit, lines: Array, force: bool = false) -> void:
	var t: String = lines[rng.randi() % lines.size()]
	t = t.replace("{you}", _you()).replace("{name}", u.data.player_name)
	if user_unit != null:
		t = t.replace("{us}", teams[u.team_index].team_name)
		t = t.replace("{them}", teams[1 - u.team_index].team_name)
	if rng.randf() < 0.45:
		t = t.to_lower()
	chat(u, t, force)


const TAUNT_KILL_YOU := ["sit down {you}", "ez {you}", "{you} thought he had me", "where u going {you}", "1 tap {you}",
	"again? lol", "{you} free elo", "is that all {you}?", "back to the bench {you}", "u peeked that?", "too slow {you}",
	"you're mine all game {you}", "dont come back to that angle", "cya {you}", "and you talked so much this week"]
const SALTY_DIED_TO_YOU := ["lucky", "lucky spray", "ok one round", "enjoy it while it lasts", "u got that one", "bot aim",
	"wallbang? really", "i'll remember that {you}", "fine. FINE.", "that's 1", "running and gunning lmao", "nice ping"]
const FRIEND_DIED_TO_YOU := ["ok that was clean {you}", "nice one man", "haha fair", "you got me", "ns {you}",
	"i'm telling everyone u got lucky", "nice shot bro", "dammit {you}"]
const FRIEND_KILL_YOU := ["sorry {you} :)", "my bad bro", "nothing personal", "gotcha {you}", "hehe", "we'll talk after",
	"had to do it", "that one's for last time"]
const NEUTRAL_DIED := ["ns", "nice shot", "wow", "how", "nice one", "rip", "ok", "?"]
const TEAM_TAUNTS := ["{them} folding again", "too easy", "is this {them}?", "where's the hype now", "next",
	"so much for {them}", "they're tilted", "keep crying {them}"]


func _kill_chat(killer: Unit, victim: Unit) -> void:
	var kr := _rel(killer)
	var vr := _rel(victim)
	var rivalry := _rival_match()
	var heat := 1.0 + (0.8 if rivalry else 0.0)
	if victim == user_unit:
		if kr < -0.3 and rng.randf() < (0.55 + 0.35 * -kr):
			_say_line(killer, TAUNT_KILL_YOU, true)
		elif kr > 0.3 and rng.randf() < 0.45:
			_say_line(killer, FRIEND_KILL_YOU)
		elif rng.randf() < 0.08 * heat + _pers_of(killer).trash_talk * 0.15 * heat:
			_say_line(killer, TAUNT_KILL_YOU)
		return
	if killer == user_unit:
		if vr < -0.3 and rng.randf() < 0.5 + 0.3 * -vr:
			_say_line(victim, SALTY_DIED_TO_YOU, true)
		elif vr > 0.3 and rng.randf() < 0.5:
			_say_line(victim, FRIEND_DIED_TO_YOU)
		elif rng.randf() < 0.12 * heat:
			_say_line(victim, NEUTRAL_DIED + (SALTY_DIED_TO_YOU if rivalry else []))
		return
	if rng.randf() < 0.05 * heat:
		_say_line(victim, NEUTRAL_DIED)
	elif rivalry and killer.side != user_unit.side and rng.randf() < 0.08:
		_say_line(killer, TEAM_TAUNTS)


const PRE_RIVAL := ["{you} hope you warmed up", "watch your back {you}", "{you} this round is yours? lol", "found you {you}",
	"i'm coming for you {you}", "{you} you said what about us?", "let's see that talk now {you}"]
const PRE_FRIEND := ["gl {you}, go easy on me", "{you} no knife pls", "after the game we're even {you}", "don't embarrass me {you}",
	"hi {you} :)", "{you} first one to die buys dinner"]
const PRE_TEAM := ["{them} is going down", "this is our map", "{them} can't stop crying in the press", "ready to send {them} home",
	"heard {them} is scared", "no mercy today"]


## Buy phase banter: rivals call you out, friends say hi, a rival team gets lippy.
func _pre_round_chat() -> void:
	if user_unit == null or Game.autoplay:
		return
	var foes: Array = units.filter(func(u: Unit) -> bool: return u.side != user_unit.side and not u.data.is_user)
	if foes.is_empty():
		return
	foes.sort_custom(func(a: Unit, b: Unit) -> bool: return _rel(a) < _rel(b))
	var worst: Unit = foes[0]
	var best: Unit = foes[-1]
	if _rel(worst) < -0.3 and rng.randf() < 0.35 + 0.3 * -_rel(worst):
		_say_line(worst, PRE_RIVAL)
	elif _rel(best) > 0.3 and rng.randf() < (0.5 if round_num == 1 else 0.15):
		_say_line(best, PRE_FRIEND)
	elif _rival_match() and rng.randf() < 0.3:
		_say_line(foes[rng.randi() % foes.size()], PRE_TEAM)
	elif _pers_of(worst).trash_talk > 0.7 and rng.randf() < 0.12:
		_say_line(worst, ["let's go", "free round", "eco? lol", "warm up's over", "here we go"])


## Round over: "nt" from the losers now and then; aces / clutches get a
## "wp" or, from trash talkers, a taunt.
func _round_chat(winner_side: int) -> void:
	var moments: Array = replay.cur.get("moments", []) if replay != null else []
	for mo: Dictionary in moments:
		var hero: Unit = null
		for u in units:
			if u.data == mo.pd:
				hero = u
		if hero == null:
			continue
		var big := (mo.kinds as Array).has("ACE") or String(" ".join(mo.kinds)).contains("CLUTCH")
		if big and _pers_of(hero).trash_talk > 0.6 and rng.randf() < 0.8:
			chat(hero, ["ez", "too easy", "sit down", "1 tap machine", "where were you going?", "next"][rng.randi() % 6], true)
			return
		if big and rng.randf() < 0.5:
			var mate: Unit = null
			for u in units:
				if u != hero and u.side == hero.side and not u.data.is_user:
					mate = u
			chat(mate if mate != null else hero, ["wp", "nice clutch", "insane", "ty carry", "what a round"][rng.randi() % 5])
			return
	if user_unit != null and not Game.autoplay:
		var foes: Array = units.filter(func(u: Unit) -> bool: return u.side != user_unit.side and not u.data.is_user)
		foes.sort_custom(func(a: Unit, b: Unit) -> bool: return _rel(a) < _rel(b))
		if not foes.is_empty():
			var they_won := winner_side != user_unit.side
			var worst: Unit = foes[0]
			if _rel(worst) < -0.3 and rng.randf() < 0.45:
				_say_line(worst, (["ez", "{you} carried us lol", "too easy", "sit {you}", "keep feeding {you}", "lmao"] if they_won
					else ["lucky round", "won't happen again", "enjoy it", "1 round lol", "ok {you} calm down"]))
				return
			if _rival_match() and they_won and rng.randf() < 0.3:
				_say_line(foes[rng.randi() % foes.size()], TEAM_TAUNTS)
				return
	if rng.randf() < 0.35:
		var losers: Array = units.filter(func(u: Unit) -> bool: return u.side != winner_side and not u.data.is_user)
		if not losers.is_empty():
			var l: Unit = losers[rng.randi() % losers.size()]
			_say_line(l, ["nt", "unlucky", "close", "nt nt", "next one", "we got this", "reset", "focus guys", "eco next?",
				"that was so close", "they had nothing", "how did we lose that"])


func _gg_chat() -> void:
	var n := 2 + rng.randi() % 3
	var pool: Array = units.filter(func(u: Unit) -> bool: return not u.data.is_user)
	pool.shuffle()
	var said := 0
	for u: Unit in pool:
		if said >= n + 2:
			break
		var r := _rel(u)
		if r < -0.3 and u.side != (user_unit.side if user_unit != null else -1):
			_say_line(u, ["gg ez", "gg {you} see you next time", "no gg", "gg, keep talking {you}", "gg go next", "?"], true)
			said += 1
		elif r > 0.3:
			_say_line(u, ["gg {you} well played", "gg man, rematch soon", "ggs {you}, drinks on me", "gg wp {you}"], true)
			said += 1
		elif said < n:
			chat(u, ["gg", "gg wp", "ggs", "gg wp all", "gg close one"][rng.randi() % 5], true)
			said += 1
