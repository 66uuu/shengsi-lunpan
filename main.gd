extends Control
# ============================================================
#  main.gd —— 流程状态机
#  TITLE → BOSS_INTRO → PLAYER_TURN → SPINNING → RESOLVE
#        → ITEM_PHASE → AI_TURN → GAME_OVER
#  只做流程编排、表现与输入；战斗数值全部在 systems/battle.gd
# ============================================================

const TableViewScript = preload("res://ui/table_view.gd")
const WheelScript = preload("res://ui/wheel.gd")
const HUDScript = preload("res://ui/hud.gd")
const BubbleScript = preload("res://ui/dialogue_bubble.gd")
const VignetteScript = preload("res://ui/vignette.gd")
const AudioScript = preload("res://systems/audio.gd")
const PauseScript = preload("res://ui/pause_menu.gd")
const BattleScript = preload("res://systems/battle.gd")
const Items = preload("res://systems/items.gd")

enum Phase { TITLE, BOSS_INTRO, PLAYER_TURN, SPINNING, RESOLVE, ITEM_PHASE, AI_TURN, GAME_OVER }

var font: Font
var ui_theme: Theme

var world: Control
var table_view
var wheel
var hud
var bubble
var vignette
var flash_rect: ColorRect
var audio
var pause_menu

var battle
var bosses: Array = []
var dialogue: Dictionary = {}
var player_hp := 140
var level_index := 0
var phase := Phase.TITLE
var busy := false

var _boss_low_said := false
var _hint_override := ""

var total_rounds := 0
var total_damage := 0
var total_max_hit := 0

var rng := RandomNumberGenerator.new()
var shake_tween: Tween

const SAVE_PATH := "user://progress.cfg"
var best_level := 0
var total_clears := 0


func _ready() -> void:
	rng.randomize()
	_setup_theme()
	_load_data()
	_load_progress()

	if _has_arg("--autoplay"):
		_run_autoplay()
		return

	_build()
	if _has_arg("--shot-battle"):
		debug_start_gameplay(0)
	else:
		world.visible = false
		hud.show_title(best_level, total_clears)
		phase = Phase.TITLE
		_refresh()


# ------------------------------------------------------------
#  初始化
# ------------------------------------------------------------
func _has_arg(flag: String) -> bool:
	for a in OS.get_cmdline_args():
		if a == flag:
			return true
	for a in OS.get_cmdline_user_args():
		if a == flag:
			return true
	return false


func _setup_theme() -> void:
	font = load("res://fonts/NotoSansSC-Regular.otf") as Font
	if font == null:
		var ff := FontFile.new()
		if ff.load_dynamic_font("res://fonts/NotoSansSC-Regular.otf") == OK:
			font = ff
	if font == null:
		font = ThemeDB.fallback_font
	ui_theme = Theme.new()
	ui_theme.default_font = font
	ui_theme.default_font_size = 26
	theme = ui_theme


func _load_data() -> void:
	var data := _read_json("res://data/bosses.json")
	bosses = data.get("bosses", [])
	player_hp = int(data.get("player_hp", 140))
	dialogue = _read_json("res://data/dialogue.json")
	if bosses.is_empty():
		push_error("bosses.json 为空")


func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("无法读取 " + path)
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error(path + " 格式错误")
		return {}
	return parsed


# ------------------------------------------------------------
#  本地存档（最佳纪录 / 累计通关）
# ------------------------------------------------------------
func _load_progress() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		best_level = int(cf.get_value("progress", "best_level", 0))
		total_clears = int(cf.get_value("progress", "total_clears", 0))


func _save_progress() -> void:
	var cf := ConfigFile.new()
	cf.set_value("progress", "best_level", best_level)
	cf.set_value("progress", "total_clears", total_clears)
	cf.save(SAVE_PATH)


