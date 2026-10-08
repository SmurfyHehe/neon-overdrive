extends SceneTree

# Cockpit mirrors on screen (2026-10-07): Roy wants the cockpit view playable
# with one hand, so the mirrors must not need the glance key (V); the default
# cockpit view, head at rest, has to show all three mirrors. Boots Game.tscn at 1280x720 (16:9), switches to the
# cockpit with the car at rest, and projects the four corners of each mirror's
# glass (rear, left door, right door) with Camera3D.unproject_position. Every
# corner must be in front of the camera and inside the viewport.
# Also prints the smallest vertical FOV that would still fit all the glass at
# 16:9, so the default can be checked against it.
# With NEON_SHOT=<path.png> and the real renderer, saves a screenshot of the
# cockpit view. Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --audio-driver Dummy --path . -s res://tests/cockpit_mirror_fov.gd

const TIMEOUT_TICKS := 60 * 30
const SETTLE_TICKS := 90

var tick := 0
var cockpit_tick := -1
var failures: Array[String] = []

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	root.size = Vector2i(1280, 720)
	ViewSettings.set_cockpit_fov(ViewSettings.COCKPIT_FOV_DEFAULT)
	change_scene_to_file("res://Game.tscn")

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _drive(c: PlayerCar) -> void:
	c.throttle_input = 0.0
	c.brake_input = 1.0
	c.steering_input = 0.0

func _process(_delta: float) -> bool:
	tick += 1
	var game := current_scene
	if game == null or game.get("player") == null or game.get("camera") == null:
		return tick > TIMEOUT_TICKS and _end("Game never became ready")
	var p: PlayerCar = game.player
	var cam: ChaseCamera = game.camera
	p.driver = _drive
	if cockpit_tick < 0:
		root.size = Vector2i(1280, 720)
		ViewSettings.set_cockpit_fov(ViewSettings.COCKPIT_FOV_DEFAULT)
		cam.set_view(ChaseCamera.View.COCKPIT)
		cockpit_tick = tick
		return false
	if tick - cockpit_tick < SETTLE_TICKS:
		return false
	_measure(cam)
	var shot := OS.get_environment("NEON_SHOT")
	if shot != "" and DisplayServer.get_name() != "headless":
		var img := root.get_texture().get_image()
		img.save_png(shot)
		print("cockpit_mirror_fov: saved ", shot, " (", img.get_width(), "x", img.get_height(), ")")
	return _end("")

func _measure(cam: ChaseCamera) -> void:
	var vp_size := Vector2(root.get_visible_rect().size)
	var aspect := vp_size.x / vp_size.y
	print("cockpit_mirror_fov: viewport %dx%d, cockpit FOV %.1f (default %.1f, slider %.0f-%.0f), eye yaw %.1f deg" % [
		vp_size.x, vp_size.y, cam.fov, ViewSettings.COCKPIT_FOV_DEFAULT,
		ViewSettings.COCKPIT_FOV_MIN, ViewSettings.COCKPIT_FOV_MAX, ChaseCamera.COCKPIT_YAW_DEG])
	_check(absf(aspect - 16.0 / 9.0) < 0.01, "the viewport should be 16:9, got %s" % vp_size)
	_check(absf(cam.fov - ViewSettings.COCKPIT_FOV_DEFAULT) < 0.5, "at rest the cockpit FOV should be the default %.1f, got %.2f" % [ViewSettings.COCKPIT_FOV_DEFAULT, cam.fov])
	_check(ViewSettings.COCKPIT_FOV_MAX >= ViewSettings.COCKPIT_FOV_DEFAULT, "the FOV slider must reach the default")
	var mirrors: CockpitMirrors = cam.frame.mirrors
	var inv := cam.global_transform.affine_inverse()
	var need_tan_v := 0.0
	for v in mirrors.views:
		var quad: MeshInstance3D = v.quad
		var half: Vector2 = (quad.mesh as QuadMesh).size * 0.5
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		var max_yaw := 0.0
		for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var world: Vector3 = quad.global_transform * Vector3(c.x * half.x, c.y * half.y, 0.0)
			var local: Vector3 = inv * world
			var depth := -local.z
			_check(not cam.is_position_behind(world), "%s glass corner is behind the camera" % quad.name)
			if depth > 0.0:
				need_tan_v = maxf(need_tan_v, maxf(absf(local.x) / depth / aspect, absf(local.y) / depth))
				max_yaw = maxf(max_yaw, absf(rad_to_deg(atan2(local.x, depth))))
			var px := cam.unproject_position(world)
			lo = lo.min(px)
			hi = hi.max(px)
		var inside := lo.x >= 0.0 and lo.y >= 0.0 and hi.x <= vp_size.x and hi.y <= vp_size.y
		print("cockpit_mirror_fov: %s glass x %.0f..%.0f y %.0f..%.0f px, outer edge %.1f deg off centre -> %s" % [
			quad.name, lo.x, hi.x, lo.y, hi.y, max_yaw, "on screen" if inside else "OFF SCREEN"])
		_check(inside, "%s glass should be fully on screen at 1280x720 (x %.0f..%.0f, y %.0f..%.0f)" % [quad.name, lo.x, hi.x, lo.y, hi.y])
	if OS.get_environment("NEON_YAW_SWEEP") != "":
		for yaw_i in 13:
			var yaw := float(yaw_i)
			var t := 0.0
			for v in mirrors.views:
				var q: MeshInstance3D = v.quad
				var hh: Vector2 = (q.mesh as QuadMesh).size * 0.5
				for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
					var l: Vector3 = Basis(Vector3.UP, deg_to_rad(yaw)) * (inv * (q.global_transform * Vector3(c.x * hh.x, c.y * hh.y, 0.0)))
					t = maxf(t, maxf(absf(l.x) / -l.z / aspect, absf(l.y) / -l.z))
			print("sweep yaw %.0f -> need FOV %.1f" % [yaw, rad_to_deg(2.0 * atan(t))])
	var need_fov := rad_to_deg(2.0 * atan(need_tan_v))
	var h_half := rad_to_deg(atan(tan(deg_to_rad(cam.fov) * 0.5) * aspect))
	print("cockpit_mirror_fov: smallest vertical FOV that fits all mirror glass at 16:9: %.1f; horizontal edge now %.1f deg" % [need_fov, h_half])

func _end(msg: String) -> bool:
	if msg != "":
		failures.append(msg)
	print("cockpit_mirror_fov: ", "FAIL" if not failures.is_empty() else "PASS")
	for f in failures:
		print("  - ", f)
	quit(1 if not failures.is_empty() else 0)
	return true
