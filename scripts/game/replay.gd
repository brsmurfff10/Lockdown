class_name Replay
extends Node2D
## Round recorder + replay player (kill-cam, round replays, highlight reel).
##
## Recording: every live round is sampled at RATE Hz into a lightweight
## timeline (per unit: position, aim, HP, flags, weapon; bomb; smokes/fires)
## plus events (shots, kills, bomb text). Rounds are kept for the whole match.
##
## Playback pauses the match (tree paused; this node and the HUD keep running),
## hides the live world and draws "ghost" units from the timeline instead.
##
## Highlights: per round, 3k+ (3K / 4K / ACE) and clutches won 1vX with X >= 2.
## Kills in the 5s exit time after a round is decided don't count.

const RATE := 20.0 ## Samples per second.
const STRIDE := 6 ## Floats per unit per frame: x, y, aim angle, hp, flags, weapon id.
const F_ALIVE := 1
const F_BOMB := 2
const F_SCOPED := 4
const F_ACTION := 8
const F_BLIND := 16
const F_KNIFE := 32 ## Knife out (and SLASH: mid-swipe).
const F_SLASH := 64
const KILLCAM_LEN := 4.0
const KILLCAM_HOLD := 0.9
const MAX_SHOTS := 6000 ## Per round, to keep memory bounded.
const SPEEDS := [0.25, 0.5, 1.0, 2.0, 4.0, 8.0]
const MAX_HIGHLIGHTS := 6

var m ## The Match.
var rounds: Array[Dictionary] = [] ## Finished rounds (in play order).
var cur: Dictionary = {} ## Round being recorded.
var _idx := {} ## Unit -> index in cur.units.
var _recording := false
var _last_sample := -1.0
var _shots := 0
var _clutch := [{}, {}] ## Per side: {i, vs, t} once that side is down to one player.

# Playback.
var active := false
var kind := "" ## "replay", "killcam" or "highlights".
var clips: Array[Dictionary] = [] ## {round (index, -1 = cur), segs [[t0, t1]], follow, title}
var clip_i := 0
var seg_i := 0
var t := 0.0
var speed := 1.0
var paused := false
var follow := -1 ## Unit index the camera follows, -1 = overview.
var _hold := 0.0
var _cam: Camera2D
var _saved := {}
var _closing := false


func setup(p_match) -> void:
	m = p_match


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS # Soldier and gun sprites are downscaled renders.
	z_index = 50
	visible = false
	_cam = Camera2D.new()
	_cam.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_cam)


# =============================================================================
# Recording
# =============================================================================

func begin_round() -> void:
	cur = {"num": m.round_num, "ot": m.ot_block(), "units": [], "frames": [], "events": [], "end": 0.0,
		"decided": -1.0, "winner_side": -1, "reason": "", "moments": [], "map": m.arena.map_name}
	_idx.clear()
	for i in m.units.size():
		var u: Unit = m.units[i]
		_idx[u] = i
		cur.units.append({"name": u.data.player_name, "side": u.side, "team": u.team_index, "user": u.data.is_user,
			"pd": u.data, "role": u.data.role})
	_recording = true
	_last_sample = -1.0
	_shots = 0
	_clutch = [{}, {}]


## Stop recording (the rest of the match is being simulated).
func stop() -> void:
	_recording = false


