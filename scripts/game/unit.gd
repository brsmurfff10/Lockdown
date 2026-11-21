class_name Unit
extends CharacterBody2D
## A soldier on the field. A child PlayerController or BotController writes
## move_input / aim_dir and calls try_fire() / begin_action().

signal died(unit: Unit, killer: Unit)
signal damaged(source: Unit, amount: float)
signal action_finished(unit: Unit, action: int)

enum Action { NONE, PLANT, DEFUSE }

const RADIUS := 12.0
const MAX_HEALTH := 100.0
## Sight lines and shots may use points this far off-centre (fraction of RADIUS).
## 0.3 means about a third of your body (~8px) must be past a corner before you
## can see or shoot (or be seen/shot) — no more hits on a 2px sliver.
const SHOULDER := 0.3
const PLAN_TEXT := {"hold": "holding the contact", "jiggle": "jiggle peek for info", "swing": "swinging",
	"push": "pushing the contact", "fallback": "falling back", "cover": "covering a reload",
	"bait": "shoulder bait", "reposition": "repositioning", "flank": "flanking", "spam": "spraying the smoke"}
const BULLET_RANGE := 6000.0 ## Bullets fly until they hit something.
const ARMOR_ABSORB := 0.35
const HELMET_ABSORB := 0.42 ## Kevlar + helmet protects a bit more.
const SCOPE_IN_TIME := 0.3
const SIDE_COLORS := [Color(0.88, 0.62, 0.30), Color(0.35, 0.60, 0.95)]
const ACCEL := 1500.0 ## px/s^2 speeding up.
const DECEL := 2000.0 ## px/s^2 slowing down (stop from full speed in ~0.1s).
const ACCURATE_SPEED_FRAC := 0.25 ## Below this fraction of top speed you're fully accurate.
const PLANT_CLICK_INTERVAL := 0.5 ## Seconds between bomb-plant clicks.
const STRIDE_TIME := 0.33 ## Seconds between running footsteps.
const RUN_FRAC := 0.7 ## Above this fraction of top speed you're running (audible).
const DRAW_TIME := 1.0 ## Seconds to bring up any weapon (gun, pistol, knife, grenade) before it can be used.
const KNIFE_RANGE := 34.0 ## Reach past the body edge.
const KNIFE_ARC := 0.6 ## cos of the half-angle the swipe covers (~53 deg each side).
const KNIFE_DAMAGE := 40.0
const KNIFE_BACKSTAB := 150.0 ## From behind: a kill even through armour.
const KNIFE_COOLDOWN := 0.55
const KNIFE_SPEED := 1.06 ## Running with the knife out is the fastest you move.
const KNIFE_REWARD := 1500
const SLASH_TIME := 0.24

var data: PlayerData
var side: int = 0 ## 0 = T, 1 = CT. Used for friend/foe.
var team_index: int = 0 ## Which TeamData in the match.
var match_node ## The Match that owns this unit.

var primary: WeaponData = null
var pistol: WeaponData
var weapon: WeaponData ## Currently held.

var health: float = MAX_HEALTH
var armor: float = 0.0
var has_kit: bool = false
var helmet: bool = false
var has_bomb: bool = false
var grenades: Dictionary = {} ## kind -> count (see Utility).
var held_grenade: String = "" ## You only: grenade in hand (4 cycles), "" = gun.
var knife_out: bool = false ## Knife in hand (3) instead of `weapon`.
var draw_t: float = 0.0 ## Still bringing the current weapon up (can't fire / throw yet).
var slash_t: float = 0.0 ## Knife swipe animation time left.
var slash_dir: float = 1.0 ## Alternates the swipe direction.
var flash_t: float = 0.0 ## Seconds of blindness left.
var alive: bool = true

var reloading: bool = false
var reload_timer: float = 0.0
var fire_cooldown: float = 0.0
var bloom: float = 0.0
var since_shot: float = 10.0
var aim_dir: Vector2 = Vector2.RIGHT
var move_input: Vector2 = Vector2.ZERO
var wants_scope: bool = false ## Player: right mouse. Bots: set automatically (auto_scope).
var auto_scope: bool = true ## Bots scope in whenever they stand (nearly) still.
var scope_t: float = 0.0 ## 0 unscoped .. 1 fully scoped.

var action: int = Action.NONE
var action_timer: float = 0.0
var action_total: float = 0.0

