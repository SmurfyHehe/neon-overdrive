extends SceneTree

# The driver (cockpit milestone 2, 2026-10-06), headless and silent:
# - a DriverModel sits in the CockpitFrame with head, torso, floating gloved
#   hands (no arms), a gold bracelet on the right wrist, legs, within the
#   triangle budget; the glove style matches the car
# - the hands stay on the rim grips (within 2 cm) across a steering sweep,
#   the wheel rolls to the car's steering, legs reach the pedals
# - a manual shift moves the lever and sends the right hand to the knob, then
#   back on the rim within 1 s
# - a next-station request sends the right hand to the touch screen, which taps
#   the next tile (the station changes on the tap), and back (tests/touch_radio.gd
#   covers the timing)
# - pulling the handbrake sends the right hand to the lever, which it holds
#   until the handbrake is released, then back on the rim
# - priority: a shift takes the hand off a radio reach, the handbrake takes it
#   off a shift
# - the hands and wrists never rise above DriverModel.HAND_TOP_MIN_DEG below the
#   eye in any of the above (the sightline spec)
# - in the cockpit view the head and torso are hidden, in the chase view shown
# - no engine errors during any of it
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/cockpit_driver.gd

const TIMEOUT_TICKS := 60 * 40
const TRI_MAX := 3000
const TRI_MIN := 600
const GRIP_TOL := 0.02

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

enum Step { BOOT, SWEEP, SHIFT, RADIO, BRAKE, PRIORITY, VIEWS, DONE }

## Physics ticks for a number of seconds (the suite runs at 60, the game at 120).
static func ticks(secs: float) -> int:
	return int(round(secs * Engine.physics_ticks_per_second))

var step := Step.BOOT
var step_start := 0
var tick := 0
var failures: Array[String] = []
var steer := 0.0
var throttle := 0.0
var logger := ErrorCounter.new()
var sweep := [-1.0, -0.6, -0.2, 0.0, 0.3, 0.7, 1.0]
var sweep_i := 0
var shift_tick := -1
var hand_at_knob := false
var hand_back_tick := -1
var hand_at_radio := false
var radio_touch := Vector3.ZERO
var lever_moved := false
var handbrake := 0.0
var hand_at_brake := false
var hand_rode_brake := false
var min_below_eye := 90.0     # degrees below the eye of the highest hand point seen
var min_below_where := ""

func _initialize() -> void:
	ExhaustTune.save_path = "user://autotune/test_cockpit_driver_exhaust.json"
	OS.add_logger(logger)
	change_scene_to_file("res://Game.tscn")

func _drive(c: PlayerCar) -> void:
	c.throttle_input = throttle
	c.brake_input = 0.0
	c.handbrake_input = handbrake
	c.steering_input = steer

## Lowest angle below the eye's horizontal of any corner of the hands' (and
## the bracelet's) mesh bounds, car space, kept as a running minimum with where
## it happened.
func _track_view(d: DriverModel, where: String) -> void:
	var eye := ChaseCamera.COCKPIT_EYE
	for side in [-1, 1]:
		var hand: MeshInstance3D = d.hands[side]
		var pts: Array[Vector3] = []
		for c in 8:
			pts.append(hand.transform * hand.get_aabb().get_endpoint(c))
			if side > 0:
				pts.append(hand.transform * d.bracelet.transform * d.bracelet.get_aabb().get_endpoint(c))
		for pt in pts:
			var v: Vector3 = eye - pt
			var below := rad_to_deg(atan2(v.y, Vector2(v.x, v.z).length()))
			if below < min_below_eye:
				min_below_eye = below
				min_below_where = "%s hand %d" % [where, side]

