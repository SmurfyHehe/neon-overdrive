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
	var dir := args[0]
	var req := AutoTuneJob.read_json(dir.path_join(AutoTuneJob.REQUEST_FILE))
	if req.is_empty():
		AutoTuneJob.write_json(dir.path_join(AutoTuneJob.RESULT_FILE), {"ok": false, "error": "no readable request"})
		quit(2)
		return
	await process_frame
	var base := AutoTuneJob.spec_from_values(req.values)
	var track := TuneTrack.new()
	root.add_child(track)
	var progress_path := dir.path_join(AutoTuneJob.PROGRESS_FILE)
	var on_progress := func(done: int, total: int, best: float) -> void:
		AutoTuneJob.write_json(progress_path, {"done": done, "total": total, "best": best})
	var r: Dictionary = await AutoTuneSearch.new().run(track, base, req.request, int(req.budget), on_progress)
	AutoTuneJob.write_json(dir.path_join(AutoTuneJob.RESULT_FILE), AutoTuneJob.result_to_json(r))
	quit(0)