var _hit_flash: float = 0.0
var _muzzle_flash: float = 0.0
var _plant_click_timer: float = 0.0
var _stride_timer: float = 0.0
var _empty_click_cd: float = 0.0
var _hit_dirs: Array[Dictionary] = [] ## {dir, t}: where recent damage came from (user only).
var _aim_len: float = 0.0 ## User only: distance along the aim to the first wall.
const AIM_LINE_MAX := 1600.0


func setup(p_data: PlayerData, p_side: int, p_team_index: int, p_match) -> void:
	data = p_data
	side = p_side
	team_index = p_team_index
	match_node = p_match
	pistol = WeaponData.by_id(WeaponData.starter(p_side))
	weapon = pistol


## Secondary slot: a bought / picked-up pistol replaces the one you hold.
func give_pistol(weapon_id: int) -> void:
	var was_held := weapon == pistol
	pistol = WeaponData.by_id(weapon_id)
	if was_held or primary == null:
		weapon = pistol
		reloading = false
		fire_cooldown = 0.25
		bloom = 0.0
		scope_t = 0.0


## Picked up from the floor (keeps its ammo).
func take_pistol(w: WeaponData) -> void:
	var was_held := weapon == pistol
	pistol = w
	if (was_held or primary == null) and action == Action.NONE:
		weapon = w
		reloading = false
		fire_cooldown = 0.3
		bloom = 0.0
		scope_t = 0.0


func give_primary(weapon_id: int) -> void:
	primary = WeaponData.by_id(weapon_id)
	_switch_to(primary)


## Picked up from the floor: keeps that gun's ammo.
func take_primary(w: WeaponData) -> void:
	primary = w
	if action == Action.NONE:
		weapon = w
		reloading = false
		fire_cooldown = 0.3
		bloom = 0.0
		scope_t = 0.0


func blind(seconds: float) -> void:
	flash_t = maxf(flash_t, seconds)


func is_blind() -> bool:
	return flash_t > 0.35


## 4: next grenade you carry (then back to your gun).
func cycle_grenade() -> void:
	var owned: Array[String] = []
	for k: String in Utility.KINDS:
		if int(grenades.get(k, 0)) > 0:
			owned.append(k)
	if owned.is_empty():
		held_grenade = ""
		return
	var i := owned.find(held_grenade)
	var before := held_grenade
	held_grenade = owned[i + 1] if i >= 0 and i + 1 < owned.size() else (owned[0] if i < 0 else "")
	if held_grenade != before:
		_start_draw()


func select_primary() -> void:
	if primary != null:
		_switch_to(primary)


func select_pistol() -> void:
	_switch_to(pistol)


## 3: the knife. Fastest to run with; a swipe in front, a backstab kills.
func select_knife() -> void:
	if action != Action.NONE or (knife_out and held_grenade == ""):
		return
	held_grenade = ""
	knife_out = true
	reloading = false
	scope_t = 0.0
	fire_cooldown = 0.0
	_start_draw()


## Q: last gun / other gun (from the knife or a grenade: back to the gun you had).
func swap_weapon() -> void:
	if knife_out or held_grenade != "":
		_switch_to(weapon)
	elif weapon == pistol:
		select_primary()
	else:
		select_pistol()


func _switch_to(w: WeaponData) -> void:
	if action != Action.NONE or (w == weapon and not knife_out and held_grenade == ""):
		return
	held_grenade = ""
	knife_out = false
	weapon = w
	reloading = false
	fire_cooldown = 0.0
	bloom = 0.0
	scope_t = 0.0
	_start_draw()


## Bringing a weapon up takes DRAW_TIME (CS-style deploy): no shooting, slashing
## or throwing until it's ready.
func _start_draw() -> void:
	draw_t = DRAW_TIME
	if alive and is_inside_tree() and match_node != null and match_node.sfx != null:
		_sfx("weapon_draw", -10.0, 0.08)


func is_drawing() -> bool:
	return draw_t > 0.0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS # Gun sprites are downscaled renders.
	collision_layer = 2
	collision_mask = 3
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	var shape := CircleShape2D.new()
	shape.radius = RADIUS
	var cs := CollisionShape2D.new()
	cs.shape = shape
	add_child(cs)


