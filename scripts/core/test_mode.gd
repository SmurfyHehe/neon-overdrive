extends RefCounted

# Test mode: true when a script under res://tests/ is the thing running
# (`godot -s res://tests/foo.gd`, which is how tests/run_tests.bat starts every
# test), or when NEON_TEST=1 is set. In test mode the game's own save files
# move to test_* names, so a test that boots Game.tscn can never write over
# Roy's real tune, slots, settings or auto-tune job files in the user folder
# (user://exhaust_tune.json was overwritten with every knob at 0.7 by a test
# run on 2026-10-06, and that folder is shared with the exported game).
# Tests that want a specific file still set the path themselves.
# Used by ExhaustTune, AudioSettings, TuneSlots and AutoTuneJob.
# No class_name on purpose: preload it, so no class cache refresh is needed.

static func active() -> bool:
	if OS.get_environment("NEON_TEST") == "1":
		return true
	for a in OS.get_cmdline_args():
		if a.begins_with("res://tests/"):
			return true
	return false

## "user://tune_slots.json" -> "user://test_tune_slots.json" in test mode.
static func path(real: String) -> String:
	if not active():
		return real
	return real.get_base_dir().path_join("test_" + real.get_file())
