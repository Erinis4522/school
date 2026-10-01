extends Control
## 게임 화면 (1차 프로토타입용 배치). 미연시(비주얼 노벨)처럼 가운데 인물 + 아래 대화창 구성.
##
## 구성
##   가운데: 베이지색 메인 창. 위쪽에 인물이 서 있고, 아래에 둥근 대화창(이름표 + 대사)이 있다.
##   메인 창 뒤: 왼쪽·오른쪽 인물 카드 두 장. 평소에는 메인 창 뒤에 숨어 있다.
##
## 한 사건의 흐름
##   (처음 보는 인물이면 자기소개) → 안건 소개(안건을 올린 인물 + 사건 제목·설명)
##   → 왼쪽을 지지하는 인물의 한마디 → 오른쪽을 지지하는 인물의 한마디 → 선택
##   선택: 메인 창 위에 "당신의 선택은?" 안내 그림이 뜨고, 메인 창 왼쪽에 왼쪽 지지자, 오른쪽에 오른쪽 지지자가 선다.
##         메인 창의 왼쪽/오른쪽을 누르면 그쪽 지지자의 인물 카드가 메인 창 뒤에서 비스듬히 펼쳐진다.
##         (인물 그림 / 선택지 문구 / 예상 변화) 반대쪽을 누르면 카드가 바뀌고, 같은 쪽을 한 번 더 누르면 결정.
##   결정: 인물 카드가 들어가고, 고른 쪽 지지자가 메인 창 가운데에 올라와 반응한다. 대화창에는 반응 대사와 결과.
##   대사·결과·중간 결산에서는 아무 곳이나 누르면 다음으로 넘어간다.
##   키보드: ← / → 는 같은 동작, Enter / Space 는 결정 또는 다음
##
## 표시와 입력만 맡고 게임 규칙은 모른다. 선택은 choose()로, 넘기기는 proceed()로 전달한다.
## 정확한 숫자는 보여 주지 않는다. 그림은 AssetLibrary가 찾는다(실제 그림 → 임시 그림).

enum Phase { CHOOSING, RESULT, CHECKPOINT, DIALOGUE }

const TextUtil = preload("res://village_sim/scripts/game/text_util.gd")
const AssetLibrary = preload("res://village_sim/scripts/game/asset_library.gd")
const UiStyle = preload("res://village_sim/scripts/game/ui_style.gd")
const PortraitView = preload("res://village_sim/scripts/game/portrait_view.gd")
const PencilCircle = preload("res://village_sim/scripts/game/pencil_circle.gd")

const SIDES: Array[String] = ["left", "right"]
const AUDIO_GROUP := "village_audio"   # audio_player.gd 의 GROUP
const MAIN_SIZE := Vector2(640, 520)          # 메인 창 (글이 길면 세로로 늘어난다)
const STAGE_PORTRAIT := Vector2(220, 250)     # 메인 창 인물 (가운데 한 명, 선택 때는 좌우 두 명)
const STAGE_PAIR_GAP := 110                   # 선택 때 좌우 두 인물 사이 간격
const BANNER_WIDTH := 400.0                   # 선택 안내 그림(assets/ui/choice) 폭. 높이는 그림 비율대로
const BANNER_OVERLAP := 14.0                  # 선택 안내 그림이 메인 창 위 테두리를 덮는 정도
const BANNER_SPACE := 80                      # 선택 안내 그림이 들어갈 자리 (메인 창 위 빈칸)
const STAGE_PAIR_PORTRAIT := Vector2(220, 226) # 선택 때 좌우 지지자 (아래에 예상 변화가 붙는다)
const PERSON_CARD_SIZE := Vector2(300, 470)   # 인물 카드 (고정 크기)
const PERSON_PORTRAIT_HEIGHT := 200
const CIRCLE_DELAY := 0.18                    # 카드가 펼쳐지기 시작하고 빨간 동그라미를 긋기까지
const PERSON_HIDDEN_MARGIN := 70              # 인물 카드가 메인 창 뒤에 가려지는 안쪽 폭
const FAN_OFFSET := 410.0                     # 펼쳐졌을 때 메인 창 중심에서 옆으로 나오는 거리
const FAN_DROP := 40.0                        # 펼쳐졌을 때 아래로 내려오는 거리
const FAN_DEGREES := 6.0                      # 펼쳐졌을 때 기울기
const FAN_SECONDS := 0.26
const CARD_RENDER_PAD := 16                   # 카드를 따로 그릴 때 그림자가 잘리지 않게 두는 바깥 여백
const BOUNCE_PIXELS := 7.0
const SHAKE_PIXELS := 5.0
const INPUT_COOLDOWN_MS := 280                # 화면이 바뀐 직후 연타로 넘어가 버리지 않게

