extends Control
## 타이틀 화면. 메뉴는 "새 게임"과 "종료" 두 개뿐이다.
##
## 타이틀 그림(assets/title/title.png)에 버튼이 그려져 있으면, 그 위치에 투명한 Godot 버튼을 정확히 겹쳐 둔다.
## (클릭은 Godot 버튼이 받는다. 마우스를 올리면 살짝 밝아진다)
## 버튼 위치는 data/visuals/title.json 의 rect (그림 원본 픽셀 기준 x, y, 너비, 높이).
## 타이틀 그림을 바꾸면 이 숫자만 고치면 된다. 그림이 없으면 글자 제목과 일반 버튼을 보여 준다.

signal new_game_requested
signal ai_lab_requested
signal quit_requested

const AssetLibrary = preload("res://village_sim/scripts/game/asset_library.gd")
const UiStyle = preload("res://village_sim/scripts/game/ui_style.gd")

const FALLBACK_TITLE := "마을의 선택"

var _layout: Dictionary = {}
var _image: TextureRect
var _buttons: Array = []   # [{"button": Button, "rect": Rect2}]


func _ready() -> void:
	theme = UiStyle.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_place_buttons)


## layout: data/visuals/title.json 내용
func setup(layout: Dictionary) -> void:
	_layout = layout
	var texture := AssetLibrary.texture(String(layout.get("image", "title/title")))
	if texture == null:
		_build_fallback()
		_build_ai_lab_button()
		return
	_image = TextureRect.new()
	_image.texture = texture
	_image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(_image)
	for entry in layout.get("buttons", []):
		var r: Array = entry["rect"]
		var button := _make_button(String(entry["action"]), String(entry.get("label", "")), true)
		add_child(button)
		_buttons.append({"button": button, "rect": Rect2(r[0], r[1], r[2], r[3])})
	_place_buttons()
	_build_ai_lab_button()
	if not _buttons.is_empty():
		_buttons[0]["button"].grab_focus()


## 그림이 화면을 꽉 채우도록(넘치는 부분은 잘림) 늘어난 비율대로 버튼 위치를 옮긴다.
func _place_buttons() -> void:
	if _image == null or _image.texture == null:
		return
	var image_size := _image.texture.get_size()
	var zoom := maxf(size.x / image_size.x, size.y / image_size.y)
	var offset := (size - image_size * zoom) / 2.0
	for entry in _buttons:
		var rect: Rect2 = entry["rect"]
		var button: Button = entry["button"]
		button.position = offset + rect.position * zoom
		button.size = rect.size * zoom


func _make_button(action: String, label: String, transparent: bool) -> Button:
	var button := Button.new()
	button.text = "" if transparent else label
	button.tooltip_text = label
	button.focus_mode = Control.FOCUS_ALL
	if transparent:
		button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		button.add_theme_stylebox_override("hover", _glow(0.22))
		button.add_theme_stylebox_override("pressed", _glow(0.35))
		button.add_theme_stylebox_override("focus", _glow(0.12))
	button.pressed.connect(func(): _on_action(action))
	return button


func _glow(alpha: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(1, 1, 1, alpha)
	box.set_corner_radius_all(18)
	return box


func _on_action(action: String) -> void:
	get_tree().call_group("village_audio", "play_sfx", "button")
	match action:
		"new_game":
			new_game_requested.emit()
		"ai_lab":
			ai_lab_requested.emit()
		"quit":
			quit_requested.emit()


## 타이틀 그림이 없을 때: 글자 제목과 일반 버튼
func _build_fallback() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 20)
	center.add_child(column)
	var title := Label.new()
	title.text = FALLBACK_TITLE
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	column.add_child(title)
	for entry in _layout.get("buttons", [{"action": "new_game", "label": "새 게임"}, {"action": "quit", "label": "종료"}]):
		var button := _make_button(String(entry["action"]), String(entry.get("label", "")), false)
		button.custom_minimum_size = Vector2(260, 56)
		button.add_theme_font_size_override("font_size", 22)
		column.add_child(button)


## 원본 타이틀 그림(새 게임·종료가 그림에 포함됨)을 수정하지 않고
## 오른쪽 상단에 교육용 실험실 버튼만 따로 추가한다.
func _build_ai_lab_button() -> void:
	var button := _make_button("ai_lab", "AI 학습 실험실", false)
	button.text = "AI 학습 실험실"
	button.anchor_left = 1.0
	button.anchor_right = 1.0
	button.offset_left = -240.0
	button.offset_right = -24.0
	button.offset_top = 22.0
	button.offset_bottom = 74.0
	button.add_theme_font_size_override("font_size", 18)
	add_child(button)
