class_name CanSim
extends RefCounted

# The beer cans on the passenger footwell floor (MA6): a 2D model in car space,
# NOT a RigidBody3D. Each can is a circle of radius R on a rectangle of floor;
# the car's acceleration pushes them (they slide forward when it brakes, back
# when it launches, sideways in a corner), rolling friction slows them, and
# they bounce off the four walls and each other. Every contact calls
# on_contact(strength 0..1) for the clink. Over rough road the cans get small
# random kicks (the rattle).
#
# Asleep: when nothing moves and the push is under what holds a can still
# (STATIC_A), step() returns at once, so a parked or cruising car costs
# nothing. Six cans awake cost a few tens of microseconds a tick
# (tests/car/cabin_dirt.gd prints the measured figure).

const MAX_CANS := 6
const R := 0.05                  # footprint radius of a lying can, m
const STATIC_A := 2.4            # m/s^2: a push below this does not start a can rolling
const ROLL_DECEL := 1.3          # m/s^2 of rolling friction on a moving can
const REST_WALL := 0.35
const REST_CAN := 0.5
const REST_SPEED := 0.03         # m/s: slower than this counts as stopped
const MIN_CONTACT := 0.12        # m/s of closing speed that is worth a clink
const FULL_CONTACT := 2.0        # m/s that clinks at full strength

var count := 0
var px := PackedFloat32Array()
var pz := PackedFloat32Array()
var vx := PackedFloat32Array()
var vz := PackedFloat32Array()
var yaw := PackedFloat32Array()   # each can's own heading, for the mesh
var roll := PackedFloat32Array()  # how far it has rolled, rad
## Floor rectangle the centres may use (already shrunk by R), car space.
var x0 := 0.2
var x1 := 0.6
var z0 := -0.5
var z1 := 0.1
var asleep := true
var on_contact := Callable()
var steps := 0                    # steps that did real work (tests)
var contacts := 0
var _seed := 12345

func _init() -> void:
	px.resize(MAX_CANS)
	pz.resize(MAX_CANS)
	vx.resize(MAX_CANS)
	vz.resize(MAX_CANS)
	yaw.resize(MAX_CANS)
	roll.resize(MAX_CANS)

## The footwell's floor in car space; the centres are kept R inside it.
func configure(left: float, right: float, front: float, back: float) -> void:
	x0 = left + R
	x1 = right - R
	z0 = front + R
	z1 = back - R
	for i in count:
		px[i] = clampf(px[i], x0, x1)
		pz[i] = clampf(pz[i], z0, z1)

func clear() -> void:
	count = 0
	asleep = true

## A can lands on the floor at (x, z). A full floor loses its oldest can.
func add(x: float, z: float, vel_x := 0.0, vel_z := 0.0) -> void:
	if count >= MAX_CANS:
		for i in MAX_CANS - 1:
			px[i] = px[i + 1]
			pz[i] = pz[i + 1]
			vx[i] = vx[i + 1]
			vz[i] = vz[i + 1]
			yaw[i] = yaw[i + 1]
			roll[i] = roll[i + 1]
		count = MAX_CANS - 1
	var i := count
	px[i] = clampf(x, x0, x1)
	pz[i] = clampf(z, z0, z1)
	vx[i] = vel_x
	vz[i] = vel_z
	yaw[i] = _rand() * TAU
	roll[i] = 0.0
	count += 1
	asleep = false

## n cans lying about the floor, the same every time (a car loaded from a save).
func scatter(n: int) -> void:
	count = 0
	var saved := _seed
	_seed = 777
	for i in clampi(n, 0, MAX_CANS):
		add(lerpf(x0, x1, _rand()), lerpf(z0, z1, _rand()))
	_seed = saved
	for i in count:
		vx[i] = 0.0
		vz[i] = 0.0
	asleep = true

func _rand() -> float:
	_seed = (_seed * 1103515245 + 12345) & 0x7fffffff
	return float(_seed % 10007) / 10006.0

