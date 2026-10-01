extends SceneTree
## 임시 그림(placeholder) 생성 도구. 도트(픽셀) 스타일의 아주 단순한 도형으로 그린다.
##
## 실행 (프로젝트 폴더에서):
##   godot --headless --script res://village_sim/tools/make_placeholders.gd
## 결과: village_sim/assets/placeholders/ 아래 PNG (있으면 덮어씀)
##
## 최종 그림이 아니다. 실제 그림은 assets/ 아래 같은 경로·이름으로 넣으면 이 임시 그림 대신 쓰인다.
## 크기 기준 (실제 그림도 이 비율이면 화면에서 정수배로 또렷하게 커진다)
##   인물 40×52 / 상태 아이콘 12×12 / 화살표 7×9 / 카드 틀 32×32 (배경은 임시 그림 없이 실제 그림만 쓴다)

const OUT := "res://village_sim/assets/placeholders/"

const INK := Color("3b2f2a")
const SKIN := Color("f1d7bf")
const SKIN_DARK := Color("e2bf9f")
const WHITE := Color("ffffff")
const CLEAR := Color(0, 0, 0, 0)

const NPCS := {
	"luka": Color("5b7db1"),
	"cherry": Color("d08a3c"),
	"noel": Color("4f9a5b"),
	"bruno": Color("7d6b5d"),
	"cain": Color("c9952c"),
	"mina": Color("b25fa8"),
	"rio": Color("8d9a3a"),
	"owen": Color("5a6170"),
}
const EXPRESSIONS: Array[String] = ["neutral", "happy", "angry", "worried"]


func _init() -> void:
	_make_portraits()
	_make_icons()
	_make_ui()
	print("임시 그림 생성 완료: ", ProjectSettings.globalize_path(OUT))
	quit()


# --- 그리기 도구 -------------------------------------------------------------------

func _image(w: int, h: int) -> Image:
	var image := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	image.fill(CLEAR)
	return image


func _rect(image: Image, x: int, y: int, w: int, h: int, color: Color) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			_px(image, xx, yy, color)


func _px(image: Image, x: int, y: int, color: Color) -> void:
	if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
		return
	if color.a >= 1.0:
		image.set_pixel(x, y, color)
	else:
		image.set_pixel(x, y, image.get_pixel(x, y).blend(color))


func _disc(image: Image, cx: int, cy: int, r: int, color: Color) -> void:
	for y in range(-r, r + 1):
		for x in range(-r, r + 1):
			if x * x + y * y <= r * r + r:
				_px(image, cx + x, cy + y, color)


func _pixels(image: Image, points: Array, color: Color) -> void:
	for point in points:
		_px(image, point[0], point[1], color)


func _save(image: Image, relative: String) -> void:
	var path := ProjectSettings.globalize_path(OUT + relative + ".png")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	image.save_png(path)


# --- 인물 (40×52) ------------------------------------------------------------------

func _make_portraits() -> void:
	for npc_id in NPCS:
		for expression in EXPRESSIONS:
			_save(_portrait(npc_id, expression, false), "characters/%s/%s" % [npc_id, expression])
			_save(_portrait(npc_id, expression, true), "characters/%s/%s_blink" % [npc_id, expression])


func _portrait(npc_id: String, expression: String, blink: bool) -> Image:
	var color: Color = NPCS[npc_id]
	var image := _image(40, 52)
	# 임시 그림 표시: 점선 테두리
	for i in range(0, 40, 4):
		_rect(image, i, 0, 2, 1, color)
		_rect(image, i, 51, 2, 1, color)
	for i in range(0, 52, 4):
		_rect(image, 0, i, 1, 2, color)
		_rect(image, 39, i, 1, 2, color)
	# 몸, 목, 머리
	_rect(image, 9, 39, 22, 4, color)
	_rect(image, 6, 42, 28, 10, color)
	_rect(image, 17, 32, 6, 7, SKIN_DARK)
	_disc(image, 20, 22, 10, SKIN)
	_accessory(image, npc_id)
	_face(image, expression, blink)
	if npc_id == "owen":
		for x0 in [13, 21]:
			_rect(image, x0, 20, 6, 1, INK)
			_rect(image, x0, 25, 6, 1, INK)
			_rect(image, x0, 20, 1, 6, INK)
			_rect(image, x0 + 5, 20, 1, 6, INK)
		_rect(image, 19, 22, 2, 1, INK)
	return image


