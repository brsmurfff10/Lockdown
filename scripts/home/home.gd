class_name Home
extends Node2D
## Your place (My Player): a top-down home you walk around. Layouts come from
## data/homes/<id>.json (written by art/homes/layouts.py), art from
## assets/homes/<id>.png (the shell) and assets/homes/props/<kind>.png (one
## sprite per furniture kind, drawn at its cell rect and rotation). Furniture
## you use with E (bed, PC, TV, kitchen, ...) calls Lifestyle.act(); pieces
## that need a purchase (studio, trophy cabinet, gym, cars...) only appear
## once you own them. Game.home_tour set = viewing a property before buying.

const CELL := 32.0
const ART_PPC := 64.0 ## Pixels per cell in the renders.
const SPEED := 150.0
const RADIUS := 10.0
const REACH := 26.0
const STRIDE_TIME := 0.36 ## Seconds between footsteps at walking speed.
const BODY_SCALE := 1.4 ## People drawn a bit bigger than true scale so they read next to furniture.
const DATA_DIR := "res://data/homes/"
const ART_DIR := "res://assets/homes/"
const WALK := ".,~_mdgsD"
const FLOOR_COLORS := {".": Color("6b4f36"), ",": Color("b9bcc0"), "~": Color("4a5a78"), "_": Color("55585e"), "m": Color("d8d4cc"),
	"d": Color("8a6440"), "g": Color("3f6b33"), "s": Color("8e8a80"), "w": Color("2f7fb5"), "D": Color("6b4f36")}
const USE_TEXT := {"bed": "Sleep", "pc": "Use the PC", "tv": "Watch pro demos", "kitchen": "Cook", "trophies": "Trophy cabinet",
	"gym": "Work out", "car": "Go for a drive", "sofa": "Sit down", "wardrobe": "Wardrobe", "view": "Take in the view",
	"tub": "Hot tub", "piano": "Play the piano", "arcade": "Play", "aquarium": "Watch the fish", "bar": "Pour a drink", "exit": "Leave"}
const GUEST_LINES := ["Nice place. Seriously.", "We should run some aim maps later.", "Coach was brutal today, huh?",
	"Your setup is cleaner than mine.", "Got anything to eat?", "Thanks for having me over.", "We're winning this weekend, I can feel it.",
	"Don't tell the others but you're my favourite duo partner.", "Is that a real trophy? Let me hold it."]

var w: World
var life: Lifestyle
var home_id := ""
var tour := ""
var data: Dictionary = {}
var props: Dictionary = {}
var grid: Array = []
var W := 0
var H := 0
var solid := PackedByteArray()
var items: Array = [] ## {k, sprite, rect: Rect2 (px), cells: Rect2i, rot, use, solid, tex}
var astar := AStarGrid2D.new()
var shell: Texture2D = null
var exit_cell := Vector2i.ZERO

var pos := Vector2.ZERO
var face := Vector2.DOWN
var moving := false
var walk_t := 0.0
var step_player: AudioStreamPlayer
var stride_t := 0.0
var steps_played := 0 ## Tests.
var pets: Array = [] ## {id, pos, path, wait, dir, tex}
var npcs: Array = [] ## {p: PlayerData or null, name, pos, dir, chef}
var casual: Array = [] ## Textures for casual bodies (assets/homes/casual.json), or empty.
var casual_ppm := 300.0

var cam: Camera2D
var ui: Control
var hud_info: Label
var hud_stats: Label
var prompt: Label
var toast: Label
var toast_t := 0.0
var modal: Control = null
var target: Dictionary = {} ## What E would use right now.


func _ready() -> void:
	w = Game.pworld
	if w == null or w.user_player == null:
		Game.goto(Game.MENU_SCENE)
		return
	life = w.life()
	tour = Game.home_tour
	home_id = tour if tour != "" else life.home
	_load_layout()
	_build_ui()
	step_player = AudioStreamPlayer.new()
	step_player.stream = Sfx._load_stream("lockdown_footstep")
	step_player.bus = "SFX"
	step_player.volume_db = -10.0
	add_child(step_player)
	cam = Camera2D.new()
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 10.0
	add_child(cam)
	cam.make_current()
	_fit_zoom()
	get_viewport().size_changed.connect(_fit_zoom)
	cam.global_position = pos
	cam.reset_smoothing()
	_spawn_life()
	_refresh_hud()
	if tour != "":
		_say("Viewing %s. Furniture you'd buy separately isn't shown." % String(Lifestyle.info(tour).get("name", tour)), 5.0)
	else:
		_say("Home. WASD to move, E to use things, P for your phone, Esc to leave.", 5.0)


