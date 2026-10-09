class_name TunerModel
extends RefCounted

# The player-facing Tuner (Tuner redesign PR 3, 2026-10-06; proposal in
# docs/planning/tuner-redesign-proposal-2026-10-06.md, approved by Roy).
#
# This file is the data and maths, no UI: the pages, every setting as an
# 11-notch bar or a short list of choices in words players know, the four
# presets, and the stat estimates. TunerScreen draws it. Every write goes through
# CarSpec.set_param(), the same single write path the raw tuner and Auto-Tune use,
# so ranges, clamping and the live re-derive (PR 1 and 2) all still apply.
#
# Presets and choices are offsets from the car's STOCK spec, so they work on
# every player car, not only the coupe.

const NOTCHES := 11

## Coupe numbers measured on the hidden test track (tests/tuning/tune_track.gd,
## 2026-10-06). The estimates are scaled so the stock coupe reads these.
const COUPE_MEASURED := {"top": 244.1, "accel": 5.60, "brake": 42.7, "grip": 1.296}

const PRESETS := ["Stock", "Street", "Grip", "Drift"]

## Share of engine power left at the wheels for the top speed estimate: 0.7 puts
## the stock coupe just under its rev cut, drag-limited, as it is on the track.
const TOP_POWER_SHARE := 0.7

var car: Vehicle
var spec: Dictionary
var stock: Dictionary
## The preset last picked, and whether anything changed since.
var preset := "Stock"
var modified := false

static var _calib := {}

func _init(target: Vehicle, target_spec: Dictionary, stock_spec: Dictionary) -> void:
	car = target
	spec = target_spec
	stock = stock_spec

# ---------- pages ----------

