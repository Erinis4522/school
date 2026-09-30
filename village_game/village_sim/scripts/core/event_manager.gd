extends RefCounted
## 다음 사건을 고른다.
##
## 규칙
##   1) 조건을 만족하는 조건부 사건(state / delayed)이 있으면,
##      그중 priority가 가장 높은 사건들 사이에서 weight로 추첨한다.
##   2) 없으면 일반 사건 중 weight로 추첨한다.
##      최근에 나온 사건과 태그가 겹치면 weight를 낮춰 비슷한 주제가 연달아 나오지 않게 한다.
##   모든 사건은 한 판에 한 번만 나온다.

const Conditions = preload("res://village_sim/scripts/core/condition_evaluator.gd")

var _general: Array = []
var _conditional: Array = []
var _recent_tag_window: int
var _recent_tag_weight: float


func _init(events: Array, selection_config: Dictionary) -> void:
	for event in events:
		if event["category"] == "general":
			_general.append(event)
		else:
			_conditional.append(event)
	_recent_tag_window = int(selection_config["recent_tag_window"])
	_recent_tag_weight = float(selection_config["recent_tag_weight"])


func pick_next(state, rng: RandomNumberGenerator) -> Dictionary:
	var event := pick_conditional(state, rng)
	if event.is_empty():
		event = pick_general(state, rng)
	return event


func pick_conditional(state, rng: RandomNumberGenerator) -> Dictionary:
	var best_priority: int = 0
	var candidates: Array = []
	for event in _conditional:
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


func pick_general(state, rng: RandomNumberGenerator) -> Dictionary:
	var recent := {}
	if _recent_tag_window > 0:
		for tags in state.recent_tags.slice(-_recent_tag_window):
			for tag in tags:
				recent[tag] = true
	var candidates: Array = []
	for event in _general:
		if not state.seen_events.has(event["id"]):
			candidates.append(event)
	return _weighted_pick(candidates, func(event): return _general_weight(event, recent), rng)


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
