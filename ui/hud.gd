extends Control
# ============================================================
#  ui/hud.gd
#  HUD：提示条 / 双方状态 / 道具槽 / 图例 / 日志 / 按钮 / 各种弹窗
#  只负责显示与输入信号，不推进游戏流程
# ============================================================

const Items = preload("res://systems/items.gd")

signal spin_pressed
signal wager_pressed
signal end_pressed
signal item_pressed(index)
signal replace_choice(index)
signal intro_continue
signal result_continue
signal restart_pressed
signal help_pressed
signal start_pressed
signal level_selected(level: int)
signal title_requested

const COL_TEXT := Color(0.949, 0.910, 0.835)
const COL_DIM := Color(0.620, 0.580, 0.500)
const COL_WOOD := Color(0.800, 0.600, 0.250)
const COL_RED := Color(0.800, 0.240, 0.180)
const COL_GREEN := Color(0.330, 0.660, 0.400)
const COL_PANEL := Color(0.045, 0.052, 0.063, 0.94)

const LEGEND := [
	["empty", "空：什么也没发生，占约 40%"],
	["bullet", "弹：弹巢 +3（最多 8 发）"],
	["shoot", "枪：弹巢打空，每发 30 伤害"],
	["item", "具：随机获得一件道具"],
	["heal", "疗：回复 15 HP"],
	["curse", "咒：受到 10 点伤害"],
	["double", "双：下一次伤害 ×2"],
	["selfhurt", "伤：走火自伤 20 HP"],
	["tire", "胎：获得漏气的轮胎（负面）"],
	["powder", "药：获得劣质火药（负面）"],
]

const TYPE_COLORS := {
	"empty": Color(0.17, 0.16, 0.14),
	"bullet": Color(0.45, 0.32, 0.12),
	"shoot": Color(0.58, 0.15, 0.12),
	"item": Color(0.12, 0.32, 0.40),
	"heal": Color(0.14, 0.40, 0.25),
	"curse": Color(0.32, 0.13, 0.38),
	"double": Color(0.62, 0.47, 0.14),
	"selfhurt": Color(0.38, 0.08, 0.08),
	"tire": Color(0.24, 0.27, 0.13),
	"powder": Color(0.33, 0.21, 0.10),
}

var font: Font
var modal_kind := ""

var _hint_label: Label
var _help_btn: Button
var _boss: Dictionary = {}
var _boss_name: Label
var _boss_alias: Label
var _boss_hp_text: Label
var _boss_hp_fill: Panel
var _boss_dots: Array[Panel] = []
var _boss_status: Label
var _player_name: Label
var _player_hp_text: Label
var _player_hp_fill: Panel
var _player_dots: Array[Panel] = []
var _player_status: Label
var _player_streak: Label
var _player_items: Array = []
var _can_use_item := false
var _item_buttons: Array[Button] = []
var _log_labels: Array[Label] = []
var _spin_btn: Button
var _end_btn: Button
var _wager_btn: Button
var _modal: Control
var game_layer: Control


func build(p_font: Font) -> void:
	font = p_font
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	game_layer = Control.new()
	game_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(game_layer)
	_build_top()
	_build_boss_panel()
	_build_item_panel()
	_build_player_panel()
	_build_log_panel()
	_build_actions()
	_build_modal()
	_build_banner()


# ------------------------------------------------------------
#  结果横幅：转到什么，直接砸在屏幕中央
# ------------------------------------------------------------
var _banner_panel: Panel
var _banner_label: Label
var _banner_t := 0.0


func _build_banner() -> void:
	_banner_panel = _panel(game_layer, Rect2(340, 450, 1240, 100),
		Color(0.028, 0.020, 0.018, 0.92), Color(0.78, 0.54, 0.24, 0.95), 16)
	_banner_label = _label(_banner_panel, "", 46, COL_TEXT, Rect2(20, 2, 1200, 96),
		HORIZONTAL_ALIGNMENT_CENTER)
	_banner_panel.modulate.a = 0.0
	_banner_label.modulate.a = 0.0
	set_process(true)


