extends SceneTree

# Renders the wheel screen (seven-segment gear and speed) in the cockpit at
# about 240 km/h in 4th, wheel straight and at quarter lock: the game's own
# cockpit view, the same eye pitched down so the whole wheel shows, a close-up
# of the screen, and the instrument cluster (tach with its gear window) over the rim. Needs the
# real renderer (no --headless). Writes PNGs to user://wheel_screen_shots/.
#
#   <godot> --path . --resolution 1280x720 -s res://tools/wheel_screen_shots.gd

const SPEED_MS := 240.0 / 3.6

var game: Node
var steer := 0.0
var parked := false   # the car stops dead for the shot; the cabin keeps what it last showed

func _initialize() -> void:
	AudioSettings.path = "user://wheel_screen_shots_settings.cfg"
	OS.set_environment("NEON_TRAFFIC", "0")
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	_run.call_deferred()

func _run() -> void:
	for i in 30:
		await process_frame
	var p: PlayerCar = game.get("player")
	var cam: ChaseCamera = game.get("camera")
	p.automatic_transmission = false
	p.gravity_scale = 0.0   # fly level at the set speed: hills must not launch or crash the rig
	p.driver = func(c: PlayerCar) -> void:
		c.throttle_input = 0.6
		c.brake_input = 0.0
		c.steering_input = steer
		c.current_gear = 4
		c.requested_gear = 4
		c.linear_velocity = Vector3.ZERO if parked else -c.global_transform.basis.z * SPEED_MS
		c.angular_velocity = Vector3.ZERO
	cam.shake_enabled = false
	cam.set_view(ChaseCamera.View.COCKPIT)
	var frame: CockpitFrame = cam.frame
	var dir := ProjectSettings.globalize_path("user://wheel_screen_shots")
	DirAccess.make_dir_recursive_absolute(dir)
	var shot := Camera3D.new()
	shot.near = 0.02
	root.add_child(shot)
	for mark in [["straight", 0.0], ["quarter_lock", 0.33]]:
		steer = mark[1]
		for i in 90:
			await physics_frame
		# freeze the cockpit's own update (the screen shows 240 in 4th, the wheel
		# holds its angle), stop the car, let the interpolation settle, shoot
		frame.set_process(false)
		parked = true
		for i in 60:
			await physics_frame
		await _shoot(shot, cam, p, frame, dir, mark[0])
		parked = false
		frame.set_process(true)
	print("wrote ", dir)
	quit(0)

func _snap(shot: Camera3D, path: String) -> void:
	for i in 8:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(path)

func _shoot(shot: Camera3D, cam: ChaseCamera, p: PlayerCar, frame: CockpitFrame, dir: String, mark: String) -> void:
	# the camera sits at the car's own eye point (the game's chase smoothing lags
	# behind a car held at 240 km/h) and draws the interior like the game's one
	var eye: Transform3D = p.global_transform * Transform3D(Basis.IDENTITY, ChaseCamera.COCKPIT_EYE)
	shot.cull_mask = cam.cull_mask
	shot.fov = cam.fov
	shot.global_transform = eye
	shot.make_current()
	await _snap(shot, "%s/%s_eye.png" % [dir, mark])
	shot.global_transform = eye * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-22.0)), Vector3.ZERO)
	await _snap(shot, "%s/%s_eye_down.png" % [dir, mark])
	# close-up of the screen from straight in front of the wheel
	var wxf: Transform3D = frame.wheel.global_transform
	shot.fov = 40.0
	shot.global_position = wxf * Vector3(0.0, 0.078, 0.40)
	shot.look_at(wxf * Vector3(0.0, 0.078, 0.0), wxf.basis.y)
	await _snap(shot, "%s/%s_screen.png" % [dir, mark])
	# the instrument cluster over the rim: the tach face with its gear window
	var tach: Vector3 = frame.dial_centres()[0]
	shot.fov = 20.0
	shot.global_transform = eye
	shot.look_at(p.global_transform * tach, p.global_transform.basis.y)
	await _snap(shot, "%s/%s_cluster.png" % [dir, mark])
	print("%s: screen '%s', %d km/h, gear %d, wheel %.0f deg" % [mark, frame.wheel.lcd_text(), Hud.kmh(p.current_speed()), p.gear, rad_to_deg(frame.wheel_angle)])
