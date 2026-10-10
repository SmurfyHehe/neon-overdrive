extends SceneTree

# Shared base for the cockpit camera-upgrade tests (C1/C2): boots Game.tscn
# with no traffic, freezes the player car where it stands, switches to the
# cockpit view and lets the test pose the body (roll/pitch) and poke the
# camera. A frozen, posed car makes the camera's maths exact, so the checks are
# on the camera and not on how the sim happens to be rolling that second.
#
# Subclasses `extends "res://tests/view/parked_cockpit.gd"`, set `name_` and
# override `_step(n)` (n = ticks since boot finished); return true when done
# after calling `_end()`. Exit code 1 on failure.

const SETTLE_TICKS := 8   # frames for the camera to catch up after a pose change
const TIMEOUT_TICKS := 60 * 40

class ErrorCounter extends Logger:
	var errors: Array[String] = []
	var _lock := Mutex.new()
	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_lock.lock()
		errors.append("%s (%s:%d in %s)" % [rationale if rationale != "" else code, file, line, function])
		_lock.unlock()
	func _log_message(_message: String, _error: bool) -> void:
		pass

var name_ := "parked_cockpit"
## false: leave the car free (tests that drive it); the camera is still switched to the cockpit.
var park := true
var tick := 0
var boot_tick := -1
var failures: Array[String] = []
var logger := ErrorCounter.new()
var p: PlayerCar
var cam: ChaseCamera
var park_basis := Basis.IDENTITY
var park_origin := Vector3.ZERO

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	ExhaustTune.save_path = "user://autotune/test_%s_exhaust.json" % name_
	OS.add_logger(logger)
	change_scene_to_file("res://Game.tscn")

## Override to drive the car (park = false); the default holds still.
func _drive(c: PlayerCar) -> void:
	c.throttle_input = 0.0
	c.brake_input = 0.0
	c.handbrake_input = 0.0
	c.steering_input = 0.0

func _physics_process(_delta: float) -> bool:
	tick += 1
	var game := current_scene
	if game == null or game.get("player") == null or game.get("camera") == null:
		return tick > TIMEOUT_TICKS and _end("Game never became ready")
	p = game.player
	cam = game.camera
	p.driver = _drive
	if boot_tick < 0:
		if tick < 40:
			return false   # let the car settle on its wheels
		boot_tick = tick
		cam.shake_enabled = false
		cam.set_view(ChaseCamera.View.COCKPIT)
		park_basis = p.global_transform.basis
		park_origin = p.global_transform.origin
		if park:
			p.freeze = true
			pose(0.0, 0.0)
	if p.freeze:
		p.linear_velocity = Vector3.ZERO
		p.angular_velocity = Vector3.ZERO
	return _step(tick - boot_tick)

## Body roll about its forward axis and pitch about its right axis (degrees),
## on the parked pose. + roll = about +z (right side down for -z forward is
## about -z; the sign only has to be consistent).
func pose(roll_deg: float, pitch_deg: float) -> void:
	var b := park_basis * Basis.from_euler(Vector3(deg_to_rad(pitch_deg), 0.0, deg_to_rad(roll_deg)), EULER_ORDER_YXZ)
	p.global_transform = Transform3D(b, park_origin)
	p.linear_velocity = Vector3.ZERO
	p.angular_velocity = Vector3.ZERO
	p.reset_physics_interpolation()

## Camera roll / pitch against the world (degrees), the same decomposition the
## camera uses to level the body.
static func tilt_of(b: Basis) -> Vector2:
	var e := b.orthonormalized().get_euler(EULER_ORDER_YXZ)
	return Vector2(rad_to_deg(e.x), rad_to_deg(e.z))   # (pitch, roll)

func _step(_n: int) -> bool:
	return _end("override _step")

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _end(msg: String) -> bool:
	if msg != "":
		failures.append(msg)
	_check(logger.errors.is_empty(), "engine errors: %s" % [logger.errors.slice(0, 5)])
	for f in failures:
		printerr("FAIL: ", f)
	print("%s: %s" % [name_, "PASS" if failures.is_empty() else "FAIL"])
	quit(0 if failures.is_empty() else 1)
	return true