func show_banner(text: String, color := Color(1.0, 0.90, 0.64)) -> void:
	if _banner_panel == null:
		return
	_banner_label.text = text
	_banner_label.add_theme_color_override("font_color", color)
	_banner_t = 2.6
	_banner_panel.modulate.a = 1.0
	_banner_label.modulate.a = 1.0


func _process(delta: float) -> void:
	if _banner_t <= 0.0:
		return
	_banner_t -= delta
	var a := clampf(_banner_t / 0.45, 0.0, 1.0)
	a = minf(a, clampf((2.6 - _banner_t) / 0.10, 0.0, 1.0))
	_banner_panel.modulate.a = a
	_banner_label.modulate.a = a


# ------------------------------------------------------------
#  基础控件
# ------------------------------------------------------------
func _sb(bg: Color, border: Color, bw := 2, radius := 14) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	return s


func _panel(parent: Control, rect: Rect2, bg: Color, border: Color, radius := 14) -> Panel:
	var p := Panel.new()
	p.position = rect.position
	p.size = rect.size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", _sb(bg, border, 2, radius))
	parent.add_child(p)
	return p


func _label(parent: Control, text: String, fs: int, color: Color, rect: Rect2,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.position = rect.position
	l.size = rect.size
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", color)
	if font != null:
		l.add_theme_font_override("font", font)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _button(parent: Control, text: String, rect: Rect2, fs: int, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.position = rect.position
	b.size = rect.size
	b.focus_mode = Control.FOCUS_NONE
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.add_theme_font_size_override("font_size", fs)
	if font != null:
		b.add_theme_font_override("font", font)
	b.add_theme_color_override("font_color", COL_TEXT)
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.78))
	b.add_theme_color_override("font_pressed_color", COL_WOOD)
	b.add_theme_color_override("font_disabled_color", Color(0.52, 0.49, 0.43))
	b.add_theme_stylebox_override("normal", _sb(Color(0.13, 0.11, 0.085), COL_WOOD.darkened(0.1), 2, 12))
	b.add_theme_stylebox_override("hover", _sb(Color(0.21, 0.17, 0.11), Color(1.0, 0.84, 0.48), 3, 12))
	b.add_theme_stylebox_override("pressed", _sb(Color(0.10, 0.085, 0.07), COL_WOOD, 2, 12))
	b.add_theme_stylebox_override("disabled", _sb(Color(0.075, 0.068, 0.058), Color(0.22, 0.19, 0.14), 1, 12))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _bar(parent: Control, rect: Rect2, fill_color: Color) -> Panel:
	var bg := Panel.new()
	bg.position = rect.position
	bg.size = rect.size
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_theme_stylebox_override("panel", _sb(Color(0.04, 0.036, 0.03), Color(0.28, 0.22, 0.14), 1, 11))
	parent.add_child(bg)
	var fill := Panel.new()
	fill.position = Vector2(3, 3)
	fill.size = Vector2(rect.size.x - 6, rect.size.y - 6)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.add_theme_stylebox_override("panel", _sb(fill_color, fill_color, 0, 9))
	bg.add_child(fill)
	return fill


# ------------------------------------------------------------
#  顶部 / 面板
# ------------------------------------------------------------
func _build_top() -> void:
	var bar := Panel.new()
	bar.position = Vector2(0, 0)
	bar.size = Vector2(1920, 68)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("panel", _sb(Color(0.035, 0.030, 0.025, 0.88), Color(0.24, 0.19, 0.12), 0, 0))
	game_layer.add_child(bar)

	_hint_label = _label(game_layer, "", 34, COL_TEXT, Rect2(60, 0, 1740, 68), HORIZONTAL_ALIGNMENT_CENTER)
	_hint_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_hint_label.add_theme_constant_override("shadow_offset_x", 2)
	_hint_label.add_theme_constant_override("shadow_offset_y", 2)

	_help_btn = _button(game_layer, "F1 说明", Rect2(1800, 10, 104, 48), 22, func() -> void: help_pressed.emit())