## Each page: {id, title, settings}. Setting kinds:
##   "range"  : one or more paths on one bar; notch 0..10 maps lo..hi (or hi..lo
##              with invert). lo_word / hi_word are the words at the ends.
##   "choice" : named options, each a function of the stock spec giving
##              {path: value}. Shown as one word; Left/Right step through them.
## Pages without settings (Setup, Mechanic, Exhaust, Advanced) are drawn by the screen.
static func pages() -> Array:
	return [
		{"id": "setup", "title": "Setup", "settings": []},
		{"id": "tyres", "title": "Tyres", "settings": [
			_choice("compound", "Compound", ["Street", "Sport", "Semi-slick"], "Softer rubber grips harder but is touchier at the limit. Sport is how the car left the factory."),
			_range("front_tyre_pressure", "Pressure front", ["front_tyre_pressure"], 1.6, 2.8, "Low", "High", "Lower: a longer, softer contact patch. Higher: sharper response and a little less drag. Far from stock either way loses grip.", "bar"),
			_range("rear_tyre_pressure", "Pressure rear", ["rear_tyre_pressure"], 1.6, 2.8, "Low", "High", "Lower: a longer, softer contact patch. Higher: sharper response and a little less drag. Far from stock either way loses grip.", "bar"),
			_range("front_static_camber", "Camber front", ["front_static_camber"], -4.0, 1.0, "Neg", "Pos", "Some negative camber keeps the outside tyre flat in a corner. Too much and the tyre stands on its edge when you launch and brake.", "deg"),
			_range("rear_static_camber", "Camber rear", ["rear_static_camber"], -4.0, 1.0, "Neg", "Pos", "Some negative camber keeps the outside tyre flat in a corner. Too much and the tyre stands on its edge when you launch and brake.", "deg"),
			_range("front_toe", "Toe front", ["front_toe"], -0.02, 0.02, "Out", "In", "Toe-out sharpens turn-in but wanders on the straight. Toe-in settles it.", "toe"),
			_range("rear_toe", "Toe rear", ["rear_toe"], 0.0, 0.02, "Zero", "In", "Rear toe-in keeps the back planted. Less of it lets the rear rotate.", "toe"),
		]},
		{"id": "suspension", "title": "Suspension", "settings": [
			_range("front_spring_length", "Ride height front", ["front_spring_length"], 0.16, 0.28, "Low", "High", "Lower: less body roll and a lower centre of gravity, but less travel over bumps.", "cm"),
			_range("rear_spring_length", "Ride height rear", ["rear_spring_length"], 0.18, 0.27, "Low", "High", "Lower: less body roll and a lower centre of gravity, but less travel over bumps.", "cm"),
			_range("front_resting_ratio", "Springs front", ["front_resting_ratio"], 0.3, 0.7, "Soft", "Stiff", "Stiffer front springs: sharper turn-in and less roll, but the front washes wide sooner. Moves balance toward understeer.", ""),
			_range("rear_resting_ratio", "Springs rear", ["rear_resting_ratio"], 0.3, 0.55, "Soft", "Stiff", "Stiffer rear springs: the rear steps out sooner. Moves balance toward oversteer.", ""),
			_range("front_damping_ratio", "Dampers front", ["front_damping_ratio"], 0.25, 0.9, "Soft", "Firm", "Firmer dampers: the car settles faster after a bump or a weight shift, but skips over rough road.", ""),
			_range("rear_damping_ratio", "Dampers rear", ["rear_damping_ratio"], 0.25, 0.9, "Soft", "Firm", "Firmer dampers: the car settles faster after a bump or a weight shift, but skips over rough road.", ""),
			_range("front_arb_ratio", "Anti-roll bar front", ["front_arb_ratio"], 0.1, 0.6, "Soft", "Stiff", "A stiffer front bar: less roll, more understeer.", ""),
			_range("rear_arb_ratio", "Anti-roll bar rear", ["rear_arb_ratio"], 0.0, 0.45, "Soft", "Stiff", "A stiffer rear bar: less roll, more oversteer.", ""),
		]},
		{"id": "gearbox", "title": "Gearbox", "settings": [
			_range("gearing", "Gearing", ["final_drive"], 2.5, 5.5, "Short", "Long", "Shorter gearing: harder acceleration, lower top speed. Longer: the opposite.", "fd", true),
		]},
		{"id": "engine", "title": "Engine", "settings": [
			_range("turbo_boost_max", "Boost", ["turbo_boost_max"], 0.0, 1.5, "None", "Max", "Turbo boost pressure. More boost, more power once the turbo spools up.", "bar"),
			_choice("power_band", "Power band", ["Low-end", "Balanced", "Top-end"], "Where the engine makes its torque. Low-end pulls out of corners; top-end pays off near the redline."),
		]},
		{"id": "diff", "title": "Differential", "settings": [
			_range("diff_lock", "Diff lock", ["rear_locking_differential_engage_torque"], 0.0, 1000.0, "Open", "Locked", "A locked diff drives both rear wheels together: better traction out of a corner, easier slides, more push on the way in.", "diff", true),
		]},
		{"id": "brakes", "title": "Brakes", "settings": [
			_range("brake_force_multiplier", "Brake pressure", ["brake_force_multiplier"], 1.0, 3.0, "Soft", "Hard", "More pressure stops harder until the tyres lock; past that, ABS does the work.", "x"),
			_choice("bias_mode", "Bias mode", ["Auto", "Manual"], "Auto splits the braking from the springs, as the factory does. Manual lets you set the split yourself."),
			_range("front_brake_bias", "Brake bias", ["front_brake_bias"], 0.45, 0.75, "Rear", "Front", "More front bias is stable under braking. More rear bias helps the car rotate into a corner, and can spin it.", "bias"),
		]},
		{"id": "aero", "title": "Aero", "settings": [
			_range("aero_downforce_coefficient_front", "Front downforce", ["aero_downforce_coefficient_front"], 0.0, 1.0, "Low", "High", "More front downforce: more front grip at speed. Adds a little drag.", ""),
			_range("aero_downforce_coefficient_rear", "Rear wing", ["aero_downforce_coefficient_rear"], 0.0, 1.2, "Low", "High", "More rear wing: a planted rear at speed, but more drag and less top speed.", ""),
		]},
		{"id": "assists", "title": "Assists", "settings": [
			_choice("traction", "Traction control", ["Off", "Low", "High"], "Cuts power when the rear wheels spin. Off lets you slide."),
			_choice("abs", "ABS", ["Off", "On"], "Stops the wheels locking under hard braking."),
			_choice("stability", "Stability", ["Off", "Low", "High"], "Catches the car when it starts to spin."),
			_range("max_steering_angle", "Steering lock", ["max_steering_angle"], deg_to_rad(30.0), deg_to_rad(50.0), "Less", "More", "More lock turns tighter and catches bigger slides, but makes the car twitchy.", "rad_deg"),
		]},
		{"id": "mechanic", "title": "Mechanic", "settings": []},
		{"id": "exhaust", "title": "Exhaust", "settings": []},
		{"id": "advanced", "title": "Advanced", "settings": []},
	]

