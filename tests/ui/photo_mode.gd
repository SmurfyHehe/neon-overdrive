extends SceneTree

# Photo mode: drives the real Game.tscn. P enters (tree paused, HUD layers
# hidden, photo camera current at the chase camera's pose), held keys move the
# camera (orbit round the frozen car, then Tab to fly free), Shift + arrows
# tilt, Shift + Z/X blur, Esc leaves and restores everything. A headless run has no
# framebuffer, so save_shot() must return "" there instead of crashing; with a
# real renderer it writes a PNG under user://photos. Exit code 1 on failure.
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/ui/photo_mode.gd

const TIMEOUT_TICKS := 1200
var failures: Array[String] = []
var tick := 0
var phase := 0
var start_tick := 0
var chase_pos := Vector3.ZERO
var layers_before := 0
var game: Node
var photo: PhotoMode

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _initialize() -> void:
	change_scene_to_file("res://Game.tscn")

func _press(action: String, down: bool) -> void:
	if down:
		Input.action_press(action)
	else:
		Input.action_release(action)

func _visible_layers() -> int:
	var n := 0
	for l in root.find_children("*", "CanvasLayer", true, false):
		if l.visible:
			n += 1
	return n

func _all_layers_kept() -> bool:
	for l in root.find_children("*", "CanvasLayer", true, false):
		if l.visible and not PhotoMode._keeps(l):
			return false
	return true