func _fit_zoom() -> void:
	var vh := get_viewport_rect().size.y
	var z := clampf(vh / 560.0, 1.3, 2.6)
	cam.zoom = Vector2(z, z)


# --- Layout --------------------------------------------------------------------

static func load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d: Variant = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


static func layout(id: String) -> Dictionary:
	return load_json(DATA_DIR + id + ".json")


static func catalog() -> Dictionary:
	return load_json(DATA_DIR + "props.json").get("props", {})


static func rot_dims(pw: int, ph: int, rot: int) -> Vector2i:
	return Vector2i(ph, pw) if rot == 90 or rot == 270 else Vector2i(pw, ph)


func _load_layout() -> void:
	data = layout(home_id)
	if data.is_empty():
		home_id = Lifestyle.STARTER
		data = layout(home_id)
	props = catalog()
	grid = data.get("grid", [])
	H = grid.size()
	W = String(grid[0]).length() if H > 0 else 0
	solid.resize(W * H)
	for y in H:
		var row: String = grid[y]
		for x in W:
			var ch := row[x]
			solid[y * W + x] = 0 if WALK.contains(ch) else 1
			if ch == "E":
				exit_cell = Vector2i(x, y)
	var art := ART_DIR + home_id + ".png"
	shell = load(art) if ResourceLoader.exists(art) else null
	var cars := life.cars()
	for d: Dictionary in data.get("items", []):
		if not _shown(d, cars):
			continue
		var k := String(d.k)
		var sprite := k
		if k.begins_with("desk_pc_"):
			sprite = "desk_pc_%d" % clampi(w.setup_level, 0, 3)
		if String(d.get("need", "")) == "car":
			sprite = String(Lifestyle.info(String(cars[int(d.get("slot", 0))])).get("sprite", k))
		var pr: Dictionary = props.get(k, {"w": 1, "h": 1, "solid": true})
		var rot := int(d.get("rot", 0))
		var dims := rot_dims(int(pr.w), int(pr.h), rot)
		var cells := Rect2i(int(d.x), int(d.y), dims.x, dims.y)
		var tp := ART_DIR + "props/" + sprite + ".png"
		var it := {"k": k, "sprite": sprite, "cells": cells, "rect": Rect2(Vector2(cells.position) * CELL, Vector2(cells.size) * CELL),
			"rot": rot, "use": String(d.get("use", "")), "solid": bool(pr.solid), "w": int(pr.w), "h": int(pr.h),
			"tex": load(tp) if ResourceLoader.exists(tp) else null}
		items.append(it)
		if bool(pr.solid):
			for yy in range(cells.position.y, cells.end.y):
				for xx in range(cells.position.x, cells.end.x):
					if xx >= 0 and yy >= 0 and xx < W and yy < H:
						solid[yy * W + xx] = 1
	# Rugs and mats first, then furniture.
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(not bool(a.solid)) > int(not bool(b.solid)))
	astar.region = Rect2i(0, 0, W, H)
	astar.cell_size = Vector2(CELL, CELL)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for y in H:
		for x in W:
			if solid[y * W + x] == 1:
				astar.set_point_solid(Vector2i(x, y))
	var sp: Array = data.get("spawn", [exit_cell.x, exit_cell.y])
	pos = cell_center(Vector2i(int(sp[0]), int(sp[1])))
	var cj := load_json(ART_DIR + "casual.json")
	casual_ppm = float(cj.get("ppm", 300.0))
	for f in cj.get("files", []):
		var cp := ART_DIR + String(f)
		if ResourceLoader.exists(cp):
			casual.append(load(cp))


func _shown(d: Dictionary, cars: Array) -> bool:
	var need := String(d.get("need", ""))
	if need == "":
		return true
	if tour != "":
		return false
	match need:
		"car":
			return int(d.get("slot", 0)) < cars.size()
		"pet":
			return not life.pets().is_empty()
	return life.owns(need)


func cell_center(c: Vector2i) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * CELL


func is_solid(c: Vector2i) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= W or c.y >= H:
		return true
	return solid[c.y * W + c.x] == 1


func _blocked(p: Vector2) -> bool:
	var x0 := floori((p.x - RADIUS) / CELL)
	var x1 := floori((p.x + RADIUS) / CELL)
	var y0 := floori((p.y - RADIUS) / CELL)
	var y1 := floori((p.y + RADIUS) / CELL)
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			if is_solid(Vector2i(cx, cy)):
				var r := Rect2(cx * CELL, cy * CELL, CELL, CELL)
				var q := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
				if q.distance_to(p) < RADIUS:
					return true
	return false


