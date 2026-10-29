extends Node

## Audio follows the already privacy-filtered animation timeline, never raw engine logs.
## No background bed, identity-dependent variant, timer, or delayed replay on unmute.
signal preferences_changed
signal cue_started(action: String)

const SoundBank = preload("res://Scripts/presentation/DuelSoundBank.gd")
const DEFAULT_VOLUME := 0.60
const OUTPUT_GAIN := 0.40
@export var persist_preferences := true
@export var settings_path := "user://duel_audio.cfg"
## Optional rights-cleared replacement resources; keys: summon, attack, position, destroy.
## Empty entries use the original synthesized substitute. Never search/download recordings.
@export var cue_overrides: Dictionary[String, AudioStream] = {}
var enabled := true
var volume := DEFAULT_VOLUME
var last_save_error := OK
var _voice: AudioStreamPlayer
var _cues: Dictionary = {}

func _ready() -> void:
	if persist_preferences: load_preferences()
	_voice = AudioStreamPlayer.new()
	add_child(_voice)
	for action in SoundBank.DURATIONS:
		_cues[action] = cue_overrides[action] if cue_overrides.get(action) != null else SoundBank.synthesize(action)
	_apply_volume()

func play_cue(action: String, _visible_name: String = "") -> void:
	if not enabled or volume <= 0.0 or not _cues.has(action) or not is_instance_valid(_voice): return
	_voice.stream = _cues[action]
	_voice.play()
	cue_started.emit(action)

func stop() -> void:
	if not is_instance_valid(_voice): return
	_voice.stop()
	_voice.stream = null

func finish_cue(_action: String, _visible_name: String = "") -> void:
	# Replacement resources may be longer or loop; never outlive their public timeline.
	stop()

func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled: stop()
	_save_preferences()
	preferences_changed.emit()

func set_volume(value: float) -> void:
	volume = clampf(value, 0.0, 1.0) if is_finite(value) else DEFAULT_VOLUME
	_apply_volume()
	if volume <= 0.0: stop()
	_save_preferences()
	preferences_changed.emit()

func _apply_volume() -> void:
	if is_instance_valid(_voice): _voice.volume_db = linear_to_db(maxf(0.00001, volume * OUTPUT_GAIN))

func load_preferences() -> void:
	var config := ConfigFile.new()
	if config.load(settings_path) != OK: return
	var stored_enabled: Variant = config.get_value("effects", "enabled", true)
	var stored_volume: Variant = config.get_value("effects", "volume", DEFAULT_VOLUME)
	enabled = stored_enabled if stored_enabled is bool else true
	volume = DEFAULT_VOLUME
	if (stored_volume is float or stored_volume is int) and is_finite(float(stored_volume)):
		volume = clampf(float(stored_volume), 0.0, 1.0)
	_apply_volume()
	if not enabled or volume <= 0.0: stop()

func _save_preferences() -> void:
	if not persist_preferences: return
	var config := ConfigFile.new()
	config.set_value("effects", "enabled", enabled)
	config.set_value("effects", "volume", volume)
	last_save_error = config.save(settings_path)
	if last_save_error != OK: push_warning("Sound preferences could not be saved (error %d)." % last_save_error)

func _exit_tree() -> void:
	stop()
	_cues.clear()
