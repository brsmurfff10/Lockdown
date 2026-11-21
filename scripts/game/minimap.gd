class_name Minimap
extends Control
## Radar in the top-left corner: the map, you, your teammates, and enemies
## only as your team calls them out (a marker where they were called, fading
## out). You never see through a teammate's eyes: positions are refreshed at
## most once per CALL_EVERY seconds per enemy, the way a callout works, and a
## heard enemy is only a rough ring.

const MAX_W := 210.0
const MAX_H := 190.0
const CALL_EVERY := 1.6 ## A spotted enemy's marker moves at most this often.
const SHOW_FOR := 6.0 ## Seconds a call stays on the radar.

var match_node ## The Match.
var _calls := {} ## Unit -> {pos, t, kind}
var _scale := 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(m) -> void:
	match_node = m
	var px: Vector2 = m.arena.size_px()
	_scale = minf(MAX_W / px.x, MAX_H / px.y)
	custom_minimum_size = px * _scale
	size = px * _scale


func _process(_delta: float) -> void:
	if match_node == null or not is_instance_valid(match_node):
		return
	var m = match_node
	visible = m.user_unit != null and not Game.autoplay and not m.is_spectating() and not m.buy_menu_open
	if not visible:
		return
	_update_calls()
	queue_redraw()


func _update_calls() -> void:
	var m = match_node
	var side: int = m.user_unit.side
	var now: float = m.round_clock
	var known: Dictionary = m.tactics.seen_by[side]
	for e in known:
		if not is_instance_valid(e):
			continue
		var s: Dictionary = known[e]
		var t := float(s.time)
		if now - t > SHOW_FOR or s.get("cleared", false):
			continue
		var c: Dictionary = _calls.get(e, {})
		if c.is_empty() or (t > float(c.t) and now - float(c.t) >= CALL_EVERY):
			_calls[e] = {"pos": s.pos, "t": t, "kind": String(s.get("kind", "seen")), "dead": not e.alive}
	for e in _calls.keys():
		if not is_instance_valid(e) or now - float(_calls[e].t) > SHOW_FOR:
			_calls.erase(e)
	if m.round_clock < 0.5:
		_calls.clear()


func _to_map(p: Vector2) -> Vector2:
	return p * _scale


func _draw() -> void:
	var m = match_node
	if m == null:
		return
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r.grow(4.0), Color(0.05, 0.06, 0.08, 0.72))
	var art: Texture2D = m.arena.art_texture
	if art != null:
		draw_texture_rect(art, r, false, Color(0.75, 0.75, 0.75, 0.9))
	else:
		draw_rect(r, Color(0.12, 0.13, 0.15, 0.9))
	draw_rect(r.grow(4.0), Color(1, 1, 1, 0.14), false, 1.0)
	# Site letters.
	var font := ThemeDB.fallback_font
	for k: String in m.arena.sites:
		var c: Vector2 = _to_map(m.arena.site_center(k))
		draw_string(font, c + Vector2(-5, 5), k, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.85, 0.4, 0.8))
	var me: Unit = m.user_unit
	var now: float = m.round_clock
	# The bomb, when your side would know where it is.
	if m.bomb_state == m.Bomb.PLANTED or (me.side == 0 and m.bomb_state == m.Bomb.DROPPED):
		var bp: Vector2 = _to_map(m.bomb_pos)
		var blink := 0.5 + 0.5 * sin(now * 8.0)
		draw_rect(Rect2(bp - Vector2(3, 3), Vector2(6, 6)), Color(1, 0.25, 0.2, 0.6 + 0.4 * blink))
	# Enemy calls.
	for e in _calls:
		var c: Dictionary = _calls[e]
		var p := _to_map(c.pos)
		var a := clampf(1.0 - (now - float(c.t)) / SHOW_FOR, 0.0, 1.0)
		var col := Color(1.0, 0.3, 0.25, a)
		if c.dead:
			draw_line(p + Vector2(-3, -3), p + Vector2(3, 3), col, 1.5)
			draw_line(p + Vector2(-3, 3), p + Vector2(3, -3), col, 1.5)
		elif c.kind == "heard":
			draw_arc(p, 6.0, 0.0, TAU, 16, col, 1.5) # Heard: roughly here.
		else:
			draw_circle(p, 3.2, col)
			draw_arc(p, 4.6, 0.0, TAU, 12, Color(0, 0, 0, a * 0.6), 1.0)
	# Teammates and you.
	for u: Unit in m.units:
		if u.side != me.side:
			continue
		var p := _to_map(u.global_position)
		var col: Color = Unit.SIDE_COLORS[u.side]
		if not u.alive:
			draw_line(p + Vector2(-2.5, -2.5), p + Vector2(2.5, 2.5), Color(col, 0.5), 1.2)
			draw_line(p + Vector2(-2.5, 2.5), p + Vector2(2.5, -2.5), Color(col, 0.5), 1.2)
			continue
		if u == me:
			var d := u.aim_dir
			var tri := PackedVector2Array([p + d * 6.0, p + d.rotated(2.5) * 4.0, p + d.rotated(-2.5) * 4.0])
			draw_colored_polygon(tri, Color(1.0, 0.95, 0.4))
		else:
			draw_circle(p, 3.0, col)
			draw_line(p, p + u.aim_dir * 6.0, Color(col, 0.7), 1.0)
