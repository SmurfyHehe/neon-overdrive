extends SceneTree

# Fixed review pictures of ONE player car, for a before/after pair (cabin
# audit, 2026-10-10): three-quarter front, three-quarter rear and side from
# outside, the cockpit as the player sees it, and a wide cockpit view that
# takes in the dash, the lever and the seat. The cameras, the seed and the
# settings file are fixed, so a later run of the same car lines up with an
# earlier one. Real renderer (no --headless): a window opens for a few
# seconds. One car per run, so only one Godot is ever open:
#
#   set NEON_CAR=p5_muscle
#   set NEON_SHOT_DIR=C:\SmurfyHehe\review-shots\cars-before-2026-10-10
#   <godot> --path . --audio-driver Dummy -s res://tools/car_review_shots.gd
#
# Writes <dir>/<kind>_<view>.png. Without NEON_SHOT_DIR it writes to
# user://car_review_shots.

const SEED := 7
const VIEWS := {
	# name: [camera position, look-at point (car space; -z forward, -x the driver's side), fov]
	"front34": [Vector3(-3.7, 1.55, -4.9), Vector3(0.0, 0.7, 0.0), 40.0],
	"rear34": [Vector3(3.7, 1.55, 4.9), Vector3(0.0, 0.7, 0.0), 40.0],
	"side": [Vector3(-7.2, 1.1, 0.0), Vector3(0.0, 0.8, 0.0), 36.0],
	"cockpit": [],        # the game's own cockpit camera
	"cockpit_wide": [],   # from the same eye, 90 degrees, tipped down to the lever
}
## A work light beside the outside cameras: the street at night shows a
## silhouette and little else, and the pictures are for judging shape.
const FILL_ENERGY := 2.2

var game: Node

func _initialize() -> void:
	AudioSettings.path = "user://car_review_shots_settings.cfg"
	OS.set_environment("NEON_TRAFFIC", "0")
	OS.set_environment("NEON_RNG_SEED", str(SEED))
	seed(SEED)
	_run.call_deferred()

func _run() -> void:
	var kind := PlayerCar.chassis_kind()
	var dir := OS.get_environment("NEON_SHOT_DIR")
	if dir == "":
		dir = ProjectSettings.globalize_path("user://car_review_shots")
	DirAccess.make_dir_recursive_absolute(dir)
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for i in 30:
		await process_frame
	var p: PlayerCar = game.get("player")
	var cam: ChaseCamera = game.get("camera")
	if p == null or cam == null:
		printerr("car_review_shots: the game did not boot a player car")
		quit(1)
		return
	p.driver = func(c: PlayerCar) -> void:
		c.throttle_input = 0.0
		c.brake_input = 1.0
		c.steering_input = 0.0
	cam.shake_enabled = false
	for i in 120:
		await physics_frame
	var shot := Camera3D.new()
	shot.near = 0.03
	shot.far = 400.0
	root.add_child(shot)
	var fill := OmniLight3D.new()
	fill.light_energy = FILL_ENERGY
	fill.omni_range = 14.0
	fill.light_color = Color(1.0, 0.95, 0.88)
	fill.visible = false
	root.add_child(fill)
	var eye: Vector3 = cam.frame.cab.eye if cam.frame != null else Vector3(-0.37, 1.1, 0.2)
	for view in VIEWS:
		var v: Array = VIEWS[view]
		var cockpit: bool = String(view).begins_with("cockpit")
		cam.set_view(ChaseCamera.View.COCKPIT if cockpit else ChaseCamera.View.CHASE)
		for i in 6:
			await physics_frame
		var xf: Transform3D = p.global_transform
		fill.visible = not cockpit
		if view == "cockpit":
			cam.make_current()
		else:
			shot.cull_mask = cam.cull_mask
			if cockpit:
				shot.fov = 90.0
				shot.global_position = xf * eye
				shot.look_at(xf * (eye + Vector3(0.12, -0.45, -1.0)), xf.basis.y)
			else:
				shot.fov = float(v[2])
				shot.global_position = xf * (v[0] as Vector3)
				shot.look_at(xf * (v[1] as Vector3))
				fill.global_position = xf * ((v[0] as Vector3) * 0.8 + Vector3(0.0, 1.6, 0.0))
			shot.make_current()
		for i in 8:
			await process_frame
		await RenderingServer.frame_post_draw
		var path := "%s/%s_%s.png" % [dir, kind, view]
		root.get_viewport().get_texture().get_image().save_png(path)
		print("car_review_shots: ", path)
	quit(0)