func _build_boss_panel() -> void:
	var p := _panel(game_layer, Rect2(30, 80, 400, 168), COL_PANEL, Color(0.62, 0.22, 0.18, 0.85))
	_boss_name = _label(p, "", 28, COL_WOOD, Rect2(18, 4, 364, 36))
	_boss_alias = _label(p, "", 22, COL_DIM, Rect2(18, 38, 210, 28))
	_boss_hp_text = _label(p, "", 22, COL_TEXT, Rect2(220, 38, 162, 28), HORIZONTAL_ALIGNMENT_RIGHT)
	_boss_hp_fill = _bar(p, Rect2(18, 72, 364, 22), COL_GREEN)
	_label(p, "弹巢", 22, COL_DIM, Rect2(18, 96, 60, 30))
	for i in 8:
		var dot := Panel.new()
		dot.position = Vector2(76 + i * 22, 101)
		dot.size = Vector2(18, 18)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.add_theme_stylebox_override("panel", _sb(Color(0.10, 0.09, 0.08), Color(0.30, 0.25, 0.18), 2, 9))
		p.add_child(dot)
		_boss_dots.append(dot)
	_boss_status = _label(p, "状态：—", 22, COL_DIM, Rect2(18, 128, 364, 34))
	_boss_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _build_player_panel() -> void:
	var p := _panel(game_layer, Rect2(30, 262, 400, 168), COL_PANEL, Color(0.55, 0.42, 0.20, 0.9))
	_player_name = _label(p, "李炎（你）", 28, COL_WOOD, Rect2(18, 4, 364, 36))
	_player_hp_text = _label(p, "", 22, COL_TEXT, Rect2(180, 40, 202, 28), HORIZONTAL_ALIGNMENT_RIGHT)
	_player_hp_fill = _bar(p, Rect2(18, 72, 364, 22), COL_GREEN)
	_label(p, "弹巢", 22, COL_DIM, Rect2(18, 96, 60, 30))
	for i in 8:
		var dot := Panel.new()
		dot.position = Vector2(76 + i * 22, 101)
		dot.size = Vector2(18, 18)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.add_theme_stylebox_override("panel", _sb(Color(0.10, 0.09, 0.08), Color(0.30, 0.25, 0.18), 2, 9))
		p.add_child(dot)
		_player_dots.append(dot)
	_player_status = _label(p, "状态：正常", 22, COL_DIM, Rect2(18, 124, 250, 36))
	_player_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_player_streak = _label(p, "气势 0/3", 22, COL_DIM, Rect2(250, 124, 132, 36), HORIZONTAL_ALIGNMENT_RIGHT)


func _build_item_panel() -> void:
	var p := _panel(game_layer, Rect2(30, 448, 400, 300), COL_PANEL, Color(0.30, 0.24, 0.15, 0.9))
	_label(p, "道具槽  /  1 · 2 · 3", 22, COL_WOOD, Rect2(16, 2, 368, 28))
	for i in 3:
		var b := _button(p, "", Rect2(16, 34 + i * 88, 368, 82), 22, func() -> void: item_pressed.emit(i))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_item_buttons.append(b)


func _build_log_panel() -> void:
	var p := _panel(game_layer, Rect2(1340, 664, 550, 354), Color(0.05, 0.044, 0.037, 0.92), Color(0.26, 0.21, 0.14, 0.85))
	_label(p, "对局记录", 22, COL_WOOD, Rect2(18, 4, 514, 30))
	for i in 5:
		var l := _label(p, "", 22, COL_TEXT, Rect2(18, 45 + i * 58, 514, 58))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		l.max_lines_visible = 2
		_log_labels.append(l)


func _build_actions() -> void:
	_spin_btn = _button(game_layer, "转动转盘\n[空格]", Rect2(1340, 328, 550, 96), 28,
		func() -> void: spin_pressed.emit())
	_end_btn = _button(game_layer, "结束回合\n[Enter]", Rect2(1340, 436, 550, 80), 26,
		func() -> void: end_pressed.emit())
	_wager_btn = _button(game_layer, "", Rect2(1340, 531, 550, 109), 24,
		func() -> void: wager_pressed.emit())
	_wager_btn.tooltip_text = "每关一次，可放弃。猜中对手扣 18 点，猜错你扣 18 点。不会消耗转盘次数。"
	_wager_btn.hide()
	var tip := _label(game_layer, "空格 转盘 · 1/2/3 道具 · Enter 结束 · F1 说明",
		22, COL_DIM, Rect2(1340, 1036, 550, 30), HORIZONTAL_ALIGNMENT_CENTER)
	tip.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))


