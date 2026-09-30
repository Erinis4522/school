extends RefCounted
## 데이터 검증. 게임을 시작할 때와 tools/validate_data.gd에서 실행된다.
##
## errors   : 반드시 고쳐야 하는 문제 (게임이 잘못 동작한다)
## warnings : 작성 규칙에서 벗어난 부분 (의도한 것이면 두어도 된다)
## info     : 밸런싱 참고용 통계

const Conditions = preload("res://village_sim/scripts/core/condition_evaluator.gd")
const Effects = preload("res://village_sim/scripts/core/effect_manager.gd")

const CATEGORIES: Array[String] = ["general", "state", "delayed"]
const ENDING_TYPES: Array[String] = ["collapse", "term_end"]
const SIDES: Array[String] = ["left", "right"]
const MAX_STATS_PER_CHOICE := 3
const LARGE_EFFECT := 15


static func validate(data: Dictionary) -> Dictionary:
	var report := {"errors": [], "warnings": [], "info": []}
	report["errors"].append_array(data.get("load_errors", []))

	var config: Dictionary = data["config"]
	var stat_ids: Array = config["stat_order"]
	if stat_ids.is_empty():
		report["errors"].append("설정 파일에 상태(stats)가 없습니다.")

	var ctx := {
		"stat_ids": stat_ids,
		"flags_set": {},     # 플래그 -> [켜는 사건 id]
		"flags_used": {},    # 플래그 -> [조건에서 쓰는 사건/엔딩 id]
		"flags_trigger": {}, # 플래그 -> [켜져 있어야 나오는 사건/엔딩 id] (no_flag 제외)
		"flags_cleared": {}, # 플래그 -> [끄는 사건 id]
	}

	_validate_events(data["events"], config, ctx, report)
	_validate_endings(data["endings"], ctx, report)
	_validate_flags(ctx, report)
	return report


static func print_report(report: Dictionary, include_info: bool = false) -> void:
	print("=== 데이터 검증: 오류 %d개 / 경고 %d개 ===" % [report["errors"].size(), report["warnings"].size()])
	for message in report["errors"]:
		printerr("[오류] " + message)
	for message in report["warnings"]:
		print("[경고] " + message)
	if include_info:
		for message in report["info"]:
			print("[정보] " + message)


# --- 사건 ----------------------------------------------------------------------

static func _validate_events(events: Array, config: Dictionary, ctx: Dictionary, report: Dictionary) -> void:
	var stat_ids: Array = ctx["stat_ids"]
	var seen_ids := {}
	var category_count := {}
	var tag_count := {}
	var stat_usage := {}
	for stat_id in stat_ids:
		stat_usage[stat_id] = {"gain_count": 0, "gain_sum": 0, "loss_count": 0, "loss_sum": 0}

	for event in events:
		var id: String = event["id"]
		var where := "사건 '%s' (%s)" % [id, String(event["source"]).get_file()]

		if id.is_empty():
			report["errors"].append("%s: id가 비어 있습니다." % where)
		elif seen_ids.has(id):
			report["errors"].append("%s: id가 '%s'와 겹칩니다." % [where, seen_ids[id]])
		else:
			seen_ids[id] = String(event["source"]).get_file()

		var category: String = event["category"]
		category_count[category] = int(category_count.get(category, 0)) + 1
		for tag in event["tags"]:
			tag_count[tag] = int(tag_count.get(tag, 0)) + 1

		if not (category in CATEGORIES):
			report["errors"].append("%s: category '%s'는 general / state / delayed 중 하나여야 합니다." % [where, category])
		if String(event["title"]).is_empty():
			report["errors"].append("%s: 제목(title)이 없습니다." % where)
		if String(event["description"]).is_empty():
			report["warnings"].append("%s: 설명(description)이 없습니다." % where)

		# 조건
		var conditions: Array = event["conditions"]
		if category == "general" and not conditions.is_empty():
			report["errors"].append("%s: 일반 사건에는 조건을 넣지 않습니다. category를 state 또는 delayed로 바꾸세요." % where)
		if category in ["state", "delayed"] and conditions.is_empty():
			report["errors"].append("%s: 조건부 사건인데 조건이 없습니다." % where)
		if category == "delayed" and not _has_delay_condition(conditions):
			report["errors"].append("%s: 지연 사건에는 {\"type\": \"flag\", \"min_age\": 1 이상} 조건이 필요합니다." % where)
		for condition in conditions:
			_validate_condition(condition, where, id, ctx, report)

		# 선택지
		for side in SIDES:
			_validate_choice(event[side + "_choice"], "%s %s 선택지" % [where, "왼쪽" if side == "left" else "오른쪽"], id, ctx, stat_usage, report)
		var left_hint: Array = Effects.affected_stats(event["left_choice"], stat_ids)
		var right_hint: Array = Effects.affected_stats(event["right_choice"], stat_ids)
		if left_hint == right_hint:
			report["warnings"].append("%s: 좌/우 선택지가 건드리는 상태가 같아 힌트로 구별되지 않습니다. %s" % [where, str(left_hint)])

	# 사건 수
	var general_count := int(category_count.get("general", 0))
	if general_count < int(config["max_turns"]):
		report["errors"].append("일반 사건이 %d개로 최대 턴(%d)보다 적습니다. 조건부 사건이 안 나오면 판이 끝나기 전에 사건이 바닥납니다." % [general_count, config["max_turns"]])

	report["info"].append("사건 수: 일반 %d / 상태·턴 조건 %d / 지연 %d / 전체 %d" % [
		general_count, int(category_count.get("state", 0)), int(category_count.get("delayed", 0)), events.size()])
	report["info"].append("일반 사건은 최대 턴(%d)의 %.1f배" % [config["max_turns"], float(general_count) / maxf(1.0, float(config["max_turns"]))])
	var tag_parts: Array = []
	for tag in tag_count:
		tag_parts.append("%s %d" % [tag, tag_count[tag]])
	report["info"].append("태그: " + ", ".join(PackedStringArray(tag_parts)))
	for stat_id in stat_ids:
		var usage: Dictionary = stat_usage[stat_id]
		report["info"].append("%s: 올리는 선택지 %d개 (합 +%d) / 내리는 선택지 %d개 (합 %d)" % [
			stat_id, usage["gain_count"], usage["gain_sum"], usage["loss_count"], usage["loss_sum"]])


