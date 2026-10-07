class_name TuneParams
extends RefCounted

# The list of CarSpec fields the tuner can change, with their absolute limits.
# Raw tuning and Auto-Tune both go through CarSpec.set_param() with a path from
# here, so there is one write path, and one place that knows how to keep the
# typed gear array and the derived values (tire cache, brake force) right.
#
# Path syntax: "key" for a plain field, "key/2" for an array element, "key/Road"
# for a dictionary entry. Only the "Road" tire entries are tunable; Dirt and
# Grass stay as the spec has them.
#
# Auto-Tune v1 fields only (decided 2026-10-05): gearing, aero, brakes and the
# Road tire keys. Engine and suspension join later, with tier caps.
#
# min..max are the safe ranges (no spin), adv_min..adv_max the hard limits set_param
# clamps to (see ADVANCED). Neither is a tier limit.

const NONE := ""
const TIRE := "tire"      # Road tire entries: wheels cache them per surface
const BRAKE := "brake"    # max_brake_force is derived from friction and the multiplier
const ENGINE := "engine"  # max_clutch_torque and the torque curve are derived from these
const TYRE_SETUP := "tyre_setup"  # pressure and camber are pushed onto the wheels (Vehicle.apply_tyre_setup)
const SUSPENSION := "suspension"  # spring/damper/ARB rates, toe, steering geometry, diff and brake split (Vehicle.apply_suspension)

# "auto": Auto-Tune may change it. The engine entries are raw-panel only until
# engine tuning joins Auto-Tune (with tier caps).
# "on_car": the value is also a property of the Vehicle. The torque shape is not:
# it lives only in the spec and CarSpec turns it into the Vehicle's torque_curve.
static var _entries: Array[Dictionary] = []

## Hard limits for the Advanced page (settings safety part 2, 2026-10-07; plan
## in docs/planning/settings-safety-design-2026-10-07.md, signed off by Roy).
## "min"/"max" stay the SAFE range: no setting at either end spins the car, and
## Auto-Tune, presets and the simple pages stay inside it. "adv_min"/"adv_max"
## are where set_param() clamps: the fun extremes. A value is cut off only where
## the test track showed the car flips, never reaches 100 km/h, or goes
## non-finite; values that only spin it or make it slow stay in (shown red).
## Paths not listed here have adv = safe.
const ADVANCED := {
	"final_drive": [2.0, 7.0],
	"gear_ratios/0": [0.5, 5.0],  # 0.3 never reaches 100 km/h; 0.5 does
	"gear_ratios/1": [0.5, 5.0],
	"gear_ratios/2": [0.5, 5.0],
	"gear_ratios/3": [0.5, 5.0],
	"gear_ratios/4": [0.5, 5.0],
	"max_torque": [150.0, 1500.0],  # 120 never reaches 100 km/h
	"max_rpm": [3500.0, 13000.0],  # 2500 never reaches 100 km/h
	"turbo_boost_max": [0.0, 3.0],
	"torque_shape/low_end": [0.0, 1.0],
	"torque_shape/peak_pos": [0.05, 1.0],
	"torque_shape/plateau": [0.0, 1.0],
	"torque_shape/falloff": [0.2, 1.5],  # 0.1 tops out at 99.5 km/h
	"aero_downforce_coefficient_front": [0.0, 2.5],
	"aero_downforce_coefficient_rear": [0.0, 3.0],
	"brake_force_multiplier": [0.5, 6.0],
	"tire_stiffnesses/Road": [4.0, 20.0],
	"coefficient_of_friction/Road": [0.5, 3.5],
	"longitudinal_grip_ratio/Road": [0.45, 2.0],  # 0.3 flips the car on launch
	"front_tyre_pressure": [1.0, 3.6],
	"rear_tyre_pressure": [1.0, 3.6],
	"front_static_camber": [-8.0, 3.0],
	"rear_static_camber": [-8.0, 3.0],
	"front_toe": [-0.06, 0.06],
	"rear_toe": [-0.03, 0.05],  # toe-out spins it: allowed, red
	"front_spring_length": [0.08, 0.40],
	"rear_spring_length": [0.08, 0.40],
	"front_resting_ratio": [0.15, 1.0],
	"rear_resting_ratio": [0.15, 1.0],
	"front_damping_ratio": [0.1, 1.5],
	"rear_damping_ratio": [0.1, 1.5],
	"front_arb_ratio": [0.0, 1.2],
	"rear_arb_ratio": [0.0, 1.2],
	"front_locking_differential_engage_torque": [0.0, 3000.0],
	"rear_locking_differential_engage_torque": [0.0, 3000.0],  # 5000 flipped once
	"front_brake_bias": [-1.0, 0.95],  # set_param keeps 0..0.2 out (see BIAS_MIN)
	"max_steering_angle": [0.349066, 1.047198],  # 20-60 deg
	"front_abs_spin_difference_threshold": [4.0, 100.0],
	"rear_abs_spin_difference_threshold": [4.0, 100.0],
}
## A set brake bias below this is raised to it; below 0 means Auto (-1).
const BIAS_MIN := 0.2

