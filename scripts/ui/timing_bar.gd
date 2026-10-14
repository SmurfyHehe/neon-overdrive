extends Control

# The timing bar for one job step (work board W1, 2026-10-11).
#
# A dark steel bar, an amber zone, a sodium sweet spot in the middle of the
# zone, and a silver needle. One press of ui_accept stops it: sweet spot is
# clean (1.0), the zone is ok (0.7), outside is a miss (0.0). A miss grinds,
# the step is redone with the needle 1.15x faster, and a second miss on the
# same step completes it at 0 (never stuck).
#
# Styles (per step, from the order data):
#   sweep   back and forth, even
#   bounce  back and forth, faster near the ends
#   rush    each pass 10% faster than the one before
#   hold    needle still; the zone drifts slowly, press when it is under it
#
# Time is injected: advance(dt). _process calls it with the frame time unless
# `auto` is false (tests). A held key is one press: key echo is ignored.
#
# Per frame (issue #579) the bar does no _draw: the steel bar is drawn once,
# and the zone (with its sweet spot) and the needle are two child canvas items
# built once per step; a frame only moves them (one transform each, and only
# when they moved). _process runs only while the bar is running on its own.
# Nothing here names a key on screen.
# No class_name on purpose: preload it.

const WorkOrders := preload("res://scripts/core/work_orders.gd")

signal step_done(mark: float)
## A miss that gets a second try; `misses` is how many so far on this step.
signal step_missed(misses: int)

const COL_BAR := Color("#1B2A4A")
const COL_EDGE := Color("#0E1424")
const COL_ZONE := Color("#FFC066")
const COL_SWEET := Color("#FF8A1F")
const COL_NEEDLE := Color("#C9CED6")
const BOUNCE_EXP := 1.8
const RUSH_GAIN := 1.10
const RUSH_CAP := 3.0
const HOLD_NEEDLE := 0.5
const HOLD_DRIFT_RATE := 0.9   # radians per second at speed 1.0

var auto := true:
	set(v):
		auto = v
		_sync_process()
var running := false:
	set(v):
		running = v
		_sync_process()
var style := "sweep"
var zone := 0.2                # width as a share of the bar
var speed := 1.0               # from the data, 0.8-1.6
var speed_mult := 1.0          # 1.15 per miss
var misses := 0
var phase := 0.0               # needle progress (hold: drift phase)
var needle := 0.0              # 0..1 along the bar
var center := 0.5              # zone centre, 0..1

var _grind: AudioStreamPlayer
static var _grind_stream: AudioStreamWAV
## The moving parts: child canvas items of this one (drawn on top of the bar).
var _zone_ci := RID()
var _needle_ci := RID()
var _zone_x := NAN     # where they were last put, so a still frame costs nothing
var _needle_x := NAN

func _ready() -> void:
	custom_minimum_size = Vector2(480, 40)
	_sync_process()
	_grind = AudioStreamPlayer.new()
	_grind.stream = _grind_wave()
	_grind.volume_db = -8.0
	add_child(_grind)

## Starts a step: {"zone", "speed", "style", "label"}.
func setup(step: Dictionary) -> void:
	zone = clampf(float(step.get("zone", 0.2)), 0.04, 0.5)
	speed = float(step.get("speed", 1.0))
	style = str(step.get("style", "sweep"))
	if not style in WorkOrders.STYLES:
		style = "sweep"
	# The zone sits somewhere between 0.30 and 0.70 of the bar, the same for
	# the same step every time.
	var h := absi(hash(str(step.get("label", "")))) % 1000
	center = 0.3 + 0.4 * float(h) / 1000.0
	speed_mult = 1.0
	misses = 0
	_restart()
	running = true

func _restart() -> void:
	phase = 0.0
	if style == "hold":
		phase = PI * 0.5  # the zone starts at one end and drifts across
	_update_needle()
	queue_redraw()   # once per step: the zone's width and place change

func sweet_half_width() -> float:
	return zone * WorkOrders.NEEDLE_CLEAN_SHARE * 0.5

func advance(dt: float) -> void:
	if not running:
		return
	var rate := 1.0 / WorkOrders.NEEDLE_BASE_PERIOD_S * speed * speed_mult
	if style == "rush":
		# One pass is half a cycle; each pass is 10% faster than the last.
		rate *= minf(pow(RUSH_GAIN, floorf(phase * 2.0)), RUSH_CAP)
	if style == "hold":
		phase += dt * HOLD_DRIFT_RATE * speed * speed_mult
	else:
		phase += dt * rate
	_update_needle()
	_place()

