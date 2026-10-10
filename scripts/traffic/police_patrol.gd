class_name PolicePatrol
extends Node3D

# Keeps one stand-in patrol car (PatrolCar) on the road, F1 of the police
# build plan. It appears out past the reveal distance, in fog, never in view
# (the same rule as traffic: tests/traffic/no_visible_spawn.gd), alternating
# oncoming and same-direction lanes, at that lane's traffic speed. Once it is
# well behind or far off, it goes and the next one comes PATROL_GAP later.
# Every patrol is registered with PoliceHeat, which decides what it sees.
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
	var d := absf(RoadFrame.unroll(car.global_position).z - _player_z())
	# Full crash physics near the player only, the rails further out, like
	# traffic (it used to run the full sim for its whole 300 m life).
	traffic.tier(car, d)
	if d > traffic.reveal_distance() + DROP_PAST_REVEAL and not traffic.in_view(car.global_position):
		drop()

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
	var speed := traffic.lane_speed(lane, oncoming)
	var z := _player_z() - (traffic.reveal_distance() + SPAWN_PAST_REVEAL)
	var c := PatrolCar.make()
	c.name = "Patrol%d" % spawn_count
	c.traffic = traffic
	c.target_speed = speed
	if traffic.in_view(RoadFrame.roll(Vector3(lane_x, c.rest_y, z))) or traffic._slot_check(c, lane_x, z, dir, speed).is_empty():
		c.free()
		return false
	add_child(c)
	c.place(lane_x, dir, z, c.rest_y, speed)
	car = c
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
	car.queue_free()
	car = null
	_wait = PATROL_GAP

## Floating origin (game.gd): moves with the world like a traffic car.
func shift_world(offset: Vector3) -> void:
	if car != null and is_instance_valid(car):
		car.shift_world(offset)

func _player_z() -> float:
	return RoadFrame.unroll(player.global_position).z
