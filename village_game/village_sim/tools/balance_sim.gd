extends SceneTree
## 밸런스 시뮬레이터. 여러 전략으로 많은 판을 화면 없이 돌려 결과를 요약한다.
##
## 실행 (프로젝트 폴더에서):
##   godot --headless --script res://village_sim/tools/balance_sim.gd -- --runs=1000
## 결과: 콘솔 출력 + <프로젝트 폴더>/balance_reports/ 에 마크다운 파일로 저장
##
## 전략
##   random       : 무작위로 고른다 (생각 없이 누르는 플레이어)
##   always_left  : 항상 왼쪽
##   always_right : 항상 오른쪽
##   careful      : 선택 직후 가장 낮은 상태가 가장 높게 남는 쪽을 고른다 (생각하며 고르는 플레이어)
##                  지연 사건은 내다보지 못하므로 눈앞만 보는 신중한 플레이어에 가깝다.

const DataLoader = preload("res://village_sim/scripts/data/data_loader.gd")
const GameSession = preload("res://village_sim/scripts/core/game_session.gd")

const STRATEGIES: Array[String] = ["random", "always_left", "always_right", "careful"]
const DEFAULT_RUNS := 500
const DOMINANT_RATIO := 0.9   # careful 전략이 한쪽을 이 비율 이상 고르면 "정답 의심"
const MIN_SAMPLES := 30       # 이보다 적게 나온 사건은 판단하지 않는다
const REPORT_DIR := "res://balance_reports"

var _decision_rng := RandomNumberGenerator.new()


func _init() -> void:
	var runs := _read_int_arg("runs", DEFAULT_RUNS)
	var data: Dictionary = DataLoader.new().load_all()
	var config: Dictionary = data["config"]

	var titles := {}
	var categories := {}
	for event in data["events"]:
		titles[event["id"]] = event["title"]
		categories[event["id"]] = event["category"]
	var ending_titles := {}
	for ending in data["endings"]:
		ending_titles[ending["id"]] = ending["title"]

	var results := {}
	for strategy in STRATEGIES:
		results[strategy] = _simulate(data, strategy, runs)

	var lines: Array[String] = []
	lines.append("# 밸런스 시뮬레이션 결과")
	lines.append("")
	lines.append("- 일시: %s" % Time.get_datetime_string_from_system(false, true))
	lines.append("- 전략마다 %d판 / 최대 %d턴 / 전략끼리 같은 시드 사용" % [runs, config["max_turns"]])
	lines.append("")
	lines.append_array(_section_summary(results))
	lines.append_array(_section_endings(results, ending_titles))
	lines.append_array(_section_final_stats(results, config))
	lines.append_array(_section_dominant(results["careful"], titles))
	lines.append_array(_section_conditional_frequency(results["random"], titles, categories, runs))
	lines.append_array(_section_general_frequency(results["random"], categories, runs))

	var text := "\n".join(PackedStringArray(lines))
	print(text)
	_save_report(text)
	quit()


# --- 시뮬레이션 --------------------------------------------------------------------

func _simulate(data: Dictionary, strategy: String, runs: int) -> Dictionary:
	var session = GameSession.new(data)
	_decision_rng.seed = hash(strategy)
	var result := {
		"runs": runs,
		"completed": 0,
		"turns_total": 0,
		"endings": {},
		"final_stats_sum": {},
		"conditional_total": 0,
		"long_streak_runs": 0,
		"event_seen": {},
		"choices": {},
	}
	for i in runs:
		session.start(i + 1)
		var streak := 0
		var max_streak := 0
		while not session.is_over():
			var event: Dictionary = session.current_event
			var is_conditional: bool = event["category"] != "general"
			streak = streak + 1 if is_conditional else 0
			max_streak = maxi(max_streak, streak)
			if is_conditional:
				result["conditional_total"] += 1
			_count(result["event_seen"], event["id"])

			var side := _decide(session, strategy)
			if not result["choices"].has(event["id"]):
				result["choices"][event["id"]] = {"left": 0, "right": 0}
			result["choices"][event["id"]][side] += 1
			session.choose(side)
			session.proceed()

		var ending: Dictionary = session.ending
		_count(result["endings"], ending["id"])
		result["turns_total"] += session.state.turn
		if max_streak >= 3:
			result["long_streak_runs"] += 1
		if ending["type"] == "term_end":
			result["completed"] += 1
			for stat_id in session.state.stats:
				result["final_stats_sum"][stat_id] = int(result["final_stats_sum"].get(stat_id, 0)) + int(session.state.stats[stat_id])
	return result


func _decide(session, strategy: String) -> String:
	match strategy:
		"always_left":
			return "left"
		"always_right":
			return "right"
		"careful":
			var left_score := _careful_score(session.preview_choice("left"))
			var right_score := _careful_score(session.preview_choice("right"))
			if left_score != right_score:
				return "left" if left_score > right_score else "right"
	return "left" if _decision_rng.randf() < 0.5 else "right"


## 가장 낮은 상태를 가장 중요하게, 그다음 전체 합을 본다.
func _careful_score(stats: Dictionary) -> int:
	var lowest := 1 << 30
	var total := 0
	for stat_id in stats:
		lowest = mini(lowest, int(stats[stat_id]))
		total += int(stats[stat_id])
	return lowest * 1000 + total


# --- 보고서 ------------------------------------------------------------------------

