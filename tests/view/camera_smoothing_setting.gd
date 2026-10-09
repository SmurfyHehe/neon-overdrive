extends SceneTree

# Camera smoothing setting (#31, PR #148): runs the real Game.tscn and checks
# - launch: a camera_smoothing saved by a previous launch is the chase
#   camera's mode right after boot (here C, "smoothing + swing")
# - mode C eases: a sideways push on the camera is still mostly there a frame later
# - pause menu: has a Camera selector that reaches every mode (A, B, C) and
#   shows the loaded one
# - picking A while paused saves camera_smoothing=0 to the settings file, and
#   after resume the camera is in A and behaves like it: the same sideways
#   push is gone on the very next frame (hard snap)
# The test uses its own settings file and deletes it at the end, so the real
# user://settings.cfg (and test mode's test_settings.cfg) are never touched.
#
# The camera places itself in _process, so the push/measure steps run in this
# SceneTree's _process, which Godot calls before the nodes' _process each frame.
#
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/view/camera_smoothing_setting.gd

const CFG := "user://camera_smoothing_test.cfg"
const TIMEOUT_TICKS := 600
const SETTLE_TICKS := 30
const OFFSET := 5.0            # metres the camera's follow point is pushed sideways

enum Step { BOOT, EASE_PUSH, EASE_CHECK, PAUSE, MENU, RESUME, SNAP_PUSH, SNAP_CHECK }

var step := Step.BOOT
var tick := 0
var step_start := 0
var failures: Array[String] = []

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	AudioSettings.path = CFG
	DirAccess.remove_absolute(CFG)
	var cfg := ConfigFile.new()
	cfg.set_value("view", "camera_smoothing", 2)   # what a previous launch saved
	cfg.save(CFG)
	change_scene_to_file("res://Game.tscn")

func _physics_process(_delta: float) -> bool:
	tick += 1
	var game := current_scene
	var waited := tick - step_start
	match step:
		Step.BOOT:
			if _is_ready(game) and waited > SETTLE_TICKS:
				_check(ViewSettings.camera_smoothing == 2, "saved smoothing 2 should load at launch, got %d" % ViewSettings.camera_smoothing)
				_check(game.camera.mode == 2, "camera should start in mode C (2) from the saved file, got %d" % game.camera.mode)
				_go(Step.EASE_PUSH)
			elif waited > TIMEOUT_TICKS:
				return _abort("Game.tscn never became ready")
		Step.PAUSE:
			game.game_state.pause()
			_go(Step.MENU)
		Step.MENU:
			if paused:
				_drive_menu(game)
				game.game_state.resume()
				_go(Step.RESUME)
			elif waited > TIMEOUT_TICKS:
				return _abort("pause() did not pause the tree")
		Step.RESUME:
			if not paused and waited > 5:
				_check(game.camera.mode == 0, "after resume the camera should be in mode A (0), got %d" % game.camera.mode)
				_go(Step.SNAP_PUSH)
			elif waited > TIMEOUT_TICKS:
				return _abort("resume() did not unpause the tree")
	return false

func _process(_delta: float) -> bool:
	if step < Step.EASE_PUSH:
		return false
	var game := current_scene
	var cam: ChaseCamera = game.camera
	match step:
		Step.EASE_PUSH, Step.SNAP_PUSH:
			cam._follow += Vector2(OFFSET, 0)
			step = Step.EASE_CHECK if step == Step.EASE_PUSH else Step.SNAP_CHECK
		Step.EASE_CHECK:
			var left := _offset_left(cam)
			_check(left > 1.0, "mode C should ease a %.0f m push out slowly, but only %.2f m was left a frame later" % [OFFSET, left])
			_go(Step.PAUSE)
		Step.SNAP_CHECK:
			var left := _offset_left(cam)
			_check(left < 0.01, "mode A should snap a %.0f m push away in one frame, %.2f m left" % [OFFSET, left])
			return _finish()
	return false

func _offset_left(cam: ChaseCamera) -> float:
	return absf(cam._follow.x - cam.target.get_global_transform_interpolated().origin.x)

func _drive_menu(game: Node) -> void:
	var menu := _menu(game)
	_check(menu.visible, "pause menu should be visible while paused")
	var s: HSlider = menu.settings.smoothing_slider
	_check(s != null, "pause menu has no camera smoothing selector")
	if s == null:
		return
	var last := ChaseCamera.MODE_NAMES.size() - 1
	var label := (s.get_parent().get_child(0) as Label).text
	_check(label.to_lower().contains("camera"), "selector label should say Camera, got '%s'" % label)
	_check(is_equal_approx(s.min_value, 0.0) and is_equal_approx(s.max_value, float(last)) and is_equal_approx(s.step, 1.0),
		"selector should step 0..%d, one notch per mode (got %.1f..%.1f step %.1f)" % [last, s.min_value, s.max_value, s.step])
	_check(is_equal_approx(s.value, 2.0), "selector should show the loaded mode 2, got %.0f" % s.value)
	for v in range(last + 1):
		s.value = v
		_check(ViewSettings.camera_smoothing == v, "selector notch %d should set the setting, got %d" % [v, ViewSettings.camera_smoothing])
	s.value = 0
	var cfg := ConfigFile.new()
	_check(cfg.load(CFG) == OK and int(cfg.get_value("view", "camera_smoothing", -1)) == 0,
		"choosing A should save camera_smoothing=0 to the settings file")

func _is_ready(game: Node) -> bool:
	return game != null and is_instance_valid(game) and game.get("camera") != null \
		and game.get("game_state") != null and _menu(game) != null

func _menu(game: Node) -> PauseMenu:
	for c in game.get_children():
		if c is PauseMenu:
			return c
	return null

func _go(s: Step) -> void:
	step = s
	step_start = tick

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _abort(msg: String) -> bool:
	failures.append(msg)
	return _finish()

func _finish() -> bool:
	DirAccess.remove_absolute(CFG)
	print("camera_smoothing_setting: ", "FAIL" if not failures.is_empty() else "PASS")
	for f in failures:
		print("  - ", f)
	quit(1 if not failures.is_empty() else 0)
	return true
