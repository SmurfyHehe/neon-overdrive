extends SceneTree

# Work board W1 (2026-10-11): the timing bar, all four styles.
# - a press at the sweet spot gives 1.0, at the zone edge 0.7, outside a miss;
# - a miss redoes the step with the needle 15% faster (phase rate x1.15);
# - a second miss completes the step at 0 and the bar stops (never stuck);
# - a held key (repeats with echo set) is one press;
# - the needle moves and stays inside the bar for every style.
#   <godot> --headless --path . -s res://tests/ui/timing_bar.gd

const Bar := preload("res://scripts/ui/timing_bar.gd")
const WorkOrders := preload("res://scripts/core/work_orders.gd")

var failures: Array[String] = []
var _marks: Array = []
var _missed := 0

func _initialize() -> void:
	for style in WorkOrders.STYLES:
		_style(style)
	for m in failures:
		printerr("FAIL: ", m)
	print("timing_bar: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _bar(style: String) -> Control:
	var b: Control = Bar.new()
	b.auto = false
	root.add_child(b)
	b.size = Vector2(480, 40)
	_marks = []
	_missed = 0
	b.step_done.connect(func(m: float) -> void: _marks.append(m))
	b.step_missed.connect(func(_n: int) -> void: _missed += 1)
	b.setup({"label": "Bolt it", "zone": 0.2, "speed": 1.0, "style": style})
	return b

func _drop(b: Control) -> void:
	root.remove_child(b)
	b.free()

func _key(echo: bool) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = KEY_ENTER
	e.physical_keycode = KEY_ENTER
	e.pressed = true
	e.echo = echo
	return e

func _style(style: String) -> void:
	var ref := _ref_phase(style)
	# Sweet spot -> clean.
	var b := _bar(style)
	b.advance(0.37)
	b.center = b.needle
	b.press()
	_check(_marks == [1.0], "%s: sweet spot gave %s" % [style, str(_marks)])
	_check(not b.running, "%s: still running after a mark" % style)
	b.press()  # a press after the step is over does nothing
	_check(_marks.size() == 1, "%s: a press after the end counted" % style)
	_drop(b)
	# Zone edge -> ok (0.7), just outside the sweet spot, just inside the zone.
	b = _bar(style)
	b.advance(0.37)
	b.center = b.needle - (b.zone * 0.5 - 0.005)
	b.press()
	_check(_marks == [0.7], "%s: zone edge gave %s" % [style, str(_marks)])
	_drop(b)
	# Outside -> miss and redo 15% faster.
	b = _bar(style)
	b.advance(0.1)
	var p1: float = b.phase
	b.setup({"label": "Bolt it", "zone": 0.2, "speed": 1.0, "style": style})
	b.advance(0.1)
	_check(is_equal_approx(b.phase, p1), "%s: setup is not repeatable" % style)
	b.advance(0.2)
	b.center = b.needle + b.zone * 0.5 + 0.1
	b.press()
	_check(_marks.is_empty() and b.running and b.misses == 1 and _missed == 1, "%s: first miss did not redo (marks %s, running %s)" % [style, str(_marks), b.running])
	_check(is_equal_approx(b.speed_mult, 1.15), "%s: redo speed is %f" % [style, b.speed_mult])
	_check(b.phase == (PI * 0.5 if style == "hold" else 0.0), "%s: the needle did not restart" % style)
	b.advance(0.1)
	var offset: float = PI * 0.5 if style == "hold" else 0.0
	_check(absf((b.phase - offset) / maxf(ref, 0.0001) - 1.15) < 0.01, "%s: needle is not 15%% faster (%f vs %f)" % [style, b.phase - offset, ref])
	# Second miss -> completes at 0.
	b.center = b.needle + b.zone * 0.5 + 0.1
	b.press()
	_check(_marks == [0.0] and not b.running, "%s: second miss gave %s running %s" % [style, str(_marks), b.running])
	b.advance(1.0)
	b.press()
	_check(_marks.size() == 1, "%s: a stopped bar took another press" % style)
	_drop(b)
	# A held key is one press: the first press misses and redoes, the repeats
	# change nothing.
	b = _bar(style)
	b.advance(0.2)
	b.center = b.needle + b.zone * 0.5 + 0.1
	b.handle_event(_key(false))
	b.handle_event(_key(true))
	b.handle_event(_key(true))
	b.handle_event(_key(true))
	_check(b.misses == 1 and b.running and _marks.is_empty(), "%s: held key counted %d presses" % [style, b.misses])
	_drop(b)
	# The needle stays on the bar and moves (hold: the zone moves instead).
	b = _bar(style)
	var moved := false
	var last_needle: float = b.needle
	var last_center: float = b.center
	for i in 600:
		b.advance(1.0 / 60.0)
		_check(b.needle >= -0.0001 and b.needle <= 1.0001, "%s: needle off the bar (%f)" % [style, b.needle])
		_check(b.center - b.zone * 0.5 >= -0.0001 and b.center + b.zone * 0.5 <= 1.0001, "%s: zone off the bar (%f)" % [style, b.center])
		if not is_equal_approx(b.needle, last_needle) or not is_equal_approx(b.center, last_center):
			moved = true
	_check(moved, "%s: nothing moved in 10 s" % style)
	_drop(b)
	print("timing_bar: %s ok" % style)

## Phase after 0.1 s on a fresh step.
func _ref_phase(style: String) -> float:
	var b := _bar(style)
	b.advance(0.1)
	var p: float = b.phase - (PI * 0.5 if style == "hold" else 0.0)
	_drop(b)
	return p
