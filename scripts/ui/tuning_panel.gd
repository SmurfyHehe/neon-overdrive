class_name TuningPanel
extends HBoxContainer

# Gearing & power tuning panel (#62 step 1), the "Gearing & Power" section of
# the Tuner screen (scripts/ui/tuner_screen.gd). T opens the screen; the game pauses
# (GameState.TUNING) and the sliders write straight into the player's Vehicle
# properties, so the next stretch of driving after closing uses the new tune.
# "Copy values" puts a car_spec.gd-ready snippet on the clipboard (and prints
# it) for the step-2 PR.
#
# Every edit goes through CarSpec.set_param() into the player's spec dict (the
# same path Auto-Tune uses), which updates the live car; the panel keeps no
# separate copy of the tune. Slider ranges come from TuneParams.
#
# Debug tool, deliberately plain Godot default controls -- not the game's UI.
# The torque knobs are the four CarSpec.build_torque_curve() shape values plus
# peak torque and redline; they are the same levers the planned upgrade tree
# will move, so a tune found here maps straight onto upgrades later.

const GEAR_COUNT := 5
# [key, label, TuneParams path, step]; min and max come from TuneParams.
const KNOBS := [
	["final_drive", "Final drive", "final_drive", 0.01],
	["gear_1", "Gear 1", "gear_ratios/0", 0.01],
	["gear_2", "Gear 2", "gear_ratios/1", 0.01],
	["gear_3", "Gear 3", "gear_ratios/2", 0.01],
	["gear_4", "Gear 4", "gear_ratios/3", 0.01],
	["gear_5", "Gear 5", "gear_ratios/4", 0.01],
	["max_torque", "Peak torque Nm", "max_torque", 5.0],
	["max_rpm", "Redline rpm", "max_rpm", 100.0],
	["turbo", "Turbo boost bar", "turbo_boost_max", 0.05],
	["low_end", "Low-end torque", "torque_shape/low_end", 0.01],
	["peak_pos", "Peak position", "torque_shape/peak_pos", 0.01],
	["plateau", "Plateau width", "torque_shape/plateau", 0.01],
	["falloff", "Torque at redline", "torque_shape/falloff", 0.01],
	# Settings safety part 2 (2026-10-07): every chassis number, out to the
	# Advanced hard limits (TuneParams.ADVANCED), past the simple pages' ranges.
	["friction", "Tyre friction", "coefficient_of_friction/Road", 0.05],
	["long_grip", "Longitudinal grip", "longitudinal_grip_ratio/Road", 0.05],
	["stiffness", "Tyre stiffness", "tire_stiffnesses/Road", 0.5],
	["pressure_f", "Pressure front bar", "front_tyre_pressure", 0.1],
	["pressure_r", "Pressure rear bar", "rear_tyre_pressure", 0.1],
	["camber_f", "Camber front deg", "front_static_camber", 0.5],
	["camber_r", "Camber rear deg", "rear_static_camber", 0.5],
	["toe_f", "Toe front rad", "front_toe", 0.005],
	["toe_r", "Toe rear rad", "rear_toe", 0.005],
	["ride_f", "Ride height front m", "front_spring_length", 0.01],
	["ride_r", "Ride height rear m", "rear_spring_length", 0.01],
	["spring_f", "Springs front", "front_resting_ratio", 0.05],
	["spring_r", "Springs rear", "rear_resting_ratio", 0.05],
	["damp_f", "Dampers front", "front_damping_ratio", 0.05],
	["damp_r", "Dampers rear", "rear_damping_ratio", 0.05],
	["arb_f", "Anti-roll bar front", "front_arb_ratio", 0.05],
	["arb_r", "Anti-roll bar rear", "rear_arb_ratio", 0.05],
	["diff_f", "Diff lock front Nm (low = locked)", "front_locking_differential_engage_torque", 50.0],
	["diff_r", "Diff lock rear Nm (low = locked)", "rear_locking_differential_engage_torque", 50.0],
	["brake", "Brake pressure", "brake_force_multiplier", 0.1],
	["bias", "Brake bias front (-1 auto)", "front_brake_bias", 0.01],
	["df_f", "Downforce front", "aero_downforce_coefficient_front", 0.05],
	["df_r", "Rear wing", "aero_downforce_coefficient_rear", 0.05],
	["steer", "Steering lock rad", "max_steering_angle", 0.01],
	["abs_f", "ABS front threshold", "front_abs_spin_difference_threshold", 1.0],
	["abs_r", "ABS rear threshold", "rear_abs_spin_difference_threshold", 1.0],
]
## Gears must each be shorter than the one before; a slider stops this far short
## of its neighbour (an out-of-order box makes the automatic hunt between gears).
const GEAR_GAP := 0.01
const AIR_DENSITY := 1.2  # kg/m^3, for the drag-limited top speed estimate
# gevp_vehicle.gd process_motor() only cuts torque above max_rpm * 1.1, and the
# torque curve holds its redline value up to there -- so the speeds a gear
# really reaches are at 110% of the "Redline rpm" knob, not at it.
const REV_CUT := 1.1

