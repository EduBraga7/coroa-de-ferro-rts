extends Node
class_name SFXManager

## Sintetizador procedural de efeitos sonoros via AudioStreamGenerator.
## Evita dependência de arquivos de áudio externos e funciona em tempo real.

const MIX_RATE: float = 22050.0
const POOL_SIZE: int = 8

var _players: Array[AudioStreamPlayer] = []
var _next_idx: int = 0
var _muted: bool = false


func _ready() -> void:
	for i in range(POOL_SIZE):
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.volume_db = -10.0
		var gen: AudioStreamGenerator = AudioStreamGenerator.new()
		gen.mix_rate = MIX_RATE
		gen.buffer_length = 0.5
		p.stream = gen
		add_child(p)
		_players.append(p)


func set_muted(val: bool) -> void:
	_muted = val


func _play_tone(freq_start: float, freq_end: float, duration: float, volume: float = 0.25, wave_type: String = "sine", noise_mix: float = 0.0) -> void:
	if _muted or DisplayServer.get_name() == "headless":
		return
	var player: AudioStreamPlayer = _players[_next_idx]
	_next_idx = (_next_idx + 1) % POOL_SIZE

	if not player.playing:
		player.play()
	var pb: AudioStreamGeneratorPlayback = player.get_stream_playback() as AudioStreamGeneratorPlayback
	if pb == null:
		return

	var frames_needed: int = mini(int(duration * MIX_RATE), pb.get_frames_available())
	if frames_needed <= 0:
		return

	var phase: float = 0.0
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()

	for i in range(frames_needed):
		var t: float = float(i) / float(frames_needed)
		var freq: float = lerpf(freq_start, freq_end, t)
		var env: float = (1.0 - t) * (1.0 - t)
		if t < 0.05:
			env *= t / 0.05

		phase += freq / MIX_RATE
		var s: float = 0.0
		if wave_type == "square":
			s = 1.0 if fmod(phase, 1.0) < 0.5 else -1.0
		elif wave_type == "saw":
			s = 2.0 * fmod(phase, 1.0) - 1.0
		else:
			s = sin(phase * TAU)

		if noise_mix > 0.0:
			var n: float = rng.randf_range(-1.0, 1.0)
			s = lerpf(s, n, noise_mix)

		var sample: float = clampf(s * env * volume, -0.95, 0.95)
		pb.push_frame(Vector2(sample, sample))


func play_select() -> void:
	_play_tone(620.0, 840.0, 0.06, 0.16, "sine")


func play_command() -> void:
	_play_tone(340.0, 520.0, 0.09, 0.18, "sine")


func play_hit_melee() -> void:
	_play_tone(260.0, 95.0, 0.11, 0.24, "saw", 0.45)


func play_shoot_arrow() -> void:
	_play_tone(920.0, 320.0, 0.10, 0.16, "sine", 0.35)


func play_harvest() -> void:
	_play_tone(190.0, 110.0, 0.08, 0.16, "square", 0.3)


func play_build_complete() -> void:
	_play_tone(440.0, 660.0, 0.22, 0.22, "sine")


func play_horn_alert() -> void:
	_play_tone(185.0, 220.0, 0.42, 0.26, "saw", 0.08)
