extends SceneTree

# A saved run brings the gearbox back as it was (2026-10-10). On a bare pad at
# the game's 120 Hz, one car saved with SaveDirector.car_state and a fresh one
# put back with restore_car:
#   - semi, 3rd at speed: comes back in semi and in 3rd (it used to come back
#     as the automatic, which then shifted for itself)
#   - automatic, floored in a low gear: comes back in that gear and keeps it
#     for the next half second (the box used to wake up believing the pedal
#     was lifted and change up on the first tick)
#   - manual, 3rd at speed: comes back in manual and in 3rd
#   - manual, standing in 1st: comes back in manual, in neutral, and the
#     engine is still running two seconds later (no clutch key is held as the
#     game loads; in gear it would stall)
#   - a save from before this (no "box", no "demand") still opens: automatic
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 120 --path . -s res://tests/core/save_gearbox.gd

const H := preload("res://tests/car/auto_box_harness.gd")
const SaveDirector := preload("res://scripts/save/save_director.gd")
const T := PlayerCar.Transmission
const KIND := "p1_coupe"

var fails: Array[String] = []
var dt := 1.0 / 120.0

func _initialize() -> void:
	Engine.physics_ticks_per_second = 120
	_run()

func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)

func _run() -> void:
	dt = 1.0 / Engine.physics_ticks_per_second
	H.ground(root)
	await physics_frame
	await _moving(T.SEMI, 3, "semi")
	await _moving(T.MANUAL, 3, "manual")
	await _auto_floored()
	await _manual_standing()
	await _old_save()
	for f in fails:
		printerr("FAIL: ", f)
	print("save_gearbox: ", "PASS" if fails.is_empty() else "FAIL (%d)" % fails.size())
	quit(0 if fails.is_empty() else 1)

## A fresh car (the automatic, as every launch) with `state` put back into it.
func _restored(state: Dictionary, p: H.Pedals) -> PlayerCar:
	var c: PlayerCar = H.car(root, KIND, T.AUTO, p)
	await physics_frame
	SaveDirector.restore_car(c, state)
	return c

## Floored through the gears by hand to `gear`, then saved.
func _moving(mode: int, gear: int, name: String) -> void:
	var p := H.Pedals.new()
	var a: PlayerCar = H.car(root, KIND, T.SEMI, p)  # semi on the way up: the test has no clutch foot
	await H.settle(self, p)
	p.throttle = 1.0
	var t := 0.0
	while t < 30.0 and not (a.current_gear == gear and a.motor_rpm > 0.6 * a.max_rpm and not a.is_shifting):
		if a.current_gear < gear and not a.is_shifting and (a.motor_rpm > 0.85 * a.max_rpm or a.current_gear < 1):
			a.shift(1)
		await physics_frame
		t += dt
	a.set_transmission_mode(mode)
	await physics_frame
	var state := SaveDirector.car_state(a)
	var kmh := H.kmh(a)
	await H.remove(self, a)
	var b := await _restored(state, p)
	_check(b.transmission_mode() == mode, "%s: came back in mode %d" % [name, b.transmission_mode()])
	_check(b.current_gear == gear, "%s: came back in gear %d, saved in %d" % [name, b.current_gear, gear])
	await H.wait(self, 1.0)
	print("%s: saved in gear %d at %.0f km/h, back in mode %s, gear %d, %.0f km/h a second on" % [name, gear, kmh,
		PlayerCar.TRANSMISSION_LETTERS[b.transmission_mode()], b.current_gear, H.kmh(b)])
	_check(b.current_gear == gear, "%s: left gear %d for %d within a second of the resume" % [name, gear, b.current_gear])
	_check(b.engine_running, "%s: the engine stopped after the resume" % name)
	_check(H.kmh(b) > kmh - 5.0, "%s: lost speed after the resume (%.0f, was %.0f km/h)" % [name, H.kmh(b), kmh])
	await H.remove(self, b)

func _auto_floored() -> void:
	var p := H.Pedals.new()
	var a: PlayerCar = H.car(root, KIND, T.AUTO, p)
	await H.settle(self, p)
	p.throttle = 1.0
	var t := 0.0
	# well into a low gear, floored: above where a lifted pedal would change up, under where a floored one does
	while t < 30.0 and not (a.current_gear == 2 and H.gearbox_rpm(a) > 0.7 * a.max_rpm and not a.auto_box.shifting):
		await physics_frame
		t += dt
	var state := SaveDirector.car_state(a)
	var gear := a.current_gear
	await H.remove(self, a)
	var b := await _restored(state, p)
	var first_change := -1.0
	t = 0.0
	while t < 0.5:
		await physics_frame
		t += dt
		if b.current_gear != gear and first_change < 0.0:
			first_change = t
	print("automatic: saved floored in gear %d (demand %.2f), back in gear %d, %s" % [gear, state.demand, b.current_gear,
		"kept it for half a second" if first_change < 0.0 else "changed after %.2f s" % first_change])
	_check(b.transmission_mode() == T.AUTO, "automatic: came back in mode %d" % b.transmission_mode())
	_check(gear == 2, "automatic: the test never got to 2nd (gear %d)" % gear)
	_check(first_change < 0.0, "automatic: changed gear %.2f s after a floored resume" % first_change)
	await H.remove(self, b)

func _manual_standing() -> void:
	var p := H.Pedals.new()
	var a: PlayerCar = H.car(root, KIND, T.MANUAL, p)
	a.clutch_input = 1.0
	await H.settle(self, p)
	p.brake = 1.0
	var state := SaveDirector.car_state(a)
	_check(a.current_gear == 1, "manual standing: the test car was in gear %d" % a.current_gear)
	await H.remove(self, a)
	var b := await _restored(state, p)
	_check(b.transmission_mode() == T.MANUAL, "manual standing: came back in mode %d" % b.transmission_mode())
	_check(b.current_gear == 0, "manual standing: came back in gear %d, not neutral" % b.current_gear)
	await H.wait(self, 2.0)
	print("manual standing: back in mode %s, gear %d, engine %s" % [PlayerCar.TRANSMISSION_LETTERS[b.transmission_mode()], b.current_gear,
		"running" if b.engine_running else "stalled"])
	_check(b.engine_running, "manual standing: stalled after the resume")
	await H.remove(self, b)

func _old_save() -> void:
	var p := H.Pedals.new()
	var a: PlayerCar = H.car(root, KIND, T.AUTO, p)
	await H.settle(self, p)
	var state := SaveDirector.car_state(a)
	state.erase("box")
	state.erase("demand")
	await H.remove(self, a)
	var b := await _restored(state, p)
	await H.wait(self, 0.5)
	print("old save: back in mode %s, gear %d" % [PlayerCar.TRANSMISSION_LETTERS[b.transmission_mode()], b.current_gear])
	_check(b.transmission_mode() == T.AUTO and b.current_gear == 1, "old save: mode %d, gear %d" % [b.transmission_mode(), b.current_gear])
	await H.remove(self, b)
