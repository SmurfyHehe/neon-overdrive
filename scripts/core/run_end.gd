extends Node

# The totalled meter and the end of the night (TM1, decided 2026-10-11).
# Listens to the wreck sensor (scripts/car/wreck_sensor.gd), moves the meter
# (scripts/car/totalled_meter.gd, stored in CarDamage.totalled) and plays the
# crash screen (scripts/ui/crash_screen.gd) when the car is totalled.
#
# No single hit or roll ends a run (Roy 1160):
#
#   a counted hit   adds a step to the meter. Under 100% nothing is cut, no
#                   cash is taken and the controls stay with the player. A
#                   step of 0.30 or more is only a dazed beat: camera shake and
#                   the ring in the ears, and cracked glass on a 0.60 step.
#   totalled (100%) the sequence below, and the night ends.
#
#   totalled  2 s: nobody is on the pedals, the car coasts to a stop on a
#             light brake; the view goes to the driver's own seat
#   hit       the camera shakes, the glass cracks, the ears ring
#   black     hard cut to black; every game sound stops except a scrape tail
#   line      Dave's line (and what the total cost)
#   morning   the night always ends at a total: the first total of a save
#             (Moose and Walt, free, once per save, meter back to 0) or the
#             tow ("The car came home on a hook."). Hold S to skip it.
#   restart   the next night, parked on the shoulder with the engine off
#             (game.gd _park_at_start; X starts it)
#
# Cash: a total takes half of tonight's cash, all of it with bad cops on you;
# the bank is never touched; the first total of a save is free. In the test
# build (GameSettings.test_build) nothing is taken at all. The tree is
# never paused and the time scale never changes: no slow motion, ever.
#
# Cars only for now. Rolls come from TM2 (add_step with
# TotalledMeter.step_for_roll); bikes and the trike come with their builds.
# The lines are placeholders in data/totalled_lines.json (the story is Roy's).
# No class_name on purpose: preload it, so no class cache refresh is needed.

const WreckRules := preload("res://scripts/car/wreck_rules.gd")
const WreckSensor := preload("res://scripts/car/wreck_sensor.gd")
const TotalledMeter := preload("res://scripts/car/totalled_meter.gd")
const CrashScreen := preload("res://scripts/ui/crash_screen.gd")
const SaveStore := preload("res://scripts/save/save_store.gd")

enum Phase { DRIVING, TOTALLED, HIT, BLACK, LINE, MORNING, DONE }

const TOTALLED_SECS := 2.0  # coasting to a stop before the hit beat
const TOTALLED_BRAKE := 0.25
const DAZE_TRAUMA := 0.7    # a counted hit that did not total the car
const DAZE_STEP := 0.30     # steps under this are no beat at all
const GLASS_STEP := 0.60    # the glass cracks only from a step this big
const HIT_SECS := 0.9       # shake, cracked glass, ring
const BLACK_SECS := 1.6     # black with the scrape tail, before Dave speaks
const LINE_SECS := 4.5
const MORNING_SECS := 12.0  # the morning card moves on by itself after this
const SKIP_HOLD_SECS := 0.7
const SKIP_ACTION := &"brake"  # S

## Everything in the world goes quiet at the cut; the crash screen's own
## sounds are on the UI bus.
const CUT_BUSES := [&"Engine", &"Turbo", &"Music", &"Tires", &"World", &"Traffic", &"Sirens", &"Scanner"]

const LINES_PATH := "res://data/totalled_lines.json"

## The meter went up: before, after, the step added.
signal meter_stepped(before: float, after: float, step: float)
## The car is totalled: what it took from tonight's cash, and whether it was
## the free first total of the save.
signal totalled_started(loss: int, free: bool)
signal finished(night_ended: bool)

var player: Node3D
var camera: Camera3D
var wallet: Node
var night_clock: Node
var game_state: GameState

## Bad cops are on the player right now: a total costs all of tonight's cash.
## TODO(police F2+): set from the chase/bust state once the police build has
## it; nothing does yet. The bust bill is not wired here.
var bad_cops := false
## Tests turn this off: they do not run as the current scene, so there is
## nothing to reload.
var restart_on_finish := true

var sensor: WreckSensor
var screen: CrashScreen
var phase := Phase.DRIVING
var last_loss := 0
var last_free := false
var ends_night := false
## How many counted steps this run has seen, and the last one's size.
var steps := 0
var last_step := 0.0