func _build() -> void:
	world = Control.new()
	world.name = "World"
	add_child(world)
	world.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	world.mouse_filter = Control.MOUSE_FILTER_IGNORE

	table_view = TableViewScript.new()
	world.add_child(table_view)
	table_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	table_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	table_view.set_font(font)

	wheel = WheelScript.new()
	world.add_child(wheel)
	wheel.position = Vector2(700, 590)
	wheel.size = Vector2(520, 520)
	wheel.tick.connect(_on_wheel_tick)
	wheel.spin_requested.connect(_on_spin_pressed)

	bubble = BubbleScript.new()
	bubble.position = Vector2(1340, 84)
	bubble.size = Vector2(550, 202)
	add_child(bubble)
	bubble.setup(font)

	hud = HUDScript.new()
	hud.name = "HUD"
	add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.build(font)
	hud.set_actions(false, false)
	hud.spin_pressed.connect(_on_spin_pressed)
	hud.end_pressed.connect(_on_end_pressed)
	hud.item_pressed.connect(_on_item_pressed)
	hud.replace_choice.connect(_on_replace_choice)
	hud.intro_continue.connect(_on_intro_continue)
	hud.result_continue.connect(_on_result_continue)
	hud.restart_pressed.connect(_on_restart)
	hud.help_pressed.connect(_on_help_pressed)
	hud.start_pressed.connect(_on_start)

	vignette = VignetteScript.new()
	add_child(vignette)
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE

	flash_rect = ColorRect.new()
	flash_rect.color = Color(1.0, 0.96, 0.88)
	add_child(flash_rect)
	flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_rect.modulate.a = 0.0

	audio = AudioScript.new()
	add_child(audio)

	var pm := PauseScript.new()
	pause_menu = pm
	add_child(pm)
	pm.setup(audio, ui_theme)


# ------------------------------------------------------------
#  关卡流程
# ------------------------------------------------------------
func _on_start() -> void:
	if phase != Phase.TITLE:
		return
	hud.hide_modal()
	total_rounds = 0
	total_damage = 0
	total_max_hit = 0
	_begin_level(0)


func _begin_level(i: int) -> void:
	level_index = i
	world.visible = true
	var b: Dictionary = bosses[i]
	battle = BattleScript.new()
	battle.setup(b, rng.randi(), player_hp)
	_boss_low_said = false
	_bubble_clear()

	table_view.set_boss(b)
	table_view.set_hp_ratio(1.0)
	hud.set_boss_header(b)
	wheel.setup(battle.wheel_layout, font)
	wheel.set_accent(_accent_of(b))
	wheel.spin_angle = 0.0
	wheel.spinning = false
	wheel.landed = -1
	wheel.queue_redraw()
	phase = Phase.BOSS_INTRO
	busy = false
	_hint_override = ""
	hud.show_boss_intro(b)
	_refresh()
	if audio != null:
		audio.play("ui")


func _on_intro_continue() -> void:
	if phase != Phase.BOSS_INTRO:
		return
	hud.hide_modal()
	_start_player_turn()


func _on_result_continue() -> void:
	if phase != Phase.RESOLVE:
		return
	hud.hide_modal()
	if level_index + 1 < bosses.size():
		_begin_level(level_index + 1)
	else:
		_show_victory()


func _on_restart() -> void:
	if phase != Phase.GAME_OVER:
		return
	hud.hide_modal()
	total_rounds = 0
	total_damage = 0
	total_max_hit = 0
	_begin_level(0)


func _on_help_pressed() -> void:
	if hud.modal_kind == "help":
		hud.hide_modal()
		_refresh()
		return
	if hud.is_modal_open():
		return
	hud.show_help()


