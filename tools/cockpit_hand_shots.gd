extends SceneTree

# Renders the hands on the wheel in the cockpit view, for judging the grip
# height and the push-pull shuffle by eye: at rest, a quarter turn each way
# (hands riding the rim), full lock each way (after the shuffle), and three
# frames caught mid-shuffle on the way to full lock. Three views each: the
# game's own cockpit camera (the hands sit at its bottom edge), the same eye
# pitched down so the whole wheel shows, and across the cabin from the
# passenger seat. Needs the real renderer (no --headless). Writes PNGs to
# user://cockpit_hand_shots/. The marks are named by the way the wheel turns
# (steering_input +1 is a left turn in this car, see PlayerCar.steer_fraction).
#
#   <godot> --path . -s res://tools/cockpit_hand_shots.gd

var game: Node
var steer := 0.0

func _initialize() -> void:
	AudioSettings.path = "user://cockpit_hand_shots_settings.cfg"
	OS.set_environment("NEON_TRAFFIC", "0")
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	_run.call_deferred()

func _run() -> void:
	for i in 30:
		await process_frame
	var p: PlayerCar = game.get("player")
	var cam: ChaseCamera = game.get("camera")
	p.driver = func(c: PlayerCar) -> void:
		c.throttle_input = 0.0
		c.brake_input = 1.0
		c.steering_input = steer
	cam.shake_enabled = false
	cam.set_view(ChaseCamera.View.COCKPIT)
	var frame: CockpitFrame = cam.frame
	var d: DriverModel = frame.driver
	for i in 60:
		await physics_frame
	var dir := ProjectSettings.globalize_path("user://cockpit_hand_shots")
	DirAccess.make_dir_recursive_absolute(dir)
	var shot := Camera3D.new()
	shot.fov = 62.0
	shot.near = 0.03
	root.add_child(shot)
	# settled poses: the input held until the wheel stops
	for mark in [["rest", 0.0], ["quarter_left", 0.33], ["quarter_right", -0.33], ["lock_left", 1.0], ["lock_right", -1.0], ["rest_again", 0.0]]:
		steer = mark[1]
		for i in 240:
			await physics_frame
		await _shoot(shot, cam, p, frame, d, dir, mark[0])
	# mid-shuffle: from straight to full lock, a frame every 0.15 s
	steer = 1.0
	for i in 3:
		for j in 9:
			await physics_frame
		await _shoot(shot, cam, p, frame, d, dir, "shuffle_%d" % i)
	steer = 0.0
	for i in 120:
		await physics_frame
	print("wrote ", dir)
	quit(0)

func _shoot(shot: Camera3D, cam: ChaseCamera, p: PlayerCar, frame: CockpitFrame, d: DriverModel, dir: String, mark: String) -> void:
	var xf: Transform3D = p.global_transform
	# the game's own cockpit camera first: what the player sees
	shot.fov = cam.fov
	shot.global_transform = cam.global_transform
	shot.make_current()
	for i in 6:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("%s/%s_eye.png" % [dir, mark])
	# the same eye pitched down, so the whole wheel and both hands show
	shot.global_transform = cam.global_transform * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-22.0)), Vector3.ZERO)
	for i in 6:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("%s/%s_eye_down.png" % [dir, mark])
	shot.fov = 62.0
	# across from the passenger seat, so the hands and the rim read together
	shot.global_position = xf * Vector3(0.25, 1.00, 0.20)
	shot.look_at(xf * (CockpitFrame.WHEEL_POS + Vector3(0.0, 0.03, 0.0)))
	for i in 6:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("%s/%s_across.png" % [dir, mark])
	print("%s: wheel %.0f deg, hands L %.0f (%s) R %.0f (%s), %d shuffles" % [mark, rad_to_deg(frame.wheel_angle),
			d.rim_deg(-1), "holding" if d.is_gripping(-1) else "sliding", d.rim_deg(1), "holding" if d.is_gripping(1) else "sliding", d.shuffle_count])
