extends RefCounted

# Shared by the car/auto_* tests and tools/auto_box_measure.gd: a bare flat (or
# sloped) pad and a sim_only PlayerCar on it, driven by plain numbers. Same
# simulation as the game's car, no body mesh, no audio, no road chunks.

const KMH := 3.6

## What the test's hands and feet are doing; PlayerCar calls drive() every tick.
class Pedals extends RefCounted:
	var throttle := 0.0
	var brake := 0.0
	var steer := 0.0   # + = right, share of lock (GEVP's own sign is flipped here)
	func drive(c: PlayerCar) -> void:
		c.throttle_input = throttle
		c.brake_input = brake
		c.steering_input = -signf(steer) * pow(absf(steer), 1.0 / maxf(c.steering_exponent, 0.1))

## A big slab of road. grade > 0 climbs in the driving direction (-Z).
static func ground(parent: Node, grade := 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.add_to_group("Road")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1200.0, 2.0, 12000.0)
	shape.shape = box
	shape.position = Vector3(0.0, -1.0, 0.0)
	body.add_child(shape)
	body.rotation.x = atan(grade)
	parent.add_child(body)
	return body

## A player car of `kind` in a gearbox mode (PlayerCar.Transmission), with the
## spec overrides applied (e.g. {"auto": {"family": "modern"}}).
static func car(parent: Node, kind: String, mode: int, pedals: Pedals, overrides := {}, at := Vector3(0.0, 0.4, 0.0)) -> PlayerCar:
	var c := PlayerCar.new()
	c.sim_only = true
	c.spec = CarSpec.player_spec(kind)
	for k in overrides:
		c.spec[k] = overrides[k]
	c.driver = pedals.drive
	c.position = at
	parent.add_child(c)
	c.set_transmission_mode(mode)
	return c

static func kmh(c: PlayerCar) -> float:
	return c.current_speed() * KMH

## Engine rpm the gearbox input shaft turns at (wheel speed through the gear).
static func gearbox_rpm(c: PlayerCar) -> float:
	return c.get_drivetrain_spin() * c.get_gear_ratio(c.current_gear) * Vehicle.ANGULAR_VELOCITY_TO_RPM

## Let `secs` of physics go by.
static func wait(tree: SceneTree, secs: float) -> void:
	for i in maxi(roundi(secs * Engine.physics_ticks_per_second), 1):
		await tree.physics_frame

static func remove(tree: SceneTree, c: PlayerCar) -> void:
	c.queue_free()
	await tree.physics_frame
	await tree.physics_frame

## Brake on while the suspension settles, then everything released.
static func settle(tree: SceneTree, pedals: Pedals, secs := 1.0) -> void:
	pedals.throttle = 0.0
	pedals.steer = 0.0
	pedals.brake = 1.0
	await wait(tree, secs)
	pedals.brake = 0.0
