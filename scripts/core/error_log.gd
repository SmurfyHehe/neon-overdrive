extends Node

# Error and crash log (2026-10-11, so a playtester's bugs reach Roy). An
# autoload, so it is up before the title screen and outlives every scene.
#
# Built on what Godot already does:
#   - godot.log: Godot writes every print, error and warning to
#     user://logs/godot.log, keeps the last few runs as godot<time>.log, and on
#     a crash its crash handler writes the backtrace there before the game dies.
#   - Logger (Godot 4.5+): OS.add_logger() hands every script error, engine
#     error and warning to _log_error() as it happens.
#
# This adds three things on top:
#   errors.log    user://logs/errors.log, this run's errors and warnings only,
#                 each with the time, where it came from and the GDScript call
#                 stack (when Godot tracked one). The same error repeating every
#                 frame is written REPEAT_CAP times, then only counted; the
#                 counts go in at the end. The first error also gets the last
#                 few seconds of game state.
#   session.txt   user://logs/session.txt, rewritten every BEAT_SECS while the
#                 game runs: version, start time and the last STATE_SECS of game
#                 state (one line a second: screen, car, speed, gear, rpm, place,
#                 night, fps). A clean quit marks it closed.
#   crash report  on the next start, a session.txt still marked running means
#                 the last run crashed, froze and was killed, or lost power. A
#                 bug-report folder is made like F9's,
#                 user://bug_reports/<date>_<time>_crash/, holding info.txt
#                 (how it ended, version, its last game state), log.txt (that
#                 run's godot log, with the crash backtrace if Godot got one
#                 written) and errors.txt (that run's errors.log).
# F9's folder (drive_recorder.gd) also gets errors.txt and the state lines.
#
# No personal data: scrub() turns the user's home folder, the user data folder
# and the project folder in any copied text into ~, user:// and res://, so no
# Windows account name ends up in a report. Nothing is sent anywhere; the files
# stay on the player's PC until they send the folder.
#
# Test runs (TestMode) use test_* file names, so a test killed by a timeout on
# Roy's laptop never makes a crash report in the real game's folder.
# No class_name on purpose: preload it for the static helpers.

const TestMode := preload("res://scripts/core/test_mode.gd")
const GameInfo := preload("res://scripts/core/game_info.gd")
const LogFolder := preload("res://scripts/core/log_folder.gd")
const PipelineCache := preload("res://scripts/core/pipeline_cache.gd")

const ERRORS := "user://logs/errors.log"
const SESSION := "user://logs/session.txt"
const PREV_ERRORS := "user://logs/errors_prev.log"
const REPORTS := "user://bug_reports"   # drive_recorder.gd's DIR
const KEEP_REPORTS := 20                # drive_recorder.gd's KEEP_REPORTS
const STATE_SECS := 10
const BEAT_SECS := 2.0
const REPEAT_CAP := 3       # the same error written this many times, then counted
const MAX_ENTRIES := 500   # per run; after that only counted
const MAX_FRAMES := 8      # call stack lines per error
const RUNNING := "status: running"
const CLOSED := "status: closed"
const ENDED_CRASH := "the game crashed (Godot's crash handler wrote a backtrace into log.txt)"
const ENDED_STOPPED := "the game stopped without closing: a crash Godot could not catch, a freeze that was ended, or the PC losing power"

## The bug-report folder made at this start for the last run's crash, "" if none.
var crash_report := ""

var _logger: ErrorLogger
var _state := PackedStringArray()   # oldest first, one line a second
var _started := ""
var _next_sample := 0
var _next_beat := 0