func sample(clock: float, force: bool = false) -> void:
	if not _recording or cur.is_empty():
		return
	if not force and _last_sample >= 0.0 and clock - _last_sample < 1.0 / RATE:
		return
	if force and _last_sample >= 0.0 and absf(clock - _last_sample) < 0.001:
		return
	_last_sample = clock
	var n: int = cur.units.size()
	var arr := PackedFloat32Array()
	arr.resize(n * STRIDE)
	for i in mini(n, m.units.size()):
		var u: Unit = m.units[i]
		if not is_instance_valid(u):
			continue
		var b := i * STRIDE
		arr[b] = u.global_position.x
		arr[b + 1] = u.global_position.y
		arr[b + 2] = u.aim_dir.angle()
		arr[b + 3] = u.health
		var f := 0
		if u.alive:
			f |= F_ALIVE
		if u.has_bomb:
			f |= F_BOMB
		if u.scope_t > 0.5:
			f |= F_SCOPED
		if u.action != Unit.Action.NONE:
			f |= F_ACTION
		if u.is_blind():
			f |= F_BLIND
		if u.knife_out and u.held_grenade == "":
			f |= F_KNIFE
			if u.slash_t > 0.0:
				f |= F_SLASH
		arr[b + 4] = f
		arr[b + 5] = u.weapon.id
	var fx := []
	if m.utility != null:
		for s: Dictionary in m.utility.smokes:
			fx.append(Vector3(s.pos.x, s.pos.y, m.utility._smoke_radius(s)))
		for fi: Dictionary in m.utility.fires:
			fx.append(Vector3(fi.pos.x, fi.pos.y, -1.0))
	cur.frames.append({"t": clock, "u": arr, "b": Vector3(m.bomb_state, m.bomb_pos.x, m.bomb_pos.y), "fx": fx})
	cur.end = clock


func on_shot(shooter: Unit, from: Vector2, to: Vector2) -> void:
	if not _recording or cur.is_empty() or _shots >= MAX_SHOTS:
		return
	_shots += 1
	cur.events.append({"k": "shot", "t": m.round_clock, "i": int(_idx.get(shooter, -1)), "a": from, "b": to})


func on_kill(killer: Unit, victim: Unit) -> void:
	if not _recording or cur.is_empty():
		return
	sample(m.round_clock, true) # Capture the exact moment.
	var live: bool = m.phase == m.Phase.LIVE
	var ev := {"k": "kill", "t": m.round_clock, "i": int(_idx.get(killer, -1)) if killer != null else -1,
		"v": int(_idx.get(victim, -1)), "w": killer.weapon.weapon_name if killer != null else "",
		"tk": killer != null and killer.side == victim.side, "post": not live}
	cur.events.append(ev)
	if not live:
		return
	# Clutch tracking: the first moment a side is down to its last player.
	var alive: Array[int] = m.alive_counts()
	for s in 2:
		if alive[s] == 1 and (_clutch[s] as Dictionary).is_empty() and alive[1 - s] >= 1:
			for u: Unit in m.units:
				if u.alive and u.side == s:
					_clutch[s] = {"i": int(_idx.get(u, -1)), "vs": alive[1 - s], "t": m.round_clock}
					break


func on_text(text: String) -> void:
	if not _recording or cur.is_empty():
		return
	cur.events.append({"k": "text", "t": m.round_clock, "s": text})


func end_round(winner_side: int, reason: String) -> void:
	if cur.is_empty():
		return
	sample(m.round_clock, true)
	cur.winner_side = winner_side
	cur.reason = reason
	cur.decided = m.round_clock
	cur.moments = _compute_moments(cur)
	rounds.append(cur) # Same dictionary keeps recording the 5s exit time.


func _compute_moments(rd: Dictionary) -> Array:
	var kills_by := {}
	for ev: Dictionary in rd.events:
		if ev.k == "kill" and not ev.post and int(ev.i) >= 0 and not ev.tk:
			if not kills_by.has(ev.i):
				kills_by[ev.i] = []
			(kills_by[ev.i] as Array).append(float(ev.t))
	var out: Array = []
	for i in kills_by:
		var times: Array = kills_by[i]
		if times.size() < 3:
			continue
		var label := "ACE" if times.size() >= 5 else "%dK" % times.size()
		var segs: Array = []
		for kt: float in times:
			segs.append([maxf(0.0, kt - 3.0), kt + 1.2])
		out.append({"i": int(i), "pd": rd.units[i].pd, "kinds": [label], "score": [0, 0, 0, 3.0, 4.5, 6.0][mini(times.size(), 5)],
			"segs": _merge(segs), "count": 1})
	for s in 2:
		var c: Dictionary = _clutch[s]
		if c.is_empty() or s != int(rd.winner_side) or int(c.vs) < 2 or int(c.i) < 0:
			continue
		var segs: Array = []
		for ev: Dictionary in rd.events:
			if ev.k == "kill" and not ev.post and int(ev.i) == int(c.i) and float(ev.t) >= float(c.t):
				segs.append([maxf(0.0, float(ev.t) - 3.0), float(ev.t) + 1.2])
		segs.append([maxf(0.0, float(rd.decided) - 3.0), float(rd.decided) + 1.0])
		var label := "1v%d CLUTCH" % int(c.vs)
		var found := false
		for mo: Dictionary in out:
			if int(mo.i) == int(c.i):
				(mo.kinds as Array).append(label)
				mo.segs = _merge((mo.segs as Array) + segs)
				mo.count = int(mo.count) + 1
				mo.score = float(mo.score) + 2.0 + float(c.vs)
				found = true
		if not found:
			out.append({"i": int(c.i), "pd": rd.units[c.i].pd, "kinds": [label], "score": 2.0 + float(c.vs),
				"segs": _merge(segs), "count": 1})
	return out


