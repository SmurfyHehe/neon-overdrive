extends SceneTree

# Falling rain (2026-10-14, scripts/fx/rain_fall.gd), headless and silent:
# boots the real Game.tscn with NEON_WEATHER unset (dry) and checks that
# - game.fx.rain (RainFall) is on the player car, one MultiMesh with the
#   Medium preset's drop count, hidden while the night is dry
# - the "rain" effect flag defaults on and turns the node off and on
# - setting Weather to RAIN (instant) shows it with about 70% of the drops,
#   DOWNPOUR shows every drop, DRY hides it again; the `amount` uniform
#   follows Weather.rain
# - the preset changes the drop count (Low 600, Medium 1400, High 2400;
#   "custom" keeps Medium's), looping over every preset
# - every view (chase, cockpit, hood) and the cockpit mirrors can see the
#   rain's render layer, looping over the views
# - the streaks fall on the game clock: `now` moves while the game runs and
#   stops while the tree is paused (pause menu, photo mode)
# - the headlight cone starts at the car's own "Headlights" lamp, for EVERY
#   playable car (the scene is rebooted once per PlayerCars.KINDS entry)
# - the car's velocity reaches the shader only when it has moved by
#   VEL_STEP (no per-tick writes), and the headlight switch reaches it
# - nothing in RainFall runs per frame or per physics tick (no _process)
# - the shader compiles (no parse error from the shader compiler)
# - nothing logs an error the whole time
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/fx/rain_fall.gd

const Weather := preload("res://scripts/world/weather.gd")
const TIMEOUT_TICKS := 60 * 60

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

var logger := ErrorCounter.new()
var tick := 0
var stage := 0
var stage_tick := 0
var failures: Array[String] = []
const FREEZES := ["photo", "pause"]
var _paused_now := -1.0
var _freeze_index := 0
var car_index := 0
var _prev_game: Node

func _initialize() -> void:
	OS.add_logger(logger)
	seed(4242)
	change_scene_to_file("res://Game.tscn")

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
		print("FAIL ", msg)