# ------------------------------------------------------------
#  玩家回合
# ------------------------------------------------------------
func _start_player_turn() -> void:
	if phase == Phase.GAME_OVER:
		return
	phase = Phase.PLAYER_TURN
	busy = true
	battle.note("—— 第 %d 回合 · 你的回合 ——" % battle.round_num)
	_refresh()
	var logs: Array = battle.begin_turn(battle.player)
	await _play_logs(logs, 0.9)
	_refresh()
	if _check_over():
		return

	if battle.player.skipped_turn:
		_hint_override = "你被缩小灯缩小了，本回合直接跳过……"
		_refresh()
		audio.play("click")
		await _wait(1.5)
		_start_ai_turn()
		return

	if battle.player.cannot_spin:
		phase = Phase.ITEM_PHASE
		busy = false
		_hint_override = "轮胎漏气：本回合不能转盘，可以用 1 个道具后结束回合"
		_refresh()
		return

	phase = Phase.PLAYER_TURN
	busy = false
	_hint_override = ""
	_refresh()


func _on_spin_pressed() -> void:
	if hud.is_modal_open():
		return
	if phase != Phase.PLAYER_TURN or busy:
		return
	if battle == null or battle.player.cannot_spin:
		return
	_player_spin()


func _player_spin() -> void:
	busy = true
	phase = Phase.SPINNING
	_hint_override = "转盘转动中……"
	_refresh()
	audio.play("ui")

	var idx: int = battle.roll_spin_index(battle.player)
	var t := String(battle.wheel_layout[idx])
	await wheel.spin_to(idx, 2.1)

	phase = Phase.RESOLVE
	var res: Dictionary = battle.resolve_spin(battle.player, t)
	_apply_result(res, true)
	if _check_over():
		return
	await _wait(1.0)
	if phase == Phase.GAME_OVER:
		return

	if bool(res.get("full", false)):
		await _handle_full_slots()
		if phase == Phase.GAME_OVER:
			return

	phase = Phase.ITEM_PHASE
	busy = false
	_hint_override = ""
	_refresh()


func _handle_full_slots() -> void:
	var item_id := String(battle.pending_item)
	if item_id == "":
		return
	hud.show_replace(item_id, battle.player.items)
	var choice: int = await hud.replace_choice
	hud.hide_modal()
	battle.apply_replace(battle.player, item_id, int(choice))
	battle.pending_item = ""
	_refresh()
	await _wait(0.4)


func _on_replace_choice(index: int) -> void:
	pass


func _on_item_pressed(index: int) -> void:
	if hud.is_modal_open():
		return
	if phase != Phase.ITEM_PHASE or busy:
		return
	if battle == null or battle.player.item_used:
		return
	if index < 0 or index >= battle.player.items.size():
		_hint_override = "空槽：转到转盘的「具」时自动放入，不能手动摆放"
		_refresh()
		return
	var item_id := String(battle.player.items[index].get("id", ""))
	if Items.is_negative(item_id):
		return
	_use_player_item(index)


# ------------------------------------------------------------
#  使用道具
# ------------------------------------------------------------
func _use_player_item(index: int) -> void:
	busy = true
	var res: Dictionary = battle.use_item(battle.player, index)
	_apply_item(res, true)
	_refresh()
	await _wait(1.0)
	if _check_over():
		return
	busy = false
	_hint_override = ""
	_refresh()


func _on_end_pressed() -> void:
	if hud.is_modal_open():
		return
	if phase != Phase.ITEM_PHASE or busy:
		return
	_start_ai_turn()


