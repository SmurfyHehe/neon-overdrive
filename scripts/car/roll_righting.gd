extends Node

# No roll ends a run (TM2, Roy 2026-10-11). A vehicle of any kind left on its
# side or roof rights itself after HOLD_SECS, and the roll costs meter
# (TotalledMeter.step_for_roll, through RunEnd.add_step). This replaces
# special_run_end.gd, where the truck and the lowrider ended the run on a flip.
#
# - "on its side or roof": the car's up axis (basis.y.y) under TIP_UP, the same
#   read the Tuner's watchdog and the old special rule used.
# - at rest: under REST_KMH. Tipped AND at rest for HOLD_SECS, counted in
#   physics ticks (never frame time), and the car is righted. A car still
#   tumbling down a slope is left alone until it stops.
# - one roll costs once. A roll starts when the car first goes past TIP_UP and
#   is over only when it has been upright (over UPRIGHT_UP) for UPRIGHT_SECS;
#   until then nothing is charged again, however many times it goes over.
#   The step is charged when the car is righted: a roll that lands back on
#   its wheels costs nothing (Roy, 2026-10-11, answer 1466). CHARGE_ON_TIP
#   would charge the moment it goes over instead.
# - righting never launches the car: the body is frozen, moved over LIFT_SECS
#   to the same spot and heading with its wheels CLEAR above the ground, level
#   with the ground under it, both speeds zeroed, then let go to drop onto its
#   wheels. If something is in the way there (a wall, a car), it is moved
#   sideways across the road by up to SIDE_MAX, towards the nearer kerb first;
#   if nowhere is free, onto the road where the off-map rescue would put it.
# - the engine is not touched: a stalled engine stays stalled (X starts it).
# - while the car is being totalled (RunEnd past DRIVING) a roll does nothing.
#
# No class_name on purpose: preload it, so no class cache refresh is needed.

const TotalledMeter := preload("res://scripts/car/totalled_meter.gd")

const TIP_UP := 0.3        # basis.y.y under this: on its side or roof
const UPRIGHT_UP := 0.8    # ... over this: upright again
const REST_KMH := 2.0
const HOLD_SECS := 3.0
const UPRIGHT_SECS := 1.0
const LIFT_SECS := 0.6
const CLEAR := 0.1         # m between the tyres and the ground when let go
const LIFT_ARC := 0.4      # extra height mid-move, so the turning body clears the road
const SIDE_STEP := 0.5
const SIDE_MAX := 3.0
const CHARGE_ON_TIP := false

enum Phase { WATCH, LIFT }

## The roll was charged: the step asked for (before difficulty), and whether
## the meter took it (false with Wrecks off, or "Looks only").
signal rolled(step: float, counted: bool)
signal righting_started
## The car has been let go, upright. `moved` is how far sideways it was put
## (0 when its own spot was free), `rescued` when it went to the road instead.
signal righted(moved: float, rescued: bool)

var car: RigidBody3D
var kind := "car"
## RunEnd (scripts/core/run_end.gd): takes the step. Null: nothing is charged.
var run_end: Node
## Whether the meter counts at all right now (Game.wrecks_on).
var counts := Callable()
## OffMapRescue, for the last resort spot. Null: the car's own spot is used.
var rescue: Node
var camera: Node

var phase := Phase.WATCH
var rolls := 0          # rolls charged or not, for tests
var rightings := 0
var hold_ticks := 0     # ticks tipped and at rest
var in_roll := false
var last_moved := 0.0
var last_rescued := false

var _upright_ticks := 0
var _charged := false
var _lift_tick := 0
var _from := Transform3D.IDENTITY
var _to := Transform3D.IDENTITY
var _was_frozen := false
var _was_freeze_mode := RigidBody3D.FREEZE_MODE_STATIC

func _init(player: RigidBody3D = null, car_kind: String = "car") -> void:
	car = player
	kind = car_kind
	name = "RollRighting"

static func ticks(secs: float) -> int:
	return roundi(secs * float(Engine.physics_ticks_per_second))