static func _range(id: String, label: String, paths: Array, lo: float, hi: float, lo_word: String, hi_word: String, hint: String, unit: String, invert := false) -> Dictionary:
	return {"id": id, "kind": "range", "label": label, "paths": paths, "lo": lo, "hi": hi,
		"lo_word": lo_word, "hi_word": hi_word, "hint": hint, "unit": unit, "invert": invert}

static func _choice(id: String, label: String, options: Array, hint: String) -> Dictionary:
	return {"id": id, "kind": "choice", "label": label, "options": options, "hint": hint}

static func page(id: String) -> Dictionary:
	for p in pages():
		if p.id == id:
			return p
	return {}

# ---------- reading and writing one setting ----------

func notch(s: Dictionary) -> int:
	if s.kind == "choice":
		return choice_index(s)
	var v := _range_value(s)
	var t := clampf((v - s.lo) / (s.hi - s.lo), 0.0, 1.0)
	if s.invert:
		t = 1.0 - t
	return roundi(t * (NOTCHES - 1))

## Moves a setting by `step` notches (or choices). Returns true if it changed.
func nudge(s: Dictionary, step: int) -> bool:
	if s.kind == "choice":
		var n: int = s.options.size()
		var i := choice_index(s)
		var to := clampi((i if i >= 0 else _default_choice(s)) + step, 0, n - 1)
		if to == i:
			return false
		set_choice(s, to)
		return true
	var cur := notch(s)
	var to := clampi(cur + step, 0, NOTCHES - 1)
	if to == cur and _on_notch(s):
		return false
	set_notch(s, to)
	return true

func set_notch(s: Dictionary, n: int) -> void:
	var t := float(n) / float(NOTCHES - 1)
	if s.invert:
		t = 1.0 - t
	var v := lerpf(s.lo, s.hi, t)
	for p in s.paths:
		_write(p, v)
	if s.id.begins_with("aero_downforce"):
		_drag_follows_downforce()
	_touched()

## 0-based index of the option the car is on, or -1 for none (a custom value).
func choice_index(s: Dictionary) -> int:
	if s.id == "bias_mode":
		return 0 if float(spec.get("front_brake_bias", -1.0)) < 0.0 else 1  # Manual is any set value
	for i in s.options.size():
		if _matches(choice_values(s.id, i)):
			return i
	return -1

func set_choice(s: Dictionary, i: int) -> void:
	var vals := choice_values(s.id, i)
	for p in vals:
		_write(p, vals[p])
	_touched()

## The {path: value} an option sets, worked out from the stock spec.
func choice_values(id: String, i: int) -> Dictionary:
	match id:
		"compound":
			var k: float = [0.92, 1.0, 1.1][i]
			var ks: float = [0.85, 1.0, 1.15][i]
			return {
				"coefficient_of_friction/Road": _clamp_path("coefficient_of_friction/Road", stock.coefficient_of_friction.Road * k),
				"tire_stiffnesses/Road": _clamp_path("tire_stiffnesses/Road", stock.tire_stiffnesses.Road * ks),
				"longitudinal_grip_ratio/Road": _clamp_path("longitudinal_grip_ratio/Road", stock.longitudinal_grip_ratio.Road * k),
			}
		"power_band":
			var t: Dictionary = stock.torque_shape
			var d: Array = [[0.15, -0.15, 0.0, -0.1], [0.0, 0.0, 0.0, 0.0], [-0.1, 0.1, 0.0, 0.1]][i]
			return {
				"torque_shape/low_end": _clamp_path("torque_shape/low_end", t.low_end + d[0]),
				"torque_shape/peak_pos": _clamp_path("torque_shape/peak_pos", t.peak_pos + d[1]),
				"torque_shape/plateau": _clamp_path("torque_shape/plateau", t.plateau + d[2]),
				"torque_shape/falloff": _clamp_path("torque_shape/falloff", t.falloff + d[3]),
			}
		"traction":
			# Lower allowed slip = earlier, harder intervention. Stock is "Low".
			return {"traction_control_max_slip": [0.0, float(stock.traction_control_max_slip), 4.0][i]}
		"abs":
			var off := TuneParams.find("front_abs_spin_difference_threshold").max as float
			return {"front_abs_spin_difference_threshold": [off, float(stock.front_abs_spin_difference_threshold)][i],
				"rear_abs_spin_difference_threshold": [off, float(stock.rear_abs_spin_difference_threshold)][i]}
		"bias_mode":
			# Manual starts from the split Auto was giving, so switching changes nothing yet.
			var auto_bias: float = car.front_axle.brake_bias if car != null and car.is_ready else 0.55
			return {"front_brake_bias": [-1.0, _clamp_path("front_brake_bias", snappedf(auto_bias, 0.01))][i]}
		"stability":
			return {"stability_yaw_strength": [0.0, float(stock.stability_yaw_strength) * 0.5, float(stock.stability_yaw_strength)][i]}
	return {}