func _physics_process(delta: float) -> void:
	_hit_flash = maxf(0.0, _hit_flash - delta)
	flash_t = maxf(0.0, flash_t - delta)
	draw_t = maxf(0.0, draw_t - delta)
	slash_t = maxf(0.0, slash_t - delta)
	if held_grenade != "" and int(grenades.get(held_grenade, 0)) <= 0:
		held_grenade = ""
	_muzzle_flash = maxf(0.0, _muzzle_flash - delta)
	if data != null and data.is_user and alive and match_node != null:
		_aim_len = match_node._wall_distance(global_position, aim_dir, AIM_LINE_MAX)
	if not _hit_dirs.is_empty():
		for h in _hit_dirs:
			h.t -= delta
		_hit_dirs = _hit_dirs.filter(func(h: Dictionary) -> bool: return h.t > 0.0)
	if not alive:
		return
	fire_cooldown = maxf(0.0, fire_cooldown - delta)
	since_shot += delta
	_update_scope(delta)
	if since_shot > 1.3 / weapon.fire_rate:
		bloom = move_toward(bloom, 0.0, weapon.recoil_recovery * delta)
	if reloading:
		reload_timer -= delta
		if reload_timer <= 0.0:
			reloading = false
			weapon.ammo = weapon.mag_size

	_empty_click_cd = maxf(0.0, _empty_click_cd - delta)
	if action != Action.NONE:
		velocity = Vector2.ZERO
		if action == Action.PLANT:
			# Click every 0.5s while planting; stops the moment the plant is cancelled.
			_plant_click_timer -= delta
			if _plant_click_timer <= 0.0 and action_timer > delta:
				_plant_click_timer += PLANT_CLICK_INTERVAL
				_sfx("lockdown_bomb_plant_click", -2.0)
		elif action == Action.DEFUSE:
			# Tool rattle while defusing: Ts can hear it from across the site.
			_plant_click_timer -= delta
			if _plant_click_timer <= 0.0 and action_timer > delta:
				_plant_click_timer += 0.45
				_sfx("bomb_defuse", -8.0, 0.08) # -8 dB: 60% quieter
		action_timer -= delta
		if action_timer <= 0.0:
			var finished := action
			action = Action.NONE
			action_finished.emit(self, finished)
	else:
		var target := move_input.limit_length(1.0) * top_speed()
		var rate := ACCEL if target.length() > velocity.length() else DECEL
		velocity = velocity.move_toward(target, rate * delta)
		move_and_slide()
		# Running is loud; walking (slow) is silent.
		if velocity.length() > top_speed() * RUN_FRAC:
			_stride_timer -= delta
			if _stride_timer <= 0.0:
				_stride_timer = STRIDE_TIME
				_sfx("lockdown_footstep", -8.0, 0.12)
		else:
			_stride_timer = 0.0
	queue_redraw()


func top_speed() -> float:
	var s := data.move_speed() * (KNIFE_SPEED if knife_out and held_grenade == "" else weapon.move_mult)
	if scope_t > 0.0:
		s *= lerpf(1.0, 0.55, scope_t)
	return s


## Scoped guns: scoping in takes SCOPE_IN_TIME and removes the unscoped spread.
## Bots scope whenever they're (nearly) standing still; the player holds right mouse.
func _update_scope(delta: float) -> void:
	if not weapon.scope or held_grenade != "" or knife_out:
		scope_t = 0.0
		return
	if auto_scope:
		wants_scope = velocity.length() < data.move_speed() * 0.3 and action == Action.NONE
	if wants_scope and not reloading:
		scope_t = minf(1.0, scope_t + delta / SCOPE_IN_TIME)
	else:
		scope_t = maxf(0.0, scope_t - delta / 0.12)


func is_scoped() -> bool:
	return scope_t >= 0.99


func is_moving() -> bool:
	return velocity.length() > top_speed() * ACCURATE_SPEED_FRAC


## 0 when still/walking slowly, 1 at full run speed.
func movement_penalty_frac() -> float:
	var frac := velocity.length() / maxf(top_speed(), 1.0)
	return clampf((frac - ACCURATE_SPEED_FRAC) / (1.0 - ACCURATE_SPEED_FRAC), 0.0, 1.0)


## Total cone width in degrees for the next shot.
func current_spread() -> float:
	var spread := data.spread_degrees() * weapon.spread_mult + weapon.base_spread + bloom
	spread += weapon.moving_inaccuracy * movement_penalty_frac() * data.moving_penalty_mult()
	if weapon.scope:
		spread += weapon.unscoped_spread * (1.0 - scope_t)
	return spread