func _physics_process(_delta: float) -> bool:
	tick += 1
	game = current_scene
	if game == null or game.get("camera") == null or game.get("game_state") == null:
		return tick > TIMEOUT_TICKS and _end("Game never became ready")
	var gs: GameState = game.game_state
	var cam: ChaseCamera = game.camera
	match phase:
		0:
			if tick < 30:
				return false
			for c in game.get_children():
				if c is PhotoMode:
					photo = c
			_check(photo != null, "Game should own a PhotoMode node")
			if photo == null:
				return _end("")
			layers_before = _visible_layers()
			_check(layers_before >= 3, "HUD layers should be visible while playing (%d)" % layers_before)
			chase_pos = cam.global_position
			_press("photo_mode", true)
			start_tick = tick
			phase = 1
		1:
			if tick - start_tick < 3:
				return false
			_press("photo_mode", false)
			_check(gs.state == GameState.State.PHOTO, "P should enter photo mode, state %d" % gs.state)
			_check(paused, "the tree should be paused")
			_check(photo.free_cam.current, "the free camera should be current")
			_check(photo.free_cam.global_position.distance_to(chase_pos) < 0.5, "free cam should start at the chase camera")
			var shown := 0
			for l in root.find_children("*", "CanvasLayer", true, false):
				if l.visible and not PhotoMode._keeps(l):
					shown += 1
			_check(shown == 0, "all HUD layers should be hidden, %d still visible" % shown)
			_check(_visible_layers() < layers_before, "fewer layers should be visible than before")
			_press("photo_forward", true)
			_press("photo_up", true)
			start_tick = tick
			phase = 2
		2:
			photo.step(1.0 / 60.0)
			if tick - start_tick < 30:
				return false
			_press("photo_forward", false)
			_press("photo_up", false)
			_check(photo.free_cam.global_position.distance_to(chase_pos) > 1.5, "held keys should move the free camera (%.2f m)" % photo.free_cam.global_position.distance_to(chase_pos))
			_check(photo.free_cam.global_position.y > chase_pos.y, "the up key should raise the camera")
			var fov0 := photo.free_cam.fov
			_press("photo_fov_narrow", true)
			photo.step(0.5)
			_press("photo_fov_narrow", false)
			_check(photo.free_cam.fov < fov0, "Z should narrow the field of view")
			# Orbit (the start): A circles the frozen car at a fixed distance, the
			# camera keeps looking at it, W runs into the near limit.
			_check(photo.orbit, "photo mode should open in orbit")
			var c := photo.aim_point()
			var d0 := photo.free_cam.global_position.distance_to(c)
			var yaw0 := photo.orbit_yaw
			_press("photo_left", true)
			for i in 30:
				photo.step(1.0 / 60.0)
			_press("photo_left", false)
			_check(absf(photo.free_cam.global_position.distance_to(c) - d0) < 0.05, "circling keeps the distance to the car (%.2f vs %.2f m)" % [photo.free_cam.global_position.distance_to(c), d0])
			_check(absf(photo.orbit_yaw - yaw0) > 0.3, "A should circle the car (%.2f rad)" % absf(photo.orbit_yaw - yaw0))
			var fwd := -photo.free_cam.global_basis.z
			_check(fwd.dot((c - photo.free_cam.global_position).normalized()) > 0.99, "the orbit camera should look at the car (dot %.3f)" % fwd.dot((c - photo.free_cam.global_position).normalized()))
			_press("photo_forward", true)
			photo.step(10.0)
			_press("photo_forward", false)
			_check(absf(photo.orbit_dist - PhotoMode.ORBIT_DIST_MIN) < 0.01, "W stops at the near limit (%.2f m)" % photo.orbit_dist)
			var flat := Vector2(photo.free_cam.global_position.x - c.x, photo.free_cam.global_position.z - c.z).length()
			_check(absf(flat - PhotoMode.ORBIT_DIST_MIN) < 0.05, "the camera sits at the near limit (%.2f m across)" % flat)
			# Shift + Left tilts the shot and stops at the limit; the fly keys and
			# the field of view are untouched by it.
			var fov1 := photo.free_cam.fov
			_press("photo_fast", true)
			_press("photo_look_left", true)
			photo.step(3.0)
			_press("photo_look_left", false)
			_check(absf(absf(photo.roll) - PhotoMode.ROLL_MAX_DEG) < 0.01, "Shift + Left tilts to the limit (%.1f deg)" % photo.roll)
			# A level camera's right axis has no lift; a tilted one does (less when
			# the camera looks steeply down, so the bar is low).
			_check(absf(photo.free_cam.global_basis.x.y) > 0.15, "a tilted shot has a tilted camera (x.y %.2f)" % photo.free_cam.global_basis.x.y)
			_check(absf(photo.aim_yaw) < 0.01, "Shift + Left must not nudge the aim")
			# Shift + X blurs the background: depth of field on, focused on the car.
			_check(photo.free_cam.attributes == photo._dof, "the photo camera should carry the depth-of-field attributes")
			_check(not photo._dof.dof_blur_far_enabled, "blur starts off")
			_press("photo_fov_wide", true)
			photo.step(1.0)
			_press("photo_fov_wide", false)
			_press("photo_fast", false)
			_check(photo.blur > 5.0 and photo.blur < 7.0, "a second of Shift + X should give about six blur steps (%.1f)" % photo.blur)
			_check(photo._dof.dof_blur_far_enabled and photo._dof.dof_blur_near_enabled, "blur on should enable depth of field")
			_check(absf(photo.free_cam.fov - fov1) < 0.01, "Shift + X must not change the field of view")
			var fdist := photo.focus_distance()
			_check(absf(fdist - photo.free_cam.global_position.distance_to(c)) < 0.05, "in orbit the focus sits on the car (%.2f m)" % fdist)
			_check(photo._dof.dof_blur_far_distance > fdist and photo._dof.dof_blur_near_distance < fdist, "the sharp band should straddle the car")
			# Tab: free camera, same place; W now flies forward.
			var before := photo.free_cam.global_position
			photo.toggle_orbit()
			_check(not photo.orbit, "Tab should switch to the free camera")
			_check(photo.free_cam.global_position.distance_to(before) < 0.01, "switching modes must not jump the camera")
			_press("photo_forward", true)
			photo.step(0.5)
			_press("photo_forward", false)
			_check(photo.free_cam.global_position.distance_to(before) > 3.0, "in free the W key flies forward (%.2f m)" % photo.free_cam.global_position.distance_to(before))
			_check(photo.focus_distance() > 0.5, "free focus distance should be a real distance (%.1f m)" % photo.focus_distance())
			photo.toggle_orbit()
			_check(photo.orbit, "Tab again goes back to orbit")
			var path := photo.save_shot()
			if DisplayServer.get_name() == "headless":
				_check(path == "", "headless has no framebuffer: save_shot must return empty")
			else:
				_check(path != "" and FileAccess.file_exists(path), "a PNG should be written (%s)" % path)
			_press("pause", true)
			start_tick = tick
			phase = 3
		3:
			if tick - start_tick < 3:
				return false
			_press("pause", false)
			_check(gs.state == GameState.State.PLAYING, "Esc should leave photo mode, state %d" % gs.state)
			_check(not paused, "the tree should run again")
			_check(cam.current and not photo.free_cam.current, "the chase camera should be current again")
			_check(_visible_layers() == layers_before, "HUD layers should be restored (%d vs %d)" % [_visible_layers(), layers_before])
			_check(photo.free_cam.attributes == null, "leaving photo mode drops the depth of field")
			# Second route: the pause menu's "Photo mode" row. The pause look's
			# orbit camera is current there and must hand over to the free camera.
			gs.pause()
			start_tick = tick
			phase = 4
		4:
			if tick - start_tick < 5:
				return false
			_check(gs.state == GameState.State.PAUSED, "pause should pause, state %d" % gs.state)
			gs.open_photo_from_pause()
			start_tick = tick
			phase = 5
		5:
			if tick - start_tick < 5:
				return false
			var look: PauseLook
			for c in game.get_children():
				if c is PauseLook:
					look = c
			_check(gs.state == GameState.State.PHOTO, "the pause row should enter photo mode, state %d" % gs.state)
			_check(photo.free_cam.current, "from the pause menu the free camera should be current")
			_check(not cam.current, "from the pause menu the game camera must not take the view back")
			_check(look != null and not look.orbit.current, "from the pause menu the orbit camera must not be current")
			_check(_visible_layers() == 0 or _all_layers_kept(), "from the pause menu all HUD layers should be hidden")
			_check(photo.orbit and absf(photo.roll) < 0.01 and photo.blur < 0.01, "a fresh photo mode starts in orbit, level and sharp")
			_press("pause", true)
			start_tick = tick
			phase = 6
		6:
			if tick - start_tick < 3:
				return false
			_press("pause", false)
			_check(gs.state == GameState.State.PAUSED, "Esc in photo mode from the pause menu goes back to pause, state %d" % gs.state)
			_check(not photo.free_cam.current, "the free camera should let go on leaving")
			gs.resume()
			start_tick = tick
			phase = 7
		7:
			if tick - start_tick < 5:
				return false
			_check(gs.state == GameState.State.PLAYING and not paused, "resume should run the game again")
			_check(cam.current and not photo.free_cam.current, "the chase camera should be current after resume")
			_check(_visible_layers() == layers_before, "HUD layers should be back after resume (%d vs %d)" % [_visible_layers(), layers_before])
			return _end("")
	return tick > TIMEOUT_TICKS and _end("timed out in phase %d" % phase)

func _end(msg: String) -> bool:
	if msg != "":
		failures.append(msg)
	print("photo_mode: ", "FAIL" if not failures.is_empty() else "PASS")
	for f in failures:
		print("  - ", f)
	quit(1 if not failures.is_empty() else 0)
	return true