## A slider or Reset changed the tune (the Auto-Tune lock labels show it).
signal tune_changed

var player: PlayerCar
var game_state: GameState
var values := {}
var start_values := {}
var sliders := {}
var value_labels := {}
var line_labels := {}  # key -> consequence Label (settings safety part 3)
var stock := CarSpec.player_spec(PlayerCar.chassis_kind())  # what "Stock" means for this car, as on the Tuner screen
var readout: Label
var copy_button: Button

func _init(car: PlayerCar, state: GameState) -> void:
	player = car
	game_state = state

func _ready() -> void:
	add_theme_constant_override("separation", 24)
	_read_from_player()
	start_values = values.duplicate()

	var columns := self
	var left := VBoxContainer.new()
	columns.add_child(left)
	var grid := GridContainer.new()
	grid.columns = 4
	left.add_child(grid)
	for k in KNOBS:
		var name_label := Label.new()
		name_label.text = k[1]
		grid.add_child(name_label)
		var entry := TuneParams.find(k[2])
		var s := HSlider.new()
		s.min_value = entry.adv_min
		s.max_value = entry.adv_max
		s.step = k[3]
		s.custom_minimum_size = Vector2(220, 0)
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		s.value = values[k[0]]
		s.value_changed.connect(_on_slider.bind(k[0]))
		grid.add_child(s)
		sliders[k[0]] = s
		var v := Label.new()
		v.custom_minimum_size = Vector2(60, 0)
		grid.add_child(v)
		value_labels[k[0]] = v
		var line := Label.new()
		line.custom_minimum_size = Vector2(300, 0)
		line.add_theme_font_size_override("font_size", 13)
		grid.add_child(line)
		line_labels[k[0]] = line
	var buttons := HBoxContainer.new()
	left.add_child(buttons)
	copy_button = Button.new()
	copy_button.text = "Copy values"
	copy_button.pressed.connect(_copy_values)
	buttons.add_child(copy_button)
	var reset := Button.new()
	reset.text = "Reset to stock"
	reset.pressed.connect(_reset)
	buttons.add_child(reset)

	readout = Label.new()
	readout.add_theme_font_override("font", _mono_font())
	columns.add_child(readout)

	game_state.state_changed.connect(_on_state_changed)
	_apply()

func _on_state_changed(new_state: GameState.State, old_state: GameState.State) -> void:
	if GameState.is_tuner(new_state) and not GameState.is_tuner(old_state):
		refresh_from_player()  # something may have changed the spec while the screen was closed

## Shows what the player's spec holds now. Called on open and whenever Auto-Tune
## (Apply, Undo, a loaded tune slot) changes the car while this panel is on screen.
func refresh_from_player() -> void:
	_read_from_player()
	for key in values:
		sliders[key].set_value_no_signal(values[key])
	_refresh()

func _on_slider(value: float, key: String) -> void:
	value = gear_in_order(key, value, values)
	_write(key, value)
	sliders[key].set_value_no_signal(values[key])
	_refresh()
	tune_changed.emit()

## `value` for knob `key`, kept between its neighbouring gears in `vals` (gear 1
## is the tallest ratio). Other knobs pass through.
static func gear_in_order(key: String, value: float, vals: Dictionary) -> float:
	if not key.begins_with("gear_"):
		return value
	var g := int(key.get_slice("_", 1))
	if g > 1:
		value = minf(value, float(vals["gear_%d" % (g - 1)]) - GEAR_GAP)
	if g < GEAR_COUNT:
		value = maxf(value, float(vals["gear_%d" % (g + 1)]) + GEAR_GAP)
	return value

func _path_of(key: String) -> String:
	for k in KNOBS:
		if k[0] == key:
			return k[2]
	return ""

## One edit: through the single write path. The stored (clamped) value is what
## the panel shows.
func _write(key: String, value: float) -> void:
	values[key] = CarSpec.set_param(player, player.spec, _path_of(key), value)

## Every knob back to the car's stock value (settings safety part 4; it used
## to go back to the values at game start, which could be a saved extreme).
func _reset() -> void:
	for k in KNOBS:
		values[k[0]] = TuneParams.get_value(stock, k[2])
		sliders[k[0]].set_value_no_signal(values[k[0]])
	_apply()
	tune_changed.emit()

func _read_from_player() -> void:
	for k in KNOBS:
		values[k[0]] = TuneParams.get_value(player.spec, k[2])

## Writes every knob. Used on open and Reset; a single slider move uses _write().
func _apply() -> void:
	for k in KNOBS:
		_write(k[0], values[k[0]])
	_refresh()

func _refresh() -> void:
	for k in KNOBS:
		var step: float = k[3]
		value_labels[k[0]].text = ("%d" % values[k[0]]) if step >= 1.0 else ("%.3f" % values[k[0]] if step < 0.01 else "%.2f" % values[k[0]])
		# Danger colour and the consequence line (settings safety part 3).
		var path: String = k[2]
		var level := SettingDanger.level(path, values[k[0]])
		var c := SettingDanger.colour(level)
		value_labels[k[0]].add_theme_color_override("font_color", c)
		line_labels[k[0]].text = SettingDanger.consequence(path, values[k[0]], TuneParams.get_value(stock, path))
		line_labels[k[0]].add_theme_color_override("font_color", c if level != SettingDanger.Level.GREEN else Color(c, 0.6))
	readout.text = _readout_text()

