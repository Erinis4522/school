class_name ControlView
extends Control
## 터치 화면(조작 전용). 명령만 보내고, 컨트롤러 상태가 바뀌면 화면을 다시 만든다.

signal teacher_action(action: String)

var controller: GameController
var _seq := 0
var _built_key := ""
var _root: VBoxContainer
var _other_mode := false  # 제안 화면에서 '다른 원칙 고르기'를 펼쳤는가
var _teacher_open := false
var _teacher_info := ""
var _corner_down := -1.0
var _now := 0.0
# 매 프레임 갱신하는 라벨들
var _live_status: Label
var _live_bubble: Label
var _live_timer: Label


func setup(c: GameController) -> void:
	controller = c
	controller.phase_changed.connect(func(_p): _other_mode = false)
	controller.suggestion_opened.connect(func(_s): _other_mode = false)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiStyle.build_theme()
	var bg := Panel.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 36)
	add_child(margin)
	_root = VBoxContainer.new()
	_root.add_theme_constant_override("separation", 22)
	margin.add_child(_root)


func _send(name: String, args: Dictionary = {}) -> void:
	_seq += 1
	controller.command(name, args, _seq)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventScreenTouch:
		controller.note_activity()
	# 교사용 숨김 메뉴: 오른쪽 위 모서리를 2초 길게 누르기
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var corner := Rect2(Vector2(size.x - 110, 0), Vector2(110, 110))
		if event.pressed and corner.has_point(event.position):
			_corner_down = _now
		elif not event.pressed:
			_corner_down = -1.0


func _process(delta: float) -> void:
	_now += delta
	_fit_to_viewport()
	if _corner_down >= 0.0 and _now - _corner_down >= 2.0:
		_corner_down = -1.0
		toggle_teacher()
	var key := "%s|%d|%s|%s|%s|%s" % [controller.phase, controller.state_version,
		str(controller.session != null and controller.session.is_paused()), str(_other_mode), str(_teacher_open), _teacher_info]
	if key != _built_key:
		_built_key = key
		_rebuild()
	_update_live()


func toggle_teacher() -> void:
	_teacher_open = not _teacher_open
	_teacher_info = ""


func show_teacher_info(t: String) -> void:
	_teacher_info = t


# ---------------- 화면 만들기 ----------------

func _clear() -> void:
	for c in _root.get_children():
		_root.remove_child(c)
		c.queue_free()
	_live_status = null
	_live_bubble = null
	_live_timer = null


func _rebuild() -> void:
	_clear()
	if _teacher_open:
		_build_teacher()
		return
	match controller.phase:
		GameController.ATTRACT:
			_build_attract()
		GameController.SELECT:
			_build_select()
		GameController.PLACE:
			_build_place()
		GameController.BATTLE:
			if controller.session != null and controller.session.is_paused():
				_build_suggestion()
			else:
				_build_battle()
		GameController.RESULT:
			_build_result()


func _spacer(expand := true) -> Control:
	var c := Control.new()
	if expand:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _hbox(sep := 20) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


