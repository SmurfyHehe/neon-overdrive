class_name AutoTuneJob
extends RefCounted

# Runs an Auto-Tune search in a separate headless Godot process and reports
# back through files. Why a process: the search needs hundreds of seconds of
# simulated driving. The running game's physics cannot go faster than real time
# (Engine.time_scale lengthens each step instead, which breaks the car, and
# there is no manual stepping), and the game must not be disturbed. A headless
# process with --fixed-fps 60 runs the same sim at ~1 s per candidate and gives
# exactly the numbers tests/tune_track.gd measures.
#
# The game side (panel) calls start(), then poll() every so often; cancel()
# kills the worker. The worker side is scripts/auto_tune_worker.gd.
#
# Files, all in user://autotune/ and overwritten per job (never deleted):
#   request.json   {values: {path: float}, request: {goals, locks}, budget}
#   progress.json  {done, total, best}
#   result.json    {ok: true, ...AutoTuneSearch result with spec as values} or
#                  {ok: false, error}
# Specs travel as {path: value} over every TuneParams path (engine knobs
# included), applied on top of CarSpec.coupe_default() -- a spec is arrays and
# nested dictionaries, and JSON would lose Array[float].
#
# Needs a Godot executable it can start: $GODOT, else the running executable if
# it is Godot's own (editor / console build), else the default of run_tests.bat.
# An exported game has none of these, so Auto-Tune is a dev-build feature.

const DIR := "user://autotune"
const REQUEST_FILE := "request.json"
const PROGRESS_FILE := "progress.json"
const RESULT_FILE := "result.json"

enum State { IDLE, RUNNING, DONE, FAILED, CANCELLED }

var state := State.IDLE
var pid := -1
var error := ""
var progress := {"done": 0, "total": 0, "best": 0.0}
var result := {}
var exe := ""

# ---------- game side ----------

## Starts a search on `spec` (a full car spec). False, with `error` set, if no
## Godot executable can be found or the process will not start.
func start(spec: Dictionary, request: Dictionary, budget: int) -> bool:
	exe = find_godot()
	if exe == "":
		error = "Auto-Tune needs a Godot executable to run its search in. Set the GODOT environment variable to Godot_v4.7.2-stable_win64_console.exe."
		state = State.FAILED
		return false
	var dir := ProjectSettings.globalize_path(DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	# Truncate the previous job's files so a stale result can't be mistaken for this one.
	write_json(dir.path_join(RESULT_FILE), {})
	write_json(dir.path_join(PROGRESS_FILE), {})
	write_json(dir.path_join(REQUEST_FILE), {"values": values_from_spec(spec), "request": request, "budget": budget})
	var args := PackedStringArray([
		"--headless", "--fixed-fps", "60",
		"--path", ProjectSettings.globalize_path("res://"),
		"-s", "res://scripts/auto_tune_worker.gd",
		"--", dir,
	])
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
	var dir := ProjectSettings.globalize_path(DIR)
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
	if own.get_file().to_lower().begins_with("godot"):
		candidates.append(own)
	candidates.append(OS.get_environment("USERPROFILE").path_join("Documents/Godot_v4.7.2-stable_win64_console.exe"))
	for c in candidates:
		if FileAccess.file_exists(c):
			return c
	return ""

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
