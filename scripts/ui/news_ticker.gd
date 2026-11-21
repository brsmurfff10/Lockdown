class_name NewsTicker
extends Control
## Scrolling market-style news wire along the bottom of the career hub:
## team "prices" (rating and weekly change) mixed with headlines from around
## the world. Hover to pause.

const SPEED := 70.0 ## px / second
const BG := Color("030405")
const AMBER := Color("ffb000")
const TAG_COL := Color("ff7f2e")
const KIND_COLORS := {"good": Color("4ade80"), "bad": Color("f87171"), "deal": Color("38d0ff"), "info": Color("d6dbe4")}

var segments: Array = [] ## [text, color]
var _offset := 0.0
var _width := 0.0
var _paused := false
var _font: Font
var _font_b: Font
const SIZE := 13


func _init() -> void:
	custom_minimum_size = Vector2(0, 28)
	mouse_filter = Control.MOUSE_FILTER_PASS
	clip_contents = true
	mouse_entered.connect(func() -> void: _paused = true)
	mouse_exited.connect(func() -> void: _paused = false)


func _ready() -> void:
	_font = UI.font(500)
	_font_b = UI.font(700)


## Builds the tape from the world: ranked teams as tickers, then headlines.
func set_world(w: World) -> void:
	segments.clear()
	var ranked := w.rankings()
	var items: Array = []
	for i in mini(14, ranked.size()):
		var t: TeamData = ranked[i]
		var now := t.rating_exact()
		var d := now - (t.last_rating if t.last_rating > 0.0 else now)
		items.append([["%s " % t.short_name, TAG_COL], ["%.1f " % now, AMBER],
			[("▲%.1f" % d) if d > 0.05 else (("▼%.1f" % -d) if d < -0.05 else "■0.0"),
				KIND_COLORS.good if d > 0.05 else (KIND_COLORS.bad if d < -0.05 else Color("8b94a7"))]])
	var heads: Array = []
	for i in range(w.wire.size() - 1, maxi(-1, w.wire.size() - 24), -1):
		var e: Dictionary = w.wire[i]
		heads.append([["◆ ", AMBER], [String(e.text).to_upper(), KIND_COLORS.get(String(e.get("kind", "info")), KIND_COLORS.info)]])
	if heads.is_empty():
		heads.append([["◆ ", AMBER], ["LOCKDOWN WIRE: SEASON %d WEEK %d" % [w.season, w.week], KIND_COLORS.info]])
	# Interleave: a few tickers, a headline, ...
	var ti := 0
	var hi := 0
	while ti < items.size() or hi < heads.size():
		for k in 3:
			if ti < items.size():
				segments.append_array(items[ti])
				segments.append(["     ", Color.WHITE])
				ti += 1
		if hi < heads.size():
			segments.append_array(heads[hi])
			segments.append(["     ", Color.WHITE])
			hi += 1
	_width = 0.0
	if _font == null:
		_font = UI.font(500)
		_font_b = UI.font(700)
	for sg in segments:
		_width += _seg_font(sg).get_string_size(String(sg[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE).x
	queue_redraw()


func _seg_font(sg: Array) -> Font:
	return _font_b if sg[1] == TAG_COL or sg[1] == AMBER else _font


func _process(delta: float) -> void:
	if not _paused and _width > 0.0:
		_offset = fmod(_offset + SPEED * delta, _width)
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	draw_line(Vector2(0, 0.5), Vector2(size.x, 0.5), Color(AMBER, 0.35), -1)
	# Fixed label on the left.
	var label_w := 92.0
	if _width > 0.0:
		var base_y := (size.y + _font.get_ascent(SIZE) - _font.get_descent(SIZE)) * 0.5
		var x := label_w - _offset
		while x < size.x:
			var cx := x
			for sg in segments:
				var f := _seg_font(sg)
				var tw := f.get_string_size(String(sg[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE).x
				if cx + tw > label_w and cx < size.x:
					draw_string(f, Vector2(roundf(cx), roundf(base_y)), String(sg[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE, sg[1])
				cx += tw
			x += _width
	draw_rect(Rect2(0, 0, label_w, size.y), AMBER)
	var lf := UI.font_spaced(700, 1)
	var ly := (size.y + lf.get_ascent(12) - lf.get_descent(12)) * 0.5
	draw_string(lf, Vector2(10, roundf(ly)), "THE WIRE", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, BG)
