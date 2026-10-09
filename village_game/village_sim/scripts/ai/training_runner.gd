extends RefCounted
## 기존 GameSession을 사용하는 교육용 강화학습. 본편과 같은 고정 2단계 난이도를 쓴다.
## 훈련 환경 / 보상 정책 / 시험 환경을 별도로 선택해 일반화를 탐구한다.

const GameSession = preload("res://village_sim/scripts/core/game_session.gd")
const TrainingAgent = preload("res://village_sim/scripts/ai/training_agent.gd")
const DeckRules = preload("res://village_sim/scripts/ai/deck_rules.gd")
const STAT_IDS: Array[String] = ["residents", "finance", "environment", "safety"]
const MAX_MOVES := 45
const EVALUATION_EPISODES := 120
const FINAL_EVALUATION_EPISODES := 10 # 학생 과제: 새로운 미션에서 10판 모두 완주
const MAX_TRAIN_EPISODES := 1000
const SCENARIOS := ["normal", "treasury", "dual"]

var data: Dictionary
var agent
var trained: int = 0
var training_history: Array = []
var training_environment := "normal"  # normal / treasury / mixed / final
var reward_policy := "balance" # 구버전 호환용
var deck: Array = ["finance", "crisis", "balance"]
var last_trained_deck: Array = []
var _scenario_cache: Dictionary = {}
var weight_snapshots: Array = []
var _rng := RandomNumberGenerator.new()


func _init(game_data: Dictionary) -> void:
	data = game_data
	agent = TrainingAgent.new()


## 학습 환경과 보상 정책의 변경은 기존 가중치/학습 횟수에 영향을 주지 않는다.
## 변경된 설정은 다음 훈련 판부터 적용한다. 초기화는 reset()을 명시적으로 호출할 때만 한다.
func configure(environment: String, policy: String) -> void:
	training_environment = environment if environment in ["normal", "treasury", "mixed", "final"] else "normal"
	reward_policy = policy if policy in ["balance", "rescue", "survival"] else "balance"


func set_deck(selected: Array) -> void:
	if DeckRules.is_valid(selected):
		deck = selected.duplicate()


func deck_name() -> String:
	return DeckRules.names(deck)


func restore_ai(saved: Dictionary) -> void:
	if not saved.has("weights"):
		return
	agent.weights.clear()
	for value in saved["weights"]:
		agent.weights.append(float(value))
	trained = int(saved.get("trained", 0))
	deck = saved.get("deck", DeckRules.DEFAULT_DECK).duplicate()
	last_trained_deck = deck.duplicate()
	training_history.clear()
	weight_snapshots.clear()
	weight_snapshots.append({"trained": trained, "weights": agent.weights.duplicate()})


func reset() -> void:
	agent.reset()
	trained = 0
	training_history.clear()
	last_trained_deck.clear()
	weight_snapshots.clear()
	weight_snapshots.append({"trained": 0, "weights": agent.weights.duplicate()})


## 기존 학습을 이어간다. 학습량 선택과 무관하게 탐색률은 실제 누적 판수에 따라 감소한다.
func train_until(target: int) -> void:
	for episode in range(trained, clampi(target, 0, MAX_TRAIN_EPISODES)):
		var epsilon := 0.06 + 0.32 * exp(-float(episode) / 140.0)
		if "explore" in deck:
			epsilon = minf(0.65, epsilon + 0.20)
		var scenario := training_environment
		if training_environment == "mixed":
			scenario = String(SCENARIOS[episode % SCENARIOS.size()])
		var result := play("trained", episode + 1, true, epsilon, false, scenario)
		training_history.append(result)
		trained += 1
		last_trained_deck = deck.duplicate()
	weight_snapshots.append({"trained": trained, "weights": agent.weights.duplicate()})


func weights_at(index: int) -> Dictionary:
	if index < 0 or index >= weight_snapshots.size():
		return {}
	return weight_snapshots[index]


## 모든 전략에 동일한 120개 평가 시드를 사용. 선택에 따라 이후 사건은 달라질 수 있다.
## 시험 환경을 바꾸어도 훈련된 가중치는 바뀌지 않는다.
func evaluate(scenario: String = "normal") -> Dictionary:
	var result := {}
	for mode in ["random", "rule", "trained"]:
		var samples: Array = []
		var sample_count := FINAL_EVALUATION_EPISODES if scenario == "final" else EVALUATION_EPISODES
		for i in sample_count:
			samples.append(play(mode, 20001 + i, false, 0.0, false, scenario))
		result[mode] = _summarize(samples)
	return result


