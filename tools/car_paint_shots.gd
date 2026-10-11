extends SceneTree

# Outside pictures of ONE player car for the paint look pass (2026-10-10):
# three-quarter front, three-quarter rear and side, from the same fixed
# cameras, seed and work light as the cabin audit's review pictures
# (tools/car_review_shots.gd on the audit branch), so they line up with the
# "before" set in review-shots/cars-before-2026-10-10.
#   <kind>_<view>.png       the Medium preset, with the work light (as before)
#   <kind>_<view>_high.png  the High preset, no work light: only what the
#                           game itself puts on the car
# Real renderer (no --headless): a window opens for a few seconds. One car
# per run, so only one Godot is ever open:
#
#   set NEON_CAR=p5_muscle
#   set NEON_SHOT_DIR=C:\SmurfyHehe\review-shots\cars-paint-after-2026-10-10
#   <godot> --path . --audio-driver Dummy -s res://tools/car_paint_shots.gd
#
# Without NEON_SHOT_DIR it writes to user://car_paint_shots. The coupe is
# shown washed (its dirt uniform is zeroed for the picture only; the saved
# dirt level is not touched), since the pictures are for judging the paint.

const SEED := 7
const VIEWS := {
	# name: [camera position, look-at point (car space; -z forward, -x the driver's side), fov]
	"front34": [Vector3(-3.7, 1.55, -4.9), Vector3(0.0, 0.7, 0.0), 40.0],
	"rear34": [Vector3(3.7, 1.55, 4.9), Vector3(0.0, 0.7, 0.0), 40.0],
	"side": [Vector3(-7.2, 1.1, 0.0), Vector3(0.0, 0.8, 0.0), 36.0],
}
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
		dir = ProjectSettings.globalize_path("user://car_paint_shots")
	DirAccess.make_dir_recursive_absolute(dir)
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for i in 30:
		await process_frame
	var p: PlayerCar = game.get("player")
	var cam: ChaseCamera = game.get("camera")
	if p == null or cam == null:
		printerr("car_paint_shots: the game did not boot a player car")
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
	root.add_child(fill)
	cam.set_view(ChaseCamera.View.CHASE)
	var paint_mat: ShaderMaterial = null
	if p.chassis_visual.has_meta("body_mat"):
		paint_mat = p.chassis_visual.get_meta("body_mat")
	for tier: String in ["medium", "high"]:
		var lit := tier == "medium"
		fill.visible = lit
		GraphicsSettings.set_preset(tier)
		TrafficSettings.set_car_count(0)   # the preset brings its own traffic
		GraphicsSettings.apply(self)
		for view in VIEWS:
			var v: Array = VIEWS[view]
			for i in 6:
				await physics_frame
			var xf: Transform3D = p.global_transform
			shot.cull_mask = cam.cull_mask
			shot.fov = float(v[2])
			shot.global_position = xf * (v[0] as Vector3)
			shot.look_at(xf * (v[1] as Vector3))
			fill.global_position = xf * ((v[0] as Vector3) * 0.8 + Vector3(0.0, 1.6, 0.0))
			shot.make_current()
			for i in 8:
				await process_frame
			if paint_mat != null:
				paint_mat.set_shader_parameter("dirt", 0.0)
			await RenderingServer.frame_post_draw
			var path := "%s/%s_%s%s.png" % [dir, kind, view, "" if lit else "_high"]
			root.get_viewport().get_texture().get_image().save_png(path)
			print("car_paint_shots: ", path)
	quit(0)
