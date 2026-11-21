extends Node
## Validates every map and renders an overview PNG of each with points,
## routes and the auto-computed threat regions. Run:
##   godot --path . res://tests/map_check.tscn -- --test --out=<dir>


func _ready() -> void:
	var out := "user://maps"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	for map_name: String in Maps.LIST:
		var arena := Arena.new()
		arena.load_map(Maps.get_map(map_name))
		add_child(arena)
		var problems := arena.validate()
		print("[map %s] %dx%d  %s" % [map_name, arena.W, arena.H, "OK" if problems.is_empty() else "PROBLEMS:"])
		for p in problems:
			print("    ", p)
		await _render(arena, "%s/%s.png" % [out, map_name])
		arena.queue_free()
		await get_tree().process_frame
	get_tree().quit()


func _render(arena: Arena, path: String) -> void:
	var px := 10 # pixels per cell in the overview
	var img := Image.create(arena.W * px, arena.H * px, false, Image.FORMAT_RGB8)
	var colors := {
		"": Color(0.12, 0.12, 0.13), "A": Color(0.55, 0.28, 0.28), "B": Color(0.28, 0.32, 0.55),
		"mid": Color(0.35, 0.35, 0.3), "ct": Color(0.25, 0.4, 0.5), "t": Color(0.5, 0.42, 0.25),
	}
	for y in arena.H:
		for x in arena.W:
			var c := Vector2i(x, y)
			var col: Color = Color(0.05, 0.05, 0.06) if arena.is_solid(c) else colors[arena.threat_at(arena.cell_center(c))]
			for sy in px:
				for sx in px:
					img.set_pixel(x * px + sx, y * px + sy, col)
	# Sites outline, points, spawns.
	for key: String in arena.sites:
		var r: Rect2i = arena.sites[key]
		for x in range(r.position.x * px, r.end.x * px):
			img.set_pixel(x, r.position.y * px, Color.RED)
			img.set_pixel(x, r.end.y * px - 1, Color.RED)
		for y in range(r.position.y * px, r.end.y * px):
			img.set_pixel(r.position.x * px, y, Color.RED)
			img.set_pixel(r.end.x * px - 1, y, Color.RED)
	for k: String in arena.points:
		_dot(img, arena.points[k], px, Color.YELLOW)
	for side in 2:
		for c: Vector2i in arena.spawns[side]:
			_dot(img, c, px, Color.ORANGE if side == 0 else Color.CYAN)
	for s: String in arena.site_info:
		for e in arena.site_info[s].ct_holds:
			_dot(img, e[0], px, Color(0.3, 0.7, 1.0))
		for e in arena.site_info[s].t_cover:
			_dot(img, e[0], px, Color(1.0, 0.6, 0.2))
	img.save_png(path)
	await get_tree().process_frame


func _dot(img: Image, c: Vector2i, px: int, col: Color) -> void:
	for sy in range(2, px - 2):
		for sx in range(2, px - 2):
			img.set_pixel(c.x * px + sx, c.y * px + sy, col)
