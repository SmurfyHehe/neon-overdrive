extends SceneTree

# Error and crash log (scripts/core/error_log.gd).
#
#   godot --headless --path . -s res://tests/core/error_log.gd
#
# Checks: the ErrorLog autoload is up and its logger is installed; a script
# error and a warning land in errors.log with where they came from, account
# names scrubbed out, the first one with game state; the same error 50 times is
# written REPEAT_CAP times and counted; session.txt is marked running. Then a
# crashed last run is faked (session.txt left running, a godot<time>.log with
# Godot's crash line and a home path in it, an errors.log) and check_last_run()
# must make one crash folder with info.txt / log.txt / errors.txt, say it was a
# crash, scrub the name, mark the session closed and not report it twice. A
# last run that closed must make nothing. Exit code 1 on failure.

const ErrorLog := preload("res://scripts/core/error_log.gd")
const LogFolder := preload("res://scripts/core/log_folder.gd")
const FAKE_LOG := "godot9999-12-31T23.59.59.log"   # sorts after any real rotated log
const NAME := "Zxqvbn"   # a made-up account name that must never reach a report

var fails: Array[String] = []
var frames := 0
var phases := 0   # a script error mid-phase must not end in PASS

func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)

func _process(_delta: float) -> bool:
	frames += 1
	if frames < 3:   # let the autoload sample a state line
		return false
	_live_run()
	_fake_crash()
	_check(phases == 2, "both checks should run to the end (a script error stopped one)")
	print("error_log: ", "FAIL" if not fails.is_empty() else "PASS")
	for f in fails:
		print("  - ", f)
	quit(1 if not fails.is_empty() else 0)
	return true

func _live_run() -> void:
	var log: Node = ErrorLog.instance()
	_check(log != null, "the ErrorLog autoload should be in the tree")
	if log == null:
		return
	_check(ErrorLog.errors_path().get_file() == "test_errors.log", "a test run should write test_errors.log, got %s" % ErrorLog.errors_path())
	push_error("error_log test: could not open C:/Users/%s/AppData/thing.cfg" % NAME)
	push_warning("error_log test: a warning from /home/%s/x" % NAME)
	for i in 50:
		push_error("error_log test: the same error every frame")
	var text := FileAccess.get_file_as_string(ErrorLog.errors_path())
	_check(text.contains("error_log test: could not open"), "errors.log should hold the error, got:\n" + text)
	_check(text.contains("WARNING") and text.contains("a warning from"), "errors.log should hold the warning")
	_check(text.contains("tests/core/error_log.gd:"), "an error should say which script and line it came from")
	_check(not text.contains(NAME), "errors.log should not hold the account name")
	_check(text.contains("Users/<user>") and text.contains("/home/<user>"), "the account name should become <user>")
	_check(text.contains("game state, the last seconds"), "the first error should come with game state")
	_check(text.count("the same error every frame") == ErrorLog.REPEAT_CAP,
			"a repeating error should be written %d times, got %d" % [ErrorLog.REPEAT_CAP, text.count("the same error every frame")])
	_check(FileAccess.get_file_as_string(ErrorLog.session_path()).begins_with(ErrorLog.RUNNING), "session.txt should say running")
	_check(log.state_text().contains("fps"), "a state line should have been sampled, got '%s'" % log.state_text())
	_check(ErrorLog.scrub(ProjectSettings.globalize_path("user://x")) == "user://x", "scrub should give the user folder back as user://")
	_check(ErrorLog.scrub("C:\\Users\\%s\\Desktop" % NAME) == "C:\\Users\\<user>\\Desktop", "scrub should handle backslash paths")
	phases += 1

func _fake_crash() -> void:
	# Scratch files: this run's own errors.log is open and must not be touched.
	var scratch := "user://test_error_log_scratch"
	DirAccess.make_dir_recursive_absolute(scratch)
	var session := scratch.path_join("session.txt")
	var errors := scratch.path_join("errors.log")
	var prev := scratch.path_join("errors_prev.log")
	var root := scratch.path_join("bug_reports")
	var fake_log := LogFolder.log_dir().path_join(FAKE_LOG)

	_put(session, "%s\nBoost Simcade 0.1.0\nstarted: then\n\n20:00:00 +5 s  playing  car kei  92 km/h\n" % ErrorLog.RUNNING)
	_put(errors, "old run: an error from C:/Users/%s/x\n" % NAME)
	_put(fake_log, "Godot Engine v4.7.2\nloading C:/Users/%s/AppData/Roaming/Godot/x\nCrashHandlerException: Program crashed\n[1] something\n" % NAME)
	var dir := ErrorLog.check_last_run_at(session, errors, prev, root)
	_check(dir != "" and DirAccess.dir_exists_absolute(dir), "a crashed last run should make a crash folder")
	_check(dir.get_file().contains("_crash"), "the crash folder should say crash in its name, got %s" % dir.get_file())
	for f in ["info.txt", "log.txt", "errors.txt"]:
		var t := FileAccess.get_file_as_string(dir.path_join(f))
		_check(t.length() > 0, "the crash folder should have a non-empty %s" % f)
		_check(not t.contains(NAME), "%s should not hold the account name" % f)
	var info := FileAccess.get_file_as_string(dir.path_join("info.txt"))
	_check(info.contains(ErrorLog.ENDED_CRASH), "info.txt should say the game crashed, got:\n" + info)
	_check(info.contains("92 km/h"), "info.txt should carry the last run's game state")
	_check(FileAccess.get_file_as_string(dir.path_join("log.txt")).contains("Program crashed"), "log.txt should be the last run's log")
	_check(FileAccess.get_file_as_string(dir.path_join("errors.txt")).contains("old run: an error"), "errors.txt should be the last run's errors")
	_check(not FileAccess.file_exists(errors), "the last run's errors.log should have been moved aside")
	_check(FileAccess.get_file_as_string(session).begins_with(ErrorLog.CLOSED), "session.txt should be closed once reported")
	_check(ErrorLog.check_last_run_at(session, errors, prev, root) == "", "the same crash should not be reported twice")

	# A run killed with no crash line: still a report, worded as stopped.
	_put(session, ErrorLog.RUNNING + "\n")
	_put(fake_log, "Godot Engine v4.7.2\nnothing wrong\n")
	var dir2 := ErrorLog.check_last_run_at(session, errors, prev, root)
	_check(dir2 != "" and FileAccess.get_file_as_string(dir2.path_join("info.txt")).contains(ErrorLog.ENDED_STOPPED),
			"a run that stopped without a crash line should be reported as stopped")
	_check(_crash_dirs(root).size() == 2, "exactly two crash folders should have been made, got %d" % _crash_dirs(root).size())

	# A run that closed: nothing.
	_put(session, ErrorLog.CLOSED + "\n")
	_check(ErrorLog.check_last_run_at(session, errors, prev, root) == "", "a run that closed should make no report")

	DirAccess.remove_absolute(fake_log)
	_remove_tree(scratch)
	phases += 1

func _remove_tree(dir: String) -> void:
	for d in DirAccess.get_directories_at(dir):
		_remove_tree(dir.path_join(d))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)

func _crash_dirs(root: String) -> PackedStringArray:
	var out := PackedStringArray()
	if DirAccess.dir_exists_absolute(root):
		for d in DirAccess.get_directories_at(root):
			if d.contains("_crash"):
				out.append(d)
	return out

func _put(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
