class_name Utility
extends Node2D
## Grenades: flashbang, smoke, frag (HE) and molotov (incendiary for CTs).
## Thrown grenades slide along the floor with drag, bounce off walls, and go
## off when the fuse ends (a fuse tuned so they stop about where you aimed).
##  - Flash: blinds everyone with line of sight, by distance and facing.
##    Teammates of the thrower expect it and get much less.
##  - Smoke: a cloud that blocks vision and line of sight for 16s.
##  - Frag: blast damage with line of sight (armor helps).
##  - Molotov: fire on the ground for 7s; smoke puts it out, bots wait it out.

const KINDS := ["flash", "smoke", "frag", "molotov"]
const MAX_OF := {"flash": 2, "smoke": 1, "frag": 1, "molotov": 1}
const MAX_TOTAL := 4
const MAX_THROW := 720.0
const DRAG := 2.4 ## Velocity decays by exp(-DRAG * t).
const FUSE := {"flash": 1.3, "smoke": 1.6, "frag": 1.6, "molotov": 1.1}
const FLASH_RANGE := 1100.0
const FRAG_RADIUS := 330.0
const FRAG_DAMAGE := 98.0
const FIRE_RADIUS := 105.0
const FIRE_TIME := 7.0
const FIRE_DPS := 38.0
const SMOKE_RADIUS := 135.0
const SMOKE_TIME := 16.0
const SMOKE_BLOOM := 0.6
const COLORS := {"flash": Color(0.95, 0.95, 0.85), "smoke": Color(0.6, 0.65, 0.7), "frag": Color(0.45, 0.6, 0.35), "molotov": Color(1.0, 0.5, 0.2)}
const SHORT := {"flash": "FL", "smoke": "SM", "frag": "HE", "molotov": "MO"}
const WALL_MASK := 1

var m ## The Match.
var projectiles: Array[Dictionary] = [] ## {kind, pos, vel, t, owner, side}
var fires: Array[Dictionary] = [] ## {pos, t, owner}
var smokes: Array[Dictionary] = [] ## {pos, age}
var _fx: Array[Dictionary] = [] ## {kind, pos, t}
var _smoke_view: Node2D
var _crackle_t := 0.0
var thrown := {} ## "T flash" -> count (dev stats).
var _next_id := 0 ## Projectile ids (bots remember which flashes they've reacted to).


static func price(kind: String, side: int) -> int:
	match kind:
		"flash":
			return 200
		"smoke":
			return 300
		"frag":
			return 300
		"molotov":
			return 400 if side == 0 else 500
	return 0


static func display_name(kind: String, side: int) -> String:
	match kind:
		"flash":
			return "Flashbang"
		"smoke":
			return "Smoke"
		"frag":
			return "Frag Grenade"
		"molotov":
			return "Molotov" if side == 0 else "Incendiary"
	return kind


static func total(grenades: Dictionary) -> int:
	var n := 0
	for k in grenades:
		n += int(grenades[k])
	return n


func _init(p_match) -> void:
	m = p_match


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS # Grenade sprites.
	_smoke_view = Node2D.new()
	_smoke_view.z_index = 10 # Smoke covers players; fire stays under them.
	_smoke_view.draw.connect(_draw_smokes)
	add_child(_smoke_view)


func clear() -> void:
	projectiles.clear()
	fires.clear()
	smokes.clear()
	_fx.clear()
	queue_redraw()
	_smoke_view.queue_redraw()


func throw(u: Unit, kind: String, target: Vector2) -> bool:
	if not u.alive or int(u.grenades.get(kind, 0)) <= 0 or u.is_drawing():
		return false
	u.grenades[kind] = int(u.grenades[kind]) - 1
	if u.grenades[kind] <= 0:
		u.grenades.erase(kind)
	var to := target - u.global_position
	var dir := to.normalized() if to.length() > 1.0 else u.aim_dir
	var dist := clampf(to.length(), 40.0, MAX_THROW)
	var fuse: float = FUSE[kind]
	# Distance covered with drag: v0 / DRAG * (1 - e^(-DRAG * fuse)).
	var v0 := dist * DRAG / (1.0 - exp(-DRAG * fuse))
	var start := u.global_position + dir * (Unit.RADIUS + 4.0)
	if not m.has_wall_los(u.global_position, start):
		start = u.global_position
	_next_id += 1
	projectiles.append({"kind": kind, "pos": start, "vel": dir * v0, "t": fuse, "owner": u, "side": u.side, "id": _next_id})
	u.aim_dir = dir
	u.on_threw(kind)
	var key := "%s %s" % ["T" if u.side == 0 else "CT", kind]
	thrown[key] = int(thrown.get(key, 0)) + 1
	m.sfx.play("grenade_bounce", u.global_position, -12.0, 0.2)
	return true


