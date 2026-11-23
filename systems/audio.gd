extends Node
# ============================================================
#  systems/audio.gd
#  全部音效程序生成（无外部音频文件）
#  转盘滴答 / 枪声 / 空枪咔哒 / 心跳（低血量加速）/ 环境低频嗡鸣 / 命中闷响
# ============================================================

const RATE := 44100

var _players: Dictionary = {}
var _tick_pool: Array[AudioStreamPlayer] = []
var _tick_index := 0
var _heart: AudioStreamPlayer
var _music: AudioStreamPlayer
var _heart_clock := 0.0
var _tension := 0.0
var _dice_music := false
var _enabled := true


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		_enabled = false
		return
	_build()


func _ensure_buses() -> void:
	for bn in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bn) == -1:
			var i := AudioServer.bus_count
			AudioServer.add_bus(i)
			AudioServer.set_bus_name(i, bn)
			AudioServer.set_bus_send(i, "Master")


func _build() -> void:
	_ensure_buses()
	_add("tick", _gen_tick(), -9.0, "res://audio/sfx_tick.wav")
	_add("shot", _gen_shot(), -2.0, "res://audio/sfx_shot.wav")
	_add("click", _gen_click(), -6.0, "res://audio/sfx_click.wav")
	_add("thud", _gen_thud(), -3.0, "res://audio/sfx_thud.wav")
	_add("heal", _gen_heal(), -5.0, "res://audio/sfx_heal.wav")
	_add("ui", _gen_ui(), -8.0, "res://audio/sfx_ui.wav")
	_add("win", _gen_win(), -2.0, "res://audio/sfx_win.wav")
	_add("lose", _gen_lose(), -2.0, "res://audio/sfx_lose.wav")
	_add("item", _gen_item(), -5.0, "res://audio/sfx_item.wav")

	var tick_paths := [
		"res://audio/sfx_tick.wav",
		"res://audio/sfx_tick2.wav",
		"res://audio/sfx_tick3.wav",
	]
	for i in 4:
		var tp := AudioStreamPlayer.new()
		tp.stream = _load_or(String(tick_paths[i % tick_paths.size()]), _gen_tick())
		tp.volume_db = -10.0
		tp.bus = "SFX"
		add_child(tp)
		_tick_pool.append(tp)

	var amb := AudioStreamPlayer.new()
	amb.stream = _gen_ambient()
	amb.volume_db = -26.0
	amb.bus = "Music"
	add_child(amb)
	amb.play()

	# 背景音乐：52 秒循环，低频压迫 + 拍点 + 心跳 + 不协和金属尖啸
	var bgm := AudioStreamPlayer.new()
	var bs = load("res://audio/bgm_shadows.wav")
	if bs is AudioStreamWAV:
		bs.loop_mode = AudioStreamWAV.LOOP_FORWARD
		bs.loop_begin = 0
		bs.loop_end = bs.get_length() * bs.mix_rate
	bgm.stream = bs
	bgm.volume_db = -13.0
	bgm.bus = "Music"
	add_child(bgm)
	_music = bgm
	bgm.play()

	_heart = AudioStreamPlayer.new()
	_heart.stream = _load_or("res://audio/sfx_heart.wav", _gen_heart())
	_heart.volume_db = -8.0
	_heart.bus = "Music"
	add_child(_heart)


func _load_or(path: String, fallback: PackedFloat32Array) -> AudioStream:
	var s = load(path)
	if s is AudioStream:
		return s
	return _wav(fallback)


func _add(key: String, samples: PackedFloat32Array, db: float, path := "") -> void:
	var p := AudioStreamPlayer.new()
	if path != "":
		p.stream = _load_or(path, samples)
	else:
		p.stream = _wav(samples)
	p.volume_db = db
	p.bus = "SFX"
	add_child(p)
	_players[key] = p


func play(key: String) -> void:
	if not _enabled:
		return
	var p: AudioStreamPlayer = _players.get(key)
	if p != null:
		p.play()


func tick() -> void:
	if not _enabled or _tick_pool.is_empty():
		return
	var p: AudioStreamPlayer = _tick_pool[_tick_index]
	_tick_index = (_tick_index + 1) % _tick_pool.size()
	p.pitch_scale = randf_range(0.9, 1.12)
	p.play()


# 0.0 安全 → 1.0 濒死；心跳间隔随紧张度缩短
func set_dice_music(active: bool) -> void:
	_dice_music = active
	if _music != null:
		_music.volume_db = -48.0 if active else lerpf(-13.0, -8.0, _tension)


func set_tension(ratio: float) -> void:
	_tension = clampf(1.0 - ratio / 0.6, 0.0, 1.0)
	if _music != null:
		_music.volume_db = -48.0 if _dice_music else lerpf(-13.0, -8.0, _tension)


func _process(delta: float) -> void:
	if not _enabled or _heart == null:
		return
	if _tension <= 0.02:
		_heart_clock = 0.0
		return
	var interval := lerpf(0.95, 0.42, _tension)
	_heart_clock -= delta
	if _heart_clock <= 0.0:
		_heart_clock = interval
		_heart.pitch_scale = lerpf(0.92, 1.15, _tension)
		_heart.volume_db = lerpf(-16.0, -5.0, _tension)
		_heart.play()


