extends RefCounted
## 화면 공통 색과 스타일 (1차 프로토타입용).
## 최종 디자인(VISUAL_SPEC.md)이 정해지면 이 파일과 assets/ui/ 그림만 바꾸면 된다.

const AssetLibrary = preload("res://village_sim/scripts/game/asset_library.gd")

const TEXT := Color("2d2a26")
const TEXT_SOFT := Color("6b6359")
const UP := Color("2f8f4e")      # 오름: 초록 (항상 ↑ 화살표와 함께 쓴다)
const DOWN := Color("c4453a")    # 내림: 빨강 (항상 ↓ 화살표와 함께 쓴다)
const PANEL := Color(0.99, 0.97, 0.93, 0.88)
const PANEL_BORDER := Color("c9bfae")
const BAR_BACK := Color("ddd5c7")
const BAR_FILL := Color("7a8ca3")
const CARD_FRAME_MARGIN := 6   # 카드 틀 그림(32×32)에서 늘어나지 않는 테두리 폭
const BEIGE := Color("f2e4c6")         # 메인 창 바탕
const BEIGE_BORDER := Color("c4a97a")
const DIALOGUE_BG := Color("fffaf0")   # 대화창 바탕
const NAME_TAG_BG := Color("8a6a43")   # 이름표 바탕
const NAME_TAG_TEXT := Color("fff6e6")


static func make_theme() -> Theme:
	var theme := Theme.new()
	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", TEXT)
	theme.set_color("font_pressed_color", "Button", TEXT)
	theme.set_color("font_focus_color", "Button", TEXT)
	theme.set_stylebox("panel", "PanelContainer", panel_box())
	theme.set_stylebox("background", "ProgressBar", _flat(BAR_BACK, 6))
	theme.set_stylebox("fill", "ProgressBar", _flat(BAR_FILL, 6))
	theme.set_stylebox("normal", "Button", _flat(Color(1, 1, 1, 0.9), 10, PANEL_BORDER))
	theme.set_stylebox("hover", "Button", _flat(Color(1, 1, 1, 1), 10, BAR_FILL))
	theme.set_stylebox("pressed", "Button", _flat(BAR_BACK, 10, BAR_FILL))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	return theme


## 작은 정보 상자(턴, 게이지, 안내, 말풍선)용 반투명 상자
static func panel_box() -> StyleBoxFlat:
	var box := _flat(PANEL, 12, PANEL_BORDER)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return box


## 메인 창·인물 카드·엔딩 카드의 베이지색 바탕.
## assets/ui/card_frame 에 실제 그림을 넣으면 그 그림을 9분할로 늘려 쓴다. (임시 도트 틀은 쓰지 않는다)
static func main_box() -> StyleBox:
	var frame := AssetLibrary.real_texture("ui/card_frame")
	if frame != null:
		var textured := StyleBoxTexture.new()
		textured.texture = frame
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			textured.set_texture_margin(side, CARD_FRAME_MARGIN)
		return textured
	var box := _flat(BEIGE, 22, BEIGE_BORDER)
	box.set_border_width_all(3)
	box.shadow_color = Color(0, 0, 0, 0.18)
	box.shadow_size = 8
	box.shadow_offset = Vector2(0, 4)
	return box


static func card_box() -> StyleBox:
	return main_box()


## 대화창: 메인 창 아래쪽의 둥근 직사각형
static func dialogue_box() -> StyleBoxFlat:
	var box := _flat(DIALOGUE_BG, 18, BEIGE_BORDER)
	box.set_border_width_all(2)
	box.content_margin_left = 20
	box.content_margin_right = 20
	box.content_margin_top = 14
	box.content_margin_bottom = 16
	return box


## 대화창 위 이름표
static func name_tag_box() -> StyleBoxFlat:
	var box := _flat(NAME_TAG_BG, 12)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 3
	box.content_margin_bottom = 4
	return box


static func level_color(level: int) -> Color:
	return UP if level > 0 else DOWN


static func _flat(color: Color, radius: int, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	if border.a > 0.0:
		box.border_color = border
		box.set_border_width_all(2)
	return box
