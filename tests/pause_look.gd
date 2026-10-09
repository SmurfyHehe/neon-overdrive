extends SceneTree

# The pause look (menus A-list, 2026-10-08), on the real Game.tscn:
# - pausing freezes the car where it is (same tick) and switches to the orbit
#   camera, which then circles the car at a steady distance
# - the blur layer shows while paused; the radio is muffled, not muted; the
#   engine bus is muted
# - resuming gives the game camera back and takes the muffle and blur off
# - the Tuner keeps the old behaviour: no orbit, radio muted
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/pause_look.gd

const TIMEOUT_TICKS := 600

enum Step { BOOT, DRIVE, ORBIT, RESUME, TUNER }

var step := Step.BOOT
var step_start := 0
var tick := 0
var failures: Array[String] = []
var look: PauseLook
var frozen_at := Vector3.ZERO
var orbit_start := Vector3.ZERO

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	change_scene_to_file("res://Game.tscn")

func _physics_process(_delta: float) -> bool:
	tick += 1
	var game := current_scene
	var waited := tick - step_start
	match step:
		Step.BOOT:
			if game != null and game.get("game_state") != null and game.get("player") != null:
				for c in game.get_children():
					if c is PauseLook:
						look = c
				if look == null:
					return _abort("Game has no PauseLook")
				Input.action_press("accelerate")
				_go(Step.DRIVE)
			elif waited > TIMEOUT_TICKS:
				return _abort("Game.tscn never became ready")
		Step.DRIVE:
			if game.player.linear_velocity.length() > 5.0:
				Input.action_release("accelerate")
				game.game_state.pause()
				frozen_at = game.player.global_position
				_check(look.is_orbiting(), "pausing should switch to the orbit camera")
				_check(look.blur_layer.visible, "pausing should show the blur")
				_check(look.muffled(), "pausing should muffle the radio")
				var mb := AudioServer.get_bus_index(&"Music")
				var eb := AudioServer.get_bus_index(&"Engine")
				_check(not AudioServer.is_bus_mute(mb), "the radio should keep playing while paused")
				_check(AudioServer.is_bus_mute(eb), "the engine should be cut while paused")
				orbit_start = look.orbit.global_position
				_go(Step.ORBIT)
			elif waited > TIMEOUT_TICKS:
				return _abort("car never got going")
		Step.ORBIT:
			if waited >= 240:  # 4 s at the test's 60 Hz
				_check(game.player.global_position.distance_to(frozen_at) < 0.001, "the car must stay frozen")
				var flat := Vector2(look.orbit.global_position.x - frozen_at.x, look.orbit.global_position.z - frozen_at.z)
				_check(absf(flat.length() - PauseLook.ORBIT_RADIUS) < 0.3, "orbit should settle at its radius (%.2f)" % flat.length())
				_check(look.orbit.global_position.distance_to(orbit_start) > 0.5, "the camera should be circling")
				game.game_state.resume()
				_check(not look.is_orbiting() and game.camera.current, "resume should give the game camera back")
				_check(not look.blur_layer.visible and not look.muffled(), "resume should clear the blur and muffle")
				_go(Step.RESUME)
		Step.RESUME:
			if waited >= 5:
				game.game_state.toggle_tuning()
				_check(not look.is_orbiting(), "the Tuner should not orbit")
				_check(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Music")), "the Tuner should mute the radio")
				game.game_state.close_tuning()
				return _finish()
	return false

func _go(next: Step) -> void:
	step = next
	step_start = tick

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _finish() -> bool:
	for f in failures:
		printerr("FAIL: ", f)
	print("pause_look: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
	return true

func _abort(msg: String) -> bool:
	failures.append("%s (stuck in step %s)" % [msg, Step.keys()[step]])
	return _finish()