static func _merge(segs: Array) -> Array:
	segs.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var out: Array = []
	for sg: Array in segs:
		if not out.is_empty() and float(sg[0]) <= float(out[-1][1]) + 1.0:
			out[-1][1] = maxf(float(out[-1][1]), float(sg[1]))
		else:
			out.append([float(sg[0]), float(sg[1])])
	return out


## {PlayerData: moments} across every recorded round (3k+ round = 1, clutch = 1).
func highlight_counts() -> Dictionary:
	var out := {}
	for rd: Dictionary in rounds:
		for mo: Dictionary in rd.moments:
			out[mo.pd] = int(out.get(mo.pd, 0)) + int(mo.count)
	return out


## Best moments as clips: `focus`'s own (falls back to anyone's if they have none).
func highlight_clips(focus: PlayerData) -> Array[Dictionary]:
	var picks: Array = []
	for ri in rounds.size():
		for mo: Dictionary in rounds[ri].moments:
			if focus == null or mo.pd == focus:
				picks.append([ri, mo])
	if picks.is_empty() and focus != null:
		return highlight_clips(null)
	picks.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1].score) > float(b[1].score))
	picks = picks.slice(0, MAX_HIGHLIGHTS)
	picks.sort_custom(func(a: Array, b: Array) -> bool:
		return int(a[0]) < int(b[0]) or (int(a[0]) == int(b[0]) and float(a[1].segs[0][0]) < float(b[1].segs[0][0])))
	var out: Array[Dictionary] = []
	for pk: Array in picks:
		var mo: Dictionary = pk[1]
		var rd: Dictionary = rounds[pk[0]]
		out.append({"round": pk[0], "segs": mo.segs, "follow": mo.i,
			"title": "%s  -  %s   (%s)" % [(mo.pd as PlayerData).player_name, " + ".join(mo.kinds), _round_name(rd)]})
	return out


static func _round_name(rd: Dictionary) -> String:
	if int(rd.get("ot", 0)) > 0:
		return "Round %d, OT %d" % [int(rd.num), int(rd.ot)]
	return "Round %d" % int(rd.num)


# =============================================================================
# Playback API
# =============================================================================

## Watch a whole recorded round (N / P step through the other rounds).
func play_round(ri: int) -> void:
	if rounds.is_empty():
		return
	var cl: Array[Dictionary] = []
	for i in rounds.size():
		var rd: Dictionary = rounds[i]
		var winner := "T" if int(rd.winner_side) == 0 else "CT"
		cl.append({"round": i, "segs": [[0.0, float(rd.end)]], "follow": _default_follow(rd),
			"title": "%s REPLAY  -  %s win (%s)" % [_round_name(rd).to_upper(), winner, rd.reason]})
	_open("replay", cl, clampi(ri, 0, cl.size() - 1))


## The best moments of `focus` (or anyone), back to back.
func play_highlights(focus: PlayerData) -> bool:
	var cl := highlight_clips(focus)
	if cl.is_empty():
		return false
	_open("highlights", cl, 0)
	return true


