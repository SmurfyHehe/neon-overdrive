extends SceneTree

# Look-back key and the proximity cue (2026-10-06), headless and silent:
# - "look_back" is bound (B) and listed on the Controls page
# - chase view: holding it puts the camera in front of the car looking back
#   (the same swing as reversing); releasing it returns the camera behind
# - cockpit view: holding it turns the head to face the car's rear with an
#   ease (part way after a few ticks, not a snap), leaning the eye to the
#   cabin centreline so the driver's own headrest is outside the view;
#   releasing it eases back to the eye, facing forward again
# - proximity cue: a traffic car placed 6 m behind in the lane raises
#   Hud.rear_threat toward 1, warms the strip frame to sodium and thickens
#   it, and warms the cockpit rearview glass; a car 40 m back, or an oncoming
#   car close behind, gives no cue; moved away, the cue decays to 0
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/view/look_back.gd

const TIMEOUT_TICKS := 60 * 30
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

enum Step { BOOT, CHASE_BACK, CHASE_FWD, COCKPIT_BACK, COCKPIT_FWD, CUE_NEAR, CUE_FAR, CUE_ONCOMING, CUE_GONE, DONE }

var step := Step.BOOT
var step_start := 0
var tick := 0
var failures: Array[String] = []
var logger := ErrorCounter.new()
var game: Node
var lane_x := 0.0
var saw_mid_turn := false   # a tick where the cockpit head was part way round

func _initialize() -> void:
	ExhaustTune.save_path = "user://autotune/test_look_back_exhaust.json"
	OS.add_logger(logger)
	game = Harness.boot(self, 2, 300.0, 7)

func _drive(c: PlayerCar) -> void:
	c.throttle_input = 0.0
	c.brake_input = 0.0
	c.handbrake_input = 0.0
	c.steering_input = 0.0

## The camera's forward against the car's forward, world space (+1 same way).
static func _facing(p: PlayerCar, cam: Camera3D) -> float:
	return (-cam.global_transform.basis.z).dot(-p.global_transform.basis.z)

static func _hud(g: Node) -> Hud:
	for n in g.get_children():
		if n is Hud:
			return n
	return null

func _put_car_behind(p: PlayerCar, dist: float, oncoming: bool) -> void:
	var tm: TrafficManager = game.traffic
	var c: TrafficCar = tm.cars[0]
	var x := lane_x if not oncoming else lane_x + 0.5
	c.place(x, 1.0 if oncoming else -1.0, p.global_position.z + dist, c.rest_y, 0.0)
	var other: TrafficCar = tm.cars[1]
	other.place(lane_x, -1.0, p.global_position.z - 200.0, other.rest_y, 0.0)

