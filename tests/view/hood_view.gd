extends SceneTree

# Hood view (2026-10-11): the camera on the bonnet is the third view.
#
# Every playable car kind (booted as the player's car, one after the other):
#   - F cycles cockpit -> hood -> chase -> cockpit (real key presses)
#   - the camera sits at the car's hood_cam (CabinSpec: its own key or the
#     computed default), above the highest body point (hood and anything bolted
#     to it) inside a 0.6 m box round it, and a ray from it to the road 10 m
#     ahead is not blocked by the car
#   - no door mirror renders, the rear mirror renders only for the HUD strip,
#     the cabin is not in front of the camera, the sound is the outside one
# On the coupe, parked:
#   - Left held: 90 +- 2 deg; Up: 20 +- 2; Down: 15 +- 2; release: under 1 deg in 0.5 s
#   - B: the camera is at roof_back_cam looking within 2 deg of the car's +z,
#     arrows ignored meanwhile; release: back on the bonnet
#   - the same key script at 60 / 120 / 144 drawn fps agrees
#   - the view is saved: a fresh boot with the file on hood starts in hood
# Frame-clock test (hold times are drawn-frame time): run with --fixed-fps 60.
#   Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --audio-driver Dummy --path . -s res://tests/view/hood_view.gd
# Exit code 1 on failure.

const Harness := preload("res://tests/traffic/traffic_harness.gd")

## Collision layer used for the shell proxy only (nothing else in the game is on it).
const SHELL_LAYER := 1 << 19
const BOX_HALF := 0.3          # the 0.6 m box round the camera
const GRID := 7
const RATES := [60, 120, 144]
const SAMPLES := [0.5, 0.75, 1.0, 1.25, 1.5]   # s; the keys are released at 1.0

var fails := 0
var logger := Harness.ErrorCounter.new()
var game: Node
var p: PlayerCar
var cam: ChaseCamera
var table: Array[String] = []

func _check(ok: bool, msg: String) -> void:
	if not ok:
		print("FAIL " + msg)
		fails += 1

func _initialize() -> void:
	OS.add_logger(logger)
	root.size = Vector2i(1280, 720)   # headless defaults to 64x64
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

## A key press seen by the camera's physics poll (just_pressed), then released.
func _tap(action: String) -> void:
	Input.action_press(action)
	await _frames(4)
	Input.action_release(action)
	await _frames(4)

func _boot(kind: String, saved_view: String) -> void:
	OS.set_environment("NEON_CAR", kind)
	AudioSettings.path = Harness.SETTINGS_PATH
	if saved_view != "":
		ViewSettings.set_camera_view(saved_view)
		ViewSettings.save_settings()
	ViewSettings.camera_view = ViewSettings.CAMERA_VIEW_DEFAULT   # only the file can bring the view back
	game = Harness.boot(self, 0, 150.0, 7, 1.0e6)
	await _frames(60)
	p = game.get("player")
	cam = game.get("camera")
	if p == null or cam == null:
		return
	p.driver = func(c: PlayerCar) -> void:
		c.throttle_input = 0.0
		c.brake_input = 1.0
		c.handbrake_input = 0.0
		c.steering_input = 0.0
	cam.shake_enabled = false
	await _frames(60)

func _free() -> void:
	game.queue_free()
	await process_frame
	await process_frame