func _init() -> void:
	name = "ErrorLog"
	process_mode = Node.PROCESS_MODE_ALWAYS   # keeps sampling on pause and title screens
	_started = Time.get_datetime_string_from_system(false, true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LogFolder.log_dir()))
	crash_report = check_last_run()
	_logger = ErrorLogger.new(errors_path(), GameInfo.title(), _started)
	_logger.state_source = state_text
	OS.add_logger(_logger)
	_write_session(RUNNING)
	PipelineCache.check_at_start()   # exported builds only (#608)

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if now >= _next_sample:
		_next_sample = now + 1000
		_sample()
	if now >= _next_beat:
		_next_beat = now + int(BEAT_SECS * 1000.0)
		_write_session(RUNNING)

func _exit_tree() -> void:
	close()

## Ends this run cleanly: repeat counts into errors.log, session marked closed.
func close() -> void:
	if _logger == null:
		return
	OS.remove_logger(_logger)
	_logger.finish()
	_logger = null
	_write_session(CLOSED)
	PipelineCache.tidy_at_exit()

static func errors_path() -> String:
	return TestMode.path(ERRORS)

static func session_path() -> String:
	return TestMode.path(SESSION)

## The running ErrorLog, or null (a test that runs without autoloads).
static func instance() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return null if tree == null else tree.root.get_node_or_null("ErrorLog")

## The last STATE_SECS of game state, oldest first, one line a second.
func state_text() -> String:
	return "\n".join(_state) + ("\n" if not _state.is_empty() else "")

## This run's errors.log so far (scrubbed).
static func errors_text() -> String:
	var path := errors_path()
	if not FileAccess.file_exists(path):
		return "No errors or warnings this run.\n"
	return scrub(FileAccess.get_file_as_string(path))

## One line of what the game is doing now.
func _sample() -> void:
	_state.append(state_line(_game()))
	while _state.size() > STATE_SECS:
		_state.remove_at(0)

## The game scene: the main scene in play, or a test's Game.tscn under the root.
func _game() -> Node:
	var scene := get_tree().current_scene
	if scene != null and "player" in scene:
		return scene
	for n in get_tree().root.get_children():
		if "player" in n:
			return n
	return scene

## "20:41:07 +312 s  driving  car kei  92 km/h  gear 3  4120 rpm  at (12, 1, -456)  night 2, 192 min  act 1  58 fps"
static func state_line(game: Node) -> String:
	var parts := PackedStringArray()
	parts.append(Time.get_time_string_from_system())
	parts.append("+%d s" % (Time.get_ticks_msec() / 1000))
	var gs: Node = game.get("game_state") if game != null else null
	if gs != null and gs.get("state") != null:
		parts.append(str(GameState.State.find_key(int(gs.state))).to_lower())
	elif game != null:
		parts.append(str(game.name))
	var p: Node3D = game.get("player") if game != null else null
	if p != null and is_instance_valid(p):
		parts.append("car %s" % PlayerCar.chassis_kind())
		if p is RigidBody3D:
			parts.append("%d km/h" % roundi((p as RigidBody3D).linear_velocity.length() * 3.6))
		if p.get("gear") != null:
			parts.append("gear %d" % int(p.gear))
		if p.get("motor_rpm") != null:
			parts.append("%d rpm" % roundi(float(p.motor_rpm)))
		var o := p.global_position
		parts.append("at (%d, %d, %d)" % [roundi(o.x), roundi(o.y), roundi(o.z)])
	var clock: Node = game.get("night_clock") if game != null else null
	if clock != null:
		parts.append("night %d, %d min" % [int(clock.night), int(clock.minutes)])
	if game != null and game.get("road_act") != null:
		parts.append("act %d" % int(game.road_act))
	parts.append("%d fps" % roundi(Engine.get_frames_per_second()))
	return "  ".join(parts)

func _write_session(status: String) -> void:
	var f := FileAccess.open(session_path(), FileAccess.WRITE)
	if f == null:
		return   # no push_error: it would come back through the logger
	f.store_string("%s\n%s\nstarted: %s\nlast written: %s\n\n%s" % [status, GameInfo.title(), _started,
			Time.get_datetime_string_from_system(false, true), state_text()])
	f.close()