func _sfx(sound: String, volume_db: float = 0.0, pitch_jitter: float = 0.05) -> void:
	if match_node != null and match_node.sfx != null:
		match_node.sfx.play(sound, global_position, volume_db, pitch_jitter)


func try_fire() -> bool:
	if not alive or action != Action.NONE or draw_t > 0.0:
		return false
	if knife_out:
		return _slash()
	if weapon.ammo <= 0:
		# Dry trigger pull.
		if _empty_click_cd <= 0.0:
			_empty_click_cd = 0.3
			_sfx("lockdown_empty_ammo", -4.0)
		start_reload()
		return false
	if reloading or fire_cooldown > 0.0:
		return false
	weapon.ammo -= 1
	fire_cooldown = 1.0 / weapon.fire_rate
	_muzzle_flash = 0.05
	_sfx(Sfx.shot_sound(weapon, side), 0.0, 0.04)
	var spread := current_spread()
	for i in weapon.pellets:
		var dir := aim_dir.rotated(deg_to_rad(randf_range(-spread, spread) * 0.5))
		match_node.spawn_bullet(self, global_position, dir)
	bloom = minf(weapon.max_bloom, bloom + weapon.recoil * data.recoil_mult())
	since_shot = 0.0
	if weapon.ammo == 0:
		start_reload()
	return true


func start_reload() -> void:
	if reloading or not alive or weapon.ammo == weapon.mag_size or action != Action.NONE or knife_out:
		return
	reloading = true
	reload_timer = weapon.reload_time
	_sfx("rifle_reload", -3.0)
	if match_node != null:
		match_node.on_reload(self)


## Knife swipe: hits the nearest enemy in reach in front of you. From behind
## (they're facing away) it's a backstab.
func _slash() -> bool:
	if fire_cooldown > 0.0:
		return false
	fire_cooldown = KNIFE_COOLDOWN
	slash_t = SLASH_TIME
	slash_dir = -slash_dir
	since_shot = 0.0
	_sfx("knife_slash", -2.0, 0.1)
	var best: Unit = null
	var best_d := INF
	for e: Unit in match_node.units:
		if e == self or not e.alive or e.side == side:
			continue
		var to := e.global_position - global_position
		var d := to.length()
		if d > KNIFE_RANGE + RADIUS * 2.0 or d >= best_d:
			continue
		if d > 1.0 and aim_dir.dot(to / d) < KNIFE_ARC:
			continue
		if not match_node.has_wall_los(global_position, e.global_position):
			continue
		best = e
		best_d = d
	if best == null:
		return true
	var back := best.aim_dir.dot((global_position - best.global_position).normalized()) < -0.25
	_sfx("knife_hit", 0.0, 0.08)
	var dealt := best.take_damage(KNIFE_BACKSTAB if back else KNIFE_DAMAGE, self, 0.85)
	match_node.on_knife_hit(self, best, dealt)
	return true


## A grenade just left your hand: the next one of that kind comes up (player),
## or your gun does. Either way it takes DRAW_TIME before you can use it.
func on_threw(kind: String) -> void:
	if held_grenade != "" and int(grenades.get(kind, 0)) > 0:
		_start_draw()
		return
	held_grenade = ""
	knife_out = false
	reloading = false
	_start_draw()


## Money for a kill with what's in your hands.
func kill_reward() -> int:
	return KNIFE_REWARD if knife_out else weapon.kill_reward


func begin_action(kind: int, duration: float) -> void:
	if action != Action.NONE or not alive:
		return
	action = kind
	action_total = duration
	action_timer = duration
	if kind == Action.DEFUSE:
		_plant_click_timer = 0.35
		_sfx("bomb_defuse_start", 0.0, 0.03)
	_plant_click_timer = 0.0 # First click immediately, then every 0.5s.
	reloading = false
	move_input = Vector2.ZERO


func cancel_action() -> void:
	action = Action.NONE


func action_progress() -> float:
	if action == Action.NONE or action_total <= 0.0:
		return 0.0
	return 1.0 - action_timer / action_total