var _meter := TotalledMeter.new()
var _own_damage: CarDamage  # only when the player has none (a test)
var _clock := 0.0           # physics seconds, for the same-hit window
var _glass_left := 0.0
var _left := 0.0
var _hold := 0.0
var _line := ""
var _was_muted := {}
var _rng := RandomNumberGenerator.new()
static var _lines_cache: Dictionary = {}
static var _last_pick: Dictionary = {}  # pool key -> the line said last

func _ready() -> void:
	_rng.randomize()
	sensor = WreckSensor.new(player as RigidBody3D)
	sensor.wrecked.connect(func(wall: float, _closing: float, other: Object) -> void: hit(wall, other))
	add_child(sensor)
	screen = CrashScreen.new()
	add_child(screen)

func _exit_tree() -> void:
	_restore_buses()

func _physics_process(delta: float) -> void:
	_clock += delta

## The meter, 0..1 (CarDamage.totalled, so it is saved with the car).
func meter() -> float:
	return _damage().totalled

func _damage() -> CarDamage:
	var d: Variant = player.get("damage") if player != null else null
	if d is CarDamage:
		return d
	if _own_damage == null:
		_own_damage = CarDamage.new()
	return _own_damage

## A counted hit of this wall speed (km/h) on `other`. True when it totalled
## the car and the sequence began.
func hit(wall_kmh: float, other: Object = null) -> bool:
	if not _can_count():
		return false
	var d := _damage()
	var key := other.get_instance_id() if other != null and is_instance_valid(other) else 0
	var after := _meter.after_hit(d.totalled, wall_kmh, key, _clock, PlayerCar.chassis_kind())
	return _apply(d, after)

## A step from anywhere else (TM2's rolls: TotalledMeter.step_for_roll(kind)).
## It goes through the difficulty factor and the "Looks only" setting like a
## hit does. True when it totalled the car.
func add_step(step: float) -> bool:
	if not _can_count():
		return false
	var d := _damage()
	return _apply(d, TotalledMeter.add(d.totalled, TotalledMeter.scaled(step)))

func _can_count() -> bool:
	if phase != Phase.DRIVING or not TotalledMeter.counts():
		return false
	if game_state != null and game_state.state != GameState.State.PLAYING:
		return false
	var d: Variant = player.get("damage") if player != null else null
	return not (d is CarDamage and not d.enabled)

func _apply(d: CarDamage, after: float) -> bool:
	var before := d.totalled
	var step := after - before
	if step <= 0.0001:
		return false
	d.totalled = after
	steps += 1
	last_step = step
	meter_stepped.emit(before, after, step)
	if TotalledMeter.is_totalled(after):
		return begin_total()
	if step >= DAZE_STEP - 0.0001:
		_daze(step)
	return false

## The beat for a big hit that did not total the car: shake and ring, cracked
## glass on the biggest steps. The player keeps the controls, the view and the
## sound.
func _daze(step: float) -> void:
	if camera is ChaseCamera:
		var cam := camera as ChaseCamera
		cam.trauma = maxf(cam.trauma, DAZE_TRAUMA)
	if step >= GLASS_STEP - 0.0001:
		screen.crack(_rng.randi())
		_glass_left = HIT_SECS
	else:
		screen.ring()

## The car is totalled now: the night ends. True when the sequence began
## (false while one is already playing, or while a menu is open).
func begin_total() -> bool:
	if phase != Phase.DRIVING:
		return false
	if game_state != null and not game_state.wreck():
		return false
	last_free = not SaveStore.first_wreck_used()  # the first total of a save
	last_loss = 0
	# The test build is a sandbox: nothing is ever taken from cash there.
	if wallet != null and not GameSettings.test_build():
		last_loss = wallet.take_cash(WreckRules.cash_loss(wallet.cash, bad_cops, last_free))
	if last_free:
		SaveStore.mark_first_wreck()
		_repair()  # Walt's fix: every part, the powertrain, the meter back to 0
	ends_night = true
	_line = _pick_line()
	sensor.enabled = false
	screen.clear_glass()
	_glass_left = 0.0
	if player != null:
		player.set("driver", _totalled_driver)
	if camera is ChaseCamera:
		(camera as ChaseCamera).set_view(ChaseCamera.View.COCKPIT)
	phase = Phase.TOTALLED
	_left = TOTALLED_SECS
	totalled_started.emit(last_loss, last_free)
	return true

