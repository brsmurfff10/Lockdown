extends Node
## Global state: settings, My Player, the two careers (both live in a World),
## and match hand-off.

var MY_PLAYER_PATH := "user://my_player.json"
var PLAYER_CAREER_PATH := "user://player_career.json"
var MANAGER_PATH := "user://manager.json"
var ACHIEVEMENTS_PATH := "user://achievements.json"

## Achievements: unlocked once, kept across every save.
const ACHIEVEMENTS := {
	"first_win": {"name": "Off the Mark", "desc": "Win a career match."},
	"ot_win": {"name": "Overtime Hero", "desc": "Win a career match in overtime."},
	"streak10": {"name": "Unstoppable", "desc": "Win 10 career matches in a row."},
	"promoted": {"name": "Moving Up", "desc": "Win promotion."},
	"top_flight": {"name": "Top Flight", "desc": "Reach the Premier League."},
	"silverware": {"name": "Silverware", "desc": "Win a cup or league playoffs."},
	"major": {"name": "Major Champion", "desc": "Win a Major."},
	"hardcore": {"name": "Hardcore Hero", "desc": "Win a trophy on Hardcore."},
	"millionaire": {"name": "Millionaire", "desc": "Have $1M in the bank (club or wallet)."},
	"homegrown": {"name": "Homegrown", "desc": "Promote an academy prospect."},
	"dream_team": {"name": "Dream Team", "desc": "Have four staff of 4+ stars."},
	"campus": {"name": "Campus", "desc": "Every facility at level 3 or higher."},
	"fine_print": {"name": "Read the Fine Print", "desc": "Lose a player to a release clause."},
	"sacked": {"name": "Shown the Door", "desc": "Get sacked."},
	"upward": {"name": "Upwardly Mobile", "desc": "Move to a bigger club as manager."},
	"mvp": {"name": "Most Valuable", "desc": "Win a league MVP award (My Player)."},
	"poy": {"name": "Best in the World", "desc": "Win Player of the Year (My Player)."},
	"allstar": {"name": "All-Star", "desc": "Get picked for the All-Star Showcase."},
	"world_champ": {"name": "World Champion", "desc": "Win the World Cup."},
	"free_agent": {"name": "Free Agent", "desc": "Join a new club on a free transfer."},
	"nemesis": {"name": "Nemesis", "desc": "Face the same rival 10 times."},
	"highlight_reel": {"name": "Highlight Reel", "desc": "Rack up 10 highlight moments."},
	"hof": {"name": "Hall of Famer", "desc": "Retire with a Hall of Famer legacy."},
	"coach": {"name": "From Player to Coach", "desc": "Coach your last club after retiring."},
	"derby": {"name": "Derby Day", "desc": "Beat your local rivals as manager."},
	"affiliate": {"name": "Second String", "desc": "Buy an affiliate club for a second roster."},
}
var achievements: Dictionary = {} ## id -> "unlocked on" text

const MENU_SCENE := "res://scenes/main_menu.tscn"
const MY_PLAYER_SCENE := "res://scenes/my_player.tscn"
const CAREER_SCENE := "res://scenes/player_hub.tscn" ## My Player career hub.
const HOME_SCENE := "res://scenes/home.tscn" ## My Player: walking around your place.
const MATCH_SCENE := "res://scenes/match.tscn"
const SETTINGS_SCENE := "res://scenes/settings.tscn"
const EDITOR_SCENE := "res://scenes/editor.tscn"
const MANAGER_SCENE := "res://scenes/manager_hub.tscn"
const MANAGER_SETUP_SCENE := "res://scenes/manager_setup.tscn"
const SETTINGS_PATH := "user://settings.json"

