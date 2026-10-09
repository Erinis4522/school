extends Control
## AI 마을 운영자 훈련소: 기존 게임의 배경, 카드, 색상, 루카 초상을 재사용.
## 한 장의 스크롤 카드에 '미션 → 훈련 설계 → 실전 시험'을 묶어 화면 잘림을 방지한다.

signal back_requested

const UiStyle = preload("res://village_sim/scripts/game/ui_style.gd")
const AssetLibrary = preload("res://village_sim/scripts/game/asset_library.gd")
const TrainingRunner = preload("res://village_sim/scripts/ai/training_runner.gd")
const DeckRules = preload("res://village_sim/scripts/ai/deck_rules.gd")

const SCENARIO_INFO := {
	"normal": {"title": "균형의 마을", "intro": "주민·재정·환경·안전을 균형 있게 지켜 주세요."},
	"treasury": {"title": "텅 빈 금고", "intro": "재정 28에서 출발합니다. 다른 자원도 지키며 마을을 운영하세요."},
	"dual": {"title": "두 가지 위기", "intro": "돈과 환경이 모두 부족해요."},
	"final": {"title": "마지막 과제: 폭풍의 마을", "intro": "폭풍의 마을에서도 연습할 수 있어요. 마지막 과제는 10번 모두 살아남기!"},
}
const ENVIRONMENTS := ["normal", "treasury", "mixed", "final"]
const MISSIONS := ["normal", "treasury", "dual", "final"]

var _runner
var _last_results: Dictionary = {}
var _snapshots: Array = [] # 설정별 시험 기록을 누적하여 이전 비교 결과도 보존
var _ignore_change := false
var _mission: OptionButton
var _environment: OptionButton
var _deck_selected: Array = ["finance", "crisis", "balance"]
var _deck_buttons: Dictionary = {}
var _deck_status: Label
var _failure_report: RichTextLabel
var _previous_report: RichTextLabel
var _luka_line: Label
var _train_label: Label
var _message: Label
var _progress: ProgressBar
var _report: RichTextLabel
var _learning_report: RichTextLabel
var _test_button: Button
var _watch_button: Button
var _card: PanelContainer
var _training_count: SpinBox
var _add_button: Button
var _decision_selector: OptionButton
var _decision_report: RichTextLabel
var _watch_result: Dictionary = {}
var _busy := false
var _reset_button: Button


func _ready() -> void:
	theme = UiStyle.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_layout()
	resized.connect(_resize_card)
	call_deferred("_resize_card")


func setup(data: Dictionary) -> void:
	_runner = TrainingRunner.new(data)
	_ignore_change = true
	_mission.select(0)
	_environment.select(0)
	_ignore_change = false
	_reset_training()


