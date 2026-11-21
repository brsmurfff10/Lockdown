class_name Arena
extends Node2D
## Generic grid map, loaded from a map data Dictionary (see scripts/maps/).
## Builds wall collision + light occluders, an A* grid for bots, computes which
## site each area "threatens" (from walking distances), and draws itself.
## Holds the tactical map knowledge bots use: points, routes, site positions.

const CELL := 32

const FLOOR_COLOR := Color(0.17, 0.18, 0.20)
const GRID_COLOR := Color(1, 1, 1, 0.03)
const WALL_COLOR := Color(0.40, 0.42, 0.46)
const WALL_EDGE := Color(0.25, 0.26, 0.29)
const ROCK_COLOR := Color(0.27, 0.28, 0.31)
const SIDE_COLORS := [Color(0.88, 0.62, 0.30), Color(0.35, 0.60, 0.95)]

enum Threat { NONE, A, B, MID, CT, T }
const THREAT_NAMES := ["", "A", "B", "mid", "ct", "t"]

var map_name := ""
var W := 0
var H := 0
var round_time := 115.0
var tempo := 1.0 ## How much longer rotations/executes take than on the small map.

var solid := PackedByteArray()
var threat := PackedByteArray()
var astar := AStarGrid2D.new()

var sites := {}
var spawns := []
var points := {}
var routes := {}
var site_info := {}
var site_angles := {} ## site -> Array[Vector2]: spots a defender could hold that Ts can't see from the entrances.
var _floor_rects: Array = []
var _cover_rects: Array = []
## Rendered 3D art for the map (assets/maps/<name>.png, 32 px per cell, made
## with art/blender/build_map.py). Without it the map is drawn as flat cells.
var art_texture: Texture2D = null


## Call before adding to the tree.
func load_map(d: Dictionary) -> void:
	map_name = d.name
	W = d.size.x
	H = d.size.y
	round_time = float(d.get("round_time", 115.0))
	tempo = float(d.get("tempo", 1.0))
	sites = d.sites
	spawns = d.spawns
	points = d.points
	routes = d.routes
	site_info = d.site_info
	_floor_rects = d.floors
	_cover_rects = d.cover
	var art := "res://assets/maps/%s.png" % map_name.to_lower()
	art_texture = load(art) if ResourceLoader.exists(art) else null


func _ready() -> void:
	if W == 0:
		load_map(Maps.get_map("Cage"))
	_build()


func _build() -> void:
	solid.resize(W * H)
	solid.fill(1)
	for r: Rect2i in _floor_rects:
		_set_rect(r, 0)
	for r: Rect2i in _cover_rects:
		_set_rect(r, 1)
	_build_collision()
	_build_astar()
	_compute_threat()
	_compute_site_angles()
	queue_redraw()


func _set_rect(r: Rect2i, value: int) -> void:
	for y in range(maxi(r.position.y, 1), mini(r.end.y, H - 1)):
		for x in range(maxi(r.position.x, 1), mini(r.end.x, W - 1)):
			solid[y * W + x] = value


func is_solid(c: Vector2i) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= W or c.y >= H:
		return true
	return solid[c.y * W + c.x] == 1


## One rectangle shape (and light occluder) per horizontal run of wall cells
## that borders floor. Deep rock never needs collision.
func _build_collision() -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	for y in H:
		var x := 0
		while x < W:
			if not (is_solid(Vector2i(x, y)) and _touches_floor(Vector2i(x, y))):
				x += 1
				continue
			var start := x
			while x < W and is_solid(Vector2i(x, y)) and _touches_floor(Vector2i(x, y)):
				x += 1
			var shape := RectangleShape2D.new()
			shape.size = Vector2((x - start) * CELL, CELL)
			var cs := CollisionShape2D.new()
			cs.shape = shape
			cs.position = Vector2((start + (x - start) / 2.0) * CELL, (y + 0.5) * CELL)
			body.add_child(cs)
			_add_occluder(Rect2(start * CELL, y * CELL, (x - start) * CELL, CELL))


func _add_occluder(r: Rect2) -> void:
	var occ := OccluderPolygon2D.new()
	occ.polygon = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	var node := LightOccluder2D.new()
	node.occluder = occ
	add_child(node)


func _build_astar() -> void:
	astar.region = Rect2i(0, 0, W, H)
	astar.cell_size = Vector2(CELL, CELL)
	astar.offset = Vector2(CELL, CELL) / 2.0
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for y in H:
		for x in W:
			if is_solid(Vector2i(x, y)):
				astar.set_point_solid(Vector2i(x, y), true)


