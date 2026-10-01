extends SceneTree
## 링크 미리보기(오픈그래프) 이미지 만들기: web/maintheme.png → web/og.jpg (1200 × 630)
##
## 실행 (프로젝트 폴더에서):
##   godot --headless --script res://village_sim/tools/make_og_image.gd
##
## 대표 그림을 1200 × 630에 꽉 차게 맞추고 넘치는 부분만 잘라 낸다.
## 위쪽에 제목 로고가 있으므로 잘라 낼 때는 아래쪽을 더 많이 자른다 (KEEP_TOP).
## 원본과 결과물은 web/ 폴더에 둔다 (Godot이 가져오지 않도록 web/.gdignore → 게임 파일 크기에 영향 없음).
## 웹 버전을 만들 때 publish_web.ps1이 og.jpg를 함께 복사한다.

const SOURCE := "res://web/maintheme.png"
const OUT := "res://web/og.jpg"
const SIZE := Vector2i(1200, 630)
const KEEP_TOP := 0.25        # 세로로 넘칠 때 위에서 자를 비율 (0 = 위는 자르지 않음, 0.5 = 위아래 똑같이)
const JPG_QUALITY := 0.9


func _initialize() -> void:
	var source := Image.load_from_file(ProjectSettings.globalize_path(SOURCE))
	if source == null or source.is_empty():
		printerr("대표 그림을 읽지 못했습니다: " + SOURCE)
		quit(1)
		return
	source.convert(Image.FORMAT_RGB8)

	# 꽉 차게 키우거나 줄인 뒤, 넘치는 부분을 자른다 (가로는 가운데, 세로는 KEEP_TOP 비율)
	var cover := maxf(float(SIZE.x) / source.get_width(), float(SIZE.y) / source.get_height())
	var scaled := Vector2i(int(ceil(source.get_width() * cover)), int(ceil(source.get_height() * cover)))
	source.resize(scaled.x, scaled.y, Image.INTERPOLATE_LANCZOS)
	var extra := scaled - SIZE
	var origin := Vector2i(extra.x / 2, int(round(extra.y * KEEP_TOP)))
	var result: Image = source.get_region(Rect2i(origin, SIZE))

	var err: Error = result.save_jpg(ProjectSettings.globalize_path(OUT), JPG_QUALITY)
	if err != OK:
		printerr("저장하지 못했습니다: %s (%d)" % [OUT, err])
		quit(1)
		return
	print("만듦: %s (%d × %d, 원본 %d × %d에서 위 %d px · 아래 %d px 잘라 냄)" % [
		ProjectSettings.globalize_path(OUT), SIZE.x, SIZE.y, scaled.x, scaled.y, origin.y, extra.y - origin.y])
	quit()