func _readout_text() -> String:
	var redline: float = values.max_rpm
	var cut := redline * REV_CUT
	var fd: float = values.final_drive
	var wheel_r: float = PlayerCar.CFG.wheel_r
	# Peak power, sampled off the curve the car is actually using.
	var peak_kw := 0.0
	var peak_rpm := 0.0
	for i in 201:
		var rpm := redline * i / 200.0
		var kw := _power_kw(rpm)
		if kw > peak_kw:
			peak_kw = kw
			peak_rpm = rpm
	var lines: Array[String] = []
	lines.append("NOW  gear %s   %d rpm   %d km/h" % [_gear_name(), int(player.motor_rpm), Hud.kmh(player.current_speed())])
	lines.append("")
	lines.append("Peak power  %d kW (%d hp) at %d rpm" % [peak_kw, peak_kw * 1.341, peak_rpm])
	lines.append("At redline  %d%% of peak power" % roundi(100.0 * _power_kw(redline) / peak_kw))
	lines.append("Rev cut     %d rpm (engine pulls to 110%% of redline)" % roundi(cut))
	lines.append("")
	lines.append("Gear  km/h@cut  step  upshift->rpm  %power")
	for g in GEAR_COUNT:
		var ratio: float = values["gear_%d" % (g + 1)]
		var line := "%-4d  %8d" % [g + 1, roundi(_kmh_at(cut, ratio, fd, wheel_r))]
		if g + 1 < GEAR_COUNT:
			var next: float = values["gear_%d" % (g + 2)]
			var drop_rpm := cut * next / ratio
			line += "  %4.2f  %12d    %3d%%" % [ratio / next, roundi(drop_rpm), roundi(100.0 * _power_kw(drop_rpm) / peak_kw)]
			if next >= ratio:
				line += "  !! not shorter"
		lines.append(line)
	lines.append("")
	var top_ratio: float = values["gear_%d" % GEAR_COUNT]
	var gear_top := _kmh_at(cut, top_ratio, fd, wheel_r)
	var drag_top := _drag_limited_kmh(top_ratio, fd, wheel_r)
	if drag_top < gear_top:
		lines.append("Top speed ~%d km/h (drag-limited in %d)" % [roundi(drag_top), GEAR_COUNT])
	else:
		lines.append("Top speed %d km/h (rev cut in %d)" % [roundi(gear_top), GEAR_COUNT])
	lines.append("  estimate: air drag only, no rolling resistance")
	return "\n".join(lines)

func _power_kw(rpm: float) -> float:
	var t: float = player.get_torque_at_rpm(rpm)
	return t * rpm * TAU / 60.0 / 1000.0

func _kmh_at(rpm: float, ratio: float, fd: float, wheel_r: float) -> float:
	return rpm / (ratio * fd) * TAU / 60.0 * wheel_r * 3.6

## Highest speed in top gear where engine power still beats air drag. Walks up
## in 1 km/h steps to the rev-cut speed; coarse, but it is only a guide.
## Ignores motor_drag and tire slip, so real top speed comes out a bit lower.
func _drag_limited_kmh(ratio: float, fd: float, wheel_r: float) -> float:
	var drag_k := 0.5 * AIR_DENSITY * player.coefficient_of_drag * player.frontal_area
	var cut_kmh := _kmh_at(values.max_rpm * REV_CUT, ratio, fd, wheel_r)
	var kmh := 1.0
	while kmh < cut_kmh:
		var v := kmh / 3.6
		var rpm := v / wheel_r * ratio * fd * 60.0 / TAU
		if _power_kw(rpm) * 1000.0 < drag_k * v * v * v:
			return kmh
		kmh += 1.0
	return cut_kmh

func _gear_name() -> String:
	return "R" if player.gear == -1 else ("N" if player.gear == 0 else str(player.gear))

func _copy_values() -> void:
	var ratios: Array[String] = []
	for i in GEAR_COUNT:
		ratios.append("%.2f" % values["gear_%d" % (i + 1)])
	var text := """# #62 tune from the tuning panel -- paste into scripts/car/car_spec.gd
var gear_ratios_typed: Array[float] = [%s]
"max_torque": %.1f,
"max_rpm": %.1f,
"final_drive": %.2f,
const DEFAULT_TORQUE_SHAPE := {"low_end": %.2f, "peak_pos": %.2f, "plateau": %.2f, "falloff": %.2f}""" % [
		", ".join(ratios), values.max_torque, values.max_rpm, values.final_drive,
		values.low_end, values.peak_pos, values.plateau, values.falloff]
	DisplayServer.clipboard_set(text)
	print(text)
	copy_button.text = "Copied (also printed)"

func _mono_font() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Consolas", "Courier New", "monospace"])
	return f
