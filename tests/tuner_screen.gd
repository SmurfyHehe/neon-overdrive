extends SceneTree

# One Tuner screen test: runs the real Game.tscn and checks that
# - T opens the screen on the Setup page (Tuner redesign PR 3) with no key hints;
#   E/Q change page, Down/Right move a notch and write the car, presets apply
#   and Stock puts the car back; the raw gearing panel still works
# - the four exhaust sliders show the car's exhaust tune and write the player's
#   spec (spec.exhaust), and the live EngineSynth.tune follows at once even
#   though the game is paused
# - exhaust paths are in tune slots but never in TuneParams.auto_paths()
# - a tune slot keeps the exhaust tune; Load puts it back (spec, synth and
#   sliders) and Undo reverts the load
# - moving a gearing slider updates the Auto-Tune lock labels
# - closing with Esc saves the exhaust tune, and a car built afterwards starts
#   from the saved tune instead of the preset
#
# Everything is written to scratch files under user://autotune/. Paced in
# physics ticks. Exit code 1 on failure. Run (headless):
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/tuner_screen.gd

const HOLD_TICKS := 6
const EXHAUST_FILE := "user://autotune/test_tuner_screen_exhaust.json"
const SLOT_FILE := "user://autotune/test_tuner_screen_slots.json"

var failures: Array[String] = []

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")  # an empty road, whatever run_tests.bat or the saved settings say
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://autotune"))
	for path in [EXHAUST_FILE, SLOT_FILE]:
		var f := FileAccess.open(path, FileAccess.WRITE)  # start empty (overwrite; never deleted)
		f.store_string("")
		f = null
	ExhaustTune.save_path = EXHAUST_FILE
	change_scene_to_file("res://Game.tscn")
	_run()

