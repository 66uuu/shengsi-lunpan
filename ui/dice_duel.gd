extends Control

signal finished(won: bool, rounds: int, jackpot: bool)

const Cinema = preload("res://ui/dice_cinema.gd")

const FACES := [Vector3.UP, Vector3.RIGHT, Vector3.BACK, Vector3.FORWARD, Vector3.LEFT, Vector3.DOWN]
const PIPS := [
	[Vector2.ZERO], [Vector2(-1,-1), Vector2(1,1)],
	[Vector2(-1,-1), Vector2.ZERO, Vector2(1,1)],
	[Vector2(-1,-1), Vector2(-1,1), Vector2(1,-1), Vector2(1,1)],
	[Vector2(-1,-1), Vector2(-1,1), Vector2.ZERO, Vector2(1,-1), Vector2(1,1)],
	[Vector2(-1,-1), Vector2(-1,0), Vector2(-1,1), Vector2(1,-1), Vector2(1,0), Vector2(1,1)],
]

const HOMES := [Vector3(-1.42, 0.444, 1.4), Vector3(1.33, 0.444, -0.78)]
var dice_audio: AudioStreamPlayer
var rng := RandomNumberGenerator.new()
var rounds := 0
var count: Array[int] = [0, 0]
var sixes: Array[int] = [0, 0]
var locked := false
var ended := false
var view: SubViewport
var stage: Node3D
var dice: Array[Node3D] = []
var ammo_bars: Array[Panel] = []
var ammo_names: Array[Label] = []
var camera: Camera3D
var offhand: Node3D
var background_music: AudioStreamPlayer
var pressure_music: AudioStreamPlayer
var camera_motion: Tween
var opponent: Node3D
var arm: Node3D
var head: Node3D
var prop: Node3D
var status: Label
var action: Button
var audio


func _ready() -> void:
	rng.randomize()
	var frame := SubViewportContainer.new()
	frame.stretch = true
	frame.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(frame)
	frame.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	view = SubViewport.new()
	view.own_world_3d = true
	view.msaa_3d = Viewport.MSAA_4X
	frame.add_child(view)
	stage = Node3D.new()
	view.add_child(stage)
	_build_stage()
	dice_audio = AudioStreamPlayer.new()
	dice_audio.stream = preload("res://audio/dice_table_roll.wav")
	dice_audio.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	dice_audio.volume_db = -5.0
	add_child(dice_audio)
	var veil := TextureRect.new()
	veil.texture = preload("res://art/dice-veil.png")
	veil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	veil.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(veil)
	veil.set_anchors_and_offsets_preset(PRESET_FULL_RECT)

	var header := _label("暗骰赌桌", 46)
	header.position = Vector2(63, 40)
	_build_ammo_card(Vector2(63, 454), 0)
	_build_ammo_card(Vector2(1589, 454), 1)
	status = _label("点数高者装一格，同点重掷。", 32)
	status.position = Vector2(68, 846)
	_start_music()
	action = Button.new()
	action.text = "掷骰  [空格]"
	action.add_theme_font_size_override("font_size", 34)
	action.position = Vector2(68, 905)
	action.custom_minimum_size = Vector2(350, 84)
	action.focus_mode = FOCUS_NONE
	add_child(action)
	action.pressed.connect(roll)
	_update_score()


func _build_ammo_card(position_on_screen: Vector2, side: int) -> void:
	var panel := Panel.new()
	panel.position = position_on_screen
	panel.size = Vector2(268, 114)
	panel.mouse_filter = MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.059, 0.036, 0.068, 0.96)
	style.border_color = Color("#c79a69") if side == 0 else Color("#bc657c")
	style.set_border_width_all(2)
	style.set_corner_radius_all(9)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var label := Label.new()
	label.position = Vector2(17, 10)
	label.add_theme_color_override("font_color", Color("#f4dfc4"))
	label.add_theme_font_size_override("font_size", 26)
	panel.add_child(label)
	ammo_names.append(label)
	for i in 6:
		var lamp := Panel.new()
		lamp.position = Vector2(17 + 39 * i, 67)
		lamp.size = Vector2(28, 20)
		lamp.mouse_filter = MOUSE_FILTER_IGNORE
		panel.add_child(lamp)
		ammo_bars.append(lamp)