## You just died: replay the last few seconds from your killer's position.
func start_killcam(killer: Unit, victim: Unit) -> void:
	if active or cur.is_empty() or not _idx.has(killer) or cur.frames.size() < 2:
		return
	var tk: float = cur.end
	var w: String = killer.weapon.weapon_name if is_instance_valid(killer) else ""
	var title := "KILL CAM  -  killed by %s%s" % [killer.data.player_name, ("  (%s)" % w) if w != "" else ""]
	_open("killcam", [{"round": -1, "segs": [[maxf(float(cur.frames[0].t), tk - KILLCAM_LEN), tk]],
		"follow": int(_idx[killer]), "victim": int(_idx.get(victim, -1)), "title": title}], 0)


func _default_follow(rd: Dictionary) -> int:
	for i in rd.units.size():
		if rd.units[i].user:
			return i
	return -1


func _open(p_kind: String, p_clips: Array[Dictionary], start: int) -> void:
	if active:
		return
	kind = p_kind
	clips = p_clips
	active = true
	_closing = false
	visible = true
	speed = 1.0
	paused = false
	_saved = {"paused": get_tree().paused, "fog": m._fog.color, "units": m.unit_layer.visible,
		"bullets": m.bullets.visible, "guns": m.gun_view.visible, "bomb": m.bomb_view.visible,
		"util": m.utility.visible, "light": m.vision_light.enabled, "cross": m.crosshair.visible, "allies": []}
	for l: PointLight2D in m.ally_lights:
		(_saved.allies as Array).append(l.enabled)
		l.enabled = false
	m.vision_light.enabled = false
	m._fog.color = Color.WHITE
	m.unit_layer.visible = false
	m.bullets.visible = false
	m.gun_view.visible = false
	m.bomb_view.visible = false
	m.utility.visible = false
	m.crosshair.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.set_custom_mouse_cursor(null)
	get_tree().paused = true
	_cam.limit_left = 0
	_cam.limit_top = 0
	_cam.limit_right = int(m.arena.size_px().x)
	_cam.limit_bottom = int(m.arena.size_px().y)
	_cam.zoom = m.camera.zoom
	_cam.position = m.camera.get_screen_center_position()
	_cam.make_current()
	m.hud.set_replay_mode(true, kind)
	_start_clip(start)


func _start_clip(i: int) -> void:
	clip_i = clampi(i, 0, clips.size() - 1)
	seg_i = 0
	var c: Dictionary = clips[clip_i]
	t = float(c.segs[0][0])
	follow = int(c.follow)
	_hold = 0.0
	paused = false
	var p := _pos_of(follow)
	if p != Vector2.INF:
		_cam.position = p


## Close (deferred, so the key that closed it doesn't reach the match this frame).
func close() -> void:
	if not active or _closing:
		return
	_closing = true
	call_deferred("_finish")


func _finish() -> void:
	if not active:
		return
	active = false
	_closing = false
	visible = false
	m._fog.color = _saved.fog
	m.unit_layer.visible = _saved.units
	m.bullets.visible = _saved.bullets
	m.gun_view.visible = _saved.guns
	m.bomb_view.visible = _saved.bomb
	m.utility.visible = _saved.util
	m.vision_light.enabled = _saved.light
	m.crosshair.visible = _saved.cross
	for i in m.ally_lights.size():
		if i < (_saved.allies as Array).size():
			m.ally_lights[i].enabled = _saved.allies[i]
	m.camera.make_current()
	m.hud.set_replay_mode(false, kind)
	get_tree().paused = bool(_saved.paused)
	kind = ""


# =============================================================================
# Playback loop
# =============================================================================

func _rd() -> Dictionary:
	var ri := int(clips[clip_i].round)
	return cur if ri < 0 else rounds[ri]


func _clip_start() -> float:
	return float(clips[clip_i].segs[0][0])


func _clip_end() -> float:
	return float(clips[clip_i].segs[-1][1])


func _process(delta: float) -> void:
	if not active:
		return
	var real := delta / maxf(Engine.time_scale, 0.01)
	var c: Dictionary = clips[clip_i]
	var segs: Array = c.segs
	if not paused:
		t += real * speed
	var seg_end := float(segs[seg_i][1])
	if t >= seg_end:
		if seg_i + 1 < segs.size():
			seg_i += 1
			t = float(segs[seg_i][0]) # Cut to the next moment.
		else:
			t = seg_end
			_hold += real
			match kind:
				"killcam":
					if _hold > KILLCAM_HOLD:
						close()
				"highlights":
					if _hold > 1.2:
						if clip_i + 1 < clips.size():
							_start_clip(clip_i + 1)
						else:
							paused = true
				_:
					paused = true
	_update_camera(real)
	_push_hud()
	queue_redraw()


