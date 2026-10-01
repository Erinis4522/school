extends RefCounted
## 다음 사건을 고른다.
##
## 규칙
##   0) 마지막 턴에는 최종 사건(final) 중 조건이 맞고 priority가 가장 높은 것을 낸다.
##   1) 조건을 만족하는 조건부 사건(state / delayed)이 있으면,
##      그중 priority가 가장 높은 사건들 사이에서 weight로 추첨한다.
##      단, 지연 사건은 현재 막의 follow_up_chance 확률로만 후보가 된다. (1막은 낮게 → 결과가 2막에 몰려 돌아옴)
##   2) 없으면 현재 막(phases)에 속한 일반 사건 중 weight로 추첨한다.
##      최근에 나온 사건과 태그가 겹치면 weight를 낮춰 비슷한 주제가 연달아 나오지 않게 한다.
##      현재 막의 일반 사건이 바닥나면 다른 막의 일반 사건을 쓴다.
##   모든 사건은 한 판에 한 번만 나온다.
##   위기(구제) 사건(태그 crisis_tag)은 한 판에 crisis_limit번까지만 나온다. 상태가 바닥날 때마다 구해 주지는 않는다.

const Conditions = preload("res://village_sim/scripts/core/condition_evaluator.gd")

var _general: Array = []
var _conditional: Array = []
var _final: Array = []
var _recent_tag_window: int
var _recent_tag_weight: float
var _crisis_tag: String
var _crisis_limit: int


func _init(events: Array, selection_config: Dictionary) -> void:
	for event in events:
		match String(event["category"]):
			"general":
				_general.append(event)
			"final":
				_final.append(event)
			_:
				_conditional.append(event)
	_recent_tag_window = int(selection_config["recent_tag_window"])
	_recent_tag_weight = float(selection_config["recent_tag_weight"])
	_crisis_tag = String(selection_config.get("crisis_tag", "crisis"))
	_crisis_limit = int(selection_config.get("crisis_limit", -1))


## act: 설정의 막 정보 {"id", "name", "from", "to", "follow_up_chance"}
func pick_next(state, rng: RandomNumberGenerator, act: Dictionary, is_final_turn: bool) -> Dictionary:
	if is_final_turn:
		var final_event := _pick_top_priority(_final, state, rng)
		if not final_event.is_empty():
			return final_event
	var event := pick_conditional(state, rng, act)
	if event.is_empty():
		event = pick_general(state, rng, act)
	return event


func pick_conditional(state, rng: RandomNumberGenerator, act: Dictionary) -> Dictionary:
	var allow_delayed := rng.randf() < float(act.get("follow_up_chance", 1.0))
	var allow_crisis := _crisis_limit < 0 or _crisis_count(state) < _crisis_limit
	var candidates: Array = []
	for event in _conditional:
		if event["category"] == "delayed" and not allow_delayed:
			continue
		if not allow_crisis and _crisis_tag in event["tags"]:
			continue
		candidates.append(event)
	return _pick_top_priority(candidates, state, rng)


## 이번 판에 이미 나온 위기(구제) 사건 수
func _crisis_count(state) -> int:
	var count := 0
	for event in _conditional:
		if _crisis_tag in event["tags"] and state.seen_events.has(event["id"]):
			count += 1
	return count


func pick_general(state, rng: RandomNumberGenerator, act: Dictionary) -> Dictionary:
	var recent := {}
	if _recent_tag_window > 0:
		for tags in state.recent_tags.slice(-_recent_tag_window):
			for tag in tags:
				recent[tag] = true
	var act_id := String(act.get("id", ""))
	var in_act: Array = []
	var any_act: Array = []
	for event in _general:
		if state.seen_events.has(event["id"]):
			continue
		any_act.append(event)
		if act_id in event["phases"]:
			in_act.append(event)
	var candidates := in_act if not in_act.is_empty() else any_act
	return _weighted_pick(candidates, func(event): return _general_weight(event, recent), rng)


## 아직 안 나왔고 조건을 만족하는 사건 중 priority가 가장 높은 것들에서 weight로 추첨.
func _pick_top_priority(events: Array, state, rng: RandomNumberGenerator) -> Dictionary:
	var best_priority: int = 0
	var candidates: Array = []
	for event in events:
		if state.seen_events.has(event["id"]):
			continue
		if not Conditions.check_all(event["conditions"], state):
			continue
		var priority: int = event["priority"]
		if candidates.is_empty() or priority > best_priority:
			best_priority = priority
			candidates = [event]
		elif priority == best_priority:
			candidates.append(event)
	return _weighted_pick(candidates, func(event): return float(event["weight"]), rng)


func _general_weight(event: Dictionary, recent_tags: Dictionary) -> float:
	var weight := float(event["weight"])
	for tag in event["tags"]:
		if recent_tags.has(tag):
			return weight * _recent_tag_weight
	return weight


func _weighted_pick(items: Array, weight_of: Callable, rng: RandomNumberGenerator) -> Dictionary:
	if items.is_empty():
		return {}
	var weights: Array[float] = []
	var total := 0.0
	for item in items:
		var weight: float = maxf(0.0, weight_of.call(item))
		weights.append(weight)
		total += weight
	if total <= 0.0:
		return items[rng.randi_range(0, items.size() - 1)]
	var roll := rng.randf() * total
	for i in items.size():
		roll -= weights[i]
		if roll < 0.0:
			return items[i]
	return items[items.size() - 1]