const TEAM_DEFS := [
	["Ironclad", "IRN", "d94d40"],
	["Voltage", "VLT", "408cf2"],
	["Nightjar", "NJR", "8c59d9"],
	["Granite", "GRN", "8c998c"],
	["Sunforge", "SUN", "f2b333"],
	["Tidebreak", "TDB", "33bfb3"],
	["Wildfire", "WLD", "f27326"],
	["Frostbite", "FRB", "a6d9f2"],
]
const ROSTER_SIZE := 7

var rng := RandomNumberGenerator.new()
var settings: Dictionary = {} ## Player preferences (crosshair, display). Saved separately from careers.

# --- Careers ---
var world: World = null ## Career Mode (manager).
var pworld: World = null ## My Player career.

# --- My Player profile ---
var my_player: PlayerData = null
var my_player_base: Dictionary = {} ## Stats at creation; new careers reset to this.

# --- Match hand-off ---
var home_tour := "" ## Home scene: viewing this property before buying ("" = your own home).
var hub_page := "" ## Career hub opens on this page next time ("" = where it was).
var pending_match: Dictionary = {} ## {mode, teams: [TeamData, TeamData], map}

# --- Dev testing: `-- --test` uses separate saves; autoplay bot-controls the user. ---
var autoplay: bool = false

var ui_sounds: UiSounds ## Hover / click / confirm sounds for every control.


func _ready() -> void:
	rng.randomize()
	InputSetup.ensure()
	settings = _read_json(SETTINGS_PATH)
	if "--test" in OS.get_cmdline_user_args():
		MY_PLAYER_PATH = "user://test_my_player.json"
		PLAYER_CAREER_PATH = "user://test_player_career.json"
		MANAGER_PATH = "user://test_manager.json"
		ACHIEVEMENTS_PATH = "user://test_achievements.json"
	achievements = _read_json(ACHIEVEMENTS_PATH)
	load_my_player()
	load_player_career()
	load_world()
	apply_display_settings()
	_ensure_audio_buses()
	apply_audio_settings()
	ui_sounds = UiSounds.new()
	add_child(ui_sounds)


func goto(scene: String) -> void:
	_flush_saves() # Never leave a screen with an unsaved career.
	get_tree().change_scene_to_file.call_deferred(scene)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_CRASH:
		_flush_saves()


# =============================================================================
# Saving: batched writes, crash-safe files, weekly backups
# =============================================================================

const BACKUPS := 3
var _save_pending := {} ## "world" / "player" -> true
var _backup_stamp := {} ## save path -> week stamp of the last backup taken


## Hubs call these after every action: the write happens once, a second later
## (and immediately on leaving the screen or quitting).
func save_world_soon() -> void:
	_defer_save("world")


func save_player_career_soon() -> void:
	_defer_save("player")


func _defer_save(kind: String) -> void:
	if _save_pending.has(kind):
		return
	_save_pending[kind] = true
	get_tree().create_timer(1.0).timeout.connect(_flush_saves)


func _flush_saves() -> void:
	var p := _save_pending.duplicate()
	_save_pending.clear()
	if p.has("world"):
		save_world()
	if p.has("player"):
		save_player_career()


## Before the first save of each new week (and each session), keep a copy:
## .bak1 is the newest, up to BACKUPS.
func _backup(path: String, stamp: int) -> void:
	if int(_backup_stamp.get(path, -1)) == stamp:
		return
	_backup_stamp[path] = stamp
	if not FileAccess.file_exists(path):
		return
	var ap := ProjectSettings.globalize_path(path)
	for i in range(BACKUPS - 1, 0, -1):
		if FileAccess.file_exists("%s.bak%d" % [path, i]):
			DirAccess.copy_absolute("%s.bak%d" % [ap, i], "%s.bak%d" % [ap, i + 1])
	DirAccess.copy_absolute(ap, ap + ".bak1")


