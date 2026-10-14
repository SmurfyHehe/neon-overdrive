extends Node

# Stakes, step S1 of races in the world (docs/planning/races-in-the-world-2026-10-14.md,
# Roy 1542): what a race, an escape and a bust are worth.
#
#   race won      +PAY_SPRINT_WIN into tonight's cash
#   escape        + cash by the highest heat the chase reached (ESCAPE_BY_HEAT)
#   honest bust   ticket and tow from the BANK by that heat (BUST_BY_HEAT,
#                 x difficulty), tonight's cash kept, clock +1 h
#   bad-cop bust  all of tonight's cash, no ticket, the bank kept
#   night one     the first bust of the night is a warning: nothing charged
#   mid-race bust the race ends BUSTED, then the bust bill as above
#
# Numbers are the economy doc's act-1 / Weekend Warrior rates (1 night of
# wages = $1,500); free mode uses them until the season economy is re-checked.
# The tow drive back to the start comes with the meet spot step (S3); here a
# bust charges the bill and the hour and the car stays where it is.
#
# Roy's rule: real-life based, effects exaggerated. Every money change slams a
# big stamp onto the screen (oversized, snaps to size with a bounce, a flash
# over the whole screen, then flies up and fades): amber for cash, silver for
# the bank.
#
# Duck-typed on purpose (tests feed it stand-ins): race needs race_ended,
# is_racing() and busted(); police needs busted, pursuit_started,
# pursuit_ended; heat needs level_changed, level and bad_cops.
# No class_name on purpose: preload it, so no class cache refresh is needed.

const Wallet := preload("res://scripts/core/wallet.gd")

const PAY_SPRINT_WIN := 450
## Index = heat level 0..5.
const ESCAPE_BY_HEAT := [0, 75, 150, 225, 375, 525]
const BUST_BY_HEAT := [0, 120, 225, 375, 600, 825]
## Of a bust bill, the ticket's share; the rest is the tow.
const TICKET_SHARE := 0.6
## Daily Driver, Weekend Warrior, Racer (DamageDifficulty.NAMES order).
const BUST_DIFFICULTY := [0.75, 1.0, 1.25]
const BUST_CLOCK_MINUTES := 60.0
## RaceController.Result.WIN / BUSTED (kept as ints so stand-ins work).
const RESULT_WIN := 1

const AMBER := Color("#FFC066")
const SILVER := Color("#C9CED6")
const NAVY := Color("#0E1424")

## A money change landed: amount (+ in, - out), "cash" or "bank", why.
signal paid(amount: int, account: String, reason: String)

var race: Object
var police: Object
var heat: Object
var wallet: Node
var night_clock: Node

## The highest heat level the chase in progress reached.
var chase_peak := 0
var chasing := false
var warned_night := -1
## Totals this session (tests, the night card later).
var won := 0
var escaped_pay := 0
var bust_paid := 0
var bad_cop_taken := 0

# ---------- the stamp ----------
const STAMP_IN := 0.22     # s: oversized to size, with a bounce
const STAMP_HOLD := 1.4
const STAMP_OUT := 0.5     # s: flies up and fades
const STAMP_START_SCALE := 2.6
const FLASH_SECS := 0.18
const FLASH_ALPHA := 0.28

var _layer: CanvasLayer
var _flash: ColorRect
var _stamp: Label
var _sub: Label
var _stamp_t := -1.0
var _flash_t := -1.0
var _queue: Array[Dictionary] = []
var _base_y := 150.0

# ---------- pure rules (tests use these) ----------

static func race_pay(result: int) -> int:
	return PAY_SPRINT_WIN if result == RESULT_WIN else 0

static func escape_pay(peak: int) -> int:
	return ESCAPE_BY_HEAT[clampi(peak, 0, ESCAPE_BY_HEAT.size() - 1)]

static func bust_bill(peak: int, difficulty: int) -> int:
	var base: int = BUST_BY_HEAT[clampi(maxi(peak, 1), 0, BUST_BY_HEAT.size() - 1)]
	var m: float = BUST_DIFFICULTY[clampi(difficulty, 0, BUST_DIFFICULTY.size() - 1)]
	return int(roundf(base * m / 5.0)) * 5

static func ticket_part(bill: int) -> int:
	return int(roundf(bill * TICKET_SHARE / 5.0)) * 5

# ---------- wiring ----------

func bind(r: Object, p: Object, h: Object, w: Node, clock: Node) -> void:
	race = r
	police = p
	heat = h
	wallet = w
	night_clock = clock
	if race != null:
		race.race_ended.connect(_on_race_ended)
	if police != null:
		police.pursuit_started.connect(_on_pursuit_started)
		police.pursuit_ended.connect(_on_pursuit_ended)
		police.busted.connect(_on_busted)
	if heat != null:
		heat.level_changed.connect(_on_level)

func _ready() -> void:
	name = "Stakes"
	if _layer == null:
		_build_ui()

func _on_race_ended(result: int) -> void:
	var pay := race_pay(result)
	if pay <= 0 or wallet == null:
		return
	wallet.add_cash(pay)
	won += pay
	_announce(pay, "cash", "race")

func _on_pursuit_started() -> void:
	chasing = true
	chase_peak = maxi(int(heat.level) if heat != null else 1, 1)

