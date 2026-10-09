class_name AutoTuneJob
extends RefCounted

# Runs an Auto-Tune search in a separate headless Godot process and reports
# back through files. Why a process: the search needs hundreds of seconds of
# simulated driving. The running game's physics cannot go faster than real time
# (Engine.time_scale lengthens each step instead, which breaks the car, and
# there is no manual stepping), and the game must not be disturbed. A headless
# process with --fixed-fps 60 runs the same sim at ~1 s per candidate and gives
# exactly the numbers tests/tuning/tune_track.gd measures.
#
# The game side (panel) calls start(), then poll() every so often; cancel()
# kills the worker. The worker side is scripts/auto_tune_worker.gd.
#
# Files, all in user://autotune/ and overwritten per job (never deleted):
#   request.json   {values: {path: float}, request: {goals, locks}, budget,
#                   trace: bool, stock: {path: float} (both optional, Test run)}
#   progress.json  {done, total, best}
#   result.json    {ok: true, ...AutoTuneSearch result with spec as values,
#                  stock_metrics when a stock spec was sent} or {ok: false, error}
# Specs travel as {path: value} over every TuneParams path (engine knobs
# included), applied on top of CarSpec.coupe_default() -- a spec is arrays and
# nested dictionaries, and JSON would lose Array[float].
#
# Needs a Godot executable it can start: $GODOT, else the running executable if
# it is Godot's own (editor / console build) or the exported game itself (an
# exported game carries the whole project in its .pck, so it can run the worker
# script with --headless; fixed 2026-10-05, it used to need a Godot install and
# failed silently in the exported exe), else the default of run_tests.bat.

const DIR := "user://autotune"
const TestMode := preload("res://scripts/core/test_mode.gd")

## DIR, or user://test_autotune when a test is running (scripts/core/test_mode.gd).
static func job_dir() -> String:
	return TestMode.path(DIR)
const REQUEST_FILE := "request.json"
const PROGRESS_FILE := "progress.json"
const RESULT_FILE := "result.json"
## An exported game ignores `-s <script>`, so its worker mode is a user argument
## the game itself reads: `game.exe --headless --fixed-fps 60 -- --autotune-worker <dir>`.
const WORKER_FLAG := "--autotune-worker"

enum State { IDLE, RUNNING, DONE, FAILED, CANCELLED }

var state := State.IDLE
var pid := -1
var error := ""
var progress := {"done": 0, "total": 0, "best": 0.0}
var result := {}
var exe := ""

# ---------- game side ----------

## Starts a search on `spec` (a full car spec). False, with `error` set, if no
## Godot executable can be found or the process will not start. `options` (the
## Tuner's Test run): trace = true keeps the brake run's telemetry trace in the
## metrics; stock = a full spec to run first, returned as stock_metrics.
func start(spec: Dictionary, request: Dictionary, budget: int, options := {}) -> bool:
	exe = find_godot()
	if exe == "":
		error = "Auto-Tune needs a Godot executable to run its search in. Set the GODOT environment variable to Godot_v4.7.2-stable_win64_console.exe."
		state = State.FAILED
		return false
	var dir := ProjectSettings.globalize_path(job_dir())
	DirAccess.make_dir_recursive_absolute(dir)
	# Truncate the previous job's files so a stale result can't be mistaken for this one.
	write_json(dir.path_join(RESULT_FILE), {})
	write_json(dir.path_join(PROGRESS_FILE), {})
	var req := {"values": values_from_spec(spec), "request": request, "budget": budget, "trace": options.get("trace", false)}
	if options.has("stock"):
		req.stock = values_from_spec(options.stock)
	write_json(dir.path_join(REQUEST_FILE), req)
	var args := PackedStringArray(["--headless", "--fixed-fps", str(Engine.physics_ticks_per_second)])
	if exe == OS.get_executable_path() and OS.has_feature("template"):
		# The exported game: it finds its own .pck and runs the worker as a mode
		# of the game itself (see Game._ready and run_worker).
		args.append_array(["--", WORKER_FLAG, dir])
	else:
		args.append_array(["--path", ProjectSettings.globalize_path("res://")])
		args.append_array(["-s", "res://scripts/tuning/auto_tune_worker.gd", "--", dir])
	pid = OS.create_process(exe, args)
	if pid <= 0:
		error = "Could not start %s" % exe
		state = State.FAILED
		return false
	state = State.RUNNING
	error = ""
	progress = {"done": 0, "total": budget, "best": 0.0}
	result = {}
	return true

