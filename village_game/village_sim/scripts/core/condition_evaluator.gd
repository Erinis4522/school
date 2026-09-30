extends RefCounted
## 사건과 엔딩이 함께 쓰는 조건 판정기.
##
## 조건은 {"type": ..., ...} 형태의 Dictionary이며, 목록으로 주어지면 모두 만족해야(AND) 통과한다.
##   {"type": "stat", "stat": "finance", "op": "<=", "value": 20}
##   {"type": "turn", "op": ">=", "value": 15}
##   {"type": "flag", "flag": "factory_built", "min_age": 3}     # min_age, max_age는 선택
##   {"type": "no_flag", "flag": "factory_settled"}
##
## 새 조건 종류를 추가하려면:
##   1) REQUIRED_FIELDS에 종류와 필수 필드를 등록한다. (데이터 검증에 쓰인다)
##   2) check()의 match에 판정 코드를 추가한다.

const OPS: Array[String] = ["<", "<=", ">", ">=", "==", "!="]

const REQUIRED_FIELDS := {
	"stat": ["stat", "op", "value"],
	"turn": ["op", "value"],
	"flag": ["flag"],
	"no_flag": ["flag"],
}


static func check_all(conditions: Array, state) -> bool:
	for condition in conditions:
		if not check(condition, state):
			return false
	return true


static func check(condition: Dictionary, state) -> bool:
	match String(condition.get("type", "")):
		"stat":
			return compare(int(state.stats.get(condition["stat"], 0)), condition["op"], condition["value"])
		"turn":
			return compare(state.turn, condition["op"], condition["value"])
		"flag":
			if not state.has_flag(condition["flag"]):
				return false
			var age: int = state.flag_age(condition["flag"])
			if condition.has("min_age") and age < int(condition["min_age"]):
				return false
			if condition.has("max_age") and age > int(condition["max_age"]):
				return false
			return true
		"no_flag":
			return not state.has_flag(condition["flag"])
	push_warning("알 수 없는 조건 종류: %s" % condition.get("type"))
	return false


static func compare(a: float, op: String, b: float) -> bool:
	match op:
		"<":
			return a < b
		"<=":
			return a <= b
		">":
			return a > b
		">=":
			return a >= b
		"==":
			return is_equal_approx(a, b)
		"!=":
			return not is_equal_approx(a, b)
	return false