func watch_example(scenario: String = "normal") -> Dictionary:
	return play("trained", 39991, false, 0.0, true, scenario)


func play(mode: String, run_seed: int, learning: bool = false, epsilon: float = 0.0, trace: bool = false, scenario: String = "normal") -> Dictionary:
	var session = GameSession.new(_data_for_scenario(scenario))
	var salt := 41
	if mode == "trained":
		salt = 17
	elif mode == "rule":
		salt = 29
	_rng.seed = int(run_seed * 17117 + salt)
	session.start(run_seed)
	_advance(session)
	var decisions: Array = []
	var risky_choices: Array = []
	var risky_counts := {"residents": 0, "finance": 0, "environment": 0, "safety": 0}
	var moves := 0
	while not session.is_over() and moves < MAX_MOVES:
		if session.current_event.is_empty():
			break
		var event: Dictionary = session.current_event
		var side := _pick(session, mode, epsilon)
		var decision_record: Dictionary = {}
		if trace and decisions.size() < 12:
			decision_record = _decision_details(session, moves + 1, side)
		var saved_features: Array[float] = []
		if learning:
			saved_features = agent.features(session, side)
		var before: Dictionary = session.state.stats.duplicate()
		var chosen_text: String = String(event[side + "_choice"]["text"])
		session.choose(side)
		var after: Dictionary = session.state.stats.duplicate()
		# 위기에 처한 자원에서 실제로 손실이 발생한 선택을 기록한다.
		# 실패 원인과 직접적으로 같다고 단정하지 않고, 재훈련 단서로만 제시한다.
		for stat_id in STAT_IDS:
			if float(before[stat_id]) <= 40.0 and float(after[stat_id]) <= float(before[stat_id]) - 3.0:
				risky_counts[stat_id] = int(risky_counts[stat_id]) + 1
				if risky_choices.size() < 2:
					risky_choices.append({"stat": stat_id, "event": String(event.get("title", "")), "choice": chosen_text, "before": before[stat_id], "after": after[stat_id]})
		_advance(session)
		var finished: bool = session.is_over()
		var reward := (_quality(after) - _quality(before)) * 0.35
		if learning:
			var is_success: bool = finished and String(session.ending.get("type", "")) == "term_end"
			reward += DeckRules.extra_reward(deck, before, after, finished, is_success)
		if finished:
			reward += 8.0 if String(session.ending.get("type", "")) == "term_end" else -_failure_penalty()
		if learning:
			agent.learn(saved_features, reward, session, finished)
		if not decision_record.is_empty():
			decision_record["after"] = after.duplicate()
			decision_record["reward"] = reward
			decision_record["choice"] = chosen_text
			decisions.append(decision_record)
		moves += 1
	var stats: Dictionary = session.state.stats
	var low := 100.0
	var high := 0.0
	var total := 0.0
	for stat_id in STAT_IDS:
		var value := float(stats.get(stat_id, 0))
		low = minf(low, value)
		high = maxf(high, value)
		total += value
	var completed: bool = session.is_over() and String(session.ending.get("type", "")) == "term_end"
	var collapsed_stat := ""
	if not completed:
		for stat_id in STAT_IDS:
			if float(stats.get(stat_id, 1)) <= 0.0:
				collapsed_stat = stat_id
				break
	# 시험 점수는 훈련 보상과 분리하여 고정. 설정을 바꿔도 비교 척도는 동일하다.
	var fixed_score := 0.55 * low + 0.45 * total / 4.0 - 0.20 * (high - low) + (12.0 if completed else -12.0)
	return {
		"completed": completed, "turns": moves, "lowest": low,
		"mean": total / 4.0, "gap": high - low, "stats": stats.duplicate(),
		"finance": float(stats.get("finance", 0)), "environment": float(stats.get("environment", 0)),
		"score": fixed_score, "decisions": decisions,
		"collapsed_stat": collapsed_stat, "risky_choices": risky_choices, "risky_counts": risky_counts,
		"ending": String(session.ending.get("title", "중단")),
	}


