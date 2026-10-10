extends SceneTree
# Driver fit, every player car (Roy, 2026-10-10: "real seat space for the
# player model, or fix the player model to fit"). Each car boots as the
# player's car (NEON_CAR), at rest, and the game's own seated driver
# (DriverModel) is measured against that car's cabin, car space:
#   head      the top of the head under the roof liner (closed cars)
#   shoulders the torso inside the door card on the driver's side, and not
#             across the car's centre line into the passenger's seat
#   hands     the left hand on the rim clear of the door card (elbow room)
#   legs      both feet reach their pedals; no part of a thigh or shin inside
#             the steering wheel's rim tube, the dash face and knee panel
#             (open over the driver's footwell), or the centre console
# Prints one line of clearances per car (metres, + is room) for the audit
# table. Exit code 1 on failure.
#
# This is the built driver, a short-bodied figure (its head top is 0.74 m over
# the cushion, a 1.46 m person's). A full-size body is a different question:
# tools/fleet_design/interior_space.gd sits scaled manikins in the same cabins.
#
# NEON_FIT_CAR=p4_kei limits the run to one car.
# Run: <godot> --headless --audio-driver Dummy --path . -s res://tests/fleet/driver_fit.gd
const Harness := preload("res://tests/traffic/traffic_harness.gd")

const RATE := 60
const HEAD_MIN := 0.03       # under the liner
const SHOULDER_MIN := 0.005  # inside the door card's face
const CENTRE_MAX := 0.02     # how far the torso may cross the centre line
const HAND_MIN := 0.02       # the left hand off the door card
const RIM_MIN := 0.004       # a leg off the rim tube's surface
const DASH_TOL := 0.01       # a leg this far into the dash is a seam, not a problem
const PEDAL_MAX := 0.03

var fails := 0
var game: Node
var logger := Harness.ErrorCounter.new()

func _check(ok: bool, msg: String) -> void:
	if not ok:
		print("FAIL " + msg)
		fails += 1

func _initialize() -> void:
	OS.add_logger(logger)
	Engine.physics_ticks_per_second = RATE
	_run.call_deferred()

