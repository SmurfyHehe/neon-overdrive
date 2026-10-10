extends CanvasLayer

# The pump menu (Stage C stops, first slice, 2026-10-09). Opens when the car
# stops in a gas station bay (scripts/world/gas_station.gd ->
# GameState.State.STATION); the game is paused while it is up.
#
# Roy's fuel rules (damage/fuel design notes, decisions 2026-10-08):
# - a fill-up takes about 10 in-game minutes (FILL_GAME_MINUTES): the night
#   clock jumps on while the gauge rises;
# - it is paid from the BANK, never tonight's cash; a short bank buys what it
#   can (FuelTank.refuel);
# - the menu is locked while a cop sees you. There are no cops yet, so "a cop
#   sees you" is the save system's chase flag (SaveStore.chase_active), which
#   the police build sets;
# - a dry tank is never a dead end: the car limps to the pump at
#   LimpMode.FUEL_KMH, and if the bank can't pay, Ferris tows you in. The tow
#   ends the night (6 a.m., so tonight's cash is banked, F0) and leaves the
#   tank at the starting third. Press it twice: it ends the night.
#
# Keyboard only: arrows and Enter on the buttons, Esc drives off. No key hints.
# No class_name on purpose: preload it, so no class cache refresh is needed.

const SaveStore := preload("res://scripts/save/save_store.gd")
const Wallet := preload("res://scripts/core/wallet.gd")

const FILL_GAME_MINUTES := 10.0
## Real seconds the gauge takes to rise on screen (the clock still jumps the
## full FILL_GAME_MINUTES).
const FILL_SHOW_SECONDS := 2.5

const AMBER := Color("#FFC066")
const ORANGE := Color("#FF8A1F")
const RED := Color(1.0, 0.3, 0.2)

var game_state: GameState
var player: Node
var wallet: Node
var night_clock: NightClock

var tank_label: Label
var money_label: Label
var message: Label
var fill_button: Button
var tow_button: Button
var leave_button: Button

## Filling: seconds into the show, -1 when not filling.
var _fill_t := -1.0
var _fill_litres := 0.0
var _fill_from := 0.0
var _tow_armed := false

func _init(state: GameState, car: Node, money: Node, clock: NightClock) -> void:
	game_state = state
	player = car
	wallet = money
	night_clock = clock

func _ready() -> void:
	name = "PumpPanel"
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	visible = false

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.custom_minimum_size = Vector2(420, 0)
	center.add_child(box)

	var title := Label.new()
	title.text = "FUEL STOP"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", ORANGE)
	box.add_child(title)
	tank_label = _label(box, "Tank")
	money_label = _label(box, "Money")
	message = _label(box, "Message")
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fill_button = _button(box, "FillUp", fill)
	tow_button = _button(box, "Tow", tow)
	leave_button = _button(box, "DriveOff", func() -> void: game_state.close_station())
	leave_button.text = "Drive off"

	game_state.state_changed.connect(_on_state_changed)

func _label(box: Control, n: String) -> Label:
	var l := Label.new()
	l.name = n
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(l)
	return l

func _button(box: Control, n: String, f: Callable) -> Button:
	var b := Button.new()
	b.name = n
	b.pressed.connect(f)
	box.add_child(b)
	return b

func _on_state_changed(new_state: GameState.State, _old: GameState.State) -> void:
	var on := new_state == GameState.State.STATION
	if on and not visible:
		_tow_armed = false
		message.text = ""
	visible = on
	if on:
		refresh()
		var first := fill_button if not fill_button.disabled else (tow_button if not tow_button.disabled else leave_button)
		first.grab_focus()
	else:
		_finish_fill()

## A cop sees you: no fill-up, no tow (SaveStore.chase_active for now).
static func locked() -> bool:
	return SaveStore.chase_active

func _room() -> float:
	return FuelTank.CAPACITY_L - player.fuel.litres

## What a fill costs, and the litres the bank can pay for.
func quote() -> Dictionary:
	var want := int(ceil(_room() - 0.001))
	var bank: int = wallet.bank
	var can := mini(want, floori(float(bank) / FuelTank.PRICE_PER_LITRE))
	return {"want": want, "can": can, "cost": can * FuelTank.PRICE_PER_LITRE}