func _data_for_scenario(scenario: String) -> Dictionary:
	if _scenario_cache.has(scenario):
		return _scenario_cache[scenario]
	# 본편과 동일한 초기 상태·하락 배율을 사용한다. 위기 미션은 초기값만 더 낮춘다.
	var copy := data.duplicate()
	var cfg: Dictionary = data["config"].duplicate(true)
	var stat_list: Array = cfg["stats"]
	for entry in stat_list:
		var stat_id := String(entry["id"])
		var base := int(entry["initial"])
		if scenario == "treasury" and stat_id == "finance":
			base = 28
		elif scenario == "dual":
			if stat_id == "finance":
				base = 35
			elif stat_id == "environment":
				base = 30
		elif scenario == "final":
			# 마지막 과제용 위기: 직접 훈련 환경으로 선택할 수도 있다.
			base = int({"residents": 42, "finance": 30, "environment": 33, "safety": 36}.get(stat_id, base))
		entry["initial"] = base
	# 폭풍의 마을에서는 손실을 조금 더 키운다. 연습과 시험 모두 같은 환경을 사용한다.
	# 본편과 다른 훈련 마을의 데이터는 변경하지 않는다.
	if scenario == "final":
		var scaling: Dictionary = cfg["effect_scale"].duplicate(true)
		for stat_id in STAT_IDS:
			var stat_scaling: Dictionary = scaling.get(stat_id, {}).duplicate()
			stat_scaling["loss"] = float(stat_scaling.get("loss", 1.0)) * 1.10
			scaling[stat_id] = stat_scaling
		cfg["effect_scale"] = scaling
	copy["config"] = cfg
	_scenario_cache[scenario] = copy
	return copy


## 실제 AI가 선택 순간에 사용한 정보만 저장한다. 사건의 숨겨진 효과는 포함하지 않는다.
func _decision_details(session, turn_id: int, chosen_side: String) -> Dictionary:
	var event: Dictionary = session.current_event
	var left_features: Array[float] = agent.features(session, "left")
	var right_features: Array[float] = agent.features(session, "right")
	return {
		"turn": turn_id, "event": String(event.get("title", "")),
		"left_text": String(event["left_choice"]["text"]),
		"right_text": String(event["right_choice"]["text"]),
		"before": session.state.stats.duplicate(),
		"hints": session.get_hints().duplicate(true),
		"side": chosen_side,
		"q_left": agent.value_from_features(agent.weights, left_features),
		"q_right": agent.value_from_features(agent.weights, right_features),
		"features_left": left_features,
		"features_right": right_features,
		"contributions": agent.explain_features(left_features if chosen_side == "left" else right_features),
	}


func _pick(session, mode: String, epsilon: float) -> String:
	if mode == "trained":
		return agent.choose(session, epsilon, _rng)
	if mode == "rule":
		var hints: Dictionary = session.get_hints()
		var scores := {}
		for side in ["left", "right"]:
			var hint: Dictionary = hints.get(side, {})
			var value := 0.0
			for stat_id in STAT_IDS:
				var shortage := (100.0 - float(session.state.stats[stat_id])) / 100.0
				value += float(hint.get(stat_id, 0)) * (0.5 + shortage * shortage * 3.0)
			scores[side] = value
		if absf(float(scores["left"]) - float(scores["right"])) > 0.00001:
			return "left" if float(scores["left"]) > float(scores["right"]) else "right"
	return "left" if _rng.randf() < 0.5 else "right"


func _quality(stats: Dictionary) -> float:
	var low := 100.0
	var high := 0.0
	var total := 0.0
	for stat_id in STAT_IDS:
		var x := float(stats.get(stat_id, 0))
		low = minf(low, x)
		high = maxf(high, x)
		total += x
	var w := 0.60
	var gap_penalty := 0.16
	if reward_policy == "rescue":
		w = 0.85
		gap_penalty = 0.07
	elif reward_policy == "survival":
		w = 0.30
		gap_penalty = 0.07
	return w * low + (1.0 - w) * total / 4.0 - gap_penalty * (high - low)


func _failure_penalty() -> float:
	if reward_policy == "rescue":
		return 22.0
	if reward_policy == "survival":
		return 32.0
	return 15.0