func _on_level(lvl: int) -> void:
	if chasing:
		chase_peak = maxi(chase_peak, lvl)

func _on_pursuit_ended(escaped: bool) -> void:
	if not chasing:
		return
	chasing = false
	if not escaped or wallet == null:
		return
	var pay := escape_pay(chase_peak)
	if pay > 0:
		wallet.add_cash(pay)
		escaped_pay += pay
		_announce(pay, "cash", "escape")

func _on_busted(cop: Object) -> void:
	# A race in progress is lost first; its own caption says BUSTED.
	if race != null and race.is_racing():
		race.busted()
	var peak := maxi(chase_peak, 1)
	chasing = false
	if wallet == null:
		return
	if heat != null and cop != null and cop in heat.bad_cops:
		var took: int = wallet.take_cash(wallet.cash)
		bad_cop_taken += took
		_announce(-took, "cash", "bad_cop")
		return
	var night: int = int(night_clock.night) if night_clock != null else 0
	if night == 1 and warned_night != 1:
		warned_night = 1
		_announce(0, "bank", "warning")
		return
	var bill := bust_bill(peak, GameSettings.difficulty)
	var took: int = wallet.take_bank(bill)
	bust_paid += took
	if night_clock != null:
		night_clock.add_minutes(BUST_CLOCK_MINUTES)
	_announce(-bill, "bank", "bust")

# ---------- the stamp ----------

func _announce(amount: int, account: String, reason: String) -> void:
	paid.emit(amount, account, reason)
	var big := ""
	var small := ""
	match reason:
		"race":
			big = "+" + Wallet.money(amount)
			small = "RACE WON"
		"escape":
			big = "+" + Wallet.money(amount)
			small = "GOT AWAY"
		"bust":
			var bill := -amount
			var ticket := ticket_part(bill)
			big = "BUSTED"
			small = "TICKET %s   TOW %s   +1 HOUR" % [Wallet.money(ticket), Wallet.money(bill - ticket)]
		"bad_cop":
			big = "-" + Wallet.money(-amount)
			small = "THEY TOOK TONIGHT'S CASH"
		"warning":
			big = "BUSTED"
			small = "WARNING THIS TIME"
	_queue.append({"big": big, "small": small, "gain": amount > 0, "colour": AMBER if account == "cash" else SILVER})
	if _stamp_t < 0.0:
		_next_stamp()

func _next_stamp() -> void:
	if _queue.is_empty():
		_stamp_t = -1.0
		return
	if _stamp == null:
		_build_ui()   # announced before _ready (bound outside the tree)
	var s: Dictionary = _queue.pop_front()
	_stamp.text = s.big
	_sub.text = s.small
	_stamp.add_theme_color_override("font_color", s.colour)
	_sub.add_theme_color_override("font_color", s.colour)
	_flash.color = Color(AMBER if s.gain else NAVY, 0.0)
	_stamp.visible = true
	_sub.visible = true
	_flash.visible = true
	_stamp_t = 0.0
	_flash_t = 0.0

## Scale of the stamp at time t (s) after it lands: oversized, snaps under
## size, settles to 1.
static func stamp_scale(t: float) -> float:
	if t >= STAMP_IN:
		return 1.0
	var k := t / STAMP_IN
	if k < 0.7:
		return lerpf(STAMP_START_SCALE, 0.88, k / 0.7)
	return lerpf(0.88, 1.0, (k - 0.7) / 0.3)

func _process(delta: float) -> void:
	if _stamp_t < 0.0:
		return
	_stamp_t += delta
	_flash_t += delta
	var fa := 0.0
	if _flash_t < FLASH_SECS:
		fa = FLASH_ALPHA * (1.0 - _flash_t / FLASH_SECS)
	_flash.color.a = fa
	_flash.visible = fa > 0.0
	var sc := stamp_scale(_stamp_t)
	_stamp.pivot_offset = _stamp.size * 0.5
	_stamp.scale = Vector2(sc, sc)
	var out_t := _stamp_t - STAMP_IN - STAMP_HOLD
	var a := 1.0
	var rise := 0.0
	if out_t > 0.0:
		var k := clampf(out_t / STAMP_OUT, 0.0, 1.0)
		a = 1.0 - k
		rise = -120.0 * k * k
	_stamp.modulate.a = a
	_sub.modulate.a = a
	_stamp.position.y = _base_y + rise
	_sub.position.y = _base_y + 96.0 + rise
	if out_t >= STAMP_OUT:
		_stamp.visible = false
		_sub.visible = false
		_next_stamp()

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 7  # over the race readout (6), under warning lights (9) and pause (10)
	add_child(_layer)
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.visible = false
	_layer.add_child(_flash)
	_stamp = _label(88)
	_sub = _label(26)
	_stamp.position.y = _base_y
	_sub.position.y = _base_y + 96.0

func _label(size: int) -> Label:
	var l := Label.new()
	UiTheme.apply(l, "menu", size)
	l.add_theme_color_override("font_outline_color", NAVY)
	l.add_theme_constant_override("outline_size", 10 if size > 40 else 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.set_anchors_preset(Control.PRESET_CENTER_TOP)
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.visible = false
	_layer.add_child(l)
	return l