func _free_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in H:
		for x in W:
			if not is_solid(Vector2i(x, y)) and String(grid[y])[x] != "D":
				out.append(Vector2i(x, y))
	return out


## A free cell next to a piece (in front of it first): where someone would stand.
func _spot_near(it: Dictionary, taken: Array) -> Vector2i:
	var c: Rect2i = it.cells
	var dirs := {0: Vector2i(0, 1), 90: Vector2i(-1, 0), 180: Vector2i(0, -1), 270: Vector2i(1, 0)}
	var front: Vector2i = dirs.get(int(it.rot), Vector2i(0, 1))
	var cand: Array[Vector2i] = []
	var mid := c.position + c.size / 2
	cand.append(Vector2i(mid.x if front.x == 0 else (c.end.x if front.x > 0 else c.position.x - 1), mid.y if front.y == 0 else (c.end.y if front.y > 0 else c.position.y - 1)))
	for yy in range(c.position.y - 1, c.end.y + 1):
		for xx in range(c.position.x - 1, c.end.x + 1):
			cand.append(Vector2i(xx, yy))
	for q in cand:
		if not is_solid(q) and not taken.has(q) and String(grid[q.y])[q.x] != "D" and q != exit_cell:
			return q
	return Vector2i(-1, -1)


# --- People and pets -------------------------------------------------------------

func _spawn_life() -> void:
	pets.clear()
	npcs.clear()
	var free := _free_cells()
	if free.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(home_id) + life.stamp()
	if tour == "":
		for id in life.pets():
			var tp := ART_DIR + "props/" + String(id) + ".png"
			var bed := _find_item("pet_bed")
			var start: Vector2i = free[rng.randi() % free.size()]
			if not bed.is_empty():
				start = (bed.cells as Rect2i).position
			pets.append({"id": id, "pos": cell_center(start), "path": PackedVector2Array(), "wait": rng.randf_range(0.5, 3.0),
				"dir": Vector2.UP, "tex": load(tp) if ResourceLoader.exists(tp) else null})
	var taken: Array = [Vector2i(pos / CELL)]
	if tour == "":
		var seats := items.filter(func(it: Dictionary) -> bool: return String(it.use) in ["sofa", "bar", "tv"])
		var gi := 0
		for g: PlayerData in life.guests_now():
			var c := Vector2i(-1, -1)
			if gi < seats.size():
				c = _spot_near(seats[gi], taken)
			if c.x < 0:
				c = free[rng.randi() % free.size()]
			taken.append(c)
			npcs.append({"p": g, "name": g.player_name, "pos": cell_center(c), "dir": Vector2.DOWN, "chef": false})
			gi += 1
		var k := _find_item_use("kitchen")
		if life.owns("chef") and not k.is_empty():
			var c2 := _spot_near(k, taken)
			if c2.x >= 0:
				taken.append(c2)
				npcs.append({"p": null, "name": "Your chef", "pos": cell_center(c2), "dir": Vector2.UP, "chef": true})


func _find_item(kind: String) -> Dictionary:
	for it: Dictionary in items:
		if String(it.k) == kind:
			return it
	return {}


func _find_item_use(use: String) -> Dictionary:
	for it: Dictionary in items:
		if String(it.use) == use:
			return it
	return {}


func _pets_tick(delta: float) -> void:
	for pt: Dictionary in pets:
		var path: PackedVector2Array = pt.path
		if path.is_empty():
			pt.wait = float(pt.wait) - delta
			if float(pt.wait) <= 0.0:
				var free := _free_cells()
				var goal: Vector2i = free[randi() % free.size()]
				if randf() < 0.35:
					goal = Vector2i(pos / CELL) # Come and see you.
				var from := Vector2i((pt.pos as Vector2) / CELL)
				if not astar.is_point_solid(from) and not astar.is_point_solid(goal):
					pt.path = astar.get_point_path(from, goal)
					if (pt.path as PackedVector2Array).size() > 0:
						(pt.path as PackedVector2Array).remove_at(0)
				pt.wait = randf_range(1.5, 5.0)
			continue
		var nxt: Vector2 = path[0] + Vector2(CELL, CELL) * 0.5
		var to := nxt - (pt.pos as Vector2)
		var sp := 55.0 if String(pt.id) == "dog" else 42.0
		if to.length() < 2.0:
			path.remove_at(0)
			pt.path = path
			if path.size() > 0 and Vector2i(path[path.size() - 1] / CELL).distance_to(Vector2i(pos / CELL)) < 1.5 and path.size() <= 1:
				pt.path = PackedVector2Array()
			continue
		pt.dir = (pt.dir as Vector2).lerp(to.normalized(), minf(1.0, delta * 8.0)).normalized()
		pt.pos = (pt.pos as Vector2) + to.normalized() * minf(to.length(), sp * delta)
		if (pt.pos as Vector2).distance_to(pos) < 26.0 and path.size() <= 2:
			pt.path = PackedVector2Array() # Close enough: sit by you.


