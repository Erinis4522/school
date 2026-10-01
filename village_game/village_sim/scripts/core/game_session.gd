extends RefCounted
## 한 판의 진행을 관리한다.
##
## 한 턴의 흐름: 사건 제시 → choose("left" / "right") → 결과 제시 → proceed() → 다음 사건 (또는 엔딩)
## 새 판을 시작하면 안내원의 첫 인사(story.json의 opening)가, 인물이 처음 등장하는 사건 앞에는
## 그 인물의 자기소개(npcs.json의 intro)가 대사로 먼저 나온다. 대사 한 줄마다 proceed()로 넘어간다.
## 막이 끝나는 턴(설정의 checkpoints)에는 결과 다음에 중간 결산을 한 번 보여 주고, proceed()로 넘어간다.
## 마지막 턴에는 최종 사건이 나오고, 그 선택 뒤 임기 종료 엔딩으로 이어진다.
## UI는 신호를 받아 화면에 보여 주고, 플레이어 입력은 choose()와 proceed()로만 전달한다.
## 밸런스 시뮬레이터도 이 클래스를 화면 없이 그대로 사용한다.

signal dialogue_presented(dialogue: Dictionary)
signal event_presented(event: Dictionary, hints: Dictionary)
signal choice_resolved(result: Dictionary)
signal checkpoint_presented(checkpoint: Dictionary)
signal stats_changed(ratios: Dictionary)
signal game_ended(ending: Dictionary, summary: Dictionary)

const GameState = preload("res://village_sim/scripts/core/game_state.gd")
const Conditions = preload("res://village_sim/scripts/core/condition_evaluator.gd")
const Effects = preload("res://village_sim/scripts/core/effect_manager.gd")
const EventManager = preload("res://village_sim/scripts/core/event_manager.gd")
const EndingResolver = preload("res://village_sim/scripts/core/ending_resolver.gd")
const VisualLayers = preload("res://village_sim/scripts/core/visual_layers.gd")

const SIDES: Array[String] = ["left", "right"]
const RECENT_TAGS_KEEP := 10
const FALLBACK_ENDING := {
	"id": "fallback_term_end",
	"type": "term_end",
	"title": "임기 종료",
	"text": "임기가 끝났습니다.",
}

var data: Dictionary
var config: Dictionary
var state
var current_event: Dictionary = {}
var last_result: Dictionary = {}
var current_checkpoint: Dictionary = {}
var current_dialogue: Dictionary = {}
var ending: Dictionary = {}

var _rng := RandomNumberGenerator.new()
var _dialogue_queue: Array = []     # 사건 앞에 나올 대사들 [{"npc", "expression", "text", "kind"}]
var _pending_event: Dictionary = {}  # 대사가 끝나면 보여 줄 사건
var _events
var _endings
var _npcs: Dictionary = {}
var _awaiting_proceed := false
var _pending_ending: Dictionary = {}


func _init(game_data: Dictionary) -> void:
	data = game_data
	config = game_data["config"]
	_events = EventManager.new(game_data["events"], config["selection"])
	_endings = EndingResolver.new(game_data["endings"])
	for npc in game_data.get("npcs", []):
		_npcs[npc["id"]] = npc


## 새 판을 시작한다. run_seed를 주면 같은 사건 흐름을 재현할 수 있다.
func start(run_seed: int = -1) -> void:
	state = GameState.new()
	state.rng_seed = run_seed if run_seed >= 0 else randi()
	_rng.seed = state.rng_seed
	for stat in config["stats"]:
		state.stats[stat["id"]] = int(stat["initial"])
	current_event = {}
	last_result = {}
	current_checkpoint = {}
	current_dialogue = {}
	ending = {}
	_awaiting_proceed = false
	_pending_ending = {}
	_dialogue_queue = []
	_pending_event = {}
	stats_changed.emit(get_stat_ratios())
	_queue_opening()
	_present_next_event()


func is_over() -> bool:
	return not ending.is_empty()


## 선택 후 결과를 보여 주는 중인지. 이때는 proceed()로만 넘어간다.
func is_showing_result() -> bool:
	return _awaiting_proceed and current_checkpoint.is_empty() and current_dialogue.is_empty()


## 첫 인사나 자기소개 대사를 보여 주는 중인지. 이때는 proceed()로만 넘어간다.
func is_showing_dialogue() -> bool:
	return not current_dialogue.is_empty()


func is_showing_checkpoint() -> bool:
	return not current_checkpoint.is_empty()


