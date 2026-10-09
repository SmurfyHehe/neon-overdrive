extends SceneTree

# LowFpsWatch (Roy 160-162): pauses on 1 s under 30 fps or a 0.5 s freeze, never
# during warm-up, and a recovered frame rate resets the count. Pure logic, headless.
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/low_fps_watch.gd

var failures: Array[String] = []

func _check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)

func _warm() -> LowFpsWatch:
	var w := LowFpsWatch.new()
	for i in 240:
		w.feed(1.0 / 60.0)  # 4 s of healthy frames
	return w

func _initialize() -> void:
	var w := _warm()
	_check(not w.feed(1.0 / 60.0), "60 fps must not pause")
	# 25 fps for just under a second: no pause; then it crosses one second: pause.
	w = _warm()
	var paused := false
	for i in 24:
		paused = paused or w.feed(0.04)
	_check(not paused, "0.96 s at 25 fps must not pause")
	_check(w.feed(0.04), "1.0 s at 25 fps must pause")
	# A good frame in between resets the slow stretch.
	w = _warm()
	for i in 20:
		w.feed(0.04)
	w.feed(1.0 / 60.0)
	paused = false
	for i in 20:
		paused = paused or w.feed(0.04)
	_check(not paused, "recovery must reset the slow count")
	# Freeze.
	w = _warm()
	_check(not w.feed(0.4), "0.4 s hitch must not pause")
	_check(w.feed(0.5), "0.5 s freeze must pause")
	# Warm-up: a long load frame right after start is ignored.
	w = LowFpsWatch.new()
	_check(not w.feed(2.0), "load hitch inside warm-up must not pause")
	w.reset()
	_check(not w.feed(0.6), "reset restarts warm-up")
	for f in failures:
		printerr("FAIL: ", f)
	print("low_fps_watch: ", "FAIL" if failures else "PASS")
	quit(1 if failures else 0)