func _update_camera(real: float) -> void:
	var vp := get_viewport().get_visible_rect().size
	if follow < 0:
		var size: Vector2 = m.arena.size_px()
		var z := minf(vp.x / size.x, vp.y / size.y) * 0.92
		_cam.zoom = _cam.zoom.lerp(Vector2(z, z), clampf(real * 6.0, 0.0, 1.0))
		_cam.position = _cam.position.lerp(size / 2.0, clampf(real * 6.0, 0.0, 1.0))
		return
	var p := _pos_of(follow)
	if p == Vector2.INF:
		return
	var z: float = m._zoom * (1.12 if kind == "killcam" else 1.0)
	_cam.zoom = _cam.zoom.lerp(Vector2(z, z), clampf(real * 6.0, 0.0, 1.0))
	_cam.position = _cam.position.lerp(p, clampf(real * 8.0, 0.0, 1.0))


func _push_hud() -> void:
	var c: Dictionary = clips[clip_i]
	var rd := _rd()
	var who := "Overview"
	if follow >= 0 and follow < rd.units.size():
		var st := _state(follow)
		who = "%s (%s)" % [rd.units[follow].name, WeaponData.name_of(int(st.w)) if not st.is_empty() and WeaponData.TABLE.has(int(st.w)) else "-"]
	var counter := ""
	if clips.size() > 1:
		counter = "%d / %d   " % [clip_i + 1, clips.size()]
	m.hud.update_replay({"title": counter + String(c.title), "t": t - _clip_start(), "len": _clip_end() - _clip_start(),
		"clock": t, "speed": speed, "paused": paused, "follow": who, "feed": _feed_lines(rd),
		"multi": clips.size() > 1, "kind": kind})


func _feed_lines(rd: Dictionary) -> Array:
	var out: Array = []
	for ev: Dictionary in rd.events:
		var et := float(ev.t)
		if et > t:
			break
		if et < t - 5.0 or ev.k == "shot":
			continue
		if ev.k == "kill":
			var v: Dictionary = rd.units[ev.v] if int(ev.v) >= 0 else {}
			var k: Dictionary = rd.units[ev.i] if int(ev.i) >= 0 else {}
			var line := ""
			if not k.is_empty():
				line = "[color=#%s]%s[/color]  [color=#8791a8]%s[/color]  " % [_side_hex(int(k.side)), k.name, ev.w]
			if not v.is_empty():
				line += "[color=#%s]%s[/color]" % [_side_hex(int(v.side)), v.name]
			out.append(line)
		elif ev.k == "text":
			out.append("[color=#fbbf24]%s[/color]" % ev.s)
	return out.slice(maxi(0, out.size() - 6))


static func _side_hex(side: int) -> String:
	return (Hud.SIDE_COLORS[clampi(side, 0, 1)] as Color).to_html(false)


# =============================================================================
# Controls
# =============================================================================

func command(cmd: String, value: float = 0.0) -> void:
	if not active:
		return
	match cmd:
		"toggle":
			if kind == "killcam":
				close()
			else:
				if paused and t >= _clip_end() - 0.01:
					_start_clip(clip_i) # Replay from the start.
				else:
					paused = not paused
		"seek":
			_seek(t + value)
		"seek_frac":
			_seek(lerpf(_clip_start(), _clip_end(), clampf(value, 0.0, 1.0)))
		"slower":
			speed = SPEEDS[maxi(0, SPEEDS.find(speed) - 1)]
		"faster":
			speed = SPEEDS[mini(SPEEDS.size() - 1, SPEEDS.find(speed) + 1)]
		"speed":
			speed = SPEEDS[(SPEEDS.find(speed) + 1) % SPEEDS.size()]
		"next":
			if clip_i + 1 < clips.size():
				_start_clip(clip_i + 1)
		"prev":
			if clip_i > 0:
				_start_clip(clip_i - 1)
		"follow_next":
			_cycle_follow(1)
		"follow_prev":
			_cycle_follow(-1)
		"overview":
			follow = -1
		"close":
			close()


