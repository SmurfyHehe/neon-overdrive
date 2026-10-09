extends SceneTree

# Mirror glance, off-screen mirror skip and blind-spot dots (2026-10-07),
# headless and silent:
# - "look_glance" is bound (V) and listed on the Controls page
# - cockpit view, straight ahead, FOV 62: the rearview and left door mirror
#   glass are on screen, the right door mirror is not, and it is never queued
#   to render
# - tap V holding right: the head turns to the right door mirror (whole glass
#   on screen), it is the focused mirror at twice the resolution; steering left
#   afterwards does not swing the head across
# - tap V with no steering: back to straight ahead, focus cleared
# - tap V holding left: the head turns to the left door mirror
# - a quick double tap (holding right) resets to straight ahead
# - chase view: the glance key does nothing
# - blind spot: a same-way car in the right lane, just behind, lights only the
#   right dot; on the left, only the left dot; a car straight behind in our
#   lane or an oncoming car alongside lights neither
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/view/mirror_glance.gd

const TIMEOUT_TICKS := 60 * 30
const SETTLE := 45   # ticks for the head to finish turning; also past the 0.3 s double-tap window
const Harness := preload("res://tests/traffic/traffic_harness.gd")

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

enum Step { BOOT, STRAIGHT, TAP_RIGHT, RIGHT, AHEAD, LEFT, DOUBLE, CHASE,
	SPOT_RIGHT, SPOT_LEFT, SPOT_BEHIND, SPOT_ONCOMING, DONE }

var step := Step.BOOT
var step_start := 0
var tick := 0
var failures: Array[String] = []
var logger := ErrorCounter.new()
var game: Node
var right_queued := 0
var tap_release := -1

func _initialize() -> void:
	ExhaustTune.save_path = "user://autotune/test_mirror_glance_exhaust.json"
	OS.add_logger(logger)
	game = Harness.boot(self, 2, 300.0, 7)

func _drive(c: PlayerCar) -> void:
	c.throttle_input = 0.0
	c.brake_input = 0.0
	c.handbrake_input = 0.0
	c.steering_input = 0.0

static func _hud(g: Node) -> Hud:
	for n in g.get_children():
		if n is Hud:
			return n
	return null

## Share of a glass quad's 5x5 sample grid inside the camera's view, 0..1.
static func _on_screen(cam: Camera3D, glass: MeshInstance3D) -> float:
	var half := (glass.mesh as QuadMesh).size * 0.5
	var inside := 0
	for i in 5:
		for j in 5:
			var p := glass.global_transform * Vector3(lerpf(-half.x, half.x, i / 4.0), lerpf(-half.y, half.y, j / 4.0), 0.0)
			if cam.is_position_in_frustum(p):
				inside += 1
	return inside / 25.0

## One tap of the real key on this tick (released a tick later).
func _tap() -> void:
	Input.action_press("look_glance")
	tap_release = tick + 1

## Places traffic car 0 at (dx, dz) from the player (+x right, +z behind),
## going our way unless `oncoming`; car 1 far away.
func _put_car(p: PlayerCar, dx: float, dz: float, oncoming: bool) -> void:
	var tm: TrafficManager = game.traffic
	var c: TrafficCar = tm.cars[0]
	c.place(p.global_position.x + dx, 1.0 if oncoming else -1.0, p.global_position.z + dz, TrafficManager.REST_Y, 0.0)
	var other: TrafficCar = tm.cars[1]
	other.place(p.global_position.x, -1.0, p.global_position.z - 200.0, TrafficManager.REST_Y, 0.0)