# --- Frame -----------------------------------------------------------------------

func _process(delta: float) -> void:
	var busy := modal != null and is_instance_valid(modal)
	var v := Vector2.ZERO
	if not busy:
		v = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	moving = v.length() > 0.05
	if moving:
		face = face.lerp(v.normalized(), minf(1.0, delta * 14.0)).normalized()
		var step := v * SPEED * delta
		var before := pos
		var nx := pos + Vector2(step.x, 0.0)
		if not _blocked(nx):
			pos = nx
		var ny := pos + Vector2(0.0, step.y)
		if not _blocked(ny):
			pos = ny
		walk_t += delta
		if pos.distance_to(before) > SPEED * delta * 0.3:
			_footstep(delta)
	else:
		stride_t = 0.0
	cam.global_position = pos
	_pets_tick(delta)
	for n: Dictionary in npcs:
		var to: Vector2 = pos - (n.pos as Vector2)
		if to.length() < 140.0 and not bool(n.chef):
			n.dir = (n.dir as Vector2).lerp(to.normalized(), minf(1.0, delta * 3.0)).normalized()
	target = {} if busy else _nearest_use()
	prompt.text = "" if target.is_empty() else "E   %s" % String(target.label)
	prompt.visible = not target.is_empty()
	if toast_t > 0.0:
		toast_t -= delta
		toast.modulate.a = clampf(toast_t / 0.6, 0.0, 1.0)
	queue_redraw()


## Footsteps while you walk (none when pressed against a wall).
func _footstep(delta: float) -> void:
	stride_t -= delta
	if stride_t > 0.0:
		return
	stride_t = STRIDE_TIME
	steps_played += 1
	if step_player != null and step_player.stream != null:
		step_player.pitch_scale = randf_range(0.9, 1.1)
		step_player.play()


func _nearest_use() -> Dictionary:
	var best := {}
	var bd := 1e9
	for it: Dictionary in items:
		var u := String(it.use)
		if u == "" or (tour != "" and u != "exit"):
			continue
		var r: Rect2 = it.rect
		if not r.grow(REACH).has_point(pos):
			continue
		var d := r.get_center().distance_to(pos)
		if d < bd:
			bd = d
			best = {"kind": "item", "use": u, "label": _label_for(u), "it": it}
	for n: Dictionary in npcs:
		var d2 := (n.pos as Vector2).distance_to(pos)
		if d2 < 40.0 and d2 < bd and tour == "":
			bd = d2
			best = {"kind": "npc", "label": ("Talk to %s" % String(n.name)) if not bool(n.chef) else "Ask the chef what's for dinner", "npc": n}
	for pt: Dictionary in pets:
		var d3 := (pt.pos as Vector2).distance_to(pos)
		if d3 < 34.0 and d3 < bd:
			bd = d3
			best = {"kind": "item", "use": "pet", "label": "Pet the %s" % String(pt.id), "it": {}}
	var ex := Rect2(Vector2(exit_cell) * CELL, Vector2(CELL, CELL))
	if ex.grow(REACH).has_point(pos):
		var d4 := ex.get_center().distance_to(pos)
		if d4 < bd:
			best = {"kind": "exit", "label": "Leave"}
	return best


func _label_for(u: String) -> String:
	if u == "car":
		var cs := life.cars()
		if not cs.is_empty():
			return "Take the %s for a drive" % String(Lifestyle.info(String(cs[0])).name).to_lower()
	return String(USE_TEXT.get(u, u.capitalize()))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quit"):
		get_viewport().set_input_as_handled()
		if modal != null and is_instance_valid(modal):
			modal.queue_free()
			modal = null
		else:
			_leave()
		return
	if modal != null and is_instance_valid(modal):
		return
	if event.is_action_pressed("use") and not target.is_empty():
		get_viewport().set_input_as_handled()
		_use(target)
	elif event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_P and tour == "":
		get_viewport().set_input_as_handled()
		_phone()


