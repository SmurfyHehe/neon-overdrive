extends SceneTree

# The HUD rear strip (2026-10-06), headless and silent:
# - in the chase view the strip shows at the top centre, textured from the
#   cockpit's rearview SubViewport (nothing extra is rendered), flipped like a
#   mirror, and the rear viewport renders while the door mirrors do not
# - in the cockpit view the strip hides (the rearview mirror is there)
# - with FxSettings "rear_strip" off the strip hides and nothing renders in
#   the chase view; on again it comes back
# - no engine errors
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/ui/hud_rear_strip.gd

const TIMEOUT_TICKS := 60 * 30

class ErrorCounter extends Logger:
	var errors: Array[String] = []
	var _lock := Mutex.new()
	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_lock.lock()
		errors.append("%s (%s:%d in %s)" % [rationale if rationale != "" else code, file, line, function])
		_lock.unlock()
	func _log_message(_message: String, _error: bool) -> void:
		pass

enum Step { BOOT, CHASE, COCKPIT, OFF, ON, DONE }

var step := Step.BOOT
var step_start := 0
var tick := 0
var failures: Array[String] = []
var logger := ErrorCounter.new()
var rear_rendered := false
var side_rendered := false

func _initialize() -> void:
	ExhaustTune.save_path = "user://autotune/test_hud_rear_strip_exhaust.json"
	OS.add_logger(logger)
	change_scene_to_file("res://Game.tscn")

func _drive(c: PlayerCar) -> void:
	c.throttle_input = 0.5
	c.brake_input = 0.0
	c.steering_input = 0.0

func _physics_process(_delta: float) -> bool:
	tick += 1
	var game := current_scene
	if game == null or game.get("player") == null or game.get("camera") == null:
		return tick > TIMEOUT_TICKS and _end("Game never became ready")
	var hud: Hud = null
	for n in game.get_children():
		if n is Hud:
			hud = n
	if hud == null:
		return tick > TIMEOUT_TICKS and _end("Game has no Hud")
	var p: PlayerCar = game.player
	var cam: ChaseCamera = game.camera
	p.driver = _drive
	var frame: CockpitFrame = cam.frame
	var mirrors: CockpitMirrors = frame.mirrors
	var waited := tick - step_start
	# watch which viewports are queued to render, any tick
	if mirrors.views[0].vp.render_target_update_mode != SubViewport.UPDATE_DISABLED:
		rear_rendered = true
	if mirrors.views[1].vp.render_target_update_mode != SubViewport.UPDATE_DISABLED or mirrors.views[2].vp.render_target_update_mode != SubViewport.UPDATE_DISABLED:
		side_rendered = true
	match step:
		Step.BOOT:
			_check(FxSettings.is_on("rear_strip"), "the rear strip defaults on")
			_check(cam.view == ChaseCamera.View.CHASE, "the game starts in the chase view")
			_go(Step.CHASE)
		Step.CHASE:
			if waited == 10:
				_check(hud.rear_frame.visible, "the rear strip shows in the chase view")
				_check(hud.rear_strip.texture == mirrors.views[0].vp.get_texture(), "the strip is the rearview mirror's own render target")
				_check(hud.rear_strip.flip_h, "the strip is flipped like a mirror")
				_check(hud.rear_frame.anchor_left == 0.5 and hud.rear_frame.anchor_right == 0.5 and hud.rear_frame.anchor_top == 0.0, "the strip sits at the top centre")
				_check(hud.rear_frame.size.x >= Hud.STRIP_SIZE.x and hud.rear_frame.size.y >= Hud.STRIP_SIZE.y, "the strip is at least %s px (%s)" % [Hud.STRIP_SIZE, hud.rear_frame.size])
				_check(mirrors.strip, "the mirrors know the strip is on")
				_check(rear_rendered, "the rear viewport renders in the chase view for the strip")
				_check(not side_rendered, "the door mirrors do not render in the chase view")
				cam.set_view(ChaseCamera.View.COCKPIT)
				_go(Step.COCKPIT)
		Step.COCKPIT:
			if waited == 10:
				_check(not hud.rear_frame.visible, "the strip hides in the cockpit view")
				_check(not mirrors.strip, "the mirrors drop the strip request in the cockpit")
				cam.set_view(ChaseCamera.View.CHASE)
				FxSettings.set_on("rear_strip", false)
				rear_rendered = false
				_go(Step.OFF)
		Step.OFF:
			if waited == 3:
				rear_rendered = false   # the frame of the switch may still have one queued
			if waited == 12:
				_check(not hud.rear_frame.visible, "the strip hides with the flag off")
				_check(not mirrors.strip and not rear_rendered and not mirrors.is_rendering(), "nothing renders for the strip with the flag off")
				FxSettings.set_on("rear_strip", true)
				_go(Step.ON)
		Step.ON:
			if waited == 10:
				_check(hud.rear_frame.visible and mirrors.strip and rear_rendered, "the strip comes back with the flag on")
				_check(logger.errors.is_empty(), "engine errors: %s" % [logger.errors.slice(0, 5)])
				return _end("")
	return false

func _go(next: Step) -> void:
	step = next
	step_start = tick

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _end(msg: String) -> bool:
	if msg != "":
		failures.append(msg)
	for f in failures:
		printerr("FAIL: ", f)
	print("hud_rear_strip: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
	return true
