extends SceneTree

# Street lamps light the car and the cabin as it passes (2026-10-09). Boots
# the real Game.tscn (real renderer: headless drops MultiMesh transforms, and
# the lamp positions are read from them), drives slowly down the road and
# checks that
# - PassingLampLight finds lamps near the car, never a dead one
# - in the chase view its spots light the car layer only, in the cockpit view
#   the cabin and driver layers only
# - each spot sits on a lamp head and aims at the car's centre line level with
#   it, so the lit band is where the lamp is
# - nothing logs an error
# Exit code 1 on failure. Run (a window opens for ~20 s):
#   Godot_v4.7.2-stable_win64_console.exe --path . --audio-driver Dummy -s res://tests/passing_lamp_light.gd

const Harness := preload("res://tests/traffic_harness.gd")

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
var failures: Array[String] = []
var game: Node
var frame := 0
var seen_lamps := false
var seen_dead := false
var lit_chase := 0
var lit_cockpit := 0
var dark := 0
var bad_mask := 0
var bad_aim := 0

func _initialize() -> void:
	OS.add_logger(logger)
	OS.set_environment("NEON_CURVES", "0")
	OS.set_environment("NEON_HILLS", "0")
	game = Harness.boot(self, 0, 300.0, 7)

func _drive(c: PlayerCar) -> void:
	c.throttle_input = 0.35 if c.current_speed() < 12.0 else 0.0
	c.brake_input = 0.0
	c.steering_input = 0.0

func _process(_d: float) -> bool:
	frame += 1
	if paused:
		for n in game.get_children():
			if n is GameState:
				n.resume()
	if frame < 30:
		return false
	var p: PlayerCar = game.player
	p.driver = _drive
	var pl := game.get_node_or_null("PassingLampLight") as PassingLampLight
	if pl == null:
		return _end("no PassingLampLight in the game")
	if frame == 600:
		game.camera.set_view(ChaseCamera.View.COCKPIT)
	if frame > 60:
		var cockpit: bool = game.camera.view == ChaseCamera.View.COCKPIT
		var want := (CockpitFrame.INTERIOR_BIT | CockpitFrame.DRIVER_BIT) if cockpit else CockpitFrame.CAR_BIT
		var lamps := pl.nearby_lamps()
		if lamps.size() > 0:
			seen_lamps = true
		for l in lamps:
			if float(l[1]) <= 0.0:
				seen_dead = true
		var any := false
		for s in pl.spots:
			if not s.visible:
				continue
			any = true
			# (The light catches up with a view switch on the next frame.)
			if s.light_cull_mask != want and frame != 600:
				bad_mask += 1
			# Aimed at the car's centre line level with the lamp.
			var fwd := -s.global_basis.z
			var local := p.to_local(s.global_position)
			var target := p.to_global(Vector3(0.0, 1.0, local.z))
			if fwd.dot((target - s.global_position).normalized()) < 0.999:
				bad_aim += 1
		if any:
			if cockpit:
				lit_cockpit += 1
			else:
				lit_chase += 1
		else:
			dark += 1
	if frame >= 1140:
		_check(seen_lamps, "finds lamps near the car")
		_check(not seen_dead, "never lights from a dead lamp")
		_check(lit_chase > 0, "lights the car in the chase view")
		_check(lit_cockpit > 0, "lights the cabin in the cockpit view")
		_check(bad_mask == 0, "spots light only the view's layers (%d wrong)" % bad_mask)
		_check(bad_aim == 0, "spots aim at the car level with their lamp (%d off)" % bad_aim)
		print("frames lit chase %d, lit cockpit %d, dark %d" % [lit_chase, lit_cockpit, dark])
		return _end("")
	return false

func _check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)

func _end(why: String) -> bool:
	if why != "":
		failures.append(why)
	for e in logger.errors:
		failures.append("logged error: " + e)
	if failures.is_empty():
		print("passing_lamp_light: PASS")
		quit(0)
	else:
		for f in failures:
			print("FAIL ", f)
		quit(1)
	return true
