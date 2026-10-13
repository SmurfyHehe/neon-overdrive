extends SceneTree
# Window crank placement (2026-10-13, issue #680): for every car, finds the
# hub position on the driver's door card nearest the car's CABIN "crank" where
# the arm through a whole turn, and the left hand on its knob, stay clear of
# the cabin's solids (CockpitFrame.keepout plus the door pocket), and prints
# the "crank" line to paste into scripts/car/<car>_data.gd. The hub sits on the
# card's face (the boss stands 1.2 cm out of it). tests/fleet/cabin_fit.gd
# checks the result.
#
# Run: <godot> --headless --audio-driver Dummy --path . -s res://tools/cabin_crank_fit.gd
# Env: NEON_FIT_CAR=<kind> for one car.
const Harness := preload("res://tests/traffic/traffic_harness.gd")
const STEP := 0.01
const TURN_SAMPLES := 12
const HAND_SAMPLES := 8

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var only := OS.get_environment("NEON_FIT_CAR")
	for k in PlayerCars.KINDS:
		var kind := String(k.id)
		if only != "" and only != kind:
			continue
		await _car(kind)
	OS.set_environment("NEON_CAR", "")
	quit(0)

func _car(kind: String) -> void:
	OS.set_environment("NEON_CAR", kind)
	var game: Node = Harness.boot(self, 0, 150.0, 7, 1.0e6)
	for i in 30:
		await physics_frame
	var cam: ChaseCamera = game.get("camera")
	var frame: CockpitFrame = cam.frame
	var driver: DriverModel = frame.driver
	frame.set_process(false)
	frame.set_physics_process(false)
	driver.set_process(false)
	var cab: Dictionary = frame.cab
	var pocket := _pocket_box(frame, driver)
	frame.set_window_control("crank")
	var mitten := driver._points_of([driver.hands[-1]])
	var start: Vector3 = cab.crank
	var seat_h := float(cab.seat_h)
	var belt := float(cab.belt_y)
	var eye: Vector3 = cab.eye
	var cands := []
	var y := seat_h + 0.10
	while y < belt - 0.06:
		var z := float(cab.dash_face_z) + 0.08
		while z < float(cab.b_pillar_z) - 0.10:
			cands.append(Vector3(-_card_face(cab, z), y, z))
			z += STEP
		y += STEP
	cands.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_squared_to(start) < b.distance_squared_to(start))
	if OS.get_environment("NEON_CRANK_WHY") != "":
		var at := start
		if OS.get_environment("NEON_CRANK_AT") != "":
			var v := OS.get_environment("NEON_CRANK_AT").split_floats(",")
			at = Vector3(v[0], v[1], v[2])
		_why(frame, driver, Vector3(-_card_face(cab, at.z), at.y, at.z), mitten, pocket)
	var found := Vector3.INF
	var tried := 0
	for c in cands:
		tried += 1
		if _clear(frame, driver, c, mitten, pocket):
			found = c
			break
	frame.set_window(0.0, 0)
	if found == Vector3.INF:
		print("%s: no clear crank spot on the card (%d tried)" % [kind, tried])
	else:
		print("%s: \"crank\": Vector3(%.3f, %.3f, %.3f),   # was %s, moved %.1f cm (%d tried)" % [kind, found.x, found.y, found.z, start, found.distance_to(start) * 100.0, tried])
	game.queue_free()
	await process_frame
	await process_frame

## |x| of the driver's door card face at z (the front half is the narrower).
static func _card_face(cab: Dictionary, z: float) -> float:
	var door_x := float(cab.door_x)
	var door_x_f := float(cab.get("door_x_front", door_x))
	var pillar_foot: Vector3 = cab.a_pillar[0]
	var door_z0 := pillar_foot.z + 0.28
	var front_len := (float(cab.b_pillar_z) - door_z0) * 0.5
	return minf(door_x, door_x_f) if z < door_z0 + front_len else door_x

func _pocket_box(frame: CockpitFrame, driver: DriverModel) -> Array:
	var box := driver.props.pocket.get_aabb()
	var xf := frame.global_transform.affine_inverse() * driver.props.pocket.global_transform
	var c := xf * box.get_center()
	return [Transform3D(Basis.IDENTITY, c), box.size * 0.5, Vector3.UP]

func _clear(frame: CockpitFrame, driver: DriverModel, hub: Vector3, mitten: PackedVector3Array, pocket: Array) -> bool:
	frame.crank_pos = hub
	frame.set_window_control("crank")
	frame.keepout.erase(frame.crank_keep)   # not against its own sweep
	var arm := frame.crank.get_node("Arm") as MeshInstance3D
	var arm_pts := driver._points_of([arm])
	driver._probe_pts.erase("Arm|")   # each candidate's arm is a new mesh of the same shape
	var extra := [] if OS.get_environment("NEON_CRANK_NO_POCKET") != "" else [pocket]
	for i in TURN_SAMPLES:
		frame.set_window(float(i) / TURN_SAMPLES / CockpitFrame.CRANK_TURNS, 0)
		if driver._clear_offset(frame.crank.transform, arm_pts, extra) != Vector3.ZERO:
			return false
	for i in HAND_SAMPLES:
		frame.set_window(float(i) / HAND_SAMPLES / CockpitFrame.CRANK_TURNS, 0)
		if driver._clear_offset(driver._crank_hand_transform(), mitten, extra) != Vector3.ZERO:
			return false
	return true

func _why(frame: CockpitFrame, driver: DriverModel, hub: Vector3, mitten: PackedVector3Array, pocket: Array) -> void:
	frame.crank_pos = hub
	frame.set_window_control("crank")
	frame.keepout.erase(frame.crank_keep)
	var arm_pts := driver._points_of([frame.crank.get_node("Arm")])
	for i in TURN_SAMPLES:
		frame.set_window(float(i) / TURN_SAMPLES / CockpitFrame.CRANK_TURNS, 0)
		print("  arm %d: %s" % [i, driver._clear_offset(frame.crank.transform, arm_pts, [pocket])])
	var boxes: Array = frame.keepout + [pocket]
	for i in HAND_SAMPLES:
		frame.set_window(float(i) / HAND_SAMPLES / CockpitFrame.CRANK_TURNS, 0)
		var xf := driver._crank_hand_transform()
		var hits := []
		for b in boxes:
			var inv: Transform3D = (b[0] as Transform3D).affine_inverse()
			var h: Vector3 = b[1]
			for p in mitten:
				var q: Vector3 = inv * (xf * p)
				if absf(q.x) < h.x and absf(q.y) < h.y and absf(q.z) < h.z:
					hits.append("%s@%s out %s" % [h * 2.0, (b[0] as Transform3D).origin, b[2]])
					break
		print("  hand %d: %s %s" % [i, driver._clear_offset(xf, mitten, [pocket]), hits])
