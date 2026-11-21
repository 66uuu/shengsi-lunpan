extends RefCounted
# ============================================================
#  systems/items.gd
#  道具数据表（纯数据访问，不依赖 UI）
#  数据来源：res://data/items.json，6 件正面道具 + 2 件负面道具，各 3 级
# ============================================================

const PATH := "res://data/items.json"

static var _db: Dictionary = {}


static func _ensure() -> void:
	if not _db.is_empty():
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_error("无法读取 res://data/items.json")
		_db = {"max_level": 3, "order": [], "items": {}}
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("items.json 格式错误")
		_db = {"max_level": 3, "order": [], "items": {}}
		return
	_db = parsed


static func order() -> Array:
	_ensure()
	return _db.get("order", [])


static func max_level() -> int:
	_ensure()
	return int(_db.get("max_level", 3))


static func has_item(item_id: String) -> bool:
	_ensure()
	return _db.get("items", {}).has(item_id)


static func data(item_id: String) -> Dictionary:
	_ensure()
	var items: Dictionary = _db.get("items", {})
	return items.get(item_id, {})


static func item_name(item_id: String) -> String:
	return String(data(item_id).get("name", item_id))


static func short_text(item_id: String) -> String:
	return String(data(item_id).get("short", ""))


static func is_negative(item_id: String) -> bool:
	return bool(data(item_id).get("negative", false))


static func level(item_id: String, lv: int) -> Dictionary:
	var d := data(item_id)
	var levels: Array = d.get("levels", [])
	if levels.is_empty():
		return {}
	var idx: int = clampi(lv - 1, 0, levels.size() - 1)
	return levels[idx]


static func line(item_id: String, lv: int) -> String:
	return String(level(item_id, lv).get("line", ""))


static func label(item_id: String, lv: int) -> String:
	return "%s Lv%d" % [item_name(item_id), clampi(lv, 1, max_level())]


static func positive_ids() -> Array:
	var out: Array = []
	for id in order():
		if not is_negative(String(id)):
			out.append(String(id))
	return out


static func negative_ids() -> Array:
	var out: Array = []
	for id in order():
		if is_negative(String(id)):
			out.append(String(id))
	return out
