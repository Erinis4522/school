extends Control
## 진입점. 데이터를 읽고 타이틀 → 게임 → 엔딩 화면을 오간다.

const DataLoader = preload("res://village_sim/scripts/data/data_loader.gd")
const DataValidator = preload("res://village_sim/scripts/data/data_validator.gd")
const GameSession = preload("res://village_sim/scripts/core/game_session.gd")
const TitleScreenScene: PackedScene = preload("res://village_sim/scenes/title/title.tscn")
const GameScreenScene: PackedScene = preload("res://village_sim/scenes/game/game.tscn")
const EndingScreenScene: PackedScene = preload("res://village_sim/scenes/ending/ending.tscn")
const VillageBackdrop = preload("res://village_sim/scripts/game/village_backdrop.gd")

var _data: Dictionary
var _session
var _screen: Control
var _backdrop


func _ready() -> void:
	_data = DataLoader.new().load_all()
	var report: Dictionary = DataValidator.validate(_data)
	DataValidator.print_report(report)
	if not report["errors"].is_empty():
		push_error("사건 데이터에 오류가 %d개 있습니다. 출력 창을 확인하세요." % report["errors"].size())

	# 마을 배경: 화면들 뒤에 깔린다. 상태가 바뀔 때마다 상황별 배경과 레이어를 맞춘다.
	_backdrop = VillageBackdrop.new()
	add_child(_backdrop)
	_backdrop.setup(_data.get("layers", []))

	_session = GameSession.new(_data)
	_session.game_ended.connect(_on_game_ended)
	_session.stats_changed.connect(func(_ratios): _refresh_backdrop())
	_show_title()


func _show_title() -> void:
	var screen = TitleScreenScene.instantiate()
	_swap_screen(screen)
	screen.setup(_data.get("title", {}))
	screen.new_game_requested.connect(_start_game)
	screen.quit_requested.connect(func(): get_tree().quit())


func _start_game() -> void:
	var screen = GameScreenScene.instantiate()
	_swap_screen(screen)
	screen.setup(_session)
	_session.start()


func _refresh_backdrop() -> void:
	var fade := float(_data.get("backgrounds", {}).get("fade_seconds", 0.6))
	_backdrop.set_background(_session.get_background_id(), fade)
	_backdrop.refresh(_session.get_active_layers())


func _on_game_ended(ending: Dictionary, summary: Dictionary) -> void:
	var screen = EndingScreenScene.instantiate()
	_swap_screen(screen)
	screen.show_ending(ending, summary)
	screen.restart_requested.connect(_start_game)


func _swap_screen(screen: Control) -> void:
	if _screen != null:
		_screen.queue_free()
	_screen = screen
	add_child(screen)
