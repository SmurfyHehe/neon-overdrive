extends SceneTree

# Record my drive, then replay it (scripts/core/drive_recorder.gd and the shared
# test driver's "replay" mode).
#
#   godot --headless --fixed-fps 120 --path . -s res://tests/core/drive_replay.gd
#
# Part 1: the game runs with the recorder on while seeded random keys
# (TestDriver "fuzz", through PlayerCar.apply_keys, the path real key presses
# take) drive the car for DRIVE_SECS (default 6). Then the recorder saves, as
# F9 does. Part 2: the game is started again from that file (NEON_REPLAY, the
# same route as `-- --replay=<file>`) and the keys play back.
#
# Fails on: no file, a file that does not load, the replay pressing different
# keys, or the car ending more than MAX_DRIFT metres from where the recorded
# drive ended. A replay restores the car's position, speed, gear and rpm but
# not tyre or suspension state, so it lands close, not on the same millimetre;
# the drift is printed. No traffic: a replay does not restore it.

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const TestDriver := preload("res://scripts/core/test_driver.gd")
const DriveRecorder := preload("res://scripts/core/drive_recorder.gd")
const RATE := 120
const MAX_DRIFT := 15.0

var logger := Harness.ErrorCounter.new()
var game: Node
var p: PlayerCar
var bot: TestDriver
var secs := 6.0
var part := 1
var tick := 0
var file := ""
var end_s := 0.0
var end_x := 0.0
var pressed := PackedInt32Array()
var fails: Array[String] = []

func _initialize() -> void:
	OS.add_logger(logger)
	Engine.physics_ticks_per_second = RATE
	var sec := OS.get_environment("DRIVE_SECS")
	secs = float(sec) if sec.is_valid_float() else 6.0
	OS.set_environment("NEON_ROAD_SEED", "37")
	OS.set_environment("NEON_REPLAY", "")
	game = Harness.boot(self, 0, 300.0, 11)

func _physics_process(_delta: float) -> bool:
	if p == null:
		p = game.get("player")
		if p == null or not p.is_ready:
			p = null
			return false
		if part == 1:
			bot = TestDriver.start(game, "fuzz", {"seed": 21, "record_keys": true})
		else:
			bot = game.get("bot")
			if bot == null or bot.mode != "replay":
				fails.append("the game did not start a replay from %s" % file)
				return _end()
		return false
	tick += 1
	var u := RoadFrame.unroll(p.global_position)
	if part == 1 and tick >= int(secs * RATE):
		var rec: DriveRecorder = game.get("recorder")
		file = rec.save() if rec != null else ""
		if file == "":
			fails.append("the recorder saved nothing")
			return _end()
		var data := DriveRecorder.load_file(file)
		if data.is_empty():
			fails.append("the saved file does not load")
			return _end()
		pressed = PackedInt32Array(data.keys)
		end_s = RoadFrame.s_at(u.z)
		end_x = u.x
		print("drive_replay: recorded %d ticks to %s; car ended %.1f m down the road at x %.2f, %.0f km/h" % [
			pressed.size(), file.get_file(), end_s, end_x, p.linear_velocity.length() * 3.6])
		_restart()
		return false
	if part == 2 and bot.replay_done:
		var drift := Vector2(RoadFrame.s_at(u.z) - end_s, u.x - end_x).length()
		print("drive_replay: replay ended %.1f m down the road at x %.2f; %.2f m from the recorded end" % [RoadFrame.s_at(u.z), u.x, drift])
		if bot.keys != pressed:
			fails.append("the replay's keys are not the recorded ones")
		if drift > MAX_DRIFT:
			fails.append("the replay ended %.1f m from the recorded drive (limit %.0f)" % [drift, MAX_DRIFT])
		return _end()
	if tick > int((secs + 20.0) * RATE):
		fails.append("part %d timed out" % part)
		return _end()
	return false

func _restart() -> void:
	root.remove_child(game)
	game.free()
	p = null
	bot = null
	tick = 0
	part = 2
	OS.set_environment("NEON_REPLAY", file)
	game = Harness.boot(self, 0, 300.0, 11)

func _end() -> bool:
	OS.set_environment("NEON_REPLAY", "")
	if not logger.errors.is_empty():
		fails.append("%d engine errors, first: %s" % [logger.errors.size(), logger.errors[0]])
	for f in fails:
		printerr("FAIL: " + f)
	print("drive_replay: %s" % ("PASS" if fails.is_empty() else "FAIL (%d)" % fails.size()))
	quit(1 if not fails.is_empty() else 0)
	return true