const SIDE_HEADINGS := {"left": "◀ 왼쪽 의견", "right": "오른쪽 의견 ▶"}
const GUIDE_START := "메인 창의 왼쪽이나 오른쪽을 눌러 선택지를 펼쳐 보세요."
const GUIDE_PREVIEW := "같은 쪽을 한 번 더 누르면 결정합니다. 반대쪽을 누르면 다른 선택지가 나와요."
const GUIDE_NEXT := "아무 곳이나 누르면 다음으로 넘어갑니다."

var _session
var _phase := Phase.CHOOSING
var _event: Dictionary = {}
var _hints: Dictionary = {}
var _preview_side := ""
var _input_ready_at := 0
var _stat_names: Dictionary = {}   # stat_id -> 화면 이름
var _stat_views: Dictionary = {}   # stat_id -> {"row", "icon", "bar", "marker"}
var _side_cards: Dictionary = {}   # "left" / "right" -> {"card", "render", "portrait", "name", "choice", "outlook", "circle", "tween"}
var _shown_npc := ""

var _stats_box: VBoxContainer
var _turn_label: Label
var _main: PanelContainer
var _stage: HBoxContainer
var _stage_portrait                 # PortraitView (가운데 한 명)
var _stage_sides: Dictionary = {}   # "left" / "right" -> PortraitView (선택 때 좌우 지지자)
var _stage_holders: Dictionary = {} # "left" / "right" -> 초상화 + 예상 변화 묶음
var _stage_chips: Dictionary = {}   # "left" / "right" -> 예상 변화 (아이콘 + 화살표)
var _banner: TextureRect            # 선택할 때 메인 창 위에 뜨는 안내 그림
var _banner_tween: Tween
var _heading_box: PanelContainer    # 사건 제목 칸
var _heading_label: Label           # 메인 창 위쪽 제목 (사건 이름)
var _subheading_label: Label        # 제목 아래 작은 안내 (왼쪽·오른쪽 의견, 고른 선택지)
var _name_tag: PanelContainer
var _name_label: Label
var _line_label: Label
var _sub_label: Label
var _guide_label: Label


func _ready() -> void:
	theme = UiStyle.make_theme()
	_build_layout()


func setup(session) -> void:
	_session = session
	for stat in session.config["stats"]:
		_stat_names[stat["id"]] = stat["name"]
		_add_stat_view(stat["id"], stat["name"])
	_ignore_mouse_on_children()
	session.dialogue_presented.connect(_on_dialogue_presented)
	session.event_presented.connect(_on_event_presented)
	session.choice_resolved.connect(_on_choice_resolved)
	session.checkpoint_presented.connect(_on_checkpoint_presented)
	session.stats_changed.connect(_on_stats_changed)


# --- 조작 ------------------------------------------------------------------------

## 메인 창의 한쪽을 눌렀을 때. 처음 누르면 그쪽 인물 카드가 펼쳐지고, 같은 쪽을 다시 누르면 결정.
func select_side(side: String) -> void:
	if _phase != Phase.CHOOSING:
		return
	if _preview_side == side:
		_sfx("card_select")
		_session.choose(side)
		return
	if not _preview_side.is_empty():
		_retract(_preview_side)
	_preview_side = side
	_fill_side_card(side)
	_fan_out(side)
	_stage_sides[side].react()
	_sfx("card_out")
	_guide_label.text = GUIDE_PREVIEW
	_show_markers(_hints.get(side, {}))


func is_showing_result() -> bool:
	return _phase == Phase.RESULT


func is_showing_checkpoint() -> bool:
	return _phase == Phase.CHECKPOINT


func is_showing_dialogue() -> bool:
	return _phase == Phase.DIALOGUE


## 대사·결과·중간 결산에서 다음으로 넘어간다.
func advance() -> void:
	if _phase != Phase.CHOOSING:
		_sfx("advance")
		_session.proceed()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if not _input_ready():
			return
		if _phase == Phase.CHOOSING:
			var center_x := _main.get_global_rect().get_center().x
			select_side("left" if get_global_mouse_position().x < center_x else "right")
		else:
			advance()


func _unhandled_input(event: InputEvent) -> void:
	if not _input_ready():
		return
	if event.is_action_pressed("ui_left"):
		select_side("left")
	elif event.is_action_pressed("ui_right"):
		select_side("right")
	elif event.is_action_pressed("ui_accept"):
		if _phase != Phase.CHOOSING:
			advance()
		elif not _preview_side.is_empty():
			select_side(_preview_side)
	else:
		return
	get_viewport().set_input_as_handled()


# --- 신호 처리 -------------------------------------------------------------------

