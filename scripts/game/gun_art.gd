class_name GunArt
## Rendered gun sprites from art/blender/gun_kit.py (`sprites`):
##  <key>_side.png  lying on its side: floor drops, HUD and buy-menu pictures
##  <key>_top.png   seen from above, muzzle to +x: the gun in a player's hands
##  <key>_icon.png  white silhouette of the side view: kill feed, buy rows
## guns.json gives each image's size, the pixel of the model origin (ax, ay),
## of the pistol grip (gx) and the real length. Keys are the weapon's "sound"
## id (kodiak, longbow...). Missing art falls back to the old line drawing
## (callers check the return value).

const DIR := "res://assets/guns/"
const BASE_LEN := 14.0 ## Dropped guns: px = BASE_LEN + PER_M * real length (m),
const PER_M := 22.0 ## so pistols stay readable and snipers don't get huge.
const HELD_PPM := 40.0 ## Held by a soldier sprite: true scale, matching the body (PlayerArt.BODY_PPM).
const HELD_WIDTH := 1.8 ## Top views are stretched sideways a little to read at game scale.
const HELD_WIDTH_NO_BODY := 3.2 ## ...more when drawn over the old circles.
const HELD_TINT := Color(1.5, 1.5, 1.5) ## Lifts dark finishes off a dark floor.
static var user_finish := Color(0, 0, 0, 0) ## Your weapon finish (My Player shop) as a tint; alpha 0 = factory.
const HOLD := {WeaponData.PISTOL: 10.0, WeaponData.SMG: 8.0} ## Grip distance (no body art).
const HOLD_DEFAULT := 6.0

static var _meta := {}
static var _tex := {}


static func _load() -> void:
	if not _meta.is_empty():
		return
	var f := FileAccess.open(DIR + "guns.json", FileAccess.READ)
	if f == null:
		_meta = {"_none": true}
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	_meta = d if d is Dictionary else {"_none": true}


static func key_of(weapon_id: int) -> String:
	return String(WeaponData.TABLE.get(weapon_id, {}).get("sound", ""))


static func has(weapon_id: int) -> bool:
	_load()
	return _meta.has(key_of(weapon_id))


static func _texture(k: String, view: String) -> Texture2D:
	var id := k + "_" + view
	if not _tex.has(id):
		var p := DIR + id + ".png"
		_tex[id] = load(p) if ResourceLoader.exists(p) else null
	return _tex[id]


## The side picture (full colour) or the white silhouette.
static func picture(weapon_id: int, silhouette: bool = false) -> Texture2D:
	if not has(weapon_id):
		return null
	return _texture(key_of(weapon_id), "icon" if silhouette else "side")


static func icon_path(weapon_id: int) -> String:
	return DIR + key_of(weapon_id) + "_icon.png" if has(weapon_id) else ""


## Dropped-gun scale: game pixels per image pixel.
static func _floor_scale(k: String) -> float:
	var m: Dictionary = _meta[k]
	return (BASE_LEN + PER_M * float(m.len_m)) / float(m.side.w)


## Held-gun scale (game px per image px) and sideways stretch.
static func _held_scale(k: String, body: bool) -> Vector2:
	if body:
		var s := HELD_PPM / 400.0 # Sprites are rendered at 400 px/m.
		return Vector2(s, s * HELD_WIDTH)
	var f := _floor_scale(k) * 1.12
	return Vector2(f, f * HELD_WIDTH_NO_BODY)


static func hold_dist(cat: int) -> float:
	return float(HOLD.get(cat, HOLD_DEFAULT))


## Where the grip sits relative to the body centre: in the soldier's right hand
## when there is player art for `side`, else straight out in front.
static func hold_point(w: WeaponData, dir: Vector2, side: int = -1, pose: String = "rifle") -> Vector2:
	if PlayerArt.has(side):
		return PlayerArt.grip(dir, pose)
	return dir * hold_dist(w.cat)


## The muzzle tip relative to the body centre, or INF without art.
static func muzzle_point(w: WeaponData, dir: Vector2, side: int = -1, pose: String = "rifle") -> Vector2:
	if not has(w.id):
		return Vector2.INF
	var k := key_of(w.id)
	var t: Dictionary = _meta[k].top
	var sc := _held_scale(k, PlayerArt.has(side))
	return hold_point(w, dir, side, pose) + dir * (float(t.w) - float(t.get("gx", t.ax))) * sc.x


