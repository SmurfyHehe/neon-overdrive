extends SceneTree

# R reverse and the one-menu tuner (2026-10-05), headless and silent, driven by
# direct calls and a scripted driver (no key events):
# - the "reverse" action exists on R
# - R (toggle_reverse) picks reverse when stopped, W then drives the car
#   backwards, S only brakes, R again returns to drive; it is refused while moving
# - T and Y open one menu with two tabs: switching keeps the game paused, the tab
#   strip shows only while a tuner is open
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/car/reverse_and_tabs.gd

const TIMEOUT_TICKS := 60 * 40

enum Step { BOOT, SETTLE, TO_REVERSE, REVERSING, BRAKE, TO_DRIVE, MOVING, TABS, DONE }

var step := Step.BOOT
var step_start := 0
var tick := 0
var failures: Array[String] = []
var throttle := 0.0
var brake := 0.0
var start_z := 0.0

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")  # an empty road, whatever run_tests.bat or the saved settings say
	change_scene_to_file("res://Game.tscn")

func _drive(c: PlayerCar) -> void:
	c.throttle_input = throttle
	c.brake_input = brake
	c.steering_input = 0.0

func _physics_process(_delta: float) -> bool:
	tick += 1
	var game := current_scene
	if game == null or game.get("player") == null or game.get("game_state") == null:
		return tick > TIMEOUT_TICKS and _end("Game never became ready")
	var p: PlayerCar = game.player
	p.driver = _drive
	var waited := tick - step_start
	match step:
		Step.BOOT:
			_check(InputMap.has_action("reverse"), "no 'reverse' action")
			var is_r := false
			for e in InputMap.action_get_events("reverse"):
				if e is InputEventKey and e.keycode == KEY_R:
					is_r = true
			_check(is_r, "'reverse' is not bound to R")
			_go(Step.SETTLE)
		Step.SETTLE:
			if waited >= 90:
				_check(p.toggle_reverse(), "R should be accepted when stopped")
				_go(Step.TO_REVERSE)
		Step.TO_REVERSE:
			if waited >= 30:
				_check(p.current_gear == -1, "gear should be reverse, is %d" % p.current_gear)
				start_z = p.global_position.z
				throttle = 1.0
				_go(Step.REVERSING)
		Step.REVERSING:
			if waited >= 120:
				_check(p.global_position.z > start_z + 1.0, "W in reverse should drive the car backwards (z %.2f -> %.2f)" % [start_z, p.global_position.z])
				_check(p.current_gear == -1, "should still be in reverse, is %d" % p.current_gear)
				throttle = 0.0
				brake = 1.0
				_go(Step.BRAKE)
		Step.BRAKE:
			if waited >= 150 or p.current_speed() < 0.3:
				_check(p.current_gear == -1, "S while stopped must only brake, gear is %d" % p.current_gear)
				if p.current_speed() < 0.5:
					_check(p.toggle_reverse(), "R should go back to drive when stopped")
					_go(Step.TO_DRIVE)
				elif waited > 400:
					return _end("car never stopped in reverse (%.1f m/s)" % p.current_speed())
		Step.TO_DRIVE:
			if waited >= 30:
				_check(p.current_gear == 1, "R should return to 1st, gear is %d" % p.current_gear)
				brake = 0.0
				throttle = 1.0
				_go(Step.MOVING)
		Step.MOVING:
			if p.current_speed() > 6.0:
				_check(not p.toggle_reverse(), "R must be refused while moving")
				_check(p.current_gear >= 1, "gear changed although R was refused")
				throttle = 0.0
				_go(Step.TABS)
			elif waited > 600:
				return _end("car never got moving forward again")
		Step.TABS:
			var gs: GameState = game.game_state
			var screen: TunerScreen = null
			for c in game.get_children():
				if c is TunerScreen:
					screen = c
			_check(screen != null, "no TunerScreen node")
			if screen != null:
				gs.toggle_tuning()
				_check(gs.state == GameState.State.TUNING and screen.visible and screen.current_page() == "setup", "T should open the Tuner on Setup")
				_check(not screen.auto.is_visible_in_tree(), "T should not show the Mechanic page")
				gs.switch_tuner(GameState.State.AUTOTUNE)
				_check(gs.state == GameState.State.AUTOTUNE and screen.visible and paused, "switching to Auto-Tune should keep the tuner open and the game paused")
				_check(screen.current_page() == "mechanic" and screen.auto.is_visible_in_tree(), "Y should show the Mechanic page")
				gs.toggle_tuning()
				_check(gs.state == GameState.State.TUNING and screen.current_page() == "setup", "T from Mechanic should go to Setup")
				gs.toggle_autotune()
				_check(gs.state == GameState.State.AUTOTUNE and screen.current_page() == "mechanic", "Y from Setup should go to Mechanic")
				gs.toggle_pause()
				_check(gs.state == GameState.State.PLAYING and not screen.visible and not paused, "Esc should close the tuner")
			return _end("")
	return false

func _go(next: Step) -> void:
	step = next
	step_start = tick

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _end(msg: String) -> bool:
	if msg != "":
		failures.append(msg)
	for f in failures:
		printerr("FAIL: ", f)
	print("reverse_and_tabs: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
	return true
