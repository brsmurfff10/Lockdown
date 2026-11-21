extends Node
## Bots can't spot or shoot the player from off the player's screen, and react
## slower to someone they didn't know about. Run:
##   godot --path . res://tests/fairness_probe.tscn --fixed-fps 60 -- --test --windowed

var m: Node
var fails := 0


func _ready() -> void:
	Game.prepare_quick_match("Dustline")
	Game.pending_match.mode = "test"
	m = load(Game.MATCH_SCENE).instantiate()
	add_child(m)
	await _physics(5)
	m.buy_menu_open = false
	await _physics(60 * 11)
	var me: Unit = m.user_unit
	var bot: Unit = null
	for u: Unit in m.units:
		if u.side != me.side and u.alive:
			bot = u
			break
	# Freeze every other unit out of the way.
	for u: Unit in m.units:
		if u != me and u != bot:
			u.global_position = m.arena.spawn_points(u.side)[0]
	var lane := _open_lane(1150.0)
	me.global_position = lane[0]
	bot.global_position = lane[1]
	bot.aim_dir = (me.global_position - bot.global_position).normalized()
	me.aim_dir = Vector2.LEFT # Look away so the camera lead doesn't pull the bot on screen.
	await _physics(30)
	var half: Vector2 = get_viewport().get_visible_rect().size / 2.0 / m.camera.zoom
	print("    screen half-extent %s, bot %.0f px away, cam center %s me %s bot %s user=%s" % [half, me.global_position.distance_to(bot.global_position), m.camera.get_screen_center_position(), me.global_position, bot.global_position, me.data.is_user])
	_check("off-screen bot with clear sight can't see you", m.has_wall_los(bot.global_position, me.global_position) and not m.sees(bot, me))
	# Same bot, now on screen.
	bot.global_position = me.global_position.lerp(bot.global_position, 0.45)
	bot.aim_dir = (me.global_position - bot.global_position).normalized()
	await _physics(2)
	_check("on-screen bot can see you", m.sees(bot, me))
	# Reaction: average spot time of a 60-rated bot, surprise vs expected.
	var bc: BotController = null
	for ch in bot.get_children():
		if ch is BotController:
			bc = ch
	var surprise := 0.0
	var expected := 0.0
	for i in 40:
		bc._target = null
		m.tactics.seen_by[bot.side].clear()
		bc._acquire(me)
		surprise += bc._reaction_left
		bc._target = null
		m.tactics.seen_by[bot.side][me] = {"pos": me.global_position, "time": m.round_clock}
		bc._acquire(me)
		expected += bc._reaction_left
	print("    base reaction %.2fs: surprised %.2fs, expected %.2fs" % [bot.data.reaction_time(), surprise / 40.0, expected / 40.0])
	_check("surprise is slower than expected contact", surprise > expected)
	print("FAIRNESS: %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit()


func _open_lane(dist: float) -> Array:
	var a: Arena = m.arena
	for y in range(4, a.H - 4, 2):
		for x in range(4, a.W - 4, 2):
			var p := a.cell_center(Vector2i(x, y))
			var q := p + Vector2(dist, 0)
			# Away from the map edges so the camera centres on the player.
			var far := a.cell_center(Vector2i(a.W - 1, a.H - 1))
			if p.x < 1000.0 or q.x > far.x - 200.0 or p.y < 560.0 or p.y > far.y - 560.0:
				continue
			if not a.is_solid(Vector2i(x, y)) and not a.is_solid(a.world_to_cell(q)) and m.has_wall_los(p, q):
				return [p, q]
	return [Vector2(300, 300), Vector2(300 + dist, 300)]


func _check(what: String, ok: bool) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		fails += 1


func _physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