func _build_layout() -> void:
	var background := TextureRect.new()
	background.texture = AssetLibrary.texture("backgrounds/normal")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var shade := ColorRect.new()
	shade.color = Color(0.13, 0.12, 0.10, 0.38)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(scroll)

	var frame := MarginContainer.new()
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.add_theme_constant_override("margin_left", 18)
	frame.add_theme_constant_override("margin_right", 18)
	frame.add_theme_constant_override("margin_top", 20)
	frame.add_theme_constant_override("margin_bottom", 28)
	scroll.add_child(frame)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.add_child(center)

	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", UiStyle.main_box())
	center.add_child(_card)
	var card_pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		card_pad.add_theme_constant_override("margin_" + side, 19)
	_card.add_child(card_pad)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 13)
	card_pad.add_child(content)

	var headline := PanelContainer.new()
	headline.add_theme_stylebox_override("panel", UiStyle.title_box())
	content.add_child(headline)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	headline.add_child(header)
	var title := _label("AI 마을 훈련소", 25, true)
	title.add_theme_color_override("font_color", UiStyle.TITLE_TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var back := _button("타이틀로", 14)
	back.custom_minimum_size.x = 108
	back.pressed.connect(func(): back_requested.emit())
	header.add_child(back)

	var story := HBoxContainer.new()
	story.add_theme_constant_override("separation", 16)
	content.add_child(story)
	var portrait := TextureRect.new()
	portrait.texture = AssetLibrary.portrait("luka", "neutral")
	portrait.custom_minimum_size = Vector2(114, 120)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	story.add_child(portrait)
	var intro_panel := PanelContainer.new()
	intro_panel.add_theme_stylebox_override("panel", UiStyle.dialogue_box())
	intro_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	story.add_child(intro_panel)
	var intro := VBoxContainer.new()
	intro.add_theme_constant_override("separation", 5)
	intro_panel.add_child(intro)
	intro.add_child(_label("루카의 도전장", 15, true))
	_luka_line = _label("", 16)
	_luka_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_child(_luka_line)

	var mission_panel := _section(content, "① 실전 미션 선택")
	_mission = _options(mission_panel, ["평범한 마을", "텅 빈 금고", "두 가지 위기", "★ 마지막 과제: 폭풍의 마을"])
	_mission.item_selected.connect(_mission_changed)

	var training_panel := _section(content, "② AI 훈련 카드 3장 고르기")
	training_panel.add_child(_label("카드는 AI가 다음 훈련에서 배우는 기준을 바꿔요.", 14))
	var card_grid := GridContainer.new()
	card_grid.columns = 3
	card_grid.add_theme_constant_override("h_separation", 8)
	card_grid.add_theme_constant_override("v_separation", 8)
	card_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	training_panel.add_child(card_grid)
	# 카드 제목만 굵게: 한 버튼에 제목과 설명을 함께 넣으면 서로 다른 글꼴을 적용할 수 없다.
	# 기존 폰트를 그대로 사용하면서 FontVariation으로 제목의 두께만 높인다.
	var deck_bold := FontVariation.new()
	deck_bold.base_font = load("res://village_sim/assets/fonts/NotoSansKR-Regular.otf")
	deck_bold.variation_embolden = 0.75
	for card in DeckRules.CARDS:
		var b := _button("", 13)
		b.custom_minimum_size.y = 80
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_toggle_card.bind(String(card["id"])))
		_deck_buttons[String(card["id"])] = b
		card_grid.add_child(b)
		var pad := MarginContainer.new()
		pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		pad.add_theme_constant_override("margin_left", 5)
		pad.add_theme_constant_override("margin_right", 5)
		pad.add_theme_constant_override("margin_top", 7)
		pad.add_theme_constant_override("margin_bottom", 7)
		b.add_child(pad)
		var text_stack := VBoxContainer.new()
		text_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text_stack.alignment = BoxContainer.ALIGNMENT_CENTER
		text_stack.add_theme_constant_override("separation", 4)
		pad.add_child(text_stack)
		var card_title := _label(String(card["name"]), 15, true)
		card_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card_title.add_theme_font_override("font", deck_bold)
		card_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text_stack.add_child(card_title)
		var card_desc := _label(String(card["description"]), 12)
		card_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card_desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text_stack.add_child(card_desc)
	_deck_status = _label("", 13, true)
	training_panel.add_child(_deck_status)
	training_panel.add_child(_label("연습할 마을", 14, true))
	_environment = _options(training_panel, ["평범한 마을", "돈이 부족한 마을", "여러 마을을 섞어서", "폭풍의 마을 (최종 과제 연습)"])
	_environment.item_selected.connect(_settings_changed)
	_update_deck_ui()

	var action_panel := _section(content, "③ 몇 판 더 연습할까요?")
	action_panel.add_child(_label("추가로 연습할 판수 (1~1,000판)", 14, true))
	_training_count = SpinBox.new()
	_training_count.min_value = 1
	_training_count.max_value = 1000
	_training_count.step = 1
	_training_count.rounded = true
	_training_count.value = 100
	_training_count.custom_minimum_size.y = 40
	_training_count.get_line_edit().add_theme_color_override("font_color", UiStyle.TEXT)
	_training_count.get_line_edit().add_theme_color_override("font_placeholder_color", UiStyle.TEXT_SOFT)
	action_panel.add_child(_training_count)
	_train_label = _label("현재 0판 연습", 19, true)
	action_panel.add_child(_train_label)
	_progress = ProgressBar.new()
	_progress.min_value = 0
	_progress.max_value = 100
	_progress.show_percentage = false
	action_panel.add_child(_progress)
	_add_button = _button("입력한 판수만큼 더 배우기", 17)
	_add_button.pressed.connect(_train_add)
	action_panel.add_child(_add_button)
	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 7)
	action_panel.add_child(actions)
	_test_button = _button("선택한 미션 시험하기", 15)
	_test_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_test_button.pressed.connect(_compare)
	actions.add_child(_test_button)
	_watch_button = _button("AI가 어떤 선택을 했는지 보기", 15)
	_watch_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_watch_button.pressed.connect(_watch)
	actions.add_child(_watch_button)
	_reset_button = _button("처음부터 다시 배우기", 14)
	_reset_button.pressed.connect(_reset_training)
	action_panel.add_child(_reset_button)
	_message = _label("", 13)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	action_panel.add_child(_message)

	var results := _section(content, "④ 시험 결과")
	_report = RichTextLabel.new()
	_report.bbcode_enabled = true
	_report.fit_content = true
	_report.scroll_active = false
	_report.selection_enabled = true
	_report.add_theme_font_size_override("normal_font_size", 16)
	_report.add_theme_color_override("default_color", UiStyle.TEXT)
	_report.add_theme_color_override("font_selected_color", UiStyle.TEXT)
	_report.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	results.add_child(_report)
	var problems := _section(content, "⑤ 실패 원인 살펴보기")
	_failure_report = RichTextLabel.new()
	_failure_report.bbcode_enabled = true
	_failure_report.fit_content = true
	_failure_report.scroll_active = false
	_failure_report.add_theme_font_size_override("normal_font_size", 16)
	_failure_report.add_theme_color_override("default_color", UiStyle.TEXT)
	_failure_report.text = "시험을 진행하면 어떤 자원이 바닥났는지 나와요."
	problems.add_child(_failure_report)
	var history := _section(content, "⑥ 덱을 바꾼 뒤 성적 비교")
	_previous_report = RichTextLabel.new()
	_previous_report.bbcode_enabled = true
	_previous_report.fit_content = true
	_previous_report.scroll_active = false
	_previous_report.add_theme_font_size_override("normal_font_size", 15)
	_previous_report.add_theme_color_override("default_color", UiStyle.TEXT)
	history.add_child(_previous_report)
	history.add_child(_label("카드 효과를 공정하게 비교하려면 AI를 초기화하고 같은 판수로 다시 훈련하세요.", 13))
	var learned_panel := _section(content, "⑦ AI가 배운 점")
	_learning_report = RichTextLabel.new()
	_learning_report.bbcode_enabled = true
	_learning_report.fit_content = true
	_learning_report.scroll_active = false
	_learning_report.selection_enabled = true
	_learning_report.add_theme_font_size_override("normal_font_size", 16)
	_learning_report.add_theme_color_override("default_color", UiStyle.TEXT)
	_learning_report.text = "AI가 연습을 마치면 여기에 배운 점이 나타나요."
	learned_panel.add_child(_learning_report)
	var inspection := _section(content, "⑧ AI가 고른 선택 자세히 보기")
	_decision_selector = _options(inspection, ["위에서 'AI가 어떤 선택을 했는지 보기'를 누르세요"])
	_decision_selector.item_selected.connect(_decision_changed)
	_decision_selector.disabled = true
	_decision_report = RichTextLabel.new()
	_decision_report.bbcode_enabled = true
	_decision_report.fit_content = true
	_decision_report.scroll_active = false
	_decision_report.selection_enabled = true
	_decision_report.add_theme_font_size_override("normal_font_size", 15)
	_decision_report.add_theme_color_override("default_color", UiStyle.TEXT)
	_decision_report.add_theme_color_override("font_selected_color", UiStyle.TEXT)
	_decision_report.text = "아직 선택 기록이 없어요."
	inspection.add_child(_decision_report)