# ------------------------------------------------------------
#  AI 回合
# ------------------------------------------------------------
func _start_ai_turn() -> void:
	if phase == Phase.GAME_OVER:
		return
	busy = true
	phase = Phase.AI_TURN
	_hint_override = "第 %d 回合 · %s 的回合……" % [battle.round_num, String(bosses[level_index].get("name", "对手"))]
	_refresh()
	await _wait(0.9)

	var upkeep: Array = battle.begin_turn(battle.boss)
	await _play_logs(upkeep, 0.85)
	if _check_over():
		return
	if battle.boss.skipped_turn:
		_hint_override = "对手被缩小了，跳过本回合"
		_refresh()
		await _wait(1.2)
		_finish_round()
		return

	var special: Array = battle.boss_turn_start()
	if not special.is_empty():
		await _play_logs(special, 0.9)
		_refresh()
		if _check_over():
			return

	var choice: int = battle.choose_item_for(battle.boss)
	if choice >= 0:
		var res: Dictionary = battle.use_item(battle.boss, choice)
		_apply_item(res, false)
		_refresh()
		await _wait(1.0)
		if _check_over():
			return

	_hint_override = "第 %d 回合 · 对手转动转盘……" % battle.round_num
	_refresh()
	await _wait(0.6)

	# 被嘴炮破防 / 漏气轮胎：转盘卡住，本回合只能看着
	if battle.boss.cannot_spin:
		_hint_override = "对手手抖得握不住转盘 —— 这回合他转不了。"
		_refresh()
		await _wait(1.5)
		_finish_round()
		return

	var idx: int = battle.roll_spin_index(battle.boss)
	var t := String(battle.wheel_layout[idx])
	await wheel.spin_to(idx, 2.0)

	phase = Phase.RESOLVE
	var res2: Dictionary = battle.resolve_spin(battle.boss, t)
	_apply_result(res2, false)
	_refresh()
	await _wait(1.1)
	if _check_over():
		return

	_finish_round()


func _finish_round() -> void:
	if phase == Phase.GAME_OVER:
		return
	battle.round_num += 1
	_start_player_turn()


# ------------------------------------------------------------
#  结算表现
# ------------------------------------------------------------
func _apply_result(res: Dictionary, actor_is_player: bool) -> void:
	var title := String(res.get("title", ""))
	var summary := String(res.get("summary", ""))
	if title != "":
		_hint_override = "【%s】%s" % [title, summary]
	else:
		_hint_override = summary

	var head := "你" if actor_is_player else String(battle.boss.display_name)
	var pre := "未知奖励 → " if bool(res.get("unknown", false)) else ""
	hud.show_banner("%s%s → %s：%s" % [pre, head, title, summary],
		Color(1.0, 0.88, 0.55) if actor_is_player else Color(1.0, 0.46, 0.40))

	if bool(res.get("shot", false)):
		if bool(res.get("empty_gun", false)):
			audio.play("click")
			_shake(8.0)
			_flash(0.18)
		else:
			audio.play("shot")
			_shake(18.0)
			_flash(0.55)
		if bool(res.get("execution", false)):
			_shake(28.0)
			_flash(0.85)
			audio.play("thud")
	if int(res.get("damage", 0)) > 0:
		audio.play("thud")
		_shake(14.0)
		_flash(0.22)
		if actor_is_player:
			table_view.set_state("hit", 0.9)
		else:
			table_view.set_state("laugh", 1.1)
			table_view.add_blood()
	elif bool(res.get("actor_hurt", false)):
		audio.play("thud")
		_shake(8.0)
		_flash(0.14)
		if actor_is_player:
			table_view.add_blood()

	if bool(res.get("empty", false)):
		_say_boss("empty")
		if not actor_is_player:
			table_view.set_state("laugh", 1.2)

	var event := String(res.get("dialogue", ""))
	if event != "":
		_say_boss(event)
	if actor_is_player and int(res.get("damage", 0)) > 0:
		_say_boss("hurt")
	if String(res.get("item", "")) != "":
		audio.play("item")

	_check_boss_low()
	_refresh()


