extends Control
## 마을 배경. 기본 배경 위에 레이어 그림을 겹치고, 지금 상태·플래그에 맞는 레이어만 서서히 보이게 한다.
## 레이어마다 정적인 그림을 살짝 살아 있게 하는 미세 움직임(anim)을 붙일 수 있다.
##
## 레이어 정의는 data/visuals/ (id, 켜지는 조건, anim), 그림은 assets/backgrounds/layers/<id>.png
## 그림이 없는 레이어는 만들지 않는다. (조건만 정의해 두고 그림은 나중에 넣어도 된다)
##
## anim 종류 (모두 선택)
##   {"type": "frames",  "fps": 2}                               <id>_1, <id>_2 … 그림을 차례로 바꿔 보여 준다 (강물 반짝임, 창문 불빛)
##   {"type": "drift",   "amplitude": [3, 2], "period": 3.0}     도트 몇 칸만큼 천천히 오간다 (굴뚝 연기, 구름)
##   {"type": "sway",    "amplitude": 1, "period": 2.8}          좌우로 아주 조금 흔들린다 (나뭇잎)
##   {"type": "flicker", "min_alpha": 0.55, "period": 1.3}       밝기가 불규칙하게 깜빡인다 (가로등, 별빛)
## 움직임은 도트 한 칸 단위로 끊어서 흐려지지 않게 한다.

const AssetLibrary = preload("res://village_sim/scripts/game/asset_library.gd")

const FADE_SECONDS := 0.4

var _layers: Dictionary = {}   # layer id -> {"image": TextureRect, "frames": Array, "anim": Dictionary, "seed": float}
var _time := 0.0


var _background_id := ""
var _background_front: TextureRect   # 지금 보이는 배경
var _background_back: TextureRect    # 바뀔 배경 (위에서 서서히 나타난 뒤 앞뒤를 바꾼다)
var _fade_seconds := 0.6


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background_front = _make_image([])
	_background_back = _make_image([])
	add_child(_background_front)
	add_child(_background_back)


## 마을 배경 전체 그림을 바꾼다. (assets/backgrounds/<id>.png) 짧게 서서히 바뀐다.
## 상황별 배경(normal / pollution / poor / complain / danger)을 고르는 규칙은 GameSession.get_background_id()
func set_background(background_id: String, fade_seconds: float = -1.0) -> void:
	if background_id == _background_id:
		return
	var frames := AssetLibrary.frames("backgrounds/" + background_id)
	if frames.is_empty():
		return
	if fade_seconds >= 0.0:
		_fade_seconds = fade_seconds
	var first := _background_id.is_empty()
	_background_id = background_id
	_background_back.texture = frames[0]
	if first:
		_swap_backgrounds()
		return
	_background_back.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_background_back, "modulate:a", 1.0, _fade_seconds)
	tween.tween_callback(_swap_backgrounds)


func _swap_backgrounds() -> void:
	_background_front.texture = _background_back.texture
	_background_back.modulate.a = 0.0


## layers: 데이터의 레이어 정의 목록 [{"id", "conditions", "anim"}] (정의 순서대로 아래에서 위로 쌓인다)
func setup(layers: Array) -> void:
	for layer in layers:
		var frames := AssetLibrary.frames("backgrounds/layers/" + String(layer["id"]))
		if frames.is_empty():
			continue   # 그림이 없는 레이어는 만들지 않는다
		var image := _make_image(frames)
		image.self_modulate.a = 0.0   # 켜고 끄기는 self_modulate, 깜빡임(flicker)은 modulate로 따로 쓴다
		add_child(image)
		_layers[layer["id"]] = {
			"image": image,
			"frames": frames,
			"anim": layer.get("anim", {}),
			"seed": float(_layers.size()) * 1.7,
		}


## active_ids: 지금 켜져야 할 레이어 id 목록 (GameSession.get_active_layers())
func refresh(active_ids: Array) -> void:
	for layer_id in _layers:
		var image: TextureRect = _layers[layer_id]["image"]
		var target := 1.0 if layer_id in active_ids else 0.0
		if image.get_meta("target", -1.0) != target:
			image.set_meta("target", target)
			create_tween().tween_property(image, "self_modulate:a", target, FADE_SECONDS)


func _process(delta: float) -> void:
	_time += delta
	for layer_id in _layers:
		var layer: Dictionary = _layers[layer_id]
		var anim: Dictionary = layer["anim"]
		if anim.is_empty():
			continue
		var image: TextureRect = layer["image"]
		var art := _art_scale(image)
		var t := _time + float(layer["seed"])
		var period := float(anim.get("period", 2.0))
		match String(anim.get("type", "")):
			"frames":
				var frames: Array = layer["frames"]
				if frames.size() > 1:
					image.texture = frames[int(_time * float(anim.get("fps", 2))) % frames.size()]
			"drift":
				var amplitude: Array = anim.get("amplitude", [2, 1])
				image.position = Vector2(
					roundf(sin(t * TAU / period) * float(amplitude[0])) * art,
					roundf(cos(t * TAU / period) * float(amplitude[1])) * art)
			"sway":
				image.position.x = roundf(sin(t * TAU / period) * float(anim.get("amplitude", 1))) * art
			"flicker":
				var low := float(anim.get("min_alpha", 0.6))
				var wave := (sin(t * TAU / period) + sin(t * TAU / (period * 0.37))) * 0.25 + 0.5
				image.modulate.a = lerpf(low, 1.0, clampf(wave, 0.0, 1.0))


## 그림 1도트가 화면에서 몇 픽셀인지 (예: 320×180 배경을 1280×720에 깔면 4)
func _art_scale(image: TextureRect) -> float:
	if image.texture == null or image.texture.get_width() == 0:
		return 1.0
	return maxf(1.0, size.x / float(image.texture.get_width()))


func _make_image(frames: Array) -> TextureRect:
	var image := TextureRect.new()
	if not frames.is_empty():
		image.texture = frames[0]
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return image
