extends Node

# Ending a run on a crash (decided 2026-10-10). Listens to the wreck sensor
# (scripts/car/wreck_sensor.gd), applies the rules (wreck_rules.gd) and plays
# the crash screen (scripts/ui/crash_screen.gd):
#
#   hit      the money is settled at once, the car's controls are taken away,
#            the view goes to the driver's own seat, the camera shakes, the
#            glass cracks and the ears ring
#   black    hard cut to black; every game sound stops except a scrape tail
#   line     Dale's line (and what the wreck cost)
#   morning  only when the night ended: the first wreck (Moose and Walt, free,
#            once per save) or a huge crash. Hold S to skip it.
#   restart  a fresh run; after a morning it is the next night
#
# The tree is never paused and the time scale never changes: no slow motion.
# The player never leaves the car: the only camera used is the cockpit one.
#
# Cars only for now. Bikes, the trike and the monster truck get their own
# hooks later; bad cops set `bad_cops` once the police build has that state.
# No class_name on purpose: preload it, so no class cache refresh is needed.

const WreckRules := preload("res://scripts/car/wreck_rules.gd")
const WreckSensor := preload("res://scripts/car/wreck_sensor.gd")
const CrashScreen := preload("res://scripts/ui/crash_screen.gd")
const SaveStore := preload("res://scripts/save/save_store.gd")

enum Phase { DRIVING, HIT, BLACK, LINE, MORNING, DONE }

const HIT_SECS := 0.9      # shake, cracked glass, ring
const BLACK_SECS := 1.6    # black with the scrape tail, before Dale speaks
const LINE_SECS := 4.5
const MORNING_SECS := 12.0  # the morning card moves on by itself after this
const SKIP_HOLD_SECS := 0.7
const SKIP_ACTION := &"brake"  # S

## Everything in the world goes quiet at the cut; the crash screen's own
## sounds are on the UI bus.
const CUT_BUSES := [&"Engine", &"Turbo", &"Music", &"Tires", &"World", &"Traffic", &"Sirens", &"Scanner"]

# Placeholder lines (the story is Roy's to write).
const WRECK_LINES := [
	"Scanner says a car just folded itself up out on the highway. If that was you: breathe. The road will still be there.",
	"Wreck on the highway, one car, no hurry. Somebody's night just got shorter.",
	"Hearing about bent metal out on the loop. Whoever you are, it's only a car. Mostly.",
]
const NIGHT_END_LINES := [
	"They're closing a lane for a wreck out there. A big one. Whoever was driving is done for tonight.",
	"That's a tow truck night for somebody. Go home. It'll be dark again tomorrow.",
]
const BAD_COP_LINE := "Word is the first car at that wreck had its lights off and its hand out. Check your pockets."
const FIRST_MORNING := [
	"Moose came out with the truck and brought you home.",
	"Walt had the car straight by sunrise. This one is on him. The next one is not.",
]
const NIGHT_END_MORNING := "The car came home on a hook."

## A wreck began: what it was (WreckRules.Outcome), what it took from tonight's
## cash, and whether it was the free first one.
signal wreck_started(outcome: int, loss: int, free: bool)
signal finished(night_ended: bool)

var player: Node3D
var camera: Camera3D
var wallet: Node
var night_clock: Node
var game_state: GameState

## Bad cops are on the player right now: a wreck costs all of tonight's cash.
## The police build sets this; nothing does yet.
var bad_cops := false
## Tests turn this off: they do not run as the current scene, so there is
## nothing to reload.
var restart_on_finish := true

var sensor: WreckSensor
var screen: CrashScreen
var phase := Phase.DRIVING
var last_outcome := WreckRules.Outcome.BUMP
var last_loss := 0
var last_free := false
var ends_night := false

var _left := 0.0
var _hold := 0.0
var _line := ""
var _was_muted := {}
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	sensor = WreckSensor.new(player as RigidBody3D)
	sensor.wrecked.connect(func(outcome: int, _wall: float, _closing: float, _other: Object) -> void: begin(outcome))
	add_child(sensor)
	screen = CrashScreen.new()
	add_child(screen)

func _exit_tree() -> void:
	_restore_buses()

## Ends the run now. True when it did (false while a wreck is already playing,
## or while a menu is open).
func begin(outcome: int) -> bool:
	if phase != Phase.DRIVING or outcome == WreckRules.Outcome.BUMP:
		return false
	if game_state != null and not game_state.wreck():
		return false
	last_outcome = outcome
	last_free = not SaveStore.first_wreck_used()
	last_loss = 0
	if wallet != null:
		last_loss = wallet.take_cash(WreckRules.cash_loss(wallet.cash, bad_cops, last_free))
	if last_free:
		SaveStore.mark_first_wreck()
		_repair()
	ends_night = last_free or outcome == WreckRules.Outcome.NIGHT_END
	_line = _pick_line()
	sensor.enabled = false
	if player != null:
		player.set("driver", _wrecked_driver)
	if camera is ChaseCamera:
		(camera as ChaseCamera).set_view(ChaseCamera.View.COCKPIT)
		(camera as ChaseCamera).trauma = 1.0
	screen.crack(_rng.randi())
	phase = Phase.HIT
	_left = HIT_SECS
	wreck_started.emit(outcome, last_loss, last_free)
	return true

func _process(delta: float) -> void:
	if phase == Phase.DRIVING or phase == Phase.DONE:
		return
	_left -= delta
	match phase:
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
				if ends_night:
					screen.card("MORNING", _morning_lines())
					phase = Phase.MORNING
					_left = MORNING_SECS
				else:
					_finish()
		Phase.MORNING:
			_hold = _hold + delta if Input.is_action_pressed(SKIP_ACTION) else 0.0
			screen.set_hold(_hold / SKIP_HOLD_SECS)
			if _left <= 0.0 or _hold >= SKIP_HOLD_SECS:
				_finish()

func _finish() -> void:
	phase = Phase.DONE
	if ends_night and night_clock != null:
		night_clock.end_night()  # 6 a.m.: what is left of tonight's cash is banked
	finished.emit(ends_night)
	if restart_on_finish and game_state != null:
		game_state.restart()

func _pick_line() -> String:
	if bad_cops and not last_free:
		return BAD_COP_LINE
	var lines := NIGHT_END_LINES if last_outcome == WreckRules.Outcome.NIGHT_END else WRECK_LINES
	return lines[_rng.randi() % lines.size()]

func _morning_lines() -> Array:
	if last_free:
		return FIRST_MORNING
	var lines := [NIGHT_END_MORNING]
	if last_loss > 0:
		lines.append("Lost on the road: %s" % wallet.money(last_loss))
	return lines

## Walt's free fix: every broken part and the powertrain, no bill.
func _repair() -> void:
	if player == null:
		return
	var damage: Variant = player.get("damage")
	if damage != null:
		damage.garage_repair(null)
	var health: Variant = player.get("health")
	if health != null:
		health.repair()

## The car after the hit: nobody is driving it. It rolls to a stop on the brake.
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