## 대사: 첫 인사, 자기소개, 안건 소개, 찬반 의견. 말하는 인물이 가운데에 서고 대화창에 한 줄씩.
func _on_dialogue_presented(dialogue: Dictionary) -> void:
	_phase = Phase.DIALOGUE
	_preview_side = ""
	_show_banner(false)
	for side in SIDES:
		_retract(side)
	_update_turn_label()
	_show_markers({})
	var npc: Dictionary = dialogue.get("npc", {})
	var kind := String(dialogue.get("kind", ""))
	_show_speaker(npc, String(dialogue.get("expression", "neutral")), false)
	var text := String(dialogue.get("text", ""))
	match kind:
		"topic":
			# 안건 소개: 위쪽 제목에 사건 이름, 대화창에는 이름표 없이 사건 설명 (따옴표 없음)
			_set_heading(String(dialogue.get("event_title", "")), "")
			_set_box("", text, "")
		"argument":
			var side := String(dialogue.get("side", ""))
			_set_heading(String(dialogue.get("event_title", "")), SIDE_HEADINGS.get(side, ""))
			_set_box(_npc_name(npc), "“%s”" % text, "")
		_:
			# 첫 인사·자기소개: 제목 없이 인물과 대사만
			_set_heading("", "")
			_set_box(_npc_name(npc), "“%s”" % text, "")
	_guide_label.text = GUIDE_NEXT
	_lock_input()


## 선택: 메인 창 위에 선택 안내 그림, 위쪽에 사건 제목, 왼쪽·오른쪽에 각 선택지의 지지자, 대화창에는 사건 설명.
## 좌우를 눌러 지지자 카드를 펼친다.
func _on_event_presented(event: Dictionary, hints: Dictionary) -> void:
	_phase = Phase.CHOOSING
	_event = event
	_hints = hints
	_preview_side = ""
	for side in SIDES:
		_retract(side)
	_update_turn_label()
	_show_pair()
	_show_banner(true)
	_set_heading(String(event["title"]), "어떻게 할까요?")
	_set_box("", String(event["description"]), "")
	_guide_label.text = GUIDE_START
	_show_markers({})
	_lock_input()


## 결과: 인물 카드가 들어가고, 고른 쪽 지지자가 가운데에 올라와 반응한다. 대화창에는 반응 대사와 결과. 게이지가 움직인다.
func _on_choice_resolved(result: Dictionary) -> void:
	_phase = Phase.RESULT
	_preview_side = ""
	_show_banner(false)
	for side in SIDES:
		_retract(side)
	var reaction: Dictionary = result.get("reaction", {})
	_set_heading(String(_event.get("title", "")), "▶ " + String(result["choice_text"]))
	if reaction.is_empty():
		_show_speaker({}, "", false)
		_set_box("", String(result["text"]), "")
	else:
		_show_speaker(reaction["npc"], String(reaction["expression"]), true)
		var line := "“%s”" % reaction["text"] if not String(reaction["text"]).is_empty() else ""
		_set_box(_npc_name(reaction["npc"]), line, String(result["text"]))
	_guide_label.text = GUIDE_NEXT
	if result.get("important", false):
		_pixel_burst(_stage_portrait if _stage.visible else _main)

	# 상태 반응: 게이지 옆 화살표가 반짝이고, 아이콘이 튀거나 흔들린다.
	var changes: Dictionary = result["changes"]
	_show_markers(changes)
	_flash_markers(changes)
	for stat_id in changes:
		_react(stat_id, int(changes[stat_id]))
	_lock_input()


## 중간 결산: 인물 없이 대화창에 마을 분위기(숫자 없이 문장으로)와 이번 막의 주요 결정.
func _on_checkpoint_presented(checkpoint: Dictionary) -> void:
	_phase = Phase.CHECKPOINT
	_show_banner(false)
	for side in SIDES:
		_retract(side)
	_show_speaker({}, "", false)
	var memories: Array = checkpoint["memories"]
	var recall := ""
	if not memories.is_empty():
		recall = "그동안의 주요 결정\n"
		for memory in memories:
			recall += "· " + String(memory) + "\n"
	_set_heading(String(checkpoint["title"]), "")
	_set_box("", checkpoint["intro"] + "\n\n" + " ".join(PackedStringArray(checkpoint["lines"])), recall.strip_edges())
	_guide_label.text = GUIDE_NEXT
	_show_markers({})
	_lock_input()


func _on_stats_changed(ratios: Dictionary) -> void:
	for stat_id in ratios:
		if _stat_views.has(stat_id):
			_stat_views[stat_id]["bar"].value = ratios[stat_id]


# --- 메인 창 ---------------------------------------------------------------------

## 가운데 인물. 다른 인물이면 아래에서 슥 올라오고, 같은 인물이면 표정만 바꾼다(react면 흔들림). 인물이 없으면 숨긴다.
func _show_speaker(npc: Dictionary, expression: String, react: bool) -> void:
	for side in SIDES:
		_stage_holders[side].visible = false
	var npc_id := String(npc.get("id", ""))
	var shown: bool = _stage_portrait.set_character(npc_id, expression) if not npc_id.is_empty() else false
	_stage_portrait.visible = shown
	_stage.visible = shown
	if not shown:
		_shown_npc = ""
		return
	if npc_id != _shown_npc:
		_shown_npc = npc_id
		_stage_portrait.play_enter()
	elif react:
		_stage_portrait.react()