## Smoke between two points (or either point inside a cloud) blocks sight,
## except through holes: a frag blows a big gap for a few seconds, bullets
## punch small ones that a spray widens into a lane. Both fill back in.
func blocks(from: Vector2, to: Vector2) -> bool:
	for s in smokes:
		var r := _smoke_radius(s)
		if r < 20.0:
			continue
		var c: Vector2 = s.pos
		var inside := from.distance_to(c) < r or to.distance_to(c) < r
		if inside:
			if from.distance_to(to) <= 48.0:
				continue
		elif Geometry2D.segment_intersects_circle(from, to, c, r) < 0.0:
			continue
		var grid: PackedByteArray = s.get("grid", PackedByteArray())
		if grid.is_empty() or _chord_blocked(from, to, c, r, s):
			return true
	return false


const GRID_CELL := 8.0 ## Cleared-cell grid over each cloud (rebuilt once a frame while it has holes).


## The part of from->to inside the cloud, sampled every 8 px against the
## cloud's cleared-cell grid: any sample not cleared blocks the view.
func _chord_blocked(a: Vector2, b: Vector2, c: Vector2, r: float, s: Dictionary) -> bool:
	var ab := b - a
	var L := ab.length()
	var grid: PackedByteArray = s.grid
	var o: Vector2 = s.grid_o
	var gn: int = s.grid_n
	if L < 0.001:
		return not _grid_clear(grid, o, gn, a)
	var dirn := ab / L
	var proj := (c - a).dot(dirn)
	var off2 := (c - a).length_squared() - proj * proj
	if off2 >= r * r:
		return false
	var half := sqrt(r * r - off2)
	var t0 := clampf(proj - half, 0.0, L)
	var t1 := clampf(proj + half, 0.0, L)
	var n := maxi(2, ceili((t1 - t0) / GRID_CELL))
	for i in n + 1:
		if not _grid_clear(grid, o, gn, a + dirn * lerpf(t0, t1, float(i) / n)):
			return true
	return false


static func _grid_clear(grid: PackedByteArray, o: Vector2, gn: int, p: Vector2) -> bool:
	var gx := int((p.x - o.x) / GRID_CELL)
	var gy := int((p.y - o.y) / GRID_CELL)
	if gx < 0 or gy < 0 or gx >= gn or gy >= gn:
		return true # Outside the cloud's square: not smoke.
	return grid[gy * gn + gx] != 0


## Marks the cells inside any hole as clear (1).
func _rebuild_grid(s: Dictionary) -> void:
	var holes: Array = s.holes
	if holes.is_empty():
		s.erase("grid")
		return
	var r := SMOKE_RADIUS + 4.0
	var gn := ceili(r * 2.0 / GRID_CELL)
	var o: Vector2 = (s.pos as Vector2) - Vector2(r, r)
	var grid := PackedByteArray()
	grid.resize(gn * gn)
	for h: Dictionary in holes:
		var hr := hole_radius(h)
		if hr < 1.0:
			continue
		var hp: Vector2 = h.pos
		var x0 := maxi(0, int((hp.x - hr - o.x) / GRID_CELL))
		var x1 := mini(gn - 1, int((hp.x + hr - o.x) / GRID_CELL))
		var y0 := maxi(0, int((hp.y - hr - o.y) / GRID_CELL))
		var y1 := mini(gn - 1, int((hp.y + hr - o.y) / GRID_CELL))
		var hr2 := hr * hr
		for gy in range(y0, y1 + 1):
			var cy := o.y + (gy + 0.5) * GRID_CELL - hp.y
			for gx in range(x0, x1 + 1):
				var cx := o.x + (gx + 0.5) * GRID_CELL - hp.x
				if cx * cx + cy * cy <= hr2:
					grid[gy * gn + gx] = 1
	s["grid"] = grid
	s["grid_o"] = o
	s["grid_n"] = gn


