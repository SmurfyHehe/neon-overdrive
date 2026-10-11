extends SceneTree

# Renders the flip-off (K) mid-gesture, for judging it by eye: the game's own
# cockpit and chase cameras with the window down, the cockpit with the window
# shut, and one close view from outside the driver's door. Needs the real
# renderer (no --headless). Writes PNGs to screenshots/gesture/ in the project
# folder (not committed). NEON_CAR picks the car.
#
#   <godot> --path . -s res://tools/gesture_shots.gd

var game: Node

func _initialize() -> void:
	AudioSettings.path = "user://gesture_shots_settings.cfg"
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
		c.steering_input = 0.0
	cam.shake_enabled = false
	var d: DriverModel = cam.frame.driver
	for i in 60:
		await physics_frame
	var dir := ProjectSettings.globalize_path("res://screenshots/gesture")
	DirAccess.make_dir_recursive_absolute(dir)
	var kind := PlayerCar.chassis_kind()
	var close := Camera3D.new()
	close.fov = 55.0
	close.near = 0.03
	root.add_child(close)
	for mark in [["down", 1.0], ["shut", 0.0]]:
		cam.perspective.window = mark[1]
		for i in 5:
			await physics_frame
		Input.action_press("flip_off")   # held: the hand stays up for the shots
		while d.left_act != DriverModel.LeftAct.GESTURE_HOLD:
			await physics_frame
		for view in ["cockpit", "chase", "close"]:
			if view == "close":
				var xf: Transform3D = p.global_transform
				close.global_position = xf * Vector3(-2.3, 1.35, -1.9)
				close.look_at(xf * Vector3(-0.8, 1.05, -0.3))
				close.make_current()
			else:
				cam.set_view(ChaseCamera.View.COCKPIT if view == "cockpit" else ChaseCamera.View.CHASE)
				cam.make_current()
			for i in 40:
				await process_frame
			root.get_viewport().get_texture().get_image().save_png("%s/%s_%s_window_%s.png" % [dir, kind, view, mark[0]])
			print("%s %s window %s: hand at %s" % [kind, view, mark[0], str(d.finger_hand.position)])
		Input.action_release("flip_off")
		while d.is_gesturing():
			await physics_frame
	quit(0)