## 선택할 때: 가운데 인물 대신 메인 창 왼쪽에 왼쪽 지지자, 오른쪽에 오른쪽 지지자. (담담한 neutral 얼굴)
## 밝은 얼굴(delight)은 그쪽을 눌러 옆으로 펼쳐지는 인물 카드에서만 쓴다.
## 각 초상화 아래에는 그 선택지를 고르면 달라질 상태(아이콘 + 화살표)를 보여 준다.
## 그림이 없는 쪽은 빈자리로 둔다(반대쪽 인물이 가운데로 쏠리지 않게).
func _show_pair() -> void:
	_stage_portrait.visible = false
	_shown_npc = ""   # 결과에서 고른 쪽 지지자가 가운데에 새로 올라오게
	var any := false
	for side in SIDES:
		var view = _stage_sides[side]
		var preview: Dictionary = _session.get_side_preview(side)
		var found: bool = view.set_character(String(preview["npc"].get("id", "")), "neutral")
		_stage_holders[side].visible = true
		_fill_effect_chips(_stage_chips[side], _hints.get(side, {}))
		view.modulate.a = 1.0 if found else 0.0
		if found:
			view.play_enter()
		any = any or found
	_stage.visible = any


## 선택 안내 그림: 선택할 때 메인 창 위에 톡 튀어나오고, 다른 때는 숨는다.
func _show_banner(on: bool) -> void:
	if _banner.texture == null:
		return
	if _banner_tween != null:
		_banner_tween.kill()
	if not on:
		_banner.visible = false
		return
	_place_banner()
	_banner.visible = true
	_banner.pivot_offset = _banner.size / 2.0
	_banner.scale = Vector2(0.85, 0.85)
	_banner.modulate.a = 0.0
	_banner_tween = create_tween().set_parallel(true)
	_banner_tween.tween_property(_banner, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, 0.18)


## 메인 창 위쪽 가운데에 붙인다. (메인 창이 글 때문에 커져도 따라간다. 화면 위로 넘치지 않게)
func _place_banner() -> void:
	var texture_size := _banner.texture.get_size()
	_banner.size = Vector2(BANNER_WIDTH, roundf(BANNER_WIDTH * texture_size.y / texture_size.x))
	var main_rect := _main.get_global_rect()
	var origin := get_global_rect().position
	var top := maxf(main_rect.position.y + BANNER_OVERLAP - _banner.size.y, origin.y)
	_banner.position = Vector2(main_rect.get_center().x - _banner.size.x / 2.0, top) - origin


## 메인 창 위쪽 제목 칸(사건 이름)과 그 아래 작은 안내. 빈 글은 숨긴다.
func _set_heading(title: String, sub: String) -> void:
	_heading_box.visible = not title.is_empty()
	_heading_label.text = title
	_subheading_label.visible = not sub.is_empty()
	_subheading_label.text = TextUtil.keep_words(sub)


## 대화창: 이름표(인물 이름), 큰 글(대사), 작은 글(결과). 빈 글은 숨긴다.
func _set_box(tag: String, line: String, sub: String) -> void:
	_name_tag.visible = not tag.is_empty()
	_name_label.text = tag
	_line_label.visible = not line.is_empty()
	_line_label.text = TextUtil.keep_words(line)
	_sub_label.visible = not sub.is_empty()
	_sub_label.text = TextUtil.keep_words(sub)


## 인물 이름만 (예: "케인")
func _npc_name(npc: Dictionary) -> String:
	return String(npc.get("name", ""))


# --- 인물 카드 -------------------------------------------------------------------

## 인물 카드 내용: 그쪽 지지자(밝은 얼굴), 이름, 선택지 문구, 이걸 고르면 마을이 어떻게 될지 내다보는 한마디
## (예상 변화 아이콘은 메인 창의 초상화 아래에 있다)
func _fill_side_card(side: String) -> void:
	var view: Dictionary = _side_cards[side]
	var preview: Dictionary = _session.get_side_preview(side)
	var npc: Dictionary = preview["npc"]
	view["portrait"].visible = view["portrait"].set_character(String(npc.get("id", "")), preview["expression"])
	view["name"].text = _npc_name(npc)
	view["choice"].text = TextUtil.keep_words(preview["text"])
	var outlook := String(preview.get("outlook", ""))
	view["outlook"].text = TextUtil.keep_words("“%s”" % outlook) if not outlook.is_empty() else ""
	view["outlook"].get_parent().visible = not outlook.is_empty()


