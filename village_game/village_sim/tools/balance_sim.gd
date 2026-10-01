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
##   lowest_first : 지금 가장 낮은 상태를 더 올리는(덜 내리는) 쪽을 고른다. 같으면 careful과 같게 고른다.
##                  (게이지만 보고 "제일 낮은 것부터 챙기는" 플레이어)
##
## 보고서에는 전략별 결과 외에, 사건 데이터만 보고 계산한 효과 구조(비용 없는 선택, 한쪽이 모든 면에서 나은 사건,
## 상태별로 "비용"으로 쓰이는 빈도)도 함께 적는다.

const DataLoader = preload("res://village_sim/scripts/data/data_loader.gd")
const GameSession = preload("res://village_sim/scripts/core/game_session.gd")

const STRATEGIES: Array[String] = ["random", "careful", "always_left", "always_right", "lowest_first"]
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
	lines.append_array(_section_failures(results, config))
	lines.append_array(_section_endings(results, ending_titles))
	lines.append_array(_section_final_stats(results, config))
	lines.append_array(_section_final_stats_all(results, config))
	lines.append_array(_section_stat_course(results, config))
	lines.append_array(_section_crisis(results, titles))
	lines.append_array(_section_sides(results))
	lines.append_array(_section_dominant(results["careful"], titles))
	lines.append_array(_section_effect_structure(data, config, titles))
	lines.append_array(_section_conditional_frequency(results["random"], titles, categories, runs))
	lines.append_array(_section_general_frequency(results["random"], categories, runs))
	lines.append_array(_section_acts(results, config))

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
		"act_turns": {},       # 막 id -> 진행된 턴 수
		"act_follow_ups": {},  # 막 id -> 지연 사건이 나온 턴 수
		"act_linked": {},      # 막 id -> 지난 선택과 이어진 턴 수 (지연 사건 + 과거 선택에 따른 대사)
		"checkpoints": 0,
		"final_stats_all": {},  # 끝난 판 전체(중도 실패 포함)의 마지막 상태 합
		"stat_at": {},          # 턴 -> {stat_id -> 합, "count" -> 그 턴까지 살아남은 판 수}
		"crisis_seen": {},      # 위기 사건 id -> 나온 횟수
		"crisis_runs": 0,       # 위기 사건이 한 번 이상 나온 판
	}
	for i in runs:
		session.start(i + 1)
		var streak := 0
		var max_streak := 0
		var had_crisis := false
		while not session.is_over():
			if session.is_showing_dialogue() or session.is_showing_checkpoint():
				session.proceed()   # 첫 인사·자기소개 대사, 중간 결산은 넘긴다
				continue
			var event: Dictionary = session.current_event
			var is_conditional: bool = event["category"] != "general"
			streak = streak + 1 if is_conditional else 0
			max_streak = maxi(max_streak, streak)
			if is_conditional:
				result["conditional_total"] += 1
			_count(result["event_seen"], event["id"])
			var act_id := String(session.get_current_act().get("id", "?"))
			_count(result["act_turns"], act_id)
			if event["category"] == "delayed":
				_count(result["act_follow_ups"], act_id)
			if event.get("linked_to_past", false):
				_count(result["act_linked"], act_id)
			if _is_crisis(event):
				_count(result["crisis_seen"], event["id"])
				had_crisis = true

			var side := _decide(session, strategy)
			if not result["choices"].has(event["id"]):
				result["choices"][event["id"]] = {"left": 0, "right": 0}
			result["choices"][event["id"]][side] += 1
			session.choose(side)
			_record_turn(result, session)
			session.proceed()
			while session.is_showing_checkpoint():
				result["checkpoints"] += 1
				session.proceed()

		var ending: Dictionary = session.ending
		_count(result["endings"], ending["id"])
		result["turns_total"] += session.state.turn
		if max_streak >= 3:
			result["long_streak_runs"] += 1
		if had_crisis:
			result["crisis_runs"] += 1
		for stat_id in session.state.stats:
			result["final_stats_all"][stat_id] = int(result["final_stats_all"].get(stat_id, 0)) + int(session.state.stats[stat_id])
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
		"lowest_first":
			var lowest_id := ""
			for stat_id in session.state.stats:
				if lowest_id.is_empty() or int(session.state.stats[stat_id]) < int(session.state.stats[lowest_id]):
					lowest_id = stat_id
			var left_stats: Dictionary = session.preview_choice("left")
			var right_stats: Dictionary = session.preview_choice("right")
			if int(left_stats[lowest_id]) != int(right_stats[lowest_id]):
				return "left" if int(left_stats[lowest_id]) > int(right_stats[lowest_id]) else "right"
			var left_score := _careful_score(left_stats)
			var right_score := _careful_score(right_stats)
			if left_score != right_score:
				return "left" if left_score > right_score else "right"
	return "left" if _decision_rng.randf() < 0.5 else "right"


