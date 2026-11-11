class_name ArenaView
extends Control
## 일반 모니터용 전투 화면. 게임 상태를 읽어 그리기만 한다 (입력 필요 없음).

var controller: GameController
var font: Font
var fx: Array = []  # 시각 효과 {kind, t0, dur, ...} (실제 시간 기준)
var banner_text := ""
var banner_until := 0.0
var flash_until := 0.0
var now := 0.0
var fps_text := ""
var _fps_acc := 0.0
var anims: Dictionary = {}  # 캐릭터 애니메이션 상태 (키: 전투 캐릭터 id 또는 준비 화면 슬롯)

const HERO_H := 1.55  # 캐릭터 그림 높이 (타일)

var _scale := 80.0
var _origin := Vector2.ZERO

const HUD_H := 76.0
const C_BG := Color("#2d4a2b")
const C_GRASS := Color("#7fb069")
const C_GRASS2 := Color("#76a862")
const C_PATH := Color("#e6cc8f")
const C_PATH_EDGE := Color("#b89a5c")
const C_TEXT := Color("#ffffff")
const C_PANEL := Color(0.08, 0.1, 0.14, 0.82)


func setup(c: GameController) -> void:
	controller = c
	controller.battle_events.connect(_on_events)
	controller.phase_changed.connect(_on_phase)
	controller.suggestion_closed.connect(func(_r): _show_banner("전투 재개!", 1.2))


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = get_theme_default_font()


func _process(delta: float) -> void:
	now += delta
	_fit_to_viewport()
	_fps_acc += delta
	if _fps_acc >= 0.5:
		_fps_acc = 0.0
		var n := 0
		if controller.session != null:
			n = controller.session.state.enemies.size()
		fps_text = "FPS %d · 적 %d · 정적메모리 %.0fMB" % [Engine.get_frames_per_second(), n, OS.get_static_memory_usage() / 1048576.0]
	var keep: Array = []
	for f in fx:
		if now - float(f["t0"]) < float(f["dur"]):
			keep.append(f)
	fx = keep
	queue_redraw()


func _on_phase(p: String) -> void:
	fx.clear()
	anims.clear()
	if p == GameController.BATTLE:
		_show_banner("전투 시작!", 1.6)


func _show_banner(t: String, dur: float) -> void:
	banner_text = t
	banner_until = now + dur


func _on_events(events: Array) -> void:
	if controller.session == null:
		return
	var st := controller.session.state
	for ev in events:
		match ev["type"]:
			"WAVE_START":
				_show_banner("%s 시작!" % GameData.waves[ev["wave"]]["name"], 2.0)
			"WAVE_CLEAR":
				_show_banner("%s 끝! 잠시 후 다음 웨이브" % GameData.waves[ev["wave"]]["name"], 2.5)
			"ATTACK":
				_on_attack_anim(ev)
				fx.append({"kind": "attack", "hero_type": ev["hero_type"], "from": ev["from"], "points": ev["points"],
					"t0": now, "dur": 0.22 if ev["hero_type"] != "SNIPER" else 0.35})
			"EXPLODE":
				fx.append({"kind": "boom", "pos": ev["pos"], "radius": ev["radius"], "fire": ev.get("kind", "") == "FIRE", "t0": now, "dur": 0.35})
			"KILL":
				fx.append({"kind": "puff", "pos": ev["pos"], "t0": now, "dur": 0.4, "type": ev["enemy_type"]})
			"LEAK":
				flash_until = now + 0.5
				fx.append({"kind": "leak", "t0": now, "dur": 0.9, "damage": ev["damage"]})
			"OUTCOME":
				_show_banner("방어 성공!" if ev["outcome"] == "win" else "기지가 무너졌어!", 2.0)


# ---------------- 좌표 ----------------

func _layout() -> void:
	var W := float(GameData.config["map"]["width"])
	var H := float(GameData.config["map"]["height"])
	_scale = minf(size.x / W, size.y / H)
	_origin = (size - Vector2(W, H) * _scale) * 0.5


func w2s(p: Vector2) -> Vector2:
	return _origin + p * _scale


# ---------------- 그리기 ----------------