func _accessory(image: Image, npc_id: String) -> void:
	match npc_id:
		"luka":
			for i in 12:
				_rect(image, 9 + i * 2, 40 + i, 3, 2, WHITE)
		"cherry":
			_rect(image, 14, 41, 12, 11, Color("fff3e0"))
			_rect(image, 15, 36, 2, 5, Color("fff3e0"))
			_rect(image, 23, 36, 2, 5, Color("fff3e0"))
		"noel":
			_disc(image, 20, 8, 3, Color("3f8a4b"))
			_rect(image, 20, 10, 1, 3, Color("2d6b36"))
		"bruno":
			_rect(image, 11, 11, 18, 6, Color("f2c230"))
			_rect(image, 8, 16, 24, 2, Color("d9a400"))
		"cain":
			_rect(image, 11, 12, 18, 5, Color("2f5d8a"))
			_rect(image, 20, 16, 13, 2, Color("2f5d8a"))
			_rect(image, 7, 45, 26, 2, Color("f7f39a"))
			_rect(image, 7, 49, 26, 2, Color("f7f39a"))
		"mina":
			_rect(image, 11, 12, 18, 4, INK)
			_rect(image, 18, 10, 4, 2, INK)
			_rect(image, 9, 40, 3, 12, Color("6d3a69"))
			_rect(image, 28, 40, 3, 12, Color("6d3a69"))
		"rio":
			_rect(image, 12, 9, 16, 6, Color("e6c77f"))
			_rect(image, 4, 14, 32, 2, Color("d9b25f"))
			_rect(image, 12, 13, 16, 1, Color("b5893a"))
		"owen":
			_rect(image, 11, 12, 18, 3, Color("4a3b33"))
			_rect(image, 11, 15, 3, 3, Color("4a3b33"))


func _face(image: Image, expression: String, blink: bool) -> void:
	if blink:
		_rect(image, 15, 23, 3, 1, INK)
		_rect(image, 22, 23, 3, 1, INK)
	else:
		_rect(image, 16, 22, 2, 2, INK)
		_rect(image, 22, 22, 2, 2, INK)
	match expression:
		"neutral":
			_rect(image, 17, 28, 6, 1, INK)
		"happy":
			_pixels(image, [[16, 27], [17, 28], [18, 29], [19, 29], [20, 29], [21, 29], [22, 28], [23, 27]], INK)
		"angry":
			_pixels(image, [[14, 19], [15, 19], [16, 20], [17, 20], [22, 20], [23, 20], [24, 19], [25, 19]], INK)
			_pixels(image, [[16, 30], [17, 29], [18, 28], [19, 28], [20, 28], [21, 28], [22, 29], [23, 30]], INK)
		"worried":
			_pixels(image, [[14, 20], [15, 20], [16, 19], [17, 19], [22, 19], [23, 19], [24, 20], [25, 20]], INK)
			_pixels(image, [[16, 29], [17, 28], [18, 28], [19, 29], [20, 29], [21, 28], [22, 28], [23, 29]], INK)


# --- 상태 아이콘 (12×12) ---------------------------------------------------------------

func _make_icons() -> void:
	var image := _image(12, 12)
	_disc(image, 4, 3, 2, Color("5b7db1"))
	_rect(image, 1, 6, 7, 6, Color("5b7db1"))
	_disc(image, 9, 4, 2, Color("7d9ac7"))
	_rect(image, 7, 7, 5, 5, Color("7d9ac7"))
	_save(image, "ui/icons/residents")

	image = _image(12, 12)
	for i in 4:
		_rect(image, 5 - i, i, 2 + i * 2, 1, Color("a07a3c"))
	for x in [1, 4, 7, 10]:
		_rect(image, x, 4, 1, 6, Color("c49a52"))
	_rect(image, 0, 10, 12, 2, Color("a07a3c"))
	_save(image, "ui/icons/finance")

	image = _image(12, 12)
	for i in 9:
		_rect(image, 2 + i, 9 - i, 2, 3, Color("4f9a5b"))
	_rect(image, 1, 10, 2, 2, Color("3f7d48"))
	for i in 6:
		_px(image, 3 + i, 9 - i, Color("d8efd9"))
	_save(image, "ui/icons/environment")

	image = _image(12, 12)
	_rect(image, 1, 1, 10, 6, Color("3a7bbf"))
	_rect(image, 2, 7, 8, 2, Color("3a7bbf"))
	_rect(image, 4, 9, 4, 2, Color("3a7bbf"))
	_rect(image, 5, 11, 2, 1, Color("3a7bbf"))
	_pixels(image, [[3, 5], [4, 6], [5, 7], [6, 6], [7, 5], [8, 4], [9, 3]], WHITE)
	_save(image, "ui/icons/safety")


# --- 화면 요소 ---------------------------------------------------------------------

func _make_ui() -> void:
	for direction in ["up", "down"]:
		var color := Color("2f8f4e") if direction == "up" else Color("c4453a")
		var image := _image(7, 9)
		for i in 4:
			var y := i if direction == "up" else 8 - i
			_rect(image, 3 - i, y, 1 + i * 2, 1, color)
		var stem_y := 4 if direction == "up" else 0
		_rect(image, 2, stem_y, 3, 5, color)
		_save(image, "ui/arrow_" + direction)

	# 카드 틀 32×32: 2픽셀 단위로 그린 도트 테두리. 9분할로 늘려 쓴다 (바깥 6픽셀은 늘어나지 않음)
	var frame := _image(32, 32)
	_rect(frame, 2, 2, 28, 28, Color("fbf7ef"))
	_rect(frame, 2, 0, 28, 2, Color("9c8e78"))
	_rect(frame, 2, 30, 28, 2, Color("9c8e78"))
	_rect(frame, 0, 2, 2, 28, Color("9c8e78"))
	_rect(frame, 30, 2, 2, 28, Color("9c8e78"))
	_rect(frame, 2, 2, 28, 2, Color("ffffff"))
	_rect(frame, 2, 26, 28, 2, Color("e6dccb"))
	_save(frame, "ui/card_frame")


