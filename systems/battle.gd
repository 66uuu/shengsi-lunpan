extends RefCounted
# ============================================================
#  systems/battle.gd
#  纯战斗逻辑：不引用任何 UI 节点，只返回“事件/日志/展示数据”
#  所有随机都走统一的 rng，轮盘权重由 Boss 数据（bosses.json）决定
# ============================================================

const Items = preload("res://systems/items.gd")

const SEGMENTS := 36
const MAX_ITEMS := 3
const TYPE_ORDER := ["empty", "bullet", "shoot", "item", "heal", "curse",
	"double", "selfhurt", "tire", "powder"]


class Fighter:
	var id := ""
	var display_name := ""
	var is_player := true
	var hp := 100
	var max_hp := 100
	var bullets := 0
	var items: Array = []            # [{ "id": String, "lv": int }]
	var armor := 0
	var armor_reflect := 0
	var immune := 0
	var dmg_mult := 1
	var poison := 0
	var poison_dmg := 8
	var skip := 0
	var bleed := 0
	var bleed_dmg := 5
	var cannot_spin := false
	var tilt := 0
	var rage_bonus := 0
	var skipped_turn := false
	var empty_streak := 0
	var momentum := false
	var damage_dealt := 0
	var max_hit := 0
	var item_used := false

	func item_lv(item_id: String) -> int:
		for it in items:
			if String(it.get("id", "")) == item_id:
				return int(it.get("lv", 1))
		return 0

	func has_item(item_id: String) -> bool:
		return item_lv(item_id) > 0

	func item_count() -> int:
		return items.size()


var rng := RandomNumberGenerator.new()
var player: Fighter
var boss: Fighter
var boss_data: Dictionary = {}
var level_id := ""
var wheel_layout: Array = []
var round_num := 1
var boss_turns := 0
var pending_item := ""
var wager_available := false
var wager_tell := ""
var _wager_is_bluff := false
var log_lines: Array = []


# ------------------------------------------------------------
#  初始化
# ------------------------------------------------------------
func setup(p_boss: Dictionary, p_seed: int = 0, p_player_hp: int = 140) -> void:
	rng = RandomNumberGenerator.new()
	if p_seed != 0:
		rng.seed = p_seed
	else:
		rng.randomize()

	boss_data = p_boss
	level_id = String(p_boss.get("id", "boss"))
	round_num = 1
	boss_turns = 0
	pending_item = ""
	log_lines.clear()

	player = Fighter.new()
	player.id = "player"
	player.display_name = "李炎"
	player.is_player = true
	player.max_hp = p_player_hp
	player.hp = p_player_hp

	boss = Fighter.new()
	boss.id = level_id
	boss.display_name = String(p_boss.get("name", "对手"))
	boss.is_player = false
	boss.max_hp = int(p_boss.get("hp", 120))
	boss.hp = boss.max_hp

	_build_wheel(p_boss.get("wheel", {}))
	_prepare_wager(rng.seed, int(p_boss.get("level", 1)))

	var sp: Dictionary = p_boss.get("special", {})
	if String(sp.get("type", "none")) == "master":
		boss.items.append({
			"id": String(sp.get("start_item", "rocket")),
			"lv": int(sp.get("start_lv", 2)),
		})


func _prepare_wager(seed_value: int, level: int) -> void:
	# 独立随机流，保留原有转盘概率。
	var wager_rng := RandomNumberGenerator.new()
	wager_rng.seed = seed_value ^ 0x7A18451
	wager_available = true
	_wager_is_bluff = wager_rng.randf() < clampf(0.35 + level * 0.075, 0.0, 0.75)
	var suspicious := _wager_is_bluff
	if wager_rng.randf() < 0.30:
		suspicious = not suspicious
	wager_tell = "他移开了视线" if suspicious else "他按住了木牌"


func challenge_wager() -> Dictionary:
	if not wager_available or player.hp <= 0 or boss.hp <= 0:
		return {}
	wager_available = false
	var loser := boss if _wager_is_bluff else player
	var amount := mini(loser.hp, 18)
	loser.hp -= amount
	if _wager_is_bluff:
		player.damage_dealt += amount
		player.max_hit = maxi(player.max_hit, amount)
	var title := "揭穿暗押" if _wager_is_bluff else "对方说了真话"
	var detail := "%s损失 %d 点生命" % [loser.display_name, amount]
	note("暗押 · %s · %s" % [title, detail])
	return {"title": title, "summary": detail, "damage": amount if _wager_is_bluff else 0,
		"actor_hurt": not _wager_is_bluff}


