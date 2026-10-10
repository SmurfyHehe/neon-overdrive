extends RefCounted

# Wet grip per wheel (water, Part 2). One of these rides on every car that
# runs the raycast sim (the player, near traffic, and cops when they drive),
# so the same water rules apply to all of them. Each physics tick step()
# works out a grip multiplier for each wheel (FL, FR, RL, RR) from:
#   - rain on the road: Weather.rain_grip(), 0.85 rain, 0.80 downpour;
#   - the puddle under the wheel: 10% less in a shallow one, 20% in a deep one;
#   - aquaplaning: a little more lost in deep water above 110 km/h;
# then holds Roy's limits: never under 55%, never more than 10% between the
# left and right wheel of an axle, and each wheel eases toward its target
# rather than jumping. Deep water also drags the car back a little.
#
# The car writes mult[i] into Wheel.grip_mult (the vendored GEVP hook) after
# anything else that sets it this tick: PowertrainHealth on the player.
#
# CPU: away from puddles (and on a dry road) step() only counts down the
# distance the car has driven since it last looked (Puddles.gather) and
# returns. Within NEAR_MARGIN of a puddle the car's own box is measured
# against the one or two puddles listed, by vector maths from where it last
# looked, and its wheels are tested only once it is over one. Measured in a
# downpour with 24 cars on Roy's laptop (2026-10-09): median 4.7 us per car
# per tick, against 190-360 us for the car's own sim (tests/world/water_drive.gd).
# No class_name on purpose: preload it, so no class cache refresh is needed.

const Weather := preload("res://scripts/world/weather.gd")
const Puddles := preload("res://scripts/world/puddles.gd")

const SHALLOW_GRIP := 0.90
const DEEP_GRIP := 0.80
## Aquaplaning starts above 110 km/h in deep water and grows to AQUA_LOSS more
## grip lost by AQUA_FULL; light on purpose.
const AQUA_START := 110.0 / 3.6
const AQUA_FULL := 160.0 / 3.6
const AQUA_LOSS := 0.10
## Hard floor and the left/right limit (Roy, 2026-10-09).
const MIN_GRIP := 0.55
const MAX_SIDE_DIFF := 0.10
## Most a wheel's multiplier moves per second: 0.2 (a deep puddle) in 0.2 s.
const RATE := 1.0
## Deep-water drag at full puddles with all four wheels in, m/s^2.
const DEEP_DRAG := 0.8
## A wheel is never further than this from the car's centre, m (half the
## longest car plus margin): the radius of the per-car puddle early-out.
const CAR_R := 3.5
## Puddles this close are listed for the wheel checks, m; the list is made
## again after the car has driven this far (Puddles.gather).
const NEAR_MARGIN := 6.0

## Settled grip multiplier per wheel, FL, FR, RL, RR.
var mult := PackedFloat32Array([1.0, 1.0, 1.0, 1.0])
## Water under each wheel this tick (Puddles.Depth).
var depth := PackedInt32Array([0, 0, 0, 0])
## Wheels in deep water this tick, and how full the puddles were.
var deep := 0
var _fill := 0.0
## mult changed since write() last copied it into the wheels.
var dirty := false
## Puddles within NEAR_MARGIN of the car when last looked (Puddles.gather),
## and how many more metres that list holds good for. Until it runs out the
## car reads no road position at all: RoadFrame.unroll is the dear part.
var near := PackedFloat32Array()
var _valid := 0.0
## Metres before the car can reach any puddle in `near` (Puddles.reach):
## the wheel checks wait until then.
var _free := 0.0
## Where the car was when the list was made: world position, road-space s
## and x, the road's basis there (inverted) and the floating origin. Wheel
## positions near a puddle come from these by plain vector maths; the road
## turns well under a degree over NEAR_MARGIN, so the error is millimetres.
var _p0 := Vector3.ZERO
var _s0 := 0.0
var _x0 := 0.0
var _to_road := Basis.IDENTITY
var _origin := -1
var _t := PackedFloat32Array([1.0, 1.0, 1.0, 1.0])
## The fast path's state: mult has settled on the rain's grip for weather
## version _wver (puddles _wfill full), and whether that grip is 1.0 (dry).
var _settled := false
var _wver := -1
var _wfill := 0.0
var _one := true

## Target grip for one wheel. Pure, for tests.
static func wheel_target(rain_grip: float, fill: float, d: int, speed: float) -> float:
	var g := rain_grip
	if d == Puddles.Depth.SHALLOW:
		g *= 1.0 - (1.0 - SHALLOW_GRIP) * fill
	elif d == Puddles.Depth.DEEP:
		g *= 1.0 - (1.0 - DEEP_GRIP) * fill
		var a := clampf((speed - AQUA_START) / (AQUA_FULL - AQUA_START), 0.0, 1.0)
		g *= 1.0 - AQUA_LOSS * a * fill
	return maxf(g, MIN_GRIP)

## Raises the lower wheel of a pair so the two are at most MAX_SIDE_DIFF apart.
static func limit_pair(t: PackedFloat32Array, a: int, b: int) -> void:
	if t[a] < t[b] - MAX_SIDE_DIFF:
		t[a] = t[b] - MAX_SIDE_DIFF
	elif t[b] < t[a] - MAX_SIDE_DIFF:
		t[b] = t[a] - MAX_SIDE_DIFF