# ------------------------------------------------------------
#  刷新
# ------------------------------------------------------------
func set_hint(text: String, danger := false) -> void:
	if _hint_label == null:
		return
	_hint_label.text = text
	_hint_label.add_theme_color_override("font_color", COL_RED.lightened(0.25) if danger else COL_TEXT)


func set_boss_header(b: Dictionary) -> void:
	_boss = b
	if _boss_name == null:
		return
	_boss_name.text = "第 %d 关 · %s" % [int(b.get("level", 1)), String(b.get("name", ""))]
	_boss_alias.text = String(b.get("alias", ""))
	var acc := _accent_of(b).lightened(0.25)
	_boss_name.add_theme_color_override("font_color", acc)


func update_side(which: String, hp: int, max_hp: int, bullets: int, status: String) -> void:
	var hp_text := _player_hp_text if which == "player" else _boss_hp_text
	var fill := _player_hp_fill if which == "player" else _boss_hp_fill
	var dots := _player_dots if which == "player" else _boss_dots
	var status_label := _player_status if which == "player" else _boss_status
	if hp_text == null:
		return
	var ratio := clampf(float(hp) / float(maxi(max_hp, 1)), 0.0, 1.0)
	var col := COL_GREEN
	if ratio <= 0.3:
		col = COL_RED
	elif ratio <= 0.6:
		col = COL_WOOD
	hp_text.text = "%d / %d" % [hp, max_hp]
	hp_text.add_theme_color_override("font_color", col)
	fill.size = Vector2(maxf(0.0, (364.0 - 6.0) * ratio), 16.0)
	fill.add_theme_stylebox_override("panel", _sb(col, col, 0, 9))
	for i in dots.size():
		var dot: Panel = dots[i]
		if i < bullets:
			dot.add_theme_stylebox_override("panel", _sb(COL_WOOD, Color(1.0, 0.88, 0.55), 2, 9))
		else:
			dot.add_theme_stylebox_override("panel", _sb(Color(0.10, 0.09, 0.08), Color(0.30, 0.25, 0.18), 2, 9))
	status_label.text = status


func set_streak(streak: int, momentum: bool) -> void:
	if _player_streak == null:
		return
	if momentum:
		_player_streak.text = "气势 爆发!"
		_player_streak.add_theme_color_override("font_color", Color(1.0, 0.78, 0.30))
	else:
		_player_streak.text = "气势 %d/3" % mini(streak, 3)
		_player_streak.add_theme_color_override("font_color", COL_DIM)


func set_items(items: Array, can_use: bool) -> void:
	_player_items = items
	_can_use_item = can_use
	if _item_buttons.is_empty():
		return
	var max_lv := Items.max_level()
	for i in _item_buttons.size():
		var b: Button = _item_buttons[i]
		if i < items.size():
			var it: Dictionary = items[i]
			var id := String(it.get("id", ""))
			var lv := int(it.get("lv", 1))
			var neg := Items.is_negative(id)
			var pips := ""
			for k in max_lv:
				pips += ("●" if k < lv else "○")
			b.text = "[%d] %s\n%s Lv%d · %s" % [i + 1, Items.item_name(id), pips, lv,
				Items.short_text(id)]
			b.tooltip_text = Items.line(id, lv)
			b.disabled = (not can_use) or neg
		else:
			b.text = "[%d] 空槽\n转到「具」会自动填充" % (i + 1)
			b.tooltip_text = "空槽位：转盘转到「具」时会自动放入，不需要手动摆放"
			b.disabled = true


func set_logs(logs: Array) -> void:
	for i in _log_labels.size():
		if i < logs.size():
			var prefix := "▸ " if i == 0 else "  "
			_log_labels[i].text = prefix + String(logs[i])
			_log_labels[i].add_theme_color_override("font_color", COL_TEXT if i == 0 else COL_DIM)
		else:
			_log_labels[i].text = ""