func choose(side: String) -> void:
	if is_over() or _awaiting_proceed or current_event.is_empty() or not (side in SIDES):
		return
	var choice: Dictionary = current_event[side + "_choice"]
	var before: Dictionary = state.stats.duplicate()
	Effects.apply_choice(state, choice, config, _rng)
	state.choice_log.append({"turn": state.turn, "event_id": current_event["id"], "side": side})
	if not String(choice["memory"]).is_empty():
		state.memories.append({"turn": state.turn, "text": choice["memory"]})

	# 이번 턴으로 판이 끝나는지는 지금 정해 두고, 결과를 보여 준 뒤 proceed()에서 엔딩으로 넘어간다.
	_pending_ending = _endings.check_collapse(state)
	if _pending_ending.is_empty() and state.turn >= int(config["max_turns"]):
		_pending_ending = _endings.resolve_term_end(state)
		if _pending_ending.is_empty():
			_pending_ending = FALLBACK_ENDING

	var changes := _stat_levels(before, state.stats)
	last_result = {
		"event": current_event,
		"side": side,
		"choice_text": choice["text"],
		"text": choice["result"],
		"changes": changes,
		"reaction": _reaction_for(current_event, side, choice, changes),
		"important": not String(choice["memory"]).is_empty(),   # 회상 문구가 있는 선택 = 중요한 선택 (화면 연출용)
	}
	_awaiting_proceed = true
	stats_changed.emit(get_stat_ratios())
	choice_resolved.emit(last_result)


## 결과(또는 중간 결산)를 확인하고 다음으로 넘어간다.
func proceed() -> void:
	if not _awaiting_proceed:
		return
	if not current_dialogue.is_empty():
		_awaiting_proceed = false
		_continue_to_event()
		return
	if not _pending_ending.is_empty():
		_awaiting_proceed = false
		_finish(_pending_ending)
		return
	if current_checkpoint.is_empty():
		var checkpoint := _checkpoint_for_turn(state.turn)
		if not checkpoint.is_empty():
			current_checkpoint = checkpoint
			checkpoint_presented.emit(current_checkpoint)
			return
	current_checkpoint = {}
	_awaiting_proceed = false
	state.turn += 1
	_present_next_event()


## 선택했을 때의 상태값을 미리 계산한다. (시뮬레이터용. 화면에는 쓰지 않는다)
func preview_choice(side: String) -> Dictionary:
	return Effects.preview_stats(state.stats, current_event[side + "_choice"], config)


## 현재 사건의 좌/우 선택지 힌트: {"left": {stat_id: 단계}, "right": {...}} (단계는 ±1 / ±2)
func get_hints() -> Dictionary:
	var hints := {}
	for side in SIDES:
		hints[side] = Effects.preview_levels(current_event[side + "_choice"], config)
	return hints


## UI용 0.0~1.0 비율. 정확한 숫자는 UI에 넘기지 않는다.
func get_stat_ratios() -> Dictionary:
	var low := float(config["stat_min"])
	var high := float(config["stat_max"])
	var ratios := {}
	for stat_id in state.stats:
		ratios[stat_id] = (float(state.stats[stat_id]) - low) / (high - low)
	return ratios


## 현재 턴이 속한 막. {"id", "name", "from", "to", "follow_up_chance"}
func get_current_act() -> Dictionary:
	for act in config["acts"]:
		if state.turn >= int(act["from"]) and state.turn <= int(act["to"]):
			return act
	return {}


## 향후 마을 배경용: 지금 켜져야 할 배경 레이어 id 목록
func get_active_layers() -> Array:
	return VisualLayers.active_layers(data.get("layers", []), state)


## 지금 보여 줄 마을 배경 id (data/visuals/backgrounds.json)
## 위험 기준(danger_threshold) 이하인 상태가 있으면 그중 값이 가장 낮은 상태의 배경, 없으면 기본 배경.
func get_background_id() -> String:
	var rules: Dictionary = data.get("backgrounds", {})
	var by_stat: Dictionary = rules.get("by_stat", {})
	var threshold := int(rules.get("danger_threshold", 30))
	var worst_id := ""
	var worst_value := threshold + 1
	for stat_id in config["stat_order"]:
		var value := int(state.stats[stat_id])
		if by_stat.has(stat_id) and value <= threshold and value < worst_value:
			worst_value = value
			worst_id = by_stat[stat_id]
	return worst_id if not worst_id.is_empty() else String(rules.get("default", "normal"))


func get_summary() -> Dictionary:
	return {
		"turns_played": state.turn,
		"max_turns": int(config["max_turns"]),
		"seed": state.rng_seed,
		"flags": state.flags.keys(),
		"memories": state.memories.duplicate(true),
	}


func _present_next_event() -> void:
	var is_final_turn: bool = state.turn >= int(config["max_turns"])
	var picked: Dictionary = _events.pick_next(state, _rng, get_current_act(), is_final_turn)
	if picked.is_empty():
		push_warning("더 나올 사건이 없어 임기를 일찍 마칩니다. 일반 사건 수를 늘려야 합니다.")
		_finish(_endings.resolve_term_end(state))
		return
	state.seen_events[picked["id"]] = state.turn
	state.recent_tags.append(picked["tags"])
	if state.recent_tags.size() > RECENT_TAGS_KEEP:
		state.recent_tags.pop_front()
	_pending_event = _for_display(picked)
	_queue_event_talk(picked)
	_continue_to_event()