func _use(t: Dictionary) -> void:
	match String(t.kind):
		"exit":
			_leave()
		"npc":
			var n: Dictionary = t.npc
			if bool(n.chef):
				_say("Chef: \"%s\"" % ["Miso salmon, greens, rice. Eat it all.", "Pasta tonight. Carbs before match day.", "Steak. You've earned it.", "Something green. Don't make that face."][randi() % 4])
				return
			var p: PlayerData = n.p
			var key := "chat_%d" % p.uid
			var line: String = GUEST_LINES[randi() % GUEST_LINES.size()]
			if not life.done_this_week(key):
				life.used[key] = life.stamp()
				w._relate(p.uid, 2.0)
				_say("%s: \"%s\"  (relationship +2)" % [p.player_name, line])
			else:
				_say("%s: \"%s\"" % [p.player_name, line])
		"item":
			var u := String(t.use)
			match u:
				"pc":
					_pc_panel()
				"trophies":
					_trophy_panel()
				"wardrobe":
					_wardrobe_panel()
				_:
					var r := life.act(u)
					if String(r.text) != "":
						_say(String(r.text))
	_refresh_hud()


func _leave() -> void:
	var back := Game.home_tour != ""
	Game.home_tour = ""
	if back:
		Game.hub_page = "Shop"
	Game.save_player_career_soon()
	Game.goto(Game.CAREER_SCENE)


# --- Drawing ---------------------------------------------------------------------

func _draw() -> void:
	var size := Vector2(W, H) * CELL
	draw_rect(Rect2(Vector2(-3000, -3000), size + Vector2(6000, 6000)), Color(0.04, 0.045, 0.055))
	if shell != null:
		draw_texture_rect(shell, Rect2(Vector2.ZERO, size), false)
	else:
		_draw_flat()
	for it: Dictionary in items:
		_draw_item(it)
	for pt: Dictionary in pets:
		_draw_pet(pt)
	for n: Dictionary in npcs:
		_draw_person(n.pos, n.dir, String(n.name), 1 if not bool(n.chef) else 0, hash(String(n.name)))
	_draw_person(pos, face, w.user_player.player_name, 0, life.outfit, true)
	if not target.is_empty() and String(target.kind) == "item" and not (target.it as Dictionary).is_empty():
		var r: Rect2 = (target.it as Dictionary).rect
		draw_rect(r.grow(2.0), Color(1.0, 0.85, 0.35, 0.55), false, 1.5)


func _draw_flat() -> void:
	for y in H:
		var row: String = grid[y]
		for x in W:
			var ch := row[x]
			var r := Rect2(x * CELL, y * CELL, CELL, CELL)
			if FLOOR_COLORS.has(ch):
				draw_rect(r, FLOOR_COLORS[ch])
				if ch == "D":
					draw_rect(r.grow(-10), Color(0.3, 0.22, 0.15))
			elif ch == "#":
				draw_rect(r, Color("2a2d33"))
				draw_rect(r.grow(-3), Color("cfcac0"))
			elif ch == "W":
				draw_rect(r, Color("2a2d33"))
				draw_rect(r.grow(-8), Color("8fd3ff"))
			elif ch == "E":
				draw_rect(r, Color("2a2d33"))
				draw_rect(r.grow(-4), Color("7a4a24"))