func _apply_item(res: Dictionary, actor_is_player: bool) -> void:
	if not bool(res.get("ok", false)):
		return
	_hint_override = "【%s】%s" % [String(res.get("title", "")), String(res.get("summary", ""))]
	hud.show_banner("%s → %s：%s" % ["你" if actor_is_player else String(battle.boss.display_name),
		String(res.get("title", "")), String(res.get("summary", ""))],
		Color(1.0, 0.88, 0.55) if actor_is_player else Color(1.0, 0.46, 0.40))
	if bool(res.get("shot", false)) or int(res.get("damage", 0)) > 0:
		audio.play("shot")
		_shake(16.0)
		_flash(0.4)
	if int(res.get("damage", 0)) > 0:
		audio.play("thud")
		if actor_is_player:
			table_view.set_state("hit", 1.0)
		else:
			table_view.set_state("laugh", 1.0)
		if not actor_is_player:
			table_view.add_blood()
	if bool(res.get("actor_hurt", false)):
		_shake(8.0)
		audio.play("thud")
		if actor_is_player:
			table_view.add_blood()
	if actor_is_player and int(res.get("damage", 0)) > 0:
		_say_boss("hurt")
	if not actor_is_player and int(res.get("damage", 0)) > 0:
		_say_boss("hit")
	if String(res.get("item", "")) != "":
		audio.play("item")
	_check_boss_low()
	_refresh()


func _play_logs(logs: Array, delay := 0.9) -> void:
	for l in logs:
		battle.note(String(l))
		_refresh()
		await _wait(delay)


func _say_boss(event: String) -> void:
	if battle == null or bubble == null:
		return
	var lib: Dictionary = dialogue.get(battle.level_id, {})
	var lines = lib.get(event, [])
	if not (lines is Array) or lines.is_empty():
		return
	var line := String(lines[rng.randi_range(0, lines.size() - 1)])
	bubble.say(line, String(bosses[level_index].get("name", "对手")))
	if event == "empty":
		table_view.set_state("laugh", 3.0)


func _bubble_clear() -> void:
	if bubble != null:
		bubble.clear_now()


func _check_boss_low() -> void:
	if battle == null or _boss_low_said:
		return
	if battle.boss.hp > 0 and battle.boss.hp <= int(battle.boss.max_hp * 0.3):
		_boss_low_said = true
		_say_boss("low")
		table_view.set_state("low", 2.0)


# ------------------------------------------------------------
#  胜负
# ------------------------------------------------------------
func _check_over() -> bool:
	if battle == null:
		return false
	if battle.boss.hp <= 0:
		_level_clear()
		return true
	if battle.player.hp <= 0:
		_defeat()
		return true
	return false


func _level_clear() -> void:
	if phase == Phase.GAME_OVER:
		return
	phase = Phase.RESOLVE
	busy = true
	table_view.set_state("hit", 1.6)
	_say_boss("lose")
	audio.play("win")
	total_rounds += battle.round_num
	total_damage += battle.player.damage_dealt
	total_max_hit = maxi(total_max_hit, battle.player.max_hit)
	best_level = maxi(best_level, level_index + 1)
	total_clears += 1
	_save_progress()

	var lines := [
		"回合数：%d" % battle.round_num,
		"造成伤害：%d" % battle.player.damage_dealt,
		"最高单次伤害：%d" % battle.player.max_hit,
		"剩余 HP：%d / %d" % [battle.player.hp, battle.player.max_hp],
	]
	hud.show_result("第 %d 关 · 通过" % int(bosses[level_index].get("level", 1)), lines,
		_accent_of(bosses[level_index]))
	_refresh()


func _defeat() -> void:
	phase = Phase.GAME_OVER
	busy = false
	_say_boss("win")
	table_view.set_state("laugh", 2.0)
	audio.play("lose")
	var lines := [
		"倒在第 %d 关：%s" % [int(bosses[level_index].get("level", 1)), String(bosses[level_index].get("name", ""))],
		"这一关回合数：%d" % battle.round_num,
		"这一关造成伤害：%d" % battle.player.damage_dealt,
		"最高单次伤害：%d" % battle.player.max_hit,
	]
	hud.show_game_over(false, lines)
	_refresh()


func _show_victory() -> void:
	phase = Phase.GAME_OVER
	audio.play("win")
	var lines := [
		"你走完了五张桌子。",
		"总回合数：%d" % total_rounds,
		"总造成伤害：%d" % total_damage,
		"最高单次伤害：%d" % total_max_hit,
	]
	hud.show_game_over(true, lines)
	_refresh()


