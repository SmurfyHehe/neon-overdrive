extends Node

# Walt's board for one day (work board W2, 2026-10-11). Owns what happened at
# the shop since the last 6 a.m.: which three cards were drawn, which order was
# taken, how it went, what it paid. Saved in the slot's shop.json (SaveStore).
#
# Stages: board -> job -> slip, then optionally late_board -> late_job ->
# late_slip, then done. Quitting mid-job restarts that job on load (nothing is
# paid until a job ends). Shop pay goes into the bank only (Wallet.pay_shop),
# once per receipt:
#   "day<N>:<order_id>"         the day's order
#   "day<N>:late:<order_id>"    the stay-late order (a third of the pay)
#   "day<N>:walt"               "Leave it to Walt" / going out without a pick
# The shop file is written BEFORE the pay, so a kill between the two leaves a
# slip that has not been paid: on load it pays (the receipt makes that safe).
# The other way round (paid, shop file not written) loads as a slip with no
# figure: the receipt is already in the wallet, so nothing is paid twice.
#
# Off unless the garage is on (NEON_SHOP=1 / 0 override it): see wants_shop().
# No class_name on purpose: preload it.

const SaveStore := preload("res://scripts/save/save_store.gd")
const WorkOrders := preload("res://scripts/core/work_orders.gd")

signal changed

const BOARD := "board"
const JOB := "job"
const SLIP := "slip"
const LATE_BOARD := "late_board"
const LATE_JOB := "late_job"
const LATE_SLIP := "late_slip"
const DONE := "done"
const RECENT_KEPT := 3

var enabled := false
var wallet: Node
var night_clock: Node
var difficulty := WorkOrders.DEFAULT_DIFFICULTY
## shop.json as loaded: {} until a day has started.
var data: Dictionary = {}

## NEON_SHOP=1 on, NEON_SHOP=0 off, otherwise it follows the garage.
static func wants_shop(garage_enabled: bool) -> bool:
	var env := OS.get_environment("NEON_SHOP")
	if env == "0":
		return false
	if env == "1":
		return true
	return garage_enabled

func _init(w: Node = null, clock: Node = null) -> void:
	wallet = w
	night_clock = clock
	name = "ShopDay"

## Reads shop.json again (after a slot change, or a simulated restart) and
## settles a pay a kill left half done.
func reload() -> void:
	data = SaveStore.load_shop()
	if data.is_empty():
		return
	data.day = int(data.get("day", 0))
	var stage := str(data.get("stage", BOARD))
	if stage == JOB and _taken_paid(str(data.get("taken", ""))):
		_mark_paid_unknown(false)
	elif stage == LATE_JOB and _taken_paid(str(data.get("late_taken", "")), true):
		_mark_paid_unknown(true)
	elif stage == SLIP or stage == LATE_SLIP:
		var late := stage == LATE_SLIP
		_settle_pay(late)
		# The clock comes back from the run save at 8 p.m.: put the 9 p.m.
		# start back while the player is still on the late slip.
		if late and night_clock != null and float(night_clock.minutes) < WorkOrders.STAY_LATE_START_MINUTES:
			_apply_late_clock()
	changed.emit()

func _receipt(order_id: String, late := false) -> String:
	return "day%d:%s%s" % [int(data.day), "late:" if late else "", order_id]

func _taken_paid(order_id: String, late := false) -> bool:
	return order_id != "" and wallet != null and _receipt(order_id, late) in wallet.receipts

func _mark_paid_unknown(late: bool) -> void:
	data.stage = LATE_SLIP if late else SLIP
	data[("late_" if late else "") + "paid"] = -1
	data[("late_" if late else "") + "marks"] = []
	_save()

## The slip stands but the pay may not have gone through: pay it (a receipt
## already in the wallet makes this a no-op).
func _settle_pay(late: bool) -> void:
	if wallet == null:
		return
	var amount := int(data.get("late_paid" if late else "paid", 0))
	if amount <= 0:
		return
	var id := "walt" if (not late and data.get("walted", false)) else str(data.get("late_taken" if late else "taken", ""))
	if id == "":
		return
	var receipt := ("day%d:walt" % int(data.day)) if id == "walt" else _receipt(id, late)
	wallet.pay_shop(amount, receipt)

# ---------- the day ----------

## True when the board should open at this dawn: starts the day if it is new.
## `day` is the night that just ended.
func want_board(day: int) -> bool:
	if not enabled or day < 1:
		return false
	begin_day(day)
	return stage() != DONE

func begin_day(day: int) -> void:
	if int(data.get("day", 0)) == day:
		return
	var recent: Array = data.get("recent", [])
	var slot := SaveStore.active_slot()
	data = {
		"day": day,
		"night": day,
		"cards": WorkOrders.draw(slot, day, recent, day),
		"stage": BOARD,
		"taken": null,
		"stay_late": false,
		"recent": recent,
	}
	_save()
	changed.emit()

