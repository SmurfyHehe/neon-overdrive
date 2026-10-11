extends RefCounted

# Shared pieces for the rival driver tests (tests/traffic/rival_*.gd): boots
# the real Game.tscn on a fixed road with no traffic, puts a racing driver on
# the road, and keeps the player parked a fixed distance from it so the world
# is built around the rival while the player does nothing.

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const SILVER := Color("#C9CED6")

## The environment every rival test runs in. `road`: RoadAlignment.scripted
## entries ([] = the seeded random road, NEON_ROAD_SEED).
static func env(road: Array, road_seed := 5) -> void:
	Engine.physics_ticks_per_second = 120
	OS.set_environment("NEON_POLICE", "0")
	OS.set_environment("NEON_CURVES", "1")
	OS.set_environment("NEON_HILLS", "0")
	OS.set_environment("NEON_LAYOUT", "0")
	OS.set_environment("NEON_ROAD", "endless")
	OS.set_environment("NEON_ROAD_SEED", str(road_seed))
	OS.set_environment("NEON_WEATHER", "dry")
	OS.set_environment("NEON_MUTE", "1")
	OS.set_environment("NEON_RACE", "")
	RoadAlignment.scripted = road

## A fresh game. No floating-origin shift (recenter far away), so two boots
## put the rival at the same world coordinates whatever the player does.
static func boot(tree: SceneTree) -> Node:
	return Harness.boot(tree, 0, 300.0, 1, 1.0e9)

static func ready(game: Node) -> bool:
	return game != null and game.get("race") != null and game.get("player") != null and game.get("traffic") != null

static func teardown(game: Node) -> void:
	if game != null and is_instance_valid(game):
		game.get_parent().remove_child(game)
		game.queue_free()

## Absolute road distance of a body, m.
static func s_of(n: Node3D) -> float:
	return RoadFrame.s_at(RoadFrame.unroll(n.global_position).z)

static func z_of(s: float) -> float:
	return float(RoadFrame.origin_index) * RoadFrame.L - s

## A racing driver in `kind` at road distance s, lane `lane`, doing `speed`.
static func spawn_rival(game: Node, kind: String, lane: int, s: float, speed: float, commit: float, seed_value: int, car_spec := {}) -> TrafficCar:
	var t: TrafficManager = game.traffic
	t.pinned_distance = 1.0e6
	var car := t.add_rival(kind, TrafficManager.lane_centre(lane, false), z_of(s), speed, SILVER, car_spec)
	var row := RivalPersonality.row(RivalPersonality.DOCKS)
	row.commit = commit
	car.racer = RivalDriver.new(row, seed_value)
	car.racer.setup(car)
	return car

## Stops the player driving itself: brakes on, nothing else.
static func hold_player(p: PlayerCar) -> void:
	p.driver = func(c: PlayerCar) -> void:
		c.throttle_input = 0.0
		c.brake_input = 1.0
		c.steering_input = 0.0
		c.handbrake_input = 0.0

## Stands the player still at road distance s, x across.
static func park_player(p: PlayerCar, x: float, s: float, y: float) -> void:
	p.global_transform = RoadFrame.pose(x, y, z_of(s), 0.0)
	p.angular_velocity = Vector3.ZERO
	TrafficCar.set_moving(p, 0.0)
	for w in p.wheel_array:
		w.last_collision_point = w.global_position
	p.reset_physics_interpolation()
