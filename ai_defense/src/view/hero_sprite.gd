class_name HeroSprite
extends RefCounted
## 캐릭터 그림 + 애니메이션 (대기 / 일반 공격 / 특기 공격).
##
## 두 가지 방식
##  1) 파츠 리그: assets/heroes/rigs/<asset>/rig.json + 파츠 PNG가 있으면 관절별로 회전 (현재 검객)
##     - rig.json 형식은 아트 패키지의 rig_manifest.json 그대로 (512 캔버스, pivot, parent, z)
##  2) 통짜 그림: assets/heroes/<asset>.png 한 장을 늘이기·기울이기·점프로 움직임 (나머지 7종)
## 둘 다 없으면 호출한 쪽이 도형 플레이스홀더를 그린다.
## 기준점: 그림의 불투명 영역 아래쪽 가운데 = 발 위치. 높이는 불투명 영역 기준으로 맞춘다
## (그림마다 여백이 달라도 크기가 일정하게 보이도록).
##
## 전투 로직과 완전히 분리되어 있다. 엔진은 ATTACK 이벤트에 special(특기 발휘) 표시만 준다.

const SPECIAL_COOLDOWN := 2.2  # 특기 모션은 너무 자주 반복되지 않게
const ATTACK_DUR := {"SWORD": 0.34, "ARCHER": 0.28, "SNIPER": 0.5, "FIRE": 0.45, "ICE": 0.4,
	"LIGHTNING": 0.42, "BOMB": 0.5, "MARK": 0.38}
const SPECIAL_DUR := 0.75
# 캐릭터별 공격 스타일: melee(앞으로 베기), shoot(반동), cast(지팡이 들어 올리기), throw(던지기)
const STYLE := {"SWORD": "melee", "ARCHER": "shoot", "SNIPER": "shoot", "FIRE": "cast", "ICE": "cast",
	"LIGHTNING": "cast", "BOMB": "throw", "MARK": "cast"}

static var _rect_cache: Dictionary = {}
static var _rig_cache: Dictionary = {}


class Anim:
	extends RefCounted
	var type := "SWORD"
	var phase := 0.0  # 캐릭터마다 숨쉬기 박자를 다르게
	var atk_t0 := -100.0
	var atk_dur := 0.3
	var special := false
	var facing := 1.0  # 1 = 원본 방향, -1 = 좌우 반전 (표적 쪽을 봄)
	var last_special := -100.0

	func _init(t: String = "SWORD", seed_value: int = 0) -> void:
		type = t
		phase = fposmod(float(seed_value) * 0.737, 1.0) * 3.0

	func trigger(now: float, is_special: bool, target_dx: float) -> void:
		if absf(target_dx) > 0.05:
			facing = 1.0 if target_dx > 0.0 else -1.0
		if is_special and now - last_special >= SPECIAL_COOLDOWN:
			special = true
			last_special = now
			atk_dur = SPECIAL_DUR
		else:
			special = false
			atk_dur = float(ATTACK_DUR.get(type, 0.35))
		atk_t0 = now

	func progress(now: float) -> float:
		var p := (now - atk_t0) / atk_dur
		return p if p >= 0.0 and p < 1.0 else -1.0


# ---------------- 공용 ----------------

static func has_art(type: String) -> bool:
	return AssetManifest.hero_texture(type) != null or rig_for(type) != null


static func used_rect(tex: Texture2D) -> Rect2:
	var key := tex.get_rid().get_id()
	if _rect_cache.has(key):
		return _rect_cache[key]
	var r := Rect2(Vector2.ZERO, tex.get_size())
	var img := tex.get_image()
	if img != null and not img.is_empty():
		if img.is_compressed():
			img.decompress()
		var u := img.get_used_rect()
		if u.size.x > 0 and u.size.y > 0:
			r = Rect2(u)
	_rect_cache[key] = r
	return r


static func _ease_attack(p: float) -> float:
	## -0.35(뒤로 준비) → 1(타격) → 0(복귀)
	if p < 0.28:
		return -0.35 * sin(p / 0.28 * PI * 0.5)
	if p < 0.45:
		return lerpf(-0.35, 1.0, (p - 0.28) / 0.17)
	return 1.0 - smoothstep(0.45, 1.0, p)


