extends SceneTree

# F9 saves one bug-report folder (scripts/core/drive_recorder.gd, K3).
#
#   godot --headless --fixed-fps 120 --path . -s res://tests/core/bug_bundle.gd
#
# The game runs with seeded random keys driving the car for DRIVE_SECS (default
# 3), with 20 older report folders already in the (test) bug-report folder and
# one rebound key in the settings file. Then F9 is pressed as a real key event.
#
# Fails on: no folder, any of drive.json / screen.png / log.txt / info.txt /
# errors.txt
# missing or empty, drive.json not loading (by file, by folder and as "last"),
# screen.png not being a picture, info.txt missing a line it should have, the
# oldest of the 21 folders still being there (or any other one gone), no click,
# or anything drawn on screen by the recorder. Headless has no picture, so
# screen.png is the blank stand-in here; run without --headless to see a real one.

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const TestDriver := preload("res://scripts/core/test_driver.gd")
const TestMode := preload("res://scripts/core/test_mode.gd")
const DriveRecorder := preload("res://scripts/core/drive_recorder.gd")
const RATE := 120
const FILES := ["drive.json", "screen.png", "log.txt", "info.txt", "errors.txt"]
const INFO_HAS := ["git: branch ", "car: ", "night: ", "act: ", "graphics preset: ", "[keys]", "horn=", "[game state", " km/h"]

var logger := Harness.ErrorCounter.new()
var game: Node
var p: PlayerCar
var rec: DriveRecorder
var root_dir := ""
var secs := 3.0
var tick := 0
var pressed_at := -1
var fails: Array[String] = []

func _initialize() -> void:
	OS.add_logger(logger)
	Engine.physics_ticks_per_second = RATE
	var sec := OS.get_environment("DRIVE_SECS")
	secs = float(sec) if sec.is_valid_float() else 3.0
	OS.set_environment("NEON_ROAD_SEED", "37")
	OS.set_environment("NEON_REPLAY", "")
	root_dir = TestMode.path(DriveRecorder.DIR)
	_seed_old_reports()
	game = Harness.boot(self, 0, 300.0, 11)

## Empties the test folder of earlier runs, then makes 20 older reports.
func _seed_old_reports() -> void:
	DirAccess.make_dir_recursive_absolute(root_dir)
	for d in DirAccess.get_directories_at(root_dir):
		for f in DirAccess.get_files_at(root_dir.path_join(d)):
			DirAccess.remove_absolute(root_dir.path_join(d).path_join(f))
		DirAccess.remove_absolute(root_dir.path_join(d))
	for i in DriveRecorder.KEEP_REPORTS:
		var dir := root_dir.path_join(_old_name(i))
		DirAccess.make_dir_recursive_absolute(dir)
		var f := FileAccess.open(dir.path_join("drive.json"), FileAccess.WRITE)
		f.store_string("{}")
		f.close()

func _old_name(i: int) -> String:
	return "2020-01-01_00-00-%02d" % i

func _physics_process(_delta: float) -> bool:
	if p == null:
		p = game.get("player")
		if p == null or not p.is_ready:
			p = null
			return false
		TestDriver.start(game, "fuzz", {"seed": 21})
		return false
	tick += 1
	if pressed_at < 0 and tick >= int(secs * RATE):
		rec = game.get("recorder")
		if rec == null:
			fails.append("the game has no recorder")
			return _end()
		var cfg := ConfigFile.new()
		cfg.load(AudioSettings.path)
		cfg.set_value("keys", "horn", PackedInt32Array([KEY_H]))
		cfg.save(AudioSettings.path)
		for down in [true, false]:
			var ev := InputEventKey.new()
			ev.physical_keycode = KEY_F9
			ev.keycode = KEY_F9
			ev.pressed = down
			Input.parse_input_event(ev)
		pressed_at = tick
		return false
	if pressed_at >= 0 and (rec.last_dir != "" or tick > pressed_at + 2 * RATE):
		_check()
		return _end()
	return false

func _check() -> void:
	if rec.last_dir == "":
		fails.append("F9 saved no bug report")
		return
	rec.flush()
	var dir := rec.last_dir
	for name in FILES:
		var f := FileAccess.open(dir.path_join(name), FileAccess.READ)
		if f == null or f.get_length() == 0:
			fails.append("%s is missing or empty" % name)
	var drive := DriveRecorder.load_file(dir.path_join("drive.json"))
	if drive.is_empty() or (drive.keys as Array).is_empty():
		fails.append("drive.json does not load as a recording")
	if DriveRecorder.load_file(dir).is_empty():
		fails.append("the folder does not load as a recording")
	if DriveRecorder.newest() != rec.last_file or DriveRecorder.load_file("last").is_empty():
		fails.append("'last' is %s, not the new report" % DriveRecorder.newest())
	var img := Image.load_from_file(dir.path_join("screen.png"))
	if img == null or img.is_empty():
		fails.append("screen.png is not a picture")
	var info := FileAccess.get_file_as_string(dir.path_join("info.txt"))
	for part in INFO_HAS:
		if not info.contains(part):
			fails.append("info.txt has no '%s'" % part)
	if not info.contains(str(ProjectSettings.get_setting("application/config/version"))):
		fails.append("info.txt has no game version")
	var left := DriveRecorder.reports(root_dir)
	if left.size() != DriveRecorder.KEEP_REPORTS:
		fails.append("%d report folders are kept, not %d" % [left.size(), DriveRecorder.KEEP_REPORTS])
	if left.has(_old_name(0)):
		fails.append("the oldest report is still there")
	if not left.has(_old_name(1)) or not left.has(dir.get_file()):
		fails.append("a report that should stay is gone")
	if rec.get("_click") == null:
		fails.append("no click was played")
	if not rec.find_children("*", "CanvasItem", true, false).is_empty() or not rec.find_children("*", "CanvasLayer", true, false).is_empty():
		fails.append("the recorder drew something on screen")
	print("bug_bundle: %s holds %s; picture %dx%d; %d folders kept" % [
		dir.get_file(), ", ".join(DirAccess.get_files_at(dir)), img.get_width() if img != null else 0, img.get_height() if img != null else 0, left.size()])
	print("bug_bundle: info.txt:\n" + info)

func _end() -> bool:
	if not logger.errors.is_empty():
		fails.append("%d engine errors, first: %s" % [logger.errors.size(), logger.errors[0]])
	for f in fails:
		printerr("FAIL: " + f)
	print("bug_bundle: %s" % ("PASS" if fails.is_empty() else "FAIL (%d)" % fails.size()))
	quit(1 if not fails.is_empty() else 0)
	return true
