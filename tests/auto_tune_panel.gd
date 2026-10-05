extends SceneTree

# Auto-Tune panel test (step 6): runs the real Game.tscn and checks that
# - Y opens the panel: state AUTOTUNE, tree paused, panel shown, raw T panel and
#   pause menu not
# - Run with no goal does nothing; with a goal it starts the search process and
#   shows progress, then the before/after result
# - the baseline the search measured matches the headless numbers for the
#   default coupe (the worker process runs the same sim as tests/tune_track.gd)
# - locks set in the UI reach the search (only the unlocked value moves)
# - Apply writes the player's spec and live car through CarSpec.set_param();
#   Undo puts them back
# - the raw T panel shows what Auto-Tune applied (its sliders re-sync on open)
# - tune slots (step 7): Save stores the whole tune (engine knobs too), Load puts
#   it back through the write path (spec and live car) and Undo reverts the load,
#   saving the same name replaces, Delete removes the entry
# - closing the panel mid-search cancels it and kills the worker
#
# Paced in physics ticks and wall-clock timeouts, not render frames (see
# tests/game_state.gd for why). Exit code 1 on failure. Run (window, ~1 min):
#   Godot_v4.7.2-stable_win64_console.exe --path . -s res://tests/auto_tune_panel.gd

const HOLD_TICKS := 6
# Default coupe on the headless test track (tests/tune_track.gd).
const EXPECT_TOP := 241.3
const EXPECT_0_100 := 5.25
const EXPECT_100_0 := 41.9
const TOLERANCE := 0.005
const SLOT_FILE := "user://autotune/test_panel_slots.json"

var failures: Array[String] = []

func _initialize() -> void:
	change_scene_to_file("res://Game.tscn")
	_run()

