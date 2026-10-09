class_name Ignition
extends RefCounted

# The X key (2026-10-09, Roy): X starts the engine and X switches it off.
# This is only the state machine; PlayerCar applies it to the GEVP vehicle.
#
#   RUN      the engine is firing. Fuel burns, the synth plays.
#   OFF      shut down by the player or stalled. Throttle is ignored.
#   CRANK    the starter turns the engine over for CRANK_SECS, then it either
#            catches (RUN) or, with an empty tank, gives up (OFF).
#
# The car boots in RUN (the night starts with the engine already on); the sweep
# and shake belong to the start from OFF, not to the first frame of a run.

enum State { RUN, OFF, CRANK }

const CRANK_SECS := 0.85
## Rpm the starter turns the engine at, as a fraction of idle (the needle
## rises from 0 to this while cranking).
const CRANK_RPM_FRAC := 0.3
## On catching, the needle flares this far from idle toward redline (fraction
## of the idle..max range) and drops back on its own.
const FLARE := 0.22
## Camera trauma (0..1) at the start of cranking and when the engine catches.
const SHAKE_CRANK := 0.18
const SHAKE_CATCH := 0.4

var state := State.RUN
var crank_t := 0.0
## Pending camera shake; the camera takes it once (take_shake).
var _shake := 0.0

func is_running() -> bool:
	return state == State.RUN

func is_cranking() -> bool:
	return state == State.CRANK

## 0..1 through the crank.
func crank_frac() -> float:
	return clampf(crank_t / CRANK_SECS, 0.0, 1.0)

## X pressed. Returns the state it moved to; a press while cranking does nothing.
func toggle() -> State:
	match state:
		State.RUN:
			state = State.OFF
		State.OFF:
			state = State.CRANK
			crank_t = 0.0
			_shake = maxf(_shake, SHAKE_CRANK)
	return state

## Advances the crank. Returns true on the tick the engine catches (fuel_ok) so
## the caller can fire it; with no fuel it falls back to OFF.
func step(delta: float, fuel_ok: bool) -> bool:
	if state != State.CRANK:
		return false
	crank_t += delta
	if crank_t < CRANK_SECS:
		return false
	crank_t = 0.0
	if not fuel_ok:
		state = State.OFF
		return false
	state = State.RUN
	_shake = maxf(_shake, SHAKE_CATCH)
	return true

## The engine stopped by itself (a stall) or was started by other code.
func sync_running(running: bool) -> void:
	if state == State.CRANK:
		return
	state = State.RUN if running else State.OFF

func take_shake() -> float:
	var s := _shake
	_shake = 0.0
	return s
