extends RefCounted
## 暗骰赌桌的原创三维场景、角色与材质。

const WALNUT := Color("#35202d")
const METAL := Color("#ad774c")
const COAT := Color("#292938")
const HAIR := Color("#262335")
const SKIN := Color("#d59781")
const SHIRT := Color("#bfa795")
const CRIMSON := Color("#7e263c")


static func mesh(parent: Node3D, shape: Mesh, position: Vector3, color: Color,
	metalness := 0.0, glow := 0.0) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metalness
	material.roughness = 0.6 if metalness < 0.5 else 0.38
	if glow > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = glow
	var node := MeshInstance3D.new()
	node.mesh = shape
	node.material_override = material
	parent.add_child(node)
	node.position = position
	return node


static func box(parent: Node3D, position: Vector3, size: Vector3, color: Color,
	metalness := 0.0, glow := 0.0) -> MeshInstance3D:
	var shape := BoxMesh.new()
	shape.size = size
	return mesh(parent, shape, position, color, metalness, glow)


static func oval(parent: Node3D, position: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var shape := SphereMesh.new()
	shape.radial_segments = 24
	shape.rings = 12
	var part := mesh(parent, shape, position, color)
	part.scale = size
	return part


static func band(parent: Node3D, position: Vector3, top: float, bottom: float,
	height: float, color: Color, metalness := 0.0, glow := 0.0) -> MeshInstance3D:
	var shape := CylinderMesh.new()
	shape.top_radius = top
	shape.bottom_radius = bottom
	shape.height = height
	shape.radial_segments = 24
	return mesh(parent, shape, position, color, metalness, glow)


static func rod(parent: Node3D, a: Vector3, b: Vector3, radius_a: float, radius_b: float,
	color: Color) -> MeshInstance3D:
	var direction := b - a
	var node := band(parent, (a + b) * 0.5, radius_b, radius_a, direction.length(), color)
	node.quaternion = Quaternion(Vector3.UP, direction.normalized())
	return node


static func rounded_die() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 12
	var edge := 0.40
	var bevel := 0.065
	for normal: Vector3 in [Vector3.UP, Vector3.DOWN, Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]:
		var u := normal.cross(Vector3.FORWARD if absf(normal.y) > 0.5 else Vector3.UP)
		var v := normal.cross(u)
		for row in segments:
			for column in segments:
				var coords := [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1),
					Vector2i(0, 0), Vector2i(1, 1), Vector2i(1, 0)]
				for point: Vector2i in coords:
					var x := lerpf(-edge, edge, float(column + point.x) / segments)
					var y := lerpf(-edge, edge, float(row + point.y) / segments)
					var raw := normal * edge + u * x + v * y
					var inner := raw.clamp(Vector3.ONE * (-edge + bevel), Vector3.ONE * (edge - bevel))
					var direction := (raw - inner).normalized()
					surface.set_normal(direction)
					surface.add_vertex(inner + direction * bevel)
	return surface.commit()


static func wall_light(parent: Node3D, x: float) -> void:
	var loc := Vector3(x, 2.38, -4.54)
	box(parent, loc, Vector3(0.34, 0.99, 0.21), WALNUT)
	band(parent, loc + Vector3(0, -0.28, 0.20), 0.19, 0.12, 0.16, METAL, 0.7)
	band(parent, loc + Vector3(0, -0.04, 0.21), 0.065, 0.077, 0.38, Color("#ffb85c"), 0.0, 1.2)
	for side in [-1, 1]:
		box(parent, loc + Vector3(side * 0.14, 0.02, 0.18), Vector3(0.027, 0.59, 0.032), METAL, 0.75)
	band(parent, loc + Vector3(0, 0.27, 0.20), 0.06, 0.19, 0.14, METAL, 0.7)
	var lamp := OmniLight3D.new()
	parent.add_child(lamp)
	lamp.position = loc + Vector3(0, 0.03, 0.44)
	lamp.light_color = Color("#ff9261")
	lamp.light_energy = 2.1
	lamp.omni_range = 2.5


