extends Node3D
class_name TrafficManager

# Milestone 3 traffic spawner (stage B step 3, 2026-10-05). Owns a fixed pool
# of TrafficCar nodes, places them in lanes ahead of the player, and recycles
# a car to a fresh slot ahead once it has fallen `recycle_behind` metres behind
# (or driven off past the chunk pool). The car count never changes except
# through set_car_count(); recycling moves cars, it never frees or creates
# them, the same pattern as game.gd's chunk pool.
#
# Lanes: the road is 4 lanes each way (game.gd), own lanes at positive x and
# oncoming at negative x, lane i centred at (i + 0.5) * RoadChunkBuilder.LANE_W.
# Cars never change lane (milestone 3), so a spawn slot is a (direction, lane,
# z) that keeps `lane_gap` to every other car in that lane and never lies
# within `spawn_min` of the player.
#
# Draw distance: cars further than `detail_distance` from the player run the
# frozen lane cruise (TrafficCar.set_detailed(false)) and are hidden; the pause
# menu's Traffic sliders set this and the car count live (TrafficSettings).

const LANE_W := RoadChunkBuilder.LANE_W

var player: Node3D
var own_lanes := 4
var onc_lanes := 4
var car_count := 40
## Beyond this many metres from the player a car is hidden and frozen.
var detail_distance := 300.0
## Spawn band ahead of the player, metres along the road.
var spawn_min := 60.0
var spawn_max := 240.0
## A car this far behind the player is recycled to a fresh slot ahead.
var recycle_behind := 60.0
## Minimum gap between cars in the same lane at spawn time (centre to centre;
## the cars are 3.4 m long). 15 m left too few slots for 80 cars when the
## test keeps one lane clear: 1679 deferred placements in 55 s.
var lane_gap := 12.0
## Random slot tries per placement before deferring to the next tick.
const SLOT_TRIES := 12
## Share of cars that drive the oncoming way.
var oncoming_share := 0.4
## Own-direction / oncoming lanes traffic may use; empty = all. Tests keep the
## player's lane clear with this.
var own_lanes_used: Array[int] = []
var onc_lanes_used: Array[int] = []
## Cruise speed per lane, m/s, lane 0 (next to the centre line, the passing
## lane in right-hand traffic) first: 115/100/85/70 km/h with the flow,
## 95/85/75/65 km/h oncoming, plus or minus SPEED_JITTER per car. Lane ordered
## on purpose: milestone 3 traffic cannot brake, so two cars in one lane must
## not close on each other faster than a nudge.
var lane_speeds_own: Array[float] = [31.9, 27.8, 23.6, 19.4]
var lane_speeds_onc: Array[float] = [26.4, 23.6, 20.8, 18.0]
const SPEED_JITTER := 0.3
## Spec every car is cloned from; empty = CarSpec.traffic_default(). Swap it
## (or hand each car its own in _make_car) for the three NPC cars later.
var spec_template := {}
var kind := "coupe"
var sim_only := false

var cars: Array[TrafficCar] = []
var spawn_count := 0
var recycle_count := 0
## Spawns that found no free slot this tick and will retry; tests watch it.
var deferred_count := 0
## Every placement, for the tests: {z, lane_x, direction, player_z, dist, gap}.
var spawn_log: Array[Dictionary] = []
var log_spawns := false

## Chassis origin height of a car settled on its springs on the flat road
## (origin is at y=0 with the springs fully extended, so it is negative).
## Measured by tests/traffic_spawn.gd, which prints the mean; cars are placed
## here so a spawn has no settling hop.
const REST_Y := -0.124

const PALETTE := [
	Color(0.62, 0.64, 0.67), Color(0.15, 0.16, 0.2), Color(0.55, 0.1, 0.1),
	Color(0.12, 0.2, 0.45), Color(0.8, 0.78, 0.7), Color(0.2, 0.35, 0.2),
	Color(0.45, 0.3, 0.15), Color(0.3, 0.3, 0.32),
]

func _ready() -> void:
	for i in car_count:
		_make_car()
	for car in cars:
		_respawn(car)