## 위기 사건: 상태가 위험해졌을 때 나오는 사건 (state 종류 중 id가 _crisis로 끝나는 것)
func _is_crisis(event: Dictionary) -> bool:
	return event["category"] == "state" and String(event["id"]).ends_with("_crisis")


## 10턴·20턴을 마친 시점의 상태를 모은다 (그때까지 살아남은 판만)
func _record_turn(result: Dictionary, session) -> void:
	var turn: int = session.state.turn
	if turn != 10 and turn != 20:
		return
	if not result["stat_at"].has(turn):
		result["stat_at"][turn] = {"count": 0}
	var bucket: Dictionary = result["stat_at"][turn]
	bucket["count"] += 1
	for stat_id in session.state.stats:
		bucket[stat_id] = int(bucket.get(stat_id, 0)) + int(session.state.stats[stat_id])


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


## 막별로 "지난 선택과 이어진 턴"의 비율. 1막은 낮고 2·3막은 높아야 의도대로다.
##   지연: 지난 선택 때문에 생긴 사건 / 연결: 지연 사건 + 지난 선택에 따라 인물의 말이 바뀐 사건
func _section_acts(results: Dictionary, config: Dictionary) -> Array[String]:
	var header := "| 전략 |"
	var divider := "|---|"
	for act in config["acts"]:
		header += " %s (%d~%d턴) 지연 / 연결 |" % [act["name"], act["from"], act["to"]]
		divider += "---|"
	header += " 판당 중간 결산 |"
	divider += "---|"
	var lines: Array[String] = ["## 막별로 지난 선택과 이어진 턴의 비율", "", header, divider]
	for strategy in STRATEGIES:
		var r: Dictionary = results[strategy]
		var row := "| %s |" % strategy
		for act in config["acts"]:
			var turns := float(r["act_turns"].get(act["id"], 0))
			row += " %s / %s |" % [_pct(r["act_follow_ups"].get(act["id"], 0), turns), _pct(r["act_linked"].get(act["id"], 0), turns)]
		row += " %.1f |" % (float(r["checkpoints"]) / r["runs"])
		lines.append(row)
	lines.append("")
	return lines


## 전략별: 판 수, 완주율, 중도 실패율, 평균 생존 턴, 어떤 상태가 0이 되어 끝났는지
func _section_failures(results: Dictionary, config: Dictionary) -> Array[String]:
	var header := "| 전략 | 판 수 | 완주율 | 중도 실패율 | 평균 생존 턴 |"
	var divider := "|---|---|---|---|---|"
	for stat in config["stats"]:
		header += " %s 0 |" % stat["name"]
		divider += "---|"
	var lines: Array[String] = ["## 완주와 실패 원인", "", "실패 원인은 전체 판 대비 비율 (어느 상태가 0이 되어 끝났는지)", "", header, divider]
	for strategy in STRATEGIES:
		var r: Dictionary = results[strategy]
		var runs := float(r["runs"])
		var row := "| %s | %d | %s | %s | %.1f |" % [strategy, r["runs"], _pct(r["completed"], runs),
			_pct(runs - r["completed"], runs), r["turns_total"] / runs]
		for stat in config["stats"]:
			row += " %s |" % _pct(r["endings"].get("collapse_" + String(stat["id"]), 0), runs)
		lines.append(row)
	lines.append("")
	return lines