func stage() -> String:
	return str(data.get("stage", DONE))

func day() -> int:
	return int(data.get("day", 0))

func act() -> Variant:
	return WorkOrders.act_for_night(day())

func card_ids() -> Array:
	return data.get("cards", [])

## The day's cards as order rows.
func cards() -> Array:
	var out: Array = []
	for id in card_ids():
		var o := WorkOrders.find(str(id))
		if not o.is_empty():
			out.append(o)
	return out

## The cards left for staying late: the ones that were not taken.
func late_cards() -> Array:
	var out: Array = []
	for o in cards():
		if o.id != data.get("taken", null):
			out.append(o)
	return out

## The order being worked right now (the day's, or the late one).
func current_order() -> Dictionary:
	var late := stage() in [LATE_JOB, LATE_SLIP]
	var id := str(data.get("late_taken", "")) if late else str(data.get("taken", ""))
	return WorkOrders.find(id) if id != "" and id != "walt" else {}

func walt_pay() -> int:
	return WorkOrders.skip_pay(act(), difficulty)

## Dollars on a card's face: "$300-$680".
func range_text(order: Dictionary) -> String:
	return WorkOrders.range_text(order, act(), difficulty)

## The board is reachable from the garage while the day is not settled.
func can_reopen() -> bool:
	return enabled and day() > 0 and stage() != DONE

# ---------- taking and finishing ----------

func take(order_id: String) -> bool:
	var s := stage()
	if s == BOARD and order_id in card_ids():
		data.taken = order_id
		data.stage = JOB
	elif s == LATE_BOARD and order_id != data.get("taken", null) and order_id in card_ids():
		data.late_taken = order_id
		data.stage = LATE_JOB
	else:
		return false
	_save()
	changed.emit()
	return true

## A job ended with these step marks (0..1 each). Writes the slip and pays.
## Returns the dollars (0 when there is no job).
func finish_job(marks: Array) -> int:
	var s := stage()
	if s != JOB and s != LATE_JOB:
		return 0
	var late := s == LATE_JOB
	var order := current_order()
	if order.is_empty():
		return 0
	var total := 0.0
	for m in marks:
		total += float(m)
	var score := total / maxf(float(marks.size()), 1.0)
	var amount := WorkOrders.pay_for(order, score, act(), difficulty, {"stay_late": late})
	var pre := "late_" if late else ""
	data[pre + "marks"] = marks.duplicate()
	data[pre + "paid"] = amount
	data.stage = LATE_SLIP if late else SLIP
	var recent: Array = data.get("recent", [])
	recent.append(order.id)
	while recent.size() > RECENT_KEPT:
		recent.remove_at(0)
	data.recent = recent
	if late:
		data.clock_applied = true
	_save()                       # the slip first ...
	if wallet != null:
		wallet.pay_shop(amount, _receipt(order.id, late))   # ... then the pay
	if late:
		_apply_late_clock()
	changed.emit()
	return amount

## "Leave it to Walt": the flat pay, straight to a slip. Returns the dollars.
func skip() -> int:
	if stage() != BOARD and stage() != JOB:
		return 0
	var amount := walt_pay()
	data.taken = "walt"
	data.walted = true
	data.paid = amount
	data.marks = []
	data.stage = SLIP
	_save()
	if wallet != null:
		wallet.pay_shop(amount, "day%d:walt" % day())
	changed.emit()
	return amount

func offer_stay_late() -> bool:
	return stage() == SLIP and not data.get("stay_late", false) and not late_cards().is_empty()

func start_stay_late() -> bool:
	if not offer_stay_late():
		return false
	data.stay_late = true
	data.stage = LATE_BOARD
	_save()
	changed.emit()
	return true

func head_out() -> void:
	if stage() == DONE:
		return
	data.stage = DONE
	_save()
	changed.emit()

## Called on "Go out": nothing taken (or a job left half done) means Walt did
## one. Returns the dollars paid (0 when the day was already settled).
func settle_for_exit() -> int:
	if not enabled or day() < 1:
		return 0
	var s := stage()
	if s == BOARD or s == JOB:
		var amount := skip()
		head_out()
		return amount
	if s != DONE:
		head_out()
	return 0

## Stay late: the next night starts at 9 p.m. instead of 8.
func _apply_late_clock() -> void:
	if night_clock != null:
		night_clock.set_time(WorkOrders.STAY_LATE_START_MINUTES, night_clock.night)
	data.clock_applied = true

func _save() -> void:
	SaveStore.save_shop(data)
