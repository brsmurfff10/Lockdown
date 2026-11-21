extends Node
## Every gun has its own firing sound: the file exists and imports, is short,
## has sane peaks, no two guns share a file, and a missing file falls back to
## the old category sound.
## Run:  godot --headless --path . res://tests/gun_sound_probe.tscn -- --test

var fails := 0


func _ready() -> void:
	var sfx := Sfx.new()
	add_child(sfx)
	var seen := {}
	print("  %-16s %-26s %7s %6s" % ["gun", "sound", "secs", "peak"])
	for wid: int in WeaponData.ALL:
		var w := WeaponData.by_id(wid)
		var key := Sfx.shot_sound(w, 0 if w.side != 1 else 1)
		var own := key.get_slice("|", 0)
		var path := "%s%s.wav" % [Sfx.AUDIO_DIR, own]
		var stream: AudioStream = sfx._stream(key)
		var length := stream.get_length() if stream != null else 0.0
		var peak := _wav_peak(path)
		print("  %-16s %-26s %7.3f %6.2f" % [w.weapon_name, own, length, peak])
		_check("%s: has its own sound key" % w.weapon_name, w.sound != "" and key.begins_with(Sfx.GUN_DIR))
		_check("%s: file imports (%s)" % [w.weapon_name, path], ResourceLoader.exists(path) and stream != null)
		_check("%s: length 0.05-3.0 s" % w.weapon_name, length >= 0.05 and length <= 3.0)
		_check("%s: peak 0.2-0.75 (no clipping)" % w.weapon_name, peak >= 0.2 and peak <= 0.75)
		_check("%s: sound not shared" % w.weapon_name, not seen.has(own))
		seen[own] = true
	# Fallback: a gun whose file is missing plays its category sound.
	var fake := WeaponData.by_id(WeaponData.RAPTOR)
	fake.sound = "no_such_gun"
	var fb_key := Sfx.shot_sound(fake, 0)
	_check("missing gun file falls back to t_rifle_shot",
		fb_key.ends_with("|t_rifle_shot") and sfx._stream(fb_key) == sfx._stream("t_rifle_shot"))
	# Played through the Weapons bus and rate-limited like before.
	sfx.played_log.clear()
	var g := Sfx.shot_sound(WeaponData.by_id(WeaponData.GUARDIAN), 1)
	for i in 10:
		sfx.play(g, Vector2.ZERO, 0.0, 0.04)
	_check("per-gun shot plays and is rate-limited (3 per 60 ms)", sfx.played_log.count(g) == Sfx.RATE_LIMIT)
	var used: Array = sfx._pool.filter(func(p: AudioStreamPlayer2D) -> bool: return p.stream != null)
	_check("per-gun shot goes to the Weapons bus", used.size() > 0 and used.all(func(p: AudioStreamPlayer2D) -> bool: return p.bus == "Weapons"))
	_check("per-gun pitch variance capped at %.2f" % Sfx.GUN_PITCH_JITTER,
		used.all(func(p: AudioStreamPlayer2D) -> bool: return absf(p.pitch_scale - 1.0) <= Sfx.GUN_PITCH_JITTER + 0.0001))
	print("GUN SOUNDS: %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit()


## Peak of a 16-bit PCM wav (0..1), read straight from the source file.
func _wav_peak(path: String) -> float:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 44:
		return 0.0
	var i := 12
	while i + 8 <= bytes.size():
		var id := bytes.slice(i, i + 4).get_string_from_ascii()
		var size := bytes.decode_u32(i + 4)
		if id == "data":
			var peak := 0
			var j := i + 8
			var end := mini(bytes.size() - 1, i + 8 + size)
			while j + 1 < end:
				peak = maxi(peak, absi(bytes.decode_s16(j)))
				j += 2
			return peak / 32768.0
		i += 8 + size + (size & 1)
	return 0.0


func _check(what: String, ok: bool) -> void:
	if not ok:
		fails += 1
		print("  FAIL  " + what)
