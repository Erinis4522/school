extends RefCounted
## 한 판의 진행을 관리한다.
##
## 한 턴의 흐름: 사건 제시 → choose("left" / "right") → 결과 제시 → proceed() → 다음 사건 (또는 엔딩)
## UI는 신호를 받아 화면에 보여주고, 플레이어 입력은 choose()와 proceed()로만 전달한다.
## 밸런스 시뮬레이터도 이 클래스를 화면 없이 그대로 사용한다.

signal event_presented(event: Dictionary, hints: Dictionary)
signal choice_resolved(result: Dictionary)
signal stats_changed(ratios: Dictionary)
signal game_ended(ending: Dictionary, summary: Dictionary)

const GameState = preload("res://village_sim/scripts/core/game_state.gd")
const Effects = preload("res://village_sim/scripts/core/effect_manager.gd")
const EventManager = preload("res://village_sim/scripts/core/event_manager.gd")
const EndingResolver = preload("res://village_sim/scripts/core/ending_resolver.gd")

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
var ending: Dictionary = {}

var _rng := RandomNumberGenerator.new()
var _awaiting_proceed := false
var _pending_ending: Dictionary = {}
var _events
var _endings


func _init(game_data: Dictionary) -> void:
	data = game_data
	config = game_data["config"]
	_events = EventManager.new(game_data["events"], config["selection"])
	_endings = EndingResolver.new(game_data["endings"])


## 새 판을 시작한다. run_seed를 주면 같은 사건 흐름을 재현할 수 있다.
func start(run_seed: int = -1) -> void:
	state = GameState.new()
	state.rng_seed = run_seed if run_seed >= 0 else randi()
	_rng.seed = state.rng_seed
	for stat in config["stats"]:
		state.stats[stat["id"]] = int(stat["initial"])
	current_event = {}
	last_result = {}
	ending = {}
	_awaiting_proceed = false
	_pending_ending = {}
	stats_changed.emit(get_stat_ratios())
	_present_next_event()


func is_over() -> bool:
	return not ending.is_empty()


## 선택 후 결과를 보여 주는 중인지. 이때는 proceed()로만 넘어간다.
func is_showing_result() -> bool:
	return _awaiting_proceed


func choose(side: String) -> void:
	if is_over() or _awaiting_proceed or current_event.is_empty() or not (side in SIDES):
		return
	var choice: Dictionary = current_event[side + "_choice"]
	var before: Dictionary = state.stats.duplicate()
	Effects.apply_choice(state, choice, config, _rng)
	state.choice_log.append({"turn": state.turn, "event_id": current_event["id"], "side": side})

	# 이번 턴으로 판이 끝나는지는 지금 정해 두고, 결과를 보여 준 뒤 proceed()에서 엔딩으로 넘어간다.
	_pending_ending = _endings.check_collapse(state)
	if _pending_ending.is_empty() and state.turn >= int(config["max_turns"]):
		_pending_ending = _endings.resolve_term_end(state)
		if _pending_ending.is_empty():
			_pending_ending = FALLBACK_ENDING

	last_result = {
		"event": current_event,
		"side": side,
		"choice_text": choice["text"],
		"text": choice["result"],
		"changes": _stat_directions(before, state.stats),
	}
	_awaiting_proceed = true
	stats_changed.emit(get_stat_ratios())
	choice_resolved.emit(last_result)


## 결과를 확인하고 다음 사건(또는 엔딩)으로 넘어간다.
func proceed() -> void:
	if not _awaiting_proceed:
		return
	_awaiting_proceed = false
	if not _pending_ending.is_empty():
		_finish(_pending_ending)
		return
	state.turn += 1
	_present_next_event()


## 선택했을 때의 상태값을 미리 계산한다. (시뮬레이터용. 화면에는 쓰지 않는다)
func preview_choice(side: String) -> Dictionary:
	return Effects.preview_stats(state.stats, current_event[side + "_choice"], config)


## 현재 사건의 좌/우 선택지가 건드리는 상태 목록.
func get_hints() -> Dictionary:
	var hints := {}
	for side in SIDES:
		hints[side] = Effects.affected_stats(current_event[side + "_choice"], config["stat_order"])
	return hints


## UI용 0.0~1.0 비율. 정확한 숫자는 UI에 넘기지 않는다.
func get_stat_ratios() -> Dictionary:
	var low := float(config["stat_min"])
	var high := float(config["stat_max"])
	var ratios := {}
	for stat_id in state.stats:
		ratios[stat_id] = (float(state.stats[stat_id]) - low) / (high - low)
	return ratios


func get_summary() -> Dictionary:
	return {
		"turns_played": state.turn,
		"max_turns": int(config["max_turns"]),
		"seed": state.rng_seed,
		"flags": state.flags.keys(),
	}


func _present_next_event() -> void:
	current_event = _events.pick_next(state, _rng)
	if current_event.is_empty():
		push_warning("더 나올 사건이 없어 임기를 일찍 마칩니다. 일반 사건 수를 늘려야 합니다.")
		_finish(_endings.resolve_term_end(state))
		return
	state.seen_events[current_event["id"]] = state.turn
	state.recent_tags.append(current_event["tags"])
	if state.recent_tags.size() > RECENT_TAGS_KEEP:
		state.recent_tags.pop_front()
	event_presented.emit(current_event, get_hints())


## 상태별로 오름(1) / 내림(-1)만 돌려준다. 변하지 않은 상태는 빠진다. 크기는 알려 주지 않는다.
func _stat_directions(before: Dictionary, after: Dictionary) -> Dictionary:
	var directions := {}
	for stat_id in after:
		var delta := int(after[stat_id]) - int(before.get(stat_id, 0))
		if delta != 0:
			directions[stat_id] = signi(delta)
	return directions


func _finish(result: Dictionary) -> void:
	ending = result if not result.is_empty() else FALLBACK_ENDING
	current_event = {}
	game_ended.emit(ending, get_summary())