func _build_attract() -> void:
	_root.add_child(_spacer())
	_root.add_child(UiStyle.label(GameData.text("ui", "title"), 96, UiStyle.C_ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	_root.add_child(UiStyle.label(GameData.text("ui", "subtitle"), 40, UiStyle.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	_root.add_child(UiStyle.label(GameData.text("ui", "guide"), 32, UiStyle.C_SUB, HORIZONTAL_ALIGNMENT_CENTER))
	var row := _hbox()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var b := UiStyle.button("시작", 520, 150, 64)
	b.pressed.connect(func(): _send("start"))
	row.add_child(b)
	_root.add_child(row)
	_root.add_child(_spacer())
	_root.add_child(UiStyle.label(GameData.text("ui", "ai_note"), 24, UiStyle.C_SUB, HORIZONTAL_ALIGNMENT_CENTER))


func _build_select() -> void:
	var top := _hbox()
	var title := UiStyle.label("캐릭터 3명을 골라 줘  (%d / 3)" % controller.selected.size(), 46, UiStyle.C_ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var rec := UiStyle.button("추천 팀으로 시작", 380, 84)
	rec.pressed.connect(func(): _send("recommended"))
	top.add_child(rec)
	_root.add_child(top)
	var names: Array = []
	for r in GameData.config.get("recommended_team", []):
		names.append(GameData.hero(r["type"])["name"])
	_root.add_child(UiStyle.label("추천 팀: " + ", ".join(names) + " (자리까지 자동으로 놓아 줘요. 나중에 바꿀 수 있어요)", 24, UiStyle.C_SUB))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 18)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for t in GameData.hero_order:
		grid.add_child(_hero_card(t))
	_root.add_child(grid)
	var bottom := _hbox()
	var back := UiStyle.button("◀ 처음으로", 280)
	back.pressed.connect(func(): _send("back"))
	bottom.add_child(back)
	bottom.add_child(_hspacer())
	var nxt := UiStyle.button("다음: 자리 정하기 ▶", 460)
	nxt.disabled = controller.selected.size() != 3
	nxt.pressed.connect(func(): _send("to_place"))
	bottom.add_child(nxt)
	_root.add_child(bottom)


func _hspacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _hero_card(t: String) -> Control:
	var d: Dictionary = GameData.hero(t)
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(400, 330)
	var on := controller.selected.has(t)
	UiStyle.set_selected(b, on)
	b.pressed.connect(func(): _send("toggle_hero", {"type": t}))
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 14
	v.offset_right = -14
	v.offset_top = 10
	v.offset_bottom = -10
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 4)
	var head := _hbox(12)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(HeroIcon.new(t, 116))
	var hv := VBoxContainer.new()
	hv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.add_child(UiStyle.label(d["name"], 40, UiStyle.C_ACCENT if on else UiStyle.C_TEXT))
	hv.add_child(UiStyle.label(d["attack"], 26, UiStyle.C_SUB))
	head.add_child(hv)
	v.add_child(head)
	v.add_child(UiStyle.label("★ " + str(d["feature"]), 27, UiStyle.C_TEXT))
	v.add_child(UiStyle.label(d["desc"], 24, UiStyle.C_SUB))
	v.add_child(UiStyle.label("사거리 %.1f · 공격 %d · %.2f초마다" % [float(d["range"]), int(d["damage"]), float(d["interval"])], 22, UiStyle.C_SUB))
	if on:
		v.add_child(UiStyle.label("✔ %d번째로 선택" % (controller.selected.find(t) + 1), 26, UiStyle.C_ACCENT))
	b.add_child(v)
	return b


func _build_place() -> void:
	_root.add_child(UiStyle.label("① 캐릭터를 누르고  ② 지도에서 번호 자리를 눌러 놓아요  ③ 행동 원칙을 골라요", 34, UiStyle.C_ACCENT))
	var body := _hbox(24)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var picker := MapPicker.new()
	picker.controller = controller
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.size_flags_vertical = Control.SIZE_EXPAND_FILL
	picker.size_flags_stretch_ratio = 1.35
	picker.slot_pressed.connect(func(s): _send("place_slot", {"slot": s}))
	body.add_child(picker)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 14)
	for i in controller.team.size():
		right.add_child(_member_row(i))
	body.add_child(right)
	_root.add_child(body)
	var bottom := _hbox()
	var back := UiStyle.button("◀ 다시 고르기", 300)
	back.pressed.connect(func(): _send("back"))
	bottom.add_child(back)
	bottom.add_child(_hspacer())
	var all_placed := true
	for m in controller.team:
		if int(m["slot"]) < 0:
			all_placed = false
	if not all_placed:
		bottom.add_child(UiStyle.label("3명을 모두 자리에 놓으면 시작할 수 있어요", 26, UiStyle.C_SUB, HORIZONTAL_ALIGNMENT_RIGHT, false))
	var go := UiStyle.button("전투 시작 ▶", 400, 96, 40)
	go.disabled = not all_placed
	go.pressed.connect(func(): _send("battle_start"))
	bottom.add_child(go)
	_root.add_child(bottom)


func _member_row(i: int) -> Control:
	var m: Dictionary = controller.team[i]
	var d: Dictionary = GameData.hero(m["type"])
	var panel := PanelContainer.new()
	var sel := i == controller.place_cursor
	panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.C_CARD_SEL if sel else UiStyle.C_CARD, 18, 4 if sel else 0, UiStyle.C_ACCENT))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	var hh := _hbox(12)
	hh.add_child(HeroIcon.new(m["type"], 96))
	var slot_txt := "자리: %d번" % (int(m["slot"]) + 1) if int(m["slot"]) >= 0 else "아직 자리에 안 놓았어요"
	if sel:
		slot_txt = "지도에서 자리를 눌러요 (" + slot_txt + ")"
	# 이름 영역 전체가 '이 캐릭터 놓기' 버튼 (텍스트는 버튼 자체 글자로 → 크기가 자동으로 맞음)
	var head := Button.new()
	head.focus_mode = Control.FOCUS_NONE
	head.text = "%s  ·  %s\n%s" % [d["name"], d["feature"], slot_txt]
	head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.add_theme_font_size_override("font_size", 28)
	head.custom_minimum_size = Vector2(0, 96)
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if sel:
		head.add_theme_color_override("font_color", UiStyle.C_ACCENT)
		head.add_theme_color_override("font_hover_color", UiStyle.C_ACCENT)
	head.pressed.connect(func(): _send("pick_member", {"index": i}))
	hh.add_child(head)
	v.add_child(hh)
	var pr := _hbox(10)
	for p in GameData.principle_order():
		var b := UiStyle.button(GameData.principle_name(p), 150, 72, 26)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UiStyle.set_selected(b, m["principle"] == p)
		b.pressed.connect(func(): _send("set_principle", {"index": i, "principle": p}))
		pr.add_child(b)
	v.add_child(pr)
	var w: Dictionary = GameData.config["principles"][m["principle"]]
	var desc := "→ " + str(w["desc"])
	if m["principle"] == "SPECIAL":
		desc += " (" + str(d.get("special_name", "")) + ")"
	v.add_child(UiStyle.label(desc, 24, UiStyle.C_SUB))
	panel.add_child(v)
	return panel