func _start_music() -> void:
	if DisplayServer.get_name() == "headless":
		return
	background_music = _loop_track(preload("res://audio/dice_cinema_base.wav"), -10.0)
	pressure_music = _loop_track(preload("res://audio/dice_cinema_pulse.wav"), -34.0)
	background_music.play()
	pressure_music.play()
	if audio != null:
		audio.set_dice_music(true)


func _loop_track(asset: AudioStreamWAV, volume: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	var stream := asset.duplicate() as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = roundi(stream.get_length() * stream.mix_rate)
	player.stream = stream
	player.bus = "Music" if AudioServer.get_bus_index("Music") >= 0 else "Master"
	player.volume_db = volume
	add_child(player)
	return player


func _exit_tree() -> void:
	if is_instance_valid(audio) and background_music != null:
		audio.set_dice_music(false)


func _frame_camera(fov: float, shift: float, duration: float) -> void:
	if camera_motion and camera_motion.is_valid():
		camera_motion.kill()
	camera_motion = create_tween().set_parallel().set_trans(Tween.TRANS_SINE)
	camera_motion.tween_property(camera, "fov", fov, duration)
	camera_motion.tween_property(camera, "h_offset", shift, duration)


func _label(message: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = message
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("#f4dfc4"))
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(label)
	return label


func _mesh(parent: Node3D, model: Mesh, pos: Vector3, color: Color) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = model
	var surface := StandardMaterial3D.new()
	surface.albedo_color = color
	surface.roughness = 0.72
	part.material_override = surface
	parent.add_child(part)
	part.position = pos
	return part


func _box(parent: Node3D, dimensions: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var model := BoxMesh.new()
	model.size = dimensions
	return _mesh(parent, model, pos, color)


func _oval(parent: Node3D, pos: Vector3, scale_value: Vector3, color: Color) -> MeshInstance3D:
	var model := SphereMesh.new()
	var part := _mesh(parent, model, pos, color)
	part.scale = scale_value
	return part


func _light(pos: Vector3, color: Color, energy: float, radius: float) -> void:
	var lamp := OmniLight3D.new()
	stage.add_child(lamp)
	lamp.position = pos
	lamp.light_color = color
	lamp.light_energy = energy
	lamp.omni_range = radius


func _build_stage() -> void:
	camera = Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(0, 3.75, 8.70)
	camera.look_at(Vector3(0, 1.00, -0.63))
	camera.fov = 41.0
	camera.current = true
	var atmosphere := WorldEnvironment.new()
	atmosphere.environment = Environment.new()
	atmosphere.environment.background_mode = Environment.BG_COLOR
	atmosphere.environment.background_color = Color("#100c19")
	atmosphere.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	atmosphere.environment.ambient_light_color = Color("#77708d")
	atmosphere.environment.ambient_light_energy = 0.46
	stage.add_child(atmosphere)
	_light(Vector3(-3, 2.8, -1.6), Color("#79b9dc"), 2.05, 9.5)
	_light(Vector3(3.4, 3.05, -2.6), Color("#fb657a"), 2.6, 9.8)
	var key := SpotLight3D.new()
	stage.add_child(key)
	key.position = Vector3(-0.12, 5.55, 1.18)
	key.look_at(Vector3(0, 1.25, -1.7))
	key.light_color = Color("#ffcc9c")
	key.light_energy = 3.5
	key.spot_range = 11
	key.spot_angle = 49
	key.shadow_enabled = true
	key.shadow_bias = 0.22
	key.shadow_normal_bias = 2.4
	Cinema.build_room(stage)
	var dealer := Cinema.build_dealer(stage)
	opponent = dealer.body
	head = dealer.head
	arm = dealer.arm
	offhand = dealer.offhand
	# 轻微的呼吸和视线移动让停顿本身也有表演。
	var idle := create_tween().set_loops().set_trans(Tween.TRANS_SINE)
	idle.tween_property(opponent, "position:y", 0.043, 2.35)
	idle.tween_property(opponent, "position:y", 0.0, 2.35)
	prop = Node3D.new()
	stage.add_child(prop)
	prop.position = Vector3(0, 0.18, -0.50)
	Cinema.box(prop, Vector3(-0.34, 0, 0), Vector3(0.83, 0.122, 0.148), Color("#838296"), 0.72)
	Cinema.box(prop, Vector3(-0.24, 0.073, 0), Vector3(0.87, 0.035, 0.115), Color("#4a5164"), 0.82)
	var drum := Cinema.band(prop, Vector3(0.11, 0, 0.0), 0.145, 0.145, 0.245, Color("#6c6479"), 0.67)
	drum.rotation.z = PI * 0.5
	Cinema.box(prop, Vector3(0.28, 0.0, 0.095), Vector3(0.28, 0.136, 0.21), Color("#8b8496"), 0.55)
	var stock := Cinema.box(prop, Vector3(0.40, -0.04, 0.23), Vector3(0.206, 0.134, 0.29), Color("#502f3b"))
	stock.rotation.y = -0.30
	dice.append(_die(HOMES[0], Color("#e3c9a9")))
	dice.append(_die(HOMES[1], Color("#80395e")))


func _die(pos: Vector3, color: Color) -> Node3D:
	var die := Node3D.new()
	stage.add_child(die)
	die.position = pos
	var shell := Cinema.mesh(die, Cinema.rounded_die(), Vector3.ZERO, color)
	(shell.material_override as StandardMaterial3D).roughness = 0.34
	for i in 6:
		var normal: Vector3 = FACES[i]
		var tangent := normal.cross(Vector3.FORWARD if absf(normal.y) > 0.5 else Vector3.UP)
		var other := normal.cross(tangent)
		for pip: Vector2 in PIPS[i]:
			var face_pos := normal * 0.401 + (tangent * pip.x + other * pip.y) * 0.195
			_oval(die, face_pos, Vector3.ONE * 0.115, Color("#221724"))
	return die


func _update_score() -> void:
	for side in 2:
		ammo_names[side].text = "%s  %d / 6" % ["你的弹量" if side == 0 else "对手弹量", count[side]]
		for i in 6:
			var style := StyleBoxFlat.new()
			style.bg_color = (Color("#e6b574") if side == 0 else Color("#e9859c")) if i < count[side] else Color("#35263c")
			style.border_color = Color("#78617c")
			style.set_border_width_all(1)
			style.set_corner_radius_all(5)
			ammo_bars[side * 6 + i].add_theme_stylebox_override("panel", style)
	if pressure_music != null:
		var pressure := maxf(count[0], count[1]) / 6.0
		create_tween().tween_property(pressure_music, "volume_db", lerpf(-34.0, -5.0, pressure), 0.30)


func settle(a: int, b: int) -> Dictionary:
	rounds += 1
	sixes[0] = sixes[0] + 1 if a == 6 else 0
	sixes[1] = sixes[1] + 1 if b == 6 else 0
	var winner := -1
	var jackpot := false
	if a != b:
		winner = 0 if a > b else 1
		count[winner] += 1
		jackpot = sixes[winner] >= 3
	return {"side": winner, "jackpot": jackpot, "done": winner >= 0 and (jackpot or count[winner] == 6)}


func roll() -> void:
	if locked or ended:
		return
	locked = true
	action.disabled = true
	status.text = "骰子翻滚中……"
	var values := [rng.randi_range(1, 6), rng.randi_range(1, 6)]
	dice_audio.play()
	_frame_camera(38.0, 0.0, 0.7)
	var toss := create_tween().set_parallel()
	for i in 2:
		var which: int = i
		var landed := Quaternion(FACES[values[i] - 1], Vector3.UP)
		toss.tween_method(func(t: float) -> void:
			var die := dice[which]
			var home: Vector3 = HOMES[which]
			var side := -1.0 if which == 0 else 1.0
			var travel := sin(PI * t)
			# 先向中央抛掷，再绕开另一枚骰子滑回各自的落点。
			var band := Vector3(side * cos(t * TAU) * 0.87, 0, side * sin(t * TAU) * 1.05)
			die.position = home.lerp(band, travel * 0.84)
			die.position.y = home.y + absf(sin(t * TAU * 2.0)) * pow(1.0-t, 1.5) * 1.18
			if t < 0.82:
				die.rotation = Vector3(t * 16.2, t * 11.3, t * 15.4 * (1 if which == 0 else -1))
			else:
				die.quaternion = Quaternion.from_euler(Vector3(13.284, 9.266, 12.628 * (1 if which == 0 else -1))).slerp(landed, (t-0.82)/0.18)
		, 0.0, 1.0, 1.48)
	toss.tween_property(arm, "rotation:x", 0.06, 0.43)
	toss.tween_property(head, "rotation:z", 0.09 if rounds % 2 == 0 else -0.07, 0.70)
	toss.tween_property(offhand, "rotation:x", 0.08, 0.42)
	await toss.finished
	var result := settle(values[0], values[1])
	var side: int = result.side
	status.text = "你 %d  ·  荷官 %d    三连六 %d/3 · %d/3    " % [values[0], values[1], mini(3, sixes[0]), mini(3, sixes[1])]
	if side == -1:
		status.text += "平局，未装填。重新掷骰。"
	else:
		status.text += ("你" if side == 0 else "对手") + "胜出。"
		await _animate_load(side)
	_update_score()
	if result.done:
		ended = true
		await _finish_visual(side)
		status.text = ("彩蛋：三连六。 " if result.jackpot else "六格已满。 ") + ("你赢了。" if side == 0 else "对手赢了。")
		await get_tree().create_timer(0.8, false).timeout
		finished.emit(side == 0, rounds, result.jackpot)
		return
	_frame_camera(41.0, 0.0, 0.45)
	create_tween().tween_property(offhand, "rotation:x", 0.32, 0.25)
	locked = false
	action.disabled = false


func _animate_load(side: int) -> void:
	_frame_camera(37.5, -0.18 if side == 0 else 0.18, 0.45)
	var start := prop.position
	var lift := start + Vector3(-0.55 if side == 0 else 0.70, 0.85, 0.65 if side == 0 else -0.88)
	var lift_move := create_tween().set_parallel().set_trans(Tween.TRANS_SINE)
	lift_move.tween_property(prop, "position", lift, 0.29)
	lift_move.tween_property(arm, "rotation:x", -0.23 if side == 1 else 0.16, 0.28)
	lift_move.tween_property(prop, "rotation:z", 0.32, 0.28)
	await lift_move.finished
	var counter := _oval(stage, lift + Vector3(0.34, 0.42, 0.12), Vector3(0.12, 0.21, 0.12), Color("#eca860"))
	var insert := create_tween()
	insert.tween_property(counter, "position", lift + Vector3(0.16, 0, 0), 0.30)
	await insert.finished
	counter.queue_free()
	_update_score()
	if audio != null:
		audio.play("click")
	var put_down := create_tween().set_parallel()
	put_down.tween_property(arm, "rotation:x", 0.24, 0.24)
	put_down.tween_property(prop, "position", start, 0.24)
	put_down.tween_property(prop, "rotation:z", 0.0, 0.24)
	await put_down.finished


func _finish_visual(side: int) -> void:
	_frame_camera(33.7, 0.0, 0.38)
	var motion := create_tween().set_parallel()
	motion.tween_property(prop, "position", Vector3(0.62 if side == 1 else -0.42, 1.0, -1.25 if side == 1 else 1.05), 0.4)
	motion.tween_property(arm, "rotation:x", -0.48 if side == 1 else 0.1, 0.4)
	await motion.finished
	if audio != null:
		audio.play("shot")
	var flash := ColorRect.new()
	flash.color = Color(1, 0.58, 0.3, 0.66)
	flash.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(flash)
	move_child(flash, 1)
	flash.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var recoil := create_tween().set_parallel()
	recoil.tween_property(flash, "modulate:a", 0.0, 0.16)
	recoil.tween_property(prop, "rotation:z", 0.48, 0.16)
	recoil.tween_property(opponent, "rotation:x", -0.24 if side == 0 else -0.06, 0.23)
	await recoil.finished
	flash.queue_free()