func _draw_item(it: Dictionary) -> void:
	var r: Rect2 = it.rect
	var tex: Texture2D = it.tex
	if tex == null:
		var col := Color(0.55, 0.42, 0.3) if bool(it.solid) else Color(0.6, 0.3, 0.3, 0.45)
		draw_rect(r.grow(-2), col)
		draw_rect(r.grow(-2), Color(0, 0, 0, 0.5), false, 1.0)
		draw_string(ThemeDB.fallback_font, r.position + Vector2(3, 12), String(it.sprite).replace("_", " "), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 4, 9, Color(1, 1, 1, 0.8))
		return
	var s := CELL / ART_PPC
	var ang := deg_to_rad(float(it.rot))
	var tsz := tex.get_size()
	if bool(it.solid):
		# Shadow: the piece's own silhouette, offset down-right.
		draw_set_transform_matrix(Transform2D(ang, Vector2(s, s), 0.0, r.get_center() + Vector2(2.0, 3.0)))
		draw_texture(tex, -tsz * 0.5, Color(0, 0, 0, 0.35))
	draw_set_transform_matrix(Transform2D(ang, Vector2(s, s), 0.0, r.get_center()))
	draw_texture(tex, -tsz * 0.5)
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_pet(pt: Dictionary) -> void:
	var p: Vector2 = pt.pos
	var tex: Texture2D = pt.tex
	var ang := (pt.dir as Vector2).angle() + PI * 0.5
	if tex == null:
		draw_circle(p, 8.0, Color("d9a441") if String(pt.id) == "dog" else Color("e07a2e"))
		draw_circle(p + (pt.dir as Vector2) * 8.0, 5.0, Color("c48f30"))
		return
	var s := CELL / ART_PPC
	draw_set_transform_matrix(Transform2D(ang, Vector2(s, s), 0.0, p + Vector2(1.5, 2.5)))
	draw_texture(tex, -tex.get_size() * 0.5, Color(0, 0, 0, 0.3))
	draw_set_transform_matrix(Transform2D(ang, Vector2(s, s), 0.0, p))
	draw_texture(tex, -tex.get_size() * 0.5)
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_person(at: Vector2, dir: Vector2, who: String, side: int, look: int, me: bool = false) -> void:
	if not casual.is_empty():
		var tex: Texture2D = casual[absi(look) % casual.size()]
		var s := PlayerArt.BODY_PPM / casual_ppm * BODY_SCALE
		var bob := sin(walk_t * 14.0) * 0.6 if me and moving else 0.0
		draw_set_transform_matrix(Transform2D(dir.angle(), Vector2(s, s), 0.0, at + Vector2(1.5, 2.0)))
		draw_texture(tex, -tex.get_size() * 0.5, Color(0, 0, 0, 0.35))
		draw_set_transform_matrix(Transform2D(dir.angle(), Vector2(s, s), 0.0, at + dir * bob))
		draw_texture(tex, -tex.get_size() * 0.5)
		draw_set_transform_matrix(Transform2D.IDENTITY)
	elif not PlayerArt.draw_body(self, side, who, "pistol", dir, PlayerArt.TINT, at):
		draw_circle(at, RADIUS, Color("ff7f2e") if me else Color("4a90d9"))
	if not me:
		var f := ThemeDB.fallback_font
		draw_string(f, at + Vector2(-60, -20), who, HORIZONTAL_ALIGNMENT_CENTER, 120, 9, Color(1, 1, 1, 0.75))


# --- UI ----------------------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.theme = UI.make_theme()
	layer.add_child(ui)
	var info := PanelContainer.new()
	info.add_theme_stylebox_override("panel", UI._box(Color(UI.PANEL, 0.88), 4, UI.BORDER, 1, 14, 10))
	info.position = Vector2(14, 14)
	ui.add_child(info)
	var iv := UI.vbox(2)
	info.add_child(iv)
	hud_info = UI.label("", 16, UI.TEXT, 700)
	iv.add_child(hud_info)
	hud_stats = UI.label("", 12, UI.TEXT_DIM)
	iv.add_child(hud_stats)
	var keys := UI.label("WASD move   E use   P phone   Esc leave" if Game.home_tour == "" else "WASD look around   Esc back to the shop", 11, UI.TEXT_FAINT)
	iv.add_child(keys)
	if Game.home_tour != "":
		var a := Lifestyle.info(Game.home_tour)
		var bar := UI.hbox(8)
		var owned := w.assets.has(Game.home_tour)
		bar.add_child(UI.small_button("Owned" if owned else "Buy  %s" % UI.money_text(int(a.get("cost", 0))), func() -> void:
			var res := life.buy(Game.home_tour)
			if res != "":
				_say(res)
				return
			Game.save_player_career_soon()
			_say("It's yours. You moved in.")
			Game.home_tour = ""
			Game.goto(Game.HOME_SCENE), 160, "PrimaryButton"))
		(bar.get_child(0) as Button).disabled = owned
		bar.add_child(UI.small_button("Back to the shop", _leave, 140, "GhostButton"))
		iv.add_child(bar)
	prompt = UI.label("", 18, UI.WARN, 700)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.offset_left = -300
	prompt.offset_right = 300
	prompt.offset_top = -120
	prompt.offset_bottom = -90
	ui.add_child(prompt)
	toast = UI.label("", 15, UI.TEXT, 600)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	toast.offset_left = -380
	toast.offset_right = 380
	toast.offset_top = -80
	toast.offset_bottom = -24
	ui.add_child(toast)
	if Game.home_tour == "":
		var pb := UI.small_button("Phone (P)", _phone, 110)
		pb.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		pb.offset_left = -250
		pb.offset_right = -140
		pb.offset_top = 14
		pb.offset_bottom = 46
		ui.add_child(pb)
		var lb := UI.small_button("Leave (Esc)", _leave, 110)
		lb.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		lb.offset_left = -126
		lb.offset_right = -14
		lb.offset_top = 14
		lb.offset_bottom = 46
		ui.add_child(lb)


