extends SceneTree

# The flip-off (K, 2026-10-11): the driver's left hand goes out of the side
# window, middle finger up, and comes back. For every player car, with both
# window controls (the car's own in the cockpit view, the other in the chase view):
# - window down, tap K: the left hand leaves the rim, the fist with the finger
#   shows instead of the mitten, it holds outside the body (every corner of it
#   past the door line) and is back on the rim as the mitten within 2.5 s;
# - sight line, the whole time: no corner of the left hand is above 8 degrees
#   below the eye within 20 degrees either side of straight ahead;
# - window shut, tap K: the same gesture behind the glass, never past the door
#   line (a car with no door glass, the open kei, goes out anyway);
# - hold K for 3 s: the hand stays out and pumps (at least 4 tops), and returns
#   after the release;
# - K during a window roll waits for the window to stop; the window key during
#   a gesture waits for the hand to be back; the right hand never leaves the rim;
# - gesture_peak fires exactly once per gesture, saying whether the hand went out;
# - glove only: the driver has no arm, forearm or sleeve node;
# - no stats: cash, bank, heat and damage are the same before and after ten
#   gestures, and the tank drains no faster than with the hands on the wheel.
# One car with NEON_FLIP_CAR=<kind>. Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --audio-driver Dummy --path . -s res://tests/view/gesture_flip_off.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const RATE := 60
const CONE_DEG := 20.0
const SIGHT_DEG := 8.0
const GRIP_TOL := 0.02
const TAP_TICKS := 3
const BACK_SECS := 2.5
const GESTURES := 10

var logger := Harness.ErrorCounter.new()
var failures: Array[String] = []
var game: Node
var p: PlayerCar
var cam: ChaseCamera
var frame: CockpitFrame
var d: DriverModel
var kind := ""
var signals := 0
var signal_open := false
# what _sample() saw since the last _watch()
var saw_fist := false
var saw_gesture := false
var far_out := -INF          # the furthest out (-x) any corner of the left hand got
var hold_min_out := INF      # while held up: the least far out of its corners
var hold_origin := Vector3.ZERO
var cone_worst := ""
var right_off := false
var two_hands := false

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append("%s: %s" % [kind, msg])