func set_wager(available: bool, tell: String, can_challenge: bool) -> void:
	_wager_btn.visible = available
	_wager_btn.disabled = not can_challenge
	_wager_btn.text = "他声称木牌下有红印 · %s\n质疑暗押 [Q] · 判错扣 18 生命" % tell


func set_actions(can_spin: bool, can_end: bool) -> void:
	if _spin_btn == null:
		return
	_spin_btn.disabled = not can_spin
	_end_btn.disabled = not can_end


# ------------------------------------------------------------
#  弹窗
# ------------------------------------------------------------
func _build_modal() -> void:
	_modal = Control.new()
	_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal.visible = false

	add_child(_modal)


func is_modal_open() -> bool:
	return modal_kind != ""


func hide_modal() -> void:
	modal_kind = ""
	_modal.visible = false
	if game_layer != null:
		game_layer.visible = true
	_clear(_modal)


func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


func _new_modal(kind: String) -> Panel:
	modal_kind = kind
	_modal.visible = true
	if game_layer != null:
		game_layer.visible = (kind == "replace" or kind == "help")
	_clear(_modal)
	var dim := ColorRect.new()
	dim.color = Color(0.015, 0.012, 0.010, 0.86)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal.add_child(dim)
	return null


func _modal_panel(rect: Rect2, border: Color) -> Panel:
	var p := Panel.new()
	p.position = rect.position
	p.size = rect.size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", _sb(Color(0.075, 0.065, 0.055, 0.99), border, 3, 22))
	_modal.add_child(p)
	return p


func show_title(best := 0, clears := 0) -> void:
	_new_modal("title")
	var artwork := TextureRect.new()
	artwork.texture = preload("res://art/bg_den2_clean.png")
	artwork.size = Vector2(1240, 1080)
	artwork.position = Vector2(680, 0)
	artwork.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	artwork.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	artwork.modulate = Color("#ad9b88")
	artwork.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal.add_child(artwork)

	var shade := ColorRect.new()
	shade.color = Color(0.017, 0.023, 0.030, 0.22)
	shade.position = artwork.position
	shade.size = artwork.size
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal.add_child(shade)

	var medallion := TextureRect.new()
	medallion.texture = preload("res://art/roulette-medallion.png")
	medallion.position = Vector2(990, 232)
	medallion.size = Vector2(640, 640)
	medallion.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	medallion.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal.add_child(medallion)

	var p := _panel(_modal, Rect2(0, 0, 740, 1080), Color("#11171f"), Color("#11171f"), 0)
	_panel(p, Rect2(736, 0, 4, 1080), COL_WOOD.darkened(0.35), COL_WOOD.darkened(0.35), 0)
	_panel(p, Rect2(76, 258, 76, 4), COL_WOOD, COL_WOOD, 0)
	_label(p, "生死轮盘", 104, COL_TEXT, Rect2(72, 280, 620, 140))
	_label(p, "地下酒馆 · 轮盘与暗骰六关", 32, COL_WOOD, Rect2(80, 443, 570, 50))
	_label(p, "每回合转一次轮盘，随后可使用一件道具。", 24, COL_DIM,
		Rect2(80, 520, 600, 40))
	_button(p, "开始对决  [Enter]", Rect2(80, 628, 380, 82), 30,
		func() -> void: start_pressed.emit())
	for i in 6:
		_button(p, "第 %d 关" % (i + 1), Rect2(80 + (i % 3) * 176, 716 + floori(i / 3.0) * 64, 162, 52), 24,
			func() -> void: level_selected.emit(i + 1))
	if best > 0:
		_label(p, "最高到达第 %d 关 · 完整通关 %d 次" % [best, clears], 22, COL_DIM,
			Rect2(80, 872, 610, 44))


