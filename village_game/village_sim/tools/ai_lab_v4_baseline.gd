extends SceneTree
## 실행: godot --headless --path . --script res://village_sim/tools/ai_lab_v4_baseline.gd
## 난이도 2단계 실제 완주율: 무작위와 규칙 기반 각각 1000판
const DataLoader = preload("res://village_sim/scripts/data/data_loader.gd")
const Runner = preload("res://village_sim/scripts/ai/training_runner.gd")

func _init() -> void:
	var data: Dictionary = DataLoader.new().load_all()
	var runner = Runner.new(data)
	for scenario in ["normal", "treasury", "dual"]:
		for mode in ["random", "rule"]:
			var completed := 0
			for i in range(1000):
				var trial: Dictionary = runner.play(mode, 80000 + i, false, 0.0, false, scenario)
				if trial["completed"]:
					completed += 1
			print("scenario=%s mode=%s runs=1000 completion=%.1f%%" % [scenario, mode, completed / 10.0])
	quit()
