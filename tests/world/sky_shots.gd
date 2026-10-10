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
# SKY_SHOT_CAM=cockpit uses the game's own cockpit view (F in play).
# SKY_SHOT_RUN=<n> jumps the parked car to the middle of district run n
# (districts.gd: 16 chunks per run, run 0 downtown) before the shot, 4
# chunks per frame so the chunk pool keeps up, then waits for the glow dome
# blend. The line also says whether a ray from the camera to the moon hits
# something (a tower in the way) and the colour at the moon's pixel.
# Run (real renderer; a window opens briefly):
#   Godot_v4.7.2-stable_win64_console.exe --path . --audio-driver Dummy -s res://tests/world/sky_shots.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const Districts := preload("res://scripts/world/districts.gd")
const SETTLE_FRAMES := 100     # after the jump (dome blend is 4 s at 60 fps + check)
const JUMP_CHUNKS := 4

var game: Node
var frame := 0
var target_idx := -1
var arrived_frame := -1

func _initialize() -> void:
	game = Harness.boot(self, 0, 300.0, 7)
	var run_env := OS.get_environment("SKY_SHOT_RUN")
	if run_env.is_valid_int():
		target_idx = int(run_env) * Districts.RUN + Districts.RUN / 2

func _chunk_idx() -> int:
	var z: float = RoadFrame.unroll(game.player.global_position).z
	return int(floor(-z / RoadChunkBuilder.CHUNK_LEN)) + int(game.origin_index)

func _process(_delta: float) -> bool:
	frame += 1
	var car: RigidBody3D = game.get("player")
	if frame < 20:
		return false
	if frame == 20 and target_idx >= 0:
		# Parked and frozen for the jump: a rigid body dropped 200 m a frame
		# lands on half-built chunks and tips over.
		car.freeze = true
	if arrived_frame < 0:
		if target_idx >= 0 and _chunk_idx() < target_idx:
			var step := mini(JUMP_CHUNKS, target_idx - _chunk_idx())
			# Set down on the road and facing along it (it bends and climbs).
			var u := RoadFrame.unroll(car.global_position)
			car.global_transform = RoadFrame.pose(u.x, 0.6, u.z - RoadChunkBuilder.CHUNK_LEN * step, 0.0)
			return false
		arrived_frame = frame
	if target_idx >= 0:
		# The floating origin may have shifted the world under the frozen car.
		car.linear_velocity = Vector3.ZERO
	var cam_mode := OS.get_environment("SKY_SHOT_CAM")
	var shot_frame := arrived_frame + SETTLE_FRAMES + (300 if target_idx >= 0 else 0)
	if frame == shot_frame - 12:
		if cam_mode == "up" or cam_mode == "moon":
			var cam := Camera3D.new()
			cam.fov = 70.0 if cam_mode == "up" else 30.0
			root.add_child(cam)
			cam.global_position = car.global_position + Vector3(0.0, 1.6, 0.0)
			if cam_mode == "up":
				cam.rotation_degrees = Vector3(14.0, 0.0, 0.0)
			else:
				# A 30 degree lens aimed at the moon: phase and halo close up.
				cam.look_at(cam.global_position + NightSky.moon_dir_of(_env().sky))
			cam.current = true
		elif cam_mode == "cockpit":
			game.camera.set_view(ChaseCamera.View.COCKPIT)
	if frame < shot_frame:
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
		tag = "night_%s_%s%s%s" % [night if night != "" else "1", OS.get_environment("NEON_CLOCK").replace(":", ""),
			"_" + OS.get_environment("SKY_SHOT_CAM") if cam_mode != "" else "",
			"_run" + OS.get_environment("SKY_SHOT_RUN") if target_idx >= 0 else ""]
	var line := "sky_shots %s: district=%s" % [tag, Districts.name_at(_chunk_idx())]
	for k in regions:
		line += " %s=%s" % [k, _avg(img, regions[k]).round()]
	var cam := root.get_viewport().get_camera_3d()
	var env := _env()
	if env != null and env.sky != null and env.sky.sky_material is ShaderMaterial:
		var d: Vector3 = NightSky.moon_dir_of(env.sky)
		var target := cam.global_position + d * 1000.0
		var px := cam.unproject_position(target)
		var on_screen := not cam.is_position_behind(target) and Rect2i(Vector2i.ZERO, img.get_size()).has_point(Vector2i(px))
		# Anything solid between the camera and the sky in the moon's direction?
		var q := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position + d * 2000.0)
		q.collision_mask = 0xFFFFFFFF
		q.exclude = [car.get_rid()]
		var hit := car.get_world_3d().direct_space_state.intersect_ray(q)
		var blocker := "none"
		if not hit.is_empty():
			var n: Node = hit.collider
			blocker = "%s@%dm" % [n.name if n != null else "?", int(cam.global_position.distance_to(hit.position))]
		var moon_rgb := Vector3.ZERO
		if on_screen:
			var p := Vector2i(px)
			moon_rgb = _avg(img, Rect2i(p - Vector2i(2, 2), Vector2i(5, 5)).intersection(Rect2i(Vector2i.ZERO, img.get_size())))
		var el := rad_to_deg(asin(d.y))
		line += " moon_el=%.1f moon_px=%s on_screen=%s blocker=%s moon_rgb=%s phase=%.2f" % [el, px.round(), on_screen, blocker, moon_rgb.round(), float(env.sky.sky_material.get_shader_parameter("phase"))]
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
	if r.get_area() <= 0:
		return Vector3.ZERO
	var sum := Vector3.ZERO
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := img.get_pixel(x, y)
			sum += Vector3(c.r8, c.g8, c.b8)
	return sum / float(r.get_area())