func show_boss_intro(b: Dictionary) -> void:
	_new_modal("intro")
	var acc := _accent_of(b)
	var p := _modal_panel(Rect2(430, 120, 1060, 840), acc)
	_label(p, "第 %d 关" % int(b.get("level", 1)), 34, acc, Rect2(60, 28, 940, 50), HORIZONTAL_ALIGNMENT_CENTER)
	_label(p, String(b.get("name", "")), 96, COL_TEXT, Rect2(60, 82, 940, 130), HORIZONTAL_ALIGNMENT_CENTER)
	_label(p, String(b.get("alias", "")), 32, COL_DIM, Rect2(60, 214, 940, 46), HORIZONTAL_ALIGNMENT_CENTER)

	var quote := "“%s”" % String(b.get("quote", ""))
	var q := _label(p, quote, 30, Color(0.95, 0.88, 0.72), Rect2(90, 286, 880, 100), HORIZONTAL_ALIGNMENT_CENTER)
	q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var rule_box := Panel.new()
	rule_box.position = Vector2(110, 412)
	rule_box.size = Vector2(840, 150)
	rule_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule_box.add_theme_stylebox_override("panel", _sb(Color(0.13, 0.10, 0.07), acc.darkened(0.3), 2, 14))
	p.add_child(rule_box)
	_label(rule_box, "特殊规则", 24, acc, Rect2(24, 8, 792, 32))
	var r := _label(rule_box, String(b.get("rule", "")), 26, COL_TEXT, Rect2(24, 46, 792, 92))
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.vertical_alignment = VERTICAL_ALIGNMENT_TOP

	_label(p, "HP %d · 你依然先手。" % int(b.get("hp", 120)),
		22, COL_DIM, Rect2(60, 590, 940, 32), HORIZONTAL_ALIGNMENT_CENTER)
	var b2 := _button(p, "进入对决\n[Enter / 点击]", Rect2(330, 652, 400, 96), 28,
		func() -> void: intro_continue.emit())


func show_replace(item_id: String, slots: Array) -> void:
	_new_modal("replace")
	var p := _modal_panel(Rect2(500, 230, 920, 620), COL_RED)
	_label(p, "道具槽已满", 56, COL_RED.lightened(0.3), Rect2(40, 18, 840, 70), HORIZONTAL_ALIGNMENT_CENTER)
	_label(p, "又转到一件「%s」" % Items.label(item_id, 1), 30, COL_TEXT,
		Rect2(40, 92, 840, 44), HORIZONTAL_ALIGNMENT_CENTER)
	_label(p, Items.line(item_id, 1), 24, COL_DIM, Rect2(40, 136, 840, 40), HORIZONTAL_ALIGNMENT_CENTER)
	_label(p, "选择要丢掉的槽位（按 1/2/3 或直接点击），ESC 放弃新道具",
		24, COL_WOOD, Rect2(40, 180, 840, 38), HORIZONTAL_ALIGNMENT_CENTER)

	for i in 3:
		var text := ""
		if i < slots.size():
			var it: Dictionary = slots[i]
			text = "替换槽位 %d · %s\n%s" % [i + 1, Items.label(String(it.get("id", "")), int(it.get("lv", 1))),
				Items.line(String(it.get("id", "")), int(it.get("lv", 1)))]
		else:
			text = "槽位 %d · 空槽位" % (i + 1)
		_button(p, text, Rect2(60, 232 + i * 92, 800, 84), 24,
			func() -> void: replace_choice.emit(i))

	_button(p, "放弃新道具 [ESC]", Rect2(280, 520, 360, 68), 24,
		func() -> void: replace_choice.emit(-1))


func show_result(title: String, lines: Array, accent: Color) -> void:
	_new_modal("result")
	var p := _modal_panel(Rect2(560, 250, 800, 580), accent)
	_label(p, title, 62, accent.lightened(0.3), Rect2(40, 24, 720, 86), HORIZONTAL_ALIGNMENT_CENTER)
	for i in lines.size():
		var l := _label(p, String(lines[i]), 28, COL_TEXT, Rect2(80, 132 + i * 54, 640, 50),
			HORIZONTAL_ALIGNMENT_CENTER)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_button(p, "继续\n[Enter]", Rect2(270, 440, 260, 90), 28,
		func() -> void: result_continue.emit())