## 사건 앞 대화를 쌓는다.
##   1) 처음 등장하는 인물들의 자기소개 (안건을 올린 인물, 왼쪽·오른쪽을 지지하는 인물)
##   2) 안건 소개: 안건을 올린 인물이 보이고, 대화창에는 사건 제목과 설명
##   3) 왼쪽을 지지하는 인물의 한마디 → 4) 오른쪽을 지지하는 인물의 한마디
## 대화(data/dialogue/)가 없는 사건은 자기소개만 하고 바로 질문으로 간다.
func _queue_event_talk(event: Dictionary) -> void:
	var debate := _debate_for(event)
	var speakers: Array = [String(event["npc"])]
	if not debate.is_empty():
		speakers.append_array([debate["left"]["npc"], debate["right"]["npc"]])
	for npc_id in speakers:
		_queue_introduction(npc_id)
	if debate.is_empty():
		return
	var shown: Dictionary = _pending_event
	var topic := _dialogue(String(event["npc"]), String(event["npc_expression"]), shown["description"], "topic")
	topic["event_title"] = shown["title"]   # 화면 위쪽 제목
	_dialogue_queue.append(topic)
	for side in SIDES:
		var line := _dialogue(debate[side]["npc"], "neutral", debate[side]["line"], "argument")
		line["side"] = side
		line["event_title"] = shown["title"]
		_dialogue_queue.append(line)


func _debate_for(event: Dictionary) -> Dictionary:
	return data.get("debates", {}).get(String(event["id"]), {})


## 대사가 남아 있으면 한 줄 보여 주고, 다 끝났으면 기다리던 사건을 보여 준다.
func _continue_to_event() -> void:
	if not _dialogue_queue.is_empty():
		current_dialogue = _dialogue_queue.pop_front()
		_awaiting_proceed = true
		dialogue_presented.emit(current_dialogue)
		return
	current_dialogue = {}
	current_event = _pending_event
	_pending_event = {}
	event_presented.emit(current_event, get_hints())


## 새 판 시작 때 안내원의 첫 인사 (story.json의 opening). 안내원은 이것으로 처음 만난 셈이 된다.
func _queue_opening() -> void:
	var opening: Dictionary = data.get("story", {}).get("opening", {})
	var npc_id := String(opening.get("npc", ""))
	for line in opening.get("lines", []):
		_dialogue_queue.append(_dialogue(npc_id, String(line.get("expression", "neutral")), String(line.get("text", "")), "opening"))
	if not npc_id.is_empty():
		state.met_npcs[npc_id] = state.turn


## 인물이 이번 판에서 처음 등장하면 자기소개 대사를 사건 앞에 넣는다. (한 판에 한 번)
func _queue_introduction(npc_id: String) -> void:
	if npc_id.is_empty() or state.met_npcs.has(npc_id) or not _npcs.has(npc_id):
		return
	state.met_npcs[npc_id] = state.turn
	for line in _npcs[npc_id]["intro"]:
		_dialogue_queue.append(_dialogue(npc_id, "happy", line, "intro"))


func _dialogue(npc_id: String, expression: String, text: String, kind: String) -> Dictionary:
	return {"npc": _npcs.get(npc_id, {}), "expression": expression, "text": text, "kind": kind}


## 화면용 사건: 과거 선택에 맞는 대사로 바꾸고, 등장인물 정보를 붙인다. (원본 데이터는 바꾸지 않는다)
func _for_display(event: Dictionary) -> Dictionary:
	var shown := event.duplicate()
	shown["linked_to_past"] = event["category"] == "delayed"
	for variant in event["description_variants"]:
		if Conditions.check_all(variant["conditions"], state):
			shown["description"] = variant["text"]
			shown["linked_to_past"] = true
			break
	shown["npc_info"] = _npcs.get(event["npc"], {})
	return shown


## 선택지 미리 보기(인물 카드)용: {"npc": 그 선택지를 지지하는 인물, "expression": 카드 표정, "text": 선택지 문구}
## 찬반 대화가 있는 사건은 각 쪽 지지자가 밝은 얼굴(happy)로 나온다.
func get_side_preview(side: String) -> Dictionary:
	var choice: Dictionary = current_event[side + "_choice"]
	var npc := _npc_for(current_event, side)
	# 찬반 지지자는 자기 의견을 내미는 쪽이라 밝은 표정(happy → 그림은 delight)
	var expression := "happy" if not _debate_for(current_event).is_empty() \
		else _expression_for(npc, choice, Effects.preview_levels(choice, config))
	return {"npc": npc, "expression": expression, "text": choice["text"]}


