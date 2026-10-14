extends SceneTree

# The driver's feet on the pedals (PersonKit body, 2026-10-09), headless:
# - at rest the right foot's ball is on the throttle pad and the left foot is
#   on the dead pedal (clutch model off), heels on the carpet, soles never
#   under the floor
# - pressing the throttle swings the pad forward and the ball of the foot goes
#   with it (CockpitFrame rotates the pedal by PEDAL_TRAVEL_DEG): the foot
#   moves at least 3 cm forward and stays on the pad
# - braking crosses the right foot to the brake pad within 0.5 s, and it is
#   back over the throttle once the brake is released
# - the legs reach their ankles throughout (leg_gap under 3 cm)
# - the sleeves run from the shoulders to the cuffs in both views: each
#   forearm ends within 2 cm of its hand's wrist
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/view/driver_feet.gd

const TIMEOUT_TICKS := 60 * 30

enum Step { BOOT, REST, THROTTLE, BRAKE, RELEASE, ARMS, DONE }

static func ticks(secs: float) -> int:
	return int(round(secs * Engine.physics_ticks_per_second))

var step := Step.BOOT
var step_start := 0
var tick := 0
var failures: Array[String] = []
var throttle := 0.0
var brake := 0.0
var rest_ball := Vector3.ZERO

func _initialize() -> void:
	AudioSettings.path = "user://test_driver_feet_settings.cfg"
	OS.set_environment("NEON_TRAFFIC", "0")
	change_scene_to_file("res://Game.tscn")

## The handbrake holds the car; the brake pedal is the test's own input.
func _drive(c: PlayerCar) -> void:
	c.throttle_input = throttle
	c.brake_input = brake
	c.handbrake_input = 1.0
	c.steering_input = 0.0

func _physics_process(_delta: float) -> bool:
	tick += 1
	if tick > TIMEOUT_TICKS:
		return _end("timed out in step %s" % Step.keys()[step])
	var game := current_scene
	if game == null or game.get("player") == null:
		return false
	var p: PlayerCar = game.get("player")
	var cam: ChaseCamera = game.get("camera")
	if cam == null or cam.frame == null or cam.frame.driver == null:
		return false
	var frame: CockpitFrame = cam.frame
	var d: DriverModel = frame.driver
	var waited := tick - step_start
	# the soles never go under the carpet, in any step once the driver has been
	# placed (headless, its first process frame can come many physics ticks
	# after the boot; until then the feet sit at the origin)
	if step != Step.BOOT and d.heel_position(1) != Vector3.ZERO:
		for side in [-1, 1]:
			if d.heel_position(side).y < DriverModel.FLOOR_Y - 1e-3:
				_check(false, "foot %d heel under the carpet (y %.3f)" % [side, d.heel_position(side).y])
	match step:
		Step.BOOT:
			p.driver = _drive
			cam.shake_enabled = false
			cam.set_view(ChaseCamera.View.COCKPIT)
			_go(Step.REST)
		Step.REST:
			if waited == ticks(1.0):
				var ball := d.ball_position(1)
				_check(ball.distance_to(d.pad_ball("throttle")) < 0.005, "at rest the right foot is on the throttle pad (%.3f m off)" % ball.distance_to(d.pad_ball("throttle")))
				_check(d.ball_position(-1).distance_to(DriverModel.DEAD_BALL) < 0.005, "with the clutch model off the left foot rests on the dead pedal")
				for side in [-1, 1]:
					_check(absf(d.heel_position(side).y - DriverModel.FLOOR_Y) < 1e-3, "foot %d: the heel is on the carpet" % side)
					_check(d.leg_gap(side) < 0.03, "leg %d reaches its ankle (short by %.3f)" % [side, d.leg_gap(side)])
					_check(d.heel_position(side).z > ball.z, "foot %d: the heel is behind the ball" % side)
				rest_ball = ball
				throttle = 1.0
				brake = 0.0
				_go(Step.THROTTLE)
		Step.THROTTLE:
			if waited == ticks(1.0):
				var ball := d.ball_position(1)
				var pad := d.pad_ball("throttle")
				var pedal := (frame.pedals.throttle as Node3D).rotation_degrees.x
				print("throttle pressed: pedal %.1f deg, ball moved %.3f m forward" % [pedal, rest_ball.z - ball.z])
				_check(pedal > CockpitFrame.PEDAL_TRAVEL_DEG * 0.8, "the throttle pedal travels with the input (%.1f deg)" % pedal)
				_check(ball.distance_to(pad) < 0.005, "the right foot rides the pad as it travels (%.3f m off)" % ball.distance_to(pad))
				_check(rest_ball.z - ball.z > 0.03, "the foot follows the pad forward (%.3f m)" % (rest_ball.z - ball.z))
				_check(d.leg_gap(1) < 0.03, "the right leg still reaches (short by %.3f)" % d.leg_gap(1))
				throttle = 0.0
				brake = 1.0
				_go(Step.BRAKE)
		Step.BRAKE:
			if waited == ticks(0.5):
				var ball := d.ball_position(1)
				var pad := d.pad_ball("brake")
				_check(ball.distance_to(pad) < 0.01, "braking: the right foot is on the brake pad within 0.5 s (%.3f m off)" % ball.distance_to(pad))
				_check(d.leg_gap(1) < 0.03, "the right leg reaches the brake (short by %.3f)" % d.leg_gap(1))
				brake = 0.0
				_go(Step.RELEASE)
		Step.RELEASE:
			if waited == ticks(0.6):
				var ball := d.ball_position(1)
				_check(ball.distance_to(d.pad_ball("throttle")) < 0.01, "brake released: the right foot is back over the throttle (%.3f m off)" % ball.distance_to(d.pad_ball("throttle")))
				cam.set_view(ChaseCamera.View.CHASE)
				_go(Step.ARMS)
		Step.ARMS:
			if waited == ticks(0.3):
				for side in [-1, 1]:
					var n := "L" if side < 0 else "R"
					var fore := d.get_node("Forearm" + n) as Node3D
					var upper := d.get_node("UpperArm" + n) as Node3D
					_check(fore.visible and upper.visible, "sleeve %s shows" % n)
					var cuff := fore.transform * Vector3(0.0, d.body.lengths.arm_lower, 0.0)
					var gap := cuff.distance_to(d.wrist_position(side))
					_check(gap < 0.02, "forearm %s ends at the cuff (%.3f m off)" % [n, gap])
					var elbow := upper.transform * Vector3(0.0, d.body.lengths.arm_upper, 0.0)
					_check(elbow.distance_to(fore.position) < 0.005, "upper arm %s meets the forearm at the elbow" % n)
				return _end("")
	return false

func _go(next: Step) -> void:
	step = next
	step_start = tick

func _check(ok: bool, msg: String) -> void:
	if not ok and not failures.has(msg):
		failures.append(msg)

func _end(msg: String) -> bool:
	if msg != "":
		failures.append(msg)
	for f in failures:
		printerr("FAIL: ", f)
	print("driver_feet: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
	return true
