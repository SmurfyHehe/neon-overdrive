extends SceneTree

# Chassis settings for the tuner (Tuner redesign PR 2, 2026-10-06): toe, ride
# height, springs, dampers, anti-roll bars, diff lock, brake bias, steering lock,
# traction control, stability and ABS. Checks:
# - stock: the coupe's spec with these keys is bit-identical on the test track to
#   the spec without them (they were GEVP defaults before; no car's feel moved)
# - live re-derive: every SUSPENSION setting changed on a running car leaves it
#   with the same wheel and axle numbers as a car built fresh from that spec
# - extremes: every new setting at both ends of its range finishes the test track
#   runs, finite, unflipped, without spinning (MAX_SLIP) or losing over 10% top
#   speed. Prints how far each end moves each metric.
# Run (tests/run_tests.bat does):
#   Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path . -s res://tests/tuner_settings.gd
# Exit code 1 on failure.

const NEW_PATHS := ["front_toe", "rear_toe", "front_spring_length", "rear_spring_length",
	"front_resting_ratio", "rear_resting_ratio", "front_damping_ratio", "rear_damping_ratio",
	"front_arb_ratio", "rear_arb_ratio", "front_locking_differential_engage_torque",
	"rear_locking_differential_engage_torque", "front_brake_bias", "max_steering_angle",
	"traction_control_max_slip", "stability_yaw_strength",
	"front_abs_spin_difference_threshold", "rear_abs_spin_difference_threshold"]
# Keys added to the spec in this PR (the others above were in it already).
const ADDED_KEYS := ["front_resting_ratio", "rear_resting_ratio", "front_toe", "rear_toe",
	"front_locking_differential_engage_torque", "rear_locking_differential_engage_torque",
	"front_brake_bias", "traction_control_max_slip", "stability_yaw_strength",
	"front_abs_spin_difference_threshold", "rear_abs_spin_difference_threshold"]
const WHEEL_FIELDS := ["spring_length", "max_spring_length", "spring_rate", "antiroll", "slow_bump",
	"slow_rebound", "fast_bump", "fast_rebound", "toe", "ackermann", "abs_spin_difference_threshold", "target_position"]
## No setting at either end may spin the car on the track (stock is ~11 deg).
const MAX_SLIP := 25.0
const METRICS := ["top_speed_kmh", "t_0_100", "brake_dist_100", "peak_lat_g", "max_slip_deg"]

var failures: Array[String] = []

func _initialize() -> void:
	await process_frame
	var base := CarSpec.coupe_default()
	for p in NEW_PATHS:
		_check(not TuneParams.find(p).is_empty(), "%s is not a TuneParams path" % p)

	# --- stock identity ---
	var legacy := CarSpec.clone_spec(base)
	for k in ADDED_KEYS:
		legacy.erase(k)
	var track := _new_track()
	var pair: Array = await track.evaluate([base, legacy])
	track.queue_free()
	_check(_same(pair[0], pair[1]), "adding the stock values changed the car:\n  now    %s\n  before %s" % [_fmt(pair[0]), _fmt(pair[1])])

	# --- live re-derive vs fresh build ---
	var live := PlayerCar.new()
	live.sim_only = true
	root.add_child(live)
	await physics_frame
	await physics_frame
	for p in NEW_PATHS:
		var e := TuneParams.find(p)
		CarSpec.set_param(live, live.spec, p, lerpf(e.min, e.max, 0.7))
	var fresh := PlayerCar.new()
	fresh.sim_only = true
	fresh.spec = CarSpec.clone_spec(live.spec)
	root.add_child(fresh)
	await physics_frame
	for i in live.wheel_array.size():
		var a: Wheel = live.wheel_array[i]
		var b: Wheel = fresh.wheel_array[i]
		for f in WHEEL_FIELDS:
			var va = a.get(f)
			var vb = b.get(f)
			var same: bool = va.is_equal_approx(vb) if va is Vector3 else is_equal_approx(float(va), float(vb))
			_check(same, "wheel %d %s: live %s, fresh %s" % [i, f, str(va), str(vb)])
	for axle in [["front", live.front_axle, fresh.front_axle], ["rear", live.rear_axle, fresh.rear_axle]]:
		_check(is_equal_approx(axle[1].brake_bias, axle[2].brake_bias), "%s brake bias: live %f, fresh %f" % [axle[0], axle[1].brake_bias, axle[2].brake_bias])
		_check(is_equal_approx(axle[1].differential_lock_torque, axle[2].differential_lock_torque), "%s diff lock differs" % axle[0])
	_check(is_equal_approx(live.max_brake_force, fresh.max_brake_force), "max brake force: live %f, fresh %f" % [live.max_brake_force, fresh.max_brake_force])
	live.queue_free()
	fresh.queue_free()

	# --- extremes ---
	var specs: Array = [base]
	var labels: Array[String] = ["stock"]
	for p in NEW_PATHS:
		var e := TuneParams.find(p)
		for end in ["min", "max"]:
			var s := CarSpec.clone_spec(base)
			TuneParams.set_value(s, p, e[end])
			specs.append(s)
			labels.append("%s %s" % [p, end])
	track = _new_track()
	var res: Array = await track.evaluate(specs)
	track.queue_free()
	print("%-48s %8s %7s %7s %6s %6s" % ["setting", "top", "0-100", "100-0", "lat g", "slip"])
	for i in res.size():
		var r: Dictionary = res[i]
		print("%-48s %8.1f %7.2f %7.1f %6.3f %6.1f" % [labels[i], r.get("top_speed_kmh", NAN), r.get("t_0_100", NAN), r.get("brake_dist_100", NAN), r.get("peak_lat_g", NAN), r.get("max_slip_deg", NAN)])
		_check(r.ok, "%s: %s" % [labels[i], str(r.problems)])
		_check(float(r.get("max_slip_deg", 99.0)) < MAX_SLIP, "%s spins the car (%.0f deg slip)" % [labels[i], r.get("max_slip_deg", NAN)])
		_check(float(r.get("top_speed_kmh", 0.0)) > res[0].top_speed_kmh * 0.9, "%s costs over 10%% top speed" % labels[i])

	print("tuner_settings: %s" % ("PASS" if failures.is_empty() else "FAIL (%d)" % failures.size()))
	for f in failures:
		print("  ", f)
	quit(0 if failures.is_empty() else 1)

func _new_track() -> TuneTrack:
	var track := TuneTrack.new()
	root.add_child(track)
	return track

func _fmt(r: Dictionary) -> String:
	return "top %.1f, 0-100 %.2f, 100-0 %.1f, lat %.3f" % [r.get("top_speed_kmh", NAN), r.get("t_0_100", NAN), r.get("brake_dist_100", NAN), r.get("peak_lat_g", NAN)]

func _same(a: Dictionary, b: Dictionary) -> bool:
	for m in METRICS:
		if a.get(m) != b.get(m):
			return false
	return true

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
		print("FAIL ", msg)
