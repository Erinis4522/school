extends RefCounted
## 엔딩 판정.
##
## collapse : 매 턴 효과를 적용한 직후 검사한다.
##            여러 개가 동시에 맞으면 해당 상태값이 더 낮은 쪽, 같으면 priority가 높은 쪽이 나온다.
## term_end : 마지막 턴을 마친 뒤 검사한다. priority가 높은 것부터 확인해 처음 맞는 엔딩이 나온다.
##            조건 없는 기본 엔딩이 반드시 하나 있어야 한다. (DataValidator가 확인)

const Conditions = preload("res://village_sim/scripts/core/condition_evaluator.gd")

var _collapse: Array = []
var _term_end: Array = []


func _init(endings: Array) -> void:
	for ending in endings:
		if ending["type"] == "collapse":
			_collapse.append(ending)
		elif ending["type"] == "term_end":
			_term_end.append(ending)
	_term_end.sort_custom(func(a, b): return a["priority"] > b["priority"])


func check_collapse(state) -> Dictionary:
	var matched: Array = []
	for ending in _collapse:
		if Conditions.check_all(ending["conditions"], state):
			matched.append(ending)
	if matched.is_empty():
		return {}
	matched.sort_custom(func(a, b): return _collapse_first(a, b, state))
	return matched[0]


func resolve_term_end(state) -> Dictionary:
	for ending in _term_end:
		if Conditions.check_all(ending["conditions"], state):
			return ending
	return {}


func _collapse_first(a: Dictionary, b: Dictionary, state) -> bool:
	var value_a := int(state.stats.get(a["stat"], 0))
	var value_b := int(state.stats.get(b["stat"], 0))
	if value_a != value_b:
		return value_a < value_b
	return a["priority"] > b["priority"]
