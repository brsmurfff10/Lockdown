class_name PlayerController
extends Node
## Drives a Unit from keyboard + mouse.

var unit: Unit


func _physics_process(_delta: float) -> void:
	if not unit.alive:
		return
	var mouse := unit.get_global_mouse_position()
	if mouse.distance_to(unit.global_position) > 1.0:
		unit.aim_dir = (mouse - unit.global_position).normalized()

	unit.auto_scope = false
	# Scoped guns: hold right mouse to scope in (slower, but no unscoped spread).
	unit.wants_scope = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if unit.match_node.buy_menu_open:
		pass # Number keys drive the buy menu.
	elif Input.is_action_just_pressed("weapon_1"):
		unit.select_primary()
	elif Input.is_action_just_pressed("weapon_2"):
		unit.select_pistol()
	elif Input.is_action_just_pressed("weapon_3"):
		unit.select_knife()
	elif Input.is_action_just_pressed("swap_weapon"):
		unit.swap_weapon()
	elif Input.is_action_just_pressed("grenade"):
		unit.cycle_grenade()

	if Input.is_action_just_pressed("request_bomb"):
		unit.match_node.request_bomb(unit)
	if Input.is_action_just_pressed("drop"):
		unit.match_node.drop_item(unit)

	if not unit.match_node.can_fight():
		unit.move_input = Vector2.ZERO
		return

	if Input.is_action_just_pressed("pickup"):
		unit.match_node.pickup_gun(unit)

	# Plant / defuse: hold E.
	if Input.is_action_pressed("use"):
		if unit.action == Unit.Action.NONE:
			unit.match_node.request_action(unit)
	elif unit.action != Unit.Action.NONE:
		unit.cancel_action()

	unit.move_input = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if unit.action != Unit.Action.NONE and unit.move_input != Vector2.ZERO:
		unit.cancel_action()

	if unit.held_grenade != "":
		# Grenade in hand: click throws it at the cursor (range-limited), then back to the gun.
		if Input.is_action_just_pressed("shoot") and unit.action == Unit.Action.NONE:
			var kind := unit.held_grenade
			unit.match_node.utility.throw(unit, kind, unit.get_global_mouse_position()) # Unit.on_threw picks what's next in hand.
		return
	var wants_fire := Input.is_action_pressed("shoot") if unit.weapon.automatic and not unit.knife_out else Input.is_action_just_pressed("shoot")
	if wants_fire:
		unit.try_fire()
	if Input.is_action_just_pressed("reload"):
		unit.start_reload()