## 실제 훈련 정책을 '구체적인 정책 선택과 판단의 한계'로 설명한다.
## 원인을 지어내지 않고, 관전 중 실제 선택과 학습된 가중치에 대한 반사실적 시험만 보여 준다.
func learning_report(evaluation: Dictionary, scenario: String = "normal") -> String:
	if trained == 0:
		return "아직 배운 것이 없어요. 먼저 몇 판 연습시켜 보세요."
	var lines: Array[String] = []
	var observed: Dictionary = watch_example(scenario)
	var example: Dictionary = _interesting_decision(observed.get("decisions", []))
	if not example.is_empty():
		var chosen_side: String = String(example["side"])
		lines.append("[b]AI가 실제로 고른 선택[/b]")
		lines.append("‘%s’ 사건에서 ‘%s’을(를) 선택했어요." % [_safe_text(String(example["event"])), _safe_text(String(example["choice"]))])
		lines.append("그 결과: %s" % _actual_change(example["before"], example["after"]))
		var other_conditions: Dictionary = _most_informative_counterfactual(example)
		if not other_conditions.is_empty():
			lines.append("\n[b]마을 사정이 바뀌면?[/b]")
			lines.append("%s이(가) 부족할 때: %s" % [other_conditions["a_name"], other_conditions["first_choice"]])
			lines.append("%s이(가) 부족할 때: %s" % [other_conditions["b_name"], other_conditions["second_choice"]])
			lines.append("부족한 자원이 달라지자 선택도 달라졌어요." if other_conditions["flip"] else "부족한 자원이 바뀌어도 같은 선택을 했어요. 다른 방법을 배울 필요가 있을까요?")
	var a: Dictionary = evaluation.get("trained", {})
	var b: Dictionary = evaluation.get("random", {})
	if not a.is_empty() and not b.is_empty():
		lines.append("\n[b]연습이 도움이 되었을까요?[/b]")
		lines.append("무작위보다 완주율 %+.0f%%p, 마을 점수 %+.1f점" % [float(a["completion"]) - float(b["completion"]), float(a["score"]) - float(b["score"])])
		lines.append("점수가 올랐다고 모든 문제를 해결한 건 아니에요." if float(a["score"]) > float(b["score"]) else "아직 무작위보다 좋은 결과가 나오지 않았어요. 연습 방법을 바꿔 보세요.")
	return "\n".join(PackedStringArray(lines))


func _safe_text(value: String) -> String:
	# RichTextLabel의 BBCode 제어 문자 때문에 게임 데이터 문구가 깨지는 것을 방지한다.
	return value.replace("[", "(").replace("]", ")")


func _signal_description(hints: Dictionary) -> String:
	var raised: Array[String] = []
	var lowered: Array[String] = []
	for stat_id in STAT_IDS:
		var level: int = int(hints.get(stat_id, 0))
		var name := _stat_name(stat_id)
		if level > 0:
			raised.append(name)
		elif level < 0:
			lowered.append(name)
	var fragments: Array[String] = []
	if not raised.is_empty():
		fragments.append("%s 개선" % "·".join(PackedStringArray(raised)))
	if not lowered.is_empty():
		fragments.append("%s 악화" % "·".join(PackedStringArray(lowered)))
	return ", ".join(PackedStringArray(fragments)) if not fragments.is_empty() else "뚜렷한 변화 없음"


func _actual_change(before: Dictionary, after: Dictionary) -> String:
	var parts: Array[String] = []
	for stat_id in STAT_IDS:
		var diff: int = int(after.get(stat_id, 0)) - int(before.get(stat_id, 0))
		if diff != 0:
			parts.append("%s %s%d" % [_stat_name(stat_id), "+" if diff > 0 else "", diff])
	return " · ".join(PackedStringArray(parts)) if not parts.is_empty() else "네 상태 모두 변화 없음"


func _stat_name(id: String) -> String:
	match id:
		"residents": return "주민"
		"finance": return "재정"
		"environment": return "환경"
		"safety": return "안전"
	return id