func _section_final_stats_all(results: Dictionary, config: Dictionary) -> Array[String]:
	var header := "| 전략 |"
	var divider := "|---|"
	for stat in config["stats"]:
		header += " %s |" % stat["name"]
		divider += "---|"
	var lines: Array[String] = ["## 모든 판(중도 실패 포함)의 평균 마지막 상태 (개발용 수치)", "", header, divider]
	for strategy in STRATEGIES:
		var r: Dictionary = results[strategy]
		var row := "| %s |" % strategy
		for stat in config["stats"]:
			row += " %.1f |" % (float(r["final_stats_all"].get(stat["id"], 0)) / r["runs"])
		lines.append(row)
	lines.append("")
	return lines


## 10턴·20턴을 마친 시점의 평균 상태. 시작값과 비교하면 어떤 상태가 빨리 줄어드는지 보인다.
func _section_stat_course(results: Dictionary, config: Dictionary) -> Array[String]:
	var header := "| 전략 | 시점 |"
	var divider := "|---|---|"
	var start_row := "| (시작) | 0턴 |"
	for stat in config["stats"]:
		header += " %s |" % stat["name"]
		divider += "---|"
		start_row += " %d |" % int(stat["initial"])
	var lines: Array[String] = ["## 진행에 따른 평균 상태 (그 시점까지 살아남은 판)", "", header, divider, start_row]
	for strategy in STRATEGIES:
		var r: Dictionary = results[strategy]
		for turn in [10, 20]:
			if not r["stat_at"].has(turn):
				continue
			var bucket: Dictionary = r["stat_at"][turn]
			var row := "| %s | %d턴 |" % [strategy, turn]
			for stat in config["stats"]:
				row += " %.1f |" % (float(bucket.get(stat["id"], 0)) / maxi(int(bucket["count"]), 1))
			lines.append(row)
	lines.append("")
	return lines


func _section_crisis(results: Dictionary, titles: Dictionary) -> Array[String]:
	var lines: Array[String] = ["## 위기 사건 발생", "", "| 전략 | 위기가 한 번 이상 나온 판 | 판당 위기 사건 수 | 사건별 (판당) |", "|---|---|---|---|"]
	for strategy in STRATEGIES:
		var r: Dictionary = results[strategy]
		var runs := float(r["runs"])
		var total := 0
		var parts: Array = []
		for event_id in r["crisis_seen"]:
			total += int(r["crisis_seen"][event_id])
			parts.append("%s %.2f" % [titles.get(event_id, event_id), r["crisis_seen"][event_id] / runs])
		lines.append("| %s | %s | %.2f | %s |" % [strategy, _pct(r["crisis_runs"], runs), total / runs, ", ".join(PackedStringArray(parts))])
	lines.append("")
	return lines


## 전략별로 왼쪽을 고른 비율. careful·lowest_first가 한쪽으로 쏠리면 위치 자체가 공략법이 된다.
func _section_sides(results: Dictionary) -> Array[String]:
	var lines: Array[String] = ["## 좌/우 선택률", "", "| 전략 | 왼쪽 | 오른쪽 |", "|---|---|---|"]
	for strategy in STRATEGIES:
		var left := 0
		var right := 0
		for event_id in results[strategy]["choices"]:
			left += int(results[strategy]["choices"][event_id]["left"])
			right += int(results[strategy]["choices"][event_id]["right"])
		lines.append("| %s | %s | %s |" % [strategy, _pct(left, left + right), _pct(right, left + right)])
	lines.append("")
	return lines


