class_name EmberFlick
extends Node3D

# A cigarette end flicked out of a car window (MA5, T9 + Roy 1378): an orange
# ember drops to the road, bounces, throws a few tiny sparks and is gone inside
# BURST_LIFE seconds. Looks only: nothing here touches the sim.
#
# One pooled GPUParticles3D burst, reused by every flick (traffic and player):
# nothing is allocated on a flick, the CPU only restarts it. The bounce is the
# particle system's own collision against one flat slab laid at the road height
# under the flick. Particles live in world space, so a flick from a moving car
# lands behind it.
#
# Traffic (T9): now and then a car AHEAD of the player, 8..40 m away and in
# sight, flicks one from its driver's window. At most once per MIN_GAP seconds
# (the first one a while after the run starts), so a few minutes apart.
#
# The player's cigarette (IdleActions.CIGARETTE) flicks through the same burst:
# DriverModel calls flick_from_player() when the window is down.

const BURST_AMOUNT := 7          # one ember and six sparks
const BURST_LIFE := 1.3          # s, under the 1.5 s the ask allows
const SPARK_SIZE := 0.035        # m across
const EMBER := Color("#FF8A1F")  # sodium
const GLOW := Color("#FFC066")   # amber
const BOUNCE := 0.45
const FRICTION := 0.5
const SLAB := Vector3(160.0, 2.0, 160.0)   # the collision slab; its top sits at the road

## Traffic: seconds between flicks, and the window in which a car may do it.
const MIN_GAP := 150.0
const MAX_GAP := 330.0
const FIRST_MIN := 90.0
const FIRST_MAX := 240.0
const RETRY_SECS := 2.0
const AHEAD_MIN := 8.0
const AHEAD_MAX := 40.0
const SIDE_MAX := 12.0
## The window, in a traffic car's own space, from the car's origin.
const WINDOW_LOCAL := Vector3(0.0, 0.45, -0.25)
const FLICK_OUT := 2.2           # m/s sideways out of the window
const FLICK_UP := 0.7

## The one in the running game (set while it is in the tree), for the driver.
static var current: EmberFlick

var player: Node3D
## Anything with a `cars` array of TrafficCar (the TrafficManager).
var traffic: Object
var burst: GPUParticles3D
var slab: GPUParticlesCollisionBox3D
var flicks := 0                  # all flicks
var traffic_flicks := 0
var player_flicks := 0
var flick_log: Array[float] = [] # the clock at each traffic flick (tests)
var last_origin := Vector3.ZERO
var last_ground := 0.0
var _mat: ParticleProcessMaterial
var _clock := 0.0
var _next_in := 0.0

func _init() -> void:
	name = "EmberFlick"
	_build()
	_next_in = randf_range(FIRST_MIN, FIRST_MAX)

func _ready() -> void:
	current = self

func _exit_tree() -> void:
	if current == self:
		current = null

