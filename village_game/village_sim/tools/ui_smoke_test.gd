extends SceneTree
## 화면 흐름 점검 도구. 실제 메인 씬을 띄우고 버튼을 자동으로 눌러
## "타이틀 → 새 게임 → 첫 인사 → 사건 → 선택 → 결과 → 다음 … → 엔딩 화면 → 다시 시작"이
## 여러 판 동안 문제없이 도는지 확인한다.
##
## 실행 (프로젝트 폴더에서):
##   godot --headless --script res://village_sim/tools/ui_smoke_test.gd

const MAIN_SCENE := "res://village_sim/scenes/main/main.tscn"
const GAMES := 5
const MAX_STEPS_PER_GAME := 300


func _initialize() -> void:
	var main = load(MAIN_SCENE).instantiate()
	root.add_child(main)
	_run.call_deferred(main)


func _run(main) -> void:
	await process_frame
	if not main._screen.has_signal("new_game_requested"):
		_fail("첫 화면이 타이틀 화면이 아닙니다.")
		return
	main._screen.new_game_requested.emit()   # 타이틀의 "새 게임"
	await process_frame

	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for game in GAMES:
		var choices := 0
		var checkpoints := 0
		var dialogues := 0
		var steps := 0
		while main._screen.has_method("setup") and steps < MAX_STEPS_PER_GAME:
			steps += 1
			var screen = main._screen
			if screen.is_showing_dialogue():
				dialogues += 1
				screen.advance()
				continue
			if screen.is_showing_checkpoint():
				checkpoints += 1
				screen.advance()
				continue
			var first := "left" if rng.randf() < 0.5 else "right"
			var second := first if rng.randf() < 0.7 else ("right" if first == "left" else "left")
			screen.select_side(first)                   # 인물 카드 펼치기
			if second != first:
				screen.select_side(second)              # 반대쪽 카드로 바꾸기
			screen.select_side(second)                  # 결정
			choices += 1
			if not screen.is_showing_result() or String(screen._sub_label.text).is_empty():
				_fail("%d번째 판 %d번째 선택 뒤 결과 카드가 나오지 않았습니다." % [game + 1, choices])
				return
			if not screen._stage.visible:
				_fail("%d번째 판 %d번째 선택 뒤 인물이 가운데 카드에 나오지 않았습니다." % [game + 1, choices])
				return
			screen.advance()
		var ending_screen = main._screen
		if not ending_screen.has_method("show_ending"):
			_fail("%d번째 판이 끝나지 않았습니다." % (game + 1))
			return
		if dialogues == 0:
			_fail("%d번째 판에 첫 인사·자기소개 대사가 하나도 없었습니다." % (game + 1))
			return
		print("%d번째 판: 선택 %d번, 대사 %d줄, 중간 결산 %d번 → [%s] %s" % [game + 1, choices, dialogues, checkpoints, ending_screen._title_label.text, ending_screen._summary_label.text])
		await process_frame
		ending_screen.restart_requested.emit()
		await process_frame
	print("화면 흐름 점검 통과")
	quit(0)


func _fail(message: String) -> void:
	printerr("실패: " + message)
	quit(1)