func _run() -> void:
	if not await _until(func(): return _ready_game() != null, 15.0):
		return _end("Game.tscn never became ready")
	var game := _ready_game()
	var player: PlayerCar = game.player
	var panel: AutoTunePanel = _find(game, AutoTunePanel)
	var raw: TuningPanel = _find(game, TuningPanel)
	_check(panel != null, "Game has no AutoTunePanel")
	if panel == null:
		return _end("")

	# --- open: game paused, panel shown ---
	await _tap(KEY_Y)
	await _until(func(): return game.game_state.state == GameState.State.AUTOTUNE, 5.0)
	_check(game.game_state.state == GameState.State.AUTOTUNE, "Y should open Auto-Tune")
	_check(panel.visible and not raw.visible and not _find(game, PauseMenu).visible, "only the Auto-Tune panel should show")
	_check(paused, "Auto-Tune should pause the game like the raw panel")

	# --- Run with no goal ---
	panel.run_button.pressed.emit()
	_check(not panel.running, "Run with no goal should not start a search")

	# --- braking, everything locked but the brake multiplier ---
	panel.goal_sliders.braking.value = 1
	for path in panel.lock_boxes:
		panel.lock_boxes[path].button_pressed = path != "brake_force_multiplier"
	_check(panel.request().locks.size() == 13 and not panel.request().locks.has("brake_force_multiplier"), "locks not read from the checkboxes")
	panel.budget_override = 8
	var start_spec := CarSpec.clone_spec(player.spec)
	var wall0 := Time.get_ticks_msec()
	panel.run_button.pressed.emit()
	_check(panel.running, "Run should start a search")
	_check(panel.run_button.disabled and not panel.cancel_button.disabled, "buttons while running")
	if not await _until(func(): return not panel.running, 300.0):
		return _end("search did not finish in 300 s")
	var wall := (Time.get_ticks_msec() - wall0) / 1000.0
	var r: Dictionary = panel.result
	print("search through the panel: %d runs in %.1f s wall" % [r.evals, wall])
	_check(not r.is_empty() and r.get("ok", false), "no result: %s" % panel.status_label.text)
	_check(paused, "game should stay paused")
	var b: Dictionary = r.base_metrics
	print("search baseline: top %.1f km/h, 0-100 %.2f s, 100-0 %.1f m (headless: %.1f, %.2f, %.1f)" % [b.top_speed_kmh, b.t_0_100, b.brake_dist_100, EXPECT_TOP, EXPECT_0_100, EXPECT_100_0])
	_check(absf(b.top_speed_kmh / EXPECT_TOP - 1.0) < TOLERANCE, "top speed %.1f differs from headless %.1f" % [b.top_speed_kmh, EXPECT_TOP])
	_check(absf(b.t_0_100 / EXPECT_0_100 - 1.0) < TOLERANCE, "0-100 %.2f differs from headless %.2f" % [b.t_0_100, EXPECT_0_100])
	_check(absf(b.brake_dist_100 / EXPECT_100_0 - 1.0) < TOLERANCE, "100-0 %.1f differs from headless %.1f" % [b.brake_dist_100, EXPECT_100_0])
	_check(r.improved, "braking search found nothing: %s" % str(r.notes))
	_check(panel.result_label.text != "" and panel.status_label.text.begins_with("Done"), "no result shown")
	if r.improved:
		for path in TuneParams.auto_paths():
			if path != "brake_force_multiplier":
				_check(is_equal_approx(r.values[path], TuneParams.get_value(start_spec, path)), "locked %s changed" % path)
		_check(not is_equal_approx(r.values.brake_force_multiplier, start_spec.brake_force_multiplier), "the one free value did not move")
		_check(not panel.apply_button.disabled, "Apply should be enabled")
		# --- Apply / Undo ---
		panel.apply_button.pressed.emit()
		_check(is_equal_approx(player.spec.brake_force_multiplier, r.values.brake_force_multiplier), "Apply did not write the spec")
		_check(is_equal_approx(player.brake_force_multiplier, r.values.brake_force_multiplier), "Apply did not reach the live car")
		_check(panel.apply_button.disabled and not panel.undo_button.disabled, "buttons after Apply")
		panel.undo_button.pressed.emit()
		_check(is_equal_approx(player.spec.brake_force_multiplier, start_spec.brake_force_multiplier), "Undo did not restore the spec")
		_check(is_equal_approx(player.brake_force_multiplier, start_spec.brake_force_multiplier), "Undo did not restore the live car")

	# --- close: game running again ---
	await _tap(KEY_Y)
	await _until(func(): return game.game_state.state == GameState.State.PLAYING, 5.0)
	_check(not paused, "closing Auto-Tune should unpause")

	# --- raw panel re-syncs to what Auto-Tune (or anything) wrote ---
	CarSpec.set_param(player, player.spec, "final_drive", 3.3)
	await _tap(KEY_T)
	await _until(func(): return game.game_state.state == GameState.State.TUNING, 5.0)
	_check(is_equal_approx(raw.sliders.final_drive.value, 3.3), "raw panel slider shows %f, spec has 3.3" % raw.sliders.final_drive.value)
	await _tap(KEY_T)
	await _until(func(): return game.game_state.state == GameState.State.PLAYING, 5.0)

	# --- tune slots ---
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://autotune"))
	var sf := FileAccess.open(SLOT_FILE, FileAccess.WRITE)  # start empty (overwrite; never deleted)
	sf.store_string("")
	sf = null
	panel.slots = TuneSlots.new(SLOT_FILE)
	panel._refresh_slots()
	await _tap(KEY_Y)
	await _until(func(): return game.game_state.state == GameState.State.AUTOTUNE, 5.0)
	_check(panel.slot_list.item_count == 0 and panel.save_button.disabled == false and panel.load_button.disabled, "empty slot list: Load should be off")
	panel.save_button.pressed.emit()
	_check(panel.slot_list.item_count == 0 and panel.status_label.text.contains("name"), "Save with no name should ask for one")
	CarSpec.set_param(player, player.spec, "final_drive", 3.3)
	CarSpec.set_param(player, player.spec, "max_torque", 420.0)   # raw-only knob: a slot keeps it too
	panel.slot_name_edit.text = "Test A"
	panel.save_button.pressed.emit()
	_check(panel.slot_list.item_count == 1 and panel.slot_list.get_item_text(0) == "Test A", "slot not listed after Save")
	_check(panel.status_label.text.begins_with("Saved"), "status after Save: %s" % panel.status_label.text)
	CarSpec.set_param(player, player.spec, "final_drive", 4.4)
	CarSpec.set_param(player, player.spec, "max_torque", 300.0)
	panel.slot_list.select(0)
	panel.slot_list.item_selected.emit(0)
	_check(panel.slot_name_edit.text == "Test A" and not panel.load_button.disabled, "picking a slot should fill the name and enable Load")
	panel.load_button.pressed.emit()
	_check(is_equal_approx(player.spec.final_drive, 3.3) and is_equal_approx(player.spec.max_torque, 420.0), "Load did not restore the saved tune: %f %f" % [player.spec.final_drive, player.spec.max_torque])
	_check(is_equal_approx(player.final_drive, 3.3) and is_equal_approx(player.max_torque, 420.0), "Load did not reach the live car")
	_check(not panel.undo_button.disabled, "Undo should be on after Load")
	panel.undo_button.pressed.emit()
	_check(is_equal_approx(player.spec.final_drive, 4.4) and is_equal_approx(player.spec.max_torque, 300.0), "Undo did not revert the Load")
	panel.save_button.pressed.emit()  # same name in the box: replaces
	_check(panel.status_label.text.begins_with("Replaced") and panel.slot_list.item_count == 1, "same name should replace: %s" % panel.status_label.text)
	_check(is_equal_approx(panel.slots.values("Test A").final_drive, 4.4), "replaced slot holds the old value")
	panel.slot_list.select(0)
	panel.delete_button.pressed.emit()
	_check(panel.slot_list.item_count == 0 and not panel.slots.has("Test A"), "Delete did not remove the slot")
	CarSpec.set_param(player, player.spec, "final_drive", start_spec.final_drive)
	CarSpec.set_param(player, player.spec, "max_torque", start_spec.max_torque)

	# --- cancel by closing mid-search ---
	panel.goal_sliders.accel.value = 1
	for path in panel.lock_boxes:
		panel.lock_boxes[path].button_pressed = false
	panel.budget_override = 60
	panel.run_button.pressed.emit()
	_check(panel.running, "search should be running")
	var job_pid: int = panel._job.pid
	await _ticks(90)  # ~1.5 s: the worker is mid-search
	await _tap(KEY_Y)
	await _until(func(): return game.game_state.state == GameState.State.PLAYING, 5.0)
	_check(not panel.running, "closing the panel should cancel the search")
	await _ticks(60)
	_check(not OS.is_process_running(job_pid), "worker still running after the panel closed")
	_check(panel.status_label.text == "Cancelled.", "status should say Cancelled, says: %s" % panel.status_label.text)
	_end("")

func _end(msg: String) -> void:
	if msg != "":
		failures.append(msg)
	for f in failures:
		printerr("FAIL: ", f)
	print("auto_tune_panel: ", "PASS" if failures.is_empty() else "FAIL")
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
