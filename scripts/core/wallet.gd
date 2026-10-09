extends Node

# Money (police build plan F0, 2026-10-09): cash earned tonight and the bank.
# Cash grows during the night (races and escapes later; today only the test
# command), and at 6 a.m. it all moves into the bank (bank_night; "head
# home" will call the same thing). The HUD shows tonight's cash, the pause
# screen shows the bank. Busts take from the bank and bad cops take tonight's
# cash (F3, F7a); they will go through take_cash / take_bank.
#
# Saved in the slot's wallet.json (SaveStore) after every change, one write
# for both numbers, so banking can never lose or double money even if the
# game dies halfway. A save the store refuses (a chase is on) is retried every
# frame until it goes through.
#
# Test command: F8 adds TEST_CASH, debug builds only (keyboard only, no
# on-screen hint: it is not a player control).
# No class_name on purpose: preload it, so no class cache refresh is needed.

const SaveStore := preload("res://scripts/save/save_store.gd")

signal changed(cash: int, bank: int)
signal banked(amount: int)

const TEST_CASH := 250
const TEST_ACTION := &"debug_add_cash"

var cash := 0
var bank := 0
var _dirty := false

## Loads the slot's money at once (not in _ready, which can run after the
## first add_cash and would overwrite it).
func _init() -> void:
	var w := SaveStore.load_wallet()
	cash = int(w.cash)
	bank = int(w.bank)

func _ready() -> void:
	if OS.is_debug_build() and not InputMap.has_action(TEST_ACTION):
		InputMap.add_action(TEST_ACTION)
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_F8
		InputMap.action_add_event(TEST_ACTION, ev)

func _unhandled_input(event: InputEvent) -> void:
	if OS.is_debug_build() and event.is_action_pressed(TEST_ACTION) and not event.is_echo():
		add_cash(TEST_CASH)

func _process(_delta: float) -> void:
	if _dirty:
		_save()

func add_cash(amount: int) -> void:
	if amount <= 0:
		return
	cash += amount
	_changed()

## Takes up to `amount` from tonight's cash; returns what it took.
func take_cash(amount: int) -> int:
	var t := clampi(amount, 0, cash)
	cash -= t
	_changed()
	return t

## Takes up to `amount` from the bank; returns what it took.
func take_bank(amount: int) -> int:
	var t := clampi(amount, 0, bank)
	bank -= t
	_changed()
	return t

## The night is over (6 a.m., or heading home): tonight's cash goes into the bank.
func bank_night() -> void:
	var amount := cash
	bank += cash
	cash = 0
	_changed()
	banked.emit(amount)

func _changed() -> void:
	changed.emit(cash, bank)
	_save()

func _save() -> bool:
	_dirty = not SaveStore.save_wallet(cash, bank)
	return not _dirty

## "$1,250"
static func money(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-$" if n < 0 else "$") + s + out
