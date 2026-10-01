extends Control
## 빨간 색연필로 동그라미를 휙 치는 연출. 이 칸(부모가 정해 준 크기)을 감싸듯 그린다.
##
##   play()  : 처음부터 한 번 빠르게 그린다 (약 0.2초).
##   clear() : 지운다.
## 손으로 친 동그라미처럼 보이게:
##   - 오른쪽 아래 원 바깥에서 시작해 한 바퀴 돌고, 시작한 선을 가로질러 오른쪽 위로 빠져나간다 (양 끝이 삐져나옴).
##   - 둥근 원이 아니라 한쪽이 불룩한 달걀 모양이다.
##   - 반지름이 크고 느리게 출렁이고(선은 매끈하게), 선 굵기는 시작과 끝이 가늘다.
##   - 살짝 어긋난 흐린 선을 한 번 더 겹쳐 색연필 결처럼 보이게 한다.
##   - 그릴 때마다 시작 위치·기울기·출렁임이 조금씩 달라진다.

const COLOR := Color(0.86, 0.15, 0.12, 0.88)
const GRAIN_COLOR := Color(0.86, 0.15, 0.12, 0.35)   # 겹쳐 그리는 흐린 선
const WIDTH := 3.8
const DRAW_SECONDS := 0.2
const SWEEP_DEGREES := 395.0          # 한 바퀴 넘게 돌아 시작한 선을 가로지른다
const START_DEGREES := 62.0           # 오른쪽 아래에서 시작 (그릴 때마다 ±12도)
const SCALE := Vector2(1.2, 1.18)     # 칸 모서리 글자까지 넉넉히 감싸도록 칸보다 크게
const SPREAD := 0.05                  # 그리는 동안 바깥으로 벌어지는 정도 (반지름 비율)
const ENTER_TAIL := 0.16              # 시작 꼬리가 원 바깥(아래)으로 삐져나온 정도
const FLICK := 0.24                   # 끝 꼬리가 원 바깥으로 휙 빠져나가는 정도
const EGG := 0.06                     # 한쪽이 불룩한 달걀 모양 정도
const SEGMENTS := 180                  # 많을수록 선이 매끈하다

var mirrored := false   # true면 좌우를 뒤집어 그린다 (꼬리가 왼쪽에서 겹침). 왼쪽 카드는 오른쪽이 메인 창에 가려지므로 뒤집는다.

var progress := 0.0:
	set(value):
		progress = value
		queue_redraw()

var _tween: Tween
var _phase_a := 0.0
var _phase_b := 0.0
var _start := START_DEGREES
var _tilt := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func play(delay: float = 0.0) -> void:
	if _tween != null:
		_tween.kill()
	_phase_a = randf() * TAU
	_phase_b = randf() * TAU
	_start = START_DEGREES + randf_range(-12.0, 12.0)
	_tilt = deg_to_rad(randf_range(-6.0, 4.0))
	progress = 0.0
	_tween = create_tween()
	_tween.tween_interval(delay)
	_tween.tween_property(self, "progress", 1.0, DRAW_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)


func clear() -> void:
	if _tween != null:
		_tween.kill()
	progress = 0.0


func _draw() -> void:
	if progress <= 0.0:
		return
	_draw_stroke(Vector2.ZERO, 1.0, COLOR, 0.0)
	_draw_stroke(Vector2(0.8, -0.6), 0.6, GRAIN_COLOR, 0.15)


## 한 줄 긋기. offset: 어긋남, width_scale: 굵기 배율, jitter_phase: 출렁임을 조금 다르게
func _draw_stroke(offset: Vector2, width_scale: float, color: Color, jitter_phase: float) -> void:
	var center := size / 2.0 + offset
	var base := size / 2.0 * SCALE
	var count := maxi(2, int(SEGMENTS * progress))
	var previous := Vector2.ZERO
	for i in count + 1:
		var t := float(i) / SEGMENTS   # 0 ~ progress
		# 오른쪽 아래에서 시작해 위로 올라가며 거꾸로(반시계) 한 바퀴 돌고, 시작한 선을 가로질러 오른쪽 위로 빠져나간다
		var angle := deg_to_rad(_start - SWEEP_DEGREES * t)
		# 시작 꼬리: 원 바깥(아래)에서 들어온다 / 끝 꼬리: 원 바깥으로 빠져나간다
		var enter := ENTER_TAIL * pow(maxf(0.0, 1.0 - t / 0.12), 2.0)
		var leave := FLICK * pow(maxf(0.0, (t - 0.82) / 0.18), 1.6)
		# 달걀처럼 한쪽(왼쪽 위)이 더 불룩하고, 손떨림처럼 잘게 출렁인다
		var egg := EGG * cos(angle - deg_to_rad(-135.0))
		# 출렁임은 크고 느리게만 (잘게 떨리면 선이 삐뚤빼뚤해 보인다)
		var wobble := 0.025 * sin(angle * 2.0 + _phase_a + jitter_phase) + 0.01 * sin(angle * 3.0 + _phase_b)
		var grow := 0.97 + SPREAD * t + egg + wobble + enter + leave
		var local := (Vector2(cos(angle) * base.x, sin(angle) * base.y) * grow).rotated(_tilt)
		if mirrored:
			local.x = -local.x
		var point := center + local
		if i > 0:
			# 시작과 끝은 가늘게 (손에 힘이 들어갔다 빠지는 느낌)
			var pressure := clampf(minf(t / 0.12, (1.0 - t) / 0.18), 0.25, 1.0)
			draw_line(previous, point, color, WIDTH * width_scale * pressure, true)
		previous = point
