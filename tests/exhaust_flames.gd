extends SceneTree

# Exhaust flames v2 (2026-10-07, Option A shader quads). Boots the real
# Game.tscn with no traffic and checks that
# - the flame colours are warm only: white-hot, amber, orange (r >= g >= b,
#   so no blue core, no magenta, no cyan)
# - queue_burst() waits VISUAL_DELAY before showing (the sound sync), flash()
#   shows at once, and a burst lights the jets, a fireball and the light
# - the fireball stays in world space (the car drives away from it) and
#   shift_world() moves it with the floating origin
# - an upshift at full throttle flames only when the car's flame setting is at
#   least UPSHIFT_FLAME_MIN: none at 0.2 (P1's preset), at least one at 0.6
# - the anti-lag switch makes the synth bang and flame on a lift even with the
#   pops knob at 0, and nothing with it off
# - a traffic car gets flames only from its spec's flame value: none on the
#   commuter default, a node on the C3 interceptor preset, and that node's own
#   pop law queues bursts on an overrun
# - switching exhaust_flames off clears everything on screen
# - nothing logs an error
# With a real renderer (no --headless) it also compiles the three shaders and
# writes screenshots of a burst to user://exhaust_flames/ (chase_1..3.png from
# the chase cam, side_1..3.png from beside the tail).
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/exhaust_flames.gd
#   Godot_v4.7.2-stable_win64_console.exe --audio-driver Dummy --path . -s res://tests/exhaust_flames.gd

class ErrorCounter extends Logger:
	var errors: Array[String] = []
	var _lock := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_lock.lock()
		errors.append("%s (%s:%d in %s)" % [rationale if rationale != "" else code, file, line, function])
		_lock.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

var logger := ErrorCounter.new()
var failures: Array[String] = []
var throttle := 0.0

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	ExhaustTune.save_path = "user://autotune/test_exhaust_flames.json"
	OS.add_logger(logger)
	seed(31)
	change_scene_to_file("res://Game.tscn")
	_run()

func _run() -> void:
	if not await _until(func(): return current_scene != null and current_scene.get("player") != null and current_scene.get("fx") != null, 20.0):
		return _end("Game never became ready")
	var game := current_scene
	var p: PlayerCar = game.player
	var fl: ExhaustFlames = game.fx.flames
	p.driver = func(c: PlayerCar) -> void:
		c.throttle_input = throttle
		c.brake_input = 0.0
		c.steering_input = 0.0
		c.handbrake_input = 0.0
	await _frames(5)

	# --- colours
	for c in [ExhaustFlames.HOT, ExhaustFlames.AMBER, ExhaustFlames.ORANGE, ExhaustFlames.LIGHT_COLOR]:
		_check(c.r >= c.g and c.g >= c.b, "flame colour %s is not warm (r >= g >= b)" % c)

	# --- delay queue and one burst
	_check(fl.jets.size() == 2, "the test car has two exhaust tips (%d jets)" % fl.jets.size())
	var b0 := fl.bursts
	fl.queue_burst(0.8)
	_check(fl.bursts == b0 and not fl.is_showing(), "queue_burst() should not show at once")
	await create_timer(ExhaustFlames.VISUAL_DELAY + 0.06).timeout
	_check(fl.bursts == b0 + 1, "queue_burst() should show after VISUAL_DELAY (bursts %d -> %d)" % [b0, fl.bursts])
	fl.flash(1.0)
	_check(fl.is_showing() and fl.jets[0].visible and fl._light.visible, "flash() should show jets and light at once")
	var ball: MeshInstance3D = fl._balls[(fl._next_ball - 1 + ExhaustFlames.POOL) % ExhaustFlames.POOL].mi
	_check(ball.visible and ball.top_level, "a burst should leave a top-level fireball")
	if DisplayServer.get_name() != "headless":
		await _shots(fl)

	# --- world-space fireball + floating origin
	fl.flash(1.0)
	ball = fl._balls[(fl._next_ball - 1 + ExhaustFlames.POOL) % ExhaustFlames.POOL].mi
	var before := ball.global_position
	fl.shift_world(Vector3(0.0, 0.0, 150.0))
	_check(ball.global_position.distance_to(before + Vector3(0.0, 0.0, 150.0)) < 0.5, "shift_world should move a live fireball")
	fl.shift_world(Vector3(0.0, 0.0, -150.0))

	# --- upshift gate: launch in first, then shift by hand at high rpm
	p.set_transmission_mode(PlayerCar.Transmission.SEMI)
	p.spec.exhaust.flame = 0.2
	throttle = 1.0
	p.current_gear = 1
	var up0 := fl.upshift_bursts
	if not await _until(func(): return _rpm_norm(p) > 0.75, 8.0):
		_check(false, "first gear never reached 75%% rpm (%.0f)" % p.motor_rpm)
	p.shift(1)
	await create_timer(0.5).timeout
	_check(fl.upshift_bursts == up0, "flame 0.2 is below UPSHIFT_FLAME_MIN: no upshift flame (%d)" % (fl.upshift_bursts - up0))
	p.spec.exhaust.flame = 0.6
	if not await _until(func(): return _rpm_norm(p) > 0.75 and not p.is_shifting, 10.0):
		_check(false, "second gear never reached 75%% rpm (%.0f)" % p.motor_rpm)
	p.shift(1)
	await create_timer(0.5).timeout
	print("upshift at flame 0.6: %d upshift bursts, gear %d" % [fl.upshift_bursts - up0, p.current_gear])
	_check(fl.upshift_bursts > up0, "flame 0.6 should flame on a full-throttle upshift")
	throttle = 0.0

	# --- anti-lag in the synth
	var off := _overrun_flames(false)
	var on := _overrun_flames(true)
	print("anti-lag overrun flames: off %d, on %d" % [off, on])
	_check(off == 0, "pops 0 and anti-lag off: no overrun flames (%d)" % off)
	_check(on >= 10, "anti-lag on: a volley of flames on the lift (%d)" % on)

	# --- traffic is data-driven
	var plain := _traffic_car(game, CarSpec.traffic_default())
	_check(plain.flames == null, "a commuter traffic car must not get flames")
	var c3_spec := CarSpec.traffic_default()
	c3_spec.exhaust = ExhaustTune.for_car("c3_interceptor").to_dict()
	var c3 := _traffic_car(game, c3_spec)
	_check(c3.flames != null and c3.flames.flame_setting() > 0.0, "the C3 preset (flame 0.05) should get flames")
	if c3.flames != null:
		c3.motor_rpm = c3.max_rpm * 0.9
		c3.throttle_amount = 0.0
		for i in 60:
			c3.flames._simulate_pops(1.0 / 60.0, c3.flames.flame_setting())
		_check(not c3.flames._queue.is_empty() or c3.flames.bursts > 0, "a C3 overrun should queue a burst")
	plain.queue_free()
	c3.queue_free()

	# --- off clears
	fl.flash(1.0)
	game.fx.set_effect("exhaust_flames", false)
	_check(not fl.is_active() and not fl.jets[0].visible, "exhaust_flames off should clear the fire")
	game.fx.set_effect("exhaust_flames", true)
	await _frames(3)
	_end("")