## `pen`: share of the armour's protection the weapon ignores (WeaponData.armor_pen).
func take_damage(amount: float, source: Unit, pen: float = 0.0) -> float:
	if not alive:
		return 0.0
	if armor > 0.0:
		var absorb := (HELMET_ABSORB if helmet else ARMOR_ABSORB) * (1.0 - clampf(pen, 0.0, 1.0))
		var absorbed := minf(amount * absorb, armor)
		armor -= absorbed
		amount -= absorbed
	var dealt := minf(amount, health)
	health -= amount
	_hit_flash = 0.1
	if data.is_user and source != null and is_instance_valid(source):
		_hit_dirs.append({"dir": (source.global_position - global_position).normalized(), "t": 1.5})
	damaged.emit(source, dealt)
	if health <= 0.0:
		health = 0.0
		_die(source)
	return dealt


func _die(killer: Unit) -> void:
	alive = false
	action = Action.NONE
	velocity = Vector2.ZERO
	move_input = Vector2.ZERO
	set_deferred("collision_layer", 0)
	z_index = -1
	queue_redraw()
	died.emit(self, killer)


func _draw() -> void:
	var side_color: Color = SIDE_COLORS[side]
	var sprite := PlayerArt.has(side)
	var who: String = data.player_name if data != null else String(name)
	var pose := PlayerArt.pose_for(weapon, held_grenade != "" or knife_out)
	if not alive:
		if sprite:
			draw_circle(Vector2.ZERO, RADIUS, Color(side_color.darkened(0.6), 0.45))
			PlayerArt.draw_body(self, side, who, pose, aim_dir, Color(0.42, 0.4, 0.4))
			return
		draw_circle(Vector2.ZERO, RADIUS, side_color.darkened(0.7))
		draw_line(Vector2(-6, -6), Vector2(6, 6), Color(0, 0, 0, 0.7), 3.0)
		draw_line(Vector2(-6, 6), Vector2(6, -6), Color(0, 0, 0, 0.7), 3.0)
		return

	var body_color := Color.WHITE if _hit_flash > 0.0 else side_color
	var gun_len := 9.0
	match weapon.cat:
		WeaponData.RIFLE, WeaponData.HEAVY:
			gun_len = 14.0
		WeaponData.SNIPER:
			gun_len = 19.0
		WeaponData.SMG, WeaponData.SHOTGUN:
			gun_len = 11.0
	var muzzle := aim_dir * (RADIUS + gun_len)
	var mp := GunArt.muzzle_point(weapon, aim_dir, side, pose)
	if mp != Vector2.INF:
		muzzle = mp
	if sprite:
		# Team base, the gun (stock hidden under the body, barrel out past the hands), the body.
		draw_circle(Vector2.ZERO, RADIUS, Color(side_color, 0.3))
		draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 32, Color(side_color, 0.95), 1.6)
		if not knife_out or held_grenade != "":
			_draw_held(muzzle, pose)
		PlayerArt.draw_body(self, side, who, pose, aim_dir, Color(2.6, 2.6, 2.6) if _hit_flash > 0.0 else PlayerArt.TINT)
		if knife_out and held_grenade == "":
			_draw_held(muzzle, pose) # The blade shows over the arm, out in front.
	else:
		_draw_held(muzzle, pose)
		draw_circle(Vector2.ZERO, RADIUS, body_color)
		draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 24, Color(0, 0, 0, 0.8), 2.0)
		draw_circle(aim_dir * 5.0, 4.0, body_color.lightened(0.35))
	if _muzzle_flash > 0.0:
		draw_circle(muzzle + aim_dir * 2.0, 5.0, Color(1.0, 0.9, 0.45))
	if scope_t > 0.5 and weapon.is_sniper() and not data.is_user and not knife_out:
		# Scoped-in sniper: a faint glint line down the angle they're holding.
		draw_line(muzzle, aim_dir * 260.0, Color(0.6, 0.85, 1.0, 0.18 * scope_t), 1.0)
	if flash_t > 0.35:
		draw_arc(Vector2.ZERO, RADIUS + 2.0, 0.0, TAU, 20, Color(1, 1, 1, minf(0.9, flash_t)), 3.0)
	if has_bomb:
		if not GunArt.draw_bomb_on_back(self, aim_dir):
			draw_rect(Rect2(-aim_dir * 9.0 - Vector2(4, 4), Vector2(8, 8)), Color(0.85, 0.15, 0.15))
	if data.is_user:
		draw_arc(Vector2.ZERO, RADIUS + 4.0, 0.0, TAU, 32, Color(1.0, 0.95, 0.4, 0.9), 2.0)
		# Red arcs pointing at whoever just hit you (works for off-screen shooters).
		for h in _hit_dirs:
			var ang: float = (h.dir as Vector2).angle()
			var a: float = clampf(h.t / 1.5, 0.0, 1.0)
			draw_arc(Vector2.ZERO, RADIUS + 22.0, ang - 0.45, ang + 0.45, 16, Color(1.0, 0.15, 0.1, 0.85 * a), 5.0)
		# Aim line: where your shot goes, stopping at the first wall.
		var start := aim_dir * (RADIUS + 16.0)
		var end := aim_dir * maxf(_aim_len, RADIUS + 16.0)
		draw_line(start, end, Color(1.0, 0.95, 0.6, 0.28), 1.5, true)
		draw_circle(end, 3.0, Color(1.0, 0.95, 0.6, 0.6))
		# Spread cone so you can feel run-and-gun vs standing still.
		var half := deg_to_rad(current_spread() * 0.5)
		var cone_col := Color(1, 1, 1, 0.18)
		draw_line(aim_dir.rotated(-half) * (RADIUS + 16.0), aim_dir.rotated(-half) * 150.0, cone_col, 1.0)
		draw_line(aim_dir.rotated(half) * (RADIUS + 16.0), aim_dir.rotated(half) * 150.0, cone_col, 1.0)

	if reloading:
		var t := 1.0 - reload_timer / weapon.reload_time
		draw_arc(Vector2.ZERO, RADIUS + 7.0, -PI / 2.0, -PI / 2.0 + TAU * t, 32, Color(1, 1, 1, 0.8), 2.0)
	if action != Action.NONE:
		var col := Color(1.0, 0.35, 0.3) if action == Action.PLANT else Color(0.4, 0.8, 1.0)
		draw_arc(Vector2.ZERO, RADIUS + 9.0, -PI / 2.0, -PI / 2.0 + TAU * action_progress(), 40, col, 3.0)

	if match_node == null or match_node.shows_health(self): # Enemy health is hidden while you play.
		var bar := Rect2(-16, -RADIUS - 12, 32, 4)
		draw_rect(bar, Color(0, 0, 0, 0.6))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * health / MAX_HEALTH, bar.size.y)), Color(0.4, 0.95, 0.4))
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(-50, -RADIUS - 16), data.player_name, HORIZONTAL_ALIGNMENT_CENTER, 100, 11, Color(1, 1, 1, 0.85))
	if match_node != null and (match_node.is_spectating() or match_node.shows_intent(self)):
		# One short line, faint (80% transparent) so it doesn't crowd the screen.
		var line: String = match_node.tactics.debug_label(self)
		for c in get_children():
			if c is BotController and (c as BotController).plan != "":
				line = PLAN_TEXT.get((c as BotController).plan, (c as BotController).plan)
		if line.length() > 34:
			line = line.substr(0, 33) + "."
		draw_string(font, Vector2(-90, RADIUS + 12), line, HORIZONTAL_ALIGNMENT_CENTER, 180, 8, Color(1, 0.9, 0.5, 0.2))


