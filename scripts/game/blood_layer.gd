class_name BloodLayer
extends Node2D
## Blood: mist and droplets spraying out of a hit (away from the shooter),
## spatter on the floor behind the victim and on a wall right behind them,
## a pool spreading under a body, and drips from badly hurt players.
## Decals last the round (clear() at round start). Drawn above the map and
## below players and bodies. Off when Game.settings.blood is false.

const MAX_DECALS := 700
const BLOOD := Color(0.42, 0.015, 0.02)
const BLOOD_DARK := Color(0.24, 0.0, 0.01)
const BLOOD_BRIGHT := Color(0.62, 0.04, 0.04)
const DRIP_HP := 30.0

var match_node: Node
var rng := RandomNumberGenerator.new()
var _particles: Array[Dictionary] = [] ## {pos, vel, r, t, life, land}
var _mists: Array[Dictionary] = [] ## {pos, vel, r, t, life}
var _decals: Array[Dictionary] = [] ## {pts: PackedVector2Array, color} or {pos, r, color}
var _pools: Array[Dictionary] = [] ## {unit, pos, r, max, blobs}
var _drip_t := {} ## Unit -> seconds until the next drip
var _air: Node2D ## Mist and flying droplets, drawn over the players.


func _init(p_match: Node) -> void:
	match_node = p_match
	rng.randomize()
	z_index = -5
	_air = Node2D.new()
	_air.z_as_relative = false
	_air.z_index = 6
	_air.draw.connect(_draw_air)
	add_child(_air)


static func enabled() -> bool:
	return bool(Game.settings.get("blood", true))


func clear() -> void:
	_particles.clear()
	_mists.clear()
	_decals.clear()
	_pools.clear()
	_drip_t.clear()
	queue_redraw()
	_air.queue_redraw()


## A bullet hit `victim` at `at`, travelling along `dir`. `amount` = damage dealt.
## `hidden`: the player can't see the victim (smoke, behind a wall): no mist,
## droplets or spatter (they'd give the hit away); a kill still leaves a pool.
func hit(victim: Node2D, at: Vector2, dir: Vector2, amount: float, killed: bool, hidden: bool = false) -> void:
	if not enabled():
		return
	if hidden:
		# Only a kill (which the kill feed announces anyway) leaves a pool.
		dir = dir.normalized()
		if killed:
			_pools.append({"unit": victim, "pos": victim.global_position + dir * 4.0, "r": 4.0, "max": rng.randf_range(20.0, 27.0),
				"blobs": _blob_offsets(7)})
		set_process(true)
		return
	dir = dir.normalized()
	var k := clampf(amount / 30.0, 0.4, 2.2) * (1.5 if killed else 1.0)
	# Exit mist (behind the victim) and a little back-spray toward the shooter.
	var exit := victim.global_position + dir * 10.0
	_mists.append({"pos": exit, "vel": dir * 70.0, "r": 6.0, "grow": 26.0 * k, "t": 0.0, "life": 0.45})
	_mists.append({"pos": at, "vel": -dir * 25.0, "r": 3.0, "grow": 10.0, "t": 0.0, "life": 0.25})
	# Droplets: fly out in a cone and land as spatter where they stop.
	var n := int(8 * k) + 4
	for i in n:
		var a := dir.angle() + rng.randfn(0.0, 0.38)
		var spd := rng.randf_range(90.0, 330.0) * (0.7 + k * 0.3)
		_particles.append({"pos": exit + Vector2.from_angle(a) * rng.randf_range(0, 6), "vel": Vector2.from_angle(a) * spd,
			"r": rng.randf_range(1.2, 2.8), "t": 0.0, "life": rng.randf_range(0.12, 0.32), "land": true})
	for i in 3:
		var a2 := (-dir).angle() + rng.randfn(0.0, 0.6)
		_particles.append({"pos": at, "vel": Vector2.from_angle(a2) * rng.randf_range(40.0, 110.0), "r": rng.randf_range(1.0, 1.8),
			"t": 0.0, "life": rng.randf_range(0.08, 0.16), "land": true})
	# Main spatter on the floor behind them, or on the wall if one is close.
	var wall := _wall_along(victim.global_position, dir, 70.0 + 30.0 * k)
	if wall != Vector2.INF:
		_wall_splat(wall, dir, k)
	else:
		_splat(victim.global_position + dir * rng.randf_range(14.0, 34.0) * k, dir, 7.0 * k)
	if killed:
		_pools.append({"unit": victim, "pos": victim.global_position + dir * 4.0, "r": 4.0, "max": rng.randf_range(20.0, 27.0),
			"blobs": _blob_offsets(7)})
	set_process(true)


## Walks out from `from` along `dir`; first wall point within `dist`, else INF.
func _wall_along(from: Vector2, dir: Vector2, dist: float) -> Vector2:
	var arena: Arena = match_node.arena
	var step := 6.0
	var d := 12.0
	while d <= dist:
		var p := from + dir * d
		if arena.is_solid(arena.world_to_cell(p)):
			return from + dir * (d - step * 0.5)
		d += step
	return Vector2.INF


func _blob_offsets(n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append([Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.2, 0.75), rng.randf_range(0.45, 0.8)])
	return out


