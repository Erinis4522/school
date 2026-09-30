extends Control
## 게임 화면 (1차 프로토타입용 배치).
##
## 조작
##   사건 카드의 왼쪽/오른쪽을 누르면 그쪽 선택지가 카드 위에 나타난다. (영향받는 상태에 ● 표시)
##   같은 쪽을 한 번 더 누르면 결정, 반대쪽을 누르면 그쪽 선택지로 바뀐다.
##   결과 카드에서는 아무 곳이나 누르면 다음 사건으로 넘어간다.
##   키보드: ← / → 는 같은 동작, Enter / Space 는 결정 또는 다음
##
## 표시와 입력만 맡고 게임 규칙은 모른다. 선택은 choose()로, 결과 확인은 proceed()로 넘긴다.
## 색·폰트·그림 같은 최종 디자인은 VISUAL_SPEC.md 이후 다시 만든다.

enum Phase { CHOOSING, RESULT }

const TextUtil = preload("res://village_sim/scripts/game/text_util.gd")

const HINT_MARK := "●"
const UP_MARK := "▲"
const DOWN_MARK := "▼"
const CARD_SIZE := Vector2(560, 440)
const TILT_DEGREES := 4.0
const TILT_SECONDS := 0.12
const INPUT_COOLDOWN_MS := 250   # 카드가 바뀐 직후 연타로 넘어가 버리지 않게

const GUIDE_START := "카드의 왼쪽이나 오른쪽을 눌러 선택지를 확인하세요."
const GUIDE_PREVIEW := "같은 쪽을 한 번 더 누르면 결정합니다. 반대쪽을 누르면 다른 선택지를 볼 수 있어요."
const GUIDE_RESULT := "아무 곳이나 누르면 다음으로 넘어갑니다."

var _session
var _phase := Phase.CHOOSING
var _event: Dictionary = {}
var _hints: Dictionary = {}
var _preview_side := ""
var _input_ready_at := 0
var _stat_views: Dictionary = {}   # stat_id -> {"bar": ProgressBar, "marker": Label}
var _tilt_tween: Tween

var _stats_box: VBoxContainer
var _turn_label: Label
var _card: PanelContainer
var _preview_label: Label
var _title_label: Label
var _choice_label: Label
var _body_label: Label
var _guide_label: Label


func _ready() -> void:
	_build_layout()


func setup(session) -> void:
	_session = session
	for stat in session.config["stats"]:
		_add_stat_view(stat["id"], stat["name"])
	_ignore_mouse_on_children()
	session.event_presented.connect(_on_event_presented)
	session.choice_resolved.connect(_on_choice_resolved)
	session.stats_changed.connect(_on_stats_changed)


# --- 조작 ------------------------------------------------------------------------

## 카드의 한쪽을 눌렀을 때. 처음 누르면 미리 보기, 같은 쪽을 다시 누르면 결정.
func select_side(side: String) -> void:
	if _phase != Phase.CHOOSING:
		return
	if _preview_side == side:
		_session.choose(side)
		return
	_preview_side = side
	var text: String = _event[side + "_choice"]["text"]
	_preview_label.text = TextUtil.keep_words(("◀  " + text) if side == "left" else (text + "  ▶"))
	_preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if side == "left" else HORIZONTAL_ALIGNMENT_RIGHT
	_preview_label.modulate.a = 1.0
	_guide_label.text = GUIDE_PREVIEW
	_show_markers_for(_hints.get(side, []))
	_tilt(-TILT_DEGREES if side == "left" else TILT_DEGREES)


func is_showing_result() -> bool:
	return _phase == Phase.RESULT


## 결과 카드에서 다음으로 넘어간다.
func advance() -> void:
	if _phase == Phase.RESULT:
		_session.proceed()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if not _input_ready():
			return
		if _phase == Phase.RESULT:
			advance()
		else:
			var card_center_x := _card.get_global_rect().get_center().x
			select_side("left" if get_global_mouse_position().x < card_center_x else "right")


func _unhandled_input(event: InputEvent) -> void:
	if not _input_ready():
		return
	if event.is_action_pressed("ui_left"):
		select_side("left")
	elif event.is_action_pressed("ui_right"):
		select_side("right")
	elif event.is_action_pressed("ui_accept"):
		if _phase == Phase.RESULT:
			advance()
		elif not _preview_side.is_empty():
			select_side(_preview_side)
	else:
		return
	get_viewport().set_input_as_handled()


# --- 신호 처리 -------------------------------------------------------------------

func _on_event_presented(event: Dictionary, hints: Dictionary) -> void:
	_phase = Phase.CHOOSING
	_event = event
	_hints = hints
	_preview_side = ""
	_turn_label.text = "%d / %d" % [_session.state.turn, int(_session.config["max_turns"])]
	_preview_label.text = " "
	_preview_label.modulate.a = 0.0
	_title_label.text = event["title"]
	_choice_label.visible = false
	_body_label.text = TextUtil.keep_words(event["description"])
	_guide_label.text = GUIDE_START
	for stat_id in _stat_views:
		_stat_views[stat_id]["marker"].text = HINT_MARK
	_show_markers_for([])
	_tilt(0.0)
	_lock_input()