class Pose:
	extends RefCounted
	var sx := 1.0
	var sy := 1.0
	var skew := 0.0
	var off := Vector2.ZERO  # 높이 비율 단위
	var spin := 1.0  # 종이 돌리기 연출 (x 배율에 곱함)
	var arm := 0.0  # 리그 전용: 무기 팔 휘두르기 (-0.4~1)
	var arm2 := 0.0  # 리그 전용: 반대 팔
	var glow := 0.0


static func pose_for(anim: Anim, now: float) -> Pose:
	var ps := Pose.new()
	var t := now + anim.phase
	var breathe := sin(t * TAU / 2.4)
	ps.sy = 1.0 + 0.022 * breathe
	ps.sx = 1.0 - 0.012 * breathe
	ps.skew = 0.02 * sin(t * TAU / 3.7)
	ps.arm2 = 0.04 * breathe
	var p := anim.progress(now)
	if p < 0.0:
		return ps
	var style: String = STYLE.get(anim.type, "melee")
	var f := anim.facing
	if not anim.special:
		var a := _ease_attack(p)
		match style:
			"melee":
				ps.skew += 0.16 * a * f
				ps.off.x += 0.07 * a * f
				ps.sx *= 1.0 + 0.05 * a
				ps.sy *= 1.0 - 0.04 * a
				ps.arm = a
			"shoot":
				# 쏘는 순간 몸이 뒤로 밀리는 반동
				var r := maxf(0.0, a)
				ps.skew += (-0.10 * r + 0.05 * minf(0.0, a)) * f
				ps.off.x -= 0.05 * r * f
				ps.sy *= 1.0 - 0.05 * r
				ps.sx *= 1.0 + 0.04 * r
			"cast":
				# 지팡이를 들어 올리며 위로 늘어남
				var u := maxf(0.0, a)
				ps.sy *= 1.0 + 0.09 * u - 0.06 * maxf(0.0, -a) * 3.0
				ps.sx *= 1.0 - 0.04 * u
				ps.off.y -= 0.04 * u
				ps.skew += 0.06 * a * f
				ps.glow = u
			"throw":
				ps.skew += (0.22 * a) * f
				ps.off.x += 0.04 * a * f
				ps.sy *= 1.0 - 0.06 * absf(a)
				ps.arm = a
		return ps
	# ---- 특기 공격: 웅크림 → 점프 → 착지 ----
	var crouch := 0.0
	var air := 0.0
	if p < 0.2:
		crouch = sin(p / 0.2 * PI * 0.5)
	elif p < 0.75:
		air = sin((p - 0.2) / 0.55 * PI)
	else:
		crouch = 0.6 * sin((p - 0.75) / 0.25 * PI)
	ps.sy *= 1.0 - 0.16 * crouch + 0.10 * air
	ps.sx *= 1.0 + 0.12 * crouch - 0.05 * air
	ps.off.y -= 0.22 * air
	ps.glow = air
	match style:
		"melee":
			# 공중에서 두 번 베기
			var q := clampf((p - 0.2) / 0.55, 0.0, 1.0)
			ps.arm = sin(q * TAU * 2.0 - PI * 0.5) * 0.5 + 0.5 if q > 0.0 else -0.35 * crouch
			ps.arm = lerpf(-0.4, 1.0, ps.arm)
			ps.skew += 0.14 * ps.arm * f * air
		"shoot":
			# 크게 숨 고르고 한 방 → 큰 반동
			var r := 0.0
			if p > 0.45:
				r = 1.0 - smoothstep(0.45, 1.0, p)
			ps.off.y = -0.06 * air
			ps.sy = 1.0 - 0.1 * crouch
			ps.skew += (-0.2 * r + 0.06 * crouch) * f
			ps.off.x -= 0.1 * r * f
			ps.glow = 1.0 - absf(p - 0.45) * 2.0
		"cast", "throw":
			# 빙그르 한 바퀴 돌며 시전
			if p >= 0.2 and p < 0.75:
				ps.spin = cos((p - 0.2) / 0.55 * TAU)
			ps.arm = air
	return ps


