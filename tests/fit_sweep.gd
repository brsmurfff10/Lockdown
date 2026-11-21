extends Node
## Fullscreen fit sweep: at the fullscreen base size (1280x720), opens every
## page of both career hubs, presses every button on it (and every button in
## any popup that opens), and reports anything that ends up wider than the
## screen. Buttons that leave the hub (matches, menus, careers) are skipped.
## Run:  godot --path . res://tests/fit_sweep.tscn -- --test [--out=<dir>]

const SKIP := ["Main Menu", "Play Match", "Play", "Watch", "Watch from the bench", "Simulate", "Coach", "New manager career",
	"Start a manager career", "Retire", "Take the job", "Advance Week", "Forfeit"]

var fails := 0
var checked := 0
var out := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	get_window().size = Vector2i(1280, 720)
	await get_tree().process_frame
	# My Player, with offers, endorsements and a request so every row exists.
	Game.end_career()
	Game.create_my_player("Fitcheck", "Rifler", "Canada")
	Game.start_career()
	var pw := Game.pworld
	pw.wallet = 500000
	pw.fame = 30000
	pw.endorsements = [{"brand": "Nightowl Headsets", "weekly": 450, "weeks": 18}]
	for i in 3:
		pw._add_offer(i if pw.teams[i] != pw.user_team() else i + 10, "%s like your form and want you to lead their lineup next season, no questions asked." % pw.teams[i].team_name)
	for i in 8:
		pw.advance_week()
		if not pw.user_match_this_week().is_empty():
			pw.sim_user_match()
			pw.advance_week()
	await _sweep_hub(Game.CAREER_SCENE, "player")
	# Manager.
	var nw := Game.new_manager_world()
	Game.start_manager_career(nw, nw.team_index(nw.league_teams(3)[2]), "Fit Check Esports", "FIT", Color.ORANGE)
	var w := Game.world
	for i in 8:
		var r := w.advance_week()
		if r == "play_match":
			w.sim_user_match()
			w.advance_week()
	w.job_offers = [{"team": 5, "note": "A very long note about a club that wants you as their manager after a strong season.", "forced": false}]
	await _sweep_hub(Game.MANAGER_SCENE, "manager")
	Game.end_career()
	print("fit_sweep: %d checks, %d overflow(s)" % [checked, fails])
	get_tree().quit()


func _sweep_hub(scene: String, tag: String) -> void:
	var hub: Node = load(scene).instantiate()
	add_child(hub)
	await _frames(4)
	_close(hub)
	for pg: String in hub.PAGES:
		var views: Array = ["Free agents", "Other clubs", "Offers"] if pg == "Transfers" else [""]
		for v: String in views:
			if v != "":
				hub._portal_view = v
			hub._show(pg)
			await _frames(4)
			await _check(hub, "%s/%s%s" % [tag, pg, ("/" + v) if v != "" else ""])
			var labels := _button_texts(hub)
			for txt: String in labels:
				hub._show(pg)
				await _frames(2)
				var b := _find_button(hub, txt)
				if b == null or b.disabled or not b.is_visible_in_tree():
					continue
				b.emit_signal("pressed")
				await _frames(4)
				await _check(hub, "%s/%s -> [%s]" % [tag, pg, txt])
				# Buttons inside a popup that just opened.
				var pop := _overlay(hub)
				if pop != null:
					for ptxt: String in _button_texts(pop):
						if ptxt in ["Close", "Cancel", "Continue"] or SKIP.has(ptxt) or _leaves(ptxt):
							continue
						var pb := _find_button(pop, ptxt)
						if pb == null or pb.disabled:
							continue
						pb.emit_signal("pressed")
						await _frames(4)
						await _check(hub, "%s/%s -> [%s] -> [%s]" % [tag, pg, txt, ptxt])
						pop = _overlay(hub)
						if pop == null:
							break
				_close(hub)
	hub.queue_free()
	await _frames(2)


func _check(hub: Node, where: String) -> void:
	checked += 1
	var vw := get_viewport().get_visible_rect().size.x
	var worst := 0.0
	var what := ""
	for c in hub.get_children():
		if c is Control and (c as Control).visible:
			var e := (c as Control).get_global_rect().end.x
			if e > worst:
				worst = e
				what = c.get_class()
			# Popup panels inside overlays.
			for cc in c.get_children():
				for p in cc.get_children():
					if p is Control and (p as Control).get_global_rect().end.x > worst:
						worst = (p as Control).get_global_rect().end.x
						what = "popup panel"
	if worst > vw + 1.0:
		fails += 1
		print("OVERFLOW  %s: %s reaches %.0f / %.0f" % [where, what, worst, vw])
		if out != "":
			get_viewport().get_texture().get_image().save_png("%s/fit_%d.png" % [out, fails])


func _button_texts(root: Node) -> Array:
	var out_t: Array = []
	for b in _buttons(root):
		var t := (b as Button).text.strip_edges()
		if t != "" and not out_t.has(t) and not SKIP.has(t) and not _leaves(t):
			out_t.append(t)
	return out_t


## Buttons that start a match or leave the hub (they'd end the sweep).
func _leaves(t: String) -> bool:
	for pre in ["Main Menu", "Watch", "Play", "Simulate", "Coach", "Start a", "New manager", " vs ", "Go home", "Tour", "Visit"]:
		if t.begins_with(pre) or (pre == " vs " and t.contains(pre)):
			return true
	return false


func _buttons(n: Node) -> Array:
	var r: Array = []
	for c in n.get_children():
		if c is NewsTicker:
			continue
		if c is Button and not (c is OptionButton) and (c as Control).is_visible_in_tree():
			r.append(c)
		r.append_array(_buttons(c))
	return r


func _find_button(root: Node, txt: String) -> Button:
	for b in _buttons(root):
		if (b as Button).text.strip_edges() == txt:
			return b
	return null


func _overlay(hub: Node) -> Node:
	for c in hub.get_children():
		if c is ColorRect and not c.is_queued_for_deletion():
			return c
	return null


func _close(hub: Node) -> void:
	for c in hub.get_children():
		if c is ColorRect:
			c.queue_free()
	if hub.has_method("_close_scout"):
		hub._close_scout()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
