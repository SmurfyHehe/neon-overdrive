extends SceneTree

# Photo mode: drives the real Game.tscn. P enters (tree paused, HUD layers
# hidden, free camera current at the chase camera's pose), held keys move the
# free camera, Esc leaves and restores everything. A headless run has no
# framebuffer, so save_shot() must return "" there instead of crashing; with a
# real renderer it writes a PNG under user://photos. Exit code 1 on failure.
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/photo_mode.gd

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
