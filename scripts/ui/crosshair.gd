class_name Crosshair
extends Control
## Custom crosshair drawn at the mouse. Look comes from Game.settings.crosshair
## (editable in Settings). Used in matches and for the Settings preview.

const DEFAULTS := {
	"length": 5.0, ## Line length in px.
	"thickness": 2.0,
	"gap": 3.0, ## Distance from centre to where each line starts.
	"lines": true,
	"t_style": false, ## No top line.
	"dot": false,
	"dot_size": 2.0,
	"outline": true,
	"color": "5cff7a",
	"alpha": 1.0,
	"dynamic": false, ## Gap widens with your current spread.
}

var unit: Unit = null ## When set (in matches), drives the dynamic gap.
var preview_center := Vector2.INF ## Settings preview: draw here instead of at the mouse.


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	var center := preview_center if preview_center != Vector2.INF else get_local_mouse_position()
	var extra := 0.0
	var s := settings()
	if bool(s.dynamic) and unit != null and is_instance_valid(unit) and unit.alive:
		extra = unit.current_spread() * 1.2
	draw_crosshair(self, center, s, extra)
	if preview_center == Vector2.INF and unit != null and is_instance_valid(unit) and unit.alive:
		_draw_ammo(center)


## Mag bar under the crosshair, and a ring that fills while reloading.
func _draw_ammo(c: Vector2) -> void:
	if unit.held_grenade != "":
		# Throw range: the grenade stops about where you click, up to MAX_THROW.
		var col: Color = Utility.COLORS[unit.held_grenade]
		draw_arc(c, 10.0, 0.0, TAU, 24, Color(col, 0.9), 2.0, true)
		var font := ThemeDB.fallback_font
		draw_string(font, c + Vector2(14, 18), Utility.SHORT[unit.held_grenade], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)
		return
	var w := unit.weapon
	if unit.reloading:
		var t := clampf(1.0 - unit.reload_timer / maxf(w.reload_time, 0.01), 0.0, 1.0)
		draw_arc(c, 17.0, 0.0, TAU, 40, Color(0, 0, 0, 0.45), 4.0, true)
		draw_arc(c, 17.0, -PI / 2.0, -PI / 2.0 + TAU * t, 40, Color(1, 1, 1, 0.9), 2.5, true)
		return
	var frac := float(w.ammo) / maxf(1.0, float(w.mag_size))
	var col := Color(1, 1, 1, 0.85)
	if frac <= 0.2:
		col = Color(1.0, 0.35, 0.3, 0.95)
	elif frac <= 0.4:
		col = Color(1.0, 0.8, 0.35, 0.9)
	var bw := 34.0
	var top := c + Vector2(-bw / 2.0, 15.0)
	draw_rect(Rect2(top - Vector2(1, 1), Vector2(bw + 2, 5)), Color(0, 0, 0, 0.55))
	if w.mag_size <= 12:
		# Small mags: one notch per round.
		var gap := 1.0
		var seg := (bw - gap * (w.mag_size - 1)) / w.mag_size
		for i in w.mag_size:
			var x := top.x + i * (seg + gap)
			draw_rect(Rect2(Vector2(x, top.y), Vector2(seg, 3)), col if i < w.ammo else Color(1, 1, 1, 0.12))
	else:
		draw_rect(Rect2(top, Vector2(bw, 3)), Color(1, 1, 1, 0.12))
		draw_rect(Rect2(top, Vector2(bw * frac, 3)), col)
	var font := ThemeDB.fallback_font
	draw_string(font, top + Vector2(bw + 5, 5), str(w.ammo), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)


static func settings() -> Dictionary:
	var s: Dictionary = DEFAULTS.duplicate()
	var saved: Dictionary = Game.settings.get("crosshair", {})
	for k in saved:
		if s.has(k):
			s[k] = saved[k]
	return s


static func draw_crosshair(ci: CanvasItem, c: Vector2, s: Dictionary, extra_gap: float = 0.0) -> void:
	var col := Color.html(String(s.color))
	col.a = float(s.alpha)
	var outline_col := Color(0, 0, 0, col.a * 0.85)
	var th := float(s.thickness)
	var length := float(s.length)
	var gap := float(s.gap) + extra_gap
	var rects: Array[Rect2] = []
	if bool(s.lines) and length > 0.0:
		rects.append(Rect2(c.x + gap, c.y - th / 2.0, length, th)) # Right
		rects.append(Rect2(c.x - gap - length, c.y - th / 2.0, length, th)) # Left
		rects.append(Rect2(c.x - th / 2.0, c.y + gap, th, length)) # Bottom
		if not bool(s.t_style):
			rects.append(Rect2(c.x - th / 2.0, c.y - gap - length, th, length)) # Top
	if bool(s.dot):
		var d := float(s.dot_size)
		rects.append(Rect2(c - Vector2(d, d) / 2.0, Vector2(d, d)))
	if bool(s.outline):
		for r in rects:
			ci.draw_rect(r.grow(1.0), outline_col)
	for r in rects:
		ci.draw_rect(r, col)