func _physics_process(_delta: float) -> bool:
	tick += 1
	if game == null or game.get("player") == null or game.get("camera") == null or game.get("traffic") == null:
		return tick > TIMEOUT_TICKS and _end("Game never became ready")
	var p: PlayerCar = game.player
	var cam: ChaseCamera = game.camera
	var hud := _hud(game)
	p.driver = _drive
	var waited := tick - step_start
	match step:
		Step.BOOT:
			if waited < 5:
				return false
			lane_x = p.global_position.x
			_check(InputMap.has_action("look_back"), "look_back is an input action")
			var keys := []
			for ev in InputMap.action_get_events("look_back"):
				if ev is InputEventKey:
					keys.append((ev as InputEventKey).keycode)
			_check(keys.has(KEY_B), "look_back is on B (%s)" % [keys])
			var listed := false
			for group in PauseMenu.controls_groups():
				for row in group[1]:
					if row[0] == "look_back":
						listed = true
			_check(listed, "look_back is on the Controls page")
			_check(hud != null, "the game has a Hud")
			cam.mode = 0   # snap camera: no swing to wait for
			cam.shake_enabled = false
			_put_car_behind(p, 200.0, false)
			Input.action_press("look_back")
			_go(Step.CHASE_BACK)
		Step.CHASE_BACK:
			if waited == 6:
				_check(cam.look_back, "the camera reads the held key")
				var rel := p.global_transform.affine_inverse() * cam.global_position
				_check(rel.z < -2.0, "holding look back in the chase view puts the camera in front of the car (z %.1f)" % rel.z)
				_check(_facing(p, cam) < -0.5, "and it looks back at the car (facing %.2f)" % _facing(p, cam))
				Input.action_release("look_back")
				_go(Step.CHASE_FWD)
		Step.CHASE_FWD:
			if waited == 6:
				var rel := p.global_transform.affine_inverse() * cam.global_position
				_check(not cam.look_back and rel.z > 2.0 and _facing(p, cam) > 0.5, "released, the chase camera is behind the car facing forward again (z %.1f, facing %.2f)" % [rel.z, _facing(p, cam)])
				cam.set_view(ChaseCamera.View.COCKPIT)
				Input.action_press("look_back")
				_go(Step.COCKPIT_BACK)
		Step.COCKPIT_BACK:
			# The turn runs on render frames (ChaseCamera._process), which a
			# headless run does not pace against the physics ticks, so the
			# ease is checked by sampling: some tick before the end must see
			# the head part way round, never a snap from ahead to behind.
			if waited < 30 and absf(_facing(p, cam)) < 0.9:
				saw_mid_turn = true
			if waited == 30:
				_check(saw_mid_turn, "the head turns with an ease: some tick saw it part way round, not a snap")
				var rel := p.global_transform.affine_inverse() * cam.global_position
				var want := ChaseCamera.COCKPIT_EYE + PlayerCars.look_back_shift(PlayerCar.chassis_kind())
				_check(rel.distance_to(want) < 0.02, "in the cockpit the eye leans to the look-back position %s (%s)" % [want, rel])
				_check(absf(rel.x) < 0.05, "which is on the cabin centreline, between the seats (x %.2f)" % rel.x)
				_check(_facing(p, cam) < -0.9, "the cockpit eye faces the rear (facing %.2f)" % _facing(p, cam))
				# The driver's own headrest (CockpitFrame: 0.36 off the centreline,
				# at eye height, 0.71 back) must be outside the view, else it is
				# the thing "blocking my POV" (Roy, 2026-10-09).
				var headrest := p.global_transform * (Vector3(-0.36, 1.10, 0.71) + PlayerCars.cabin_offset(PlayerCar.chassis_kind()))
				var to_hr := (headrest - cam.global_position).normalized()
				var off_axis := rad_to_deg(acos(clampf(to_hr.dot(-cam.global_transform.basis.z), -1.0, 1.0)))
				var aspect := cam.get_viewport().get_visible_rect().size.aspect()
				var half_h := rad_to_deg(atan(tan(deg_to_rad(cam.fov) * 0.5) * aspect))
				print("look back: headrest %.0f degrees off the view axis, half-width of the view %.0f" % [off_axis, half_h])
				_check(off_axis > half_h, "the driver's headrest is outside the view (%.0f > %.0f degrees)" % [off_axis, half_h])
				Input.action_release("look_back")
				_go(Step.COCKPIT_FWD)
		Step.COCKPIT_FWD:
			if waited == 1:
				saw_mid_turn = false
			if waited < 30 and absf(_facing(p, cam)) < 0.9:
				saw_mid_turn = true
			if waited == 30:
				_check(saw_mid_turn, "released, the head eases back the same way, not a snap")
				var rel := p.global_transform.affine_inverse() * cam.global_position
				_check(rel.distance_to(ChaseCamera.COCKPIT_EYE) < 0.02, "and the eye is back at the driver's eye (%s)" % rel)
				_check(_facing(p, cam) > 0.9, "released, the cockpit eye faces forward (facing %.2f)" % _facing(p, cam))
				_check(hud.rear_threat < 0.02, "no cue with nothing behind (%.2f)" % hud.rear_threat)
				cam.set_view(ChaseCamera.View.CHASE)
				_put_car_behind(p, 6.0, false)
				_go(Step.CUE_NEAR)
		Step.CUE_NEAR:
			if waited == 40:
				var now := hud.rear_threat_now()
				print("cue: car 6 m behind -> threat now %.2f, smoothed %.2f, border %d px" % [now, hud.rear_threat, hud.rear_style.border_width_top])
				_check(now > 0.8, "a car 6 m behind in the lane is a strong cue (%.2f)" % now)
				_check(hud.rear_threat > 0.7, "the smoothed cue has risen (%.2f)" % hud.rear_threat)
				_check(hud.rear_style.border_width_top >= 3, "the strip frame thickens (%d px)" % hud.rear_style.border_width_top)
				_check(hud.rear_style.border_color.r > 0.9 and hud.rear_style.border_color.b < 0.4, "the strip frame warms to sodium (%s)" % hud.rear_style.border_color)
				var glass: Color = cam.frame.mirrors.views[0].mat.albedo_color
				_check(glass.b < CockpitMirrors.GLASS_TINT.b - 0.2, "the rearview glass warms too (%s)" % glass)
				_put_car_behind(p, 40.0, false)
				_go(Step.CUE_FAR)
		Step.CUE_FAR:
			if waited == 40:
				_check(hud.rear_threat_now() == 0.0 and hud.rear_threat < 0.05, "a car 40 m back gives no cue (now %.2f, smoothed %.2f)" % [hud.rear_threat_now(), hud.rear_threat])
				_put_car_behind(p, 6.0, true)
				_go(Step.CUE_ONCOMING)
		Step.CUE_ONCOMING:
			if waited == 40:
				_check(hud.rear_threat_now() == 0.0, "an oncoming car close behind gives no cue (%.2f)" % hud.rear_threat_now())
				_put_car_behind(p, 200.0, false)
				_go(Step.CUE_GONE)
		Step.CUE_GONE:
			if waited == 40:
				_check(hud.rear_threat < 0.02 and hud.rear_style.border_width_top == 1, "the cue decays when the car is gone (%.2f, %d px)" % [hud.rear_threat, hud.rear_style.border_width_top])
				var glass: Color = cam.frame.mirrors.views[0].mat.albedo_color
				_check(glass.is_equal_approx(CockpitMirrors.GLASS_TINT), "the rearview glass is plain again (%s)" % glass)
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
	print("look_back: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
	return true
