extends SceneTree

# Wipers that sweep in rain and never break, the fuel flap that opens at the
# pump, and the refuel nozzle (car-parts-every-vehicle plan, Roy 1175 1177
# 1180), headless.
# - the player's cars carry two wiper blades on the glass and a flap over the
#   body's fuel recess; cops carry them too (the flap never opens: no tank)
# - dry: the blades stay parked. Rain: they sweep up past 60 degrees, stay on
#   the glass, and finish the stroke and park when the rain stops
# - wipers are not a damage part: they cannot break
# - the weather reader takes a script's static var (the water PR's Weather)
# - the pump menu's flags (at_pump, filling) and any FuelTank.refuel() open
#   the flap in about 0.4 s, then the nozzle plugs in; letting go backs the
#   nozzle out first, then closes the flap
# - nothing logs an error
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/car/wipers_and_flap.gd

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

class FakeBank extends RefCounted:
	var bank := 1000
	func spend_bank(n: int) -> bool:
		if n > bank:
			return false
		bank -= n
		return true

var logger := ErrorCounter.new()
var fails := 0

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	OS.add_logger(logger)
	_run()

func _run() -> void:
	_reader()
	for kind in ["p1_coupe", "p2_hothatch", "p5_muscle"]:
		await _car(kind)
	await _cop()
	_check(logger.errors.is_empty(), "errors were logged: %s" % [logger.errors])
	print("PASS" if fails == 0 else "FAILURES: %d" % fails)
	quit(1 if fails > 0 else 0)

func _reader() -> void:
	var s := GDScript.new()
	s.source_code = "extends RefCounted\nstatic var wetness := 0.6\n"
	s.reload()
	_check(absf(CarWipers.read_static(s, "wetness") - 0.6) < 1e-6, "the weather reader should read a script's static var")
	_check(CarWipers.read_static(s, "missing") == 0.0, "an unknown property reads as dry")
	CarWipers.rain_override = -1.0
	_check(CarWipers.rain_amount() == 0.0, "no weather script means dry")
	_check(not "wiper" in " ".join(CarDamage.PART_NAMES + CarDamage.LAMP_NAMES), "wipers are not a damage part: they never break (Roy 1180)")

func _player(kind: String) -> PlayerCar:
	PlayerCars.selected = kind
	var p: PlayerCar = load("res://scripts/car/player.gd").new()
	p.position = Vector3(0.0, 0.6, 0.0)
	root.add_child(p)
	await process_frame
	return p

func _car(kind: String) -> void:
	var p := await _player(kind)
	var w := p.get_node_or_null("CarWipers") as CarWipers
	var f := p.get_node_or_null("CarFuelFlap") as CarFuelFlap
	_check(w != null and w.blade_count() == 2, "%s: two wiper blades on the glass" % kind)
	_check(f != null, "%s: a fuel flap over the recess" % kind)
	if w == null or f == null:
		p.free()
		return
	w.set_process(false)
	f.set_process(false)
	_check(w.get("broken") == null and w.get("health") == null, "%s: wipers carry no damage state" % kind)

	# ---- dry: parked
	CarWipers.rain_override = 0.0
	for i in 20:
		w.advance(0.05)
	_check(w.phase == 0.0 and w.angle == 0.0, "%s: dry, the wipers stay parked" % kind)
	var parked := w.tip(0)
	# ---- rain: sweeps, stays on the glass
	CarWipers.rain_override = 0.75
	var peak := 0.0
	var scr: Dictionary = p.chassis_visual.get_meta("windscreen")
	var off_glass := 0
	for i in 40:
		w.advance(0.05)
		peak = maxf(peak, w.angle)
		var d: float = (w.tip(0) - scr.base).dot(scr.normal)
		if d < 0.0 or d > 0.04:
			off_glass += 1
	_check(peak > 1.05, "%s: in rain the blades sweep past 60 degrees, peak %.2f rad" % [kind, peak])
	_check(off_glass == 0, "%s: the blades stay on the glass (%d samples off)" % [kind, off_glass])
	_check(w.tip(0).distance_to(parked) > 0.0 or peak > 0.0, "%s: the blade tip moves" % kind)
	# ---- the rain stops: finishes the stroke and parks
	CarWipers.rain_override = 0.0
	var steps := 0
	while w.phase > 0.0 and steps < 100:
		w.advance(0.05)
		steps += 1
	_check(w.phase == 0.0 and w.angle == 0.0 and steps <= 30, "%s: after the rain the blades park within a stroke (%d steps)" % [kind, steps])
	CarWipers.rain_override = -1.0

	# ---- the pump: flap, then nozzle; back out, then close
	_check(f.open == 0.0 and f.plug == 0.0, "%s: flap shut and nozzle away at the start" % kind)
	p.fuel.at_pump = true
	var t_open := 0.0
	while not f.is_open() and t_open < 2.0:
		f.advance(0.02)
		t_open += 0.02
	_check(f.is_open() and t_open <= 0.5, "%s: the flap opens in about 0.4 s, took %.2f" % [kind, t_open])
	_check(f.plug < 0.5, "%s: the nozzle waits for the flap" % kind)
	var t_plug := 0.0
	while not f.is_plugged() and t_plug < 3.0:
		f.advance(0.02)
		t_plug += 0.02
	_check(f.is_plugged() and t_plug <= 0.8, "%s: the nozzle plugs in within 0.8 s, took %.2f" % [kind, t_plug])
	_check(absf(f._pivot.rotation.y - CarFuelFlap.OPEN_ANGLE) < 0.01, "%s: the flap stands open at %.2f rad" % [kind, CarFuelFlap.OPEN_ANGLE])
	_check(f._nozzle.visible, "%s: the nozzle shows while plugged in" % kind)
	p.fuel.at_pump = false
	f.advance(0.1)
	_check(f.open > 0.99 and f.plug < 1.0, "%s: the nozzle backs out before the flap closes" % kind)
	var t_end := 0.0
	while (f.open > 0.0 or f.plug > 0.0) and t_end < 4.0:
		f.advance(0.02)
		t_end += 0.02
	_check(f.open == 0.0 and f.plug == 0.0 and not f._nozzle.visible, "%s: flap shut and nozzle away again (%.2f s)" % [kind, t_end])

	# ---- any refuel opens the flap, even with no flags set
	p.fuel.litres = 10.0
	var bank := FakeBank.new()
	_check(p.fuel.refuel(bank) > 0.0, "%s: a refuel buys fuel" % kind)
	_check(p.fuel.is_filling(), "%s: a refuel counts as filling for the flap" % kind)
	for i in 30:
		f.advance(0.02)
	_check(f.open > 0.99, "%s: a refuel from anywhere opens the flap" % kind)
	p.free()

func _cop() -> void:
	var t := TrafficCar.new()
	t.kind = "c1_patrol"
	t.build = "stock"
	t.position = Vector3(8.0, 0.6, 0.0)
	root.add_child(t)
	await process_frame
	var w := t.get_node_or_null("CarWipers") as CarWipers
	var f := t.get_node_or_null("CarFuelFlap") as CarFuelFlap
	_check(w != null and w.blade_count() == 2, "a cop car has wipers")
	_check(f != null, "a cop car has a fuel flap")
	if f != null:
		f.set_process(false)
		for i in 20:
			f.advance(0.05)
		_check(f.open == 0.0, "a car with no tank never opens its flap")
	t.free()
