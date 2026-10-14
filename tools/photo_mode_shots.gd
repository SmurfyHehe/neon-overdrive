extends SceneTree

# Photo mode shots, for judging by eye (camera proposal 2026-10-13, section 3):
# the car stopped on the road, photo mode opened, then the six-shot sheet:
# orbit low front, orbit rear three-quarter, free high, blur off and on, tilt.
# Needs the real renderer (no --headless). NEON_CAR=<kind> picks the car;
# NEON_SHOT_DIR the output folder.
#
#   NEON_CAR=p1_coupe <godot> --path . -s res://tools/photo_mode_shots.gd

var game: Node

func _initialize() -> void:
	AudioSettings.path = "user://photo_mode_shots_settings.cfg"
	OS.set_environment("NEON_TRAFFIC", "0")
	OS.set_environment("NEON_CURVES", "0")
	OS.set_environment("NEON_HILLS", "0")
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	_run.call_deferred()

func _run() -> void:
	var gs: GameState = game.get("game_state")
	var cam: ChaseCamera = game.get("camera")
	var photo: PhotoMode
	for c in game.get_children():
		if c is PhotoMode:
			photo = c
	cam.shake_enabled = false
	var dir := OS.get_environment("NEON_SHOT_DIR")
	if dir == "":
		dir = "C:/SmurfyHehe/review-shots/photo-mode"
	DirAccess.make_dir_recursive_absolute(dir)
	var kind := PlayerCar.chassis_kind()
	for i in 120:
		await process_frame
	gs.toggle_photo()
	for i in 10:
		await process_frame
	# 1: orbit, low front three-quarter, close
	photo.set_orbit(true)
	photo.orbit_yaw = deg_to_rad(180.0 + 35.0)
	photo.orbit_dist = 4.2
	photo.orbit_height = 0.1
	photo.aim_pitch = 0.0
	photo.free_cam.fov = 45.0
	await _shot(dir, kind, "1_orbit_low_front", photo)
	# 2: orbit, rear three-quarter, a little high
	photo.orbit_yaw = deg_to_rad(-40.0)
	photo.orbit_dist = 6.0
	photo.orbit_height = 1.6
	await _shot(dir, kind, "2_orbit_rear_34", photo)
	# 3: free, high over the road looking down at the car
	photo.set_orbit(false)
	var c := photo.aim_point()
	photo.free_cam.global_position = c + Vector3(3.0, 5.0, 7.0)
	photo.free_cam.look_at(c, Vector3.UP)
	var e := photo.free_cam.global_transform.basis.get_euler()
	photo._pitch = e.x
	photo._yaw = e.y
	await _shot(dir, kind, "3_free_high", photo)
	# 4 and 5: orbit side, blur off then on
	photo.set_orbit(true)
	photo.orbit_yaw = deg_to_rad(90.0 + 20.0)
	photo.orbit_dist = 5.0
	photo.orbit_height = 0.8
	photo.blur = 0.0
	await _shot(dir, kind, "4_side_sharp", photo)
	photo.blur = 7.0
	await _shot(dir, kind, "5_side_blur_7", photo)
	# 6: tilt
	photo.blur = 0.0
	photo.roll = 25.0
	await _shot(dir, kind, "6_tilt_25", photo)
	quit(0)

func _shot(dir: String, kind: String, tag: String, photo: PhotoMode) -> void:
	photo.step(0.0)
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := "%s/%s_%s.png" % [dir, kind, tag]
	img.save_png(path)
	print("shot ", path)
