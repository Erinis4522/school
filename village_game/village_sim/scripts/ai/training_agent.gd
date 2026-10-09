extends RefCounted
## 교육용 선형 Q-learning 에이전트.
## 선택 전에 공개되는 힌트(변화의 방향/강도)와 현재 상태만 관찰한다.
## 사건 JSON의 정답 effects / 미래 사건은 읽지 않는다.

const SIDES: Array[String] = ["left", "right"]
const STAT_IDS: Array[String] = ["residents", "finance", "environment", "safety"]
const LEARNING_RATE := 0.035
const DISCOUNT := 0.88
const FEATURE_COUNT := 9

var weights: Array[float] = []


func _init() -> void:
	reset()


func reset() -> void:
	weights.clear()
	for _i in FEATURE_COUNT:
		weights.append(0.0)


## 행동마다 같은 9개 특징: 방향 편향(1) + 네 상태의 예상 변화(4) + 부족 자원 가중 변화(4)
func features(session, side: String) -> Array[float]:
	var result: Array[float] = [1.0 if side == "left" else -1.0]
	var all_hints: Dictionary = session.get_hints()
	var hint: Dictionary = all_hints.get(side, {})
	for stat_id in STAT_IDS:
		var level := float(hint.get(stat_id, 0)) / 2.0
		result.append(level)
	for stat_id in STAT_IDS:
		var level := float(hint.get(stat_id, 0)) / 2.0
		var shortage := clampf((100.0 - float(session.state.stats.get(stat_id, 50))) / 100.0, 0.0, 1.0)
		result.append(level * shortage * shortage * 2.0)
	return result


func value(session, side: String) -> float:
	return _dot(features(session, side))


func choose(session, epsilon: float, rng: RandomNumberGenerator) -> String:
	if rng.randf() < epsilon:
		return SIDES[rng.randi_range(0, 1)]
	var left := value(session, "left")
	var right := value(session, "right")
	if absf(left - right) < 0.00001:
		return SIDES[rng.randi_range(0, 1)]
	return "left" if left > right else "right"


## Q(s,a) <- Q(s,a) + alpha * (보상 + 감가된 다음 상태의 최선 가치 - Q(s,a))
func learn(previous_features: Array[float], reward: float, next_session, finished: bool) -> void:
	var predicted := _dot(previous_features)
	var next_best := 0.0
	if not finished:
		next_best = maxf(value(next_session, "left"), value(next_session, "right"))
	var error := clampf(reward + DISCOUNT * next_best - predicted, -35.0, 35.0)
	for i in FEATURE_COUNT:
		weights[i] = clampf(weights[i] + LEARNING_RATE * error * previous_features[i], -30.0, 30.0)


func _dot(values: Array[float]) -> float:
	var sum := 0.0
	for i in FEATURE_COUNT:
		sum += values[i] * weights[i]
	return sum


## 과거 체크포인트에 저장된 실제 가중치로 동일 사건의 예상 행동 가치 재계산.
func value_from_features(saved_weights: Array, saved_features: Array) -> float:
	var total := 0.0
	for i in mini(saved_weights.size(), saved_features.size()):
		total += float(saved_weights[i]) * float(saved_features[i])
	return total


## AI의 설명은 자연어 추측이 아니라 특징 × 학습 가중치의 실제 기여도.
func explain_features(saved_features: Array) -> Array:
	var labels := ["방향 자체의 편향", "주민 변화 힌트", "재정 변화 힌트", "환경 변화 힌트", "안전 변화 힌트", "부족한 주민 고려", "부족한 재정 고려", "부족한 환경 고려", "부족한 안전 고려"]
	var result: Array = []
	for i in FEATURE_COUNT:
		result.append({"name": labels[i], "effect": weights[i] * saved_features[i]})
	result.sort_custom(func(a, b): return absf(a["effect"]) > absf(b["effect"]))
	return result
