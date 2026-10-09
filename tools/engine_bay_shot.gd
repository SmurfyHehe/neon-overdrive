extends SceneTree

# Renders the coupe with its hood up, for judging the engine bay by eye: the
# game boots, photo mode opens the hood, and three cameras shoot the bay from
# the front three-quarter, straight over the nose and from the driver's side.
# Needs the real renderer (no --headless). Writes PNGs to user://engine_bay/.
#
#   <godot> --path . -s res://tools/engine_bay_shot.gd

const Harness := preload("res://tests/traffic_harness.gd")

var game: Node

func _initialize() -> void:
	OS.set_environment("NEON_TEST_CAR", "")
	game = Harness.boot(self, 0, 300.0, 3)
	_run.call_deferred()

func _run() -> void:
	var p: PlayerCar = game.get("player")
	while not p.is_ready:
		await physics_frame
	for i in 90:   # settle on the springs
		await physics_frame
	var bay: EngineBay = p.engine_bay
	if bay == null:
		print("engine_bay_shot: no EngineBay on the player")
		quit(1)
		return
	game.get("game_state").toggle_photo()
	for i in 600:  # the swing runs through the pause; wait for it to finish
		await process_frame
		if is_equal_approx(bay.angle, EngineBay.OPEN_ANGLE):
			break
	print("engine_bay_shot: hood angle %.1f, open %s" % [bay.angle, bay.is_open])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://engine_bay"))
	var car_t := p.global_transform
	var bay_centre := car_t * Vector3(0.0, 0.6, -1.3)
	var cam := Camera3D.new()
	cam.fov = 45.0
	root.add_child(cam)
	var views := {
		"front34": Vector3(-2.6, 1.9, -4.2),
		"nose": Vector3(0.0, 2.6, -3.4),
		"side": Vector3(-3.6, 1.5, -1.0),
	}
	for v in views:
		cam.global_position = car_t * views[v]
		cam.look_at(bay_centre)
		cam.make_current()
		for i in 10:
			await process_frame
		var path := "user://engine_bay/%s.png" % v
		root.get_viewport().get_texture().get_image().save_png(path)
		print("engine_bay_shot: ", ProjectSettings.globalize_path(path))
	quit(0)