## 인물 카드가 메인 창 뒤에 숨어 있을 때의 위치 (메인 창 중심에 겹침)
func _rest_position(card: Control) -> Vector2:
	return _main.get_global_rect().get_center() - get_global_rect().position - card.size / 2.0


## 메인 창 뒤에서 비스듬히 펼쳐져 나온다.
func _fan_out(side: String) -> void:
	var view: Dictionary = _side_cards[side]
	var card: Control = view["card"]
	var direction := -1.0 if side == "left" else 1.0
	card.pivot_offset = Vector2(card.size.x / 2.0, card.size.y)
	view["render"].render_target_update_mode = SubViewport.UPDATE_ALWAYS   # 숨쉬기·깜빡임이 보이도록 펼쳐져 있는 동안 계속 그린다
	if not card.visible:
		card.position = _rest_position(card)
		card.rotation_degrees = 0.0
		card.visible = true
	var target := _rest_position(card) + Vector2(FAN_OFFSET * direction, FAN_DROP)
	var tween := _restart_tween(view)
	tween.tween_property(card, "position", target, FAN_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "rotation_degrees", FAN_DEGREES * direction, FAN_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	view["circle"].play(CIRCLE_DELAY)   # 대사창에 빨간 색연필 동그라미


## 메인 창 뒤로 다시 들어간다.
func _retract(side: String) -> void:
	var view: Dictionary = _side_cards[side]
	var card: Control = view["card"]
	if not card.visible:
		return
	var tween := _restart_tween(view)
	tween.tween_property(card, "position", _rest_position(card), 0.18).set_ease(Tween.EASE_IN)
	tween.tween_property(card, "rotation_degrees", 0.0, 0.18)
	tween.chain().tween_callback(func():
		card.visible = false
		view["circle"].clear()
		view["render"].render_target_update_mode = SubViewport.UPDATE_DISABLED)


func _restart_tween(view: Dictionary) -> Tween:
	var old: Tween = view.get("tween")
	if old != null:
		old.kill()
	var tween := create_tween().set_parallel(true)
	view["tween"] = tween
	return tween


# --- 표시 도우미 -----------------------------------------------------------------

func _update_turn_label() -> void:
	var act: Dictionary = _session.get_current_act()
	var prefix := (String(act["name"]) + "  ·  ") if not act.is_empty() else ""
	_turn_label.text = "%s%d / %d" % [prefix, _session.state.turn, int(_session.config["max_turns"])]


## 화살표 그림 묶음 (단계 ±1 → 1개, ±2 → 2개). 그림이 없으면 ↑ ↓ 글자.
func _make_arrows(level: int) -> HBoxContainer:
	var arrows := HBoxContainer.new()
	arrows.add_theme_constant_override("separation", 0)
	arrows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var texture := AssetLibrary.texture("ui/arrow_up" if level > 0 else "ui/arrow_down")
	for i in absi(level):
		if texture != null:
			var image := TextureRect.new()
			image.texture = texture
			image.custom_minimum_size = Vector2(14, 18)
			AssetLibrary.apply_filter(image, texture, image.custom_minimum_size)
			image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			image.mouse_filter = Control.MOUSE_FILTER_IGNORE
			arrows.add_child(image)
		else:
			var label := Label.new()
			label.text = "↑" if level > 0 else "↓"
			label.add_theme_color_override("font_color", UiStyle.level_color(level))
			arrows.add_child(label)
	return arrows


func _make_icon(stat_id: String, icon_size: float) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = AssetLibrary.stat_icon(stat_id)
	icon.custom_minimum_size = Vector2(icon_size, icon_size)
	AssetLibrary.apply_filter(icon, icon.texture, icon.custom_minimum_size)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


## 게이지 옆 표시. levels에 없는 상태는 비운다.
func _show_markers(levels: Dictionary) -> void:
	for stat_id in _stat_views:
		var marker: HBoxContainer = _stat_views[stat_id]["marker"]
		for child in marker.get_children():
			child.queue_free()
		if levels.has(stat_id):
			marker.add_child(_make_arrows(int(levels[stat_id])))


## 예상 변화: [아이콘] 주민 ↑ (색 + 화살표를 함께 써서 색만으로 전달하지 않음)
func _fill_effect_chips(box: Container, levels: Dictionary) -> void:
	for child in box.get_children():
		child.queue_free()
	for stat_id in levels:
		var level := int(levels[stat_id])
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 3)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(_make_icon(stat_id, 24))
		var name_label := Label.new()
		name_label.text = _stat_names.get(stat_id, stat_id)
		name_label.add_theme_font_size_override("font_size", 16)
		name_label.add_theme_color_override("font_color", UiStyle.level_color(level))
		chip.add_child(name_label)
		chip.add_child(_make_arrows(level))
		box.add_child(chip)


# --- 연출 ------------------------------------------------------------------------

