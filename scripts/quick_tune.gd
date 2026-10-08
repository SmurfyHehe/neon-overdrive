class_name QuickTune
extends CanvasLayer

# The quick tune (Tuner UI overhaul PR 5; Roy, 2026-10-08: "quick tune from a
# small tuner in the car, a menu that pops up while driving; the full Tuner at
# the shop and garage"). A small plate at the left of the screen with four
# settings you might want between corners. The game keeps running.
#
# Keys (keyboard only, listed on the pause menu's Controls page, never on
# screen; actions quick_tune / quick_tune_down / quick_tune_up): Tab opens it,
# and Tab again steps to the next setting; [ and ] move the focused one down or
# up a notch. It closes by itself after a few seconds without a key, or when
# the game pauses. None of these keys drive the car.
#
# Every change goes through TunerModel, the same single write path as the full
# Tuner, so ranges, danger zones and the live re-derive all apply.

const IDLE_CLOSE_S := 4.0
## [label, page, setting id] for TunerModel settings; "character" is the dial.
const ITEMS := [
	["Grip to Drift", "", "character"],
	["Brake bias", "brakes", "front_brake_bias"],
	["Traction control", "assists", "traction"],
	["Diff lock", "diff", "diff_lock"],
]

var player: PlayerCar
var game_state: GameState
var model: TunerModel
var index := 0
var is_open := false
var _idle := 0.0
## Seconds without a key before it closes (tests shorten it).
var idle_close_s := IDLE_CLOSE_S
var plate: PanelContainer
var rows: Array[Dictionary] = []   # {name: Label, value: Label, bar: RotaryDial or null}
var dial: RotaryDial

func _init(car: PlayerCar, state: GameState) -> void:
	player = car
	game_state = state

func _ready() -> void:
	layer = 6  # over the HUD (5), under the warning lights (9) and menus (10)
	process_mode = Node.PROCESS_MODE_PAUSABLE  # a paused game closes it, see _process
	# Share the Tuner's model, so the dial and the preset name agree in both.
	for c in get_parent().get_children():
		if c is TunerScreen and c.model != null:
			model = c.model
	if model == null:
		model = TunerModel.new(player, player.spec, CarSpec.coupe_default())
	game_state.state_changed.connect(func(to: GameState.State, _from: GameState.State) -> void:
		if to != GameState.State.PLAYING:
			close())  # a menu or the Tuner took over
	plate = PanelContainer.new()
	var bg := UiTheme.plate_panel()
	bg.set_content_margin_all(10)
	plate.add_theme_stylebox_override("panel", bg)
	plate.theme = UiTheme.get_theme()
	plate.position = Vector2(16, 120)
	plate.custom_minimum_size = Vector2(300, 0)
	plate.visible = false
	add_child(plate)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	plate.add_child(col)
	col.add_child(UiTheme.title_label("QUICK TUNE", 24, UiTheme.AMBER))
	col.add_child(UiTheme.floor_tape())
	dial = RotaryDial.new()
	dial.custom_minimum_size = Vector2(280, 120)
	dial.lo_word = "Grip"
	dial.hi_word = "Drift"
	dial.ticks = TunerModel.CHARACTER_NOTCHES
	col.add_child(dial)
	for it in ITEMS:
		var h := HBoxContainer.new()
		col.add_child(h)
		var n := Label.new()
		n.text = it[0]
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(n)
		var v := Label.new()
		v.add_theme_font_override("font", UiTheme.font("mono"))
		v.add_theme_color_override("font_color", UiTheme.AMBER)
		h.add_child(v)
		rows.append({"name": n, "value": v})

func setting(i: int) -> Dictionary:
	var it: Array = ITEMS[i]
	if it[2] == "character":
		return {}
	for s in TunerModel.page(it[1]).settings:
		if s.id == it[2]:
			return s
	return {}

func open() -> void:
	is_open = true
	_idle = 0.0
	plate.visible = true
	_refresh()

func close() -> void:
	is_open = false
	plate.visible = false

## Moves the focused setting by `step` notches. Returns true if it changed.
func nudge(step: int) -> bool:
	_idle = 0.0
	var changed := false
	if ITEMS[index][2] == "character":
		var to := clampi(model.character + step, 0, TunerModel.CHARACTER_NOTCHES - 1)
		changed = to != model.character
		if changed:
			model.set_character(to)
	else:
		var s := setting(index)
		if s.id == "front_brake_bias" and float(player.spec.get("front_brake_bias", -1.0)) < 0.0:
			model.set_choice(TunerModel.page("brakes").settings[1], 1)  # Auto -> Manual at the split Auto gave
		changed = model.nudge(s, step)
	_refresh()
	return changed

## Polled on the physics tick like all game input (#30). Opening and the
## steps are presses, so holding a key does nothing more.
func _physics_process(_delta: float) -> void:
	if game_state.state != GameState.State.PLAYING or game_state.typing_in_text():
		return
	if Input.is_action_just_pressed("quick_tune"):
		if is_open:
			index = (index + 1) % ITEMS.size()
			_idle = 0.0
			_refresh()
		else:
			open()
	elif is_open and Input.is_action_just_pressed("quick_tune_down"):
		nudge(-1)
	elif is_open and Input.is_action_just_pressed("quick_tune_up"):
		nudge(1)

func _process(delta: float) -> void:
	if not is_open:
		return
	if game_state.state != GameState.State.PLAYING:
		close()
		return
	_idle += delta
	if _idle > idle_close_s:
		close()

func _refresh() -> void:
	for i in rows.size():
		var r: Dictionary = rows[i]
		var focused := i == index
		r.name.text = ("> " if focused else "  ") + ITEMS[i][0]
		r.name.add_theme_color_override("font_color", UiTheme.SODIUM if focused else UiTheme.SILVER)
		if ITEMS[i][2] == "character":
			r.value.text = TunerModel.character_word(model.character)
		else:
			r.value.text = model.value_text(setting(i))
	dial.set_values(float(model.character) / (TunerModel.CHARACTER_NOTCHES - 1), 0.5, TunerModel.character_word(model.character))
