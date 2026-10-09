extends SceneTree
## 실행: godot --headless --path <village_game> --script res://village_sim/tools/ai_lab_smoke_test.gd

const DataLoader = preload("res://village_sim/scripts/data/data_loader.gd")
const Runner = preload("res://village_sim/scripts/ai/training_runner.gd")

func _init() -> void:
	var data: Dictionary = DataLoader.new().load_all()
	assert(data.get("load_errors", []).is_empty(), "JSON 데이터 읽기 실패")
	var trainer = Runner.new(data)
	var base: Dictionary = trainer.play("random", 30001, false, 0, false, "normal")
	var treasury: Dictionary = trainer.play("random", 30001, false, 0, false, "treasury")
	var dual: Dictionary = trainer.play("random", 30001, false, 0, false, "dual")
	assert(base.has("score") and treasury.has("score") and dual.has("score"), "미션별 점수 누락")
	assert(trainer.trained == 0, "실전 시험이 학습 횟수를 변경함")
	for env in ["normal", "treasury", "mixed", "final"]:
		trainer.reset()
		trainer.configure(env, "balance")
		trainer.train_until(20)
		assert(trainer.trained == 20, "20판 훈련 실패")
		trainer.train_until(50)
		assert(trainer.trained == 50, "50판 훈련 실패")
		trainer.train_until(100)
		assert(trainer.trained == 100, "100판 훈련 실패")
		var results: Dictionary = trainer.evaluate("dual")
		for policy in ["random", "rule", "trained"]:
			var result: Dictionary = results[policy]
			assert(result["runs"] == 120, "평가 횟수 불일치")
			assert(result["completion"] >= 0.0 and result["completion"] <= 100.0, "완주율 이상")
		assert(trainer.trained == 100, "평가가 훈련 상태를 변경함")
		print("훈련 환경 %s / 복합 위기: 무작위 %.1f, 규칙 %.1f, 학습 %.1f" % [env, results["random"]["score"], results["rule"]["score"], results["trained"]["score"]])
		var watch: Dictionary = trainer.watch_example("treasury")
		assert(not watch["decisions"].is_empty(), "관전 기록 없음")
	trainer.configure("mixed", "rescue")
	assert(trainer.trained == 100, "환경 변경 시 학습 결과가 사라지면 안 됨")
	trainer.train_until(120)
	trainer.configure("normal", "survival")
	assert(trainer.trained == 120, "보상 변경 시 학습 결과가 사라지면 안 됨")
	print("AI 훈련소: 미션 · 혼합 훈련 · 보상 정책 · 평가 · 관전 테스트 완료")
	quit()
