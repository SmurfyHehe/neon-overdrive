class_name OffMapRescue
extends CanvasLayer

# Off-map rescue (2026-10-10, Roy: "driving off the map", step 1). If the car
# ends up somewhere it cannot drive back from, the screen fades to black and
# the car is put back on the road where it last drove, standing still. Free:
# no fee, no damage, the run and the night carry on.
#
# "Somewhere impossible" is read in road space (RoadFrame.unroll: x across,
# y up from the surface, z along), once per physics tick:
# - a number in the car's state is NaN or infinite              -> at once
# - more than BELOW under the road surface (fell off or through) -> at once
# - more than ABOVE over it (thrown by a physics glitch)        -> at once
# - past the inner face of an out-of-bounds wall (in it, on top
#   of it or beyond it)                                         -> after GRACE
# - beside or beyond road that is not built (off either end of
#   the chunk pool: the road is only recycled forward)          -> after GRACE
# The two timed ones wait in case the car is only passing over (a hop along
# the top of the wall) and comes back by itself.
#
# Upside down ON the road is a crash, not a place the map should not have let
# the car reach, so the real rules leave it alone. The test build's sandbox
# (TestBuild) has no crash rules, so there a car left on its roof or side for
# FLIP_S is put back too, and "Put me back on the road" (request(): the pause
# menu row and the put_back key) does it on demand from anywhere.
#
# Where it is put back (2026-10-10, Roy: "i want you to spawn on the side of
# the road ... to need to actually start the car"): parked at the kerb on the
# own side, off the driving lanes, facing along the road, level, standing
# still, engine off (PlayerCar.ignition_off; X starts it). spot() is also
# where a run starts and where a saved run comes back (Game._setup_player).
#
# Game._physics_process already unrolls the player's position each tick and
# RoadFrame memoises it, so the watch itself is a dozen comparisons.

const TestBuild := preload("res://scripts/core/test_build.gd")
const TestMode := preload("res://scripts/core/test_mode.gd")
const TestDriver := preload("res://scripts/core/test_driver.gd")
const Districts := preload("res://scripts/world/districts.gd")
const GasStation := preload("res://scripts/world/gas_station.gd")

## The car was put back; `reason` is one of the REASON_ strings.
signal rescued(reason: String)

const REASON_NAN := "bad numbers"
const REASON_BELOW := "below the road"
const REASON_ABOVE := "far above the road"
const REASON_OUTSIDE := "outside the walls"
const REASON_NO_ROAD := "off the end of the road"
const REASON_FLIPPED := "on its roof or side"
const REASON_ASKED := "asked to be put back"

## Sandbox only: on its roof or side (basis.y.y under FLIP_UP) and slower than
## FLIP_SPEED m/s for this many seconds.
const FLIP_S := 2.5
const FLIP_UP := 0.3
const FLIP_SPEED := 2.0
## Parked: the car's centre this far in from the kerb face, m (half a car plus
## a hand's width). A shoulder narrower than the car leaves it part in the
## kerbside lane, never less than PARK_MIN out from the road edge.
const PARK_FROM_KERB := 1.05
const PARK_MIN := 0.35
## How far it looks either way along the road for a free parking spot, in
## steps of PARK_STEP m.
const PARK_STEP := 8.0
const PARK_STEPS := 12
## Never parked this close to a gas station's bay (stopping in the bay opens
## the pump), m along the road.
const STATION_CLEAR := 30.0
## The box that must be free of anything solid, m (a car and a margin), and
## how high its centre sits over the road.
const PARK_BOX := Vector3(2.2, 1.0, 5.0)
const PARK_BOX_Y := 0.95
## The car's origin over the road surface when it is set down, m.
const PARK_Y := 0.05

## Under the road surface, m. The lowest a driving car's origin gets is a few
## cm (springs bottomed out in a dip).
const BELOW := 3.0
## Over the road surface, m: five times the wall height. The biggest crest
## jump clears a few metres.
const ABOVE := 60.0
## The car's centre this far past a wall's INNER face counts as outside, m: in
## the wall, on top of it, or beyond it. A car leaning on the wall keeps its
## centre most of a metre inside the face (half its width), so only a car the
## wall failed to hold reads as past it.
const OUTSIDE := 0.3
## Seconds outside the walls, or off the built road, before the rescue.
const GRACE := 0.5
const FADE_OUT := 0.25
const HOLD := 0.2
const FADE_IN := 0.4
## A spot is remembered as good only this far inside the walls, m ...
const GOOD_INSET := 1.0
## ... with this many wheels on the ground, this upright (basis.y.y) ...
const GOOD_WHEELS := 3
const GOOD_UP := 0.9
## Good spots are looked for every this many ticks (0.1 s at 120 Hz).
const REMEMBER_EVERY := 12
## ... and the car is put back this far inside the built road's ends, m.
const END_INSET := 30.0
## Room the car needs from traffic where it is put back: m along the road
## either way, and m across.
const CLEAR_Z := 14.0
const CLEAR_X := 2.4
## How far back it looks for a clear spot, in steps of CLEAR_Z.
const BACK_STEPS := 6

