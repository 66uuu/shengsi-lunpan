extends Control
# ============================================================
#  ui/dialogue_bubble.gd
#  屏幕上方对话框：逐字打字机（0.03 秒/字），仅展示，不接受输入
# ============================================================

const CHARS_PER_SEC := 1.0 / 0.03

var speaker := ""
var full_text := ""
var _typed := 0.0
var _hold := 0.0
var _typing := false
var _alpha := 0.0
var _font: Font

var _name_label: Label
var _text_label: Label


func setup(p_font: Font) -> void:
	_font = p_font
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0

	_name_label = Label.new()
	_name_label.position = Vector2(28, 12)
	_name_label.size = Vector2(480, 30)
	_name_label.add_theme_font_size_override("font_size", 22)
	_name_label.add_theme_color_override("font_color", Color(0.82, 0.62, 0.26))
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name_label)

	_text_label = Label.new()
	_text_label.position = Vector2(28, 46)
	_text_label.size = Vector2(size.x - 56, size.y - 60)
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.add_theme_font_size_override("font_size", 25)
	_text_label.add_theme_color_override("font_color", Color(0.96, 0.92, 0.85))
	_text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_text_label)


func say(text: String, p_speaker: String, hold_time := 3.4,
		tint := Color(0.62, 0.48, 0.24, 0.85)) -> void:
	if _name_label == null:
		return
	speaker = p_speaker
	full_text = text
	_typed = 0.0
	_typing = true
	_hold = hold_time
	_name_label.text = speaker
	_name_label.add_theme_color_override("font_color", tint.lightened(0.30))
	_text_label.text = text
	_text_label.visible_characters = 0
	_text_label.size = Vector2(size.x - 56, size.y - 60)
	_tint = tint
	_style = null
	modulate.a = 1.0
	queue_redraw()


func clear_now() -> void:
	_typing = false
	full_text = ""
	_hold = 0.0
	if _text_label != null:
		_text_label.text = ""
	_name_label.text = ""
	modulate.a = 0.0
	queue_redraw()


func is_active() -> bool:
	return _typing or _hold > 0.0


func _process(delta: float) -> void:
	if _text_label == null:
		return
	if _typing:
		_typed += CHARS_PER_SEC * delta
		var total: int = _text_label.text.length()
		_text_label.visible_characters = mini(int(_typed), total)
		if int(_typed) >= total:
			_typing = false
	elif _hold > 0.0:
		_hold -= delta
		if _hold <= 0.0:
			var tw := create_tween()
			tw.tween_property(self, "modulate:a", 0.0, 0.4)


func _draw() -> void:
	var s := size
	var body := Rect2(0, 0, s.x, s.y - 26)
	draw_style_box(_bubble_style(), body)
	# 指向对手的尾巴（气泡在右上，对手在左下）
	var tail := PackedVector2Array([
		Vector2(86, s.y - 28),
		Vector2(146, s.y - 28),
		Vector2(104, s.y + 4),
	])
	draw_colored_polygon(tail, Color(0.075, 0.065, 0.055, 0.97))
	draw_polyline(PackedVector2Array([tail[0], tail[2], tail[1]]),
		Color(0.62, 0.48, 0.24, 0.7), 2.0)


var _style: StyleBoxFlat
var _tint := Color(0.62, 0.48, 0.24, 0.85)


func _bubble_style() -> StyleBoxFlat:
	if _style == null:
		_style = StyleBoxFlat.new()
		_style.bg_color = Color(0.075, 0.065, 0.055, 0.97)
		_style.border_color = _tint
		_style.set_border_width_all(2)
		_style.set_corner_radius_all(18)
	return _style