func _physics_process(_delta: float) -> bool:
	tick += 1
	var game := current_scene
	if game == null or game.get("player") == null or game.get("fx") == null:
		return tick > TIMEOUT_TICKS and _end("Game never became ready")
	if tick > TIMEOUT_TICKS:
		return _end("timed out in stage %d" % stage)
	var p: PlayerCar = game.player
	var fx: FxPack = game.fx
	var r: RainFall = fx.rain
	var waited := tick - stage_tick
	match stage:
		0:
			if waited < 5:
				return false
			_check(r != null and r.is_inside_tree() and r.get_parent() == p, "RainFall should ride on the player car")
			_check(r.multimesh != null and r.multimesh.instance_count == RainFall.COUNT["medium"],
				"Medium should hold %d drops (got %s)" % [RainFall.COUNT["medium"], str(r.multimesh.instance_count) if r.multimesh else "none"])
			_check(r.multimesh.use_custom_data, "drops should carry their seeds in custom data")
			_check(not r.visible and r.multimesh.visible_instance_count == 0, "a dry night should draw no rain")
			_check(not r.is_processing() and not r.is_physics_processing(), "RainFall must not run per frame")
			_check(FxSettings.is_on("rain"), "the rain effect should default on")
			_check(r.custom_aabb.size.x > 1000.0, "the drop box needs a custom AABB so the camera never culls it")
			_check_shader(r)
			Weather.set_level(Weather.Level.RAIN, true)
			_go(1)
		1:
			if waited < 3:
				return false
			var want := int(round(r.capacity * Weather.STAGE[Weather.Level.RAIN].rain))
			_check(r.visible, "steady rain should show the streaks")
			_check(is_equal_approx(r.amount, Weather.rain), "amount should follow Weather.rain (%.2f vs %.2f)" % [r.amount, Weather.rain])
			_check(r.multimesh.visible_instance_count == want,
				"steady rain should draw %d of %d drops (got %d)" % [want, r.capacity, r.multimesh.visible_instance_count])
			_check(is_equal_approx(float(r.material_override.get_shader_parameter("amount")), Weather.rain), "the amount uniform should be written")
			fx.set_effect("rain", false)
			r.sync()
			_check(not r.enabled and not r.visible, "rain off should hide the streaks")
			fx.set_effect("rain", true)
			r.sync()
			_check(r.enabled and r.visible, "rain on should show them again")
			Weather.set_level(Weather.Level.DOWNPOUR, true)
			_go(2)
		2:
			if waited < 3:
				return false
			_check(r.multimesh.visible_instance_count == r.capacity, "a downpour should draw every drop (%d of %d)" % [r.multimesh.visible_instance_count, r.capacity])
			# presets
			var was := GraphicsSettings.preset
			for preset in GraphicsSettings.PRESETS + ["custom"]:
				GraphicsSettings.preset = preset
				r.apply_graphics()
				var want_n: int = RainFall.COUNT.get(preset, RainFall.COUNT_DEFAULT)
				_check(r.capacity == want_n and r.multimesh.instance_count == want_n,
					"%s should hold %d drops (got %d)" % [preset, want_n, r.capacity])
				_check(r.multimesh.visible_instance_count == r.capacity, "%s in a downpour should draw every drop" % preset)
			GraphicsSettings.preset = was
			r.apply_graphics()
			# every view's camera, and the mirrors, see the rain's layer
			var cam: ChaseCamera = game.camera
			for v in ChaseCamera.View.values():
				cam.set_view(v)
				_check((cam.cull_mask & r.layers) != 0, "view %d should see the rain layer" % v)
			cam.set_view(ChaseCamera.View.CHASE)
			_check((CockpitFrame.MIRROR_CULL & r.layers) != 0, "the cockpit mirrors should see the rain layer")
			# the clock: moves while the game runs, stops in photo mode and on
			# the pause screen (the game's own states)
			_check(r.now > 0.0, "now should have moved by now")
			_freeze_index = 0
			_go(21)
			# velocity reaches the shader in steps, not every tick
			var v0: Vector3 = r.material_override.get_shader_parameter("car_vel")
			p.linear_velocity = Vector3(0.0, 0.0, -0.4)
			r.sync()
			_check(r.material_override.get_shader_parameter("car_vel") == v0, "a %.1f m/s change should not rewrite car_vel" % 0.4)
			p.linear_velocity = Vector3(0.0, 0.0, -25.0)
			r.sync()
			_check(r.material_override.get_shader_parameter("car_vel") == Vector3(0.0, 0.0, -25.0), "a 25 m/s change should reach the shader")
			p.linear_velocity = Vector3.ZERO
			# headlights
			p.set_headlights(false)
			r.sync()
			_check(float(r.material_override.get_shader_parameter("head_on")) == 0.0, "lights off should reach the shader")
			p.set_headlights(true)
			r.sync()
			_check(float(r.material_override.get_shader_parameter("head_on")) == 1.0, "lights on should reach the shader")
			Weather.set_level(Weather.Level.DRY, true)
			_go(3)
		21:
			var gs: GameState = game.game_state
			if _freeze_index >= FREEZES.size():
				_check(not paused and gs.state == GameState.State.PLAYING, "the game should be playing again after the freeze checks")
				Weather.set_level(Weather.Level.DRY, true)
				_go(3)
				return false
			var fz: String = FREEZES[_freeze_index]
			if waited == 0:
				if fz == "photo":
					gs.toggle_photo()
				else:
					gs.pause()
				_paused_now = -1.0
				return false
			if waited < 4:
				return false
			if _paused_now < 0.0:
				_check(paused, "%s should pause the tree" % fz)
				_paused_now = r.now
				return false
			if waited < 8:
				return false
			_check(r.now == _paused_now, "now should not move in %s (%.3f vs %.3f)" % [fz, r.now, _paused_now])
			if fz == "photo":
				gs.close_photo()
			else:
				gs.resume()
			_freeze_index += 1
			_go(21)
		3:
			if waited < 3:
				return false
			_check(not r.visible and r.multimesh.visible_instance_count == 0, "back to dry should hide the rain (visible %s amount %.2f weather.rain %.2f paused %s level %d)" % [r.visible, r.amount, Weather.rain, paused, Weather.level])
			# the pin wins over the weather
			RainFall.pin = 0.5
			r.sync()
			_check(r.visible and is_equal_approx(r.amount, 0.5), "NEON_RAIN pin should draw half rain on a dry night")
			RainFall.pin = -1.0
			r.sync()
			_check(not r.visible, "clearing the pin should follow the weather again")
			_go(4)
		4:
			# every playable car: reboot the scene with NEON_CAR and check the
			# rain rides on it and its cone starts at that car's own lamp
			if car_index >= PlayerCars.KINDS.size():
				return _end("")
			var kind: String = PlayerCars.KINDS[car_index].id
			OS.set_environment("NEON_CAR", kind)
			Weather.reset()
			_prev_game = game
			change_scene_to_file("res://Game.tscn")
			_go(5)
		5:
			if waited < 8:
				return false
			var kind: String = PlayerCars.KINDS[car_index].id
			if game == _prev_game:
				return waited > 1200 and _end("%s never booted" % kind)
			Weather.set_level(Weather.Level.DOWNPOUR, true)
			r.sync()
			var spot := p.get_node_or_null("Headlights") as Node3D
			_check(r.get_parent() == p and r.visible, "%s: rain should ride on the car and show in a downpour" % kind)
			_check(spot != null and r.head_offset() == spot.position,
				"%s: the cone should start at the car's own headlamp (%s vs %s)" % [kind, r.head_offset(), spot.position if spot else "no lamp"])
			print("rain_fall: %s ok" % kind)
			car_index += 1
			_go(4)
	return false

func _go(s: int) -> void:
	stage = s
	stage_tick = tick

func _check_shader(r: RainFall) -> void:
	var sh: Shader = (r.material_override as ShaderMaterial).shader
	_check(sh != null and sh.code.find("CAMERA_POSITION_WORLD") >= 0, "the shader should place drops from the camera")
	# a parse error logs an error at compile time, which the logger catches

func _end(msg: String) -> bool:
	if msg != "":
		failures.append(msg)
	for e in logger.errors:
		failures.append("error logged: " + e)
	Weather.reset()
	if failures.is_empty():
		print("rain_fall: PASS (%d ticks)" % tick)
		quit(0)
	else:
		print("rain_fall: %d failure(s)" % failures.size())
		for f in failures:
			print("  ", f)
		quit(1)
	return true