# ---------------- 그리기 ----------------

static func draw(ci: CanvasItem, anim: Anim, feet: Vector2, height: float, now: float, alpha := 1.0) -> bool:
	## 그림이 있으면 그리고 true. 없으면 false (호출한 쪽이 도형으로 그림)
	var ps := pose_for(anim, now)
	var rig := rig_for(anim.type)
	if rig != null:
		_draw_rig(ci, rig, ps, anim, feet, height, now, alpha)
		return true
	var tex := AssetManifest.hero_texture(anim.type)
	if tex == null:
		return false
	var ur := used_rect(tex)
	var s := height / ur.size.y
	var base := _base_xform(ps, anim, feet, height)
	if ps.glow > 0.01:
		_draw_glow(ci, anim.type, feet + Vector2(0, -height * 0.45) + ps.off * height, height * 0.5, ps.glow, alpha)
	ci.draw_set_transform_matrix(base)
	ci.draw_texture_rect_region(tex, Rect2(Vector2(-ur.size.x * 0.5 * s, -ur.size.y * s), ur.size * s), ur, Color(1, 1, 1, alpha))
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	return true


static func _base_xform(ps: Pose, anim: Anim, feet: Vector2, height: float) -> Transform2D:
	var xs := ps.sx * anim.facing * ps.spin
	if absf(xs) < 0.02:
		xs = 0.02 * signf(xs if xs != 0.0 else 1.0)
	# 발 기준 변형. skew는 화면 기준 방향 (+면 머리가 오른쪽으로)
	return Transform2D(0.0, Vector2(xs, ps.sy), ps.skew * signf(xs), feet + ps.off * height)


static func _draw_glow(ci: CanvasItem, type: String, center: Vector2, r: float, k: float, alpha: float) -> void:
	var col := PlaceholderArt.hero_color(type).lightened(0.55)
	ci.draw_circle(center, r * 0.8, Color(col.r, col.g, col.b, 0.16 * k * alpha))
	for i in 3:
		var rr := r * (0.75 + 0.18 * i)
		ci.draw_arc(center, rr, 0, TAU, 40, Color(col.r, col.g, col.b, (0.45 - 0.12 * i) * k * alpha), 3.0, true)


static func draw_static(ci: CanvasItem, type: String, feet: Vector2, height: float, alpha := 1.0) -> bool:
	## 카드·지도용 (대기 동작만, 실제 시간으로 숨쉬기)
	var a := Anim.new(type, type.hash())
	return draw(ci, a, feet, height, Time.get_ticks_msec() / 1000.0, alpha)


# ---------------- 파츠 리그 ----------------

class Rig:
	extends RefCounted
	var parts: Array = []  # [{name, z, pivot, parent, tex, rect}] z 순
	var by_name: Dictionary = {}
	var bounds := Rect2()  # 전체 불투명 영역 (캔버스 좌표)


static func rig_for(type: String) -> Rig:
	var asset := str(GameData.hero(type).get("asset", type.to_lower()))
	if _rig_cache.has(asset):
		return _rig_cache[asset]
	var rig: Rig = null
	var dir := "res://assets/heroes/rigs/%s/" % asset
	var ext_dir := ""
	if OS.has_feature("template"):
		ext_dir = GameData.external_dir().path_join("assets/heroes/rigs").path_join(asset) + "/"
	var json_path := ""
	if ext_dir != "" and FileAccess.file_exists(ext_dir + "rig.json"):
		json_path = ext_dir + "rig.json"
	elif FileAccess.file_exists(dir + "rig.json"):
		json_path = dir + "rig.json"
	if json_path != "":
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(json_path))
		if parsed is Dictionary and parsed.has("part_layers"):
			rig = Rig.new()
			var first := true
			for p in parsed["part_layers"]:
				var tex := _load_part(ext_dir, dir, str(p["name"]))
				if tex == null:
					rig = null
					break
				var r := used_rect(tex)
				var part := {"name": str(p["name"]), "z": int(p.get("z", 0)), "pivot": Vector2(float(p["pivot"][0]), float(p["pivot"][1])),
					"parent": p.get("parent", null), "tex": tex, "rect": r}
				rig.parts.append(part)
				rig.by_name[part["name"]] = part
				rig.bounds = r if first else rig.bounds.merge(r)
				first = false
			if rig != null:
				rig.parts.sort_custom(func(a, b): return a["z"] < b["z"])
	_rig_cache[asset] = rig
	return rig


