extends SceneTree

# Auto-Tune in an exported game (2026-10-05): the game can run the search itself
# as a headless worker (`-- --autotune-worker <dir>`), because an exported exe
# ignores `-s <script>`. This starts that mode as a child of this process with a
# tiny request and checks it writes an ok result. Silent, no window.
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/auto_tune_worker_mode.gd

const TIMEOUT_SECS := 240.0

var pid := -1
var waited := 0.0
var dir := ""

func _initialize() -> void:
	dir = ProjectSettings.globalize_path("user://autotune_worker_mode_test")
	DirAccess.make_dir_recursive_absolute(dir)
	AutoTuneJob.write_json(dir.path_join(AutoTuneJob.RESULT_FILE), {})
	AutoTuneJob.write_json(dir.path_join(AutoTuneJob.PROGRESS_FILE), {})
	AutoTuneJob.write_json(dir.path_join(AutoTuneJob.REQUEST_FILE), {"values": {}, "request": {"goals": {"accel": 1}, "locks": {}}, "budget": 3})
	var args := PackedStringArray([
		"--headless", "--audio-driver", "Dummy", "--fixed-fps", "60",
		"--path", ProjectSettings.globalize_path("res://"),
		"--", AutoTuneJob.WORKER_FLAG, dir,
	])
	pid = OS.create_process(OS.get_executable_path(), args)
	if pid <= 0:
		_end("could not start the worker")

func _process(delta: float) -> bool:
	waited += delta
	if pid <= 0:
		return false
	if OS.is_process_running(pid):
		if waited > TIMEOUT_SECS:
			OS.kill(pid)
			_end("worker still running after %.0f s" % TIMEOUT_SECS)
		return false
	var r := AutoTuneJob.read_json(dir.path_join(AutoTuneJob.RESULT_FILE))
	if r.is_empty():
		_end("worker ended without a result")
	elif not r.get("ok", false):
		_end("worker reported an error: %s" % str(r.get("error", "")))
	else:
		print("worker mode: %d runs, improved=%s" % [int(r.evals), str(r.improved)])
		_end("")
	return true

func _end(msg: String) -> void:
	if msg != "":
		printerr("FAIL: ", msg)
	print("auto_tune_worker_mode: ", "PASS" if msg == "" else "FAIL")
	quit(0 if msg == "" else 1)