func _run() -> void:
	if not await _until(func(): return _ready_game() != null, 15.0):
		return _end("Game.tscn never became ready")
	var game := _ready_game()
	var player: PlayerCar = game.player
	var screen: TunerScreen = _find(game, TunerScreen)
	_check(screen != null, "Game has no TunerScreen")
	if screen == null:
		return _end("")
	var audio: EngineAudio = null
	for c in player.get_children():
		if c is EngineAudio:
			audio = c
	_check(audio != null, "player has no EngineAudio")
	if audio == null:
		return _end("")
	var preset := ExhaustTune.for_car("p1_coupe")

	# --- registry: exhaust is stored with the car but Auto-Tune never sees it ---
	for p in TuneParams.auto_paths():
		_check(not p.begins_with("exhaust/"), "%s is an Auto-Tune path" % p)
	for p in TuneParams.exhaust_paths():
		_check(not TuneParams.find(p).is_empty() and not TuneParams.find(p).auto, "%s should be tunable but not Auto-Tune" % p)
		_check(AutoTuneJob.values_from_spec(player.spec).has(p), "%s missing from the values a tune slot stores" % p)
	_check(not AutoTuneJob._auto_values(player.spec).has("exhaust/loudness"), "Auto-Tune results must not carry exhaust")

	# --- T opens the screen ---
	await _tap(KEY_T)
	await _until(func(): return game.game_state.state == GameState.State.TUNING, 5.0)
	_check(screen.visible and paused, "T should open the Tuner screen and pause")
	_check(screen.current_page() == "setup" and screen.preset_buttons[0].has_focus(), "T should open on the Setup page with Stock focused")
	_check(not screen.auto.is_visible_in_tree(), "the Mechanic (Auto-Tune) page should not show after T")
	_check(is_equal_approx(screen.exhaust.sliders.loudness.value, preset.loudness) and is_equal_approx(screen.exhaust.sliders.flame.value, preset.flame), "exhaust sliders should start on the car's preset")
	_check(not screen.car_label.text.contains("T or Y") and not screen.hint.text.contains("Esc"), "no key hints on the screen")

	# --- keyboard navigation: E to Tyres, Down to front pressure, Right one notch ---
	await _tap(KEY_E)
	_check(screen.current_page() == "tyres", "E should go to the Tyres page, on %s" % screen.current_page())
	var p0: float = player.spec.front_tyre_pressure
	await _tap(KEY_DOWN)
	await _tap(KEY_RIGHT)
	_check(player.spec.front_tyre_pressure > p0 and is_equal_approx(player.front_tyre_pressure, player.spec.front_tyre_pressure), "Right should raise the front pressure (%f -> %f)" % [p0, player.spec.front_tyre_pressure])
	_check(screen.preset_label.text.contains("(modified)"), "changing a setting should mark the setup modified: %s" % screen.preset_label.text)
	await _tap(KEY_Q)
	_check(screen.current_page() == "setup", "Q should go back to Setup")
	screen.preset_buttons[2].pressed.emit()  # Grip
	_check(screen.preset_label.text == "Setup: Grip" and player.spec.front_static_camber < 0.0, "the Grip preset should apply (label %s, camber %f)" % [screen.preset_label.text, player.spec.front_static_camber])
	screen.preset_buttons[0].pressed.emit()  # back to Stock
	_check(is_equal_approx(player.spec.front_tyre_pressure, CarSpec.coupe_default().front_tyre_pressure) and is_equal_approx(player.spec.front_static_camber, 0.0), "Stock should put the car back")

	# --- the raw gearing panel (Advanced) still drives the Auto-Tune lock labels ---
	var fd: HSlider = screen.manual.sliders.final_drive
	fd.value = fd.value + 0.1
	_check(is_equal_approx(player.spec.final_drive, fd.value), "the Advanced final drive slider should write the spec")
	_check(screen.auto.lock_boxes["final_drive"].text.contains("%.2f" % fd.value), "Auto-Tune lock label should follow the slider: %s" % screen.auto.lock_boxes["final_drive"].text)

	# --- exhaust sliders: spec and the live synth, while paused ---
	screen.exhaust.sliders.loudness.value = 0.9
	screen.exhaust.sliders.flame.value = 0.8
	_check(is_equal_approx(player.spec.exhaust.loudness, 0.9) and is_equal_approx(player.spec.exhaust.flame, 0.8), "exhaust sliders did not write the spec")
	_check(is_equal_approx(audio.synth.tune.loudness, 0.9) and is_equal_approx(audio.synth.tune.flame, 0.8), "synth tune did not follow the sliders (%f, %f)" % [audio.synth.tune.loudness, audio.synth.tune.flame])
	screen.exhaust.sliders.pops.value = preset.pops

	# --- tune slot keeps the exhaust tune ---
	var slots := TuneSlots.new(SLOT_FILE)
	screen.auto.slots = slots
	screen.auto._refresh_slots()
	screen.auto.slot_name_edit.text = "Loud"
	screen.auto.save_button.pressed.emit()
	_check(slots.has("Loud") and is_equal_approx(slots.values("Loud")["exhaust/flame"], 0.8), "slot did not store the exhaust tune")
	screen.exhaust.sliders.flame.value = 0.1
	screen.exhaust.sliders.loudness.value = 0.2
	screen.auto.slot_list.select(0)
	screen.auto.load_button.pressed.emit()
	_check(is_equal_approx(player.spec.exhaust.flame, 0.8) and is_equal_approx(player.spec.exhaust.loudness, 0.9), "Load did not restore the exhaust tune")
	_check(is_equal_approx(audio.synth.tune.flame, 0.8), "Load did not reach the synth")
	_check(is_equal_approx(screen.exhaust.sliders.flame.value, 0.8), "exhaust slider did not follow the Load")
	screen.auto.undo_button.pressed.emit()
	_check(is_equal_approx(player.spec.exhaust.flame, 0.1) and is_equal_approx(player.spec.exhaust.loudness, 0.2), "Undo did not revert the exhaust tune")
	screen.exhaust.sliders.loudness.value = 0.9   # the values the saved file should end up with
	screen.exhaust.sliders.flame.value = 0.6

	# --- Esc closes it, and the tune is saved a moment later ---
	await _tap(KEY_ESCAPE)
	await _until(func(): return game.game_state.state == GameState.State.PLAYING, 5.0)
	_check(not screen.visible and root.gui_get_focus_owner() == null, "Esc should close the screen and drop focus")
	await _ticks(20)
	var saved := ExhaustTune.load_saved("p1_coupe")
	_check(not saved.is_empty() and is_equal_approx(saved.loudness, 0.9) and is_equal_approx(saved.flame, 0.6), "exhaust tune not saved: %s" % str(saved))

	# --- a car built later starts from the saved tune ---
	var later := PlayerCar.new()
	root.add_child(later)
	await _ticks(2)
	_check(is_equal_approx(later.spec.exhaust.loudness, 0.9) and is_equal_approx(later.spec.exhaust.flame, 0.6), "a new car did not start from the saved tune: %s" % str(later.spec.exhaust))
	var later_audio: EngineAudio = null
	for c in later.get_children():
		if c is EngineAudio:
			later_audio = c
	_check(later_audio != null and is_equal_approx(later_audio.synth.tune.loudness, 0.9), "a new car's synth did not start from the saved tune")
	_end("")

func _end(msg: String) -> void:
	if msg != "":
		failures.append(msg)
	for f in failures:
		printerr("FAIL: ", f)
	print("tuner_screen: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _ready_game() -> Node:
	var g := current_scene
	if g != null and is_instance_valid(g) and g.get("player") != null and g.get("game_state") != null:
		return g
	return null

# Waits (physics ticks) until cond is true or timeout_s of WALL time passes.
func _until(cond: Callable, timeout_s: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if (Time.get_ticks_msec() - t0) / 1000.0 > timeout_s:
			return false
		await physics_frame
	return true

func _ticks(n: int) -> void:
	for i in n:
		await physics_frame

func _tap(code: Key) -> void:
	_key(code, true)
	await _ticks(HOLD_TICKS)
	_key(code, false)
	# Key events reach the GUI when the input buffer is flushed, once per rendered
	# frame; under load several physics ticks can pass in one frame.
	await process_frame
	await process_frame

func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)

func _find(game: Node, type) -> Node:
	for c in game.get_children():
		if is_instance_of(c, type):
			return c
	return null

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
