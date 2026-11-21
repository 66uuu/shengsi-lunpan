extends Control
# ============================================================
#  ui/wheel.gd
#  双方共用的 36 格转盘：按桌面透视压成椭圆 + 转动动画 + 滴答信号
# ============================================================

signal spin_finished
signal tick
signal spin_requested

const SEGMENTS := 36
const FLAT := 1.0           # 正圆转盘

const TYPE_LABELS := {
	"empty": "空", "bullet": "弹", "shoot": "枪", "item": "具",
	"heal": "疗", "curse": "咒", "double": "双", "selfhurt": "伤",
	"tire": "胎", "powder": "药", "unknown": "?",
}

const TYPE_COLORS := {
	"empty": Color(0.115, 0.110, 0.098),
	"bullet": Color(0.255, 0.185, 0.075),
	"shoot": Color(0.320, 0.065, 0.055),
	"item": Color(0.075, 0.160, 0.195),
	"heal": Color(0.085, 0.200, 0.130),
	"curse": Color(0.175, 0.065, 0.190),
	"double": Color(0.345, 0.255, 0.075),
	"selfhurt": Color(0.225, 0.045, 0.045),
	"tire": Color(0.145, 0.155, 0.075),
	"powder": Color(0.195, 0.125, 0.055),
	"unknown": Color(0.400, 0.180, 0.520),
}

var types: Array = []
var spin_angle := 0.0
var spinning := false
var landed := -1
var font: Font
var accent := Color(0.80, 0.60, 0.25)

var _last_idx := -1
var _hub_hover := false


func setup(p_types: Array, p_font: Font) -> void:
	types = p_types
	font = p_font
	queue_redraw()


func set_accent(c: Color) -> void:
	accent = c
	queue_redraw()


