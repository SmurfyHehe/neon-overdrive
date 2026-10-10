extends SceneTree

# What the automatic does, written out: every gear change with its time, speed
# and revs, through a launch, a pull to top speed, a lift, a kickdown, feathering
# the throttle key, a stop, reverse and a switch of gearbox mode. Odd things
# are flagged with "!!". Flat pad, the game's 120 Hz. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 120 --path . -s res://tools/auto_box_trace.gd
# NEON_TRACE_CARS=p1_coupe,p5_muscle picks the cars (default: every player car).
# NEON_TRACE_MODS=1 fits everything the car's mod tree offers (the test build's car).

const H := preload("res://tests/car/auto_box_harness.gd")
const HUNT_WINDOW := 3.0   # s: a shift undone inside this, at about the same speed, is hunting
const HUNT_KMH := 6.0

var _c: PlayerCar
var _p: H.Pedals
var _t := 0.0
var _gear := 0
var _log: Array = []       # [t, from, to, kmh, rpm]
var _limiter := 0
var _kicks := 0
var _duty := 0.0

func _initialize() -> void:
	Engine.physics_ticks_per_second = 120
	_run()

func _run() -> void:
	H.ground(root)
	await physics_frame
	var want := OS.get_environment("NEON_TRACE_CARS")
	for k in PlayerCars.KINDS:
		if want == "" or k.id in want.split(","):
			await _car(k.id)
	quit(0)

func _step(secs: float) -> void:
	var dt := 1.0 / Engine.physics_ticks_per_second
	for i in maxi(roundi(secs / dt), 1):
		await physics_frame
		_t += dt
		_duty += (_p.throttle - _duty) * dt / 2.0
		if _c.motor_is_redline:
			_limiter += 1
		if _c.current_gear != _gear:
			_log.append([_t, _gear, _c.current_gear, H.kmh(_c), _c.motor_rpm])
			if true:
				var box := _c.auto_box
				var kick := box != null and box.kick_count != _kicks
				_kicks = box.kick_count if box != null else 0
				print("   %6.2f s  %2d -> %2d  at %5.1f km/h  %4.0f rpm  brake %.1f  demand %.2f  key down %.0f%% of the last 2 s%s" % [_t, _gear, _c.current_gear,
					H.kmh(_c), _c.motor_rpm, _p.brake, box.demand if box != null else 0.0, _duty * 100.0, "  (kickdown)" if kick else ""])
			_gear = _c.current_gear

func _state() -> String:
	return "gear %d, %.1f km/h, %.0f rpm" % [_c.current_gear, H.kmh(_c), _c.motor_rpm]

## Shifts undone inside HUNT_WINDOW since log entry `from`.
func _hunts(from: int) -> int:
	var n := 0
	for i in range(maxi(from, 1), _log.size()):
		var a: Array = _log[i - 1]
		var b: Array = _log[i]
		if b[2] == a[1] and b[0] - a[0] < HUNT_WINDOW and a[1] > 0 and a[2] > 0 and absf(b[3] - a[3]) < HUNT_KMH:
			n += 1
	return n

func _phase(title: String) -> int:
	print(" %s (%s)" % [title, _state()])
	_limiter = 0
	return _log.size()

func _end(from: int, note := "") -> void:
	var hunts := _hunts(from + 1)
	var line := "   = %s, %d shifts" % [_state(), _log.size() - from]
	if absf(_c.global_position.x) > 50.0 or _c.global_position.y < -1.0:
		line += ", !! off line: x %.0f m, y %.1f m, z %.0f m" % [_c.global_position.x, _c.global_position.y, _c.global_position.z]
	if hunts > 0:
		line += ", !! %d undone inside %.0f s at the same speed (hunting)" % [hunts, HUNT_WINDOW]
	if _limiter > 12:
		line += ", !! %.1f s on the limiter" % (_limiter / 120.0)
	print(line + note)

func _stop() -> void:
	_p.throttle = 0.0
	_p.brake = 1.0
	var waited := 0.0
	while H.kmh(_c) > 0.3 and waited < 30.0:
		await _step(0.25)
		waited += 0.25
	await _step(1.5)
	# back to the middle of the pad (it is 6 km each way)
	# and pointing down it again: a full stop with no hands on the wheel leaves some cars askew
	_c.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, _c.global_position.y, 0.0))
	_c.linear_velocity = Vector3.ZERO
	_c.angular_velocity = Vector3.ZERO
	_c.previous_global_position = _c.global_position
	for w in _c.wheel_array:
		w.previous_global_position = w.global_position
	await _step(0.5)

