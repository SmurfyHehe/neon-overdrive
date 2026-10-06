extends SceneTree

# Tuning panel test (#62): runs the real Game.tscn and checks that
# - CarSpec.build_torque_curve() at the default shape matches the old
#   hand-placed curve, so adding the knobs did not change the car
# - T opens the Tuner screen: tree paused, state TUNING, gearing panel shown,
#   Auto-Tune section folded away, pause menu not, keyboard focus on the first slider
# - moving sliders writes into the live Vehicle (gearing, torque, curve)
# - the readout shows 253 km/h in 5th: #62's 230 at 7000 rpm, but GEVP
#   only cuts at 110% of redline (7700 rpm)
# - T closes it again, and Esc closes it too; focus is released on close
#
# Exit code 1 on failure. Run (a window opens for a few seconds):
#   Godot_v4.7.2-stable_win64_console.exe --path . -s res://tests/tuning_panel.gd

# Game polls input in _physics_process (#30), and Input.is_action_just_pressed
# is only true on the physics tick the press landed in. A key pressed and
# released in the same render frame is gone before a tick can see it, so a tap
# presses now and releases HOLD_TICKS physics ticks later (2 = at least one
# whole tick with the key down, whichever order the callbacks run in).
const HOLD_TICKS := 2

var frame := 0
var tick := 0
var failures: Array[String] = []
var releases := {}             # Key -> tick on which to release it

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")  # an empty road, whatever run_tests.bat or the saved settings say
	change_scene_to_file("res://Game.tscn")

func _physics_process(_delta: float) -> bool:
	tick += 1
	for code in releases.keys():
		if tick >= releases[code]:
			_send(code, false)
			releases.erase(code)
	return false

func _process(_delta: float) -> bool:
	frame += 1
	var game := current_scene
	match frame:
		5:
			_check_default_curve()
		20:
			_key(KEY_T)
		60:
			var panel := _panel(game)
			_check(paused, "T should pause the tree")
			_check(game.game_state.state == GameState.State.TUNING, "state should be TUNING")
			_check(_screen(game).visible and panel.is_visible_in_tree(), "tuner screen should show the gearing panel")
			_check(not _screen(game).auto.is_visible_in_tree(), "T should leave the Auto-Tune section folded away")
			_check(root.gui_get_focus_owner() == panel.sliders.final_drive, "first slider should have keyboard focus on open, has %s" % root.gui_get_focus_owner())
			_check(not _find(game, PauseMenu).visible, "pause menu should stay hidden")
			_check(panel.readout.text.contains("253"), "readout should show 253 km/h in 5th:\n" + panel.readout.text)
			panel.sliders.final_drive.value = 3.5
			panel.sliders.gear_5.value = 1.1
			panel.sliders.max_torque.value = 500.0
			var before: float = game.player.get_torque_at_rpm(1000.0)
			panel.sliders.low_end.value = 0.7
			_check(is_equal_approx(game.player.final_drive, 3.5), "final_drive not applied")
			_check(is_equal_approx(game.player.gear_ratios[4], 1.1), "gear 5 not applied")
			_check(is_equal_approx(game.player.max_torque, 500.0), "max_torque not applied")
			_check(game.player.get_torque_at_rpm(1000.0) > before, "low-end knob should raise low-rpm torque")
			# One write path: the player's spec dict holds the same values.
			var spec: Dictionary = game.player.spec
			_check(is_equal_approx(spec.final_drive, 3.5), "spec final_drive not written")
			_check(is_equal_approx(spec.gear_ratios[4], 1.1), "spec gear 5 not written")
			_check(spec.gear_ratios.is_typed(), "spec gear_ratios lost its type")
			_check(is_equal_approx(spec.max_torque, 500.0), "spec max_torque not written")
			_check(is_equal_approx(spec.torque_shape.low_end, 0.7), "spec torque shape not written")
			_key(KEY_T)
		100:
			_check(not paused, "second T should unpause")
			_check(game.game_state.state == GameState.State.PLAYING, "state should be PLAYING")
			_check(not _screen(game).visible, "tuner screen should hide")
			_check(root.gui_get_focus_owner() == null, "focus should be released on close")
			_key(KEY_T)
		140:
			_key(KEY_ESCAPE)
		180:
			_check(not paused, "Esc should close the panel and unpause")
			_check(game.game_state.state == GameState.State.PLAYING, "Esc should return to PLAYING")
			_check(not _find(game, PauseMenu).visible, "Esc out of tuning should not open the pause menu")
			for f in failures:
				printerr("FAIL: ", f)
			print("tuning_panel: ", "PASS" if failures.is_empty() else "FAIL")
			quit(0 if failures.is_empty() else 1)
	return false

func _check_default_curve() -> void:
	var old := Curve.new()
	for p in [Vector2(0.0, 0.35), Vector2(0.25, 0.75), Vector2(0.55, 1.0), Vector2(0.85, 0.9), Vector2(1.0, 0.55)]:
		old.add_point(p)
	var built := CarSpec.default_torque_curve()
	for i in 101:
		var x := i / 100.0
		if absf(old.sample_baked(x) - built.sample_baked(x)) > 0.001:
			failures.append("default curve differs at x=%.2f: %.4f vs %.4f" % [x, old.sample_baked(x), built.sample_baked(x)])
			return

func _screen(game: Node) -> TunerScreen:
	return _find(game, TunerScreen)

func _panel(game: Node) -> TuningPanel:
	return _screen(game).manual

func _find(game: Node, type) -> Node:
	for c in game.get_children():
		if is_instance_of(c, type):
			return c
	return null

func _key(code: Key) -> void:
	_send(code, true)
	releases[code] = tick + HOLD_TICKS

func _send(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
