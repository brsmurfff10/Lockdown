class_name Sfx
extends Node2D
## Positional sound effects. Sounds live in res://audio/<name>.wav|.ogg|.mp3.
## Missing files are skipped silently (warned once), so code can reference
## sounds before they're recorded.
##
## Sound names in use:
##   pistol_shot, t_pistol_shot, rifle_shot, t_rifle_shot, smg_shot,
##   shotgun_shot, sniper_shot, rifle_reload, lockdown_empty_ammo,
##   lockdown_bullet_impact_body, lockdown_bullet_impact_wall, bullet_flyby,
##   lockdown_footstep, lockdown_bomb_plant_click, bomb_beep, bomb_defuse,
##   bomb_defuse_start, suppressed_shot
##
## Gunshots: every gun has its own file, res://audio/guns/<WeaponData.sound>.wav,
## made from the recordings above. Sfx.shot_sound() returns "guns/<key>|<fallback>";
## play() uses the gun's file and falls back to the old category sound
## (pistol_shot, t_rifle_shot, ...) if that file is missing.

const AUDIO_DIR := "res://audio/"
const EXTENSIONS := ["wav", "ogg", "mp3"]
const POOL_SIZE := 32
const MAX_DISTANCE := 1800.0
const WEAPON_SOUNDS := ["pistol_shot", "t_pistol_shot", "rifle_shot", "t_rifle_shot", "smg_shot", "shotgun_shot", "sniper_shot", "suppressed_shot", "rifle_reload", "lockdown_empty_ammo"]
## Per-gun firing sounds live in res://audio/<GUN_DIR><key>.wav.
const GUN_DIR := "guns/"
## Per-gun shots get at most this much random pitch so each gun stays recognisable.
const GUN_PITCH_JITTER := 0.03
## Objective sounds carry across the map: quieter with distance, never silent.
## sound -> [max_distance px, attenuation exponent]
## Footsteps: you hear them from half as far as other sounds (bots hear them at Tactics.SOUND_RANGE.steps).
const SHORT_RANGE := {"lockdown_footstep": [900.0, 1.6]}
const LONG_RANGE := {"bomb_defuse": [4200.0, 0.7], "bomb_defuse_start": [4200.0, 0.7],
	"lockdown_bomb_plant_click": [4200.0, 0.7], "bomb_beep": [4200.0, 0.8]}
## Sounds dropped entirely at high fast-forward speeds.
const LOW_PRIORITY := ["lockdown_footstep", "lockdown_bullet_impact_wall", "bullet_flyby"]
## Same sound can't start more than this many times within RATE_WINDOW_MS (real time).
const RATE_LIMIT := 3
const RATE_WINDOW_MS := 60

var _cache := {} ## name -> AudioStream or null
var _pool: Array[AudioStreamPlayer2D] = []
var _next := 0
var _listener: AudioListener2D
var play_log: Array[String] = [] ## Dev tests only (--test): every sound requested.
var played_log: Array[String] = [] ## Dev tests only: sounds that got past the limiter.
var _recent := {} ## sound -> Array[int] of recent start times (ms, real time)
var _log_enabled := "--test" in OS.get_cmdline_user_args()


func _ready() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer2D.new()
		p.max_distance = MAX_DISTANCE
		p.attenuation = 1.6
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	_listener = AudioListener2D.new()
	add_child(_listener)
	_listener.make_current()


## Hear the world from this position (the unit you're playing or spectating).
func set_listener(pos: Vector2) -> void:
	_listener.global_position = pos


func play(sound: String, pos: Vector2, volume_db: float = 0.0, pitch_jitter: float = 0.05) -> void:
	if _log_enabled:
		play_log.append(sound)
	var stream := _stream(sound)
	if stream == null:
		return
	# Fast-forward: thin out the noise instead of stacking it.
	var speed := Engine.time_scale
	if speed >= 4.0 and sound in LOW_PRIORITY:
		return
	var now := Time.get_ticks_msec()
	var times: Array = _recent.get(sound, [])
	times = times.filter(func(t: int) -> bool: return now - t < RATE_WINDOW_MS)
	var limit := RATE_LIMIT if speed <= 1.0 else maxi(1, int(RATE_LIMIT / speed * 2.0))
	if times.size() >= limit:
		_recent[sound] = times
		return
	times.append(now)
	_recent[sound] = times
	if speed > 1.0:
		volume_db -= 5.0 * log(speed) / log(2.0)
	if _log_enabled:
		played_log.append(sound)
	# Reuse the oldest player in the pool.
	var p := _pool[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = stream
	p.global_position = pos
	p.volume_db = volume_db
	var reach: Array = LONG_RANGE.get(sound, SHORT_RANGE.get(sound, [MAX_DISTANCE, 1.6]))
	p.max_distance = reach[0]
	p.attenuation = reach[1]
	var gun := sound.begins_with(GUN_DIR)
	p.bus = "Weapons" if gun or sound in WEAPON_SOUNDS else "SFX"
	if gun:
		pitch_jitter = minf(pitch_jitter, GUN_PITCH_JITTER)
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()


func _stream(sound: String) -> AudioStream:
	if _cache.has(sound):
		return _cache[sound]
	# "guns/<key>|<fallback>": the gun's own file, else the category sound.
	var bar := sound.find("|")
	if bar >= 0:
		var own := _load_stream(sound.left(bar))
		if own == null:
			push_warning("Sfx: missing gun sound '%s', using '%s'" % [sound.left(bar), sound.substr(bar + 1)])
			own = _stream(sound.substr(bar + 1))
		_cache[sound] = own
		return own
	var stream := _load_stream(sound)
	if stream == null:
		push_warning("Sfx: missing sound '%s' (put it in %s)" % [sound, AUDIO_DIR])
	_cache[sound] = stream
	return stream


## res://audio/<sound>.<ext> for the first extension that exists, or null.
static func _load_stream(sound: String) -> AudioStream:
	for ext in EXTENSIONS:
		var path := "%s%s.%s" % [AUDIO_DIR, sound, ext]
		if ResourceLoader.exists(path):
			return load(path)
	return null


## Firing sound for this gun: "guns/<key>|<category fallback>" (see _stream).
static func shot_sound(w: WeaponData, side: int) -> String:
	var fallback := category_shot_sound(w, side)
	if w.sound == "":
		return fallback
	return "%s%s|%s" % [GUN_DIR, w.sound, fallback]


## The old one-sound-per-category mapping, used when a gun's own file is missing.
static func category_shot_sound(w: WeaponData, side: int) -> String:
	match w.cat:
		WeaponData.PISTOL:
			if w.id == WeaponData.SENTRY:
				return "suppressed_shot"
			return "t_pistol_shot" if w.side == 0 or (w.side == WeaponData.ANY and side == 0) else "pistol_shot"
		WeaponData.RIFLE:
			return "t_rifle_shot" if w.side == 0 else "rifle_shot"
		WeaponData.HEAVY:
			return "t_rifle_shot"
		WeaponData.SMG:
			return "smg_shot"
		WeaponData.SHOTGUN:
			return "shotgun_shot"
		WeaponData.SNIPER:
			return "sniper_shot"
	return "pistol_shot"