## 선택 직후 상태 반응 (약 0.3초)
##   오름: 위로 톡 튀며 밝아진다
##   내림: 아래로 살짝 내려앉으며 좌우로 흔들리고 어두워진다
func _react(stat_id: String, level: int) -> void:
	if not _stat_views.has(stat_id):
		return
	var row: Control = _stat_views[stat_id]["row"]
	var icon: TextureRect = _stat_views[stat_id]["icon"]
	row.position = Vector2.ZERO
	var move := create_tween()
	var tint := create_tween()
	if level > 0:
		move.tween_property(row, "position:y", -BOUNCE_PIXELS * absi(level), 0.1).set_ease(Tween.EASE_OUT)
		move.tween_property(row, "position:y", 0.0, 0.18).set_ease(Tween.EASE_IN)
		icon.modulate = Color(1.5, 1.5, 1.5)
	else:
		var amount := SHAKE_PIXELS * absi(level)
		move.tween_property(row, "position", Vector2(-amount, 4.0), 0.07)
		for x in [amount, -amount * 0.5, 0.0]:
			move.tween_property(row, "position", Vector2(x, 4.0 if x != 0.0 else 0.0), 0.07)
		icon.modulate = Color(0.45, 0.45, 0.45)
	tint.tween_property(icon, "modulate", Color.WHITE, 0.35)


## 게이지 옆 화살표가 두 번 짧게 반짝인다.
func _flash_markers(levels: Dictionary) -> void:
	for stat_id in levels:
		if not _stat_views.has(stat_id):
			continue
		var marker: Control = _stat_views[stat_id]["marker"]
		var tween := create_tween()
		for i in 2:
			tween.tween_property(marker, "modulate", Color(2.2, 2.2, 2.2), 0.07)
			tween.tween_property(marker, "modulate", Color.WHITE, 0.1)


## 중요한 선택(회상 문구가 있는 선택)일 때 인물 위로 작은 조각이 튄다.
func _pixel_burst(target: Control) -> void:
	var particles := CPUParticles2D.new()
	particles.one_shot = true
	particles.emitting = false
	particles.amount = 18
	particles.lifetime = 0.55
	particles.explosiveness = 0.95
	particles.direction = Vector2.UP
	particles.spread = 70.0
	particles.initial_velocity_min = 120.0
	particles.initial_velocity_max = 220.0
	particles.gravity = Vector2(0, 520)
	particles.scale_amount_min = 4.0
	particles.scale_amount_max = 6.0
	particles.color_ramp = _burst_colors()
	var rect := target.get_global_rect()
	particles.position = rect.position + Vector2(rect.size.x / 2.0, 20.0) - get_global_rect().position
	add_child(particles)
	particles.emitting = true
	get_tree().create_timer(1.0).timeout.connect(particles.queue_free)


func _burst_colors() -> Gradient:
	var gradient := Gradient.new()
	gradient.set_color(0, Color("ffe27a"))
	gradient.set_color(1, Color(1.0, 0.6, 0.4, 0.0))
	return gradient


## 효과음 (AudioPlayer가 없으면 조용히 넘어간다)
func _sfx(action: String) -> void:
	get_tree().call_group(AUDIO_GROUP, "play_sfx", action)


func _lock_input() -> void:
	_input_ready_at = Time.get_ticks_msec() + INPUT_COOLDOWN_MS


func _input_ready() -> bool:
	return Time.get_ticks_msec() >= _input_ready_at


## 클릭은 모두 이 화면(루트)이 받아 메인 창 기준 왼쪽/오른쪽으로 판단한다.
func _ignore_mouse_on_children() -> void:
	for child in find_children("*", "Control", true, false):
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE


# --- 화면 구성 -------------------------------------------------------------------

