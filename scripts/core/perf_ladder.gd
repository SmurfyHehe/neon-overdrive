class_name PerfLadder
extends Node

# What the game does when the PC falls behind (Roy, 2026-10-10: "save more on
# CPU"). It used to pause itself after a second under 30 fps. Now it climbs a
# ladder, one rung at a time, and climbs back down when there is room:
#
#   1 PICTURE  the 3D picture at its lowest dynamic-resolution scale, no wet
#              road mirrors, coarser mesh LOD
#   2 TRAFFIC  full crash physics for fewer cars (a shorter physics band)
#   3 RIVALS   a race rival far away rides the rails like traffic
#   then       a burst of slow motion (SLOWMO_SECS): fewer physics steps per
#              frame, so time runs slower instead of frames getting longer
#
# The player's car is never touched: it steps at the full tick rate on every
# rung, and slow motion only means fewer of those steps per real second.
# (Engine.time_scale is no use here: it shortens each step and runs as many.)
# A real freeze still pauses the game (GameState, STALL_SECS).
#
# Nothing here writes a saved setting: every rung is a hold on top of the
# player's own values and lets go on the way down.
#
# feed() is the decision on plain frame times, so tests drive it with numbers;
# _process() gives it the wall clock (the engine's own delta stops growing
# once the physics step cap is reached).

const TestMode := preload("res://scripts/core/test_mode.gd")
const RoadWet := preload("res://scripts/world/road_wet.gd")

enum { NONE, PICTURE, TRAFFIC, RIVALS }
const TOP := RIVALS

## A frame slower than this many fps counts as behind; faster than FAST_FPS
## counts as room to spare.
const SLOW_FPS := 33.0
const FAST_FPS := 45.0
## Behind for this long: one rung up. Slow frames add up, fast ones pay it
## back at half rate, so a stutter every other frame still counts.
const UP_SECS := 0.6
## Room to spare for this long: one rung down. Doubles (to DOWN_SECS_MAX) each
## time a step down is followed by a step up within BOUNCE_SECS, so a PC that
## only keeps up on a rung stays on it instead of see-sawing.
const DOWN_SECS := 8.0
const DOWN_SECS_MAX := 120.0
const BOUNCE_SECS := 20.0
## Frames right after a change (and after a start or resume) are not judged.
const SETTLE_SECS := 1.0
const WARMUP_SECS := 3.0
const SLOWMO_SECS := 2.0
const SLOWMO_REST := 8.0
const SLOWMO_STEPS := 3
## The shorter physics band on TRAFFIC and above (m).
const TRAFFIC_BAND := 40.0
const LOD_THRESHOLD := 4.0

var rung := NONE
var slowmo := false
## Rungs climbed and slow-motion bursts so far (tests, the benchmark line).
var climbs := 0
var slowmo_count := 0

var game_state: GameState
var traffic: TrafficManager
var dynres: DynamicResolution
## False: _process does nothing (tests and tools drive feed() themselves).
var live := true

var _age := 0.0
var _settle := 0.0
var _slow := 0.0
var _fast := 0.0
var _down_secs := DOWN_SECS
var _since_down := INF
var _slowmo_left := 0.0
var _slowmo_rest := 0.0
var _last_usec := 0
var _applied := -1
var _base_band := -1.0
var _base_pinned := -1.0
var _base_steps := -1
var _base_lod := -1.0

## Real play sessions only, like the freeze pause: a test window or a
## benchmark on a busy laptop keeps the load it asked for.
static func wanted() -> bool:
	return DisplayServer.get_name() != "headless" and not TestMode.active() and not Benchmark.requested()

func _ready() -> void:
	add_to_group(GraphicsSettings.GROUP)
	process_mode = Node.PROCESS_MODE_ALWAYS
	if game_state != null:
		game_state.state_changed.connect(func(_n, _o): rest())

## The frame lengths that count as behind / as room to spare, in seconds. With
## the 30 fps cap on, every frame is 33 ms: that is the target, not a lag.
static func slow_frame(cap: int) -> float:
	return maxf(1.0 / SLOW_FPS, 1.25 / float(cap)) if cap > 0 else 1.0 / SLOW_FPS

static func fast_frame(cap: int) -> float:
	return maxf(1.0 / FAST_FPS, 1.1 / float(cap)) if cap > 0 else 1.0 / FAST_FPS

