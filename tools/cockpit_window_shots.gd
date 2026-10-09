extends SceneTree

# Renders the side window animation in the cockpit view, for judging it by
# eye: for each window control (switch, then crank, swapped live on the same
# cabin) the window shut, half way and fully down, from the driver's eye
# looking at the door, plus one from the passenger seat looking across. Needs
# the real renderer (no --headless). Writes PNGs to user://cockpit_window_shots/.
#
#   <godot> --path . -s res://tools/cockpit_window_shots.gd

var game: Node

func _initialize() -> void:
	AudioSettings.path = "user://cockpit_window_shots_settings.cfg"
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
	cam.set_view(ChaseCamera.View.COCKPIT)
	var frame: CockpitFrame = cam.frame
	var d: DriverModel = frame.driver
	for i in 60:
		await physics_frame
	var dir := ProjectSettings.globalize_path("user://cockpit_window_shots")
	DirAccess.make_dir_recursive_absolute(dir)
	var shot := Camera3D.new()
	shot.fov = 70.0
	shot.near = 0.03
	root.add_child(shot)
	for control in ["switch", "crank"]:
		frame.set_window_control(control)
		for mark in [["shut", 0.0], ["half", 0.5], ["down", 1.0]]:
			var openness: float = mark[1]
			# The real key, through the camera, so the shot is what the game
			# shows: held until the window reaches the mark (the hand is at
			# the control while it is held), nothing pressed for "shut".
			if openness > 0.0:
				Input.action_press("window")
				while cam.window_openness() < openness:
					await physics_frame
				for i in 3:
					await physics_frame
			# the driver's eye, turned to the door
			var xf: Transform3D = p.global_transform
			var eye := xf * ChaseCamera.COCKPIT_EYE
			shot.global_position = eye
			shot.look_at(xf * Vector3(-0.83, 0.80, -0.10))
			shot.make_current()
			for i in 6:
				await process_frame
			root.get_viewport().get_texture().get_image().save_png("%s/%s_%s_driver.png" % [dir, control, mark[0]])
			# across from the passenger seat, so the hand, the control and the glass read together
			shot.global_position = xf * Vector3(0.30, 1.05, 0.35)
			shot.look_at(xf * Vector3(-0.80, 0.85, -0.10))
			for i in 6:
				await process_frame
			root.get_viewport().get_texture().get_image().save_png("%s/%s_%s_across.png" % [dir, control, mark[0]])
			print("%s %s: window %.2f glass bottom %.3f left hand at window %s" % [control, mark[0], frame.window, frame.glass_bottom_y(), str(d.left_at_window())])
			# back up for the next mark: release, then a tap rolls it all the way up
			Input.action_release("window")
			for i in 20:
				await physics_frame
			Input.action_press("window")
			for i in 3:
				await physics_frame
			Input.action_release("window")
			while cam.window_openness() > 0.0:
				await physics_frame
			for i in 60:
				await physics_frame
	print("wrote ", dir)
	quit(0)
