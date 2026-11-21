extends Control
# ============================================================
#  ui/vignette.gd
#  画面氛围叠加：暗角 / 胶片噪点 / 低血量红色脉动 / 灯光闪烁
# ============================================================

var danger := 0.0          # 0..1 低血量强度
var time := 0.0
var _grain_clock := 0.0
var _grain: Array = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.seed = 20261121


func _process(delta: float) -> void:
	time += delta
	_grain_clock -= delta
	if _grain_clock <= 0.0:
		_grain_clock = 0.06
		_grain.clear()
		for i in 240:
			_grain.append(Vector3(_rng.randf_range(0, size.x), _rng.randf_range(0, size.y),
				_rng.randf_range(0.012, 0.045)))
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 1.0:
		return

	# 暗角：一圈圈向内变淡的边框
	var base := 0.10 + 0.16 * danger
	for i in 22:
		var inset := float(i) * 8.0
		var a := base * pow(1.0 - float(i) / 22.0, 1.7)
		draw_rect(Rect2(inset, inset, w - inset * 2.0, h - inset * 2.0),
			Color(0.0, 0.0, 0.0, a), false, 9.0)

	# 低血量红色脉动
	if danger > 0.01:
		var pulse := 0.5 + 0.5 * sin(time * 6.0)
		var red_a := 0.05 + 0.16 * danger * pulse
		draw_rect(Rect2(0, 0, w, h), Color(0.55, 0.02, 0.02, red_a * 0.35))
		for i in 14:
			var inset2 := float(i) * 10.0
			draw_rect(Rect2(inset2, inset2, w - inset2 * 2.0, h - inset2 * 2.0),
				Color(0.62, 0.04, 0.03, red_a * pow(1.0 - float(i) / 14.0, 1.5)), false, 10.0)

	# 胶片噪点
	for p in _grain:
		var v: Vector3 = p
		draw_rect(Rect2(v.x, v.y, 2.0, 2.0), Color(0.92, 0.90, 0.82, v.z))

	# 灯光闪烁：极轻微的明暗抖动
	var flick := sin(time * 9.3) * 0.5 + sin(time * 23.7) * 0.5
	if flick > 0.55:
		draw_rect(Rect2(0, 0, w, h), Color(0.0, 0.0, 0.0, 0.025))
