extends SceneTree
# Player cars (stage D, 2026-10-09): every car in PlayerCars.KINDS boots as
# THE player's car (NEON_CAR=<kind>, the same path the pause menu's Car page
# takes through PlayerCars.selected) and gets a drive test:
#   - Game.tscn boots with that car, no script or engine errors;
#   - the body is the sheet car's (chassis_visual meta "kind"), the wheels hang
#     at the sheet's hub height and track;
#   - it settles upright, then a lane driver holds full throttle for 15 s:
#     it must move, reach a per-car floor speed, stay in its lane, stay
#     finite and upright;
#   - the spec is CarSpec.player_spec(kind), with that car's torque and mass,
#     and the Tuner's "Stock" (TunerScreen) is that spec, not the coupe's.
# The beater is the slowest by design (T0): its floor is lower.
#
# Run: <godot> --headless --fixed-fps 120 --path . -s res://tests/fleet/player_cars.gd
const Harness := preload("res://tests/traffic/traffic_harness.gd")
const RATE := 120
const DRIVE_SECS := 15.0
## The lane driver (tests/traffic/traffic_harness.gd) holds a lane to under 1 m at
## 120 km/h through the default bends (tests/world/curve_drive.gd); above that the
## fast cars run wide, so the drive is capped there. The cars' pace shows in
## the 0-100 time, not the top speed.
const CAP_KMH := 125.0
## km/h each car must reach in DRIVE_SECS from a standing start.
const FLOOR_KMH := {
	"p0_beater": 70.0, "p1_coupe": 120.0, "p2_hothatch": 120.0, "p3_tuner": 120.0,
	"p4_kei": 100.0, "p5_muscle": 120.0, "p6_crossover": 120.0,
}
## 0-100 km/h ceiling per car, seconds (the beater is slow by design: T0).
const T100_MAX := {
	"p0_beater": 16.0, "p1_coupe": 7.0, "p2_hothatch": 10.5, "p3_tuner": 7.0,
	"p4_kei": 13.0, "p5_muscle": 7.0, "p6_crossover": 7.0,
}

var logger := Harness.ErrorCounter.new()
var fails := 0
var game: Node

func _check(ok: bool, msg: String) -> void:
	if not ok:
		print("FAIL " + msg)
		fails += 1

func _initialize() -> void:
	OS.add_logger(logger)
	Engine.physics_ticks_per_second = RATE
	_run.call_deferred()

func _run() -> void:
	# The special vehicles borrow the coupe body until their body steps and are
	# driven by tests/car/special_s0.gd.
	for k in PlayerCars.sprint_ids():
		await _drive(k)
	OS.set_environment("NEON_CAR", "")
	_finish()

