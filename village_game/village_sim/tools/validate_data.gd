extends SceneTree
## 사건·엔딩 데이터 검증 도구. 게임을 켜지 않고 데이터만 검사한다.
##
## 실행 (프로젝트 폴더에서):
##   godot --headless --script res://village_sim/tools/validate_data.gd
## 오류가 있으면 종료 코드 1을 돌려준다.

const DataLoader = preload("res://village_sim/scripts/data/data_loader.gd")
const DataValidator = preload("res://village_sim/scripts/data/data_validator.gd")


func _init() -> void:
	var data: Dictionary = DataLoader.new().load_all()
	var report: Dictionary = DataValidator.validate(data)
	DataValidator.print_report(report, true)
	quit(1 if not report["errors"].is_empty() else 0)
