class_name VfxLayer
extends Node2D
## Realistic explosion / smoke / fire visuals from rendered sheets in
## assets/vfx (made in Blender from Mantaflow sims):
##   explosion_sheet.png  8x8 flipbook: fireball turning into rolling smoke
##   smoke_puffs.png      4x4 static puff variants, stacked into smoke clouds
##   fire_sheet.png       8x8 looping flames, tiled over a burning area
##   scorch.png           burn mark left on the ground
## Smoke and fire drawing is stateless (seeded by position and age) so the
## replay draws exactly the same clouds. Missing sheets: callers fall back to
## the old circles (draw_* return false).
##
## Layers: ground (scorch, z -6, under blood) / fire (flames, z -2,
## under players; alpha from brightness, normal blend) / air (explosions over players, z 9) / smoke (z 10, hides players).

const DIR := "res://assets/vfx/"
const EXPLOSION := {"file": "explosion_sheet.png", "grid": Vector2i(8, 8), "frames": 64, "fps": 30.0, "extent": 0.84}
const PUFFS := {"file": "smoke_puffs.png", "grid": Vector2i(4, 4)}
const FIRE := {"file": "fire_sheet.png", "grid": Vector2i(8, 8), "frames": 64, "fps": 26.0, "extent": 0.56} ## extent = solid flame
const SCORCH := "scorch.png"
const MAX_SCORCH := 40

static var _tex := {}

var match_node: Node
var _explosions: Array[Dictionary] = [] ## {pos, t, radius}
var _scorch: Array[Dictionary] = [] ## {pos, r, rot}
var _lights: Array[Dictionary] = [] ## {light, t, life, energy}
var _ground: Node2D
var _fire: Node2D
var _air: Node2D
var _smoke: Node2D
var _light_tex: Texture2D


static func tex(file: String) -> Texture2D:
	if not _tex.has(file):
		var p := DIR + file
		_tex[file] = load(p) if ResourceLoader.exists(p) else null
	return _tex[file]


static func available() -> bool:
	return tex(EXPLOSION.file) != null and tex(PUFFS.file) != null and tex(FIRE.file) != null


func _init(p_match: Node) -> void:
	match_node = p_match
	_ground = _layer(-6, _draw_ground)
	_fire = _layer(-2, _draw_fire_layer)
	_air = _layer(9, _draw_air)
	_smoke = _layer(10, _draw_smoke_layer)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 256
	gt.height = 256
	_light_tex = gt


func _layer(z: int, fn: Callable) -> Node2D:
	var n := Node2D.new()
	n.z_as_relative = false
	n.z_index = z
	n.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	n.draw.connect(fn)
	add_child(n)
	return n


func clear() -> void:
	_explosions.clear()
	_scorch.clear()
	for l in _lights:
		(l.light as Node).queue_free()
	_lights.clear()
	for n in [_ground, _fire, _air, _smoke]:
		(n as Node2D).queue_redraw()


## A grenade or bomb going off at `pos`; `radius` is the visual fireball radius.
func explode(pos: Vector2, radius: float, big: bool = false) -> void:
	_explosions.append({"pos": pos, "t": 0.0, "radius": radius, "rot": randf() * TAU})
	add_scorch(pos, radius * (0.55 if big else 0.42))
	flash_light(pos, radius * (2.6 if big else 2.2), 1.5 if big else 1.1, 0.5 if big else 0.35, Color(1.0, 0.7, 0.4))
	_sparks(pos, radius, big)


func add_scorch(pos: Vector2, r: float) -> void:
	_scorch.append({"pos": pos, "r": r, "rot": randf() * TAU})
	if _scorch.size() > MAX_SCORCH:
		_scorch.remove_at(0)
	_ground.queue_redraw()


## A short burst of light that lights up the dark (works with the fog's CanvasModulate).
func flash_light(pos: Vector2, size: float, energy: float, life: float, col: Color) -> void:
	var l := PointLight2D.new()
	l.texture = _light_tex
	l.texture_scale = size / 256.0 * 2.0
	l.energy = energy
	l.color = col
	l.global_position = pos
	l.blend_mode = Light2D.BLEND_MODE_ADD
	add_child(l)
	_lights.append({"light": l, "t": 0.0, "life": life, "energy": energy})