static func _e(path: String, label: String, lo: float, hi: float, rederive := NONE, auto := true, on_car := true) -> Dictionary:
	var adv: Array = ADVANCED.get(path, [lo, hi])
	return {"path": path, "label": label, "min": lo, "max": hi, "adv_min": adv[0], "adv_max": adv[1],
		"rederive": rederive, "auto": auto, "on_car": on_car}

static func all() -> Array[Dictionary]:
	if _entries.is_empty():
		_entries.append(_e("final_drive", "Final drive", 2.5, 5.5))
		for i in 5:
			_entries.append(_e("gear_ratios/%d" % i, "Gear %d" % (i + 1), 0.5, 4.5))
		_entries.append(_e("max_torque", "Peak torque Nm", 150.0, 900.0, ENGINE, false))
		_entries.append(_e("max_rpm", "Redline rpm", 4000.0, 10000.0, ENGINE, false))
		_entries.append(_e("turbo_boost_max", "Turbo boost bar", 0.0, 1.5, ENGINE, false, true))
		_entries.append(_e("torque_shape/low_end", "Low-end torque", 0.1, 0.9, ENGINE, false, false))
		_entries.append(_e("torque_shape/peak_pos", "Peak position", 0.25, 0.95, ENGINE, false, false))
		_entries.append(_e("torque_shape/plateau", "Plateau width", 0.0, 0.5, ENGINE, false, false))
		_entries.append(_e("torque_shape/falloff", "Torque at redline", 0.2, 1.0, ENGINE, false, false))
		# Exhaust (cosmetic, never Auto-Tune). In all() so tune slots store them;
		# not on the car: EngineAudio reads them from the spec.
		for k in ExhaustTune.KEYS:
			_entries.append(_e("exhaust/" + k, k.capitalize(), 0.0, 1.0, NONE, false, false))
		_entries.append(_e("coefficient_of_drag", "Drag coefficient", 0.20, 0.40))
		_entries.append(_e("aero_downforce_coefficient_front", "Downforce front", 0.0, 1.0))
		_entries.append(_e("aero_downforce_coefficient_rear", "Downforce rear", 0.0, 1.2))
		_entries.append(_e("brake_force_multiplier", "Brake force", 1.0, 3.0, BRAKE))
		_entries.append(_e("tire_stiffnesses/Road", "Tire stiffness", 6.0, 14.0, TIRE))
		_entries.append(_e("coefficient_of_friction/Road", "Tire friction", 1.0, 2.5, TIRE))
		_entries.append(_e("lateral_grip_assist/Road", "Lateral grip assist", 0.0, 0.2, TIRE))
		_entries.append(_e("longitudinal_grip_ratio/Road", "Longitudinal grip", 0.5, 1.2, TIRE))
		# Tuner redesign PR 1: not Auto-Tune until the calibration sweep has run
		# with it (proposal section 9).
		_entries.append(_e("front_tyre_pressure", "Tyre pressure front bar", 1.6, 2.8, TYRE_SETUP, false))
		_entries.append(_e("rear_tyre_pressure", "Tyre pressure rear bar", 1.6, 2.8, TYRE_SETUP, false))
		_entries.append(_e("front_static_camber", "Camber front deg", -4.0, 1.0, TYRE_SETUP, false))
		_entries.append(_e("rear_static_camber", "Camber rear deg", -4.0, 1.0, TYRE_SETUP, false))
		# Tuner redesign PR 2: chassis settings, raw-panel only like PR 1's.
		# Ranges are what the test track showed safe on the coupe (2026-10-06):
		# rear toe-out, no front bar, a stiff rear bar and a stiff or tall rear
		# end each spun the car (30-70 deg slip) and are cut off. The rear is touchy:
		# springs past 0.55 or ride height past 0.27 m already slide it.
		# tests/tuner_settings.gd drives every one of them at both ends.
		_entries.append(_e("front_toe", "Toe front rad", -0.02, 0.02, SUSPENSION, false))
		_entries.append(_e("rear_toe", "Toe rear rad", 0.0, 0.02, SUSPENSION, false))
		_entries.append(_e("front_spring_length", "Ride height front m", 0.16, 0.28, SUSPENSION, false))
		_entries.append(_e("rear_spring_length", "Ride height rear m", 0.18, 0.27, SUSPENSION, false))
		_entries.append(_e("front_resting_ratio", "Springs front (soft-stiff)", 0.3, 0.7, SUSPENSION, false))
		_entries.append(_e("rear_resting_ratio", "Springs rear (soft-stiff)", 0.3, 0.55, SUSPENSION, false))
		_entries.append(_e("front_damping_ratio", "Dampers front", 0.25, 0.9, SUSPENSION, false))
		_entries.append(_e("rear_damping_ratio", "Dampers rear", 0.25, 0.9, SUSPENSION, false))
		_entries.append(_e("front_arb_ratio", "Anti-roll bar front", 0.1, 0.6, SUSPENSION, false))
		_entries.append(_e("rear_arb_ratio", "Anti-roll bar rear", 0.0, 0.45, SUSPENSION, false))
		_entries.append(_e("front_locking_differential_engage_torque", "Diff lock front Nm (low = locked)", 0.0, 1000.0, SUSPENSION, false))
		_entries.append(_e("rear_locking_differential_engage_torque", "Diff lock rear Nm (low = locked)", 0.0, 1000.0, SUSPENSION, false))
		_entries.append(_e("front_brake_bias", "Brake bias front (-1 auto)", -1.0, 0.8, SUSPENSION, false))
		_entries.append(_e("max_steering_angle", "Steering lock rad", deg_to_rad(30.0), deg_to_rad(50.0), SUSPENSION, false))
		_entries.append(_e("traction_control_max_slip", "Traction control slip (0 off)", 0.0, 20.0, NONE, false))
		_entries.append(_e("stability_yaw_strength", "Stability strength", 0.0, 12.0, NONE, false))
		_entries.append(_e("front_abs_spin_difference_threshold", "ABS front threshold", 4.0, 40.0, SUSPENSION, false))
		_entries.append(_e("rear_abs_spin_difference_threshold", "ABS rear threshold", 4.0, 40.0, SUSPENSION, false))
	return _entries