func refresh() -> void:
	var f: FuelTank = player.fuel
	var shown := f.litres if _fill_t < 0.0 else _fill_from + _fill_litres * clampf(_fill_t / FILL_SHOW_SECONDS, 0.0, 1.0)
	var frac := shown / FuelTank.CAPACITY_L
	var bars := clampi(ceili(frac * 10.0 - 0.001), 0, 10)
	tank_label.text = "Tank %s %d%%  ·  %.0f of %.0f L" % ["▮".repeat(bars) + "▯".repeat(10 - bars), roundi(frac * 100.0), shown, FuelTank.CAPACITY_L]
	money_label.text = "$%d a litre  ·  Bank %s  ·  tonight's cash %s stays in your pocket" % [
		FuelTank.PRICE_PER_LITRE, Wallet.money(wallet.bank), Wallet.money(wallet.cash)]
	var q := quote()
	var busy := _fill_t >= 0.0
	if locked():
		message.text = "A cop has eyes on you. Not now."
		message.add_theme_color_override("font_color", RED)
	if q.want <= 0:
		fill_button.text = "Tank's full"
	elif q.can <= 0:
		fill_button.text = "Fill up: bank can't cover a litre"
	elif q.can < q.want:
		fill_button.text = "Fill %d L for %s (all the bank covers)" % [q.can, Wallet.money(q.cost)]
	else:
		fill_button.text = "Fill up: %d L for %s" % [q.can, Wallet.money(q.cost)]
	fill_button.disabled = busy or locked() or q.can <= 0
	tow_button.text = ("Sure? Ends the night now, banks %s" % Wallet.money(wallet.cash)) if _tow_armed else "Call Ferris: tow, ends the night"
	tow_button.disabled = busy or locked()
	leave_button.disabled = busy

## Buys what the bank covers; the clock jumps FILL_GAME_MINUTES while the
## gauge rises. Money and fuel change at once (one save), only the show lasts.
func fill() -> void:
	if _fill_t >= 0.0 or locked():
		return
	_tow_armed = false
	var bank_before: int = wallet.bank
	_fill_from = player.fuel.litres
	_fill_litres = player.fuel.refuel(wallet)
	if _fill_litres <= 0.0:
		message.text = "The bank can't cover it. Ferris can tow you in."
		message.add_theme_color_override("font_color", RED)
		refresh()
		return
	message.text = "Filling: %.0f L for %s" % [_fill_litres, Wallet.money(bank_before - wallet.bank)]
	message.add_theme_color_override("font_color", AMBER)
	_fill_t = 0.0
	refresh()

func _process(delta: float) -> void:
	if not visible:
		return
	if _fill_t >= 0.0:
		var step := minf(delta, FILL_SHOW_SECONDS - _fill_t)
		_fill_t += delta
		if night_clock != null and step > 0.0:
			night_clock.advance(step / FILL_SHOW_SECONDS * clock_seconds())
		if _fill_t >= FILL_SHOW_SECONDS:
			_finish_fill()
			message.text = "Filled %.0f L. %d minutes gone, it's %s." % [_fill_litres, int(FILL_GAME_MINUTES), night_clock.text() if night_clock != null else ""]
			leave_button.grab_focus()
	refresh()

## Real seconds of clock time a fill-up takes.
static func clock_seconds() -> float:
	return FILL_GAME_MINUTES * NightClock.REAL_SECONDS_PER_HOUR / 60.0

func _finish_fill() -> void:
	_fill_t = -1.0

## Ferris tows you in: the night ends (tonight's cash is banked by game.gd's
## 6 a.m. hook) and the tank is left at the starting third. First press arms.
func tow() -> void:
	if _fill_t >= 0.0 or locked():
		return
	if not _tow_armed:
		_tow_armed = true
		refresh()
		return
	_tow_armed = false
	var cash: int = wallet.cash
	if night_clock != null:
		night_clock.advance((NightClock.NIGHT_MINUTES - night_clock.minutes) * NightClock.REAL_SECONDS_PER_HOUR / 60.0 + 0.01)
	var start := FuelTank.CAPACITY_L * FuelTank.START_FRACTION
	player.fuel.litres = maxf(player.fuel.litres, start)
	message.text = "Ferris towed you in. Night over, %s banked. He left you a third of a tank." % Wallet.money(cash)
	message.add_theme_color_override("font_color", AMBER)
	refresh()
	leave_button.grab_focus()
