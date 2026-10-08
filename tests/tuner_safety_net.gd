extends SceneTree

# Settings safety part 4 on the real Game.tscn, headless:
# - every settings page ends in "Reset page to stock": Right on it puts that page
#   back to stock and leaves the other pages alone
# - Advanced asks once ("Open Advanced"), then opens straight to the sliders;
#   its Reset now goes to stock, not to the values at game start
# - auto-revert: closing the Tuner with a red value arms the watchdog; upside
#   down for 3 s asks Keep / Revert (Revert focused) and Revert puts the old tune
#   back with the car upright; full throttle at a standstill for 8 s asks too,
#   and Keep keeps the tune; the countdown reverts on its own; a stock-safe tune
#   does not arm it; a NaN car is reverted at once without asking
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 60 --path . -s res://tests/tuner_safety_net.gd

var failures: Array[String] = []
var game: Node
var screen: TunerScreen
var player: PlayerCar
var dog: TuneWatchdog

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	change_scene_to_file("res://Game.tscn")
	_run()

func _run() -> void:
	var t0 := Time.get_ticks_msec()
	while (current_scene == null or current_scene.get("game_state") == null) and Time.get_ticks_msec() - t0 < 15000:
		await process_frame
	game = current_scene
	for c in game.get_children():
		if c is TunerScreen:
			screen = c
	if screen == null:
		return _end("no TunerScreen")
	player = game.player
	await _frames(30)
	dog = screen.watchdog
	_check(dog != null and dog.is_inside_tree(), "the watchdog should be in the scene")
	var stock := CarSpec.coupe_default()

	# --- per-page reset ---
	game.game_state.toggle_tuning()
	await process_frame
	screen.show_page("tyres")
	screen.model.nudge(TunerModel.page("tyres").settings[1], 3)  # front pressure
	screen.show_page("suspension")
	_check(screen.rows.back().setting.kind == "reset", "the last row should be Reset page to stock")
	var springs: Dictionary = TunerModel.page("suspension").settings[3]  # rear springs
	screen.model.nudge(springs, 4)
	_check(player.spec.rear_resting_ratio != stock.rear_resting_ratio, "nudge did not move the rear springs")
	screen.row_index = screen.rows.size() - 1
	screen._nudge(1)
	_check(is_equal_approx(player.spec.rear_resting_ratio, stock.rear_resting_ratio) and is_equal_approx(player.rear_resting_ratio, stock.rear_resting_ratio), "page reset left rear springs at %f" % player.spec.rear_resting_ratio)
	_check(player.spec.front_tyre_pressure > stock.front_tyre_pressure, "resetting Suspension should not touch Tyres")
	screen.show_page("tyres")
	screen.reset_current_page()
	_check(is_equal_approx(player.spec.front_tyre_pressure, stock.front_tyre_pressure), "Tyres page reset failed")

	# --- Advanced gate and its Reset ---
	TunerGate.set_advanced_ok(false)
	screen.show_page("advanced")
	_check(screen.adv_gate.visible and not screen.manual.visible and screen.adv_gate_button.has_focus(), "Advanced should ask first, with the button focused")
	screen.adv_gate_button.pressed.emit()
	_check(TunerGate.advanced_ok() and screen.manual.visible and not screen.adv_gate.visible, "Open Advanced should show the sliders and remember it")
	screen.show_page("setup")
	screen.show_page("advanced")
	_check(screen.manual.visible and screen.manual.sliders.final_drive.has_focus(), "the second visit should open straight to the sliders")
	screen.manual.sliders.final_drive.value = 6.5
	screen.manual._reset()
	_check(is_equal_approx(player.spec.final_drive, stock.final_drive), "Advanced Reset should go to stock, final drive %f" % player.spec.final_drive)
	game.game_state.toggle_tuning()
	await _frames(2)
	_check(not dog.watching, "a stock tune should not arm the watchdog")

	# --- flipped: ask, Revert ---
	game.game_state.toggle_tuning()
	await process_frame
	CarSpec.set_param(player, player.spec, "rear_toe", -0.03)  # red: spins
	game.game_state.toggle_tuning()
	await _frames(2)
	_check(dog.watching, "closing with a red value should arm the watchdog")
	var upside := Transform3D(Basis(Vector3.FORWARD, PI), player.global_position + Vector3(0, 1.5, 0))
	for i in 60 * 4:
		if dog.dialog.visible:
			break
		player.global_transform = upside
		player.linear_velocity = Vector3.ZERO
		player.angular_velocity = Vector3.ZERO
		await physics_frame
	_check(dog.dialog.visible and dog.reason.contains("flipped"), "upside down for 3 s should ask (reason '%s')" % dog.reason)
	_check(dog.revert_button.has_focus(), "Revert should have focus")
	_check(not dog.message.text.contains("Enter") and not dog.message.text.contains("Esc"), "no key hints in the question")
	dog.revert_button.pressed.emit()
	await _frames(2)
	_check(not dog.dialog.visible, "Revert should close the question")
	_check(is_equal_approx(player.spec.rear_toe, stock.rear_toe) and is_equal_approx(player.rear_toe, stock.rear_toe), "Revert should put the old rear toe back, got %f" % player.spec.rear_toe)
	_check(player.global_transform.basis.y.y > 0.9, "Revert should set the car upright")

	# --- stuck: ask, Keep ---
	game.game_state.toggle_tuning()
	await process_frame
	CarSpec.set_param(player, player.spec, "max_rpm", 3500.0)  # red: slow everywhere
	game.game_state.toggle_tuning()
	await _frames(2)
	Input.action_press("accelerate")
	for i in 60 * 10:
		if dog.dialog.visible:
			break
		player.linear_velocity = Vector3.ZERO
		await physics_frame
	Input.action_release("accelerate")
	_check(dog.dialog.visible and dog.reason.contains("get going"), "full throttle at a standstill for 8 s should ask (reason '%s', throttle %f)" % [dog.reason, player.throttle_input])
	dog.keep_button.pressed.emit()
	await _frames(2)
	_check(not dog.dialog.visible and is_equal_approx(player.spec.max_rpm, 3500.0), "Keep should keep the tune")

	# --- the countdown reverts on its own ---
	var before: int = dog.reverted_count
	dog.saved_spec = CarSpec.clone_spec(stock)
	dog.ask("test")
	dog.countdown = 0.2
	await _frames(30)
	_check(not dog.dialog.visible and dog.reverted_count == before + 1 and is_equal_approx(player.spec.max_rpm, stock.max_rpm), "the countdown should revert")

	# --- NaN: at once, no question ---
	before = dog.reverted_count
	player.linear_velocity = Vector3(NAN, 0.0, 0.0)
	await _frames(3)
	_check(dog.reverted_count == before + 1 and not dog.dialog.visible, "a NaN car should be reverted at once without asking")
	_check(is_finite(player.linear_velocity.x) and is_finite(player.global_position.x), "after a NaN revert the car should be finite")
	_end("")

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
		print("FAIL ", msg)

func _end(msg: String) -> void:
	if msg != "":
		failures.append(msg)
	print("tuner_safety_net: %s" % ("PASS" if failures.is_empty() else "FAIL (%d)" % failures.size()))
	quit(0 if failures.is_empty() else 1)