static func hole_radius(h: Dictionary) -> float:
	return float(h.r) * clampf(float(h.t) / 0.8, 0.0, 1.0) # Refills over the last 0.8 s.


func _in_hole(p: Vector2, holes: Array) -> bool:
	for h: Dictionary in holes:
		if p.distance_to(h.pos) < hole_radius(h):
			return true
	return false


const BULLET_HOLE_R := 15.0
const BULLET_HOLE_T := 1.6
const FRAG_HOLE_T := 3.5
const MAX_HOLES := 90


## A bullet flew from `from` to `to`: punch a line of small holes through any cloud it crossed.
func on_bullet(from: Vector2, to: Vector2) -> void:
	for s in smokes:
		var r := _smoke_radius(s)
		if r < 20.0:
			continue
		var c: Vector2 = s.pos
		var ab := to - from
		var L := ab.length()
		if L < 1.0:
			continue
		var dirn := ab / L
		var proj := (c - from).dot(dirn)
		var off2 := (c - from).length_squared() - proj * proj
		if off2 >= r * r:
			continue
		var half := sqrt(r * r - off2)
		var t0 := clampf(proj - half, 0.0, L)
		var t1 := clampf(proj + half, 0.0, L)
		if t1 - t0 < 4.0:
			continue
		var holes: Array = s.get("holes", [])
		var t := t0
		while t <= t1:
			var hp := from + dirn * t
			# A spray down the same line refreshes the holes it already made instead of piling up new ones.
			var merged := false
			for h: Dictionary in holes:
				if h.get("bullet", false) and hp.distance_squared_to(h.pos) < 100.0:
					h.t = BULLET_HOLE_T
					h["hits"] = int(h.get("hits", 1)) + 1
					merged = true
					break
			if not merged:
				holes.append({"pos": hp, "r": BULLET_HOLE_R, "t": BULLET_HOLE_T, "bullet": true})
			t += BULLET_HOLE_R * 1.1
		while holes.size() > MAX_HOLES:
			holes.pop_front()
		s["holes"] = holes


## How deep inside a smoke `p` is: 0 outside (or in a cleared hole), 1 well inside.
func smoke_depth(p: Vector2) -> float:
	var best := 0.0
	for s in smokes:
		var r := _smoke_radius(s)
		if r < 20.0:
			continue
		var d := p.distance_to(s.pos)
		if d >= r:
			continue
		var grid: PackedByteArray = s.get("grid", PackedByteArray())
		if not grid.is_empty() and _grid_clear(grid, s.grid_o, s.grid_n, p):
			continue
		best = maxf(best, clampf((r - d) / (r * 0.35), 0.0, 1.0))
	return best


func in_smoke(p: Vector2, margin: float = 0.0) -> bool:
	for s in smokes:
		if p.distance_to(s.pos) < _smoke_radius(s) + margin:
			return true
	return false


func in_fire(p: Vector2, margin: float = 0.0) -> bool:
	for f in fires:
		if p.distance_to(f.pos) < FIRE_RADIUS + margin:
			return true
	return false


func _smoke_radius(s: Dictionary) -> float:
	var age: float = s.age
	var grow := clampf(age / SMOKE_BLOOM, 0.0, 1.0)
	var shrink := clampf((SMOKE_TIME - age) / 1.5, 0.0, 1.0)
	return SMOKE_RADIUS * grow * (0.6 + 0.4 * shrink)