func _section(parent: VBoxContainer, title: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.panel_box())
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	panel.add_child(column)
	column.add_child(_label(title, 18, true))
	return column


func _label(value: String, font_size: int, bold: bool = false) -> Label:
	var result := Label.new()
	result.text = value
	result.add_theme_font_size_override("font_size", font_size)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.add_theme_color_override("font_color", UiStyle.HEADING_TEXT if bold else UiStyle.TEXT)
	return result


func _button(value: String, font_size: int) -> Button:
	var result := Button.new()
	result.text = value
	result.custom_minimum_size = Vector2(0, 40)
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", UiStyle.TEXT)
	return result


func _options(parent: VBoxContainer, titles: Array) -> OptionButton:
	var control := OptionButton.new()
	for name in titles:
		control.add_item(String(name))
	control.custom_minimum_size = Vector2(0, 42)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 버튼 본체뿐 아니라 클릭해서 펼쳐지는 PopupMenu까지 명시적으로 밝게 지정한다.
	# Godot 기본 PopupMenu의 검은 배경과 어두운 글씨가 겹치지 않도록 한다.
	var normal := StyleBoxFlat.new()
	normal.bg_color = UiStyle.DIALOGUE_BG
	normal.border_color = UiStyle.BEIGE_BORDER
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(9)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 7
	normal.content_margin_bottom = 7
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("f2e4c6")
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("e9d8b7")
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color("ede5d7")
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		control.add_theme_stylebox_override(state, pressed if state in ["pressed", "hover_pressed"] else (hover if state == "hover" else normal))
	control.add_theme_stylebox_override("disabled", disabled)
	control.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		control.add_theme_color_override(key, UiStyle.TEXT)
	control.add_theme_color_override("font_disabled_color", UiStyle.TEXT_SOFT)
	# 기본 화살표 아이콘도 글자색에 맞게 짙게 표시한다.
	control.add_theme_constant_override("modulate_arrow", 1)
	var popup := control.get_popup()
	var popup_panel := StyleBoxFlat.new()
	popup_panel.bg_color = UiStyle.DIALOGUE_BG
	popup_panel.border_color = UiStyle.BEIGE_BORDER
	popup_panel.set_border_width_all(2)
	popup_panel.set_corner_radius_all(8)
	popup_panel.content_margin_left = 4
	popup_panel.content_margin_right = 4
	popup_panel.content_margin_top = 4
	popup_panel.content_margin_bottom = 4
	var popup_hover := StyleBoxFlat.new()
	popup_hover.bg_color = Color("e9d8b7")
	popup_hover.set_corner_radius_all(5)
	popup_hover.content_margin_left = 5
	popup_hover.content_margin_right = 5
	popup.add_theme_stylebox_override("panel", popup_panel)
	popup.add_theme_stylebox_override("hover", popup_hover)
	popup.add_theme_stylebox_override("separator", StyleBoxEmpty.new())
	popup.add_theme_color_override("font_color", UiStyle.TEXT)
	popup.add_theme_color_override("font_hover_color", UiStyle.HEADING_TEXT)
	popup.add_theme_color_override("font_disabled_color", UiStyle.TEXT_SOFT)
	popup.add_theme_color_override("font_separator_color", UiStyle.TEXT_SOFT)
	parent.add_child(control)
	return control