func _physics_process(_delta: float) -> void:
	if car == null or not is_instance_valid(car):
		return
	if phase == Phase.LIFT:
		_lift_step()
		return
	if not car.global_transform.is_finite() or not car.linear_velocity.is_finite():
		return  # the off-map rescue's case
	if car.freeze:
		hold_ticks = 0  # held in place by something else (a photo, a cutscene)
		return
	step(car.global_transform.basis.y.y, car.linear_velocity.length() * 3.6)

## One tick of the watch, from raw numbers. True on the tick the car is to be
## righted (the caller's _physics_process then starts the move).
func step(up_y: float, speed_kmh: float) -> bool:
	if _totalling():
		hold_ticks = 0
		return false
	if up_y < TIP_UP:
		_upright_ticks = 0
		if not in_roll:
			in_roll = true
			if CHARGE_ON_TIP:
				_charge()
	elif up_y > UPRIGHT_UP:
		_upright_ticks += 1
		if in_roll and _upright_ticks >= ticks(UPRIGHT_SECS):
			in_roll = false
			_charged = false
	else:
		_upright_ticks = 0
	hold_ticks = hold_ticks + 1 if up_y < TIP_UP and speed_kmh < REST_KMH else 0
	if hold_ticks < ticks(HOLD_SECS):
		return false
	hold_ticks = 0
	_charge()
	_begin_lift()
	return true

func _totalling() -> bool:
	# RunEnd.Phase.DRIVING is 0.
	return run_end != null and is_instance_valid(run_end) and int(run_end.get("phase")) != 0

## The roll's step, once per roll.
func _charge() -> void:
	if _charged:
		return
	_charged = true
	rolls += 1
	var s := TotalledMeter.step_for_roll(kind)
	var counted := false
	if run_end != null and is_instance_valid(run_end) and (not counts.is_valid() or counts.call()):
		var before: float = run_end.meter()
		run_end.add_step(s)
		counted = run_end.meter() > before
	rolled.emit(s, counted)

# ---------- the move ----------

func _begin_lift() -> void:
	if car == null or not is_instance_valid(car) or not car.is_inside_tree():
		return  # step() driven by a test with no car
	_from = car.global_transform
	last_moved = 0.0
	last_rescued = false
	_to = _free_spot(_upright_at(_from.origin, _from.basis))
	_was_frozen = car.freeze
	_was_freeze_mode = car.freeze_mode
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	car.freeze = true
	_lift_tick = 0
	phase = Phase.LIFT
	righting_started.emit()

func _lift_step() -> void:
	_lift_tick += 1
	var n := maxi(ticks(LIFT_SECS), 1)
	var t := clampf(float(_lift_tick) / float(n), 0.0, 1.0)
	var e := t * t * (3.0 - 2.0 * t)
	var xf := _from.interpolate_with(_to, e)
	xf.origin += _to.basis.y * (sin(PI * t) * LIFT_ARC)
	car.global_transform = xf
	if _lift_tick < n:
		return
	car.global_transform = _to
	car.freeze = _was_frozen
	car.freeze_mode = _was_freeze_mode
	_stand_still()
	phase = Phase.WATCH
	rightings += 1
	righted.emit(last_moved, last_rescued)

## Standing still, with the sim's saved positions and wheel spin to match (GEVP
## reads speed off them), and no crash read out of the stop. The same handover
## the off-map rescue does (off_map_rescue.gd _put_back).
func _stand_still() -> void:
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	if car is Vehicle:
		TrafficCar.set_moving(car as Vehicle, 0.0)
		for w in (car as Vehicle).wheel_array:
			w.last_collision_point = w.global_position
	car.reset_physics_interpolation()
	var d: Variant = car.get("damage")
	if d is CarDamage:
		(d as CarDamage).forget_motion()
	if camera != null and is_instance_valid(camera) and camera.has_method("forget_motion"):
		camera.forget_motion()