## kind: "world" (manager) or "player". Newest first: {index, path, season, week, team, modified}.
func list_backups(kind: String) -> Array:
	var path := MANAGER_PATH if kind == "world" else PLAYER_CAREER_PATH
	var out: Array = []
	for i in range(1, BACKUPS + 1):
		var bp := "%s.bak%d" % [path, i]
		if not FileAccess.file_exists(bp):
			continue
		var d := _read_json(bp)
		var team := ""
		var ti := int(d.get("user_team_idx", -1))
		var tl: Array = d.get("teams", [])
		if ti >= 0 and ti < tl.size():
			team = String(tl[ti].get("name", ""))
		out.append({"index": i, "path": bp, "season": int(d.get("season", 0)), "week": int(d.get("week", 0)), "team": team,
			"modified": Time.get_datetime_string_from_unix_time(FileAccess.get_modified_time(bp), true)})
	return out


func restore_backup(kind: String, index: int) -> bool:
	var path := MANAGER_PATH if kind == "world" else PLAYER_CAREER_PATH
	var bp := "%s.bak%d" % [path, index]
	if not FileAccess.file_exists(bp):
		return false
	_save_pending.erase(kind)
	DirAccess.copy_absolute(ProjectSettings.globalize_path(bp), ProjectSettings.globalize_path(path))
	if kind == "world":
		load_world()
	else:
		load_my_player()
		load_player_career()
	return true


## The engine's log for this session (errors and warnings included).
func read_log() -> String:
	var p := "user://logs/godot.log"
	if not FileAccess.file_exists(p):
		return ""
	return FileAccess.get_file_as_string(p)


# =============================================================================
# Display / settings
# =============================================================================

## Fullscreen by default; F11 toggles; the choice is remembered in settings.
func apply_display_settings() -> void:
	if DisplayServer.get_name() == "headless":
		return
	# `-- --windowed` (dev tests) forces a window so test runs don't take over the screen.
	var full := bool(settings.get("fullscreen", true)) and not "--windowed" in OS.get_cmdline_user_args()
	# Exclusive fullscreen gets the real screen size (borderless fullscreen on
	# Windows is 2px short), so the UI scales by an exact factor and stays sharp.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN if full else DisplayServer.WINDOW_MODE_WINDOWED)


func set_fullscreen(on: bool) -> void:
	settings["fullscreen"] = on
	save_settings()
	apply_display_settings()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		set_fullscreen(not bool(settings.get("fullscreen", true)))


## Master -> SFX, Master -> Weapons, Master -> UI. Volumes come from settings (0-100%).
func _ensure_audio_buses() -> void:
	for bus in ["SFX", "Weapons", "UI"]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")


func volume(key: String) -> float:
	return float(settings.get("volume_" + key, 80.0 if key != "master" else 70.0))


func apply_audio_settings() -> void:
	for pair in [["master", "Master"], ["sfx", "SFX"], ["weapons", "Weapons"], ["ui", "UI"]]:
		var i := AudioServer.get_bus_index(pair[1])
		if i >= 0:
			var v := volume(pair[0]) / 100.0
			AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
			AudioServer.set_bus_mute(i, v <= 0.001)


func set_volume(key: String, value: float) -> void:
	settings["volume_" + key] = value
	apply_audio_settings()
	save_settings()


func save_settings() -> void:
	_write_json(SETTINGS_PATH, settings)


## Dev A/B switches passed on the command line as `-- --ab=name1,name2`.
func ab_flag(name: String) -> bool:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ab=") and name in a.substr(5).split(","):
			return true
	return false


# =============================================================================
# Career Mode (manager)
# =============================================================================

## Step 1: generate a fresh world. Step 2 (setup screen): take_over a team.
func new_manager_world(pack: String = "") -> World:
	var w := World.new()
	w.new_world("manager", pack)
	return w


func start_manager_career(w: World, team_idx: int, org_name: String, tag: String, color: Color) -> void:
	w.take_over(team_idx, org_name, tag, color)
	world = w
	save_world()


func save_world() -> void:
	_save_pending.erase("world")
	if world != null:
		_backup(MANAGER_PATH, world.stamp())
		_write_json(MANAGER_PATH, world.to_dict(), false)


