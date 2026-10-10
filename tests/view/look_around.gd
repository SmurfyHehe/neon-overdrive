extends SceneTree

# Look around with the arrow keys, off-screen mirror skip and blind-spot dots
# (2026-10-09; replaces the V mirror glance), headless and silent:
# - look_left/right/up/down are bound to the arrow keys and listed on the
#   Controls page; the arrows no longer steer or drive; look_glance is gone
# - cockpit view, straight ahead, FOV 62: the rearview and left door mirror
#   glass are on screen, the right door mirror is not, and it is never queued
#   to render
# - hold Right: the head turns right until the right door mirror is on screen,
#   it is the focused mirror at twice the resolution; the car does not steer
# - release: the head eases back straight ahead, focus cleared
# - hold Left: the head turns left; hold Up / Down: it tilts up / down, capped
# - chase view: the arrow keys do nothing to the camera
# - blind spot: a same-way car in the right lane, just behind, lights only the
#   right dot; on the left, only the left dot; a car straight behind in our
#   lane or an oncoming car alongside lights neither
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/view/look_around.gd

const TIMEOUT_TICKS := 60 * 30
const SETTLE := 60   # ticks for the head to finish turning
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

enum Step { BOOT, STRAIGHT, LOOK_RIGHT, BACK, LOOK_LEFT, UP, DOWN, CHASE,
	SPOT_RIGHT, SPOT_LEFT, SPOT_BEHIND, SPOT_ONCOMING, DONE }

var step := Step.BOOT
var step_start := 0
var tick := 0
var failures: Array[String] = []
var logger := ErrorCounter.new()
var game: Node
var right_queued := 0
var seen_right := -1.0
var seen_left := -1.0
var seen_focus := 0
var seen_size := Vector2i.ZERO

func _initialize() -> void:
	ExhaustTune.save_path = "user://autotune/test_look_around_exhaust.json"
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
			_check(not InputMap.has_action("look_glance"), "the V mirror glance is gone")
			for pair in [["look_left", KEY_LEFT], ["look_right", KEY_RIGHT], ["look_up", KEY_UP], ["look_down", KEY_DOWN]]:
				var keys := []
				for ev in InputMap.action_get_events(pair[0]):
					if ev is InputEventKey:
						keys.append((ev as InputEventKey).keycode)
				_check(keys.has(pair[1]), "%s is on the arrow key (%s)" % [pair[0], keys])
				var listed := false
				for group in SettingsScreen.controls_groups():
					for row in group[1]:
						if row[0] == pair[0]:
							listed = true
				_check(listed, "%s is on the Controls page" % pair[0])
			for act in ["accelerate", "brake", "steer_left", "steer_right"]:
				for ev in InputMap.action_get_events(act):
					if ev is InputEventKey:
						var k := (ev as InputEventKey).keycode
						_check(k != KEY_LEFT and k != KEY_RIGHT and k != KEY_UP and k != KEY_DOWN, "%s is not on an arrow key" % act)
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
				Input.action_press("look_right")
				_go(Step.LOOK_RIGHT)
		Step.LOOK_RIGHT:
			# The head sweeps past the mirror (58 degrees right) on its way to the
			# full turn, so sample the mirror once, as the yaw crosses 55 degrees.
			if seen_right < 0.0 and cam.look_yaw < -55.0:
				seen_right = _on_screen(cam, m.views[2].quad)
				seen_focus = m.focus
				seen_size = m.views[2].vp.size
			if waited == SETTLE:
				print("look right: yaw %.1f, right mirror %.0f%% on screen at 55 deg" % [cam.look_yaw, seen_right * 100])
				_check(cam.look_yaw < -90.0, "holding Right turns the head right (%.1f)" % cam.look_yaw)
				_check(seen_right >= 0.9, "turning right, the right door mirror comes on screen (%.2f)" % seen_right)
				_check(seen_focus == 1, "and is the focused mirror (%d)" % seen_focus)
				_check(seen_size == CockpitMirrors._scaled(CockpitMirrors.SIDE_SIZE) * 2, "rendering at twice the size (%s)" % seen_size)
				_check(Input.get_axis("steer_left", "steer_right") == 0.0, "looking right does not steer")
				Input.action_release("look_right")
				_go(Step.BACK)
		Step.BACK:
			if waited == SETTLE:
				_check(absf(cam.look_yaw) < 1.0 and absf(cam.look_pitch) < 1.0, "release: the head is straight ahead again (%.1f, %.1f)" % [cam.look_yaw, cam.look_pitch])
				_check(m.focus == 0 and m.views[2].vp.size == CockpitMirrors._scaled(CockpitMirrors.SIDE_SIZE), "no focus, normal size (%d, %s)" % [m.focus, m.views[2].vp.size])
				Input.action_press("look_left")
				_go(Step.LOOK_LEFT)
		Step.LOOK_LEFT:
			if seen_left < 0.0 and cam.look_yaw > 55.0:
				seen_left = _on_screen(cam, m.views[1].quad)
				seen_focus = m.focus
			if waited == SETTLE:
				print("look left: yaw %.1f, left mirror %.0f%% on screen at 55 deg" % [cam.look_yaw, seen_left * 100])
				_check(cam.look_yaw > 90.0, "holding Left turns the head left (%.1f)" % cam.look_yaw)
				_check(seen_left >= 0.9, "turning left, the left door mirror comes on screen (%.2f)" % seen_left)
				_check(seen_focus == -1, "and is the focused mirror (%d)" % seen_focus)
				Input.action_release("look_left")
				Input.action_press("look_up")
				_go(Step.UP)
		Step.UP:
			if waited == SETTLE:
				_check(absf(cam.look_yaw) < 1.0, "yaw came back (%.1f)" % cam.look_yaw)
				_check(cam.look_pitch > 20.0 and cam.look_pitch <= ChaseCamera.LOOK_PITCH_UP + 0.01, "holding Up tilts the head up, capped (%.1f)" % cam.look_pitch)
				Input.action_release("look_up")
				Input.action_press("look_down")
				_go(Step.DOWN)
		Step.DOWN:
			if waited == SETTLE:
				_check(cam.look_pitch < -15.0 and cam.look_pitch >= -ChaseCamera.LOOK_PITCH_DOWN - 0.01, "holding Down tilts the head down, capped (%.1f)" % cam.look_pitch)
				Input.action_release("look_down")
				cam.set_view(ChaseCamera.View.CHASE)
				Input.action_press("look_right")
				_go(Step.CHASE)
		Step.CHASE:
			if waited == 10:
				Input.action_release("look_right")
				_check(absf(cam.look_yaw) < 0.01, "the chase view ignores the arrow keys (%.1f)" % cam.look_yaw)
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
	print("look_around: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
	return true