func _default_choice(s: Dictionary) -> int:
	return {"compound": 1, "power_band": 1, "traction": 1, "abs": 1, "stability": 2, "bias_mode": 0}.get(s.id, 0)

func value_text(s: Dictionary) -> String:
	if s.kind == "choice":
		var i := choice_index(s)
		return s.options[i] if i >= 0 else "Custom"
	var v := _range_value(s)
	match s.unit:
		"bar": return "%.1f bar" % v
		"deg": return "%+.1f°" % v
		"toe": return "%+.2f°" % rad_to_deg(v)
		"cm": return "%d cm" % roundi(v * 100.0)
		"x": return "x%.1f" % v
		"fd": return "%.2f final" % v
		"rad_deg": return "%d°" % roundi(rad_to_deg(v))
		"diff": return "%d%% lock" % roundi(100.0 * (1.0 - clampf(v / s.hi, 0.0, 1.0)))
		"bias":
			if float(spec.get("front_brake_bias", -1.0)) < 0.0:
				return "Auto (%d%% front)" % roundi(100.0 * v)
			return "%d%% front" % roundi(100.0 * v)
	return "%d / 10" % notch(s)

func _range_value(s: Dictionary) -> float:
	var p: String = s.paths[0]
	var v := TuneParams.get_value(spec, p)
	if p == "front_brake_bias" and v < 0.0 and car != null and car.is_ready:
		v = car.front_axle.brake_bias  # "auto": what GEVP worked out from the springs
	return v

func _on_notch(s: Dictionary) -> bool:
	var t := float(notch(s)) / float(NOTCHES - 1)
	if s.invert:
		t = 1.0 - t
	return is_equal_approx(lerpf(s.lo, s.hi, t), _range_value(s))

# ---------- presets ----------

## Applies a preset: everything back to stock, then the preset's offsets.
func apply_preset(name: String) -> void:
	for e in TuneParams.all():
		if e.path.begins_with("exhaust/"):
			continue  # exhaust is cosmetic and has its own page
		_write(e.path, TuneParams.get_value(stock, e.path))
	var vals := _preset_values(name)
	for p in vals:
		_write(p, vals[p])
	if vals.has("aero_downforce_coefficient_front") or vals.has("aero_downforce_coefficient_rear"):
		_drag_follows_downforce()
	preset = name
	modified = false

## Every path a page's settings write (ranges and choices).
static func page_paths(id: String) -> Array[String]:
	var out: Array[String] = []
	var probe := TunerModel.new(null, CarSpec.coupe_default(), CarSpec.coupe_default())
	for s in page(id).get("settings", []):
		var paths: Array = s.paths if s.kind == "range" else probe.choice_values(s.id, 0).keys()
		for p in paths:
			if not out.has(p):
				out.append(p)
	if id == "aero":
		out.append("coefficient_of_drag")  # follows the wings on this page
	return out

## Puts one page's settings back to the car's stock values (settings safety
## part 4). Returns true if anything changed.
func reset_page(id: String) -> bool:
	var changed := false
	for p in page_paths(id):
		var v := TuneParams.get_value(stock, p)
		if TuneParams.get_value(spec, p) != v:
			_write(p, v)
			changed = true
	if changed:
		_touched()
	return changed

func preset_label() -> String:
	return preset + (" (modified)" if modified else "")