func _draw() -> void:
	if types.is_empty():
		return
	var f: Font = font if font != null else ThemeDB.fallback_font
	var c := size * 0.5
	var r: float = minf(size.x, size.y) * 0.5 - 30.0
	var seg := TAU / SEGMENTS

	# ---------- 盘面：整体压扁成椭圆 ----------
	# 先画一层接地阴影
	for i in 3:
		var sa := 0.18 - 0.05 * float(i)
		draw_set_transform(c + Vector2(0, 12.0 + 7.0 * float(i)), 0.0, Vector2(1.0, FLAT))
		draw_circle(Vector2.ZERO, r + 36.0 - 10.0 * float(i), Color(0, 0, 0, sa))
	draw_set_transform(c, 0.0, Vector2(1.0, FLAT))
	draw_circle(Vector2.ZERO, r + 26.0, Color(0.07, 0.055, 0.04))
	draw_circle(Vector2.ZERO, r + 20.0, accent.darkened(0.68))
	draw_circle(Vector2.ZERO, r + 14.0, accent.darkened(0.42))
	draw_circle(Vector2.ZERO, r + 7.0, Color(0.065, 0.055, 0.045))

	for i in SEGMENTS:
		var a0: float = -PI / 2.0 + spin_angle + i * seg
		var pts := PackedVector2Array()
		pts.append(Vector2.ZERO)
		for k in range(5):
			var a: float = a0 + seg * float(k) / 4.0
			pts.append(Vector2(cos(a), sin(a)) * r)
		var t: String = String(types[i])
		var col: Color = TYPE_COLORS.get(t, Color(0.2, 0.2, 0.2))
		draw_colored_polygon(pts, col)
		draw_line(Vector2.ZERO, Vector2(cos(a0), sin(a0)) * r, Color(0.04, 0.035, 0.028, 0.9), 1.4)
		if not spinning and i == landed:
			draw_colored_polygon(pts, Color(1.0, 0.92, 0.62, 0.18))
			draw_polyline(pts, Color(1.0, 0.86, 0.52, 0.95), 3.0)

	# 盘面内圈
	draw_arc(Vector2.ZERO, r * 0.94, 0, TAU, 96, Color(0.0, 0.0, 0.0, 0.24), 2.0)
	draw_arc(Vector2.ZERO, r * 0.55, 0, TAU, 96, Color(0.0, 0.0, 0.0, 0.16), 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# ---------- 文字：位置贴椭圆，字形保持正立可读 ----------
	for i in SEGMENTS:
		var mid: float = -PI / 2.0 + spin_angle + i * seg + seg * 0.5
		var t: String = String(types[i])
		var lp := Vector2(c.x + cos(mid) * r * 0.80, c.y + sin(mid) * r * 0.80 * FLAT)
		if t == "empty":
			draw_circle(lp, 2.6, Color(0.46, 0.43, 0.37, 0.50))
			continue
		var s: String = TYPE_LABELS.get(t, "?")
		var fs := 24
		if t == "unknown":
			fs = 30
		var sz: Vector2 = f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var rot: float = mid
		if cos(mid) < 0.0:
			rot += PI
		var lcol := Color(0.96, 0.92, 0.83)
		if t == "unknown":
			lcol = Color(1.0, 0.86, 0.42)
		draw_string(f, Vector2(lp.x - sz.x * 0.5, lp.y + sz.y * 0.34), s,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, lcol)

	# ---------- 中心按钮（椭圆底座 + 正立文字） ----------
	var hub_col := Color(0.30, 0.20, 0.09)
	if _hub_hover and not spinning:
		hub_col = Color(0.42, 0.29, 0.12)
	draw_set_transform(c, 0.0, Vector2(1.0, FLAT))
	draw_circle(Vector2.ZERO, 104.0, Color(0.05, 0.045, 0.035))
	draw_circle(Vector2.ZERO, 96.0, hub_col)
	draw_arc(Vector2.ZERO, 96.0, 0, TAU, 64, accent, 3.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var hub := "转动" if not spinning else "……"
	var hs := 34
	var hsz: Vector2 = f.get_string_size(hub, HORIZONTAL_ALIGNMENT_LEFT, -1, hs)
	draw_string(f, Vector2(c.x - hsz.x * 0.5, c.y + hsz.y * 0.33), hub,
		HORIZONTAL_ALIGNMENT_LEFT, -1, hs, Color(0.96, 0.86, 0.60))

	# ---------- 顶部指针（竖直，不压扁） ----------
	var ty: float = c.y - r * FLAT - 2.0
	var tri := PackedVector2Array([
		Vector2(c.x - 22.0, ty - 50.0),
		Vector2(c.x + 22.0, ty - 50.0),
		Vector2(c.x, ty),
	])
	draw_colored_polygon(tri, Color(0.62, 0.10, 0.08))
	draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]),
		Color(0.92, 0.78, 0.52), 2.0)


func current_index() -> int:
	var seg := TAU / SEGMENTS
	return int(floor(fposmod(-spin_angle, TAU) / seg)) % SEGMENTS


func spin_to(target_idx: int, duration := 2.0) -> void:
	if types.is_empty():
		return
	spinning = true
	landed = -1
	var seg := TAU / SEGMENTS
	var cur := spin_angle
	var target_angle := -float(target_idx) * seg
	var delta := fposmod(target_angle - cur, TAU)
	var final := cur + TAU * 4.0 + delta
	_last_idx = current_index()
	queue_redraw()
	var tw := create_tween()
	tw.tween_method(_set_angle, cur, final, duration).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	await tw.finished
	spin_angle = final
	spinning = false
	landed = target_idx
	queue_redraw()
	spin_finished.emit()


func _set_angle(a: float) -> void:
	spin_angle = a
	queue_redraw()


func _process(_delta: float) -> void:
	if not spinning:
		return
	var idx := current_index()
	if idx != _last_idx:
		_last_idx = idx
		tick.emit()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var d: Vector2 = (event.position - size * 0.5) / Vector2(1.0, FLAT)
		var inside: bool = d.length() <= 100.0
		if inside != _hub_hover:
			_hub_hover = inside
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if inside else Control.CURSOR_ARROW
			queue_redraw()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var d: Vector2 = (event.position - size * 0.5) / Vector2(1.0, FLAT)
		if d.length() <= 100.0 and not spinning:
			spin_requested.emit()
			accept_event()