## The grenade or gun in hand (gun art when available, else a line to `muzzle`).
func _draw_held(muzzle: Vector2, pose: String) -> void:
	# Still bringing it up: held low and to the right, swinging up into the aim.
	var d := aim_dir.rotated(0.85 * ease(draw_t / DRAW_TIME, 1.6)) if draw_t > 0.0 else aim_dir
	if knife_out and held_grenade == "":
		GunArt.draw_knife(self, d, side, pose, 1.0 - slash_t / SLASH_TIME if slash_t > 0.0 else 0.0, slash_dir)
	elif held_grenade != "":
		var at := PlayerArt.grip(d, pose) if PlayerArt.has(side) else d * (RADIUS + 3.0)
		if not GunArt.draw_grenade(self, held_grenade, side, at, d.angle(), GunArt.GRENADE_HELD_PX):
			draw_circle(at, 4.5, Color(0, 0, 0, 0.8))
			draw_circle(at, 3.2, Utility.COLORS[held_grenade])
	elif not GunArt.draw_held(self, weapon, d, side, pose, Vector2.ZERO, GunArt.user_finish if data != null and data.is_user else Color(0, 0, 0, 0)):
		draw_line(aim_dir * 4.0, muzzle, Color(0.1, 0.1, 0.1), 5.0)