func _sparks(pos: Vector2, radius: float, big: bool) -> void:
	var p := CPUParticles2D.new()
	p.z_as_relative = false
	p.z_index = 9
	p.global_position = pos
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 60 if big else 34
	p.lifetime = 0.55 if big else 0.4
	p.direction = Vector2.RIGHT
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = radius * 2.0
	p.initial_velocity_max = radius * (4.5 if big else 3.6)
	p.damping_min = radius * 2.0
	p.damping_max = radius * 4.0
	p.scale_amount_min = 1.2
	p.scale_amount_max = 2.6
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.95, 0.7, 1.0))
	ramp.add_point(0.4, Color(1.0, 0.6, 0.2, 1.0))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.5, 0.15, 0.05, 0.0))
	p.color_ramp = ramp
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = mat
	add_child(p)
	p.emitting = true
	get_tree().create_timer(p.lifetime + 0.2).timeout.connect(p.queue_free)


func _process(delta: float) -> void:
	for e in _explosions:
		e.t += delta
	_explosions = _explosions.filter(func(e: Dictionary) -> bool: return e.t * EXPLOSION.fps < EXPLOSION.frames)
	for l in _lights:
		l.t += delta
		var k: float = clampf(l.t / l.life, 0.0, 1.0)
		(l.light as PointLight2D).energy = l.energy * pow(1.0 - k, 2.0)
		if k >= 1.0:
			(l.light as Node).queue_free()
	_lights = _lights.filter(func(l: Dictionary) -> bool: return l.t < l.life)
	_update_fire_lights()
	_fire.queue_redraw()
	_air.queue_redraw()
	_smoke.queue_redraw()


# --- Fire lights: one flickering light per burning area -----------------------------

var _fire_lights := {} ## Vector2 (fire pos) -> PointLight2D


func _update_fire_lights() -> void:
	var u = match_node.utility if match_node != null else null
	var live := {}
	if u != null and available():
		var now := Time.get_ticks_msec() / 1000.0
		for f: Dictionary in u.fires:
			var key: Vector2 = f.pos
			live[key] = true
			if not _fire_lights.has(key):
				var l := PointLight2D.new()
				l.texture = _light_tex
				l.texture_scale = Utility.FIRE_RADIUS * 3.2 / 256.0 * 2.0
				l.color = Color(1.0, 0.55, 0.2)
				l.global_position = key
				add_child(l)
				_fire_lights[key] = l
			var fade := clampf(float(f.t) / 1.0, 0.0, 1.0)
			(_fire_lights[key] as PointLight2D).energy = (0.9 + 0.25 * sin(now * 11.0 + key.x) + 0.15 * sin(now * 23.0)) * fade
	for key in _fire_lights.keys():
		if not live.has(key):
			(_fire_lights[key] as Node).queue_free()
			_fire_lights.erase(key)


# --- Drawing ------------------------------------------------------------------------

func _draw_ground() -> void:
	var sc := tex(SCORCH)
	var u = match_node.utility if match_node != null else null
	if sc == null:
		return
	for s in _scorch:
		_draw_centered(_ground, sc, s.pos, Vector2.ONE * s.r * 2.0, s.rot, Color(1, 1, 1, 0.85))
	if u != null:
		for f: Dictionary in u.fires: # Ground blackens under a fire as it burns.
			var k := clampf((Utility.FIRE_TIME - float(f.t)) / 2.5, 0.0, 1.0)
			_draw_centered(_ground, sc, f.pos, Vector2.ONE * Utility.FIRE_RADIUS * 2.3, float(hash(f.pos) % 628) / 100.0, Color(1, 1, 1, 0.8 * k))


func _draw_fire_layer() -> void:
	var u = match_node.utility if match_node != null else null
	if u == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	for f: Dictionary in u.fires:
		draw_fire(_fire, f.pos, Utility.FIRE_RADIUS, now, clampf(float(f.t) / 1.0, 0.0, 1.0))


func _draw_air() -> void:
	var sheet := tex(EXPLOSION.file)
	if sheet == null:
		return
	for e in _explosions:
		var frame := int(e.t * EXPLOSION.fps)
		var size: float = e.radius * 2.0 / float(EXPLOSION.extent)
		_draw_frame(_air, sheet, EXPLOSION.grid, frame, e.pos, Vector2.ONE * size, e.rot, Color.WHITE)


func _draw_smoke_layer() -> void:
	var u = match_node.utility if match_node != null else null
	if u == null:
		return
	for s: Dictionary in u.smokes:
		var r: float = u._smoke_radius(s)
		var fade := clampf((Utility.SMOKE_TIME - float(s.age)) / 1.5, 0.0, 1.0)
		var you: Vector2 = Vector2.INF
		var uu = match_node.user_unit
		if uu != null and is_instance_valid(uu) and uu.alive and not Game.autoplay and not match_node.is_spectating():
			you = uu.global_position
		draw_smoke(_smoke, s.pos, r, float(s.age), fade, s.get("holes", []), you)