## One frame's real length. Returns the rung to be on now.
func feed(frame_seconds: float, cap := 0) -> int:
	if frame_seconds <= 0.0:
		return rung
	_age += frame_seconds
	_since_down += frame_seconds
	if slowmo:
		_slowmo_left -= frame_seconds
		if _slowmo_left <= 0.0:
			slowmo = false
			_slowmo_rest = SLOWMO_REST
			_settle = SETTLE_SECS
		return rung
	_slowmo_rest = maxf(_slowmo_rest - frame_seconds, 0.0)
	if _age < WARMUP_SECS:
		return rung
	if _settle > 0.0:
		_settle -= frame_seconds
		return rung
	if frame_seconds > slow_frame(cap):
		_slow += frame_seconds
		_fast = 0.0
	else:
		_slow = maxf(_slow - frame_seconds * 0.5, 0.0)
		_fast = _fast + frame_seconds if frame_seconds < fast_frame(cap) else 0.0
	if _slow >= UP_SECS:
		_slow = 0.0
		_fast = 0.0
		if rung < TOP:
			rung += 1
			climbs += 1
			_settle = SETTLE_SECS
			if _since_down < BOUNCE_SECS:
				_down_secs = minf(_down_secs * 2.0, DOWN_SECS_MAX)
		elif _slowmo_rest <= 0.0:
			slowmo = true
			slowmo_count += 1
			_slowmo_left = SLOWMO_SECS
	elif _fast >= _down_secs and rung > NONE:
		rung -= 1
		_fast = 0.0
		_slow = 0.0
		_settle = SETTLE_SECS
		_since_down = 0.0
	return rung

## After a pause, a restart or any state change: the next frames are not the
## player's frame rate. The rung stays.
func rest() -> void:
	_age = 0.0
	_slow = 0.0
	_fast = 0.0
	_last_usec = 0
	if slowmo:
		slowmo = false
		_slowmo_rest = SLOWMO_REST
		apply()

## Settings changed: the player picked new values, so start from them.
func apply_graphics() -> void:
	rung = NONE
	slowmo = false
	_down_secs = DOWN_SECS
	rest()
	_applied = -1
	# After DynamicResolution and the traffic manager have taken the new values.
	apply.call_deferred()

func _process(_delta: float) -> void:
	if not live:
		return
	var now := Time.get_ticks_usec()
	var frame_seconds := (now - _last_usec) / 1000000.0 if _last_usec > 0 else 0.0
	_last_usec = now
	if game_state != null and game_state.state != GameState.State.PLAYING:
		return
	if GraphicsAutoPick.running:
		return   # the first-launch timing wants the plain game
	var before := rung
	var was_slowmo := slowmo
	feed(frame_seconds, GraphicsSettings.fps_cap)
	if rung != before or slowmo != was_slowmo:
		apply()

## Puts the holds for the current rung on (or lets them go).
func apply() -> void:
	_remember()
	var key := rung * 2 + (1 if slowmo else 0)
	if key == _applied:
		return
	_applied = key
	if dynres != null and is_instance_valid(dynres):
		dynres.hold_low(rung >= PICTURE)
	if is_inside_tree():
		get_viewport().mesh_lod_threshold = maxf(_base_lod, LOD_THRESHOLD) if rung >= PICTURE else _base_lod
		# The preset's own answer when the hold is off (graphics_settings.gd).
		RoadWet.set_reflections(GraphicsSettings.preset != "low" and rung < PICTURE)
	if traffic != null and is_instance_valid(traffic):
		traffic.physics_distance = minf(_base_band, TRAFFIC_BAND) if rung >= TRAFFIC else _base_band
		traffic.pinned_distance = 0.0 if rung >= RIVALS else _base_pinned
	Engine.max_physics_steps_per_frame = mini(_base_steps, SLOWMO_STEPS) if slowmo else _base_steps

## The values to come back to, read once before the first hold.
func _remember() -> void:
	if _base_band >= 0.0:
		return
	_base_band = traffic.physics_distance if traffic != null else 0.0
	_base_pinned = traffic.pinned_distance if traffic != null else 0.0
	if _base_steps < 0:
		_base_steps = Engine.max_physics_steps_per_frame
	if _base_lod < 0.0 and is_inside_tree():
		_base_lod = get_viewport().mesh_lod_threshold

func _exit_tree() -> void:
	# A restart reloads the scene: the engine-wide value must not stay lowered.
	if _base_steps > 0:
		Engine.max_physics_steps_per_frame = _base_steps
