extends Control
# ESC 暂停菜单：音乐/音效音量、全屏、重新开始、退出

var audio: Node
var _root: Control
var _music: HSlider
var _sfx: HSlider
var _music_val: Label
var _sfx_val: Label
var _fs_btn: Button
var opened := false
var _cfg := ConfigFile.new()


func setup(a: Node, th: Theme) -> void:
	audio = a
	theme = th


func _ready() -> void:
	z_index = 90
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_load_cfg()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.visible = false
	add_child(_root)

	var shade := ColorRect.new()
	shade.color = Color(0.012, 0.009, 0.008, 0.84)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(shade)

	var panel := Panel.new()
	panel.position = Vector2(660, 180)
	panel.size = Vector2(600, 720)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.055, 0.045, 0.038, 0.98)
	sb.border_color = Color(0.42, 0.30, 0.16, 0.95)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(18)
	panel.add_theme_stylebox_override("panel", sb)
	_root.add_child(panel)

	_title(panel, "暂  停", 54, 26)
	_title(panel, "按 ESC 继续", 22, 92, Color(0.62, 0.56, 0.46))

	_label(panel, "背景音乐", Rect2(60, 168, 200, 40), 26)
	_music = _slider(panel, Rect2(60, 212, 400, 40), 0.0, 100.0, 72.0, _on_music)
	_music_val = _label(panel, "72", Rect2(480, 208, 70, 44), 24)

	_label(panel, "音效", Rect2(60, 282, 200, 40), 26)
	_sfx = _slider(panel, Rect2(60, 326, 400, 40), 0.0, 100.0, 88.0, _on_sfx)
	_sfx_val = _label(panel, "88", Rect2(480, 322, 70, 44), 24)

	_fs_btn = _button(panel, "全屏：关", Rect2(60, 410, 480, 58), _on_fullscreen)
	_button(panel, "重新开始", Rect2(60, 484, 480, 58), _on_restart)
	_button(panel, "退出游戏", Rect2(60, 558, 480, 58), _on_quit)
	_button(panel, "返回游戏", Rect2(60, 632, 480, 58), _on_resume)


func _title(p: Control, txt: String, fs: int, y: int, col := Color(0.90, 0.84, 0.72)) -> void:
	var l := Label.new()
	l.text = txt
	l.position = Vector2(0, y)
	l.size = Vector2(600, fs + 20)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	p.add_child(l)


func _label(p: Control, txt: String, r: Rect2, fs: int) -> Label:
	var l := Label.new()
	l.text = txt
	l.position = r.position
	l.size = r.size
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", Color(0.88, 0.84, 0.76))
	p.add_child(l)
	return l


func _slider(p: Control, r: Rect2, lo: float, hi: float, val: float, cb: Callable) -> HSlider:
	var s := HSlider.new()
	s.position = r.position
	s.size = r.size
	s.min_value = lo
	s.max_value = hi
	s.value = val
	s.step = 1.0
	s.value_changed.connect(cb)
	p.add_child(s)
	return s


func _button(p: Control, txt: String, r: Rect2, cb: Callable) -> Button:
	var b := Button.new()
	b.text = txt
	b.position = r.position
	b.size = r.size
	b.add_theme_font_size_override("font_size", 26)
	b.pressed.connect(cb)
	p.add_child(b)
	return b


func toggle() -> void:
	opened = not opened
	_root.visible = opened
	get_tree().paused = opened
	if opened and audio != null:
		audio.play("ui")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
			toggle()
			get_viewport().set_input_as_handled()


func _on_music(v: float) -> void:
	_music_val.text = str(int(v))
	_set_bus("Music", v / 100.0)
	_save_cfg()


func _on_sfx(v: float) -> void:
	_sfx_val.text = str(int(v))
	_set_bus("SFX", v / 100.0)
	_save_cfg()


func _set_bus(bus_name: String, linear: float) -> void:
	var i := AudioServer.get_bus_index(bus_name)
	if i < 0:
		return
	AudioServer.set_bus_mute(i, linear <= 0.005)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(linear, 0.005)))


func _on_fullscreen() -> void:
	var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	if full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		_fs_btn.text = "全屏：关"
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_fs_btn.text = "全屏：开"


func _on_restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_resume() -> void:
	toggle()


func _on_quit() -> void:
	get_tree().paused = false
	get_tree().quit()


func _load_cfg() -> void:
	_cfg.load("user://progress.cfg")
	var m := float(_cfg.get_value("settings", "music", 72))
	var s := float(_cfg.get_value("settings", "sfx", 88))
	_music.value = m
	_sfx.value = s
	_music_val.text = str(int(m))
	_sfx_val.text = str(int(s))
	_set_bus("Music", m / 100.0)
	_set_bus("SFX", s / 100.0)


func _save_cfg() -> void:
	_cfg.set_value("settings", "music", _music.value)
	_cfg.set_value("settings", "sfx", _sfx.value)
	_cfg.save("user://progress.cfg")
