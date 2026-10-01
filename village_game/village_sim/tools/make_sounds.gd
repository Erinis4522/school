extends SceneTree
## 임시 소리(placeholder) 생성 도구. 짧은 효과음 4개와 반복되는 배경음 1곡을 코드로 합성해 WAV로 저장한다.
##
## 실행 (프로젝트 폴더에서):
##   godot --headless --script res://village_sim/tools/make_sounds.gd
## 결과: village_sim/assets/placeholders/audio/ 아래 WAV (있으면 덮어씀)
##
## 최종 소리가 아니다. 실제 소리는 assets/audio/ 아래 같은 이름으로 넣으면 이 임시 소리 대신 쓰인다.
##   sfx/button      버튼 누를 때        sfx/advance     대사 넘길 때
##   sfx/card_out    인물 카드 펼칠 때    sfx/card_select 선택을 결정할 때
##   bgm/village_theme  배경음 (반복)

const OUT := "res://village_sim/assets/placeholders/audio/"
const RATE := 22050


func _init() -> void:
	_save(_button(), "sfx/button")
	_save(_advance(), "sfx/advance")
	_save(_card_out(), "sfx/card_out")
	_save(_card_select(), "sfx/card_select")
	_save(_village_theme(), "bgm/village_theme")
	print("임시 소리 생성 완료: ", ProjectSettings.globalize_path(OUT))
	quit()


# --- 합성 도구 ---------------------------------------------------------------------

func _buffer(seconds: float) -> PackedFloat32Array:
	var buffer := PackedFloat32Array()
	buffer.resize(int(seconds * RATE))
	return buffer


## 음 하나를 더한다. wave: "sine" / "soft"(사인 + 약한 배음) / "triangle"
func _note(buffer: PackedFloat32Array, start: float, length: float, freq: float, volume: float, wave: String = "soft", attack: float = 0.008, freq_end: float = -1.0) -> void:
	var first := int(start * RATE)
	var count := int(length * RATE)
	var phase := 0.0
	for i in count:
		var index := first + i
		if index >= buffer.size():
			break
		var t := float(i) / RATE
		var progress := float(i) / count
		var f := freq if freq_end < 0.0 else lerpf(freq, freq_end, progress)
		phase += TAU * f / RATE
		var sample := 0.0
		match wave:
			"sine":
				sample = sin(phase)
			"triangle":
				sample = 2.0 * absf(2.0 * fposmod(phase / TAU, 1.0) - 1.0) - 1.0
			_:
				sample = sin(phase) + 0.25 * sin(phase * 2.0) + 0.08 * sin(phase * 3.0)
		var envelope := minf(1.0, t / attack) * exp(-4.5 * progress)
		buffer[index] += sample * envelope * volume


## 부드러운 바람 소리(걸러 낸 잡음). 휙 하고 지나가는 느낌
func _swish(buffer: PackedFloat32Array, start: float, length: float, volume: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var first := int(start * RATE)
	var count := int(length * RATE)
	var smooth := 0.0
	for i in count:
		var index := first + i
		if index >= buffer.size():
			break
		var progress := float(i) / count
		var cutoff := lerpf(0.35, 0.08, progress)   # 점점 낮은 소리로
		smooth += (rng.randf_range(-1.0, 1.0) - smooth) * cutoff
		var envelope := sin(PI * progress) * (1.0 - progress * 0.4)
		buffer[index] += smooth * envelope * volume


func _save(buffer: PackedFloat32Array, relative: String) -> void:
	var peak := 0.0001
	for sample in buffer:
		peak = maxf(peak, absf(sample))
	var gain := minf(1.0, 0.9 / peak)
	var bytes := PackedByteArray()
	bytes.resize(buffer.size() * 2)
	for i in buffer.size():
		bytes.encode_s16(i * 2, int(clampf(buffer[i] * gain, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = bytes
	var path := ProjectSettings.globalize_path(OUT + relative + ".wav")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	stream.save_to_wav(path)


# --- 효과음 ------------------------------------------------------------------------

func _button() -> PackedFloat32Array:
	var buffer := _buffer(0.12)
	_note(buffer, 0.0, 0.1, 880.0, 0.6)
	_note(buffer, 0.0, 0.07, 1320.0, 0.25, "sine")
	return buffer


func _advance() -> PackedFloat32Array:
	var buffer := _buffer(0.08)
	_note(buffer, 0.0, 0.07, 700.0, 0.4, "sine", 0.004, 980.0)
	return buffer


func _card_out() -> PackedFloat32Array:
	var buffer := _buffer(0.24)
	_swish(buffer, 0.0, 0.22, 0.9)
	_note(buffer, 0.02, 0.14, 520.0, 0.08, "sine", 0.02, 380.0)
	return buffer


func _card_select() -> PackedFloat32Array:
	var buffer := _buffer(0.45)
	_note(buffer, 0.0, 0.3, 1046.5, 0.5)    # 도
	_note(buffer, 0.09, 0.35, 1318.5, 0.5)  # 미
	_note(buffer, 0.18, 0.27, 1568.0, 0.3)  # 솔
	return buffer


# --- 배경음: 잔잔한 4박자 아르페지오 (8마디 반복, 약 20초) ------------------------------------

func _village_theme() -> PackedFloat32Array:
	var beat := 60.0 / 96.0
	var bars := 8
	var buffer := _buffer(beat * 4.0 * bars)
	# 마디마다 화음 (근음 주파수, 화음 구성음)
	var chords := [
		[130.81, [261.63, 329.63, 392.00]],   # C
		[110.00, [220.00, 261.63, 329.63]],   # Am
		[87.31, [174.61, 220.00, 261.63]],    # F
		[98.00, [196.00, 246.94, 293.66]],    # G
		[130.81, [261.63, 329.63, 392.00]],   # C
		[110.00, [220.00, 261.63, 329.63]],   # Am
		[73.42, [146.83, 174.61, 220.00]],    # Dm
		[98.00, [196.00, 246.94, 293.66]],    # G
	]
	var pattern := [0, 1, 2, 1, 0, 1, 2, 1]   # 8분음표 아르페지오 순서
	# 위에서 흐르는 짧은 선율 (마디별 음, 0이면 쉼)
	var melody := [523.25, 0.0, 659.25, 0.0, 587.33, 0.0, 523.25, 493.88]
	for bar in bars:
		var start: float = bar * beat * 4.0
		var root: float = chords[bar][0]
		var tones: Array = chords[bar][1]
		_note(buffer, start, beat * 1.8, root, 0.35, "sine", 0.02)
		_note(buffer, start + beat * 2.0, beat * 1.8, root, 0.28, "sine", 0.02)
		for step in 8:
			var tone: float = tones[pattern[step]] * 2.0
			_note(buffer, start + step * beat * 0.5, beat * 0.9, tone, 0.13, "triangle", 0.01)
		if melody[bar] > 0.0:
			_note(buffer, start + beat, beat * 2.5, melody[bar], 0.12, "soft", 0.05)
	return buffer
