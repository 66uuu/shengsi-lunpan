extends Control
# ============================================================
#  ui/table_view.gd
#  写实暗黑对坐场景：脏酒吧底图 + AI 写实立绘 + 桌面遮挡 + 压迫感
# ============================================================

const W := 1920.0
const H := 1080.0
const BOSS_H := 720.0        # 立绘显示高度
const BOSS_BOTTOM := 800.0   # 立绘底边，伸到桌子后面，由桌面条盖住
const DESK_Y := 748.0        # 背景图里桌面的远边

var font: Font
var boss: Dictionary = {}
var hp_ratio := 1.0
var state := "idle"

var _state_left := 0.0
var _time := 0.0
var _hit_flash := 0.0
var _tex_bg: Texture2D
var _tex_boss: Texture2D
var _last_ratio := 1.0
var _blood: Array = []
var _rng := RandomNumberGenerator.new()
var _twitch := 0.0
var _twitch_t := 2.0
var _grad_in: GradientTexture2D     # 黑 → 透明
var _grad_out: GradientTexture2D    # 透明 → 黑
var _grad_top: GradientTexture2D    # 上黑 → 下透明


func _ready() -> void:
	_tex_bg = load("res://art/bg_den2_clean.png")
	_rng.seed = 7719
	_grad_in = _make_grad(false, true)
	_grad_out = _make_grad(true, true)
	_grad_top = _make_grad(false, false)
	set_process(true)


func _make_grad(rev: bool, horizontal: bool) -> GradientTexture2D:
	var g := Gradient.new()
	if rev:
		g.set_color(0, Color(0, 0, 0, 0))
		g.set_color(1, Color(0, 0, 0, 1))
	else:
		g.set_color(0, Color(0, 0, 0, 1))
		g.set_color(1, Color(0, 0, 0, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	if horizontal:
		t.width = 256
		t.height = 16
		t.fill_from = Vector2(0, 0)
		t.fill_to = Vector2(1, 0)
	else:
		t.width = 16
		t.height = 256
		t.fill_from = Vector2(0, 0)
		t.fill_to = Vector2(0, 1)
	return t


func set_font(f: Font) -> void:
	font = f
	queue_redraw()


func set_boss(b: Dictionary) -> void:
	boss = b
	_last_ratio = 1.0
	_blood.clear()
	var p := "res://art/boss_%s_a.png" % String(b.get("id", ""))
	_tex_boss = load(p) if ResourceLoader.exists(p) else null
	queue_redraw()


func set_hp_ratio(r: float) -> void:
	hp_ratio = clampf(r, 0.0, 1.0)
	_last_ratio = hp_ratio
	queue_redraw()


# 玩家中枪时调用：在画面边缘留下擦不掉的血
func add_blood() -> void:
	var edge := _rng.randi_range(0, 2)
	var p := Vector2.ZERO
	if edge == 0:
		p = Vector2(_rng.randf_range(90.0, 420.0), _rng.randf_range(860.0, 1040.0))
	elif edge == 1:
		p = Vector2(_rng.randf_range(1500.0, 1840.0), _rng.randf_range(760.0, 1030.0))
	else:
		p = Vector2(_rng.randf_range(600.0, 1320.0), _rng.randf_range(980.0, 1060.0))
	_blood.append([p, _rng.randf_range(26.0, 64.0)])
	if _blood.size() > 14:
		_blood.pop_front()
	queue_redraw()


func set_state(s: String, dur := 1.0) -> void:
	state = s
	_state_left = maxf(dur, 0.01)
	if s == "hit":
		_hit_flash = 1.0
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	if _state_left > 0.0:
		_state_left -= delta
		if _state_left <= 0.0 and state != "idle":
			state = "idle"
	_hit_flash = maxf(0.0, _hit_flash - delta * 2.4)
	# 不定时的神经质抽搐：让对面看着“不正常”
	_twitch_t -= delta
	if _twitch_t <= 0.0:
		if _rng.randf() < 0.45:
			_twitch = 1.0
		_twitch_t = _rng.randf_range(1.6, 4.2)
	_twitch = maxf(0.0, _twitch - delta * 3.0)
	queue_redraw()
	_sync_boss_mesh()


func _draw() -> void:
	_draw_background()
	_draw_guns()
	_draw_blood()
	_draw_pressure()


# ------------------------------------------------------------
#  背景（cover 铺满，左右各裁一点）
# ------------------------------------------------------------
func _bg_layout() -> Dictionary:
	if _tex_bg == null:
		return {}
	var ts := _tex_bg.get_size()
	var sc := maxf(W / ts.x, H / ts.y)
	var w := ts.x * sc
	var h := ts.y * sc
	return {"sc": sc, "w": w, "h": h, "ox": (W - w) * 0.5, "oy": (H - h) * 0.5, "ts": ts}


func _draw_background() -> void:
	var L := _bg_layout()
	if L.is_empty():
		draw_rect(Rect2(0, 0, W, H), Color(0.02, 0.02, 0.02))
		return
	draw_texture_rect(_tex_bg, Rect2(L.ox, L.oy, L.w, L.h), false)


# ------------------------------------------------------------
#  对手：网格变形立绘（不是一张死图，会呼吸、会晃、会抽搐）
# ------------------------------------------------------------
const GX := 18
const GY := 20

var _mi: MeshInstance2D
var _desk: Sprite2D


func _ensure_mesh() -> void:
	if _mi != null:
		return
	_mi = MeshInstance2D.new()
	_mi.material = CanvasItemMaterial.new()
	_mi.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_mi)
	# 桌沿遮挡条：只在立绘之后、桌面那一小条，把对手下半身压进桌子后面
	_desk = Sprite2D.new()
	_desk.texture = _tex_bg
	_desk.region_enabled = true
	_desk.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_desk)
	_layout_desk()