func load_world() -> void:
	var d := _read_json(MANAGER_PATH)
	world = World.from_dict(d) if not d.is_empty() and d.get("mode", "manager") == "manager" and d.has("schedules") else null


## Your next match this week, as a watchable bot match.
func prepare_manager_match() -> bool:
	if world == null:
		return false
	var mt := world.user_match_this_week()
	if mt.is_empty() or not world.can_field_team():
		return false
	var ui := world.team_index(world.user_team())
	var opp_idx: int = mt.b if mt.a == ui else mt.a
	pending_match = {"mode": "manager", "teams": [world.user_team(), world.teams[opp_idx]], "map": mt.get("map", "")}
	BotController.mistake_mult = world.diff("bots")
	world.prepare_match_day()
	return true


## result: {score: [user, opp], rounds, players: {PlayerData: stats}}
func finish_manager_match(result: Dictionary) -> void:
	pending_match = {}
	if world == null:
		return
	world.record_user_match(result.score, result.rounds, result.players)
	save_world()


# =============================================================================
# My Player profile
# =============================================================================

## True if newly unlocked (and saved).
func unlock_achievement(id: String) -> bool:
	if achievements.has(id) or not ACHIEVEMENTS.has(id):
		return false
	achievements[id] = Time.get_date_string_from_system()
	_write_json(ACHIEVEMENTS_PATH, achievements)
	return true


func create_my_player(p_name: String, p_role: String, p_nation: String = "") -> PlayerData:
	var p := PlayerData.new()
	p.player_name = p_name
	p.role = p_role
	p.nation = p_nation if p_nation != "" else PlayerData.NATIONS[rng.randi() % PlayerData.NATIONS.size()]
	p.age = 18
	p.is_user = true
	var bias: Dictionary = PlayerData.ROLE_BIAS[p_role]
	for k: String in PlayerData.STAT_KEYS:
		p.set_stat(k, 48.0 + float(bias.get(k, 0)))
	p.potential = 92
	my_player = p
	my_player_base = p.stats.duplicate()
	save_my_player()
	return p


func delete_my_player() -> void:
	my_player = null
	my_player_base = {}
	DirAccess.remove_absolute(ProjectSettings.globalize_path(MY_PLAYER_PATH))
	end_career()


func save_my_player() -> void:
	if my_player == null:
		return
	_write_json(MY_PLAYER_PATH, {"player": my_player.to_dict(), "base": my_player_base})


func load_my_player() -> void:
	var d := _read_json(MY_PLAYER_PATH)
	if d.is_empty():
		return
	my_player = PlayerData.from_dict(d.get("player", {}))
	my_player.is_user = true
	my_player_base = d.get("base", my_player.stats.duplicate())


# =============================================================================
# My Player career (you play; same 64-team world, AI runs your club)
# =============================================================================

var career_active: bool:
	get:
		return pworld != null


func start_career(difficulty: String = "Normal", pack: String = "") -> void:
	assert(my_player != null)
	# Fresh rookie: reset to creation stats.
	for k: String in PlayerData.STAT_KEYS:
		my_player.set_stat(k, float(my_player_base.get(k, 48.0)))
	my_player.age = 18
	my_player.matches_played = 0
	my_player.career_kills = 0
	my_player.career_deaths = 0
	my_player.titles = 0
	my_player.recent_ratings.clear()
	my_player.match_log.clear()
	my_player.season_stats = {}
	my_player.form = 0.0
	my_player.morale = 70.0
	my_player.out_weeks = 0
	my_player.ailment = ""
	my_player.bench_weeks = 0
	my_player.promise_until = 0
	pworld = World.new()
	pworld.difficulty = difficulty
	pworld.new_world("player", pack)
	pworld.used_names[my_player.player_name] = true
	pworld.place_user_player(my_player)
	save_player_career()


