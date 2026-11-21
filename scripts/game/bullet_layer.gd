class_name BulletLayer
extends Node2D
## Hitscan shots: a single raycast resolves the hit instantly. This node only
## draws short-lived tracers and impact puffs.

const WALL_MASK := 1
const UNIT_MASK := 2
const TRACER_TIME := 0.07
const IMPACT_TIME := 0.12

var _tracers: Array[Dictionary] = []
var _impacts: Array[Dictionary] = []


func fire(shooter: Unit, origin: Vector2, dir: Vector2, w: WeaponData, exclude: Array[RID]) -> void:
	var to := origin + dir * Unit.BULLET_RANGE
	var q := PhysicsRayQueryParameters2D.create(origin, to, WALL_MASK | UNIT_MASK, exclude)
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	var end := to
	if not hit.is_empty():
		end = hit.position
		var col = hit.collider
		if col is Unit:
			# Decided before the damage: a kill mustn't reveal a body you couldn't see.
			var seen: bool = get_parent().user_sees(col)
			var dealt := (col as Unit).take_damage(w.damage_at(origin.distance_to(end)), shooter, w.armor_pen)
			get_parent().register_damage(shooter, dealt)
			get_parent().blood.hit(col, end, dir, dealt, not (col as Unit).alive, not seen)
			if seen: # No red puff on someone you can't see (smoke, fog): that's a wallhack.
				_impacts.append({"pos": end, "t": IMPACT_TIME, "color": Color(1.0, 0.3, 0.25)})
			_play("lockdown_bullet_impact_body", end, -2.0)
		else:
			_impacts.append({"pos": end, "t": IMPACT_TIME, "color": Color(1.0, 0.9, 0.6)})
			_play("lockdown_bullet_impact_wall", end, -6.0)
	if not get_parent().utility.smokes.is_empty():
		get_parent().utility.on_bullet(origin, end)
	_check_flyby(shooter, origin, end)
	get_parent().on_shot(shooter, origin, end)
	_tracers.append({"from": origin + dir * (Unit.RADIUS + 10.0), "to": end, "t": TRACER_TIME})
	queue_redraw()


func _play(sound: String, pos: Vector2, volume_db: float) -> void:
	var sfx: Sfx = get_parent().sfx
	if sfx != null:
		sfx.play(sound, pos, volume_db, 0.1)


## Enemy shot passed close to the unit we're listening as (and didn't hit it): whizz.
func _check_flyby(shooter: Unit, from: Vector2, to: Vector2) -> void:
	var listener: Unit = get_parent()._camera_target()
	if listener == null or not listener.alive or listener == shooter or listener.side == shooter.side:
		return
	var closest := Geometry2D.get_closest_point_to_segment(listener.global_position, from, to)
	var d := closest.distance_to(listener.global_position)
	if d > Unit.RADIUS + 2.0 and d < 70.0:
		_play("bullet_flyby", closest, -4.0)


func clear_all() -> void:
	_tracers.clear()
	_impacts.clear()
	queue_redraw()


func _process(delta: float) -> void:
	if _tracers.is_empty() and _impacts.is_empty():
		return
	for t in _tracers:
		t.t -= delta
	for i in _impacts:
		i.t -= delta
	_tracers = _tracers.filter(func(t: Dictionary) -> bool: return t.t > 0.0)
	_impacts = _impacts.filter(func(i: Dictionary) -> bool: return i.t > 0.0)
	queue_redraw()


func _draw() -> void:
	for t in _tracers:
		var a: float = t.t / TRACER_TIME
		draw_line(t.from, t.to, Color(1.0, 0.92, 0.6, 0.55 * a), 1.5)
	for imp in _impacts:
		var k: float = imp.t / IMPACT_TIME
		draw_circle(imp.pos, 3.0 + (1.0 - k) * 4.0, Color(imp.color, k))
