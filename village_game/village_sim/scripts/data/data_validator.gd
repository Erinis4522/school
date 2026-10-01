extends RefCounted
## 데이터 검증. 게임을 시작할 때와 tools/validate_data.gd에서 실행된다.
##
## errors   : 반드시 고쳐야 하는 문제 (게임이 잘못 동작한다)
## warnings : 작성 규칙에서 벗어난 부분 (의도한 것이면 두어도 된다)
## info     : 밸런싱 참고용 통계

const Conditions = preload("res://village_sim/scripts/core/condition_evaluator.gd")
const Effects = preload("res://village_sim/scripts/core/effect_manager.gd")

const CATEGORIES: Array[String] = ["general", "state", "delayed", "final"]
const ENDING_TYPES: Array[String] = ["collapse", "term_end"]
const SIDES: Array[String] = ["left", "right"]
const EXPRESSIONS: Array[String] = ["neutral", "happy", "angry", "worried"]  # 기본 표정 (그림 파일 이름과 같다)
const LAYER_ANIMS: Array[String] = ["frames", "drift", "sway", "flicker"]  # village_backdrop.gd가 아는 배경 움직임
const MAX_STATS_PER_CHOICE := 3
const LARGE_EFFECT := 15


static func validate(data: Dictionary) -> Dictionary:
	var report := {"errors": [], "warnings": [], "info": []}
	report["errors"].append_array(data.get("load_errors", []))

	var config: Dictionary = data["config"]
	var stat_ids: Array = config["stat_order"]
	if stat_ids.is_empty():
		report["errors"].append("설정 파일에 상태(stats)가 없습니다.")

	var act_ids: Array = []
	for act in config["acts"]:
		act_ids.append(act["id"])
	if act_ids.is_empty():
		report["errors"].append("설정 파일에 막(acts)이 없습니다.")

	var npc_ids := {}
	for npc in data.get("npcs", []):
		if npc_ids.has(npc["id"]):
			report["errors"].append("NPC id '%s'가 겹칩니다." % npc["id"])
		npc_ids[npc["id"]] = 0
		if not String(npc["concern"]).is_empty() and not (npc["concern"] in stat_ids):
			report["errors"].append("NPC '%s'의 concern '%s'는 없는 상태입니다." % [npc["id"], npc["concern"]])
		for expression in EXPRESSIONS:
			if npc["lines"].get(expression, []).is_empty():
				report["warnings"].append("NPC '%s'에 '%s' 표정 기본 대사가 없습니다." % [npc["id"], expression])

	var ctx := {
		"stat_ids": stat_ids,
		"act_ids": act_ids,
		"npc_ids": npc_ids,   # NPC id -> 등장 사건 수
		"flags_set": {},      # 플래그 -> [켜는 사건 id]
		"flags_used": {},     # 플래그 -> [조건에서 쓰는 사건/엔딩 id]
		"flags_trigger": {},  # 플래그 -> [그 플래그 때문에 나오는 지연 사건 id]
		"flags_cleared": {},  # 플래그 -> [끄는 사건 id]
	}

	_validate_acts(config, report)
	_validate_events(data["events"], config, ctx, report)
	_validate_endings(data["endings"], ctx, report)
	_validate_story(data.get("story", {}), config, report)
	var opening_npc := String(data.get("story", {}).get("opening", {}).get("npc", ""))
	if not opening_npc.is_empty() and not npc_ids.has(opening_npc):
		report["errors"].append("story.json의 첫 인사(opening) 인물 '%s'가 없는 인물입니다." % opening_npc)
	# 사건 앞 대화 (data/dialogue/)
	var event_ids := {}
	for event in data["events"]:
		event_ids[event["id"]] = true
	var debates: Dictionary = data.get("debates", {})
	for event_id in debates:
		var debate: Dictionary = debates[event_id]
		var where := "대화 '%s' (%s)" % [event_id, String(debate["source"]).get_file()]
		if not event_ids.has(event_id):
			report["errors"].append("%s: 없는 사건입니다." % where)
		for side in ["left", "right"]:
			var npc_id: String = debate[side]["npc"]
			if not npc_ids.has(npc_id):
				report["errors"].append("%s: %s 인물 '%s'가 없습니다." % [where, side, npc_id])
			if String(debate[side]["line"]).is_empty():
				report["warnings"].append("%s: %s 대사가 비어 있습니다." % [where, side])
		if debate["left"]["npc"] == debate["right"]["npc"]:
			report["warnings"].append("%s: 왼쪽과 오른쪽 인물이 같습니다. 찬반 구도가 되려면 서로 달라야 합니다." % where)
	var without_debate: Array = []
	for event_id in event_ids:
		if not debates.has(event_id):
			without_debate.append(event_id)
	if not without_debate.is_empty():
		report["warnings"].append("대화가 없는 사건 %d개 (바로 질문이 나옵니다): %s" % [without_debate.size(), ", ".join(PackedStringArray(without_debate))])

	var backgrounds: Dictionary = data.get("backgrounds", {})
	if backgrounds.is_empty():
		report["warnings"].append("배경 규칙(visuals/backgrounds.json)이 없습니다. 기본 배경만 나옵니다.")
	for stat_id in backgrounds.get("by_stat", {}):
		if not (stat_id in stat_ids):
			report["errors"].append("배경 규칙의 '%s'는 없는 상태입니다." % stat_id)
	for layer in data.get("layers", []):
		var anim_type := String(layer["anim"].get("type", ""))
		if not anim_type.is_empty() and not (anim_type in LAYER_ANIMS):
			report["warnings"].append("배경 레이어 '%s': anim 종류 '%s'는 없습니다. (가능: %s)" % [layer["id"], anim_type, ", ".join(PackedStringArray(LAYER_ANIMS))])
		for condition in layer["conditions"]:
			_validate_condition(condition, "배경 레이어 '%s'" % layer["id"], "layer:" + String(layer["id"]), false, ctx, report)
	_validate_flags(ctx, report)

	var npc_parts: Array = []
	for npc_id in npc_ids:
		npc_parts.append("%s %d" % [npc_id, npc_ids[npc_id]])
	report["info"].append("NPC별 등장 사건 수: " + ", ".join(PackedStringArray(npc_parts)))
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


