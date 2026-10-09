class_name SpikeLog

# Frame-spike attribution (2026-10-09). Benchmark mode turns this on; the
# game's hot spots (chunk rebuilds, traffic respawns, texture uploads, ...)
# call mark() with how long they took, and the benchmark report prints the
# slowest frames with what ran in them. Off (the default) a mark is one
# static bool check, so the hooks cost nothing in normal play.

static var enabled := false
static var _events: Array = []  # this frame's [tag, ms]

## Records that `tag` took `ms` this frame (benchmark mode only).
static func mark(tag: String, ms: float) -> void:
	if enabled:
		_events.append([tag, ms])

## Milliseconds since `usec` (Time.get_ticks_usec()).
static func since(usec: int) -> float:
	return float(Time.get_ticks_usec() - usec) / 1000.0

## Hands over this frame's events and starts a new frame.
static func take() -> Array:
	var e := _events
	_events = []
	return e