func _seek(to: float) -> void:
	var segs: Array = clips[clip_i].segs
	to = clampf(to, _clip_start(), _clip_end())
	t = to
	seg_i = 0
	for i in segs.size():
		if to >= float(segs[i][0]) - 0.001:
			seg_i = i
	if t < float(segs[seg_i][0]):
		t = float(segs[seg_i][0])
	_hold = 0.0


func _cycle_follow(step: int) -> void:
	var n: int = _rd().units.size()
	if n == 0:
		return
	follow = posmod(follow + step, n) if follow >= 0 else (0 if step > 0 else n - 1)


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = (event as InputEventKey).physical_keycode
		var handled := true
		match k:
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
				command("toggle")
			KEY_ESCAPE, KEY_BACKSPACE, KEY_V:
				close()
			KEY_LEFT:
				command("seek", -5.0)
			KEY_RIGHT:
				command("seek", 5.0)
			KEY_MINUS, KEY_KP_SUBTRACT:
				command("slower")
			KEY_EQUAL, KEY_KP_ADD:
				command("faster")
			KEY_N, KEY_PAGEDOWN:
				command("next")
			KEY_P, KEY_PAGEUP:
				command("prev")
			KEY_F:
				command("overview")
			KEY_TAB:
				command("follow_next")
			_:
				handled = false
		if handled:
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if kind == "killcam" and mb.button_index == MOUSE_BUTTON_LEFT:
			close()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			command("follow_next")
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			command("follow_prev")
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			m._zoom = clampf(m._zoom + 0.08, m.ZOOM_MIN, m.ZOOM_MAX)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			m._zoom = clampf(m._zoom - 0.08, m.ZOOM_MIN, m.ZOOM_MAX)
		get_viewport().set_input_as_handled()


# =============================================================================
# Timeline lookups + drawing
# =============================================================================

## Index of the last frame at or before time `at`.
func _frame_index(rd: Dictionary, at: float) -> int:
	var frames: Array = rd.frames
	var lo := 0
	var hi := frames.size() - 1
	if hi < 0:
		return -1
	if at <= float(frames[0].t):
		return 0
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		if float(frames[mid].t) <= at:
			lo = mid
		else:
			hi = mid - 1
	return lo


## Interpolated state of unit `i` at the playback time: {pos, ang, hp, f, w}.
func _state(i: int, at: float = -1.0) -> Dictionary:
	var rd := _rd()
	if at < 0.0:
		at = t
	var fi := _frame_index(rd, at)
	if fi < 0 or i < 0:
		return {}
	var fa: Dictionary = rd.frames[fi]
	var fb: Dictionary = rd.frames[mini(fi + 1, rd.frames.size() - 1)]
	var a: PackedFloat32Array = fa.u
	var b: PackedFloat32Array = fb.u
	var base := i * STRIDE
	if base + STRIDE > a.size():
		return {}
	var span := float(fb.t) - float(fa.t)
	var k := clampf((at - float(fa.t)) / span, 0.0, 1.0) if span > 0.0001 else 0.0
	var pa := Vector2(a[base], a[base + 1])
	var pb := Vector2(b[base], b[base + 1])
	var flags := int(a[base + 4])
	# Don't slide a body that just died / teleport at round start.
	if pa.distance_to(pb) > 120.0 or (flags & F_ALIVE) == 0:
		k = 0.0
	return {"pos": pa.lerp(pb, k), "ang": lerp_angle(a[base + 2], b[base + 2], k), "hp": lerpf(a[base + 3], b[base + 3], k),
		"f": flags, "w": int(a[base + 5])}


func _pos_of(i: int) -> Vector2:
	var st := _state(i)
	return Vector2.INF if st.is_empty() else st.pos


