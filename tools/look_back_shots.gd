extends SceneTree

# Screenshots of the cockpit look-back for review (not a pass/fail test): the
# view ahead, part way through the head's turn, and held at the rear window,
# for one car. Writes PNGs to -- --out=<dir> (default user://look_back_shots),
# named <car>_<shot>.png. Needs a real renderer; NEON_CAR picks the car:
#   set NEON_CAR=p1_coupe
#   godot --audio-driver Dummy --path . -s res://tools/look_back_shots.gd -- --out=C:/tmp/shots

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	var out := "user://look_back_shots"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var game: Node = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for i in 60:
		await process_frame
	var cam: ChaseCamera = game.get("camera")
	var car := PlayerCar.chassis_kind()
	cam.set_view(ChaseCamera.View.COCKPIT)
	for i in 30:
		await process_frame
	await _shot(out, car, "ahead")
	Input.action_press("look_back")
	for i in 8:
		await process_frame
	await _shot(out, car, "turning")
	for i in 40:
		await process_frame
	await _shot(out, car, "back")
	Input.action_release("look_back")
	for i in 40:
		await process_frame
	await _shot(out, car, "released")
	quit(0)

func _shot(out: String, car: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	var path := "%s/%s_%s.png" % [out, car, name]
	img.save_png(path)
	print("wrote ", ProjectSettings.globalize_path(path))
