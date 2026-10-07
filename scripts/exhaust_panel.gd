class_name ExhaustPanel
extends VBoxContainer

# The "Exhaust" section of the Tuner screen: four sliders (loudness, raspiness,
# pops, flame), cosmetic only. They write into the player's spec under
# "exhaust" through CarSpec.set_param(), the same path as the gearing sliders;
# EngineAudio copies the spec into the live synth every frame, so changes are
# heard at once, and saves the tune to disk once it settles. The held keys
# U/J, I/K and O/L still work while driving and move the same values.
#
# These paths are in TuneParams.all() (so tune slots store them) but never in
# TuneParams.auto_paths(): Auto-Tune does not touch them.

const STEP := 0.01
## [key, label]; the TuneParams path is "exhaust/<key>".
const KNOBS := [
	["loudness", "Loudness"],
	["raspiness", "Raspiness"],
	["pops", "Pops and crackle"],
	["flame", "Flame"],
]

var player: PlayerCar
var sliders := {}
var value_labels := {}
var preset_button: Button
var anti_lag_check: CheckButton

func _init(car: PlayerCar) -> void:
	player = car

func _ready() -> void:
	var grid := GridContainer.new()
	grid.columns = 6  # two knobs per row: keeps the screen short enough to fit 648 px
	grid.add_theme_constant_override("h_separation", 10)
	add_child(grid)
	for k in KNOBS:
		var name_label := Label.new()
		name_label.text = k[1]
		grid.add_child(name_label)
		var s := HSlider.new()
		s.min_value = 0.0
		s.max_value = 1.0
		s.step = STEP
		s.custom_minimum_size = Vector2(220, 0)
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		s.value_changed.connect(_on_slider.bind(k[0]))
		grid.add_child(s)
		sliders[k[0]] = s
		var v := Label.new()
		v.custom_minimum_size = Vector2(60, 0)
		grid.add_child(v)
		value_labels[k[0]] = v
	# Anti-lag crackle: a switch, not a knob (Roy, 2026-10-07). Cosmetic only.
	anti_lag_check = CheckButton.new()
	anti_lag_check.text = "Anti-lag crackle"
	anti_lag_check.toggled.connect(func(on: bool) -> void: _on_slider(1.0 if on else 0.0, "anti_lag"))
	add_child(anti_lag_check)
	preset_button = Button.new()
	preset_button.text = "Reset to car preset"
	preset_button.pressed.connect(_reset_to_preset)
	add_child(preset_button)
	refresh()

## Shows what the spec holds now. The Tuner screen calls it on open: a tune slot,
## the held keys or a saved tune may have changed it since the panel was built.
func refresh() -> void:
	for k in KNOBS:
		var key: String = k[0]
		var v := TuneParams.get_value(player.spec, "exhaust/" + key)
		sliders[key].set_value_no_signal(v)
		value_labels[key].text = "%.2f" % v
	anti_lag_check.set_pressed_no_signal(TuneParams.get_value(player.spec, "exhaust/anti_lag") >= 0.5)
	# Turbo cars only: the switch keeps its value but greys out with no boost.
	var turbo := float(player.spec.get("turbo_boost_max", 0.0)) > 0.0
	anti_lag_check.disabled = not turbo
	anti_lag_check.text = "Anti-lag crackle" if turbo else "Anti-lag crackle (needs a turbo)"
	_push_to_synth()

func _on_slider(value: float, key: String) -> void:
	var stored := CarSpec.set_param(player, player.spec, "exhaust/" + key, value)
	if value_labels.has(key):
		value_labels[key].text = "%.2f" % stored
	_push_to_synth()

## Live apply: EngineAudio copies the spec into the synth every frame, but it does
## not tick while the Tuner screen has the game paused, so push it now.
func _push_to_synth() -> void:
	for c in player.get_children():
		if c is EngineAudio:
			c.sync_tune()

func _reset_to_preset() -> void:
	var preset := ExhaustTune.for_car(EngineAudio.START_PRESET).to_dict()
	for key in preset:
		CarSpec.set_param(player, player.spec, "exhaust/" + key, preset[key])
	refresh()