func _draw() -> void:
	if not active or clips.is_empty():
		return
	var rd := _rd()
	if rd.frames.is_empty():
		return
	var fi := _frame_index(rd, t)
	var fr: Dictionary = rd.frames[fi]
	# Smokes / fires.
	for v: Vector3 in fr.fx:
		if v.z < 0.0 and VfxLayer.draw_fire(self, Vector2(v.x, v.y), Utility.FIRE_RADIUS, t):
			continue
		if v.z < 0.0:
			draw_circle(Vector2(v.x, v.y), Utility.FIRE_RADIUS, Color(1.0, 0.4, 0.08, 0.35))
			draw_arc(Vector2(v.x, v.y), Utility.FIRE_RADIUS, 0, TAU, 32, Color(1.0, 0.5, 0.15, 0.7), 2.0)
	# Bomb.
	var b: Vector3 = fr.b
	var bpos := Vector2(b.y, b.z)
	match int(b.x):
		1: # Dropped.
			if not GunArt.draw_bomb(self, bpos, true):
				draw_rect(Rect2(bpos - Vector2(6, 5), Vector2(12, 10)), Color(0.8, 0.15, 0.15))
		2, 3: # Planted / defused.
			var art := GunArt.draw_bomb(self, bpos)
			if not art:
				draw_rect(Rect2(bpos - Vector2(7, 6), Vector2(14, 12)), Color(0.7, 0.12, 0.12))
			if int(b.x) == 2 and fmod(t, 1.0) < 0.35:
				var led := bpos + (Vector2(-7.0, 4.7) if art else Vector2.ZERO)
				draw_circle(led, 5.0, Color(1, 0.15, 0.1, 0.35))
				draw_circle(led, 2.2, Color(1, 0.35, 0.3))
		4: # Exploded.
			draw_circle(bpos, 60.0, Color(1.0, 0.55, 0.2, 0.3))
	# Shots: tracers for ~0.12s.
	var evs: Array = rd.events
	for ev: Dictionary in evs:
		var et := float(ev.t)
		if et > t:
			break
		if ev.k == "shot" and et > t - 0.12:
			var a := 1.0 - (t - et) / 0.12
			draw_line(ev.a, ev.b, Color(1.0, 0.92, 0.6, 0.6 * a), 1.5)
	var font := ThemeDB.fallback_font
	# Units.
	var victim := int(clips[clip_i].get("victim", -1))
	for i in rd.units.size():
		var st := _state(i)
		if st.is_empty():
			continue
		var side := int(rd.units[i].side)
		var col: Color = Unit.SIDE_COLORS[side]
		var p: Vector2 = st.pos
		var dir := Vector2.RIGHT.rotated(st.ang)
		var who := String(rd.units[i].name)
		var wid := int(st.w)
		var wdata: WeaponData = WeaponData.by_id(wid) if WeaponData.TABLE.has(wid) else null
		var knife := (int(st.f) & F_KNIFE) != 0
		var pose := PlayerArt.pose_for(wdata, knife)
		var sprite := PlayerArt.has(side)
		if (int(st.f) & F_ALIVE) == 0:
			if sprite:
				draw_circle(p, Unit.RADIUS, Color(col.darkened(0.6), 0.45))
				PlayerArt.draw_body(self, side, who, pose, dir, Color(0.42, 0.4, 0.4), p)
			else:
				draw_circle(p, Unit.RADIUS, col.darkened(0.7))
				draw_line(p + Vector2(-6, -6), p + Vector2(6, 6), Color(0, 0, 0, 0.7), 3.0)
				draw_line(p + Vector2(-6, 6), p + Vector2(6, -6), Color(0, 0, 0, 0.7), 3.0)
			if i == victim:
				draw_arc(p, Unit.RADIUS + 5.0, 0, TAU, 24, Color(1.0, 0.25, 0.2, 0.9), 2.0)
			continue
		if i == follow:
			# Their view: a faint cone so you see what they saw.
			var half := deg_to_rad(55.0)
			var pts := PackedVector2Array([p])
			for s in 13:
				pts.append(p + dir.rotated(-half + 2.0 * half * s / 12.0) * 520.0)
			draw_colored_polygon(pts, Color(1.0, 0.95, 0.6, 0.07))
		var wcat := WeaponData.cat_of(wid) if WeaponData.TABLE.has(wid) else WeaponData.PISTOL
		var gun_len := 9.0
		match wcat:
			WeaponData.RIFLE, WeaponData.HEAVY:
				gun_len = 14.0
			WeaponData.SNIPER:
				gun_len = 19.0
			WeaponData.SMG, WeaponData.SHOTGUN:
				gun_len = 11.0
		var muzzle := p + dir * (Unit.RADIUS + gun_len)
		if wdata != null:
			var mp := GunArt.muzzle_point(wdata, dir, side, pose)
			if mp != Vector2.INF:
				muzzle = p + mp
		if sprite:
			# Same art as live play: team base, gun in hand, soldier.
			draw_circle(p, Unit.RADIUS, Color(col, 0.3))
			draw_arc(p, Unit.RADIUS, 0.0, TAU, 32, Color(col, 0.95), 1.6)
			if knife:
				PlayerArt.draw_body(self, side, who, pose, dir, PlayerArt.TINT, p)
				GunArt.draw_knife(self, dir, side, pose, 0.5 if (int(st.f) & F_SLASH) != 0 else 0.0, 1.0, p)
			else:
				if wdata == null or not GunArt.draw_held(self, wdata, dir, side, pose, p):
					draw_line(p + dir * 4.0, muzzle, Color(0.1, 0.1, 0.1), 5.0)
				PlayerArt.draw_body(self, side, who, pose, dir, PlayerArt.TINT, p)
		else:
			draw_line(p + dir * 4.0, muzzle, Color(0.1, 0.1, 0.1), 5.0)
			draw_circle(p, Unit.RADIUS, col)
			draw_arc(p, Unit.RADIUS, 0.0, TAU, 24, Color(0, 0, 0, 0.8), 2.0)
			draw_circle(p + dir * 5.0, 4.0, col.lightened(0.35))
		if (int(st.f) & F_SCOPED) != 0 and wcat == WeaponData.SNIPER:
			draw_line(muzzle, p + dir * 260.0, Color(0.6, 0.85, 1.0, 0.25), 1.0)
		if (int(st.f) & F_BOMB) != 0 and not GunArt.draw_bomb_on_back(self, dir, p):
			draw_rect(Rect2(p - dir * 9.0 - Vector2(4, 4), Vector2(8, 8)), Color(0.85, 0.15, 0.15))
		if (int(st.f) & F_BLIND) != 0:
			draw_arc(p, Unit.RADIUS + 2.0, 0.0, TAU, 20, Color(1, 1, 1, 0.8), 3.0)
		if i == follow:
			draw_arc(p, Unit.RADIUS + 4.0, 0.0, TAU, 32, Color(1.0, 0.95, 0.4, 0.95), 2.0)
		elif rd.units[i].user:
			draw_arc(p, Unit.RADIUS + 4.0, 0.0, TAU, 32, Color(1.0, 0.95, 0.4, 0.45), 1.5)
		var bar := Rect2(p + Vector2(-16, -Unit.RADIUS - 12), Vector2(32, 4))
		draw_rect(bar, Color(0, 0, 0, 0.6))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(float(st.hp) / Unit.MAX_HEALTH, 0.0, 1.0), 4)), Color(0.4, 0.95, 0.4))
		draw_string(font, p + Vector2(-50, -Unit.RADIUS - 16), String(rd.units[i].name), HORIZONTAL_ALIGNMENT_CENTER, 100, 11, Color(1, 1, 1, 0.9))
	# Kill flashes.
	for ev: Dictionary in evs:
		var et := float(ev.t)
		if et > t:
			break
		if ev.k == "kill" and et > t - 0.8 and int(ev.v) >= 0:
			var st := _state(int(ev.v))
			if not st.is_empty():
				var a := 1.0 - (t - et) / 0.8
				draw_arc(st.pos, Unit.RADIUS + 6.0 + 22.0 * (1.0 - a), 0, TAU, 32, Color(1.0, 0.25, 0.2, a), 3.0)
	# Smoke clouds on top of everything (they hid people live too, but we show a bit through).
	for v: Vector3 in fr.fx:
		if v.z > 1.0 and not VfxLayer.draw_smoke(self, Vector2(v.x, v.y), v.z, t, 0.75):
			draw_circle(Vector2(v.x, v.y), v.z, Color(0.62, 0.64, 0.68, 0.6))
