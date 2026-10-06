extends SceneTree

# Tuner Mechanic and Test run (Tuner redesign PR 4, 2026-10-06), on the real
# Game.tscn, headless:
# - Test run on the stat panel drives the current setup round the hidden test
#   track in a worker process and the panel then shows measured numbers (no "~")
#   that match the headless track's numbers for the stock coupe
# - changing any setting afterwards puts the estimates back
# - the Mechanic's plain-words result: change_words() reads a final drive rise as
#   shorter gearing, and a result with nothing found says so
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 60 --path . -s res://tests/tuner_test_run.gd

const EXPECT_TOP := 244.1  # tests/tune_track.gd at 60 Hz
const TIMEOUT_S := 120.0

var failures: Array[String] = []

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	change_scene_to_file("res://Game.tscn")
	_run()

func _run() -> void:
	var t0 := Time.get_ticks_msec()
	while (current_scene == null or current_scene.get("game_state") == null) and Time.get_ticks_msec() - t0 < 15000:
		await process_frame
	var game := current_scene
	var screen: TunerScreen = null
	for c in game.get_children():
		if c is TunerScreen:
			screen = c
	if screen == null:
		return _end("no TunerScreen")
	game.game_state.toggle_tuning()
	await process_frame
	_check(screen.stats.labels.top.text.contains("~"), "before a test run the top speed should be an estimate: %s" % screen.stats.labels.top.text)

	screen.start_test_run()
	_check(screen.test_button.disabled, "Test run should disable its button while it runs")
	t0 = Time.get_ticks_msec()
	while screen.test_button.disabled and Time.get_ticks_msec() - t0 < TIMEOUT_S * 1000.0:
		await process_frame
	_check(not screen.test_button.disabled and screen.test_button.text == "Test run", "test run did not finish: %s" % screen.test_button.text)
	var top_text: String = screen.stats.labels.top.text
	print("after the test run: ", top_text)
	_check(not top_text.contains("~") and top_text.contains(str(roundi(EXPECT_TOP))), "top speed should read the measured %d km/h: %s" % [roundi(EXPECT_TOP), top_text])

	screen.model.nudge(TunerModel.page("tyres").settings[1], 1)
	screen._refresh()
	_check(screen.stats.labels.top.text.contains("~"), "a change should put the estimates back: %s" % screen.stats.labels.top.text)

	_check(AutoTunePanel.change_words("final_drive", 4.1, 4.45).begins_with("Shorter gearing"), "final drive up should read as shorter gearing")
	_check(AutoTunePanel.change_words("aero_downforce_coefficient_rear", 0.5, 0.8).begins_with("More rear wing"), "rear downforce up should read as more rear wing")
	_check(screen.auto.plain_result_text({"improved": false, "notes": []}).contains("nothing better"), "an empty result should say nothing better was found")
	game.game_state.toggle_tuning()
	_end("")

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
		print("FAIL ", msg)

func _end(msg: String) -> void:
	if msg != "":
		failures.append(msg)
	print("tuner_test_run: %s" % ("PASS" if failures.is_empty() else "FAIL (%d)" % failures.size()))
	quit(0 if failures.is_empty() else 1)