## At start: if the last run's session.txt never got closed, make its crash
## report folder. Moves the last run's errors.log aside either way, so this run
## starts a fresh one. Returns the folder made, "" when the last run closed.
static func check_last_run() -> String:
	return check_last_run_at(session_path(), errors_path(), TestMode.path(PREV_ERRORS), TestMode.path(REPORTS))

## check_last_run() with its files named (the test points it at scratch files).
static func check_last_run_at(session: String, errors: String, prev: String, root: String) -> String:
	if FileAccess.file_exists(errors):
		DirAccess.rename_absolute(errors, prev)
	if not FileAccess.file_exists(session):
		return ""
	var text := FileAccess.get_file_as_string(session)
	if not text.begins_with(RUNNING):
		return ""
	var log := previous_log()
	var log_text := FileAccess.get_file_as_string(log) if log != "" else ""
	var crashed := log_text.contains("Program crashed") or log_text.contains("CrashHandlerException")
	var stamp := Time.get_datetime_string_from_system().replace("T", "_").replace(":", "-")
	var dir := root.path_join(stamp + "_crash")
	var n := 1
	while DirAccess.dir_exists_absolute(dir):
		n += 1
		dir = root.path_join("%s_crash_%d" % [stamp, n])
	DirAccess.make_dir_recursive_absolute(dir)
	var info := "Crash report, made when the game started again at %s.\n" % Time.get_datetime_string_from_system(false, true)
	info += "How the last run ended: %s.\n" % (ENDED_CRASH if crashed else ENDED_STOPPED)
	info += "This start: %s\n\nThe last run (its session.txt):\n%s" % [GameInfo.title(), text.trim_prefix(RUNNING).strip_edges(true, false)]
	_write(dir.path_join("info.txt"), scrub(info))
	_write(dir.path_join("log.txt"), scrub(log_text) if log != "" else "No log from the last run (file logging is %s).\n" % ("on" if LogFolder.logging_enabled() else "off"))
	_write(dir.path_join("errors.txt"), scrub(FileAccess.get_file_as_string(prev)) if FileAccess.file_exists(prev) else "No errors or warnings were logged in the last run.\n")
	# A report it opened is closed now: the next start must not report it again.
	_write(session, CLOSED + "\n(reported in %s)\n" % dir.get_file())
	_prune(root)
	print("ErrorLog: the last run did not close; crash report in %s" % scrub(ProjectSettings.globalize_path(dir)))
	return dir

## The last run's godot log: the newest rotated godot<time>.log. Godot renames
## godot.log to that at start, before any script runs, so godot.log itself is
## always this run. "" when there is none (first run, or logging off).
static func previous_log() -> String:
	var dir := LogFolder.log_dir()
	if not DirAccess.dir_exists_absolute(dir):
		return ""
	var current := LogFolder.log_file().get_file()
	var base := current.get_basename()
	var best := ""
	for f in DirAccess.get_files_at(dir):
		if f != current and f.begins_with(base) and f.get_extension() == current.get_extension() and f > best:
			best = f
	return "" if best == "" else dir.path_join(best)

## Personal paths out of `text`: the home folder becomes ~, the user data folder
## user://, the project folder res://, and any other C:\Users\<name> or
## /home/<name> loses the name.
static func scrub(text: String) -> String:
	return ErrorLogger.scrub(text)

static func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()

## Keeps the newest KEEP_REPORTS folders, as F9 does.
static func _prune(root: String) -> void:
	var recorder: Script = load("res://scripts/core/drive_recorder.gd")
	recorder.prune(root, KEEP_REPORTS)