func _build_wheel(weights: Dictionary) -> void:
	var layout: Array = []
	for t in TYPE_ORDER:
		for i in int(weights.get(t, 0)):
			layout.append(t)
	while layout.size() < SEGMENTS:
		layout.append("empty")
	while layout.size() > SEGMENTS:
		layout.pop_back()
	for i in range(layout.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = layout[i]
		layout[i] = layout[j]
		layout[j] = tmp
	wheel_layout = layout


# ------------------------------------------------------------
#  随机：统一 RNG + 按 Boss 权重
# ------------------------------------------------------------
func roll_spin_index(_actor: Fighter) -> int:
	var counts := {}
	for t in wheel_layout:
		counts[t] = int(counts.get(t, 0)) + 1
	var total := wheel_layout.size()
	var pick := rng.randi_range(0, total - 1)
	var acc := 0
	var chosen := "empty"
	for t in TYPE_ORDER:
		acc += int(counts.get(t, 0))
		if pick < acc:
			chosen = t
			break
	var candidates: Array = []
	for i in wheel_layout.size():
		if wheel_layout[i] == chosen:
			candidates.append(i)
	if candidates.is_empty():
		return 0
	return int(candidates[rng.randi_range(0, candidates.size() - 1)])


# ------------------------------------------------------------
#  回合开始维护
# ------------------------------------------------------------
func begin_turn(f: Fighter) -> Array:
	var logs: Array = []
	f.cannot_spin = false
	f.skipped_turn = false
	f.item_used = false

	# 被嘴炮激怒到破防：本回合手抖，转不动
	if f.tilt > 0:
		f.tilt -= 1
		f.cannot_spin = true
		logs.append("%s 还没缓过来，手抖得根本握不住转盘" % f.display_name)

	if f.immune > 0:
		f.immune -= 1

	if f.bleed > 0:
		f.bleed -= 1
		_loss(f, f.bleed_dmg, "流血", logs)

	if f.poison > 0:
		f.poison -= 1
		_loss(f, f.poison_dmg, "丧尸病毒", logs)

	var tire_lv := f.item_lv("tire")
	if tire_lv > 0:
		f.cannot_spin = true
		f.skipped_turn = false
		logs.append("「漏气的轮胎」：%s 本回合无法转动转盘" % f.display_name)
		_delevel(f, "tire")

	if f.skip > 0:
		f.skip -= 1
		f.cannot_spin = true
		f.skipped_turn = true
		logs.append("%s 被缩小灯缩小，直接跳过本回合" % f.display_name)

	return logs


func _loss(f: Fighter, amount: int, reason: String, logs: Array) -> void:
	f.hp = maxi(0, f.hp - amount)
	logs.append("%s 受到「%s」伤害 -%d HP（剩 %d）" % [f.display_name, reason, amount, f.hp])


# ------------------------------------------------------------
#  Boss 回合开始：偷道具 / 自我治疗
# ------------------------------------------------------------
func boss_turn_start() -> Array:
	var logs: Array = []
	boss_turns += 1
	var sp: Dictionary = boss_data.get("special", {})
	match String(sp.get("type", "none")):
		"steal":
			var every := int(sp.get("every", 2))
			if boss_turns % every == 0 and not player.items.is_empty():
				var idx := rng.randi_range(0, player.items.size() - 1)
				var taken: Dictionary = player.items[idx]
				player.items.remove_at(idx)
				var nm := Items.item_name(String(taken.get("id", "")))
				if boss.items.size() < MAX_ITEMS:
					boss.items.append(taken)
					logs.append("红发荷官从你的口袋摸走了「%s」，收进了她自己的道具槽" % nm)
				else:
					logs.append("红发荷官摸走了「%s」，她的槽位满了，随手丢掉了" % nm)
		"heal_self":
			var every2 := int(sp.get("every", 3))
			if boss_turns % every2 == 0:
				var amount := int(sp.get("amount", 20))
				var before := boss.hp
				boss.hp = mini(boss.max_hp, boss.hp + amount)
				logs.append("疯批医生给自己打了一针，回复 %d HP（%d/%d）" % [boss.hp - before, boss.hp, boss.max_hp])
	return logs


# ------------------------------------------------------------
#  转盘结算
# ------------------------------------------------------------
# 未知格落地：真面目
func _roll_unknown() -> String:
	var r := rng.randf()
	if r < 0.34:
		return "bullet"
	elif r < 0.64:
		return "item"
	elif r < 0.78:
		return "heal"
	elif r < 0.90:
		return "double"
	return "curse"


func resolve_spin(actor: Fighter, t: String) -> Dictionary:
	var foe: Fighter = boss if actor.is_player else player
	var res := {
		"type": t,
		"title": "",
		"summary": "",
		"logs": [],
		"damage": 0,
		"shot": false,
		"empty_gun": false,
		"empty": false,
		"dialogue": "",
		"target_hurt": false,
		"actor_hurt": false,
		"item": "",
		"full": false,
	}

	# 未知格：转盘上只有「?」，落地才知道是什么
	if t == "unknown":
		t = _roll_unknown()
		res.type = t
		res.unknown = true

	if t != "empty":
		actor.empty_streak = 0

	match t:
		"empty":
			res.empty = true
			actor.empty_streak += 1
			if actor.empty_streak >= 3 and not actor.momentum:
				actor.momentum = true
				_push_log(res, "气势爆发！%s 连续 %d 次空转，下一次伤害 +10%%" % [actor.display_name, actor.empty_streak])
			_push_log(res, "%s 转到「空」，什么也没发生" % actor.display_name)
			res.title = "空"
			res.summary = "什么也没发生。"
			if actor.empty_streak >= 2:
				res.summary += "  连续空转 ×%d" % actor.empty_streak
			if not actor.is_player:
				res.dialogue = "empty"
				var sp: Dictionary = boss_data.get("special", {})
				if String(sp.get("type", "none")) == "master":
					var heal := int(sp.get("empty_heal", 5))
					var before := boss.hp
					boss.hp = mini(boss.max_hp, boss.hp + heal)
					if boss.hp > before:
						_push_log(res, "轮盘之主嗤笑一声，借着空转回复了 %d HP" % (boss.hp - before))
						res.summary += "  对手回复 %d HP" % (boss.hp - before)
		"bullet":
			if actor.bullets < 8:
				actor.bullets = mini(actor.bullets + 3, 8)
				_push_log(res, "%s 转到「子弹 +3」，弹巢 %d/8" % [actor.display_name, actor.bullets])
				res.title = "子弹 +3"
				res.summary = "弹巢现在 %d/8 发" % actor.bullets
			else:
				_push_log(res, "%s 转到「子弹 +3」，但弹巢已满（8/8）" % actor.display_name)
				res.title = "子弹 +3"
				res.summary = "弹巢已满，没有变化"
		"shoot":
			res.shot = true
			if actor.bullets > 0:
				var n := actor.bullets
				actor.bullets = 0
				# 醉汉手抖：半数子弹打偏
				if not actor.is_player:
					var sp0: Dictionary = boss_data.get("special", {})
					if String(sp0.get("type", "")) == "drunk":
						n = maxi(1, int(ceil(float(n) * 0.5)))
						_push_log(res, "老张手抖得厉害，一半的子弹打在了墙上")
				var base := 30 * n
				# 处决：对方濒死且弹巢里至少 3 发，伤害 ×1.5
				if foe.hp > 0 and foe.hp <= int(foe.max_hp * 0.25) and n >= 3:
					base = int(round(float(base) * 1.5))
					res.execution = true
					_push_log(res, "处决时刻：%s 已经没有退路了" % foe.display_name)
				var dr := deal_damage(actor, foe, base, "立即开枪")
				for l in dr.get("logs", []):
					res.logs.append(String(l))
				res.damage = int(dr.get("damage", 0))
				if res.damage > 0:
					res.target_hurt = true
					if not actor.is_player:
						res.dialogue = "hit"
					res.title = "处决" if bool(res.get("execution", false)) else "立即开枪"
					res.summary = "%d 发子弹 → 造成 %d 点伤害" % [n, res.damage]
				else:
					res.title = "立即开枪"
					res.summary = "%d 发子弹被挡下了" % n
			else:
				actor_hurt(res, actor, 5, "空枪")
				res.empty_gun = true
				res.title = "空枪"
				res.summary = "弹巢是空的，走火自扣 5 HP"
		"item":
			var pool: Array = Items.positive_ids()
			var item_id := String(pool[rng.randi_range(0, pool.size() - 1)])
			_apply_grant(res, actor, item_id)
		"heal":
			var before := actor.hp
			actor.hp = mini(actor.max_hp, actor.hp + 15)
			var gained := actor.hp - before
			_push_log(res, "%s 转到「治疗」，回复 %d HP（%d/%d）" % [actor.display_name, gained, actor.hp, actor.max_hp])
			res.title = "治疗"
			res.summary = "回复 %d HP（现在 %d/%d）" % [gained, actor.hp, actor.max_hp]
		"curse":
			actor_hurt(res, actor, 10, "诅咒")
			res.title = "诅咒"
			res.summary = "被诅咒，损失 10 HP"
		"double":
			actor.dmg_mult = 2
			_push_log(res, "%s 转到「双倍」，下一次伤害 ×2" % actor.display_name)
			res.title = "双倍"
			res.summary = "下一次造成伤害时翻倍"
		"selfhurt":
			actor_hurt(res, actor, 20, "走火自伤")
			res.title = "自伤"
			res.summary = "枪走了火，损失 20 HP"
		"tire":
			_apply_grant(res, actor, "tire")
		"powder":
			_apply_grant(res, actor, "powder")
		_:
			res.title = "未知"
			res.summary = "转盘卡住了"

	_sync_logs(res.get("logs", []))
	return res


func _apply_grant(res: Dictionary, actor: Fighter, item_id: String) -> void:
	var g := grant_item(actor, item_id)
	for l in g.get("logs", []):
		res.logs.append(String(l))
	var nm := Items.item_name(item_id)
	res.item = item_id
	match String(g.get("status", "")):
		"full":
			res.full = true
			res.title = "道具槽已满"
			res.summary = "又转到一件「%s」，但你没有空槽位" % nm
			if actor.is_player:
				pending_item = item_id
			else:
				var slot := _boss_auto_slot()
				apply_replace(boss, item_id, slot)
		"upgraded":
			res.title = "道具升级"
			res.summary = "「%s」升到 Lv%d：%s" % [nm, int(g.get("lv", 1)), Items.line(item_id, int(g.get("lv", 1)))]
		"maxed":
			res.title = "道具满级"
			res.summary = "「%s」已经是 Lv3，没有变化" % nm
		_:
			res.title = "获得道具"
			res.summary = "获得「%s」：%s" % [nm, Items.line(item_id, 1)]


func _boss_auto_slot() -> int:
	return best_slot_for(boss)


func best_slot_for(f: Fighter) -> int:
	# 优先替换负面道具，其次是等级最低的
	var best := 0
	var best_score := 99
	for i in f.items.size():
		var it: Dictionary = f.items[i]
		var score := int(it.get("lv", 1))
		if Items.is_negative(String(it.get("id", ""))):
			score -= 10
		if score < best_score:
			best_score = score
			best = i
	return best


# ------------------------------------------------------------
#  伤害
# ------------------------------------------------------------
func deal_damage(attacker: Fighter, target: Fighter, amount: int, source: String,
		ignore_defense: bool = false) -> Dictionary:
	var out := {"damage": 0, "blocked": false, "reflected": 0, "logs": []}
	var an := attacker.display_name
	var tn := target.display_name

	if not ignore_defense:
		if target.immune > 0:
			out.blocked = true
			_ll(out, "%s 处于免伤状态，%s 的 %d 点伤害被完全吸收" % [tn, source, amount])
			return out
		if target.armor > 0:
			target.armor -= 1
			out.blocked = true
			_ll(out, "%s 的防弹衣挡下了「%s」（剩余 %d 次）" % [tn, source, target.armor])
			if target.armor_reflect > 0:
				var rf := target.armor_reflect
				target.armor_reflect = 0
				attacker.hp = maxi(0, attacker.hp - rf)
				out["reflected"] = rf
				_ll(out, "防弹衣反弹 %d 点伤害给 %s（剩 %d）" % [rf, an, attacker.hp])
			return out

	var dmg := amount
	var powder_lv := attacker.item_lv("powder")
	if powder_lv > 0:
		var factor := float(Items.level("powder", powder_lv).get("factor", 0.5))
		dmg = int(round(float(dmg) * factor))
		_delevel(attacker, "powder")
		_ll(out, "劣质火药：%s 的这次伤害只剩 %d 点" % [an, dmg])

	if attacker.dmg_mult > 1:
		var mult := attacker.dmg_mult
		dmg *= mult
		attacker.dmg_mult = 1
		_ll(out, "双倍生效：%s 的伤害 ×%d → %d" % [an, mult, dmg])

	if attacker.momentum:
		attacker.momentum = false
		attacker.empty_streak = 0
		dmg = int(round(float(dmg) * 1.1))
		_ll(out, "气势加成：%s 的伤害 +10%% → %d" % [an, dmg])

	if attacker.rage_bonus > 0:
		var bonus := attacker.rage_bonus
		attacker.rage_bonus = 0
		dmg += bonus
		_ll(out, "被惹毛了：%s 的这次伤害 +%d → %d" % [an, bonus, dmg])

	if dmg <= 0:
		return out

	target.hp = maxi(0, target.hp - dmg)
	attacker.damage_dealt += dmg
	attacker.max_hit = maxi(attacker.max_hit, dmg)
	out["damage"] = dmg
	_ll(out, "%s 用「%s」对 %s 造成 %d 点伤害（剩 %d）" % [an, source, tn, dmg, target.hp])

	if not attacker.is_player:
		var sp: Dictionary = boss_data.get("special", {})
		if String(sp.get("type", "none")) == "bleed":
			target.bleed = int(sp.get("turns", 3))
			target.bleed_dmg = int(sp.get("dmg", 5))
			_ll(out, "%s 的子弹撕开伤口：流血 %d 点 × %d 回合" % [an, target.bleed_dmg, target.bleed])

	return out


func actor_hurt(res: Dictionary, f: Fighter, amount: int, reason: String) -> void:
	f.hp = maxi(0, f.hp - amount)
	res.actor_hurt = true
	_push_log(res, "%s 受到「%s」-%d HP（剩 %d）" % [f.display_name, reason, amount, f.hp])


func _ll(out: Dictionary, text: String) -> void:
	var arr: Array = out.get("logs", [])
	arr.append(text)
	out["logs"] = arr


# ------------------------------------------------------------
#  道具
# ------------------------------------------------------------
func grant_item(f: Fighter, item_id: String) -> Dictionary:
	var out := {"status": "added", "item": item_id, "lv": 1, "logs": []}
	for entry in f.items:
		if String(entry.get("id", "")) == item_id:
			var lv := int(entry.get("lv", 1))
			if lv < Items.max_level():
				entry["lv"] = lv + 1
				out.status = "upgraded"
				out.lv = lv + 1
				_ll(out, "%s 的「%s」升级到 Lv%d" % [f.display_name, Items.item_name(item_id), lv + 1])
			else:
				out.status = "maxed"
				out.lv = lv
				_ll(out, "%s 的「%s」已经是 Lv3，无法继续升级" % [f.display_name, Items.item_name(item_id)])
			return out

	if f.items.size() >= MAX_ITEMS:
		out.status = "full"
		return out

	f.items.append({"id": item_id, "lv": 1})
	_ll(out, "%s 获得道具「%s」Lv1" % [f.display_name, Items.item_name(item_id)])
	return out


func apply_replace(f: Fighter, item_id: String, slot: int) -> bool:
	if slot < 0 or slot >= f.items.size():
		_append_global("%s 放弃了「%s」" % [f.display_name, Items.item_name(item_id)])
		return false
	var old_name := Items.item_name(String(f.items[slot].get("id", "")))
	f.items[slot] = {"id": item_id, "lv": 1}
	_append_global("%s 丢掉了「%s」，槽位 %d 换成「%s」Lv1" % [
		f.display_name, old_name, slot + 1, Items.item_name(item_id)])
	return true


func use_item(f: Fighter, index: int) -> Dictionary:
	var res := {
		"ok": false, "title": "", "summary": "", "logs": [], "damage": 0,
		"shot": false, "target_hurt": false, "actor_hurt": false, "dialogue": "",
	}
	if index < 0 or index >= f.items.size():
		res.summary = "槽位是空的"
		return res
	var entry: Dictionary = f.items[index]
	var item_id := String(entry.get("id", ""))
	var lv := int(entry.get("lv", 1))
	var d := Items.level(item_id, lv)

	if Items.is_negative(item_id):
		res.summary = "「%s」是负面道具，无法主动使用" % Items.item_name(item_id)
		return res

	f.items.remove_at(index)
	var foe: Fighter = boss if f.is_player else player
	res.ok = true
	res.title = Items.label(item_id, lv)
	_push_log(res, "%s 使用「%s」Lv%d" % [f.display_name, Items.item_name(item_id), lv])

	match item_id:
		"hero":
			var dr := deal_damage(f, foe, int(d.get("dmg", 45)), "祖国人激光眼", true)
			_merge(res, dr)
			res.damage = int(dr.get("damage", 0))
			res.target_hurt = res.damage > 0
			res.summary = "激光眼造成 %d 点真实伤害（无视免伤与护甲）" % res.damage
		"rocket":
			var dr2 := deal_damage(f, foe, int(d.get("dmg", 35)), "火箭筒")
			_merge(res, dr2)
			res.damage = int(dr2.get("damage", 0))
			res.target_hurt = res.damage > 0
			var back := int(d.get("self", 5))
			f.hp = maxi(0, f.hp - back)
			res.actor_hurt = true
			_push_log(res, "火箭筒后坐力：%s 自伤 %d HP（剩 %d）" % [f.display_name, back, f.hp])
			res.summary = "对对手 %d 伤害，自身反噬 %d" % [res.damage, back]
		"dora":
			var skip := int(d.get("skip", 1))
			foe.skip += skip
			_push_log(res, "%s 被缩小灯命中，接下来跳过 %d 个回合" % [foe.display_name, skip])
			res.summary = "对手跳过 %d 个回合" % skip
		"immortal":
			f.immune = maxi(f.immune, int(d.get("immune", 1)))
			f.dmg_mult = maxi(f.dmg_mult, int(d.get("mult", 2)))
			var heal := int(d.get("heal", 0))
			if heal > 0:
				var before := f.hp
				f.hp = mini(f.max_hp, f.hp + heal)
				_push_log(res, "仙气护体，%s 回复 %d HP" % [f.display_name, f.hp - before])
			_push_log(res, "%s 获得大罗金仙状态：免伤 %d 回合，下次伤害 ×%d" % [
				f.display_name, int(d.get("immune", 1)), int(d.get("mult", 2))])
			res.summary = Items.line(item_id, lv)
		"virus":
			foe.poison = maxi(foe.poison, int(d.get("turns", 3)))
			foe.poison_dmg = int(d.get("dmg", 8))
			_push_log(res, "%s 感染丧尸病毒：每回合 -%d HP，持续 %d 回合" % [
				foe.display_name, foe.poison_dmg, foe.poison])
			res.summary = "对手每回合开始 -%d HP，持续 %d 回合" % [foe.poison_dmg, foe.poison]
		"armor":
			var charges := int(d.get("charges", 1))
			f.armor += charges
			var reflect := int(d.get("reflect", 0))
			if reflect > 0:
				f.armor_reflect = reflect
			_push_log(res, "%s 穿好防弹衣：可抵挡 %d 次伤害%s" % [
				f.display_name, charges, "，并反弹 %d 点" % reflect if reflect > 0 else ""])
			res.summary = Items.line(item_id, lv)
		_:
			res.summary = "什么也没发生"

	if res.shot:
		pass
	_sync_logs(res.get("logs", []))
	return res


func _merge(res: Dictionary, dr: Dictionary) -> void:
	for l in dr.get("logs", []):
		res.logs.append(String(l))


# ------------------------------------------------------------
#  嘴炮：心理博弈（可能让对手破防，也可能把他惹毛）
# ------------------------------------------------------------
func taunt(actor: Fighter) -> Dictionary:
	var foe: Fighter = boss if actor.is_player else player
	var out := {"tilted": false, "raged": false}
	var r := rng.randf()
	if r < 0.20:
		foe.tilt += 1
		out.tilted = true
		_append_global("%s 被一句话堵住了喉咙，手开始发抖" % foe.display_name)
	elif r < 0.32:
		foe.rage_bonus += 5
		out.raged = true
		_append_global("%s 眼神变了——他动真格的了" % foe.display_name)
	return out


# ------------------------------------------------------------
#  AI 选道具
# ------------------------------------------------------------
func choose_item_for(f: Fighter) -> int:
	if f.items.is_empty():
		return -1
	var hp_ratio := float(f.hp) / float(f.max_hp)
	if hp_ratio < 0.4:
		for i in f.items.size():
			var id := String(f.items[i].get("id", ""))
			if id == "immortal" or id == "armor":
				return i
	for i in f.items.size():
		if String(f.items[i].get("id", "")) == "hero":
			return i
	for i in f.items.size():
		var id2 := String(f.items[i].get("id", ""))
		if id2 == "rocket" or id2 == "virus" or id2 == "dora":
			return i
	return -1


# ------------------------------------------------------------
#  内部工具
# ------------------------------------------------------------
func _push_log(res: Dictionary, text: String) -> void:
	var arr: Array = res.get("logs", [])
	arr.append(text)
	res["logs"] = arr


func _sync_logs(logs: Array) -> void:
	for l in logs:
		_append_global(String(l))


func _append_global(text: String) -> void:
	log_lines.push_front(text)
	if log_lines.size() > 60:
		log_lines.pop_back()


func note(text: String) -> void:
	_append_global(text)


func _delevel(f: Fighter, item_id: String) -> void:
	for i in f.items.size():
		var it: Dictionary = f.items[i]
		if String(it.get("id", "")) == item_id:
			it["lv"] = int(it.get("lv", 1)) - 1
			if int(it["lv"]) <= 0:
				f.items.remove_at(i)
			return


# ------------------------------------------------------------
#  调试用自动对局（默认不参与正常流程，仅 --autoplay 调用）
# ------------------------------------------------------------
func debug_simulate(p_boss: Dictionary, p_seed: int) -> Dictionary:
	var b = get_script().new()
	b.setup(p_boss, p_seed)
	var winner := "draw"
	var guard := 0
	var dbg_p_spins := 0
	var dbg_p_skips := 0
	var dbg_types := {}

	while guard < 600:
		guard += 1

		# ---- 玩家回合 ----
		b.begin_turn(b.player)
		if b.player.hp <= 0:
			winner = "boss"
			break
		if not b.player.cannot_spin:
			dbg_p_spins += 1
			var pi: int = b.roll_spin_index(b.player)
			var pty := String(b.wheel_layout[pi])
			dbg_types[pty] = int(dbg_types.get(pty, 0)) + 1
			b.resolve_spin(b.player, pty)
			if b.pending_item != "":
				b.apply_replace(b.player, b.pending_item, b.best_slot_for(b.player))
				b.pending_item = ""
		else:
			dbg_p_skips += 1
		if b.boss.hp <= 0:
			winner = "player"
			break
		if b.player.hp <= 0:
			winner = "boss"
			break
		var pitem: int = b.choose_item_for(b.player)
		if pitem >= 0:
			b.use_item(b.player, pitem)
		if b.boss.hp <= 0:
			winner = "player"
			break
		if b.player.hp <= 0:
			winner = "boss"
			break

		# ---- Boss 回合 ----
		b.begin_turn(b.boss)
		b.boss_turn_start()
		if b.player.hp <= 0:
			winner = "boss"
			break
		if not b.boss.cannot_spin:
			var bitem: int = b.choose_item_for(b.boss)
			if bitem >= 0:
				b.use_item(b.boss, bitem)
			if b.player.hp <= 0:
				winner = "boss"
				break
			var bi: int = b.roll_spin_index(b.boss)
			b.resolve_spin(b.boss, String(b.wheel_layout[bi]))
			if b.pending_item != "":
				b.apply_replace(b.boss, b.pending_item, b.best_slot_for(b.boss))
				b.pending_item = ""
		if b.boss.hp <= 0:
			winner = "player"
			break
		if b.player.hp <= 0:
			winner = "boss"
			break

		b.round_num += 1
		if b.round_num > 400:
			winner = "draw"
			break

	return {
		"boss": String(p_boss.get("name", "")),
		"winner": winner,
		"rounds": b.round_num,
		"player_hp": b.player.hp,
		"boss_hp": b.boss.hp,
		"player_damage": b.player.damage_dealt,
		"boss_damage": b.boss.damage_dealt,
		"player_max_hit": b.player.max_hit,
		"boss_max_hit": b.boss.max_hit,
		"guard": guard,
		"p_spins": dbg_p_spins,
		"p_skips": dbg_p_skips,
		"types": dbg_types,
	}