func _layout_desk() -> void:
	if _desk == null or _tex_bg == null:
		return
	var L := _bg_layout()
	if L.is_empty():
		return
	var sc: float = L.sc
	var ox: float = L.ox
	var oy: float = L.oy
	var band_h := 56.0
	var sx: float = -ox / sc
	var sy: float = (DESK_Y - oy) / sc
	_desk.region_rect = Rect2(sx, sy, W / sc, band_h / sc)
	_desk.scale = Vector2(sc, sc)
	_desk.position = Vector2(ox + (sx + (W / sc) * 0.5) * sc, oy + (sy + (band_h / sc) * 0.5) * sc)


func _sync_boss_mesh() -> void:
	if _tex_boss == null:
		if _mi != null:
			_mi.visible = false
		return
	_ensure_mesh()
	_mi.visible = true
	_mi.texture = _tex_boss

	var tex_size := _tex_boss.get_size()
	var tw := BOSS_H * (tex_size.x / tex_size.y)

	var dx := 0.0
	var dy := 0.0
	var scl := 1.0
	match state:
		"laugh":
			dy = -absf(sin(_time * 9.0)) * 10.0
			dx = sin(_time * 4.5) * 3.0
			scl = 1.04
		"hit":
			dx = _hit_flash * 16.0
			dy = -_hit_flash * 24.0
			scl = 1.03
		"low":
			dx = sin(_time * 22.0) * 3.5
		_:
			dy = sin(_time * 1.5) * 3.0

	var heat := clampf(1.0 - hp_ratio, 0.0, 1.0)
	var tint := Color(0.90, 0.84 - heat * 0.28, 0.76 - heat * 0.30, 1.0)
	tint = tint.darkened(heat * 0.22)
	_mi.modulate = tint

	var ww := tw * scl
	var hh := BOSS_H * scl
	var left := W * 0.5 - ww * 0.5 + dx
	var top := BOSS_BOTTOM - hh + dy
	_update_mesh(Rect2(left, top, ww, hh))