# ------------------------------------------------------------
#  合成
# ------------------------------------------------------------
func _wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size() - 1
	return w


func _gen_tick() -> PackedFloat32Array:
	# 木质转盘“嗒”声：木腔共鸣 + 拨片瞬态（无电子高频）
	var n := int(RATE * 0.12)
	var out := PackedFloat32Array()
	out.resize(n)
	var noise := RandomNumberGenerator.new()
	noise.seed = 3311
	for i in n:
		var t := float(i) / RATE
		var v := sin(TAU * 392.0 * t) * exp(-t * 62.0) * 0.85
		v += sin(TAU * 208.0 * t) * exp(-t * 48.0) * 0.55
		v += sin(TAU * 623.0 * t) * exp(-t * 105.0) * 0.28
		v += noise.randf_range(-1.0, 1.0) * exp(-t * 700.0) * 0.25
		out[i] = v * 0.7
	return out


func _gen_shot() -> PackedFloat32Array:
	var n := int(RATE * 0.5)
	var out := PackedFloat32Array()
	out.resize(n)
	var noise := RandomNumberGenerator.new()
	noise.seed = 7123
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var nz := noise.randf_range(-1.0, 1.0)
		lp += (nz - lp) * 0.2
		var boom := sin(TAU * (92.0 * exp(-t * 16.0) + 30.0) * t) * exp(-t * 9.0)
		out[i] = boom * 0.9 + lp * 2.4 * exp(-t * 22.0) + nz * 0.45 * exp(-t * 80.0)
	return out


func _gen_click() -> PackedFloat32Array:
	var n := int(RATE * 0.12)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var a := sin(TAU * 1500.0 * t) * exp(-t * 130.0)
		var b := 0.0
		if t > 0.045:
			b = sin(TAU * 980.0 * (t - 0.045)) * exp(-(t - 0.045) * 90.0) * 0.6
		out[i] = a + b
	return out


func _gen_thud() -> PackedFloat32Array:
	var n := int(RATE * 0.34)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var f := 92.0 * exp(-t * 7.0) + 38.0
		out[i] = sin(TAU * f * t) * exp(-t * 9.0) * 0.85
	return out


func _gen_heart() -> PackedFloat32Array:
	var n := int(RATE * 0.62)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		if t < 0.2:
			v += sin(TAU * (58.0 * exp(-t * 6.0) + 32.0) * t) * exp(-t * 16.0)
		if t > 0.19:
			var t2 := t - 0.19
			v += 0.7 * sin(TAU * (52.0 * exp(-t2 * 6.0) + 30.0) * t2) * exp(-t2 * 18.0)
		out[i] = v * 0.9
	return out


func _gen_heal() -> PackedFloat32Array:
	var n := int(RATE * 0.42)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var f := 420.0 + 520.0 * t
		out[i] = (sin(TAU * f * t) + 0.35 * sin(TAU * f * 2.0 * t)) * exp(-t * 3.0) * 0.45
	return out


func _gen_item() -> PackedFloat32Array:
	var n := int(RATE * 0.36)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var f := 660.0 if t < 0.14 else 880.0
		out[i] = sin(TAU * f * t) * exp(-t * 5.0) * 0.35
	return out


func _gen_ui() -> PackedFloat32Array:
	var n := int(RATE * 0.06)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = (sin(TAU * 1500.0 * t) + 0.4 * sin(TAU * 2400.0 * t)) * exp(-t * 70.0) * 0.4
	return out


func _gen_win() -> PackedFloat32Array:
	var n := int(RATE * 0.9)
	var out := PackedFloat32Array()
	out.resize(n)
	var notes := [261.6, 329.6, 392.0, 523.2]
	for i in n:
		var t := float(i) / RATE
		var seg: int = int(t / 0.2)
		var f: float = notes[mini(seg, notes.size() - 1)]
		out[i] = (sin(TAU * f * t) + 0.3 * sin(TAU * f * 2.0 * t)) * exp(-t * 1.6) * 0.5
	return out


func _gen_lose() -> PackedFloat32Array:
	var n := int(RATE * 0.95)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var f := 190.0 * exp(-t * 1.0)
		out[i] = sin(TAU * f * t) * exp(-t * 1.1) * 0.6
	return out


func _gen_ambient() -> AudioStreamWAV:
	var seconds := 6.0
	var n := int(RATE * seconds)
	var out := PackedFloat32Array()
	out.resize(n)
	var noise := RandomNumberGenerator.new()
	noise.seed = 4242
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var trem := 0.55 + 0.45 * sin(TAU * (1.0 / seconds) * t)
		var tone := sin(TAU * 45.0 * t) * 0.5 + sin(TAU * 90.0 * t) * 0.22 + sin(TAU * 135.0 * t) * 0.08
		lp += (noise.randf_range(-1.0, 1.0) - lp) * 0.02
		out[i] = (tone * trem + lp * 1.4) * 0.22
	return _wav(out, true)