static func build_room(parent: Node3D) -> void:
	box(parent, Vector3(0, 2.1, -4.94), Vector3(13.2, 6.1, 0.36), Color("#200f21"))
	var random := RandomNumberGenerator.new()
	random.seed = 8519
	for row in 12:
		for column in 16:
			var x := (column - 7.5) * 0.78 + float(row % 2) * 0.39
			var tint := Color("#392537").lerp(Color("#211827"), random.randf())
			box(parent, Vector3(x, 0.57 + row * 0.296, -4.74), Vector3(0.746, 0.264, 0.07), tint)
	box(parent, Vector3(0, 0.23, -4.59), Vector3(12.6, 0.28, 0.23), WALNUT)
	box(parent, Vector3(0, 3.68, -4.58), Vector3(12.6, 0.24, 0.25), WALNUT)
	for side in [-1, 1]:
		var x: float = 3.78 * side
		box(parent, Vector3(x, 2.08, -4.51), Vector3(0.31, 4.38, 0.36), Color("#513541"))
		box(parent, Vector3(x, 3.47, -4.37), Vector3(0.52, 0.20, 0.39), METAL, 0.4)
		band(parent, Vector3(x, 1.45, -4.27), 0.12, 0.12, 2.45, WALNUT)
		wall_light(parent, 2.68 * side)
	# 后墙的三维拱券和铁栅。几何体参与景深、投影和相机视差。
	box(parent, Vector3(0, 1.82, -4.63), Vector3(2.86, 2.45, 0.10), Color("#161a2b"))
	for i in 17:
		var angle := PI * float(i) / 16.0
		var at := Vector3(cos(angle) * 1.49, 2.72 + sin(angle) * 1.01, -4.50)
		var masonry := box(parent, at, Vector3(0.31, 0.19, 0.24), Color("#606078"))
		masonry.rotation.z = angle - PI * 0.5
	for index in 7:
		var x := (index - 3) * 0.37
		var ceiling := 2.70 + sqrt(maxf(0, 1.0 - pow(x / 1.49, 2))) * 0.78
		box(parent, Vector3(x, (0.57 + ceiling) * 0.5, -4.49),
			Vector3(0.047, ceiling - 0.57, 0.065), Color("#414654"), 0.65)
	for y in [1.46, 2.68]:
		box(parent, Vector3(0, y, -4.46), Vector3(2.77, 0.053, 0.065), Color("#414654"), 0.65)

	for side in [-1, 1]:
		box(parent, Vector3(side * 6.58, 2.11, -0.98), Vector3(0.28, 6.1, 7.95), Color("#251829"))
		box(parent, Vector3(side * 6.38, 1.19, -1.03), Vector3(0.16, 0.24, 8.0), WALNUT)
		for panel in 4:
			box(parent, Vector3(side * 6.38, 2.25, -3.7 + panel * 1.55), Vector3(0.11, 2.47, 0.064), METAL, 0.45)

	# 木质桌沿、毛毡、黄铜饰条与包角。
	box(parent, Vector3(0, -0.22, 0.15), Vector3(10.95, 0.34, 6.23), Color("#2a1923"))
	box(parent, Vector3(0, -0.021, 0.15), Vector3(10.68, 0.091, 6.0), WALNUT)
	box(parent, Vector3(0, 0.021, 0.15), Vector3(8.48, 0.028, 4.67), Color("#193637"))
	for side in [-1, 1]:
		box(parent, Vector3(side * 4.24, 0.038, 0.15), Vector3(0.044, 0.014, 4.70), METAL, 0.65)
		box(parent, Vector3(0, 0.038, 0.15 + side * 2.34), Vector3(8.51, 0.014, 0.044), METAL, 0.65)
		box(parent, Vector3(side * 5.30, -0.035, 0.15), Vector3(0.17, 0.123, 5.94), Color("#593a38"))
		box(parent, Vector3(0, -0.035, 0.15 + side * 2.99), Vector3(10.77, 0.123, 0.17), Color("#593a38"))
		for end in [-1, 1]:
			band(parent, Vector3(side * 5.22, 0.049, 0.15 + end * 2.86), 0.136, 0.136, 0.05, METAL, 0.8)
	# 人物旁的实物道具用于建立尺寸和光影层次。
	for side in [-1, 1]:
		var x: float = 3.76 * side
		band(parent, Vector3(x, 0.104, -1.84), 0.22, 0.27, 0.14, WALNUT)
		band(parent, Vector3(x, 0.31, -1.84), 0.047, 0.069, 0.42, Color("#d89d6a"))
		var flame := oval(parent, Vector3(x, 0.584, -1.84), Vector3(0.073, 0.15, 0.073), Color("#ffc978"))
		var material := flame.material_override as StandardMaterial3D
		material.emission_enabled = true
		material.emission = Color("#ffae55")
		material.emission_energy_multiplier = 1.7