func _make_car() -> TrafficCar:
	var car := TrafficCar.new()
	car.kind = kind
	car.sim_only = sim_only
	car.color = PALETTE[randi() % PALETTE.size()]
	if not spec_template.is_empty():
		car.spec = CarSpec.clone_spec(spec_template)
	# Off the road and far behind until _respawn places it, so a car never
	# starts on the player.
	car.position = Vector3(0.0, REST_Y, 10000.0)
	add_child(car)
	cars.append(car)
	return car

func _physics_process(_delta: float) -> void:
	var pz := player.global_position.z
	for car in cars:
		var z := car.global_position.z
		if z > pz + recycle_behind or z < pz - spawn_max - RoadChunkBuilder.CHUNK_LEN:
			recycle_count += 1
			_respawn(car)
	for car in cars:
		car.set_detailed(absf(car.global_position.z - pz) <= detail_distance)

## Puts a car in a free slot ahead of the player. If every slot is taken it
## parks the car far behind (hidden, frozen) and tries again next tick.
func _respawn(car: TrafficCar) -> void:
	var pz := player.global_position.z
	var slot := _find_slot(car, pz)
	if slot.is_empty():
		deferred_count += 1
		car.set_detailed(false)
		car.place(car.lane_x, car.direction, pz + recycle_behind + 10000.0, REST_Y, 0.0)
		return
	spawn_count += 1
	car.target_speed = slot.speed
	car.set_detailed(slot.dist <= detail_distance)
	car.place(slot.lane_x, slot.direction, slot.z, REST_Y, slot.speed)
	if log_spawns:
		spawn_log.append({"z": slot.z, "lane_x": slot.lane_x, "direction": slot.direction,
			"player_z": pz, "dist": slot.dist, "gap": slot.gap})

func _find_slot(car: TrafficCar, pz: float) -> Dictionary:
	for attempt in SLOT_TRIES:
		var oncoming := randf() < oncoming_share
		var lanes: Array[int] = onc_lanes_used if oncoming else own_lanes_used
		var n_lanes := onc_lanes if oncoming else own_lanes
		var lane_i: int = lanes[randi() % lanes.size()] if not lanes.is_empty() else randi() % n_lanes
		var lane_x := lane_centre(lane_i, oncoming)
		var dir := 1.0 if oncoming else -1.0
		var z := pz - randf_range(spawn_min, spawn_max)
		var gap := _lane_gap(car, lane_x, z)
		if gap < lane_gap:
			continue
		return {"lane_x": lane_x, "direction": dir, "z": z, "dist": pz - z, "gap": gap,
			"speed": lane_speed(lane_i, oncoming) + randf_range(-SPEED_JITTER, SPEED_JITTER)}
	return {}

func lane_speed(lane_i: int, oncoming: bool) -> float:
	var speeds := lane_speeds_onc if oncoming else lane_speeds_own
	return speeds[mini(lane_i, speeds.size() - 1)]

## Closest other car in this lane, along the road.
func _lane_gap(car: TrafficCar, lane_x: float, z: float) -> float:
	var best := INF
	for other in cars:
		if other == car or not is_equal_approx(other.lane_x, lane_x):
			continue
		best = minf(best, absf(other.global_position.z - z))
	return best

static func lane_centre(lane_i: int, oncoming: bool) -> float:
	var x := (float(lane_i) + 0.5) * LANE_W
	return -x if oncoming else x

## Floating origin (game.gd): move every car with the world.
func shift_world(offset: Vector3) -> void:
	for car in cars:
		car.shift_world(offset)

## Live count change from the Settings sliders. Removes the cars furthest from
## the player first; new cars spawn ahead like any recycled one.
func set_car_count(n: int) -> void:
	n = maxi(n, 0)
	while cars.size() > n:
		var far: TrafficCar = cars[0]
		var pz := player.global_position.z
		for car in cars:
			if absf(car.global_position.z - pz) > absf(far.global_position.z - pz):
				far = car
		cars.erase(far)
		# queue_free() runs at the end of the frame, and a car added below could
		# be placed on top of this one in the meantime: park it out of the way
		# first (frozen, 50 km behind), out of the draft lookup too.
		far.set_detailed(false)
		far.remove_from_group("aero_vehicles")
		far.global_position.z += 50000.0
		far.queue_free()
	while cars.size() < n:
		_respawn(_make_car())
	car_count = n

func detailed_count() -> int:
	var n := 0
	for car in cars:
		if car.detailed:
			n += 1
	return n