func _draw() -> void:
	if controller == null:
		return
	_layout()
	draw_rect(Rect2(Vector2.ZERO, size), C_BG)
	_draw_map()
	var phase := controller.phase
	var st: GameState = controller.session.state if controller.session != null else null
	if st != null and (phase == GameController.BATTLE or phase == GameController.RESULT):
		_draw_battle(st)
	else:
		_draw_setup()
	_draw_fx()
	if flash_until > now:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 0, 0, 0.18 * (flash_until - now) / 0.5))
	if st != null and phase == GameController.BATTLE:
		_draw_hud(st)
		if controller.session.is_paused():
			_draw_suggestion(st)
		else:
			_draw_bubble(st)
	if banner_until > now and not (controller.session != null and controller.session.is_paused()):
		_draw_banner(banner_text)
	match phase:
		GameController.ATTRACT:
			_draw_attract()
		GameController.SELECT, GameController.PLACE:
			_draw_setup_banner()
		GameController.RESULT:
			_draw_result()
	if controller.show_fps:
		_text(fps_text, Vector2(size.x - 16, size.y - 14), 22, Color(1, 1, 0.6), HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_map() -> void:
	var W := float(GameData.config["map"]["width"])
	var H := float(GameData.config["map"]["height"])
	var map_rect := Rect2(_origin, Vector2(W, H) * _scale)
	var bg := AssetManifest.texture("map", "background")
	if bg != null:
		draw_texture_rect(bg, map_rect, false)
	else:
		draw_rect(map_rect, C_GRASS)
		# 잔디 무늬 (고정 패턴)
		for ix in int(W):
			for iy in int(H):
				if (ix + iy) % 2 == 0:
					draw_rect(Rect2(w2s(Vector2(ix, iy)), Vector2(_scale, _scale)), C_GRASS2)
	var pts := PackedVector2Array()
	for p in GameData.path.points:
		pts.append(w2s(p))
	draw_polyline(pts, C_PATH_EDGE, _scale * 1.0, false)
	for p in pts:
		draw_circle(p, _scale * 0.5, C_PATH_EDGE)
	draw_polyline(pts, C_PATH, _scale * 0.82, false)
	for p in pts:
		draw_circle(p, _scale * 0.41, C_PATH)
	# 출발점 동굴
	var s0 := w2s(GameData.path.points[0] + Vector2(0.7, 0))
	draw_circle(s0, _scale * 0.55, Color("#3b2f2f"))
	_text("출발", s0 + Vector2(0, -_scale * 0.7), 22, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	# 기지
	var bp := w2s(GameData.path.end_point())
	var btex := AssetManifest.texture("map", "base")
	if btex != null:
		var side := _scale * 2.0
		draw_texture_rect(btex, Rect2(bp - Vector2(side * 0.5, side * 0.85), Vector2(side, side)), false)
	else:
		var w := _scale * 1.6
		draw_rect(Rect2(bp + Vector2(-w * 0.5, -w * 0.75), Vector2(w, w * 0.8)), Color("#c9b79c"))
		draw_rect(Rect2(bp + Vector2(-w * 0.5, -w * 0.75), Vector2(w, w * 0.8)), Color("#6d5b45"), false, 3.0)
		draw_colored_polygon(PackedVector2Array([bp + Vector2(-w * 0.62, -w * 0.72), bp + Vector2(0, -w * 1.25), bp + Vector2(w * 0.62, -w * 0.72)]), Color("#b5523b"))
		draw_rect(Rect2(bp + Vector2(-w * 0.13, -w * 0.32), Vector2(w * 0.26, w * 0.37)), Color("#4a3a2a"))
	_text("기지", bp + Vector2(0, _scale * 0.55), 24, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_slot(i: int, highlight: bool) -> void:
	var c := w2s(GameData.slots[i])
	var stex := AssetManifest.texture("map", "slot")
	if stex != null:
		var side := _scale * 1.2
		draw_texture_rect(stex, Rect2(c - Vector2(side, side) * 0.5, Vector2(side, side)), false)
	else:
		draw_circle(c, _scale * 0.48, Color(1, 1, 1, 0.18 if not highlight else 0.35))
		draw_arc(c, _scale * 0.48, 0, TAU, 32, Color(1, 1, 1, 0.65), 3.0, true)
	_text(str(i + 1), c + Vector2(0, _scale * 0.12), 26, Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_CENTER)


func _draw_range(pos: Vector2, type: String, col: Color) -> void:
	var r := float(GameData.hero(type)["range"]) * _scale
	draw_circle(w2s(pos), r, Color(col.r, col.g, col.b, 0.10))
	draw_arc(w2s(pos), r, 0, TAU, 64, Color(col.r, col.g, col.b, 0.55), 2.0, true)


func _draw_setup() -> void:
	var used: Dictionary = {}
	for m in controller.team:
		if int(m["slot"]) >= 0:
			used[int(m["slot"])] = m
	for i in GameData.slots.size():
		if not used.has(i):
			_draw_slot(i, false)
	for slot in used.keys():
		var m: Dictionary = used[slot]
		_draw_range(GameData.slots[slot], m["type"], PlaceholderArt.hero_color(m["type"]))
	for slot in used.keys():
		var m: Dictionary = used[slot]
		var c := w2s(GameData.slots[slot])
		_draw_hero_at(m["type"], _anim("s%d" % slot, m["type"], slot), c)
		_label_under_hero(c, GameData.hero(m["type"])["name"] + " · " + GameData.principle_name(m["principle"]))


func _label_under_hero(c: Vector2, t: String) -> void:
	_text(t, c + Vector2(0, _scale * 0.8), 20, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, true)


func _draw_battle(st: GameState) -> void:
	var alpha := controller.interpolation_alpha()
	var used: Dictionary = {}
	for h in st.heroes:
		used[h.slot] = true
	for i in GameData.slots.size():
		if not used.has(i):
			var c := w2s(GameData.slots[i])
			draw_arc(c, _scale * 0.4, 0, TAU, 24, Color(1, 1, 1, 0.25), 2.0, true)
	var paused := controller.session.is_paused()
	if paused:
		var sh: Entities.Hero = st.heroes[controller.session.active["hero_id"]]
		_draw_range(sh.pos, sh.type, Color(1, 1, 0.6))
	# 투사체
	for p in st.projectiles:
		var pp := w2s(p.prev_pos.lerp(p.pos, alpha))
		draw_circle(pp, _scale * 0.16, Color(0.1, 0.1, 0.12))
		draw_circle(pp + Vector2(_scale * 0.1, -_scale * 0.12), _scale * 0.05, Color(1, 0.6, 0.1))
	# 적 (뒤에 있는 것부터)
	for e in st.enemies:
		if not e.alive:
			continue
		var c := w2s(e.prev_pos.lerp(e.pos, alpha))
		var r: float = e.radius * _scale
		PlaceholderArt.draw_enemy(self, e.type, c, r)
		if e.is_slowed():
			draw_arc(c, r * 1.25, 0, TAU, 20, Color(0.6, 0.9, 1.0, 0.9), 3.0, true)
		if e.is_burning():
			draw_circle(c + Vector2(r * 0.7, -r * 0.7), r * 0.28, Color(1.0, 0.5, 0.1, 0.9))
		if e.is_marked():
			var m := c + Vector2(0, -r * 1.45)
			draw_colored_polygon(PackedVector2Array([m + Vector2(0, -9), m + Vector2(8, 0), m + Vector2(0, 9), m + Vector2(-8, 0)]), Color(1.0, 0.9, 0.2))
		if e.hp < e.max_hp:
			var bw := maxf(r * 2.0, 30.0)
			var bpos := c + Vector2(-bw * 0.5, -r * 1.2 - 8)
			draw_rect(Rect2(bpos, Vector2(bw, 6)), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(bpos, Vector2(bw * e.hp / e.max_hp, 6)), Color(0.95, 0.3, 0.25))
	# 캐릭터
	for h in st.heroes:
		var c := w2s(h.pos)
		if h.last_target_id >= 0 and not paused and st.time - h.last_attack_time < 0.25:
			var t := st.find_enemy(h.last_target_id)
			if t != null and t.alive:
				draw_arc(w2s(t.pos), t.radius * _scale * 1.5, 0, TAU, 20, Color(1, 1, 1, 0.8), 2.0, true)
		var bounce := 0.0
		if st.time - h.last_attack_time < 0.12:
			bounce = -_scale * 0.06
		_draw_hero_at(h.type, _anim("h%d" % h.id, h.type, h.slot), c, 1.0, bounce)
		_label_under_hero(c, GameData.principle_name(h.principle))


func _draw_fx() -> void:
	for f in fx:
		var k := clampf((now - float(f["t0"])) / float(f["dur"]), 0.0, 1.0)
		var a := 1.0 - k
		match f["kind"]:
			"attack":
				var from := w2s(f["from"])
				var pts: Array = f["points"]
				var col := PlaceholderArt.hero_color(f["hero_type"])
				col.a = a
				match f["hero_type"]:
					"LIGHTNING":
						var line := PackedVector2Array([from])
						for p in pts:
							line.append(w2s(p))
						draw_polyline(line, Color(0.85, 0.75, 1.0, a), 4.0)
					"SWORD":
						for p in pts:
							var c := w2s(p)
							draw_arc(c, _scale * 0.45, -PI * 0.8 + k, -PI * 0.1 + k, 10, Color(1, 1, 1, a), 4.0)
					"BOMB":
						pass
					"FIRE":
						draw_line(from, w2s(pts[0]), Color(1.0, 0.55, 0.2, a * 0.7), 3.0)
					"SNIPER":
						draw_line(from, w2s(pts[0]), Color(1.0, 0.95, 0.7, a), 4.0)
					_:
						draw_line(from, w2s(pts[0]), col.lightened(0.3), 3.0)
			"boom":
				var c := w2s(f["pos"])
				var r := float(f["radius"]) * _scale * (0.6 + 0.4 * k)
				var col: Color = Color(1.0, 0.5, 0.15, 0.45 * a) if f["fire"] else Color(1.0, 0.85, 0.4, 0.5 * a)
				draw_circle(c, r, col)
				draw_arc(c, r, 0, TAU, 32, Color(1, 1, 1, 0.6 * a), 3.0)
			"special":
				# 특기 발휘: 캐릭터 색 고리 + 빛줄기 + 특기 이름
				var c := w2s(f["pos"]) + Vector2(0, -_scale * 0.35)
				var col := PlaceholderArt.hero_color(f["hero_type"])
				var r := _scale * (0.5 + 1.0 * k)
				draw_arc(c, r, 0, TAU, 40, Color(col.r, col.g, col.b, 0.8 * a), 5.0, true)
				for i in 8:
					var dir := Vector2.from_angle(TAU * i / 8.0 + k)
					draw_line(c + dir * r * 0.6, c + dir * r * 1.05, Color(1, 1, 0.85, 0.7 * a), 3.0)
				_text(f["text"], c + Vector2(0, -_scale * (1.45 + 0.35 * k)), 26, Color(1, 0.95, 0.6, a), HORIZONTAL_ALIGNMENT_CENTER, true)
			"puff":
				var c := w2s(f["pos"])
				draw_arc(c, _scale * (0.2 + 0.4 * k), 0, TAU, 20, Color(1, 1, 1, 0.8 * a), 3.0)
			"leak":
				var bp := w2s(GameData.path.end_point())
				_text("-%d" % int(f["damage"]), bp + Vector2(0, -_scale * (1.4 + 0.6 * k)), 44, Color(1, 0.3, 0.3, a), HORIZONTAL_ALIGNMENT_CENTER, true)


func _draw_hud(st: GameState) -> void:
	draw_rect(Rect2(0, 0, size.x, HUD_H), C_PANEL)
	# 기지 HP
	var hp_txt := "기지 HP  %d / %d" % [st.base_hp, st.base_hp_max]
	_text(hp_txt, Vector2(24, 50), 34, C_TEXT)
	var bw := 260.0
	var bx := 290.0
	draw_rect(Rect2(bx, 26, bw, 26), Color(0, 0, 0, 0.5))
	var ratio := float(st.base_hp) / float(maxi(1, st.base_hp_max))
	draw_rect(Rect2(bx, 26, bw * ratio, 26), Color(0.3, 0.85, 0.4) if ratio > 0.4 else Color(0.95, 0.35, 0.3))
	# 웨이브
	var wave_name := "준비"
	if st.wave_index >= 0:
		wave_name = "웨이브 %d / %d" % [st.wave_index + 1, GameData.waves.size()]
	_text(wave_name, Vector2(size.x * 0.5, 50), 36, Color(1, 0.95, 0.6), HORIZONTAL_ALIGNMENT_CENTER)
	# 진행도 막대 (전체 웨이브 진행)
	var total := 0.0
	var done := 0.0
	for i in GameData.waves.size():
		var d := float(GameData.waves[i]["duration"])
		total += d
		if i < st.wave_index:
			done += d
		elif i == st.wave_index:
			done += minf(st.wave_time, d)
	draw_rect(Rect2(size.x * 0.5 - 200, 62, 400, 8), Color(0, 0, 0, 0.5))
	draw_rect(Rect2(size.x * 0.5 - 200, 62, 400 * clampf(done / total, 0, 1), 8), Color(1, 0.85, 0.3))
	var secs := int(st.time)
	_text("시간 %d:%02d   처치 %d" % [secs / 60, secs % 60, st.kills], Vector2(size.x - 24, 50), 32, C_TEXT, HORIZONTAL_ALIGNMENT_RIGHT)


func _bubble_rect(anchor: Vector2, text: String, fs: int, max_w: float) -> Rect2:
	var sz := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, max_w, fs)
	var pad := Vector2(22, 16)
	var box := sz + pad * 2
	var pos := anchor + Vector2(-box.x * 0.5, -box.y - 18)
	if pos.y < HUD_H + 8:
		pos.y = anchor.y + _scale * 0.9  # 위가 막히면 아래로
	pos.x = clampf(pos.x, 12, size.x - box.x - 12)
	pos.y = clampf(pos.y, HUD_H + 8, size.y - box.y - 12)
	return Rect2(pos, box)


func _draw_bubble(st: GameState) -> void:
	var b: Dictionary = controller.session.speech.current
	if b.is_empty():
		return
	var h: Entities.Hero = st.heroes[b["hero"]]
	var anchor := w2s(h.pos) + Vector2(0, -_scale * (HERO_H - 0.25))
	var text := "%s: %s" % [GameData.hero(h.type)["name"], b["text"]]
	var fs := 30
	var r := _bubble_rect(anchor, text, fs, 520)
	_draw_box(r, Color(1, 1, 1, 0.96), Color(0.2, 0.2, 0.25), anchor)
	draw_multiline_string(font, r.position + Vector2(22, 16 + fs), text, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 44, fs, -1, Color(0.1, 0.1, 0.15))


func _draw_box(r: Rect2, fill: Color, border: Color, tail_to: Vector2 = Vector2.INF) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(16)
	if tail_to != Vector2.INF:
		var base_x := clampf(tail_to.x, r.position.x + 24, r.end.x - 24)
		var base_y := r.end.y if tail_to.y > r.end.y else r.position.y
		var tip := tail_to
		draw_colored_polygon(PackedVector2Array([Vector2(base_x - 14, base_y), Vector2(base_x + 14, base_y), tip]), border)
		draw_colored_polygon(PackedVector2Array([Vector2(base_x - 10, base_y), Vector2(base_x + 10, base_y), tip.lerp(Vector2(base_x, base_y), 0.25)]), fill)
	draw_style_box(sb, r)


func _draw_suggestion(st: GameState) -> void:
	var s: Dictionary = controller.session.active
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.45))
	var h: Entities.Hero = st.heroes[s["hero_id"]]
	var c := w2s(h.pos)
	draw_circle(c, _scale * 0.7, Color(1, 1, 0.6, 0.35))
	_draw_hero_at(h.type, _anim("h%d" % h.id, h.type, h.slot), c, 1.25)
	var title := "%s의 %s" % [GameData.hero(h.type)["name"], "제안" if s["has_change"] else "의견"]
	var body: String = s["message"]
	var fs := 34
	var max_w := minf(1100.0, size.x - 120)
	var sz := font.get_multiline_string_size(body, HORIZONTAL_ALIGNMENT_LEFT, max_w, fs)
	var box := Vector2(max_w + 60, sz.y + 170)
	var pos := Vector2((size.x - box.x) * 0.5, c.y - box.y - _scale * 2.0)
	if pos.y < HUD_H + 10:
		pos.y = c.y + _scale * 1.0
	pos.y = clampf(pos.y, HUD_H + 10, size.y - box.y - 10)
	var r := Rect2(pos, box)
	_draw_box(r, Color(1, 1, 0.97), Color(0.95, 0.75, 0.2), c + Vector2(0, -_scale * 1.7))
	_text(title, r.position + Vector2(30, 52), 38, Color(0.55, 0.35, 0.0))
	draw_multiline_string(font, r.position + Vector2(30, 70 + fs), body, HORIZONTAL_ALIGNMENT_LEFT, max_w, fs, -1, Color(0.1, 0.1, 0.15))
	var left := int(ceil(controller.suggestion_time_left()))
	_text("전투 잠깐 멈춤 · 터치 화면에서 골라 줘! (%d초 뒤 그대로 진행)" % left, Vector2(r.position.x + 30, r.end.y - 24), 26, Color(0.35, 0.35, 0.4))
	_text("일시정지", Vector2(size.x * 0.75, 50), 32, Color(1, 0.9, 0.4), HORIZONTAL_ALIGNMENT_CENTER)