func _physics_process(delta: float) -> void:
	if projectiles.is_empty() and fires.is_empty() and smokes.is_empty() and _fx.is_empty():
		return
	var space := get_world_2d().direct_space_state
	for g in projectiles.duplicate():
		var step: Vector2 = g.vel * delta
		if step.length() > 0.5:
			var q := PhysicsRayQueryParameters2D.create(g.pos, g.pos + step, WALL_MASK)
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				g.pos += step
			else:
				g.pos = hit.position + hit.normal * 2.0
				g.vel = (g.vel as Vector2).bounce(hit.normal) * 0.45
				m.sfx.play("grenade_bounce", g.pos, -8.0, 0.2)
		g.vel *= exp(-DRAG * delta)
		g["spin"] = float(g.get("spin", 0.0)) + (g.vel as Vector2).length() * delta * 0.05
		g.t -= delta
		if g.t <= 0.0:
			projectiles.erase(g)
			_detonate(g)
	for s in smokes.duplicate():
		s.age += delta
		if s.age >= SMOKE_TIME:
			smokes.erase(s)
			continue
		var holes: Array = s.get("holes", [])
		if not holes.is_empty():
			for h: Dictionary in holes:
				h.t -= delta
			s["holes"] = holes.filter(func(h: Dictionary) -> bool: return float(h.t) > 0.0)
			_rebuild_grid(s)
		elif s.has("grid"):
			s.erase("grid")
	for f in fires.duplicate():
		f.t -= delta
		if f.t <= 0.0:
			fires.erase(f)
			continue
		for u: Unit in m.units:
			if u.alive and u.global_position.distance_to(f.pos) < FIRE_RADIUS:
				var owner: Unit = f.owner if is_instance_valid(f.owner) else null
				var mult := 0.5 if owner != null and owner.side == u.side else 1.0
				var dealt := u.take_damage(FIRE_DPS * mult * delta, owner)
				if owner != null and owner.side != u.side:
					m.register_damage(owner, dealt)
	if not fires.is_empty():
		_crackle_t -= delta
		if _crackle_t <= 0.0:
			_crackle_t = 0.5
			for f in fires:
				m.sfx.play("fire_crackle", f.pos, -6.0, 0.15)
	for fx in _fx.duplicate():
		fx.t -= delta
		if fx.t <= 0.0:
			_fx.erase(fx)
	queue_redraw()
	_smoke_view.queue_redraw()


func _detonate(g: Dictionary) -> void:
	var pos: Vector2 = g.pos
	var owner: Unit = g.owner if is_instance_valid(g.owner) else null
	if m.tactics != null:
		m.tactics.on_utility(String(g.kind), pos, int(g.side))
	match String(g.kind):
		"flash":
			m.sfx.play("grenade_flash", pos, 0.0, 0.05)
			_fx.append({"kind": "flash", "pos": pos, "t": 0.18})
			m.vfx.flash_light(pos, 1100.0, 5.0, 0.3, Color(1.0, 1.0, 0.95))
			for u: Unit in m.units:
				if not u.alive:
					continue
				var d := u.global_position.distance_to(pos)
				if d > FLASH_RANGE or not m.has_line_of_sight(pos, u.global_position):
					continue
				var facing := u.aim_dir.dot((pos - u.global_position).normalized()) if d > 1.0 else 1.0
				# Looking at it: full. Side-on still hurts; turned fully away takes the least.
				var fac := 1.0 if facing > 0.5 else (0.75 if facing > 0.0 else (0.4 if facing > -0.5 else 0.15))
				var strength := fac * (1.0 - pow(d / FLASH_RANGE, 1.6))
				if u.side == int(g.side):
					strength *= 0.5 # Their own flash: they knew it was coming.
				u.blind(0.2 + 4.2 * strength)
		"frag":
			m.sfx.play("grenade_frag", pos, 2.0, 0.05)
			_fx.append({"kind": "frag", "pos": pos, "t": 0.45})
			m.vfx.explode(pos, 110.0)
			for s in smokes:
				var sr := _smoke_radius(s)
				if (s.pos as Vector2).distance_to(pos) < sr + 90.0:
					# The blast clears a big gap in the cloud for a few seconds.
					var at: Vector2 = (s.pos as Vector2) + (pos - s.pos).limit_length(sr * 0.5)
					(s.holes as Array).append({"pos": at, "r": SMOKE_RADIUS * 0.85, "t": FRAG_HOLE_T})
			for u: Unit in m.units:
				if not u.alive:
					continue
				var d := u.global_position.distance_to(pos)
				if d > FRAG_RADIUS or not m.has_wall_los(pos, u.global_position):
					continue
				var dmg := FRAG_DAMAGE * pow(1.0 - d / FRAG_RADIUS, 1.3)
				if owner != null and owner.side == u.side:
					dmg *= 0.5
				var dealt := u.take_damage(dmg, owner)
				m.blood.hit(u, u.global_position, u.global_position - pos, dealt, not u.alive)
				if owner != null and owner.side != u.side:
					m.register_damage(owner, dealt)
		"smoke":
			m.sfx.play("grenade_smoke", pos, -2.0, 0.05)
			smokes.append({"pos": pos, "age": 0.0, "holes": []})
			for f in fires.duplicate():
				if (f.pos as Vector2).distance_to(pos) < SMOKE_RADIUS + FIRE_RADIUS * 0.4:
					fires.erase(f) # Smoke puts fire out.
		"molotov":
			m.sfx.play("grenade_molotov", pos, -1.0, 0.05)
			for s in smokes:
				if (s.pos as Vector2).distance_to(pos) < _smoke_radius(s):
					return # Lands in smoke: fizzles out.
			fires.append({"pos": pos, "t": FIRE_TIME, "owner": owner})


