extends Node
## Writes art/maps/<map>.json for the Blender map builder (art/blender/build_map.py)
## from the real Arena grid, buildings included. Replaces art/export_map.py.
##   godot --headless --path . res://tests/export_maps.tscn -- --test [--map=dustline]


func _ready() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map="):
			only = a.substr(6).to_lower()
	for map_name: String in Maps.LIST:
		if only != "" and map_name.to_lower() != only:
			continue
		var d: Dictionary = Maps.get_map(map_name)
		var arena := Arena.new()
		arena.load_map(d)
		add_child(arena)
		var rows: Array = []
		var windows: Array = []
		for y in arena.H:
			var row := ""
			for x in arena.W:
				var c := Vector2i(x, y)
				row += "#" if arena.is_solid(c) else "."
				if arena.is_window(c):
					windows.append([x, y])
			rows.append(row)
		var interiors: Array = []
		var props: Array = []
		var doors: Array = []
		var inner: Array = []
		for b: Dictionary in arena.buildings:
			var r: Rect2i = (b.rect as Rect2i).grow(-1)
			interiors.append([r.position.x, r.position.y, r.size.x, r.size.y, String(b.get("floor", "wood")), String(b.name)])
			for p: Rect2i in b.get("props", []):
				props.append(_r(p))
			for p: Rect2i in b.get("doors", []):
				doors.append(_r(p))
			for p: Rect2i in b.get("walls", []):
				inner.append(_r(p))
		var sites := {}
		for k: String in d.sites:
			sites[k] = _r(d.sites[k])
		var spawns: Array = []
		for side: Array in d.spawns:
			spawns.append(side.map(func(c: Vector2i) -> Array: return [c.x, c.y]))
		var out := {"name": map_name.to_lower(), "size": [arena.W, arena.H], "open": rows,
			"floors": (d.floors as Array).map(_r), "cover": (d.cover as Array).map(_r), "sites": sites, "spawns": spawns,
			"windows": windows, "interiors": interiors, "props": props, "doors": doors, "inner_walls": inner,
			"gates": arena.gates.map(_r), "barricades": arena.barricades.map(_r)}
		var path := ProjectSettings.globalize_path("res://art/maps/%s.json" % map_name.to_lower())
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(JSON.stringify(out))
		f.close()
		print("wrote %s (%d buildings, %d window cells)" % [path, arena.buildings.size(), windows.size()])
		arena.queue_free()
	get_tree().quit()


func _r(r: Rect2i) -> Array:
	return [r.position.x, r.position.y, r.size.x, r.size.y]