func _draw_banner(t: String) -> void:
	var fs := 56
	var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 80
	var r := Rect2(Vector2((size.x - w) * 0.5, size.y * 0.42), Vector2(w, 100))
	_draw_box(r, Color(0.1, 0.12, 0.18, 0.85), Color(1, 0.85, 0.3))
	_text(t, Vector2(size.x * 0.5, r.position.y + 70), fs, Color(1, 0.95, 0.7), HORIZONTAL_ALIGNMENT_CENTER)


func _draw_attract() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.5))
	var cx := size.x * 0.5
	_text(GameData.text("ui", "title"), Vector2(cx, size.y * 0.33), 120, Color(1, 0.92, 0.55), HORIZONTAL_ALIGNMENT_CENTER, true)
	_text(GameData.text("ui", "subtitle"), Vector2(cx, size.y * 0.45), 46, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, true)
	var guide := GameData.text("ui", "guide")
	draw_multiline_string(font, Vector2(size.x * 0.18, size.y * 0.56), guide, HORIZONTAL_ALIGNMENT_CENTER, size.x * 0.64, 34, -1, Color(0.95, 0.95, 0.95))
	var blink := 0.6 + 0.4 * sin(now * 3.0)
	_text("터치 화면의 [시작]을 눌러 주세요", Vector2(cx, size.y * 0.8), 44, Color(1, 1, 0.6, blink), HORIZONTAL_ALIGNMENT_CENTER, true)
	_text(GameData.text("ui", "ai_note"), Vector2(cx, size.y - 30), 22, Color(0.85, 0.85, 0.85), HORIZONTAL_ALIGNMENT_CENTER)


