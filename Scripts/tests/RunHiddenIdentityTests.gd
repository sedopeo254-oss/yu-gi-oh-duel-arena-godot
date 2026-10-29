extends SceneTree

func _finalize() -> void:
	TestFixtures.release_real_library()


## Focused regression runner for the player-channel hidden-identity boundary.
func _initialize() -> void:
	var suite := HiddenIdentityTests.run()
	print(suite.report())
	print("TOTAL: %d passed, %d failed" % [suite.passed, suite.failed])
	var passed := suite.failed == 0 and suite.total() > 0
	print("RESULT: %s" % ("PASS" if passed else "FAIL"))
	quit(0 if passed else 1)
