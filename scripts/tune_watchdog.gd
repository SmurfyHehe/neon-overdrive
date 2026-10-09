class_name TuneWatchdog
extends CanvasLayer

# Auto-revert for a tune that leaves the car undrivable (settings safety part 4,
# 2026-10-07; plan in docs/planning/settings-safety-design-2026-10-07.md, signed
# off by Roy).
#
# When the Tuner opens, the watchdog keeps a copy of the tune. When it closes
# with any setting in the red (SettingDanger), it watches the first WATCH_S of
# driving:
#   - a non-finite car (NaN position or speed): revert at once, no question
#   - upside down for FLIP_S
#   - full throttle for STUCK_S without passing STUCK_KMH
# On a trigger it asks "Keep tune / Revert" with a COUNTDOWN_S countdown;
# Revert has focus and is what happens on timeout. Reverting puts the old tune
# back and sets the car upright where it stands. Spinning never triggers it:
# that is the fun extreme. No key hints; the buttons say what they do.

const WATCH_S := 20.0
const FLIP_S := 3.0
const STUCK_S := 8.0
const STUCK_KMH := 30.0
const COUNTDOWN_S := 10.0

var player: PlayerCar
var game_state: GameState
## The tune when the Tuner last opened; {} when there is nothing to go back to.
var saved_spec := {}
var watching := false
var watch_t := 0.0
var flip_t := 0.0
var stuck_t := 0.0
var countdown := 0.0
var reason := ""
var reverted_count := 0  # for tests

var dialog: PanelContainer
var message: Label
var keep_button: Button
var revert_button: Button

func _init(car: PlayerCar, state: GameState) -> void:
	player = car
	game_state = state
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	dialog = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(TunerScreen.NAVY, 0.96)
	style.border_color = SettingDanger.RED
	style.set_border_width_all(2)
	style.set_content_margin_all(16)
	dialog.add_theme_stylebox_override("panel", style)
	dialog.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	dialog.position.y = 80
	add_child(dialog)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	dialog.add_child(box)
	message = Label.new()
	message.add_theme_color_override("font_color", TunerScreen.SILVER)
	box.add_child(message)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	keep_button = Button.new()
	keep_button.text = "Keep tune"
	keep_button.pressed.connect(keep)
	buttons.add_child(keep_button)
	revert_button = Button.new()
	revert_button.text = "Revert"
	revert_button.pressed.connect(revert)
	buttons.add_child(revert_button)
	dialog.visible = false
	game_state.state_changed.connect(_on_state_changed)

func _on_state_changed(new_state: GameState.State, old_state: GameState.State) -> void:
	if GameState.is_tuner(new_state) and not GameState.is_tuner(old_state):
		saved_spec = CarSpec.clone_spec(player.spec)
		watching = false
	elif not GameState.is_tuner(new_state) and GameState.is_tuner(old_state):
		if not saved_spec.is_empty() and player.spec.hash() != saved_spec.hash() and has_red(player.spec):
			arm()

## Whether any tunable value of `spec` is in the red zone.
static func has_red(spec: Dictionary) -> bool:
	for e in TuneParams.all():
		if SettingDanger.level(e.path, TuneParams.get_value(spec, e.path)) == SettingDanger.Level.RED:
			return true
	return false

func arm() -> void:
	watching = true
	watch_t = 0.0
	flip_t = 0.0
	stuck_t = 0.0

func _physics_process(delta: float) -> void:
	if dialog.visible or saved_spec.is_empty():
		return
	if not _car_finite():
		reason = "the car's numbers broke"
		revert()  # nothing to keep: no question asked
		return
	if not watching or game_state.state != GameState.State.PLAYING:
		return
	watch_t += delta
	if watch_t > WATCH_S:
		watching = false
		return
	flip_t = flip_t + delta if player.global_transform.basis.y.y < 0.0 else 0.0
	var slow := absf(player.current_speed()) * 3.6 < STUCK_KMH
	stuck_t = stuck_t + delta if slow and player.throttle_input > 0.9 else 0.0
	if not slow:
		stuck_t = 0.0
	if flip_t >= FLIP_S:
		ask("the car flipped")
	elif stuck_t >= STUCK_S:
		ask("the car can't get going")

func _car_finite() -> bool:
	var p := player.global_position
	var v := player.linear_velocity
	return is_finite(p.x) and is_finite(p.y) and is_finite(p.z) and is_finite(v.x) and is_finite(v.y) and is_finite(v.z)

## Shows the Keep / Revert question for `why`.
func ask(why: String) -> void:
	reason = why
	watching = false
	countdown = COUNTDOWN_S
	dialog.visible = true
	_update_message()
	revert_button.grab_focus()

func _process(delta: float) -> void:
	if not dialog.visible:
		return
	countdown -= delta
	if countdown <= 0.0:
		revert()
		return
	_update_message()

func _update_message() -> void:
	message.text = "This tune looks undrivable: %s.\nReverting to your last tune in %d s." % [reason, ceili(maxf(countdown, 0.0))]

func keep() -> void:
	_close()

## Puts the tune from when the Tuner last opened back on the car, and the car
## upright where it stands.
func revert() -> void:
	if not saved_spec.is_empty():
		for e in TuneParams.all():
			CarSpec.set_param(player, player.spec, e.path, TuneParams.get_value(saved_spec, e.path))
	if not _car_finite() or player.global_transform.basis.y.y < 0.5:
		_upright()
	reverted_count += 1
	watching = false
	_close()

func _upright() -> void:
	var t := player.global_transform
	var p := t.origin if _car_finite() else Vector3(0.0, 1.0, 0.0)
	var fwd := -t.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.1 or not is_finite(fwd.x):
		fwd = Vector3.FORWARD
	player.global_transform = Transform3D(Basis.looking_at(fwd.normalized(), Vector3.UP), p + Vector3(0.0, 0.5, 0.0))
	player.linear_velocity = Vector3.ZERO
	player.angular_velocity = Vector3.ZERO

func _close() -> void:
	dialog.visible = false
	var f := get_viewport().gui_get_focus_owner()
	if f:
		f.release_focus()