## A smoke-grenade cloud of stacked puffs, slowly turning and drifting.
## Stateless: the same (pos, age) always draws the same cloud.
## `holes` (Utility smoke holes) thin the cloud out where a frag or bullets cleared it.
## `you`: the player's position when standing in it: puffs right around them thin out a little.
static func draw_smoke(ci: CanvasItem, pos: Vector2, radius: float, age: float, fade: float = 1.0, holes: Array = [], you: Vector2 = Vector2.INF) -> bool:
	var sheet := tex(PUFFS.file)
	if sheet == null or radius <= 1.0:
		return sheet != null
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(pos))
	# A soft solid core guarantees the cloud hides players (in tiles when holes need to show through).
	var core := radius * 0.72
	if holes.is_empty():
		ci.draw_circle(pos, core, Color(0.6, 0.62, 0.65, 0.55 * fade))
	else:
		var step := core * 0.2
		var gy := -core
		while gy <= core:
			var gx := -core
			while gx <= core:
				if Vector2(gx, gy).length() <= core:
					var q := pos + Vector2(gx, gy)
					var clear := _hole_clear(q, step * 0.6, holes)
					if clear < 0.95:
						ci.draw_circle(q, step * 0.62, Color(0.6, 0.62, 0.65, 0.3 * fade * (1.0 - clear)))
				gx += step
			gy += step
	var n := 30
	for i in n:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * radius * 0.78
		var drift := Vector2.from_angle(a + age * 0.05) * (d + age * 0.6)
		var spin := (rng.randf() - 0.5) * 0.25 * age + rng.randf() * TAU
		var size := radius * rng.randf_range(0.75, 1.15)
		var shade := rng.randf_range(0.82, 1.0)
		var variant := rng.randi() % (PUFFS.grid.x * PUFFS.grid.y)
		var at := pos + drift.limit_length(radius * 0.8)
		var alpha := 0.95 * fade
		if you != Vector2.INF and at.distance_to(you) < size * 0.45:
			alpha *= lerpf(0.35, 1.0, at.distance_to(you) / (size * 0.45))
		if not holes.is_empty():
			alpha *= 1.0 - _hole_clear(at, size * 0.3, holes)
			if alpha < 0.02:
				continue
		_draw_frame(ci, sheet, PUFFS.grid, variant, at, Vector2.ONE * size, spin, Color(shade, shade, shade * 1.02, alpha))
	return true


## How cleared (0..1) the area of radius `r` around `p` is: a big frag gap
## clears it outright, a lane of bullet holes thins it with every hole.
static func _hole_clear(p: Vector2, r: float, holes: Array) -> float:
	var clear := 0.0
	var bullets := 0.0
	for h: Dictionary in holes:
		var hr := Utility.hole_radius(h)
		var d := p.distance_to(h.pos)
		if h.get("bullet", false):
			if d < r + hr:
				bullets += minf(float(h.get("hits", 1)), 3.0)
		else:
			clear = maxf(clear, clampf((hr + r * 0.5 - d) / maxf(r, 1.0), 0.0, 1.0))
	return clampf(maxf(clear, bullets * 0.09), 0.0, 1.0 if clear >= 0.99 else 0.9)


## A burning patch: looping flame flipbooks tiled over the area, offset in time.
static func draw_fire(ci: CanvasItem, pos: Vector2, radius: float, now: float, fade: float = 1.0) -> bool:
	var sheet := tex(FIRE.file)
	if sheet == null:
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(pos)) + 7
	var n := 16
	for i in n:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * radius * 0.8
		var size := rng.randf_range(140.0, 180.0) * radius / 105.0 # Frames ~150 px, overlapping (solid flame is 56% of a frame).
		var frame := int((now + rng.randf() * 10.0) * FIRE.fps * rng.randf_range(0.85, 1.15)) % int(FIRE.frames)
		_draw_frame(ci, sheet, FIRE.grid, frame, pos + Vector2.from_angle(a) * d, Vector2.ONE * size, rng.randf() * TAU,
			Color(1, 1, 1, fade))
	return true


static func _draw_frame(ci: CanvasItem, sheet: Texture2D, grid: Vector2i, frame: int, pos: Vector2, size: Vector2, rot: float, col: Color) -> void:
	var fs := sheet.get_size() / Vector2(grid)
	var src := Rect2(Vector2(frame % grid.x, (frame / grid.x) % grid.y) * fs, fs)
	ci.draw_set_transform_matrix(Transform2D(rot, pos))
	ci.draw_texture_rect_region(sheet, Rect2(-size * 0.5, size), src, col)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


static func _draw_centered(ci: CanvasItem, t: Texture2D, pos: Vector2, size: Vector2, rot: float, col: Color) -> void:
	ci.draw_set_transform_matrix(Transform2D(rot, pos))
	ci.draw_texture_rect(t, Rect2(-size * 0.5, size), false, col)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