func _rpm_norm(p: PlayerCar) -> float:
	return (p.motor_rpm - p.idle_rpm) / (p.max_rpm - p.idle_rpm)

# 2 s of overrun at 6000 rpm with pops 0: how many flame events.
func _overrun_flames(anti_lag: bool) -> int:
	var s := EngineSynth.new()
	s.tune = ExhaustTune.new(0.5, 0.3, 0.0, 0.5, 1.0 if anti_lag else 0.0)
	var n := 0
	for i in 2 * 44100 / 512:
		s.render(512, 6000.0, 0.0, false)
		if s.take_flames() > 0.0:
			n += 1
	return n

func _traffic_car(game: Node, spec: Dictionary) -> TrafficCar:
	var car := TrafficCar.new()
	car.spec = spec
	car.process_mode = Node.PROCESS_MODE_DISABLED  # no manager: only _ready runs
	car.position = Vector3(0.0, 0.5, 9000.0)
	game.add_child(car)
	return car

func _shots(fl: ExhaustFlames) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://exhaust_flames"))
	# chase cam, then a camera beside the tail so the jet's length shows
	var prev := root.get_viewport().get_camera_3d()
	var side := Camera3D.new()
	var car: Node3D = fl.get_parent()
	for view in ["chase", "side"]:
		if view == "side":
			car.add_child(side)
			side.position = Vector3(-3.2, 0.9, 3.2)
			side.look_at(car.to_global(Vector3(0.0, 0.3, 2.6)))
			side.fov = 50.0
			side.make_current()
			await _frames(4)
		await create_timer(0.6).timeout  # let the last burst die out
		fl.flash(1.0)
		for i in 3:
			await _frames(2 if i == 0 else 4)
			var img := root.get_viewport().get_texture().get_image()
			img.save_png("user://exhaust_flames/%s_%d.png" % [view, i + 1])
	if prev != null:
		prev.make_current()
	side.queue_free()
	print("screenshots: ", ProjectSettings.globalize_path("user://exhaust_flames"))

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _until(cond: Callable, timeout_s: float) -> bool:
	var t := 0.0
	while not cond.call():
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		if t > timeout_s:
			return false
	return true

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _end(msg: String) -> void:
	if msg != "":
		failures.append(msg)
	for e in logger.errors:
		failures.append("logged error: " + e)
	for f in failures:
		printerr("FAIL: ", f)
	print("exhaust_flames: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	OS.remove_logger(logger)
	quit(0 if failures.is_empty() else 1)