func _build_battle() -> void:
	_live_status = UiStyle.label("", 40, UiStyle.C_ACCENT)
	_root.add_child(_live_status)
	_root.add_child(UiStyle.label("큰 화면에서 전투를 지켜봐! 캐릭터가 스스로 표적을 골라 공격해요.", 32, UiStyle.C_TEXT))
	var row := _hbox(20)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for h in controller.session.state.heroes:
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := VBoxContainer.new()
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		var ic := HeroIcon.new(h.type, 160)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(ic)
		v.add_child(UiStyle.label(GameData.hero(h.type)["name"], 40, UiStyle.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER))
		v.add_child(UiStyle.label("행동 원칙", 24, UiStyle.C_SUB, HORIZONTAL_ALIGNMENT_CENTER))
		v.add_child(UiStyle.label(GameData.principle_name(h.principle), 38, UiStyle.C_ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
		panel.add_child(v)
		row.add_child(panel)
	_root.add_child(row)
	_live_bubble = UiStyle.label("", 32, UiStyle.C_TEXT)
	_root.add_child(_live_bubble)
	_root.add_child(UiStyle.label("작전은 캐릭터가 바꾸자고 제안할 때 이 화면에서 정할 수 있어요.", 26, UiStyle.C_SUB))


func _build_suggestion() -> void:
	var s: Dictionary = controller.session.active
	var h: Entities.Hero = controller.session.state.heroes[s["hero_id"]]
	var name: String = GameData.hero(h.type)["name"]
	var head := _hbox(24)
	head.add_child(HeroIcon.new(h.type, 150))
	var hv := VBoxContainer.new()
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.add_child(UiStyle.label("%s의 %s" % [name, "제안" if s["has_change"] else "의견"], 48, UiStyle.C_ACCENT))
	if s["has_change"]:
		hv.add_child(UiStyle.label("지금: %s   →   제안: %s" % [GameData.principle_name(s["from"]), GameData.principle_name(s["to"])], 38, UiStyle.C_TEXT))
	else:
		hv.add_child(UiStyle.label("지금: %s  (바꾸자는 제안은 없어요)" % GameData.principle_name(s["from"]), 34, UiStyle.C_TEXT))
	head.add_child(hv)
	_root.add_child(head)
	var sit: String = s["situation"]
	if s["evidence"] != "":
		sit += ". " + s["evidence"]
	_root.add_child(UiStyle.label("전황: " + sit + ".", 32, UiStyle.C_TEXT))
	if not _other_mode:
		_root.add_child(UiStyle.label(s["ask"], 32, UiStyle.C_TEXT))
		var cards := _hbox(20)
		cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
		cards.add_child(_list_card("예상 장점", s["pros"], UiStyle.C_PRO))
		cards.add_child(_list_card("예상 단점", s["cons"], UiStyle.C_CON))
		_root.add_child(cards)
		_root.add_child(UiStyle.label(s["estimate"], 24, UiStyle.C_SUB))
		_root.add_child(UiStyle.label(s["estimate_note"], 22, UiStyle.C_SUB))
		var row := _hbox(24)
		var buttons: Array = []
		if s["has_change"]:
			buttons.append(["바꿔보기", "suggest_accept"])
		buttons.append(["그대로 유지", "suggest_keep"])
		buttons.append(["다른 원칙 고르기", "other"])
		for bdef in buttons:
			var b := UiStyle.button(bdef[0], 300, 110, 38)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var cmd: String = bdef[1]
			if cmd == "other":
				b.pressed.connect(func(): _other_mode = true)
			else:
				b.pressed.connect(func(): _send(cmd))
			row.add_child(b)
		_root.add_child(row)
	else:
		_root.add_child(UiStyle.label("%s의 행동 원칙을 직접 골라 줘" % name, 34, UiStyle.C_ACCENT))
		var row2 := _hbox(20)
		row2.size_flags_vertical = Control.SIZE_EXPAND_FILL
		for p in GameData.principle_order():
			var w: Dictionary = GameData.config["principles"][p]
			var b := Button.new()
			b.focus_mode = Control.FOCUS_NONE
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.custom_minimum_size = Vector2(300, 200)
			var cur: bool = p == h.principle
			b.text = "%s\n%s%s" % [w["name"], w["desc"], "\n(지금 원칙)" if cur else ""]
			b.disabled = cur
			b.pressed.connect(func(): _send("suggest_other", {"principle": p}))
			row2.add_child(b)
		_root.add_child(row2)
		var back := UiStyle.button("◀ 제안 다시 보기", 360)
		back.pressed.connect(func(): _other_mode = false)
		_root.add_child(back)
	_live_timer = UiStyle.label("", 26, UiStyle.C_SUB, HORIZONTAL_ALIGNMENT_CENTER)
	_root.add_child(_live_timer)


func _list_card(title: String, items: Array, col: Color) -> Control:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_theme_stylebox_override("panel", UiStyle.box(col, 18))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.add_child(UiStyle.label(title, 34, UiStyle.C_ACCENT))
	for it in items:
		v.add_child(UiStyle.label("• " + str(it), 28, UiStyle.C_TEXT))
	p.add_child(v)
	return p


func _build_result() -> void:
	var r: Dictionary = controller.result
	_root.add_child(UiStyle.label("방어 성공!" if r["outcome"] == "win" else "끝까지 잘 버텼어요!", 64, UiStyle.C_ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	var secs := int(r["time"])
	_root.add_child(UiStyle.label("생존 %d:%02d · 웨이브 %d/%d · 기지 HP %d/%d · 처치 %d · 점수 %d" % [
		secs / 60, secs % 60, int(r["wave"]) + 1, GameData.waves.size(), r["hp"], r["hp_max"], r["kills"], r["score"]],
		32, UiStyle.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.add_child(UiStyle.label("내 작전 기록", 34, UiStyle.C_ACCENT))
	var decisions: Array = r["decisions"]
	if decisions.is_empty():
		v.add_child(UiStyle.label("이번 판에는 특별 제안이 없었어요. (위기나 기지 피격이 없었거나 바로 끝났어요)", 28, UiStyle.C_TEXT))
	var kinds := {"crisis": "방어선 위기", "first_hit": "기지 첫 피격", "test": "테스트"}
	var choice_txt := {"accept": "제안대로 바꿨어요", "keep": "그대로 유지했어요", "other": "직접 다른 원칙을 골랐어요", "timeout": "시간이 지나 그대로 유지했어요"}
	for dd in decisions:
		var hn: String = GameData.hero(dd["hero_type"])["name"]
		var line := "• %s 때 %s: " % [kinds.get(dd["kind"], dd["kind"]), hn]
		if dd["has_change"]:
			line += "‘%s’→‘%s’ 제안 → " % [GameData.principle_name(dd["from"]), GameData.principle_name(dd["to"])]
		else:
			line += "그대로 가자는 의견 → "
		line += choice_txt.get(dd["choice"], dd["choice"])
		if dd["choice"] == "other":
			line += " (‘%s’)" % GameData.principle_name(dd["final"])
		v.add_child(UiStyle.label(line, 28, UiStyle.C_TEXT))
	var fin: Array = []
	for h in r["heroes"]:
		fin.append("%s ‘%s’" % [GameData.hero(h["type"])["name"], GameData.principle_name(h["principle"])])
	v.add_child(UiStyle.label("최종 작전: " + ", ".join(fin), 28, UiStyle.C_SUB))
	panel.add_child(v)
	_root.add_child(panel)
	_root.add_child(UiStyle.label(GameData.text("ui", "result_message"), 40, UiStyle.C_ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	_root.add_child(UiStyle.label(GameData.text("ui", "end_message"), 28, UiStyle.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	var row := _hbox()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var b := UiStyle.button("다음 학생 시작", 560, 130, 52)
	b.pressed.connect(func(): _send("next_student"))
	row.add_child(b)
	_root.add_child(row)
	_live_timer = UiStyle.label("", 24, UiStyle.C_SUB, HORIZONTAL_ALIGNMENT_CENTER)
	_root.add_child(_live_timer)


func _build_teacher() -> void:
	_root.add_child(UiStyle.label("교사용 메뉴", 52, UiStyle.C_ACCENT))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 18)
	var items := [
		["처음 화면으로 (재시작)", "reset"], ["전체 화면 켜기/끄기", "fullscreen"], ["화면 역할 바꾸기", "swap"],
		["테스트: 제안 열기 (전투 중)", "test_suggest"], ["FPS·성능 표시", "fps"], ["화면 연결 안내", "display_info"],
		["그림 파일 상태", "asset_info"], ["메뉴 닫기", "close"], ["프로그램 종료", "quit"],
	]
	for it in items:
		var b := UiStyle.button(it[0], 380, 100, 30)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var act: String = it[1]
		b.pressed.connect(func(): _on_teacher(act))
		grid.add_child(b)
	_root.add_child(grid)
	if _teacher_info != "":
		var p := PanelContainer.new()
		p.add_child(UiStyle.label(_teacher_info, 26, UiStyle.C_TEXT))
		_root.add_child(p)
	_root.add_child(UiStyle.label("단축키: F10 메뉴 · F11 전체화면 · F9 화면 역할 바꾸기 · F3 FPS · Ctrl+R 처음으로", 24, UiStyle.C_SUB))


func _on_teacher(act: String) -> void:
	match act:
		"reset":
			_send("teacher_reset")
			_teacher_open = false
		"fps":
			_send("teacher_toggle_fps")
		"test_suggest":
			_teacher_open = false
			_send("teacher_test_suggest")
		"close":
			_teacher_open = false
		"asset_info":
			var lines: Array = []
			for a in AssetManifest.report():
				lines.append("%s %s" % ["■ PNG" if a[1] else "□ 도형", a[0]])
			_teacher_info = "\n".join(lines.slice(0, 8)) + "\n" + "\n".join(lines.slice(8))
		_:
			teacher_action.emit(act)


func _update_live() -> void:
	if controller.session != null:
		var st := controller.session.state
		if _live_status != null:
			var w := "웨이브 %d/%d" % [st.wave_index + 1, GameData.waves.size()] if st.wave_index >= 0 else "준비"
			_live_status.text = "%s · 기지 HP %d/%d · 처치 %d · %d초" % [w, st.base_hp, st.base_hp_max, st.kills, int(st.time)]
		if _live_bubble != null:
			if controller.last_bubble_text != "" and controller.last_bubble_hero >= 0:
				_live_bubble.text = "최근 보고 — %s: “%s”" % [GameData.hero(st.heroes[controller.last_bubble_hero].type)["name"], controller.last_bubble_text]
			else:
				_live_bubble.text = "최근 보고 — (아직 없음)"
	if _live_timer != null:
		if controller.phase == GameController.RESULT:
			_live_timer.text = "%d초 뒤 자동으로 처음 화면으로 돌아가요" % int(ceil(controller.result_time_left()))
		else:
			_live_timer.text = "모든 선택은 똑같이 괜찮아요. %d초 안에 고르지 않으면 지금 원칙을 그대로 유지하고 전투를 이어가요." % int(ceil(controller.suggestion_time_left()))


func _fit_to_viewport() -> void:
	## 창(뷰포트) 크기에 항상 꽉 차게 (창 이동·전체화면 전환·화면 역할 바꾸기 후에도)
	var vr := get_viewport_rect()
	if position != Vector2.ZERO or size != vr.size:
		position = Vector2.ZERO
		size = vr.size
