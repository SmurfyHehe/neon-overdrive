extends SceneTree

# Wet roads on some nights (2026-10-09), headless. Checks that
# - RoadChunkBuilder.set_wet() makes the asphalt darker and glossy and back
#   again exactly (dry = the stage A matte)
# - with NEON_WET=1 the game boots wet, every chunk has its lamp streaks
#   shown; with NEON_WET=0 dry and hidden
# - unforced, about WET_CHANCE of nights roll wet
# - nothing logs an error
# The streaks' look was checked by eye on the real renderer.
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/wet_road.gd

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

func _check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)

func _initialize() -> void:
	OS.add_logger(logger)
	var m := RoadChunkBuilder._get_own_mat()
	var dry_color := m.albedo_color
	var dry_rough := m.roughness
	RoadChunkBuilder.set_wet(true)
	_check(m.roughness < 0.3 and m.albedo_color.get_luminance() < dry_color.get_luminance(), "wet asphalt is darker and glossy")
	RoadChunkBuilder.set_wet(true)
	var twice := m.albedo_color
	RoadChunkBuilder.set_wet(false)
	_check(m.albedo_color == dry_color and is_equal_approx(m.roughness, dry_rough), "drying gives back the exact dry look")
	RoadChunkBuilder.set_wet(true)
	_check(m.albedo_color == twice, "wetting twice does not darken twice")
	RoadChunkBuilder.set_wet(false)
	OS.set_environment("NEON_WET", "1")
	game = Harness.boot(self, 0, 300.0, 3)

func _streaks_visible() -> Array:
	var out := []
	for c in game.chunk_pool:
		out.append((c.root.get_node("LampStreaks") as Node3D).visible)
	return out

func _process(_d: float) -> bool:
	frame += 1
	if frame == 20:
		_check(RoadChunkBuilder.wet, "NEON_WET=1 boots wet")
		_check(_streaks_visible().all(func(v: bool) -> bool: return v), "every chunk shows its lamp streaks when wet")
		OS.set_environment("NEON_WET", "0")
		_check(not game._roll_wet(), "NEON_WET=0 rolls dry")
		OS.set_environment("NEON_WET", "")
		var wet := 0
		for i in 4000:
			if game._roll_wet():
				wet += 1
		var share := float(wet) / 4000.0
		print("wet share %.3f" % share)
		_check(absf(share - game.WET_CHANCE) < 0.03, "about %.0f%% of nights are wet (%.3f)" % [game.WET_CHANCE * 100.0, share])
		RoadChunkBuilder.set_wet(false, self)
		_check(not _streaks_visible().any(func(v: bool) -> bool: return v), "drying hides every chunk's streaks")
	if frame == 25:
		for e in logger.errors:
			failures.append("logged error: " + e)
		if failures.is_empty():
			print("wet_road: PASS")
			quit(0)
		else:
			for f in failures:
				print("FAIL ", f)
			quit(1)
		return true
	return false
