extends SceneTree

## Separate optional runner. The normal regression suite needs no native compiler.
func _initialize() -> void:
	var t := TestCase.new("OcgCoreDiagnostic")
	t.start("native lifecycle and deterministic transcript")
	var first := OcgCoreDiagnostic.run(42)
	if not t.check(first.get("ok", false), "native diagnostic succeeds: %s" % first):
		print(t.report())
		print("RESULT: FAIL")
		quit(1)
		return
	var second := OcgCoreDiagnostic.run(42)
	t.check(second.get("ok", false), "repeat native diagnostic succeeds")
	t.eq(first, second, "same seed produces identical native checkpoints and transcript")
	var other := OcgCoreDiagnostic.run(43)
	t.check(other.get("ok", false), "different seed diagnostic succeeds")
	if other.get("ok", false):
		t.ne(first.report.transcript_fnv1a64, other.report.transcript_fnv1a64, "core RNG changes the shuffled transcript")
	var minimum := OcgCoreDiagnostic.run(0)
	var maximum := OcgCoreDiagnostic.run(4294967295)
	t.check(minimum.get("ok", false), "minimum uint32 seed is accepted")
	t.check(maximum.get("ok", false), "maximum uint32 seed is accepted")
	t.start("invalid reports fail closed")
	var revision: String = first.report.core_revision
	var report: Dictionary = first.report
	t.check(not OcgCoreDiagnostic.run(-1).ok, "negative seed rejected")
	t.check(not OcgCoreDiagnostic.run(4294967296).ok, "overflow seed rejected")
	t.check(not OcgCoreDiagnostic.validate_report("not json", 0, revision, 42).ok, "malformed JSON rejected")
	t.check(not OcgCoreDiagnostic.validate_report("[]", 0, revision, 42).ok, "array report rejected")
	t.check(not OcgCoreDiagnostic.validate_report(JSON.stringify(report), 1, revision, 42).ok, "nonzero exit cannot claim pass")
	t.check(not OcgCoreDiagnostic.validate_report(JSON.stringify(report), 0, "wrong", 42).ok, "wrong core revision rejected")
	t.check(not OcgCoreDiagnostic.validate_report(JSON.stringify(report), 0, revision, 7).ok, "wrong seed rejected")
	var changed: Dictionary = report.duplicate(true)
	changed.after_summon_options = 1
	t.check(not OcgCoreDiagnostic.validate_report(JSON.stringify(changed), 0, revision, 42).ok, "incorrect summon allowance rejected")
	changed = report.duplicate(true)
	changed.message_count = "1"
	t.check(not OcgCoreDiagnostic.validate_report(JSON.stringify(changed), 0, revision, 42).ok, "invalid message count type rejected")
	changed = report.duplicate(true)
	changed.transcript_fnv1a64 = "not-a-valid-hash!"
	t.check(not OcgCoreDiagnostic.validate_report(JSON.stringify(changed), 0, revision, 42).ok, "invalid transcript digest rejected")
	for invalid_counts in [[5], [5, 5, 5], [5, "5"], [5, true], [5, 5.5], "5,5"]:
		changed = report.duplicate(true)
		changed.opening_hand_counts = invalid_counts
		t.check(not OcgCoreDiagnostic.validate_report(JSON.stringify(changed), 0, revision, 42).ok, "invalid count shape/type rejected")
	changed = report.duplicate(true)
	changed.fixture_only = false
	t.check(not OcgCoreDiagnostic.validate_report(JSON.stringify(changed), 0, revision, 42).ok, "non-fixture report rejected")
	changed = report.duplicate(true)
	changed.schema_version = 2
	t.check(not OcgCoreDiagnostic.validate_report(JSON.stringify(changed), 0, revision, 42).ok, "unknown schema rejected")
	t.check(not OcgCoreDiagnostic.validate_report(" ".repeat(16385), 0, revision, 42).ok, "oversized report rejected")
	print(t.report())
	print("TOTAL: %d passed, %d failed" % [t.passed, t.failed])
	print("RESULT: %s" % ("PASS" if t.failed == 0 else "FAIL"))
	quit(0 if t.failed == 0 else 1)