static func _validate_choice(choice: Dictionary, where: String, owner_id: String, ctx: Dictionary, stat_usage: Dictionary, report: Dictionary) -> void:
	var stat_ids: Array = ctx["stat_ids"]
	if String(choice["text"]).is_empty():
		report["errors"].append("%s: 문구(text)가 없습니다." % where)
	if String(choice["result"]).is_empty():
		report["warnings"].append("%s: 결과 문구(result)가 없습니다." % where)

	var effects: Dictionary = choice["effects"]
	var touched := 0
	for stat_id in effects:
		var value := int(effects[stat_id])
		if not (stat_id in stat_ids):
			report["errors"].append("%s: 없는 상태 '%s'" % [where, stat_id])
			continue
		if value == 0:
			continue
		touched += 1
		if absi(value) > LARGE_EFFECT:
			report["warnings"].append("%s: %s 변화 %d가 큽니다. (기준 %d)" % [where, stat_id, value, LARGE_EFFECT])
		var usage: Dictionary = stat_usage[stat_id]
		if value > 0:
			usage["gain_count"] += 1
			usage["gain_sum"] += value
		else:
			usage["loss_count"] += 1
			usage["loss_sum"] += value
	if touched == 0:
		report["warnings"].append("%s: 상태 변화가 없습니다. 힌트가 비어 보입니다." % where)
	elif touched > MAX_STATS_PER_CHOICE:
		report["warnings"].append("%s: %d개 상태를 건드립니다. (권장 %d개 이하)" % [where, touched, MAX_STATS_PER_CHOICE])

	for entry in choice["set_flags"]:
		var flag: String = entry["flag"]
		if flag.is_empty():
			report["errors"].append("%s: set_flags에 이름 없는 플래그가 있습니다." % where)
			continue
		var chance: float = entry["chance"]
		if chance <= 0.0 or chance > 1.0:
			report["errors"].append("%s: 플래그 '%s'의 chance %.2f는 0보다 크고 1 이하여야 합니다." % [where, flag, chance])
		_add_ref(ctx["flags_set"], flag, owner_id)
	for flag in choice["clear_flags"]:
		_add_ref(ctx["flags_cleared"], flag, owner_id)


static func _has_delay_condition(conditions: Array) -> bool:
	for condition in conditions:
		if condition is Dictionary and condition.get("type") == "flag" and int(condition.get("min_age", 0)) >= 1:
			return true
	return false