func _resize_card() -> void:
	if _card != null:
		_card.custom_minimum_size.x = minf(930.0, maxf(300.0, size.x - 48.0))


func _mission_id() -> String:
	return String(MISSIONS[_mission.selected])


func _environment_id() -> String:
	return String(ENVIRONMENTS[_environment.selected])


func _toggle_card(card_id: String) -> void:
	if _busy:
		return
	if card_id in _deck_selected:
		_deck_selected.erase(card_id)
	elif _deck_selected.size() < 3:
		_deck_selected.append(card_id)
	else:
		_message.text = "3장만 고를 수 있어요. 먼저 다른 카드를 빼주세요."
		return
	_update_deck_ui()
	if _runner != null and _deck_selected.size() == 3:
		_runner.set_deck(_deck_selected)
		_message.text = "다음 추가 학습부터 새 덱이 적용돼요."


func _update_deck_ui() -> void:
	if _deck_status == null:
		return
	_deck_status.text = "선택: %d/3장  ·  %s" % [_deck_selected.size(), DeckRules.names(_deck_selected)]
	for card_id in _deck_buttons:
		var b: Button = _deck_buttons[card_id]
		var selected: bool = card_id in _deck_selected
		b.add_theme_color_override("font_color", UiStyle.TEXT)
		b.add_theme_color_override("font_hover_color", UiStyle.TEXT)
		var style := StyleBoxFlat.new()
		style.bg_color = Color("dcf0df") if selected else UiStyle.DIALOGUE_BG
		style.border_color = Color("43805e") if selected else UiStyle.BEIGE_BORDER
		style.set_border_width_all(3 if selected else 1)
		style.set_corner_radius_all(8)
		b.add_theme_stylebox_override("normal", style)
		var hover_style := style.duplicate() as StyleBoxFlat
		hover_style.bg_color = Color("c9e5d3") if selected else Color("f3e5cb")
		b.add_theme_stylebox_override("hover", hover_style)
		b.add_theme_stylebox_override("pressed", style)
		b.tooltip_text = "선택됨" if selected else "눌러서 선택"
	if _add_button != null:
		_add_button.disabled = _busy or _deck_selected.size() != 3 or (_runner != null and _runner.trained >= 1000)


