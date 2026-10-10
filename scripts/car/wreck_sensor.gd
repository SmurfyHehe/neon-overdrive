extends Node

# Watches the player's car for a hard hit (wreck_rules.gd). Every physics tick
# it reads the car's contacts; the first tick a thing touches the car, it
# works out how fast the two were closing along the contact, turns that into a
# wall speed with the other thing's mass, and reports the outcome.
#
# The contacts a tick shows were already solved by the physics step before
# it, so the speeds read now are the speeds AFTER the hit. The closing speed
# comes from the tick before: the player's own velocity is kept from last
# tick, and the other car's is worked back from its speed now and what the
# hit took from the player (momentum is kept across the hit).
#
# The road under the car is not a hit (a mostly vertical contact, as in
# CarDamage and CrashAudio), so a landing never ends a run.
# No class_name on purpose: preload it, so no class cache refresh is needed.

const WreckRules := preload("res://scripts/car/wreck_rules.gd")

## A hit at or over the wreck threshold. Speeds in km/h; `other` is the thing
## hit (a TrafficCar, a wall body, or null if it is already gone).
signal wrecked(outcome: int, wall_kmh: float, closing_kmh: float, other: Object)

## A contact flatter than this (normal.y) is the road, not a wall.
const GROUND_NORMAL_Y := 0.6

var player: RigidBody3D
var enabled := true

## The last new contact, bump or not, for tests and the debug overlay.
var last_wall_kmh := 0.0
var last_closing_kmh := 0.0
var hits := 0

var _prev_vel := Vector3.ZERO
var _have_prev := false
var _touching := {}  # instance id -> true, the things touched last tick

func _init(car: RigidBody3D) -> void:
	player = car

func _physics_process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var vel := player.linear_velocity
	if enabled and _have_prev:
		_read(vel)
	_prev_vel = vel
	_have_prev = true

func _read(vel: Vector3) -> void:
	var st := PhysicsServer3D.body_get_direct_state(player.get_rid())
	if st == null:
		return
	var now := {}
	var worst := 0.0
	var worst_closing := 0.0
	var worst_obj: Object = null
	for i in st.get_contact_count():
		var obj := st.get_contact_collider_object(i)
		var normal := st.get_contact_local_normal(i)
		var body := obj as RigidBody3D
		var moving := body != null and not body.freeze
		if not moving and absf(normal.y) > GROUND_NORMAL_Y:
			continue  # the road
		var id := st.get_contact_collider_id(i)
		now[id] = true
		if _touching.has(id):
			continue  # still leaning on it: the hit was judged when it began
		var other_before := Vector3.ZERO
		var other_mass := 0.0
		if moving:
			other_mass = body.mass
			other_before = body.linear_velocity + (vel - _prev_vel) * (player.mass / body.mass)
		var closing := absf((_prev_vel - other_before).dot(normal))
		var wall := WreckRules.wall_speed(closing, player.mass, other_mass)
		if wall > worst:
			worst = wall
			worst_closing = closing
			worst_obj = obj
	var fresh := false
	for id in now:
		if not _touching.has(id):
			fresh = true
	_touching = now
	if not fresh:
		return
	hits += 1
	last_wall_kmh = worst * 3.6
	last_closing_kmh = worst_closing * 3.6
	var result := WreckRules.outcome(last_wall_kmh)
	if result != WreckRules.Outcome.BUMP:
		wrecked.emit(result, last_wall_kmh, last_closing_kmh, worst_obj)