func _preset_values(name: String) -> Dictionary:
	var out := {}
	match name:
		"Street":
			out.merge(choice_values("compound", 0))
			out.merge(choice_values("traction", 2))
			out["front_resting_ratio"] = stock.get("front_resting_ratio", 0.5) * 0.85
			out["rear_resting_ratio"] = stock.get("rear_resting_ratio", 0.5) * 0.85
			out["front_damping_ratio"] = 0.45
			out["rear_damping_ratio"] = 0.45
			out["front_arb_ratio"] = stock.front_arb_ratio + 0.05
			out["rear_arb_ratio"] = maxf(stock.rear_arb_ratio - 0.05, 0.0)
			out["rear_locking_differential_engage_torque"] = 400.0
			out["front_tyre_pressure"] = stock.front_tyre_pressure + 0.1
			out["rear_tyre_pressure"] = stock.rear_tyre_pressure + 0.1
		"Grip":
			out.merge(choice_values("compound", 2))
			out["front_static_camber"] = -1.5
			out["rear_static_camber"] = -1.0
			out["front_resting_ratio"] = 0.6
			out["rear_resting_ratio"] = 0.5
			out["front_arb_ratio"] = 0.3
			out["rear_arb_ratio"] = 0.3
			out["aero_downforce_coefficient_front"] = stock.aero_downforce_coefficient_front + 0.2
			out["aero_downforce_coefficient_rear"] = stock.aero_downforce_coefficient_rear + 0.3
			out["rear_locking_differential_engage_torque"] = 150.0
			out["rear_toe"] = 0.015
			out.merge(choice_values("stability", 1))
		"Drift":
			# Easy slides, not a spin: the first cut (locked diff, stiff rear bar,
			# stability off) spun the coupe right round on the test track.
			out["rear_locking_differential_engage_torque"] = 100.0
			out["rear_arb_ratio"] = stock.rear_arb_ratio + 0.1
			out["front_toe"] = -0.005
			out["max_steering_angle"] = deg_to_rad(48.0)
			out["rear_tyre_pressure"] = stock.rear_tyre_pressure + 0.2
			out.merge(choice_values("traction", 0))
			out.merge(choice_values("stability", 1))
	for p in out:
		out[p] = _clamp_path(p, out[p])
	return out

# ---------- writes ----------

func _write(path: String, value: float) -> void:
	if car != null:
		CarSpec.set_param(car, spec, path, value)
	else:
		TuneParams.set_value(spec, path, _clamp_path(path, value))

func _touched() -> void:
	modified = true

## In the simple view drag follows downforce: more wing, more drag. Raw drag is
## still on the Advanced page.
func _drag_follows_downforce() -> void:
	var df := float(spec.aero_downforce_coefficient_front) - float(stock.aero_downforce_coefficient_front)
	var dr := float(spec.aero_downforce_coefficient_rear) - float(stock.aero_downforce_coefficient_rear)
	_write("coefficient_of_drag", float(stock.coefficient_of_drag) + 0.02 * df + 0.04 * dr)

func _matches(vals: Dictionary) -> bool:
	for p in vals:
		if absf(TuneParams.get_value(spec, p) - float(vals[p])) > 0.0005:
			return false
	return not vals.is_empty()

static func _clamp_path(path: String, v: float) -> float:
	var e := TuneParams.find(path)
	return clampf(v, e.min, e.max) if not e.is_empty() else v

# ---------- stat estimates ----------

## Instant estimates for the stat panel: top speed (km/h), 0-100 (s), 100-0 (m),
## peak lateral grip (g) and balance (-1 understeer .. +1 oversteer). They are
## rough physics scaled so the stock coupe reads its measured track numbers, so
## the screen shows them with "~"; a test run (PR 4) replaces them.
static func estimate(s: Dictionary) -> Dictionary:
	if _calib.is_empty():
		var raw := _raw(CarSpec.coupe_default())
		_calib = {"top": COUPE_MEASURED.top / raw.top, "accel": COUPE_MEASURED.accel / raw.accel,
			"brake": COUPE_MEASURED.brake / raw.brake, "grip": COUPE_MEASURED.grip / raw.grip}
	var r := _raw(s)
	return {"top": r.top * _calib.top, "accel": r.accel * _calib.accel, "brake": r.brake * _calib.brake,
		"grip": r.grip * _calib.grip, "balance": r.balance}

