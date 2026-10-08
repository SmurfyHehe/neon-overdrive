extends SceneTree

# Cockpit screenshots (interiors pass, 2026-10-08). Not a pass/fail test: boots
# the real Game.tscn with a real renderer, switches to the cockpit view and
# saves PNGs of the interior straight ahead at rest, at speed and in a corner,
# so a person can judge the look. NEON_INTERIOR picks the interior style
# (InteriorStyle ids; default the car's own), SHOT_DIR the output folder
# (default user://cockpit_shots), SHOT_TAG a filename prefix.
# Run (needs a window, so no --headless):
#   Godot_v4.7.2-stable_win64_console.exe --audio-driver Dummy --path . -s res://tests/cockpit_shots.gd

const SIZE := Vector2i(1280, 720)

# members, not locals: a lambda copies the locals it captures
var throttle := 0.0
var steer := 0.0

func _initialize() -> void:
	ExhaustTune.save_path = "user://autotune/test_cockpit_shots_exhaust.json"
	root.size = SIZE
	DisplayServer.window_set_size(SIZE)
	change_scene_to_file("res://Game.tscn")
	_run.call_deferred()

func _run() -> void:
	var game: Node = null
	for i in 600:
		await physics_frame
		game = current_scene
		if game != null and game.get("player") != null and game.get("camera") != null:
			break
	if game == null or game.get("player") == null:
		push_error("cockpit_shots: the game never became ready")
		quit(1)
		return
	var p: PlayerCar = game.player
	var cam: ChaseCamera = game.camera
	var dir := OS.get_environment("SHOT_DIR")
	if dir == "":
		dir = ProjectSettings.globalize_path("user://cockpit_shots")
	DirAccess.make_dir_recursive_absolute(dir)
	var tag := OS.get_environment("SHOT_TAG")
	if tag == "":
		tag = "cockpit"
	p.driver = _drive
	if OS.get_environment("SHOT_BOOST") != "":
		p.turbo_boost_max = float(OS.get_environment("SHOT_BOOST"))   # shows the boost pod
	cam.set_view(ChaseCamera.View.COCKPIT)
	await _secs(1.5)
	await _shot(dir, tag + "_1_rest")
	throttle = 1.0
	var t := 0.0
	while absf(p.current_speed()) * 3.6 < 100.0 and t < 14.0:
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
	await _shot(dir, tag + "_2_speed")
	throttle = 0.5
	steer = 0.6
	await _secs(0.6)
	await _shot(dir, tag + "_3_corner")
	steer = 0.0
	await _secs(1.4)
	await _shot(dir, tag + "_4_sweep")
	# Two views of the cabin itself: from the passenger seat toward the driver,
	# and from the back over the console. Same layers as the cockpit camera.
	throttle = 0.0
	var free := Camera3D.new()
	free.fov = 70.0
	free.near = 0.02
	free.cull_mask = cam.cull_mask
	p.add_child(free)
	for v in [[Vector3(0.42, 1.16, 0.62), Vector3(-0.36, 0.78, -0.30), "_5_cabin"], [Vector3(0.05, 1.24, 0.95), Vector3(-0.15, 0.78, -0.45), "_6_console"]]:
		free.position = v[0]
		free.look_at(p.to_global(v[1]))
		free.make_current()
		await _secs(0.3)
		await _shot(dir, tag + v[2])
	print("cockpit_shots: ", dir)
	quit(0)

func _drive(c: PlayerCar) -> void:
	c.throttle_input = throttle
	c.brake_input = 0.0
	c.steering_input = steer

func _secs(s: float) -> void:
	var t := 0.0
	while t < s:
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second

func _shot(dir: String, name: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(dir.path_join(name + ".png"))