## Updates and returns the state. Call it repeatedly while RUNNING.
func poll() -> State:
	if state != State.RUNNING:
		return state
	var dir := ProjectSettings.globalize_path(job_dir())
	var p := read_json(dir.path_join(PROGRESS_FILE))
	if not p.is_empty():
		progress = p
	if OS.is_process_running(pid):
		return state
	var r := read_json(dir.path_join(RESULT_FILE))
	if r.is_empty():
		error = "The search process ended without a result (see the Godot console)."
		state = State.FAILED
	elif not r.get("ok", false):
		error = str(r.get("error", "unknown error"))
		state = State.FAILED
	else:
		result = r
		state = State.DONE
	return state

func cancel() -> void:
	if state == State.RUNNING:
		OS.kill(pid)
		state = State.CANCELLED

## The Auto-Tune values of the result's spec as a spec dictionary: `base` with
## the result's values written in.
func result_spec(base: Dictionary) -> Dictionary:
	var spec := CarSpec.clone_spec(base)
	for path in result.values:
		TuneParams.set_value(spec, path, float(result.values[path]))
	return spec

static func find_godot() -> String:
	var candidates: Array[String] = []
	var env := OS.get_environment("GODOT")
	if env != "":
		candidates.append(env)
	var own := OS.get_executable_path()
	if own.get_file().to_lower().begins_with("godot") or OS.has_feature("template"):
		candidates.append(own)
	candidates.append(OS.get_environment("USERPROFILE").path_join("Documents/Godot_v4.7.2-stable_win64_console.exe"))
	for c in candidates:
		if FileAccess.file_exists(c):
			return c
	return ""

# ---------- worker side ----------

## The job directory if this process was started as an Auto-Tune worker in game
## mode (`-- --autotune-worker <dir>`), else "".
static func worker_dir_from_args() -> String:
	var args := OS.get_cmdline_user_args()
	var i := args.find(WORKER_FLAG)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else ""

## Runs the search on a TuneTrack inside `tree` and writes progress and result
## files into `dir`, then quits the tree. Used by auto_tune_worker.gd (dev) and by
## the game's own worker mode (exported build).
static func run_worker(tree: SceneTree, dir: String) -> void:
	var req := read_json(dir.path_join(REQUEST_FILE))
	if req.is_empty():
		write_json(dir.path_join(RESULT_FILE), {"ok": false, "error": "no readable request"})
		tree.quit(2)
		return
	await tree.process_frame
	var base := spec_from_values(req.values)
	var track := TuneTrack.new()
	track.record_trace = req.get("trace", false)
	tree.root.add_child(track)
	var stock_metrics := {}
	if req.has("stock"):  # first, in the same lanes, so the two runs compare like for like
		stock_metrics = (await track.evaluate([spec_from_values(req.stock)]))[0]
	var progress_path := dir.path_join(PROGRESS_FILE)
	var on_progress := func(done: int, total: int, best: float) -> void:
		write_json(progress_path, {"done": done, "total": total, "best": best})
	var r: Dictionary = await AutoTuneSearch.new().run(track, base, req.request, int(req.budget), on_progress)
	var out := result_to_json(r)
	if req.has("stock"):
		out.stock_metrics = stock_metrics
	write_json(dir.path_join(RESULT_FILE), out)
	tree.quit(0)

# ---------- shared by both sides ----------

## Every tunable value of a spec (raw and Auto-Tune paths) as {path: float}.
static func values_from_spec(spec: Dictionary) -> Dictionary:
	var out := {}
	for e in TuneParams.all():
		out[e.path] = TuneParams.get_value(spec, e.path)
	return out

## The default coupe with `values` written over it.
static func spec_from_values(values: Dictionary) -> Dictionary:
	var spec := CarSpec.coupe_default()
	for path in values:
		TuneParams.set_value(spec, path, float(values[path]))
	return spec

## A search result in JSON-safe form: the result spec becomes {path: value} for
## the Auto-Tune paths, each verified candidate likewise.
static func result_to_json(r: Dictionary) -> Dictionary:
	var verified := []
	for v in r.verified:
		verified.append({
			"values": _auto_values(v.spec), "search_score": v.search_score, "full_score": v.full_score,
			"metrics": v.metrics, "accepted": v.accepted, "why": v.why,
		})
	return {
		"ok": true, "improved": r.improved, "values": _auto_values(r.spec), "base_metrics": r.base_metrics,
		"metrics": r.metrics, "score": r.score, "evals": r.evals, "notes": r.notes, "verified": verified,
	}

static func _auto_values(spec: Dictionary) -> Dictionary:
	var out := {}
	for path in TuneParams.auto_paths():
		out[path] = TuneParams.get_value(spec, path)
	return out

static func write_json(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("AutoTuneJob: cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return
	f.store_string(JSON.stringify(data))

## {} if the file is missing, empty or half-written.
static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
