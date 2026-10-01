extends SceneTree
## 링크 미리보기(오픈그래프) 이미지 만들기: assets/title/title.png → web/og.jpg (1200 × 630)
##
## 실행 (프로젝트 폴더에서):
##   godot --headless --script res://village_sim/tools/make_og_image.gd
##
## 타이틀 그림(16:9)을 자르지 않고 가운데에 통째로 넣고, 남는 양옆은 같은 그림을 흐리고 어둡게 깔아 채운다.
## 결과물은 web/ 폴더에 둔다 (Godot이 가져오지 않도록 web/.gdignore). 웹 버전을 만들 때 publish_web.ps1이 함께 복사한다.

const SOURCE := "res://village_sim/assets/title/title.png"
const OUT := "res://web/og.jpg"
const SIZE := Vector2i(1200, 630)
const BLUR_SIZE := Vector2i(60, 32)   # 이만큼 줄였다가 키워 흐리게 만든다
const BACK_DARKEN := 0.55             # 뒷배경 밝기 (1 = 그대로)
const JPG_QUALITY := 0.9


func _initialize() -> void:
	var source := Image.load_from_file(ProjectSettings.globalize_path(SOURCE))
	if source == null or source.is_empty():
		printerr("타이틀 그림을 읽지 못했습니다: " + SOURCE)
		quit(1)
		return
	source.convert(Image.FORMAT_RGBA8)

	# 뒷배경: 화면을 꽉 채우도록 키워 가운데를 자르고, 흐리게 + 어둡게
	var cover := maxf(float(SIZE.x) / source.get_width(), float(SIZE.y) / source.get_height())
	var back: Image = source.duplicate()
	back.resize(int(ceil(source.get_width() * cover)), int(ceil(source.get_height() * cover)), Image.INTERPOLATE_LANCZOS)
	back = back.get_region(Rect2i((back.get_size() - SIZE) / 2, SIZE))
	back.resize(BLUR_SIZE.x, BLUR_SIZE.y, Image.INTERPOLATE_BILINEAR)
	back.resize(SIZE.x, SIZE.y, Image.INTERPOLATE_CUBIC)
	for y in SIZE.y:
		for x in SIZE.x:
			var c := back.get_pixel(x, y)
			back.set_pixel(x, y, Color(c.r * BACK_DARKEN, c.g * BACK_DARKEN, c.b * BACK_DARKEN, 1.0))

	# 앞: 그림 전체가 들어가도록 줄여 가운데에
	var fit := minf(float(SIZE.x) / source.get_width(), float(SIZE.y) / source.get_height())
	var front: Image = source.duplicate()
	front.resize(int(round(source.get_width() * fit)), int(round(source.get_height() * fit)), Image.INTERPOLATE_LANCZOS)
	back.blend_rect(front, Rect2i(Vector2i.ZERO, front.get_size()), (SIZE - front.get_size()) / 2)

	back.convert(Image.FORMAT_RGB8)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT).get_base_dir())
	var err := back.save_jpg(ProjectSettings.globalize_path(OUT), JPG_QUALITY)
	if err != OK:
		printerr("저장하지 못했습니다: %s (%d)" % [OUT, err])
		quit(1)
		return
	print("만듦: %s (%d × %d)" % [ProjectSettings.globalize_path(OUT), SIZE.x, SIZE.y])
	quit()
