extends Node

# Record my drive (2026-10-10, Roy: a bug he hits while playing should be
# replayable). Always on in the game: it keeps the last KEEP_SECS of driving
# keys (one number per physics tick, PlayerCar.last_keys) and, every SNAP_SECS,
# where the car and the road were (SaveDirector.capture(), the same data a
# saved run resumes from).
#
# F9 saves one bug-report folder (K3, 2026-10-11), user://bug_reports/<date>_<time>/:
#   drive.json   the recording
#   screen.png   the game view as it was on the press
#   log.txt      a copy of Godot's log so far (user://logs/godot.log)
#   errors.txt   this run's errors and warnings (error_log.gd), with call stacks
#   info.txt     game version, git branch and commit (a run from the project
#                folder only; an exported build has no .git), car, night and
#                act, graphics preset, the [keys] section of settings.cfg, and
#                the last seconds of game state (error_log.gd)
# Text files have the player's home and user folders scrubbed out
# (ErrorLog.scrub), so no account name is in a report.
# Nothing is drawn on screen (HUD rule): a short camera click says it saved.
# The newest KEEP_REPORTS folders stay; older ones go to the recycle bin.
#
# Play one back with  -- --replay=<drive.json or its folder>  (or
# --replay=last): the game boots on the recording's road with the car where it
# was at the start of the kept stretch, and the shared test driver
# (scripts/core/test_driver.gd, mode "replay") presses the same keys on the
# same ticks. "last" is the newest bug report, or the newest old-style
# user://drives/drive_<time>.json when there is no report yet.
#
# A replay only repeats the driving keys (W S A D, the gear keys, X). It does
# NOT repeat lights, horn or blinkers, and does not restore the traffic (cars
# are respawned, so a hit on a traffic car will not repeat), damage, fuel and
# tyre state, or anything a bot driving through pedals did (last_keys is -1
# then; such ticks replay as no keys). It needs the same physics rate and car
# as the recording; both are in the file and set on replay.
#
# Cost: one array write per physics tick, one capture() every SNAP_SECS. On F9
# the picture is read back on the main thread and written by a worker thread.
# No class_name on purpose: preload it.

const TestMode := preload("res://scripts/core/test_mode.gd")
const SaveDirector := preload("res://scripts/save/save_director.gd")
const GameInfo := preload("res://scripts/core/game_info.gd")
const LogFolder := preload("res://scripts/core/log_folder.gd")
const ErrorLog := preload("res://scripts/core/error_log.gd")
const ACTION := "record_drive"
const KEEP_SECS := 60.0
const SNAP_SECS := 5.0
const DIR := "user://bug_reports"
const OLD_DIR := "user://drives"   # where F9 wrote single files before K3
const DRIVE_FILE := "drive.json"
const KEEP_REPORTS := 20
const CLICK_DB := -8.0
const VERSION := 1

var game: Node
var last_file := ""   # the drive.json the last F9 wrote (tests read it)
var last_dir := ""    # its bug-report folder
var _keys := PackedInt32Array()
var _snaps: Array = []   # [{tick, run, steer}], oldest first
var _tick := 0
var _first := 0   # tick number of _keys[0]
var _png_task := -1
var _click: AudioStreamPlayer

func _init(owner_game: Node) -> void:
	game = owner_game
	name = "DriveRecorder"

func _ready() -> void:
	if not InputMap.has_action(ACTION):
		InputMap.add_action(ACTION)
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_F9
		InputMap.action_add_event(ACTION, ev)

func _exit_tree() -> void:
	flush()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION) and not event.is_echo():
		if save() != "":
			_play_click()

func _physics_process(_delta: float) -> void:
	var p: PlayerCar = game.player
	if p == null or not p.is_ready:
		return
	var rate := Engine.physics_ticks_per_second
	if _tick % int(SNAP_SECS * rate) == 0:
		_snaps.append({"tick": _tick, "run": game.saver.capture(), "steer": p._steer_smooth})
	_keys.append(maxi(p.last_keys, 0))
	_tick += 1
	# Drop whole snapshot periods once more than KEEP_SECS is held.
	if _snaps.size() > 1 and _tick - int(_snaps[1].tick) >= int(KEEP_SECS * rate):
		_snaps.pop_front()
		var cut := int(_snaps[0].tick) - _first
		_keys = _keys.slice(cut)
		_first += cut