static func build_dealer(parent: Node3D) -> Dictionary:
	var body := Node3D.new()
	parent.add_child(body)
	body.position = Vector3(0, 0, -2.74)
	# 椅背、躯干、衬衣、两侧翻领。
	oval(body, Vector3(0, 1.43, -0.37), Vector3(1.69, 2.30, 0.48), WALNUT)
	oval(body, Vector3(0, 1.51, -0.22), Vector3(1.42, 1.92, 0.29), CRIMSON.darkened(0.55))
	for side in [-1, 1]:
		band(body, Vector3(side * 0.83, 1.51, -0.35), 0.051, 0.068, 1.80, METAL, 0.52)
	oval(body, Vector3(0, 0.94, 0.04), Vector3(1.62, 1.73, 0.73), COAT)
	oval(body, Vector3(0, 1.25, 0.32), Vector3(0.65, 1.09, 0.27), SHIRT)
	rod(body, Vector3(0, 1.26, 0.41), Vector3(0, 1.61, 0.34), 0.14, 0.14, SKIN)
	for side in [-1, 1]:
		var x: float = side
		var lapel := box(body, Vector3(x * 0.29, 1.22, 0.44), Vector3(0.20, 0.65, 0.065), Color("#585464"))
		lapel.rotation.z = x * -0.41
		var collar := box(body, Vector3(x * 0.118, 1.49, 0.439), Vector3(0.131, 0.22, 0.060), SHIRT.lightened(0.16))
		collar.rotation.z = x * -0.40
		oval(body, Vector3(x * 0.125, 1.33, 0.489), Vector3(0.26, 0.14, 0.067), CRIMSON)
		oval(body, Vector3(x * 0.61, 1.25, 0.11), Vector3(0.57, 0.62, 0.62), COAT)
	oval(body, Vector3(0, 1.33, 0.515), Vector3(0.11, 0.13, 0.071), CRIMSON.darkened(0.45))
	for i in 3:
		oval(body, Vector3(0, 0.79 + i * 0.115, 0.434), Vector3.ONE * 0.062, METAL)

	var head := Node3D.new()
	body.add_child(head)
	head.position = Vector3(0, 1.96, 0.12)
	_build_face(head)
	var arm := Node3D.new()
	body.add_child(arm)
	arm.position = Vector3(0.65, 1.10, 0.18)
	_build_arm(arm, 1.0, true)
	arm.rotation.x = 0.28
	var other := Node3D.new()
	body.add_child(other)
	other.position = Vector3(-0.65, 1.10, 0.18)
	_build_arm(other, -1.0, false)
	other.rotation.x = 0.32
	return {"body": body, "head": head, "arm": arm, "offhand": other}