func _build() -> void:
	_mat = ParticleProcessMaterial.new()
	_mat.gravity = Vector3(0.0, -9.8, 0.0)
	_mat.spread = 28.0
	_mat.initial_velocity_min = 1.0
	_mat.initial_velocity_max = 3.0
	_mat.scale_min = 0.4
	_mat.scale_max = 1.4
	_mat.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
	_mat.collision_bounce = BOUNCE
	_mat.collision_friction = FRICTION
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	grad.colors = PackedColorArray([GLOW, EMBER, Color(0.35, 0.08, 0.0, 0.0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	_mat.color_ramp = ramp
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * SPARK_SIZE
	quad.material = m
	burst = GPUParticles3D.new()
	burst.name = "Burst"
	burst.amount = BURST_AMOUNT
	burst.lifetime = BURST_LIFE
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.randomness = 0.35
	burst.local_coords = false
	burst.emitting = false
	burst.process_material = _mat
	burst.draw_pass_1 = quad
	burst.visibility_aabb = AABB(Vector3(-60.0, -10.0, -60.0), Vector3(120.0, 30.0, 120.0))
	burst.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(burst)
	slab = GPUParticlesCollisionBox3D.new()
	slab.name = "RoadSlab"
	slab.size = SLAB
	add_child(slab)

## Throws one cigarette end from `origin` (world) with world velocity `vel`.
func flick(origin: Vector3, vel: Vector3, exclude: Array[RID] = []) -> void:
	flicks += 1
	last_origin = origin
	last_ground = _road_height(origin, exclude)
	var speed := maxf(vel.length(), 0.1)
	_mat.direction = vel / speed
	_mat.initial_velocity_min = speed * 0.7
	_mat.initial_velocity_max = speed * 1.15
	# the slab: top at the road, under the flick and where the burst will go
	var mid := origin + Vector3(vel.x, 0.0, vel.z) * BURST_LIFE * 0.4
	slab.global_position = Vector3(mid.x, last_ground - SLAB.y * 0.5, mid.z)
	burst.global_position = origin
	burst.restart()
	burst.emitting = true

## From the player's window (car space `local`); the end leaves with most of the
## car's speed, so it lands behind it.
func flick_from_player(car: Node3D, local: Vector3, car_vel: Vector3) -> void:
	var xf := car.global_transform
	var out := (xf.basis * Vector3.LEFT).normalized()
	player_flicks += 1
	# the ray down to the road skips the player's own body: from a low open
	# car (the kei) it starts inside the collision box and found its roof
	var own: Array[RID] = []
	if car is CollisionObject3D:
		own.append((car as CollisionObject3D).get_rid())
	flick(xf * local, car_vel * 0.9 + out * FLICK_OUT + Vector3.UP * FLICK_UP, own)

func _road_height(origin: Vector3, exclude: Array[RID] = []) -> float:
	var fallback := origin.y - 0.9
	if not is_inside_tree():
		return fallback
	var space := get_world_3d().direct_space_state
	if space == null:
		return fallback
	var q := PhysicsRayQueryParameters3D.create(origin + Vector3.UP * 0.3, origin + Vector3.DOWN * 3.0)
	q.exclude = exclude
	var hit := space.intersect_ray(q)
	return float(hit.position.y) if not hit.is_empty() else fallback

# ---------- traffic ----------

## Whether a car at `rel` (from the player) is one to flick from: ahead in the
## player's direction, close enough to see, not off to the side.
static func in_sight(rel: Vector3, fwd: Vector3, right: Vector3) -> bool:
	var ahead := rel.dot(fwd)
	return ahead >= AHEAD_MIN and ahead <= AHEAD_MAX and absf(rel.dot(right)) <= SIDE_MAX

func _physics_process(delta: float) -> void:
	_clock += delta
	if player == null or traffic == null or not is_instance_valid(player):
		return
	_next_in -= delta
	if _next_in > 0.0:
		return
	var car := _pick()
	if car == null:
		_next_in = RETRY_SECS   # none in sight: look again soon, the gap stays unspent
		return
	_next_in = randf_range(MIN_GAP, MAX_GAP)
	traffic_flicks += 1
	flick_log.append(_clock)
	if flick_log.size() > 256:
		flick_log.pop_front()   # a test reads it; in play it only grew (#611)
	var xf := car.global_transform
	var local := WINDOW_LOCAL + Vector3(-float(car.get("half_w")), 0.0, 0.0)
	var out := (xf.basis * Vector3.LEFT).normalized()
	var v := -xf.basis.z * float(car.get("target_speed"))
	if car is RigidBody3D and (car as RigidBody3D).linear_velocity.length() > 1.0:
		v = (car as RigidBody3D).linear_velocity
	flick(xf * local, v * 0.9 + out * FLICK_OUT + Vector3.UP * FLICK_UP)

func _pick() -> Node3D:
	var cars = traffic.get("cars")
	if cars == null:
		return null
	var xf := player.global_transform
	var fwd := -xf.basis.z
	var right := xf.basis.x
	var best: Node3D = null
	var best_d := INF
	for c in cars:
		if not is_instance_valid(c):
			continue
		var car := c as Node3D
		if car == null or not car.visible or bool(car.get("wrecked")) or bool(car.get("benched")):
			continue
		var rel := car.global_position - xf.origin
		if not in_sight(rel, fwd, right):
			continue
		var d := absf(rel.dot(fwd) - 24.0)   # the nearest to a comfortable 24 m
		if d < best_d:
			best_d = d
			best = car
	return best