func show_game_over(win: bool, lines: Array) -> void:
	_new_modal("over")
	var acc := COL_WOOD if win else COL_RED
	var p := _modal_panel(Rect2(540, 240, 840, 620), acc)
	_label(p, "全 部 通 关" if win else "你 倒 下 了", 72, acc.lightened(0.25),
		Rect2(40, 24, 760, 100), HORIZONTAL_ALIGNMENT_CENTER)
	for i in lines.size():
		var l := _label(p, String(lines[i]), 28, COL_TEXT, Rect2(70, 140 + i * 56, 700, 52),
			HORIZONTAL_ALIGNMENT_CENTER)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_button(p, ("重新开始\n[Enter]" if win else "重试本关\n[Enter]"), Rect2(290, 460, 260, 96), 28,
		func() -> void: restart_pressed.emit())
	_button(p, "返回选关", Rect2(572, 468, 186, 80), 24,
		func() -> void: title_requested.emit())


func show_help() -> void:
	_new_modal("help")
	var p := _modal_panel(Rect2(320, 60, 1280, 960), COL_WOOD)
	_label(p, "生死轮盘 · v5 说明", 64, COL_TEXT, Rect2(60, 18, 1160, 86), HORIZONTAL_ALIGNMENT_CENTER)
	var rules := [
		"1. 每回合只能转一次转盘；结算立即生效，然后可以用 1 个道具（可选），再结束回合。",
		"2. 转盘 36 格：空/弹/枪/具/疗/咒/双/伤/胎/药。空结果约占 40%，是心理战的核心。",
		"3. 「具」会给你一件随机道具；重复获得同名道具会升级（Lv1→Lv3），不会丢失。",
		"4. 道具槽只有 3 个；槽满时会出现三选一：替换槽位 1/2/3，或按 ESC 放弃。",
		"5. 「胎」和「药」是负面道具：轮胎让你若干回合不能转盘，劣质火药让下次开枪减伤。",
		"6. 连续 3 次空转会积累气势，下一次伤害 +10%。右下角日志会解释每次结算。",
		"7. 5 个 Boss 各有特殊规则，开战前会显示。台词只会在气泡里出现，你无法回话。",
		"8. 低血量时心跳会加快、屏幕出现红色脉动；开枪会震动屏幕。",
	]
	for i in rules.size():
		var l := _label(p, rules[i], 26, COL_TEXT, Rect2(60, 120 + i * 82, 1160, 76))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_label(p, "快捷键：空格 转动 · 1/2/3 用道具 · Enter 结束回合 · F1 / ESC 关闭本页",
		24, COL_DIM, Rect2(60, 800, 1160, 34), HORIZONTAL_ALIGNMENT_CENTER)
	_button(p, "返回对局 [ESC]", Rect2(490, 850, 300, 78), 26,
		func() -> void: help_pressed.emit())


func _accent_of(b: Dictionary) -> Color:
	var arr = b.get("accent", [0.8, 0.6, 0.25])
	if arr is Array and arr.size() >= 3:
		return Color(float(arr[0]), float(arr[1]), float(arr[2]))
	return COL_WOOD


func _unhandled_input(event: InputEvent) -> void:
	if modal_kind == "":
		return
	if not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return
	match modal_kind:
		"title":
			if k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER or k.keycode == KEY_SPACE:
				start_pressed.emit()
				get_viewport().set_input_as_handled()
		"intro":
			if k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER or k.keycode == KEY_SPACE:
				intro_continue.emit()
				get_viewport().set_input_as_handled()
		"result":
			if k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
				result_continue.emit()
				get_viewport().set_input_as_handled()
		"over":
			if k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
				restart_pressed.emit()
				get_viewport().set_input_as_handled()
		"replace":
			match k.keycode:
				KEY_1:
					replace_choice.emit(0)
				KEY_2:
					replace_choice.emit(1)
				KEY_3:
					replace_choice.emit(2)
				KEY_ESCAPE:
					replace_choice.emit(-1)
			get_viewport().set_input_as_handled()
		"help":
			if k.keycode == KEY_ESCAPE or k.keycode == KEY_F1:
				help_pressed.emit()
				get_viewport().set_input_as_handled()