## 사건 데이터만 보고 계산한 효과 구조 (시뮬레이션과 무관)
##   비용 없는 선택: 내려가는 상태가 하나도 없는 선택
##   한쪽이 나은 사건: 한 선택지가 모든 상태에서 다른 쪽보다 같거나 좋은 사건
##   상태별 비용 쓰임: 그 상태만 내려가고 다른 상태는 오르는 선택 수 (그 상태가 "공용 비용"처럼 쓰이는지)
func _section_effect_structure(data: Dictionary, config: Dictionary, titles: Dictionary) -> Array[String]:
	var stat_ids: Array = []
	var names := {}
	for stat in config["stats"]:
		stat_ids.append(stat["id"])
		names[stat["id"]] = stat["name"]
	var down_count := {}
	var down_sum := {}
	var up_count := {}
	var up_sum := {}
	var sole_cost := {}
	var free_choices: Array = []
	var dominated: Array = []
	var choice_total := 0
	for event in data["events"]:
		var effects := {}
		for side in ["left", "right"]:
			var choice: Dictionary = event[side + "_choice"]
			var fx: Dictionary = choice["effects"]
			effects[side] = fx
			choice_total += 1
			var downs: Array = []
			var ups: Array = []
			for stat_id in fx:
				var v := int(fx[stat_id])
				if v < 0:
					downs.append(stat_id)
					down_count[stat_id] = int(down_count.get(stat_id, 0)) + 1
					down_sum[stat_id] = int(down_sum.get(stat_id, 0)) + v
				elif v > 0:
					ups.append(stat_id)
					up_count[stat_id] = int(up_count.get(stat_id, 0)) + 1
					up_sum[stat_id] = int(up_sum.get(stat_id, 0)) + v
			if downs.is_empty() and not ups.is_empty():
				free_choices.append("%s (%s) %s: %s" % [titles[event["id"]], event["id"], "왼쪽" if side == "left" else "오른쪽", _fx_text(fx, names)])
			if downs.size() == 1 and not ups.is_empty():
				sole_cost[downs[0]] = int(sole_cost.get(downs[0], 0)) + 1
		for side in ["left", "right"]:
			var other := "right" if side == "left" else "left"
			var better_somewhere := false
			var worse_somewhere := false
			for stat_id in stat_ids:
				var a := int(effects[side].get(stat_id, 0))
				var b := int(effects[other].get(stat_id, 0))
				if a > b:
					better_somewhere = true
				elif a < b:
					worse_somewhere = true
			if better_somewhere and not worse_somewhere:
				dominated.append("%s (%s): %s 쪽이 모든 면에서 같거나 나음 — 왼쪽 %s / 오른쪽 %s" % [
					titles[event["id"]], event["id"], "왼쪽" if side == "left" else "오른쪽",
					_fx_text(effects["left"], names), _fx_text(effects["right"], names)])

	var lines: Array[String] = ["## 효과 구조 (사건 데이터 %d개 선택지 기준)" % choice_total, "",
		"| 상태 | 내리는 선택 수 | 내림 합 | 올리는 선택 수 | 올림 합 | 혼자만 비용인 선택 수 |", "|---|---|---|---|---|---|"]
	for stat_id in stat_ids:
		lines.append("| %s | %d | %d | %d | +%d | %d |" % [names[stat_id], int(down_count.get(stat_id, 0)), int(down_sum.get(stat_id, 0)),
			int(up_count.get(stat_id, 0)), int(up_sum.get(stat_id, 0)), int(sole_cost.get(stat_id, 0))])
	lines.append("")
	lines.append("### 비용 없는 선택 (내려가는 상태 없음) %d개" % free_choices.size())
	lines.append("")
	for text in free_choices:
		lines.append("- " + text)
	lines.append("")
	lines.append("### 한쪽이 모든 면에서 나은 사건 %d개" % dominated.size())
	lines.append("")
	for text in dominated:
		lines.append("- " + text)
	lines.append("")
	return lines


func _fx_text(fx: Dictionary, names: Dictionary) -> String:
	var parts: Array = []
	for stat_id in fx:
		parts.append("%s %+d" % [names.get(stat_id, stat_id), int(fx[stat_id])])
	return ", ".join(PackedStringArray(parts)) if not parts.is_empty() else "변화 없음"


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