static func _raw(s: Dictionary) -> Dictionary:
	var curve := CarSpec.build_torque_curve(s.torque_shape.low_end, s.torque_shape.peak_pos, s.torque_shape.plateau, s.torque_shape.falloff)
	var max_rpm: float = s.max_rpm
	var boost_k := 1.0 + float(s.get("turbo_gain", 0.45)) * float(s.get("turbo_boost_max", 0.0)) * 0.6
	var torque := func(rpm: float) -> float: return curve.sample_baked(clampf(rpm / max_rpm, 0.0, 1.0)) * float(s.max_torque) * boost_k
	var wheel_r: float = PlayerCar.CFG.wheel_r
	var fd: float = s.final_drive
	var gears: Array = s.gear_ratios
	var mass: float = s.vehicle_mass
	var cd: float = s.coefficient_of_drag
	var area: float = s.frontal_area
	var cof: float = s.coefficient_of_friction.Road
	var pressure_k := 1.0 - 0.15 * (maxf(absf(float(s.get("front_tyre_pressure", 2.2)) - float(s.get("tyre_pressure_stock", 2.2))) - 0.1, 0.0)
		+ maxf(absf(float(s.get("rear_tyre_pressure", 2.2)) - float(s.get("tyre_pressure_stock", 2.2))) - 0.1, 0.0)) * 0.5
	var camber_lat := (Wheel.camber_lateral_curve(float(s.get("front_static_camber", 0.0)) + 1.5)
		+ Wheel.camber_lateral_curve(float(s.get("rear_static_camber", 0.0)) + 1.5)) * 0.5
	var camber_long := 1.0 - 0.01 * (absf(float(s.get("front_static_camber", 0.0))) + absf(float(s.get("rear_static_camber", 0.0)))) * 0.5
	# top speed: where power meets air drag in top gear, or the rev cut
	var top_g: float = gears[gears.size() - 1]
	var cut_kmh := max_rpm * 1.1 / (top_g * fd) * TAU / 60.0 * wheel_r * 3.6
	var drag_k := 0.5 * 1.2 * cd * area
	var top := cut_kmh
	var kmh := 20.0
	while kmh < cut_kmh:
		var v := kmh / 3.6
		var rpm := v / wheel_r * top_g * fd * 60.0 / TAU
		# GEVP's rolling resistance grows with speed and with load, so downforce
		# costs top speed through it (gevp_wheel.gd process_rolling_resistance).
		var c_rr := 0.005 + 0.5 * (0.01 + 0.0095 * pow(v * 0.036, 2.0))
		var load := mass * 9.81 + (float(s.aero_downforce_coefficient_front) + float(s.aero_downforce_coefficient_rear)) * 0.5 * 1.2 * v * v * area
		if TOP_POWER_SHARE * torque.call(rpm) * top_g * fd / wheel_r * v < (drag_k * v * v + c_rr * load) * v:
			top = kmh
			break
		kmh += 1.0
	# 0-100: best gear's force, capped by rear-tyre traction, 0.2 s per shift
	# x1.35: weight moves onto the rear tyres under acceleration.
	var traction: float = 1.35 * mass * 9.81 * (1.0 - float(s.front_weight_distribution)) * cof * float(s.longitudinal_grip_ratio.Road) * pressure_k * camber_long
	var v := 0.0
	var t := 0.0
	var gear := 0
	while v < 27.78 and t < 30.0:
		var ratio: float = gears[gear]
		var rpm := maxf(v / wheel_r * ratio * fd * 60.0 / TAU, max_rpm * 0.35)
		if rpm > max_rpm and gear < gears.size() - 1:
			gear += 1
			t += 0.2
			continue
		var f := minf(torque.call(minf(rpm, max_rpm)) * ratio * fd / wheel_r, traction) - drag_k * v * v
		v += maxf(f, 1.0) / mass * 0.01
		t += 0.01
	# 100-0: tyre-limited, or brake-limited if the pressure is low
	var brake_g := cof * camber_long * pressure_k * minf(float(s.brake_force_multiplier) / 2.0, 1.0)
	var brake := 27.78 * 27.78 / (2.0 * 9.81 * maxf(brake_g, 0.1))
	# lateral grip: friction plus downforce at ~100 km/h, camber and pressure
	var df: float = (float(s.aero_downforce_coefficient_front) + float(s.aero_downforce_coefficient_rear)) * 0.5 * 1.2 * 27.78 * 27.78 * area
	var grip := cof * (1.0 + df / (mass * 9.81)) * camber_lat * pressure_k
	# balance: + = oversteer
	var bal := 0.0
	bal += (float(s.rear_arb_ratio) - float(s.front_arb_ratio)) * 2.0
	bal += (float(s.get("rear_resting_ratio", 0.5)) - float(s.get("front_resting_ratio", 0.5))) * 2.0
	bal -= float(s.get("rear_toe", 0.01)) * 25.0
	bal -= float(s.get("front_toe", 0.01)) * 15.0
	bal += (1.0 - clampf(float(s.get("rear_locking_differential_engage_torque", 200.0)) / 1000.0, 0.0, 1.0)) * 0.3
	bal += (float(s.aero_downforce_coefficient_front) - float(s.aero_downforce_coefficient_rear)) * 0.5
	bal += (float(s.get("front_static_camber", 0.0)) - float(s.get("rear_static_camber", 0.0))) * -0.05
	return {"top": top, "accel": t, "brake": brake, "grip": grip, "balance": clampf(bal, -1.0, 1.0)}
