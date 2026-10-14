extends SceneTree

# Photo mode, every player car and every view (Roy 2026-10-14: a change must
# reach everything in the game, and a test must loop over it). Each car boots
# as the player's car (NEON_CAR); in the chase, cockpit and hood views, and
# from the pause menu, P opens photo mode and the orbit must:
#   - start outside the car's own body (a kei car and the Camel alike),
#   - look at the middle of that body,
#   - draw the body (in the cockpit view it sits on the mirror-only layer),
#   - stay outside the body with W held to the near limit,
#   - never drop under the car's floor with Q held,
# and leaving must hand the view back to the camera it came from.
# Exit code 1 on failure. NEON_FIT_CAR=p5_muscle limits the run to one car.
#   <godot> --headless --audio-driver Dummy --path . -s res://tests/ui/photo_mode_fleet.gd
const Harness := preload("res://tests/traffic/traffic_harness.gd")

const RATE := 60
const VIEWS := [ChaseCamera.View.CHASE, ChaseCamera.View.COCKPIT, ChaseCamera.View.HOOD]

var fails := 0
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
		await _car(String(k.id))
	OS.set_environment("NEON_CAR", "")
	if logger.errors.size() > 0:
		print("FAIL %d engine errors: %s" % [logger.errors.size(), str(logger.errors.slice(0, 5))])
		fails += logger.errors.size()
	print("photo_mode_fleet: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)

func _car(kind: String) -> void:
	OS.set_environment("NEON_CAR", kind)
	var game: Node = Harness.boot(self, 0, 150.0, 7, 1.0e6)
	for i in RATE:
		await physics_frame
	var p: PlayerCar = game.get("player")
	var cam: ChaseCamera = game.get("camera")
	var gs: GameState = game.get("game_state")
	var photo: PhotoMode
	for c in game.get_children():
		if c is PhotoMode:
			photo = c
	_check(p != null and cam != null and gs != null and photo != null, "%s: the game should boot with a photo mode" % kind)
	if p == null or cam == null or gs == null or photo == null:
		game.queue_free()
		await process_frame
		return
	p.driver = func(c: PlayerCar) -> void:
		c.throttle_input = 0.0
		c.brake_input = 1.0
		c.steering_input = 0.0
	for v in VIEWS:
		cam.set_view(v)
		for i in 10:
			await physics_frame
		var seen := root.get_viewport().get_camera_3d()
		gs.toggle_photo()
		for i in 3:
			await process_frame
		_check(gs.state == GameState.State.PHOTO and photo.free_cam.current, "%s view %d: P should open photo mode on the photo camera" % [kind, v])
		_orbit_checks(kind, "view %d" % v, p, photo)
		gs.close_photo()
		for i in 3:
			await process_frame
		_check(gs.state == GameState.State.PLAYING and seen != null and seen.current, "%s view %d: leaving should hand the view back" % [kind, v])
		_check(cam.view == v, "%s: leaving photo mode keeps the view (%d vs %d)" % [kind, cam.view, v])
	# The pause menu route: the pause look's orbit camera is current there.
	cam.set_view(ChaseCamera.View.CHASE)
	gs.pause()
	for i in 5:
		await process_frame
	gs.open_photo_from_pause()
	for i in 3:
		await process_frame
	_check(gs.state == GameState.State.PHOTO and photo.free_cam.current, "%s pause: the pause row should open photo mode" % kind)
	_orbit_checks(kind, "pause", p, photo)
	gs.close_photo()
	for i in 3:
		await process_frame
	_check(gs.state == GameState.State.PAUSED, "%s pause: Esc goes back to the pause menu" % kind)
	gs.resume()
	for i in 3:
		await process_frame
	game.queue_free()
	await process_frame

func _orbit_checks(kind: String, where: String, p: PlayerCar, photo: PhotoMode) -> void:
	var tag := "%s %s" % [kind, where]
	var box := photo.car_box()
	_check(box.size.x > 1.0 and box.size.z > 2.0 and box.size.y > 0.8, "%s: the body should measure as a car (%s)" % [tag, str(box.size)])
	_check(photo.orbit, "%s: photo mode opens in orbit" % tag)
	_check(_outside(p, box, photo.free_cam.global_position), "%s: the orbit should start outside the body" % tag)
	_check(_looks_at(photo), "%s: the orbit should look at the car" % tag)
	# Every piece of the body is on a layer the photo camera draws.
	var unseen := 0
	for n in p.chassis_visual.find_children("*", "VisualInstance3D", true, false):
		if n is Light3D:
			continue
		if (n as VisualInstance3D).layers & photo.free_cam.cull_mask == 0:
			unseen += 1
	_check(unseen == 0, "%s: %d body parts are on layers the photo camera does not draw" % [tag, unseen])
	# W to the near limit, from a few angles: still outside the skin.
	for a in [0.0, 45.0, 90.0, 135.0, 180.0]:
		photo.orbit_yaw = deg_to_rad(a)
		Input.action_press("photo_forward")
		photo.step(10.0)
		Input.action_release("photo_forward")
		_check(_outside(p, box, photo.free_cam.global_position), "%s: at the near limit from %.0f deg the camera is inside the body" % [tag, a])
		_check(_looks_at(photo), "%s: at the near limit from %.0f deg the orbit looks away from the car" % [tag, a])
	# Q to the floor: never under the car.
	Input.action_press("photo_down")
	photo.step(10.0)
	Input.action_release("photo_down")
	var cam_local: Vector3 = p.global_transform.affine_inverse() * photo.free_cam.global_position
	_check(cam_local.y > box.position.y, "%s: Q drops the camera under the car's floor (%.2f vs %.2f)" % [tag, cam_local.y, box.position.y])
	photo.orbit_dist = 6.0
	photo.orbit_height = 2.0

func _outside(p: PlayerCar, box: AABB, pos: Vector3) -> bool:
	var local: Vector3 = p.global_transform.affine_inverse() * pos
	return not box.grow(0.2).has_point(local)

func _looks_at(photo: PhotoMode) -> bool:
	var fwd := -photo.free_cam.global_basis.z
	var to := (photo.aim_point() - photo.free_cam.global_position).normalized()
	return fwd.dot(to) > 0.98
