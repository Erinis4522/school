extends Control
## 진입점. 데이터를 읽고 게임 화면과 엔딩 화면을 오간다.

const DataLoader = preload("res://village_sim/scripts/data/data_loader.gd")
const DataValidator = preload("res://village_sim/scripts/data/data_validator.gd")
const GameSession = preload("res://village_sim/scripts/core/game_session.gd")
const GameScreenScene: PackedScene = preload("res://village_sim/scenes/game/game.tscn")
const EndingScreenScene: PackedScene = preload("res://village_sim/scenes/ending/ending.tscn")

var _session
var _screen: Control


func _ready() -> void:
	var data: Dictionary = DataLoader.new().load_all()
	var report: Dictionary = DataValidator.validate(data)
	DataValidator.print_report(report)
	if not report["errors"].is_empty():
		push_error("사건 데이터에 오류가 %d개 있습니다. 출력 창을 확인하세요." % report["errors"].size())

	_session = GameSession.new(data)
	_session.game_ended.connect(_on_game_ended)
	_start_game()


func _start_game() -> void:
	var screen = GameScreenScene.instantiate()
	_swap_screen(screen)
	screen.setup(_session)
	_session.start()


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