enum Phase { WATCH, FADE_OUT, HOLD, FADE_IN }

## Tests: false switches the watch off (the car can be left out of bounds).
var enabled := true
## Parking also switches the engine off (X starts it). Off in automated tests
## unless they ask (NEON_PARKED=1): they drive the moment they are placed.
var engine_off_when_parked := parked_start()
## How many times the car has been put back this session.
var count := 0
var last_reason := ""
var phase := Phase.WATCH

var _game: Node
var _player: PlayerCar
var _black: ColorRect
var _t := 0.0
var _out_for := 0.0
var _reason := ""
var _has_good := false
var _good_s := 0.0  # metres along the road (RoadFrame.s_at), origin-proof
var _good_x := 0.0
var _good_y := 0.0
var _chunk := {}  # the chunk_pool entry the car was last in
var _tick := 0
var _flipped_for := 0.0

func _init(game: Node, player: PlayerCar) -> void:
	_game = game
	_player = player
	name = "OffMapRescue"
	layer = 8  # over the HUD (5), under the warning lights (9) and the menus (10)
	_black = ColorRect.new()
	_black.color = Color(0, 0, 0, 0)
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.visible = false
	add_child(_black)

func _physics_process(delta: float) -> void:
	match phase:
		Phase.WATCH:
			_watch(delta)
		Phase.FADE_OUT:
			_t += delta
			_set_black(_t / FADE_OUT)
			if _t >= FADE_OUT:
				_put_back()
				phase = Phase.HOLD
				_t = 0.0
		Phase.HOLD:
			_t += delta
			if _t >= HOLD:
				phase = Phase.FADE_IN
				_t = 0.0
		Phase.FADE_IN:
			_t += delta
			_set_black(1.0 - _t / FADE_IN)
			if _t >= FADE_IN:
				phase = Phase.WATCH
				_out_for = 0.0

func _set_black(a: float) -> void:
	_black.color.a = clampf(a, 0.0, 1.0)
	_black.visible = _black.color.a > 0.0

## Why the car is off the map at this instant, "" if it is not. `timed` comes
## back true for the reasons that wait GRACE.
func check() -> Array:
	var p := _player.global_position
	if not (p.is_finite() and _player.linear_velocity.is_finite() and _player.angular_velocity.is_finite() and _player.global_transform.basis.is_finite()):
		return [REASON_NAN, false]
	var u := RoadFrame.unroll(p)
	if not u.is_finite():
		return [REASON_NAN, false]
	if u.y < -BELOW:
		return [REASON_BELOW, false]
	if u.y > ABOVE:
		return [REASON_ABOVE, false]
	var b := _bounds_at(u.z)
	if b == Vector2.ZERO:
		return [REASON_NO_ROAD, true]
	if u.x > b.x + OUTSIDE or u.x < -(b.y + OUTSIDE):
		return [REASON_OUTSIDE, true]
	return ["", false]

func _watch(delta: float) -> void:
	if not enabled:
		return
	var c := check()
	var reason: String = c[0]
	if reason == "" and TestBuild.on():
		var over := _player.global_transform.basis.y.y < FLIP_UP and _player.linear_velocity.length() < FLIP_SPEED
		_flipped_for = _flipped_for + delta if over else 0.0
		if _flipped_for >= FLIP_S:
			_flipped_for = 0.0
			request(REASON_FLIPPED)
			return
	if reason == "":
		_out_for = 0.0
		_tick += 1
		if _tick % REMEMBER_EVERY == 0:
			_remember()
		return
	_out_for += delta
	if c[1] and _out_for < GRACE:
		return
	_reason = reason
	phase = Phase.FADE_OUT
	_t = 0.0

## Inner faces of the two walls (own side, oncoming side; both |x|) of the
## built chunk at road-space z; ZERO where no road is built.
func _bounds_at(z: float) -> Vector2:
	var idx: int = _game.origin_index + floori(-z / RoadChunkBuilder.CHUNK_LEN)
	# The car stays in one chunk for many ticks: try the one found last time.
	if _chunk.get("index", -1) == idx:
		return RoadChunkBuilder.bounds(_chunk.root)
	for c: Dictionary in _game.chunk_pool:
		if c.index == idx:
			_chunk = c
			return RoadChunkBuilder.bounds(c.root)
	return Vector2.ZERO

func _remember() -> void:
	if _player.global_transform.basis.y.y < GOOD_UP:
		return
	var down := 0
	for w in _player.wheel_array:
		if (w as Wheel).is_colliding():
			down += 1
	if down < GOOD_WHEELS:
		return
	var u := RoadFrame.unroll(_player.global_position)
	var b := _bounds_at(u.z)
	if b == Vector2.ZERO or u.x > b.x - GOOD_INSET or u.x < -(b.y - GOOD_INSET):
		return
	_has_good = true
	_good_s = RoadFrame.s_at(u.z)
	_good_x = u.x
	_good_y = u.y

