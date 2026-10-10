extends SceneTree

# Sky shots (night pass, 2026-10-10): one frame of the sky from the chase
# camera, plus region averages, for before/after comparisons across nights.
# Boots Game.tscn (no traffic), waits for the sky to settle, saves
# SKY_SHOT_DIR/<tag>.png and prints the mean colour of five regions: top of
# sky, mid sky, the horizon gap down the road, and two asphalt patches (left
# lane, right lane). Reports, does not assert.
# Env: NEON_NIGHT=N picks the night (stars, phase, moon path), NEON_CLOCK=HH:MM
# the time, SKY_SHOT_TAG the file name (default night_<N>_<HHMM>), and
# SKY_SHOT_CAM=up swaps in a camera on the car roof tilted 14 degrees up, so
# the moon, stars and glow dome fill the frame (the chase camera mostly
# shows buildings). The road regions are meaningless from that camera.
# Run (real renderer; a window opens briefly):
#   Godot_v4.7.2-stable_win64_console.exe --path . --audio-driver Dummy -s res://tests/world/sky_shots.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const WAIT_FRAMES := 100

var game: Node
var frame := 0

func _initialize() -> void:
	game = Harness.boot(self, 0, 300.0, 7)

func _process(_delta: float) -> bool:
	frame += 1
	var cam_mode := OS.get_environment("SKY_SHOT_CAM")
	if frame == WAIT_FRAMES - 12 and (cam_mode == "up" or cam_mode == "moon"):
		var cam := Camera3D.new()
		cam.fov = 70.0 if cam_mode == "up" else 30.0
		root.add_child(cam)
		var car: Node3D = game.get("player")
		cam.global_position = car.global_position + Vector3(0.0, 1.6, 0.0)
		if cam_mode == "up":
			cam.rotation_degrees = Vector3(14.0, 0.0, 0.0)
		else:
			# A 30 degree lens aimed at the moon: phase and halo close up.
			cam.look_at(cam.global_position + NightSky.moon_dir_of(_env().sky))
		cam.current = true
	if frame < WAIT_FRAMES:
		return false
	var img := root.get_viewport().get_texture().get_image()
	var w := img.get_width()
	var h := img.get_height()
	var regions := {
		"top": Rect2i(int(w * 0.29), int(h * 0.005), int(w * 0.06), int(h * 0.06)),
		"mid": Rect2i(int(w * 0.44), int(h * 0.20), int(w * 0.12), int(h * 0.06)),
		"horizon": Rect2i(int(w * 0.475), int(h * 0.40), int(w * 0.05), int(h * 0.04)),
		"road_l": Rect2i(int(w * 0.18), int(h * 0.80), int(w * 0.08), int(h * 0.05)),
		"road_r": Rect2i(int(w * 0.74), int(h * 0.80), int(w * 0.08), int(h * 0.05)),
	}
	var night := OS.get_environment("NEON_NIGHT")
	var tag := OS.get_environment("SKY_SHOT_TAG")
	if tag == "":
		tag = "night_%s_%s%s" % [night if night != "" else "1", OS.get_environment("NEON_CLOCK").replace(":", ""), "_" + OS.get_environment("SKY_SHOT_CAM") if OS.get_environment("SKY_SHOT_CAM") != "" else ""]
	var line := "sky_shots %s:" % tag
	for k in regions:
		line += " %s=%s" % [k, _avg(img, regions[k]).round()]
	var cam := root.get_viewport().get_camera_3d()
	var env := _env()
	if env != null and env.sky != null and env.sky.sky_material is ShaderMaterial:
		var d: Vector3 = NightSky.moon_dir_of(env.sky)
		var target := cam.global_position + d * 1000.0
		var on_screen := not cam.is_position_behind(target) and Rect2i(Vector2i.ZERO, img.get_size()).has_point(Vector2i(cam.unproject_position(target)))
		line += " moon_px=%s on_screen=%s phase=%.2f" % [cam.unproject_position(target).round(), on_screen, float(env.sky.sky_material.get_shader_parameter("phase"))]
	print(line)
	var dir := OS.get_environment("SKY_SHOT_DIR")
	if dir != "":
		DirAccess.make_dir_recursive_absolute(dir)
		img.save_png(dir.path_join("%s.png" % tag))
		print("saved %s" % dir.path_join("%s.png" % tag))
	quit(0)
	return true

func _env() -> Environment:
	for n in game.get_children():
		if n is WorldEnvironment:
			return n.environment
	return null

static func _avg(img: Image, r: Rect2i) -> Vector3:
	var sum := Vector3.ZERO
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := img.get_pixel(x, y)
			sum += Vector3(c.r8, c.g8, c.b8)
	return sum / float(r.get_area())