## How high the car's origin sits over the ground with its springs hanging
## free and its tyres just touching.
func ride_height() -> float:
	var h := -INF
	if car is Vehicle:
		for w in (car as Vehicle).wheel_array:
			h = maxf(h, -w.position.y + w.spring_length + w.tire_radius)
	return h if is_finite(h) else 0.5

## The car upright at `at`: heading kept, level with the ground under it, tyres
## CLEAR above it.
func _upright_at(at: Vector3, heading: Basis) -> Transform3D:
	var g := _ground(at)
	var up: Vector3 = g[1]
	# The nose, flattened onto the ground. Standing on its nose or tail the
	# nose has no heading: the roof (or the floor) points the way then.
	var fwd := -heading.z
	fwd -= up * fwd.dot(up)
	if fwd.length() < 0.2:
		fwd = heading.y - up * heading.y.dot(up)
	if fwd.length() < 0.01 or not fwd.is_finite():
		fwd = Vector3.FORWARD - up * Vector3.FORWARD.dot(up)
	var ground: Vector3 = g[0]
	return Transform3D(Basis.looking_at(fwd.normalized(), up), ground + up * (ride_height() + CLEAR))

## [point, normal] of the ground under `at`: what the wheels stand on (the
## road and the sidewalks). The road's own surface where the ray finds nothing.
func _ground(at: Vector3) -> Array:
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.5, at + Vector3.DOWN * 6.0)
	q.collision_mask = (1 << (CarSpec.WORLD_LAYER - 1)) | (1 << (CarSpec.KERB_LAYER - 1))
	q.exclude = [car.get_rid()]
	var hit := car.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var n: Vector3 = hit.normal
		# A ray that lands on something steep (a kerb face): level instead.
		return [hit.position, n if n.y > 0.9 else Vector3.UP]
	var u := RoadFrame.unroll(at)
	if RoadFrame.align == null or not u.is_finite():
		return [Vector3(at.x, 0.0, at.z), Vector3.UP]
	return [RoadFrame.roll(Vector3(u.x, 0.0, u.z)), RoadFrame.basis_at(u.z).y]

## `want`, or the nearest free spot sideways across the road from it, or the
## road spot the off-map rescue would use.
func _free_spot(want: Transform3D) -> Transform3D:
	if not _blocked(want):
		return want
	var u := RoadFrame.unroll(want.origin)
	# Across the road, in the world: towards the nearer kerb first (the own
	# side is +x in road space), then the other way.
	var across := RoadFrame.basis_at(u.z).x if RoadFrame.align != null else Vector3.RIGHT
	var first := 1.0 if u.x >= 0.0 else -1.0
	for side: float in [first, -first]:
		var d := SIDE_STEP
		while d <= SIDE_MAX + 0.001:
			var xf := _upright_at(want.origin + across * (side * d), want.basis)
			if _wall_between(want.origin, xf.origin):
				break  # never to the far side of a wall
			if not _blocked(xf):
				last_moved = d
				return xf
			d += SIDE_STEP
	last_rescued = true
	if rescue != null and is_instance_valid(rescue) and rescue.has_method("target"):
		var r: Vector3 = rescue.target()
		return RoadFrame.pose(r.x, ride_height() + CLEAR, r.z, 0.0)
	return want

func _wall_between(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.collision_mask = 1 << (CarSpec.WALL_LAYER - 1)
	q.exclude = [car.get_rid()]
	return not car.get_world_3d().direct_space_state.intersect_ray(q).is_empty()

## Whether the car's body would sit inside a wall or another car at `xf`.
func _blocked(xf: Transform3D) -> bool:
	var space := car.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	q.collision_mask = (1 << (CarSpec.CAR_LAYER - 1)) | (1 << (CarSpec.WALL_LAYER - 1))
	q.exclude = [car.get_rid()]
	for child in car.get_children():
		var cs := child as CollisionShape3D
		if cs == null or cs.disabled or cs.shape == null:
			continue
		q.shape = cs.shape
		q.transform = xf * cs.transform
		if not space.intersect_shape(q, 1).is_empty():
			return true
	return false
