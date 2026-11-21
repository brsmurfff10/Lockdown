extends Node
## Bot AI depth: static helpers (team styles, habits), the F3 debug overlay
## (beliefs, stress, calls), IGL calls, enemy-economy reads and chat.
## Run:  godot --path . res://tests/ai_debug_probe.tscn -- --test --windowed --out=<dir>

var out := "user://ai_debug"
var m: Node
var fails := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = Vector2i(1600, 900)

	# --- Static helpers for the career UI ---
	var s1 := Tactics.team_style("Ironclad")
	_check("team_style is deterministic and valid (%s)" % s1, s1 == Tactics.team_style("Ironclad") and Tactics.TEAM_STYLES.has(s1))
	var styles := {}
	for n in ["Ironclad", "Frostbite", "Sunforge", "Nightjar", "Wildfire", "Granite", "Voltage", "Red Sharks", "Static Legion"]:
		styles[Tactics.team_style(n)] = true
	_check("several different team styles exist (%d)" % styles.size(), styles.size() >= 3)
	var p := PlayerData.new()
	p.player_name = "Habitual"
	p.uid = 4242
	p.role = "AWPer"
	var h1 := BotPersonality.habits(p)
	p.player_name = "Renamed"
	var h2 := BotPersonality.habits(p)
	_check("habits are 1-2, stable from the uid even after a rename (%s)" % [h1], h1.size() in [1, 2] and h1 == h2)
	_check("mistake_mult defaults to 1.0", BotController.mistake_mult == 1.0)

	# --- A watched bot match with the overlay on ---
	Game.autoplay = true
	Game.prepare_quick_match("Dustline")
	Game.pending_match.mode = "spectate" # No fog: the overlay is easy to read.
	m = load(Game.MATCH_SCENE).instantiate()
	add_child(m)
	await _physics(30)
	m.debug_ai = true
	m._zoom = 0.6
	var shot_taken := false
	_check("side styles set from team names", m.tactics.side_style[0] == Tactics.team_style(m.teams[m.team_of_side(0)].team_name))
	Engine.time_scale = 2.0
	var calls := {}
	var markers := 0
	var stressed := 0.0
	for i in 60 * 50:
		await get_tree().physics_frame
		for side in 2:
			if String(m.tactics.igl_call[side]) != "":
				calls[m.tactics.igl_call[side]] = true
		if i % 30 == 0:
			markers = maxi(markers, m.tactics.beliefs(0).size() + m.tactics.beliefs(1).size())
			for u: Unit in m.units:
				for c in u.get_children():
					if c is BotController:
						stressed = maxf(stressed, (c as BotController).stress)
		if not shot_taken and i > 60 * 14 and m.tactics.beliefs(0).size() + m.tactics.beliefs(1).size() >= 3:
			shot_taken = true
			# Follow someone who has a contact in mind.
			for u: Unit in m.units:
				for c in u.get_children():
					if c is BotController and u.alive and (c as BotController)._mem_conf > 0.3:
						m._spec_unit = u
			await _wait(20)
			_shot("ai_debug_beliefs")
		if i == 60 * 22:
			Engine.time_scale = 1.0
			m.chat(m.units[0], "nice shot", true)
			m.chat(m.units[6], "nt", true)
			await _wait(6)
			_shot("ai_debug_overlay")
			Engine.time_scale = 2.0
		if m.phase == m.Phase.MATCH_OVER:
			break
	Engine.time_scale = 1.0
	_check("IGL made calls this match (%d distinct)" % calls.size(), calls.size() >= 2)
	_check("belief markers were tracked (max %d at once)" % markers, markers >= 1)
	_check("someone felt stress (max %.2f)" % stressed, stressed > 0.1)
	await _wait(5)
	_shot("ai_debug_overlay2")
	print("  calls: ", calls.keys().slice(0, 8))
	print("AI DEBUG: %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit()


func _check(what: String, ok: bool) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		fails += 1


func _shot(name: String) -> void:
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])


func _physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