# --- 막 ------------------------------------------------------------------------

static func _validate_acts(config: Dictionary, report: Dictionary) -> void:
	var expected_from := 1
	for act in config["acts"]:
		if int(act["from"]) != expected_from:
			report["errors"].append("막 '%s'는 %d턴에 시작해야 합니다. (막 사이에 빈 턴이나 겹치는 턴이 없어야 함)" % [act["id"], expected_from])
		expected_from = int(act["to"]) + 1
	if not config["acts"].is_empty() and expected_from - 1 != int(config["max_turns"]):
		report["errors"].append("마지막 막이 최대 턴(%d)에서 끝나야 합니다." % config["max_turns"])


# --- 사건 ----------------------------------------------------------------------

static func _validate_events(events: Array, config: Dictionary, ctx: Dictionary, report: Dictionary) -> void:
	var stat_ids: Array = ctx["stat_ids"]
	var seen_ids := {}
	var category_count := {}
	var tag_count := {}
	var act_pool := {}     # 막 id -> 그 막에 나올 수 있는 일반 사건 수
	var act_touch := {}    # 막 id -> [선택지가 건드리는 상태 수 합, 선택지 수]
	var has_default_final := false
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
			report["errors"].append("%s: category '%s'는 general / state / delayed / final 중 하나여야 합니다." % [where, category])
		if String(event["title"]).is_empty():
			report["errors"].append("%s: 제목(title)이 없습니다." % where)
		if String(event["description"]).is_empty():
			report["warnings"].append("%s: 설명(description)이 없습니다." % where)

		# 막
		for phase in event["phases"]:
			if not (phase in ctx["act_ids"]):
				report["errors"].append("%s: phases의 '%s'는 설정에 없는 막입니다. (가능: %s)" % [where, phase, ", ".join(PackedStringArray(ctx["act_ids"]))])
			elif category == "general":
				act_pool[phase] = int(act_pool.get(phase, 0)) + 1

		# 등장인물
		var npc: String = event["npc"]
		if not npc.is_empty():
			if ctx["npc_ids"].has(npc):
				ctx["npc_ids"][npc] += 1
			else:
				report["errors"].append("%s: 없는 NPC '%s'" % [where, npc])
		_check_expression(event["npc_expression"], where, report)
		for side in SIDES:
			var reaction_expression: String = event[side + "_choice"]["reaction_expression"]
			if not reaction_expression.is_empty():
				_check_expression(reaction_expression, where, report)
			var side_npc: String = event[side + "_choice"]["npc"]
			if not side_npc.is_empty():
				if ctx["npc_ids"].has(side_npc):
					ctx["npc_ids"][side_npc] += 1
				else:
					report["errors"].append("%s: 선택지의 npc '%s'가 없는 인물입니다." % [where, side_npc])

		# 조건
		var conditions: Array = event["conditions"]
		if category == "general" and not conditions.is_empty():
			report["errors"].append("%s: 일반 사건에는 조건을 넣지 않습니다. category를 state 또는 delayed로 바꾸세요." % where)
		if category in ["state", "delayed"] and conditions.is_empty():
			report["errors"].append("%s: 조건부 사건인데 조건이 없습니다." % where)
		if category == "delayed" and not _has_delay_condition(conditions):
			report["errors"].append("%s: 지연 사건에는 {\"type\": \"flag\", \"min_age\": 1 이상} 조건이 필요합니다." % where)
		if category == "final" and conditions.is_empty():
			has_default_final = true
		for condition in conditions:
			_validate_condition(condition, where, id, category == "delayed", ctx, report)

		# 과거 선택에 따라 바뀌는 설명
		for variant in event["description_variants"]:
			if String(variant["text"]).is_empty():
				report["warnings"].append("%s: description_variants에 빈 문구가 있습니다." % where)
			if variant["conditions"].is_empty():
				report["warnings"].append("%s: 조건 없는 description_variants는 항상 원래 설명을 덮어씁니다." % where)
			for condition in variant["conditions"]:
				_validate_condition(condition, where + " 대사 변형", id, false, ctx, report)

		# 선택지
		for side in SIDES:
			var touched := _validate_choice(event[side + "_choice"], "%s %s 선택지" % [where, "왼쪽" if side == "left" else "오른쪽"], id, ctx, stat_usage, report)
			if category == "general":
				for phase in event["phases"]:
					var sums: Array = act_touch.get(phase, [0, 0])
					act_touch[phase] = [sums[0] + touched, sums[1] + 1]
		var left_hint: Dictionary = Effects.preview_levels(event["left_choice"], config)
		var right_hint: Dictionary = Effects.preview_levels(event["right_choice"], config)
		if left_hint == right_hint:
			report["warnings"].append("%s: 좌/우 선택지의 힌트(방향·강도)가 같아 구별되지 않습니다." % where)

	# 사건 수
	var general_count := int(category_count.get("general", 0))
	if general_count < int(config["max_turns"]):
		report["errors"].append("일반 사건이 %d개로 최대 턴(%d)보다 적습니다. 조건부 사건이 안 나오면 판이 끝나기 전에 사건이 바닥납니다." % [general_count, config["max_turns"]])
	for act in config["acts"]:
		var length := int(act["to"]) - int(act["from"]) + 1
		var pool := int(act_pool.get(act["id"], 0))
		if pool < length:
			report["warnings"].append("막 '%s'(%d턴)에 나올 수 있는 일반 사건이 %d개뿐입니다. 부족하면 다른 막의 사건을 끌어 씁니다." % [act["id"], length, pool])
	if int(category_count.get("final", 0)) > 0 and not has_default_final:
		report["errors"].append("조건 없는 최종 사건(final)이 없습니다. 조건이 하나도 안 맞으면 마지막 턴에 일반 사건이 나옵니다.")

	report["info"].append("사건 수: 일반 %d / 상태·턴 조건 %d / 지연 %d / 최종 %d / 전체 %d" % [
		general_count, int(category_count.get("state", 0)), int(category_count.get("delayed", 0)),
		int(category_count.get("final", 0)), events.size()])
	for act in config["acts"]:
		var sums: Array = act_touch.get(act["id"], [0, 0])
		report["info"].append("막 '%s' (%d~%d턴): 일반 사건 %d개, 선택지당 평균 %.1f개 상태" % [
			act["id"], act["from"], act["to"], int(act_pool.get(act["id"], 0)), float(sums[0]) / maxf(1.0, float(sums[1]))])
	var tag_parts: Array = []
	for tag in tag_count:
		tag_parts.append("%s %d" % [tag, tag_count[tag]])
	report["info"].append("태그: " + ", ".join(PackedStringArray(tag_parts)))
	for stat_id in stat_ids:
		var usage: Dictionary = stat_usage[stat_id]
		report["info"].append("%s: 올리는 선택지 %d개 (합 +%d) / 내리는 선택지 %d개 (합 %d)" % [
			stat_id, usage["gain_count"], usage["gain_sum"], usage["loss_count"], usage["loss_sum"]])