func _section_summary(results: Dictionary) -> Array[String]:
	var lines: Array[String] = ["## 요약", "", "| 전략 | 임기 완주율 | 평균 진행 턴 | 판당 조건부 사건 | 조건부 3연속 이상 나온 판 |", "|---|---|---|---|---|"]
	for strategy in STRATEGIES:
		var r: Dictionary = results[strategy]
		var runs := float(r["runs"])
		lines.append("| %s | %s | %.1f | %.1f | %s |" % [
			strategy, _pct(r["completed"], runs), r["turns_total"] / runs,
			r["conditional_total"] / runs, _pct(r["long_streak_runs"], runs)])
	lines.append("")
	return lines


func _section_endings(results: Dictionary, ending_titles: Dictionary) -> Array[String]:
	var header := "| 엔딩 |"
	var divider := "|---|"
	for strategy in STRATEGIES:
		header += " %s |" % strategy
		divider += "---|"
	var lines: Array[String] = ["## 엔딩 분포", "", header, divider]
	for ending_id in ending_titles:
		var row := "| %s (%s) |" % [ending_titles[ending_id], ending_id]
		for strategy in STRATEGIES:
			var r: Dictionary = results[strategy]
			row += " %s |" % _pct(r["endings"].get(ending_id, 0), float(r["runs"]))
		lines.append(row)
	lines.append("")
	return lines


func _section_final_stats(results: Dictionary, config: Dictionary) -> Array[String]:
	var header := "| 전략 |"
	var divider := "|---|"
	for stat in config["stats"]:
		header += " %s |" % stat["name"]
		divider += "---|"
	var lines: Array[String] = ["## 임기를 마친 판의 평균 최종 상태 (개발용 수치)", "", header, divider]
	for strategy in STRATEGIES:
		var r: Dictionary = results[strategy]
		var row := "| %s |" % strategy
		for stat in config["stats"]:
			if r["completed"] > 0:
				row += " %.1f |" % (float(r["final_stats_sum"].get(stat["id"], 0)) / r["completed"])
			else:
				row += " - |"
		lines.append(row)
	lines.append("")
	return lines


func _section_dominant(careful: Dictionary, titles: Dictionary) -> Array[String]:
	var lines: Array[String] = [
		"## 정답 의심 사건",
		"",
		"careful 전략이 %d%% 이상 한쪽만 고른 사건 (%d번 이상 나온 사건만). 눈앞의 효과만 본 결과이므로, 지연 사건으로 균형을 맞춘 사건은 괜찮을 수 있다." % [int(DOMINANT_RATIO * 100), MIN_SAMPLES],
		"",
		"| 사건 | 고른 쪽 | 비율 | 표본 |",
		"|---|---|---|---|",
	]
	var count := 0
	for event_id in careful["choices"]:
		var picks: Dictionary = careful["choices"][event_id]
		var total: int = picks["left"] + picks["right"]
		if total < MIN_SAMPLES:
			continue
		var left_ratio := float(picks["left"]) / total
		if left_ratio >= DOMINANT_RATIO or left_ratio <= 1.0 - DOMINANT_RATIO:
			var side := "왼쪽" if left_ratio >= 0.5 else "오른쪽"
			lines.append("| %s (%s) | %s | %s | %d |" % [titles.get(event_id, "?"), event_id, side, _pct(maxf(left_ratio, 1.0 - left_ratio), 1.0), total])
			count += 1
	if count == 0:
		lines.append("| (없음) | | | |")
	lines.append("")
	return lines


func _section_conditional_frequency(random_result: Dictionary, titles: Dictionary, categories: Dictionary, runs: int) -> Array[String]:
	var lines: Array[String] = ["## 조건부 사건 등장률 (random 전략)", "", "| 사건 | 종류 | 등장률 |", "|---|---|---|"]
	var ids: Array = []
	for event_id in categories:
		if categories[event_id] != "general":
			ids.append(event_id)
	ids.sort_custom(func(a, b): return int(random_result["event_seen"].get(a, 0)) > int(random_result["event_seen"].get(b, 0)))
	for event_id in ids:
		lines.append("| %s (%s) | %s | %s |" % [titles[event_id], event_id, categories[event_id], _pct(random_result["event_seen"].get(event_id, 0), float(runs))])
	lines.append("")
	return lines


func _section_general_frequency(random_result: Dictionary, categories: Dictionary, runs: int) -> Array[String]:
	var low := INF
	var high := 0.0
	var total := 0.0
	var count := 0
	for event_id in categories:
		if categories[event_id] != "general":
			continue
		var rate := float(random_result["event_seen"].get(event_id, 0)) / runs
		low = minf(low, rate)
		high = maxf(high, rate)
		total += rate
		count += 1
	var lines: Array[String] = ["## 일반 사건 등장률 (random 전략)", ""]
	if count > 0:
		lines.append("- 사건 %d개, 판당 평균 %.1f개 등장" % [count, total])
		lines.append("- 사건별 등장률: 최저 %s / 평균 %s / 최고 %s" % [_pct(low, 1.0), _pct(total / count, 1.0), _pct(high, 1.0)])
	lines.append("")
	return lines


# --- 도우미 ------------------------------------------------------------------------

func _count(counter: Dictionary, key: String) -> void:
	counter[key] = int(counter.get(key, 0)) + 1


func _pct(value: float, total: float) -> String:
	if total <= 0.0:
		return "-"
	return "%.1f%%" % (value / total * 100.0)


func _read_int_arg(key: String, default_value: int) -> int:
	var prefix := "--%s=" % key
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.substr(prefix.length()).to_int()
	return default_value


func _save_report(text: String) -> void:
	var dir := ProjectSettings.globalize_path(REPORT_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	var stamp := Time.get_datetime_string_from_system(false, false).replace(":", "-")
	var path := dir.path_join("balance_%s.md" % stamp)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("보고서를 저장하지 못했습니다: %s" % path)
		return
	file.store_string(text)
	file.close()
	print("\n보고서 저장: %s" % path)