## The paths Auto-Tune is allowed to change.
static func auto_paths() -> Array[String]:
	var out: Array[String] = []
	for e in all():
		if e.auto:
			out.append(e.path)
	return out

## The exhaust paths ("exhaust/loudness" ...): cosmetic, never Auto-Tune.
static func exhaust_paths() -> Array[String]:
	var out: Array[String] = []
	for k in ExhaustTune.KEYS:
		out.append("exhaust/" + k)
	return out

## The entry for a path, or an empty dictionary if it is not tunable.
static func find(path: String) -> Dictionary:
	for e in all():
		if e.path == path:
			return e
	return {}

## Reads a path from a spec Dictionary or a live Vehicle.
static func get_value(target: Variant, path: String) -> float:
	var parts := path.split("/")
	var field = _read(target, parts[0])
	if parts.size() == 1:
		return field
	return field[int(parts[1])] if field is Array else field[parts[1]]

## Writes a path into a spec Dictionary or a live Vehicle. In place for arrays
## and dictionaries, so a typed Array[float] stays typed.
static func set_value(target: Variant, path: String, value: float) -> void:
	var parts := path.split("/")
	if parts.size() == 1:
		if target is Dictionary:
			target[parts[0]] = value
		else:
			target.set(parts[0], value)
		return
	var field = _read(target, parts[0])
	if field is Array:
		field[int(parts[1])] = value
	else:
		field[parts[1]] = value

static func _read(target: Variant, key: String) -> Variant:
	return target[key] if target is Dictionary else target.get(key)
