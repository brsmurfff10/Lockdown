extends Node
## Screenshots of every home with everything bought, plus the Shop and Home hub
## pages.   godot --path . res://tests/home_shot.tscn -- --test --out=<dir> [--zoom=N]
func _ready() -> void:
	var out := ""
	var zoom := 0.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		if a.begins_with("--zoom="):
			zoom = float(a.substr(7))
	get_window().size = Vector2i(1600, 900)
	Game.end_career()
	Game.create_my_player("Homebody", "Rifler", "Canada")
	Game.start_career()
	var w := Game.pworld
	var life := w.life()
	w.wallet = 20000000
	w.setup_level = 3
	for id: String in Lifestyle.SHOP:
		if not bool(Lifestyle.SHOP[id].get("hidden", false)):
			life.buy(id)
	life.party()
	var scene: PackedScene = load("res://scenes/home.tscn")
	for hid in ["rented_room", "apartment", "loft", "seaside_flat", "townhouse", "house", "villa", "penthouse", "sky_duplex"]:
		life.home = hid
		var h: Home = scene.instantiate()
		add_child(h)
		await get_tree().process_frame
		# Whole home in view.
		var vs := get_viewport().get_visible_rect().size
		var z := zoom if zoom > 0.0 else minf(vs.x / (h.W * Home.CELL + 40.0), vs.y / (h.H * Home.CELL + 40.0))
		h.cam.zoom = Vector2(z, z)
		h.pos = Vector2(h.W, h.H) * Home.CELL * 0.5 if zoom <= 0.0 else h.pos
		h.cam.position_smoothing_enabled = false
		for i in 20:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s/home_%s.png" % [out, hid])
		h.queue_free()
		await get_tree().process_frame
	get_tree().quit()
