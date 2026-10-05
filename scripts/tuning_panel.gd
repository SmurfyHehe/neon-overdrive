class_name TuningPanel
extends CanvasLayer

# Gearing & power tuning panel (#62 step 1). T opens it; the game pauses
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
	["low_end", "Low-end torque", "torque_shape/low_end", 0.01],
	["peak_pos", "Peak position", "torque_shape/peak_pos", 0.01],
	["plateau", "Plateau width", "torque_shape/plateau", 0.01],
	["falloff", "Torque at redline", "torque_shape/falloff", 0.01],
]
const AIR_DENSITY := 1.2  # kg/m^3, for the drag-limited top speed estimate
# gevp_vehicle.gd process_motor() only cuts torque above max_rpm * 1.1, and the
# torque curve holds its redline value up to there -- so the speeds a gear
# really reaches are at 110% of the "Redline rpm" knob, not at it.
const REV_CUT := 1.1

var player: PlayerCar
var game_state: GameState
var values := {}
var start_values := {}
var sliders := {}
var value_labels := {}
var readout: Label
var copy_button: Button

func _init(car: PlayerCar, state: GameState) -> void:
	player = car
	game_state = state

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10  # same layer as the pause menu; they are never open together
	visible = false
	_read_from_player()
	start_values = values.duplicate()

	var panel := PanelContainer.new()
	panel.position = Vector2(16, 90)
	var bg := StyleBoxFlat.new()  # near-opaque: bright buildings behind made the text unreadable
	bg.bg_color = Color(0.03, 0.02, 0.07, 0.92)
	bg.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", bg)
	add_child(panel)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	panel.add_child(columns)

	var left := VBoxContainer.new()
	columns.add_child(left)
	var title := Label.new()
	title.text = "TUNING (#62)  -  T or Esc to close, game paused"
	left.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 3
	left.add_child(grid)
	for k in KNOBS:
		var name_label := Label.new()
		name_label.text = k[1]
		grid.add_child(name_label)
		var entry := TuneParams.find(k[2])
		var s := HSlider.new()
		s.min_value = entry.min
		s.max_value = entry.max
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
	var buttons := HBoxContainer.new()
	left.add_child(buttons)
	copy_button = Button.new()
	copy_button.text = "Copy values"
	copy_button.pressed.connect(_copy_values)
	buttons.add_child(copy_button)
	var reset := Button.new()
	reset.text = "Reset"
	reset.pressed.connect(_reset)
	buttons.add_child(reset)

	readout = Label.new()
	readout.add_theme_font_override("font", _mono_font())
	columns.add_child(readout)

	game_state.state_changed.connect(_on_state_changed)
	_apply()

func _on_state_changed(new_state: GameState.State, _old_state: GameState.State) -> void:
	visible = new_state == GameState.State.TUNING
	if visible:
		# Auto-Tune (or Reset) may have changed the spec since the panel was built.
		_read_from_player()
		for key in values:
			sliders[key].set_value_no_signal(values[key])
		_refresh()
	else:
		# Sliders keep keyboard focus otherwise and eat the arrow keys.
		var focused := get_viewport().gui_get_focus_owner()
		if focused:
			focused.release_focus()

func _on_slider(value: float, key: String) -> void:
	_write(key, value)
	_refresh()

func _path_of(key: String) -> String:
	for k in KNOBS:
		if k[0] == key:
			return k[2]
	return ""

## One edit: through the single write path. The stored (clamped) value is what
## the panel shows.
func _write(key: String, value: float) -> void:
	values[key] = CarSpec.set_param(player, player.spec, _path_of(key), value)

func _reset() -> void:
	for key in start_values:
		sliders[key].set_value_no_signal(start_values[key])
	values = start_values.duplicate()
	_apply()

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
		value_labels[k[0]].text = ("%d" % values[k[0]]) if step >= 1.0 else ("%.2f" % values[k[0]])
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
	lines.append("NOW  gear %s   %d rpm   %d km/h" % [_gear_name(), int(player.motor_rpm), int(player.current_speed() * 3.6)])
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
	var text := """# #62 tune from the tuning panel -- paste into scripts/car_spec.gd
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