func _refresh_hud() -> void:
	var nm := String(Lifestyle.info(home_id).get("name", "Home"))
	hud_info.text = nm if tour == "" else "Viewing: %s" % nm
	var p := w.user_player
	hud_stats.text = "Season %d, week %d    Wallet %s    Fatigue %d    Morale %d    Form %+.1f" % [w.season, w.week, UI.money_text(w.wallet), int(w.fatigue), int(p.morale), p.form]


func _say(t: String, secs: float = 4.0) -> void:
	toast.text = t
	toast_t = secs
	toast.modulate.a = 1.0


func _open(width: int, title: String) -> VBoxContainer:
	if modal != null and is_instance_valid(modal):
		modal.queue_free()
	var m := UI.modal(ui, width, UI.ACCENT)
	modal = m[0]
	var box: VBoxContainer = m[1]
	var head := UI.hbox(8)
	head.add_child(UI.label(title, 20, UI.TEXT, 700))
	head.add_child(UI.spacer())
	head.add_child(UI.small_button("Close", _close, 80, "GhostButton"))
	box.add_child(head)
	return box


func _close() -> void:
	if modal != null and is_instance_valid(modal):
		modal.queue_free()
	modal = null
	_refresh_hud()


func _row(box: VBoxContainer, title: String, sub: String, btn: String, cb: Callable, disabled: bool = false) -> void:
	var r := UI.hbox(10)
	var v := UI.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UI.label(title, 14, UI.TEXT, 600))
	if sub != "":
		var l := UI.label(sub, 11, UI.TEXT_DIM)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(l)
	r.add_child(v)
	var b := UI.small_button(btn, cb, 130, "PrimaryButton")
	b.disabled = disabled
	r.add_child(b)
	box.add_child(r)