func _draw_setup_banner() -> void:
	draw_rect(Rect2(0, 0, size.x, HUD_H), C_PANEL)
	var t := "작전 준비 중 — 터치 화면에서 캐릭터 3명을 고르고 있어요 (%d/3)" % controller.selected.size()
	if controller.phase == GameController.PLACE:
		t = "작전 준비 중 — 터치 화면에서 캐릭터를 자리에 놓고 행동 원칙을 정해요"
	_text(t, Vector2(size.x * 0.5, 50), 34, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_result() -> void:
	var r: Dictionary = controller.result
	if r.is_empty():
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55))
	var box := Rect2(Vector2(size.x * 0.2, size.y * 0.12), Vector2(size.x * 0.6, size.y * 0.76))
	_draw_box(box, Color(0.1, 0.12, 0.18, 0.95), Color(1, 0.85, 0.3))
	var cx := size.x * 0.5
	var title := "방어 성공!" if r["outcome"] == "win" else "끝까지 잘 버텼어요!"
	_text(title, Vector2(cx, box.position.y + 100), 72, Color(1, 0.92, 0.55), HORIZONTAL_ALIGNMENT_CENTER)
	var secs := int(r["time"])
	var lines := [
		"생존 시간  %d:%02d" % [secs / 60, secs % 60],
		"마지막 웨이브  %d / %d" % [int(r["wave"]) + 1, GameData.waves.size()],
		"기지 남은 HP  %d / %d" % [r["hp"], r["hp_max"]],
		"처치한 적  %d" % r["kills"],
		"점수  %d" % r["score"],
	]
	var y := box.position.y + 190
	for l in lines:
		_text(l, Vector2(cx, y), 40, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
		y += 58
	y += 20
	var fin: Array = []
	for h in r["heroes"]:
		fin.append("%s: %s" % [GameData.hero(h["type"])["name"], GameData.principle_name(h["principle"])])
	_text("내가 정한 최종 작전 — " + "  ·  ".join(fin), Vector2(cx, y), 30, Color(0.85, 0.95, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
	y += 46
	var dec: Array = r["decisions"]
	var acc := 0
	var kept := 0
	var other := 0
	for d in dec:
		match d["choice"]:
			"accept": acc += 1
			"other": other += 1
			_: kept += 1
	var dline := "AI 제안 %d번 — 바꿔봄 %d · 유지 %d · 직접 고름 %d" % [dec.size(), acc, kept, other]
	if dec.is_empty():
		dline = "이번 판에는 AI의 특별 제안이 없었어요"
	_text(dline, Vector2(cx, y), 30, Color(0.85, 0.95, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
	y += 66
	_text(GameData.text("ui", "result_message"), Vector2(cx, y), 40, Color(1, 1, 0.7), HORIZONTAL_ALIGNMENT_CENTER)
	y += 56
	_text(GameData.text("ui", "end_message"), Vector2(cx, y), 28, Color(0.9, 0.9, 0.9), HORIZONTAL_ALIGNMENT_CENTER)


func _text(t: String, pos: Vector2, fs: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, outline := false) -> void:
	var p := pos
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		p.x -= font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		p.x -= font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if outline:
		draw_string_outline(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(3, fs / 9), Color(0, 0, 0, 0.75 * col.a))
	draw_string(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _fit_to_viewport() -> void:
	## 창(뷰포트) 크기에 항상 꽉 차게 (창 이동·전체화면 전환·화면 역할 바꾸기 후에도)
	var vr := get_viewport_rect()
	if position != Vector2.ZERO or size != vr.size:
		position = Vector2.ZERO
		size = vr.size


# ---------------- 캐릭터 그림·애니메이션 ----------------

func _anim(key: String, type: String, seed_value: int) -> HeroSprite.Anim:
	var a: HeroSprite.Anim = anims.get(key)
	if a == null or a.type != type:
		a = HeroSprite.Anim.new(type, seed_value + 1)
		anims[key] = a
	return a


func _draw_hero_at(type: String, a: HeroSprite.Anim, slot_center: Vector2, mult := 1.0, fallback_bounce := 0.0) -> void:
	## 슬롯 가운데보다 조금 아래가 발 위치. PNG가 없으면 도형으로.
	var feet := slot_center + Vector2(0, _scale * 0.42)
	draw_set_transform(feet, 0.0, Vector2(1.0, 0.3))
	draw_circle(Vector2.ZERO, _scale * 0.42 * mult, Color(0, 0, 0, 0.22))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if not HeroSprite.draw(self, a, feet, _scale * HERO_H * mult, now):
		PlaceholderArt.draw_hero(self, type, slot_center + Vector2(0, -_scale * 0.15 + fallback_bounce), _scale * 0.42 * mult, font)


func _on_attack_anim(ev: Dictionary) -> void:
	var a := _anim("h%d" % int(ev["hero"]), ev["hero_type"], 0)
	var target_pos: Vector2 = ev["points"][0]
	var from: Vector2 = ev["from"]
	a.trigger(now, bool(ev.get("special", false)), target_pos.x - from.x)
	if a.special and a.atk_t0 == now:
		fx.append({"kind": "special", "pos": from, "hero_type": ev["hero_type"], "t0": now, "dur": 0.9,
			"text": str(GameData.hero(ev["hero_type"]).get("special_name", "특기")) + "!"})