func _mission_changed(_index: int) -> void:
	if _ignore_change or _runner == null:
		return
	_last_results.clear()
	_watch_result.clear()
	_decision_selector.disabled = true
	_decision_selector.clear()
	_decision_selector.add_item("시험 후 선택 기록을 볼 수 있어요")
	_decision_report.text = ""
	_refresh_intro()
	_message.text = ""
	_report.text = "시험 버튼을 눌러 보세요."
	_learning_report.text = ""
	_failure_report.text = "시험을 진행하면 실패 원인이 나와요."
	_update_history()


func _settings_changed(_index: int) -> void:
	if _ignore_change or _runner == null:
		return
	_runner.configure(_environment_id(), "balance")
	_message.text = ""
	# 이전 기록과 학습한 결과는 보존한다. 다음 추가 학습부터 새 설정 적용.


func _refresh_intro() -> void:
	var info: Dictionary = SCENARIO_INFO[_mission_id()]
	_luka_line.text = "%s — %s" % [info["title"], info["intro"]]


func _reset_training() -> void:
	if _runner == null or _busy:
		return
	_runner.configure(_environment_id(), "balance")
	_runner.reset()
	_runner.set_deck(_deck_selected)
	_last_results.clear()
	# 이전 시험 기록은 남겨 두어 새 덱과 비교할 수 있게 한다.
	_watch_result.clear()
	_refresh_intro()
	_train_label.text = "현재 0판 연습"
	_progress.value = 0
	_progress.max_value = 100
	_add_button.disabled = false
	_test_button.disabled = false
	_watch_button.disabled = true
	_decision_selector.disabled = true
	_decision_selector.clear()
	_decision_selector.add_item("선택 기록을 먼저 열어 보세요")
	_decision_report.text = ""
	_message.text = ""
	_report.text = "연습 전후에 시험 결과가 어떻게 달라지는지 비교해 보세요."
	_learning_report.text = "아직 배운 것이 없어요."
	_failure_report.text = "시험을 진행하면 실패 원인이 나와요."
	_update_history()
	_update_deck_ui()


func _set_busy(active: bool) -> void:
	_busy = active
	_mission.disabled = active
	_environment.disabled = active
	for b in _deck_buttons.values():
		b.disabled = active
	_training_count.editable = not active
	_add_button.disabled = active or _deck_selected.size() != 3 or (_runner != null and _runner.trained >= 1000)
	_test_button.disabled = active
	_watch_button.disabled = active or (_runner == null or _runner.trained == 0)
	_reset_button.disabled = active


func _train_add() -> void:
	if _runner == null or _busy:
		return
	if _deck_selected.size() != 3:
		_message.text = "카드를 세 장 고른 후 연습시켜 주세요."
		return
	_runner.set_deck(_deck_selected)
	var target := mini(1000, _runner.trained + int(_training_count.value))
	if target <= _runner.trained:
		_message.text = "총 1,000판까지 연습할 수 있어요."
		return
	_run_training_to(target)


