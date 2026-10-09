extends SceneTree
## Godot headless 실행: godot --headless --path <village_game> --script res://village_sim/tools/ai_deck_smoke_test.gd

const DataLoader = preload("res://village_sim/scripts/data/data_loader.gd")
const Runner = preload("res://village_sim/scripts/ai/training_runner.gd")
const DeckRules = preload("res://village_sim/scripts/ai/deck_rules.gd")

func _init() -> void:
	var data: Dictionary = DataLoader.new().load_all()
	assert(data.get("load_errors", []).is_empty(), "게임 데이터 읽기 실패")
	assert(DeckRules.is_valid(["finance", "crisis", "balance"]), "카드 3장 검증 실패")
	assert(not DeckRules.is_valid(["finance", "finance", "balance"]), "중복 카드 차단 실패")
	var before := {"residents": 50, "finance": 40, "environment": 55, "safety": 50}
	var after := {"residents": 48, "finance": 52, "environment": 55, "safety": 50}
	var finance_bonus: float = DeckRules.extra_reward(["finance", "balance", "explore"], before, after, false, false)
	var environment_bonus: float = DeckRules.extra_reward(["environment", "balance", "explore"], before, after, false, false)
	assert(finance_bonus > environment_bonus, "자원 카드 보상이 결과와 무관함")
	var trainer = Runner.new(data)
	trainer.reset()
	trainer.set_deck(["finance", "crisis", "balance"])
	trainer.configure("normal", "balance")
	trainer.train_until(8)
	assert(trainer.trained == 8, "훈련 횟수 오류")
	var original_weights := trainer.agent.weights.duplicate()
	trainer.set_deck(["environment", "careful", "explore"])
	assert(trainer.agent.weights == original_weights, "카드 변경만으로 학습 결과가 변하면 안 됨")
	trainer.train_until(16)
	assert(trainer.trained == 16, "추가 학습 실패")
	assert(trainer.agent.weights != original_weights, "추가 학습 후 가중치 변화 없음")
	# 최종 과제(폭풍의 마을)에서도 추가 훈련이 가능하며 기존 학습은 유지된다.
	trainer.configure("final", "balance")
	assert(trainer.training_environment == "final", "폭풍의 마을 훈련 환경 선택 실패")
	trainer.train_until(20)
	assert(trainer.trained == 20, "폭풍의 마을 추가 학습 실패")
	var evaluation: Dictionary = trainer.evaluate("final")
	assert(evaluation["trained"]["runs"] == 10, "최종 시험 횟수 오류")
	assert(evaluation["trained"]["failure_causes"].has("finance"), "실패 원인 집계 누락")
	assert(evaluation["trained"].has("risky_counts"), "위기 선택 기록 누락")
	print("AI 덱 테스트 통과: 카드 효과, 기존 학습 유지, 추가 훈련, 실패 분석")
	quit()
