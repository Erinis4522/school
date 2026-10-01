extends RefCounted
## 그림 찾기. 실제 그림이 있으면 그것을, 없으면 임시 그림(placeholder)을 쓴다.
##
##   실제 그림   : res://village_sim/assets/<상대 경로>.<png|webp|jpg|svg>
##   임시 그림   : res://village_sim/assets/placeholders/<같은 상대 경로>.<...>
##
## 실제 그림 폴더에 같은 이름의 파일을 넣기만 하면 교체된다. 코드는 고치지 않는다.
## (폴더 구조와 파일 이름은 assets/README.md 참고)

const ROOT := "res://village_sim/assets/"
const PLACEHOLDER_ROOT := "res://village_sim/assets/placeholders/"
const EXTENSIONS: Array[String] = ["png", "webp", "jpg", "svg"]
const DEFAULT_EXPRESSION := "neutral"
## 게임 속 표정 → 그 표정 그림이 없을 때 대신 찾을 그림 표정 (앞쪽부터)
const EXPRESSION_ALIASES := {
	"happy": ["delight"],
	"worried": ["sad"],
	"angry": ["sad"],
	"delight": ["happy"],
	"sad": ["worried", "angry"],
}

static var _cache: Dictionary = {}


## 상대 경로(확장자 없이)로 그림을 찾는다. 실제 → 임시 순서. 둘 다 없으면 null.
static func texture(relative: String) -> Texture2D:
	var found := _find(ROOT, relative)
	if found == null:
		found = _find(PLACEHOLDER_ROOT, relative)
	return found


## 인물 초상. 실제 그림의 해당 표정 → 실제 그림의 기본 표정 → 임시 그림의 해당 표정 → 임시 그림의 기본 표정.
## (실제 그림이 일부만 있어도 임시 그림과 섞이지 않도록 실제 그림을 먼저 끝까지 찾는다)
static func portrait(npc_id: String, expression: String) -> Texture2D:
	return portrait_set(npc_id, expression).get("texture")


## 초상과 눈 깜빡임 그림: {"texture": 그림, "blink": 같은 이름 뒤에 _blink 가 붙은 그림 또는 null}
## 깜빡임 그림이 없으면 깜빡이지 않는다. (나중에 <이름>_blink.png 만 넣으면 깜빡이기 시작한다)
##
## 파일 이름은 두 방식 모두 된다.
##   characters/<인물 id>_<표정>.png      예: characters/luka_delight.png
##   characters/<인물 id>/<표정>.png      예: characters/luka/delight.png
## 게임 속 표정 이름과 그림 표정 이름이 다르면 EXPRESSION_ALIASES 순서대로 찾는다. (happy → delight 등)
static func portrait_set(npc_id: String, expression: String) -> Dictionary:
	if npc_id.is_empty():
		return {}
	var expr := expression if not expression.is_empty() else DEFAULT_EXPRESSION
	var names: Array = [expr]
	names.append_array(EXPRESSION_ALIASES.get(expr, []))
	names.append(DEFAULT_EXPRESSION)
	for root in [ROOT, PLACEHOLDER_ROOT]:
		for name in names:
			for base in ["characters/%s_%s" % [npc_id, name], "characters/%s/%s" % [npc_id, name]]:
				var found := _find(root, base)
				if found != null:
					return {"texture": found, "blink": _find(root, base + "_blink")}
	return {}


## 작은 그림(도트)을 크게 키울 때는 또렷하게(Nearest), 큰 그림을 줄일 때는 부드럽게(밉맵) 보이도록 필터를 고른다.
static func apply_filter(item: CanvasItem, texture: Texture2D, display_size: Vector2) -> void:
	if texture == null:
		return
	var enlarged := display_size.x > texture.get_width() * 1.01
	item.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if enlarged else CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


## 프레임 애니메이션용 그림 묶음. <이름>_1, <이름>_2, ... 가 있으면 그 순서대로, 없으면 <이름> 한 장.
## 실제 그림 쪽에 하나라도 있으면 실제 그림만 쓴다.
static func frames(relative: String) -> Array[Texture2D]:
	for root in [ROOT, PLACEHOLDER_ROOT]:
		var result: Array[Texture2D] = []
		var index := 1
		while true:
			var frame := _find(root, "%s_%d" % [relative, index])
			if frame == null:
				break
			result.append(frame)
			index += 1
		if result.is_empty():
			var single := _find(root, relative)
			if single != null:
				result.append(single)
		if not result.is_empty():
			return result
	var none: Array[Texture2D] = []
	return none


## 실제 그림만 찾는다. (임시 그림은 쓰지 않음) 없으면 null.
static func real_texture(relative: String) -> Texture2D:
	return _find(ROOT, relative)


static func stat_icon(stat_id: String) -> Texture2D:
	return texture("ui/icons/" + stat_id)


static func _find(root: String, relative: String) -> Texture2D:
	var key := root + relative
	if _cache.has(key):
		return _cache[key]
	var result: Texture2D = null
	for extension in EXTENSIONS:
		var path := "%s%s.%s" % [root, relative, extension]
		if ResourceLoader.exists(path):
			result = load(path) as Texture2D
			if result != null:
				break
	_cache[key] = result
	return result