func _run_training_to(target: int) -> void:
	_set_busy(true)
	_watch_result.clear()
	_decision_selector.disabled = true
	_decision_selector.clear()
	_decision_selector.add_item("AI의 선택 기록을 열어 보세요")
	_decision_report.text = ""
	_progress.max_value = target
	_message.text = "연습 중…"
	while _runner.trained < target:
		_runner.train_until(mini(target, _runner.trained + 20))
		_train_label.text = "현재 %d판 연습" % _runner.trained
		_progress.value = _runner.trained
		await get_tree().process_frame
	_set_busy(false)
	_message.text = ""
	_compare()


func _compare() -> void:
	if _runner == null or _busy:
		return
	var result: Dictionary = _runner.evaluate(_mission_id())
	_last_results = result
	_snapshots.append({
		"mission": _mission_id(), "environment": _environment_id(),
		"deck": _runner.last_trained_deck.duplicate(), "trained": _runner.trained,
		"result": result["trained"].duplicate(true),
		"weights": _runner.agent.weights.duplicate()
	})
	var lines: Array[String] = []
	var scenario: String = _mission_id()
	var a: Dictionary = result["trained"]
	lines.append("[b]%s · 총 %d판 연습한 AI[/b]" % [SCENARIO_INFO[scenario]["title"], _runner.trained])
	if scenario == "final":
		lines.append("[b]최종 도전: 10번의 시험에서 모두 살아남기![/b]")
		lines.append("[b]AI 기록: %d / %d판 완주 · %s[/b]" % [a["completed"], a["runs"], "도전 성공!" if int(a["completed"]) == int(a["runs"]) else "다시 훈련해 보세요"])
	else:
		lines.append("같은 조건에서 120판을 시험한 결과예요.")
	lines.append("\n[b]                    완주율      마을 점수[/b]")
	for mode in ["random", "rule", "trained"]:
		var r: Dictionary = result[mode]
		var name: String = "마음대로 선택" if mode == "random" else "정해진 규칙" if mode == "rule" else "학습한 AI"
		lines.append("%s     %.0f%%        %.1f점" % [name, r["completion"], r["score"]])
	_report.text = "\n".join(PackedStringArray(lines))
	_failure_report.text = _failure_analysis(result["trained"])
	_update_history()
	_learning_report.text = _runner.learning_report(result, scenario)
	_message.text = ""


func _failure_analysis(sample: Dictionary) -> String:
	var total := int(sample.get("runs", 0)) - int(sample.get("completed", 0))
	if total == 0:
		return "시험 중 실패한 마을이 없어요. 더 어려운 미션에서도 시험해 보세요."
	var failures: Dictionary = sample.get("failure_causes", {})
	var ranked: Array = []
	for stat_id in ["residents", "finance", "environment", "safety"]:
		ranked.append({"id": stat_id, "n": int(failures.get(stat_id, 0))})
	ranked.sort_custom(func(a, b): return int(a["n"]) > int(b["n"]))
	var lines: Array[String] = ["[b]%d번의 실패 중[/b]" % total]
	for item in ranked:
		if int(item["n"]) > 0:
			lines.append("• %s 고갈로 종료: %d회" % [_stat_label(String(item["id"])), item["n"]])
	var risks: Dictionary = sample.get("risky_counts", {})
	var top_stat := ""
	var top_count := 0
	for stat_id in ["residents", "finance", "environment", "safety"]:
		if int(risks.get(stat_id, 0)) > top_count:
			top_count = int(risks[stat_id])
			top_stat = stat_id
	if top_count > 0:
		lines.append("\n[b]위기 상황에서 나타난 선택[/b]")
		lines.append("실패한 마을에서 %s이(가) 40 이하일 때, 이를 더 줄인 선택이 %d번 있었어요." % [_stat_label(top_stat), top_count])
		for example in sample.get("risk_examples", []):
			if String(example["stat"]) == top_stat:
				lines.append("예: ‘%s’에서 ‘%s’ 선택 → %s %d→%d" % [String(example["event"]), String(example["choice"]), _stat_label(top_stat), int(example["before"]), int(example["after"])])
				break
	lines.append("\n이 기록은 실패의 단서예요. 한 번의 선택이 실패의 유일한 원인인 것은 아니에요.")
	return "\n".join(PackedStringArray(lines))


func _stat_label(stat_id: String) -> String:
	match stat_id:
		"residents": return "주민"
		"finance": return "재정"
		"environment": return "환경"
		"safety": return "안전"
	return "알 수 없음"