## Draws the gun in the hands of a unit at `at` facing `dir`.
static func draw_held(ci: CanvasItem, w: WeaponData, dir: Vector2, side: int = -1, pose: String = "rifle", at: Vector2 = Vector2.ZERO, finish: Color = Color(0, 0, 0, 0)) -> bool:
	if not has(w.id):
		return false
	var k := key_of(w.id)
	var tex := _texture(k, "top")
	if tex == null:
		return false
	var t: Dictionary = _meta[k].top
	var sc := _held_scale(k, PlayerArt.has(side))
	# Explicit matrix: the sideways stretch must apply in the gun's own frame.
	ci.draw_set_transform_matrix(Transform2D(dir.angle(), sc, 0.0, at + hold_point(w, dir, side, pose)))
	var o := Vector2(-float(t.get("gx", t.ax)), -float(t.ay))
	ci.draw_texture(tex, o + Vector2(0.0, 2.0) / sc.y, Color(0, 0, 0, 0.5))
	ci.draw_texture(tex, o, HELD_TINT if finish.a <= 0.0 else Color(HELD_TINT.r * finish.r, HELD_TINT.g * finish.g, HELD_TINT.b * finish.b))
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	return true


## Draws a dropped gun lying on its side at `pos`, turned by `angle`.
static func draw_floor(ci: CanvasItem, w: WeaponData, pos: Vector2, angle: float) -> bool:
	if not has(w.id):
		return false
	var k := key_of(w.id)
	var tex := _texture(k, "side")
	if tex == null:
		return false
	var s := _floor_scale(k)
	var half := tex.get_size() * 0.5
	ci.draw_set_transform_matrix(Transform2D(angle, Vector2(s, s), 0.0, pos))
	ci.draw_texture(tex, -half + Vector2(2.0, 2.5) / s, Color(0, 0, 0, 0.45))
	ci.draw_texture(tex, -half)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	return true


## The C4 seen from above (also the planted-bomb sprite).
static func bomb_texture() -> Texture2D:
	if not _tex.has("_bomb"):
		var p := "res://assets/sprites/c4_planted.png"
		_tex["_bomb"] = load(p) if ResourceLoader.exists(p) else null
	return _tex["_bomb"]


## Draws the C4 on a carrier's back (unit at `at` facing `dir`).
static func draw_bomb_on_back(ci: CanvasItem, dir: Vector2, at: Vector2 = Vector2.ZERO) -> bool:
	var bt := bomb_texture()
	if bt == null:
		return false
	ci.draw_set_transform_matrix(Transform2D(dir.angle() + PI * 0.5, Vector2.ONE * (14.0 / bt.get_width()), 0.0, at - dir * 7.0))
	ci.draw_texture(bt, -bt.get_size() * 0.5)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	return true


## Draws the planted (or dropped, smaller) bomb at `pos`.
static func draw_bomb(ci: CanvasItem, pos: Vector2, dropped: bool = false) -> bool:
	var bt := bomb_texture()
	if bt == null:
		return false
	var size := Vector2(30, 22.5) * (0.8 if dropped else 1.0)
	ci.draw_texture_rect(bt, Rect2(pos - size * 0.5, size), false)
	return true



# --- Grenades (assets/grenades, rendered at 1600 px/m) ----------------------------

const GRENADE_DIR := "res://assets/grenades/"
const GRENADE_HELD_PX := 10.0 ## On-screen length of a grenade in hand (well above true scale, to read).
const GRENADE_THROWN_PX := 11.0


static func grenade_key(kind: String, side: int) -> String:
	if kind == "molotov" and side == 1:
		return "g_incendiary" # CTs buy the incendiary canister.
	return "g_" + kind


## Side picture (or white silhouette) of a grenade kind for a side.
static func grenade_picture(kind: String, side: int, silhouette: bool = false) -> Texture2D:
	var id := "%s_%s" % [grenade_key(kind, side), "icon" if silhouette else "side"]
	if not _tex.has(id):
		var p := GRENADE_DIR + id + ".png"
		_tex[id] = load(p) if ResourceLoader.exists(p) else null
	return _tex[id]