# ------------------------------------------------------------
#  输入
# ------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return
	if k.keycode == KEY_F1:
		_on_help_pressed()
		get_viewport().set_input_as_handled()
		return
	if hud.is_modal_open():
		return
	match k.keycode:
		KEY_SPACE:
			_on_spin_pressed()
		KEY_1:
			_on_item_pressed(0)
		KEY_2:
			_on_item_pressed(1)
		KEY_3:
			_on_item_pressed(2)
		KEY_ENTER, KEY_KP_ENTER:
			_on_end_pressed()


# ------------------------------------------------------------
#  刷新
# ------------------------------------------------------------
func _refresh() -> void:
	if battle == null or hud == null:
		return
	hud.update_side("player", battle.player.hp, battle.player.max_hp,
		battle.player.bullets, _status_text(battle.player))
	hud.update_side("boss", battle.boss.hp, battle.boss.max_hp,
		battle.boss.bullets, _status_text(battle.boss))
	var can_item: bool = phase == Phase.ITEM_PHASE and not busy and not battle.player.item_used
	hud.set_items(battle.player.items, can_item)
	hud.set_streak(battle.player.empty_streak, battle.player.momentum)
	hud.set_logs(battle.log_lines)
	hud.set_actions(phase == Phase.PLAYER_TURN and not busy and not battle.player.cannot_spin,
		phase == Phase.ITEM_PHASE and not busy)

	if _hint_override != "":
		hud.set_hint(_hint_override, battle.player.hp <= int(battle.player.max_hp * 0.25))
	else:
		hud.set_hint(_default_hint(), false)

	var br := float(battle.boss.hp) / float(battle.boss.max_hp)
	table_view.set_hp_ratio(br)
	var pr := float(battle.player.hp) / float(battle.player.max_hp)
	vignette.danger = clampf((0.45 - pr) / 0.45, 0.0, 1.0)
	audio.set_tension(pr)


func _default_hint() -> String:
	match phase:
		Phase.TITLE:
			return "生死轮盘 · 按 Enter 开始"
		Phase.BOSS_INTRO:
			return "对手登场 · 按 Enter 进入对决"
		Phase.PLAYER_TURN:
			if battle != null and battle.player.cannot_spin:
				return "第 %d 回合 · 本回合不能转盘" % battle.round_num
			return "第 %d 回合 · 轮到你：按 空格 转动转盘" % (battle.round_num if battle != null else 1)
		Phase.SPINNING:
			return "转盘转动中……"
		Phase.RESOLVE:
			return "结算中……"
		Phase.ITEM_PHASE:
			if battle != null and not battle.player.item_used and not battle.player.items.is_empty():
				return "第 %d 回合 · 可用 1 个道具（1/2/3），或按 Enter 结束回合" % battle.round_num
			return "第 %d 回合 · 按 Enter 结束回合" % (battle.round_num if battle != null else 1)
		Phase.AI_TURN:
			return "对手回合……"
		Phase.GAME_OVER:
			return "对局结束 · 按 Enter 重新开始"
	return ""


func _status_text(f) -> String:
	var parts: Array = []
	if f.armor > 0:
		parts.append("防弹衣×%d" % f.armor)
	if f.immune > 0:
		parts.append("免伤%d" % f.immune)
	if f.dmg_mult > 1:
		parts.append("伤害×2")
	if f.poison > 0:
		parts.append("中毒%d" % f.poison)
	if f.bleed > 0:
		parts.append("流血%d" % f.bleed)
	if f.skip > 0:
		parts.append("跳过%d" % f.skip)
	if f.item_lv("tire") > 0:
		parts.append("漏气轮胎 Lv%d" % f.item_lv("tire"))
	if f.item_lv("powder") > 0:
		parts.append("劣质火药 Lv%d" % f.item_lv("powder"))
	if parts.is_empty():
		return "状态：正常"
	return "状态：" + " · ".join(parts)