func _draw() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var art := VfxLayer.available() # Rendered fire/explosions live in the VfxLayer.
	for f in fires:
		if art:
			break
		var fade := clampf(float(f.t) / 1.0, 0.0, 1.0)
		var p: Vector2 = f.pos
		draw_circle(p, FIRE_RADIUS, Color(1.0, 0.35, 0.05, 0.28 * fade))
		for i in 9:
			var a := float(i) * 2.4 + now * 1.3
			var r := FIRE_RADIUS * (0.25 + 0.55 * fmod(float(i) * 0.37, 1.0))
			var o := Vector2(cos(a), sin(a)) * r
			var flick := 0.6 + 0.4 * sin(now * 9.0 + i * 1.7)
			draw_circle(p + o, 14.0 + 8.0 * flick, Color(1.0, 0.55 + 0.25 * flick, 0.1, 0.45 * fade))
		draw_arc(p, FIRE_RADIUS, 0, TAU, 40, Color(1.0, 0.45, 0.1, 0.6 * fade), 2.0)
	for g in projectiles:
		# Tumbling through the air: spin slows as it loses speed.
		var spin := float(g.get("spin", 0.0))
		if not GunArt.draw_grenade(self, String(g.kind), int(g.side), g.pos, spin, GunArt.GRENADE_THROWN_PX):
			var c: Color = COLORS[g.kind]
			draw_circle(g.pos, 5.0, Color(0, 0, 0, 0.8))
			draw_circle(g.pos, 3.5, c)
	for fx in _fx:
		if fx.kind == "frag":
			if art:
				continue
			var k := 1.0 - float(fx.t) / 0.45
			draw_circle(fx.pos, FRAG_RADIUS * (0.2 + 0.8 * k), Color(1.0, 0.6, 0.2, 0.35 * (1.0 - k)))
			draw_arc(fx.pos, FRAG_RADIUS * (0.2 + 0.8 * k), 0, TAU, 40, Color(1.0, 0.8, 0.4, 0.7 * (1.0 - k)), 3.0)
		elif fx.kind == "flash":
			draw_circle(fx.pos, 60.0, Color(1, 1, 1, float(fx.t) / 0.18))


func _draw_smokes() -> void:
	if VfxLayer.available():
		return # Rendered smoke clouds live in the VfxLayer.
	for s in smokes:
		var r := _smoke_radius(s)
		if r <= 1.0:
			continue
		var p: Vector2 = s.pos
		var fade := clampf((SMOKE_TIME - float(s.age)) / 1.5, 0.0, 1.0)
		_smoke_view.draw_circle(p, r, Color(0.62, 0.64, 0.68, 0.96 * fade))
		for i in 7:
			var a := float(i) * TAU / 7.0 + float(s.age) * 0.08
			_smoke_view.draw_circle(p + Vector2(cos(a), sin(a)) * r * 0.55, r * 0.5, Color(0.7, 0.72, 0.76, 0.5 * fade))
