class_name RaceSession
extends Node

# Race core (RC1, docs/planning/races-rivals-plan-2026-10-09.md). One race at a
# time: your car against one rival on the endless road, from where you stand to
# a line `length_m` further along it. This node is the referee only. It never
# drives anything: who the rival is and how it drives (RC2's racing driver, or
# the scripted dummy below) is someone else's job, so the rule "the rival never
# reads the gap to the player" cannot be broken from here.
#
# Rules (plan section 3, Roy 2026-10-09):
# - Win: you cross the line first. Lose: the rival crosses first.
# - A wrecked or stuck rival does not end the race: you must still cross the
#   line (Roy 87). Nothing here watches for wrecks; a rival that never gets to
#   the line simply never wins.
# - Give up from the pause menu (Roy 88): a loss, no pay.
# - Busted mid-race (police, later): a loss. busted() is the hook.
# - No "gap too big" early finish: section 3 replaced it (the RC1 row in the
#   build-order table still lists it; section 3 is the newer rule).
# - Every race, won or lost, moves the night clock on 15 minutes. A win pays
#   `pay` into `winnings`, a stub until cash on you exists (run structure R1).
#
# Progress is distance along the road (RoadFrame road space plus the floating
# origin's whole chunks), so curves, hills and origin shifts do not move the
# line. The race is a pausable node: it stops with the game.

enum Phase { IDLE, RACING, FINISHED }
enum Result { NONE, WIN, LOSE, GIVE_UP, BUSTED }

signal started
signal finished(result: Result)
signal paid(amount: int)

## Game minutes a race takes off the night (living-world rule: a race = +15 min).
const CLOCK_MINUTES := 15.0
## The result caption stays up this long, real seconds.
const CAPTION_SECONDS := 6.0
## Scripted dummy rival (tests and NEON_RACE): lane 2 of our side, next to the
## player's spawn lane 1.
const DUMMY_LANE := 2

var phase := Phase.IDLE
var result := Result.NONE
var player: Node3D
var rival: Node3D
var rival_name := ""
var length_m := 0.0
var pay := 0
## The night clock to move on at the finish; null in bare tests.
var night_clock: NightClock
## Stub for cash on you: everything races have paid this session.
var winnings := 0
## Road distance of the start and the finish line, m.
var start_d := 0.0
var finish_d := 0.0
## Seconds since the start.
var elapsed := 0.0
## The finish caption ("" when none is showing) and how long it has left.
var caption := ""
var caption_left := 0.0
## True when this node spawned the rival (the dummy) and must shift and free it.
var owns_rival := false

## Distance along the road, m, counted from the road's start: unaffected by
## floating-origin shifts.
static func road_distance(p: Vector3) -> float:
	return float(RoadFrame.origin_index) * RoadFrame.L - RoadFrame.unroll(p).z

func is_racing() -> bool:
	return phase == Phase.RACING

## Starts a sprint from the player's position to `length` m down the road.
## Returns false (and changes nothing) while a race is already running.
func start(p_player: Node3D, p_rival: Node3D, length: float, p_pay: int = 0, p_name: String = "") -> bool:
	if phase == Phase.RACING or p_player == null or p_rival == null or length <= 0.0:
		return false
	if owns_rival and rival != null and rival != p_rival and is_instance_valid(rival):
		rival.queue_free()
		owns_rival = false
	player = p_player
	rival = p_rival
	length_m = length
	pay = p_pay
	rival_name = p_name
	start_d = road_distance(player.global_position)
	finish_d = start_d + length
	elapsed = 0.0
	result = Result.NONE
	caption = ""
	caption_left = 0.0
	phase = Phase.RACING
	started.emit()
	return true

## Distance from the start, m (negative behind the line). -INF for a car that
## is gone (untyped: a typed Node3D argument errors on a freed rival).
func progress(car: Variant) -> float:
	if not is_instance_valid(car) or not car is Node3D:
		return -INF
	return road_distance((car as Node3D).global_position) - start_d

## Player minus rival, m: positive while you lead. 0 outside a race.
func gap() -> float:
	if phase == Phase.IDLE or player == null or rival == null or not is_instance_valid(rival):
		return 0.0
	return progress(player) - progress(rival)

## Metres left to the line for the player.
func to_go() -> float:
	return maxf(length_m - progress(player), 0.0)

func _physics_process(delta: float) -> void:
	tick(delta)

## One referee step. Public so tests can step without a physics loop.
func tick(delta: float) -> void:
	if caption_left > 0.0:
		caption_left -= delta
		if caption_left <= 0.0:
			caption = ""
	if phase != Phase.RACING:
		return
	elapsed += delta
	var over_p := progress(player) - length_m
	var over_r := progress(rival) - length_m
	if over_p >= 0.0 and over_r >= 0.0:
		# Both over in one tick: whoever is further past crossed first.
		_finish(Result.WIN if over_p >= over_r else Result.LOSE)
	elif over_p >= 0.0:
		_finish(Result.WIN)
	elif over_r >= 0.0:
		_finish(Result.LOSE)

## Pause menu "Give up" (Roy 88). Does nothing outside a race.
func give_up() -> void:
	if phase == Phase.RACING:
		_finish(Result.GIVE_UP)

## Busted mid-race: a loss (the bust rules themselves belong to the police plan).
func busted() -> void:
	if phase == Phase.RACING:
		_finish(Result.BUSTED)

func _finish(r: Result) -> void:
	phase = Phase.FINISHED
	result = r
	if r == Result.WIN and pay > 0:
		winnings += pay
		paid.emit(pay)
	if night_clock != null:
		night_clock.add_minutes(CLOCK_MINUTES)
	caption = result_text(r, pay)
	caption_left = CAPTION_SECONDS
	finished.emit(r)

static func result_text(r: Result, amount: int) -> String:
	match r:
		Result.WIN:
			return "You won  +$%d" % amount if amount > 0 else "You won"
		Result.LOSE:
			return "You lost"
		Result.GIVE_UP:
			return "You gave up"
		Result.BUSTED:
			return "Busted. Race lost"
	return ""

## Floating-origin shift (game.gd): a rival this node spawned is not traffic,
## so nobody else moves it.
func shift_world(offset: Vector3) -> void:
	if owns_rival and rival != null and is_instance_valid(rival) and rival.has_method("shift_world"):
		rival.shift_world(offset)

## Scripted dummy rival (RC1 only, until RC2's racing driver): a traffic car
## that holds lane DUMMY_LANE at `speed` m/s and sees nothing (no occupancy
## index, so no braking for traffic and no lane changes). Placed level with
## the player, rolling at the player's speed. Run it on an empty road.
func spawn_dummy(parent: Node, p_player: Node3D, speed: float) -> TrafficCar:
	var car := TrafficCar.new()
	car.kind = "n2_cityhatch"
	car.color = Color("#FFC066")
	car.target_speed = speed
	parent.add_child(car)
	var z := RoadFrame.unroll(p_player.global_position).z
	var v: float = p_player.linear_velocity.length() if p_player is RigidBody3D else 0.0
	car.place(TrafficManager.lane_centre(DUMMY_LANE, false), -1.0, z, car.rest_y, v)
	if owns_rival and rival != null and is_instance_valid(rival):
		rival.queue_free()
	rival = car
	owns_rival = true
	return car

## Dummy race in one call: spawn the dummy next to the player and start.
func start_dummy(parent: Node, p_player: Node3D, length: float, rival_speed: float, p_pay: int = 0) -> bool:
	if phase == Phase.RACING:
		return false
	var car := spawn_dummy(parent, p_player, rival_speed)
	return start(p_player, car, length, p_pay, "Dummy")