## Writes each error and warning to errors.log as it happens. Godot may call it
## from any thread, so everything goes through one lock, and nothing in here
## may print or push an error (that would come straight back in).
class ErrorLogger extends Logger:
	const TYPES := ["ERROR", "WARNING", "SCRIPT ERROR", "SHADER ERROR"]
	var state_source: Callable   # main-thread game state lines, for the first error
	var _file: FileAccess
	var _lock := Mutex.new()
	var _seen := {}   # "file:line code" -> times
	var _entries := 0
	var _errors := 0
	var _warnings := 0

	func _init(path: String, title: String, started: String) -> void:
		_file = FileAccess.open(path, FileAccess.WRITE)
		if _file != null:
			_file.store_string("%s, started %s\n\n" % [title, started])
			_file.flush()

	## ErrorLog.scrub() (here so the logger can use it too).
	static func scrub(text: String) -> String:
		var swaps := [
			[ProjectSettings.globalize_path("user://").trim_suffix("/"), "user:/"],
			[ProjectSettings.globalize_path("res://").trim_suffix("/"), "res:/"],
		]
		var home := OS.get_environment("USERPROFILE") if OS.has_feature("windows") else OS.get_environment("HOME")
		if home.length() > 3:
			swaps.append([home.replace("\\", "/"), "~"])
		for s in swaps:
			var from: String = s[0]
			if from.length() > 3:
				text = text.replace(from, s[1]).replace(from.replace("/", "\\"), s[1])
		var users := RegEx.create_from_string("(?i)([A-Z]:[\\\\/](?:Users|Documents and Settings)[\\\\/])[^\\\\/\\r\\n\"']+")
		text = users.sub(text, "$1<user>", true)
		var homes := RegEx.create_from_string("(/home/|/Users/)[^/\\r\\n\"']+")
		return homes.sub(text, "$1<user>", true)

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		_lock.lock()
		if error_type == ERROR_TYPE_WARNING:
			_warnings += 1
		else:
			_errors += 1
		# push_error() and friends report their C++ caller; the script line that
		# called them is the top of the GDScript call stack.
		var where := "%s:%d in %s()" % [file, line, function]
		if not script_backtraces.is_empty() and script_backtraces[0].get_frame_count() > 0:
			var top := script_backtraces[0]
			where = "%s:%d in %s()" % [top.get_frame_file(0), top.get_frame_line(0), top.get_frame_function(0)]
		var key := "%s %s" % [where, code]
		var times: int = _seen.get(key, 0) + 1
		_seen[key] = times
		if _file != null and times <= REPEAT_CAP and _entries < MAX_ENTRIES:
			_entries += 1
			var msg := code if rationale == "" else "%s (%s)" % [rationale, code]
			var text := "[+%.3f s] %s at %s: %s\n" % [Time.get_ticks_msec() / 1000.0,
					TYPES[clampi(error_type, 0, TYPES.size() - 1)], where, msg]
			if times == REPEAT_CAP:
				text += "  (repeats from here on are only counted)\n"
			for bt in script_backtraces:
				for i in mini(bt.get_frame_count(), MAX_FRAMES):
					text += "  %s %s:%d in %s()\n" % ["stack:" if i == 0 else "      ", bt.get_frame_file(i),
							bt.get_frame_line(i), bt.get_frame_function(i)]
			if _errors + _warnings == 1 and state_source.is_valid() and OS.get_thread_caller_id() == OS.get_main_thread_id():
				var state: String = state_source.call()
				if state != "":
					text += "  game state, the last seconds before this:\n"
					for s in state.strip_edges().split("\n"):
						text += "    %s\n" % s
			_file.store_string(scrub(text))
			_file.flush()   # on disk now, in case the next thing is a crash
		_lock.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	## Repeat counts and totals at the end of the file.
	func finish() -> void:
		_lock.lock()
		if _file != null:
			var text := "\nThis run: %d errors, %d warnings.\n" % [_errors, _warnings]
			for key in _seen:
				if int(_seen[key]) > REPEAT_CAP:
					text += "  %dx %s\n" % [_seen[key], key]
			_file.store_string(text)
			_file.close()
			_file = null
		_lock.unlock()
