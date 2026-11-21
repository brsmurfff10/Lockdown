class_name PlayerArt
## Rendered player sprites (art/blender/player_kit.py): CT and T soldiers seen
## from above, facing +x, in two poses: "rifle" (shouldered, both hands on the
## gun) and "pistol" (held out in two hands). Each side has looks (variants);
## a player keeps the same look all match, picked from their name.
## players.json gives the render scale, the hand positions per pose and the
## files, so the held gun (GunArt) sits in the right hand. Missing art falls
## back to the old circles (callers check the return value).

const DIR := "res://assets/players/"
const BODY_PPM := 38.0 ## Game px per metre for bodies (shoulders ~26 px wide).
const SIDE_KEYS := ["T", "CT"] ## Unit.side 0 = T, 1 = CT.
const TINT := Color(1.15, 1.15, 1.15) ## Lifts the renders a little under the match lighting.

static var _meta := {}
static var _tex := {} ## "ct/rifle" -> Texture2D


static func _load() -> void:
	if not _meta.is_empty():
		return
	var f := FileAccess.open(DIR + "players.json", FileAccess.READ)
	var d: Variant = JSON.parse_string(f.get_as_text()) if f != null else null
	_meta = d if d is Dictionary and d.has("files") else {"_none": true}


static func _variants(side: int) -> Array:
	_load()
	if _meta.has("_none") or side < 0 or side > 1:
		return []
	var v: Variant = _meta.get("variants", {}).get(SIDE_KEYS[side], [])
	if v is Array and not v.is_empty():
		return v
	return [String(SIDE_KEYS[side]).to_lower()]


static func has(side: int) -> bool:
	return not _variants(side).is_empty()


## The look for a player: stable per name, spread across the side's variants.
static func variant_for(side: int, who: String) -> String:
	var vs := _variants(side)
	if vs.is_empty():
		return ""
	return String(vs[absi(who.hash()) % vs.size()])


static func pose_for(w: WeaponData, grenade: bool = false) -> String:
	return "pistol" if grenade or (w != null and w.cat == WeaponData.PISTOL) else "rifle"


static func _texture(variant: String, pose: String) -> Texture2D:
	var id := variant + "/" + pose
	if not _tex.has(id):
		var files: Variant = _meta.get("files", {}).get(variant, {})
		var fn := ""
		if files is Dictionary:
			fn = String(files.get(pose, files.get("rifle", "")))
		elif files is String:
			fn = files # Older single-pose format.
		var p := DIR + fn
		_tex[id] = load(p) if fn != "" and ResourceLoader.exists(p) else null
	return _tex[id]


## Where the right hand (gun grip) is, relative to the body centre, for a unit facing `dir`.
static func grip(dir: Vector2, pose: String = "rifle") -> Vector2:
	_load()
	var hands: Dictionary = _meta.get("hands", {})
	var hp: Variant = hands.get(pose)
	var h: Array = hp.get("grip", [0.33, -0.12, 1.36]) if hp is Dictionary else hands.get("grip", [0.33, -0.12, 1.36])
	# World +Y (the soldier's left) is image-up, which is -y on screen.
	return Vector2(float(h[0]), -float(h[1])).rotated(dir.angle()) * BODY_PPM


## Draws the body centred on `at`, facing `dir`, tinted by `tint`.
static func draw_body(ci: CanvasItem, side: int, who: String, pose: String, dir: Vector2, tint: Color = TINT, at: Vector2 = Vector2.ZERO) -> bool:
	if not has(side):
		return false
	var tex := _texture(variant_for(side, who), pose)
	if tex == null:
		return false
	var s := BODY_PPM / float(_meta.get("ppm", 300.0))
	ci.draw_set_transform_matrix(Transform2D(dir.angle(), Vector2(s, s), 0.0, at))
	var half := tex.get_size() * 0.5
	ci.draw_texture(tex, -half + Vector2(1.5, 2.0) / s, Color(0, 0, 0, 0.4 * tint.a))
	ci.draw_texture(tex, -half, tint)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	return true