## Writes the bug-report folder; returns its drive.json's path, "" on failure.
func save() -> String:
	if _snaps.is_empty():
		push_warning("DriveRecorder: nothing recorded yet")
		return ""
	var snap: Dictionary = _snaps[0]
	var data := {
		"version": VERSION,
		"saved": Time.get_datetime_string_from_system(false, true),
		"ticks_per_second": Engine.physics_ticks_per_second,
		"car": PlayerCar.chassis_kind(),
		"traffic": TrafficSettings.car_count,
		"run": snap.run,
		"steer": snap.steer,
		"keys": Array(_keys.slice(int(snap.tick) - _first)),
	}
	var root := TestMode.path(DIR)
	var stamp := Time.get_datetime_string_from_system().replace("T", "_").replace(":", "-")
	var dir := root.path_join(stamp)
	var n := 1
	while DirAccess.dir_exists_absolute(dir):   # a second press in the same second
		n += 1
		dir = root.path_join("%s_%d" % [stamp, n])
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join(DRIVE_FILE)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("DriveRecorder: could not write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return ""
	f.store_string(JSON.stringify(data))
	f.close()
	last_file = path
	last_dir = dir
	print("DriveRecorder: %.1f s saved to %s" % [float(data.keys.size()) / Engine.physics_ticks_per_second, ErrorLog.scrub(ProjectSettings.globalize_path(dir))])
	_write_screen(dir.path_join("screen.png"))
	_write_text(dir.path_join("info.txt"), ErrorLog.scrub(info_text()))
	_write_text(dir.path_join("log.txt"), ErrorLog.scrub(_log_text()))
	_write_text(dir.path_join("errors.txt"), ErrorLog.errors_text())
	prune(root, KEEP_REPORTS)
	return path

## Reads a recording; {} when it is missing or not one. `path` is a drive
## file, a bug-report folder, or "last" = the newest recording.
static func load_file(path: String) -> Dictionary:
	if path == "last":
		path = newest()
	elif DirAccess.dir_exists_absolute(path):
		path = path.path_join(DRIVE_FILE)
	if path == "" or not FileAccess.file_exists(path):
		push_error("DriveRecorder: no recording at '%s'" % path)
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or int(data.get("version", 0)) != VERSION or not data.get("keys") is Array \
			or not data.get("run") is Dictionary or not SaveDirector.valid_run(data.run):
		push_error("DriveRecorder: '%s' is not a drive recording" % path)
		return {}
	return data

## The newest bug report's drive.json; with no report, the newest old-style
## file in user://drives. "" when there is neither.
static func newest() -> String:
	var test_mode: Script = load("res://scripts/core/test_mode.gd")
	var root: String = test_mode.path(DIR)
	var dirs := reports(root)
	for i in range(dirs.size() - 1, -1, -1):
		var file := root.path_join(dirs[i]).path_join(DRIVE_FILE)
		if FileAccess.file_exists(file):
			return file
	var old: String = test_mode.path(OLD_DIR)
	var best := ""
	if not DirAccess.dir_exists_absolute(old):
		return ""
	for f in DirAccess.get_files_at(old):
		if f.begins_with("drive_") and f.ends_with(".json") and f > best:
			best = f
	return "" if best == "" else old.path_join(best)

## The bug-report folders in `root`, oldest first (their names sort by time).
static func reports(root: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not DirAccess.dir_exists_absolute(root):
		return out
	for d in DirAccess.get_directories_at(root):
		if d.length() >= 19 and d[4] == "-" and d[10] == "_" and d.left(4).is_valid_int():
			out.append(d)
	out.sort()
	return out

## Keeps the newest `keep` bug-report folders in `root`. Older ones go to the
## recycle bin (Roy: nothing of his is deleted for good); where there is no
## bin, they are removed. Folders F9 did not name are left alone.
static func prune(root: String, keep: int) -> void:
	var dirs := reports(root)
	for i in dirs.size() - keep:
		var dir := root.path_join(dirs[i])
		if OS.move_to_trash(ProjectSettings.globalize_path(dir)) == OK:
			continue
		for f in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(f))
		if DirAccess.remove_absolute(dir) != OK:
			push_warning("DriveRecorder: could not remove the old bug report %s" % dir)

## Waits for the picture of the last report to be on disk (tests, and on quit).
func flush() -> void:
	if _png_task != -1:
		WorkerThreadPool.wait_for_task_completion(_png_task)
		_png_task = -1

## What info.txt holds.
func info_text() -> String:
	var lines := PackedStringArray()
	lines.append("%s, saved %s" % [GameInfo.title(), Time.get_datetime_string_from_system(false, true)])
	var git := git_head(ProjectSettings.globalize_path("res://"))
	lines.append("git: %s" % ("not in this build" if git.is_empty() else "branch %s, commit %s" % [git.branch, git.commit]))
	lines.append("godot: %s, %s, %s" % [Engine.get_version_info().string, OS.get_name(), RenderingServer.get_video_adapter_name()])
	var kind := PlayerCar.chassis_kind()
	lines.append("car: %s (%s)" % [PlayerCars.title(kind), kind])
	var clock: NightClock = game.get("night_clock")
	if clock != null:
		lines.append("night: %d, %d minutes in" % [clock.night, int(clock.minutes)])
	lines.append("act: %d" % int(game.get("road_act")))
	lines.append("graphics preset: %s" % GraphicsSettings.preset)
	lines.append("traffic cars: %d, physics ticks per second: %d" % [TrafficSettings.car_count, Engine.physics_ticks_per_second])
	lines.append("")
	lines.append("[keys]  (from %s)" % ProjectSettings.globalize_path(AudioSettings.path))
	var cfg := ConfigFile.new()
	if cfg.load(AudioSettings.path) == OK and cfg.has_section("keys"):
		for k in cfg.get_section_keys("keys"):
			lines.append("%s=%s" % [k, var_to_str(cfg.get_value("keys", k))])
	else:
		lines.append("no keys are rebound (all defaults)")
	var log: Node = ErrorLog.instance()
	if log != null:
		lines.append("")
		lines.append("[game state, the last seconds before F9]")
		lines.append(log.state_text().strip_edges())
	return "\n".join(lines) + "\n"

## {branch, commit} of the checkout at `project_dir`, read from its .git (a
## folder, or in a worktree a file that points at one); {} when there is none.
static func git_head(project_dir: String) -> Dictionary:
	var git := project_dir.path_join(".git")
	if FileAccess.file_exists(git):
		var link := FileAccess.get_file_as_string(git).strip_edges()
		if not link.begins_with("gitdir:"):
			return {}
		git = link.trim_prefix("gitdir:").strip_edges()
		if git.is_relative_path():
			git = project_dir.path_join(git)
	if not FileAccess.file_exists(git.path_join("HEAD")):
		return {}
	var head := FileAccess.get_file_as_string(git.path_join("HEAD")).strip_edges()
	if not head.begins_with("ref:"):
		return {"branch": "(detached)", "commit": head.left(10)}
	var ref := head.trim_prefix("ref:").strip_edges()
	# A worktree keeps its branches in the main .git folder.
	if FileAccess.file_exists(git.path_join("commondir")):
		var common := FileAccess.get_file_as_string(git.path_join("commondir")).strip_edges()
		git = git.path_join(common).simplify_path() if common.is_relative_path() else common
	var commit := ""
	if FileAccess.file_exists(git.path_join(ref)):
		commit = FileAccess.get_file_as_string(git.path_join(ref)).strip_edges()
	elif FileAccess.file_exists(git.path_join("packed-refs")):
		for line in FileAccess.get_file_as_string(git.path_join("packed-refs")).split("\n"):
			if line.strip_edges().ends_with(" " + ref):
				commit = line.get_slice(" ", 0)
	return {"branch": ref.trim_prefix("refs/heads/"), "commit": commit.left(10) if commit != "" else "unknown"}

## The game view as drawn last frame. The read-back is on this thread, the PNG
## packing (the slow part) on a worker. Headless has no picture: a blank one is
## written, so a report always has the same four files.
func _write_screen(path: String) -> void:
	flush()
	var img: Image = null
	if DisplayServer.get_name() != "headless":
		img = get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		img = Image.create_empty(16, 9, false, Image.FORMAT_RGB8)
	_png_task = WorkerThreadPool.add_task(func() -> void:
		if img.save_png(path) != OK:
			push_warning("DriveRecorder: could not write %s" % path))

## Godot's log so far. The engine still has the file open; reading it is fine.
func _log_text() -> String:
	var path := LogFolder.log_file()
	if not LogFolder.logging_enabled() or not FileAccess.file_exists(path):
		return "No log file at %s (file logging is %s).\n" % [path, "on" if LogFolder.logging_enabled() else "off"]
	return FileAccess.get_file_as_string(path)

static func _write_text(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("DriveRecorder: could not write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return
	f.store_string(text)
	f.close()

func _play_click() -> void:
	if _click == null:
		_click = AudioStreamPlayer.new()
		_click.bus = &"UI"
		_click.volume_db = CLICK_DB
		_click.stream = MenuSfx._wav(click_samples())
		add_child(_click)
	_click.play()

## A camera shutter, synthesised (there is no photo-mode shutter sound to
## share): two short noise ticks 55 ms apart, the second lower and softer.
static func click_samples() -> PackedFloat32Array:
	var rate := MenuSfx.MIX_RATE
	var out := PackedFloat32Array()
	out.resize(int(0.11 * rate))
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for tick in [[0.0, 3200.0, 0.9], [0.055, 1900.0, 0.6]]:
		var start := int(float(tick[0]) * rate)
		var low := 0.0
		for i in int(0.03 * rate):
			var t := float(i) / rate
			# Noise through a one-pole low-pass, plus a little tone: a click, not a hiss.
			low = lerpf(low, rng.randf_range(-1.0, 1.0), 0.45)
			out[start + i] += float(tick[2]) * exp(-t / 0.006) * (0.7 * low + 0.3 * sin(TAU * float(tick[1]) * t))
	return out
