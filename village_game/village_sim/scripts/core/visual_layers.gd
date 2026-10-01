extends RefCounted
## 마을 배경 레이어 판정 (향후 확장용).
##
## data/visuals/ 의 레이어 정의 [{"id": "factory", "conditions": [...]}] 중
## 지금 상태와 플래그에 맞는 레이어 id 목록을 돌려준다.
## 아직 그림은 없다. 배경 에셋이 생기면 화면 쪽에서 이 목록대로 레이어를 켜고 끄기만 하면 된다.

const Conditions = preload("res://village_sim/scripts/core/condition_evaluator.gd")


static func active_layers(layers: Array, state) -> Array:
	var active: Array = []
	for layer in layers:
		if Conditions.check_all(layer["conditions"], state):
			active.append(layer["id"])
	return active