func _drive(kind: String) -> void:
	OS.set_environment("NEON_CAR", kind)
	_check(PlayerCar.chassis_kind() == kind, "NEON_CAR=%s should pick that car, got %s" % [kind, PlayerCar.chassis_kind()])
	var errors_before := logger.errors.size()
	game = Harness.boot(self, 0, 150.0, 7, 1.0e6)
	for i in RATE * 2:
		await physics_frame
	var p: PlayerCar = game.get("player")
	_check(p != null, "%s: the game has no player" % kind)
	if p == null:
		return
	var info := PlayerCars.info(kind)
	var want := CarSpec.player_spec(kind)
	_check(absf(float(p.spec.max_torque) - float(want.max_torque)) < 0.5 and absf(float(p.spec.vehicle_mass) - float(want.vehicle_mass)) < 0.5,
		"%s: spec is %s Nm / %s kg, player_spec says %s / %s" % [kind, p.spec.max_torque, p.spec.vehicle_mass, want.max_torque, want.vehicle_mass])
	_check(absf(PlayerCars.peak_torque(want) - float(info.nm)) < 1.0 and absf(float(want.vehicle_mass) - float(info.kg)) < 0.5,
		"%s: PlayerCars.KINDS says %d Nm / %d kg, player_spec %.1f (peak) / %s" % [kind, info.nm, info.kg, PlayerCars.peak_torque(want), want.vehicle_mass])
	# body and wheels
	var cfg := PlayerCar.wheel_config(kind)
	if p.chassis_visual != null:
		_check(String(p.chassis_visual.get_meta("kind", "")) == kind, "%s: the body is %s" % [kind, p.chassis_visual.get_meta("kind", "")])
	var lift := -float(cfg.get("rest_y", -P1CoupeBuilder.BODY_LIFT))
	var y := p.global_position.y
	print("player_cars: %s settles at y = %.3f (rest_y %.3f)" % [kind, y, -lift])
	_check(absf(y + lift) < 0.03, "%s settles at y %.3f, the body is drawn for %.3f" % [kind, y, -lift])
	for w in p.wheel_array:
		var hub := p.to_local(w.wheel_node.global_position)
		_check(absf(absf(hub.x) - float(cfg.wheel_x)) < 0.01 and absf(absf(hub.z) - float(cfg.axle_z)) < 0.01,
			"%s wheel hub at %s, the sheet draws it at x +-%.2f, z +-%.2f" % [kind, hub, cfg.wheel_x, cfg.axle_z])
	_check(p.global_transform.basis.y.y > 0.99, "%s does not stand upright" % kind)
	# drive
	# Lane position in road space (RoadFrame.unroll: curves and hills are on by default).
	var lane := RoadFrame.unroll(p.global_position).x
	var z0 := RoadFrame.unroll(p.global_position).z
	p.driver = Harness.lane_driver(lane, 1.0, CAP_KMH / 3.6)
	var t := 0.0
	var vmax := 0.0
	var t100 := -1.0
	var max_err := 0.0
	var err_at := ""
	while t < DRIVE_SECS:
		await physics_frame
		t += 1.0 / RATE
		vmax = maxf(vmax, p.current_speed())
		if t100 < 0.0 and p.current_speed() >= 100.0 / 3.6:
			t100 = t
		if t > 3.0:
			var e := absf(RoadFrame.unroll(p.global_position).x - lane)
			if e > max_err:
				max_err = e
				err_at = "t %.1f s, %.0f km/h, gear %d" % [t, Harness.kmh(p.current_speed()), p.current_gear]
	p.driver = Callable()
	var travel := z0 - RoadFrame.unroll(p.global_position).z
	print("player_cars: %s 0-100 km/h %.1f s, %.0f km/h in %.0f s (cap %.0f), %.0f m, gear %d, lane error %.2f m (%s)" % [
		kind, t100, Harness.kmh(vmax), DRIVE_SECS, CAP_KMH, travel, p.current_gear, max_err, err_at])
	_check(t100 > 0.0 and t100 <= float(T100_MAX[kind]), "%s took %.1f s to 100 km/h (ceiling %.0f)" % [kind, t100, T100_MAX[kind]])
	_check(travel > 20.0, "%s moved %.1f m in %.0f s" % [kind, travel, DRIVE_SECS])
	_check(Harness.kmh(vmax) >= float(FLOOR_KMH[kind]), "%s only reached %.0f km/h (floor %.0f)" % [kind, Harness.kmh(vmax), FLOOR_KMH[kind]])
	_check(max_err < 1.0, "%s wandered %.2f m off its lane" % [kind, max_err])
	_check(Harness.finite(p), "%s has non-finite state" % kind)
	_check(p.global_transform.basis.y.y > 0.95, "%s is not upright after the drive" % kind)
	_check(logger.errors.size() == errors_before, "%s: %d error(s) logged: %s" % [kind, logger.errors.size() - errors_before, logger.errors.slice(errors_before)])
	# the Tuner's Stock is this car
	var ts: Variant = game.find_children("*", "TunerScreen", true, false)
	if ts is Array and not (ts as Array).is_empty():
		var model: Variant = (ts as Array)[0].get("model")
		if model != null and model.get("stock") != null:
			_check(absf(float(model.stock.max_torque) - float(want.max_torque)) < 0.5, "%s: the Tuner's Stock is %s Nm, want %s" % [kind, model.stock.max_torque, want.max_torque])
	game.queue_free()
	await physics_frame
	await physics_frame

func _finish() -> void:
	print("player_cars: %d warning(s)" % logger.warnings)
	if fails == 0:
		print("PASS player_cars")
		quit(0)
	else:
		print("FAIL player_cars: %d check(s)" % fails)
		quit(1)
