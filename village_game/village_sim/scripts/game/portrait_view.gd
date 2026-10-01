extends Control
## 인물 초상 한 칸. 정적인 그림도 살아 있어 보이게 하는 미세 연출을 맡는다.
##
## 맞추는 방식 (fit_mode)
##   "cover"   : 칸을 꽉 채우고 넘치는 부분은 잘라 낸다. 위쪽(얼굴)을 기준으로 붙인다. 카드 그림처럼 보인다.
##   "contain" : 그림 전체가 칸 안에 들어간다. 아래쪽 가운데에 붙는다.
##   작은 도트 그림을 키울 때는 정수배(×2, ×3 …)로 키워 도트가 고르게 보이게 한다.
## 모양
##   둥근 모서리 안쪽만 그림이 보이고, 그 위에 테두리를 그린다. (둥글기·색·굵기는 UiStyle)
## 미세 연출
##   숨쉬기: 테두리 안에서 그림만 아주 미세하게 위아래로 움직인다.
##   눈 깜빡임: <이름>_blink 그림이 있으면 가끔 0.12초 동안 바꿔 보여 준다. 없으면 깜빡이지 않는다.
##   등장: play_enter()를 부르면 테두리째 아래에서 슥 올라오며 나타난다.
##   반응: react()를 부르면 테두리째 짧게 좌우로 흔들린다.
##
## 그림은 AssetLibrary.portrait_set()이 찾는다. 이 노드는 그림 파일 이름을 모른다.

const AssetLibrary = preload("res://village_sim/scripts/game/asset_library.gd")
const UiStyle = preload("res://village_sim/scripts/game/ui_style.gd")

const BREATH_PERIOD := 2.6      # 숨쉬기 한 번(초)
const BREATH_PIXELS := 2.0      # 화면 픽셀 기준 움직임 (도트 그림을 키운 경우에는 도트 1칸)
const BLINK_SECONDS := 0.12
const BLINK_INTERVAL := Vector2(2.5, 5.0)   # 다음 깜빡임까지 (최소, 최대) 초
const ENTER_PIXELS := 36.0
const ENTER_SECONDS := 0.3
const COVER_TOP := 0.02          # cover 모드에서 그림 위쪽을 얼마나 잘라 낼지 (그림 높이 비율)

@export_enum("cover", "contain") var fit_mode := "cover"

var _holder: Control      # 모양 + 테두리 묶음 (등장·흔들림 때 함께 움직인다)
var _mask: Panel          # 둥근 모서리 모양. 그림은 이 모양 안쪽만 그려진다
var _frame: Panel         # 테두리 (그림 위에 겹침)
var _image: TextureRect
var _texture: Texture2D
var _blink: Texture2D
var _scale := 1.0
var _pixel_art := false
var _time := 0.0
var _next_blink := 3.0
var _blink_left := 0.0
var _enter_offset := 0.0
var _shake_x := 0.0
var _tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_holder = Control.new()
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_holder)

	_mask = Panel.new()
	_mask.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	_mask.add_theme_stylebox_override("panel", UiStyle.portrait_mask())
	_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_holder.add_child(_mask)

	_image = TextureRect.new()
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_SCALE
	_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mask.add_child(_image)

	_frame = Panel.new()
	_frame.add_theme_stylebox_override("panel", UiStyle.portrait_frame())
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_holder.add_child(_frame)
	resized.connect(_layout)


## 인물과 표정을 바꾼다. 그림이 없으면 false.
func set_character(npc_id: String, expression: String) -> bool:
	var found := AssetLibrary.portrait_set(npc_id, expression)
	_texture = found.get("texture")
	_blink = found.get("blink")
	_image.texture = _texture
	_holder.visible = _texture != null
	_layout()
	return _texture != null


## 아래에서 슥 올라오며 나타난다.
func play_enter() -> void:
	_restart_tween()
	_enter_offset = ENTER_PIXELS
	_holder.modulate.a = 0.0
	_holder.position.y = _enter_offset
	_tween.tween_property(self, "_enter_offset", 0.0, ENTER_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_holder, "modulate:a", 1.0, ENTER_SECONDS * 0.7)


## 선택 직후 반응: 짧게 좌우로 흔들린다. (약 0.25초)
func react() -> void:
	_restart_tween().set_parallel(false)
	var step := maxf(_scale, 1.0) if _pixel_art else 3.0
	for x in [-2.0 * step, 2.0 * step, -1.0 * step, 0.0]:
		_tween.tween_property(self, "_shake_x", x, 0.06)


func _restart_tween() -> Tween:
	if _tween != null:
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	return _tween


func _process(delta: float) -> void:
	if _texture == null:
		return
	_time += delta
	var unit := _scale if _pixel_art else 1.0
	var breath := roundf(sin(_time * TAU / BREATH_PERIOD) * BREATH_PIXELS / unit) * unit if _pixel_art \
		else sin(_time * TAU / BREATH_PERIOD) * BREATH_PIXELS
	_holder.position = Vector2(_shake_x, _enter_offset)
	_image.position = _base_position() + Vector2(0, breath)
	if _blink != null:
		if _blink_left > 0.0:
			_blink_left -= delta
			if _blink_left <= 0.0:
				_image.texture = _texture
				_next_blink = randf_range(BLINK_INTERVAL.x, BLINK_INTERVAL.y)
		else:
			_next_blink -= delta
			if _next_blink <= 0.0:
				_image.texture = _blink
				_blink_left = BLINK_SECONDS


func _layout() -> void:
	if _image == null or size.x <= 0.0 or size.y <= 0.0:
		return
	_holder.size = size
	_mask.size = size
	_frame.size = size
	if _texture == null:
		return
	var texture_size := _texture.get_size()
	var fit_w := size.x / texture_size.x
	var fit_h := size.y / texture_size.y
	var fit := maxf(fit_w, fit_h) if fit_mode == "cover" else minf(fit_w, fit_h)
	_pixel_art = fit > 1.0
	_scale = floorf(fit) if _pixel_art and fit_mode == "contain" else fit
	_image.size = texture_size * _scale
	AssetLibrary.apply_filter(_image, _texture, _image.size)
	_image.position = _base_position()


## cover: 가로 가운데, 위쪽 기준 / contain: 아래쪽 가운데. 정수 위치로 맞춘다.
## cover에서는 숨쉬기 때 위쪽에 틈이 보이지 않게 숨쉬기 폭 이상은 잘라 둔다.
func _base_position() -> Vector2:
	var x := roundf((size.x - _image.size.x) / 2.0)
	if fit_mode == "cover":
		return Vector2(x, -maxf(roundf(_image.size.y * COVER_TOP), BREATH_PIXELS * 2.0))
	return Vector2(x, roundf(size.y - _image.size.y))
