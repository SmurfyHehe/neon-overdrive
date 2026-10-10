class_name MechanicPanel
extends VBoxContainer

# The simple front of Auto-Tune on the Tuner's Mechanic page (Tuner redesign
# PR 4, 2026-10-06). Pick ONE goal, tick what to keep, press Run; the result
# comes back in plain words with Apply / Discard (AutoTunePanel.plain_result_text).
# It drives the AutoTunePanel underneath (goal weights, locks, search length),
# which keeps all its logic and tests; the Advanced box shows that panel's raw
# controls again.

const GOALS := [["accel", "Launch"], ["top_speed", "Top speed"], ["braking", "Braking"], ["grip", "Cornering"]]
## Keep boxes per Tuner page: the Auto-Tune paths each one locks.
const KEEPS := [
	["gearbox", "Keep gearbox", ["final_drive", "gear_ratios/"]],
	["aero", "Keep aero", ["coefficient_of_drag", "aero_downforce_coefficient_front", "aero_downforce_coefficient_rear"]],
	["brakes", "Keep brakes", ["brake_force_multiplier"]],
	["tyres", "Keep tires", ["tire_stiffnesses/", "coefficient_of_friction/", "lateral_grip_assist/", "longitudinal_grip_ratio/"]],
]
## Normal search (60 runs) in the simple view.
const SIMPLE_BUDGET := 1

var auto: AutoTunePanel
var goal_buttons := {}    # goal -> Button
var keep_boxes := {}      # page id -> CheckBox
var advanced_box: CheckBox
var goal := "accel"

func _init(panel: AutoTunePanel) -> void:
	auto = panel

func _ready() -> void:
	add_theme_constant_override("separation", 6)
	var row := HBoxContainer.new()
	add_child(row)
	var group := ButtonGroup.new()
	for g in GOALS:
		var b := Button.new()
		b.text = g[1]
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_ALL
		b.pressed.connect(set_goal.bind(g[0]))
		row.add_child(b)
		goal_buttons[g[0]] = b
	var keeps := HBoxContainer.new()
	add_child(keeps)
	for k in KEEPS:
		var cb := CheckBox.new()
		cb.text = k[1]
		cb.toggled.connect(func(_on: bool) -> void: _sync())
		keeps.add_child(cb)
		keep_boxes[k[0]] = cb
	advanced_box = CheckBox.new()
	advanced_box.text = "Advanced"
	advanced_box.toggled.connect(set_advanced)
	add_child(advanced_box)
	if not auto.is_node_ready():
		await auto.ready  # it sits below this panel, so it is built after it
	set_goal(goal)
	set_advanced(false)

func set_goal(g: String) -> void:
	goal = g
	goal_buttons[g].set_pressed_no_signal(true)
	_sync()

func set_advanced(on: bool) -> void:
	advanced_box.set_pressed_no_signal(on)
	auto.set_advanced(on)
	_sync()

## Writes the simple choices into the panel underneath. In Advanced the raw
## controls are the player's, so they are left alone.
func _sync() -> void:
	if auto.advanced:
		return
	for g in auto.goal_sliders:
		auto.goal_sliders[g].value = AutoTunePanel.MAX_WEIGHT if g == goal else 0
	for path in auto.lock_boxes:
		var keep := false
		for k in KEEPS:
			if keep_boxes[k[0]].button_pressed:
				for prefix in k[2]:
					keep = keep or path == prefix or (prefix.ends_with("/") and path.begins_with(prefix))
		auto.lock_boxes[path].button_pressed = keep
	auto.budget_option.select(SIMPLE_BUDGET)