func _physics_process(_delta: float) -> bool:
	tick += 1
	if tick == tap_release:
		Input.action_release("look_glance")
	if game == null or game.get("player") == null or game.get("camera") == null or game.get("traffic") == null:
		return tick > TIMEOUT_TICKS and _end("Game never became ready")
	var p: PlayerCar = game.player
	var cam: ChaseCamera = game.camera
	var hud := _hud(game)
	p.driver = _drive
	var waited := tick - step_start
	var m: CockpitMirrors = cam.frame.mirrors if cam.frame != null else null
	if m != null and m.views[2].vp.render_target_update_mode != SubViewport.UPDATE_DISABLED and step == Step.STRAIGHT:
		right_queued += 1
	match step:
		Step.BOOT:
			if waited < 5:
				return false
			_check(m != null, "the cockpit has mirrors")
			if m == null:
				return _end("")
			_check(InputMap.has_action("look_glance"), "look_glance is an input action")
			var keys := []
			for ev in InputMap.action_get_events("look_glance"):
				if ev is InputEventKey:
					keys.append((ev as InputEventKey).keycode)
			_check(keys.has(KEY_V), "look_glance is on V (%s)" % [keys])
			var listed := false
			for group in PauseMenu.controls_groups():
				for row in group[1]:
					if row[0] == "look_glance":
						listed = true
			_check(listed, "look_glance is on the Controls page")
			cam.shake_enabled = false
			root.size = Vector2i(1280, 720)   # headless defaults to 64x64; the angles assume 16:9
			ViewSettings.set_cockpit_fov(ViewSettings.COCKPIT_FOV_DEFAULT)
			_put_car(p, 0.0, 200.0, false)
			cam.set_view(ChaseCamera.View.COCKPIT)
			_go(Step.STRAIGHT)
		Step.STRAIGHT:
			if waited == SETTLE:
				var rear := _on_screen(cam, m.views[0].quad)
				var left := _on_screen(cam, m.views[1].quad)
				var right := _on_screen(cam, m.views[2].quad)
				print("straight ahead, FOV %.0f: rearview %.0f%%, left %.0f%%, right %.0f%% on screen" % [cam.fov, rear * 100, left * 100, right * 100])
				_check(rear > 0.9, "the rearview is on screen looking ahead (%.2f)" % rear)
				_check(left > 0.5, "the left door mirror is on screen looking ahead (%.2f)" % left)
				_check(right == 0.0 and not CockpitMirrors.glass_on_screen(cam, m.views[2].quad), "the right door mirror is off screen looking ahead (%.2f)" % right)
				_check(right_queued == 0, "an off-screen mirror is never queued to render (%d ticks)" % right_queued)
				Input.action_press("steer_right")
				_tap()
				_go(Step.TAP_RIGHT)
		Step.TAP_RIGHT:
			if waited == 2:
				Input.action_release("steer_right")
				Input.action_press("steer_left")   # a correction mid-glance
			if waited == SETTLE:
				var right := _on_screen(cam, m.views[2].quad)
				var want := cam.glance_angles(1)
				print("glance right: yaw %.1f (target %.1f), pitch %.1f, right mirror %.0f%% on screen" % [cam.glance_yaw, want.x, cam.glance_pitch, right * 100])
				_check(cam.glance == 1, "tap V holding right glances right (%d)" % cam.glance)
				_check(want.x < -45.0 and absf(cam.glance_yaw - want.x) < 1.0, "the head has turned to the right mirror (%.1f of %.1f)" % [cam.glance_yaw, want.x])
				_check(right >= 0.9, "the right door mirror is on screen (%.2f)" % right)
				_check(m.focus == 1, "the right mirror is the focused one (%d)" % m.focus)
				_check(m.views[2].vp.size == CockpitMirrors._scaled(CockpitMirrors.SIDE_SIZE) * 2, "and renders at twice the size (%s)" % m.views[2].vp.size)
				_go(Step.RIGHT)
		Step.RIGHT:
			if waited == 1:
				Input.action_release("steer_left")
				_check(cam.glance == 1, "steering left after the tap keeps the head right (%d)" % cam.glance)
			if waited == 40:   # past the double-tap window
				_tap()
				_go(Step.AHEAD)
		Step.AHEAD:
			if waited == SETTLE:
				_check(cam.glance == 0 and absf(cam.glance_yaw) < 1.0, "tap V with no steering looks ahead again (glance %d, yaw %.1f)" % [cam.glance, cam.glance_yaw])
				_check(cam.glance_lean.length() < 0.005, "the lean comes back (%s)" % cam.glance_lean)
				_check(m.focus == 0 and m.views[2].vp.size == CockpitMirrors._scaled(CockpitMirrors.SIDE_SIZE), "no focus, normal size (%d, %s)" % [m.focus, m.views[2].vp.size])
				Input.action_press("steer_left")
				_tap()
				_go(Step.LEFT)
		Step.LEFT:
			if waited == 2:
				Input.action_release("steer_left")
			if waited == SETTLE:
				var left := _on_screen(cam, m.views[1].quad)
				print("glance left: yaw %.1f, left mirror %.0f%% on screen" % [cam.glance_yaw, left * 100])
				_check(cam.glance == -1 and cam.glance_yaw > 30.0, "tap V holding left glances left (glance %d, yaw %.1f)" % [cam.glance, cam.glance_yaw])
				_check(left >= 0.9, "the left door mirror is on screen (%.2f)" % left)
				Input.action_press("steer_right")
				_tap()
				_go(Step.DOUBLE)
		Step.DOUBLE:
			if waited == 2:   # the camera reads the tap on the tick after the press
				_check(cam.glance == 1, "the first tap of the double tap swaps sides (%d)" % cam.glance)
			if waited == 6:   # 0.05 s later
				_tap()
			if waited == SETTLE:
				Input.action_release("steer_right")
				_check(cam.glance == 0 and absf(cam.glance_yaw) < 1.0, "a double tap resets to straight ahead (glance %d, yaw %.1f)" % [cam.glance, cam.glance_yaw])
				cam.set_view(ChaseCamera.View.CHASE)
				Input.action_press("steer_right")
				_tap()
				_go(Step.CHASE)
		Step.CHASE:
			if waited == 10:
				Input.action_release("steer_right")
				_check(cam.glance == 0, "the chase view ignores the glance key (%d)" % cam.glance)
				cam.set_view(ChaseCamera.View.COCKPIT)
				_put_car(p, 3.2, 3.0, false)
				_go(Step.SPOT_RIGHT)
		Step.SPOT_RIGHT:
			if waited == 40:
				print("blind spot right: threat %s, dots %s/%s" % [hud.side_threat, m.dots[0].visible, m.dots[1].visible])
				_check(m.dots[1].visible and not m.dots[0].visible, "a car in the right lane just behind lights the right dot only (%s)" % [hud.side_threat])
				_put_car(p, -3.2, 1.0, false)
				_go(Step.SPOT_LEFT)
		Step.SPOT_LEFT:
			if waited == 40:
				_check(m.dots[0].visible and not m.dots[1].visible, "a car alongside on the left lights the left dot only (%s)" % [hud.side_threat])
				_put_car(p, 0.0, 6.0, false)
				_go(Step.SPOT_BEHIND)
		Step.SPOT_BEHIND:
			if waited == 40:
				_check(not m.dots[0].visible and not m.dots[1].visible, "a car straight behind in our lane lights no dot (%s)" % [hud.side_threat])
				_put_car(p, 3.2, 1.0, true)
				_go(Step.SPOT_ONCOMING)
		Step.SPOT_ONCOMING:
			if waited == 40:
				_check(hud.side_threat_now() == [0.0, 0.0], "an oncoming car alongside gives no cue (%s)" % [hud.side_threat_now()])
				_check(logger.errors.is_empty(), "engine errors: %s" % [logger.errors.slice(0, 5)])
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
	print("mirror_glance: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
	return true