func wake() -> void:
	asleep = false

## One tick. (ax, az) is the car's own acceleration in car space (m/s^2, -z is
## forward), `rough` 0..1 how hard the road is jolting it.
func step(dt: float, ax: float, az: float, rough: float) -> void:
	if count == 0:
		return
	var push := Vector2(-ax, -az)   # what the cans feel: the opposite of the car's
	var push_len := push.length()
	if asleep:
		if push_len < STATIC_A and rough < 0.05:
			return
		asleep = false
	steps += 1
	if rough > 0.05 and _rand() < 0.35 * rough:
		var k := int(_rand() * count) % count
		vx[k] += (_rand() - 0.5) * 0.7 * rough
		vz[k] += (_rand() - 0.5) * 0.7 * rough
	var busy := false
	for i in count:
		var vel := Vector2(vx[i], vz[i])
		var sp := vel.length()
		if sp < REST_SPEED and push_len < STATIC_A:
			vx[i] = 0.0
			vz[i] = 0.0
			continue
		vel += push * dt
		sp = vel.length()
		if sp > 0.0:
			vel *= maxf(sp - ROLL_DECEL * dt, 0.0) / sp
		px[i] += vel.x * dt
		pz[i] += vel.y * dt
		var hit := 0.0
		if px[i] < x0:
			px[i] = x0
			hit = maxf(hit, -vel.x)
			vel.x = absf(vel.x) * REST_WALL
		elif px[i] > x1:
			px[i] = x1
			hit = maxf(hit, vel.x)
			vel.x = -absf(vel.x) * REST_WALL
		if pz[i] < z0:
			pz[i] = z0
			hit = maxf(hit, -vel.y)
			vel.y = absf(vel.y) * REST_WALL
		elif pz[i] > z1:
			pz[i] = z1
			hit = maxf(hit, vel.y)
			vel.y = -absf(vel.y) * REST_WALL
		if hit > MIN_CONTACT:
			_contact(hit)
		vx[i] = vel.x
		vz[i] = vel.y
		# it rolls about its own axis by the way it travels across it
		roll[i] += (vel.x * -sin(yaw[i]) + vel.y * -cos(yaw[i])) * dt / 0.031
		if vel.length() > REST_SPEED:
			busy = true
	# can against can: equal masses, a soft bounce, then pushed apart
	for i in count:
		for j in range(i + 1, count):
			var dx := px[j] - px[i]
			var dz := pz[j] - pz[i]
			var d2 := dx * dx + dz * dz
			if d2 >= 4.0 * R * R:
				continue
			var d := sqrt(d2)
			var nx := 1.0
			var nz := 0.0
			if d > 0.0001:
				nx = dx / d
				nz = dz / d
			var over := 2.0 * R - d
			px[i] = clampf(px[i] - nx * over * 0.5, x0, x1)
			pz[i] = clampf(pz[i] - nz * over * 0.5, z0, z1)
			px[j] = clampf(px[j] + nx * over * 0.5, x0, x1)
			pz[j] = clampf(pz[j] + nz * over * 0.5, z0, z1)
			var closing := (vx[i] - vx[j]) * nx + (vz[i] - vz[j]) * nz
			if closing > 0.0:
				var imp := closing * (1.0 + REST_CAN) * 0.5
				vx[i] -= nx * imp
				vz[i] -= nz * imp
				vx[j] += nx * imp
				vz[j] += nz * imp
				if closing > MIN_CONTACT:
					_contact(closing)
				busy = true
	if not busy and push_len < STATIC_A and rough < 0.05:
		asleep = true
		for i in count:
			vx[i] = 0.0
			vz[i] = 0.0

func _contact(speed: float) -> void:
	contacts += 1
	if on_contact.is_valid():
		on_contact.call(clampf(speed / FULL_CONTACT, 0.1, 1.0))
