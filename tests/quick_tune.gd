extends SceneTree

# The in-car quick tune (Tuner UI overhaul PR 5), on the real Game.tscn:
# - Tab opens it while driving and the game keeps running (not paused)
# - Tab again steps through its four settings; ] and [ move the focused one
# - Brake bias leaves Auto at the split Auto gave, then moves a notch
# - the Grip to Drift dial here is the Tuner's own (one shared model)
# - it closes after the idle time, and when the game pauses
# - its keys are on the pause menu's Controls page and drive nothing
# Optional: NEON_SHOT=<png> (real renderer) saves the quick tune over the drive.
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 60 --path . -s res://tests/quick_tune.gd

var failures: Array[String] = []

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	change_scene_to_file("res://Game.tscn")
	_run()

func _press(action: String) -> void:
	Input.action_press(action)
	await physics_frame
	await physics_frame
	Input.action_release(action)
	await physics_frame

func _run() -> void:
	var t0 := Time.get_ticks_msec()
	while (current_scene == null or current_scene.get("game_state") == null) and Time.get_ticks_msec() - t0 < 15000:
		await process_frame
	var game := current_scene
	var qt: QuickTune = null
	var screen: TunerScreen = null
	for c in game.get_children():
		if c is QuickTune:
			qt = c
		if c is TunerScreen:
			screen = c
	if qt == null:
		return _end("no QuickTune in the game")
	for i in 30:
		await physics_frame
	_check(qt.model == screen.model, "the quick tune should share the Tuner's model")
	var spec: Dictionary = game.player.spec

	await _press("quick_tune")
	_check(qt.is_open and qt.plate.visible, "Tab should open the quick tune")
	_check(not paused and game.game_state.state == GameState.State.PLAYING, "the game should keep running")
	_check(qt.index == 0, "it opens on the Grip to Drift dial")
	var shot := OS.get_environment("NEON_SHOT")
	if shot != "":
		root.size = Vector2i(1280, 720)
		Input.action_press("accelerate")  # driving, so the shot shows it over a moving car
		for i in 90:
			await physics_frame
		Input.action_release("accelerate")
		qt.open()
		await process_frame
		await process_frame
		root.get_texture().get_image().save_png(shot)
		print("screenshot: ", shot)
	await _press("quick_tune_up")
	_check(qt.model.character == TunerModel.CHARACTER_STOCK + 1, "] should move the dial one notch toward Drift: %d" % qt.model.character)
	_check(qt.rows[0].value.text == "Drift 1", "the row reads Drift 1: %s" % qt.rows[0].value.text)
	await _press("quick_tune_down")
	_check(qt.model.character == TunerModel.CHARACTER_STOCK, "[ should bring it back to stock")

	await _press("quick_tune")
	_check(qt.index == 1, "Tab again should step to Brake bias")
	var before_bias: float = game.player.front_axle.brake_bias
	await _press("quick_tune_up")
	_check(float(spec.front_brake_bias) >= 0.0, "Brake bias should leave Auto")
	_check(float(spec.front_brake_bias) > before_bias - 0.04, "and start from the split Auto gave (%.2f), then move: %.2f" % [before_bias, float(spec.front_brake_bias)])

	await _press("quick_tune")
	var tc: Dictionary = qt.setting(2)
	var tc_before := qt.model.choice_index(tc)
	await _press("quick_tune_down")
	_check(qt.model.choice_index(tc) == tc_before - 1, "[ on Traction should step it down one")

	# the idle timer closes it
	qt.idle_close_s = 0.3
	var t1 := Time.get_ticks_msec()
	while qt.is_open and Time.get_ticks_msec() - t1 < 3000:
		await process_frame
	_check(not qt.is_open, "it should close by itself when left alone")
	qt.idle_close_s = QuickTune.IDLE_CLOSE_S

	# a pause closes it
	await _press("quick_tune")
	game.game_state.pause()
	await process_frame
	_check(not qt.is_open, "pausing should close it")
	game.game_state.resume()

	# Controls page lists it; its keys are not driving keys
	for a in ["quick_tune", "quick_tune_down", "quick_tune_up"]:
		_check(InputMap.has_action(a), "action %s should exist" % a)
		for ev in InputMap.action_get_events(a):
			for drive in ["accelerate", "brake", "handbrake", "steer_left", "steer_right", "shift_up", "shift_down", "pause", "tuning_panel"]:
				_check(not InputMap.action_has_event(drive, ev), "%s's key is also %s" % [a, drive])
	var src := FileAccess.get_file_as_string("res://scripts/pause_menu.gd")
	_check(src.contains("\"quick_tune\"") and src.contains("Quick tune"), "the Controls page should list the quick tune")
	_end("")

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
		print("FAIL ", msg)

func _end(msg: String) -> void:
	if msg != "":
		failures.append(msg)
	print("quick_tune: %s" % ("PASS" if failures.is_empty() else "FAIL (%d)" % failures.size()))
	quit(0 if failures.is_empty() else 1)