## Floor spatter: a core blob, satellites and droplets stretched along `dir`.
func _splat(pos: Vector2, dir: Vector2, size: float) -> void:
	var col := BLOOD.lerp(BLOOD_DARK, rng.randf() * 0.4)
	_add_ellipse(pos, dir, size, size * rng.randf_range(0.6, 0.9), col)
	for i in rng.randi_range(3, 6):
		var off := dir.rotated(rng.randfn(0.0, 0.7)) * rng.randf_range(size * 0.6, size * 1.6)
		_add_ellipse(pos + off, dir, size * rng.randf_range(0.25, 0.5), size * rng.randf_range(0.18, 0.35), col)
	# Streaks: thin elongated drops flung further out.
	for i in rng.randi_range(3, 7):
		var a := dir.rotated(rng.randfn(0.0, 0.35))
		var p := pos + a * rng.randf_range(size * 1.4, size * 3.2)
		_add_ellipse(p, a, rng.randf_range(2.0, 4.5), rng.randf_range(0.8, 1.6), col.lightened(0.05))


## Wall spatter: a wide splash fanned out along the wall face.
func _wall_splat(pos: Vector2, dir: Vector2, k: float) -> void:
	var along := Vector2(-dir.y, dir.x)
	var col := BLOOD_BRIGHT.lerp(BLOOD, 0.5)
	_add_ellipse(pos, along, 9.0 * k, 4.0 * k, col)
	for i in rng.randi_range(5, 9):
		var p := pos + along * rng.randfn(0.0, 9.0 * k) - dir * rng.randf_range(0.0, 4.0)
		_add_ellipse(p, along.rotated(rng.randfn(0.0, 0.2)), rng.randf_range(2.0, 6.0) * k, rng.randf_range(1.0, 2.2), col)
	# Runs: a few streaks dripping back toward the floor side.
	for i in rng.randi_range(1, 3):
		var p2 := pos + along * rng.randfn(0.0, 6.0 * k)
		_add_ellipse(p2 - dir * 5.0, dir, rng.randf_range(4.0, 8.0), 1.0, col.darkened(0.15))


func _add_ellipse(pos: Vector2, dir: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	var ang := dir.angle()
	var segs := 10
	for i in segs:
		var t := TAU * i / segs
		var wob := 1.0 + rng.randf_range(-0.12, 0.12)
		pts.append(pos + Vector2(cos(t) * rx * wob, sin(t) * ry * wob).rotated(ang))
	_decals.append({"pts": pts, "color": Color(col, rng.randf_range(0.82, 0.95))})
	if _decals.size() > MAX_DECALS:
		_decals.remove_at(0)


func _process(delta: float) -> void:
	var busy := false
	for p in _particles:
		p.t += delta
		p.pos += p.vel * delta
		p.vel *= exp(-6.0 * delta)
		if p.t >= p.life and p.land:
			p.land = false
			_add_ellipse(p.pos, (p.vel as Vector2).normalized() if (p.vel as Vector2).length() > 1.0 else Vector2.RIGHT,
				p.r * rng.randf_range(1.1, 2.0), p.r * rng.randf_range(0.7, 1.1), BLOOD.lerp(BLOOD_DARK, rng.randf() * 0.5))
	_particles = _particles.filter(func(p: Dictionary) -> bool: return p.t < p.life)
	for m in _mists:
		m.t += delta
		m.pos += m.vel * delta
		m.vel *= exp(-5.0 * delta)
	_mists = _mists.filter(func(m: Dictionary) -> bool: return m.t < m.life)
	for pool in _pools:
		if pool.r < pool.max:
			pool.r = minf(pool.max, pool.r + delta * (pool.max - pool.r) * 0.6 + delta * 0.6)
			busy = true
	if enabled():
		_drips(delta)
	busy = busy or not _particles.is_empty() or not _mists.is_empty()
	queue_redraw()
	_air.queue_redraw()
	if not busy and _drip_t.is_empty():
		set_process(false)


## Badly hurt players leave drops behind them while they move.
func _drips(delta: float) -> void:
	for u: Unit in match_node.units:
		if not u.alive or u.health > DRIP_HP:
			_drip_t.erase(u)
			continue
		var t := float(_drip_t.get(u, rng.randf_range(0.1, 0.4))) - delta * (1.0 + u.velocity.length() / 120.0)
		if t <= 0.0:
			t = rng.randf_range(0.35, 0.8) * (u.health / DRIP_HP + 0.4)
			var p := u.global_position + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(2.0, 7.0)
			_add_ellipse(p, Vector2.from_angle(rng.randf() * TAU), rng.randf_range(1.3, 2.6), rng.randf_range(1.0, 2.0), BLOOD.lerp(BLOOD_DARK, 0.3))
		_drip_t[u] = t


func _draw() -> void:
	for pool in _pools:
		var r: float = pool.r
		draw_circle(pool.pos, r * 0.7, Color(BLOOD_DARK, 0.9))
		for b: Array in pool.blobs:
			draw_circle(pool.pos + (b[0] as Vector2) * r, r * float(b[1]), Color(BLOOD_DARK, 0.88))
		draw_circle(pool.pos + Vector2(-r * 0.15, -r * 0.15), r * 0.35, Color(BLOOD, 0.5))
	for d in _decals:
		draw_colored_polygon(d.pts, d.color)


func _draw_air() -> void:
	for m in _mists:
		var k: float = m.t / m.life
		var r2: float = m.r + m.grow * sqrt(k)
		_air.draw_circle(m.pos, r2, Color(BLOOD_BRIGHT, 0.32 * (1.0 - k)))
		_air.draw_circle(m.pos, r2 * 0.6, Color(BLOOD_BRIGHT, 0.22 * (1.0 - k)))
	for p in _particles:
		var v: Vector2 = p.vel
		var tail: Vector2 = v * 0.018
		_air.draw_line(p.pos - tail, p.pos, Color(BLOOD_BRIGHT, 0.95), p.r * 1.4)
		_air.draw_circle(p.pos, p.r, Color(BLOOD_BRIGHT, 0.95))