func _update_history() -> void:
	if _previous_report == null:
		return
	var same: Array = []
	for record in _snapshots:
		if String(record["mission"]) == _mission_id():
			same.append(record)
	if same.is_empty():
		_previous_report.text = "아직 시험 기록이 없어요. 덱을 바꿔 다시 시험해 보세요."
		return
	var lines: Array[String] = []
	for i in range(maxi(0, same.size() - 5), same.size()):
		var r: Dictionary = same[i]
		lines.append("%d판 · %s → 완주 %.0f%% / 마을 점수 %.1f" % [int(r["trained"]), DeckRules.names(r["deck"]), float(r["result"]["completion"]), float(r["result"]["score"])])
	if same.size() >= 2:
		var previous: Dictionary = same[same.size() - 2]
		var current: Dictionary = same[same.size() - 1]
		lines.append("\n지난 시험보다 완주율 %+.0f%%p, 마을 점수 %+.1f" % [float(current["result"]["completion"]) - float(previous["result"]["completion"]), float(current["result"]["score"]) - float(previous["result"]["score"])])
	_previous_report.text = "\n".join(PackedStringArray(lines))


func _watch() -> void:
	if _runner == null or _runner.trained <= 0 or _busy:
		return
	_watch_result = _runner.watch_example(_mission_id())
	_decision_selector.clear()
	for item in _watch_result["decisions"]:
		_decision_selector.add_item("%d턴 · %s" % [item["turn"], item["event"]])
	_decision_selector.disabled = _watch_result["decisions"].is_empty()
	if not _decision_selector.disabled:
		_decision_selector.select(0)
		_decision_changed(0)
	_message.text = ""


func _decision_changed(index: int) -> void:
	if _runner == null or _watch_result.is_empty():
		return
	var items: Array = _watch_result.get("decisions", [])
	if index < 0 or index >= items.size():
		return
	var item: Dictionary = items[index]
	var before: Dictionary = item["before"]
	var after: Dictionary = item["after"]
	var lines: Array[String] = []
	lines.append("[b]%d턴 · %s[/b]" % [item["turn"], item["event"]])
	lines.append("선택 전: 주민 %d · 재정 %d · 환경 %d · 안전 %d" % [before["residents"], before["finance"], before["environment"], before["safety"]])
	lines.append("A. %s  →  AI 예상 점수 %+.2f" % [item["left_text"], item["q_left"]])
	lines.append("B. %s  →  AI 예상 점수 %+.2f" % [item["right_text"], item["q_right"]])
	lines.append("[b]AI의 선택: %s[/b]" % item["choice"])
	lines.append("선택 후: 주민 %d · 재정 %d · 환경 %d · 안전 %d" % [after["residents"], after["finance"], after["environment"], after["safety"]])
	lines.append("\n[b]AI가 중요하게 본 것[/b]")
	var shown := 0
	for c in item["contributions"]:
		if absf(float(c["effect"])) < 0.01:
			continue
		lines.append("• %s: %+.2f" % [c["name"], c["effect"]])
		shown += 1
		if shown >= 3:
			break
	if shown == 0:
		lines.append("아직 큰 영향을 미친 특징이 없습니다.")
	lines.append("\n[b]연습 전과 지금, 무엇이 달라졌을까?[/b]")
	var left_features: Array = item["features_left"]
	var right_features: Array = item["features_right"]
	for checkpoint in _runner.weight_snapshots:
		var wa: Array = checkpoint["weights"]
		var qa: float = _runner.agent.value_from_features(wa, left_features)
		var qb: float = _runner.agent.value_from_features(wa, right_features)
		var predicted := "왼쪽" if qa > qb + 0.00001 else "오른쪽" if qb > qa + 0.00001 else "동점(무작위)"
		lines.append("%d판 연습: A %+.1f / B %+.1f → %s" % [checkpoint["trained"], qa, qb, predicted])
	lines.append("\n[font_size=13]예상 점수는 AI가 배운 판단 기준이에요. 실제 성공 확률은 아니에요.[/font_size]")
	_decision_report.text = "\n".join(PackedStringArray(lines))
