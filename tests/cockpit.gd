extends SceneTree

# Cockpit camera and perspective audio (Phase C, 2026-10-05), headless and silent:
# - F is bound to camera_view; set_view switches the camera between the chase rig
#   and the driver's eye
# - in the cockpit the camera sits at the car-local eye point, faces the same way as
#   the car, the body is kept off the cockpit camera (it moves to the mirror-only
#   render layer, see CockpitFrame), the interior is shown, and the wheel turns
#   with the steering
# - the audio eases to cabin muffling (low-pass cutoffs down on Engine, Tires, World)
#   and a louder, clearer radio, and back out in the chase view
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/cockpit.gd

const TIMEOUT_TICKS := 60 * 30

enum Step { BOOT, CHASE_CHECK, COCKPIT, BLEND_IN, BACK, BLEND_OUT, DONE }

var step := Step.BOOT
var step_start := 0
var tick := 0
var failures: Array[String] = []
var steer := 0.0
var chase_music_db := 0.0

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")  # an empty road, whatever run_tests.bat or the saved settings say
	change_scene_to_file("res://Game.tscn")

func _drive(c: PlayerCar) -> void:
	c.throttle_input = 0.0
	c.brake_input = 0.0
	c.steering_input = steer

func _physics_process(_delta: float) -> bool:
	tick += 1
	var game := current_scene
	if game == null or game.get("player") == null or game.get("camera") == null:
		return tick > TIMEOUT_TICKS and _end("Game never became ready")
	var p: PlayerCar = game.player
	var cam: ChaseCamera = game.camera
	p.driver = _drive
	var waited := tick - step_start
	match step:
		Step.BOOT:
			var bound := false
			for e in InputMap.action_get_events("camera_view"):
				if e is InputEventKey and e.keycode == KEY_F:
					bound = true
			_check(bound, "camera_view should be bound to F")
			_check(cam.view == ChaseCamera.View.CHASE, "the game should start in the chase view")
			_go(Step.CHASE_CHECK)
		Step.CHASE_CHECK:
			if waited == 30:
				_check(cam.perspective.cutoff(&"Engine") > 15000.0, "chase view should leave the Engine bus open (%.0f Hz)" % cam.perspective.cutoff(&"Engine"))
				chase_music_db = AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Music"))
				_check(not cam.frame.visible and not cam.frame.body_hidden_from_camera(), "chase view shows the body and no frame")
				cam.set_view(ChaseCamera.View.COCKPIT)
				steer = 0.8
				_go(Step.COCKPIT)
		Step.COCKPIT:
			if waited == 20:
				var xf := p.get_global_transform_interpolated()
				var eye := xf * ChaseCamera.COCKPIT_EYE
				_check(cam.global_position.distance_to(eye) < 0.2, "the cockpit camera should sit at the eye point (%.2f m away)" % cam.global_position.distance_to(eye))
				var fwd := -cam.global_basis.z
				var car_fwd := -xf.basis.z
				_check(fwd.dot(car_fwd) > 0.99, "the cockpit camera should face where the car faces (dot %.3f)" % fwd.dot(car_fwd))
				_check(cam.frame.body_hidden_from_camera(), "the body should be off the cockpit camera in the cockpit")
				_check(cam.frame.visible, "the cockpit frame should be shown")
				_check(absf(cam.frame.wheel.angle) > 0.3, "the wheel should turn with the steering (%.2f)" % cam.frame.wheel.angle)
				_go(Step.BLEND_IN)
		Step.BLEND_IN:
			if waited == 40:
				var e := cam.perspective.cutoff(&"Engine")
				var t := cam.perspective.cutoff(&"Tires")
				var w := cam.perspective.cutoff(&"World")
				_check(e < 4000.0 and t < 3200.0 and w < 2200.0, "the cabin should muffle: engine %.0f tires %.0f world %.0f Hz" % [e, t, w])
				var db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Music"))
				_check(db > chase_music_db + 3.0, "the radio should be clearer inside (%.1f vs %.1f dB)" % [db, chase_music_db])
				cam.set_view(ChaseCamera.View.CHASE)
				_go(Step.BACK)
		Step.BACK:
			if waited == 40:
				_check(cam.perspective.cutoff(&"Engine") > 15000.0, "back in the chase view the Engine bus should open again (%.0f Hz)" % cam.perspective.cutoff(&"Engine"))
				_check(not cam.frame.body_hidden_from_camera() and not cam.frame.visible, "chase view should show the body and hide the frame again")
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
	print("cockpit: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
	return true