# --- Threat map ---------------------------------------------------------------

## Tags every floor cell with the site it leads to, by comparing walking
## distances to each site and each spawn. No hand-made regions needed.
func _compute_threat() -> void:
	var d_a := _distance_field(_rect_cells(sites.A))
	var d_b := _distance_field(_rect_cells(sites.B))
	var d_t := _distance_field(_spawn_cells(0))
	var d_ct := _distance_field(_spawn_cells(1))
	threat.resize(W * H)
	threat.fill(Threat.NONE)
	for y in H:
		for x in W:
			var i := y * W + x
			if solid[i] == 1:
				continue
			var c := Vector2i(x, y)
			var t := Threat.MID
			if (sites.A as Rect2i).grow(1).has_point(c):
				t = Threat.A
			elif (sites.B as Rect2i).grow(1).has_point(c):
				t = Threat.B
			elif d_t[i] <= 6:
				t = Threat.T
			elif d_ct[i] < d_t[i] * 0.55:
				t = Threat.CT
			elif d_a[i] < d_b[i] * 0.75:
				t = Threat.A
			elif d_b[i] < d_a[i] * 0.75:
				t = Threat.B
			threat[i] = t


func _rect_cells(r: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if not is_solid(Vector2i(x, y)):
				out.append(Vector2i(x, y))
	return out


func _spawn_cells(side: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c: Vector2i in spawns[side]:
		out.append(c)
	return out


## BFS walking distance (in cells) from any source cell.
func _distance_field(sources: Array[Vector2i]) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(W * H)
	dist.fill(1 << 28)
	var queue: Array[Vector2i] = []
	for s in sources:
		dist[s.y * W + s.x] = 0
		queue.append(s)
	var head := 0
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while head < queue.size():
		var c := queue[head]
		head += 1
		var nd := dist[c.y * W + c.x] + 1
		for d: Vector2i in dirs:
			var n := c + d
			if is_solid(n):
				continue
			var ni := n.y * W + n.x
			if dist[ni] > nd:
				dist[ni] = nd
				queue.append(n)
	return dist


# --- Queries ----------------------------------------------------------------

func world_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))


func cell_center(c: Vector2i) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * CELL


func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	return astar.get_point_path(nearest_open(world_to_cell(from)), nearest_open(world_to_cell(to)))


func nearest_open(c: Vector2i) -> Vector2i:
	if not is_solid(c):
		return c
	for radius in range(1, 8):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var n := c + Vector2i(dx, dy)
				if not is_solid(n):
					return n
	return Vector2i(W / 2, H / 2)


