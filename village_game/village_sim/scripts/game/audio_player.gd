extends Node
## 배경음과 효과음 재생. 메인 씬에 하나만 둔다.
##
## 어디서든 이렇게 부른다 (이 노드를 직접 알 필요 없음):
##   get_tree().call_group(AudioPlayer.GROUP, "play_sfx", "card_out")
##   get_tree().call_group(AudioPlayer.GROUP, "play_bgm", "game")
##
## 어떤 상황에 어떤 소리 파일을 쓸지, 소리 크기는 data/audio/audio.json 에서 정한다.
## 소리 파일은 assets/audio/sfx/<이름>, assets/audio/bgm/<이름> (ogg / wav / mp3). 없으면 임시 소리, 그것도 없으면 조용히 넘어간다.

const AssetLibrary = preload("res://village_sim/scripts/game/asset_library.gd")

const GROUP := "village_audio"
const SFX_VOICES := 4          # 동시에 겹쳐 날 수 있는 효과음 수
const BGM_FADE_SECONDS := 0.8

var _config: Dictionary = {}
var _bgm: AudioStreamPlayer
var _bgm_id := ""
var _sfx: Array = []
var _next_sfx := 0
var _cache: Dictionary = {}


func _ready() -> void:
	add_to_group(GROUP)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bgm = AudioStreamPlayer.new()
	add_child(_bgm)
	for i in SFX_VOICES:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_sfx.append(player)


## config: data/audio/audio.json 내용
func setup(config: Dictionary) -> void:
	_config = config
	var volumes: Dictionary = config.get("volume_db", {})
	_bgm.volume_db = float(volumes.get("bgm", -14))
	for player in _sfx:
		player.volume_db = float(volumes.get("sfx", -6))


## 상황 이름(audio.json의 sfx 키)에 맞는 효과음을 한 번 낸다.
func play_sfx(action: String) -> void:
	var sound_id := String(_config.get("sfx", {}).get(action, action))
	var stream := _load("sfx/" + sound_id)
	if stream == null:
		return
	var player: AudioStreamPlayer = _sfx[_next_sfx]
	_next_sfx = (_next_sfx + 1) % _sfx.size()
	player.stream = stream
	player.pitch_scale = randf_range(0.97, 1.03)   # 같은 소리가 반복돼도 덜 단조롭게
	player.play()


## 상황 이름(audio.json의 bgm 키)에 맞는 배경음을 반복해서 튼다. 이미 같은 곡이면 그대로 둔다.
func play_bgm(scene: String) -> void:
	var sound_id := String(_config.get("bgm", {}).get(scene, ""))
	if sound_id.is_empty() or sound_id == _bgm_id:
		return
	var stream := _load("bgm/" + sound_id)
	if stream == null:
		return
	_bgm_id = sound_id
	_make_looping(stream)
	var target := _bgm.volume_db
	_bgm.stream = stream
	_bgm.volume_db = -40.0
	_bgm.play()
	create_tween().tween_property(_bgm, "volume_db", target, BGM_FADE_SECONDS)


func _load(relative: String) -> AudioStream:
	if not _cache.has(relative):
		_cache[relative] = AssetLibrary.audio(relative)
	return _cache[relative]


## 배경음은 끝나면 처음부터 다시. (ogg / mp3 는 loop, wav 는 loop_mode)
func _make_looping(stream: AudioStream) -> void:
	if stream is AudioStreamWAV:
		var wav: AudioStreamWAV = stream
		# 압축되지 않은 wav만 여기서 반복 구간을 계산한다. (압축된 wav는 가져오기 설정의 Loop Mode를 Forward로)
		var uncompressed := wav.format == AudioStreamWAV.FORMAT_16_BITS or wav.format == AudioStreamWAV.FORMAT_8_BITS
		if wav.loop_mode == AudioStreamWAV.LOOP_DISABLED and uncompressed:
			var bytes_per_sample := (2 if wav.format == AudioStreamWAV.FORMAT_16_BITS else 1) * (2 if wav.stereo else 1)
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = wav.data.size() / bytes_per_sample
	elif "loop" in stream:
		stream.set("loop", true)