## Whether a run starts parked at the kerb with the engine off, and a put-back
## leaves it off: in play, yes. Automated tests, the benchmark and the test
## driver's bots start in the lane with the engine running, as they always
## did, unless NEON_PARKED=1 asks; NEON_PARKED=0 turns it off in play.
static func parked_start() -> bool:
	var env := OS.get_environment("NEON_PARKED")
	if env == "0" or env == "1":
		return env == "1"
	if TestMode.active() or Benchmark.requested():
		return false
	return TestDriver.requested_mode() == "" and TestDriver.requested_replay() == ""

## Puts the car back now (fade, park, fade in), wherever it is and however it
## lies. False while a put-back is already running.
func request(reason := REASON_ASKED) -> bool:
	if phase != Phase.WATCH:
		return false
	_reason = reason
	phase = Phase.FADE_OUT
	_t = 0.0
	return true

## Road-space x of the parked car at `s` metres along the road: on the own
## side's shoulder, its kerb side PARK_FROM_KERB in from the kerb face.
static func park_x(s: float) -> float:
	var shoulder := Districts.shoulder_at(floori(s / RoadChunkBuilder.CHUNK_LEN))
	return GasStation.own_edge(s) + maxf(shoulder - PARK_FROM_KERB, PARK_MIN)

## Road-space spot to put the car back on: parked at the kerb beside where it
## is (or, with no usable position, where it last drove), kept inside the built
## road, moved along the road if traffic, a pole, a prop or a gas station's bay
## is in the way.
func target() -> Vector3:
	var cur := RoadFrame.unroll(_player.global_position)
	var s: float = RoadFrame.s_at(cur.z) if cur.is_finite() else NAN
	if not is_finite(s) or _bounds_at(float(RoadFrame.origin_index) * RoadChunkBuilder.CHUNK_LEN - s) == Vector2.ZERO:
		s = _good_s if _has_good else NAN
	return spot(s)

## The parking spot nearest `s` metres along the road (NAN: the middle of the
## built road).
func spot(s: float) -> Vector3:
	var l := RoadChunkBuilder.CHUNK_LEN
	var lo := INF
	var hi := -INF
	for c: Dictionary in _game.chunk_pool:
		lo = minf(lo, float(c.index) * l)
		hi = maxf(hi, float(c.index + 1) * l)
	if not is_finite(s):
		s = (lo + hi) / 2.0
	s = clampf(s, lo + END_INSET, hi - END_INSET)
	for step in PARK_STEPS * 2 + 1:
		# s, then 1 back, 1 on, 2 back, 2 on ...
		var off := float((step + 1) / 2) * PARK_STEP * (-1.0 if step % 2 == 1 else 1.0)
		var st := s + off
		if st < lo + END_INSET or st > hi - END_INSET:
			continue
		var x := park_x(st)
		var z := float(RoadFrame.origin_index) * l - st
		if _clear(x, z, st):
			return Vector3(x, 0.0, z)
	# Nowhere free either way: beside where it is anyway.
	return Vector3(park_x(s), 0.0, float(RoadFrame.origin_index) * l - s)

func _clear(x: float, z: float, s: float) -> bool:
	if GasStation.enabled and absf(s - GasStation.s_of(maxi(0, roundi((s - GasStation.first_s) / GasStation.SPACING)))) < STATION_CLEAR:
		return false
	var traffic: TrafficManager = _game.traffic
	if traffic != null:
		for car in traffic.cars:
			if car.benched or not car.global_position.is_finite():
				continue
			var u := RoadFrame.unroll(car.global_position)
			if absf(u.z - z) < CLEAR_Z and absf(u.x - x) < CLEAR_X:
				return false
	# Anything solid standing there: a pole, a prop, a wall, a parked car.
	if not _player.is_inside_tree():
		return true
	var q := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = PARK_BOX
	q.shape = box
	q.transform = RoadFrame.pose(x, PARK_BOX_Y, z, 0.0)
	q.exclude = [_player.get_rid()]
	q.collision_mask = 0xFFFFFFFF
	return _player.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()

## Parks the car at spot(s) at once, with no fade (the start of a run).
func park_at(s: float) -> void:
	_park(spot(s))

func _put_back() -> void:
	_park(target())
	# The sandbox never leaves a tester with a car that cannot drive on.
	if TestBuild.on():
		if _player.damage.is_engine_dead():
			_player.damage.garage_repair(null)
			_player.health.repair()
		if _player.fuel.is_low():
			_player.fuel.litres = FuelTank.CAPACITY_L
	count += 1
	last_reason = _reason
	print("OffMapRescue: car parked at the kerb (%s)" % _reason)
	rescued.emit(_reason)

func _park(u: Vector3) -> void:
	_player.global_transform = RoadFrame.pose(u.x, u.y + PARK_Y, u.z, 0.0)
	# Standing still, with the sim's saved positions and wheel spin to match
	# (GEVP reads speed off them; see Game._shift_origin).
	TrafficCar.set_moving(_player, 0.0)
	for w in _player.wheel_array:
		w.last_collision_point = w.global_position
	_player.reset_physics_interpolation()
	# The stop is not a crash: no damage and no camera shake from it.
	_player.damage.forget_motion()
	var cam: ChaseCamera = _game.camera
	if cam != null:
		cam.forget_motion()
	if engine_off_when_parked:
		_player.ignition_off()