func _build_layout() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# 인물 카드 두 장: 메인 창보다 먼저 추가해서 메인 창 뒤에 그려지게 한다.
	for side in SIDES:
		_side_cards[side] = _make_side_card(side)

	# 왼쪽 위: 막 이름과 진행 턴
	var turn_panel := PanelContainer.new()
	turn_panel.position = Vector2(24, 20)
	add_child(turn_panel)
	_turn_label = Label.new()
	_turn_label.add_theme_font_size_override("font_size", 18)
	turn_panel.add_child(_turn_label)

	# 오른쪽 위: 상태 게이지
	var stats_panel := PanelContainer.new()
	stats_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	stats_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	stats_panel.offset_right = -20
	stats_panel.offset_top = 16
	add_child(stats_panel)
	_stats_box = VBoxContainer.new()
	_stats_box.add_theme_constant_override("separation", 4)
	stats_panel.add_child(_stats_box)

	# 가운데: 메인 창 + 안내 문구
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	center.add_child(column)

	# 메인 창 위 빈칸: 선택 안내 그림이 뜨는 자리 (그림은 이 자리와 메인 창 위 테두리에 겹쳐 그린다)
	var banner_space := Control.new()
	banner_space.custom_minimum_size = Vector2(0, BANNER_SPACE)
	column.add_child(banner_space)

	# 글이 길어져 메인 창이 커지면 바깥 배치(안내 문구 위치)도 다시 계산하게 알린다.
	_main = PanelContainer.new()
	_main.custom_minimum_size = MAIN_SIZE
	_main.add_theme_stylebox_override("panel", UiStyle.main_box())
	_main.resized.connect(func():
		column.update_minimum_size()
		column.queue_sort()
		if _banner != null and _banner.visible:
			_place_banner.call_deferred())
	column.add_child(_main)

	var main_margin := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]:
		main_margin.add_theme_constant_override("margin_" + edge, 22)
	_main.add_child(main_margin)

	var main_column := VBoxContainer.new()
	main_column.alignment = BoxContainer.ALIGNMENT_END
	main_column.add_theme_constant_override("separation", 10)
	main_margin.add_child(main_column)

	# 제목: 사건 이름(진한 띠 모양 칸) + 그 아래 작은 안내
	_heading_box = PanelContainer.new()
	_heading_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_heading_box.add_theme_stylebox_override("panel", UiStyle.title_box())
	main_column.add_child(_heading_box)
	_heading_label = Label.new()
	_heading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_heading_label.add_theme_font_size_override("font_size", 24)
	_heading_label.add_theme_color_override("font_color", UiStyle.TITLE_TEXT)
	_heading_box.add_child(_heading_label)

	_subheading_label = Label.new()
	_subheading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subheading_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subheading_label.add_theme_font_size_override("font_size", 16)
	_subheading_label.add_theme_color_override("font_color", UiStyle.TEXT_SOFT)
	main_column.add_child(_subheading_label)

	# 무대: 평소에는 가운데 인물 한 명, 선택할 때는 왼쪽·오른쪽 지지자 두 명
	_stage = HBoxContainer.new()
	_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stage.alignment = BoxContainer.ALIGNMENT_CENTER
	_stage.add_theme_constant_override("separation", STAGE_PAIR_GAP)
	main_column.add_child(_stage)
	for side in ["left", "center", "right"]:
		var portrait = PortraitView.new()
		portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if side == "center":
			portrait.custom_minimum_size = STAGE_PORTRAIT
			portrait.visible = false
			_stage.add_child(portrait)
			_stage_portrait = portrait
			continue
		# 좌우 지지자: 초상화 아래에 그 선택지를 고르면 달라질 상태(아이콘 + 화살표)
		var holder := VBoxContainer.new()
		holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		holder.add_theme_constant_override("separation", 6)
		holder.visible = false
		_stage.add_child(holder)
		portrait.custom_minimum_size = STAGE_PAIR_PORTRAIT
		holder.add_child(portrait)
		var chips := HFlowContainer.new()
		chips.alignment = FlowContainer.ALIGNMENT_CENTER
		chips.custom_minimum_size = Vector2(STAGE_PAIR_PORTRAIT.x, 26)
		chips.add_theme_constant_override("h_separation", 10)
		holder.add_child(chips)
		_stage_sides[side] = portrait
		_stage_holders[side] = holder
		_stage_chips[side] = chips

	# 대화창: 둥근 직사각형. 이름표 + 대사 + 작은 글
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UiStyle.dialogue_box())
	main_column.add_child(box)

	var box_column := VBoxContainer.new()
	box_column.add_theme_constant_override("separation", 8)
	box.add_child(box_column)

	_name_tag = PanelContainer.new()
	_name_tag.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_name_tag.add_theme_stylebox_override("panel", UiStyle.name_tag_box())
	box_column.add_child(_name_tag)
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 16)
	_name_label.add_theme_color_override("font_color", UiStyle.NAME_TAG_TEXT)
	_name_tag.add_child(_name_label)

	_line_label = Label.new()
	_line_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line_label.add_theme_font_size_override("font_size", 20)
	box_column.add_child(_line_label)

	_sub_label = Label.new()
	_sub_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub_label.add_theme_font_size_override("font_size", 17)
	_sub_label.add_theme_color_override("font_color", UiStyle.TEXT_SOFT)
	box_column.add_child(_sub_label)

	var guide_gap := Control.new()
	guide_gap.custom_minimum_size = Vector2(0, 12)
	column.add_child(guide_gap)

	var guide_panel := PanelContainer.new()
	guide_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(guide_panel)
	_guide_label = Label.new()
	_guide_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_guide_label.add_theme_color_override("font_color", UiStyle.TEXT_SOFT)
	guide_panel.add_child(_guide_label)

	# 선택 안내 그림: 메인 창보다 나중에 추가해서 메인 창 위 테두리에 겹쳐 그려지게 한다. 그림이 없으면 안 뜬다.
	_banner = TextureRect.new()
	_banner.texture = AssetLibrary.texture("ui/choice")
	_banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_banner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.visible = false
	add_child(_banner)


