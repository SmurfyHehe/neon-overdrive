class_name LowFpsWatch
extends RefCounted

# Decides when the game is running too badly to play (Roy 160-162): fps under
# FLOOR_FPS for SLOW_SECONDS in a row, or one frame longer than FREEZE_SECONDS.
# Pure logic on frame times, so tests can feed it numbers. GameState owns one
# and opens the pause screen when it says so.

const FLOOR_FPS := 30.0
const SLOW_SECONDS := 1.0
const FREEZE_SECONDS := 0.5
## Ignore the first seconds after a (re)start: scene load and shader compile
## hitches are not the player's frame rate.
const WARMUP_SECONDS := 3.0

## False: only a freeze pauses; a low frame rate is PerfLadder's job (it
## lowers the load instead of stopping the game).
var slow_pauses := true
var freeze_seconds := FREEZE_SECONDS

var _age := 0.0
var _slow_time := 0.0

## Feed one frame's real (unscaled) duration. Returns true when the game should pause.
func feed(frame_seconds: float) -> bool:
	_age += frame_seconds
	if _age < WARMUP_SECONDS:
		return false
	if frame_seconds >= freeze_seconds:
		return true
	if not slow_pauses:
		return false
	if frame_seconds > 1.0 / FLOOR_FPS:
		_slow_time += frame_seconds
	else:
		_slow_time = 0.0
	return _slow_time >= SLOW_SECONDS

## Start over (after resume, restart or a state change).
func reset() -> void:
	_age = 0.0
	_slow_time = 0.0
