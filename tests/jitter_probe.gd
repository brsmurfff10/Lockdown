extends Node
## Bot movement in fights, measured: plays bot-only matches and counts, per
## second of combat, how often a fighting bot's movement flips (reverses, or
## starts/stops), how often its target drops and re-acquires, and how often its
## aim reverses direction. Lower = smoother.
##   godot --headless --path . --fixed-fps 60 res://tests/jitter_probe.tscn -- --test [--secs=90] [--ab=flag]

var secs := 90.0
var combat_t := 0.0
var move_flips := 0
var stop_starts := 0
var reacq := 0
var aim_rev := 0
var _last := {} ## unit -> {mv, tgt, lost_t, aim_v}


func _ready() -> void:
	Game.autoplay = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--secs="):
			secs = float(a.substr(7))
	for map in ["Dustline", "Cage"]:
		Game.prepare_quick_match(map)
		Game.pending_match.mode = "test"
		var m: Node = load(Game.MATCH_SCENE).instantiate()
		add_child(m)
		var t := 0.0
		while t < secs:
			await get_tree().physics_frame
			t += 1.0 / 60.0
			_sample(m, 1.0 / 60.0)
		m.queue_free()
		await get_tree().process_frame
	var c := maxf(combat_t, 0.001)
	print("JITTER: combat %.0f s | move flips %.2f/s | stop-go %.2f/s | target lost+regained <0.5s %.2f/s | aim reversals %.2f/s" % [
		combat_t, move_flips / c, stop_starts / c, reacq / c, aim_rev / c])
	get_tree().quit()


func _ctrl(u: Unit) -> BotController:
	for ch in u.get_children():
		if ch is BotController:
			return ch
	return null


func _sample(m: Node, dt: float) -> void:
	for u: Unit in m.units:
		if not u.alive:
			_last.erase(u)
			continue
		var b := _ctrl(u)
		if b == null:
			continue
		var l: Dictionary = _last.get(u, {"mv": Vector2.ZERO, "tgt": null, "lost_t": -9.0, "aim": u.aim_dir.angle(), "av": 0.0, "clock": 0.0})
		l.clock = float(l.clock) + dt
		var tgt = b._target
		if tgt == null and l.tgt != null:
			l.lost_t = l.clock
		elif tgt != null and l.tgt == null and float(l.clock) - float(l.lost_t) < 0.5:
			reacq += 1
		if tgt != null:
			combat_t += dt
			var mv: Vector2 = u.move_input
			var pm: Vector2 = l.mv
			if (mv == Vector2.ZERO) != (pm == Vector2.ZERO):
				if mv != Vector2.ZERO:
					stop_starts += 1
			elif mv != Vector2.ZERO and pm != Vector2.ZERO and mv.normalized().dot(pm.normalized()) < -0.3:
				move_flips += 1
			var a := u.aim_dir.angle()
			var av := wrapf(a - float(l.aim), -PI, PI)
			if absf(av) > 0.002 and absf(float(l.av)) > 0.002 and signf(av) != signf(float(l.av)):
				aim_rev += 1
			if absf(av) > 0.002:
				l.av = av
		l.aim = u.aim_dir.angle()
		l.mv = u.move_input
		l.tgt = tgt
		_last[u] = l