## After retiring: take over your last club as its manager (replaces any
## manager career). The retired player leaves the roster.
func coach_from_player() -> void:
	if pworld == null or not pworld.retired:
		return
	var w := World.from_dict(pworld.to_dict())
	var me := w.user_player
	var t := w.user_team()
	t.roster.erase(me)
	w._refill_roster(t)
	w.mode = "manager"
	w.user_player = null
	w.offers.clear()
	w.inbox.clear()
	w.take_over(w.team_index(t), t.team_name, t.short_name, t.color)
	w._news("%s retires as a player and takes charge of %s." % [me.player_name, t.team_name])
	world = w
	save_world()
	unlock_achievement("coach")


func end_career() -> void:
	pworld = null
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PLAYER_CAREER_PATH))


func save_player_career() -> void:
	_save_pending.erase("player")
	if pworld != null:
		_backup(PLAYER_CAREER_PATH, pworld.stamp())
		_write_json(PLAYER_CAREER_PATH, pworld.to_dict(), false)
	save_my_player()


func load_player_career() -> void:
	var d := _read_json(PLAYER_CAREER_PATH)
	if d.is_empty() or my_player == null or d.get("mode", "") != "player":
		pworld = null
		return
	pworld = World.from_dict(d)
	if pworld.user_player == null:
		pworld = null
		return
	my_player = pworld.user_player # One object for both views.


func train(key: String, intensity: String = "Normal") -> float:
	if pworld == null:
		return 0.0
	var d := pworld.train_user(key, intensity)
	save_player_career()
	return d


## Your next match this week, played by you.
func prepare_player_match() -> bool:
	if pworld == null:
		return false
	var mt := pworld.user_match_this_week()
	if mt.is_empty():
		return false
	var ui := pworld.team_index(pworld.user_team())
	var opp_idx: int = mt.b if mt.a == ui else mt.a
	var m: String = _default_map()
	# On the bench (or injured): watch your team from the stands instead.
	var md := "career" if pworld.user_play_block() == "" else "bench"
	pending_match = {"mode": md, "teams": [pworld.user_team(), pworld.teams[opp_idx]], "map": m if m != "" else mt.get("map", "")}
	BotController.mistake_mult = pworld.diff("bots")
	pworld.prepare_match_day()
	return true


## Live viewing: watch an AI match from this week (either career). The result
## is recorded instead of simulated.
var _watch: Dictionary = {} ## {world: World, a, b, back: scene}


func prepare_watch_match(w: World, a: int, b: int, back_scene: String) -> bool:
	var mt := w.find_week_match(a, b)
	if mt.is_empty():
		return false
	_watch = {"world": w, "a": a, "b": b, "back": back_scene}
	w.roll_match_day(w.teams[a])
	w.roll_match_day(w.teams[b])
	var m: String = _default_map()
	pending_match = {"mode": "watch", "teams": [w.teams[a], w.teams[b]], "map": m if m != "" else String(mt.get("map", ""))}
	BotController.mistake_mult = 1.0
	return true


func finish_watch_match(result: Dictionary) -> void:
	pending_match = {}
	if _watch.is_empty():
		return
	var w: World = _watch.world
	w.record_watched_match(int(_watch.a), int(_watch.b), result.score, result.rounds, result.players)
	if w == world:
		save_world()
	elif w == pworld:
		save_player_career()


func watch_back_scene() -> String:
	return String(_watch.get("back", MENU_SCENE))


## All-Star Showcase: an exhibition with copies of the players (doesn't count).
func prepare_allstar() -> bool:
	if pworld == null or not pworld.allstar_pending():
		return false
	var m: String = _default_map()
	pending_match = {"mode": "allstar", "teams": pworld.allstar_teams(), "map": m}
	return true


