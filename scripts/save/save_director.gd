extends Node

# When the game saves, and what a run save holds (run structure, 2026-10-09).
# Game adds one of these; SaveStore does the writing.
#
# Auto-save only. It writes the run:
#   - every AUTOSAVE_SECS of driving,
#   - when the game is paused or a Tuner/photo screen opens,
#   - when the night rolls over,
#   - on quit (pause menu Quit or the window's close button).
# Never during a chase (SaveStore.chase_active). Restart starts a fresh run:
# the run file is emptied, money and parts stay; a restart mid-chase leaves the
# chase open, so it counts as a bust like a quit.
#
# A run save is enough to put the car back exactly: the road (seed, shape,
# floating-origin index, the barrier roll of the chunks around the car), the
# car's transform, velocity, spin, gear and rpm, the night clock and the radio.
# Traffic is not saved; it respawns around the car as on a fresh start.
#
# Off in test mode unless a test sets `enabled` (like PlayerTune), so tests that
# boot Game.tscn never resume each other's runs.
# No class_name on purpose: preload it, so no class cache refresh is needed.

const SaveStore := preload("res://scripts/save/save_store.gd")
const TestMode := preload("res://scripts/core/test_mode.gd")

const RUN_VERSION := 1
const AUTOSAVE_SECS := 30.0

static var enabled := not TestMode.active()

## Fired once on load when the last session ended with a chase open (quit,
## crash or restart mid-chase). The run was not resumed.
signal busted_on_return

var game: Node
## The run read at boot ({} for a fresh run), and whether it was a bust.
var resumed := {}
var busted := false
var saves := 0  # how many run saves this session wrote (tests read it)
var _left := AUTOSAVE_SECS

func _init(owner_game: Node) -> void:
	game = owner_game
	name = "SaveDirector"
	process_mode = Node.PROCESS_MODE_ALWAYS  # quit and pause saves come while paused

## Called by Game before it builds the world: reads the slot and returns the
## run to resume, or {} for a fresh start.
func read_run() -> Dictionary:
	if not enabled:
		return {}
	var meta := SaveStore.load_meta()
	busted = meta.busted
	if busted:
		SaveStore.clear_run()
		return {}
	var run := SaveStore.load_run()
	resumed = run if valid_run(run) else {}
	return resumed

func _ready() -> void:
	if busted:
		busted_on_return.emit.call_deferred()

## True when `run` has everything restore needs, all finite.
static func valid_run(run: Dictionary) -> bool:
	if int(run.get("version", 0)) != RUN_VERSION:
		return false
	for k in ["road", "car", "origin_index"]:
		if not run.has(k):
			return false
	var car: Variant = run.car
	if not car is Dictionary or not _floats(car.get("xform"), 12) or not _floats(car.get("lin_vel"), 3) or not _floats(car.get("ang_vel"), 3):
		return false
	return run.road is Dictionary and _floats([run.road.get("curviness"), run.road.get("hilliness"), run.road.get("kicker_chance"), run.road.get("seed"), run.origin_index], 5)

static func _floats(a: Variant, n: int) -> bool:
	if not a is Array or a.size() != n:
		return false
	for v in a:
		if not (v is float or v is int) or not is_finite(float(v)):
			return false
	return true

# ---------- capture / restore ----------

static func xform_to_array(t: Transform3D) -> Array:
	return [t.basis.x.x, t.basis.x.y, t.basis.x.z, t.basis.y.x, t.basis.y.y, t.basis.y.z,
		t.basis.z.x, t.basis.z.y, t.basis.z.z, t.origin.x, t.origin.y, t.origin.z]

static func array_to_xform(a: Array) -> Transform3D:
	return Transform3D(Basis(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8])),
		Vector3(a[9], a[10], a[11]))

static func v3(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])

## The run as it is now.
func capture() -> Dictionary:
	var p: Node3D = game.player
	var sections := {}
	for c in game.chunk_pool:
		for i in [c.index - 1, c.index]:
			if game.section_cache.has(str(i)):
				sections[str(i)] = game.section_cache[str(i)]
	var run := {
		"version": RUN_VERSION,
		"road": {"seed": game.road_seed, "curviness": game.curviness, "hilliness": game.hilliness,
			"kicker_chance": game.kicker_chance},
		"origin_index": game.origin_index,
		"recenter_count": game.recenter_count,
		"sections": sections,
		"car": {"xform": xform_to_array(p.global_transform),
			"lin_vel": [p.linear_velocity.x, p.linear_velocity.y, p.linear_velocity.z],
			"ang_vel": [p.angular_velocity.x, p.angular_velocity.y, p.angular_velocity.z],
			"gear": p.current_gear, "rpm": p.motor_rpm},
	}
	if game.night_clock != null:
		run.clock = {"minutes": game.night_clock.minutes, "night": game.night_clock.night}
	if game.radio != null:
		run.radio = game.radio.station
	return run

## Puts the car's motion back once it is in the tree (Vehicle._ready has run).
func restore_car(p: Node3D, car: Dictionary) -> void:
	p.global_transform = array_to_xform(car.xform)
	p.linear_velocity = v3(car.lin_vel)
	p.angular_velocity = v3(car.ang_vel)
	if car.get("gear") is float or car.get("gear") is int:
		p.current_gear = int(car.gear)
	if car.get("rpm") is float or car.get("rpm") is int:
		p.motor_rpm = float(car.rpm)
	# GEVP reads speed off the last step's positions (see Game._shift_origin).
	p.previous_global_position = p.global_position
	for w in p.wheel_array:
		w.previous_global_position = w.global_position
	p.reset_physics_interpolation()

# ---------- when to save ----------

## Writes the run now unless saving is off or a chase is on. True if written.
func save_now() -> bool:
	if not enabled or SaveStore.chase_active or game.player == null:
		return false
	_left = AUTOSAVE_SECS
	if SaveStore.save_run(capture()):
		saves += 1
		return true
	return false

func _process(delta: float) -> void:
	if get_tree().paused:
		return
	_left -= delta
	if _left <= 0.0:
		save_now()

func on_state_changed(new_state: int, old_state: int) -> void:
	if old_state == GameState.State.PLAYING and new_state != GameState.State.PLAYING:
		save_now()

## Restart: a fresh run. Mid-chase the chase stays open (a bust next load).
func on_restart() -> void:
	if enabled and not SaveStore.chase_active:
		SaveStore.clear_run()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_now()
