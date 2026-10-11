class_name PolicePatrol
extends Node3D

# Keeps one stand-in patrol car (PatrolCar) on the road, F1 of the police
# build plan. It appears out past the reveal distance, in fog, never in view
# (the same rule as traffic: tests/traffic/no_visible_spawn.gd), alternating
# oncoming and same-direction lanes, at that lane's traffic speed. Once it is
# well behind or far off, it goes and the next one comes PATROL_GAP later.
# Every patrol is registered with PoliceHeat, which decides what it sees.
#
# Since police step P5 the patrol has a CopBrain: at heat 1 it chases (lights
# on, the free driver), loses you, searches, or calls the chase off; and this
# node runs the bust ring (under 10 km/h with a chasing cop within 6 m for
# 3 s). The car is in the traffic index (TrafficManager.adopt), so traffic
# sees it. A patrol in a chase is never dropped.
#
# NEON_POLICE=0 turns it off (tests/run_tests.bat does, so older drive tests
# meet no cop); the benchmark never has one.

const PATROL_GAP := 25.0       # s between one patrol leaving and the next
const SPAWN_PAST_REVEAL := 40.0
const DROP_PAST_REVEAL := 60.0
const RETRY := 1.0

var player: Node3D
var traffic: TrafficManager
var heat: PoliceHeat
var car: PatrolCar
var oncoming_next := true
var spawn_count := 0
var _wait := 3.0               # first patrol a few seconds in

## The chase began (the first cop went into Pursuit) / ended: escaped = heat
## cooled to nothing, not escaped = busted.
signal pursuit_started
signal pursuit_ended(escaped: bool)
## The bust ring filled. What a bust costs (ticket, tow, night one's warning)
## is the bust stage's; this only ends the chase and clears the heat.
signal busted(cop: Node3D)

var brain: CopBrain
var ghost: Node3D
## The bust ring, 0..1 (HeatIcons draws it).
var bust_fill := 0.0
var chasing := false
var busts := 0
var escapes := 0
## Game hook: whether the road has no centre barrier at road z.
var undivided_at := Callable()
var _brain_acc := 0.0

static func enabled(benchmark: bool) -> bool:
	return not benchmark and OS.get_environment("NEON_POLICE") != "0"

func _physics_process(delta: float) -> void:
	if player == null or traffic == null:
		return
	if car != null and not is_instance_valid(car):
		car = null
	if car == null:
		_wait -= delta
		if _wait <= 0.0:
			_wait = RETRY
			spawn()
		return
	var cz := car.road_z()
	var d := absf(cz - _player_z())
	# Shown, hidden and put on the rails by the traffic manager (adopted): full
	# crash physics within its pinned distance of the player, the rails beyond.
	_brain_acc += delta
	if _brain_acc >= 1.0 / PoliceRules.BRAIN_HZ:
		brain.step(_brain_acc)
		_brain_acc = 0.0
	if brain.driver != null and brain.driver.recycle_due:
		brain.driver.recycle(car)   # stuck or flipped 5 s: back behind the player, out of view
	_chase_step(delta)
	if brain.state == CopBrain.State.PATROL and not chasing and d > traffic.reveal_distance() + DROP_PAST_REVEAL and not traffic.in_view(car.global_position):
		drop()

## The chase as a whole: started, the bust ring, escaped.
func _chase_step(delta: float) -> void:
	var on := heat != null and heat.level >= PoliceHeat.ONE_CAR
	if on and not chasing and brain.in_chase():
		chasing = true
		bust_fill = 0.0
		pursuit_started.emit()
	if not chasing:
		bust_fill = 0.0
		return
	if not on:
		chasing = false
		bust_fill = 0.0
		escapes += 1
		pursuit_ended.emit(true)
		return
	var cop_dist := INF
	if brain.in_chase() and car.detailed:
		cop_dist = maxf(car.global_position.distance_to(player.global_position) - PoliceRules.BUST_BODY, 0.0)
	bust_fill = PoliceRules.bust_step(bust_fill, delta, absf(heat._kmh_of(player)), cop_dist)
	if bust_fill >= 1.0:
		chasing = false
		bust_fill = 0.0
		busts += 1
		heat.bust()
		brain.step(0.0)   # heat is gone: back to Patrol, lights off
		busted.emit(car)
		pursuit_ended.emit(false)

## Puts a patrol car on the road now, if a slot is free. True if placed.
func spawn() -> bool:
	if car != null:
		return false
	var oncoming := oncoming_next
	var lane := 0
	if not traffic.lane_allowed(lane, oncoming):
		var used := traffic.onc_lanes_used if oncoming else traffic.own_lanes_used
		if used.is_empty():
			return false
		lane = used[0]
	var lane_x := TrafficManager.lane_centre(lane, oncoming)
	var dir := 1.0 if oncoming else -1.0
	var z := _player_z() - (traffic.reveal_distance() + SPAWN_PAST_REVEAL)
	var city := traffic.city_at(z, dir)
	var speed := traffic.lane_speed(lane, oncoming, city)
	var c := PatrolCar.make()
	c.name = "Patrol%d" % spawn_count
	c.traffic = traffic
	c.target_speed = speed
	c.pace_lane = lane
	c.pace_far = oncoming
	c.pace_city = city
	if traffic.in_view(RoadFrame.roll(Vector3(lane_x, c.rest_y, z))) or traffic._slot_check(c, lane_x, z, dir, speed).is_empty():
		c.free()
		return false
	add_child(c)
	c.place(lane_x, dir, z, c.rest_y, speed)
	traffic.adopt(c)
	car = c
	if ghost == null:
		ghost = Node3D.new()
		ghost.name = "LastSeen"
		add_child(ghost)
	brain = CopBrain.new(c, heat, traffic, player, ghost)
	brain.undivided_at = undivided_at
	spawn_count += 1
	oncoming_next = not oncoming_next
	if heat != null:
		heat.register_cop(c)
	return true

func drop() -> void:
	if car == null:
		return
	if heat != null:
		heat.unregister_cop(car)
	traffic.disown(car)
	car.free_driver = null
	brain = null
	car.queue_free()
	car = null
	_wait = PATROL_GAP

## Floating origin (game.gd): the car is in the traffic manager's list
## (adopted), which moves it with the world; nothing to do here.
func shift_world(_offset: Vector3) -> void:
	pass

func _player_z() -> float:
	return RoadFrame.unroll(player.global_position).z
