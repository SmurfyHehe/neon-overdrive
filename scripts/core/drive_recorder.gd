extends Node

# Record my drive (2026-10-10, Roy: a bug he hits while playing should be
# replayable). Always on in the game: it keeps the last KEEP_SECS of driving
# keys (one number per physics tick, PlayerCar.last_keys) and, every SNAP_SECS,
# where the car and the road were (SaveDirector.capture(), the same data a
# saved run resumes from). F9 writes that to user://drives/drive_<time>.json.
#
# Play one back with  -- --replay=<file>  (or --replay=last): the game boots on
# the recording's road with the car where it was at the start of the kept
# stretch, and the shared test driver (scripts/core/test_driver.gd, mode
# "replay") presses the same keys on the same ticks.
#
# What a replay does NOT restore: the traffic (cars are respawned, so a hit on
# a traffic car will not repeat), damage, fuel and tyre state, and anything a
# bot driving through pedals did (last_keys is -1 then; such ticks replay as
# no keys). It needs the same physics rate and car as the recording; both are
# in the file and set on replay.
#
# Cost: one array write per physics tick, one capture() every SNAP_SECS.
# No class_name on purpose: preload it.

const TestMode := preload("res://scripts/core/test_mode.gd")
const SaveDirector := preload("res://scripts/save/save_director.gd")
const ACTION := "record_drive"
const KEEP_SECS := 60.0
const SNAP_SECS := 5.0
const DIR := "user://drives"
const VERSION := 1

var game: Node
var last_file := ""   # the file the last F9 wrote (tests read it)
var _keys := PackedInt32Array()
var _snaps: Array = []   # [{tick, run, steer}], oldest first
var _tick := 0
var _first := 0   # tick number of _keys[0]
var _label: Label
var _label_left := 0.0

func _init(owner_game: Node) -> void:
	game = owner_game
	name = "DriveRecorder"

func _ready() -> void:
	if not InputMap.has_action(ACTION):
		InputMap.add_action(ACTION)
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_F9
		InputMap.action_add_event(ACTION, ev)
	set_process(false)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION) and not event.is_echo():
		var path := save()
		_toast("Drive saved: " + path.get_file() if path != "" else "Drive NOT saved (see the log)")

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

## Writes the kept stretch; returns the file's path, "" on failure.
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
	var dir := TestMode.path(DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("drive_%s.json" % Time.get_datetime_string_from_system().replace(":", "-"))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("DriveRecorder: could not write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return ""
	f.store_string(JSON.stringify(data))
	f.close()
	last_file = path
	print("DriveRecorder: %.1f s saved to %s" % [float(data.keys.size()) / Engine.physics_ticks_per_second, ProjectSettings.globalize_path(path)])
	return path

## Reads a recording; {} when it is missing or not one. "last" = the newest
## file in the drives folder.
static func load_file(path: String) -> Dictionary:
	if path == "last":
		path = newest()
	if path == "" or not FileAccess.file_exists(path):
		push_error("DriveRecorder: no recording at '%s'" % path)
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or int(data.get("version", 0)) != VERSION or not data.get("keys") is Array \
			or not data.get("run") is Dictionary or not SaveDirector.valid_run(data.run):
		push_error("DriveRecorder: '%s' is not a drive recording" % path)
		return {}
	return data

static func newest() -> String:
	var dir: String = load("res://scripts/core/test_mode.gd").path(DIR)
	var best := ""
	for f in DirAccess.get_files_at(dir):
		if f.begins_with("drive_") and f.ends_with(".json") and f > best:
			best = f
	return "" if best == "" else dir.path_join(best)

func _toast(text: String) -> void:
	if _label == null:
		var layer := CanvasLayer.new()
		add_child(layer)
		_label = Label.new()
		_label.position = Vector2(16, 84)
		_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.4))  # amber #FFC066
		layer.add_child(_label)
	_label.text = text
	_label.visible = true
	_label_left = 3.0
	set_process(true)

func _process(delta: float) -> void:
	_label_left -= delta
	if _label_left <= 0.0:
		_label.visible = false
		set_process(false)
