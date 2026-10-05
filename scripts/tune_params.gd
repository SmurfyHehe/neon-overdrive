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
# Ranges are absolute sanity limits, not tier limits. Gearing, drag and the
# tire entries are provisional until the test track (tests/) has swept them.

const NONE := ""
const TIRE := "tire"      # Road tire entries: wheels cache them per surface
const BRAKE := "brake"    # max_brake_force is derived from friction and the multiplier
const ENGINE := "engine"  # max_clutch_torque and the torque curve are derived from these

# "auto": Auto-Tune may change it. The engine entries are raw-panel only until
# engine tuning joins Auto-Tune (with tier caps).
# "on_car": the value is also a property of the Vehicle. The torque shape is not:
# it lives only in the spec and CarSpec turns it into the Vehicle's torque_curve.
static var _entries: Array[Dictionary] = []

static func _e(path: String, label: String, lo: float, hi: float, rederive := NONE, auto := true, on_car := true) -> Dictionary:
	return {"path": path, "label": label, "min": lo, "max": hi, "rederive": rederive, "auto": auto, "on_car": on_car}

static func all() -> Array[Dictionary]:
	if _entries.is_empty():
		_entries.append(_e("final_drive", "Final drive", 2.5, 5.5))
		for i in 5:
			_entries.append(_e("gear_ratios/%d" % i, "Gear %d" % (i + 1), 0.5, 4.5))
		_entries.append(_e("max_torque", "Peak torque Nm", 150.0, 900.0, ENGINE, false))
		_entries.append(_e("max_rpm", "Redline rpm", 4000.0, 10000.0, ENGINE, false))
		_entries.append(_e("torque_shape/low_end", "Low-end torque", 0.1, 0.9, ENGINE, false, false))
		_entries.append(_e("torque_shape/peak_pos", "Peak position", 0.25, 0.95, ENGINE, false, false))
		_entries.append(_e("torque_shape/plateau", "Plateau width", 0.0, 0.5, ENGINE, false, false))
		_entries.append(_e("torque_shape/falloff", "Torque at redline", 0.2, 1.0, ENGINE, false, false))
		_entries.append(_e("coefficient_of_drag", "Drag coefficient", 0.20, 0.40))
		_entries.append(_e("aero_downforce_coefficient_front", "Downforce front", 0.0, 1.0))
		_entries.append(_e("aero_downforce_coefficient_rear", "Downforce rear", 0.0, 1.2))
		_entries.append(_e("brake_force_multiplier", "Brake force", 0.7, 1.5, BRAKE))
		_entries.append(_e("tire_stiffnesses/Road", "Tire stiffness", 6.0, 14.0, TIRE))
		_entries.append(_e("coefficient_of_friction/Road", "Tire friction", 2.0, 4.0, TIRE))
		_entries.append(_e("lateral_grip_assist/Road", "Lateral grip assist", 0.0, 0.2, TIRE))
		_entries.append(_e("longitudinal_grip_ratio/Road", "Longitudinal grip", 0.35, 0.7, TIRE))
	return _entries

## The paths Auto-Tune is allowed to change.
static func auto_paths() -> Array[String]:
	var out: Array[String] = []
	for e in all():
		if e.auto:
			out.append(e.path)
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
