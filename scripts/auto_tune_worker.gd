extends SceneTree

# Auto-Tune worker: the other end of AutoTuneJob. Runs as its own headless
# Godot process (--headless --fixed-fps 60), reads a request file, runs
# AutoTuneSearch on a TuneTrack and writes progress and result files. Not part
# of the game; the game starts it. Arguments after "--": the job directory.
#
#   Godot --headless --fixed-fps 60 --path <project> -s res://scripts/auto_tune_worker.gd -- <dir>

func _initialize() -> void:
	_run()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("auto_tune_worker: no job directory given")
		quit(2)
		return
	AutoTuneJob.run_worker(self, args[0])
