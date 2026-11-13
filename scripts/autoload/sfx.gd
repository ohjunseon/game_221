extends Node
## 효과음. 오디오 파일 없이 실행 시점에 짧은 음을 합성한다.

const RATE := 22050
const VOICES := 8

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next: int = 0


func _ready() -> void:
	_streams = {
		"pick": _tone([880.0], 0.06),
		"place": _tone([523.0, 784.0], 0.06),
		"error": _tone([160.0], 0.15),
		"buy": _tone([660.0, 990.0], 0.07),
		"complete": _tone([523.0, 659.0, 784.0, 1047.0], 0.1),
		"unlock": _tone([392.0, 523.0, 659.0, 784.0, 1047.0, 1319.0], 0.12),
		"door": _tone([220.0, 180.0], 0.12),
		"rumble": _noise(2.0),
	}
	for i in VOICES:
		var player := AudioStreamPlayer.new()
		player.volume_db = -8.0
		add_child(player)
		_players.append(player)


func play(sound: String, pitch: float = 1.0) -> void:
	if not _streams.has(sound):
		return
	var player := _players[_next]
	_next = (_next + 1) % VOICES
	player.stream = _streams[sound]
	player.pitch_scale = pitch
	player.play()


func _tone(freqs: Array, note_seconds: float) -> AudioStreamWAV:
	var note_samples := int(RATE * note_seconds)
	var data := PackedByteArray()
	data.resize(note_samples * freqs.size() * 2)
	var index := 0
	for freq: float in freqs:
		for i in note_samples:
			var envelope := 1.0 - float(i) / note_samples
			var sample := sin(TAU * freq * i / RATE) * envelope * 0.35
			data.encode_s16(index * 2, int(sample * 32767.0))
			index += 1
	return _make_stream(data)


func _noise(seconds: float) -> AudioStreamWAV:
	var samples := int(RATE * seconds)
	var data := PackedByteArray()
	data.resize(samples * 2)
	var value := 0.0
	for i in samples:
		var envelope := 1.0 - float(i) / samples
		value = lerpf(value, randf_range(-1.0, 1.0), 0.08)
		data.encode_s16(i * 2, int(value * envelope * 0.9 * 32767.0))
	return _make_stream(data)


func _make_stream(data: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	return stream
