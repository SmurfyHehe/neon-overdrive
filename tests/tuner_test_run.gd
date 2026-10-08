extends SceneTree

# Tuner Mechanic and Test run (Tuner redesign PR 4, 2026-10-06), on the real
# Game.tscn, headless:
# - Test run on the stat panel drives the current setup round the hidden test
#   track in a worker process and the panel then shows measured numbers (no "~")
#   that match the headless track's numbers for the stock coupe
# - the run also records the brake run's trace (speed, throttle, brake samples)
#   for this setup and for stock, and the stat panel flips to the pit-wall result:
#   speed trace and a signed delta column (stock against stock reads level)
# - pressing Test run again cancels it, and a run past the timeout is killed
# - changing any setting afterwards puts the estimates back
# - a second Test run, on a changed setup, reuses the stock run and shows a delta
# Optional: NEON_SHOT=<png path> saves a screenshot of the pit-wall result.
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

	# pressing the button again cancels (settings safety, 2026-10-07)
	screen.start_test_run()
	_check(screen.test_running(), "Test run did not start")
	screen.start_test_run()
	_check(not screen.test_running() and screen.test_button.text == "Test run cancelled", "a second press should cancel: %s" % screen.test_button.text)
	# a hung worker is killed after the timeout
	screen.test_timeout_s = 0.2
	screen.start_test_run()
	t0 = Time.get_ticks_msec()
	while screen.test_running() and Time.get_ticks_msec() - t0 < 5000:
		await process_frame
	_check(not screen.test_running() and screen.test_button.text == "Test run timed out", "the timeout did not stop the run: %s" % screen.test_button.text)
	screen.test_timeout_s = TIMEOUT_S

	screen.start_test_run()
	_check(screen.test_running(), "Test run should be running")
	t0 = Time.get_ticks_msec()
	while screen.test_running() and Time.get_ticks_msec() - t0 < TIMEOUT_S * 1000.0:
		await process_frame
	_check(not screen.test_running() and screen.test_button.text == "Test run", "test run did not finish: %s" % screen.test_button.text)
	var top_text: String = screen.stats.labels.top.text
	print("after the test run: ", top_text)
	_check(not top_text.contains("~") and top_text.contains(str(roundi(EXPECT_TOP))), "top speed should read the measured %d km/h: %s" % [roundi(EXPECT_TOP), top_text])

	var tr: Dictionary = screen.stats.measured.get("trace", {})
	var n: int = tr.get("speed", []).size()
	print("trace: %d samples, peak %.1f km/h, stock %d samples" % [n, tr.speed.max() if n > 0 else 0.0, screen.stock_run.get("trace", {}).get("speed", []).size()])
	_check(n > 20 and tr.throttle.size() == n and tr.brake.size() == n, "the test run should record speed/throttle/brake samples: %d" % n)
	_check(n > 0 and tr.speed.max() >= 99.0 and tr.throttle.max() == 1.0 and tr.brake.max() == 1.0, "the trace should reach 100 km/h on throttle and then brake")
	_check(screen.stock_run.has("trace"), "the first test run should also measure stock")
	_check(screen.pit_wall.visible and not screen.stats.visible, "the stat panel should flip to the pit-wall result")
	_check(screen.pit_wall.trace.mine.size() > 0 and screen.pit_wall.trace.stock.size() > 0, "the speed trace should have both runs")
	var d0: String = screen.pit_wall.deltas.t_0_100.text
	print("stock vs stock 0-100 delta: '%s'" % d0)
	_check(not d0.contains("▲") and not d0.contains("▼"), "stock against stock should read level: %s" % d0)

	screen.model.nudge(TunerModel.page("tyres").settings[1], 1)
	screen._refresh()
	_check(screen.stats.labels.top.text.contains("~"), "a change should put the estimates back: %s" % screen.stats.labels.top.text)
	_check(screen.stats.visible and not screen.pit_wall.visible, "a change should flip back to the estimates")

	# A second run on the changed setup: stock is not driven again.
	var stock_before: Dictionary = screen.stock_run
	screen.start_test_run()
	t0 = Time.get_ticks_msec()
	while screen.test_button.disabled and Time.get_ticks_msec() - t0 < TIMEOUT_S * 1000.0:
		await process_frame
	_check(screen.stock_run == stock_before, "the second test run should reuse the stock run")
	_check(screen.pit_wall.visible, "the second test run should show the pit-wall result")
	for k in screen.pit_wall.deltas:
		print("  %s   %s" % [screen.pit_wall.values[k].text, screen.pit_wall.deltas[k].text])
	var shot := OS.get_environment("NEON_SHOT")
	if shot != "":
		for i in 5:
			await process_frame
		root.get_viewport().get_texture().get_image().save_png(shot)
		print("screenshot: ", shot)

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
