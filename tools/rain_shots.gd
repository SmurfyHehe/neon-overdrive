extends SceneTree

# Screenshots of the falling rain (scripts/fx/rain_fall.gd) for judging it by
# eye: the chase view and a low eye-level view, dry, in steady rain and in a
# downpour, standing still and at speed (the streaks lean back), the
# downpour on the Low preset, and the cockpit with drops on the glass. Boots the real game scene with no traffic and
# pins the weather stage (Weather.set_level, instant: wet road, puddles and
# wipers come with it). Needs the real renderer (no --headless). Writes PNGs
# to user://rain_shots/.
#
#   <godot> --path . -s res://tools/rain_shots.gd
#   cloud: xvfb-run -a <godot> --rendering-driver opengl3 --path . -s res://tools/rain_shots.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const Weather := preload("res://scripts/world/weather.gd")

var game: Node

func _initialize() -> void:
	game = Harness.boot(self, 0, 300.0, 7)
	_run.call_deferred()

func _run() -> void:
	for i in 30:
		await process_frame
	var p: PlayerCar = game.get("player")
	Harness.launch_player(p, 12.0)
	for i in 90:
		await physics_frame
	p.linear_velocity = Vector3.ZERO
	p.angular_velocity = Vector3.ZERO
	for i in 30:
		await physics_frame
	var dir := ProjectSettings.globalize_path("user://rain_shots")
	DirAccess.make_dir_recursive_absolute(dir)
	var chase: Camera3D = root.get_viewport().get_camera_3d()
	var eye := Camera3D.new()
	eye.fov = 60.0
	root.add_child(eye)
	var shots := {
		"dry": [Weather.Level.DRY, "medium"],
		"rain": [Weather.Level.RAIN, "medium"],
		"downpour": [Weather.Level.DOWNPOUR, "medium"],
		"downpour_low": [Weather.Level.DOWNPOUR, "low"],
	}
	for name in shots:
		Weather.set_level(shots[name][0], true)
		GraphicsSettings.set_preset(shots[name][1])
		GraphicsSettings.apply(self)
		for i in 6:
			await physics_frame
		chase.make_current()
		await _shoot("%s/%s_chase.png" % [dir, name])
		eye.global_position = p.global_position + Vector3(1.5, 1.2, 0.0)
		eye.look_at(p.global_position + Vector3(0.0, 0.6, -60.0))
		eye.make_current()
		await _shoot("%s/%s_eye.png" % [dir, name])
	# cockpit: drops on the glass, the wipers mid-sweep
	Weather.set_level(Weather.Level.DOWNPOUR, true)
	GraphicsSettings.set_preset("medium")
	GraphicsSettings.apply(self)
	var cam: ChaseCamera = game.get("camera")
	cam.set_view(ChaseCamera.View.COCKPIT)
	for i in 150:
		await physics_frame
	await _shoot("%s/downpour_cockpit.png" % dir)
	for i in 40:
		await physics_frame
	await _shoot("%s/downpour_cockpit_b.png" % dir)
	cam.set_view(ChaseCamera.View.CHASE)
	# at speed: the streaks lean back
	Weather.set_level(Weather.Level.DOWNPOUR, true)
	GraphicsSettings.set_preset("medium")
	GraphicsSettings.apply(self)
	chase.make_current()
	Harness.launch_player(p, 35.0)
	for i in 20:
		await physics_frame
	await _shoot("%s/downpour_speed_chase.png" % dir)
	print("rain_shots: wrote PNGs to ", dir)
	quit(0)

func _shoot(path: String) -> void:
	for i in 12:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(path)
