extends RefCounted
## data/ 폴더의 JSON 파일을 읽어 게임이 쓰는 형태로 정리한다.
##
## - 모듈 루트는 이 스크립트 위치에서 계산하므로, 모듈 폴더의 data 경로를 따로 적을 필요가 없다.
## - data/events/ 아래의 모든 .json 파일(하위 폴더 포함)을 읽는다.
##   새 사건 묶음은 폴더나 파일을 추가하기만 하면 된다. 코드는 고치지 않는다.
## - 파일 하나에는 사건 하나(객체) 또는 여러 개(배열)를 담을 수 있다. data/endings/도 같다.
## - 읽기 오류는 결과의 "load_errors"에 모이고, DataValidator가 함께 보고한다.

const CONFIG_FILE := "config/game_config.json"
const EVENTS_DIR := "events"
const ENDINGS_DIR := "endings"

var _errors: Array = []


## 모듈 루트 경로 (예: res://village_sim)
func module_root() -> String:
	# 이 파일의 위치: <모듈 루트>/scripts/data/data_loader.gd
	return get_script().resource_path.get_base_dir().get_base_dir().get_base_dir()


## 설정·사건·엔딩을 모두 읽는다. data_dir을 주면 다른 데이터 폴더를 쓸 수 있다. (예: 다른 마을 유형)
func load_all(data_dir: String = "") -> Dictionary:
	_errors = []
	if data_dir.is_empty():
		data_dir = module_root().path_join("data")

	var config := _normalize_config(_read_json(data_dir.path_join(CONFIG_FILE)))

	var events: Array = []
	for path in _list_json_files(data_dir.path_join(EVENTS_DIR)):
		for raw in _as_array(_read_json(path), path):
			var event := _normalize_event(raw, path, config)
			if not event.is_empty():
				events.append(event)

	var endings: Array = []
	for path in _list_json_files(data_dir.path_join(ENDINGS_DIR)):
		for raw in _as_array(_read_json(path), path):
			var ending := _normalize_ending(raw, path)
			if not ending.is_empty():
				endings.append(ending)

	return {
		"config": config,
		"events": events,
		"endings": endings,
		"load_errors": _errors,
	}


# --- 파일 읽기 ---------------------------------------------------------------

func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		_errors.append("파일이 없습니다: %s" % path)
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		_errors.append("%s (%d번째 줄): JSON 형식 오류 - %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


## 폴더 안의 .json 파일 경로를 이름순으로 모은다. 하위 폴더도 포함한다.
func _list_json_files(dir_path: String) -> Array:
	var result: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		_errors.append("폴더를 열 수 없습니다: %s" % dir_path)
		return result
	var files := Array(dir.get_files())
	files.sort()
	for file_name in files:
		if String(file_name).get_extension().to_lower() == "json":
			result.append(dir_path.path_join(file_name))
	var subdirs := Array(dir.get_directories())
	subdirs.sort()
	for subdir in subdirs:
		result.append_array(_list_json_files(dir_path.path_join(subdir)))
	return result


func _as_array(value: Variant, path: String = "") -> Array:
	if value is Array:
		return value
	if value is Dictionary:
		return [value]
	if value != null:
		_errors.append("%s: 배열 또는 객체여야 합니다." % path)
	return []


func _string_array(value: Variant) -> Array:
	var result: Array = []
	if value is Array:
		for item in value:
			result.append(String(item))
	return result


# --- 정리(정규화) ----------------------------------------------------------------

func _normalize_config(raw: Variant) -> Dictionary:
	var source: Dictionary = raw if raw is Dictionary else {}
	var stats: Array = []
	var stat_order: Array = []
	for stat in source.get("stats", []):
		if not (stat is Dictionary):
			_errors.append("설정: stats 항목은 객체여야 합니다.")
			continue
		var stat_id := String(stat.get("id", ""))
		stats.append({
			"id": stat_id,
			"name": String(stat.get("name", stat_id)),
			"initial": int(stat.get("initial", 50)),
		})
		stat_order.append(stat_id)

	var selection: Dictionary = source.get("selection", {})
	return {
		"max_turns": int(source.get("max_turns", 30)),
		"stat_min": int(source.get("stat_min", 0)),
		"stat_max": int(source.get("stat_max", 100)),
		"stats": stats,
		"stat_order": stat_order,
		"selection": {
			"default_weight": float(selection.get("default_weight", 10)),
			"recent_tag_window": int(selection.get("recent_tag_window", 2)),
			"recent_tag_weight": float(selection.get("recent_tag_weight", 0.3)),
		},
		"default_priority": source.get("default_priority", {"state": 30, "delayed": 50}),
		"effect_scale": source.get("effect_scale", {}),
	}


func _normalize_event(raw: Variant, path: String, config: Dictionary) -> Dictionary:
	if not (raw is Dictionary):
		_errors.append("%s: 사건은 객체여야 합니다." % path)
		return {}
	var category := String(raw.get("category", "general"))
	var default_priority: int = int(config["default_priority"].get(category, 0))
	return {
		"id": String(raw.get("id", "")),
		"category": category,
		"tags": _string_array(raw.get("tags", [])),
		"title": String(raw.get("title", "")),
		"description": String(raw.get("description", "")),
		"weight": float(raw.get("weight", config["selection"]["default_weight"])),
		"priority": int(raw.get("priority", default_priority)),
		"conditions": _as_array(raw.get("conditions", []), path),
		"left_choice": _normalize_choice(raw.get("left_choice", null)),
		"right_choice": _normalize_choice(raw.get("right_choice", null)),
		"source": path,
	}


func _normalize_choice(raw: Variant) -> Dictionary:
	var source: Dictionary = raw if raw is Dictionary else {}
	var effects := {}
	var raw_effects: Variant = source.get("effects", {})
	if raw_effects is Dictionary:
		for stat_id in raw_effects:
			effects[String(stat_id)] = int(round(float(raw_effects[stat_id])))

	# set_flags 항목은 "flag_name" 또는 {"flag": "flag_name", "chance": 0.5} 형태
	var set_flags: Array = []
	var raw_flags: Variant = source.get("set_flags", [])
	if raw_flags is Array:
		for entry in raw_flags:
			if entry is Dictionary:
				set_flags.append({"flag": String(entry.get("flag", "")), "chance": float(entry.get("chance", 1.0))})
			else:
				set_flags.append({"flag": String(entry), "chance": 1.0})

	return {
		"text": String(source.get("text", "")),
		"result": String(source.get("result", "")),
		"effects": effects,
		"set_flags": set_flags,
		"clear_flags": _string_array(source.get("clear_flags", [])),
	}


func _normalize_ending(raw: Variant, path: String) -> Dictionary:
	if not (raw is Dictionary):
		_errors.append("%s: 엔딩은 객체여야 합니다." % path)
		return {}
	return {
		"id": String(raw.get("id", "")),
		"type": String(raw.get("type", "")),
		"stat": String(raw.get("stat", "")),
		"priority": int(raw.get("priority", 0)),
		"conditions": _as_array(raw.get("conditions", []), path),
		"title": String(raw.get("title", "")),
		"text": String(raw.get("text", "")),
		"source": path,
	}
