extends RefCounted
## 학습용 카드: 3장의 효과는 다음 추가 학습에서만 적용된다.
## 즉시 행동 점수를 높이지 않으므로 새 카드를 끼웠다고 AI가 갑자기 똑똑해지지 않는다.

const CARDS := [
	{"id": "residents", "name": "주민의 목소리", "description": "주민의 변화에 더 큰 관심"},
	{"id": "finance", "name": "튼튼한 금고", "description": "재정의 변화에 더 큰 관심"},
	{"id": "environment", "name": "푸른 마을", "description": "환경의 변화에 더 큰 관심"},
	{"id": "safety", "name": "안전 제일", "description": "안전의 변화에 더 큰 관심"},
	{"id": "crisis", "name": "위기 대응", "description": "위험한 자원부터 살리기"},
	{"id": "balance", "name": "균형 감각", "description": "자원 사이의 차이를 줄이기"},
	{"id": "future", "name": "먼 미래", "description": "게임 마지막의 결과 중시"},
	{"id": "careful", "name": "신중한 선택", "description": "한 번에 큰 손실 경계"},
	{"id": "explore", "name": "모험가", "description": "훈련 중 새 선택 더 시도"},
]
const DEFAULT_DECK := ["finance", "crisis", "balance"]
const STAT_IDS := ["residents", "finance", "environment", "safety"]

static func is_valid(deck: Array) -> bool:
	if deck.size() != 3:
		return false
	var unique := {}
	for id in deck:
		var found := false
		for card in CARDS:
			if card["id"] == id:
				found = true
				break
		if not found or unique.has(id):
			return false
		unique[id] = true
	return true

static func names(deck: Array) -> String:
	var titles: Array[String] = []
	for card in CARDS:
		if card["id"] in deck:
			titles.append(String(card["name"]))
	return " · ".join(PackedStringArray(titles))

static func extra_reward(deck: Array, before: Dictionary, after: Dictionary, finished: bool, completed: bool) -> float:
	var bonus := 0.0
	for stat_id in STAT_IDS:
		if stat_id in deck:
			bonus += 0.55 * (float(after.get(stat_id, 0)) - float(before.get(stat_id, 0)))
	if "crisis" in deck:
		var low_before := 100.0
		var low_after := 100.0
		for stat_id in STAT_IDS:
			low_before = minf(low_before, float(before.get(stat_id, 0)))
			low_after = minf(low_after, float(after.get(stat_id, 0)))
		bonus += 0.85 * (low_after - low_before)
		if low_after < 20.0:
			bonus -= 3.0
	if "balance" in deck:
		var before_min := 100.0
		var before_max := 0.0
		var after_min := 100.0
		var after_max := 0.0
		for stat_id in STAT_IDS:
			before_min = minf(before_min, float(before.get(stat_id, 0)))
			before_max = maxf(before_max, float(before.get(stat_id, 0)))
			after_min = minf(after_min, float(after.get(stat_id, 0)))
			after_max = maxf(after_max, float(after.get(stat_id, 0)))
		bonus -= 0.40 * ((after_max - after_min) - (before_max - before_min))
	if "careful" in deck:
		for stat_id in STAT_IDS:
			var loss := float(before.get(stat_id, 0)) - float(after.get(stat_id, 0))
			bonus -= 0.55 * maxf(0.0, loss - 5.0)
	if "future" in deck and finished:
		if completed:
			var low := 100.0
			for stat_id in STAT_IDS:
				low = minf(low, float(after.get(stat_id, 0)))
			bonus += 8.0 + 0.25 * low
		else:
			bonus -= 12.0
	return clampf(bonus, -28.0, 28.0)
