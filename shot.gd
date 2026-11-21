extends SceneTree

var node: Node
var frame := 0


func _initialize() -> void:
	var scene: PackedScene = load("res://main.tscn")
	node = scene.instantiate()
	get_root().add_child(node)


func _process(_delta: float) -> bool:
	frame += 1
	match frame:
		5:
			node.debug_start_gameplay(0)
		40:
			node.pause_menu.toggle()
		62:
			var img: Image = get_root().get_texture().get_image()
			img.save_png("D:/Temp/v7_pause.png")
			print("saved pause")
		70:
			quit()
	return false