func _pc_panel() -> void:
	var box := _open(560, "Your PC  (setup level %d)" % w.setup_level)
	_row(box, "Aim practice", "An hour on an aim map: a small boost to a shooting stat. Once a week.", "Practise" if not life.done_this_week("pc") else "Done",
		func() -> void: _do_and_close("pc"), life.done_this_week("pc"))
	_row(box, "Go live", "Stream for a few hours from home: subs, donations and followers%s. Once a week." % (" (studio: +50%)" if life.owns("studio") else ""),
		"Stream" if not life.done_this_week("stream") else "Done", func() -> void: _do_and_close("stream"), life.done_this_week("stream"))
	box.add_child(UI.divider())
	box.add_child(UI.label("Streaming schedule (weekly)", 14, UI.TEXT, 600))
	var sr := UI.hbox(8)
	for lv: String in World.STREAM:
		var l2 := lv
		sr.add_child(UI.small_button(lv, func() -> void:
			w.set_stream(l2)
			_pc_panel(), 90, "PrimaryButton" if w.stream_level == lv else "GhostButton"))
	box.add_child(sr)
	var d := UI.label(String(World.STREAM[w.stream_level].desc), 11, UI.TEXT_DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(d)


func _do_and_close(action: String) -> void:
	var r := life.act(action)
	_close()
	if String(r.text) != "":
		_say(String(r.text))


func _trophy_panel() -> void:
	var box := _open(620, "Trophy cabinet")
	if w.trophies.is_empty():
		box.add_child(UI.label("Empty for now. Win something.", 14, UI.TEXT_DIM))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	for t: Dictionary in w.trophies:
		var place := int(t.place)
		var col := UI.WARN if place == 1 else (UI.TEXT_DIM if place == 2 else UI.ACCENT2)
		var pnl := PanelContainer.new()
		pnl.add_theme_stylebox_override("panel", UI._box(Color(col, 0.08), 4, col, 1, 10, 6))
		var v := UI.vbox(0)
		v.add_child(UI.label(["Promotion", "Winner", "Runner-up"][clampi(place, 0, 2)] if place <= 2 else "Top 4", 11, col, 700))
		v.add_child(UI.label(String(t.name), 13, UI.TEXT, 600))
		v.add_child(UI.label("Season %d" % int(t.s), 11, UI.TEXT_FAINT))
		pnl.add_child(v)
		flow.add_child(pnl)
	box.add_child(flow)
	var p := w.user_player
	if not p.honours.is_empty():
		box.add_child(UI.divider())
		box.add_child(UI.label("Titles (wear one with your name)", 14, UI.TEXT, 600))
		var tf := HFlowContainer.new()
		tf.add_theme_constant_override("h_separation", 6)
		tf.add_theme_constant_override("v_separation", 6)
		for h: Dictionary in p.honours:
			var lbl := PlayerData.honour_label(h)
			var on := p.title == lbl
			tf.add_child(UI.small_button(("Wearing: " if on else "") + lbl, func() -> void:
				p.title = "" if on else lbl
				Game.save_player_career_soon()
				_trophy_panel(), 0, "PrimaryButton" if on else "GhostButton"))
		box.add_child(tf)


func _wardrobe_panel() -> void:
	var box := _open(600, "Wardrobe")
	var n := maxi(1, casual.size())
	if n > 1:
		box.add_child(UI.label("Outfit", 14, UI.TEXT, 600))
		var orow := UI.hbox(8)
		for i in n:
			var ii := i
			orow.add_child(UI.small_button("Look %d" % (i + 1), func() -> void:
				life.outfit = ii
				Game.save_player_career_soon()
				_wardrobe_panel(), 90, "PrimaryButton" if life.outfit == i else "GhostButton"))
		box.add_child(orow)
	box.add_child(UI.label("Weapon finish (shows on your guns in matches)", 14, UI.TEXT, 600))
	var srow := HFlowContainer.new()
	srow.add_theme_constant_override("h_separation", 6)
	srow.add_theme_constant_override("v_separation", 6)
	srow.add_child(UI.small_button("Factory", func() -> void:
		life.skin = ""
		Game.save_player_career_soon()
		_wardrobe_panel(), 90, "PrimaryButton" if life.skin == "" else "GhostButton"))
	var any := false
	for id: String in Lifestyle.SHOP:
		if String(Lifestyle.SHOP[id].cat) == "skin" and w.assets.has(id):
			any = true
			var idd := id
			srow.add_child(UI.small_button(String(Lifestyle.SHOP[id].name).replace(" weapon finish", ""), func() -> void:
				life.skin = idd
				Game.save_player_career_soon()
				_wardrobe_panel(), 90, "PrimaryButton" if life.skin == id else "GhostButton"))
	box.add_child(srow)
	if not any:
		box.add_child(UI.label("Buy weapon finishes in the Shop.", 11, UI.TEXT_FAINT))
	var style: Array = []
	for id: String in Lifestyle.SHOP:
		if String(Lifestyle.SHOP[id].cat) == "style" and w.assets.has(id):
			style.append(String(Lifestyle.SHOP[id].name))
	if not style.is_empty():
		box.add_child(UI.label("Also yours: " + ", ".join(style), 12, UI.TEXT_DIM))


func _phone() -> void:
	var box := _open(600, "Phone")
	var gs := life.guests_now()
	if not gs.is_empty():
		box.add_child(UI.label("Over at yours this week: " + ", ".join(gs.map(func(q: PlayerData) -> String: return q.player_name)), 12, UI.GOOD))
	_row(box, "Throw a house party", "Invite the squad over: relationships and followers up. Things can get out of hand. %s" % UI.money_text(Lifestyle.PARTY_COST),
		"Party", func() -> void:
			var r := life.party()
			_close()
			_say(r if r != "" else "Party!")
			_spawn_life(), w.teamless)
	var vr := life.vacation_ready()
	_row(box, "Book a vacation", "A week away: fatigue gone, morale +15. The coach won't love it mid-season. %s" % UI.money_text(Lifestyle.VACATION_COST),
		"Book" if vr else "Too soon", func() -> void:
			var r2 := life.vacation()
			_close()
			_say(r2), not vr)
	box.add_child(UI.divider())
	box.add_child(UI.label("Invite someone over", 14, UI.TEXT, 600))
	var inv := life.invitable()
	if inv.is_empty():
		box.add_child(UI.label("No teammates to invite.", 12, UI.TEXT_DIM))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	for q: PlayerData in inv:
		var uid := q.uid
		flow.add_child(UI.small_button("%s  (%s)" % [q.player_name, World.relation_text(w.relation(q.uid))], func() -> void:
			var r3 := life.invite(uid)
			_close()
			_say(r3 if r3 != "" else "They're on their way over.")
			_spawn_life(), 0, "GhostButton"))
	box.add_child(flow)
	box.add_child(UI.divider())
	var nav := UI.hbox(8)
	for pg: String in ["Messages", "Feed", "Shop"]:
		var pgg := pg
		nav.add_child(UI.small_button(pg, func() -> void:
			Game.hub_page = pgg
			Game.save_player_career_soon()
			Game.goto(Game.CAREER_SCENE), 110, "GhostButton"))
	box.add_child(nav)