func _car(kind: String) -> void:
	_p = H.Pedals.new()
	var over := {}
	if OS.get_environment("NEON_TRACE_MODS") == "1":
		var stock := CarSpec.player_spec(kind)
		TuneParams.set_gear_count((stock.gear_ratios as Array).size())
		var fit: Dictionary = ModTree.showcase_fit(kind) if ModTree.has_tree(kind) else ModTree.max_fit(kind, [])
		over = ModTree.build(stock, fit).spec
	_c = H.car(root, kind, PlayerCar.Transmission.AUTO, _p, over)
	_t = 0.0
	_log.clear()
	_gear = _c.current_gear
	_kicks = 0
	print("== %s: %s box, %d gears %s, final %.2f, redline %.0f, idle %.0f, %.0f Nm%s" % [kind, _c.auto_box.family if _c.auto_box != null else "NO",
		_c.gear_ratios.size(), str(_c.gear_ratios), _c.final_drive, _c.max_rpm, _c.idle_rpm, _c.max_torque, " (all mods)" if not over.is_empty() else ""])

	var at := _phase("standing on the brake 2 s")
	_p.brake = 1.0
	await _step(2.0)
	_end(at, "" if _c.current_gear == 1 and absf(H.kmh(_c)) < 0.5 else "  !! not standing in 1st")

	at = _phase("brake off 4 s: creep")
	_p.brake = 0.0
	await _step(4.0)
	_end(at, "" if H.kmh(_c) > 2.0 and H.kmh(_c) < 12.0 else "  !! creep outside 2-12 km/h")

	at = _phase("floored 40 s")
	_p.throttle = 1.0
	var top_gear := 0
	for i in 40:
		await _step(1.0)
		top_gear = maxi(top_gear, _c.current_gear)
	var vmax := H.kmh(_c)
	_end(at, ", highest gear %d of %d%s" % [top_gear, _c.gear_ratios.size(), "" if top_gear >= _c.gear_ratios.size() - 1 else "  !! never got near top gear"])

	at = _phase("lift off 10 s")
	_p.throttle = 0.0
	await _step(10.0)
	_end(at)

	at = _phase("full brake to a stop")
	await _stop()
	_end(at, "" if _c.current_gear == 1 else "  !! stopped in gear %d" % _c.current_gear)

	# A keyboard driver holds a speed by tapping the throttle key: on below it, off above.
	for hold in [40.0, 60.0, 90.0, 130.0]:
		at = _phase("holding %.0f km/h on the key for 20 s" % hold)
		_p.brake = 0.0
		for i in 20 * 30:
			_p.throttle = 1.0 if H.kmh(_c) < hold else 0.0
			await _step(1.0 / 30.0)
		_end(at)

	at = _phase("holding 70 km/h for 8 s, then floored 4 s: kickdown")
	for i in 8 * 30:
		_p.throttle = 1.0 if H.kmh(_c) < 70.0 else 0.0
		_p.brake = 1.0 if H.kmh(_c) > 80.0 else 0.0
		await _step(1.0 / 30.0)
	_p.brake = 0.0
	_p.throttle = 0.0
	await _step(1.0)
	var kicks := _c.auto_box.kick_count if _c.auto_box != null else 0
	var g0 := _c.current_gear
	_p.throttle = 1.0
	await _step(4.0)
	var kicked: int = (_c.auto_box.kick_count if _c.auto_box != null else 0) - kicks
	_end(at, ", %d kickdown(s) from gear %d%s" % [kicked, g0, "" if kicked > 0 or g0 == 1 else "  !! no kickdown"])

	at = _phase("full brake to a stop")
	await _stop()
	_end(at, "" if _c.current_gear == 1 else "  !! stopped in gear %d" % _c.current_gear)

	at = _phase("R, floored 3 s, brake, R again, floored 3 s")
	var ok := _c.toggle_reverse()
	await _step(0.8)
	_p.brake = 0.0
	_p.throttle = 1.0
	await _step(3.0)
	var back := H.kmh(_c)
	_p.throttle = 0.0
	_p.brake = 1.0
	await _step(4.0)
	var ok2 := _c.toggle_reverse()
	await _step(0.8)
	_p.brake = 0.0
	_p.throttle = 1.0
	await _step(3.0)
	_end(at, ", reverse reached %.1f km/h%s" % [back, "" if ok and ok2 and back < -5.0 and H.kmh(_c) > 10.0 and _c.current_gear >= 1 else "  !! reverse or the way back failed"])

	at = _phase("at speed: G to SEMI, G to MANUAL, G to AUTO, floored throughout")
	await _step(4.0)
	for m in [PlayerCar.Transmission.SEMI, PlayerCar.Transmission.MANUAL, PlayerCar.Transmission.AUTO]:
		_c.set_transmission_mode(m)
		await _step(2.0)
		print("   mode %s: %s, engine %s" % [PlayerCar.TRANSMISSION_LETTERS[m], _state(), "running" if _c.engine_running else "STOPPED !!"])
	await _step(6.0)
	_end(at)
	print(" top speed seen %.0f km/h, %d shifts in all" % [vmax, _log.size()])
	_p.throttle = 0.0
	await H.remove(self, _c)
