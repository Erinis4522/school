extends Control
## 엔딩 화면 (1차 프로토타입용).
## assets/endings/<엔딩 id>.png 가 있으면 엔딩 그림을 함께 보여 준다. 없으면 글만 나온다.

signal restart_requested
signal title_requested

const TextUtil = preload("res://village_sim/scripts/game/text_util.gd")
const AssetLibrary = preload("res://village_sim/scripts/game/asset_library.gd")
const UiStyle = preload("res://village_sim/scripts/game/ui_style.gd")
const RECAP_COUNT := 5   # 엔딩에서 돌아볼 주요 결정 수 (가장 최근 것부터)

var _image: TextureRect
var _title_label: Label
var _text_label: Label
var _summary_label: Label
var _recap_label: Label


func _ready() -> void:
	theme = UiStyle.make_theme()
	_build_layout()


func show_ending(ending: Dictionary, summary: Dictionary) -> void:
	var texture := AssetLibrary.texture("endings/" + String(ending.get("id", "")))
	_image.texture = texture
	_image.visible = texture != null
	_title_label.text = ending.get("title", "")
	_text_label.text = TextUtil.keep_words(ending.get("text", ""))
	if ending.get("type", "") == "term_end":
		_summary_label.text = "임기 %d턴을 모두 마쳤습니다." % summary["max_turns"]
	else:
		_summary_label.text = "%d턴째에 마을 운영이 멈췄습니다." % summary["turns_played"]

	var memories: Array = summary.get("memories", [])
	if memories.is_empty():
		_recap_label.text = ""
	else:
		var lines: Array = ["임기 동안의 주요 결정"]
		for memory in memories.slice(-RECAP_COUNT):
			lines.append("· %s  (%d턴)" % [memory["text"], memory["turn"]])
		_recap_label.text = "\n".join(PackedStringArray(lines))


func _build_layout() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiStyle.card_box())
	center.add_child(card)

	var margin := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 36)
	card.add_child(margin)

	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(720, 0)
	column.add_theme_constant_override("separation", 20)
	margin.add_child(column)

	_image = TextureRect.new()
	_image.custom_minimum_size = Vector2(0, 200)
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_image.visible = false
	column.add_child(_image)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 34)
	column.add_child(_title_label)

	_text_label = Label.new()
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text_label.add_theme_font_size_override("font_size", 20)
	column.add_child(_text_label)

	_summary_label = Label.new()
	_summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary_label.add_theme_color_override("font_color", UiStyle.TEXT_SOFT)
	column.add_child(_summary_label)

	_recap_label = Label.new()
	_recap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_recap_label.add_theme_color_override("font_color", UiStyle.TEXT_SOFT)
	column.add_child(_recap_label)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 14)
	column.add_child(actions)
	var restart_button := Button.new()
	restart_button.text = "다시 시작"
	restart_button.custom_minimum_size = Vector2(240, 56)
	restart_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	restart_button.add_theme_font_size_override("font_size", 20)
	restart_button.pressed.connect(func():
		get_tree().call_group("village_audio", "play_sfx", "button")
		restart_requested.emit())
	actions.add_child(restart_button)
	var title_button := Button.new()
	title_button.text = "타이틀로 돌아가기"
	title_button.custom_minimum_size = Vector2(240, 50)
	title_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	title_button.add_theme_font_size_override("font_size", 18)
	title_button.pressed.connect(func():
		get_tree().call_group("village_audio", "play_sfx", "button")
		title_requested.emit())
	actions.add_child(title_button)