func spawn_points(side: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for c: Vector2i in spawns[side]:
		out.append(cell_center(c))
	return out


## World position of a named point (or a raw cell).
func pt(name_or_cell) -> Vector2:
	if name_or_cell is Vector2i:
		return cell_center(name_or_cell)
	return cell_center(points[name_or_cell])


## A named point nudged up to `spread` cells so bots don't stack single-file.
func jittered(name_or_cell, rng: RandomNumberGenerator, spread: int = 1) -> Vector2:
	var c: Vector2i = name_or_cell if name_or_cell is Vector2i else points[name_or_cell]
	for i in 6:
		var n := c + Vector2i(rng.randi_range(-spread, spread), rng.randi_range(-spread, spread))
		if not is_solid(n):
			return cell_center(n)
	return cell_center(c)


## "A", "B", or "" for a world position (plantable zone).
func site_at(p: Vector2) -> String:
	var c := world_to_cell(p)
	for key: String in sites:
		if (sites[key] as Rect2i).has_point(c):
			return key
	return ""


## Which site an area threatens: "A", "B", "mid", "ct", "t", or "".
func threat_at(p: Vector2) -> String:
	var c := world_to_cell(p)
	if c.x < 0 or c.y < 0 or c.x >= W or c.y >= H:
		return ""
	return THREAT_NAMES[threat[c.y * W + c.x]]


func region_at(p: Vector2) -> String:
	return threat_at(p)


func site_center(site: String) -> Vector2:
	var r: Rect2i = sites[site]
	return cell_center(r.position + r.size / 2)


func random_point_in_site(site: String, rng: RandomNumberGenerator) -> Vector2:
	var r: Rect2i = sites[site]
	for i in 30:
		var c := Vector2i(rng.randi_range(r.position.x, r.end.x - 1), rng.randi_range(r.position.y, r.end.y - 1))
		if not is_solid(c):
			return cell_center(c)
	return site_center(site)


func size_px() -> Vector2:
	return Vector2(W * CELL, H * CELL)


## Dev check: points on floor, plant spots in plant zones, every route walkable,
## holds can see what they watch. Returns a list of problems (empty = good).
func validate() -> Array[String]:
	var bad: Array[String] = []
	for k: String in points:
		if is_solid(points[k]):
			bad.append("point %s %s is solid" % [k, points[k]])
	for c: Vector2i in spawns[0] + spawns[1]:
		if is_solid(c):
			bad.append("spawn %s is solid" % c)
	var t_spawn := cell_center(spawns[0][0])
	var ct_spawn := cell_center(spawns[1][0])
	for rn: String in routes:
		var r: Dictionary = routes[rn]
		var chain: Array = r.via.duplicate()
		chain.append(r.stage)
		if r.entry != "":
			chain.append(r.entry)
		var prev := t_spawn
		for p in chain:
			if not points.has(p):
				bad.append("route %s: unknown point %s" % [rn, p])
				continue
			if find_path(prev, pt(p)).is_empty():
				bad.append("route %s: no path to %s" % [rn, p])
			prev = pt(p)
	for s: String in site_info:
		var info: Dictionary = site_info[s]
		for c: Vector2i in info.plant:
			if is_solid(c) or not (sites[s] as Rect2i).has_point(c):
				bad.append("site %s plant %s not on open plant zone" % [s, c])
		for e in info.ct_holds:
			if is_solid(e[0]):
				bad.append("site %s ct_hold %s solid" % [s, e[0]])
			elif not _los_cells(e[0], points[e[1]] if e[1] is String else e[1]):
				bad.append("site %s ct_hold %s can't see %s" % [s, e[0], e[1]])
		for e in info.t_cover:
			if is_solid(e[0]):
				bad.append("site %s t_cover %s solid" % [s, e[0]])
		for k in ["retake", "flank"]:
			for p in info[k]:
				if not points.has(p):
					bad.append("site %s %s: unknown point %s" % [s, k, p])
		for k in ["main_route", "alt_route", "short_route"]:
			if not routes.has(info[k]):
				bad.append("site %s %s: unknown route %s" % [s, k, info[k]])
		if find_path(ct_spawn, site_center(s)).is_empty():
			bad.append("CT spawn can't reach site %s" % s)
	for need in ["ct_spawn", "ct_mid", "mid_hold", "mid_center", "mid_entry"]:
		if not points.has(need):
			bad.append("missing required point %s" % need)
	return bad


# --- Tactical analysis ---------------------------------------------------------

## For each site: the corners and holds a defender could be sitting in that an
## attacker can't see from any entrance. Attackers clear these one by one.
func _compute_site_angles() -> void:
	site_angles.clear()
	for site: String in site_info:
		var r: Rect2i = sites[site]
		var center := r.position + r.size / 2
		var entries: Array[Vector2i] = []
		for rn: String in routes:
			var route: Dictionary = routes[rn]
			if route.get("site", "") == site and String(route.get("entry", "")) != "":
				var e: Vector2i = points[route.entry]
				if not entries.has(e):
					entries.append(e)
		var cands: Array = [] # [cell, priority]
		for h: Array in site_info[site].get("ct_holds", []):
			cands.append([h[0], -100.0])
		var area := r.grow(5)
		for y in range(area.position.y, area.end.y):
			for x in range(area.position.x, area.end.x):
				var c := Vector2i(x, y)
				if is_solid(c) or not _hugs_wall(c):
					continue
				if not _los_cells(c, center):
					continue
				var hidden := true
				for e in entries:
					if _los_cells(e, c):
						hidden = false
						break
				if hidden:
					var near := INF
					for e in entries:
						near = minf(near, Vector2(c - e).length())
					cands.append([c, near])
		cands.sort_custom(func(a: Array, b: Array) -> bool: return a[1] < b[1])
		var picked: Array[Vector2] = []
		var picked_cells: Array[Vector2i] = []
		for cand: Array in cands:
			var c: Vector2i = cand[0]
			var ok := true
			for pc in picked_cells:
				if Vector2(c - pc).length() < 4.0:
					ok = false
					break
			if ok:
				picked_cells.append(c)
				picked.append(cell_center(c))
			if picked.size() >= 6:
				break
		site_angles[site] = picked


func _hugs_wall(c: Vector2i) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if is_solid(c + d):
			return true
	return false


## Post-plant spots: can see the bomb (to stop a defuse), hidden from as many
## of the given approach points as possible, spread apart for crossfires.
func post_plant_spots(bomb: Vector2, approaches: Array[Vector2], n: int) -> Array[Vector2]:
	var bc := world_to_cell(bomb)
	var appr: Array[Vector2i] = []
	for a in approaches:
		appr.append(world_to_cell(a))
	var scored: Array = []
	for dy in range(-15, 16):
		for dx in range(-15, 16):
			var d := Vector2(dx, dy).length()
			if d < 4.0 or d > 15.0:
				continue
			var c := bc + Vector2i(dx, dy)
			if c.x < 1 or c.y < 1 or c.x >= W - 1 or c.y >= H - 1 or is_solid(c):
				continue
			if not _los_cells(c, bc):
				continue
			var exposure := 0
			for a in appr:
				if _los_cells(a, c):
					exposure += 1
			var score := exposure * 10.0 + absf(d - 9.0) * 0.4 - (2.0 if _hugs_wall(c) else 0.0)
			scored.append([c, score])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[1] < b[1])
	var out: Array[Vector2] = []
	var cells: Array[Vector2i] = []
	for s: Array in scored:
		var c: Vector2i = s[0]
		var ok := true
		for pc in cells:
			if Vector2(c - pc).length() < 5.0:
				ok = false
				break
		if ok:
			cells.append(c)
			out.append(cell_center(c))
		if out.size() >= n:
			break
	if out.is_empty():
		out.append(bomb)
	return out