## My Player showmatch ("pug") or trial match: an exhibition with copies of
## the players that doesn't count for stats. It runs through the match scene's
## exhibition mode, so the result comes back via finish_allstar().
func prepare_showmatch(kind: String = "pug") -> bool:
	if pworld == null or pworld.soc().can_showmatch() != "":
		return false
	if kind == "trial" and pworld.soc().trial_team() == null:
		return false
	var m: String = _default_map()
	pending_match = {"mode": "allstar", "kind": kind, "teams": pworld.soc().showmatch_teams(kind), "map": m}
	BotController.mistake_mult = pworld.diff("bots")
	return true


func finish_allstar(result: Dictionary) -> void:
	var kind := String(pending_match.get("kind", "allstar"))
	pending_match = {}
	if pworld == null:
		return
	var best := -1.0
	var mine := 1.0
	var mvp_me := false
	for p: PlayerData in result.players:
		var s: Dictionary = result.players[p]
		var r := Progression.match_rating(s.kills, s.deaths, result.rounds, s.objectives, s.damage)
		if p.is_user:
			mine = r
		if r > best:
			best = r
			mvp_me = p.is_user
	if kind == "pug" or kind == "trial":
		pworld.soc().finish_showmatch(result.score, mine, kind)
	else:
		pworld.finish_allstar(result.score, mine, mvp_me)
	save_player_career()


func finish_player_match(result: Dictionary) -> void:
	pending_match = {}
	if pworld == null:
		return
	pworld.record_user_match(result.score, result.rounds, result.players)
	pworld.note_highlights(result.get("highlights", {}))
	save_player_career()


# =============================================================================
# Quick / spectate matches (throwaway teams)
# =============================================================================

## Tests use the small, hand-verified Cage map unless told otherwise.
func _default_map() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map="):
			return a.substr(6)
	return "Cage" if "--test" in OS.get_cmdline_user_args() else ""


func prepare_quick_match(map_name: String = "") -> void:
	var league := _generate_league()
	var a: TeamData = league[0]
	var b: TeamData = league[1 + rng.randi() % (league.size() - 1)]
	var you: PlayerData
	if my_player != null:
		you = PlayerData.from_dict(my_player.to_dict()) # Copy: quick matches don't progress you.
		you.is_user = true
	else:
		you = PlayerData.new()
		you.player_name = "You"
		you.is_user = true
	a.roster.pop_back()
	a.roster.append(you)
	a.sort_roster()
	pending_match = {"mode": "quick", "teams": [a, b], "map": map_name if map_name != "" else _default_map()}
	BotController.mistake_mult = 1.0


## Bot-vs-bot match you can watch (no user player).
func prepare_spectate_match() -> void:
	var league := _generate_league()
	var a: TeamData = league[0]
	var b: TeamData = league[1 + rng.randi() % (league.size() - 1)]
	pending_match = {"mode": "spectate", "teams": [a, b], "map": ""}
	BotController.mistake_mult = 1.0


func _generate_league() -> Array[TeamData]:
	var out: Array[TeamData] = []
	var used := {}
	if my_player != null:
		used[my_player.player_name] = true
	for def in TEAM_DEFS:
		var t := TeamData.new()
		t.team_name = def[0]
		t.short_name = def[1]
		t.color = Color.html(def[2])
		var quality := rng.randf_range(46.0, 70.0)
		var non_awp := ["Entry", "Rifler", "Rifler", "Support", "Lurker"]
		for i in ROSTER_SIZE:
			var role: String = "AWPer" if i == 0 else String(non_awp[rng.randi() % non_awp.size()])
			t.roster.append(PlayerData.generate(rng, quality, used, role))
		t.sort_roster()
		out.append(t)
	return out


# =============================================================================
# Persistence helpers
# =============================================================================

## Crash-safe: write a temp file, then swap it in, so a crash mid-write can't
## leave a half-written save.
func _write_json(path: String, data: Dictionary, pretty: bool = true) -> void:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data, "\t" if pretty else ""))
	f.close()
	var ap := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ap)
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ap)


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var txt := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(txt)
	return parsed if parsed is Dictionary else {}