func _update_mesh(rect: Rect2) -> void:
	var w := rect.size.x
	var h := rect.size.y
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()

	var breathe := sin(_time * 1.35) * 0.012
	var sway := sin(_time * 0.75) * 3.0
	var tick := _time * 26.0

	for j in GY + 1:
		var v := float(j) / float(GY)
		for i in GX + 1:
			var u := float(i) / float(GX)
			var x := w * u
			var y := h * v
			# 呼吸：胸腔鼓起（中段横向扩张）
			var d := (v - 0.58) / 0.24
			var chest := exp(-d * d)
			x += (u - 0.5) * w * breathe * chest * 2.4
			# 头肩缓慢摇摆（只让肩膀动，别把脸拧变形）
			if v < 0.46:
				x += sway * (1.0 - v / 0.46) * 0.55
			# 神经质抽动（很轻，只动脖子以上）
			if _twitch > 0.01 and v < 0.40:
				x += sin(_time * 43.0) * 2.4 * _twitch * (1.0 - v / 0.40)
			match state:
				"laugh":
					y += sin(_time * 13.0 + u * 7.0) * 2.0 * (1.0 - v)
					x += sin(_time * 9.0 + v * 5.0) * 0.7
				"hit":
					x += _hit_flash * 14.0 * (1.0 - v)
					y -= _hit_flash * 8.0
				"low":
					x += sin(tick + v * 9.0) * 2.4
					y += cos(tick * 1.3 + u * 6.0) * 1.2
			verts.append(Vector2(x, y))
			uvs.append(Vector2(u, v))

	for j in GY:
		for i in GX:
			var a := j * (GX + 1) + i
			var b := a + 1
			var c := a + GX + 1
			var d2 := c + 1
			idx.append(a); idx.append(b); idx.append(c)
			idx.append(b); idx.append(d2); idx.append(c)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mi.mesh = mesh
	_mi.position = rect.position


# ------------------------------------------------------------
#  桌面上的两把左轮（暗部剪影，避免抢画面）
# ------------------------------------------------------------
func _draw_guns() -> void:
	_draw_gun(Vector2(572, 954), -0.20)
	_draw_gun(Vector2(1348, 954), 0.20)


# 俯视左轮：枪口朝桌子远端，握把朝玩家，和桌面透视一致
func _draw_gun(pos: Vector2, ang: float) -> void:
	draw_set_transform(pos, ang, Vector2(2.4, 2.4))
	var dark := Color(0.045, 0.042, 0.038)
	var metal := Color(0.155, 0.145, 0.135)
	var hi := Color(0.58, 0.53, 0.43, 0.50)
	var wood := Color(0.20, 0.125, 0.065)
	# 枪管
	draw_rect(Rect2(-8, -72, 16, 44), dark)
	draw_rect(Rect2(-8, -72, 3.5, 44), hi)
	# 机匣
	draw_rect(Rect2(-17, -32, 34, 38), dark)
	draw_rect(Rect2(-17, -32, 34, 2), metal)
	# 转轮
	draw_circle(Vector2(0, -12), 18, dark)
	draw_arc(Vector2(0, -12), 18, 0, TAU, 26, hi, 1.6)
	draw_arc(Vector2(0, -12), 10, 0, TAU, 20, metal, 1.2)
	# 握把
	var grip := PackedVector2Array([
		Vector2(-13, 6), Vector2(13, 6), Vector2(8, 50), Vector2(-7, 50),
	])
	draw_colored_polygon(grip, wood)
	draw_polyline(PackedVector2Array([
		Vector2(-13, 6), Vector2(13, 6), Vector2(8, 50), Vector2(-7, 50), Vector2(-13, 6),
	]), hi, 1.3)
	# 扳机护圈
	draw_arc(Vector2(0, 10), 11, 0.15, PI - 0.15, 16, dark, 2.6)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ------------------------------------------------------------
#  血
# ------------------------------------------------------------
func _draw_blood() -> void:
	for b in _blood:
		var p: Vector2 = b[0]
		var rr: float = b[1]
		draw_circle(p, rr, Color(0.26, 0.015, 0.012, 0.50))
		draw_circle(p + Vector2(rr * 0.55, rr * 0.22), rr * 0.42, Color(0.20, 0.01, 0.008, 0.42))
		draw_circle(p + Vector2(-rr * 0.5, rr * 0.35), rr * 0.30, Color(0.20, 0.01, 0.008, 0.38))


# ------------------------------------------------------------
#  濒死压迫：画面往血里沉
# ------------------------------------------------------------
func _draw_pressure() -> void:
	var heat := clampf(1.0 - hp_ratio, 0.0, 1.0)
	if heat < 0.45:
		return
	var pulse := 0.05 + 0.05 * sin(_time * 5.2)
	draw_rect(Rect2(0, 0, W, H), Color(0.30, 0.0, 0.0, heat * pulse * 2.2))