func _run() -> void:
	var only := OS.get_environment("NEON_FIT_CAR")
	for k in PlayerCars.KINDS:
		if only != "" and String(k.id) != only:
			continue
		await _fit(String(k.id))
	OS.set_environment("NEON_CAR", "")
	if logger.errors.size() > 0:
		print("FAIL %d engine errors: %s" % [logger.errors.size(), str(logger.errors.slice(0, 5))])
		fails += logger.errors.size()
	print("driver_fit: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)

func _fit(kind: String) -> void:
	OS.set_environment("NEON_CAR", kind)
	game = Harness.boot(self, 0, 150.0, 7, 1.0e6)
	for i in RATE:
		await physics_frame
	var p: PlayerCar = game.get("player")
	var cam: ChaseCamera = game.get("camera")
	_check(p != null and cam != null and cam.frame != null and cam.frame.driver != null, "%s: the game should boot with a driver" % kind)
	if p == null or cam == null or cam.frame == null or cam.frame.driver == null:
		game.queue_free()
		await process_frame
		return
	p.driver = func(c: PlayerCar) -> void:
		c.throttle_input = 0.0
		c.brake_input = 1.0
		c.steering_input = 0.0
	for i in RATE * 2:
		await physics_frame
	var frame: CockpitFrame = cam.frame
	var d: DriverModel = frame.driver
	var cab: Dictionary = frame.cab
	var to_car := p.global_transform.affine_inverse()
	var door_x := float(cab.door_x)
	# head under the liner (its underside is 3.5 cm under roof_y, CockpitFrame)
	var head_top := -INF
	for v in _verts(d.head_mesh, to_car):
		head_top = maxf(head_top, v.y)
	var head_room := INF if bool(cab.open_top) else float(cab.roof_y) - 0.035 - head_top
	_check(head_room >= HEAD_MIN, "%s: the driver's head is %.3f m from the roof liner (at least %.2f)" % [kind, head_room, HEAD_MIN])
	# torso between the door card and the centre line
	var torso_min := INF
	var torso_max := -INF
	for v in _verts(d.torso_mesh, to_car):
		torso_min = minf(torso_min, v.x)
		torso_max = maxf(torso_max, v.x)
	var shoulder_room := torso_min + door_x
	_check(shoulder_room >= SHOULDER_MIN, "%s: the driver's shoulder is %.3f m inside the door card (at least %.3f)" % [kind, shoulder_room, SHOULDER_MIN])
	_check(torso_max <= CENTRE_MAX, "%s: the driver's torso crosses the centre line by %.3f m" % [kind, torso_max])
	# the left hand on the rim, off the door
	var hand_min := INF
	for v in _verts(d.hands[-1], to_car):
		hand_min = minf(hand_min, v.x)
	var hand_room := hand_min + door_x
	_check(hand_room >= HAND_MIN, "%s: the left hand is %.3f m from the door card (at least %.2f)" % [kind, hand_room, HAND_MIN])
	# legs: pedals reached, clear of the rim tube and of the dash
	var pedal_gap := maxf(d.leg_gap(-1), d.leg_gap(1))
	_check(pedal_gap < PEDAL_MAX, "%s: a foot is %.3f m short of its pedal" % [kind, pedal_gap])
	var wheel_inv: Transform3D = (to_car * frame.wheel.global_transform).affine_inverse()
	var rim_room := INF
	var dash_in := 0.0
	var console_in := 0.0
	var con_half := frame.console_width() * 0.5 if String(cab.console) == "tunnel" else 0.0
	var con_top := float((cab.lever as Vector3).y) + 0.005
	var top_near := float((cab.cluster as Vector2).x)
	var face_z := float(cab.dash_face_z)
	for side in [-1, 1]:
		for part in ["thigh", "shin"]:
			for v in _verts(d.legs[side][part], to_car):
				var w: Vector3 = wheel_inv * v
				var tube := Vector2(Vector2(w.x, w.y).length() - SteeringWheel.RADIUS, w.z).length() - SteeringWheel.GRIP_R
				rim_room = minf(rim_room, tube)
				if v.x >= frame.well_x0 and v.x <= frame.well_x1:
					if v.y > frame.well_y:   # the footwell: the face stops above the legs
						dash_in = maxf(dash_in, minf((face_z + 0.06) - v.z, v.y - frame.well_y))
				elif v.y > top_near - 0.38:
					dash_in = maxf(dash_in, (face_z + 0.06) - v.z)
				elif v.y > top_near - 0.56:
					dash_in = maxf(dash_in, (face_z + 0.03) - v.z)
				if v.z > face_z + 0.06 and v.y < con_top:
					console_in = maxf(console_in, con_half - absf(v.x))
	_check(rim_room >= RIM_MIN, "%s: a leg is %.3f m from the wheel rim (at least %.3f)" % [kind, rim_room, RIM_MIN])
	_check(dash_in <= DASH_TOL, "%s: a knee is %.3f m inside the dash" % [kind, dash_in])
	_check(console_in <= DASH_TOL, "%s: a leg is %.3f m inside the centre console" % [kind, console_in])
	var bones := DriverModel.leg_lengths(cab)
	print("%s: legs %.0f%%, head %s, shoulder %+.3f, centre %+.3f, left hand %+.3f, leg to rim %+.3f, knee in dash %.3f, leg in console %.3f, pedal gap %.3f" % [kind, (bones.x + bones.y) / (DriverModel.THIGH + DriverModel.SHIN) * 100.0,
		"open top" if is_inf(head_room) else "%+.3f" % head_room, shoulder_room, -torso_max, hand_room, rim_room, dash_in, console_in, pedal_gap])
	game.queue_free()
	await process_frame
	await process_frame

## The mesh's vertices in car space.
static func _verts(mi: MeshInstance3D, to_car: Transform3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	if mi == null or mi.mesh == null:
		return out
	var xf := to_car * mi.global_transform
	for v in mi.mesh.get_faces():
		out.append(xf * v)
	return out