## 선택지를 검사하고, 건드리는 상태 수를 돌려준다.
static func _validate_choice(choice: Dictionary, where: String, owner_id: String, ctx: Dictionary, stat_usage: Dictionary, report: Dictionary) -> int:
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
	return touched


## 기본 표정이 아니면 알려 준다. (새 표정을 쓰려면 같은 이름의 그림 파일이 있어야 하고, 없으면 neutral 그림이 나온다)
static func _check_expression(expression: String, where: String, report: Dictionary) -> void:
	if not (expression in EXPRESSIONS):
		report["warnings"].append("%s: 표정 '%s'는 기본 표정(%s)이 아닙니다. 같은 이름의 그림이 없으면 neutral 그림이 나옵니다." % [where, expression, ", ".join(PackedStringArray(EXPRESSIONS))])


static func _has_delay_condition(conditions: Array) -> bool:
	for condition in conditions:
		if condition is Dictionary and condition.get("type") == "flag" and int(condition.get("min_age", 0)) >= 1:
			return true
	return false


## is_trigger: 이 조건이 지연 사건을 일으키는 조건인지 (결과 문구 복선 안내에 쓰임)
static func _validate_condition(condition: Variant, where: String, owner_id: String, is_trigger: bool, ctx: Dictionary, report: Dictionary) -> void:
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
	if type in ["stat", "trend"] and not (String(condition.get("stat", "")) in ctx["stat_ids"]):
		report["errors"].append("%s: 없는 상태 '%s'" % [where, condition.get("stat", "")])
	if condition.has("flag"):
		_add_ref(ctx["flags_used"], String(condition["flag"]), owner_id)
		if type == "flag" and is_trigger:
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
			_validate_condition(condition, where, id, false, ctx, report)

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


