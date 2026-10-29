class_name OcgCoreDiagnostic
extends RefCounted

## Opt-in, synchronous development diagnostic backed by the real native OCG core.
## NOT a DuelSession implementation and NEVER selected by the playable board.
## Call from a headless runner or worker thread: the subprocess may take up to 10s.
## Only synthetic Normal Monster fixtures are supported; no card scripts/assets load.

const BINARY_PATH := "res://Tools/ocg/bin/ocg_probe"
const LOCK_PATH := "res://ThirdParty/ocg/lock.json"


static func is_available() -> bool:
	return OS.get_name() == "Linux" and FileAccess.file_exists(BINARY_PATH)


static func run(seed: int = 42) -> Dictionary:
	if seed < 0 or seed > 4294967295:
		return _failure("Seed must be in the uint32 range (0..4294967295).")
	if not is_available():
		return _failure("Optional Linux diagnostic is not built. Run python3 Tools/build_ocg_probe.py --fetch.")
	var lock_data: Variant = JSON.parse_string(FileAccess.get_file_as_string(LOCK_PATH))
	if not lock_data is Dictionary or not lock_data.get("core", {}) is Dictionary:
		return _failure("Cannot read the pinned core manifest.")
	var expected_revision := str(lock_data.get("core", {}).get("revision", ""))
	if expected_revision.length() != 40:
		return _failure("Invalid pinned core revision.")
	var output: Array = []
	# Pass an argv array, never a shell string; only a bounded numeric input crosses.
	var exit_code := OS.execute(ProjectSettings.globalize_path(BINARY_PATH),
		PackedStringArray(["--seed", str(seed)]), output, true)
	var stdout := "".join(output)
	return validate_report(stdout, exit_code, expected_revision, seed)


static func validate_report(stdout: String, exit_code: int, expected_revision: String, seed: int) -> Dictionary:
	if exit_code != 0:
		return _failure("Native diagnostic failed (exit %d): %s" % [exit_code, stdout.left(512)])
	if stdout.length() > 16384:
		return _failure("Native report exceeds size limit.")
	var parser := JSON.new()
	if parser.parse(stdout) != OK:
		return _failure("Native diagnostic returned invalid JSON.")
	var parsed: Variant = parser.data
	if not parsed is Dictionary:
		return _failure("Native diagnostic returned invalid JSON.")
	var report: Dictionary = parsed
	if report.get("schema_version") != 1 or report.get("status") != "ok":
		return _failure("Native report schema/status mismatch.")
	if report.get("backend") != "fluorohydride-diagnostic" or report.get("core_revision") != expected_revision:
		return _failure("Native executable does not match the pinned Fluorohydride core.")
	if report.get("scenario") != "normal-summon-turn" or report.get("fixture_only") != true or report.get("seed") != seed:
		return _failure("Native diagnostic scenario/seed mismatch.")
	var expected := {
		"opening_hand_counts": [5, 5], "opening_summon_options": 5,
		"after_summon_hand_counts": [4, 5], "after_summon_field_counts": [1, 0],
		"after_summon_options": 0, "second_turn_player": 1,
		"second_turn_hand_counts": [4, 6], "second_turn_deck_counts": [35, 34],
		"invalid_response_rejected": true, "summons": 1, "turns": 2,
	}
	for key in expected:
		if not _matches_checkpoint(report.get(key), expected[key]):
			return _failure("Native checkpoint mismatch: %s" % key)
	var digest := str(report.get("transcript_fnv1a64", ""))
	if digest.length() != 16 or not digest.is_valid_hex_number(false):
		return _failure("Native transcript digest is invalid.")
	var count: Variant = report.get("message_count")
	if (not count is int and not count is float) or count < 1 or count > 4096 or count != floor(count):
		return _failure("Native message count is invalid.")
	return {"ok": true, "report": report}


static func _matches_checkpoint(actual: Variant, expected: Variant) -> bool:
	# JSON numbers are floats in Godot; nested Array equality does not coerce
	# them like scalar numeric equality. Keep strict shape/types without casts
	# that would accidentally accept "5", 5.5, or a boolean as a count.
	if expected is Array:
		if not actual is Array or actual.size() != expected.size():
			return false
		for index in expected.size():
			if not _matches_checkpoint(actual[index], expected[index]):
				return false
		return true
	if expected is int:
		return (actual is int or actual is float) and actual == expected
	return typeof(actual) == typeof(expected) and actual == expected


static func _failure(message: String) -> Dictionary:
	# Fail explicitly, never silently substitute the existing engine or fake success.
	return {"ok": false, "error": message}
