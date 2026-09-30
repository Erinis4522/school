extends Control
## 엔딩 화면 (1차 프로토타입용 최소 UI).

signal restart_requested

const TextUtil = preload("res://village_sim/scripts/game/text_util.gd")

var _title_label: Label
var _text_label: Label
var _summary_label: Label


func _ready() -> void:
	_build_layout()


func show_ending(ending: Dictionary, summary: Dictionary) -> void:
	_title_label.text = ending.get("title", "")
	_text_label.text = TextUtil.keep_words(ending.get("text", ""))
	if ending.get("type", "") == "term_end":
		_summary_label.text = "임기 %d턴을 모두 마쳤습니다." % summary["max_turns"]
	else:
		_summary_label.text = "%d턴째에 마을 운영이 멈췄습니다." % summary["turns_played"]


func _build_layout() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(720, 0)
	column.add_theme_constant_override("separation", 28)
	center.add_child(column)

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
	column.add_child(_summary_label)

	var restart_button := Button.new()
	restart_button.text = "다시 시작"
	restart_button.custom_minimum_size = Vector2(240, 60)
	restart_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	restart_button.add_theme_font_size_override("font_size", 20)
	restart_button.pressed.connect(func(): restart_requested.emit())
	column.add_child(restart_button)