## 결과 카드: 고른 선택지와 결과 문구, 상태별 오름/내림만 보여 준다. (얼마나 변했는지는 숨김)
func _on_choice_resolved(result: Dictionary) -> void:
	_phase = Phase.RESULT
	_preview_side = ""
	_preview_label.modulate.a = 0.0
	_choice_label.text = TextUtil.keep_words("▶ " + String(result["choice_text"]))
	_choice_label.visible = true
	_body_label.text = TextUtil.keep_words(result["text"])
	_guide_label.text = GUIDE_RESULT

	var changes: Dictionary = result["changes"]
	for stat_id in _stat_views:
		var marker: Label = _stat_views[stat_id]["marker"]
		if changes.has(stat_id):
			marker.text = UP_MARK if changes[stat_id] > 0 else DOWN_MARK
			marker.modulate.a = 1.0
		else:
			marker.modulate.a = 0.0
	_tilt(0.0)
	_lock_input()


func _on_stats_changed(ratios: Dictionary) -> void:
	for stat_id in ratios:
		if _stat_views.has(stat_id):
			_stat_views[stat_id]["bar"].value = ratios[stat_id]


# --- 도우미 ----------------------------------------------------------------------

func _show_markers_for(stat_ids: Array) -> void:
	for stat_id in _stat_views:
		_stat_views[stat_id]["marker"].modulate.a = 1.0 if stat_id in stat_ids else 0.0


func _tilt(degrees: float) -> void:
	if _tilt_tween != null:
		_tilt_tween.kill()
	_tilt_tween = create_tween()
	_tilt_tween.tween_property(_card, "rotation_degrees", degrees, TILT_SECONDS)


func _lock_input() -> void:
	_input_ready_at = Time.get_ticks_msec() + INPUT_COOLDOWN_MS


func _input_ready() -> bool:
	return Time.get_ticks_msec() >= _input_ready_at


## 클릭은 모두 이 화면(루트)이 받아 카드 기준 왼쪽/오른쪽으로 판단한다.
func _ignore_mouse_on_children() -> void:
	for child in find_children("*", "Control", true, false):
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE


# --- 화면 구성 -------------------------------------------------------------------

func _build_layout() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# 왼쪽 위: 진행 턴
	_turn_label = Label.new()
	_turn_label.position = Vector2(32, 24)
	_turn_label.add_theme_font_size_override("font_size", 18)
	add_child(_turn_label)

	# 오른쪽 위: 상태 게이지
	_stats_box = VBoxContainer.new()
	_stats_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_stats_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_stats_box.offset_left = -250
	_stats_box.offset_right = -24
	_stats_box.offset_top = 20
	_stats_box.add_theme_constant_override("separation", 6)
	add_child(_stats_box)

	# 가운데: 사건 카드 + 안내 문구
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	center.add_child(column)

	_card = PanelContainer.new()
	_card.custom_minimum_size = CARD_SIZE
	_card.resized.connect(func(): _card.pivot_offset = _card.size / 2.0)
	column.add_child(_card)

	var card_margin := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]:
		card_margin.add_theme_constant_override("margin_" + edge, 28)
	_card.add_child(card_margin)

	var card_column := VBoxContainer.new()
	card_column.add_theme_constant_override("separation", 18)
	card_margin.add_child(card_column)

	_preview_label = Label.new()
	_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_label.custom_minimum_size = Vector2(0, 64)
	_preview_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_preview_label.add_theme_font_size_override("font_size", 22)
	card_column.add_child(_preview_label)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 30)
	card_column.add_child(_title_label)

	_choice_label = Label.new()
	_choice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_choice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_choice_label.add_theme_font_size_override("font_size", 18)
	_choice_label.visible = false
	card_column.add_child(_choice_label)

	_body_label = Label.new()
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_label.add_theme_font_size_override("font_size", 20)
	card_column.add_child(_body_label)

	_guide_label = Label.new()
	_guide_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_guide_label.modulate.a = 0.7
	column.add_child(_guide_label)


func _add_stat_view(stat_id: String, display_name: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var name_label := Label.new()
	name_label.text = display_name
	name_label.custom_minimum_size = Vector2(44, 0)
	row.add_child(name_label)

	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.step = 0.001
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(140, 16)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)

	var marker := Label.new()
	marker.text = HINT_MARK
	marker.custom_minimum_size = Vector2(22, 0)
	marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	marker.modulate.a = 0.0
	row.add_child(marker)

	_stats_box.add_child(row)
	_stat_views[stat_id] = {"bar": bar, "marker": marker}