## Grid line-of-sight between cell centres (for validation, before physics exists).
func _los_cells(a: Vector2i, b: Vector2i) -> bool:
	var pa := cell_center(a)
	var pb := cell_center(b)
	var steps := int(pa.distance_to(pb) / 8.0) + 1
	for i in steps + 1:
		var p := pa.lerp(pb, float(i) / steps)
		if is_solid(world_to_cell(p)):
			return false
	return true


# --- Drawing ----------------------------------------------------------------

func _draw() -> void:
	# Beyond the map edge (the camera can look past it now): plain dark ground.
	draw_rect(Rect2(Vector2(-4000, -4000), size_px() + Vector2(8000, 8000)), Color(0.055, 0.058, 0.065))
	if art_texture != null:
		draw_texture_rect(art_texture, Rect2(Vector2.ZERO, size_px()), false)
		for side in 2:
			for c: Vector2i in spawns[side]:
				draw_rect(Rect2(Vector2(c) * CELL, Vector2(CELL, CELL)).grow(4), Color(SIDE_COLORS[side], 0.08))
		for key: String in sites:
			var sr: Rect2i = sites[key]
			draw_rect(Rect2(Vector2(sr.position) * CELL, Vector2(sr.size) * CELL), Color(0.9, 0.25, 0.25, 0.25), false, 2.0)
		return
	draw_rect(Rect2(Vector2.ZERO, size_px()), ROCK_COLOR)
	for y in H:
		for x in W:
			if not is_solid(Vector2i(x, y)):
				var r := Rect2(x * CELL, y * CELL, CELL, CELL)
				draw_rect(r, FLOOR_COLOR)
				draw_rect(r, GRID_COLOR, false, 1.0)

	for side in 2:
		for c: Vector2i in spawns[side]:
			draw_rect(Rect2(Vector2(c) * CELL, Vector2(CELL, CELL)).grow(4), Color(SIDE_COLORS[side], 0.10))

	var font := ThemeDB.fallback_font
	for key: String in sites:
		var r: Rect2i = sites[key]
		var rect := Rect2(Vector2(r.position) * CELL, Vector2(r.size) * CELL)
		draw_rect(rect, Color(0.9, 0.2, 0.2, 0.07))
		draw_rect(rect, Color(0.9, 0.25, 0.25, 0.35), false, 2.0)
		draw_string(font, rect.get_center() + Vector2(-60, 40), key, HORIZONTAL_ALIGNMENT_CENTER, 120, 110, Color(0.9, 0.25, 0.25, 0.18))

	for y in H:
		for x in W:
			var c := Vector2i(x, y)
			if is_solid(c) and _touches_floor(c):
				var r := Rect2(x * CELL, y * CELL, CELL, CELL)
				draw_rect(r, WALL_EDGE)
				draw_rect(r.grow(-2), WALL_COLOR)


func _touches_floor(c: Vector2i) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
		var n: Vector2i = c + d
		if n.x >= 0 and n.y >= 0 and n.x < W and n.y < H and not is_solid(n):
			return true
	return false