## Looks again at the puddles around car v (Puddles.gather).
func refresh(v: Vehicle) -> void:
	var u := RoadFrame.unroll(v.global_position)
	_p0 = v.global_position
	_s0 = RoadFrame.s_at(u.z)
	_x0 = u.x
	_to_road = RoadFrame.basis_at(u.z).transposed()
	_origin = RoadFrame.origin_index
	_valid = Puddles.gather(_s0, _x0, CAR_R, NEAR_MARGIN, near)
	_free = 0.0

## Puts every wheel straight on the weather's grip, no easing: for a car that
## has just appeared (a traffic spawn), not one already driving.
func settle() -> void:
	var g := maxf(Weather.rain_grip(), MIN_GRIP)
	for i in 4:
		mult[i] = g
		depth[i] = Puddles.Depth.NONE
	deep = 0
	_valid = 0.0
	_free = 0.0
	near.clear()
	_settled = false
	dirty = true

## Updates mult for car v; true if any wheel is off 1.0 (the caller writes
## it). `dirty` says whether mult moved since the last write.
func step(v: Vehicle, delta: float) -> bool:
	# Fast path, nearly every tick: the tyres sit on the rain's grip for this
	# weather and no puddle is within reach yet.
	var moved := absf(v.speed) * delta
	_valid -= moved
	_free -= moved
	if _settled and _wver == Weather.version and (_wfill == 0.0 or (_valid > 0.0 and (near.is_empty() or _free > 0.0))):
		return not _one
	_settled = false
	var rg := Weather.rain_grip()
	var fill := Weather.puddle_fill()
	_fill = fill
	var t := _t
	var was_wet := deep > 0 or depth[0] != 0 or depth[1] != 0 or depth[2] != 0 or depth[3] != 0
	deep = 0
	var in_water := false
	if fill > 0.0:
		if _valid <= 0.0 or _origin != RoadFrame.origin_index:
			refresh(v)
		if not near.is_empty() and _free <= 0.0:
			var c := _to_road * (v.global_position - _p0)
			_free = Puddles.reach(near, _s0 - c.z, _x0 + c.x, CAR_R)
		if not near.is_empty() and _free <= 0.0:
			var speed := v.linear_velocity.length()
			var n := mini(4, v.wheel_array.size())
			for i in n:
				var w: Wheel = v.wheel_array[i]
				var d := Puddles.Depth.NONE
				if w.is_colliding():
					var off := _to_road * (w.global_position - _p0)
					d = Puddles.depth_in(near, _s0 - off.z, _x0 + off.x)
				depth[i] = d
				if d != Puddles.Depth.NONE:
					in_water = true
					if d == Puddles.Depth.DEEP:
						deep += 1
				t[i] = wheel_target(rg, fill, d, speed)
			for i in range(n, 4):
				t[i] = maxf(rg, MIN_GRIP)
	if not in_water:
		var g := maxf(rg, MIN_GRIP)
		if was_wet:
			depth.fill(Puddles.Depth.NONE)
		# mult is float32: compare within float32's step, or 0.8 never equals 0.8.
		if absf(mult[0] - g) < 1e-6 and absf(mult[1] - g) < 1e-6 and absf(mult[2] - g) < 1e-6 and absf(mult[3] - g) < 1e-6:
			# Out of the water with every wheel on the rain's grip: settled.
			_settled = true
			_wver = Weather.version
			_wfill = fill
			_one = g >= 1.0
			return not _one
		t.fill(g)
	_wver = Weather.version
	_wfill = fill
	limit_pair(t, 0, 1)
	limit_pair(t, 2, 3)
	var dm := RATE * delta
	for i in 4:
		mult[i] = move_toward(mult[i], t[i], dm)
	# Ease-in can leave a pair briefly further apart than the targets are;
	# hold the limit on what the tyres actually get too.
	limit_pair(mult, 0, 1)
	limit_pair(mult, 2, 3)
	dirty = true
	_one = false
	return true

## Deep water holds the car back a little: DEEP_DRAG per wheel in it, faded
## in over the first 10 m/s. Separate from step() so a test can time step()
## without pushing the car.
func apply_drag(v: Vehicle) -> void:
	if deep == 0:
		return
	var speed := v.linear_velocity.length()
	if speed > 0.5:
		var scale := DEEP_DRAG * _fill * float(deep) / 4.0 * minf(speed / 10.0, 1.0)
		v.apply_central_force(-v.linear_velocity / speed * v.mass * scale)

## Writes mult into the wheels: the whole multiplier (traffic, nothing else
## sets grip_mult there).
func write(v: Vehicle) -> void:
	for i in mini(4, v.wheel_array.size()):
		v.wheel_array[i].grip_mult = mult[i]
	dirty = false

## Multiplies mult into what PowertrainHealth already wrote this tick (tyre
## temperature and wear), keeping the 55% floor for the water's share: a worn
## tyre that is already under 55% is not lifted by this.
func write_over(v: Vehicle) -> void:
	for i in mini(4, v.wheel_array.size()):
		var w: Wheel = v.wheel_array[i]
		var g := w.grip_mult
		w.grip_mult = maxf(g * mult[i], minf(g, MIN_GRIP))
	dirty = false