static func _build_arm(arm: Node3D, side: float, reaching: bool) -> void:
	var elbow := Vector3(side * 0.18, -0.45, 0.43)
	var wrist := Vector3(side * -0.02, -0.57, 0.88 if reaching else 0.69)
	rod(arm, Vector3.ZERO, elbow, 0.19, 0.15, COAT)
	oval(arm, elbow, Vector3(0.29, 0.28, 0.28), COAT)
	rod(arm, elbow, wrist, 0.15, 0.101, COAT)
	rod(arm, wrist - Vector3(0, 0, 0.07), wrist + Vector3(0, 0, 0.01), 0.115, 0.106, SHIRT)
	oval(arm, wrist + Vector3(0, -0.015, 0.09), Vector3(0.181, 0.108, 0.213), SKIN)
	for finger in 4:
		var x := (finger - 1.5) * 0.035
		var length := 0.098 - 0.013 * absf(finger - 1.3)
		rod(arm, wrist + Vector3(x, -0.019, 0.148),
			wrist + Vector3(x, -0.044, 0.148 + length), 0.018, 0.012, SKIN)
	rod(arm, wrist + Vector3(side * -0.063, 0.004, 0.074),
		wrist + Vector3(side * -0.109, -0.038, 0.143), 0.026, 0.017, SKIN)


static func _build_face(head: Node3D) -> void:
	# 面部比一般写实比例略宽，重点保留脸颊、眼眶和发束轮廓。
	oval(head, Vector3(0, 0.057, -0.018), Vector3(0.72, 0.79, 0.70), HAIR)
	oval(head, Vector3(0, 0.015, 0.086), Vector3(0.594, 0.68, 0.542), SKIN)
	oval(head, Vector3(0, -0.154, 0.117), Vector3(0.452, 0.421, 0.478), SKIN)
	oval(head, Vector3(0, -0.240, 0.149), Vector3(0.270, 0.224, 0.314), SKIN)
	oval(head, Vector3(0, -0.062, 0.349), Vector3(0.114, 0.172, 0.152), SKIN.lightened(0.045))
	oval(head, Vector3(0, -0.117, 0.373), Vector3(0.111, 0.081, 0.123), SKIN)
	oval(head, Vector3(0, -0.185, 0.343), Vector3(0.207, 0.048, 0.052), Color("#a83f50"))
	oval(head, Vector3(0, -0.193, 0.357), Vector3(0.168, 0.012, 0.024), Color("#4e2334"))
	for side in [-1, 1]:
		var x: float = side
		oval(head, Vector3(x * 0.275, -0.014, 0.10), Vector3(0.122, 0.184, 0.107), SKIN.darkened(0.17))
		oval(head, Vector3(x * 0.270, -0.109, 0.143), Vector3.ONE * 0.047, METAL)
		oval(head, Vector3(x * 0.146, 0.018, 0.304), Vector3(0.227, 0.110, 0.073), Color("#452837"))
		oval(head, Vector3(x * 0.142, 0.016, 0.331), Vector3(0.182, 0.077, 0.040), Color("#ebccbc"))
		oval(head, Vector3(x * 0.130, 0.016, 0.352), Vector3(0.065, 0.074, 0.027), Color("#9b4d59"))
		oval(head, Vector3(x * 0.130, 0.015, 0.366), Vector3(0.038, 0.055, 0.020), Color("#211a2c"))
		oval(head, Vector3(x * 0.130 - 0.011, 0.028, 0.378), Vector3.ONE * 0.022, Color("#fff0cc"))
		rod(head, Vector3(x * 0.063, 0.079, 0.334), Vector3(x * 0.23, 0.112, 0.286), 0.015, 0.024, HAIR)
		# 侧部发束由多层弯折形体组成，侧面依然保有厚度。
		for i in 4:
			var hair := oval(head, Vector3(x * (0.268 + i * 0.018), -0.103 - i * 0.038, 0.093 - i * 0.038),
				Vector3(0.235, 0.703 - i * 0.047, 0.276), HAIR.lerp(Color("#683b59"), i * 0.10))
			hair.rotation.z = -x * (0.18 + i * 0.11)

	# 斜刘海分成多片三维发束，让眼睛下沿留在主光下。
	for i in 6:
		var stripe := oval(head, Vector3(-0.202 + i * 0.074, 0.252 - i * 0.011, 0.224),
			Vector3(0.156, 0.309 + i * 0.017, 0.209), HAIR.lerp(Color("#5d3e63"), i * 0.073))
		stripe.rotation.z = -0.53 - i * 0.11