func _initialize() -> void:
	Engine.physics_ticks_per_second = RATE
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	var only := OS.get_environment("NEON_FLIP_CAR")
	for k in PlayerCars.ids():
		if only != "" and String(k) != only:
			continue
		await _car(String(k))
	OS.set_environment("NEON_CAR", "")
	_release_keys()
	kind = "all"
	_check(logger.errors.is_empty(), "%d engine error(s): %s" % [logger.errors.size(), logger.errors.slice(0, 3)])
	for f in failures:
		printerr("FAIL: ", f)
	print("gesture_flip_off: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _release_keys() -> void:
	Input.action_release("flip_off")
	Input.action_release("window")

func _ticks(n: int) -> void:
	for i in n:
		await physics_frame
		_sample()

func _secs(s: float) -> void:
	await _ticks(int(round(s * RATE)))

func _watch() -> void:
	saw_fist = false
	saw_gesture = false
	far_out = -INF
	hold_min_out = INF
	cone_worst = ""
	right_off = false
	two_hands = false

## One look at the hands, in car space (the driver sits at the car's origin).
func _sample() -> void:
	var mitten: MeshInstance3D = d.hands[-1]
	var fist := d.finger_hand.visible
	var node: MeshInstance3D = d.finger_hand if fist else mitten
	saw_fist = saw_fist or fist
	saw_gesture = saw_gesture or d.is_gesturing()
	two_hands = two_hands or fist == mitten.visible
	var eye: Vector3 = frame.cab.eye
	var bb := node.mesh.get_aabb()
	var least := INF
	for i in 8:
		var c := node.transform * bb.get_endpoint(i)
		far_out = maxf(far_out, -c.x)
		least = minf(least, -c.x)
		var rel := c - eye
		if rel.z < 0.0:
			var az := rad_to_deg(atan2(-rel.x, -rel.z))
			var el := rad_to_deg(atan2(rel.y, Vector2(rel.x, rel.z).length()))
			if absf(az) < CONE_DEG and el > -SIGHT_DEG and cone_worst == "":
				cone_worst = "%.1f deg left, %.1f deg up (%s)" % [az, el, DriverModel.LeftAct.keys()[d.left_act]]
	if d.left_act == DriverModel.LeftAct.GESTURE_HOLD:
		hold_min_out = minf(hold_min_out, least)
		hold_origin = node.position
	if d.is_busy() or d.hand_position(1).distance_to(d.grip_position(1)) > GRIP_TOL:
		right_off = true

func _set_window(v: float) -> void:
	cam.perspective.window = v
	await _ticks(3)
	_check(is_equal_approx(frame.window, v) and frame.window_direction == 0, "the test could not put the window at %.1f" % v)

func _tap() -> void:
	Input.action_press("flip_off")
	await _ticks(TAP_TICKS)
	Input.action_release("flip_off")

func _on_rim(what: String) -> void:
	_check(not d.is_gesturing() and d.left_act == DriverModel.LeftAct.GRIP, "%s: the left hand is not back (%s)" % [what, DriverModel.LeftAct.keys()[d.left_act]])
	_check(d.hand_position(-1).distance_to(d.grip_position(-1)) < GRIP_TOL, "%s: the left hand is %.3f m off the rim" % [what, d.hand_position(-1).distance_to(d.grip_position(-1))])
	_check((d.hands[-1] as Node3D).visible and not d.finger_hand.visible, "%s: the mitten is not back" % what)

func _always(what: String) -> void:
	_check(cone_worst == "", "%s: the left hand is in the road view: %s" % [what, cone_worst])
	_check(not right_off, "%s: the right hand left the rim" % what)
	_check(not two_hands, "%s: the mitten and the fist showed together (or neither)" % what)

func _car(k: String) -> void:
	kind = k
	OS.set_environment("NEON_CAR", k)
	game = Harness.boot(self, 0, 150.0, 7, 1.0e6)
	for i in RATE:
		await physics_frame
	p = game.get("player")
	cam = game.get("camera")
	if p == null or cam == null or cam.frame == null or cam.frame.driver == null:
		failures.append("%s: the game should boot with a cockpit frame and a driver" % k)
		game.queue_free()
		await process_frame
		return
	frame = cam.frame
	d = frame.driver
	p.driver = func(c: PlayerCar) -> void:
		c.throttle_input = 0.0
		c.brake_input = 0.0
		c.handbrake_input = 0.0
		c.steering_input = 0.0
	signals = 0
	d.gesture_peak.connect(func(open: bool) -> void:
		signals += 1
		signal_open = open)
	_check(InputMap.has_action("flip_off") and InputMap.has_action("idle_action"), "flip_off and idle_action should be bound")
	for n in d.find_children("*", "", true, false):
		var low := String(n.name).to_lower()
		_check(not ("arm" in low or "sleeve" in low), "the driver has a %s node" % n.name)
	cam.set_view(ChaseCamera.View.COCKPIT)
	await _secs(0.5)
	_watch()
	await _ticks(2)
	_always("at rest")
	var own := frame.window_control
	for control in [own, "switch" if own == "crank" else "crank"]:
		if control != own:
			frame.set_window_control(control)
			cam.set_view(ChaseCamera.View.CHASE)
		await _tap_case(true, control)
		await _tap_case(false, control)
	frame.set_window_control(own)
	cam.set_view(ChaseCamera.View.COCKPIT)
	await _hold_case()
	await _wait_cases()
	await _no_stats()
	print("gesture_flip_off: %s ok so far: %d failure(s)" % [k, failures.size()])
	_release_keys()
	game.queue_free()
	await process_frame
	await process_frame

func _tap_case(open: bool, control: String) -> void:
	var what := "%s, %s, window %s" % [control, "cockpit" if cam.view == ChaseCamera.View.COCKPIT else "chase", "down" if open else "shut"]
	await _set_window(1.0 if open else 0.0)
	var goes_out := open or not d.has_door_glass()
	var before := signals
	_watch()
	await _tap()
	await _ticks(int(BACK_SECS * RATE) - TAP_TICKS)
	_check(saw_gesture and saw_fist, "%s: K did not raise the finger" % what)
	_check(signals - before == 1, "%s: gesture_peak fired %d times for one tap" % [what, signals - before])
	_check(signal_open == goes_out, "%s: gesture_peak said window_open = %s" % [what, signal_open])
	_on_rim(what)
	_always(what)
	if goes_out:
		_check(hold_min_out > d.door_line(), "%s: the hand is not outside the body (its nearest corner is %.3f out, the door line is %.3f)" % [what, hold_min_out, d.door_line()])
	else:
		_check(far_out < d.door_line(), "%s: the hand went past the door line (%.3f out, the line is %.3f)" % [what, far_out, d.door_line()])
		_check(-hold_origin.x < d.pane_x(hold_origin.y), "%s: the hand is not inside the glass" % what)

func _hold_case() -> void:
	await _set_window(1.0)
	var before := signals
	var peaks := d.gesture_peaks
	_watch()
	Input.action_press("flip_off")
	await _secs(3.0)
	_check(d.left_act == DriverModel.LeftAct.GESTURE_HOLD, "hold: the hand did not stay out for 3 s (%s)" % DriverModel.LeftAct.keys()[d.left_act])
	Input.action_release("flip_off")
	await _secs(1.5)
	_check(d.gesture_peaks - peaks >= 4, "hold: %d tops in 3 s, want at least 4" % (d.gesture_peaks - peaks))
	_check(signals - before == 1, "hold: gesture_peak fired %d times, want once" % (signals - before))
	_on_rim("hold")
	_always("hold")

func _wait_cases() -> void:
	# K while the window is rolling: nothing until the window stops
	await _set_window(0.0)
	_watch()
	Input.action_press("window")
	await _ticks(6)
	await _tap()
	await _ticks(20)
	_check(not saw_gesture, "K during a window roll did not wait")
	_check(frame.window > 0.0, "the window should still be rolling down")
	Input.action_release("window")
	var waited := 0
	while not d.is_gesturing() and waited < RATE * 4:
		await _ticks(1)
		waited += 1
	_check(d.is_gesturing(), "the waiting K never happened once the window stopped")
	_check(frame.window_direction == 0, "the gesture started while the window was still moving")
	await _secs(BACK_SECS)
	_on_rim("K after a window roll")
	_always("K during a window roll")
	# the window key while the hand is out: the window stays put until it is back
	await _set_window(0.0)
	_watch()
	await _tap()
	await _secs(0.3)
	_check(d.is_gesturing(), "the gesture should be under way")
	Input.action_press("window")
	var moved := false
	var guard := 0
	while d.is_gesturing() and guard < RATE * 4:
		await _ticks(1)
		guard += 1
		moved = moved or frame.window > 0.0 or frame.window_direction != 0
	_check(not moved, "the window moved while the hand was out")
	_check(not d.is_gesturing(), "the gesture never ended with the window key held")
	await _secs(0.5)
	_check(frame.window > 0.0, "the held window key did nothing after the hand came back")
	Input.action_release("window")
	await _secs(0.5)
	_always("the window key during a gesture")

func _stats() -> Dictionary:
	var s := {}
	var wallet: Variant = game.get("wallet")
	if wallet != null:
		s["cash"] = wallet.get("cash")
		s["bank"] = wallet.get("bank")
	var heat: Variant = game.get("police_heat")
	if heat != null:
		s["heat"] = heat.get("heat")
		s["level"] = heat.get("level")
		s["seen"] = heat.get("seen")
	var damage: Variant = p.get("damage")
	if damage != null:
		s["parts"] = str(damage.get("parts"))
		s["lamps"] = str(damage.get("lamps"))
		s["hits"] = damage.get("hits")
	return s

func _fuel() -> float:
	var tank: Variant = p.get("fuel")
	return float(tank.get("litres")) if tank != null else 0.0

## Ten gestures change nothing the game keeps score with. The tank drains at
## idle anyway, so its rate is compared with a stretch of plain idling first.
func _no_stats() -> void:
	await _set_window(1.0)
	var idle_ticks := RATE * 4
	var fuel_a := _fuel()
	await _ticks(idle_ticks)
	var fuel_b := _fuel()
	var before := _stats()
	var each := int(1.35 * RATE)
	for i in GESTURES:
		await _tap()
		await _ticks(each - TAP_TICKS)
	var after := _stats()
	var fuel_c := _fuel()
	_check(not before.is_empty(), "no stats to compare (wallet, heat and damage are all missing)")
	_check(str(before) == str(after), "ten gestures changed the stats: %s -> %s" % [before, after])
	var idle_rate := (fuel_a - fuel_b) / idle_ticks
	var gesture_rate := (fuel_b - fuel_c) / (GESTURES * each)
	_check(gesture_rate <= idle_rate * 1.02 + 1e-9, "the tank drained faster during gestures (%.7f against %.7f l per tick)" % [gesture_rate, idle_rate])
	if kind == PlayerCars.DEFAULT:
		print("gesture_flip_off: stats compared %s, fuel %.4f -> %.4f l" % [before.keys(), fuel_b, fuel_c])
	await _secs(1.5)
	_on_rim("after ten gestures")
