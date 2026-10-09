extends SceneTree

# Renders every player car for the interior/exterior/underside pass
# (2026-10-09), for judging by eye: the cockpit view from the driver's eye,
# a three-quarter view from outside at the glass (the cabin shows through),
# a side view at the door, and one from below the road surface looking up
# at the underside. Needs the real renderer (no --headless). Writes PNGs to
# user://car_fit_shots/<kind>_<view>.png.
#
#   <godot> --path . -s res://tools/car_fit_shots.gd
#   NEON_FIT_CAR=p4_kei limits it to one car.

const VIEWS := {
	# name: [camera position (car space), look-at point (car space), fov]
	"cockpit": [Vector3.ZERO, Vector3(0.0, 0.0, -10.0), 62.0],   # from the car's own eye (filled per car)
	"outside": [Vector3(-3.6, 1.9, -3.4), Vector3(0.0, 0.9, 0.0), 40.0],
	"side": [Vector3(-4.2, 1.15, 0.2), Vector3(0.0, 0.95, 0.1), 36.0],
	"rear_quarter": [Vector3(3.2, 1.7, 3.6), Vector3(0.0, 0.9, 0.2), 40.0],
	"below": [Vector3(-0.9, -1.6, 0.4), Vector3(0.0, 0.3, 0.0), 70.0],
	"cockpit_wide": [Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, -10.0), 90.0],
}

var game: Node
var lamp: OmniLight3D

func _initialize() -> void:
	AudioSettings.path = "user://car_fit_shots_settings.cfg"
	OS.set_environment("NEON_TRAFFIC", "0")
	_run.call_deferred()

func _run() -> void:
	var only := OS.get_environment("NEON_FIT_CAR")
	var dir := ProjectSettings.globalize_path("user://car_fit_shots")
	DirAccess.make_dir_recursive_absolute(dir)
	for k in PlayerCars.KINDS:
		var kind := String(k.id)
		if only != "" and kind != only:
			continue
		await _shoot(kind, dir)
	print("car_fit_shots: wrote to %s" % dir)
	quit(0)

func _shoot(kind: String, dir: String) -> void:
	OS.set_environment("NEON_CAR", kind)
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for i in 30:
		await process_frame
	var p: PlayerCar = game.get("player")
	var cam: ChaseCamera = game.get("camera")
	p.driver = func(c: PlayerCar) -> void:
		c.throttle_input = 0.0
		c.brake_input = 1.0
		c.steering_input = 0.0
	cam.shake_enabled = false
	for i in 90:
		await physics_frame
	var shot := Camera3D.new()
	shot.near = 0.03
	shot.far = 400.0
	root.add_child(shot)
	var frame: CockpitFrame = cam.frame
	var eye: Vector3 = frame.cab.eye
	for view in VIEWS:
		var v: Array = VIEWS[view]
		var from: Vector3 = v[0]
		var at: Vector3 = v[1]
		var cockpit: bool = String(view).begins_with("cockpit")
		if cockpit:
			from = eye
			at = eye + Vector3(0.0, -0.05, -10.0)
			cam.set_view(ChaseCamera.View.COCKPIT)
			shot.cull_mask = cam.cull_mask
		else:
			cam.set_view(ChaseCamera.View.CHASE)
			shot.cull_mask = cam.cull_mask
		for i in 4:
			await physics_frame
		var xf: Transform3D = p.global_transform
		shot.fov = float(v[2])
		shot.global_position = xf * from
		shot.look_at(xf * at)
		if view == "below":
			# the road is in the way: look up from under it with the road layer off,
			# and a work light under the car (nothing lights an underside at night)
			shot.cull_mask &= ~1
			shot.cull_mask |= 1 << (CarFx.CAR_LAYER - 1)
			if lamp == null:
				lamp = OmniLight3D.new()
				lamp.light_energy = 3.0
				lamp.omni_range = 6.0
				lamp.light_color = Color(1.0, 0.9, 0.75)
				root.add_child(lamp)
			lamp.global_position = xf * Vector3(0.0, -0.6, 0.0)
			lamp.visible = true
		elif lamp != null:
			lamp.visible = false
		shot.make_current()
		for i in 8:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [dir, kind, view])
	print("%s: %d cockpit triangles" % [kind, frame.triangle_count()])
	shot.queue_free()
	game.queue_free()
	for i in 4:
		await process_frame
