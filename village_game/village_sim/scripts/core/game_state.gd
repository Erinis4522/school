extends RefCounted
## 한 판 동안의 마을 상태.
## 순수 데이터 객체이며 노드나 UI에 의존하지 않는다.

var stats: Dictionary = {}          # stat_id -> int
var flags: Dictionary = {}          # 플래그 이름 -> 켜진 턴
var turn: int = 1                   # 지금 진행 중인 턴 (1부터 시작)
var seen_events: Dictionary = {}    # event_id -> 등장한 턴
var choice_log: Array = []          # [{turn, event_id, side}]
var recent_tags: Array = []         # 최근 등장한 사건들의 태그 목록 (가장 최근이 마지막)
var rng_seed: int = 0


func has_flag(flag: String) -> bool:
	return flags.has(flag)


## 플래그가 켜진 뒤 지난 턴 수. 꺼져 있으면 -1.
func flag_age(flag: String) -> int:
	if not flags.has(flag):
		return -1
	return turn - int(flags[flag])


## 이미 켜져 있으면 처음 켜진 턴을 유지한다.
func set_flag(flag: String) -> void:
	if not flags.has(flag):
		flags[flag] = turn


func clear_flag(flag: String) -> void:
	flags.erase(flag)


func to_dict() -> Dictionary:
	return {
		"stats": stats.duplicate(),
		"flags": flags.duplicate(),
		"turn": turn,
		"seen_events": seen_events.duplicate(),
		"choice_log": choice_log.duplicate(true),
		"rng_seed": rng_seed,
	}
