extends Node

## Small original synthesized palette: no recordings, samples or copyrighted music.
## Demo-only, independently muteable; audio never touches engine timing/state.
var enabled := true
var _ambience: AudioStreamPlayer
var _voice: AudioStreamPlayer
var _cues: Dictionary = {}
const RATE := 22050

func _ready() -> void:
	_ambience = AudioStreamPlayer.new()
	_ambience.volume_db = -26
	add_child(_ambience)
	_voice = AudioStreamPlayer.new()
	_voice.volume_db = -15
	add_child(_voice)
	for cue in ["summon", "attack", "position", "destroy"]: _cues[cue] = _synthesize(cue)
	var air := _synthesize("ambience")
	air.loop_mode = AudioStreamWAV.LOOP_FORWARD
	air.loop_end = air.data.size() / 2
	_ambience.stream = air
	if enabled: _ambience.play()

func set_enabled(value: bool) -> void:
	enabled = value
	if not is_instance_valid(_ambience): return
	if enabled: _ambience.play()
	else:
		_ambience.stop()
		_voice.stop()

func play_cue(action: String, _visible_name: String = "") -> void:
	if not enabled or not _cues.has(action): return
	_voice.stream = _cues[action]
	_voice.play()

func _synthesize(kind: String) -> AudioStreamWAV:
	var duration: float = {"ambience": 9.0, "summon": 2.2, "attack": 1.0, "position": 1.05, "destroy": 1.8}[kind]
	var samples := int(duration * RATE)
	var bytes := PackedByteArray()
	bytes.resize(samples * 2)
	var random := RandomNumberGenerator.new()
	random.seed = 41773
	var low_noise := 0.0
	for i in range(samples):
		var t := float(i) / RATE
		var p := t / duration
		var n := random.randf_range(-1, 1)
		low_noise = lerpf(low_noise, n, 0.035)
		var sample := 0.0
		match kind:
			"ambience":
				var envelope := pow(sin(p * PI), 0.25)
				sample = envelope * (sin(TAU * 49.0 * t) * 0.26 + sin(TAU * 73.42 * t) * 0.12 + sin(TAU * 147.08 * t) * 0.035 + low_noise * 0.4)
			"summon":
				var envelope := sin(p * PI)
				sample = envelope * (sin(TAU * (70.0 * t - 8.0 * t * t)) * 0.32 + low_noise * 1.5 + sin(TAU * 585.0 * t) * 0.035)
			"attack":
				var envelope := exp(-pow((p - 0.38) * 7.5, 2.0))
				sample = envelope * (n * 0.46 + sin(TAU * (550.0 * t - 240.0 * t * t)) * 0.12) + sin(TAU * 52.0 * t) * exp(-pow((p - 0.53) * 10.0, 2.0)) * 0.28
			"position":
				var envelope := sin(p * PI)
				sample = envelope * (low_noise * 0.7 + sin(TAU * (84.0 * t + sin(t * 12.0) * 0.12)) * 0.16)
			"destroy":
				var cracks := exp(-pow((p - 0.12) * 48.0, 2.0)) + exp(-pow((p - 0.29) * 34.0, 2.0)) * 0.65
				var dust := smoothstep(0.20, 0.36, p) * pow(1.0 - p, 1.7)
				sample = n * (cracks * 0.5 + dust * 0.3) + low_noise * dust * 1.5 + sin(TAU * 41.0 * t) * dust * 0.3
		# Smooth endpoints avoid clicks, even if a user advances or replays a fixture.
		sample *= smoothstep(0.0, 0.012, t) * smoothstep(0.0, 0.04, duration - t)
		bytes.encode_s16(i * 2, int(clampf(sample, -0.95, 0.95) * 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = bytes
	return stream

func _exit_tree() -> void:
	# Release mixer-held playback resources before the scene is replaced or quit.
	if is_instance_valid(_ambience):
		_ambience.stop()
		_ambience.stream = null
	if is_instance_valid(_voice):
		_voice.stop()
		_voice.stream = null
	_cues.clear()
