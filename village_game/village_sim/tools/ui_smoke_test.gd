extends SceneTree
## 화면 흐름 점검 도구. 실제 메인 씬을 띄우고 버튼을 자동으로 눌러
## "사건 → 선택 → 결과 → 다음 … → 엔딩 화면 → 다시 시작"이 여러 판 동안 문제없이 도는지 확인한다.
##
## 실행 (프로젝트 폴더에서):
##   godot --headless --script res://village_sim/tools/ui_smoke_test.gd

const MAIN_SCENE := "res://village_sim/scenes/main/main.tscn"
const GAMES := 5
const MAX_CLICKS_PER_GAME := 100


func _initialize() -> void:
	var main = load(MAIN_SCENE).instantiate()
	root.add_child(main)
	_run.call_deferred(main)


func _run(main) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for game in GAMES:
		var clicks := 0
		while main._screen.has_method("setup") and clicks < MAX_CLICKS_PER_GAME:
			var screen = main._screen
			var first := "left" if rng.randf() < 0.5 else "right"
			var second := first if rng.randf() < 0.7 else ("right" if first == "left" else "left")
			screen.select_side(first)                   # 미리 보기
			if second != first:
				screen.select_side(second)              # 반대쪽 미리 보기로 바꾸기
			screen.select_side(second)                  # 결정
			clicks += 1
			if not screen.is_showing_result() or String(screen._body_label.text).is_empty():
				printerr("실패: %d번째 판 %d번째 선택 뒤 결과 카드가 나오지 않았습니다." % [game + 1, clicks])
				quit(1)
				return
			screen.advance()
		var ending_screen = main._screen
		if not ending_screen.has_method("show_ending"):
			printerr("실패: %d번째 판이 %d번 눌러도 끝나지 않았습니다." % [game + 1, clicks])
			quit(1)
			return
		print("%d번째 판: %d번 선택 → [%s] %s" % [game + 1, clicks, ending_screen._title_label.text, ending_screen._summary_label.text])
		await process_frame
		ending_screen.restart_requested.emit()
		await process_frame
	print("화면 흐름 점검 통과")
	quit(0)