func _process(delta: float) -> void:
	if _glass_left > 0.0:
		_glass_left -= delta
		if _glass_left <= 0.0 and phase == Phase.DRIVING:
			screen.clear_glass()
	if phase == Phase.DRIVING or phase == Phase.DONE:
		return
	_left -= delta
	match phase:
		Phase.TOTALLED:
			if _left <= 0.0:
				if camera is ChaseCamera:
					(camera as ChaseCamera).trauma = 1.0
				if player != null:
					player.set("driver", _wrecked_driver)
				screen.crack(_rng.randi())
				phase = Phase.HIT
				_left = HIT_SECS
		Phase.HIT:
			if _left <= 0.0:
				_cut_buses()
				screen.black()
				phase = Phase.BLACK
				_left = BLACK_SECS
		Phase.BLACK:
			if _left <= 0.0:
				screen.say(_line if last_loss <= 0 else "%s\n\nLost on the road: %s" % [_line, wallet.money(last_loss)])
				phase = Phase.LINE
				_left = LINE_SECS
		Phase.LINE:
			if _left <= 0.0:
				screen.card("MORNING", _morning_lines())
				phase = Phase.MORNING
				_left = MORNING_SECS
		Phase.MORNING:
			_hold = _hold + delta if Input.is_action_pressed(SKIP_ACTION) else 0.0
			screen.set_hold(_hold / SKIP_HOLD_SECS)
			if _left <= 0.0 or _hold >= SKIP_HOLD_SECS:
				_finish()

func _finish() -> void:
	phase = Phase.DONE
	if night_clock != null:
		night_clock.end_night()  # 6 a.m.: what is left of tonight's cash is banked
	finished.emit(ends_night)
	if restart_on_finish and game_state != null:
		game_state.restart()

func _pick_line() -> String:
	if bad_cops and not last_free:
		return _pick("Dave", "bad_cops")
	return _pick("Dave", "total")

func _morning_lines() -> Array:
	if last_free:
		var out: Array = []
		for who in ["Moose", "Walt"]:
			var l := _pick(who, "first_total_morning")
			if l != "":
				out.append(l)
		return out
	var lines := [_pick("Ferris", "morning")]
	if last_loss > 0:
		lines.append("Lost on the road: %s" % wallet.money(last_loss))
	return lines

## A line from data/totalled_lines.json (speaker -> pool -> lines). The same
## line is never said twice in a row from one pool. "" when the pool is empty.
func _pick(speaker: String, pool: String) -> String:
	var lines: Array = _lines().get(speaker, {}).get(pool, [])
	if lines.is_empty():
		return ""
	var key := "%s/%s" % [speaker, pool]
	var last: String = _last_pick.get(key, "")
	var choices := lines.filter(func(l: Variant) -> bool: return str(l) != last)
	if choices.is_empty():
		choices = lines
	var line := str(choices[_rng.randi() % choices.size()])
	_last_pick[key] = line
	return line

static func _lines() -> Dictionary:
	if _lines_cache.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LINES_PATH))
		if parsed is Dictionary:
			_lines_cache = parsed
		else:
			push_warning("run_end: %s is missing or not a JSON object; no totalled lines" % LINES_PATH)
	return _lines_cache

## Walt's free fix: every broken part, the powertrain and the meter, no bill.
func _repair() -> void:
	if player == null:
		return
	var damage: Variant = player.get("damage")
	if damage != null:
		damage.garage_repair(null)
	var health: Variant = player.get("health")
	if health != null:
		health.repair()

## Right after the total: nobody is on the pedals. The car coasts to a stop on
## a light brake instead of locking up.
static func _totalled_driver(c: Node) -> void:
	c.set("throttle_input", 0.0)
	c.set("brake_input", TOTALLED_BRAKE)
	c.set("clutch_input", 0.0)

## After the totalling beat: nobody is driving it, it is held on the brake.
static func _wrecked_driver(c: Node) -> void:
	c.set("throttle_input", 0.0)
	c.set("brake_input", 1.0)
	c.set("clutch_input", 0.0)

func _cut_buses() -> void:
	for bus_name in CUT_BUSES:
		var bus := AudioServer.get_bus_index(bus_name)
		if bus >= 0 and not _was_muted.has(bus_name):
			_was_muted[bus_name] = AudioServer.is_bus_mute(bus)
			AudioServer.set_bus_mute(bus, true)

func _restore_buses() -> void:
	for bus_name in _was_muted:
		var bus := AudioServer.get_bus_index(bus_name)
		if bus >= 0:
			AudioServer.set_bus_mute(bus, _was_muted[bus_name])
	_was_muted.clear()