static func _load_part(ext_dir: String, dir: String, name: String) -> Texture2D:
	if ext_dir != "" and FileAccess.file_exists(ext_dir + name + ".png"):
		var img := Image.load_from_file(ext_dir + name + ".png")
		if img != null and not img.is_empty():
			return ImageTexture.create_from_image(img)
	if ResourceLoader.exists(dir + name + ".png"):
		var t: Variant = load(dir + name + ".png")
		if t is Texture2D:
			return t
	return null


static func _rig_angles(ps: Pose, now: float, anim: Anim) -> Dictionary:
	var t := now + anim.phase
	var sway := sin(t * 2.0)
	var a := ps.arm
	# 검 휘두르기: 위로 들었다가(+) 앞으로 크게 내려 벤다(−)
	var swing := 0.0
	if a < 0.0:
		swing = -a * 1.1  # 준비: 검을 뒤로 들기
	else:
		swing = lerpf(0.0, -1.25, a)
	return {
		"torso": sway * 0.013,
		"head_face": -sway * 0.016,
		"hair_front": -sway * 0.02,
		"hair_back": -sway * 0.018,
		"coat_back": sin(t * 2.6) * 0.03,
		"upper_arm_left": swing * 0.45 + sway * 0.01,
		"forearm_left": swing * 0.3,
		"weapon_sword": swing,
		"upper_arm_right": -0.15 * maxf(0.0, a) + ps.arm2,
		"forearm_right": -0.1 * maxf(0.0, a),
		"leg_left": 0.05 * minf(0.0, a),
		"leg_right": -0.06 * maxf(0.0, a),
	}


static func _draw_rig(ci: CanvasItem, rig: Rig, ps: Pose, anim: Anim, feet: Vector2, height: float, now: float, alpha: float) -> void:
	var s := height / rig.bounds.size.y
	var base := _base_xform(ps, anim, feet, height)
	# 캔버스 좌표 → 발 기준 좌표: 불투명 영역 아래쪽 가운데가 (0,0)
	var anchor := Vector2(rig.bounds.position.x + rig.bounds.size.x * 0.5, rig.bounds.end.y)
	var to_local := base * Transform2D(0.0, Vector2(s, s), 0.0, Vector2.ZERO) * Transform2D(0.0, -anchor)
	if ps.glow > 0.01:
		_draw_glow(ci, anim.type, feet + Vector2(0, -height * 0.45) + ps.off * height, height * 0.5, ps.glow, alpha)
	var ang := _rig_angles(ps, now, anim)
	var globals: Dictionary = {}
	for part in rig.parts:
		globals[part["name"]] = _part_xform(rig, part, ang, globals)
	for part in rig.parts:
		var xf: Transform2D = to_local * globals[part["name"]]
		ci.draw_set_transform_matrix(xf)
		var r: Rect2 = part["rect"]
		var pv: Vector2 = part["pivot"]
		ci.draw_texture_rect_region(part["tex"], Rect2(r.position - pv, r.size), r, Color(1, 1, 1, alpha))
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


static func _part_xform(rig: Rig, part: Dictionary, ang: Dictionary, globals: Dictionary) -> Transform2D:
	## 캔버스 좌표계에서 이 파츠의 변환 (관절 위치로 옮긴 뒤 회전). 그림은 (-pivot)에 그린다.
	var pv: Vector2 = part["pivot"]
	var rot := float(ang.get(part["name"], 0.0))
	var parent = part["parent"]
	if parent != null and globals.has(parent):
		var pp: Vector2 = rig.by_name[parent]["pivot"]
		return globals[parent] * Transform2D(rot, pv - pp)
	return Transform2D(rot, pv)
