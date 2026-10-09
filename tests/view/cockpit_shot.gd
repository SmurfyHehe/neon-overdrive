extends SceneTree

# Screenshots of the cockpit view for review (not a pass/fail test): boots the
# car in NEON_CAR (default: the selected one), switches to the cockpit view and
# saves one PNG per FOV listed in -- --fovs=62,70 (default: the car's own).
# --chase keeps the chase view; --drive=<s> holds full throttle that long first.
# Writes to -- --out=<dir> (default user://cockpit_shots). Needs a real renderer:
#   NEON_CAR=p6_crossover godot --audio-driver Dummy --path . -s res://tests/view/cockpit_shot.gd -- --out=C:/tmp/shots

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	var out := "user://cockpit_shots"
	var fovs: Array[float] = []
	var chase := false
	var drive_secs := 0.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a == "--chase":
			chase = true
		elif a.begins_with("--drive="):
			drive_secs = float(a.trim_prefix("--drive="))
		elif a.begins_with("--fovs="):
			for f in a.trim_prefix("--fovs=").split(","):
				fovs.append(float(f))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var game: Node = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for i in 90:
		await process_frame
	var cam: ChaseCamera = game.get("camera")
	if not chase:
		cam.set_view(ChaseCamera.View.COCKPIT)
	if drive_secs > 0.0:
		var p: PlayerCar = game.get("player")
		p.driver = func(c: PlayerCar) -> void:
			c.throttle_input = 1.0
			c.brake_input = 0.0
			c.steering_input = 0.0
		for i in int(drive_secs * 60.0):
			await physics_frame
	var kind := PlayerCar.chassis_kind()
	if fovs.is_empty():
		fovs.append(-1.0)
	for f in fovs:
		if f > 0.0:
			ViewSettings.set_cockpit_fov(f)
		for i in 20:
			await process_frame
		var img := root.get_texture().get_image()
		var path := ProjectSettings.globalize_path("%s/%s_%s_fov%.0f.png" % [out, kind, "chase" if chase else "cockpit", cam.fov])
		img.save_png(path)
		print("shot: %s (fov %.1f, eye %s)" % [path, cam.fov, cam.eye])
	quit(0)