## 인물 카드 한 장 (고정 크기). 위: 인물 그림 칸 / 아래: 글 칸(따로 바탕을 깔아 그림과 겹치지 않게).
## 메인 창에 가려지는 안쪽에는 여백을 두어 내용이 바깥쪽에 보이게 한다.
## 카드는 비스듬히 기울어 나오는데, 글자·작은 아이콘을 그대로 기울이면 자글자글하게 깨진다.
## 그래서 카드 내용은 따로 만든 화면(SubViewport)에 똑바로 그리고, 그 그림을 부드럽게(linear) 기울여 보여 준다.
func _make_side_card(side: String) -> Dictionary:
	var card := Control.new()
	card.size = PERSON_CARD_SIZE
	card.visible = false
	add_child(card)

	# 카드 그림자가 잘리지 않게 바깥에 여백(CARD_RENDER_PAD)을 두고 그린다.
	var render := SubViewport.new()
	render.size = Vector2i(PERSON_CARD_SIZE) + Vector2i.ONE * CARD_RENDER_PAD * 2
	render.transparent_bg = true
	render.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	render.render_target_update_mode = SubViewport.UPDATE_DISABLED
	card.add_child(render)

	var image := TextureRect.new()
	image.texture = render.get_texture()
	image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	image.position = -Vector2.ONE * CARD_RENDER_PAD
	image.size = Vector2(render.size)
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(image)

	# 따로 그리는 화면에는 테마가 이어지지 않으므로 여기서 다시 붙인다.
	var content := Control.new()
	content.theme = UiStyle.make_theme()
	content.position = Vector2.ONE * CARD_RENDER_PAD
	content.size = PERSON_CARD_SIZE
	render.add_child(content)

	var background := Panel.new()
	background.add_theme_stylebox_override("panel", UiStyle.main_box())
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 14)
	margin.add_theme_constant_override("margin_left", PERSON_HIDDEN_MARGIN if side == "right" else 12)
	margin.add_theme_constant_override("margin_right", PERSON_HIDDEN_MARGIN if side == "left" else 12)
	content.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	var portrait := PortraitView.new()
	portrait.custom_minimum_size = Vector2(0, PERSON_PORTRAIT_HEIGHT)
	column.add_child(portrait)

	# 초상화 아래: 이름 · 선택지 문구
	var name_label := Label.new()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_color", UiStyle.TEXT_SOFT)
	name_label.add_theme_font_size_override("font_size", 15)
	column.add_child(name_label)

	var choice_label := Label.new()
	choice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	choice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	choice_label.add_theme_font_size_override("font_size", 19)
	choice_label.add_theme_color_override("font_color", UiStyle.HEADING_TEXT)
	column.add_child(choice_label)

	# 대사창: 이 선택지를 고르면 마을이 어떻게 될지 내다보는 인물의 한마디 + 빨간 동그라미
	var text_panel := PanelContainer.new()
	text_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_panel.add_theme_stylebox_override("panel", UiStyle.dialogue_box())
	column.add_child(text_panel)

	var outlook_label := Label.new()
	outlook_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outlook_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	outlook_label.add_theme_font_size_override("font_size", 15)
	text_panel.add_child(outlook_label)

	var circle := PencilCircle.new()
	circle.mirrored = side == "left"   # 왼쪽 카드는 오른쪽이 메인 창에 가려지므로, 꼬리가 보이는 쪽(왼쪽)에서 겹치게
	text_panel.add_child(circle)   # 대사창과 같은 칸에 겹쳐 그 위에 그린다

	return {
		"card": card,
		"render": render,
		"portrait": portrait,
		"name": name_label,
		"choice": choice_label,
		"outlook": outlook_label,
		"circle": circle,
		"tween": null,
	}


## 게이지 한 줄: [아이콘] 이름 [게이지] [화살표]
## 반응 애니메이션 때 컨테이너가 위치를 되돌리지 않도록 일반 Control(holder) 안에 둔다.
func _add_stat_view(stat_id: String, display_name: String) -> void:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(262, 30)
	_stats_box.add_child(holder)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 8)
	holder.add_child(row)

	var icon := _make_icon(stat_id, 24)
	row.add_child(icon)

	var name_label := Label.new()
	name_label.text = display_name
	name_label.custom_minimum_size = Vector2(40, 0)
	row.add_child(name_label)

	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.step = 0.001
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(130, 14)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)

	var marker := HBoxContainer.new()
	marker.custom_minimum_size = Vector2(34, 0)
	marker.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(marker)

	_stat_views[stat_id] = {"row": row, "icon": icon, "bar": bar, "marker": marker}