## Draws a grenade (side view) centred on `pos`, its top pointing along `angle`, `length` px long.
static func draw_grenade(ci: CanvasItem, kind: String, side: int, pos: Vector2, angle: float, length: float) -> bool:
	var tex := grenade_picture(kind, side)
	if tex == null:
		return false
	var s := length / float(tex.get_height())
	var half := tex.get_size() * 0.5
	ci.draw_set_transform_matrix(Transform2D(angle + PI * 0.5, Vector2(s, s), 0.0, pos))
	ci.draw_texture(tex, -half + Vector2(1.5, 2.0) / s, Color(0, 0, 0, 0.5))
	ci.draw_texture(tex, -half, HELD_TINT)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	return true


# --- Knife (assets/knife, rendered at 400 px/m) --------------------------------

const KNIFE_DIR := "res://assets/knife/"
const KNIFE_ICON := "res://assets/knife/knife_icon.png"
const KNIFE_SCALE := 1.9 ## Drawn well over true scale so the blade reads at game zoom.
const SWIPE_ARC := 1.25 ## Radians swept each side of the aim by a swipe.

static var _knife_meta := {}


static func _knife() -> Dictionary:
	if _knife_meta.is_empty():
		var f := FileAccess.open(KNIFE_DIR + "guns.json", FileAccess.READ)
		var d: Variant = JSON.parse_string(f.get_as_text()) if f != null else null
		_knife_meta = d.get("knife", {"_none": true}) if d is Dictionary else {"_none": true}
	return _knife_meta


static func knife_picture() -> Texture2D:
	if not _tex.has("_knife"):
		var p := KNIFE_DIR + "knife_side.png"
		_tex["_knife"] = load(p) if ResourceLoader.exists(p) else null
	return _tex["_knife"]


## The knife in hand at `at` (unit centre) facing `dir`. `swipe` 0..1 runs a
## slash across the front (side = +1 / -1 alternates the direction); 0 = idle.
static func draw_knife(ci: CanvasItem, dir: Vector2, side: int, pose: String, swipe: float, swipe_side: float, at: Vector2 = Vector2.ZERO) -> void:
	var hand := hold_point_knife(dir, side, pose)
	var ang := dir.angle()
	if swipe > 0.0:
		# Wind-up behind one shoulder, fast cut across, follow through.
		var e := ease(swipe, 0.45)
		var off := swipe_side * lerpf(SWIPE_ARC, -SWIPE_ARC, e)
		hand = hand.rotated(off * 0.55) + dir * sin(swipe * PI) * 5.0
		ang += off
		# Motion streak along the blade tip's path.
		var reach := hand.length() + 12.0
		var a0 := dir.angle() + swipe_side * SWIPE_ARC * 0.55
		var a1 := dir.angle() + off * 0.55
		var alpha := 0.5 * sin(swipe * PI)
		ci.draw_arc(at, reach, minf(a0, a1), maxf(a0, a1), 18, Color(1, 1, 1, alpha), 3.0, true)
		ci.draw_arc(at, reach - 3.0, minf(a0, a1), maxf(a0, a1), 18, Color(0.85, 0.9, 1.0, alpha * 0.5), 1.5, true)
	var tex := knife_picture()
	var m := _knife()
	if tex == null or m.has("_none"):
		var tip := hand + Vector2.from_angle(ang) * 10.0
		ci.draw_line(at + hand, at + tip, Color(0.8, 0.82, 0.85), 2.0)
		return
	var v: Dictionary = m.side
	var s := HELD_PPM / 400.0 * KNIFE_SCALE
	ci.draw_set_transform_matrix(Transform2D(ang, Vector2(s, s), 0.0, at + hand))
	var o := Vector2(-float(v.gx), -float(v.ay))
	ci.draw_texture(tex, o + Vector2(0.0, 2.0) / s, Color(0, 0, 0, 0.45))
	ci.draw_texture(tex, o, Color(1.7, 1.7, 1.7))
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


static func hold_point_knife(dir: Vector2, side: int, pose: String) -> Vector2:
	# A little ahead of the pistol grip: the knife hand reaches forward.
	return (PlayerArt.grip(dir, pose) + dir * 3.0) if PlayerArt.has(side) else dir * 9.0
