extends RefCounted
## 선택지 효과를 상태에 적용한다.
##
## 선택지 형식 (DataLoader가 정리한 뒤):
##   {"text": String, "effects": {stat_id: int},
##    "set_flags": [{"flag": String, "chance": float}], "clear_flags": [String]}
##
## 설정 파일의 effect_scale로 상태별 증가/감소 폭을 한꺼번에 조절할 수 있다. (밸런싱용)


static func scaled_delta(stat_id: String, delta: int, config: Dictionary) -> int:
	var scale: Dictionary = config["effect_scale"].get(stat_id, {})
	var factor: float = scale.get("gain" if delta > 0 else "loss", 1.0)
	return int(round(delta * factor))


static func apply_choice(state, choice: Dictionary, config: Dictionary, rng: RandomNumberGenerator) -> void:
	var before: Dictionary = state.stats
	state.stats = preview_stats(before, choice, config)
	for stat_id in state.stats:
		if int(state.stats[stat_id]) > int(before.get(stat_id, 0)):
			state.raised_count[stat_id] = int(state.raised_count.get(stat_id, 0)) + 1
	for entry in choice["set_flags"]:
		var chance: float = entry["chance"]
		if chance >= 1.0 or rng.randf() < chance:
			state.set_flag(entry["flag"])
	for flag in choice["clear_flags"]:
		state.clear_flag(flag)


## 효과를 적용한 뒤의 상태값을 계산한다. 원본은 바꾸지 않는다.
static func preview_stats(stats: Dictionary, choice: Dictionary, config: Dictionary) -> Dictionary:
	var result := stats.duplicate()
	var effects: Dictionary = choice["effects"]
	for stat_id in effects:
		if not result.has(stat_id):
			continue
		var delta := scaled_delta(stat_id, int(effects[stat_id]), config)
		result[stat_id] = clampi(int(result[stat_id]) + delta, int(config["stat_min"]), int(config["stat_max"]))
	return result


## 힌트용: 상태별 방향과 강도. 정확한 숫자 대신 이것만 화면에 보여 준다.
##   1 = 조금 오름(↑), 2 = 크게 오름(↑↑), -1 = 조금 내림(↓), -2 = 크게 내림(↓↓)
## 변화가 없는 상태는 빠진다. 키 순서는 설정 파일의 상태 순서를 따른다.
static func preview_levels(choice: Dictionary, config: Dictionary) -> Dictionary:
	var levels := {}
	var effects: Dictionary = choice["effects"]
	for stat_id in config["stat_order"]:
		var delta := scaled_delta(stat_id, int(effects.get(stat_id, 0)), config)
		if delta != 0:
			levels[stat_id] = level_of(delta, config)
	return levels


## 변화량 → 강도 단계. 설정의 strong_effect 이상이면 "크게".
static func level_of(delta: int, config: Dictionary) -> int:
	var strength := 2 if absi(delta) >= int(config["strong_effect"]) else 1
	return strength * signi(delta)