static func _validate_condition(condition: Variant, where: String, owner_id: String, ctx: Dictionary, report: Dictionary) -> void:
	if not (condition is Dictionary):
		report["errors"].append("%s: 조건은 객체여야 합니다." % where)
		return
	var type := String(condition.get("type", ""))
	if not Conditions.REQUIRED_FIELDS.has(type):
		report["errors"].append("%s: 알 수 없는 조건 종류 '%s' (가능: %s)" % [where, type, ", ".join(PackedStringArray(Conditions.REQUIRED_FIELDS.keys()))])
		return
	for field in Conditions.REQUIRED_FIELDS[type]:
		if not condition.has(field):
			report["errors"].append("%s: '%s' 조건에 '%s' 항목이 없습니다." % [where, type, field])
	if condition.has("op") and not (String(condition["op"]) in Conditions.OPS):
		report["errors"].append("%s: 비교 기호 '%s'를 쓸 수 없습니다. (가능: %s)" % [where, condition["op"], ", ".join(PackedStringArray(Conditions.OPS))])
	if type == "stat" and not (String(condition.get("stat", "")) in ctx["stat_ids"]):
		report["errors"].append("%s: 없는 상태 '%s'" % [where, condition.get("stat", "")])
	if condition.has("flag"):
		_add_ref(ctx["flags_used"], String(condition["flag"]), owner_id)
		if type == "flag":
			_add_ref(ctx["flags_trigger"], String(condition["flag"]), owner_id)


# --- 엔딩 ----------------------------------------------------------------------

static func _validate_endings(endings: Array, ctx: Dictionary, report: Dictionary) -> void:
	var seen_ids := {}
	var has_default_term_end := false
	var collapse_stats := {}

	for ending in endings:
		var id: String = ending["id"]
		var where := "엔딩 '%s' (%s)" % [id, String(ending["source"]).get_file()]
		if id.is_empty():
			report["errors"].append("%s: id가 비어 있습니다." % where)
		elif seen_ids.has(id):
			report["errors"].append("%s: id가 겹칩니다." % where)
		seen_ids[id] = true

		var type: String = ending["type"]
		if not (type in ENDING_TYPES):
			report["errors"].append("%s: type은 collapse 또는 term_end여야 합니다." % where)
		if String(ending["title"]).is_empty() or String(ending["text"]).is_empty():
			report["warnings"].append("%s: 제목이나 본문이 비어 있습니다." % where)

		var conditions: Array = ending["conditions"]
		for condition in conditions:
			_validate_condition(condition, where, id, ctx, report)

		if type == "collapse":
			if conditions.is_empty():
				report["errors"].append("%s: 붕괴 엔딩에 조건이 없으면 첫 턴에 바로 끝납니다." % where)
			var stat: String = ending["stat"]
			if not (stat in ctx["stat_ids"]):
				report["errors"].append("%s: 붕괴 엔딩에는 어느 상태의 엔딩인지 stat 항목이 필요합니다." % where)
			collapse_stats[stat] = true
		elif type == "term_end" and conditions.is_empty():
			has_default_term_end = true

	if not has_default_term_end:
		report["errors"].append("조건 없는 임기 종료(term_end) 기본 엔딩이 없습니다.")
	for stat_id in ctx["stat_ids"]:
		if not collapse_stats.has(stat_id):
			report["warnings"].append("상태 '%s'의 붕괴 엔딩이 없습니다." % stat_id)


# --- 플래그 --------------------------------------------------------------------

static func _validate_flags(ctx: Dictionary, report: Dictionary) -> void:
	var flags_set: Dictionary = ctx["flags_set"]
	for flag in ctx["flags_used"]:
		if not flags_set.has(flag):
			report["errors"].append("플래그 '%s'를 조건에서 쓰는데(%s) 켜는 선택지가 없습니다. 이름 오타인지 확인하세요." % [flag, ", ".join(PackedStringArray(ctx["flags_used"][flag]))])
	for flag in ctx["flags_cleared"]:
		if not flags_set.has(flag):
			report["warnings"].append("플래그 '%s'를 끄는데(%s) 켜는 선택지가 없습니다." % [flag, ", ".join(PackedStringArray(ctx["flags_cleared"][flag]))])
	var unused: Array = []
	var foreshadow: Array = []
	for flag in flags_set:
		if not ctx["flags_used"].has(flag):
			unused.append(flag)
		if ctx["flags_trigger"].has(flag):
			for owner_id in flags_set[flag]:
				if not (owner_id in foreshadow):
					foreshadow.append(owner_id)
	report["info"].append("뒤에 다른 사건으로 이어지는 선택이 있는 사건 (결과 문구에 '나중에 무슨 일이 생길지 모른다'는 느낌을 담을 것): " + ", ".join(PackedStringArray(foreshadow)))
	if not unused.is_empty():
		report["info"].append("켜기만 하고 조건에서 쓰지 않는 플래그 (엔딩 확장용이면 괜찮음): " + ", ".join(PackedStringArray(unused)))


static func _add_ref(refs: Dictionary, key: String, owner_id: String) -> void:
	if not refs.has(key):
		refs[key] = []
	refs[key].append(owner_id)