func _update_needle() -> void:
	match style:
		"hold":
			needle = HOLD_NEEDLE
			var amp := 0.5 - zone * 0.5 - 0.02
			center = 0.5 + amp * sin(phase)
		"bounce":
			var u := 2.0 * _triangle(phase) - 1.0
			needle = 0.5 + 0.5 * signf(u) * pow(absf(u), BOUNCE_EXP)
		_:
			needle = _triangle(phase)

## 0 -> 1 -> 0 once per whole phase unit.
static func _triangle(p: float) -> float:
	return 1.0 - absf(2.0 * fposmod(p, 1.0) - 1.0)

## What the needle is worth right now: 1.0, 0.7 or 0.0.
func mark_now() -> float:
	var d := absf(needle - center)
	if d <= sweet_half_width():
		return WorkOrders.MARK_CLEAN
	if d <= zone * 0.5:
		return WorkOrders.MARK_OK
	return WorkOrders.MARK_MISS

## One press. Finishes the step, or grinds and redoes it.
func press() -> void:
	if not running:
		return
	var m := mark_now()
	if m > WorkOrders.MARK_MISS:
		running = false
		step_done.emit(m)
		return
	misses += 1
	if _grind != null and is_inside_tree():
		_grind.play()
	if misses >= WorkOrders.MISSES_TO_GIVE_UP:
		running = false
		step_done.emit(WorkOrders.MARK_MISS)
		return
	speed_mult *= WorkOrders.NEEDLE_MISS_SPEEDUP
	_restart()
	step_missed.emit(misses)

func _process(delta: float) -> void:
	advance(delta)

## Process only while there is a needle to move on its own.
func _sync_process() -> void:
	set_process(running and auto)

func _input(event: InputEvent) -> void:
	handle_event(event)

## ui_accept pressed, not a held-key repeat.
func handle_event(event: InputEvent) -> void:
	if running and event.is_action_pressed("ui_accept", false):
		press()
		var vp := get_viewport()
		if vp != null:
			vp.set_input_as_handled()

## The steel bar, and the zone and needle shapes (on a resize or a new step).
## The same rectangles as ever: the zone and sweet spot are drawn around the
## zone centre and the needle around x = 0, then moved into place.
func _draw() -> void:
	var w := size.x
	var h := size.y
	draw_rect(Rect2(0, 0, w, h), COL_EDGE)
	draw_rect(Rect2(3, 3, w - 6, h - 6), COL_BAR)
	var rs := RenderingServer
	var me := get_canvas_item()
	if not _zone_ci.is_valid():
		_zone_ci = rs.canvas_item_create()
		rs.canvas_item_set_parent(_zone_ci, me)
		rs.canvas_item_set_draw_index(_zone_ci, 0)
		_needle_ci = rs.canvas_item_create()
		rs.canvas_item_set_parent(_needle_ci, me)
		rs.canvas_item_set_draw_index(_needle_ci, 1)
	var inner := w - 6.0
	rs.canvas_item_clear(_zone_ci)
	rs.canvas_item_add_rect(_zone_ci, Rect2(-zone * 0.5 * inner, 3, zone * inner, h - 6), COL_ZONE)
	var sw := sweet_half_width() * 2.0 * inner
	rs.canvas_item_add_rect(_zone_ci, Rect2(-sw * 0.5, 3, sw, h - 6), COL_SWEET)
	rs.canvas_item_clear(_needle_ci)
	rs.canvas_item_add_rect(_needle_ci, Rect2(-2, 0, 4, h), COL_NEEDLE)
	_zone_x = NAN
	_needle_x = NAN
	_place()

## Moves the zone and the needle to where they are now; nothing if unmoved.
func _place() -> void:
	if not _zone_ci.is_valid():
		return
	var inner := size.x - 6.0
	var zx := 3.0 + center * inner
	if zx != _zone_x:
		_zone_x = zx
		RenderingServer.canvas_item_set_transform(_zone_ci, Transform2D(0.0, Vector2(zx, 0.0)))
	var nx := 3.0 + needle * inner
	if nx != _needle_x:
		_needle_x = nx
		RenderingServer.canvas_item_set_transform(_needle_ci, Transform2D(0.0, Vector2(nx, 0.0)))

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _zone_ci.is_valid():
		RenderingServer.free_rid(_zone_ci)
		RenderingServer.free_rid(_needle_ci)

## A short grinding burst, generated here (no asset): decaying noise through
## a coarse saw so it reads as gears biting.
static func _grind_wave() -> AudioStreamWAV:
	if _grind_stream != null:
		return _grind_stream
	var rate := 22050
	var n := int(rate * 0.22)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1196
	var saw := 0.0
	for i in n:
		var t := float(i) / float(n)
		saw = fposmod(saw + 90.0 / rate, 1.0)
		var s := ((saw * 2.0 - 1.0) * 0.5 + rng.randf_range(-1.0, 1.0) * 0.5) * (1.0 - t) * 0.6
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	_grind_stream = w
	return w