func _accent_of(b: Dictionary) -> Color:
	var arr = b.get("accent", [0.8, 0.6, 0.25])
	if arr is Array and arr.size() >= 3:
		return Color(float(arr[0]), float(arr[1]), float(arr[2]))
	return Color(0.8, 0.6, 0.25)


# ------------------------------------------------------------
#  表现工具
# ------------------------------------------------------------
func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _on_wheel_tick() -> void:
	audio.tick()


func _shake(strength := 12.0) -> void:
	if shake_tween != null and shake_tween.is_valid():
		shake_tween.kill()
	world.position = Vector2.ZERO
	shake_tween = create_tween()
	shake_tween.tween_method(_set_shake.bind(strength), 1.0, 0.0, 0.34)
	shake_tween.tween_callback(_reset_shake)


func _set_shake(v: float, strength: float) -> void:
	world.position = Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * strength * v


func _reset_shake() -> void:
	world.position = Vector2.ZERO


func _flash(amount := 0.4) -> void:
	flash_rect.modulate.a = amount
	var tw := create_tween()
	tw.tween_property(flash_rect, "modulate:a", 0.0, 0.3)


# ------------------------------------------------------------
#  调试：截图用
# ------------------------------------------------------------
func debug_show_intro(i: int) -> void:
	_begin_level(i)


func debug_start_gameplay(i: int) -> void:
	_begin_level(i)
	hud.hide_modal()
	await _start_player_turn()


func debug_force_resolve(t: String) -> void:
	if battle == null:
		_begin_level(0)
	var idx := 0
	for i in battle.wheel_layout.size():
		if String(battle.wheel_layout[i]) == t:
			idx = i
			break
	wheel.spin_angle = -float(idx) * TAU / 36.0
	wheel.spinning = false
	wheel.landed = idx
	wheel.queue_redraw()
	phase = Phase.RESOLVE
	var res: Dictionary = battle.resolve_spin(battle.player, t)
	_apply_result(res, true)
	_refresh()


# ------------------------------------------------------------
#  自动对局（仅 --autoplay，不参与正常游戏）
# ------------------------------------------------------------
func _run_autoplay() -> void:
	print("=== 生死轮盘 v2 · 自动模拟 ===")
	var sim = BattleScript.new()
	var dist_battle = BattleScript.new()
	dist_battle.setup(bosses[4], 777)
	var dist := {}
	for n in 36000:
		var ti: int = dist_battle.roll_spin_index(dist_battle.player)
		var ty := String(dist_battle.wheel_layout[ti])
		dist[ty] = int(dist.get(ty, 0)) + 1
	print("权重抽样 36000 次（第5关）：" + str(dist))
	var wins := 0
	var total := 0
	for run in 4:
		print("--- 第 %d 局 ---" % (run + 1))
		for i in bosses.size():
			var b: Dictionary = bosses[i]
			var result: Dictionary = sim.debug_simulate(b, 1000 + run * 37 + i * 13)
			total += 1
			if String(result.get("winner", "")) == "player":
				wins += 1
			print("关卡%d %s：胜者=%s 回合=%d 玩家HP=%d 对手HP=%d 玩家伤害=%d 最高单次=%d 循环次数=%d 玩家转盘=%d 被跳过=%d 结果=%s" % [
				int(b.get("level", i + 1)), String(b.get("name", "")),
				String(result.get("winner", "")), int(result.get("rounds", 0)),
				int(result.get("player_hp", 0)), int(result.get("boss_hp", 0)),
				int(result.get("player_damage", 0)), int(result.get("player_max_hit", 0)),
				int(result.get("guard", 0)), int(result.get("p_spins", 0)),
				int(result.get("p_skips", 0)), str(result.get("types", {})),
			])
	print("=== 模拟结束：玩家胜 %d / %d 关 ===" % [wins, total])
	get_tree().quit(0)