func _run() -> void:
	for k in PlayerCars.KINDS:
		await _kind(String(k.id))
	await _behaviour()
	OS.set_environment("NEON_CAR", "")
	for line in table:
		print(line)
	if logger.errors.size() > 0:
		print("FAIL %d engine errors: %s" % [logger.errors.size(), str(logger.errors.slice(0, 5))])
		fails += logger.errors.size()
	print("hood_view: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)

# ---------- every car kind ----------

func _kind(kind: String) -> void:
	await _boot(kind, "chase")
	_check(p != null and cam != null and cam.frame != null, "%s: the game should boot with a cockpit frame" % kind)
	if p == null or cam == null or cam.frame == null:
		await _free()
		return
	_check(cam.view == ChaseCamera.View.CHASE, "%s: starts in the chase view with chase saved" % kind)
	# F: chase -> cockpit -> hood -> chase -> cockpit
	await _tap("camera_view")
	_check(cam.view == ChaseCamera.View.COCKPIT, "%s: F from chase goes to the cockpit (%s)" % [kind, cam.view])
	await _tap("camera_view")
	_check(cam.view == ChaseCamera.View.HOOD, "%s: F from the cockpit goes to the hood (%s)" % [kind, cam.view])
	await _frames(6)
	var t0 := Time.get_ticks_usec()
	cam.set_view(ChaseCamera.View.HOOD)   # again, to time the fit to the body
	var fit_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	table.append("  %-16s fit to the body on entering hood view: %.1f ms" % [kind, fit_ms])
	await _frames(6)
	_hood_checks(kind)
	await _shell_checks(kind)
	await _tap("camera_view")
	_check(cam.view == ChaseCamera.View.CHASE, "%s: F from the hood goes to the chase view (%s)" % [kind, cam.view])
	await _tap("camera_view")
	_check(cam.view == ChaseCamera.View.COCKPIT, "%s: F from chase goes round to the cockpit (%s)" % [kind, cam.view])
	await _free()

## Things read off the camera and the frame, no geometry.
func _hood_checks(kind: String) -> void:
	var cab := CabinSpec.for_kind(PlayerCar.chassis_kind())
	var rel := p.get_global_transform_interpolated().affine_inverse() * cam.global_position
	_check(rel.distance_to(cam.hood_cam) < 0.04, "%s: the camera %s is at hood_cam %s" % [kind, rel, cam.hood_cam])
	if cab.has("hood_cam"):
		_check(cam.hood_cam.is_equal_approx(CabinSpec.hood_cam(cab)), "%s: hood_cam is the car's own point" % kind)
	else:
		var dflt := CabinSpec.hood_cam(cab)
		_check(is_equal_approx(cam.hood_cam.x, dflt.x) and cam.hood_cam.y >= dflt.y - 0.001 and cam.hood_cam.z <= dflt.z + 0.001,
			"%s: hood_cam %s is the CabinSpec default %s, only risen or moved forward" % [kind, cam.hood_cam, dflt])
	var fwd := -cam.global_basis.z
	var car_fwd := -p.global_basis.z
	_check(fwd.angle_to(car_fwd) < deg_to_rad(3.0), "%s: looks where the car points (%.1f deg)" % [kind, rad_to_deg(fwd.angle_to(car_fwd))])
	_check(absf(cam.fov - ViewSettings.hood_fov) < 0.8, "%s: FOV %.1f is the hood FOV setting %.1f (its own since the View page)" % [kind, cam.fov, ViewSettings.hood_fov])
	# mirrors: the door mirrors never render in this view; the rear one only for the HUD strip
	var mirrors: CockpitMirrors = cam.frame.mirrors
	_check(not mirrors.active, "%s: the mirrors are not active in hood view" % kind)
	for i in [1, 2]:
		var vp: SubViewport = mirrors.views[i].vp
		_check(vp.render_target_update_mode == SubViewport.UPDATE_DISABLED, "%s: door mirror %d is not rendering" % [kind, i])
	if not mirrors.strip:
		var rear: SubViewport = mirrors.views[0].vp
		_check(rear.render_target_update_mode == SubViewport.UPDATE_DISABLED, "%s: the rear mirror is off with no strip" % kind)
	# the cabin is behind the camera, never in front of it
	var nearest := 1.0e9
	var interior_meshes := 0
	var inv := p.get_global_transform_interpolated().affine_inverse()
	for mi in cam.frame.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or not m.is_visible_in_tree() or (m.layers & cam.cull_mask) == 0:
			continue
		var a := _car_aabb(m, inv)
		interior_meshes += 1
		nearest = minf(nearest, a.position.z)
	_check(interior_meshes == 0 or nearest >= rel.z - 0.01, "%s: cabin parts reach z %.2f, ahead of the camera at z %.2f" % [kind, nearest, rel.z])
	_check(not cam.perspective.target >= 0.5, "%s: the sound is the outside perspective" % kind)
	_check(not cam.frame.cockpit, "%s: the cabin frame is in its outside state" % kind)
	_check(cam.frame.body_hidden_from_camera() == false, "%s: the body is drawn" % kind)

static func _car_aabb(m: MeshInstance3D, inv: Transform3D) -> AABB:
	var box := AABB()
	var first := true
	var xf := inv * m.global_transform
	var src := m.mesh.get_aabb()
	for i in 8:
		var v: Vector3 = xf * src.get_endpoint(i)
		box = AABB(v, Vector3.ZERO) if first else box.expand(v)
		first = false
	return box

## The car's body and everything bolted to it, as one collision shell off to the side.
func _shell_checks(kind: String) -> void:
	var inv := p.get_global_transform_interpolated().affine_inverse()
	var shell := PackedVector3Array()
	var low_y := 1.0e9
	for mi in p.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or not m.is_visible_in_tree() or (m.layers & cam.cull_mask) == 0:
			continue
		if cam.frame.is_ancestor_of(m) or _under(m, Undercarriage.NODE_NAME) or m.name == Undercarriage.PLATE_NAME:
			continue
		var xf := inv * m.global_transform
		for v in m.mesh.get_faces():
			var w: Vector3 = xf * v
			shell.append(w)
			low_y = minf(low_y, w.y)
	_check(shell.size() > 0, "%s: the body should have a mesh" % kind)
	if shell.is_empty():
		return
	var proxy := StaticBody3D.new()
	proxy.collision_layer = SHELL_LAYER
	proxy.collision_mask = 0
	var shape := CollisionShape3D.new()
	var poly := ConcavePolygonShape3D.new()
	poly.backface_collision = true
	poly.set_faces(shell)
	shape.shape = poly
	proxy.add_child(shape)
	var base := Vector3(0.0, 500.0, 0.0)
	proxy.position = base
	root.add_child(proxy)
	await physics_frame
	await physics_frame
	var space := root.get_world_3d().direct_space_state
	var cab := CabinSpec.for_kind(PlayerCar.chassis_kind())
	var at: Vector3 = cam.hood_cam
	# the highest surface in the 0.6 m box: rays straight down from above it
	var top := -1.0e9
	for ix in GRID:
		for iz in GRID:
			var x := at.x - BOX_HALF + 2.0 * BOX_HALF * float(ix) / float(GRID - 1)
			var z := at.z - BOX_HALF + 2.0 * BOX_HALF * float(iz) / float(GRID - 1)
			var q := PhysicsRayQueryParameters3D.create(base + Vector3(x, at.y + 3.0, z), base + Vector3(x, low_y - 1.0, z), SHELL_LAYER)
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				top = maxf(top, (hit.position - base).y)
	var margin := at.y - top
	_check(top > -1.0e8, "%s: no body found under the camera" % kind)
	_check(margin > 0.02, "%s: the camera (y %.3f) is %.3f m above the highest body point in the box (%.3f)" % [kind, at.y, margin, top])
	# line of sight to the road 10 m ahead of the nose
	var rear_front_z := INF
	for v in shell:
		rear_front_z = minf(rear_front_z, v.z)
	var road := Vector3(0.0, low_y, rear_front_z - 10.0)
	var q2 := PhysicsRayQueryParameters3D.create(base + at, base + road, SHELL_LAYER)
	q2.hit_back_faces = true
	var blocked := space.intersect_ray(q2)
	_check(blocked.is_empty(), "%s: the car blocks the view of the road 10 m ahead (hit at %s)" % [kind, str(blocked.get("position", Vector3.ZERO) - base)])
	var own := cab.has("hood_cam")
	var roof: Vector3 = cam.roof_back_cam
	var roof_top := -1.0e9
	for ix in GRID:
		for iz in GRID:
			var x2 := roof.x - BOX_HALF + 2.0 * BOX_HALF * float(ix) / float(GRID - 1)
			var z2 := roof.z - BOX_HALF + 2.0 * BOX_HALF * float(iz) / float(GRID - 1)
			var hit2 := space.intersect_ray(PhysicsRayQueryParameters3D.create(base + Vector3(x2, roof.y + 3.0, z2), base + Vector3(x2, low_y - 1.0, z2), SHELL_LAYER))
			if not hit2.is_empty():
				roof_top = maxf(roof_top, (hit2.position - base).y)
	_check(roof.y > roof_top + 0.02, "%s: the roof camera (y %.3f) is above the body under it (%.3f)" % [kind, roof.y, roof_top])
	table.append("  %-16s hood_cam (%.2f, %.3f, %.2f) %s  body top in box %.3f  margin %.3f  roof_back_cam (%.2f, %.2f, %.2f) %s" % [kind,
		at.x, at.y, at.z, "override" if own else "fitted  ", top, margin, roof.x, roof.y, roof.z, "override" if cab.has("roof_back_cam") else "default"])
	proxy.queue_free()

static func _under(n: Node, parent_name: String) -> bool:
	var q := n
	while q != null:
		if q.name == parent_name:
			return true
		q = q.get_parent()
	return false

# ---------- keys, B, rates, saved view ----------

func _rel() -> Vector3:
	return p.get_global_transform_interpolated().affine_inverse() * cam.global_position

## Angle (deg) between where the camera looks and the car's heading.
func _yaw_off() -> float:
	return rad_to_deg((-cam.global_basis.z).angle_to(-p.global_basis.z))

func _behaviour() -> void:
	await _boot(PlayerCars.DEFAULT, "hood")
	_check(p != null and cam != null, "the coupe should boot")
	if p == null or cam == null:
		return
	# a file saved on hood starts in hood
	_check(cam.view == ChaseCamera.View.HOOD, "saved on hood: starts in the hood view (%s)" % cam.view)
	_check(cam.mode_name() == "HOOD", "mode name is HOOD (%s)" % cam.mode_name())
	var home := cam.hood_cam
	# arrows
	Input.action_press("look_left")
	await _frames(60)
	print("hold Left 1 s: look %.1f deg, camera %.1f deg off the car's heading" % [cam.look_yaw, _yaw_off()])
	_check(absf(cam.look_yaw - 90.0) <= 2.0, "hold Left: 90 +- 2 (%.1f)" % cam.look_yaw)
	_check(absf(_yaw_off() - 90.0) <= 3.0, "hold Left: the view is turned 90 +- 3 (%.1f)" % _yaw_off())
	_check(_rel().distance_to(home) < 0.04, "the camera stays on the bonnet while looking (%s)" % _rel())
	Input.action_release("look_left")
	await _frames(30)
	_check(absf(cam.look_yaw) < 1.0, "release Left: under 1 deg in 0.5 s (%.2f)" % cam.look_yaw)
	Input.action_press("look_up")
	await _frames(60)
	print("hold Up 1 s: pitch %.1f" % cam.look_pitch)
	_check(absf(cam.look_pitch - 20.0) <= 2.0, "hold Up: 20 +- 2 (%.1f)" % cam.look_pitch)
	Input.action_release("look_up")
	await _frames(30)
	_check(absf(cam.look_pitch) < 1.0, "release Up: under 1 deg in 0.5 s (%.2f)" % cam.look_pitch)
	Input.action_press("look_down")
	await _frames(60)
	print("hold Down 1 s: pitch %.1f" % cam.look_pitch)
	_check(absf(cam.look_pitch + 15.0) <= 2.0, "hold Down: 15 +- 2 down (%.1f)" % cam.look_pitch)
	Input.action_release("look_down")
	await _frames(30)
	_check(absf(cam.look_pitch) < 1.0, "release Down: under 1 deg in 0.5 s (%.2f)" % cam.look_pitch)
	# tap: a plain 35 deg glance
	Input.action_press("look_right")
	await _frames(6)
	Input.action_release("look_right")
	var peak := 0.0
	for i in 30:
		await process_frame
		peak = maxf(peak, absf(cam.look_yaw))
	print("tap Right 0.1 s: peak %.1f deg" % peak)
	_check(absf(peak - 35.0) <= 3.0, "tap: a 35 deg glance (%.1f)" % peak)
	await _frames(120)
	_check(absf(cam.look_yaw) < 1.0, "the glance is gone after 2 s (%.2f)" % cam.look_yaw)
	# B: the roof camera, arrows ignored, release goes back
	Input.action_press("look_back")
	await _frames(20)
	var back := _rel()
	var flat := (-cam.global_basis.z).angle_to(p.global_basis.z)
	print("B: camera %s (roof_back_cam %s), %.2f deg off the car's +z" % [back, cam.roof_back_cam, rad_to_deg(flat)])
	_check(back.distance_to(cam.roof_back_cam) < 0.04, "B: at roof_back_cam (%s vs %s)" % [back, cam.roof_back_cam])
	_check(rad_to_deg(flat) < 2.0, "B: looking straight back (%.2f deg off)" % rad_to_deg(flat))
	Input.action_press("look_left")
	Input.action_press("look_up")
	await _frames(30)
	flat = (-cam.global_basis.z).angle_to(p.global_basis.z)
	_check(rad_to_deg(flat) < 2.0, "B with Left+Up held: arrows ignored (%.2f deg off)" % rad_to_deg(flat))
	_check(_rel().distance_to(cam.roof_back_cam) < 0.04, "B with arrows: still at roof_back_cam")
	Input.action_release("look_left")
	Input.action_release("look_up")
	Input.action_release("look_back")
	await _frames(20)
	_check(_rel().distance_to(home) < 0.04, "B released: back on the bonnet (%s)" % _rel())
	_check(_yaw_off() < 2.0, "B released: looking ahead (%.2f deg)" % _yaw_off())
	_check(cam.view == ChaseCamera.View.HOOD, "B does not change the view")
	# the same keys at three frame rates
	_rates()
	await _free()
	# the saved view survives a restart; F walks on from it
	await _boot(PlayerCars.DEFAULT, "")
	_check(cam != null and cam.view == ChaseCamera.View.HOOD, "restart: still in the hood view")
	await _tap("camera_view")
	_check(cam.view == ChaseCamera.View.CHASE, "restart: F goes hood -> chase")
	_check(ViewSettings.camera_view == "chase", "the file says chase (%s)" % ViewSettings.camera_view)
	await _free()
	await _boot(PlayerCars.DEFAULT, "")
	_check(cam != null and cam.view == ChaseCamera.View.CHASE, "restart: back in chase")
	await _free()
	ViewSettings.set_camera_view("chase")

func _rates() -> void:
	cam.set_process(false)
	cam.set_view(ChaseCamera.View.HOOD)
	var runs := {}
	for r in RATES:
		runs[r] = _run_rate(r)
	for i in SAMPLES.size():
		var ref: Dictionary = runs[60][i]
		for r in [120, 144]:
			var got: Dictionary = runs[r][i]
			_check(absf(ref.yaw - got.yaw) <= 1.0, "t=%.2f s: look %.2f at 60 fps vs %.2f at %d fps" % [SAMPLES[i], ref.yaw, got.yaw, r])
			_check(absf(ref.pitch - got.pitch) <= 1.0, "t=%.2f s: pitch %.2f at 60 fps vs %.2f at %d fps" % [SAMPLES[i], ref.pitch, got.pitch, r])
			_check(absf(ref.fov - got.fov) <= 0.2, "t=%.2f s: fov %.2f at 60 fps vs %.2f at %d fps" % [SAMPLES[i], ref.fov, got.fov, r])
			_check(ref.pos.distance_to(got.pos) <= 0.03, "t=%.2f s: camera %s at 60 fps vs %s at %d fps" % [SAMPLES[i], ref.pos, got.pos, r])
	var d: Dictionary = runs[60][2]
	var e: Dictionary = runs[144][2]
	print("1.0 s: look %.2f / %.2f deg, pitch %.2f / %.2f at 60 / 144 fps" % [d.yaw, e.yaw, d.pitch, e.pitch])
	cam.set_process(true)

func _run_rate(rate: int) -> Array:
	Input.action_release("look_left")
	Input.action_release("look_up")
	cam.look_yaw = 0.0
	cam.look_pitch = 0.0
	cam.corner_yaw = 0.0
	cam._hold_dir = 0
	cam._hold_t = 0.0
	cam._latch_t = 0.0
	cam.look_back = false
	cam._process(1.0 / 240.0)
	Input.action_press("look_left")
	Input.action_press("look_up")
	var out := []
	var dt := 1.0 / float(rate)
	var next_i := 0
	var frames := int(round(SAMPLES[-1] * rate))
	for f in range(1, frames + 1):
		var t := f * dt
		if f == int(round(1.0 * rate)) + 1:
			Input.action_release("look_left")
			Input.action_release("look_up")
		cam._process(dt)
		if next_i < SAMPLES.size() and absf(t - SAMPLES[next_i]) < dt * 0.5:
			out.append({"yaw": cam.look_yaw, "pitch": cam.look_pitch, "fov": cam.fov, "pos": cam.global_position})
			next_i += 1
	Input.action_release("look_left")
	Input.action_release("look_up")
	return out