# --- 중간 결산 ------------------------------------------------------------------

static func _validate_story(story: Dictionary, config: Dictionary, report: Dictionary) -> void:
	var checkpoints: Array = story.get("checkpoints", [])
	if checkpoints.is_empty():
		report["info"].append("중간 결산(story.json의 checkpoints)이 없습니다.")
	for checkpoint in checkpoints:
		var turn := int(checkpoint.get("after_turn", 0))
		if turn < 1 or turn >= int(config["max_turns"]):
			report["errors"].append("중간 결산 after_turn %d는 1 이상, 최대 턴(%d) 미만이어야 합니다." % [turn, config["max_turns"]])
		if String(checkpoint.get("title", "")).is_empty():
			report["warnings"].append("%d턴 중간 결산에 제목이 없습니다." % turn)
	var stat_lines: Dictionary = story.get("stat_lines", {})
	for stat_id in config["stat_order"]:
		var bands: Array = stat_lines.get(stat_id, [])
		if bands.is_empty():
			report["warnings"].append("중간 결산에 상태 '%s'의 문장이 없습니다." % stat_id)
		elif int(bands[bands.size() - 1].get("max", 0)) < int(config["stat_max"]):
			report["warnings"].append("중간 결산 '%s' 문장 구간이 최대값(%d)까지 닿지 않습니다." % [stat_id, config["stat_max"]])


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
	report["info"].append("뒤에 지연 사건으로 이어지는 선택이 있는 사건 (결과 문구에 '나중에 무슨 일이 생길지 모른다'는 느낌을 담을 것): " + ", ".join(PackedStringArray(foreshadow)))
	if not unused.is_empty():
		report["info"].append("켜기만 하고 조건에서 쓰지 않는 플래그 (엔딩 확장용이면 괜찮음): " + ", ".join(PackedStringArray(unused)))


static func _add_ref(refs: Dictionary, key: String, owner_id: String) -> void:
	if not refs.has(key):
		refs[key] = []
	refs[key].append(owner_id)
