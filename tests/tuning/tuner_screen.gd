extends SceneTree

# One Tuner screen test: runs the real Game.tscn and checks that
# - T opens the screen on the Quick page (tuner overhaul, 2026-10-10) with the
#   car's own name in the header and no key hints; only Quick is listed until
#   Detailed is on; a preset on show is previewed and only fitted on Enter; a
#   dial moves its real settings; changed rows carry a dot; every row has a
#   "You'll feel" line; Backspace undoes
# - with Detailed on, E/Q change page, Down/Right move a notch and write the car,
#   presets apply and Stock puts the car back; the raw gearing panel still works
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
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/tuning/tuner_screen.gd

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
	_check(screen.current_page() == "quick", "T should open on the Quick page, on %s" % screen.current_page())
	_check(screen.car_label.text.contains("Coupe - Sports coupe") and not screen.car_label.text.contains("P1"), "the header should name the car: %s" % screen.car_label.text)
	_check(not screen.auto.is_visible_in_tree(), "the Mechanic (Auto-Tune) page should not show after T")
	_check(is_equal_approx(screen.exhaust.sliders.loudness.value, preset.loudness) and is_equal_approx(screen.exhaust.sliders.flame.value, preset.flame), "exhaust sliders should start on the car's preset")
	_check(not screen.car_label.text.contains("T or Y") and not screen.hint.text.contains("Esc"), "no key hints on the screen")

	# --- Quick page: only page listed while Detailed is off (not saved: that is Roy's settings file) ---
	screen.set_detailed(false, false)
	_check(screen.visible_page_ids().size() == 1 and not screen.page_labels[2].visible, "only Quick should be listed while Detailed is off")
	await _tap(KEY_E)
	_check(screen.current_page() == "quick", "E should stay on Quick while Detailed is off")
	_check(screen.rows.size() == 6 and screen.hint.text.contains(TunerFeel.PREFIX), "the Quick page should have six rows and a feel line: %s" % screen.hint.text)
	# preset on show: previewed, the car untouched until Enter
	await _tap(KEY_RIGHT)
	await _tap(KEY_RIGHT)
	_check(screen.preset_show == 2 and screen.model.preset == "Stock" and is_equal_approx(player.spec.front_static_camber, 0.0), "looking at Grip should not fit it")
	_check(screen.preview_label.visible and screen.preview_label.text.contains("GRIP") and screen.rows[0].value.text.contains("preview"), "Grip should be previewed: %s / %s" % [screen.preview_label.text, screen.rows[0].value.text])
	await _tap(KEY_ENTER)
	_check(screen.preset_label.text == "Setup: Grip" and player.spec.front_static_camber < 0.0, "Enter should fit Grip (label %s, camber %f)" % [screen.preset_label.text, player.spec.front_static_camber])
	_check(not screen.preview_label.visible and screen.rows[0].name.text.contains(TunerScreen.CHANGED_DOT), "a fitted preset: no preview, a dot on the row (%s)" % screen.rows[0].name.text)
	await _tap(KEY_BACKSPACE)
	_check(screen.preset_label.text == "Setup: Stock" and is_equal_approx(player.spec.front_static_camber, 0.0), "Backspace should take Grip off again (label %s)" % screen.preset_label.text)
	_check(not screen.rows[0].name.text.contains(TunerScreen.CHANGED_DOT), "no dot on the Preset row at Stock")
	# Grip / Slide dial: one notch toward Slide moves the rear bar and marks the row
	await _tap(KEY_DOWN)
	var arb0: float = player.spec.rear_arb_ratio
	_check(screen.hint.text.contains("One notch toward Slide"), "a dial should preview both ways: %s" % screen.hint.text)
	await _tap(KEY_RIGHT)
	_check(player.spec.rear_arb_ratio > arb0 and screen.model.dial("q_grip_slide") == 1, "Right should move Grip / Slide one notch (bar %f -> %f, dial %d)" % [arb0, player.spec.rear_arb_ratio, screen.model.dial("q_grip_slide")])
	_check(screen.rows[1].name.text.contains(TunerScreen.CHANGED_DOT) and screen.rows[1].bar.now == 6, "the moved dial should show a dot and sit one right of the middle")
	_check(screen.preset_label.text.contains("(modified)"), "a dial should mark the setup modified")
	await _tap(KEY_BACKSPACE)
	_check(is_equal_approx(player.spec.rear_arb_ratio, arb0) and screen.model.dial("q_grip_slide") == 0, "Backspace should put the dial back")
	# Pull / Top speed dial: toward Pull shortens the final drive, on the car too
	await _tap(KEY_DOWN)
	await _tap(KEY_DOWN)
	var fd0: float = player.spec.final_drive
	await _tap(KEY_LEFT)
	_check(player.spec.final_drive > fd0 and is_equal_approx(player.final_drive, player.spec.final_drive) and screen.model.dial("q_pull_top") == -1, "Left should shorten the gearing (%f -> %f)" % [fd0, player.spec.final_drive])
	_check(screen.undo() and is_equal_approx(player.spec.final_drive, fd0) and not screen.undo(), "undo should put the gearing back, and then have nothing left")
	# Ask Walt: Right picks the goal (not started here: a search launches a second Godot)
	await _tap(KEY_DOWN)
	await _tap(KEY_RIGHT)
	_check(screen.walt_goal == 1 and screen.rows[4].value.text == "Top speed", "Right on Ask Walt should pick Top speed: %s" % screen.rows[4].value.text)
	screen._walt_finish()
	_check(screen.rows[4].value.text != "Top speed" and is_equal_approx(player.spec.final_drive, fd0), "Walt back with nothing: the row says so and the car is untouched")
	# every row, here and on the full pages, has a feel line
	for pg in [TunerModel.quick_page()] + TunerModel.pages():
		for st in pg.settings:
			_check(TunerFeel.for_setting(st) != "", "no feel line for %s" % st.id)
	for k in TuningPanel.KNOBS:
		_check(TunerFeel.for_path(k[2]) != "", "no feel line for the raw %s" % k[2])
	for ep in TuneParams.exhaust_paths():
		_check(TunerFeel.for_path(ep) != "", "no feel line for %s" % ep)

	# --- Detailed on: the full pages are listed and Q/E reach them ---
	screen.set_detailed(true, false)
	_check(screen.visible_page_ids().size() == 13 and screen.page_labels[2].visible, "Detailed should list every page")
	await _tap(KEY_E)
	_check(screen.current_page() == "setup" and screen.preset_buttons[0].has_focus(), "E should go to Setup with Stock focused")

	# --- keyboard navigation: E to Tires, Down to front pressure, Right one notch ---
	await _tap(KEY_E)
	_check(screen.current_page() == "tyres" and screen.page_title.text == "TIRES", "E should go to the Tires page, on %s" % screen.current_page())
	var p0: float = player.spec.front_tyre_pressure
	await _tap(KEY_DOWN)
	await _tap(KEY_RIGHT)
	_check(player.spec.front_tyre_pressure > p0 and is_equal_approx(player.front_tyre_pressure, player.spec.front_tyre_pressure), "Right should raise the front pressure (%f -> %f)" % [p0, player.spec.front_tyre_pressure])
	_check(screen.preset_label.text.contains("(modified)"), "changing a setting should mark the setup modified: %s" % screen.preset_label.text)
	# consequence line and danger zones (settings safety part 3)
	var prow: Dictionary = screen.rows[1]
	_check(prow.line != null and prow.line.text.begins_with("High"), "front pressure up should say what it does: %s" % (prow.line.text if prow.line else "no line"))
	_check(prow.bar.zones.size() == TunerModel.NOTCHES, "the pressure bar should carry a zone per notch")
	_check(prow.name.text.contains(TunerScreen.CHANGED_DOT) and not screen.rows[2].name.text.contains(TunerScreen.CHANGED_DOT), "only the changed row should carry a dot")
	_check(screen.page_labels[2].text.contains(TunerScreen.CHANGED_DOT) and not screen.page_labels[3].text.contains(TunerScreen.CHANGED_DOT), "the Tires page should carry a dot in the list")
	_check(screen.hint.text.contains(TunerFeel.PREFIX), "a settings row should have a feel line: %s" % screen.hint.text)
	var rp: Dictionary = screen.rows[2]  # rear pressure: amber at its ends on the simple page, never red
	_check(rp.bar.zones[0] == SettingDanger.Level.AMBER and not rp.bar.zones.has(SettingDanger.Level.RED), "rear pressure zones: %s" % str(rp.bar.zones))
	await _tap(KEY_Q)
	_check(screen.current_page() == "setup", "Q should go back to Setup")
	screen.preset_buttons[2].pressed.emit()  # Grip
	_check(screen.preset_label.text == "Setup: Grip" and player.spec.front_static_camber < 0.0, "the Grip preset should apply (label %s, camber %f)" % [screen.preset_label.text, player.spec.front_static_camber])
	screen.preset_buttons[0].pressed.emit()  # back to Stock
	_check(is_equal_approx(player.spec.front_tyre_pressure, CarSpec.coupe_default().front_tyre_pressure) and is_equal_approx(player.spec.front_static_camber, 0.0), "Stock should put the car back")

	# --- the raw gearing panel (Advanced) still drives the Auto-Tune lock labels ---
	var fd: HSlider = screen.manual.sliders.final_drive
	fd.value = fd.value + 0.1
	_check(screen.manual.name_labels.final_drive.text.begins_with(TuningPanel.CHANGED_DOT) and not screen.manual.name_labels.gear_1.text.begins_with(TuningPanel.CHANGED_DOT), "the raw panel should dot the changed row only")
	_check(is_equal_approx(player.spec.final_drive, fd.value), "the Advanced final drive slider should write the spec")
	_check(screen.auto.lock_boxes["final_drive"].text.contains("%.2f" % fd.value), "Auto-Tune lock label should follow the slider: %s" % screen.auto.lock_boxes["final_drive"].text)

	# --- exhaust page: the focused slider's feel line; one slider dragged is one undo ---
	screen.show_page("exhaust")
	_check(screen.hint.text.contains("Only what you hear"), "the focused exhaust slider should have its feel line: %s" % screen.hint.text)
	var undo0 := screen.undo_stack.size()
	screen.exhaust.sliders.loudness.value = 0.5
	screen.exhaust.sliders.loudness.value = 0.55
	_check(screen.undo_stack.size() == undo0 + 1, "dragging one slider should be one undo step (%d -> %d)" % [undo0, screen.undo_stack.size()])
	screen.undo()
	_check(is_equal_approx(player.spec.exhaust.loudness, preset.loudness) and is_equal_approx(audio.synth.tune.loudness, preset.loudness), "undo should put the exhaust back, on the synth too")

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