## 그 선택지의 인물: 선택지의 npc → 대화(data/dialogue/)의 그쪽 지지자 → 사건의 인물 순서.
func _npc_for(event: Dictionary, side: String) -> Dictionary:
	var npc_id := String(event[side + "_choice"]["npc"])
	if npc_id.is_empty():
		npc_id = String(_debate_for(event).get(side, {}).get("npc", ""))
	if npc_id.is_empty():
		npc_id = String(event["npc"])
	return _npcs.get(npc_id, {})


## 선택지에 reaction_expression이 있으면 그것, 없으면 그 인물이 신경 쓰는 상태(concern)의 변화로 정한다.
##   오르면 happy, 조금 내리면 worried, 크게 내리면 angry, 그대로면 neutral
func _expression_for(npc: Dictionary, choice: Dictionary, levels: Dictionary) -> String:
	if not String(choice["reaction_expression"]).is_empty():
		return choice["reaction_expression"]
	if npc.is_empty():
		return "neutral"
	var level := int(levels.get(npc["concern"], 0))
	if level > 0:
		return "happy"
	if level <= -2:
		return "angry"
	if level < 0:
		return "worried"
	return "neutral"


## 선택 직후 인물의 반응: {"npc_id", "npc", "expression", "text"}. 인물이 없으면 빈 Dictionary.
## 반응하는 인물은 고른 쪽을 지지한 인물이다.
##   찬반 대화가 있는 사건: 자기 의견이 받아들여졌으므로 기쁜 얼굴. (그 인물이 사건의 인물이고
##     선택지에 reaction이 적혀 있으면 그 대사와 표정을 쓴다)
##   대화가 없는 사건: 선택지의 reaction / reaction_expression, 없으면 인물이 신경 쓰는 상태의 변화로 표정을 정한다.
## 대사가 비면 그 인물의 표정별 기본 대사 중 하나 (같은 사건·같은 선택이면 항상 같은 대사)
func _reaction_for(event: Dictionary, side: String, choice: Dictionary, changes: Dictionary) -> Dictionary:
	var npc := _npc_for(event, side)
	if npc.is_empty():
		return {}
	var custom_applies := _debate_for(event).is_empty() or String(npc["id"]) == String(event["npc"])
	var expression := _expression_for(npc, choice, changes) if custom_applies else "happy"
	if not _debate_for(event).is_empty() and String(choice["reaction_expression"]).is_empty():
		expression = "happy"
	var text: String = choice["reaction"] if custom_applies else ""
	if text.is_empty():
		var lines: Dictionary = npc["lines"]
		var options: Array = lines.get(expression, lines.get("neutral", []))
		if not options.is_empty():
			text = options[absi(hash(String(event["id"]) + side)) % options.size()]
	return {"npc_id": npc["id"], "npc": npc, "expression": expression, "text": text}


## 이 턴이 끝날 때 보여 줄 중간 결산. 없으면 빈 Dictionary.
func _checkpoint_for_turn(turn: int) -> Dictionary:
	var story: Dictionary = data.get("story", {})
	for checkpoint in story.get("checkpoints", []):
		if int(checkpoint["after_turn"]) != turn:
			continue
		var lines: Array = []
		var stat_lines: Dictionary = story.get("stat_lines", {})
		for stat_id in config["stat_order"]:
			var line := _stat_line(stat_lines.get(stat_id, []), int(state.stats[stat_id]))
			if not line.is_empty():
				lines.append(line)
		var memories: Array = []
		for memory in state.memories:
			if int(memory["turn"]) > turn - int(checkpoint.get("recall_turns", 10)):
				memories.append(memory["text"])
		return {
			"title": checkpoint["title"],
			"intro": checkpoint["intro"],
			"lines": lines,
			"memories": memories.slice(-int(checkpoint.get("recall_count", 3))),
		}
	return {}


## 상태값에 맞는 문장. bands는 [{"max": 30, "text": ...}, ...] (max 오름차순, 처음 맞는 것)
func _stat_line(bands: Array, value: int) -> String:
	for band in bands:
		if value <= int(band["max"]):
			return band["text"]
	return ""


## 상태별 실제 변화의 방향과 강도 (±1 / ±2). 변하지 않은 상태는 빠진다.
func _stat_levels(before: Dictionary, after: Dictionary) -> Dictionary:
	var levels := {}
	for stat_id in config["stat_order"]:
		var delta := int(after[stat_id]) - int(before.get(stat_id, 0))
		if delta != 0:
			levels[stat_id] = Effects.level_of(delta, config)
	return levels


func _finish(result: Dictionary) -> void:
	ending = result if not result.is_empty() else FALLBACK_ENDING
	current_event = {}
	current_checkpoint = {}
	game_ended.emit(ending, get_summary())