func _interesting_decision(decisions: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_score := -1000
	for candidate in decisions:
		var entry: Dictionary = candidate
		var chosen: Dictionary = entry.get("hints", {}).get(String(entry.get("side", "left")), {})
		var gains := 0
		var losses := 0
		for stat_id in STAT_IDS:
			var hint := int(chosen.get(stat_id, 0))
			if hint > 0: gains += 1
			if hint < 0: losses += 1
		var score := (12 if gains > 0 and losses > 0 else 0) + gains + losses
		if score > best_score:
			best = entry
			best_score = score
	return best


func _probe_value(case: Dictionary, stats: Dictionary, side: String) -> float:
	# TrainingAgent.features()와 동일한 9개 입력식을 사용한다.
	var features: Array[float] = [1.0 if side == "left" else -1.0]
	var signals: Dictionary = case["hints"].get(side, {})
	for stat_id in STAT_IDS:
		features.append(float(signals.get(stat_id, 0)) / 2.0)
	for stat_id in STAT_IDS:
		var level: float = float(signals.get(stat_id, 0)) / 2.0
		var shortage: float = clampf((100.0 - float(stats.get(stat_id, 50))) / 100.0, 0.0, 1.0)
		features.append(level * shortage * shortage * 2.0)
	return agent.value_from_features(agent.weights, features)


func _probe_choice(case: Dictionary, stats: Dictionary) -> String:
	var a: float = _probe_value(case, stats, "left")
	var b: float = _probe_value(case, stats, "right")
	if absf(a - b) < 0.00001:
		return "동점(무작위 선택)"
	return "왼쪽 정책" if a > b else "오른쪽 정책"


func _most_informative_counterfactual(case: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := -1.0
	for a in range(STAT_IDS.size()):
		for b in range(a + 1, STAT_IDS.size()):
			var first: Dictionary = case["before"].duplicate()
			var second: Dictionary = first.duplicate()
			first[STAT_IDS[a]] = 15
			first[STAT_IDS[b]] = 80
			second[STAT_IDS[a]] = 80
			second[STAT_IDS[b]] = 15
			var v1: float = _probe_value(case, first, "left") - _probe_value(case, first, "right")
			var v2: float = _probe_value(case, second, "left") - _probe_value(case, second, "right")
			var flip: bool = (v1 > 0.00001 and v2 < -0.00001) or (v1 < -0.00001 and v2 > 0.00001)
			var distance: float = absf(v1 - v2) + (100.0 if flip else 0.0)
			if distance > best_distance:
				best_distance = distance
				best = {"a_name": _stat_name(STAT_IDS[a]), "b_name": _stat_name(STAT_IDS[b]), "first_choice": _probe_choice(case, first), "second_choice": _probe_choice(case, second), "flip": flip}
	return best


func _advance(session) -> void:
	for _i in 250:
		if session.is_over():
			return
		if session.is_showing_dialogue() or session.is_showing_checkpoint() or session.is_showing_result():
			session.proceed()
			continue
		if not session.current_event.is_empty():
			return
		return


func _summarize(samples: Array) -> Dictionary:
	var completed := 0
	var lowest := 0.0
	var mean := 0.0
	var gap := 0.0
	var turns := 0.0
	var finance := 0.0
	var environment := 0.0
	var score := 0.0
	var failure_causes := {"residents": 0, "finance": 0, "environment": 0, "safety": 0, "unknown": 0}
	var risky_counts := {"residents": 0, "finance": 0, "environment": 0, "safety": 0}
	var examples: Array = []
	for sample in samples:
		completed += 1 if sample["completed"] else 0
		lowest += float(sample["lowest"])
		mean += float(sample["mean"])
		gap += float(sample["gap"])
		turns += float(sample["turns"])
		finance += float(sample["finance"])
		environment += float(sample["environment"])
		score += float(sample["score"])
		if not bool(sample["completed"]):
			var cause: String = String(sample.get("collapsed_stat", ""))
			if cause.is_empty():
				cause = "unknown"
			failure_causes[cause] = int(failure_causes.get(cause, 0)) + 1
		if not bool(sample["completed"]):
			for stat_id in STAT_IDS:
				risky_counts[stat_id] = int(risky_counts[stat_id]) + int(sample.get("risky_counts", {}).get(stat_id, 0))
		if examples.size() < 3 and not sample["completed"]:
			for risk in sample.get("risky_choices", []):
				if examples.size() < 3:
					examples.append(risk)
	var n := maxf(1.0, float(samples.size()))
	return {"runs": samples.size(), "completed": completed, "completion": 100.0 * completed / n,
		"lowest": lowest / n, "mean": mean / n, "gap": gap / n, "turns": turns / n,
		"finance": finance / n, "environment": environment / n, "score": score / n,
		"failure_causes": failure_causes, "risky_counts": risky_counts, "risk_examples": examples}
