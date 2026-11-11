class_name HeroIcon
extends Control
## 카드·목록용 캐릭터 초상 (PNG 또는 도형). 입력은 부모에게 넘긴다.

var hero_type := "SWORD":
	set(v):
		hero_type = v
		queue_redraw()
var dim := false:
	set(v):
		dim = v
		queue_redraw()


func _init(t: String = "SWORD", px: float = 120.0) -> void:
	hero_type = t
	custom_minimum_size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	if HeroSprite.has_art(hero_type):
		queue_redraw()  # 대기 동작(숨쉬기)


func _draw() -> void:
	var a := 0.45 if dim else 1.0
	var h := minf(size.x, size.y)
	if HeroSprite.draw_static(self, hero_type, Vector2(size.x * 0.5, size.y * 0.5 + h * 0.47), h * 0.94, a):
		return
	var r := minf(size.x, size.y) * 0.34
	PlaceholderArt.draw_hero(self, hero_type, size * 0.5 + Vector2(0, -r * 0.1), r, get_theme_default_font(), 0.45 if dim else 1.0)