func _physics_process(_delta: float) -> bool:
	tick += 1
	var game := current_scene
	if game == null or game.get("player") == null or game.get("camera") == null:
		return tick > TIMEOUT_TICKS and _end("Game never became ready")
	var p: PlayerCar = game.player
	var cam: ChaseCamera = game.camera
	p.driver = _drive
	var frame: CockpitFrame = cam.frame
	var d: DriverModel = frame.driver
	var waited := tick - step_start
	if step != Step.BOOT:
		_track_view(d, Step.keys()[step])
	match step:
		Step.BOOT:
			_check(d != null and d.get_parent() == frame, "the driver should be a child of the cockpit frame")
			for n in ["Torso", "Torso/TorsoMesh", "Torso/Head", "Torso/Head/HeadMesh",
					"HandL", "HandR", "HandR/Bracelet", "ThighL", "ThighR", "ShinL", "ShinR", "FootL", "FootR"]:
				_check(d.get_node_or_null(n) != null, "the driver should have a node %s" % n)
			for n in ["UpperArmL", "UpperArmR", "ForearmL", "ForearmR"]:
				_check(d.get_node_or_null(n) == null, "no arms: the driver should not have a node %s" % n)
			_check(d.get_node_or_null("HandL/Bracelet") == null, "the bracelet is on the right wrist only")
			_check(d.glove_style == PlayerCar.chassis_kind() or not DriverModel.GLOVE_STYLES.has(PlayerCar.chassis_kind()), "the glove style follows the car (%s)" % d.glove_style)
			var gold := (d.bracelet.material_override if d.bracelet.material_override != null else d.bracelet.mesh.surface_get_material(0)) as StandardMaterial3D
			_check(gold != null and gold.metallic >= 0.8, "the bracelet is metallic gold")
			_check(d.bracelet.mesh.surface_get_array_len(0) / 3 >= 4 * 12 * DriverModel.LINKS - 1, "the bracelet is a ring of %d modelled links" % DriverModel.LINKS)
			print("driver triangles: %d" % d.tri_count)
			_check(d.tri_count >= TRI_MIN and d.tri_count <= TRI_MAX, "driver triangles %d, want %d..%d" % [d.tri_count, TRI_MIN, TRI_MAX])
			for n in d.find_children("*", "VisualInstance3D", true, false):
				_check((n as VisualInstance3D).layers == CockpitFrame.DRIVER_BIT, "driver meshes sit on the driver layer (%s)" % n.name)
			for v in frame.mirrors.views:
				_check((v.cam as Camera3D).cull_mask & CockpitFrame.DRIVER_BIT == 0, "mirror cameras never draw the driver")
			cam.set_view(ChaseCamera.View.COCKPIT)
			steer = sweep[0]
			_go(Step.SWEEP)
		Step.SWEEP:
			if waited == ticks(0.9):
				_check(absf(frame.steering - p.steer_fraction()) < 1e-4, "the frame reads the steering")
				_check(absf(frame.wheel_angle - p.steer_fraction() * CockpitFrame.WHEEL_LOCK_RAD) < deg_to_rad(1.5), "the wheel has rolled to the car's steering (%.0f deg)" % rad_to_deg(frame.wheel_angle))
				for side in [-1, 1]:
					var gap: float = d.hand_position(side).distance_to(d.grip_position(side))
					_check(gap <= GRIP_TOL, "hand %d is %.3f m off its rim grip at steer %.1f (wheel %.0f deg)" % [side, gap, steer, rad_to_deg(frame.wheel.angle)])
					_check(d.leg_gap(side) < 0.03, "leg %d cannot reach its pedal (short by %.3f m)" % [side, d.leg_gap(side)])
				# the grip really is on the rim centreline: the hand turns with the
				# wheel inside the grip range and stays at its edge past it (car space,
				# the wheel's own rotation left out)
				var deg := rad_to_deg(frame.wheel.angle)
				var to_wheel := (frame.wheel_mount.transform * frame.wheel.transform).affine_inverse()
				for side in [-1, 1]:
					var local: Vector3 = to_wheel * d.hand_position(side)
					var ang := rad_to_deg(atan2(local.y, local.x))
					var nearest := frame.wheel.rim_point(ang)
					_check(local.distance_to(nearest) <= GRIP_TOL, "hand %d is %.3f m off the rim centreline at wheel %.0f deg" % [side, local.distance_to(nearest), deg])
					# the hand holds the rim somewhere in its range (the top end is
					# the sightline cap); tests/cockpit_steering_hands.gd covers the
					# shuffle itself
					var world_ang: float = d.rim_deg(side)
					var span := DriverModel.rim_range(side)
					_check(world_ang >= span[0] - 0.5 and world_ang <= span[1] + 0.5, "hand %d sits at %.0f deg of the rim, outside %s (wheel %.0f)" % [side, world_ang, span, deg])
					_check(absf(wrapf(world_ang - (ang - deg), -180.0, 180.0)) < 8.0, "hand %d is drawn at %.0f deg of the rim but holds %.0f" % [side, ang - deg, world_ang])
				sweep_i += 1
				if sweep_i < sweep.size():
					steer = sweep[sweep_i]
					step_start = tick
				else:
					steer = 0.0
					throttle = 1.0
					p.automatic_transmission = false
					_go(Step.SHIFT)
		Step.SHIFT:
			if waited == ticks(0.5):
				var before: int = p.gear
				p.shift(1)
				_check(p.is_shifting and p.requested_gear == before + 1, "shift(1) should start a shift to %d" % (before + 1))
				shift_tick = tick
			if shift_tick > 0:
				lever_moved = lever_moved or frame.lever_moving
				var knob: Vector3 = frame.lever.transform * frame.lever_knob.position
				if d.hand_position(1).distance_to(knob) < 0.06:
					hand_at_knob = true
				if hand_at_knob and hand_back_tick < 0 and not d.is_busy() and d.hand_position(1).distance_to(d.grip_position(1)) <= GRIP_TOL:
					hand_back_tick = tick
			if waited == ticks(0.5) + ticks(1.25):
				_check(lever_moved, "a manual shift should move the lever")
				_check(hand_at_knob, "the right hand should reach the gear knob during a manual shift")
				_check(hand_back_tick > 0 and hand_back_tick - shift_tick <= ticks(1.0), "the hand should be back on the rim within 1 s (%d ticks)" % (hand_back_tick - shift_tick))
				_check(not d.is_busy(), "the driver is idle again after the shift")
				throttle = 0.3
				radio_touch = frame.radio_touch().pos
				frame.request_radio()
				shift_tick = tick
				_go(Step.RADIO)
		Step.RADIO:
			if d.hand_position(1).distance_to(radio_touch) < 0.10:
				hand_at_radio = true
			if waited == ticks(1.2):
				_check(hand_at_radio, "a station change should send the right hand to the head unit")
				_check(not d.is_busy() and d.hand_position(1).distance_to(d.grip_position(1)) <= GRIP_TOL, "the hand returns to the rim after the radio press")
				_check(game.radio.station == 0 and frame.head_unit.station == 0, "the tap tuned the first station and the screen shows it (%d)" % frame.head_unit.station)
				throttle = 0.0
				handbrake = 1.0
				_go(Step.BRAKE)
		Step.BRAKE:
			var grip: Vector3 = frame.handbrake.transform * Vector3(0.0, 0.017, -0.21)
			var at_lever := d.hand_position(1).distance_to(grip) < 0.08
			if at_lever:
				hand_at_brake = true
				if frame.handbrake.rotation_degrees.x > 20.0:
					hand_rode_brake = true
			if waited == ticks(0.6):
				_check(hand_at_brake and at_lever, "pulling the handbrake should put the right hand on the lever and keep it there")
				_check(hand_rode_brake, "the hand rides the lever up as the handbrake lifts")
				handbrake = 0.0
			if waited == ticks(0.6) + ticks(0.5):
				_check(not d.is_busy() and d.hand_position(1).distance_to(d.grip_position(1)) <= GRIP_TOL, "the hand returns to the rim after the handbrake is released")
				throttle = 0.3
				frame.request_radio()
				_go(Step.PRIORITY)
		Step.PRIORITY:
			# radio reach under way, then a shift, then the handbrake
			if waited == ticks(0.1):
				_check(d.act == DriverModel.Act.RADIO_REACH, "the radio reach has started (%s)" % DriverModel.Act.keys()[d.act])
				p.shift(1 if p.gear < 3 else -1)
			if waited == ticks(0.2):
				_check(d.act == DriverModel.Act.SHIFT_REACH or d.act == DriverModel.Act.SHIFT_HOLD, "a shift takes the hand off the radio (%s)" % DriverModel.Act.keys()[d.act])
				handbrake = 1.0
			if waited == ticks(0.3):
				_check(d.act == DriverModel.Act.BRAKE_REACH or d.act == DriverModel.Act.BRAKE_HOLD, "the handbrake takes the hand off the shift (%s)" % DriverModel.Act.keys()[d.act])
				handbrake = 0.0
			if waited == ticks(1.3):
				_check(not d.is_busy() and d.hand_position(1).distance_to(d.grip_position(1)) <= GRIP_TOL, "the hand is back on the rim after the pile-up")
				_go(Step.VIEWS)
		Step.VIEWS:
			if waited == ticks(0.1):
				_check(not d.head.visible and not d.torso_mesh.visible, "in the cockpit view the head and torso are hidden")
				_check((d.get_node("HandR") as Node3D).visible and (d.get_node("HandL") as Node3D).visible and d.bracelet.visible, "hands and bracelet stay visible in the cockpit")
				print("hands: highest point seen %.1f deg below the eye (%s)" % [min_below_eye, min_below_where])
				_check(min_below_eye >= DriverModel.HAND_TOP_MIN_DEG, "a hand rose to %.1f deg below the eye (%s); the road band must stay clear" % [min_below_eye, min_below_where])
				cam.set_view(ChaseCamera.View.CHASE)
			if waited == ticks(0.2):
				_check(d.head.visible and d.torso_mesh.visible, "in the chase view the whole driver shows")
				_check(frame.visible, "the interior is drawn in the chase view (through the glass)")
				var glass := P1CoupeBuilder._get_glass_material()
				_check(glass.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and glass.albedo_color.a < 0.9, "the P1 glass is see-through")
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
	print("cockpit_driver: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
	return true
