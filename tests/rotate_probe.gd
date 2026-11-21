extends Node
## Rotations, measured: plays bot-only matches; whenever a "rotate" radio call
## goes out, snapshots that side, and 6 s later lists who barely moved and what
## the team brain had them doing. Also watches saving players of both sides
## sitting near each other without fighting.
##   godot --headless --path . --fixed-fps 60 res://tests/rotate_probe.tscn -- --test [--secs=240]

var secs := 240.0
var pending: Array = [] ## {t, side, snap: {unit: pos}, text}
var calls := 0
var stayers := 0
var movers := 0
var reasons := {}
var save_meet := 0
var _seen_pairs := {}
var _clock := 0.0


func _ready() -> void:
	Game.autoplay = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--secs="):
			secs = float(a.substr(7))
	for map in ["Dustline", "Cage", "Harbor"]:
		Game.prepare_quick_match(map)
		Game.pending_match.mode = "test"
		var m: Node = load(Game.MATCH_SCENE).instantiate()
		add_child(m)
		var hud_hooked := false
		var t := 0.0
		var last_n := 0
		while t < secs:
			await get_tree().physics_frame
			t += 1.0 / 60.0
			_clock += 1.0 / 60.0
			if m.hud != null and not hud_hooked:
				hud_hooked = true
			_watch_radio(m)
			_resolve(m)
			_watch_saves(m)
		m.queue_free()
		pending.clear()
		await get_tree().process_frame
	print("ROTATE: %d calls, %d teammates moved, %d stayed put" % [calls, movers, stayers])
	for k in reasons:
		print("   stayed: %-60s x%d" % [k, reasons[k]])
	print("SAVE MEETS: %d times a saving player and an enemy were within 250px with sight and nobody fired for 4s" % save_meet)
	get_tree().quit()


var _last_call := {}
func _watch_radio(m: Node) -> void:
	var tac = m.tactics
	for side in [0, 1]:
		var text := String(tac.igl_call[side])
		if text == String(_last_call.get(side, "")):
			continue
		_last_call[side] = text
		if text.to_lower().contains("rotate"):
			calls += 1
			var snap := {}
			for u: Unit in m.units:
				if u.alive and u.side == side:
					snap[u] = u.global_position
			pending.append({"t": _clock + 10.0, "side": side, "snap": snap, "text": text})


func _resolve(m: Node) -> void:
	var tac = m.tactics
	for p in pending.duplicate():
		if _clock < float(p.t):
			continue
		pending.erase(p)
		if not m.is_live():
			continue
		for u: Unit in p.snap:
			if not is_instance_valid(u) or not u.alive:
				continue
			var moved: float = u.global_position.distance_to(p.snap[u])
			if moved < 120.0:
				stayers += 1
				var st := String(tac.ct_state.get(u, "")) if u.side == 1 else "T"
				var home := String(tac.ct_home.get(u, {}).get("site", "?")) if u.side == 1 else "-"
				var called := String(tac.ct_call_site) if u.side == 1 else "-"
				var rel := "ON called site" if home == called else ("OTHER site" if home in ["A", "B"] else home)
				var why := "%s %s | state=%s | %s" % ["CT" if u.side == 1 else "T", rel, st, String(tac.thought.get(u, "?")).left(30)]
				reasons[why] = int(reasons.get(why, 0)) + 1
			else:
				movers += 1


func _watch_saves(m: Node) -> void:
	var tac = m.tactics
	for u: Unit in m.units:
		if not u.alive or not tac.saving.has(u):
			continue
		for e: Unit in m.enemies_of(u.side):
			if u.global_position.distance_to(e.global_position) < 250.0 and m.can_see(u, e):
				var k := "%d_%d" % [u.get_instance_id(), e.get_instance_id()]
				var first: float = _seen_pairs.get(k, -1.0)
				if first < 0.0:
					_seen_pairs[k] = _clock
				elif _clock - first > 4.0 and _clock - first < 4.0 + 1.0 / 60.0:
					save_meet += 1
					print("  save meet: %s (saving, %s) and %s (%s), %s / %s" % [u.data.player_name, "CT" if u.side == 1 else "T", e.data.player_name,
						"saving" if tac.saving.has(e) else "not saving", String(tac.thought.get(u, "")), String(tac.thought.get(e, ""))])
			else:
				_seen_pairs.erase("%d_%d" % [u.get_instance_id(), e.get_instance_id()])
